resource "tls_private_key" "eks" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "eks" {
  key_name   = "${var.project_name}-eks-key"
  public_key = tls_private_key.eks.public_key_openssh
}