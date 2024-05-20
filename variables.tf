variable "region" {
  type        = string
  description = "AWS Region"
}

variable "env" {
  type        = string
  default     = "dev"
  description = "Name of the environment, will be used as prefix in resources names"
}
variable "vpc_id" {
  type        = string
  description = "VPC ID"
}

variable "private_subnet_ids" {
  type        = list(any)
  description = "List of private subnet IDs in the VPC."
}

variable "cw_auto_lambda_timeout" {
  type        = string
  description = "Timeout parameter for Cloudwatch Dynamic Alarm lambda"
  default     = "300"
}

variable "cw_autolambda_runtime" {
  type        = string
  description = "Lambda Runtime detail"
  default     = "python3.9"
}

########################## CW Alarms #################################
variable "defaults" {
  description = "Map of default values which will be used for each item."
  type        = any
  default     = {}
}

variable "alarms" {
  description = "Maps of items to create a CW alarms using modules. Values are passed through to the module."
  type        = any
  default     = {}
}
variable "alarm_prefix" {
  type        = string
  description = "Prefix to add for alarm name"
}

variable "alarm_separator" {
  type        = string
  description = "Separator for alarm name"
  default     = "-"
}

variable "sns_topic_email" {
  type        = string
  description = "sns subscription email"
  default     = ""
}

variable "s3_bucket_name" {
  type        = string
  description = "S3 bucket Name"
}
variable "alarm_list_file_key" {
  type        = string
  description = "S3 bucket File key for Alarm List"
}
variable "clusterName" {
  type        = string
  description = "EKS Cluster Name"
}
variable "auto_scaling_group_name" {
  description = "Name of the EKS Auto Scaling Group"
  type        = string
}
