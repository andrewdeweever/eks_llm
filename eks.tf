# EKS Module: Creates secure EKS cluster with CPU and GPU node groups
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 21.0.7"

  name               = "${var.project_name}-eks"
  kubernetes_version = "1.32"

  authentication_mode                      = "API_AND_CONFIG_MAP"
  enable_cluster_creator_admin_permissions = true

  #   access_entries = {
  #     andrew_deweever = {
  #       kubernetes_groups = ["eks-admins"]
  #       principal_arn     = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:user/andrew.deweever"
  #       user_name         = "andrew.deweever"
  #     }
  #   }
  access_entries = {
    bastion = {
      kubernetes_groups = ["eks-admins"]
      principal_arn     = aws_iam_role.bastion.arn
      role_name         = aws_iam_role.bastion.name
    }
  }

  addons = {
    vpc-cni = {
      most_recent    = true
      before_compute = true
      configuration_values = jsonencode({
        env = {
          ENABLE_PREFIX_DELEGATION     = "true"
          WARM_PREFIX_TARGET           = "1"
          AWS_VPC_K8S_CNI_EXTERNALSNAT = "true" # Add this
        }
      })
    }
    coredns = {
      most_recent = true
    }
    kube-proxy = {
      most_recent = true
    }
  }

  endpoint_private_access = true
  endpoint_public_access  = true
  enabled_log_types       = ["api", "audit", "authenticator", "controllerManager", "scheduler"]
  create_kms_key          = true # Default is true, so optional; module creates/manages the KMS key

  encryption_config = {
    resources = ["secrets"]
  }
  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets
  node_security_group_additional_rules = {
    allow_ssh = {
      description = "Allow SSH"
      protocol    = "tcp"
      from_port   = 22
      to_port     = 22
      type        = "ingress"
      cidr_blocks = [module.vpc.vpc_cidr_block]
    }
  }

  enable_irsa = true

  eks_managed_node_groups = {
    cpu = {
      min_size       = 1
      max_size       = 3
      desired_size   = 2
      instance_types = ["m5.large"]
      ami_type       = "AL2023_x86_64_STANDARD"
      key_name       = aws_key_pair.eks.key_name
    }
    gpu = {
      min_size       = 1
      max_size       = 3
      desired_size   = 1
      instance_types = ["g4dn.xlarge"]
      ami_type       = "AL2023_x86_64_NVIDIA"
      key_name       = aws_key_pair.eks.key_name
    }
  }
}

resource "helm_release" "gpu_operator" {
  name             = "gpu-operator"
  repository       = "https://helm.ngc.nvidia.com/nvidia"
  chart            = "gpu-operator"
  version          = "v25.3.2" # Use the latest supported version; check NVIDIA docs for updates
  namespace        = "gpu-operator"
  create_namespace = true

  # Disable toolkit as per your steps
  set {
    name  = "toolkit.enabled"
    value = "false"
  }
  set {
    name  = "driver.version"
    value = "570.172.08" # Use the latest stable version; check NVIDIA
  }

  # Optional: Add wait and timeout for stability
  wait    = true
  timeout = 600 # 10 minutes

  # Dependency: Ensure this runs after EKS cluster creation
  depends_on = [module.eks]
}
