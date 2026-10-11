locals {
  bootstrap_scripts = {
    for name, service in local.services : name => templatefile("${path.module}/templates/user-data.sh.tftpl", {
      region        = var.aws_region
      binary_bucket = aws_s3_bucket.binaries.id
      binary_key    = aws_s3_object.binary.key
      binary_sha256 = local.binary_sha256
      service_name  = service.service_name
      listen_port   = service.port
      upstream_uri  = service.upstream_uri
    })
  }
}

resource "aws_instance" "service" {
  for_each = local.services

  ami                         = local.ami_id
  instance_type               = var.instance_type
  subnet_id                   = aws_subnet.private[each.key].id
  private_ip                  = each.value.private_ip
  associate_public_ip_address = false
  vpc_security_group_ids      = [aws_security_group.ec2[each.key].id]
  iam_instance_profile        = aws_iam_instance_profile.ec2.name
  user_data_replace_on_change = true

  user_data = local.bootstrap_scripts[each.key]

  root_block_device {
    volume_size           = 8
    volume_type           = "gp3"
    encrypted             = true
    delete_on_termination = true
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  tags = { Name = "${var.project_name}-${each.key}-ec2" }

  # Finish network/IAM/object setup before launching. Runtime fetch also retries
  # for IAM propagation and endpoint/DNS readiness.
  depends_on = [
    aws_iam_role_policy_attachment.ssm,
    aws_iam_role_policy.binary,
    aws_route.internet,
    aws_route.customer_nat,
    aws_route.peer,
    aws_route_table_association.private,
    aws_route_table_association.public,
    aws_vpc_endpoint.ssm,
    aws_vpc_endpoint.s3,
    aws_vpc_security_group_ingress_rule.customer,
    aws_vpc_security_group_ingress_rule.account,
    aws_vpc_security_group_ingress_rule.statement,
    aws_vpc_security_group_ingress_rule.endpoint,
    aws_vpc_security_group_egress_rule.ec2,
    aws_s3_object.binary
  ]
}
