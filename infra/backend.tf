# For remote backend setup with S3 and DynamoDB
resource "aws_s3_bucket" "terraform-state-storage-s3" {
  bucket        = "tech-test-app-remote-state-storage-bucket"
  acl           = "private"
  force_destroy = true

  versioning {
    enabled = true
  }

  tags = {
    Name = "TechTechApp Remote State Storage Bucket"
  }
}

terraform {
  backend "s3" {
    bucket          = "tech-test-app-remote-state-storage-bucket"
    encrypt         = true
    key             = "terraform.tfstate"
    region          = "us-east-1"
    dynamodb_tablle = "tech-test-app-terraform-state-lock-dynamo"
  }
}

resource "aws_dynamodb_table" "dynamodb-terraform-state-lock" {
  name           = "tech-test-app-terraform-state-lock-dynamo"
  hash_key       = "LockID"
  read_capacity  = 20
  write_capacity = 20

  attribute {
    name = "LockID"
    type = "S"
  }

  tags = {
    Name = "TechTechApp DynamoDB Terraform State Lock Table"
  }
}
