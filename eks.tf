module "ebs_csi_irsa_role" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts"
  version = "~> 6.0"

  name                  = "${var.project_name}-ebs-csi"
  attach_ebs_csi_policy = true

  oidc_providers = {
    ex = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:ebs-csi-controller-sa"]
    }
  }
}

# EKS Module: Creates secure EKS cluster with CPU and GPU node groups
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 21.15.1"

  name               = "${var.project_name}-eks"
  kubernetes_version = "1.35"

  authentication_mode                      = "API_AND_CONFIG_MAP"
  enable_cluster_creator_admin_permissions = true
  # === Karpenter discovery tags (required) ===
  node_security_group_tags = {
    "karpenter.sh/discovery" = "${var.project_name}"
  }

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
          ENABLE_PREFIX_DELEGATION = "true"
          WARM_PREFIX_TARGET       = "1"
        }
      })
    }
    coredns = {
      most_recent = true
    }
    kube-proxy = {
      most_recent = true
    }
    aws-ebs-csi-driver = {
      service_account_role_arn = module.ebs_csi_irsa_role.arn
      most_recent              = true
    }
    eks-pod-identity-agent = {
      before_compute = true
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
    initial = {
      min_size       = 1
      max_size       = 3
      desired_size   = 2
      disk_size      = 100
      instance_types = ["m5.large"]
      ami_type       = "AL2023_x86_64_STANDARD"
      key_name       = aws_key_pair.eks.key_name
      block_device_mappings = {
        # Root volume (increase size here)
        xvda = {
          device_name = "/dev/xvda"
          ebs = {
            volume_size           = 75 # New size in GiB (default is ~20)
            volume_type           = "gp3"
            delete_on_termination = true
            encrypted             = true
            # Optional: iops = 3000  # For higher performance
            # throughput = 125  # For gp3 (MiB/s)
          }
        }
      }
    }
    karpenter_controller = {
      min_size       = 1
      max_size       = 3
      desired_size   = 2
      disk_size      = 100
      instance_types = ["m5.large"]
      ami_type       = "AL2023_x86_64_STANDARD"
      key_name       = aws_key_pair.eks.key_name
      labels = {
        "karpenter.sh/controller" = "true"
      }
      taints = {
        karpenter = {
          key    = "KarpenterOnly"
          value  = "true"
          effect = "NO_SCHEDULE"
        }
      }
      block_device_mappings = {
        # Root volume (increase size here)
        xvda = {
          device_name = "/dev/xvda"
          ebs = {
            volume_size           = 75 # New size in GiB (default is ~20)
            volume_type           = "gp3"
            delete_on_termination = true
            encrypted             = true
            # Optional: iops = 3000  # For higher performance
            # throughput = 125  # For gp3 (MiB/s)
          }
        }
      }
    }
  }
}


module "eks_blueprints_addons" {
  source  = "aws-ia/eks-blueprints-addons/aws"
  version = "~> 1.16" # latest as of March 2026

  cluster_name      = module.eks.cluster_name
  cluster_endpoint  = module.eks.cluster_endpoint
  cluster_version   = module.eks.cluster_version
  oidc_provider_arn = module.eks.oidc_provider_arn

  # Disable the limited EKS addon version so we don't have conflicts
  enable_metrics_server = true

  metrics_server = {
    most_recent = true
    values = [jsonencode({
      args = [
        "--kubelet-insecure-tls",
        "--kubelet-preferred-address-types=InternalIP,ExternalIP,Hostname"
      ]
    })]
  }

  enable_karpenter = true
  karpenter = {
    chart_version       = "1.9.0" # ← current latest as of March 2026
    repository          = "oci://public.ecr.aws/karpenter"
    chart               = "karpenter"
    repository_username = data.aws_ecrpublic_authorization_token.token.user_name
    repository_password = data.aws_ecrpublic_authorization_token.token.password
    values = [jsonencode({
      nodeSelector = {
        "karpenter.sh/controller" = "true"
      }
      tolerations = [
        {
          key      = "KarpenterOnly"
          operator = "Equal"
          value    = "true"
          effect   = "NoSchedule"
        }
      ]
    })]
  }
}

