/*
 * Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
 * SPDX-License-Identifier: MIT-0
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy of this
 * software and associated documentation files (the "Software"), to deal in the Software
 * without restriction, including without limitation the rights to use, copy, modify,
 * merge, publish, distribute, sublicense, and/or sell copies of the Software, and to
 * permit persons to whom the Software is furnished to do so.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED,
 * INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A
 * PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
 * HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
 * OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
 * SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
 */

#### SNS Topic To Sens EKS Alarm Notification #########
resource "aws_sns_topic" "eks_alarm_sns" {
  name              = "${local.name}-cw-eks-alarm"
  kms_master_key_id = aws_kms_key.kms_key.arn
  tags              = local.tags
  delivery_policy   = <<EOF
{
  "http": {
    "defaultHealthyRetryPolicy": {
      "minDelayTarget": 20,
      "maxDelayTarget": 20,
      "numRetries": 3,
      "numMaxDelayRetries": 0,
      "numNoDelayRetries": 0,
      "numMinDelayRetries": 0,
      "backoffFunction": "linear"
    },
    "disableSubscriptionOverrides": false,
    "defaultRequestPolicy": {
      "headerContentType": "text/plain; charset=UTF-8"
    }
  }
}
EOF
}

resource "aws_sns_topic_policy" "eks_alarm_sns_policy" {
  arn = aws_sns_topic.eks_alarm_sns.arn

  policy = data.aws_iam_policy_document.sns_topic_policy.json
}

data "aws_iam_policy_document" "sns_topic_policy" {
  policy_id = "__default_policy_ID"

  statement {
    actions = [
      "SNS:Subscribe",
      "SNS:SetTopicAttributes",
      "SNS:RemovePermission",
      "SNS:Receive",
      "SNS:Publish",
      "SNS:ListSubscriptionsByTopic",
      "SNS:GetTopicAttributes",
      "SNS:DeleteTopic",
      "SNS:AddPermission",
    ]

    condition {
      test     = "StringEquals"
      variable = "AWS:SourceOwner"

      values = [
        local.account_id,
      ]
    }

    effect = "Allow"

    principals {
      type        = "AWS"
      identifiers = ["*"]
    }

    resources = [
      aws_sns_topic.eks_alarm_sns.arn,
    ]

    sid = "__default_statement_ID"
  }
}
resource "aws_sns_topic_subscription" "subscriber" {
    topic_arn = aws_sns_topic.eks_alarm_sns.arn
    protocol = "email"
    endpoint = var.sns_topic_email
}

######################## Cloudwatch Alarms ##############################
module "cw_alarms" {
  source = "./modules/metric-alarm"

  for_each = var.alarms

  create_metric_alarm                   = try(each.value.create_metric_alarm, var.defaults.create_metric_alarm, true)
  alarm_name                            = try(each.value.alarm_name, var.defaults.alarm_name)
  alarm_description                     = try(each.value.alarm_description, var.defaults.alarm_description, null)
  comparison_operator                   = try(each.value.comparison_operator, var.defaults.comparison_operator)
  evaluation_periods                    = try(each.value.evaluation_periods, var.defaults.evaluation_periods)
  threshold                             = try(each.value.threshold, var.defaults.threshold, null)
  threshold_metric_id                   = try(each.value.threshold_metric_id, var.defaults.threshold_metric_id, null)
  unit                                  = try(each.value.unit, var.defaults.unit, null)
  metric_name                           = try(each.value.metric_name, var.defaults.metric_name, null)
  namespace                             = try(each.value.namespace, var.defaults.namespace, null)
  period                                = try(each.value.period, var.defaults.period, null)
  statistic                             = try(each.value.statistic, var.defaults.statistic, null)
  actions_enabled                       = try(each.value.actions_enabled, var.defaults.actions_enabled, true)
  datapoints_to_alarm                   = try(each.value.datapoints_to_alarm, var.defaults.datapoints_to_alarm, null)
  dimensions                            = try(each.value.dimensions, var.defaults.dimensions, null)
  alarm_actions                         = try(each.value.alarm_actions, [(aws_sns_topic.eks_alarm_sns.arn)], null)
  insufficient_data_actions             = try(each.value.insufficient_data_actions, var.defaults.insufficient_data_actions, null)
  ok_actions                            = try(each.value.ok_actions, [(aws_sns_topic.eks_alarm_sns.arn)], null)
  extended_statistic                    = try(each.value.extended_statistic, var.defaults.extended_statistic, null)
  treat_missing_data                    = try(each.value.treat_missing_data, var.defaults.treat_missing_data, "missing")
  evaluate_low_sample_count_percentiles = try(each.value.evaluate_low_sample_count_percentiles, var.defaults.evaluate_low_sample_count_percentiles, null)
  metric_query                          = try(each.value.metric_query, var.defaults.metric_query, [])
  tags                                  = local.tags
}

