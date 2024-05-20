import boto3, json
import os, logging
from os import getenv
from io import StringIO
logger = logging.getLogger()
log_level = getenv("LOGLEVEL", "INFO")
level = logging.getLevelName(log_level)
logger.setLevel(level)

valid_comparators = ['GreaterThanOrEqualToThreshold', 'GreaterThanThreshold', 'LessThanThreshold',
                     'LessThanOrEqualToThreshold', "LessThanLowerOrGreaterThanUpperThreshold", "LessThanLowerThreshold",
                     "GreaterThanUpperThreshold"]

valid_anomaly_detection_comparators = ["LessThanLowerOrGreaterThanUpperThreshold", "LessThanLowerThreshold",
                                       "GreaterThanUpperThreshold"]


def get_private_dns_name(instance_id):
    # Create EC2 client
    ec2_client = boto3.client('ec2')
    try:
    # Describe instances to get private DNS name
        response = ec2_client.describe_instances(InstanceIds=[instance_id])
    # Extract private DNS name from the response
        if 'Reservations' in response and response['Reservations']:
            # Assuming the instance has private DNS name, get it
            private_dns_name = response['Reservations'][0]['Instances'][0].get('PrivateDnsName')
            return private_dns_name
        else:
            logger.error(f"Instance ID {instance_id} not found in describe_instances response.")
            return None
    except Exception as e:
        logger.error(f"An error occurred while trying to get private DNS name for instance ID {instance_id}: {e}")
        return None
    
def create_alarm(AlarmName, MetricName, ComparisonOperator, Threshold, EvaluationPeriods, Period, Namespace, Unit, Datapoints, Statistic, actions_enabled, AlarmDescription, Dimensions, TreatMissingData, sns_topic_arn, tags):
    if AlarmDescription:
        AlarmDescription = AlarmDescription.replace("_", " ")
    else:
        AlarmDescription = 'Created by cloudwatch-auto-alarms'
    try:
        cw_client = boto3.client('cloudwatch')

        metrics = [{
            'Id': 'm1',
            'MetricStat': {
                'Metric': {
                    'MetricName': MetricName,
                    'Namespace': Namespace,
                    'Dimensions': Dimensions
                },
                'Stat': Statistic,
                'Period': Period,
                'Unit': Unit
            },
        }]

        alarm_details = {
            'AlarmName': AlarmName,
            'AlarmDescription': AlarmDescription,
            'EvaluationPeriods': int(EvaluationPeriods),
            'ComparisonOperator': ComparisonOperator,
            'TreatMissingData': TreatMissingData,
            'Metrics': metrics,
            'DatapointsToAlarm': Datapoints,
            'Tags': tags
        }

        if ComparisonOperator in valid_anomaly_detection_comparators:
            metrics.append(
                {
                    'Id': 't1',
                    'Label': 't1',
                    'Expression': "ANOMALY_DETECTION_BAND(m1, {})".format(Threshold),
                }
            )
            alarm_details['ThresholdMetricId'] = 't1'
        else:
            alarm_details['Threshold'] = Threshold
        
        if sns_topic_arn is not None:
            alarm_details['AlarmActions'] = [sns_topic_arn]
        
        response = cw_client.put_metric_alarm(**alarm_details)
        return True
    except Exception as error:
        logger.exception(f"Error in create_alarm function: {error}")
        return False
def delete_alarms(alarm_prefix, alarm_identifier, alarm_separator):
    try:
        alarm_list = []
        AlarmNamePattern = alarm_separator.join([alarm_prefix, alarm_identifier])
        cw_client = boto3.client('cloudwatch')
        response = cw_client.describe_alarms(AlarmNamePrefix=AlarmNamePattern,)
        if 'MetricAlarms' in response:
            for alarm in response['MetricAlarms']:
                alarm_name = alarm['AlarmName']
                alarm_list.append(alarm_name)
        if alarm_list:
            response = cw_client.delete_alarms(AlarmNames=alarm_list)
            return {
                'delete_status': True,
                'alarm_list': alarm_list,
                'api_call': True
              }
        else:
            logger.error('No Alarm Found With Prefix {}'.format(AlarmNamePattern))
            return {
                  'delete_status': False,
                  'alarm_list': alarm_list,
                  'alarm_p': AlarmNamePattern,
                  'api_call': True
                   }
    except Exception as e:
        logger.error('Error deleting alarms for {}!: {}'.format(AlarmNamePattern, e))
        return {
              'delete_status': False,
              'api_call': False,
              'alarm_p': AlarmNamePattern,
                }

def get_instance_ids_from_auto_scaling_group(auto_scaling_group_name):
        autoscaling_client = boto3.client('autoscaling')
        response = autoscaling_client.describe_auto_scaling_groups(
            AutoScalingGroupNames=[auto_scaling_group_name]
        )
        instance_ids = []

        for group in response['AutoScalingGroups']:
            for instance in group['Instances']:
                instance_ids.append(instance['InstanceId'])
        return instance_ids

def process_alarms(al_json_content, alarm_prefix, alarm_separator, sns_topic_arn, instanceId, tags):
    output_variable = {}
    for alarm in al_json_content.get('alarms', []):
        alarm_suffix = alarm.get('alarm_name')
        if not alarm_suffix:
             raise ValueError("Alarm name is Not Provided in input list and its Empty")
        dynamic_alarm_name = alarm_separator.join([alarm_prefix, instanceId, alarm_suffix])
        metric_name = alarm.get('metric_name')
        comparison_operator = alarm.get('comparison_operator')
        threshold = alarm.get('threshold')
        evaluation_periods = alarm.get('evaluation_periods')
        period = alarm.get('period')
        namespace = alarm.get('namespace')
        unit = alarm.get('unit')
        datapoints =  alarm.get('datapoints')
        statistic = alarm.get('statistic')
        actions_enabled = alarm.get('actions_enabled')
        alarm_description = alarm.get('alarm_description')
        dimensions = alarm.get('dimensions', {})
        treat_missing_data = alarm.get('treat_missing_data')
        instance_private_dns_name = get_private_dns_name(instanceId)
        if not instance_private_dns_name:
              raise ValueError("Instance private DNS name is empty. Code execution will be failed.")
        instance_id_dict = {'Name': 'InstanceId', 'Value': instanceId}
        private_dns_name_dict = {'Name': 'NodeName', 'Value': instance_private_dns_name}
        dimensions.append(instance_id_dict)
        dimensions.append(private_dns_name_dict)
        create_status = create_alarm(dynamic_alarm_name, metric_name, comparison_operator, threshold, evaluation_periods, period, namespace, unit, datapoints, statistic, actions_enabled, alarm_description, dimensions, treat_missing_data, sns_topic_arn, tags)
        if create_status:
            output_status = "Alarm {} for Node {} is Successful".format(alarm_suffix, instanceId)
            if instanceId in output_variable:
                output_variable[instanceId].append(output_status)
            else:
                output_variable[instanceId] = [output_status]
        else:
            output_status = "Alarm {} for Node {} is Failed. Check CloudWatch Logs for more details".format(alarm_suffix, instanceId)
            if instanceId in output_variable:
                output_variable[instanceId].append(output_status)
            else:
                output_variable[instanceId] = [output_status]

    return output_variable
def send_notification(sns_topic_arn, subject, message_body):
    sns_client = boto3.client('sns')
    message_body = message_body
    response = sns_client.publish(
            TopicArn=sns_topic_arn,
            Message=message_body,
            Subject=subject
            )
