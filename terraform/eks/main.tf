# SecureKube AWS EKS Production Hardening Module
# Implements CIS EKS Benchmark, IRSA, KMS Secrets Encryption, and IMDSv2.

provider "aws" {
  region = var.aws_region
}

# ── 1. KMS Key for Kubernetes Secrets Encryption ─────────────────────
resource "aws_kms_key" "eks_secrets" {
  count                   = var.enable_kms_secrets_encryption ? 1 : 0
  description             = "KMS Key for ${var.cluster_name} Secrets Encryption"
  deletion_window_in_days = 30
  enable_key_rotation     = true

  tags = {
    Name        = "${var.cluster_name}-secrets-key"
    Environment = "production"
    ManagedBy   = "SecureKube"
  }
}

# ── 2. IAM Role for EKS Control Plane ────────────────────────────────
resource "aws_iam_role" "cluster_role" {
  name = "${var.cluster_name}-control-plane-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "eks.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "cluster_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.cluster_role.name
}

resource "aws_iam_role_policy_attachment" "cluster_vpc_controller" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSVPCResourceController"
  role       = aws_iam_role.cluster_role.name
}

# ── 3. EKS Hardened Cluster ──────────────────────────────────────────
resource "aws_eks_cluster" "securekube" {
  name     = var.cluster_name
  version  = var.cluster_version
  role_arn = aws_iam_role.cluster_role.arn

  # CIS EKS Control: All control plane logs enabled
  enabled_cluster_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]

  vpc_config {
    subnet_ids              = var.subnet_ids
    endpoint_private_access = true
    endpoint_public_access  = true
    public_access_cidrs     = ["0.0.0.0/0"] # Restrict to corporate VPN in production
  }

  dynamic "encryption_config" {
    for_each = var.enable_kms_secrets_encryption ? [1] : []
    content {
      provider {
        key_arn = aws_kms_key.eks_secrets[0].arn
      }
      resources = ["secrets"]
    }
  }

  depends_on = [
    aws_iam_role_policy_attachment.cluster_policy,
    aws_iam_role_policy_attachment.cluster_vpc_controller,
  ]
}

# ── 4. OIDC Provider for IAM Roles for Service Accounts (IRSA) ────────
data "tls_certificate" "eks_oidc" {
  url = aws_eks_cluster.securekube.identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "oidc" {
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.eks_oidc.certificates[0].sha1_fingerprint]
  url             = aws_eks_cluster.securekube.identity[0].oidc[0].issuer
}

# ── 5. IAM Role for Hardened Node Group ──────────────────────────────
resource "aws_iam_role" "node_role" {
  name = "${var.cluster_name}-node-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "node_worker" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.node_role.name
}

resource "aws_iam_role_policy_attachment" "node_cni" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.node_role.name
}

resource "aws_iam_role_policy_attachment" "node_registry" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.node_role.name
}

# ── 6. Hardened Managed Node Group with IMDSv2 ───────────────────────
resource "aws_launch_template" "hardened_node" {
  name_prefix   = "${var.cluster_name}-hardened-"
  instance_type = var.node_instance_types[0]

  # Enforce IMDSv2 (Blocks SSRF container metadata escape attacks)
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  monitoring {
    enabled = true
  }

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name      = "${var.cluster_name}-node"
      ManagedBy = "SecureKube"
    }
  }
}

resource "aws_eks_node_group" "hardened_nodes" {
  cluster_name    = aws_eks_cluster.securekube.name
  node_group_name = "${var.cluster_name}-hardened-nodes"
  node_role_arn   = aws_iam_role.node_role.arn
  subnet_ids      = var.subnet_ids

  scaling_config {
    desired_size = var.desired_nodes
    max_size     = var.max_nodes
    min_size     = var.min_nodes
  }

  launch_template {
    id      = aws_launch_template.hardened_node.id
    version = "$Latest"
  }

  depends_on = [
    aws_iam_role_policy_attachment.node_worker,
    aws_iam_role_policy_attachment.node_cni,
    aws_iam_role_policy_attachment.node_registry,
  ]
}

# ── 7. Post-Provisioning Baseline Bootstrap ──────────────────────────
resource "null_resource" "apply_securekube_baseline" {
  triggers = {
    cluster_endpoint = aws_eks_cluster.securekube.endpoint
  }

  provisioner "local-exec" {
    command = <<-EOT
      aws eks update-kubeconfig --region ${var.aws_region} --name ${var.cluster_name}
      kubectl apply -k ../../kustomize/base
      kubectl apply -k ../../kustomize/base/vap
    EOT
  }

  depends_on = [aws_eks_node_group.hardened_nodes]
}
