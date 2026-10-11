resource "aws_vpc_endpoint" "ssm" {
  for_each = local.interface_endpoints

  vpc_id              = aws_vpc.service[each.value.service].id
  service_name        = "com.amazonaws.${var.aws_region}.${each.value.endpoint}"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true
  subnet_ids          = [aws_subnet.private[each.value.service].id]
  security_group_ids  = [aws_security_group.endpoint[each.value.service].id]
  tags                = { Name = "${var.project_name}-${each.key}-endpoint" }
}

resource "aws_vpc_endpoint" "s3" {
  for_each = local.backend_services

  vpc_id            = aws_vpc.service[each.key].id
  service_name      = "com.amazonaws.${var.aws_region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [aws_route_table.private[each.key].id]
  tags              = { Name = "${var.project_name}-${each.key}-s3" }

  # Endpoints permit only this role to retrieve this demo executable.
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = "*"
      Action    = ["s3:GetObject"]
      Resource  = [aws_s3_object.binary.arn]
      Condition = {
        ArnEquals = { "aws:PrincipalArn" = aws_iam_role.ec2.arn }
      }
    }]
  })
}
