resource "aws_vpc" "service" {
  for_each = local.services

  cidr_block           = each.value.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags                 = { Name = "${var.project_name}-${each.key}-vpc" }
}

resource "aws_subnet" "private" {
  for_each = local.services

  vpc_id                  = aws_vpc.service[each.key].id
  cidr_block              = each.value.subnet_cidr
  availability_zone       = local.azs[0]
  map_public_ip_on_launch = false
  tags                    = { Name = "${var.project_name}-${each.key}-private" }
}

resource "aws_subnet" "public" {
  for_each = local.public_subnets

  vpc_id                  = aws_vpc.service["customer"].id
  cidr_block              = each.value.cidr
  availability_zone       = local.azs[each.value.az_index]
  map_public_ip_on_launch = false
  tags                    = { Name = "${var.project_name}-customer-public-${each.key}" }
}

resource "aws_internet_gateway" "customer" {
  vpc_id = aws_vpc.service["customer"].id
  tags   = { Name = "${var.project_name}-igw" }
}

resource "aws_eip" "nat" {
  domain = "vpc"
  tags   = { Name = "${var.project_name}-nat-eip" }
}

resource "aws_nat_gateway" "customer" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public["a"].id
  tags          = { Name = "${var.project_name}-nat" }
  depends_on    = [aws_internet_gateway.customer]
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.service["customer"].id
  tags   = { Name = "${var.project_name}-customer-public-rt" }
}

resource "aws_route" "internet" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.customer.id
}

resource "aws_route_table_association" "public" {
  for_each       = local.public_subnets
  subnet_id      = aws_subnet.public[each.key].id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table" "private" {
  for_each = local.services
  vpc_id   = aws_vpc.service[each.key].id
  tags     = { Name = "${var.project_name}-${each.key}-private-rt" }
}

resource "aws_route_table_association" "private" {
  for_each       = local.services
  subnet_id      = aws_subnet.private[each.key].id
  route_table_id = aws_route_table.private[each.key].id
}

resource "aws_route" "customer_nat" {
  route_table_id         = aws_route_table.private["customer"].id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.customer.id
}

resource "aws_vpc_peering_connection" "service" {
  for_each = local.peering_pairs

  vpc_id      = aws_vpc.service[each.value.requester].id
  peer_vpc_id = aws_vpc.service[each.value.accepter].id
  auto_accept = true
  tags        = { Name = "${var.project_name}-${each.key}-peering" }
}

resource "aws_route" "peer" {
  for_each = local.peer_routes

  route_table_id            = aws_route_table.private[each.value.owner].id
  destination_cidr_block    = local.services[each.value.destination].vpc_cidr
  vpc_peering_connection_id = aws_vpc_peering_connection.service[each.value.peer].id
}
