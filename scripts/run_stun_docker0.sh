#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Network / IPs
# Use Docker default bridge network (host interface: docker0)
NET_NAME="${NET_NAME:-bridge}"

# (These are only used when you are NOT using default bridge)
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
PACKETS="${PACKETS:-10000}"

usage() {
  cat <<EOF
Usage:
  $(basename "$0") up        # start server
  $(basename "$0") test      # run one client test
  $(basename "$0") down      # stop/remove server (+ network if not bridge)
  $(basename "$0") logs      # tail server logs
  $(basename "$0") status    # show network + containers

Notes:
  - Default NET_NAME=bridge uses docker0.
  - On default bridge, Docker does NOT support --ip static IP assignment.

Env overrides (examples):
  NET_NAME=bridge $(basename "$0") up
  NET_NAME=turnnet SUBNET=10.244.0.0/24 SERVER_IP=10.244.0.24 CLIENT_IP=10.244.0.25 $(basename "$0") up

EOF
}

ensure_network() {
  if [ "${NET_NAME}" = "bridge" ]; then
    echo "[run] using default Docker network 'bridge' (host interface docker0) - no create needed"
    return
  fi

  if docker network inspect "${NET_NAME}" >/dev/null 2>&1; then
    echo "[run] network ${NET_NAME} already exists"
  else
    echo "[run] creating network ${NET_NAME} (${SUBNET})"
    docker network create --subnet "${SUBNET}" "${NET_NAME}" >/dev/null
  fi
}

get_container_ip() {
  local name="$1"
  docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$name"
}

start_server() {
  if docker ps --format '{{.Names}}' | grep -qx "${SERVER_NAME}"; then
    echo "[run] server container ${SERVER_NAME} already running"
    return
  fi

  if docker ps -a --format '{{.Names}}' | grep -qx "${SERVER_NAME}"; then
    echo "[run] removing existing stopped container ${SERVER_NAME}"
    docker rm -f "${SERVER_NAME}" >/dev/null
  fi

  if [ "${NET_NAME}" = "bridge" ]; then
    echo "[run] starting server ${SERVER_NAME} on default bridge (docker0)"
    docker run -d --name "${SERVER_NAME}" --network bridge \
      -e REALM="${REALM}" \
      -e TURN_USER="${TURN_USER}" \
      -e TURN_PASS="${TURN_PASS}" \
      -p 3478:3478/udp -p 3478:3478/tcp \
      -p 49160-49200:49160-49200/udp \
      "${SERVER_IMAGE}" >/dev/null

    local sip
    sip="$(get_container_ip "${SERVER_NAME}")"
    echo "[run] server started, container IP on bridge: ${sip}"
  else
    echo "[run] starting server ${SERVER_NAME} @ ${SERVER_IP} on network ${NET_NAME}"
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
  fi
}

run_client_test() {
  local mode="${1:-fg}"  # fg | bg

  # cleanup residual
  docker rm -f turnclient >/dev/null 2>&1 || true

  local server_host
  local local_ip_env=""

  if [ "${NET_NAME}" = "bridge" ]; then
    server_host="$(get_container_ip "${SERVER_NAME}")"
    if [ -z "${server_host}" ]; then
      echo "[err] server container not running or no IP found; run: $0 up"
      exit 1
    fi
    echo "[run] running client test (${mode}) on bridge -> ${server_host}:3478 (PACKETS=${PACKETS})"
    # LOCAL_IP not meaningful here because we don't control client IP on bridge
  else
    server_host="${SERVER_IP}"
    local_ip_env="-e LOCAL_IP=${CLIENT_IP}"
    echo "[run] running client test (${mode}) from ${CLIENT_IP} -> ${SERVER_IP}:3478 (PACKETS=${PACKETS})"
  fi

  if [ "${mode}" = "bg" ]; then
    if [ "${NET_NAME}" = "bridge" ]; then
      docker run -d --name turnclient --network bridge \
        -e SERVER_HOST="${server_host}" \
        -e SERVER_PORT="3478" \
        -e REALM="${REALM}" \
        -e TURN_USER="${TURN_USER}" \
        -e TURN_PASS="${TURN_PASS}" \
        -e PACKETS="${PACKETS}" \
        -e VERBOSE="1" \
        -e Y_FLAG="1" \
        "${CLIENT_IMAGE}" >/dev/null
    else
      docker run -d --name turnclient --network "${NET_NAME}" --ip "${CLIENT_IP}" \
        -e SERVER_HOST="${server_host}" \
        -e SERVER_PORT="3478" \
        ${local_ip_env} \
        -e REALM="${REALM}" \
        -e TURN_USER="${TURN_USER}" \
        -e TURN_PASS="${TURN_PASS}" \
        -e PACKETS="${PACKETS}" \
        -e VERBOSE="1" \
        -e Y_FLAG="1" \
        "${CLIENT_IMAGE}" >/dev/null
    fi
    echo "[run] client started in background as container 'turnclient'"
    echo "[run] tail logs: $0 client-logs"
  else
    if [ "${NET_NAME}" = "bridge" ]; then
      docker run --rm --name turnclient --network bridge \
        -e SERVER_HOST="${server_host}" \
        -e SERVER_PORT="3478" \
        -e REALM="${REALM}" \
        -e TURN_USER="${TURN_USER}" \
        -e TURN_PASS="${TURN_PASS}" \
        -e PACKETS="${PACKETS}" \
        -e VERBOSE="1" \
        -e Y_FLAG="1" \
        "${CLIENT_IMAGE}"
    else
      docker run --rm --name turnclient --network "${NET_NAME}" --ip "${CLIENT_IP}" \
        -e SERVER_HOST="${server_host}" \
        -e SERVER_PORT="3478" \
        ${local_ip_env} \
        -e REALM="${REALM}" \
        -e TURN_USER="${TURN_USER}" \
        -e TURN_PASS="${TURN_PASS}" \
        -e PACKETS="${PACKETS}" \
        -e VERBOSE="1" \
        -e Y_FLAG="1" \
        "${CLIENT_IMAGE}"
    fi
  fi
}

stop_all() {
  echo "[run] stopping/removing server container (if any)"
  docker rm -f "${SERVER_NAME}" >/dev/null 2>&1 || true

  if [ "${NET_NAME}" != "bridge" ]; then
    echo "[run] removing network ${NET_NAME} (if any)"
    docker network rm "${NET_NAME}" >/dev/null 2>&1 || true
  else
    echo "[run] NET_NAME=bridge: not removing default network"
  fi

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
  echo
  if [ "${NET_NAME}" = "bridge" ]; then
    echo "=== host docker0 ==="
    ip link show docker0 || true
    ip addr show docker0 || true
  fi
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

