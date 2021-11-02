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

set -Ceuo pipefail

VERSION=0.6.0-next

#
# Syslog info
#
logging_info() {
  echo "setup: $1" 1>&2
  /usr/bin/logger -i -p "user.info" -t "FI-BB" "setup: $1"
}

#
# Syslog err
#
logging_err() {
  echo "setup: $1" 1>&2
  /usr/bin/logger -i -p "user.err" -t "FI-BB" "setup: $1"
}

#
# Setup logging step1
#
setup_logging_step1() {
  logging_info "${FUNCNAME[0]}"

  LOG_DIR=/var/log/fiware
  NGINX_LOG_DIR=${LOG_DIR}/nginx

  RSYSLOG_CONF=${WORK_DIR}/rsyslog.conf
  LOGROTATE_CONF=${WORK_DIR}/logrotate.conf

  if [ -d "${LOG_DIR}" ]; then
    ${SUDO} rm -fr "${LOG_DIR}"
  fi
  ${SUDO} mkdir "${LOG_DIR}"
  ${SUDO} mkdir "${NGINX_LOG_DIR}"
  if [ "${DISTRO}" = "Ubuntu" ]; then
    ${SUDO} chown syslog:adm "${LOG_DIR}"
  fi

  # FI-BB log
  echo "${LOG_DIR}/fi-bb.log" >> "${LOGROTATE_CONF}"
  cat <<EOF >> "${RSYSLOG_CONF}"
:syslogtag,contains,"FI-BB" ${LOG_DIR}/fi-bb.log
& stop

EOF

  ${SYSTEMCTL} restart rsyslog.service
}

#
# Check data direcotry
#
check_data_direcotry() {
  logging_info "${FUNCNAME[0]}"

  if [ -d ./data ]; then
    ${DOCKER_COMPOSE} up -d --build
    exit "${ERR_CODE}"
  fi
}

#
# Get config sh
#
get_config_sh() {
  logging_info "${FUNCNAME[0]}"

  if [ ! -e ./config.sh ]; then
    logging_err "config.sh file not found"
    exit "${ERR_CODE}"
  fi

  . ./config.sh

  if $FIBB_TEST; then
    MOCK_PATH="${FIBB_TEST_MOCK_PATH-""}"
    IMAGE_CERTBOT="letsfiware/certmock:0.2.0"
  fi
}

#
# Set and check values
#
set_and_check_values() {
  logging_info "${FUNCNAME[0]}"

  SSL_CERTIFICATE=fullchain.pem
  SSL_CERTIFICATE_KEY=privkey.pem

  IDM_ADMIN_UID="admin"

  SETUP_DIR=./setup
  TEMPLEATE=${SETUP_DIR}/templeate

  for NAME in KEYROCK ORION
  do
    eval VAL=\"\$$NAME\"
    if [ "$VAL" = "" ]; then
        logging_err "${NAME} is empty"
        exit "${ERR_CODE}"
    fi
  done

  if [ -z "${POSTFIX}" ]; then
    POSTFIX=false
  fi

  if [ -z "${QUERYPROXY}" ]; then
    QUERYPROXY=false
  fi

  if [ -z "${REGPROXY}" ]; then
    REGPROXY=false
  fi

  if [ -z "${KEYROCK_POSTGRES}" ]; then
    KEYROCK_POSTGRES=false
  fi

  if [ -z "${IDM_ADMIN_USER}" ]; then
    IDM_ADMIN_USER="admin"
  fi

  if [ -z "${IDM_ADMIN_EMAIL}" ]; then
    IDM_ADMIN_EMAIL=${IDM_ADMIN_USER}@${DOMAIN_NAME}
  fi

  if [ -z "${CERT_EMAIL}" ]; then
    CERT_EMAIL=${IDM_ADMIN_EMAIL}
  fi

  if [ -z "${CERT_REVOKE}" ]; then
    CERT_REVOKE=false
  fi

  CERT_DIR=/etc/letsencrypt

  if [ "${WIRECLOUD}" = "" ]; then
    NGSIPROXY=""
  fi

  if [ "${WIRECLOUD}" != "" ] && [ "${NGSIPROXY}" = "" ]; then
    logging_err "error: NGSIPROXY is empty"
    exit "${ERR_CODE}"
  fi

  if [ "${IOTAGENT}" = "" ]; then
    MOSQUITTO=""
  fi

  if [ "${IOTAGENT}" != "" ] && [ "${MOSQUITTO}" = "" ]; then
    logging_err "error: MOSQUITTO is empty"
    exit "${ERR_CODE}"
  fi

  if [ -z "${MQTT_1883}" ]; then
    MQTT_1883=false
  fi

  if [ -z "${MQTT_TLS}" ]; then
    MQTT_TLS=true
  fi

  if ! "${MQTT_1883}" && ! "${MQTT_TLS}"; then
    logging_err "error: Both MQTT_1883 and MQTT_TLS are false"
    exit "${ERR_CODE}"
  fi

  if [ -n "${NODE_RED_INSTANCE_NUMBER}" ]; then
    if [ "${NODE_RED_INSTANCE_NUMBER}" -lt 2 ] || [ "${NODE_RED_INSTANCE_NUMBER}" -gt 20 ]; then
      echo "error: NODE_RED_INSTANCE_NUMBER out of range (2-20)"
      exit "${ERR_CODE}"
    fi
    if [ -z "${NODE_RED_INSTANCE_HTTP_ADMIN_ROOT}" ]; then
      NODE_RED_INSTANCE_HTTP_ADMIN_ROOT=/node-red
    fi
    if [ -z "${NODE_RED_INSTANCE_USERNAME}" ]; then
      NODE_RED_INSTANCE_USERNAME=node-red
    fi
  else
    NODE_RED_INSTANCE_NUMBER=1
  fi
}

#
# Add variables to .env file
#
add_env() {
  logging_info "${FUNCNAME[0]}"

  if [ -z "${IDM_ADMIN_PASS}" ]; then
    IDM_ADMIN_PASS=$(pwgen -s 16 1)
  fi

  cat <<EOF >> .env
VERSION=${VERSION}

DATA_DIR=${DATA_DIR}
CERTBOT_DIR=${CERTBOT_DIR}
CONFIG_DIR=${CONFIG_DIR}
CONFIG_NGINX=${CONFIG_NGINX}
NGINX_SITES=${NGINX_SITES}
SETUP_DIR=${SETUP_DIR}
WORK_DIR=${WORK_DIR}
CONTRIB_DIR=${CONTRIB_DIR}
TEMPLEATE=${TEMPLEATE}

LOG_DIR=${LOG_DIR}
NGINX_LOG_DIR=${NGINX_LOG_DIR}

DOMAIN_NAME=${DOMAIN_NAME}

DOCKER_COMPOSE="${DOCKER_COMPOSE}"

CURL="${CURL}"
NGSI_GO="${NGSI_GO}"

FIREWALL=${FIREWALL}

KEYROCK_POSTGRES=${KEYROCK_POSTGRES}

CERT_DIR=${CERT_DIR}
IMAGE_CERTBOT=${IMAGE_CERTBOT}
CERT_EMAIL=${CERT_EMAIL}
CERT_REVOKE=${CERT_REVOKE}
CERT_TEST=${CERT_TEST}
CERT_FORCE_RENEWAL=${CERT_FORCE_RENEWAL}

IDM_ADMIN_UID=${IDM_ADMIN_UID}
IDM_ADMIN_USER=${IDM_ADMIN_USER}
IDM_ADMIN_EMAIL=${IDM_ADMIN_EMAIL}
IDM_ADMIN_PASS=${IDM_ADMIN_PASS}

IMAGE_KEYROCK=${IMAGE_KEYROCK}
IMAGE_WILMA=${IMAGE_WILMA}
IMAGE_ORION=${IMAGE_ORION}
IMAGE_CYGNUS=${IMAGE_CYGNUS}
IMAGE_COMET=${IMAGE_COMET}
IMAGE_WIRECLOUD=${IMAGE_WIRECLOUD}
IMAGE_NGSIPROXY=${IMAGE_NGSIPROXY}
IMAGE_QUANTUMLEAP=${IMAGE_QUANTUMLEAP}
IMAGE_IOTAGENT=${IMAGE_IOTAGENT}

IMAGE_TOKENPROXY=${IMAGE_TOKENPROXY}
IMAGE_QUERYPROXY=${IMAGE_QUERYPROXY}
IMAGE_REGPROXY=${IMAGE_REGPROXY}

IMAGE_MONGO=${IMAGE_MONGO}
IMAGE_MYSQL=${IMAGE_MYSQL}
IMAGE_POSTGRES=${IMAGE_POSTGRES}
IMAGE_CRATE=${IMAGE_CRATE}

IMAGE_NGINX=${IMAGE_NGINX}
IMAGE_REDIS=${IMAGE_REDIS}
IMAGE_ELASTICSEARCH=${IMAGE_ELASTICSEARCH}
IMAGE_MEMCACHED=${IMAGE_MEMCACHED}
IMAGE_GRAFANA=${IMAGE_GRAFANA}
IMAGE_MOSQUITTO=${IMAGE_MOSQUITTO}
IMAGE_NODE_RED=${IMAGE_NODE_RED}
IMAGE_POSTFIX=${IMAGE_POSTFIX}

# Logging settings
IDM_DEBUG=${IDM_DEBUG}
CYGNUS_LOG_LEVEL=${CYGNUS_LOG_LEVEL}
LOGOPS_LEVEL=${LOGOPS_LEVEL}
QUANTUMLEAP_LOGLEVEL=${QUANTUMLEAP_LOGLEVEL}
WIRECLOUD_LOGLEVEL=${WIRECLOUD_LOGLEVEL}
TOKENPROXY_LOGLEVEL=${TOKENPROXY_LOGLEVEL}
TOKENPROXY_VERBOSE=${TOKENPROXY_VERBOSE}
QUERYPROXY_LOGLEVEL=${QUERYPROXY_LOGLEVEL}
NODE_RED_LOGGING_LEVEL=${NODE_RED_LOGGING_LEVEL}
NODE_RED_LOGGING_METRICS=${NODE_RED_LOGGING_METRICS}
NODE_RED_LOGGING_AUDIT=${NODE_RED_LOGGING_AUDIT}
GF_LOG_LEVEL=${GF_LOG_LEVEL}
MOSQUITTO_LOG_TYPE=${MOSQUITTO_LOG_TYPE}

EOF
}

