# This script does:
# - create a Elastic Container Registry
# - publish the REST Proxy image to ECR
# - define a Task Execution Policy
# - create a security group
# - create a ECS cluster
# - deploy a REST Proxy that is connected to Confluent Cloud
# - test if REST Proxy works as expected

# MODIFY: add your variables
cat > secret-vars.sh <<EOF
export AWS_ACCESS_KEY_ID=
export AWS_SECRET_ACCESS_KEY=
export CC_BOOTSTRAP_SERVERS="pkc-xxxx.eu-central-1.aws.confluent.cloud:9092"
export CLUSTER_MANAGER_KAFKA_API_KEY="xxxxxxxxxxxxxxx"
export CLUSTER_MANAGER_KAFKA_SECRET="xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
export region="eu-central-1"
export image_version=7.2.1
export ecs_cluster_name=rest-proxy-cluster
export ecs_ecr_repo_name=ecs-rest-proxy
export owner_email=xxxx@example.io
EOF

# use vars from file
source secret-vars.sh

# create ECR repo
aws ecr create-repository \
--repository-name $ecs_ecr_repo_name \
--tags Key=owner_email,Value=$owner_email

# docker login into ecr repo
eval "$(aws ecr get-login --region $region --no-include-email)"

# tag image before push
export ecr_repo=$(aws ecr describe-repositories --query "repositories[].[repositoryUri]" --output text | grep $ecs_ecr_repo_name)
docker tag confluentinc/cp-kafka-rest:$image_version $ecr_repo:$image_version

# push rest image to ecr
docker push $ecr_repo:$image_version

