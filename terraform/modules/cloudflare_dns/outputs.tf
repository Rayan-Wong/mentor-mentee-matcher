output "cloudflare_name" {
  value = try(cloudflare_dns_record.cname[0].name, null)
}
