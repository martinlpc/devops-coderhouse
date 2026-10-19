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