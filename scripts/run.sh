#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Network / IPs
NET_NAME="${NET_NAME:-turnnet}"
SUBNET="${SUBNET:-10.244.0.0/24}"
SERVER_IP="${SERVER_IP:-10.244.0.24}"
CLIENT_IP="${CLIENT_IP:-10.244.0.25}"
SERVER_NAME="${SERVER_NAME:-turnserver}"

# Images
SERVER_IMAGE="${SERVER_IMAGE:-my-turnserver}"
CLIENT_IMAGE="${CLIENT_IMAGE:-my-turnclient}"

# TURN auth/config (must match both sides)
REALM="${REALM:-myrealm}"
TURN_USER="${TURN_USER:-demo}"
TURN_PASS="${TURN_PASS:-demo}"

# Client load
PACKETS="${PACKETS:-10}"

usage() {
  cat <<EOF
Usage:
  $(basename "$0") up        # create network, start server
  $(basename "$0") test      # run one client test
  $(basename "$0") down      # stop/remove server + network
  $(basename "$0") logs      # tail server logs
  $(basename "$0") status    # show network + containers

Env overrides (examples):
  SERVER_IMAGE=my-turnserver CLIENT_IMAGE=my-turnclient \\
  SERVER_IP=10.244.0.24 CLIENT_IP=10.244.0.25 \\
  REALM=myrealm TURN_USER=demo TURN_PASS=demo \\
  PACKETS=1000 \\
  $(basename "$0") up

EOF
}

ensure_network() {
  if docker network inspect "${NET_NAME}" >/dev/null 2>&1; then
    echo "[run] network ${NET_NAME} already exists"
  else
    echo "[run] creating network ${NET_NAME} (${SUBNET})"
    docker network create --subnet "${SUBNET}" "${NET_NAME}" >/dev/null
  fi
}

start_server() {
  if docker ps --format '{{.Names}}' | grep -qx "${SERVER_NAME}"; then
    echo "[run] server container ${SERVER_NAME} already running"
    return
  fi

  # if exists but stopped
  if docker ps -a --format '{{.Names}}' | grep -qx "${SERVER_NAME}"; then
    echo "[run] removing existing stopped container ${SERVER_NAME}"
    docker rm -f "${SERVER_NAME}" >/dev/null
  fi

  echo "[run] starting server ${SERVER_NAME} @ ${SERVER_IP}"
  docker run -d --name "${SERVER_NAME}" --network "${NET_NAME}" --ip "${SERVER_IP}" \
    -e LISTEN_IP="${SERVER_IP}" \
    -e RELAY_IP="${SERVER_IP}" \
    -e REALM="${REALM}" \
    -e TURN_USER="${TURN_USER}" \
    -e TURN_PASS="${TURN_PASS}" \
    -p 3478:3478/udp -p 3478:3478/tcp \
    -p 49160-49200:49160-49200/udp \
    "${SERVER_IMAGE}" >/dev/null

  echo "[run] server started"
}


run_client_test() {
  local mode="${1:-fg}"  # fg | bg

  echo "[run] running client test (${mode}) from ${CLIENT_IP} -> ${SERVER_IP}:3478 (PACKETS=${PACKETS})"

  # 清理残留占 IP
  docker rm -f turnclient >/dev/null 2>&1 || true

  if [ "${mode}" = "bg" ]; then
    docker run -d --name turnclient --network "${NET_NAME}" --ip "${CLIENT_IP}" \
      -e SERVER_HOST="${SERVER_IP}" \
      -e SERVER_PORT="3478" \
      -e LOCAL_IP="${CLIENT_IP}" \
      -e REALM="${REALM}" \
      -e TURN_USER="${TURN_USER}" \
      -e TURN_PASS="${TURN_PASS}" \
      -e PACKETS="${PACKETS}" \
      -e VERBOSE="1" \
      -e Y_FLAG="1" \
      "${CLIENT_IMAGE}" >/dev/null
    echo "[run] client started in background as container 'turnclient'"
    echo "[run] tail logs: ./run.sh client-logs"
  else
    docker run --rm --name turnclient --network "${NET_NAME}" --ip "${CLIENT_IP}" \
      -e SERVER_HOST="${SERVER_IP}" \
      -e SERVER_PORT="3478" \
      -e LOCAL_IP="${CLIENT_IP}" \
      -e REALM="${REALM}" \
      -e TURN_USER="${TURN_USER}" \
      -e TURN_PASS="${TURN_PASS}" \
      -e PACKETS="${PACKETS}" \
      -e VERBOSE="1" \
      -e Y_FLAG="1" \
      "${CLIENT_IMAGE}"
  fi
}




stop_all() {
  echo "[run] stopping/removing server container (if any)"
  docker rm -f "${SERVER_NAME}" >/dev/null 2>&1 || true

  echo "[run] removing network ${NET_NAME} (if any)"
  docker network rm "${NET_NAME}" >/dev/null 2>&1 || true

  echo "[run] down done"
}

show_logs() {
  docker logs -f "${SERVER_NAME}"
}

status() {
  echo "=== containers ==="
  docker ps -a --filter "name=^/${SERVER_NAME}$" || true
  echo
  echo "=== network ${NET_NAME} ==="
  docker network inspect "${NET_NAME}" >/dev/null 2>&1 && docker network inspect "${NET_NAME}" | sed -n '1,200p' || echo "(network not found)"
}

cmd="${1:-}"
case "${cmd}" in
  up)
    ensure_network
    start_server
    ;;
  test)
    ensure_network
    run_client_test fg
    ;;
  test-bg)
    ensure_network
    start_server
    run_client_test bg
    ;;
  logs)
    show_logs
    ;;
  client-logs)
    docker logs -f turnclient
    ;;  
  status)
    status
    ;;
  down)
    stop_all
    ;;
  *)
    usage
    exit 1
    ;;
esac

