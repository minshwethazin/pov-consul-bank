# Standalone rules avoid dependency cycles between referenced security groups.
resource "aws_security_group" "alb" {
  name_prefix = "${var.project_name}-alb-"
  description = "Client access to the Customer ALB"
  vpc_id      = aws_vpc.service["customer"].id
  tags        = { Name = "${var.project_name}-alb-sg" }
}

resource "aws_security_group" "ec2" {
  for_each = local.services

  name_prefix = "${var.project_name}-${each.key}-"
  description = "Private ${each.value.service_name} instance"
  vpc_id      = aws_vpc.service[each.key].id
  tags        = { Name = "${var.project_name}-${each.key}-ec2-sg" }
}

resource "aws_security_group" "endpoint" {
  for_each = local.backend_services

  name_prefix = "${var.project_name}-${each.key}-endpoint-"
  description = "SSM interface endpoint access from local EC2"
  vpc_id      = aws_vpc.service[each.key].id
  tags        = { Name = "${var.project_name}-${each.key}-endpoint-sg" }
}

resource "aws_vpc_security_group_ingress_rule" "alb" {
  for_each = local.alb_ingress

  security_group_id = aws_security_group.alb.id
  description       = "Approved client on port ${each.value.port}"
  cidr_ipv4         = each.value.cidr
  ip_protocol       = "tcp"
  from_port         = each.value.port
  to_port           = each.value.port
}

resource "aws_vpc_security_group_egress_rule" "alb_to_customer" {
  security_group_id            = aws_security_group.alb.id
  referenced_security_group_id = aws_security_group.ec2["customer"].id
  ip_protocol                  = "tcp"
  from_port                    = local.services.customer.port
  to_port                      = local.services.customer.port
}

resource "aws_vpc_security_group_ingress_rule" "customer" {
  security_group_id            = aws_security_group.ec2["customer"].id
  referenced_security_group_id = aws_security_group.alb.id
  ip_protocol                  = "tcp"
  from_port                    = local.services.customer.port
  to_port                      = local.services.customer.port
}

resource "aws_vpc_security_group_ingress_rule" "account" {
  security_group_id            = aws_security_group.ec2["account"].id
  referenced_security_group_id = aws_security_group.ec2["customer"].id
  ip_protocol                  = "tcp"
  from_port                    = local.services.account.port
  to_port                      = local.services.account.port
  depends_on                   = [aws_vpc_peering_connection.service["customer_account"]]
}

resource "aws_vpc_security_group_ingress_rule" "statement" {
  security_group_id            = aws_security_group.ec2["statement"].id
  referenced_security_group_id = aws_security_group.ec2["account"].id
  ip_protocol                  = "tcp"
  from_port                    = local.services.statement.port
  to_port                      = local.services.statement.port
  depends_on                   = [aws_vpc_peering_connection.service["account_statement"]]
}

# Lab EC2 outbound access: peer services, AWS endpoints and Customer NAT.
resource "aws_vpc_security_group_egress_rule" "ec2" {
  for_each = local.services

  security_group_id = aws_security_group.ec2[each.key].id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

resource "aws_vpc_security_group_ingress_rule" "endpoint" {
  for_each = local.backend_services

  security_group_id            = aws_security_group.endpoint[each.key].id
  referenced_security_group_id = aws_security_group.ec2[each.key].id
  ip_protocol                  = "tcp"
  from_port                    = 443
  to_port                      = 443
}
