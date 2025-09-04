resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "main-vpc"
  }
}

resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "main-igw"
  }
}

resource "aws_subnet" "public" {
  count                  = 3
  vpc_id                 = aws_vpc.main.id
  cidr_block             = cidrsubnet("10.0.0.0/16", 8, count.index)
  availability_zone      = var.availability_zones[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name = "public-subnet-${count.index + 1}"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }

  tags = {
    Name = "public-rt"
  }
}

resource "aws_route_table_association" "public_assoc" {
  count          = length(aws_subnet.public)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_security_group" "allow_http" {
  name        = "allow_http"
  description = "Allow HTTP and SSH"
  vpc_id      = aws_vpc.main.id

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
    Name = "allow_http"
  }
}

resource "aws_instance" "web" {
  count                      = 3
  ami                        = var.ami_id
  instance_type              = "t3.micro"
  subnet_id                  = aws_subnet.public[count.index].id
  vpc_security_group_ids      = [aws_security_group.allow_http.id]
  associate_public_ip_address = true

  user_data = <<-EOT
    #!/bin/bash
    yum update -y
    amazon-linux-extras enable nginx1
    yum install nginx -y
    echo "<h1>${var.page_titles[count.index]}</h1>" > /usr/share/nginx/html/index.html
    systemctl start nginx
    systemctl enable nginx
  EOT

  tags = {
    Name = "web-${count.index + 1}"
  }
}

resource "aws_lb" "app_lb" {
  name               = "app-lb"
  internal           = false
  load_balancer_type  = "application"
  security_groups     = [aws_security_group.allow_http.id]
  subnets             = aws_subnet.public[*].id

  tags = {
    Name = "app-lb"
  }
}

resource "aws_lb_target_group" "tg" {
  count    = 3
  name     = "tg-${count.index + 1}"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id

  health_check {
    path = "/"
    port = "80"
  }

  tags = {
    Name = "tg-${count.index + 1}"
  }
}

resource "aws_lb_target_group_attachment" "tga" {
  count            = 3
  target_group_arn = aws_lb_target_group.tg[count.index].arn
  target_id        = aws_instance.web[count.index].id
  port             = 80
}

resource "aws_lb_listener" "listener" {
  load_balancer_arn = aws_lb.app_lb.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type = "fixed-response"

    fixed_response {
      content_type = "text/plain"
      message_body = "Not Found"
      status_code  = "404"
    }
  }
}

resource "aws_lb_listener_rule" "rule" {
  count        = 3
  listener_arn = aws_lb_listener.listener.arn
  priority     = count.index + 1

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.tg[count.index].arn
  }

  condition {
    path_pattern {
      values = [var.paths[count.index]]
    }
  }
}