#
# Add sub-domains to .env file
#
add_domain_to_env() {
  logging_info "${FUNCNAME[0]}"

  for NAME in "${APPS[@]}"
  do
    eval VAL=\"\$"$NAME"\"
    if [ -n "$VAL" ]; then
        eval echo "${NAME}"=\"\$"${NAME}"."${DOMAIN_NAME}"\" >> .env
        eval "${NAME}"=\"\$"${NAME}"."${DOMAIN_NAME}"\"
    else
        echo "${NAME}"= >> .env
    fi 
  done

  echo -e -n "\n" >> .env
}

#
# Setup complete
#
setup_complete() {
  logging_info "${FUNCNAME[0]}"

  rm -f "${INSTALL}"

  . ./.env

  echo "*** Setup has been completed ***"
  echo "IDM: https://${KEYROCK}"
  echo "User: ${IDM_ADMIN_EMAIL}"
  echo "Password: ${IDM_ADMIN_PASS}"
  echo "Please see the .env file for details."
  if [ -e "${NODE_RED_USERS_TEXT}" ]; then
    echo "User informatin for Node-RED is here: ${NODE_RED_USERS_TEXT}"
  fi
}

#
# Get distribution name
#
get_distro() {
  logging_info "${FUNCNAME[0]}"

  DISTRO=

  if [ -e /etc/redhat-release ]; then
    DISTRO="CentOS"
  elif [ -e /etc/debian_version ] || [ -e /etc/debian_release ]; then

    if [ -e /etc/lsb-release ]; then
      ver="$(sed -n -e "/DISTRIB_RELEASE=/s/DISTRIB_RELEASE=\(.*\)/\1/p" /etc/lsb-release | awk -F. '{printf "%2d%02d", $1,$2}')"
      if [ "${ver}" -ge 1804 ]; then
        DISTRO="Ubuntu"
      else
        MSG="Error: Ubuntu ${ver} not supported"
        logging_err "${FUNCNAME[0]} ${MSG}"
        exit "${ERR_CODE}"
      fi
    else
      MSG="Error: not Ubuntu"
      logging_err "${FUNCNAME[0]} ${MSG}"
      exit "${ERR_CODE}"
    fi
  else
    MSG="Unknown distro"
    logging_err "${FUNCNAME[0]} ${MSG}"
    exit "${ERR_CODE}"
  fi

  echo "DISTRO=${DISTRO}" >> .env
  echo -e -n "\n" >> .env
  logging_info "${FUNCNAME[0]} ${DISTRO}"
}

#
# Check machine architecture
#
check_machine() {
  logging_info "${FUNCNAME[0]}"

  machine=$("${UNAME}" -m)
  if [ "${machine}" = "x86_64" ]; then
    logging_info "${FUNCNAME[0]} ${machine}"
    return
  fi

  MSG="Error: ${machine} not supported"
  logging_err "${FUNCNAME[0]} ${MSG}"
  exit "${ERR_CODE}"
}

#
# Install commands for Ubuntu
#
install_commands_ubuntu() {
  logging_info "${FUNCNAME[0]}"

  ${APT} update
  ${APT} install -y curl pwgen jq make zip
}

#
# Install commands for CentOS
#
install_commands_centos() {
  logging_info "${FUNCNAME[0]}"

  ${YUM} install -y epel-release
  ${YUM} install -y curl pwgen jq bind-utils make zip
}

#
# Install commands
#
install_commands() {
  logging_info "${FUNCNAME[0]}"

  update=false
  for cmd in curl pwgen jq zip
  do
    if ! type "${cmd}" >/dev/null 2>&1; then
        update=true
    fi
  done

  if "${update}"; then
    case "${DISTRO}" in
      "Ubuntu" ) install_commands_ubuntu ;;
      "CentOS" ) install_commands_centos ;;
    esac
  fi

  CURL=$(type curl | sed "s/.* \(\/.*\)/\1/")
  if $FIBB_TEST; then
    CURL="${CURL} --insecure"
  fi
}

#
# Setup firewall
#
setup_firewall() {
  logging_info "${FUNCNAME[0]}"

  if [ -z "${FIREWALL}" ]; then
    FIREWALL=false
  fi
  
  if "${FIREWALL}"; then
    case "${DISTRO}" in
      "Ubuntu" ) ${APT} install -y firewalld ;;
      "CentOS" ) ${YUM} -y install firewalld ;;
    esac
    ${SYSTEMCTL} start firewalld
    ${SYSTEMCTL} enable firewalld
    ${FIREWALL-CMD} --zone=public --add-service=http --permanent
    ${FIREWALL-CMD} --zone=public --add-service=https --permanent
    ${FIREWALL-CMD} --reload
  fi
}

#
# Install Docker for Ubuntu
#
#   https://docs.docker.com/engine/install/ubuntu/
#
install_docker_ubuntu() {
  logging_info "${FUNCNAME[0]}"

  ${SUDO} cp -p /etc/apt/sources.list{,.bak}
  ${APT_GET} update
  ${APT_GET} install -y \
      apt-transport-https \
      ca-certificates \
      curl \
      gnupg-agent \
      software-properties-common
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | ${APT_KEY} add -
  ${ADD_APT_REPOSITORY} "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
  ${APT_GET} install -y docker-ce docker-ce-cli containerd.io
  ${SYSTEMCTL} start docker
  ${SYSTEMCTL} enable docker
}

#
# Install Docker for CentOS
#
#   https://docs.docker.com/engine/install/centos/
#
install_docker_centos() {
  logging_info "${FUNCNAME[0]}"

  ${YUM} install -y yum-utils
  ${YUM_CONFIG_MANAGER} --add-repo https://download.docker.com/linux/centos/docker-ce.repo
  ${YUM} install -y docker-ce docker-ce-cli containerd.io
  ${SYSTEMCTL} start docker
  ${SYSTEMCTL} enable docker
}

#
# Check Docker
#
check_docker() {
  logging_info "${FUNCNAME[0]}"

  if ! type "${DOCKER_CMD}" >/dev/null 2>&1; then
    case "${DISTRO}" in
       "Ubuntu" ) install_docker_ubuntu ;;
       "CentOS" ) install_docker_centos ;;
    esac
  fi

  DOCKER="${SUDO} $(type docker | sed "s/.* \(\/.*\)/\1/")"
  if $FIBB_TEST; then
    DOCKER="${SUDO} ${MOCK_PATH}docker"
  fi
  
  local ver
  ver=$(${DOCKER} --version)
  logging_info "${FUNCNAME[0]} ${ver}"

  ver=$(${DOCKER} version -f "{{.Server.Version}}" | awk -F. '{printf "%2d%02d%02d", $1,$2,$3}')
  if [ "${ver}" -ge 201006 ]; then
      return
  fi

  MSG="Docker engine requires equal or higher version than 20.10.6"
  logging_err "${FUNCNAME[0]} ${MSG}"
  exit "${ERR_CODE}"
}

#
# Check docker-compose
#
check_docker_compose() {
  logging_info "${FUNCNAME[0]}"

  if [ -e "${DOCKER_COMPOSE_CMD}" ]; then
    local ver
    ver=$(${DOCKER_COMPOSE} --version)
    logging_info "${FUNCNAME[0]} ${ver}"

    ver=$(${DOCKER_COMPOSE} version --short | awk -F. '{printf "%2d%02d%02d", $1,$2,$3}')
    if [ "${ver}" -ge 11700 ]; then
      return
    fi
  fi

  curl -sOL https://github.com/docker/compose/releases/download/1.29.2/docker-compose-Linux-x86_64
  ${SUDO} mv docker-compose-Linux-x86_64 "${DOCKER_COMPOSE_CMD}"
  ${SUDO} chmod a+x "${DOCKER_COMPOSE_CMD}"
}

#
# Check NGSI Go
#
check_ngsi_go() {
  logging_info "${FUNCNAME[0]}"

  if [ -e /usr/local/bin/ngsi ]; then
    local ver
    ver=$(/usr/local/bin/ngsi --version)
    logging_info "${ver}"
    ver=$(/usr/local/bin/ngsi --version | sed -e "s/ngsi version \([^ ]*\) .*/\1/" | awk -F. '{printf "%2d%02d%02d", $1,$2,$3}')
    if [ "${ver}" -ge 900 ]; then
        cp /usr/local/bin/ngsi "${WORK_DIR}"
        return
    fi
  fi

  curl -sOL https://github.com/lets-fiware/ngsi-go/releases/download/v0.9.0/ngsi-v0.9.0-linux-amd64.tar.gz
  ${SUDO} tar zxf ngsi-v0.9.0-linux-amd64.tar.gz -C /usr/local/bin
  rm -f ngsi-v0.9.0-linux-amd64.tar.gz

  if [ -d /etc/bash_completion.d ]; then
    curl -OL https://raw.githubusercontent.com/lets-fiware/ngsi-go/main/autocomplete/ngsi_bash_autocomplete
    ${SUDO} mv ngsi_bash_autocomplete /etc/bash_completion.d/
    source /etc/bash_completion.d/ngsi_bash_autocomplete
    echo "source /etc/bash_completion.d/ngsi_bash_autocomplete" >> ~/.bashrc
  fi

  cp /usr/local/bin/ngsi "${WORK_DIR}"
}

#
# Setup init
#
setup_init() {
  logging_info "${FUNCNAME[0]}"

  KEYROCK_DIR="${WORK_DIR}/keyrock"
  MYSQL_DIR="${WORK_DIR}/mysql"
  POSTGRES_DIR="${WORK_DIR}/postgres"

  CONFIG_NGINX=${CONFIG_DIR}/nginx
  NGINX_SITES=${CONFIG_DIR}/nginx/sites-enable

  CERTBOT_DIR=$(pwd)/data/cert

  NGSI_GO="/usr/local/bin/ngsi --batch --config ${WORK_DIR}/ngsi-go-config.json --cache ${WORK_DIR}/ngsi-go-token-cache.json"
  if $FIBB_TEST; then
    NGSI_GO="${NGSI_GO} --insecureSkipVerify"
  fi

  IDM=keyrock-$(date +%Y%m%d_%H-%M-%S)

  DOCKER_COMPOSE_YML=./docker-compose.yml

  readonly APPS=(KEYROCK ORION COMET WIRECLOUD NGSIPROXY NODE_RED GRAFANA QUANTUMLEAP IOTAGENT MOSQUITTO KNOWAGE)

  val=

  POSTGRES_INSTALLED=false
  POSTGRES_PASSWORD=

  CONTRIB_DIR=./CONTRIB
}

