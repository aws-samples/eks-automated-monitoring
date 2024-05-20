import json
import logging
import os
from os import getenv
from functions import get_private_dns_name, send_notification, process_alarms, delete_alarms, get_instance_ids_from_auto_scaling_group
import boto3
from botocore.exceptions import ClientError

logger = logging.getLogger()
log_level = getenv("LOGLEVEL", "INFO")
level = logging.getLevelName(log_level)
logger.setLevel(level)

sns_topic_arn = getenv("SNS_TOPIC_ARN")
alarm_prefix = getenv("ALARM_PREFIX")
alarm_separator = getenv("ALARM_SEPARATOR", "-")
cw_namespace = getenv("CLOUDWATCH_NAMESPACE", "ContainerInsights")
bucket_name = getenv("S3_BUCKET_NAME")
alarm_file_key = getenv("ALARMS_LIST_FILE_KEY")
auto_scaling_group_name = getenv("AUTO_SCALING_GROUP_NAME")
def lambda_handler(event, context):
    s3 = boto3.client('s3')
    status_dict = {}
    tags_get = json.loads(os.environ.get('TAGS', '{}'))
    tags = [{'Key': key, 'Value': value} for key, value in tags_get.items()]
    if not event:
        # Handle the case when the event is empty
            response_alarm_list = s3.get_object(Bucket=bucket_name, Key=alarm_file_key)
            alarm_file_content = response_alarm_list['Body'].read().decode('utf-8')
            instanceIds = get_instance_ids_from_auto_scaling_group(auto_scaling_group_name)
            if instanceIds:
              for instanceId in instanceIds:
                al_json_content = json.loads(alarm_file_content)
                status = process_alarms(al_json_content, alarm_prefix, alarm_separator, sns_topic_arn, instanceId, tags)
                status_dict.update(status)
              header = "=== CloudWatch Alarm Status Report ===\n"
              footer = "\n=== End of Report ==="
              message_body = f"{header}{json.dumps(status_dict, indent=2)}{footer}"
              subject = "EKS Nodes CW Dynamic Alarm Creation Status"
              send_notification(sns_topic_arn, subject, message_body)
            else:
              logger.info ("No Instance Ids Found in ASG")
    else:
        instanceId = event['detail']['EC2InstanceId']
        try:
            # Load JSON content
            response_alarm_list = s3.get_object(Bucket=bucket_name, Key=alarm_file_key)
            alarm_file_content = response_alarm_list['Body'].read().decode('utf-8')
            al_json_content = json.loads(alarm_file_content)
            if 'source' in event and event['source'] == 'aws.autoscaling' and event['detail-type'] == 'EC2 Instance Launch Successful':
                status = process_alarms(al_json_content, alarm_prefix, alarm_separator, sns_topic_arn, instanceId, tags)
                status_dict.update(status)
                header = "=== CloudWatch Alarm Status Report ===\n"
                footer = "\n=== End of Report ==="
                message_body = f"{header}{json.dumps(status_dict, indent=2)}{footer}"
                subject = "EKS Nodes CW Dynamic Alarm Creation Status"
                send_notification(sns_topic_arn, subject, message_body)
            elif 'source' in event and event['source'] == 'aws.autoscaling' and event['detail-type'] == 'EC2 Instance Terminate Successful':
                result = delete_alarms(alarm_prefix, instanceId, alarm_separator)
                delete_status = result.get('delete_status')
                a_list = result.get('alarm_list')
                api_call_status = result.get('api_call')
                if delete_status and api_call_status:
                    header = "=== Below Mentioned CW Dynamic Alarms Are Succesfully Deleted ===\n"
                    footer = "\n=== End of Report ==="
                    status_dict[instanceId] = a_list
                    message_body = f"{header}{json.dumps(status_dict, indent=2)}{footer}"
                    subject = "EKS Nodes CW Dynamic Alarm Deletion Status"
                    send_notification(sns_topic_arn, subject, message_body)
                elif not delete_status and not api_call_status:
                        header = "=== Error in CW Dynamic Alarm Deletion!! Check CloudWatch logs ===\n"
                        footer = "\n=== End of Report ==="
                        a_p = result.get('alarm_p')
                        message_body = f"{header}Error in Alarm Deletion with Prefix - {a_p}. Check CloudWatch Logs{footer}"
                        subject = "EKS Nodes CW Dynamic Alarm Deletion Status"
                        send_notification(sns_topic_arn, subject, message_body)
                elif not delete_status and api_call_status:
                        a_p = result.get('alarm_p')
                        header = "=== Error in CW Dynamic Alarm Deletion!! Check CloudWatch logs ===\n"
                        footer = "\n=== End of Report ==="
                        message_body = f"{header}No Alarm Found With Alarm Prefix {a_p}. Check CloudWatch Logs{footer}"
                        subject = "EKS Nodes CW Dynamic Alarm Deletion Status"
                        send_notification(sns_topic_arn, subject, message_body)
                else:
                        header = "=== Error in CW Dynamic Alarm Deletion!! Check CloudWatch logs ===\n"
                        footer = "\n=== End of Report ==="
                        message_body = f"{header}Unknown Error Exist While Deleting Alarms Check CloudWatch Logs{footer}"
                        subject = "EKS Nodes CW Dynamic Alarm Deletion Status"
                        send_notification(sns_topic_arn, subject, message_body)
        except Exception as error:
            logger.exception(f"Error is: {error}")
            raise error
