variable "aws_region" {
  description = "AWS region to deploy resources"
  type        = string
  default     = "us-west-2"
}

variable "project_name" {
  description = "Project name"
  type        = string
  default     = "eks-llm"
}

variable "argo_domain_name" {
  description = "Domain name for ArgoCD (e.g., argo.example.com)"
  type        = string
  default     = "argo.deweever.bsisandbox.com"
}

variable "argocd_lb_name" {
  description = "Name for the Application Load Balancer for ArgoCD"
  type        = string
  default     = "argocd-alb"
}
variable "environment" {
  description = "Environment (e.g., dev, prod)"
  type        = string
  default     = "dev"
}

variable "git_username" {
  description = "Git repository username for ArgoCD access"
  type        = string
  default     = "andrewdeweever" # Replace with your Git username
}

variable "git_password" {
  description = "Git repository password or token for ArgoCD access"
  type        = string
  sensitive   = true
}
