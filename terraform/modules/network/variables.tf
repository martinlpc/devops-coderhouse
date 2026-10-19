variable "project_name" {
  description = "Prefijo para el nombre de los recursos"
  type        = string
}

variable "vpc_cidr" {
  description = "Rango de IPs de la VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidr" {
  description = "Rango de IPs de la subred pública"
  type        = string
  default     = "10.0.1.0/24"
}

variable "allowed_cidr" {
  description = "IP o rango autorizado para SSH y la API de Kubernetes"
  type        = string
}