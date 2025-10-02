data "aws_caller_identity" "current" {}

data "aws_availability_zones" "available" {}

data "aws_ami" "ubuntu_latest" {
  most_recent = true
  owners      = ["099720109477"]

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }

}

data "aws_route53_zone" "zone" {
  name         = "bsisandbox.com"
  private_zone = false
}

# data "aws_lb" "argocd" {
#   name = var.argocd_lb_name

#   depends_on = [helm_release.argocd]
# }
