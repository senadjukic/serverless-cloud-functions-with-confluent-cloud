terraform {
  required_providers {
    confluent = {
      source  = "confluentinc/confluent"
      version = "1.0.0"
    }
  }
}

provider "confluent" {
  cloud_api_key    = var.confluent_cloud_api_key
  cloud_api_secret = var.confluent_cloud_api_secret
}

resource "confluent_environment" "environment" {
  display_name = var.environment_name
}

# Update the config to use a cloud provider and region of your choice.
# https://registry.terraform.io/providers/confluentinc/confluent/latest/docs/resources/confluent_kafka_cluster
# AWS Frankfurt: eu-central-1
# Azure Frankfurt: ger-west-central
# Azure Zurich: swz-north
resource "confluent_kafka_cluster" "basic" {
  display_name = var.cluster_name
  availability = "SINGLE_ZONE"
  cloud        = "AWS"
  region       = "eu-central-1"
  basic {}
  environment {
    id = confluent_environment.environment.id
  }
}

// 'cluster-manager' service account is required in this configuration to create new topic and grant ACLs
// to 'cf-producer' and 'cf-consumer' service accounts.
resource "confluent_service_account" "cluster-manager" {
  display_name = "cluster-manager"
  description  = "Service account to manage Kafka cluster"
}

resource "confluent_role_binding" "cluster-manager-rbac" {
  principal   = "User:${confluent_service_account.cluster-manager.id}"
  role_name   = "CloudClusterAdmin"
  crn_pattern = confluent_kafka_cluster.basic.rbac_crn
}

resource "confluent_api_key" "cluster-manager-kafka-api-key" {
  display_name = "cluster-manager-kafka-api-key"
  description  = "Kafka API Key that is owned by 'cluster-manager' service account"
  owner {
    id          = confluent_service_account.cluster-manager.id
    api_version = confluent_service_account.cluster-manager.api_version
    kind        = confluent_service_account.cluster-manager.kind
  }

  managed_resource {
    id          = confluent_kafka_cluster.basic.id
    api_version = confluent_kafka_cluster.basic.api_version
    kind        = confluent_kafka_cluster.basic.kind

    environment {
      id = confluent_environment.environment.id
    }
  }

  # The goal is to ensure that confluent_role_binding.cluster-manager-rbac is created before
  # confluent_api_key.cluster-manager-kafka-api-key is used to create instances of
  # confluent_kafka_topic, confluent_kafka_acl resources.

  # 'depends_on' meta-argument is specified in confluent_api_key.cluster-manager-kafka-api-key to avoid having
  # multiple copies of this definition in the configuration which would happen if we specify it in
  # confluent_kafka_topic, confluent_kafka_acl resources instead.
  depends_on = [
    confluent_role_binding.cluster-manager-rbac
  ]
}

resource "confluent_kafka_topic" "cf-topic" {
  kafka_cluster {
    id = confluent_kafka_cluster.basic.id
  }
  topic_name    = var.topic_name
  rest_endpoint = confluent_kafka_cluster.basic.rest_endpoint
  credentials {
    key    = confluent_api_key.cluster-manager-kafka-api-key.id
    secret = confluent_api_key.cluster-manager-kafka-api-key.secret
  }
}

resource "confluent_service_account" "cf-consumer" {
  display_name = "cf-consumer"
  description  = "Service account to consume from new topic of Kafka cluster"
}

resource "confluent_api_key" "cf-consumer-kafka-api-key" {
  display_name = "cf-consumer-kafka-api-key"
  description  = "Kafka API Key that is owned by 'cf-consumer' service account"
  owner {
    id          = confluent_service_account.cf-consumer.id
    api_version = confluent_service_account.cf-consumer.api_version
    kind        = confluent_service_account.cf-consumer.kind
  }

  managed_resource {
    id          = confluent_kafka_cluster.basic.id
    api_version = confluent_kafka_cluster.basic.api_version
    kind        = confluent_kafka_cluster.basic.kind

    environment {
      id = confluent_environment.environment.id
    }
  }
}

