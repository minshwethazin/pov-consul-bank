variable "aws_region" {
  description = "Region for the entire lab, including the ALB ACM certificate."
  type        = string
  default     = "ap-northeast-1"
}

variable "project_name" {
  description = "Unique name prefix for this new stack."
  type        = string
  default     = "retail-bank-tf"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,19}$", var.project_name))
    error_message = "Use 3-20 lowercase letters, numbers and hyphens, beginning with a letter."
  }
}

variable "allowed_client_cidrs" {
  description = "Public IPv4 CIDRs allowed to reach ALB ports 80 and 443. Usually your public IP/32."
  type        = set(string)

  validation {
    condition     = length(var.allowed_client_cidrs) > 0 && alltrue([for cidr in var.allowed_client_cidrs : can(cidrnetmask(cidr))])
    error_message = "Provide at least one valid IPv4 CIDR, for example 203.0.113.10/32."
  }
}

variable "instance_type" {
  description = "x86_64 instance type. The prepared executable is Linux AMD64."
  type        = string
  default     = "t3.micro"
}

variable "ami_id" {
  description = "Optional pinned Amazon Linux 2023 x86_64 AMI ID. Null uses the public SSM latest-AMI parameter."
  type        = string
  default     = null

  validation {
    condition     = var.ami_id == null ? true : can(regex("^ami-[0-9a-f]+$", var.ami_id))
    error_message = "ami_id must be null or an AMI ID."
  }
}

variable "availability_zones" {
  description = "Optional two AZ names in this Region. Null selects the first two available AZs."
  type        = list(string)
  default     = null

  validation {
    condition     = var.availability_zones == null ? true : length(var.availability_zones) == 2 && length(distinct(var.availability_zones)) == 2
    error_message = "Supply exactly two different Availability Zones, or null."
  }
}

variable "binary_path" {
  description = "Path to the extracted Linux AMD64 fake-service executable, relative to the working directory or absolute."
  type        = string
  default     = "assets/fake-service"

  validation {
    condition     = fileexists(var.binary_path)
    error_message = "Binary missing. Run bash scripts/prepare-binary.sh before terraform plan/apply/test."
  }
}

variable "enable_https" {
  description = "Create ACM certificate, validation CNAME, custom-domain alias, HTTPS listener and HTTP redirect."
  type        = bool
  default     = false
}

variable "domain_name" {
  description = "Unused fully qualified hostname for this lab, e.g. bank-tf.hellogeolab.site."
  type        = string
  default     = ""

  validation {
    condition     = !var.enable_https || can(regex("^([a-z0-9]([a-z0-9-]*[a-z0-9])?\\.)+[a-z]{2,}$", var.domain_name))
    error_message = "When enable_https=true, provide a lowercase fully qualified hostname without protocol, path or trailing dot."
  }
}

variable "route53_zone_id" {
  description = "Existing authoritative public Route 53 hosted zone ID, required for HTTPS."
  type        = string
  default     = ""

  validation {
    condition     = !var.enable_https || can(regex("^Z[A-Z0-9]+$", var.route53_zone_id))
    error_message = "When enable_https=true, set the existing public hosted zone ID (starts with Z)."
  }
}

variable "tags" {
  description = "Additional tags."
  type        = map(string)
  default     = {}
}