# Let Karpenter-provisioned nodes join the cluster
resource "aws_eks_access_entry" "karpenter_nodes" {
  cluster_name  = module.eks.cluster_name
  principal_arn = module.eks_blueprints_addons.karpenter.node_iam_role_arn
  type          = "EC2_LINUX"
}

# === STANDARD (CPU / compute) — equivalent to AL2023_x86_64_STANDARD ===
resource "kubectl_manifest" "ec2nodeclass_standard" {
  yaml_body = <<YAML
apiVersion: karpenter.k8s.aws/v1
kind: EC2NodeClass
metadata:
  name: standard
spec:
  role: ${module.eks_blueprints_addons.karpenter.node_iam_role_name}
  subnetSelectorTerms:
    - tags:
        karpenter.sh/discovery: ${var.project_name}
  securityGroupSelectorTerms:
    - tags:
        karpenter.sh/discovery: ${var.project_name}
  amiSelectorTerms:
    - name: amazon-eks-node-al2023-x86_64-standard-*
YAML

  depends_on = [module.eks_blueprints_addons]
}

# === NVIDIA GPU — equivalent to AL2023_x86_64_NVIDIA ===
resource "kubectl_manifest" "ec2nodeclass_gpu_nvidia" {
  yaml_body = <<YAML
apiVersion: karpenter.k8s.aws/v1
kind: EC2NodeClass
metadata:
  name: gpu-nvidia
spec:
  role: ${module.eks_blueprints_addons.karpenter.node_iam_role_name}
  subnetSelectorTerms:
    - tags:
        karpenter.sh/discovery: ${var.project_name}
  securityGroupSelectorTerms:
    - tags:
        karpenter.sh/discovery: ${var.project_name}
  amiSelectorTerms:
    - name: amazon-eks-node-al2023-x86_64-nvidia-*
YAML

  depends_on = [module.eks_blueprints_addons]
}

# === COMPUTE NodePool (uses STANDARD AMI) ===
resource "kubectl_manifest" "nodepool_compute" {
  yaml_body = <<YAML
apiVersion: karpenter.sh/v1
kind: NodePool
metadata:
  name: compute
spec:
  template:
    metadata:
      labels:
        "type": "cpu"
    spec:
      nodeClassRef:
        group: karpenter.k8s.aws
        kind: EC2NodeClass
        name: standard
      requirements:
        - key: karpenter.sh/capacity-type
          operator: In
          values: ["on-demand"]
        - key: kubernetes.io/arch
          operator: In
          values: ["amd64"]
        - key: kubernetes.io/os
          operator: In
          values: ["linux"]
        - key: node.kubernetes.io/instance-type
          operator: In
          values: ["m5.xlarge"]      
  disruption:
    consolidationPolicy: WhenEmptyOrUnderutilized
    consolidateAfter: 60s
YAML

  depends_on = [kubectl_manifest.ec2nodeclass_standard]
}

# === GPU NodePool (uses NVIDIA AMI) ===
resource "kubectl_manifest" "nodepool_gpu" {
  yaml_body = <<YAML
apiVersion: karpenter.sh/v1
kind: NodePool
metadata:
  name: gpu
spec:
  template:
    metadata:
      labels:
        "type": "gpu"  
    spec:
      nodeClassRef:
        group: karpenter.k8s.aws
        kind: EC2NodeClass
        name: gpu-nvidia
      requirements:
        - key: karpenter.sh/capacity-type
          operator: In
          values: ["on-demand"]
        - key: karpenter.k8s.aws/instance-type
          operator: In
          values: ["g6.xlarge"]
      taints:
        - key: nvidia.com/gpu
          value: "true"
          effect: NoSchedule
  disruption:
    consolidationPolicy: WhenEmptyOrUnderutilized
    consolidateAfter: 5m
YAML

  depends_on = [kubectl_manifest.ec2nodeclass_gpu_nvidia]
}
