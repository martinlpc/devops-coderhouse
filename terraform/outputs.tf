output "public_ip" {
  description = "IP pública de la instancia"
  value       = module.compute.public_ip
}

output "ssh_command" {
  description = "Comando para entrar por SSH"
  value       = "ssh -i ~/.ssh/devops-pf ubuntu@${module.compute.public_ip}"
}