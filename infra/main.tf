# https://github.com/terraform-aws-modules/terraform-aws-alb/tree/master/examples
# https://rebirth.devoteam.com/2023/07/18/ecs-fargate-terraform/

locals {
  region = "eu-west-3"
  name   = "free-tier"

  vpc_cidr = "10.0.0.0/16"
  # azs      = slice(data.aws_availability_zones.available.names, 0, 3)
  azs      = [data.aws_availability_zones.available.names[0]]

  container_name = "nginx"
  container_port = 80
  host_port = 80
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

  # enable_dns_hostnames = true
  # enable_dns_support   = true
}


resource "aws_security_group" "vpc_endpoints" {
  provider = aws.freetier
  name        = "vpc-endpoints"
  description = "Allow ECS tasks to reach SSM endpoints"
  vpc_id      = module.vpc.vpc_id

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = module.vpc.public_subnets_cidr_blocks
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# resource "aws_vpc_endpoint" "ssm" {
#   provider          = aws.freetier
#   vpc_id            = module.vpc.vpc_id
#   service_name      = "com.amazonaws.${local.region}.ssm"
#   vpc_endpoint_type = "Interface"
#   subnet_ids        = module.vpc.public_subnets
#   security_group_ids = [aws_security_group.vpc_endpoints.id]
#   private_dns_enabled = true
# }

# resource "aws_vpc_endpoint" "ssmmessages" {
#   provider          = aws.freetier
#   vpc_id            = module.vpc.vpc_id
#   service_name      = "com.amazonaws.${local.region}.ssmmessages"
#   vpc_endpoint_type = "Interface"
#   subnet_ids        = module.vpc.public_subnets
#   security_group_ids = [aws_security_group.vpc_endpoints.id]
#   private_dns_enabled = true
# }

# resource "aws_vpc_endpoint" "ec2messages" {
#   provider          = aws.freetier
#   vpc_id            = module.vpc.vpc_id
#   service_name      = "com.amazonaws.${local.region}.ec2messages"
#   vpc_endpoint_type = "Interface"
#   subnet_ids        = module.vpc.public_subnets
#   security_group_ids = [aws_security_group.vpc_endpoints.id]
#   private_dns_enabled = true
# }

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
  deployment_maximum_percent         = 100
  deployment_minimum_healthy_percent = 0
  capacity_provider_strategy = [{capacity_provider = "FARGATE_SPOT", weight = 1, base = 0}]
  subnet_ids = module.vpc.public_subnets
  security_group_rules = {
    http_in = {
      type                     = "ingress"
      from_port                = local.host_port
      to_port                  = local.container_port
      protocol                 = "tcp"
      cidr_blocks              = ["0.0.0.0/0"]
      description              = "Allow HTTP from anywhere"
    }
    https_in = {
      type        = "ingress"
      from_port   = 443
      to_port     = 443
      protocol    = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
      description = "Allow HTTPS from anywhere"
    }
    egress_all = {
      type        = "egress"
      from_port   = 0
      to_port     = 0
      protocol    = "-1"
      cidr_blocks = ["0.0.0.0/0"]
    }
  }  

  enable_execute_command = false #true
  container_definitions = {
    (local.container_name) = {
      name = local.container_name
      essential = true
      image     = "${var.image}:${file("${path.module}/../VERSION")}-geoip2"
      # image     = "${var.image}:${file("${path.module}/../VERSION")}"
      port_mappings = [
        {
          name          = local.container_name
          containerPort = local.container_port
          hostPort      = local.host_port
          protocol      = "tcp"
        },
        {
          name          = "https"
          containerPort = 443
          hostPort      = 443
          protocol      = "tcp"
        }
      ]
      readonly_root_filesystem = false
      enable_cloudwatch_logging = false
    }
    dns-updater = {
      name = "dns-updater"
      essential = false
      image     = "docker.io/curlimages/curl:latest"
      enable_cloudwatch_logging = false
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
          curl -s https://developers.hostinger.com/api/dns/v1/zones/$${DOMAIN_NAME} --request PUT --header 'Content-Type: application/json' --header "Authorization: Bearer $${HOSTINGER_TOKEN}" --data "{\"overwrite\":true,\"zone\":[{\"name\":\"$${DNS_RECORD_A}\",\"records\":[{\"content\":\"$${PUBLIC_IP}\"}],\"ttl\": 60,\"type\":\"A\"}]}";
        EOT
      ]
    }
  }

  runtime_platform = {
    cpu_architecture        = "ARM64"
    operating_system_family = "LINUX"
  }

  # ephemeral_storage = {
  #   size_in_gib = 1 # range (21 - 200)
  # }
  create_tasks_iam_role = false
  tasks_iam_role_arn = aws_iam_role.ecs_task.arn
}