resource "confluent_kafka_acl" "cf-producer-write-on-topic" {
  kafka_cluster {
    id = confluent_kafka_cluster.basic.id
  }
  resource_type = "TOPIC"
  resource_name = confluent_kafka_topic.cf-topic.topic_name
  pattern_type  = "LITERAL"
  principal     = "User:${confluent_service_account.cf-producer.id}"
  host          = "*"
  operation     = "WRITE"
  permission    = "ALLOW"
  rest_endpoint = confluent_kafka_cluster.basic.rest_endpoint
  credentials {
    key    = confluent_api_key.cluster-manager-kafka-api-key.id
    secret = confluent_api_key.cluster-manager-kafka-api-key.secret
  }
}

resource "confluent_service_account" "cf-producer" {
  display_name = "cf-producer"
  description  = "Service account to produce to new topic of Kafka cluster"
}

resource "confluent_api_key" "cf-producer-kafka-api-key" {
  display_name = "cf-producer-kafka-api-key"
  description  = "Kafka API Key that is owned by 'cf-producer' service account"
  owner {
    id          = confluent_service_account.cf-producer.id
    api_version = confluent_service_account.cf-producer.api_version
    kind        = confluent_service_account.cf-producer.kind
  }

  managed_resource {
    id          = confluent_kafka_cluster.basic.id
    api_version = confluent_kafka_cluster.basic.api_version
    kind        = confluent_kafka_cluster.basic.kind

    environment {
      id = confluent_environment.environment.id
    }
  }
}

// Note to consume from a topic, the principal of the consumer ('cf-consumer' service account)
// needs to be authorized to perform 'READ' operation on both Topic and Group resources:
// confluent_kafka_acl.cf-consumer-read-on-topic, confluent_kafka_acl.cf-consumer-read-on-group.
// https://docs.confluent.io/platform/current/kafka/authorization.html#using-acls
resource "confluent_kafka_acl" "cf-consumer-read-on-topic" {
  kafka_cluster {
    id = confluent_kafka_cluster.basic.id
  }
  resource_type = "TOPIC"
  resource_name = confluent_kafka_topic.cf-topic.topic_name
  pattern_type  = "LITERAL"
  principal     = "User:${confluent_service_account.cf-consumer.id}"
  host          = "*"
  operation     = "READ"
  permission    = "ALLOW"
  rest_endpoint = confluent_kafka_cluster.basic.rest_endpoint
  credentials {
    key    = confluent_api_key.cluster-manager-kafka-api-key.id
    secret = confluent_api_key.cluster-manager-kafka-api-key.secret
  }
}

resource "confluent_kafka_acl" "cf-consumer-read-on-group" {
  kafka_cluster {
    id = confluent_kafka_cluster.basic.id
  }
  resource_type = "GROUP"
  // The existing values of resource_name, pattern_type attributes are set up to match Confluent CLI's default consumer group ID ("confluent_cli_consumer_<uuid>").
  // https://docs.confluent.io/confluent-cli/current/command-reference/kafka/topic/confluent_kafka_topic_consume.html
  // Update the values of resource_name, pattern_type attributes to match your target consumer group ID.
  // https://docs.confluent.io/platform/current/kafka/authorization.html#prefixed-acls
  resource_name = "confluent_cli_consumer_"
  pattern_type  = "PREFIXED"
  principal     = "User:${confluent_service_account.cf-consumer.id}"
  host          = "*"
  operation     = "READ"
  permission    = "ALLOW"
  rest_endpoint = confluent_kafka_cluster.basic.rest_endpoint
  credentials {
    key    = confluent_api_key.cluster-manager-kafka-api-key.id
    secret = confluent_api_key.cluster-manager-kafka-api-key.secret
  }
}

// ------ remove from here if you don't need a connector ------

// Lambda Sink Connector Service Accounts and ACLs - 
resource "confluent_service_account" "cf-connector" {
  display_name = "cf-connector"
  description  = "Service account of Lambda Sink Connector to consume from 'cf-topic' topic of 'basic' Kafka cluster"
}


