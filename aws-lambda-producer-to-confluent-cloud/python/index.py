#!/usr/bin/env python
#
# how to execute locally using Python 3.x:
# $ python3 -m venv cf_produce
# $ source cf_produce/bin/activate
# $ pip3 install confluent_kafka
# $ echo "lambda_handler(0,0)" >> index.py
# $ python3 -B index.py
# $ deactivate
# $ rm -rf cf_produce
#
# how to package for lambda deployment
# $ pip3 install --target ./ confluent_kafka

import uuid
import json
import logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

from env import *

from confluent_kafka import Producer, Consumer, KafkaError, KafkaException

def lambda_handler(event, context):
    def error_cb(err):
        print("Client error: {}".format(err))
        if err.code() == KafkaError._ALL_BROKERS_DOWN or \
        err.code() == KafkaError._AUTHENTICATION:
            # Any exception raised from this callback will be re-raised from the
            # triggering flush() or poll() call.
            raise KafkaException(err)


    # Create producer
    p = Producer({
        'bootstrap.servers': env_cluster_bootstrap_endpoint,
        'sasl.mechanism': 'PLAIN',
        'security.protocol': 'SASL_SSL',
        'sasl.username': env_producer_kafka_api_key,
        'sasl.password': env_producer_kafka_api_secret,
        'error_cb': error_cb,
    })

    def acked(err, msg):
        """Delivery report callback called (from flush()) on successful or failed delivery of the message."""
        if err is not None:
            logger.info('Failed to deliver message: {}'.format(err.str()))
        else:
            logger.info('Produced to topic: [{}] partition:[{}] offset: [{}]'.format(msg.topic(), msg.partition(), msg.offset()))
            logger.info(event)

    # Produce message: this is an asynchronous operation.
    # Upon successful or permanently failed delivery to the broker the
    # callback will be called to propagate the produce result.
    # The delivery callback is triggered from poll() or flush().
    # For long running
    # produce loops it is recommended to call poll() to serve these
    # delivery report callbacks.
    p.produce(env_topic_name, key="key", value= json.dumps(event), callback=acked)

    # Trigger delivery report callbacks from previous produce calls.
    p.poll(0)

    # flush() is typically called when the producer is done sending messages to wait
    # for outstanding messages to be transmitted to the broker and delivery report
    # callbacks to get called. For continous producing you should call p.poll(0)
    # after each produce() call to trigger delivery report callbacks.
    p.flush(10)