output "instance_id" {
  description = "ID de la instancia EC2"
  value       = aws_instance.main.id
}

output "public_ip" {
  description = "IP pública de la instancia"
  value       = aws_instance.main.public_ip
}