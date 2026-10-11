output "aws_region" {
  value = var.aws_region
}

output "alb_dns_name" {
  value = aws_lb.customer.dns_name
}

output "application_url" {
  value = var.enable_https ? "https://${var.domain_name}" : "http://${aws_lb.customer.dns_name}"
}

output "ui_url" {
  value = var.enable_https ? "https://${var.domain_name}/ui/" : "http://${aws_lb.customer.dns_name}/ui/"
}

output "instance_ids" {
  value = { for name, instance in aws_instance.service : name => instance.id }
}

output "private_ips" {
  value = { for name, instance in aws_instance.service : name => instance.private_ip }
}

output "vpc_ids" {
  value = { for name, vpc in aws_vpc.service : name => vpc.id }
}

output "peering_ids" {
  value = { for name, peer in aws_vpc_peering_connection.service : name => peer.id }
}

output "binary_bucket" {
  value = aws_s3_bucket.binaries.id
}

output "target_group_arn" {
  value = aws_lb_target_group.customer.arn
}

output "session_manager_commands" {
  value = {
    for name, instance in aws_instance.service :
    name => "aws ssm start-session --target ${instance.id} --region ${var.aws_region}"
  }
}

output "selected_ami_id" {
  value = local.ami_id
}

output "selected_availability_zones" {
  value = local.azs
}