data "aws_iam_policy_document" "kms_key_policy_doc" {
  statement {
    sid       = "Enable IAM User Permissions"
    effect    = "Allow"
    actions   = ["kms:*"]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "kms:CallerAccount"
      values   = ["${data.aws_caller_identity.current.account_id}"]
    }

    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"]
    }
  }
  statement {
    sid       = "Enable Cloudwatch to access KMS KEY Permissions"
    effect    = "Allow"
    actions   = ["kms:Decrypt", "kms:GenerateDataKey*", "kms:DescribeKey"]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "kms:KeySpec"
      values   = ["SYMMETRIC_DEFAULT"]
    }

    principals {
      type        = "Service"
      identifiers = ["cloudwatch.amazonaws.com"]
    }
  }
}
resource "aws_kms_key" "kms_key" {
  description              = "KMS Key to encrypt CW Alarm data"
  customer_master_key_spec = "SYMMETRIC_DEFAULT"
  tags                     = local.tags
  policy                   = data.aws_iam_policy_document.kms_key_policy_doc.json
  deletion_window_in_days  = 7
  enable_key_rotation      = true
}

# Add an alias to the key
resource "aws_kms_alias" "this" {
  name          = "alias/${local.name}/key"
  target_key_id = aws_kms_key.kms_key.key_id
}



########################

resource "aws_security_group" "lambda_cw_alarm_sg" {
  name        = "${var.env}-${var.region}-${var.clusterName}-CloudWatchAutoAlarms"
  description = "Security Group for Lambda Function"
  vpc_id      = var.vpc_id
  tags        = local.tags
  egress {
    description = "Allow outbound connection to make calls to AWS Services - EC2, CloudWatch"
    from_port   = 443
    to_port     = 443
    protocol    = "TCP"
    cidr_blocks = ["0.0.0.0/0"]
  }
}


data "aws_iam_policy_document" "lambda_cw_alarm_assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_policy" "lambda_cw_alarm_policy" {
  name = "${var.env}-${var.region}-${var.clusterName}-CloudWatchAutoAlarms"
  policy = jsonencode(
    {
      Version = "2012-10-17"
      Statement = [
        {
          Effect = "Allow"
          Action = [
            "cloudwatch:PutMetricData"
          ]
          Resource = ["arn:${data.aws_partition.current.partition}:cloudwatch:${var.region}:${data.aws_caller_identity.current.account_id}:ContainerInsights/*"]
        },
        {
          Effect = "Allow",
          Action = [
            "logs:CreateLogGroup",
            "logs:CreateLogStream",
            "logs:PutLogEvents",
            "logs:DescribeLogGroups"
          ],
          Resource = ["arn:${data.aws_partition.current.partition}:logs:${var.region}:${data.aws_caller_identity.current.account_id}:log-group:*"],
        },
        {
          Effect = "Allow",
          Action = [
            "logs:PutLogEvents"
          ],
          Resource = ["arn:${data.aws_partition.current.partition}:logs:${var.region}:${data.aws_caller_identity.current.account_id}:log-group:*:log-stream:*"],
        },
        {
          Effect = "Allow",
          Action = [
            "ec2:DescribeInstances",
          ],
          Resource = ["*"],
          Condition = {
            StringEquals = {
              "ec2:Region" : var.region
            }
          }
        },
        {
          Effect = "Allow",
          Action = [
            "cloudwatch:DescribeAlarms",
            "cloudwatch:DeleteAlarms",
            "cloudwatch:PutMetricAlarm"
          ],
          Resource = ["arn:${data.aws_partition.current.partition}:cloudwatch:${var.region}:${data.aws_caller_identity.current.account_id}:alarm:*"],
        },
        {
          Effect = "Allow",
          Action = [
            "s3:Get*",
            "s3:ListBucket"
          ],
          Resource = ["arn:aws:s3:::${local.s3_bucket_name}/*"],
        },
        {
          Effect = "Allow",
          Action = [
            "kms:GenerateDataKey*",
            "kms:DescribeKey",
            "kms:Decrypt"
          ],
          Resource = ["${aws_kms_key.kms_key.arn}"]
        },
        {
          Effect = "Allow",
          Action = [
            "autoscaling:DescribeAutoScalingGroups",
            "autoscaling:DescribeAutoScalingInstances",
            "autoscaling:DescribeLaunchConfigurations",
            "autoscaling:DescribeScalingActivities"
          ],
          Resource = ["*"]
        },
        {
          Effect = "Allow",
          Action = [
            "SNS:Publish"
          ],
          Resource = aws_sns_topic.cw_alarm_status_notification.arn
        }

      ]
  })
}


