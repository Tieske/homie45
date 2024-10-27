#!/usr/bin/env bash

export HOMIE_MQTT_URI="mqtt://synology"
export HOMIE_MQTT_ID="homie45-bridge-123"
export HOMIE_DOMAIN4="homie"
export HOMIE_DOMAIN5="homie"
export HOMIE_SUBSCRIBE_DELAY=1000
#export HOMIE_LOG_LOGGER="rsyslog"
export HOMIE_LOG_LOGLEVEL="info"
#export HOMIE_LOG_LOGPATTERN="%message (%source)"
export HOMIE_LOG_RFC="rfc5424"
export HOMIE_LOG_MAXSIZE="8000"
export HOMIE_LOG_HOSTNAME="synology.local"
export HOMIE_LOG_PORT="8514"
export HOMIE_LOG_PROTOCOL="tcp"
export HOMIE_LOG_IDENT="homie45bridge"


LUA_PATH="./src/?/init.lua;./src/?.lua;$LUA_PATH"
lua bin/homie45bridge.lua

# docker run -it --rm \
#     -e NETATMO_CLIENT_ID \
#     -e NETATMO_CLIENT_SECRET \
#     -e NETATMO_USERNAME \
#     -e NETATMO_PASSWORD \
#     -e NETATMO_POLL_INTERVAL \
#     -e HOMIE_DOMAIN \
#     -e HOMIE_MQTT_URI \
#     -e HOMIE_DEVICE_ID \
#     -e HOMIE_DEVICE_NAME \
#     -e HOMIE_LOG_LOGGER \
#     -e HOMIE_LOG_LOGLEVEL \
#     -e HOMIE_LOG_LOGPATTERN \
#     -e HOMIE_LOG_RFC \
#     -e HOMIE_LOG_MAXSIZE \
#     -e HOMIE_LOG_HOSTNAME \
#     -e HOMIE_LOG_PORT \
#     -e HOMIE_LOG_PROTOCOL \
#     -e HOMIE_LOG_IDENT \
#     tieske/homie-netatmo:dev
