variable "project_name" {
  description = "Prefijo para el nombre de los recursos"
  type        = string
}

variable "instance_type" {
  description = "Tipo de instancia EC2"
  type        = string
  default     = "t3.small"
}

variable "subnet_id" {
  description = "ID de la subred donde se lanza la instancia"
  type        = string
}

variable "security_group_id" {
  description = "ID del security group de la instancia"
  type        = string
}

variable "public_key" {
  description = "Clave pública SSH"
  type        = string
}