resource "confluent_kafka_acl" "cf-connector-describe-on-cluster" {
  kafka_cluster {
    id = confluent_kafka_cluster.basic.id
  }
  resource_type = "CLUSTER"
  resource_name = "kafka-cluster"
  pattern_type  = "LITERAL"
  principal     = "User:${confluent_service_account.cf-connector.id}"
  host          = "*"
  operation     = "DESCRIBE"
  permission    = "ALLOW"
  rest_endpoint = confluent_kafka_cluster.basic.rest_endpoint
  credentials {
    key    = confluent_api_key.cluster-manager-kafka-api-key.id
    secret = confluent_api_key.cluster-manager-kafka-api-key.secret
  }
}

resource "confluent_kafka_acl" "cf-connector-read-on-target-topic" {
  kafka_cluster {
    id = confluent_kafka_cluster.basic.id
  }
  resource_type = "TOPIC"
  resource_name = confluent_kafka_topic.cf-topic.topic_name
  pattern_type  = "LITERAL"
  principal     = "User:${confluent_service_account.cf-connector.id}"
  host          = "*"
  operation     = "READ"
  permission    = "ALLOW"
  rest_endpoint = confluent_kafka_cluster.basic.rest_endpoint
  credentials {
    key    = confluent_api_key.cluster-manager-kafka-api-key.id
    secret = confluent_api_key.cluster-manager-kafka-api-key.secret
  }
}

resource "confluent_kafka_acl" "cf-connector-create-on-dlq-lcc-topics" {
  kafka_cluster {
    id = confluent_kafka_cluster.basic.id
  }
  resource_type = "TOPIC"
  resource_name = "dlq-lcc"
  pattern_type  = "PREFIXED"
  principal     = "User:${confluent_service_account.cf-connector.id}"
  host          = "*"
  operation     = "CREATE"
  permission    = "ALLOW"
  rest_endpoint = confluent_kafka_cluster.basic.rest_endpoint
  credentials {
    key    = confluent_api_key.cluster-manager-kafka-api-key.id
    secret = confluent_api_key.cluster-manager-kafka-api-key.secret
  }
}

resource "confluent_kafka_acl" "cf-connector-write-on-dlq-lcc-topics" {
  kafka_cluster {
    id = confluent_kafka_cluster.basic.id
  }
  resource_type = "TOPIC"
  resource_name = "dlq-lcc"
  pattern_type  = "PREFIXED"
  principal     = "User:${confluent_service_account.cf-connector.id}"
  host          = "*"
  operation     = "WRITE"
  permission    = "ALLOW"
  rest_endpoint = confluent_kafka_cluster.basic.rest_endpoint
  credentials {
    key    = confluent_api_key.cluster-manager-kafka-api-key.id
    secret = confluent_api_key.cluster-manager-kafka-api-key.secret
  }
}

resource "confluent_kafka_acl" "cf-connector-create-on-success-lcc-topics" {
  kafka_cluster {
    id = confluent_kafka_cluster.basic.id
  }
  resource_type = "TOPIC"
  resource_name = "success-lcc"
  pattern_type  = "PREFIXED"
  principal     = "User:${confluent_service_account.cf-connector.id}"
  host          = "*"
  operation     = "CREATE"
  permission    = "ALLOW"
  rest_endpoint = confluent_kafka_cluster.basic.rest_endpoint
  credentials {
    key    = confluent_api_key.cluster-manager-kafka-api-key.id
    secret = confluent_api_key.cluster-manager-kafka-api-key.secret
  }
}

resource "confluent_kafka_acl" "cf-connector-write-on-success-lcc-topics" {
  kafka_cluster {
    id = confluent_kafka_cluster.basic.id
  }
  resource_type = "TOPIC"
  resource_name = "success-lcc"
  pattern_type  = "PREFIXED"
  principal     = "User:${confluent_service_account.cf-connector.id}"
  host          = "*"
  operation     = "WRITE"
  permission    = "ALLOW"
  rest_endpoint = confluent_kafka_cluster.basic.rest_endpoint
  credentials {
    key    = confluent_api_key.cluster-manager-kafka-api-key.id
    secret = confluent_api_key.cluster-manager-kafka-api-key.secret
  }
}

