
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region = "ap-south-1"
}


data "aws_ecr_repository" "app" {
  name = "nodejs-cicd-app"
}

# 4. Find the default VPC
data "aws_vpc" "default" {
  default = true
}

# 5. Find available subnets
data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }

  filter {
    name   = "state"
    values = ["available"]
  }
}

# 6. Find the latest Ubuntu 24.04 AMI
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
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


# Security group for Node.js application
resource "aws_security_group" "app_sg" {
  name        = "nodejs-cicd-security-group"
  description = "Allow traffic to Node.js application"
  vpc_id      = data.aws_vpc.default.id

  # Allow incoming application traffic
  ingress {
    description = "Node.js application"
    from_port   = 3000
    to_port     = 3000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow outgoing traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "nodejs-cicd-security-group"
  }
}


# IAM role that EC2 can assume
resource "aws_iam_role" "ec2_ecr_role" {
  name = "nodejs-cicd-ec2-ecr-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
}

# Allow EC2 to pull images from our ECR repository
resource "aws_iam_role_policy" "ecr_policy" {
  name = "nodejs-cicd-ecr-pull-policy"
  role = aws_iam_role.ec2_ecr_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["ecr:GetAuthorizationToken"]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage"
        ]
        Resource = data.aws_ecr_repository.app.arn
      }
    ]
  })
}

# Instance profile to attach the IAM role to EC2
resource "aws_iam_instance_profile" "ec2_profile" {
  name = "nodejs-cicd-ec2-instance-profile"
  role = aws_iam_role.ec2_ecr_role.name
}

resource "aws_iam_role_policy_attachment" "ssm_policy" {
  role       = aws_iam_role.ec2_ecr_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}


# EC2 instance for Node.js application
resource "aws_instance" "app_server" {
  ami           = data.aws_ami.ubuntu.id
  instance_type = "t3.micro"

  subnet_id = data.aws_subnets.default.ids[0]

  vpc_security_group_ids = [
    aws_security_group.app_sg.id
  ]

  iam_instance_profile = aws_iam_instance_profile.ec2_profile.name

  associate_public_ip_address = true

  depends_on = [
    aws_iam_role_policy.ecr_policy,
    aws_iam_role_policy_attachment.ssm_policy
  ]

  user_data = <<-EOF
    #!/bin/bash
    set -e
    set -o pipefail

    apt-get update -y
    apt-get install -y docker.io curl unzip

    systemctl enable docker
    systemctl start docker

    curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" \
      -o "/tmp/awscliv2.zip"

    unzip -q /tmp/awscliv2.zip -d /tmp
    /tmp/aws/install

    aws ecr get-login-password --region ap-south-1 | \
      docker login --username AWS --password-stdin ${data.aws_ecr_repository.app.repository_url}

    docker pull ${data.aws_ecr_repository.app.repository_url}:v1

    docker run -d \
      --name nodejs-app \
      --restart unless-stopped \
      -p 3000:3000 \
      ${data.aws_ecr_repository.app.repository_url}:v1
  EOF

  user_data_replace_on_change = true

  tags = {
    Name = "nodejs-cicd-app-server"
  }
}

