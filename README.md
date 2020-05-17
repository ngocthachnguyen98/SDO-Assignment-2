**Student Name: Thach Ngoc Nguyen**

**Student Number: s3651311**

# Servian TechTestApp


## DEPENDENCIES


### VPC

The code below is how the VPC is created on AWS using Terraform in `infra/vpc.tf`.

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

Once the VPC is declared, we will have the environment to deploy our EC2 instance (in the Private layer) with a load balancer (deployed in the Public layer) and backed by an RDS database in the Data layer.

### Key Pair

But to log into the instance, a key pair is needed. 

In the `infra/keys` directory, the RSA key named `ec2-key` will be generated through `infra/key_gen.sh`, which is triggered when running `make up` command. The key will also be added to the `~/.ssh` directory.

The shell script `infra/key_gen.sh` will also create `terraform.tfvars` file to populate `var.public_key` in `infra/ec2.tf`.

```
# key_gen.sh
#!/bin/bash
set +ex

mkdir -p keys

test -f keys/ec2-key || yes | ssh-keygen -t rsa -b 4096 -f keys/ec2-key -N ''

echo -e 'public_key = ''"'"$(cat keys/ec2-key.pub)"'"' > ./terraform.tfvars
```
```
# Key Pair
resource "aws_key_pair" "A2_TechTestApp_deployer" {
  key_name   = "tech-test-app-deployer-key"
  public_key = var.public_key
}
```

---

### EC2 instance

For the AMI, the latest Amazon Linux 2 image will be used for the instance.

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

Only one instance will be deployed in the Private layer as stated in the specification.

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

This security group provides access to the EC2 instance for SSH, HTTP. 

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
* With a database security group

```
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
```
```
# Database subnet group
resource "aws_db_subnet_group" "main" {
  name       = "tech-test-app-db-subnet-group"
  subnet_ids = [aws_subnet.data_az1.id, aws_subnet.data_az2.id, aws_subnet.data_az3.id]

  tags = {
    Name = "TechTestApp DB Subnet Group"
  }
}
```
```
# Databse security group
resource "aws_security_group" "default" {
  description = "Postgres"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "Postgres"
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

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
    Name = "DB Security Group"
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
```
```
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
```
```
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

---

## DEPLOY INSTRUCTION

### For Local Backend

* First we need to deploy infrastructure onto AWS. Simply change into `/infra` directory where the `Makefile` located and run:

```
make init-no-remote
make up
```

* After initializing our backend and the infrastructure is ready, change into `/ansible` directory and run this command: 

```
./run_ansible.sh
```

* What the above command would do is first generate `inventory.yml` file with the public IP of our EC2 instance so that we can access it from `playbook.yml`

* Secondly it will generate `/vars/external_vars.yml` with the database endpoint, username and password for overriding environment variables from the `playbook.yml`

* Lastly it will execute `playbook.yml` 

```
# run_ansible.sh
#!/bin/bash
set +ex

# Genereate inventory.yml file with ec2 host
instance_public_ip="$(cd ../infra && terraform output instance_public_ip)"
echo -e 'all:\n  hosts:\n    ''"'"${instance_public_ip}"'"' > inventory.yml

# Add any additional variables
db_endpoint="$(cd ../infra && terraform output db_endpoint)"
db_user="$(cd ../infra && terraform output db_user)"
db_pass="$(cd ../infra && terraform output db_pass)"

echo -e 'db_endpoint: '"${db_endpoint}"'\n'\
'db_user: '"${db_user}"'\n'\
'db_pass: '"${db_pass}" > ./vars/external_vars.yml;

# Execute playbook.yml
ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook -i inventory.yml -e 'record_host_keys=True' -u ec2-user --private-key ~/.ssh/ec2-key playbook.yml
```

---

### For Remote Backend

* We first need to deploy our infrastructure with **local backend** first to get the S3 Bucket and DynamoDB set up on AWS, which is what's done in the above step. 

* Then uncomment this code block below in `infra/backend.tf`:  

```
# Remote Backend
terraform {
  backend "s3" {
    bucket          = "tech-test-app-remote-state-storage-bucket"
    encrypt         = true
    key             = "terraform.tfstate"
    region          = "us-east-1"
    dynamodb_tablle = "tech-test-app-terraform-state-lock-dynamo"
  }
}
```

* Run `make init` command to initializing the remote backend with the right `--backend-config` option:

```
# infra/Makefile

init:
  terraform init --backend-config="key=terraform.tfstate" --backend-config="dynamodb_table=tech-test-app-terraform-state-lock-dynamo" --backend-config="bucket=tech-test-app-remote-state-storage-bucket"
```

---

### Ansible Playbook

The playbook will go a number of steps in order to deploy the application

#### 1. Check if the release file of the app exists

When run for the first time, the application release file `TechTestApp_v.0.6.0_linux64.zip` will be stored at `/tmp` on the EC2 remote host. We want to check at this location whether the file has already been downloaded.

```
- name: 1. Check if the release file of the app exists
  stat:
    path: /tmp/TechTestApp_v.0.6.0_linux64.zip
  register: release_file
```

#### 2. Download app release to EC2 instance to tmp directory

If the release file already exists at `/tmp`, this step will be skipped. If not, the file will be downloaded.

```
- name: 2. Download app release to EC2 instance to tmp directory
  become: yes
  get_url:
    url: "https://github.com/servian/TechTestApp/releases/download/v.0.6.0/TechTestApp_v.0.6.0_linux64.zip" # path to release file 
    dest: /tmp
    mode: '0644'
  when: not release_file.stat.exists
  register: download_result
