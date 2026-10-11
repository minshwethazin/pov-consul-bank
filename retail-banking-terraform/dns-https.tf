# This stack reuses a zone. It never creates/deletes the shared hosted zone.
data "aws_route53_zone" "existing" {
  count        = var.enable_https ? 1 : 0
  zone_id      = var.route53_zone_id
  private_zone = false
}

resource "aws_acm_certificate" "site" {
  count             = var.enable_https ? 1 : 0
  domain_name       = var.domain_name
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
    precondition {
      condition = (
        !data.aws_route53_zone.existing[0].private_zone &&
        (var.domain_name == trimsuffix(data.aws_route53_zone.existing[0].name, ".") ||
        endswith(var.domain_name, ".${trimsuffix(data.aws_route53_zone.existing[0].name, ".")}"))
      )
      error_message = "The hostname must belong to the selected public hosted zone."
    }
  }
}

resource "aws_route53_record" "validation" {
  for_each = var.enable_https ? {
    for item in aws_acm_certificate.site[0].domain_validation_options :
    item.domain_name => {
      name   = item.resource_record_name
      type   = item.resource_record_type
      record = item.resource_record_value
    }
  } : {}

  zone_id = var.route53_zone_id
  name    = each.value.name
  type    = each.value.type
  ttl     = 60
  records = [each.value.record]
  # Do not overwrite a validation record managed outside this state.
  allow_overwrite = false
}

resource "aws_acm_certificate_validation" "site" {
  count                   = var.enable_https ? 1 : 0
  certificate_arn         = aws_acm_certificate.site[0].arn
  validation_record_fqdns = [for record in aws_route53_record.validation : record.fqdn]
  timeouts {
    create = "45m"
  }
}

resource "aws_lb_listener" "https" {
  count = var.enable_https ? 1 : 0

  load_balancer_arn = aws_lb.customer.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = aws_acm_certificate_validation.site[0].certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.customer.arn
  }
}

resource "aws_route53_record" "site" {
  count           = var.enable_https ? 1 : 0
  zone_id         = var.route53_zone_id
  name            = var.domain_name
  type            = "A"
  allow_overwrite = false

  alias {
    name                   = aws_lb.customer.dns_name
    zone_id                = aws_lb.customer.zone_id
    evaluate_target_health = true
  }
}
