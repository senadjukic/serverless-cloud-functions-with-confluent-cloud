variable "confluent_cloud_api_key" {
  description = "Confluent Cloud API Key (also referred as Cloud API ID)"
  type        = string
}

variable "confluent_cloud_api_secret" {
  description = "Confluent Cloud API Secret"
  type        = string
  sensitive   = true
}

variable "environment_name" {
  description = "Name of the Confluent Cloud environment"
  type        = string
}

variable "cluster_name" {
  description = "Name of the Confluent Cloud cluster in the environment"
  type        = string
}

variable "topic_name" {
  description = "Name of the topic on the cluster"
  type        = string
}

variable "aws_access_key_id" {
  description = "AWS Access Key ID"
  type        = string
  sensitive   = true
}

variable "aws_secret_access_key" {
  description = "AWS Secret Access Key"
  type        = string
  sensitive   = true
}

variable "lambda_sink_function_name" {
  description = "Name of the Lambda function to be invoked"
  type        = string
}




