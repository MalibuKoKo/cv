terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
      version = "5.98.0"
    }
  }
}

provider "aws" {
  alias  = "org"
  region = "us-east-1" # Obligatoire pour AWS Organizations
}

provider "aws" {
  alias  = "freetier"
  region  = local.region
  assume_role {role_arn = var.freetier_assume_role_arn}
}