terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
  backend "s3" {}
}

provider "aws" {
  region = var.aws_region
}

variable "aws_region" {
  default = "us-east-1"
}

variable "project_name" {
  description = "Project name for tagging and resource naming"
}

variable "public_key" {
  description = "SSH public key for EC2 access"
}

variable "instance_type" {
  default = "t3.micro"
}

#  Key pair 
resource "aws_key_pair" "app" {
  key_name   = "${var.project_name}-key"
  public_key = var.public_key
}

#  VPC / networking (default VPC) 
data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

#  Security group 
resource "aws_security_group" "app" {
  name        = "${var.project_name}-sg"
  description = "Allow HTTP and SSH"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Project = var.project_name
    Name    = "${var.project_name}-sg"
  }
}

#  AMI: latest Amazon Linux 2023 
data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

#  EC2 instance 
resource "aws_instance" "app" {
  ami                         = data.aws_ami.al2023.id
  instance_type               = var.instance_type
  key_name                    = aws_key_pair.app.key_name
  vpc_security_group_ids      = [aws_security_group.app.id]
  subnet_id                   = data.aws_subnets.default.ids[0]
  associate_public_ip_address = true

  tags = {
    Project = var.project_name
    Name    = "${var.project_name}-app"
  }
}

#  Elastic IP (stable public address) 
resource "aws_eip" "app" {
  instance = aws_instance.app.id
  domain   = "vpc"

  tags = {
    Project = var.project_name
    Name    = "${var.project_name}-eip"
  }
}

#  Outputs 
output "instance_public_ip" {
  value = aws_eip.app.public_ip
}

output "app_url" {
  value = "http://${aws_eip.app.public_ip}"
}