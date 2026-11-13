output "vpc_id" {
  value = aws_vpc.main.id
}

output "app_instance_ids" {
  value = aws_instance.app[*].id
}

output "app_public_ips" {
  value = aws_instance.app[*].public_ip
}

output "app_private_ips" {
  value = aws_instance.app[*].private_ip
}

output "db_instance_id" {
  value = aws_instance.db.id
}

output "db_public_ip" {
  value = aws_instance.db.public_ip
}

output "db_private_ip" {
  value = aws_instance.db.private_ip
}