```

#### 3. Check if the app directory exists

The path where the application is installed is `/etc/app`. Therefore, we want to check if the application is already installed (unzipping the realease file) at this location.

```
- name: 3. Check if the app directory exists
  stat:
    path: /etc/app
  register: app_dir
```

#### 4. Create app directory if it does not exist

If the `app` directory already exists, this step will be skipped. If not, we create the `app` directory for the application installation coming in later step.

```
- name: 4. Create app directory if it does not exist
  become: yes
  shell: "cd /etc && mkdir app"
  when: not app_dir.stat.exists
```

#### 5. Unzip the release file, if the application has not been already installed

The `/tmp/TechTestApp_v.0.6.0_linux64.zip` file will unzipped to install the Tech Test App on the EC2 instance at `/etc/app`.

```
- name: 5. Unzip the release file, if the application has not been already installed
  become: yes
  unarchive:
    src: /tmp/TechTestApp_v.0.6.0_linux64.zip
    dest: /etc/app
    remote_src: yes
  when: not app_dir.stat.exists
  register: install_result
```

#### 6. Include environment varibles file

The environment variables are generated from `run_ansible.sh` and located `/vars/external_vars.yml`. These will be use for overriding and targeting the right AWS RDS instance (public endpoint, database username and password).

```
- name: 6. Include environment varibles file    
  include_vars: external_vars.yml
```

#### 7. Override environment variables for conf.toml and run TechTestApp updatedb -s

According to the Tech Test App documentation, We will run `./TechTestApp udatedb -s` to create tables and seed data to our RDS instance.

```
- name: 7. Override environment variables for conf.toml and run TechTestApp updatedb -s
  become: yes
  shell: |
    export VTT_DBUSER={{ db_user }}
    export VTT_DBPASSWORD={{ db_pass }}
    export VTT_DBHOST={{ db_endpoint }}
    export VTT_LISTENHOST=0.0.0.0
    export VTT_LISTENPORT=80
    ./TechTestApp updatedb -s
  args:
    chdir: /etc/app/dist
  register: updatedb_result
```

#### 8. Install TechTestApp.service systemd unit file

The application needs to be set up as an SystemD service as specified. Therefore, a template `TechTestApp.service.j2` is provided for feeding in the environment variables. The service file will be located at `/etc/systemd/system/`.

```
- name: 8. Install TechTestApp.service systemd unit file
  template: 
    src: TechTestApp.service.j2
    dest: /etc/systemd/system/TechTestApp.service
    owner: root
    group: root
    mode: '0600'
  become: yes
```

#### 9. Start the application, if the service is rebooted

This step is for configuring the service file of the application to automatically start if the server is rebooted.

```
- name: 9. Start the application, if the service is rebooted
  become: yes
  systemd:
    name: TechTestApp.service
    enabled: yes      # start the service on boot
    state: started
    daemon_reload: yes
```

---

### Circle CI Deployment

***Note:*** *While working on this part, my account was not able to push any job to CircleCI. Therefore, I had created a different repository to work with. I have provided Screenshots folder for this issue*

---

The `./circleci/config.yml` is developed to run on every commit on every branch in the repository.

Because there are some similiarity in the jobs. A command named `setup-cd` has been declared at the beginning of the file with environment configuring steps. This will install *Terraform, Ansible and AWS CLI*:

```
setup-cd:
  steps:
    - run:
        name: Configure environment
        command: |
          # Install Terraform
          curl -o terraform.zip https://releases.hashicorp.com/terraform/0.12.24/terraform_0.12.24_linux_amd64.zip
          sudo unzip terraform.zip -d /usr/local/bin/

          # Install Ansible
          sudo apt-add-repository ppa:ansible/ansible
          sudo apt-get update
          sudo apt-get install ansible -y
          sudo apt-get install python -y

          # Install AWS CLI
          curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
          unzip awscliv2.zip
          sudo ./aws/install
```

---

#### Build job

* This job will start by running the `setup-cd` command. 

* Then it will package up Infrastructure as Code (IAC) and scripts into directory * called `artifacts`. 

* This directory will be kept within the workspace for the later job:

```
# Build job summary
- setup-cd

- run: 
    name: Package up Infrastructure as Code (IAC) and scripts
    command: |
      mkdir artifacts
      cp -r infra artifacts/infra
      cp -r ansible artifacts/ansible

- persist_to_workspace:
    root: ./
    paths:
      - artifacts 
```

---

#### Deploy test job

* This job will also start by running the `setup-cd` command. 

* With the `artifacts` directory packaged up from the previous job, we will use the `Makefile` to initialize the remote backend and deploy infrastructure on AWS.

* Then also from the `artifacts` directory, we will run the shell script to execute the Ansible playbook.

```
# Deploy test job summary
- setup-cd

- run:
  name: Deploy infrastructure
  command: |
    cd artifacts/infra
    make init
    make up

- run:
  name: Run shell script to generate environment variables and execute Ansible Playbook
  command: |
    cd artifacts/ansible
    ./run_ansible.sh
```

#### Deploy prod job

This job is similar to 'Deploy test job' but in a production environment.

---

## CLEAN UP INSTRUCTION

Simply change into `infra` directory and run this command:

```
make down
```

If there are some issues related to states lock when destroying resource, run this command to force destroying:

```
make down-loose
```