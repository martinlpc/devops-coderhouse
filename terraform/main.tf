provider "aws" {
  region  = var.aws_region
  profile = var.aws_profile

  default_tags {
    tags = {
      Project   = var.project_name
      ManagedBy = "terraform"
    }
  }
}

module "network" {
  source       = "./modules/network"
  project_name = var.project_name
  allowed_cidr = var.allowed_cidr
}

module "compute" {
  source            = "./modules/compute"
  project_name      = var.project_name
  subnet_id         = module.network.public_subnet_id
  security_group_id = module.network.security_group_id
  public_key        = file(pathexpand(var.ssh_public_key_path))
}