#
# Make directories
#
make_directories() {
  logging_info "${FUNCNAME[0]}"

  if [ -d "${WORK_DIR}" ]; then
    rm -fr "${WORK_DIR}"
  fi

  mkdir "${DATA_DIR}"
  mkdir "${WORK_DIR}"
  mkdir "${KEYROCK_DIR}"
  mkdir "${MYSQL_DIR}"
  mkdir "${POSTGRES_DIR}"

  mkdir -p "${CONFIG_DIR}"/nginx
  mkdir -p "${NGINX_SITES}"

  rm -fr "${CERTBOT_DIR}"
  mkdir -p "${CERTBOT_DIR}"
}

#
# Add /etc/hosts
#
add_etc_hosts() {
  logging_info "${FUNCNAME[0]}"

  for name in "${APPS[@]}"
  do
    eval val=\"\$"${name}"\"
    if [ -n "${val}" ]; then
      result=0
      output=$(grep "${val}" /etc/hosts 2> /dev/null) || result=$?
      echo "${output}" > /dev/null
      if [ ! "$result" = "0" ]; then
        ${SUDO} bash -c "echo $1 ${val} >> /etc/hosts"
        echo "Add '$1 ${val}' to /etc/hosts"
      fi
    fi
  done

  cat /etc/hosts
}

#
# Validate domain
#
validate_domain() {
  logging_info "${FUNCNAME[0]}"

  local IPS

  if [ -n "${IP_ADDRESS}" ]; then
      IPS=("${IP_ADDRESS}")
  else
      # shellcheck disable=SC2207
      IPS=($(hostname -I))
  fi

  if "$FIBB_TEST"; then
    IP_ADDRESS=${IPS[0]}
    echo "${IP_ADDRESS}"
    add_etc_hosts "${IP_ADDRESS}" 
  fi

  logging_info "${IPS[@]}"

  # shellcheck disable=SC2068
  for name in ${APPS[@]}
  do
    eval val=\"\$"${name}"\"
    if [ -n "${val}" ]; then
        logging_info "Sub-domain: ${val}"
        IP=$(${HOST_CMD} -4 ${val} | awk 'match($0,/[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/) { print substr($0, RSTART, RLENGTH) }' || true)
        if [ "$IP" = "" ]; then
          IP=$(sed -n -e "/${val}/s/\([^ ].*\) .*/\1/p" /etc/hosts)
        fi
        logging_info "IP address: ${IP}"
        found=false
        # shellcheck disable=SC2068
        for ip_addr in ${IPS[@]}
        do
          if [ "${IP}" = "${ip_addr}" ] ; then
            found=true
            IP_ADDRESS="${IP}"
          fi
        done
        if ! "${found}"; then
            # shellcheck disable=SC2124
            MSG="IP address error: ${val}, ${IP_ADDRESS[@]}"
            logging_err "${MSG}"
            exit "${ERR_CODE}"
        fi 
    fi 
  done

  logging_info "IP_ADDRESS: ${IP_ADDRESS}"
  cat <<EOF >> .env

IP_ADDRESS=${IP_ADDRESS}
EOF
}

#
# wait for serive
#
wait() {
  logging_info "${FUNCNAME[0]}"

  local host
  local ret

  host=$1
  ret=$2

  echo "Wait for ${host} to be ready (${WAIT_TIME} sec)" 1>&2

  for i in $(seq "${WAIT_TIME}")
  do
    # shellcheck disable=SC2086
    if [ "${ret}" == "$(${CURL} ${host} -o /dev/null -w '%{http_code}\n' -s)" ]; then
      return
    fi
    sleep 1
  done

  logging_err "${host}: Timeout was reached."
  exit "${ERR_CODE}"
}

#
# get cert
#
get_cert() {
  logging_info "${FUNCNAME[0]}"

  echo "${CERT_DIR}/live/$1" 1>&2

  if ${SUDO} [ -d "${CERT_DIR}/live/$1" ] && ${CERT_REVOKE}; then
    # shellcheck disable=SC2086
    ${DOCKER} run --rm -v "${CERT_DIR}:/etc/letsencrypt" "${IMAGE_CERTBOT}" revoke -n -v ${CERT_TEST} --cert-path "${CERT_DIR}/live/$1/cert.pem"
  fi

  if ${SUDO} [ ! -d "${CERT_DIR}/live/$1" ]; then
    local root_ca
    root_ca="${PWD}/config/root_ca"
    if [ ! -d "${root_ca}" ]; then
      mkdir "${root_ca}"
    fi
    wait "http://$1/" "404"
    # shellcheck disable=SC2086
    ${SUDO} docker run --rm \
      -v "${CERTBOT_DIR}/$1:/var/www/html/$1" \
      -v "${CERT_DIR}:/etc/letsencrypt" \
      -v "${root_ca}":/root_ca \
      -e IP_ADDRESS="${IP_ADDRESS}" \
      "${IMAGE_CERTBOT}" \
      certonly ${CERT_TEST} --agree-tos -m "${CERT_EMAIL}" --webroot -w "/var/www/html/$1" -d "$1"
  else
    echo "Skip: ${CERT_DIR}/live/$1 direcotry already exits"
  fi
}

#
# setup cert
#
setup_cert() {
  logging_info "${FUNCNAME[0]}"

  for name in "${APPS[@]}"
  do
    eval val=\"\$"${name}"\"
    if [ -n "${val}" ]; then
      if [ ! -d "${CERTBOT_DIR}"/"${val}" ]; then
        mkdir "${CERTBOT_DIR}"/"${val}"
      fi
      sed -e "s/HOST/${val}/" "${TEMPLEATE}"/nginx/nginx-cert > "${NGINX_SITES}"/"${val}"
    fi 
  done

  cp "${TEMPLEATE}"/docker/setup-cert.yml ./docker-cert.yml
  cp "${TEMPLEATE}"/nginx/nginx.conf "${CONFIG_DIR}"/nginx/

  ${DOCKER_COMPOSE} -f docker-cert.yml up -d

  for name in "${APPS[@]}"
  do
    eval val=\"\$"${name}"\"
    if [ -n "${val}" ]; then
      get_cert "${val}"
    fi 
  done

  ${DOCKER_COMPOSE} -f docker-cert.yml down

  RND=$(od -An -tu1 -N1 /dev/urandom)
  HOUR=$(( "${RND}" % 5 ))
  RND=$(od -An -tu1 -N1 /dev/urandom)
  MINUTE=$(( "${RND}" % 60 ))

  CRON_FILE=/etc/cron.d/fiware-big-bang

  if [ -e "${CRON_FILE}" ]; then
    ${SUDO} rm -f "${CRON_FILE}"
  fi

  CRON_SH="${MINUTE} ${HOUR} \* \* \* root ${PWD}/config/script/renew.sh > /dev/null 2>&1"
  ${SUDO} sh -c "echo ${CRON_SH} > ${CRON_FILE}"

  local msg
  msg=$(echo "${CRON_FILE}: $CRON_SH" | sed -e "s/\\\\//g")
  logging_info "${msg}"
}

#
# Add fiware.conf
#
add_rsyslog_conf() {
  logging_info "${FUNCNAME[0]}"

  set +u
  while [ "$1" ]
  do
    cat <<EOF >> "${RSYSLOG_CONF}"
:syslogtag,startswith,"[$1]" /var/log/fiware/$1.log
& stop

EOF
    echo "${LOG_DIR}/$1.log" >> "${LOGROTATE_CONF}"
    shift
  done
  set -u
}

#
# setup_logging_step2
#
setup_logging_step2() {
  logging_info "${FUNCNAME[0]}"

  files=("$(sed -z -e "s/\n/ /g" "${LOGROTATE_CONF}")")
  # shellcheck disable=SC2068
  for file in ${files[@]}
  do
    ${SUDO} touch "${file}"
    if [ "${DISTRO}" = "Ubuntu" ]; then
      ${SUDO} chown syslog:adm "${file}"
    else
      ${SUDO} chown root:root "${file}"
      ${SUDO} chmod 0644 "${file}"
    fi
  done

  if [ "${DISTRO}" = "Ubuntu" ]; then
    ${SUDO} cp "${RSYSLOG_CONF}" /etc/rsyslog.d/10-fiware.conf
    ROTATE_CMD="/usr/lib/rsyslog/rsyslog-rotate"
  else
    ${SUDO} cp "${RSYSLOG_CONF}" /etc/rsyslog.d/fiware.conf
    ROTATE_CMD="/bin/kill -HUP \`cat /var/run/syslogd.pid 2> /dev/null\` 2> /dev/null || true"
  fi

  ${SYSTEMCTL} restart rsyslog.service

  cat <<EOF >> "${LOGROTATE_CONF}"
{
        rotate 4
        weekly
        dateext
        missingok
        notifempty
        compress
        delaycompress
        sharedscripts
        postrotate
                ${ROTATE_CMD}
        endscript
}
EOF

  ${SUDO} cp "${LOGROTATE_CONF}" /etc/logrotate.d/fiware
}

#
# Up Keyrock with MySQL
#
up_keyrock_mysql() {
  logging_info "${FUNCNAME[0]}"

  cp -a "${TEMPLEATE}"/docker/setup-keyrock-mysql.yml ./docker-idm.yml

  MYSQL_ROOT_PASSWORD=$(pwgen -s 16 1)

  IDM_HOST=https://${KEYROCK}

  IDM_DB_HOST=mysql
  IDM_DB_NAME=idm
  IDM_DB_USER=idm
  IDM_DB_PASS=$(pwgen -s 16 1)

  cat <<EOF >> .env
IDM_HOST=${IDM_HOST}

# Mysql

MYSQL_ROOT_PASSWORD=${MYSQL_ROOT_PASSWORD}

IDM_DB_HOST=${IDM_DB_HOST}
IDM_DB_NAME=${IDM_DB_NAME}
IDM_DB_USER=${IDM_DB_USER}
IDM_DB_PASS=${IDM_DB_PASS}

# Keyrock

IDM_ADMIN_UID=${IDM_ADMIN_UID}
IDM_ADMIN_USER=${IDM_ADMIN_USER}
IDM_ADMIN_EMAIL=${IDM_ADMIN_EMAIL}
IDM_ADMIN_PASS=${IDM_ADMIN_PASS}
IDM_SESSION_SECRET=$(pwgen -s 16 1)
IDM_ENCRYPTION_KEY=$(pwgen -s 16 1)
EOF

  cat <<EOF > "${MYSQL_DIR}"/init.sql
CREATE USER '${IDM_DB_USER}'@'%' IDENTIFIED BY '${IDM_DB_PASS}';
GRANT ALL PRIVILEGES ON ${IDM_DB_NAME}.* TO '${IDM_DB_USER}'@'%';
flush PRIVILEGES;
EOF
}

