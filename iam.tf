# IAM resources for External DNS on EKS
# This configures IRSA for external-dns to manage Route53 records.
# Assumptions: EKS OIDC provider is enabled (via eks.tf); cluster_name variable defined.
# Prerequisites: Hosted zones exist in Route53; external-dns deployed with service account 'external-dns' in 'external-dns' namespace.
# Annotate the service account in external-dns-values.yaml: serviceAccount.annotations."eks\.amazonaws\.com/role-arn": aws_iam_role.external_dns.arn
# Best practices: Least privilege; use OIDC for trust instead of access keys.

data "aws_iam_policy_document" "external_dns_assume_role_policy" {
  statement {
    effect = "Allow"

    principals {
      type        = "Federated"
      identifiers = [module.eks.oidc_provider_arn] # EKS OIDC provider ARN
    }

    actions = ["sts:AssumeRoleWithWebIdentity"]

    condition {
      test     = "StringEquals"
      variable = "${replace(module.eks.cluster_oidc_issuer_url, "https://", "")}:sub"
      values   = ["system:serviceaccount:external-dns:external-dns"] # Namespace:ServiceAccount
    }

    condition {
      test     = "StringEquals"
      variable = "${replace(module.eks.cluster_oidc_issuer_url, "https://", "")}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "external_dns" {
  name = "${var.project_name}-external-dns" # e.g., eks-llm-external-dns; use unique name

  assume_role_policy = data.aws_iam_policy_document.external_dns_assume_role_policy.json

  tags = {
    Name        = "${var.project_name}-external-dns"
    Environment = var.environment # e.g., "dev"; defined in variables.tf
    ManagedBy   = "Terraform"
  }
}

data "aws_iam_policy_document" "external_dns_policy" {
  statement {
    effect = "Allow"

    actions = [
      "route53:ChangeResourceRecordSets"
    ]

    resources = [
      "arn:aws:route53:::hostedzone/*" # All hosted zones; restrict to specific zones for least privilege if known
    ]
  }

  statement {
    effect = "Allow"

    actions = [
      "route53:DescribeHostedZones",
      "route53:ListHostedZones",
      "route53:ListResourceRecordSets"
    ]

    resources = ["*"]
  }

  # Optional: If using private hosted zones or other features
  # statement {
  #   effect = "Allow"
  #   actions = ["route53:ListTagsForResource"]
  #   resources = ["arn:aws:route53:::hostedzone/*"]
  # }
}

resource "aws_iam_policy" "external_dns" {
  name        = "${var.project_name}-external-dns-policy"
  description = "Policy for external-dns to manage Route53 records in ${var.project_name}-eks EKS cluster"
  policy      = data.aws_iam_policy_document.external_dns_policy.json

  tags = {
    Name        = "${var.project_name}-external-dns-policy"
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

resource "aws_iam_role_policy_attachment" "external_dns" {
  role       = aws_iam_role.external_dns.name
  policy_arn = aws_iam_policy.external_dns.arn
}

# Outputs for reference (add to outputs.tf if needed)
