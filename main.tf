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

  default_tags {
    tags = {
      Name      = "Test TFC Agents"
      Terraform = "true"
      Workspace = terraform.workspace
      TTL       = "Ephemeral Workspace"
      Owner     = "Lucy"
      Purpose   = "Test TFC Agents"
      Source    = "https://github.com/hashi-strawb/tf-agent-pool"
    }
  }
}

data "aws_availability_zones" "available" {
  state = "available"
}
data "aws_region" "current" {}

module "vpc" {
  source = "terraform-aws-modules/vpc/aws"

  name = "agent-vpc"
  cidr = "10.0.0.0/16"

  azs            = data.aws_availability_zones.available.names[*]
  public_subnets = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]
}


# Allow us to easily connect to the EC2 instance with AWS EC2 Connect

data "aws_ip_ranges" "ec2_instance_connect" {
  regions  = [data.aws_region.current.name]
  services = ["ec2_instance_connect"]
}

resource "aws_security_group" "ec2_instance_connect" {
  name        = "ec2_instance_connect"
  description = "Allow EC2 Instance Connect to access this host"

  vpc_id = module.vpc.vpc_id

  ingress {
    from_port        = "22"
    to_port          = "22"
    protocol         = "tcp"
    cidr_blocks      = data.aws_ip_ranges.ec2_instance_connect.cidr_blocks
    ipv6_cidr_blocks = data.aws_ip_ranges.ec2_instance_connect.ipv6_cidr_blocks
  }

  tags = {
    CreateDate = data.aws_ip_ranges.ec2_instance_connect.create_date
    SyncToken  = data.aws_ip_ranges.ec2_instance_connect.sync_token
  }
}


data "tfe_ip_ranges" "addresses" {}


moved {
  from = aws_security_group.outbound_http_tfc
  to   = aws_security_group.outbound_http
}

resource "aws_security_group" "outbound_http" {
  name        = "outbound_http"
  description = "Allow outbound HTTP(S) access to everywhere"

  vpc_id = module.vpc.vpc_id

  egress {
    cidr_blocks = [
      "0.0.0.0/0",
    ]
    from_port = 443
    ipv6_cidr_blocks = [
      "::/0",
    ]
    protocol = "tcp"
    to_port  = 443
  }
  egress {
    cidr_blocks = [
      "0.0.0.0/0",
    ]
    from_port = 80
    ipv6_cidr_blocks = [
      "::/0",
    ]
    protocol = "tcp"
    to_port  = 80
  }
}

# Now create the EC2 instance
resource "aws_instance" "agent" {
  ami = "ami-0c41542cdc0e23561" # picked from the catalog by hand 
  # TODO: https://discuss.hashicorp.com/t/how-to-filters-amazon-linux-3-with-graviton-and-gp3-type/52933/2

  associate_public_ip_address = true

  instance_type = "t4g.nano"
  vpc_security_group_ids = [
    aws_security_group.ec2_instance_connect.id,
    aws_security_group.outbound_http.id,
  ]

  subnet_id = module.vpc.public_subnets[0]

  lifecycle {
    create_before_destroy = true
  }


  # Doesn't seem like this does actually work...
  user_data = <<-EOF
    #!/bin/bash
    echo "export TFC_AGENT_NAME=${var.tfc_agent_name}"   >> /home/ec2-user
    echo "export TFC_AGENT_TOKEN=${var.tfc_agent_token}" >> /home/ec2-user

    wget https://releases.hashicorp.com/tfc-agent/1.22.0-rc.1/tfc-agent_1.22.0-rc.1_linux_arm64.zip
    unzip tfc-agent*.zip

    /home/ec2-user/tfc-agent &
  EOF

}