#
# UP keyrock with PostgreSQL
#
up_keyrock_postgres() {
  logging_info "${FUNCNAME[0]}"

  cp "${CONTRIB_DIR}/keyrock/20210603073911-hashed-access-tokens.js" "${KEYROCK_DIR}"

  cp -a "${TEMPLEATE}"/docker/setup-keyrock-postgres.yml ./docker-idm.yml

  POSTGRES_PASSWORD=$(pwgen -s 16 1)

  IDM_HOST=https://${KEYROCK}

  IDM_DB_DIALECT=postgres
  IDM_DB_HOST=postgres
  IDM_DB_PORT=5432
  IDM_DB_NAME=idm
  IDM_DB_USER=idm
  IDM_DB_PASS=$(pwgen -s 16 1)

  cat <<EOF >> .env
IDM_HOST=${IDM_HOST}

# PostgreSQL

POSTGRES_PASSWORD=${POSTGRES_PASSWORD}

IDM_DB_DIALECT=${IDM_DB_DIALECT}
IDM_DB_HOST=${IDM_DB_HOST}
IDM_DB_PORT=${IDM_DB_PORT}
IDM_DB_NAME=${IDM_DB_NAME}
IDM_DB_USER=${IDM_DB_USER}
IDM_DB_PASS=${IDM_DB_PASS}

# Keyrock

IDM_ADMIN_UID=${IDM_ADMIN_UID}
IDM_ADMIN_USER=${IDM_ADMIN_USER}
IDM_ADMIN_EMAIL=${IDM_ADMIN_EMAIL}
IDM_ADMIN_PASS=${IDM_ADMIN_PASS}
IDM_SESSION_SECRET=$(pwgen -s 16 1)
IDM_ENCRYPTION_KEY=$(pwgen -s 16 1)
EOF

  cat <<EOF > "${POSTGRES_DIR}"/init.sql
create role ${IDM_DB_USER} with SUPERUSER CREATEDB login password '${IDM_DB_PASS}';
EOF
}

#
# Up keyrock
#
up_keyrock() {

  if "${KEYROCK_POSTGRES}"; then
    up_keyrock_postgres
  else
    up_keyrock_mysql
  fi

  ${DOCKER_COMPOSE} -f docker-idm.yml up -d

  wait "http://localhost:3000/" "200"

  ${NGSI_GO} server add --host "${IDM}" --serverType keyrock --serverHost http://localhost:3000 --idmType idm --username "${IDM_ADMIN_EMAIL}" --password "${IDM_ADMIN_PASS}"
}

#
# Tear down Keyrock
#
down_keyrock() {
  logging_info "${FUNCNAME[0]}"

  ${DOCKER_COMPOSE} -f docker-idm.yml down
}

#
# Add docker-compose.yml
#
add_docker_compose_yml() {
  logging_info "${FUNCNAME[0]} $1"

  echo "" >> ${DOCKER_COMPOSE_YML}
  sed -e '/^version:/,/services:/d' "${TEMPLEATE}"/docker/"$1" >> ${DOCKER_COMPOSE_YML}
}

#
# Create nginx conf
#
create_nginx_conf() {
  sed -e "s/HOST/$1/" "${TEMPLEATE}/nginx/$2" > "${NGINX_SITES}/$1"
}

#
# Add nginx ports
#
add_nginx_ports() {
  set +u
  while [ "$1" ]
  do
    sed -i -e "/__NGINX_PORTS__/ i \      - $1" ${DOCKER_COMPOSE_YML}
    shift
  done
  set -u
}

#
# Add nginx depends_on
#
add_nginx_depends_on() {
  set +u
  while [ "$1" ]
  do
    sed -i -e "/__NGINX_DEPENDS_ON__/ i \      - $1" ${DOCKER_COMPOSE_YML}
    shift
  done
  set -u
}

#
# Add nginx volumes
#
add_nginx_volumes() {
  set +u
  while [ "$1" ]
  do
    sed -i -e "/__NGINX_VOLUMES__/ i \      - $1" "${DOCKER_COMPOSE_YML}"
    shift
  done
  set -u
}

#
# Add to docker_compose.yml
#
add_to_docker_compose_yml() {
  sed -i -e "/$1/i \ $2" "${DOCKER_COMPOSE_YML}"
}

#
# Delete from docker_compose.yml
#
delete_from_docker_compose_yml() {
  sed -i -e "/$1/d" "${DOCKER_COMPOSE_YML}"
}

#
# create_dummy_cert
#
create_dummy_cert() {
  logging_info "${FUNCNAME[0]}"

  echo "subjectAltName=IP:${IP_ADDRESS}" > "${WORK_DIR}/ip.txt"

  openssl genrsa 2048 > "${WORK_DIR}/server.key"
  openssl req -new -key "${WORK_DIR}/server.key" << EOF > "${WORK_DIR}/server.csr"
JP
Tokyo
Smart city
Let's FIWARE
FI-BB
${DOMAIN_NAME}
admin@${DOMAIN_NAME}
fiware

EOF

  openssl x509 -days 3650 --extfile "${WORK_DIR}/ip.txt" -req -signkey "${WORK_DIR}/server.key" < "${WORK_DIR}/server.csr" > "${WORK_DIR}/server.crt"
  openssl rsa -in "${WORK_DIR}/server.key" -out "${WORK_DIR}/server.key" << EOF
fiware
EOF

  cp "${WORK_DIR}/server.crt" "${CONFIG_NGINX}/fullchain.pem"
  cp "${WORK_DIR}/server.key" "${CONFIG_NGINX}/privkey.pem"
}

#
# Nginx
#
setup_nginx() {
  logging_info "${FUNCNAME[0]}"

  rm -fr "${NGINX_SITES}"
  mkdir -p "${NGINX_SITES}"

  cp "${TEMPLEATE}"/docker/docker-nginx.yml "${DOCKER_COMPOSE_YML}"

  cp "${TEMPLEATE}"/nginx/default_server "${NGINX_SITES}"

  create_dummy_cert

  add_rsyslog_conf "nginx"
}

#
#  Setup MySQL
#
setup_mysql() {
  logging_info "${FUNCNAME[0]}"

  add_docker_compose_yml "docker-mysql.yml"

  sed -i -e "/- IDM_DB_DIALECT/d" ${DOCKER_COMPOSE_YML}
  sed -i -e "/- IDM_DB_PORT/d" ${DOCKER_COMPOSE_YML}

  sed -i -e "/ __KEYROCK_DEPENDS_ON__/s/^.*/      - mysql/" ${DOCKER_COMPOSE_YML}

  add_rsyslog_conf "mysql"
}

#
#  Setup Postgres
#
setup_postgres() {
  logging_info "${FUNCNAME[0]}"

  if "${POSTGRES_INSTALLED}"; then
    return
  else
    POSTGRES_INSTALLED=true
  fi

  add_docker_compose_yml "docker-postgres.yml"

  sed -i -e "/ __KEYROCK_DEPENDS_ON__/s/^.*/      - postgres/" ${DOCKER_COMPOSE_YML}

  add_rsyslog_conf "postgres"

  if [ -n "${POSTGRES_PASSWORD}" ]; then
    return
  fi

  POSTGRES_PASSWORD=$(pwgen -s 16 1)

  cat <<EOF >> .env

# Postgres

POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
EOF
}

#
# Keyrock 
#
setup_keyrock() {
  logging_info "${FUNCNAME[0]}"

  add_docker_compose_yml "docker-keyrock.yml"

  create_nginx_conf "${KEYROCK}" "nginx-keyrock"

  add_nginx_depends_on "keyrock"

  add_rsyslog_conf "keyrock"

  mkdir "${CONFIG_DIR}"/keyrock
  echo "${DOMAIN_NAME}" > "${CONFIG_DIR}"/keyrock/whitelist.txt

  cp "${CONTRIB_DIR}/keyrock/list_users.js" "${CONFIG_DIR}/keyrock"

  add_to_docker_compose_yml "__KEYROCK_VOLUMES__" "     - ${CONFIG_DIR}/keyrock/whitelist.txt:/opt/fiware-idm/etc/email_list/whitelist.txt"
  add_to_docker_compose_yml "__KEYROCK_VOLUMES__" "     - ${CONFIG_DIR}/keyrock/list_users.js:/opt/fiware-idm/controllers/web/list_users.js"
  add_to_docker_compose_yml "__KEYROCK_ENVIRONMENT__" "     - IDM_EMAIL_LIST=whitelist"

  if ${KEYROCK_POSTGRES}; then
    setup_postgres
  else
    setup_mysql
  fi
}

#
# Wilma and Tokenproxy
#
setup_wilma() {
  logging_info "${FUNCNAME[0]}"

  add_docker_compose_yml "docker-wilma.yml"

  add_docker_compose_yml "docker-tokenproxy.yml"

  add_nginx_depends_on "wilma" "tokenproxy"

  add_rsyslog_conf "pep-proxy" "tokenproxy"

  # Create Applicaton for Orion
  AID=$(${NGSI_GO} applications --host "${IDM}" create --name "Wilma" --description "Wilma application" --url "http://localhost/" --redirectUri "http://localhost/")
  SECRET=$(${NGSI_GO} applications --host "${IDM}" get --aid "${AID}" | jq -r .application.secret )

  ORION_CLIENT_ID=${AID}

  # Create PEP Proxy for FIWARE Orion
  PEP_PASSWORD=$(${NGSI_GO} applications --host "${IDM}" pep --aid "${AID}" create --run | jq -r .pep_proxy.password)
  PEP_ID=$(${NGSI_GO} applications --host "${IDM}" pep --aid "${AID}" list | jq -r .pep_proxy.id)

  cp -r "${SETUP_DIR}"/docker/tokenproxy "${CONFIG_DIR}"/
  cp "${WORK_DIR}"/ngsi "${CONFIG_DIR}"/tokenproxy/

  cd "${CONFIG_DIR}"/tokenproxy > /dev/null
  ${DOCKER} build -t "${IMAGE_TOKENPROXY}" .
  rm -f ngsi
  cd - > /dev/null

  cat <<EOF >> .env

# Tokenproxy
TOKENPROXY_CLIENT_ID=${AID}
TOKENPROXY_CLIENT_SECRET=${SECRET}

# PEP Proxy
PEP_PROXY_APP_ID=${AID}
PEP_PROXY_USERNAME=${PEP_ID}
PEP_PASSWORD=${PEP_PASSWORD}
EOF
}

