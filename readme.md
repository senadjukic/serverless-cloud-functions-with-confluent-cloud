# Serverless Cloud Functions with Confluent Cloud

## Description
This demo demonstrates how cloud functions can produce and consume from Confluent Cloud. The current examples are with AWS Lambda and are baked by Terraform.

## Prerequisites
1. Check if you have Confluent Cloud Account
2. Check if you have Terraform https://learn.hashicorp.com/tutorials/terraform/install-cli#install-terraform
3. Check if you have Confluent CLI
4. Follow https://registry.terraform.io/providers/confluentinc/confluent/latest/docs/guides/sample-project#create-a-cloud-api-key

## Deployment
1. cd confluent-cloud-cluster
2. create terraform.vars file with your credentials

```
touch terraform.tfvars

confluent_cloud_api_key = "(see Confluent Cloud settings)"
confluent_cloud_api_secret = "(see Confluent Cloud settings)"
environment_name = "cloud-functions"
cluster_name = "cf-basic"
topic_name = "temperature"
aws_access_key_id = "(see AWS IAM)"
aws_secret_access_key = "(see AWS IAM)"
lambda_sink_function_name = "Connector_Sink_Lambda_Function"
```

3. `terraform init`
4. `terraform apply -auto-approve`
5. create input file for python vars (change path_to_env_file)

```
export path_to_env_file="/c/work/serverless-cloud-funtions-with-confluent-cloud/aws-lambda-producer-to-confluent-cloud/python/env.py"

echo "env_cluster_bootstrap_endpoint = \"$(terraform output -raw cluster_bootstrap_endpoint | cut -c 12-)"\" > $path_to_env_file

echo "env_producer_kafka_api_key = \"$(terraform output -raw producer_kafka_api_key)"\" >> $path_to_env_file

echo "env_producer_kafka_api_secret = \"$(terraform output -raw producer_kafka_api_secret)"\" >> $path_to_env_file

echo "env_topic_name = \"$(terraform output -raw topic_name)"\" >> $path_to_env_file
```

**How to package Python packages for AWS Lambda deployment** <br>
```
pip3 install --target /c/work/serverless-cloud-funtions-with-confluent-cloud/aws-lambda-producer-to-confluent-cloud/python/ confluent_kafka

pip3 install --target /c/work/serverless-cloud-funtions-with-confluent-cloud/aws-lambda-sink-connector-invocation/python/ requests
```

## Usage

**How to see the records in the CLI?** <br>
```confluent kafka topic consume -b temperature```

**How to invoke the functions from AWS CLI?** <br>
```export RANDOM_TEMPERATURE=$(( RANDOM % 10 ))``` <br>
```echo $RANDOM_TEMPERATURE``` <br>

```
aws lambda invoke \
    --function-name sjukic_Producer_to_Confluent_Cloud_Lambda_Function \
    --payload '{"temperature_guess":"'"${RANDOM_TEMPERATURE}"'"}' \
    response.json
``` 

Example value:

```
aws lambda invoke \
    --function-name sjukic_Producer_to_Confluent_Cloud_Lambda_Function \
    --payload '{"temperature_guess":"25.5"}' \
    response.json
```

**How to delete the function?** <br>
```aws lambda delete-function --function-name Producer_to_Confluent_Cloud_Lambda_Function``` <br>
```aws lambda delete-function --function-name Connector_Sink_Lambda_Function```

