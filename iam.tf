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

# IAM resources for Cert-Manager on EKS
# This configures IRSA for cert-manager to manage Route53 records for DNS-01 validation.
# Assumptions: EKS OIDC provider is enabled (via eks.tf); cluster_name variable defined.
# Prerequisites: Cert-manager deployed with service account 'cert-manager' in 'cert-manager' namespace.
# Annotate the service account in cert-manager-values.yaml: serviceAccount.annotations."eks\.amazonaws\.com/role-arn": aws_iam_role.cert_manager.arn
# Best practices: Least privilege; use OIDC for trust instead of access keys.

data "aws_iam_policy_document" "cert_manager_assume_role_policy" {
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
      values   = ["system:serviceaccount:cert-manager:cert-manager"] # Namespace:ServiceAccount
    }

    condition {
      test     = "StringEquals"
      variable = "${replace(module.eks.cluster_oidc_issuer_url, "https://", "")}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "cert_manager" {
  name = "${var.project_name}-cert-manager" # e.g., eks-llm-cert-manager; use unique name

  assume_role_policy = data.aws_iam_policy_document.cert_manager_assume_role_policy.json
}

data "aws_iam_policy_document" "cert_manager_policy" {
  statement {
    effect    = "Allow"
    actions   = ["route53:GetChange"]
    resources = ["arn:aws:route53:::change/*"]
  }

  statement {
    effect = "Allow"
    actions = [
      "route53:ChangeResourceRecordSets",
      "route53:ListResourceRecordSets"
    ]
    resources = ["arn:aws:route53:::hostedzone/*"]
    condition {
      test     = "ForAllValues:StringEquals"
      variable = "route53:ChangeResourceRecordSetsRecordTypes"
      values   = ["TXT"]
    }
  }

  statement {
    effect    = "Allow"
    actions   = ["route53:ListHostedZonesByName"]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "cert_manager" {
  name        = "${var.project_name}-cert-manager-policy"
  description = "Policy for cert-manager to manage Route53 records for DNS-01 validation in ${var.project_name}-eks EKS cluster"
  policy      = data.aws_iam_policy_document.cert_manager_policy.json

  tags = {
    Name        = "${var.project_name}-cert-manager-policy"
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

resource "aws_iam_role_policy_attachment" "cert_manager" {
  role       = aws_iam_role.cert_manager.name
  policy_arn = aws_iam_policy.cert_manager.arn
}

# IAM Role for AWS Load Balancer Controller
resource "aws_iam_role" "aws-load-balancer-controller-role" {
  name = "${var.project_name}-aws-load-balancer-controller"

  assume_role_policy = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "",
      "Effect": "Allow",
      "Principal": {
        "Federated": "${module.eks.oidc_provider_arn}"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "${replace(module.eks.cluster_oidc_issuer_url, "https://", "")}:sub": "system:serviceaccount:kube-system:aws-load-balancer-controller",
          "${replace(module.eks.cluster_oidc_issuer_url, "https://", "")}:aud": "sts.amazonaws.com"
        }
      }
    }
  ]
}
POLICY

  depends_on = [module.eks]

  tags = {
    "ServiceAccountName"      = "aws-load-balancer-controller"
    "ServiceAccountNameSpace" = "kube-system"
  }
}

resource "aws_iam_policy" "aws-load-balancer-controller" {
  name        = "${var.project_name}-aws-load-balancer-controller-policy"
  description = "Policy which will be used for creating alb from the aws lb controller."

  policy = file("iam_policy.json")
}


resource "aws_iam_role_policy_attachment" "aws-load-balancer-controller" {
  role       = aws_iam_role.aws-load-balancer-controller-role.name
  policy_arn = aws_iam_policy.aws-load-balancer-controller.arn
}

# IAM resources for RAG services on EKS
# This configures IRSA for RAG ingestion and retrieval pods to access S3 bucket for documents and FAISS index.
# Assumptions: EKS OIDC provider enabled; s3.tf defines the bucket.
# Prerequisites: Deploy RAG services with service account 'rag-service' in 'rag' namespace.
# Annotate the service account: serviceAccount.annotations."eks\.amazonaws\.com/role-arn": aws_iam_role.rag_s3.arn
# Best practices: Least privilege - only specific S3 actions on the RAG bucket; use OIDC trust.

data "aws_iam_policy_document" "rag_s3_assume_role_policy" {
  statement {
    effect = "Allow"

    principals {
      type        = "Federated"
      identifiers = [module.eks.oidc_provider_arn]
    }

    actions = ["sts:AssumeRoleWithWebIdentity"]

    condition {
      test     = "StringEquals"
      variable = "${replace(module.eks.cluster_oidc_issuer_url, "https://", "")}:sub"
      values   = ["system:serviceaccount:rag:rag-service"]
    }

    condition {
      test     = "StringEquals"
      variable = "${replace(module.eks.cluster_oidc_issuer_url, "https://", "")}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "rag_s3" {
  name = "${var.project_name}-rag-s3"

  assume_role_policy = data.aws_iam_policy_document.rag_s3_assume_role_policy.json

  tags = {
    Name        = "${var.project_name}-rag-s3"
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

data "aws_iam_policy_document" "rag_s3_policy" {
  statement {
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
      "s3:ListBucket"
    ]
    resources = [
      aws_s3_bucket.rag_documents.arn,
      "${aws_s3_bucket.rag_documents.arn}/*"
    ]
  }
}

resource "aws_iam_policy" "rag_s3" {
  name        = "${var.project_name}-rag-s3-policy"
  description = "Policy for RAG services to access S3 bucket for documents and vectors in ${var.project_name}-eks"
  policy      = data.aws_iam_policy_document.rag_s3_policy.json

  tags = {
    Name        = "${var.project_name}-rag-s3-policy"
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

resource "aws_iam_role_policy_attachment" "rag_s3" {
  role       = aws_iam_role.rag_s3.name
  policy_arn = aws_iam_policy.rag_s3.arn
}

output "rag_s3_role_arn" {
  value       = aws_iam_role.rag_s3.arn
  description = "ARN of the IAM role for RAG S3 access"
}