resource "aws_iam_role" "lambda_cw_alarm_role" {
  name               = "${var.env}-${var.region}-${var.clusterName}-CloudWatchAutoAlarms"
  assume_role_policy = data.aws_iam_policy_document.lambda_cw_alarm_assume_role.json
}

resource "aws_iam_role_policy_attachment" "lambda_cw_alarm_policy_attachment" {
  policy_arn = aws_iam_policy.lambda_cw_alarm_policy.arn
  role       = aws_iam_role.lambda_cw_alarm_role.name
}

resource "aws_iam_role_policy_attachment" "lambda_autocw_AWSLambdaVPCAccessExecutionRole_attachment" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
  role       = aws_iam_role.lambda_cw_alarm_role.name
}

data "archive_file" "lambda" {
  type        = "zip"
  source_dir  = "src"
  output_path = "src/cwautoalarm.zip"
}

resource "aws_lambda_function" "lambda_cw_alarm_lambda" {
    #checkov:skip=CKV_AWS_116:The Dead Letter queue(DLQ) for Lambda is optional. It can be configured if required.
    #checkov:skip=CKV_AWS_50:The X ray tracing for lambda is optional. It can be configured if required  
    #checkov:skip=CKV_AWS_272: AWS Lambda code signing is secure practice and can be configured if required.
  filename                       = "src/cwautoalarm.zip"
  timeout                        = var.cw_auto_lambda_timeout
  handler                        = "cw_auto_alarm.lambda_handler"
  runtime                        = var.cw_autolambda_runtime
  memory_size                    = 512
  reserved_concurrent_executions = 5
  role                           = aws_iam_role.lambda_cw_alarm_role.arn
  source_code_hash               = data.archive_file.lambda.output_base64sha256
  kms_key_arn                    = aws_kms_key.kms_key.arn
  environment {
    variables = {
      TAGS                    = jsonencode(local.tags)
      LOGLEVEL                = "INFO"
      CLOUDWATCH_NAMESPACE    = "ContainerInsights"
      ALARM_PREFIX            = var.alarm_prefix
      ALARM_SEPARATOR         = var.alarm_separator
      S3_BUCKET_NAME          = local.s3_bucket_name
      ALARMS_LIST_FILE_KEY    = var.alarm_list_file_key
      SNS_TOPIC_ARN           = aws_sns_topic.cw_alarm_status_notification.arn
      AUTO_SCALING_GROUP_NAME = var.auto_scaling_group_name
    }
  }
  function_name = "${var.env}-${var.region}-${var.clusterName}-CloudWatchAutoAlarms"
  vpc_config {
    # Every subnet should be able to reach an EFS mount target in the same Availability Zone. Cross-AZ mounts are not permitted.
    subnet_ids         = var.private_subnet_ids
    security_group_ids = [aws_security_group.lambda_cw_alarm_sg.id]
  }
}


resource "aws_lambda_permission" "cloudwatch_events_invoke" {
  statement_id  = "AllowExecutionFromCloudWatchEvents"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.lambda_cw_alarm_lambda.arn
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.ec2_instance_run_terminated_event.arn
}



resource "aws_cloudwatch_event_rule" "ec2_instance_run_terminated_event" {
  name          = "eks_ec2_asg_scaling_event"
  description   = "Trigger Lambda function post a new EC2 instance Succesfully Launch/terminated"
  event_pattern = <<PATTERN
  {
    "source": ["aws.autoscaling"],
    "detail-type": ["EC2 Instance Launch Successful", "EC2 Instance Terminate Successful"],
    "detail": {
      "AutoScalingGroupName": ["${var.auto_scaling_group_name}"]
  }
}
PATTERN
}
resource "aws_cloudwatch_event_target" "lambda_cw" {
  rule      = aws_cloudwatch_event_rule.ec2_instance_run_terminated_event.name
  target_id = "SendToLambda"
  arn       = aws_lambda_function.lambda_cw_alarm_lambda.arn
}