#
# Orion
#
setup_orion() {
  logging_info "${FUNCNAME[0]}"

  add_docker_compose_yml "docker-orion.yml"
  add_docker_compose_yml "docker-mongo.yml"

  create_nginx_conf "${ORION}" "nginx-orion"

  add_nginx_depends_on "orion"

  add_rsyslog_conf "orion" "mongo"

  mkdir -p "${CONFIG_DIR}/mongo"
  cp "${TEMPLEATE}/mongo-init.js" "${CONFIG_DIR}/mongo/"

  CB_HOST=https://${ORION}

  cat <<EOF >> .env

CB_HOST=${CB_HOST}
EOF
}

#
# Queryproxy
#
setup_queryproxy() {
  if ! ${QUERYPROXY}; then
    return
  fi 

  logging_info "${FUNCNAME[0]}"

  cp -r "${SETUP_DIR}"/docker/queryproxy "${CONFIG_DIR}"/
  cp "${WORK_DIR}"/ngsi "${CONFIG_DIR}"/queryproxy/

  cd "${CONFIG_DIR}"/queryproxy > /dev/null
  ${DOCKER} build -t "${IMAGE_QUERYPROXY}" .
  rm -f ngsi
  cd - > /dev/null

  add_docker_compose_yml "docker-queryproxy.yml"

  add_nginx_depends_on "queryproxy"

  add_rsyslog_conf "queryproxy"

  cat <<EOF > "${WORK_DIR}"/nginx_queryproxy
  location /v2/ex/entities {
    set \$req_uri "\$uri";
    auth_request /_check_oauth2_token;

    proxy_pass http://queryproxy:1030;
    proxy_redirect     default;
  }

  location /health {
    set \$req_uri "\$uri";
    auth_request /_check_oauth2_token;

    proxy_pass http://queryproxy:1030;
    proxy_redirect     default;
  }
EOF

  sed -i -e "/# __NGINX_ORION_/r ${WORK_DIR}/nginx_queryproxy" "${NGINX_SITES}/${ORION}"
}

#
# Regproxy
#
setup_regproxy() {
  if ! ${REGPROXY}; then
    return
  fi

  logging_info "${FUNCNAME[0]}"

  cp -r "${SETUP_DIR}"/docker/regproxy "${CONFIG_DIR}"/
  cp "${WORK_DIR}"/ngsi "${CONFIG_DIR}"/regproxy/

  cd "${CONFIG_DIR}"/regproxy > /dev/null
  ${DOCKER} build -t "${IMAGE_REGPROXY}" .
  rm -f ngsi
  cd - > /dev/null

  add_docker_compose_yml "docker-regproxy.yml"

  add_nginx_depends_on "regproxy"

  add_to_docker_compose_yml "__ORION_DEPENDS_ON__" "     - regproxy"

  add_rsyslog_conf "regproxy"

  REGPROXY_NGSITYPE="${REGPROXY_NGSITYPE:-v2}"
  : "${REGPROXY_HOST:?REGPROXY_HOST missing}"
  : "${REGPROXY_IDMTYPE:?REGPROXY_IDMTYPE missing}"
  : "${REGPROXY_IDMHOST:?REGPROXY_IDMHOST missing}"
  : "${REGPROXY_USERNAME:?REGPROXY_USERNAME missing}"
  : "${REGPROXY_PASSWORD:?REGPROXY_PASSWORD missing}"
  REGPROXY_CLIENT_ID="${REGPROXY_CLIENT_ID:-}"
  REGPROXY_CLIENT_SECRET="${REGPROXY_CLIENT_SECRET:-}"
  LOG_LEVEL="${LOG_LEVEL:-info}"

  cat <<EOF >> .env

# Regproxy

REGPROXY_HOST=${REGPROXY_HOST}
REGPROXY_NGSITYPE=${REGPROXY_NGSITYPE}
REGPROXY_IDMTYPE=${REGPROXY_IDMTYPE}
REGPROXY_IDMHOST=${REGPROXY_IDMHOST}
REGPROXY_USERNAME=${REGPROXY_USERNAME}
REGPROXY_PASSWORD=${REGPROXY_PASSWORD}
REGPROXY_CLIENT_ID=${REGPROXY_CLIENT_ID}
REGPROXY_CLIENT_SECRET=${REGPROXY_CLIENT_SECRET}
REGPROXY_LOGLEVEL=${REGPROXY_LOGLEVEL}
REGPROXY_VERBOSE=${REGPROXY_VERBOSE}
EOF
}

#
# Cygnus and Comet
#
setup_comet() {
  if [ -z "${COMET}" ]; then
    return
  fi 

  logging_info "${FUNCNAME[0]}"

  add_docker_compose_yml "docker-comet.yml"

  create_nginx_conf "${COMET}" "nginx-comet"

  add_nginx_depends_on "comet"

  add_rsyslog_conf "comet" "cygnus"
}

#
# QuantumLeap
#
setup_quantumleap() {
  if [ -z "${QUANTUMLEAP}" ]; then
    return
  fi

  logging_info "${FUNCNAME[0]}"

  add_docker_compose_yml "docker-quantumleap.yml"

  create_nginx_conf "${QUANTUMLEAP}" "nginx-quantumleap"

  add_nginx_depends_on  "quantumleap"

  add_rsyslog_conf "quantumleap" "redis" "crate"

  # Workaround for CrateDB. See https://crate.io/docs/crate/howtos/en/latest/deployment/containers/docker.html#troubleshooting
  ${SUDO} sysctl -w vm.max_map_count=262144
}

#
#
#
login_and_logoff_wirecloud() {
  logging_info "${FUNCNAME[0]}"

  wait "https://${WIRECLOUD}/" "200"

  sleep 1

  ${CURL} -sL "https://${WIRECLOUD}/login" -c "${WORK_DIR}/cookie01.txt"  -o "${WORK_DIR}/out1.txt"

  CSRF_TOKEN=$(sed -n "/name='_csrf/s/.*value='\(.*\)'.*/\1/p" "${WORK_DIR}/out1.txt")
  OAUTH2_URL=$(sed -n "/\/oauth2\/authorize/s/.*action=\"\([^\"]*\)\".*/\1/p" "${WORK_DIR}/out1.txt" | sed -e "s/amp;//g")

  sleep 1

  ${CURL} -sL -b "${WORK_DIR}/cookie01.txt" -c "${WORK_DIR}/cookie02.txt" \
    -o "${WORK_DIR}/out2.txt" \
    --data "email=${IDM_ADMIN_EMAIL}" \
    --data "password=${IDM_ADMIN_PASS}" \
    --data "_csrf=${CSRF_TOKEN}" \
    -X POST "https://${KEYROCK}${OAUTH2_URL}"

  CSRF_TOKEN=$(sed -n "/name='_csrf/s/.*value='\(.*\)'.*/\1/p" "${WORK_DIR}/out2.txt")
  OAUTH2_URL=$(sed -n "/enable_app/s/.*action=\"\([^\"]*\)\".*/\1/p" "${WORK_DIR}/out2.txt" | sed -e "s/amp;//g")

  sleep 1

  ${CURL} -sL -b "${WORK_DIR}/cookie02.txt" -c "${WORK_DIR}/cookie03.txt" -o "${WORK_DIR}/out3.txt" --data "_csrf=${CSRF_TOKEN}" \
    --data "user_authorized_application[shared_attributes]=username" \
    --data "user_authorized_application[shared_attributes]=email" \
    --data "user_authorized_application[shared_attributes]=identity_attributes" \
    --data "user_authorized_application[shared_attributes]=image" \
    --data "user_authorized_application[shared_attributes]=gravatar" \
    --data "user_authorized_application[shared_attributes]=eidas_profile" \
    -X POST "https://${KEYROCK}${OAUTH2_URL}"

  sleep 1

  ${CURL} -sL -b "${WORK_DIR}/cookie03.txt" -o "${WORK_DIR}/out4.txt" "https://${WIRECLOUD}/logout"
}

#
# patch widget
#
patch_widget() {
  local widget widget_path patch_dir ql_patch

  widget=$1
  widget_path=$(cd "$(dirname "$2")"; pwd)/$(basename "$2")
  patch_dir="${WORK_DIR}/widget_patch"
  ql_patch="\"URL of the QuantumLeap server to use for retrieving entity information\"\\n                default="

  for name in ngsi-browser ngsi-source ngsi-type-browser quantumleap-source
  do
    # shellcheck disable=SC2143
    if [ "$(echo "${widget}" | grep "${name}")" ]; then
      logging_info "Patch ${name}"
      mkdir "${patch_dir}"
      cd "${patch_dir}"
      unzip "${widget_path}" > /dev/null
      sed -i "s%http://orion.lab.fiware.org:1026%https://${ORION}%" config.xml
      sed -i "s%ngsiproxy.lab.fiware.org%${NGSIPROXY}%" config.xml
      sed -i ":l; N; s/${ql_patch}\"\"/${ql_patch}\"https:\/\/${QUANTUMLEAP}\"/; b l;" config.xml
      rm "${widget_path}"
      # shellcheck disable=SC2035
      zip -r "${widget_path}" -b /tmp * > /dev/null
      cd - > /dev/null
      rm -fr "${patch_dir}"
      return
  fi
  done
}

#
# install widgets for WireCloud
#
install_widgets_for_wirecloud() {
  if [ -z "${WIRECLOUD}" ]; then
    return
  fi

  if ${SKIP_INSTALL_WIDGET}; then
    return
  fi

  logging_info "${FUNCNAME[0]}"

  login_and_logoff_wirecloud

  mkdir -p "${WORK_DIR}/widgets/"

  while read -r line
  do
    name="$(basename "${line}")"
    logging_info "Installing ${name}"
    fullpath="${WORK_DIR}/widgets/${name}"

    curl -sL "${line}" -o "${fullpath}"
    patch_widget "${name}" "${fullpath}"
    set +e
    ${NGSI_GO} macs --host "${WIRECLOUD}" install --file "${fullpath}" --overwrite
    set -e
  done < "${SETUP_DIR}/widgets_list.txt"

  cat <<EOF > "${WORK_DIR}/patch.sql"
UPDATE catalogue_catalogueresource SET public = true;
\q
EOF
  ${SUDO} sh -c "${DOCKER_COMPOSE_CMD} exec -T postgres psql -U postgres postgres < ${WORK_DIR}/patch.sql"
}

