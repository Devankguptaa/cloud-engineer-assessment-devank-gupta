########################################
# Q1 - VPC, Subnets, IGW, NAT Gateway
# Author: Devank Gupta
########################################

terraform {
  required_version = ">= 1.0.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

########################################
# Provider Configuration
########################################

provider "aws" {
  region = "ap-south-1" # Mumbai
}

########################################
# Locals - Common naming and CIDR design
########################################

locals {
  # Prefix to use for all AWS resource names
  name_prefix = "Devank_Gupta"

  # CIDR Design:
  # VPC:           10.0.0.0/16
  # Public Subnet1 10.0.1.0/24  (AZ 1)
  # Public Subnet2 10.0.2.0/24  (AZ 2)
  # Private Subnet1 10.0.11.0/24 (AZ 1)
  # Private Subnet2 10.0.12.0/24 (AZ 2)

  vpc_cidr            = "10.0.0.0/16"
  public_subnet_1_cidr  = "10.0.1.0/24"
  public_subnet_2_cidr  = "10.0.2.0/24"
  private_subnet_1_cidr = "10.0.11.0/24"
  private_subnet_2_cidr = "10.0.12.0/24"
}

########################################
# Get Available AZs in this Region
########################################

data "aws_availability_zones" "available" {
  state = "available"
}

########################################
# VPC
########################################

resource "aws_vpc" "main" {
  cidr_block           = local.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${local.name_prefix}_VPC"
  }
}

########################################
# Internet Gateway
########################################

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${local.name_prefix}_IGW"
  }
}

########################################
# Subnets
########################################

# Public Subnet 1 (AZ 1)
resource "aws_subnet" "public_1" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = local.public_subnet_1_cidr
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true

  tags = {
    Name = "${local.name_prefix}_Public_Subnet_1"
    Tier = "public"
  }
}

# Public Subnet 2 (AZ 2)
resource "aws_subnet" "public_2" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = local.public_subnet_2_cidr
  availability_zone       = data.aws_availability_zones.available.names[1]
  map_public_ip_on_launch = true

  tags = {
    Name = "${local.name_prefix}_Public_Subnet_2"
    Tier = "public"
  }
}

# Private Subnet 1 (AZ 1)
resource "aws_subnet" "private_1" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = local.private_subnet_1_cidr
  availability_zone = data.aws_availability_zones.available.names[0]

  tags = {
    Name = "${local.name_prefix}_Private_Subnet_1"
    Tier = "private"
  }
}

# Private Subnet 2 (AZ 2)
resource "aws_subnet" "private_2" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = local.private_subnet_2_cidr
  availability_zone = data.aws_availability_zones.available.names[1]

  tags = {
    Name = "${local.name_prefix}_Private_Subnet_2"
    Tier = "private"
  }
}

########################################
# Elastic IP for NAT Gateway
########################################

resource "aws_eip" "nat_eip" {
  domain = "vpc"

  tags = {
    Name = "${local.name_prefix}_NAT_EIP"
  }
}

########################################
# NAT Gateway (in Public Subnet 1)
########################################

resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat_eip.id
  subnet_id     = aws_subnet.public_1.id

  tags = {
    Name = "${local.name_prefix}_NAT_Gateway"
  }

  depends_on = [aws_internet_gateway.igw]
}

########################################
# Route Tables
########################################

# Public Route Table - Internet-facing
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${local.name_prefix}_Public_Route_Table"
  }
}

# Route for Public RT: Internet-bound via IGW
resource "aws_route" "public_internet_route" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.igw.id
}

# Private Route Table - Outbound via NAT
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${local.name_prefix}_Private_Route_Table"
  }
}

# Route for Private RT: Internet-bound via NAT Gateway
resource "aws_route" "private_nat_route" {
  route_table_id         = aws_route_table.private.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.nat.id
}

########################################
# Route Table Associations
########################################

# Public subnets -> Public Route Table
resource "aws_route_table_association" "public_1_assoc" {
  subnet_id      = aws_subnet.public_1.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "public_2_assoc" {
  subnet_id      = aws_subnet.public_2.id
  route_table_id = aws_route_table.public.id
}

# Private subnets -> Private Route Table
resource "aws_route_table_association" "private_1_assoc" {
  subnet_id      = aws_subnet.private_1.id
  route_table_id = aws_route_table.private.id
}

resource "aws_route_table_association" "private_2_assoc" {
  subnet_id      = aws_subnet.private_2.id
  route_table_id = aws_route_table.private.id
}

########################################
# Outputs (useful for screenshots / verification)
########################################

output "vpc_id" {
  value = aws_vpc.main.id
}

output "public_subnets" {
  value = [aws_subnet.public_1.id, aws_subnet.public_2.id]
}

output "private_subnets" {
  value = [aws_subnet.private_1.id, aws_subnet.private_2.id]
}

output "nat_gateway_id" {
  value = aws_nat_gateway.nat.id
}

output "internet_gateway_id" {
  value = aws_internet_gateway.igw.id
}
