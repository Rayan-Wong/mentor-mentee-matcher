resource "cloudflare_dns_record" "cname" {
  count   = var.is_localstack ? 0 : 1
  zone_id = "1853f51ba6d3f5081e6477329ccd706c"
  name    = "mentor-mentee-matcher"
  ttl     = 1
  type    = "CNAME"
  content = var.aws_alb_dns
  proxied = true
}

resource "cloudflare_dns_record" "www" {
  count   = var.is_localstack ? 0 : 1
  zone_id = "1853f51ba6d3f5081e6477329ccd706c"
  name    = "www.mentor-mentee-matcher"
  ttl     = 1
  type    = "CNAME"
  content = var.aws_alb_dns
  proxied = true
}
