data "aws_partition" "current" {}
data "aws_caller_identity" "current" {}
data "aws_autoscaling_group" "eks_asg_arn" {
  name = var.auto_scaling_group_name
}