# create policy task execition policy
cat > task-execution-assume-role.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "",
      "Effect": "Allow",
      "Principal": {
        "Service": "ecs-tasks.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF

aws iam --region $region attach-role-policy --role-name ecsTaskExecutionRole --policy-arn arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy
aws iam --region $region create-role --role-name ecsTaskExecutionRole --assume-role-policy-document file://task-execution-assume-role.json --tags Key=owner_email,Value=$owner_email

# create cluster config
ecs-cli configure --cluster $ecs_cluster_name --default-launch-type FARGATE --config-name $ecs_cluster_name --region $region

# create cli profile
ecs-cli configure profile --access-key $AWS_ACCESS_KEY_ID --secret-key $AWS_SECRET_ACCESS_KEY --profile-name ecs-profile

# create ecs cluster
ecs-cli up --cluster-config  $ecs_cluster_name --ecs-profile ecs-profile --force  > subnets.txt 

export vpc_id=$(awk -F: '/VPC created: / { print substr($2,2);}' subnets.txt)
export subnet_1=$(awk -F: '/Subnet created: / { print substr($2,2);}' subnets.txt | head -1)
export subnet_2=$(awk -F: '/Subnet created: / { print substr($2,2);}' subnets.txt | tail -1)

# get security group
export security_group_id=$(aws ec2 describe-security-groups --filters Name=vpc-id,Values=$vpc_id --region $region | jq '.[] | .[].GroupId' | sed s/'"'/''/g)

# open port for public (not recommended in production, rather use --source-group or fixed IP for ingress of the invoking service)
aws ec2 authorize-security-group-ingress --group-id $security_group_id --protocol tcp --port 8082 --cidr 0.0.0.0/0 --region $region

# Alternative: open port for your ip 
# export my_ip=$(curl ifconfig.me/ip)
# aws ec2 authorize-security-group-ingress --group-id $security_group_id --protocol tcp --port 8082 --cidr $my_ip/24 --region $region

# verify security group ingress
aws ec2 describe-security-groups --group-ids $security_group_id

# create docker-compose script
cat > docker-compose.yml <<EOF
---
version: '2'
services:
  rest-proxy:
    image: $ecr_repo:$image_version
    ports:
      - 8082:8082
    environment:
      KAFKA_REST_HOST_NAME: rest-proxy
      KAFKA_REST_LISTENERS: "http://0.0.0.0:8082"
      # KAFKA_REST_SCHEMA_REGISTRY_URL: $SCHEMA_REGISTRY_URL
      # KAFKA_REST_CLIENT_BASIC_AUTH_CREDENTIALS_SOURCE: $BASIC_AUTH_CREDENTIALS_SOURCE
      # KAFKA_REST_CLIENT_SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO: $SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO
      KAFKA_REST_BOOTSTRAP_SERVERS: "$CC_BOOTSTRAP_SERVERS"
      KAFKA_REST_SECURITY_PROTOCOL: "SASL_SSL"
      KAFKA_REST_SASL_JAAS_CONFIG: org.apache.kafka.common.security.plain.PlainLoginModule required username="$CLUSTER_MANAGER_KAFKA_API_KEY" password="$CLUSTER_MANAGER_KAFKA_SECRET";
      KAFKA_REST_SASL_MECHANISM: "PLAIN"
      KAFKA_REST_CLIENT_BOOTSTRAP_SERVERS: "$CC_BOOTSTRAP_SERVERS"
      KAFKA_REST_CLIENT_SECURITY_PROTOCOL: "SASL_SSL"
      KAFKA_REST_CLIENT_SASL_JAAS_CONFIG: org.apache.kafka.common.security.plain.PlainLoginModule required username="$CLUSTER_MANAGER_KAFKA_API_KEY" password="$CLUSTER_MANAGER_KAFKA_SECRET";
      KAFKA_REST_CLIENT_SASL_MECHANISM: "PLAIN"
EOF

# ecs-params.yml
cat > ecs-params.yml <<EOF
version: 1
task_definition:
  task_execution_role: ecsTaskExecutionRole
  ecs_network_mode: awsvpc
  os_family: Linux
  task_size:
    mem_limit: 0.5GB
    cpu_limit: 256
run_params:
  network_configuration:
    awsvpc_configuration:
      subnets:
        - "$subnet_1"
        - "$subnet_2"
      security_groups:
        - "$security_group_id"
      assign_public_ip: ENABLED
EOF

# deploy docker-compose to cluster
ecs-cli compose --project-name $ecs_cluster_name service up --create-log-groups --cluster-config $ecs_cluster_name --ecs-profile ecs-profile

# check if container is running
ecs-cli compose --project-name  $ecs_cluster_name service ps --cluster-config $ecs_cluster_name --ecs-profile ecs-profile

# get public IP and port
export ecs_task_public_ip_with_port=$(ecs-cli compose --project-name  $ecs_cluster_name service ps --cluster-config $ecs_cluster_name --ecs-profile ecs-profile | awk '/tcp/ { print $3;}' | sed 's/-.*//')

# test: get Cluster ID
curl -X GET "http://${ecs_task_public_ip_with_port}/v3/clusters/" | jq -r ".data[0].cluster_id"

# test: create Topic
export KAFKA_CLUSTER_ID=$(curl -X GET "http://${ecs_task_public_ip_with_port}/v3/clusters/" | jq -r ".data[0].cluster_id")
curl -X POST \
     -H "Content-Type: application/json" \
     -d "{\"topic_name\":\"created-by-rest-proxy\",\"partitions_count\":6,\"configs\":[]}" \
     "http://${ecs_task_public_ip_with_port}/v3/clusters/${KAFKA_CLUSTER_ID}/topics" | jq .

# test: produce records
curl -X POST \
     -H "Content-Type: application/vnd.kafka.json.v2+json" \
     -H "Accept: application/vnd.kafka.v2+json" \
     --data '{"records":[{"key":"alice","value":{"count":0}},{"key":"alice","value":{"count":1}},{"key":"alice","value":{"count":2}}]}' \
     "http://${ecs_task_public_ip_with_port}/topics/created-by-rest-proxy" | jq .

