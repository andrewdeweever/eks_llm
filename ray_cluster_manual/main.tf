provider "aws" {
  region = "us-east-1" # Change to your preferred region
}


resource "tls_private_key" "ray_key" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "aws_key_pair" "ray_key_pair" {
  key_name   = "ray-key-pair"
  public_key = tls_private_key.ray_key.public_key_openssh
}

variable "my_ip" {
  description = "Your IP address for SSH access (e.g., '203.0.113.0/32')"
  type        = string
  default     = "66.181.119.146/32"
}

# Data source for latest DLAMI AMI ID (PyTorch 2.9 on Amazon Linux 2023, OSS NVIDIA Driver for g6 compatibility)
data "aws_ssm_parameter" "dlami" {
  name = "/aws/service/deeplearning/ami/x86_64/oss-nvidia-driver-gpu-pytorch-2.9-amazon-linux-2023/latest/ami-id"
}

# VPC
resource "aws_vpc" "ray_vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = {
    Name = "ray-vpc"
  }
}

# Subnet (public for internet access)
resource "aws_subnet" "ray_subnet" {
  vpc_id                  = aws_vpc.ray_vpc.id
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = true
  availability_zone       = "us-east-1a" # Change if needed
  tags = {
    Name = "ray-subnet"
  }
}

# Internet Gateway
resource "aws_internet_gateway" "ray_igw" {
  vpc_id = aws_vpc.ray_vpc.id
  tags = {
    Name = "ray-igw"
  }
}

# Route Table
resource "aws_route_table" "ray_rt" {
  vpc_id = aws_vpc.ray_vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.ray_igw.id
  }
  tags = {
    Name = "ray-rt"
  }
}

# Route Table Association
resource "aws_route_table_association" "ray_rta" {
  subnet_id      = aws_subnet.ray_subnet.id
  route_table_id = aws_route_table.ray_rt.id
}

# Security Group
resource "aws_security_group" "ray_sg" {
  vpc_id = aws_vpc.ray_vpc.id
  name   = "ray-sg"

  # Inbound: SSH from your IP
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.my_ip]
  }

  # Inbound: Ray ports (from anywhere; restrict if needed)
  ingress {
    from_port   = 6379
    to_port     = 6379
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 8265
    to_port     = 8265
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 8000
    to_port     = 8000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Inbound: All traffic within VPC
  ingress {
    from_port = 0
    to_port   = 0
    protocol  = "-1"
    self      = true
  }

  # Outbound: All traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "ray-sg"
  }
}

resource "aws_placement_group" "ray_cluster_pg" {
  name     = "ray-cluster-pg"
  strategy = "cluster" # For low-latency grouping in the same AZ
}

# Head Instance
resource "aws_instance" "ray_head" {
  ami                    = data.aws_ssm_parameter.dlami.value
  instance_type          = "g6.xlarge"
  key_name               = aws_key_pair.ray_key_pair.key_name
  subnet_id              = aws_subnet.ray_subnet.id
  vpc_security_group_ids = [aws_security_group.ray_sg.id]

  root_block_device {
    volume_size = 100 # GiB
  }
  placement_group = aws_placement_group.ray_cluster_pg.name

  tags = {
    Name = "ray-head"
  }
}

# Worker Instance
resource "aws_instance" "ray_worker" {
  count                  = 3
  ami                    = data.aws_ssm_parameter.dlami.value
  instance_type          = "g6.xlarge"
  key_name               = aws_key_pair.ray_key_pair.key_name
  subnet_id              = aws_subnet.ray_subnet.id
  vpc_security_group_ids = [aws_security_group.ray_sg.id]
  placement_group        = aws_placement_group.ray_cluster_pg.name

  root_block_device {
    volume_size = 100 # GiB
  }

  tags = {
    Name = "ray-worker"
  }
}

# Outputs
output "head_public_ip" {
  value = aws_instance.ray_head.public_ip
}

output "worker_public_ip_0" {
  value = aws_instance.ray_worker[0].public_ip
}
output "worker_public_ip_1" {
  value = aws_instance.ray_worker[1].public_ip
}
output "worker_public_ip_2" {
  value = aws_instance.ray_worker[2].public_ip
}
# output "dlami_id" {
#   value = data.aws_ssm_parameter.dlami.value
# }

output "ssh_priv" {
  value     = tls_private_key.ray_key.private_key_pem
  sensitive = true
}