resource "aws_ssm_parameter" "cert" {
  provider  = aws.freetier
  name        = "/${local.container_name}/cert"
  type        = "SecureString"  # chiffrement KMS automatique géré par AWS
  description = "Certificat SSL pour ${local.container_name}"
  value       = file("certs/archive/${var.dns_record_a}.${var.domain_name}/fullchain1.pem")  # chemin vers ton certificat local
  tags        = local.tags
}

resource "aws_ssm_parameter" "key" {
  provider    = aws.freetier
  name        = "/${local.container_name}/key"
  type        = "SecureString"
  description = "Clé privée SSL pour ${local.container_name}"
  value       = file("certs/archive/${var.dns_record_a}.${var.domain_name}/privkey1.pem")  # chemin vers ta clé privée locale
  tags        = local.tags
}

resource "aws_ssm_parameter" "dummy_cert" {
  provider  = aws.freetier
  name        = "/dummy/cert"
  type        = "SecureString"  # chiffrement KMS automatique géré par AWS
  description = "Certificat SSL pour dummy"
  value       = file("certs/archive/dummy/fullchain.pem")  # chemin vers ton certificat local
  tags        = local.tags
}

resource "aws_ssm_parameter" "dummy_key" {
  provider    = aws.freetier
  name        = "/dummy/key"
  type        = "SecureString"
  description = "Clé privée SSL pour dummy"
  value       = file("certs/archive/dummy/privkey.pem")  # chemin vers ta clé privée locale
  tags        = local.tags
}

resource "aws_iam_role" "ecs_task" {
  provider    = aws.freetier
  name = "ecs-task-role-myservice"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Condition = {
          ArnLike = {
            "aws:SourceArn" = "arn:aws:ecs:${local.region}:${data.aws_caller_identity.current.account_id}:*"
          }
          StringEquals = {
             "aws:SourceAccount" = "${data.aws_caller_identity.current.account_id}"
          }
        }
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
        Sid       = "ECSTasksAssumeRole"
      }
    ]
  })
}

data "aws_caller_identity" "current" {
  provider    = aws.freetier
}

resource "aws_iam_policy" "ecs_task_ssm_policy" {
  provider    = aws.freetier
  name = "ecs-task-ssm-access"

  # policy = jsonencode({
  #   Version = "2012-10-17"
  #   Statement = [
  #     {
  #       Effect = "Allow"
  #       Action = [
  #         "ssm:GetParameter",
  #         "ssm:GetParameters"
  #       ]
  #       Resource = [
  #         "arn:aws:ssm:${local.region}:${data.aws_caller_identity.current.account_id}:parameter/${local.container_name}/cert",
  #         "arn:aws:ssm:${local.region}:${data.aws_caller_identity.current.account_id}:parameter/${local.container_name}/key"
  #       ]
  #     },
  #     {
  #       Effect = "Allow"
  #       Action = [
  #         "ssm:StartSession",
  #         "ssm:SendCommand",
  #         "ssm:DescribeSessions",
  #         "ssm:GetConnectionStatus",
  #         "ssmmessages:CreateControlChannel",
  #         "ssmmessages:CreateDataChannel",
  #         "ssmmessages:OpenControlChannel",
  #         "ssmmessages:OpenDataChannel"
  #       ]
  #       Resource = "*"
  #     }
  #   ]
  # })
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ssm:GetParameter",
          "ssm:GetParameters"
        ]
        Resource = [
          "arn:aws:ssm:${local.region}:${data.aws_caller_identity.current.account_id}:parameter/${local.container_name}/cert",
          "arn:aws:ssm:${local.region}:${data.aws_caller_identity.current.account_id}:parameter/${local.container_name}/key",
          "arn:aws:ssm:${local.region}:${data.aws_caller_identity.current.account_id}:parameter/dummy/cert",
          "arn:aws:ssm:${local.region}:${data.aws_caller_identity.current.account_id}:parameter/dummy/key"
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_task_ssm_attach" {
  provider    = aws.freetier
  role       = aws_iam_role.ecs_task.name
  policy_arn = aws_iam_policy.ecs_task_ssm_policy.arn
}

# resource "aws_iam_role_policy_attachment" "ecs_task_ssm_attach2" {
#   provider    = aws.freetier
#   role       = aws_iam_role.ecs_task.name
#   policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
# }