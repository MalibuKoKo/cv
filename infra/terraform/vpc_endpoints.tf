# https://rebirth.devoteam.com/2023/07/18/ecs-fargate-terraform/

# resource "aws_security_group" "vpc_endpoints" {
#   provider = aws.freetier
#   name        = "vpc-endpoints"
#   description = "Allow ECS tasks to reach SSM endpoints"
#   vpc_id      = module.vpc.vpc_id

#   ingress {
#     from_port   = 443
#     to_port     = 443
#     protocol    = "tcp"
#     cidr_blocks = module.vpc.public_subnets_cidr_blocks
#   }

#   egress {
#     from_port   = 0
#     to_port     = 0
#     protocol    = "-1"
#     cidr_blocks = ["0.0.0.0/0"]
#   }
# }

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

# resource "aws_iam_role_policy_attachment" "ecs_task_ssm_attach2" {
#   provider    = aws.freetier
#   role       = aws_iam_role.ecs_task.name
#   policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
# }