#
# WireCLoud and ngsiproxy
#
setup_wirecloud() {
  if [ -z "${WIRECLOUD}" ]; then
    return
  fi

  logging_info "${FUNCNAME[0]}"

  add_docker_compose_yml "docker-wirecloud.yml"

  local aid
  local secret
  local rid

  # Create Applicaton for WireCloud
  aid=$(${NGSI_GO} applications --host "${IDM}" create --name "WireCloud" --description "WireCloud application" --url "https://${WIRECLOUD}/" --redirectUri "https://${WIRECLOUD}/complete/fiware/")
  secret=$(${NGSI_GO} applications --host "${IDM}" get --aid "${aid}" | jq -r .application.secret)
  rid=$(${NGSI_GO} applications --host "${IDM}" roles --aid "${aid}" create --name Admin)
  ${NGSI_GO} applications --host "${IDM}" users --aid "${aid}" assign --rid "${rid}" --uid "${IDM_ADMIN_UID}" > /dev/null

  # Add WireCloud application as a trusted application to WireCloud application
  ${NGSI_GO} applications --host "${IDM}" trusted --aid "${ORION_CLIENT_ID}" add --tid "${aid}"  > /dev/null

  create_nginx_conf "${WIRECLOUD}" "nginx-wirecloud"
  create_nginx_conf "${NGSIPROXY}" "nginx-ngsiproxy"

  add_nginx_depends_on "wirecloud" "ngsiproxy"

  add_nginx_volumes "./data/wirecloud/wirecloud-static:/var/www/static:ro"

  add_rsyslog_conf "wirecloud" "elasticsearch" "memcached" "ngsiproxy"

WIRECLOUD_CLIENT_ID=${aid}
WIRECLOUD_CLIENT_SECRET=${secret}

  cat <<EOF >> .env

# WireCloud 

WIRECLOUD_CLIENT_ID=${WIRECLOUD_CLIENT_ID}
WIRECLOUD_CLIENT_SECRET=${WIRECLOUD_CLIENT_SECRET}
EOF

  setup_postgres

  if $FIBB_TEST; then
    add_to_docker_compose_yml "__WIRECLOUD_ENVIRONMENT__" "     - REQUESTS_CA_BUNDLE=/root_ca/root-ca.crt"
    add_to_docker_compose_yml "__WIRECLOUD_VOLUMES__" "     - \${CONFIG_DIR}/root_ca/root-ca.crt:/root_ca/root-ca.crt"
  fi
}

