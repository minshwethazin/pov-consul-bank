resource "aws_s3_bucket" "binaries" {
  bucket_prefix = "${var.project_name}-bin-"
  force_destroy = false
  tags          = { Name = "${var.project_name}-binaries" }
}

resource "aws_s3_bucket_public_access_block" "binaries" {
  bucket                  = aws_s3_bucket.binaries.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "binaries" {
  bucket = aws_s3_bucket.binaries.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_policy" "tls_only" {
  bucket = aws_s3_bucket.binaries.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "DenyInsecureTransport"
      Effect    = "Deny"
      Principal = "*"
      Action    = "s3:*"
      Resource  = [aws_s3_bucket.binaries.arn, "${aws_s3_bucket.binaries.arn}/*"]
      Condition = { Bool = { "aws:SecureTransport" = "false" } }
    }]
  })
}

resource "aws_s3_object" "binary" {
  bucket                 = aws_s3_bucket.binaries.id
  key                    = "fake-service"
  source                 = abspath(var.binary_path)
  source_hash            = local.binary_sha256
  server_side_encryption = "AES256"
  content_type           = "application/octet-stream"
  depends_on = [
    aws_s3_bucket_public_access_block.binaries,
    aws_s3_bucket_server_side_encryption_configuration.binaries,
    aws_s3_bucket_policy.tls_only
  ]
}

resource "aws_iam_role" "ec2" {
  name_prefix = "${var.project_name}-ec2-"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.ec2.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy" "binary" {
  name = "ReadFakeServiceBinary"
  role = aws_iam_role.ec2.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["s3:GetObject"]
      Resource = [aws_s3_object.binary.arn]
    }]
  })
}

resource "aws_iam_instance_profile" "ec2" {
  name_prefix = "${var.project_name}-ec2-"
  role        = aws_iam_role.ec2.name
}
