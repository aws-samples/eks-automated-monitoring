locals {
  cluster_name   = var.clusterName
  name           = "${var.env}-${var.region}-${var.clusterName}"
  region         = var.region
  account_id     = data.aws_caller_identity.current.account_id
  s3_bucket_name = "${local.cluster_name}-${var.s3_bucket_name}-${local.account_id}"

  tags = {
    Environment = "eks-${var.env}"
    Region      = "US"
  }
}
