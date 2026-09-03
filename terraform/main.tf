terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}


data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical's official AWS account

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}


data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }

  filter {
    name   = "availability-zone"
    values = ["us-east-1a", "us-east-1b"]
  }
}


resource "tls_private_key" "lb_key" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "local_file" "private_key" {
  content         = tls_private_key.lb_key.private_key_pem
  filename        = "${path.module}/nginx-lb-key.pem"
  file_permission = "0400"
}

resource "aws_key_pair" "lb_key" {
  key_name   = "nginx-lb-key"
  public_key = tls_private_key.lb_key.public_key_openssh
}

# --- Security Groups ---
resource "aws_security_group" "lb_sg" {
  name        = "lb-sg"
  description = "Load balancer SG"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["144.48.130.72/32"]
  }
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "backend_sg" {
  name        = "backend-sg"
  description = "Backend servers SG"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["144.48.130.72/32"]
  }
  ingress {
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.lb_sg.id]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}


# --- Backend instances ---
resource "aws_instance" "backend" {
  for_each = {
    a = "A"
    b = "B"
  }

  ami           = data.aws_ami.ubuntu.id
  instance_type = "t3.micro"
  key_name      = aws_key_pair.lb_key.key_name

  subnet_id = data.aws_subnets.default.ids[
    each.key == "a" ? 0 : 1
  ]

  vpc_security_group_ids      = [aws_security_group.backend_sg.id]
  associate_public_ip_address = true

  user_data = templatefile("${path.module}/templates/backend-userdata.sh.tpl", {
    label = each.value
  })

  tags = {
    Name = "Backend-Server-${each.value}"
  }
}

# --- Load balancer instance ---
resource "aws_instance" "lb" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = "t3.micro"
  key_name                    = aws_key_pair.lb_key.key_name
  subnet_id                   = data.aws_subnets.default.ids[0]
  vpc_security_group_ids      = [aws_security_group.lb_sg.id]
  associate_public_ip_address = true

  user_data = templatefile("${path.module}/templates/lb-userdata.sh.tpl", {
    backend_ips = [for i in aws_instance.backend : i.private_ip]
  })

  tags       = { Name = "NGINX-Load-Balancer" }
  depends_on = [aws_instance.backend]
}
