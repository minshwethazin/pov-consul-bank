resource "aws_lb" "customer" {
  name               = "${var.project_name}-alb"
  internal           = false
  load_balancer_type = "application"
  ip_address_type    = "ipv4"
  security_groups    = [aws_security_group.alb.id]
  subnets            = [for key in sort(keys(local.public_subnets)) : aws_subnet.public[key].id]
  depends_on         = [aws_route.internet, aws_route_table_association.public]
}

resource "aws_lb_target_group" "customer" {
  name             = "${var.project_name}-tg"
  port             = local.services.customer.port
  protocol         = "HTTP"
  protocol_version = "HTTP1"
  target_type      = "instance"
  vpc_id           = aws_vpc.service["customer"].id

  health_check {
    enabled             = true
    protocol            = "HTTP"
    port                = "traffic-port"
    path                = "/"
    matcher             = "200"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }
}

resource "aws_lb_target_group_attachment" "customer" {
  target_group_arn = aws_lb_target_group.customer.arn
  target_id        = aws_instance.service["customer"].id
  port             = local.services.customer.port
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.customer.arn
  port              = 80
  protocol          = "HTTP"

  dynamic "default_action" {
    for_each = var.enable_https ? [] : [1]
    content {
      type             = "forward"
      target_group_arn = aws_lb_target_group.customer.arn
    }
  }

  dynamic "default_action" {
    for_each = var.enable_https ? [1] : []
    content {
      type = "redirect"
      redirect {
        protocol    = "HTTPS"
        port        = "443"
        host        = var.domain_name
        path        = "/#{path}"
        query       = "#{query}"
        status_code = "HTTP_301"
      }
    }
  }

  # On upgrade, wait for a working HTTPS listener before changing HTTP to redirect.
  depends_on = [aws_lb_listener.https]
}
