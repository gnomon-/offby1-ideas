provider "aws" {
  profile = "me"
  region  = "us-west-2"
}

provider "aws" {
  alias  = "useast1"
  region = "us-east-1"
}

data "aws_caller_identity" "current" {}

module "log_storage" {
  bucket        = "logs.ideas.offby1.net"
  s3_logs_path  = "s3-log-"
  cdn_logs_path = "cf-log-"
  readers       = [data.aws_caller_identity.current.account_id]
  source        = "github.com/jetbrains-infra/terraform-aws-s3-bucket-for-logs?ref=v0.4.1"
  tags          = local.tags
}

variable "website_domain" {
  type    = string
  default = "offby1.website"
}

variable "dotnet_subdomain" {
  type    = string
  default = "ideas.offby1.net"
}

variable "s3_origin_id" {
  default = "S3-ideas.offby1.net"
}

data "aws_route53_zone" "zone" {
  name = "offby1.net"
}

data "aws_route53_zone" "website" {
  name = "offby1.website"
}

locals {
  zone_id_map = {
    "ideas.offby1.net" = data.aws_route53_zone.zone.zone_id
    "offby1.website"   = data.aws_route53_zone.website.zone_id
  }
  domain_names = [
    var.dotnet_subdomain,
    var.website_domain,
  ]
  domain_name = var.website_domain
  bucket_name = var.dotnet_subdomain

  tags = {
    Project = "ideas.blog"
    Domain  = "offby1.net"
    Source  = "https://github.com/offbyone/ideas"
  }
}

resource "aws_s3_bucket" "blog" {
  depends_on = [module.log_storage.s3_logs_bucket]
  bucket     = local.bucket_name
  acl        = "public-read"
  policy     = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [{
    "Sid": "AddPerm",
    "Effect": "Allow",
    "Principal": "*",
    "Action": "s3:GetObject",
    "Resource": "arn:aws:s3:::${local.bucket_name}/*"
  }]
}
EOF

  cors_rule {
    allowed_headers = ["*"]
    allowed_methods = ["GET", "HEAD", ]
    allowed_origins = formatlist("https://%s", local.domain_names)
    expose_headers  = ["ETag"]
    max_age_seconds = 0
  }

  website {
    index_document = "index.html"
    error_document = "error.html"
  }

  logging {
    target_bucket = module.log_storage.s3_logs_bucket
    target_prefix = module.log_storage.s3_logs_path
  }

  tags = local.tags

}

resource "aws_s3_bucket" "wwwblog" {
  bucket = "www.${local.bucket_name}"
  acl    = "public-read"
  website {
    redirect_all_requests_to = local.bucket_name
  }
  tags = local.tags
}

resource "aws_cloudfront_distribution" "frontend" {
  depends_on = [aws_s3_bucket.blog]

  origin {
    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "http-only"
      origin_ssl_protocols   = ["TLSv1", "TLSv1.1", "TLSv1.2"]
    }

    // Important to use this format of origin domain name, it is the only format that
    // supports S3 redirects with CloudFront
    domain_name = aws_s3_bucket.blog.bucket_domain_name
    // domain_name = "${var.bucket_name}.s3-website-${var.aws_region}.amazonaws.com"

    origin_id = var.s3_origin_id
    # origin_path = var.origin_path
  }

  enabled             = true
  http_version        = "http1.1"
  is_ipv6_enabled     = false
  default_root_object = "index.html"

  aliases = local.domain_names

  logging_config {
    bucket          = module.log_storage.cdn_logs_bucket
    include_cookies = false
    prefix          = module.log_storage.cdn_logs_path
  }

  default_cache_behavior {
    allowed_methods          = ["GET", "HEAD"]
    cached_methods           = ["GET", "HEAD"]
    target_origin_id         = var.s3_origin_id
    cache_policy_id          = data.aws_cloudfront_cache_policy.none.id
    origin_request_policy_id = data.aws_cloudfront_origin_request_policy.cors-s3.id

    viewer_protocol_policy = "redirect-to-https"

    // Using CloudFront defaults, tune to liking
    min_ttl     = 0
    default_ttl = 0
    max_ttl     = 0
  }

  price_class = "PriceClass_100"

  viewer_certificate {
    acm_certificate_arn      = aws_acm_certificate.certificate.arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.1_2016"
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  tags = local.tags
}

data "aws_cloudfront_cache_policy" "none" {
  name = "Managed-CachingDisabled"
}

data "aws_cloudfront_origin_request_policy" "cors-s3" {
  name = "Managed-CORS-S3Origin"
}

resource "aws_acm_certificate" "certificate" {
  provider    = aws.useast1
  domain_name = local.domain_names[0]
  tags = merge(local.tags, {
    Name = "ideas-offby1-net"
  })

  validation_method = "DNS"

  subject_alternative_names = slice(local.domain_names, 1, length(local.domain_names))

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_route53_record" "cert_validation" {
  for_each = {
    for dvo in aws_acm_certificate.certificate.domain_validation_options : dvo.domain_name => {
      name    = dvo.resource_record_name
      record  = dvo.resource_record_value
      type    = dvo.resource_record_type
      zone_id = local.zone_id_map[dvo.domain_name]
    }
  }

  allow_overwrite = true
  name            = each.value.name
  type            = each.value.type
  zone_id         = each.value.zone_id
  records         = [each.value.record]
  ttl             = 60

}

resource "aws_acm_certificate_validation" "certificate" {
  provider                = aws.useast1
  certificate_arn         = aws_acm_certificate.certificate.arn
  validation_record_fqdns = [for record in aws_route53_record.cert_validation : record.fqdn]
}

resource "aws_route53_record" "blog" {
  zone_id = data.aws_route53_zone.website.zone_id
  name    = local.domain_name
  type    = "A"
  alias {
    name                   = aws_cloudfront_distribution.frontend.domain_name
    zone_id                = aws_cloudfront_distribution.frontend.hosted_zone_id
    evaluate_target_health = true
  }
}

resource "aws_iam_user" "blog_deploy" {
  name = "${local.bucket_name}_blog_deploy"
  path = "/s3/"
  tags = local.tags

}

resource "aws_iam_access_key" "blog_deploy" {
  user = aws_iam_user.blog_deploy.name
}

resource "aws_iam_user_policy" "blog_deploy_rw" {
  name   = "${local.bucket_name}_rw"
  user   = aws_iam_user.blog_deploy.name
  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Action": [
      "s3:ListBucketMultipartUploads",
      "s3:ListBucket",
      "s3:GetBucketLocation",
      "cloudfront:CreateInvalidation"
    ],
    "Resource": [
      "arn:aws:s3:::${local.bucket_name}",
      "${aws_cloudfront_distribution.frontend.arn}"
    ],
    "Condition": {}
  }, {
    "Effect": "Allow",
    "Action": [
      "s3:AbortMultipartUpload",
      "s3:DeleteObject",
      "s3:DeleteObjectVersion",
      "s3:GetObject",
      "s3:GetObjectAcl",
      "s3:GetObjectVersion",
      "s3:GetObjectVersionAcl",
      "s3:PutObject",
      "s3:PutObjectAcl",
      "s3:PutObjectAclVersion"
    ],
    "Resource": "arn:aws:s3:::${local.bucket_name}/*",
    "Condition": {}
  }, {
    "Effect": "Allow",
    "Action": "s3:ListAllMyBuckets",
    "Resource": "*",
    "Condition": {}
  }
]
}
EOF
}

