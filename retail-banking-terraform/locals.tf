data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_partition" "current" {}

data "aws_ssm_parameter" "al2023" {
  count = var.ami_id == null ? 1 : 0
  name  = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

locals {
  azs    = var.availability_zones == null ? slice(data.aws_availability_zones.available.names, 0, 2) : var.availability_zones
  ami_id = var.ami_id == null ? nonsensitive(data.aws_ssm_parameter.al2023[0].value) : var.ami_id

  services = {
    customer = {
      vpc_cidr     = "10.10.0.0/16"
      subnet_cidr  = "10.10.3.0/24"
      private_ip   = "10.10.3.170"
      port         = 9091
      service_name = "customer-profile-svc"
      upstream_uri = "http://10.20.1.141:9092"
    }
    account = {
      vpc_cidr     = "10.20.0.0/16"
      subnet_cidr  = "10.20.1.0/24"
      private_ip   = "10.20.1.141"
      port         = 9092
      service_name = "account-svc"
      upstream_uri = "http://10.30.1.130:9093"
    }
    statement = {
      vpc_cidr     = "10.30.0.0/16"
      subnet_cidr  = "10.30.1.0/24"
      private_ip   = "10.30.1.130"
      port         = 9093
      service_name = "statement-svc"
      upstream_uri = ""
    }
  }

  backend_services = { for name, svc in local.services : name => svc if name != "customer" }
  public_subnets = {
    a = { cidr = "10.10.1.0/24", az_index = 0 }
    b = { cidr = "10.10.2.0/24", az_index = 1 }
  }
  peering_pairs = {
    customer_account  = { requester = "customer", accepter = "account" }
    account_statement = { requester = "account", accepter = "statement" }
  }
  peer_routes = {
    customer_to_account  = { owner = "customer", destination = "account", peer = "customer_account" }
    account_to_customer  = { owner = "account", destination = "customer", peer = "customer_account" }
    account_to_statement = { owner = "account", destination = "statement", peer = "account_statement" }
    statement_to_account = { owner = "statement", destination = "account", peer = "account_statement" }
  }
  interface_endpoints = {
    for item in setproduct(keys(local.backend_services), ["ssm", "ssmmessages"]) :
    "${item[0]}_${item[1]}" => { service = item[0], endpoint = item[1] }
  }
  alb_ingress = {
    for item in setproduct(var.allowed_client_cidrs, var.enable_https ? [80, 443] : [80]) :
    "${item[0]}:${item[1]}" => { cidr = item[0], port = item[1] }
  }

  binary_sha256 = fileexists(var.binary_path) ? filesha256(var.binary_path) : ""
}
