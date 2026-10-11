# Mock tests require no AWS credentials and create no AWS resources.
mock_provider "aws" {
  override_during = plan

  mock_data "aws_availability_zones" {
    defaults = {
      names = ["ap-northeast-1a", "ap-northeast-1c"]
    }
  }

  mock_data "aws_partition" {
    defaults = {
      partition = "aws"
    }
  }

  mock_data "aws_ssm_parameter" {
    defaults = {
      value = "ami-0123456789abcdef0"
    }
  }

  mock_data "aws_route53_zone" {
    defaults = {
      name         = "example.com."
      private_zone = false
      zone_id      = "Z0123456789"
    }
  }

  mock_resource "aws_lb" {
    defaults = {
      arn      = "arn:aws:elasticloadbalancing:ap-northeast-1:123456789012:loadbalancer/app/test-alb/1234567890abcdef"
      dns_name = "test-alb.ap-northeast-1.elb.amazonaws.com"
      zone_id  = "Z14GRHDCWA56QT"
    }
  }

  mock_resource "aws_lb_target_group" {
    defaults = {
      arn = "arn:aws:elasticloadbalancing:ap-northeast-1:123456789012:targetgroup/test-tg/1234567890abcdef"
    }
  }
}

# Make bootstrap inputs known during both test plans.
override_resource {
  target          = aws_s3_bucket.binaries
  override_during = plan

  values = {
    id     = "retail-bank-test-binaries"
    bucket = "retail-bank-test-binaries"
    arn    = "arn:aws:s3:::retail-bank-test-binaries"
  }
}

override_resource {
  target          = aws_s3_object.binary
  override_during = plan

  values = {
    id     = "fake-service"
    bucket = "retail-bank-test-binaries"
    key    = "fake-service"
    arn    = "arn:aws:s3:::retail-bank-test-binaries/fake-service"
  }
}

# Test inputs override values from terraform.tfvars.
variables {
  allowed_client_cidrs = ["203.0.113.10/32"]
  enable_https         = false
  domain_name          = ""
  route53_zone_id      = ""
}

run "http_network_and_services" {
  command = plan

  assert {
    condition = (
      length(aws_vpc.service) == 3 &&
      length(aws_subnet.private) == 3 &&
      length(aws_subnet.public) == 2
    )
    error_message = "Expected three service VPCs, three private subnets and two Customer public subnets."
  }

  assert {
    condition = (
      length(aws_vpc_peering_connection.service) == 2 &&
      length(aws_route.peer) == 4
    )
    error_message = "Expected two peerings and four reciprocal peering routes."
  }

  assert {
    condition = (
      length(aws_vpc_endpoint.ssm) == 4 &&
      length(aws_vpc_endpoint.s3) == 2
    )
    error_message = "Each backend needs two SSM interface endpoints and one S3 gateway endpoint."
  }

  assert {
    condition = alltrue([
      for instance in aws_instance.service : (
        instance.associate_public_ip_address == false &&
        instance.metadata_options[0].http_tokens == "required" &&
        instance.root_block_device[0].encrypted == true
      )
    ])
    error_message = "Service instances must be private, require IMDSv2 and use encrypted root disks."
  }

  assert {
    condition = (
      length(aws_lb_listener.https) == 0 &&
      aws_lb_listener.http.default_action[0].type == "forward"
    )
    error_message = "HTTP mode must forward requests without an HTTPS listener."
  }

  assert {
    condition = (
      length(aws_vpc_security_group_ingress_rule.alb) == 1 &&
      alltrue([
        for rule in aws_vpc_security_group_ingress_rule.alb : (
          rule.cidr_ipv4 == "203.0.113.10/32" &&
          rule.from_port == 80 &&
          rule.to_port == 80
        )
      ])
    )
    error_message = "HTTP ingress must allow only port 80 from the approved client CIDR."
  }

  assert {
    condition = (
      strcontains(
        local.bootstrap_scripts["customer"],
        "UPSTREAM_URIS=http://10.20.1.141:9092"
      ) &&
      strcontains(
        local.bootstrap_scripts["account"],
        "UPSTREAM_URIS=http://10.30.1.130:9093"
      ) &&
      strcontains(
        local.bootstrap_scripts["statement"],
        "Restart=on-failure"
      )
    )
    error_message = "Bootstrap must wire Customer to Account to Statement and enable automatic restart."
  }
}

run "https_and_redirect" {
  command = plan

  variables {
    enable_https    = true
    domain_name     = "bank-tf.example.com"
    route53_zone_id = "Z0123456789"
  }

  override_data {
    target          = data.aws_route53_zone.existing[0]
    override_during = plan

    values = {
      id           = "Z0123456789"
      zone_id      = "Z0123456789"
      name         = "example.com."
      private_zone = false
    }
  }

  # Only the HTTPS test creates this certificate.
  override_resource {
    target          = aws_acm_certificate.site[0]
    override_during = plan

    values = {
      arn = "arn:aws:acm:ap-northeast-1:123456789012:certificate/12345678-1234-1234-1234-123456789012"

      domain_validation_options = [{
        domain_name           = "bank-tf.example.com"
        resource_record_name  = "_validation.bank-tf.example.com."
        resource_record_type  = "CNAME"
        resource_record_value = "_validation.acm-validations.aws."
      }]
    }
  }

  assert {
    condition = (
      length(aws_lb_listener.https) == 1 &&
      aws_lb_listener.https[0].port == 443 &&
      aws_lb_listener.https[0].protocol == "HTTPS"
    )
    error_message = "HTTPS mode must configure a TLS listener on port 443."
  }

  assert {
    condition = (
      aws_lb_listener.http.default_action[0].type == "redirect" &&
      aws_lb_listener.http.default_action[0].redirect[0].status_code == "HTTP_301" &&
      aws_lb_listener.http.default_action[0].redirect[0].host == "bank-tf.example.com"
    )
    error_message = "HTTP must redirect to the canonical HTTPS hostname."
  }

  assert {
    condition = (
      length(aws_route53_record.site) == 1 &&
      aws_route53_record.site[0].allow_overwrite == false
    )
    error_message = "Create one DNS alias without overwriting existing records."
  }

  assert {
    condition = (
      length(aws_vpc_security_group_ingress_rule.alb) == 2 &&
      alltrue([
        for rule in aws_vpc_security_group_ingress_rule.alb : (
          rule.cidr_ipv4 == "203.0.113.10/32" &&
          contains([80, 443], rule.from_port) &&
          rule.to_port == rule.from_port
        )
      ]) &&
      output.ui_url == "https://bank-tf.example.com/ui/"
    )
    error_message = "HTTPS mode must restrict ports 80/443 to approved clients and output the HTTPS UI URL."
  }
}