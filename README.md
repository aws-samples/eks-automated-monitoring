# EKS Automated Monitoring 
This repo accompanies the following AWS blog post:

[Automate monitoring for your Amazon EKS cluster using CloudWatch Container Insights](https://aws.amazon.com/blogs/infrastructure-and-automation/automate-monitoring-for-your-amazon-eks-cluster-using-cloudwatch-container-insights)

Follow the steps outlined in the blog post to deploy the following infrastructure
* An Amazon EKS cluster and CloudWatch Observability EKS add-on deployed using CloudFormation templates.
* CloudWatch static alarms, configured with Terraform.
* Dynamic alarms configured for Amazon EKS workloads using AWS Lambda, Amazon SNS, Amazon EventBridge, and Amazon S3.

![alt text](Architecture.png)