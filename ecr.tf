resource "aws_ecrpublic_repository" "example" {
  provider = aws.ecr_public

  repository_name = "my-public-repo"

  catalog_data {
    description       = "My public ECR repository"
    architectures     = ["x86-64"]
    operating_systems = ["Linux"]
  }
}