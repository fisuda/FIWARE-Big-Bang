#!/bin/bash

# MIT License
#
# Copyright (c) 2021 Kazuhito Suda
#
# This file is part of FIWARE Big Bang
#
# https://github.com/lets-fiware/FIWARE-Big-Bang
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

set -ue

if [ -d ./data ]; then
  sudo /usr/local/bin/docker-compose up -d --build
  exit
fi

if [ $# -eq 0 ] || [ $# -ge 3 ]; then
  echo "$0 DOMAIN_NAME [GLOBAL_IP_ADDRESS]"
  exit 1
fi

DOMAIN_NAME=$1
IP_ADDRESS=

if [ $# -ge 2 ]; then
  IP_ADDRESS=$2
fi

if [ ! -e ./config.sh ]; then
  echo "config.sh file not found"
  exit 1
fi

. ./config.sh

for NAME in KEYROCK ORION
do
  eval VAL=\"\$$NAME\"
  if [ "$VAL" = "" ]; then
      echo "${NAME} is empty"
      exit 1
  fi
done

if [ -z "${FIREWALL}" ]; then
  FIREWALL=false
fi

export FIREWALL

SETUP_DIR=./setup
${SETUP_DIR}/prepare.sh

if [ -z "${IDM_ADMIN_EMAIL_NAME}" ]; then
  IDM_ADMIN_EMAIL_NAME=admin
fi

if [ -z "${IDM_ADMIN_PASS}" ]; then
  IDM_ADMIN_PASS=$(pwgen -s 16 1)
fi

if [ -z "${CERT_EMAIL}" ]; then
  CERT_EMAIL=${IDM_ADMIN_EMAIL_NAME}@${DOMAIN_NAME}
fi

if [ -z "${CERT_REVOKE}" ]; then
  CERT_REVOKE=false
fi

if [ -z "${LOGGING}" ]; then
  LOGGING=true
fi

DATA_DIR=./data
CERT_DIR=$(pwd)/data/cert
CONFIG_DIR=./config

DOCKER_COMPOSE=/usr/local/bin/docker-compose
CERTBOT=certbot/certbot:v1.18.0

if [ "${WIRECLOUD}" = "" ]; then
  NGSIPROXY=""
fi

if [ "${WIRECLOUD}" != "" -a "${NGSIPROXY}" = "" ]; then
  echo "error: NGSIPROXY is empty"
  exit 1
fi

cat <<EOF >> .env
DATA_DIR=${DATA_DIR}
CERT_DIR=${CERT_DIR}
CONFIG_DIR=${CONFIG_DIR}
NGINX_SITES=${CONFIG_DIR}/nginx/sites-enable
SETUP_DIR=${SETUP_DIR}
TEMPLEATE=${SETUP_DIR}/templeate

DOMAIN_NAME=${DOMAIN_NAME}
IP_ADDRESS=${IP_ADDRESS}

DOCKER_COMPOSE=${DOCKER_COMPOSE}
CERTBOT=${CERTBOT}

FIREWALL=${FIREWALL}
LOGGING=${LOGGING}

CERT_EMAIL=${CERT_EMAIL}
CERT_REVOKE=${CERT_REVOKE}

IDM_ADMIN_EMAIL=${IDM_ADMIN_EMAIL_NAME}@${DOMAIN_NAME}
IDM_ADMIN_PASS=${IDM_ADMIN_PASS}

EOF

for NAME in KEYROCK ORION COMET WIRECLOUD NGSIPROXY NODE_RED GRAFANA QUANTUMLEAP
do
  eval VAL=\"\$$NAME\"
  if [ -n "$VAL" ]; then
      eval echo ${NAME}=\"\$${NAME}.${DOMAIN_NAME}\" >> .env
  else
      echo ${NAME}= >> .env
  fi 
done

echo -e -n "\n" >> .env

${SETUP_DIR}/setup.sh

. ./.env

echo "*** Setup has been completed ***"
echo "IDM: https://${KEYROCK}"
echo "User: ${IDM_ADMIN_EMAIL}"
echo "Password: ${IDM_ADMIN_PASS}"
echo "Please see the .env file for details."
