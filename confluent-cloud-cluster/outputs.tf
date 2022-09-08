output "environment_id" {
  value = confluent_environment.environment.id
  sensitive = true
}

output "cluster_id" {
  value = confluent_kafka_cluster.basic.id
  sensitive = true
}

output "cluster_bootstrap_endpoint" {
  value = confluent_kafka_cluster.basic.bootstrap_endpoint
  sensitive = true
}

output "topic_name" {
  value = confluent_kafka_topic.cf-topic.topic_name
  sensitive = true
}

output "cluster_manager_id" {
  value = confluent_service_account.cluster-manager.id
  sensitive = true
}

output "cluster_manager_kafka_api_key" {
  value = confluent_api_key.cluster-manager-kafka-api-key.id
  sensitive = true
}

output "cluster_manager_kafka_api_secret" {
  value = confluent_api_key.cluster-manager-kafka-api-key.secret
  sensitive = true
}

output "producer_id" {
  value = confluent_service_account.cf-producer.id
  sensitive = true
}

output "producer_kafka_api_key" {
  value = confluent_api_key.cf-producer-kafka-api-key.id
  sensitive = true
}

output "producer_kafka_api_secret" {
  value = confluent_api_key.cf-producer-kafka-api-key.secret
  sensitive = true
}

output "consumer_id" {
  value = confluent_service_account.cf-consumer.id
  sensitive = true
}

output "consumer_kafka_api_key" {
  value = confluent_api_key.cf-consumer-kafka-api-key.id
  sensitive = true
}

output "consumer_kafka_api_secret" {
  value = confluent_api_key.cf-consumer-kafka-api-key.secret
  sensitive = true
}

output "resource-ids" {
  value = <<-EOT
  Environment ID:   ${confluent_environment.environment.id}
  Kafka Cluster ID: ${confluent_kafka_cluster.basic.id}
  Kafka topic name: ${confluent_kafka_topic.cf-topic.topic_name}

  Service Accounts and their Kafka API Keys (API Keys inherit the permissions granted to the owner):
  ${confluent_service_account.cluster-manager.display_name}:                     ${confluent_service_account.cluster-manager.id}
  ${confluent_service_account.cluster-manager.display_name}'s Kafka API Key:     "${confluent_api_key.cluster-manager-kafka-api-key.id}"
  ${confluent_service_account.cluster-manager.display_name}'s Kafka API Secret:  "${confluent_api_key.cluster-manager-kafka-api-key.secret}"

  ${confluent_service_account.cf-producer.display_name}:                    ${confluent_service_account.cf-producer.id}
  ${confluent_service_account.cf-producer.display_name}'s Kafka API Key:    "${confluent_api_key.cf-producer-kafka-api-key.id}"
  ${confluent_service_account.cf-producer.display_name}'s Kafka API Secret: "${confluent_api_key.cf-producer-kafka-api-key.secret}"

  ${confluent_service_account.cf-consumer.display_name}:                    ${confluent_service_account.cf-consumer.id}
  ${confluent_service_account.cf-consumer.display_name}'s Kafka API Key:    "${confluent_api_key.cf-consumer-kafka-api-key.id}"
  ${confluent_service_account.cf-consumer.display_name}'s Kafka API Secret: "${confluent_api_key.cf-consumer-kafka-api-key.secret}"

  In order to use the Confluent CLI v2 to produce and consume messages from topic '${confluent_kafka_topic.cf-topic.topic_name}' using Kafka API Keys
  of ${confluent_service_account.cf-producer.display_name} and ${confluent_service_account.cf-consumer.display_name} service accounts
  run the following commands:

  # 1. Log in to Confluent Cloud
  $ confluent login

  # 2. Produce key-value records to topic '${confluent_kafka_topic.cf-topic.topic_name}' by using ${confluent_service_account.cf-producer.display_name}'s Kafka API Key
  $ confluent kafka topic produce ${confluent_kafka_topic.cf-topic.topic_name} --environment ${confluent_environment.environment.id} --cluster ${confluent_kafka_cluster.basic.id} --api-key "${confluent_api_key.cf-producer-kafka-api-key.id}" --api-secret "${confluent_api_key.cf-producer-kafka-api-key.secret}"
  # Enter a few records and then press 'Ctrl-C' when you're done.
  # Sample record:
  # {"temperature_guess":"20.0"}

  # 3. Consume records from topic '${confluent_kafka_topic.cf-topic.topic_name}' by using ${confluent_service_account.cf-consumer.display_name}'s Kafka API Key
  $ confluent kafka topic consume ${confluent_kafka_topic.cf-topic.topic_name} --from-beginning --environment ${confluent_environment.environment.id} --cluster ${confluent_kafka_cluster.basic.id} --api-key "${confluent_api_key.cf-consumer-kafka-api-key.id}" --api-secret "${confluent_api_key.cf-consumer-kafka-api-key.secret}"
  # When you are done, press 'Ctrl-C'.
  EOT

  sensitive = true
}
