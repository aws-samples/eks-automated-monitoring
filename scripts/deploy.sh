#Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
#SPDX-License-Identifier: MIT-0

#!/bin/bash

set -e

argHelper()
{
   echo ""
   echo "Usage: $0 -o apply OR destroy"
   echo -e "\t To provision the infrastructure pass [-o apply] flag"
   echo -e "\t To de-provision the infrastructure pass [-o destroy] flag"
   exit 1
}

while getopts "o:" opt
do
   case "$opt" in
      o ) param1="$OPTARG" ;;
      ? ) argHelper ;;
   esac
done

if [[ -z "$param1" ]];
then
   echo "Please pass the correct parameter to script";
   argHelper
fi

# EDIT THIS:
#------------------------------------------------------------------------------#
CLUSTER_VERSION=1.28
NUM_WORKER_NODES=3
WORKER_NODES_INSTANCE_TYPE=t2.medium
STACK_NAME=test-cluster
KEY_PAIR_NAME=eks-us-east-1
CWADDONVERSION=v1.5.5-eksbuild.1
S3_BUCKET_NAME=eks-dynamic-node-alarms
REGION=us-east-1
ENV=dev
SNS_EMAIL=<Provide Email Address>
TF_ROLE="<Provide IAM Role ARN to launch AWS Resources>"
TF_STATE_KEY="cloudwatch-insights/terraform.state"
ACCOUNT_ID=$(aws sts get-caller-identity --query "Account" --output text)
#------------------------------------------------------------------------------#

# Output colours
COLOUR='\033[1;34m'
NOC='\033[0m'

CURRENT_PATH=$(pwd)

if [[ "$param1" == "apply" ]];
then

  cd ${CURRENT_PATH}/scripts/

  echo -e  "$COLOUR> Deploying CloudFormation stack (may take up to 15 minutes)...! $NOC"
  aws cloudformation deploy \
    --region "$REGION" \
    --template-file eks-infra.yaml \
    --capabilities CAPABILITY_IAM \
    --stack-name "$STACK_NAME" \
    --parameter-overrides \
        ClusterVersion="$CLUSTER_VERSION" \
        CWAddOnVersion="$CWADDONVERSION" \
        NumWorkerNodes="$NUM_WORKER_NODES" \
        WorkerNodesInstanceType="$WORKER_NODES_INSTANCE_TYPE"


  echo -e "\n$COLOUR> Updating kubeconfig file...! $NOC"
  aws eks update-kubeconfig --region "$REGION" --name "$STACK_NAME"

  echo -e "\n$COLOUR> Configuring worker nodes (to join the cluster)...! $NOC"
  # Get worker nodes role ARN from CloudFormation stack output
  arn=$(aws cloudformation describe-stacks \
    --region "$REGION" \
    --stack-name "$STACK_NAME" \
    --query "Stacks[0].Outputs[?OutputKey=='WorkerNodesRoleArn'].OutputValue" \
    --output text)
  # Enable worker nodes to join the cluster:
  cat <<-EOF | kubectl apply -f -
    apiVersion: v1
    kind: ConfigMap
    metadata:
      name: aws-auth
      namespace: kube-system
    data:
      mapRoles: |
        - rolearn: $arn
          username: system:node:{{EC2PrivateDNSName}}
          groups:
            - system:bootstrappers
            - system:nodes
