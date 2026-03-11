#!/usr/bin/env bash

export HOMIE_MQTT_URI="mqtt://synology.home"
export HOMIE_MQTT_ID="homie45-bridge-123"
export HOMIE_DOMAIN4="homie"
export HOMIE_DOMAIN5="homie"
export HOMIE_DEVICE_ID="homie45bridge"
export HOMIE_SUBSCRIBE_DELAY=1000
# export HOMIE_LOG_LOGLEVEL="debug"
export HOMIE_LOG_LOGLEVEL="info"



# podman build --no-cache --progress plain --tag tieske/homie45bridge:dev .
# podman image push tieske/homie45bridge:dev

podman run -it --rm --init --name=homie45 \
    -e HOMIE_MQTT_URI \
    -e HOMIE_MQTT_ID \
    -e HOMIE_DOMAIN4 \
    -e HOMIE_DOMAIN5 \
    -e HOMIE_DEVICE_ID \
    -e HOMIE_SUBSCRIBE_DELAY \
    -e HOMIE_LOG_LOGLEVEL \
    tieske/homie45bridge:dev
