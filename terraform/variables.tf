variable "aws_region" {
  description = "Región de AWS donde se crea la infraestructura"
  type        = string
  default     = "us-east-1"
}

variable "aws_profile" {
  description = "Perfil de AWS CLI con las credenciales a usar"
  type        = string
  default     = "terraform-pf"
}

variable "project_name" {
  description = "Prefijo usado en el nombre y las etiquetas de los recursos"
  type        = string
  default     = "devops-pf"
}

variable "allowed_cidr" {
  description = "IP autorizada para SSH y la API de Kubernetes, en formato CIDR (ej: 203.0.113.10/32)"
  type        = string
}