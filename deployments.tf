# resource "kubernetes_namespace" "argocd" {
#   metadata {
#     name = "argocd"
#   }
# }

resource "kubernetes_secret" "git-repo" {
  metadata {
    name      = "argocd-git-repo-creds"
    namespace = "argocd"
    labels = {
      "argocd.argoproj.io/secret-type" = "repo-creds"
    }
  }

  type = "Opaque"

  data = {
    username = var.git_username
    password = var.git_password
    type     = "git"
  }
}

# resource "helm_release" "gpu_operator" {
#   name             = "gpu-operator"
#   repository       = "https://helm.ngc.nvidia.com/nvidia"
#   chart            = "gpu-operator"
#   version          = "v25.3.2" # Use the latest supported version; check NVIDIA docs for updates
#   namespace        = "gpu-operator"
#   create_namespace = true

#   # Disable toolkit as per your steps
#   set {
#     name  = "toolkit.enabled"
#     value = "false"
#   }
#   set {
#     name  = "driver.version"
#     value = "570.172.08" # Use the latest stable version; check NVIDIA
#   }

#   # Optional: Add wait and timeout for stability
#   wait    = true
#   timeout = 600 # 10 minutes

#   # Dependency: Ensure this runs after EKS cluster creation
#   depends_on = [module.eks]
# }

# IAM Role for AWS Load Balancer Controller
# resource "aws_iam_role" "aws-load-balancer-controller-role" {
#   name = "${var.project_name}-aws-load-balancer-controller"

#   assume_role_policy = <<POLICY
# {
#   "Version": "2012-10-17",
#   "Statement": [
#     {
#       "Sid": "",
#       "Effect": "Allow",
#       "Principal": {
#         "Federated": "${module.eks.oidc_provider_arn}"
#       },
#       "Action": "sts:AssumeRoleWithWebIdentity",
#       "Condition": {
#         "StringEquals": {
#           "${replace(module.eks.cluster_oidc_issuer_url, "https://", "")}:sub": "system:serviceaccount:kube-system:aws-load-balancer-controller",
#           "${replace(module.eks.cluster_oidc_issuer_url, "https://", "")}:aud": "sts.amazonaws.com"
#         }
#       }
#     }
#   ]
# }
# POLICY

#   depends_on = [module.eks]

#   tags = {
#     "ServiceAccountName"      = "aws-load-balancer-controller"
#     "ServiceAccountNameSpace" = "kube-system"
#   }
# }

# resource "aws_iam_policy" "aws-load-balancer-controller" {
#   name        = "${var.project_name}-aws-load-balancer-controller-policy"
#   description = "Policy which will be used for creating alb from the aws lb controller."

#   policy = file("iam_policy.json")
# }


# resource "aws_iam_role_policy_attachment" "aws-load-balancer-controller" {
#   role       = aws_iam_role.aws-load-balancer-controller-role.name
#   policy_arn = aws_iam_policy.aws-load-balancer-controller.arn
# }

# resource "helm_release" "alb_controller" {
#   name       = "aws-load-balancer-controller"
#   repository = "https://aws.github.io/eks-charts"
#   chart      = "aws-load-balancer-controller"
#   namespace  = "kube-system"

#   values = [
#     <<-EOT
#       clusterName: "${var.project_name}-eks"
#       vpcId: ${module.vpc.vpc_id}

#       subnetIds: ${jsonencode(module.vpc.public_subnets)}
#       serviceAccount:
#         create: true
#         name: aws-load-balancer-controller
#         annotations:
#           eks.amazonaws.com/role-arn: ${aws_iam_role.aws-load-balancer-controller-role.arn}
#     EOT
#   ]

#   wait    = true
#   timeout = 600

#   depends_on = [module.eks, aws_iam_role.aws-load-balancer-controller-role]
# }

# # ACM Certificate for ArgoCD
# resource "aws_acm_certificate" "argocd" {
#   domain_name       = var.argo_domain_name
#   validation_method = "DNS"
#   lifecycle {
#     create_before_destroy = true
#   }
# }

# resource "aws_route53_record" "argocd_cert_validation" {
#   for_each = {
#     for dvo in aws_acm_certificate.argocd.domain_validation_options : dvo.domain_name => {
#       name   = replace(dvo.resource_record_name, "/\\.$/", "") # Remove trailing dot if present
#       record = dvo.resource_record_value
#       type   = dvo.resource_record_type
#     }
#   }

#   allow_overwrite = true
#   name            = each.value.name
#   records         = [each.value.record]
#   ttl             = 60
#   type            = each.value.type
#   zone_id         = data.aws_route53_zone.zone.zone_id
# }

# resource "aws_acm_certificate_validation" "argocd" {
#   certificate_arn         = aws_acm_certificate.argocd.arn
#   validation_record_fqdns = [for record in aws_route53_record.argocd_cert_validation : record.fqdn]
# }

# resource "aws_route53_record" "argocd" {
#   zone_id = data.aws_route53_zone.zone.zone_id
#   name    = var.argo_domain_name
#   type    = "A"

#   alias {
#     name                   = data.aws_lb.argocd.dns_name
#     zone_id                = data.aws_lb.argocd.zone_id
#     evaluate_target_health = false
#   }

#   depends_on = [helm_release.argocd, aws_acm_certificate_validation.argocd]
# }

resource "helm_release" "argocd" {
  name             = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  version          = "8.5.8"
  namespace        = "argocd"
  create_namespace = true

  #values = [templatefile("argocd-values.yaml", { cert_arn = aws_acm_certificate.argocd.arn })]
  # values = [
  #   <<-EOT
  #   server:
  #     ingress:
  #       enabled: true
  #       ingressClassName: alb
  #       tls: false
  #       annotations:
  #         kubernetes.io/ingress.class: alb
  #         alb.ingress.kubernetes.io/scheme: internet-facing
  #         alb.ingress.kubernetes.io/target-type: ip
  #         alb.ingress.kubernetes.io/certificate-arn: ${aws_acm_certificate_validation.argocd.certificate_arn}
  #         alb.ingress.kubernetes.io/load-balancer-name: ${var.argocd_lb_name}
  #         alb.ingress.kubernetes.io/ssl-redirect: '443'
  #         alb.ingress.kubernetes.io/listen-ports: '[{"HTTP": 80}, {"HTTPS":443}]'
  #       hostname: ${var.argo_domain_name}
  #   configs:
  #     params:
  #       server.insecure: true
  #   EOT
  # ]

  wait    = true
  timeout = 600

  depends_on = [module.eks]
}

resource "kubectl_manifest" "argocd_root_app" {
  yaml_body = jsonencode({
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "Application"
    metadata = {
      name      = "root"
      namespace = "argocd"
    }
    spec = {
      project = "default"
      source = {
        repoURL        = "https://github.com/andrewdeweever/eks_llm"
        targetRevision = "HEAD" # Pin to 'main' or tag for production stability
        path           = "argocd-apps/"
        directory = {
          recurse = true
        }
      }
      destination = {
        server    = "https://kubernetes.default.svc"
        namespace = "argocd"
      }
      syncPolicy = {
        automated = {
          prune    = true
          selfHeal = true
        }
        syncOptions = ["CreateNamespace=true"]
      }
    }
  })

  depends_on = [helm_release.argocd, kubernetes_secret.git-repo, module.eks] # Ensure ArgoCD and repo creds are ready
}

# Note: This "App of Apps" pattern deploys all sub-apps in argocd-apps/. For private repo, the git-repo secret handles auth.
# Best practices: Use a dedicated ArgoCD project for apps; add sync waves if ordering matters (e.g., cert-manager before ingress).
