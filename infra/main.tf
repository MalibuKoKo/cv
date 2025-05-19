# https://github.com/terraform-aws-modules/terraform-aws-alb/tree/master/examples
# https://rebirth.devoteam.com/2023/07/18/ecs-fargate-terraform/

locals {
  region = "eu-west-3"
  name   = "free-tier"

  vpc_cidr = "10.0.0.0/16"
  azs      = slice(data.aws_availability_zones.available.names, 0, 3)

  container_name = "nginx"
  container_port = 80
  domain_name = var.domain_name

  tags = {
    Name       = local.name
    Repository = "https://github.com/MalibuKoKo/cv"
    Project    = "ecs-fargate"
  }
}

################################################################################
# Account
################################################################################
resource "aws_organizations_account" "free_tier" {
  name      = local.name
  email     = var.email # Doit être unique
  role_name = "OrganizationAccountAccessRole"
  iam_user_access_to_billing = "ALLOW"
  provider  = aws.org
  # tags = local.tags
}

################################################################################
# Availability zones
################################################################################
data "aws_availability_zones" "available" {
  provider = aws.freetier
}

################################################################################
# VPC
################################################################################
module "vpc" {
  providers = { aws = aws.freetier }
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"
  tags = local.tags

  name = local.name
  cidr = local.vpc_cidr

  azs             = local.azs
  # private_subnets = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 4, k)]
  public_subnets  = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 8, k + 48)]

  enable_nat_gateway = false
  single_nat_gateway = false
}

################################################################################
# ECS Cluster
################################################################################
module "ecs_cluster" {
  providers = { aws = aws.freetier }
  source  = "terraform-aws-modules/ecs/aws"
  version = "~> 5.0"
  tags = local.tags

  cluster_name = local.name

  # Capacity provider
  fargate_capacity_providers = {
    FARGATE_SPOT = {
      default_capacity_provider_strategy = {
        weight = 1
        base   = 0
      }
    }
  }

  # Désactive les options coûteuses
  create_cloudwatch_log_group = false

  # Pas d'instance EC2 (on utilisera Fargate uniquement)
  # default_capacity_provider_use_fargate = true
}

################################################################################
# Service
################################################################################
module "ecs_service" {
  providers = { aws = aws.freetier }
  source  = "terraform-aws-modules/ecs/aws//modules/service"
  version = "~> 5.0"
  tags = local.tags

  name        = local.container_name
  cluster_arn = module.ecs_cluster.cluster_arn
  cpu    = 256
  memory = 512
  assign_public_ip   = true
  launch_type = "FARGATE"
  desired_count = 1
  capacity_provider_strategy = [{capacity_provider = "FARGATE_SPOT", weight = 1, base = 0}]
  subnet_ids = module.vpc.public_subnets
  security_group_rules = {
    http_in = {
      type                     = "ingress"
      from_port                = local.container_port
      to_port                  = local.container_port
      protocol                 = "tcp"
      cidr_blocks              = ["0.0.0.0/0"]
      description              = "Allow HTTP from anywhere"
    }
    egress_all = {
      type        = "egress"
      from_port   = 0
      to_port     = 0
      protocol    = "-1"
      cidr_blocks = ["0.0.0.0/0"]
    }
  }  

  enable_execute_command = true
  container_definitions = {
    (local.container_name) = {
      name = local.container_name
      essential = true
      image     = var.image
      port_mappings = [
        {
          name          = local.container_name
          containerPort = local.container_port
          hostPort      = local.container_port
          protocol      = "tcp"
        }
      ]
      readonly_root_filesystem = false
      # enable_cloudwatch_logging = false
      environment = [
        {
          name  = "MAXMIND_TOKEN",
          value = var.maxmind_token
        }
      ]
      command   = [
        "sh", "-c",
        <<-EOT
          set -x
          curl -L "https://download.maxmind.com/app/geoip_download?edition_id=GeoLite2-Country&license_key=$${MAXMIND_TOKEN}&suffix=mmdb" -o /etc/nginx/GeoLite2-Country.mmdb

          cat > /etc/nginx/nginx.conf <<EOF
          load_module modules/ngx_http_geoip2_module.so;

          events {}

          http {
            geoip2 /etc/nginx/GeoLite2-Country.mmdb {
              $geoip2_data_country_code source=$remote_addr country iso_code;
            }

            map $geoip2_data_country_code $blocked_country {
              default 0;
              EG 1;
              VE 1;
              CN 1;
              BY 1;
              HK 1;
              SY 1;
              KP 1;
              PK 1;
              TH 1;
              BR 1;
              NG 1;
              TR 1;
              UA 1;
              ID 1;
              RU 1;
              CU 1;
              IR 1;
              VN 1;
            }

            server {
              listen 80;

              if ($blocked_country) {
                return 403;
              }

              location / {
                root /usr/share/nginx/html;
                index index.html;
              }
            }
          }
          EOF
          nginx -g 'daemon off;'
        EOT
      ]
    }
    dns-updater = {
      name = "dns-updater"
      essential = false
      image     = "docker.io/curlimages/curl:latest" # "public.ecr.aws/taskusinc/mirrors/curlimages/curl:latest"
      dependencies = [{
        containerName = local.container_name
        condition     = "START"
      }]
      environment = [
        {
          name  = "HOSTINGER_TOKEN",
          value = var.hostinger_token
        },
        {
          name  = "DOMAIN_NAME",
          value = var.domain_name
        },
        {
          name  = "DNS_RECORD_A",
          value = var.dns_record_a
        }
      ]
      command   = [
        "sh", "-c",
        <<-EOT
          echo "Attente de NGINX...";
          until curl -s http://localhost:80 > /dev/null; do
            sleep 1;
          done;
          echo "NGINX est prêt. Mise à jour DNS...";
          PUBLIC_IP=$(curl -s https://checkip.amazonaws.com);
          set -x;
          curl -s https://developers.hostinger.com/api/dns/v1/zones/$${DOMAIN_NAME} --request PUT --header 'Content-Type: application/json' --header "Authorization: Bearer $${HOSTINGER_TOKEN}" --data "{\"overwrite\":true,\"zone\":[{\"name\":\"$${DNS_RECORD_A}\",\"records\":[{\"content\":\"$${PUBLIC_IP}\"}],\"ttl\": 300,\"type\":\"A\"}]}";
        EOT
      ]
    }
  }
}
