output "instance_public_ip" {
  value = aws_instance.web[0].public_ip
}

output "lb_endpoint" {
  value = aws_lb.A2_TechTestApp.dns_name
}

output "db_endpoint" {
  value = aws_db_instance.A2_TechTestApp.address
}

output "db_user" {
  value = aws_db_instance.A2_TechTestApp.username
}

output "db_pass" {
  value = aws_db_instance.A2_TechTestApp.password
}

output "state_bucket_name" {
  value = aws_s3_bucket.terraform-state-storage-s3.bucket
}

output "dynamoDb_lock_table_name" {
  value = aws_dynamodb_table.dynamodb-terraform-state-lock.name
}