data "aws_iam_policy_document" "alarm_bucket_policy" {
  statement {
    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"]
    }

    actions = [
      "s3:ListBucket",
      "s3:Get*"
    ]

    resources = [
      "arn:aws:s3:::${local.s3_bucket_name}",
      "arn:aws:s3:::${local.s3_bucket_name}/*"
    ]
  }
}

module "s3_bucket" {
  
  source = "git::https://github.com/terraform-aws-modules/terraform-aws-s3-bucket.git?ref=8a0b697adfbc673e6135c70246cff7f8052ad95a"
  bucket = local.s3_bucket_name

  force_destroy       = true
  acceleration_status = "Suspended"
  request_payer       = "BucketOwner"

  # Bucket policies
  attach_policy                         = true
  attach_deny_insecure_transport_policy = true
  allowed_kms_key_arn                   = aws_kms_key.kms_key.arn

  # S3 bucket-level Public Access Block configuration (by default now AWS has made this default as true for S3 bucket-level block public access)
  block_public_acls       = true
  block_public_policy     = true
  restrict_public_buckets = true
  tags                    = local.tags

  # S3 Bucket Ownership Controls
  control_object_ownership = true
  object_ownership         = "BucketOwnerPreferred"

  expected_bucket_owner = data.aws_caller_identity.current.account_id

  acl = "private" # "acl" conflicts with "grant" and "owner"

  versioning = {
    status     = true
    mfa_delete = false
  }

  server_side_encryption_configuration = {
    rule = {
      apply_server_side_encryption_by_default = {
        kms_master_key_id = "${aws_kms_key.kms_key.arn}"
        sse_algorithm     = "aws:kms"
      }
    }
  }
}

resource "aws_s3_object" "this" {
  bucket = module.s3_bucket.s3_bucket_id
  key    = "alarm_list_inputs.json"
  source = "./files/alarm_list_inputs.json"
  etag   = filemd5("./files/alarm_list_inputs.json")

}

###################### SNS Notification ###########

resource "aws_sns_topic" "cw_alarm_status_notification" {
  name              = "${local.name}-alarmSetupNotify"
  kms_master_key_id = aws_kms_key.kms_key.arn
  tags              = local.tags
  delivery_policy   = <<EOF
{
  "http": {
    "defaultHealthyRetryPolicy": {
      "minDelayTarget": 20,
      "maxDelayTarget": 20,
      "numRetries": 3,
      "numMaxDelayRetries": 0,
      "numNoDelayRetries": 0,
      "numMinDelayRetries": 0,
      "backoffFunction": "linear"
    },
    "disableSubscriptionOverrides": false,
    "defaultRequestPolicy": {
      "headerContentType": "text/plain; charset=UTF-8"
    }
  }
}
EOF
}

resource "aws_sns_topic_policy" "alarm_status_sns_policy" {
  arn = aws_sns_topic.cw_alarm_status_notification.arn

  policy = data.aws_iam_policy_document.alarm_status_sns_topic_policy.json
}

data "aws_iam_policy_document" "alarm_status_sns_topic_policy" {
  policy_id = "__default_policy_ID"

  statement {
    actions = [
      "SNS:Subscribe",
      "SNS:SetTopicAttributes",
      "SNS:RemovePermission",
      "SNS:Receive",
      "SNS:Publish",
      "SNS:ListSubscriptionsByTopic",
      "SNS:GetTopicAttributes",
      "SNS:DeleteTopic",
      "SNS:AddPermission",
    ]

    condition {
      test     = "StringEquals"
      variable = "AWS:SourceOwner"

      values = [
        local.account_id,
      ]
    }

    effect = "Allow"

    principals {
      type        = "AWS"
      identifiers = ["*"]
    }

    resources = [
      aws_sns_topic.cw_alarm_status_notification.arn,
    ]

    sid = "__default_statement_ID"
  }
}

resource "aws_sns_topic_subscription" "this" {
    topic_arn = aws_sns_topic.cw_alarm_status_notification.arn
    protocol = "email"
    endpoint = var.sns_topic_email
}
