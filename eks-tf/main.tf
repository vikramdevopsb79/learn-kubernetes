#Cluster creation
resource "aws_eks_cluster" "example" {
  name     = "example"
  role_arn = aws_iam_role.example.arn
  enabled_cluster_log_types = ["audit"]

  vpc_config {
    subnet_ids = ["subnet-0b124925f5cc1454f", "subnet-0664653888f58619b"]
  }

  # Ensure that IAM Role permissions are created before and deleted after EKS Cluster handling.
  # Otherwise, EKS will not be able to properly delete EKS managed EC2 infrastructure such as Security Groups.
  depends_on = [
    aws_iam_role_policy_attachment.example-AmazonEKSClusterPolicy,
    aws_iam_role_policy_attachment.example-AmazonEKSVPCResourceController,
  ]
}
#From vpc we are transferring data so need check vpc data source subnets
# data "aws_subnets" "subnets" {
#   filter {
#     name   = "vpc-id"
#     values = ["vpc-090640b79f57fae25"]
#   }
# }

output "endpoint" {
  value = aws_eks_cluster.example.endpoint
}

output "kubeconfig-certificate-authority-data" {
  value = aws_eks_cluster.example.certificate_authority[0].data
}

data "aws_iam_policy_document" "assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["eks.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "example" {
  name               = "eks-cluster-example"
  assume_role_policy = data.aws_iam_policy_document.assume_role.json
}

resource "aws_iam_role_policy_attachment" "example-AmazonEKSClusterPolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.example.name
}

# Optionally, enable Security Groups for Pods
# Reference: https://docs.aws.amazon.com/eks/latest/userguide/security-groups-for-pods.html
resource "aws_iam_role_policy_attachment" "example-AmazonEKSVPCResourceController" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSVPCResourceController"
  role       = aws_iam_role.example.name
}

#Servers creation
resource "aws_eks_node_group" "example" {
  depends_on      = [aws_eks_addon.vpc-cni]
  cluster_name    = aws_eks_cluster.example.name
  node_group_name = "example"
  node_role_arn   = aws_iam_role.node-example.arn
  subnet_ids      = ["subnet-0b124925f5cc1454f", "subnet-0664653888f58619b"]
  # Choosing Spot instance and instance type because of saving cost
  instance_types  = ["t3.medium", "t3.large"]
  capacity_type   = "SPOT"
#
  scaling_config {
    desired_size = 1
    max_size     = 2
    min_size     = 1
  }
}
resource "aws_iam_role" "node-example" {
  name = "eks-node-group-example"

  assume_role_policy = jsonencode({
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
    }]
    Version = "2012-10-17"
  })
}

resource "aws_iam_role_policy_attachment" "example-AmazonEKSWorkerNodePolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.node-example.name
}

resource "aws_iam_role_policy_attachment" "example-AmazonEKS_CNI_Policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.node-example.name
}

resource "aws_iam_role_policy_attachment" "example-AmazonEC2ContainerRegistryReadOnly" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.node-example.name
}
resource "aws_eks_addon" "vpc-cni" {
  cluster_name = aws_eks_cluster.example.name
  addon_name   = "vpc-cni"

  configuration_values = jsonencode({
    "enableNetworkPolicy" : "true"
  })
}
data "external" "oidc-thumbprint" {
  program = [
    "/usr/bin/kubergrunt", "eks", "oidc-thumbprint", "--issuer-url", "${aws_eks_cluster.example.identity[0].oidc[0].issuer}"
  ]
}

resource "aws_iam_openid_connect_provider" "eks" {
  url = aws_eks_cluster.example.identity[0].oidc[0].issuer

  client_id_list = [
    "sts.amazonaws.com",
  ]

  thumbprint_list = [data.external.oidc-thumbprint.result.thumbprint]
}

locals {
  eks_client_id = element(tolist(split("/", tostring(aws_eks_cluster.example.identity[0].oidc[0].issuer))), 4)
}

resource "aws_eks_identity_provider_config" "example" {
  cluster_name = aws_eks_cluster.example.name

  oidc {
    client_id                     = local.eks_client_id
    identity_provider_config_name = "iam-oidc"
    issuer_url                    = aws_eks_cluster.example.identity[0].oidc[0].issuer
  }
}

resource "aws_iam_role" "eks-cluster-autoscale" {
  name = "eks-cluster-autoscale"

  assume_role_policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Effect" : "Allow",
        "Action" : "sts:AssumeRoleWithWebIdentity",
        "Principal" : {
          "Federated" : "arn:aws:iam::739561048503:oidc-provider/oidc.eks.us-east-1.amazonaws.com/id/${local.eks_client_id}"
        },
        "Condition" : {
          "StringEquals" : {
            "oidc.eks.us-east-1.amazonaws.com/id/${local.eks_client_id}:aud" : "sts.amazonaws.com",
            "oidc.eks.us-east-1.amazonaws.com/id/${local.eks_client_id}:sub" : "system:serviceaccount:kube-system:cluster-autoscaler"
          }
        }
      }
    ]
  })

  tags = {
    Name = "eks-cluster-autoscale"
  }
}

#annoniations need to add in cluster to consume it and install kubegrunt
resource "aws_iam_policy" "cluster-autoscale" {
  name        = "cluster-autoscale"
  path        = "/"
  description = "cluster-autoscale"

  policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Effect" : "Allow",
        "Action" : [
          "autoscaling:DescribeAutoScalingGroups",
          "autoscaling:DescribeAutoScalingInstances",
          "autoscaling:DescribeLaunchConfigurations",
          "autoscaling:DescribeScalingActivities",
          "autoscaling:DescribeTags",
          "ec2:DescribeImages",
          "ec2:DescribeInstanceTypes",
          "ec2:DescribeLaunchTemplateVersions",
          "ec2:GetInstanceTypesFromInstanceRequirements",
          "eks:DescribeNodegroup"
        ],
        "Resource" : ["*"]
      },
      {
        "Effect" : "Allow",
        "Action" : [
          "autoscaling:SetDesiredCapacity",
          "autoscaling:TerminateInstanceInAutoScalingGroup"
        ],
        "Resource" : ["*"]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "cluster-autoscale" {
  policy_arn = aws_iam_policy.cluster-autoscale.arn
  role       = aws_iam_role.eks-cluster-autoscale.name
}