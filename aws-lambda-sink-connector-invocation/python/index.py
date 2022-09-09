#!/usr/bin/env python
#
# how to execute locally using Python 3.x:
# $ python3 -m venv cf_sink_connector
# $ source cf_sink_connector/bin/activate
# $ pip3 install requests
# $ echo "lambda_handler(0,0)" >> index.py
# $ python3 -B index.py
# $ deactivate
# $ rm -rf cf_sink_connector
#
# how to package for lambda deployment
# $ pip3 install --target ./ requests

import uuid

from env import *

import math
import requests
import json

def lambda_handler(event, context):

    # Show input from event
    print("Event")
    print(event)

    print("Guessed Temperature Value:")
    record = event[0]['payload']['value'].replace('{temperature_guess=', '').replace('}', '')
    print(record)
    
    # Go for real temperature of your city: https://www.latlong.net
    # Example: Zurich
    if env_openweather_key:
        lat = "47.376888"
        lon = "8.541694"
        url = "https://api.openweathermap.org/data/2.5/onecall?lat=%s&lon=%s&appid=%s&units=metric" % (lat, lon, env_openweather_key)
        response = requests.get(url)
        data = json.loads(response.text)
        zurich_real_temperature = data["current"]["temp"]

        print("Temperature in Zurich from the OpenWeather API:")
        print(zurich_real_temperature)

        print("Difference from Zurich's real temperature to guessed temperature:")
        diff = math.fabs(zurich_real_temperature - float(record))
        print(diff)

    else:
        print("No Openweather key found to calculate difference between guessed and real temperature.")