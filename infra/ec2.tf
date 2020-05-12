# Key Pair
resource "aws_key_pair" "A2_TechTestApp_deployer" {
  key_name   = "tech-test-app-deployer-key"
  public_key = var.public_key
}


# An EC2 instance ("an EC2 instance deployed in the Private layer")
data "aws_ami" "amazon-linux-2" { # latest amazon linux 2 ami
  most_recent = true

  owners = ["amazon"]

  filter {
    name   = "owner-alias"
    values = ["amazon"]
  }

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm*"]
  }
}

resource "aws_instance" "web" {
  ami                         = data.aws_ami.amazon-linux-2.id
  instance_type               = "t2.micro"
  subnet_id                   = aws_subnet.private_az1.id
  associate_public_ip_address = true
  key_name                    = aws_key_pair.A2_TechTestApp_deployer.key_name
  vpc_security_group_ids      = [aws_security_group.main.id]
  count                       = 1

  tags = {
    Name = "TechTestApp EC2 Instance"
  }
}


# Target Group
resource "aws_lb_target_group" "A2_TechTestApp" {
  name     = "tech-test-app-target-group"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id
}


# Load Balancer ("a Load Balancer deployed in Public layer")
resource "aws_lb" "A2_TechTestApp" {
  name               = "tech-test-app-lb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.main.id]
  subnets            = [aws_subnet.public_az1.id, aws_subnet.public_az2.id, aws_subnet.public_az3.id]

  tags = {
    Environment = "production"
  }
}


# Load Balancer Listener
resource "aws_lb_listener" "front_end" {
  load_balancer_arn = aws_lb.A2_TechTestApp.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.A2_TechTestApp.arn
  }
}


# # Launch Configuration do not need
# resource "aws_launch_configuration" "A2_TechTestApp" {
#   name            = "tech-test-app-lc"
#   image_id        = var.ami_id
#   instance_type   = "t2.micro"
#   security_groups = [aws_security_group.main.id]

#   key_name = aws_key_pair.A2_TechTestApp_deployer.key_name
# }


# # Auto Scaling Group ("EC2 instance deployed in Private layer") do not need
# resource "aws_autoscaling_group" "A2_TechTestApp" {
#   name                 = "tech-test-app-asg"
#   launch_configuration = aws_launch_configuration.A2_TechTestApp.name
#   max_size             = 1
#   min_size             = 1
#   vpc_zone_identifier  = [aws_subnet.private_az1.id, aws_subnet.private_az2.id, aws_subnet.private_az3.id]
#   target_group_arns    = [aws_lb_target_group.A2_TechTestApp.arn]
# }
