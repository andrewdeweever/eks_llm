locals {
  argo_domain_parts = split(".", var.argo_domain_name)
  argo_record_name  = join(".", slice(local.argo_domain_parts, 0, 2)) # First two: "argo.deweever"

  # Optional: Rest for zone name (e.g., "bsisandbox.com")
  argo_zone_name = join(".", slice(local.argo_domain_parts, 2, length(local.argo_domain_parts)))
}
