**Student Name: Thach Ngoc Nguyen**

**Student Number: s3651311**

# Servian TechTestApp


## DEPENDENCIES

### VPC
The code below is how the VPC is created on AWS using Terraform in `infra/vpc.tf`

```
resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"

  tags = {
    Name = "SDO Assignment 2"
  }
}
```

We also give Internet access by creating a gateway. This will help us connect to and from the services in our above VPC:

```
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "SDO Assignment 2"
  }
}
```

We create the default route table in the VPC so AWS knows to send internet bound traffic to the gateway. 

```
resource "aws_default_route_table" "main" {
  default_route_table_id = aws_vpc.main.default_route_table_id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name = "SDO Assignment 2 default route table"
  }
}
```
---
### Subnets
The specification states that we will need a VPC with 3 layers across 3 availability zones (9 subnets) (Public, Private and Data). One availability zone will have one subnet for public, one for private and one for data.

* The 3 availability zones are: us-east-1a, us-east-1b & us-east-1c.
* For the 9 subnets, there are 3 for the public, 3 for the private and 3 for the data. 
* Below are are the 3 representing code blocks for the subnets for one availability zone.

```
# Public
resource "aws_subnet" "public_az1" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.0.0/22"
  availability_zone       = "us-east-1a"
  map_public_ip_on_launch = true

  tags = {
    Name = "Public AZ1"
  }
}
```

```
# Private
resource "aws_subnet" "private_az1" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.16.0/22"
  availability_zone       = "us-east-1a"
  map_public_ip_on_launch = true

  tags = {
    Name = "Private AZ1"
  }
}
```

```
# Data
resource "aws_subnet" "data_az1" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.32.0/22"
  availability_zone       = "us-east-1a"
  map_public_ip_on_launch = true

  tags = {
    Name = "Data AZ1"
  }
}
```
---
### Application Deployment
Once the VPC is declared, we will have the environment to deploy our EC2 instance (in the Private layer) with a load balancer (deployed in the Public layer) and backed by an RDS database in the Data layer

### Key Pair
But to log into the instance, a key pair is needed. This can be an RSA SSH key created on your local machine. You need to declare public key `id_rsa.pub` (could have differnt naming) in `infra/terraform.tfvars` for `var.public_key` in `infra/ec2.tf`

```
resource "aws_key_pair" "A2_TechTestApp_deployer" {
  key_name   = "tech-test-app-deployer-key"
  public_key = var.public_key
}
```
---
### EC2 instance
For the AMI, the latest Amazon Linux 2 image will be used for the instance

```
data "aws_ami" "amazon-linux-2" {
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
```

Only one instance will be deployed in the Private layer as stated in the specification

```
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
```
---
### Security Group
This security group provides access:
* To EC2 instance for SSH, HTTP (to get the website) 
* To the RDS instance (to run update script like updatedb command for the TechTestApp)

```
resource "aws_security_group" "main" {
  description = "Allow SSH and HTTP inbound traffic"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "SSH from Internet"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTP from Internet"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # For Postgres database
  ingress {
    description = "Postgres"
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    # cidr_blocks = ["0.0.0.0/0"]
    cidr_blocks = [aws_subnet.data_az1.cidr_block, aws_subnet.data_az2.cidr_block, aws_subnet.data_az3.cidr_block]
  }

  # Allow all outbound traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  lifecycle {
    create_before_destroy = true
  }

  tags = {
    Name = "Security Group"
  }
}
```
---
### Target Group 
The target group is for telling the load balancer to direct the traffic to the EC2 instance.

```
resource "aws_lb_target_group" "A2_TechTestApp" {
  name     = "tech-test-app-target-group"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id
}
```
---
### Load Balancer
Next is the load balancer with its listener. The listener is used to define the routing, and ties the port and protocol to the instance in the target group.

```
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
```

```
resource "aws_lb_listener" "front_end" {
  load_balancer_arn = aws_lb.A2_TechTestApp.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.A2_TechTestApp.arn
  }
}
```
---
### RDS instance
A database backing the application will be deployed:
* In the Data layer (a database subnet group will be declared for this purpose)
* With Postgres 10.7 
* With specific configuration according to the documentaion of the application, like database name, username, etc.


```
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
```
---
### Remote Backend
For storing Terraform state file remotely, an AWS S3 bucket and DynamoDB table will be set up as below:
* First code block is for declaring S3 bucket 
* Second code block is for declaring DynamoDB table
* The third one is where you put S3 bucket and DynamoDB together (remote backend)

```
resource "aws_s3_bucket" "terraform-state-storage-s3" {
  bucket = "tech-test-app-remote-state-storage-bucket"
  acl    = "private"
  force_destroy = true

  versioning {
    enabled = true
  }

  tags = {
    Name = "TechTechApp Remote State Storage Bucket"
  }
}


resource "aws_dynamodb_table" "dynamodb-terraform-state-lock" {
  name = "tech-test-app-terraform-state-lock-dynamo"
  hash_key = "LockID"
  read_capacity = 20
  write_capacity = 20
 
  attribute {
    name = "LockID"
    type = "S"
  }
 
  tags = {
    Name = "TechTechApp DynamoDB Terraform State Lock Table"
  }
}


terraform {
  backend "s3" {
    bucket = "tech-test-app-remote-state-storage-bucket"
    encrypt = true
    key    = "terraform.tfstate"
    region = "us-east-1"
    dynamodb_tablle = "tech-test-app-terraform-state-lock-dynamo"
  }
}
```

The Makefile is also updated with the right terraform init command for initiializing the remote backend

```
terraform init --backend-config="key=terraform.tfstate" --backend-config="dynamodb_table=tech-test-app-terraform-state-lock-dynamo" --backend-config="bucket=tech-test-app-remote-state-storage-bucket"
```
---
## DEPLOY INSTRUCTION

First we need to deploy infrastructure onto AWS. Simply change into `/infra` directory where the `Makefile` located and run:

```
make init
make up
```

After the infrastructure is ready, change into `/ansible` directory and run this command: 

```
./run_ansible.sh
```

* What the above command would do is first generate `inventory.yml` file with the public IP of our EC2 instance so that we can access it from `playbook.yml`
* Secondly it will generate `/vars/external_vars.yml` with the database endpoint, username and password for overriding environment variables from the `playbook.yml`
* Lastly it will run `playbook.yml` 

### Ansible Playbook



---
## CLEAN UP INSTRUCTION
