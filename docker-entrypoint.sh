#!/bin/sh
set -e


if [ "$1" == 'haproxy' ]; then
  if [ -z "${SYSLOG_HOST}" ]; then
      export SYSLOG_HOST='127.0.0.1'
  fi
  if [ -z "${SYSLOG_FACILITY}" ]; then
      export SYSLOG_FACILITY='daemon'
  fi
  
  sed -i -e "s/#SYSLOG_HOST#/${SYSLOG_HOST}/g" $HAPROXY_CONFIG
  sed -i -e "s/#SYSLOG_FACILITY#/${SYSLOG_FACILITY}/g" $HAPROXY_CONFIG
  
  touch ${HAPROXY_DOMAIN_MAP}
  touch ${HAPROXY_BACKEND_CONFIG}
  
  # Internal params
  HAPROXY_PID_FILE="/var/run/haproxy.pid"
  HAPROXY_CMD="haproxy -f ${HAPROXY_CONFIG} -f ${HAPROXY_BACKEND_CONFIG} -D -p ${HAPROXY_PID_FILE}"
  HAPROXY_CONFIG_CHECK="haproxy -f ${HAPROXY_CONFIG} -f ${HAPROXY_BACKEND_CONFIG} -c"
  
  # Start the metadata service config generator
  echo "[INFO]: starting rancher metadata service config generator"
  python /gen-haproxy-map.py --domain "${STACK_DOMAIN}" &

  sleep 5
  echo "[DEBUG]: contents:"
  cat ${HAPROXY_BACKEND_CONFIG}
  # Check the config
  ${HAPROXY_CONFIG_CHECK}
  # Start haproxy
  ${HAPROXY_CMD}
  
  if [ $? == 0 ]; then
    echo "[INFO]: haproxy started with ${HAPROXY_CONFIG} and ${HAPROXY_BACKEND_CONFIG}"
  else
    echo "[ERROR]: haproxy failed to start"
  fi
  
  while inotifywait -q -e create,delete,modify,attrib ${HAPROXY_CONFIG} ${HAPROXY_BACKEND_CONFIG}; do
    if [ -f ${HAPROXY_PID_FILE} ]; then
      echo "[INFO]: restarting haproxy from config changes..."
      ${HAPROXY_CONFIG_CHECK}
      ${HAPROXY_CMD} -sf $(cat ${HAPROXY_PID_FILE})
      echo "[INFO] haproxy restarted new pid: $(cat ${HAPROXY_PID_FILE})"
    else
      echo "[ERROR] haproxy pid not found exiting"
      break
    fi
  done
else
  exec "$@"
fi
