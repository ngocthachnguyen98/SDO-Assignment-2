# RDS Instance
resource "aws_db_instance" "A2_TechTestApp" {
  identifier            = "tech-test-app-db"
  allocated_storage     = 20
  max_allocated_storage = 0 # disable autoscaling
  storage_type          = "gp2"
  engine                = "postgres"
  engine_version        = "10.7"
  instance_class        = "db.t2.micro"
  name                  = "app"
  username              = "postgres"
  password              = "changeme"
  port                  = "5432"
  skip_final_snapshot   = true

  vpc_security_group_ids = [aws_security_group.main.id]

  db_subnet_group_name = aws_db_subnet_group.main.name

  tags = {
    Name = "TechTestApp DB Instance"
  }
}


resource "aws_db_subnet_group" "main" {
  name       = "tech-test-app-db-subnet-group"
  subnet_ids = [aws_subnet.data_az1.id, aws_subnet.data_az2.id, aws_subnet.data_az3.id]

  tags = {
    Name = "TechTestApp DB Subnet Group"
  }
}
