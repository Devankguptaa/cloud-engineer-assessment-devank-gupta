##############################################
# Q3 - HA Architecture with ALB + ASG
# Author: Devank Gupta
##############################################

provider "aws" {
  region = "ap-south-1"
}

##############################################
# Locals
##############################################

locals {
  name_prefix = "Devank_Gupta_Q3"

  vpc_cidr             = "10.20.0.0/16"
  public_subnet_1_cidr = "10.20.1.0/24"
  public_subnet_2_cidr = "10.20.2.0/24"
  private_subnet_1_cidr = "10.20.11.0/24"
  private_subnet_2_cidr = "10.20.12.0/24"
}

##############################################
# AZs
##############################################

data "aws_availability_zones" "available" {
  state = "available"
}

##############################################
# VPC
##############################################

resource "aws_vpc" "main" {
  cidr_block           = local.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${local.name_prefix}_VPC"
  }
}

##############################################
# Internet Gateway
##############################################

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${local.name_prefix}_IGW"
  }
}

##############################################
# Subnets
##############################################

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

resource "aws_subnet" "private_1" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = local.private_subnet_1_cidr
  availability_zone = data.aws_availability_zones.available.names[0]

  tags = {
    Name = "${local.name_prefix}_Private_Subnet_1"
    Tier = "private"
  }
}

resource "aws_subnet" "private_2" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = local.private_subnet_2_cidr
  availability_zone = data.aws_availability_zones.available.names[1]

  tags = {
    Name = "${local.name_prefix}_Private_Subnet_2"
    Tier = "private"
  }
}

##############################################
# NAT Gateway (for private subnets)
##############################################

resource "aws_eip" "nat_eip" {
  domain = "vpc"

  tags = {
    Name = "${local.name_prefix}_NAT_EIP"
  }
}

resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat_eip.id
  subnet_id     = aws_subnet.public_1.id

  tags = {
    Name = "${local.name_prefix}_NAT_Gateway"
  }

  depends_on = [aws_internet_gateway.igw]
}

##############################################
# Route Tables
##############################################

# Public RT: 0.0.0.0/0 -> IGW
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${local.name_prefix}_Public_Route_Table"
  }
}

resource "aws_route" "public_internet_route" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.igw.id
}

# Private RT: 0.0.0.0/0 -> NAT
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${local.name_prefix}_Private_Route_Table"
  }
}

resource "aws_route" "private_nat_route" {
  route_table_id         = aws_route_table.private.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.nat.id
}

# Associations
resource "aws_route_table_association" "public_1_assoc" {
  subnet_id      = aws_subnet.public_1.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "public_2_assoc" {
  subnet_id      = aws_subnet.public_2.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "private_1_assoc" {
  subnet_id      = aws_subnet.private_1.id
  route_table_id = aws_route_table.private.id
}

resource "aws_route_table_association" "private_2_assoc" {
  subnet_id      = aws_subnet.private_2.id
  route_table_id = aws_route_table.private.id
}

##############################################
# Security Groups
##############################################

# ALB SG: allow HTTP from internet
resource "aws_security_group" "alb_sg" {
  name   = "${local.name_prefix}_ALB_SG"
  vpc_id = aws_vpc.main.id

  ingress {
    description = "HTTP from anywhere"
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

  tags = {
    Name = "${local.name_prefix}_ALB_SG"
  }
}

# EC2 SG: allow HTTP from within VPC (ALB resides inside)
resource "aws_security_group" "ec2_sg" {
  name   = "${local.name_prefix}_EC2_SG"
  vpc_id = aws_vpc.main.id

  ingress {
    description = "HTTP from VPC"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = [local.vpc_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${local.name_prefix}_EC2_SG"
  }
}

##############################################
# AMI for EC2
##############################################

data "aws_ami" "amazon_linux" {
  most_recent = true

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }

  owners = ["137112412989"] # Amazon
}

##############################################
# Launch Template for ASG
##############################################

resource "aws_launch_template" "web_lt" {
  name_prefix   = "${local.name_prefix}_LT_"
  image_id      = data.aws_ami.amazon_linux.id
  instance_type = "t3.micro"

  vpc_security_group_ids = [aws_security_group.ec2_sg.id]

  user_data = base64encode(<<-EOF
#!/bin/bash
yum update -y
amazon-linux-extras install nginx1 -y || yum install nginx -y
systemctl enable nginx
systemctl start nginx

cat > /usr/share/nginx/html/index.html << 'HTML'
<!DOCTYPE html>
<html>
<head>
  <title>Devank Gupta - HA Resume Site</title>
</head>
<body>
  <h1>Welcome to Devank Gupta's Highly Available Resume Site</h1>
  <p>This page is served from an EC2 instance running in a private subnet, behind an Application Load Balancer and Auto Scaling Group.</p>
</body>
</html>
HTML
EOF
  )

  tag_specifications {
    resource_type = "instance"

    tags = {
      Name = "${local.name_prefix}_Web_Server"
    }
  }
}


##############################################
# Target Group
##############################################

resource "aws_lb_target_group" "web_tg" {
  name        = "devank-gupta-q3-tg"
  port        = 80
  protocol    = "HTTP"
  target_type = "instance"
  vpc_id      = aws_vpc.main.id

  health_check {
    path                = "/"
    protocol            = "HTTP"
    matcher             = "200"
    interval            = 30
    healthy_threshold   = 3
    unhealthy_threshold = 3
    timeout             = 5
  }

  tags = {
    Name = "${local.name_prefix}_TG"
  }
}

##############################################
# Application Load Balancer
##############################################

resource "aws_lb" "app_lb" {
  name               = "devank-gupta-q3-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  subnets            = [aws_subnet.public_1.id, aws_subnet.public_2.id]

  tags = {
    Name = "${local.name_prefix}_ALB"
  }
}

resource "aws_lb_listener" "http_listener" {
  load_balancer_arn = aws_lb.app_lb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.web_tg.arn
  }
}

##############################################
# Auto Scaling Group
##############################################

resource "aws_autoscaling_group" "web_asg" {
  name                      = "${local.name_prefix}_ASG"
  max_size                  = 3
  min_size                  = 1
  desired_capacity          = 2
  health_check_type         = "ELB"
  health_check_grace_period = 60

  vpc_zone_identifier = [
    aws_subnet.private_1.id,
    aws_subnet.private_2.id
  ]

  target_group_arns = [aws_lb_target_group.web_tg.arn]

  launch_template {
    id      = aws_launch_template.web_lt.id
    version = "$Latest"
  }

  tag {
    key                 = "Name"
    value               = "${local.name_prefix}_ASG_Instance"
    propagate_at_launch = true
  }

  depends_on = [aws_lb_listener.http_listener]
}

##############################################
# Outputs
##############################################

output "alb_dns_name" {
  value = aws_lb.app_lb.dns_name
}