EOF

  echo -e "\n$COLOUR> Almost done! Cluster will be ready when all nodes have a 'Ready' status. $NOC"
  echo  "> Check node status using: kubectl get nodes --watch"

  alarm_list_inputs_path=$(realpath "../files/alarm_list_inputs.json")
  terraform_tfvars_path=$(realpath "../terraform.tfvars")
  provider_tf_path=$(realpath "../provider.tf")

  if [[ "$OSTYPE" == "darwin"* ]]; then

    echo -e "\n$COLOUR> Updating Cluster Name inside alarm list json $NOC"
    sed -i '' "s/Cluster_Name/"${STACK_NAME}"/g" "${alarm_list_inputs_path}"
    sleep 5
    echo -e "\n$COLOUR> Updating Cluster Name in terraform tfvars $NOC"
    sed -i '' "s/Cluster_Name/"${STACK_NAME}"/g" "${terraform_tfvars_path}"
    sleep 3
    echo -e "\n$COLOUR> Updating TF_ROLE in provider.tf $NOC"
    sed -i '' "s#TF_ROLE#"${TF_ROLE}"#g" "${provider_tf_path}"
    sleep 3
  else
    echo -e "\n$COLOUR> Updating Cluster Name inside alarm list json $NOC"
    sed -i "s/Cluster_Name/"${STACK_NAME}"/g" "${alarm_list_inputs_path}"
    sleep 5
    echo -e "\n$COLOUR> Updating Cluster Name in terraform tfvars $NOC"
    sed -i "s/Cluster_Name/"${STACK_NAME}"/g" "${terraform_tfvars_path}"
    sleep 3
    echo -e "\n$COLOUR> Updating TF_ROLE in provider.tf $NOC"
    sed -i "s#TF_ROLE#"${TF_ROLE}"#g" "${provider_tf_path}"
    sleep 3
  fi

  echo -e "\n$COLOUR> Updating VPCId, SubnetIds and ASG Name into terraform tfvars! $NOC"

  VPCId=$(aws cloudformation describe-stacks \
    --region "$REGION" \
    --stack-name "$STACK_NAME" \
    --query "Stacks[0].Outputs[?OutputKey=='VPCId'].OutputValue" \
    --output text)

  PrivateSubnetId1=$(aws cloudformation describe-stacks \
    --region "$REGION" \
    --stack-name "$STACK_NAME" \
    --query "Stacks[0].Outputs[?OutputKey=='PrivateSubnetId1'].OutputValue" \
    --output text)

  PrivateSubnetId2=$(aws cloudformation describe-stacks \
    --region "$REGION" \
    --stack-name "$STACK_NAME" \
    --query "Stacks[0].Outputs[?OutputKey=='PrivateSubnetId2'].OutputValue" \
    --output text)

  AutoScalingGroupName=$(aws cloudformation describe-stacks \
    --region "$REGION" \
    --stack-name "$STACK_NAME" \
    --query "Stacks[0].Outputs[?OutputKey=='AutoScalingGroupName'].OutputValue" \
    --output text)
  
  if [[ "$OSTYPE" == "darwin"* ]]; then
    sed -i '' "s/^ *clusterName *= *[^ ]*/clusterName = \"${STACK_NAME}\"/" "${terraform_tfvars_path}"
    sleep 2
    sed -i '' "s/^ *vpc_id *= *[^ ]*/vpc_id = \"${VPCId}\"/" "${terraform_tfvars_path}"
    sleep 2
    sed -i '' "s/^ *private_subnet_ids *= .*[^ ]* */private_subnet_ids = [\""${PrivateSubnetId1}"\", \""${PrivateSubnetId1}"\"]/" "${terraform_tfvars_path}"
    sleep 2
    sed -i '' "s/^ *auto_scaling_group_name *= *[^ ]*/auto_scaling_group_name = \"${AutoScalingGroupName}\"/" "${terraform_tfvars_path}"
    sleep 2
  else
    sed -i "s/^ *clusterName *= *[^ ]*/clusterName = \"${STACK_NAME}\"/" "${terraform_tfvars_path}"
    sleep 2
    sed -i "s/^ *vpc_id *= *[^ ]*/vpc_id = \"${VPCId}\"/" "${terraform_tfvars_path}"
    sleep 2
    sed -i "s/^ *private_subnet_ids *= .*[^ ]* */private_subnet_ids = [\""${PrivateSubnetId1}"\", \""${PrivateSubnetId1}"\"]/" "${terraform_tfvars_path}"
    sleep 2
    sed -i "s/^ *auto_scaling_group_name *= *[^ ]*/auto_scaling_group_name = \"${AutoScalingGroupName}\"/" "${terraform_tfvars_path}"
    sleep 2
  fi
  cd ${CURRENT_PATH}/

  echo -e "\n$COLOUR> Deploying dynamic alerting via terraform...! $NOC"


  # Create a bucket to store terraform state file and update the backend.tf
  TF_BACKEND_BUCKET=("tf-state-${S3_BUCKET_NAME}-${REGION}-${ACCOUNT_ID}")
  aws s3api create-bucket --bucket "${TF_BACKEND_BUCKET}" --region "${REGION}"

  aws s3api put-bucket-versioning --bucket "${TF_BACKEND_BUCKET}" --versioning-configuration Status=Enabled
  sleep 3

  TF_BACKEND_CONFIG=$(cat <<-EOF
  terraform {
    backend "s3" {
      bucket         = "${TF_BACKEND_BUCKET}"
      key            = "${TF_STATE_KEY}"
      region         = "${REGION}"
      role_arn       = "${TF_ROLE}"
    }
  }
EOF
)

  TF_BACKEND_FILE="backend.tf"
  echo "$TF_BACKEND_CONFIG" > "$TF_BACKEND_FILE"
  if [ -f "$TF_BACKEND_FILE" ]; then
    echo -e "\n$COLOUR> Terraform backend configuration created in $TF_BACKEND_FILE $NOC"
  else
    echo -e "\n$COLOUR> Issue while creating a terraform backend configuration $TF_BACKEND_FILE $NOC"
  fi

  terraform init
  terraform plan -var="region=${REGION}" -var="env=${ENV}" -var="s3_bucket_name=${S3_BUCKET_NAME}" -var="sns_topic_email=${SNS_EMAIL}"
  terraform apply -var="region=${REGION}" -var="env=${ENV}" -var="s3_bucket_name=${S3_BUCKET_NAME}" -var="sns_topic_email=${SNS_EMAIL}" -auto-approve

elif [[ "$param1" == "destroy" ]];
then
  echo -e "\n$COLOUR> Destroying dynamic alerting resources created by terraform...! $NOC"
  terraform init
  terraform destroy -var="region=${REGION}" -var="env=${ENV}" -var="s3_bucket_name=${S3_BUCKET_NAME}" -var="sns_topic_email=${SNS_EMAIL}" -auto-approve

  echo -e "\n$COLOUR> Deleting VPC and EKS resoures created by cloudformation...! $NOC"
  cd ${CURRENT_PATH}/scripts/
  aws cloudformation delete-stack --stack-name "$STACK_NAME" --region "$REGION"

else
  echo "Please pass the correct parameter to script";
  argHelper
fi