#
# mosquitto
#
setup_mosquitto() {
  logging_info "${FUNCNAME[0]}"

  add_docker_compose_yml "docker-mosquitto.yml"

  add_nginx_depends_on "mosquitto"

  add_rsyslog_conf "mosquitto"

  mkdir -p "${CONFIG_DIR}"/mosquitto
  cd "${CONFIG_DIR}"/mosquitto
  local dir
  dir=$PWD  
  cd - > /dev/null

  if [ -z "${MQTT_USERNAME}" ]; then
    MQTT_USERNAME=fiware
  fi
  if [ -z "${MQTT_PASSWORD}" ]; then
    MQTT_PASSWORD=$(pwgen -s 16 1)
  fi
  echo "${MQTT_USERNAME}:${MQTT_PASSWORD}" > "${dir}"/password.txt

  cat <<EOF >> .env

# MQTT

MQTT_USERNAME=${MQTT_USERNAME}
MQTT_PASSWORD=${MQTT_PASSWORD}
MQTT_1883=${MQTT_1883}
MQTT_TLS=${MQTT_TLS}
EOF

  ${DOCKER} run --rm -v "${dir}":/work "${IMAGE_MOSQUITTO}" mosquitto_passwd -U /work/password.txt

  add_to_docker_compose_yml "__IOTA_DEPENDS_ON__" "     - mosquitto"
  add_to_docker_compose_yml "__IOTA_ENVIRONMENT__" "     - IOTA_MQTT_HOST=mosquitto"
  add_to_docker_compose_yml "__IOTA_ENVIRONMENT__" "     - IOTA_MQTT_PORT=1883"
  add_to_docker_compose_yml "__IOTA_ENVIRONMENT__" "     - IOTA_MQTT_USERNAME=\${MQTT_USERNAME}"
  add_to_docker_compose_yml "__IOTA_ENVIRONMENT__" "     - IOTA_MQTT_PASSWORD=\${MQTT_PASSWORD}"

  cat <<EOF > "${dir}/mosquitto.conf"
persistence true
persistence_location /mosquitto/data/

log_dest stdout

listener 1883

allow_anonymous false
password_file /mosquitto/config/password.txt

connection_messages true
log_timestamp true
EOF


  local log_types
  local log_type

  # shellcheck disable=SC2206
  log_types=(${MOSQUITTO_LOG_TYPE//,/ })

  for log_type in "${log_types[@]}"
  do
    echo "log_type ${log_type}" >> "${dir}/mosquitto.conf"
  done

  # Add nginx.conf to mosquitto configuration
  local nginx_conf
  nginx_conf="${CONFIG_DIR}"/nginx/nginx.conf

  cat <<EOF >> "${nginx_conf}"

stream {
    upstream mqtt {
      server mosquitto:1883;
    }
EOF

  if ${MQTT_1883}; then
    add_nginx_ports "1883:1883"

    echo "MQTT_PORT=1883" >> .env

    cat <<EOF >> "${CONFIG_DIR}"/nginx/nginx.conf
    server {
      listen 1883;
      proxy_pass mqtt;
    }
EOF
  fi

  if ${MQTT_TLS}; then 
    # ISRG Root X1 - https://letsencrypt.org/certificates/
    local file
    file="${dir}/isrgrootx1.pem"
    curl -s https://letsencrypt.org/certs/isrgrootx1.pem -o "${file}"
    echo "ROOT_CA=${file}" >> .env

    add_nginx_ports "8883:8883"

    echo "MQTT_TLS_PORT=8883" >> .env

    cat <<EOF >> "${CONFIG_DIR}"/nginx/nginx.conf
    server {
      listen 8883 ssl;
      proxy_pass mqtt;
      ssl_certificate ${CERT_DIR}/live/${MOSQUITTO}/fullchain.pem;
      ssl_certificate_key ${CERT_DIR}/live/${MOSQUITTO}/privkey.pem;
    }
EOF
  fi

echo "}" >> "${nginx_conf}"
}

#
# IoT Agent
#
setup_iotagent() {
  if [ -z "${IOTAGENT}" ]; then
    return
  fi

  logging_info "${FUNCNAME[0]}"

  add_docker_compose_yml "docker-iotagent.yml"

  create_nginx_conf "${IOTAGENT}" "nginx-iotagent"

  add_nginx_depends_on "iot-agent"

  add_rsyslog_conf "iotagent"

  setup_mosquitto
}

#
# Node-RED multi instance
#
setup_node_red_multi_instance() {
  logging_info "${FUNCNAME[0]}"

  local http_node_root
  local http_admin_root
  local username
  local number
  local env_val
  local node_red_yml
  local node_red_nginx

  node_red_yaml="${TEMPLEATE}"/docker/docker-node-red.yml

  create_nginx_conf "${NODE_RED}" "nginx-node-red"

  node_red_nginx="${NGINX_SITES}/${NODE_RED}"

  rm -f "${NODE_RED_USERS_TEXT}"

  cat <<EOF >> .env

# Node-RED

EOF

  ORION_RID_API=$(${NGSI_GO} applications --host "${IDM}" roles --aid "${ORION_CLIENT_ID}" create --name "/node-red/api")

  for i in $(seq "${NODE_RED_INSTANCE_NUMBER}")
  do
    number=$(printf "%03d" "$i")
    http_node_root=${NODE_RED_INSTANCE_HTTP_NODE_ROOT}${number}
    http_admin_root=${NODE_RED_INSTANCE_HTTP_ADMIN_ROOT}${number}
    username=${NODE_RED_INSTANCE_USERNAME}${number}
    env_val=NODE_RED_${number}_
 
    echo "" >> ${DOCKER_COMPOSE_YML}

    sed "s/node-red/${username}/" "${node_red_yaml}" | \
    sed "s/letsfiware\/node-red[0-9][0-9]*:/letsfiware\/node-red:/" | \
    sed "/NODE_RED_CLIENT_ID/s/NODE_RED_/${env_val}/g" | \
    sed "/NODE_RED_CLIENT_SECRET/s/NODE_RED_/${env_val}/g" | \
    sed "/NODE_RED_CALLBACK_URL/s/NODE_RED_/${env_val}/g" | \
    sed "s/${env_val}/NODE_RED_/" | \
    sed "/__NODE_RED_ENVIRONMENT__/i \      - NODE_RED_HTTP_NODE_ROOT=${http_node_root}" | \
    sed "/__NODE_RED_ENVIRONMENT__/i \      - NODE_RED_HTTP_ADMIN_ROOT=${http_admin_root}" | \
    sed "/^version:/,/services:/d" >> ${DOCKER_COMPOSE_YML}

    sed -i -e "s/proxy_pass http:\/\/node-red:1880/return 404/" "${node_red_nginx}"
    sed -i -e "/__NODE_RED_SERVER__/i \  location ${http_admin_root} {\n    proxy_pass http:\/\/${username}:1880${http_admin_root};\n  }\n" "${node_red_nginx}"

    add_rsyslog_conf "${username}"

    NODE_RED_URL=https://${NODE_RED}${http_admin_root}/
    NODE_RED_CALLBACK_URL=https://${NODE_RED}${http_admin_root}/auth/strategy/callback

    # Create application for Node-RED
    NODE_RED_CLIENT_ID=$(${NGSI_GO} applications --host "${IDM}" create --name "Node-RED ${number}" --description "Node-RED ${number} application" --url "${NODE_RED_URL}" --redirectUri "${NODE_RED_CALLBACK_URL}")
    NODE_RED_CLIENT_SECRET=$(${NGSI_GO} applications --host "${IDM}" get --aid "${NODE_RED_CLIENT_ID}" | jq -r .application.secret )

    # Create roles and add them to Admin
    RID_FULL=$(${NGSI_GO} applications --host "${IDM}" roles --aid "${NODE_RED_CLIENT_ID}" create --name "/node-red/full")
    ${NGSI_GO} applications --host "${IDM}" users --aid "${NODE_RED_CLIENT_ID}" assign --rid "${RID_FULL}" --uid "${IDM_ADMIN_UID}" > /dev/null
    ${NGSI_GO} applications --host "${IDM}" roles --aid "${NODE_RED_CLIENT_ID}" create --name "/node-red/read" > /dev/null
    RID_API=$(${NGSI_GO} applications --host "${IDM}" roles --aid "${NODE_RED_CLIENT_ID}" create --name "/node-red/api")
    ${NGSI_GO} applications --host "${IDM}" users --aid "${NODE_RED_CLIENT_ID}" assign --rid "${RID_API}" --uid "${IDM_ADMIN_UID}" > /dev/null

    # Add Wilma application as a trusted application to Node-RED application
    ${NGSI_GO} applications --host "${IDM}" trusted --aid "${NODE_RED_CLIENT_ID}" add --tid "${ORION_CLIENT_ID}"  > /dev/null
    ${NGSI_GO} applications --host "${IDM}" users --aid "${ORION_CLIENT_ID}" assign --rid "${ORION_RID_API}" --uid "${IDM_ADMIN_UID}" > /dev/null

    password=$(pwgen -s 16 1)
    NODE_RED_UID=$(${NGSI_GO} users --host "${IDM}" create --username "${username}" --password "${password}" --email "${username}@${DOMAIN_NAME}")
    ${NGSI_GO} applications --host "${IDM}" users --aid "${NODE_RED_CLIENT_ID}" assign --rid "${RID_FULL}" --uid "${NODE_RED_UID}" > /dev/null
    ${NGSI_GO} applications --host "${IDM}" users --aid "${NODE_RED_CLIENT_ID}" assign --rid "${RID_API}" --uid "${NODE_RED_UID}" > /dev/null
    ${NGSI_GO} applications --host "${IDM}" users --aid "${ORION_CLIENT_ID}" assign --rid "${ORION_RID_API}" --uid "${NODE_RED_UID}" > /dev/null

    add_nginx_depends_on "${username}"

    mkdir "${DATA_DIR}/${username}"
    ${SUDO} chown 1000:1000 "${DATA_DIR}/${username}"

    echo -e "https://${NODE_RED}${http_admin_root}\t${username}@${DOMAIN_NAME}\t${password}" >> "${NODE_RED_USERS_TEXT}"

  cat <<EOF >> .env
${env_val}CLIENT_ID=${NODE_RED_CLIENT_ID}
${env_val}CLIENT_SECRET=${NODE_RED_CLIENT_SECRET}
${env_val}CALLBACK_URL=${NODE_RED_CALLBACK_URL}
EOF
  done

  sed -i -e "/__NODE_RED_SERVER__/d" "${node_red_nginx}"
}

#
# Node-RED
#
setup_node_red() {
  if [ -z "${NODE_RED}" ]; then
    return
  fi

  logging_info "${FUNCNAME[0]}"

  cp -r "${SETUP_DIR}"/docker/node-red "${CONFIG_DIR}"/
  cp "${CONTRIB_DIR}/node-red-contrib-FIWARE_official/contextbroker.js" "${CONFIG_DIR}"/node-red/contextbroker.js

  cd "${CONFIG_DIR}"/node-red > /dev/null
  ${DOCKER} build -t "${IMAGE_NODE_RED}" .
  cd - > /dev/null

  if [ "${NODE_RED_INSTANCE_NUMBER}" -ge 2 ]; then
    setup_node_red_multi_instance
    return
  fi

  add_docker_compose_yml "docker-node-red.yml"

  create_nginx_conf "${NODE_RED}" "nginx-node-red"

  add_nginx_depends_on  "node-red"

  add_rsyslog_conf "node-red"

  NODE_RED_URL=https://${NODE_RED}/
  NODE_RED_CALLBACK_URL=https://${NODE_RED}/auth/strategy/callback
  
  # Create application for Node-RED
  NODE_RED_CLIENT_ID=$(${NGSI_GO} applications --host "${IDM}" create --name "Node-RED" --description "Node-RED application" --url "${NODE_RED_URL}" --redirectUri "${NODE_RED_CALLBACK_URL}")
  NODE_RED_CLIENT_SECRET=$(${NGSI_GO} applications --host "${IDM}" get --aid "${NODE_RED_CLIENT_ID}" | jq -r .application.secret )

  # Create roles and add them to Admin
  RID=$(${NGSI_GO} applications --host "${IDM}" roles --aid "${NODE_RED_CLIENT_ID}" create --name "/node-red/full")
  ${NGSI_GO} applications --host "${IDM}" users --aid "${NODE_RED_CLIENT_ID}" assign --rid "${RID}" --uid "${IDM_ADMIN_UID}" > /dev/null
  ${NGSI_GO} applications --host "${IDM}" roles --aid "${NODE_RED_CLIENT_ID}" create --name "/node-red/read" > /dev/null
  RID=$(${NGSI_GO} applications --host "${IDM}" roles --aid "${NODE_RED_CLIENT_ID}" create --name "/node-red/api")
  ${NGSI_GO} applications --host "${IDM}" users --aid "${NODE_RED_CLIENT_ID}" assign --rid "${RID}" --uid "${IDM_ADMIN_UID}" > /dev/null

  # Add Wilma application as a trusted application to Node-RED application
  ${NGSI_GO} applications --host "${IDM}" trusted --aid "${NODE_RED_CLIENT_ID}" add --tid "${ORION_CLIENT_ID}"  > /dev/null
  RID=$(${NGSI_GO} applications --host "${IDM}" roles --aid "${ORION_CLIENT_ID}" create --name "/node-red/api")
  ${NGSI_GO} applications --host "${IDM}" users --aid "${ORION_CLIENT_ID}" assign --rid "${RID}" --uid "${IDM_ADMIN_UID}" > /dev/null

  mkdir "${DATA_DIR}"/node-red
  ${SUDO} chown 1000:1000 "${DATA_DIR}"/node-red

  cat <<EOF >> .env

# Node-RED

NODE_RED_CLIENT_ID=${NODE_RED_CLIENT_ID}
NODE_RED_CLIENT_SECRET=${NODE_RED_CLIENT_SECRET}
NODE_RED_CALLBACK_URL=${NODE_RED_CALLBACK_URL}
EOF
}

#
# Grafana
#
setup_grafana() {
  if [ -z "${GRAFANA}" ]; then
    return
  fi

  logging_info "${FUNCNAME[0]}"

  add_docker_compose_yml "/docker-grafana.yml"

  create_nginx_conf "${GRAFANA}" "nginx-grafana"

  add_nginx_depends_on  "grafana"

  add_rsyslog_conf "grafana"

  # Create application for Grafana
  GF_SERVER_ROOT_URL=https://${GRAFANA}/
  GF_SERVER_REDIRECT_URL=https://${GRAFANA}/login/generic_oauth
  GRAFANA_CLIENT_ID=$(${NGSI_GO} applications --host "${IDM}" create --name "Grafana" --description "Grafana application" --url "${GF_SERVER_ROOT_URL}" --redirectUri "${GF_SERVER_REDIRECT_URL}" --responseType "code,token,id_token")
  GRAFANA_CLIENT_SECRET=$(${NGSI_GO} applications --host "${IDM}" get --aid "${GRAFANA_CLIENT_ID}" | jq -r .application.secret )

  mkdir -p "${DATA_DIR}"/grafana
  ${SUDO} chown 472:472 "${DATA_DIR}"/grafana

  cat <<EOF >> .env

# Grafana

GRAFANA_CLIENT_ID=${GRAFANA_CLIENT_ID}
GRAFANA_CLIENT_SECRET=${GRAFANA_CLIENT_SECRET}

GF_SERVER_DOMAIN=${GRAFANA}
GF_SERVER_ROOT_URL=${GF_SERVER_ROOT_URL}

GF_AUTH_DISABLE_LOGIN_FORM=true
GF_AUTH_SIGNOUT_REDIRECT_URL=https://${KEYROCK}/auth/external_logout?_method=DELETE&client_id=${GRAFANA_CLIENT_ID}

GF_AUTH_GENERIC_OAUTH_NAME=keyrock
GF_AUTH_GENERIC_OAUTH_ENABLED=true
GF_AUTH_GENERIC_OAUTH_ALLOW_SIGN_UP=false
GF_AUTH_GENERIC_OAUTH_CLIENT_ID=${GRAFANA_CLIENT_ID}
GF_AUTH_GENERIC_OAUTH_CLIENT_SECRET=${GRAFANA_CLIENT_SECRET}
GF_AUTH_GENERIC_OAUTH_SCOPES=openid
GF_AUTH_GENERIC_OAUTH_EMAIL_ATTRIBUTE_NAME=email
GF_AUTH_GENERIC_OAUTH_AUTH_URL=https://${KEYROCK}/oauth2/authorize
GF_AUTH_GENERIC_OAUTH_TOKEN_URL=https://${KEYROCK}/oauth2/token
GF_AUTH_GENERIC_OAUTH_API_URL=https://${KEYROCK}/user

GF_INSTALL_PLUGINS="https://github.com/orchestracities/grafana-map-plugin/archive/master.zip;grafana-map-plugin,grafana-clock-panel,grafana-worldmap-panel"
EOF
}

setup_postfix() {
  if ! ${POSTFIX}; then
    return
  fi

  logging_info "${FUNCNAME[0]}"

  cp -r "${SETUP_DIR}"/docker/postfix "${CONFIG_DIR}"/

  cd "${CONFIG_DIR}"/postfix > /dev/null
  ${DOCKER} build -t "${IMAGE_POSTFIX}" .
  cd - > /dev/null

  add_docker_compose_yml "docker-postfix.yml"

  local file

  for file in main.cf transport_maps aliases.regexp
  do
    sed -i -e "/__POSTFIX_VOLUMES__/i \      - ${CONFIG_DIR}/postfix/${file}:/etc/postfix/${file}" "${DOCKER_COMPOSE_YML}"
    "${SUDO}" chown root.root "${CONFIG_DIR}/postfix/${file}"
    "${SUDO}" chmod 0644 "${CONFIG_DIR}/postfix/${file}"
  done

  sudo sed -i -e "/^myhostname/s/localdomain/${DOMAIN_NAME}/" "${CONFIG_DIR}/postfix/main.cf"
  sudo sed -i -e "/^mydomain/s/localdomain/${DOMAIN_NAME}/" "${CONFIG_DIR}/postfix/main.cf"

  sed -i -e "/__POSTFIX_VOLUMES__/i \      - ${DATA_DIR}/postfix/mail:/var/mail" "${DOCKER_COMPOSE_YML}"

  sed -i -e "/__KEYROCK_DEPENDS_ON__/i \      - postfix" "${DOCKER_COMPOSE_YML}"
  sed -i -e "/__KEYROCK_ENVIRONMENT__/i \      - IDM_EMAIL_HOST=postfix" "${DOCKER_COMPOSE_YML}"
  sed -i -e "/__KEYROCK_ENVIRONMENT__/i \      - IDM_EMAIL_POST=25" "${DOCKER_COMPOSE_YML}"
  sed -i -e "/__KEYROCK_ENVIRONMENT__/i \      - IDM_EMAIL_ADDRESS=${IDM_ADMIN_EMAIL}" "${DOCKER_COMPOSE_YML}"

  add_rsyslog_conf "postfix"
}

setup_ngsi_go() {
  logging_info "${FUNCNAME[0]}"

  NGSI_GO=/usr/local/bin/ngsi
  if $FIBB_TEST; then
    NGSI_GO="${NGSI_GO} --insecureSkipVerify"
  fi

  SERVERS=("$(${NGSI_GO} server list --all -1)")

  for NAME in "${APPS[@]}"
  do
    eval VAL=\"\$"$NAME"\"
    if [ -n "$VAL" ]; then
      # shellcheck disable=SC2068
      for name in ${SERVERS[@]}
      do
        if [ "${VAL}" = "${name}" ]; then
          ngsi server delete --host "${name}"
        fi
      done
    fi
  done

  for NAME in "${APPS[@]}"
  do
    eval VAL=\"\$"$NAME"\"
    if [ -n "$VAL" ]; then
      case "${NAME}" in
          "KEYROCK" ) ${NGSI_GO} server add --host "${VAL}" --serverType keyrock --serverHost "https://${VAL}" --username "${IDM_ADMIN_EMAIL}" --password "${IDM_ADMIN_PASS}" ;;
          "ORION" )  ${NGSI_GO} broker add --host "${VAL}" --ngsiType v2 --brokerHost "https://${VAL}" --idmType tokenproxy --idmHost "https://${ORION}/token" --username "${IDM_ADMIN_EMAIL}" --password "${IDM_ADMIN_PASS}" ;;
          "COMET" ) ${NGSI_GO} server add --host "${VAL}" --serverType comet --serverHost "https://${VAL}" --idmType tokenproxy --idmHost "https://${ORION}/token" --username "${IDM_ADMIN_EMAIL}" --password "${IDM_ADMIN_PASS}" ;;
          "IOTAGENT" ) ${NGSI_GO} server add --host "${VAL}" --serverType iota --serverHost "https://${VAL}" --idmType tokenproxy --idmHost "https://${ORION}/token" --username "${IDM_ADMIN_EMAIL}" --password "${IDM_ADMIN_PASS}" --service openiot --path /;;
          "WIRECLOUD" ) ${NGSI_GO} server add --host "${VAL}" --serverType wirecloud --serverHost "https://${VAL}" --idmType keyrock --idmHost "https://${KEYROCK}/oauth2/token" --username "${IDM_ADMIN_EMAIL}" --password "${IDM_ADMIN_PASS}" --clientId "${WIRECLOUD_CLIENT_ID}" --clientSecret "${WIRECLOUD_CLIENT_SECRET}";;
          "QUANTUMLEAP" ) ${NGSI_GO} server add --host "${VAL}" --serverType quantumleap --serverHost "https://${VAL}" --idmType tokenproxy --idmHost "https://${ORION}/token" --username "${IDM_ADMIN_EMAIL}" --password "${IDM_ADMIN_PASS}" ;;
      esac
    fi
  done
}

