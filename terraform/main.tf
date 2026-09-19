module "network" {
  source = "./modules/network"

  region       = var.region
  project_name = var.project_name
}

module "compute" {
  source = "./modules/compute"

  region                = var.region
  project_name          = var.project_name
  vpc_id                = module.network.vpc_id
  web_subnet_id         = module.network.web_subnet_id
  web_sg_id             = module.network.web_sg_id
  db_sg_id              = module.network.db_sg_id
  db_subnet_ids         = module.network.db_subnet_ids
  public_subnet_ids     = module.network.public_subnet_ids
  admin_ssh_public_key  = var.admin_ssh_public_key
  db_admin_password     = var.db_admin_password
}

module "monitoring" {
  source = "./modules/monitoring"

  region                = var.region
  project_name          = var.project_name
  monitoring_subnet_id  = module.network.monitoring_subnet_id
  monitoring_sg_id      = module.network.monitoring_sg_id
  key_name              = module.compute.key_name
}
