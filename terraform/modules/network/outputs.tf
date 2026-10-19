output "vpc_id" {
  description = "ID de la VPC"
  value       = aws_vpc.main.id
}

output "public_subnet_id" {
  description = "ID de la subred pública"
  value       = aws_subnet.public.id
}

output "security_group_id" {
  description = "ID del security group de la instancia"
  value       = aws_security_group.main.id
}