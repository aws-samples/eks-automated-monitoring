output "cw_alarms" {
  description = "Map of outputs of a wrapper."
  value       = module.cw_alarms
  # sensitive = false  # No sensitive module output found
}

output "bucket_name" {
  value = module.s3_bucket.s3_bucket_id
}

output "function_name" {
  description = "The name of the Lambda function"
  value       = join("", aws_lambda_function.lambda_cw_alarm_lambda.*.function_name)
}
