#!/bin/sh

if [ "$1" = "haproxy" ]; then
  # Configure haproxy logging
  if [ -z "${SYSLOG_HOST}" ]; then
    export SYSLOG_HOST=$(curl -sS "http://${RANCHER_API_HOST}/${RANCHER_API_VERSION}/self/host/agent_ip")
  fi
  if [ -z "${SYSLOG_FACILITY}" ]; then
    export SYSLOG_FACILITY='daemon'
  fi
  echo "[INFO]: setting SYSLOG_HOST to: ${SYSLOG_HOST}"
  echo "[INFO]: setting SYSLOG_FACILITY to: ${SYSLOG_FACILITY}"
  sed -i -e "s/#SYSLOG_HOST#/${SYSLOG_HOST}/g" $HAPROXY_CONFIG
  sed -i -e "s/#SYSLOG_FACILITY#/${SYSLOG_FACILITY}/g" $HAPROXY_CONFIG

  # Enable ssl if wanted
  if [ "${ENABLE_SSL}" != 'false' ]; then
    echo "[INFO]: ssl enabled...configuring"

    if [ -f ${HAPROXY_SSL_CERT} ]; then
      echo "[INFO]: certificate: ${HAPROXY_SSL_CERT} already exists, skip fetching."
    else
      if [ "${SSL_BASE64_ENCODED}" != 'false' ]; then
        echo "[INFO]: getting base64 encoded ssl certificate from metadata http://${RANCHER_API_HOST}/${RANCHER_API_VERSION}/self/service/metadata/ssl_cert"
        curl -sS http://${RANCHER_API_HOST}/${RANCHER_API_VERSION}/self/service/metadata/ssl_cert | base64 -d > ${HAPROXY_SSL_CERT}

        echo "[INFO]: getting base64 encoded ssl key from metadata http://${RANCHER_API_HOST}/${RANCHER_API_VERSION}/self/service/metadata/ssl_key"
        curl -sS http://${RANCHER_API_HOST}/${RANCHER_API_VERSION}/self/service/metadata/ssl_key | base64 -d >> ${HAPROXY_SSL_CERT}
      else
        echo "[INFO]: getting ssl certificate from metadata http://${RANCHER_API_HOST}/${RANCHER_API_VERSION}/self/service/metadata/ssl_cert"
        curl -sS http://${RANCHER_API_HOST}/${RANCHER_API_VERSION}/self/service/metadata/ssl_cert > ${HAPROXY_SSL_CERT}

        echo "[INFO]: getting ssl key from metadata http://${RANCHER_API_HOST}/${RANCHER_API_VERSION}/self/service/metadata/ssl_key"
        curl -sS http://${RANCHER_API_HOST}/${RANCHER_API_VERSION}/self/service/metadata/ssl_key >> ${HAPROXY_SSL_CERT}
      fi
    fi

    echo "[INFO]: enabling ssl"
    sed -i -e "s/#ENABLE_SSL#//g" $HAPROXY_CONFIG
    echo "[INFO]: substituting ssl certificate"
    sed -i -e "s%#SSL_CERT#%${HAPROXY_SSL_CERT}%g" $HAPROXY_CONFIG

    if [ "${ENABLE_SSL_REDIRECTION}" != 'false' ]; then
      echo "[INFO]: enabling ssl redirection to ${SSL_REDIRECTION_TYPE}"
      sed -i -e "s/#ENABLE_SSL_REDIRECTION#//g" $HAPROXY_CONFIG
      sed -i -e "s/#SSL_REDIRECTION_TYPE#//g" $HAPROXY_CONFIG
    fi

  fi

  # Enable haproxy stats if wanted
  if [ "${ENABLE_STATS}" != "false" ]; then
    echo "[INFO]: enabling haproxy stats on port: ${STATS_PORT}"
    sed -i -e "s/#ENABLE_STATS#//g" $HAPROXY_CONFIG
    sed -i -e "s/#STATS_PORT#/${STATS_PORT}/g" $HAPROXY_CONFIG
    sed -i -e "s/#STATS_USERNAME#/${STATS_USERNAME}/g" $HAPROXY_CONFIG
    sed -i -e "s/#STATS_PASSWORD#/${STATS_PASSWORD}/g" $HAPROXY_CONFIG
  fi

  # Make sure initial dynamic files exist.
  touch ${HAPROXY_DOMAIN_MAP}
  touch ${HAPROXY_BACKEND_CONFIG}
  
  # Internal params
  HAPROXY_PID_FILE="/var/run/haproxy.pid"
  HAPROXY_CMD="haproxy -f ${HAPROXY_CONFIG} -f ${HAPROXY_BACKEND_CONFIG} -D -p ${HAPROXY_PID_FILE}"
  HAPROXY_CONFIG_CHECK="haproxy -f ${HAPROXY_CONFIG} -f ${HAPROXY_BACKEND_CONFIG} -c"
  
  echo "[DEBUG]: ${HAPROXY_BACKEND_CONFIG} contents:"
  cat ${HAPROXY_BACKEND_CONFIG}
  # Check the config
  ${HAPROXY_CONFIG_CHECK}
  # Start haproxy
  ${HAPROXY_CMD}
  
  if [ $? == 0 ]; then
    echo "[INFO]: haproxy started with ${HAPROXY_CONFIG} and ${HAPROXY_BACKEND_CONFIG}"
  else
    echo "[ERROR]: haproxy failed to start"
    echo "[ERROR]: ${HAPROXY_DOMAIN_MAP} contents:"
    cat ${HAPROXY_DOMAIN_MAP}
    echo "[ERROR]: ${HAPROXY_BACKEND_CONFIG} contents:"
    cat ${HAPROXY_BACKEND_CONFIG}
    exit 1
  fi
  
  while inotifywait -q -e create,delete,modify,attrib ${HAPROXY_CONFIG} ${HAPROXY_BACKEND_CONFIG}; do
    if [ -f ${HAPROXY_PID_FILE} ]; then
      echo "[INFO]: restarting haproxy from config changes..."
      ${HAPROXY_CONFIG_CHECK}
      # Since we want haproxy to continue but we want to know the current config not just the failing line
      if [ $? != 0 ]; then
        echo "[ERROR]: haproxy config test failed:"
    	echo "[ERROR]: ${HAPROXY_DOMAIN_MAP} contents:"
    	cat ${HAPROXY_DOMAIN_MAP}
    	echo "[ERROR]: ${HAPROXY_BACKEND_CONFIG} contents:"
    	cat ${HAPROXY_BACKEND_CONFIG}
      else
        ${HAPROXY_CMD} -sf $(cat ${HAPROXY_PID_FILE})
        echo "[INFO] haproxy restarted new pid: $(cat ${HAPROXY_PID_FILE})"
      fi
    else
      echo "[ERROR] haproxy pid not found exiting"
      break
    fi
  done

elif [ "$1" = "generate-maps" ]; then
  if [ "${STACK_DOMAIN}" == "none" ]; then
    echo "[ERROR]: STACK_DOMAIN MUST be defined..."
    exit 1
  fi

  # Start the metadata service config generator
  if [ "${DISABLE_METADATA}" == "false" ]; then
    echo "[INFO]: starting rancher metadata service config generator"
    python /gen-haproxy-map.py \
      --apihost "${RANCHER_API_HOST}" \
      --apiversion "${RANCHER_API_VERSION}" \
      --label "${RANCHER_LABEL}" \
      --proxylabel "${RANCHER_PROXY_LABEL}" \
      --domain "${STACK_DOMAIN}" \
      --domainmap "${HAPROXY_DOMAIN_MAP}" \
      --backends "${HAPROXY_BACKEND_CONFIG}"
  else
    echo "[ERROR]: DISABLE_METADATA: ${DISABLE_METADATA} This is an error unless your debugging without rancher..."
    exit 1
  fi
else
  exec "$@"
fi