#
# update nginx file
#
update_nginx_file() {
  logging_info "${FUNCNAME[0]}"

  for name in "${APPS[@]}"
  do
    if [ "${name}" = "MOSQUITTO" ]; then
      continue
    fi
    eval val=\"\$"${name}"\"
    if [ -n "${val}" ]; then
      sed -i -e "s/SSL_CERTIFICATE_KEY/${SSL_CERTIFICATE_KEY}/" "${NGINX_SITES}"/"${val}"
      sed -i -e "s/SSL_CERTIFICATE/${SSL_CERTIFICATE}/" "${NGINX_SITES}"/"${val}"
    fi
  done
}

#
# copy scripts
#
copy_scripts() {
  logging_info "${FUNCNAME[0]}"

  mkdir "${CONFIG_DIR}/script"
  cp "${SETUP_DIR}/script/"* "${CONFIG_DIR}/script/"
  chmod a+x "${CONFIG_DIR}/script/"*

  cp "${SETUP_DIR}/_Makefile" ./Makefile
}

#
# Boot up containers
#
boot_up_containers() {
  logging_info "${FUNCNAME[0]}"

  logging_info "docker-compose up -d --build"
  ${DOCKER_COMPOSE} up -d --build

  wait "https://${KEYROCK}/" "200"
}

#
# Setup end
#
setup_end() {
  logging_info "${FUNCNAME[0]}"

  delete_from_docker_compose_yml "__NGINX_"
  delete_from_docker_compose_yml "__KEYROCK_"
  delete_from_docker_compose_yml "__WIRECLOUD_"
  delete_from_docker_compose_yml "__IOTA_"
  delete_from_docker_compose_yml "__MOSQUITTO_"
  delete_from_docker_compose_yml "__NODE_RED_"
  delete_from_docker_compose_yml "__ORION_"
  delete_from_docker_compose_yml "__POSTFIX_"

  sed -i -e "/# __NGINX_ORION_/d" "${NGINX_SITES}/${ORION}"
}

#
# clean up
#
clean_up() {
  logging_info "${FUNCNAME[0]}"

  rm -f docker-idm.yml
  rm -f docker-cert.yml
  rm -fr "${WORK_DIR}"
}

#
# parse args
#
parse_args() {

  FIBB_TEST="${FIBB_TEST:-false}"

  ERR_CODE=1
  if ${FIBB_TEST}; then
    ERR_CODE=0
  fi

  if [ $# -eq 0 ] || [ $# -ge 3 ]; then
    echo "$0 DOMAIN_NAME [GLOBAL_IP_ADDRESS]"
    exit "${ERR_CODE}"
  fi

  DOMAIN_NAME=$1
  IP_ADDRESS=

  if [ $# -ge 2 ]; then
    IP_ADDRESS=$2
  fi
}

#
# setup main
#
setup_main() {
  logging_info "${FUNCNAME[0]}"

  setup_cert

  up_keyrock

  setup_nginx
  setup_keyrock
  setup_wilma
  setup_orion
  setup_queryproxy
  setup_regproxy
  setup_comet
  setup_quantumleap
  setup_wirecloud
  setup_iotagent
  setup_node_red
  setup_grafana
  setup_postfix

  down_keyrock

  update_nginx_file
  setup_ngsi_go

  setup_logging_step2

  copy_scripts

  setup_end

  boot_up_containers

  install_widgets_for_wirecloud

  clean_up
}

init_cmd() {
  SUDO=sudo
  IS_ROOT=false 

  MOCK_PATH=""
  if $FIBB_TEST; then
    MOCK_PATH="${FIBB_TEST_MOCK_PATH-""}"
  fi

  APT="${SUDO} ${MOCK_PATH}apt"
  APT_GET="${SUDO} ${MOCK_PATH}apt-get"
  APT_KEY="${SUDO} ${MOCK_PATH}apt-key"
  ADD_APT_REPOSITORY="${SUDO} ${MOCK_PATH}add-apt-repository"
  SYSTEMCTL="${SUDO} ${MOCK_PATH}systemctl"
  YUM="${SUDO} ${MOCK_PATH}yum"
  YUM_CONFIG_MANAGER="${SUDO} ${MOCK_PATH}yum-config-manager"
  FIREWALL_CMD="${SUDO} ${MOCK_PATH}firewall-cmd"
  UNAME="${FIBB_TEST_UNAME_CMD:-uname}"
  DOCKER_CMD="${FIBB_TEST_DOCKER_CMD:-docker}"
  DOCKER_COMPOSE_CMD="/usr/local/bin/docker-compose"
  DOCKER_COMPOSE="${SUDO} ${DOCKER_COMPOSE_CMD}"
  HOST_CMD="${FIBB_TEST_HOST_CMD:-host}"
  WAIT_TIME=${FIBB_WAIT_TIME:-300}
  SKIP_INSTALL_WIDGET="${FIBB_TEST_SKIP_INSTALL_WIDGET:-false}"

  INSTALL=".install"

  DATA_DIR=./data
  WORK_DIR=./.work
  CONFIG_DIR=./config
  ENV_FILE=.env
  NODE_RED_USERS_TEXT=node-red_users.txt
}

#
# Remove unnecessary directories and files
#
remove_files() {
  if [ -e "${INSTALL}" ]; then
    for file in docker-compose.yml docker-cert.yml docker-idm.yml
    do
      if [ -e "${file}" ]; then
        set +e
        "${DOCKER_COMPOSE}" -f "${file}" down
        set -e
        sleep 5
        rm -f "${file}"
      fi
    done

    if [ -d "${DATA_DIR}" ]; then
      "${SUDO}" rm -fr "${DATA_DIR}"
    fi

    "${SUDO}" rm -fr "${CONFIG_DIR}"
    rm -fr "${WORK_DIR}"
    rm -f "${ENV_FILE}"
    rm -f "${NODE_RED_USERS_TEXT}"
  fi

  touch "${INSTALL}"
}

#
# main
#
main() {
  LANG=C

  parse_args "$@"

  init_cmd

  remove_files

  check_machine

  get_distro

  setup_init

  check_data_direcotry

  make_directories

  get_config_sh

  set_and_check_values

  setup_logging_step1

  install_commands

  setup_firewall

  check_docker
  check_docker_compose
  check_ngsi_go

  add_env

  add_domain_to_env

  validate_domain

  setup_main

  setup_complete
}

main "$@"
