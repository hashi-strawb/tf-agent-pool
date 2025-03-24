terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  cloud {
    organization = "fancycorp"
    workspaces {
      name = "tf-agent-pool"
    }
  }
}

provider "aws" {
  region = "eu-west-2"
}
