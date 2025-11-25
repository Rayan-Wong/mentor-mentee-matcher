resource "cloudflare_dns_record" "cname" {
  count   = var.is_localstack ? 0 : 1
  zone_id = var.dns_zone_id
  name    = var.root_cname
  ttl     = 1
  type    = "CNAME"
  content = var.aws_alb_dns
  proxied = true
}

resource "cloudflare_dns_record" "www" {
  count   = var.is_localstack ? 0 : 1
  zone_id = var.dns_zone_id
  name    = "www.${var.root_cname}"
  ttl     = 1
  type    = "CNAME"
  content = var.aws_alb_dns
  proxied = true
}
