#!/usr/bin/env bash

export HOMIE_MQTT_URI="mqtt://synology"
export HOMIE_MQTT_ID="homie45-bridge-123"
export HOMIE_DOMAIN4="homie/"
export HOMIE_DOMAIN5="homie5/"
export HOMIE_LOG_LOGLEVEL="info"



docker build --no-cache --progress plain --tag tieske/homie45bridge:dev .
# docker image push tieske/homie45bridge:dev

docker run -it --rm \
    -e HOMIE_MQTT_URI \
    -e HOMIE_MQTT_ID \
    -e HOMIE_DOMAIN4 \
    -e HOMIE_DOMAIN5 \
    -e HOMIE_LOG_LOGLEVEL \
    tieske/homie45bridge:dev
