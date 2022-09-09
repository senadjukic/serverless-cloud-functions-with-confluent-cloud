# Serverless Cloud Functions with Confluent Cloud

## Description
This demo demonstrates how cloud functions can produce and consume from Confluent Cloud. The current examples are with AWS Lambda and are baked by Terraform.

## Prerequisites
1. Check if you have a Confluent Cloud Account
2. Create Confluent Cloud API keys <br> https://registry.terraform.io/providers/confluentinc/confluent/latest/docs/guides/sample-project#create-a-cloud-api-key
3. Check if you have Terraform installed `terraform -version` <br> https://learn.hashicorp.com/tutorials/terraform/install-cli#install-terraform
4. Check if you have the Confluent CLI installed `confluent version` <br> https://docs.confluent.io/confluent-cli/current/install.html
5. Check if you have the AWS CLI installed `aws --version` <br> https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html
6. Optional: Create a Openweathermap Key for the OneCall API https://openweathermap.org/api

## Deployment
1. Clone the repo and enter into the directory
``` 
git clone https://github.com/senadjukic/serverless-cloud-functions-with-confluent-cloud.git \
&& cd serverless-cloud-functions-with-confluent-cloud 
```

2. Create the terraform.tfvars for the cluster creation with your credentials

```
cat <<EOF >>$PWD/serverless-cloud-funtions-with-confluent-cloud/confluent-cloud-cluster/terraform.tfvars
confluent_cloud_api_key = "(see Confluent Cloud settings)"
confluent_cloud_api_secret = "(see Confluent Cloud settings)"
environment_name = "cloud-functions"
cluster_name = "cf-basic"
topic_name = "temperature"
aws_access_key_id = "(see AWS IAM)"
aws_secret_access_key = "(see AWS IAM)"
lambda_sink_function_name = "Connector_Sink_Lambda_Function"
EOF
```

3. `terraform -chdir=confluent-cloud-cluster/ init`
4. `terraform -chdir=confluent-cloud-cluster/ apply -auto-approve`
5. Create the input file for the Python variables

```
cat <<EOF >>$PWD/serverless-cloud-funtions-with-confluent-cloud/aws-lambda-producer-to-confluent-cloud/python/env.py
env_topic_name = "$(terraform output -raw topic_name)"
env_cluster_bootstrap_endpoint = "$(terraform output -raw cluster_bootstrap_endpoint | cut -c 12-)"
env_producer_kafka_api_key = "$(terraform output -raw producer_kafka_api_key)"
env_producer_kafka_api_secret = "$(terraform output -raw producer_kafka_api_secret)"
env_topic_name = "$(terraform output -raw topic_name)"
EOF
```

6. Package Python packages for AWS Lambda deployment
```
pip3 install --target $PWD/serverless-cloud-funtions-with-confluent-cloud/aws-lambda-producer-to-confluent-cloud/python/ confluent_kafka

pip3 install --target $PWD/serverless-cloud-funtions-with-confluent-cloud/aws-lambda-sink-connector-invocation/python/ requests
```
7. Optional: Add your Openweather API key
`echo 'env_openweather_key = "(your openweather key)"' > $PWD/serverless-cloud-functions-with-confluent-cloud/aws-lambda-sink-connector-invocation/python/env.py`

8. `terraform -chdir=aws-lambda-producer-to-confluent-cloud/ init`
9. `terraform -chdir=aws-lambda-producer-to-confluent-cloud/ apply -auto-approve`

10. `terraform -chdir=aws-lambda-sink-connector-invocation/ init`
11. `terraform -chdir=aws-lambda-sink-connector-invocation/ apply -auto-approve`

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
    /dev/stdout | cat
``` 

Example value:

```
aws lambda invoke \
    --function-name sjukic_Producer_to_Confluent_Cloud_Lambda_Function \
    --payload '{"temperature_guess":"25.5"}' \
    /dev/stdout | cat
```

## Deletion

Via AWS CLI:
```
aws lambda delete-function --function-name Producer_to_Confluent_Cloud_Lambda_Function

aws lambda delete-function --function-name Connector_Sink_Lambda_Function

Via Terraform:

```
terraform -chdir=aws-lambda-producer-to-confluent-cloud/ apply -auto-approve -destroy

terraform -chdir=aws-lambda-sink-connector-invocation/ apply -auto-approve -destroy

terraform -chdir=confluent-cloud-cluster/ apply -auto-approve -destroy
```