resource "confluent_kafka_acl" "cf-connector-create-on-error-lcc-topics" {
  kafka_cluster {
    id = confluent_kafka_cluster.basic.id
  }
  resource_type = "TOPIC"
  resource_name = "error-lcc"
  pattern_type  = "PREFIXED"
  principal     = "User:${confluent_service_account.cf-connector.id}"
  host          = "*"
  operation     = "CREATE"
  permission    = "ALLOW"
  rest_endpoint = confluent_kafka_cluster.basic.rest_endpoint
  credentials {
    key    = confluent_api_key.cluster-manager-kafka-api-key.id
    secret = confluent_api_key.cluster-manager-kafka-api-key.secret
  }
}

resource "confluent_kafka_acl" "cf-connector-write-on-error-lcc-topics" {
  kafka_cluster {
    id = confluent_kafka_cluster.basic.id
  }
  resource_type = "TOPIC"
  resource_name = "error-lcc"
  pattern_type  = "PREFIXED"
  principal     = "User:${confluent_service_account.cf-connector.id}"
  host          = "*"
  operation     = "WRITE"
  permission    = "ALLOW"
  rest_endpoint = confluent_kafka_cluster.basic.rest_endpoint
  credentials {
    key    = confluent_api_key.cluster-manager-kafka-api-key.id
    secret = confluent_api_key.cluster-manager-kafka-api-key.secret
  }
}

resource "confluent_kafka_acl" "cf-connector-read-on-connect-lcc-group" {
  kafka_cluster {
    id = confluent_kafka_cluster.basic.id
  }
  resource_type = "GROUP"
  resource_name = "connect-lcc"
  pattern_type  = "PREFIXED"
  principal     = "User:${confluent_service_account.cf-connector.id}"
  host          = "*"
  operation     = "READ"
  permission    = "ALLOW"
  rest_endpoint = confluent_kafka_cluster.basic.rest_endpoint
  credentials {
    key    = confluent_api_key.cluster-manager-kafka-api-key.id
    secret = confluent_api_key.cluster-manager-kafka-api-key.secret
  }
}

// Sink Connector
resource "confluent_connector" "lambda_sink" {
  environment {
    id = confluent_environment.environment.id
  }
  kafka_cluster {
    id = confluent_kafka_cluster.basic.id
  }

  config_sensitive = {
    "aws.access.key.id"     = var.aws_access_key_id
    "aws.secret.access.key" = var.aws_secret_access_key
  }

  config_nonsensitive = {
    "topics"                     = confluent_kafka_topic.cf-topic.topic_name
    "input.data.format"          = "JSON"
    "connector.class"            = "LambdaSink"
    "name"                       = "LambdaSinkConnector_0"
    "kafka.auth.mode"            = "SERVICE_ACCOUNT"
    "kafka.service.account.id"   = confluent_service_account.cf-connector.id
    "aws.lambda.function.name"   = var.lambda_sink_function_name,
    "aws.lambda.invocation.type" = "sync",
    "output.data.format"         = "JSON"
    "behavior.on.error"          = "fail",
    "tasks.max"                  = "1"
  }

  depends_on = [
    confluent_kafka_acl.cf-connector-describe-on-cluster,
    confluent_kafka_acl.cf-connector-read-on-target-topic,
    confluent_kafka_acl.cf-connector-create-on-dlq-lcc-topics,
    confluent_kafka_acl.cf-connector-write-on-dlq-lcc-topics,
    confluent_kafka_acl.cf-connector-create-on-success-lcc-topics,
    confluent_kafka_acl.cf-connector-write-on-success-lcc-topics,
    confluent_kafka_acl.cf-connector-create-on-error-lcc-topics,
    confluent_kafka_acl.cf-connector-write-on-error-lcc-topics,
    confluent_kafka_acl.cf-connector-read-on-connect-lcc-group,
  ]
}
