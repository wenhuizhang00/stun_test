#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Network / IPs
# Use Docker default bridge network (host interface: docker0) by default
NET_NAME="${NET_NAME:-bridge}"

# (Only used when NET_NAME != bridge)
SUBNET="${SUBNET:-10.244.0.0/24}"
SERVER_IP="${SERVER_IP:-10.244.0.24}"
CLIENT_IP="${CLIENT_IP:-10.244.0.25}"

# Containers
SERVER_NAME="${SERVER_NAME:-ncserver}"
CLIENT_NAME="${CLIENT_NAME:-ncclient}"

# Images
SERVER_IMAGE="${SERVER_IMAGE:-ncserver}"
CLIENT_IMAGE="${CLIENT_IMAGE:-ncclient}"

# Server config
PORT="${PORT:-3478}"
IFACE="${IFACE:-any}"

# Client load
COUNT="${COUNT:-200}"
PPS="${PPS:-200}"
PAYLOAD_BYTES="${PAYLOAD_BYTES:-64}"

usage() {
  cat <<EOF
Usage:
  $(basename "$0") up           # start UDP server (tcpdump+nc)
  $(basename "$0") test         # run client once (fg)
  $(basename "$0") test-bg      # run client in background (container kept)
  $(basename "$0") logs         # tail server logs
  $(basename "$0") client-logs  # tail client logs (when test-bg)
  $(basename "$0") status       # show containers + network
  $(basename "$0") down         # stop server (+ remove network if not bridge)

Notes:
  - Default NET_NAME=bridge uses docker0.
  - Default bridge does NOT support static --ip assignment.

Env overrides:
  NET_NAME=bridge $(basename "$0") up
  NET_NAME=turnnet SUBNET=10.244.0.0/24 SERVER_IP=10.244.0.24 CLIENT_IP=10.244.0.25 $(basename "$0") up

EOF
}

get_container_ip() {
  local name="$1"
  docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$name"
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

start_server() {
  if docker ps --format '{{.Names}}' | grep -qx "${SERVER_NAME}"; then
    echo "[run] server container ${SERVER_NAME} already running"
    return
  fi

  # remove stopped server if any
  if docker ps -a --format '{{.Names}}' | grep -qx "${SERVER_NAME}"; then
    echo "[run] removing existing stopped container ${SERVER_NAME}"
    docker rm -f "${SERVER_NAME}" >/dev/null
  fi

  if [ "${NET_NAME}" = "bridge" ]; then
    echo "[run] starting server ${SERVER_NAME} on default bridge (docker0) :${PORT}"
    docker run -d --name "${SERVER_NAME}" --network bridge \
      --cap-add=NET_ADMIN --cap-add=NET_RAW \
      -e PORT="${PORT}" -e IFACE="${IFACE}" \
      "${SERVER_IMAGE}" >/dev/null

    local sip
    sip="$(get_container_ip "${SERVER_NAME}")"
    echo "[run] server started, container IP on bridge: ${sip}:${PORT}"
  else
    echo "[run] starting server ${SERVER_NAME} @ ${SERVER_IP}:${PORT} on network ${NET_NAME}"
    docker run -d --name "${SERVER_NAME}" --network "${NET_NAME}" --ip "${SERVER_IP}" \
      --cap-add=NET_ADMIN --cap-add=NET_RAW \
      -e PORT="${PORT}" -e IFACE="${IFACE}" \
      "${SERVER_IMAGE}" >/dev/null
    echo "[run] server started"
  fi

  echo "[run] tail logs: ./${0##*/} logs"
}

run_client() {
  local mode="${1:-fg}" # fg|bg

  # remove any old client container
  docker rm -f "${CLIENT_NAME}" >/dev/null 2>&1 || true

  local dst_host
  local client_net_args=()
  local pretty_src=""

  if [ "${NET_NAME}" = "bridge" ]; then
    dst_host="$(get_container_ip "${SERVER_NAME}")"
    if [ -z "${dst_host}" ]; then
      echo "[err] server not running or IP not found; run: ./${0##*/} up"
      exit 1
    fi
    client_net_args=(--network bridge)
    pretty_src="(src ip auto)"
  else
    dst_host="${SERVER_IP}"
    client_net_args=(--network "${NET_NAME}" --ip "${CLIENT_IP}")
    pretty_src="${CLIENT_IP}"
  fi

  echo "[run] running client (${mode}) ${pretty_src} -> ${dst_host}:${PORT} (COUNT=${COUNT} PPS=${PPS} BYTES=${PAYLOAD_BYTES})"

  if [[ "${mode}" == "bg" ]]; then
    docker run -d --name "${CLIENT_NAME}" "${client_net_args[@]}" \
      -e DST_HOST="${dst_host}" \
      -e DST_PORT="${PORT}" \
      -e COUNT="${COUNT}" \
      -e PPS="${PPS}" \
      -e PAYLOAD_BYTES="${PAYLOAD_BYTES}" \
      "${CLIENT_IMAGE}" >/dev/null
    echo "[run] client started in background as '${CLIENT_NAME}'"
    echo "[run] tail logs: ./${0##*/} client-logs"
  else
    docker run --rm --name "${CLIENT_NAME}" "${client_net_args[@]}" \
      -e DST_HOST="${dst_host}" \
      -e DST_PORT="${PORT}" \
      -e COUNT="${COUNT}" \
      -e PPS="${PPS}" \
      -e PAYLOAD_BYTES="${PAYLOAD_BYTES}" \
      "${CLIENT_IMAGE}"
  fi
}

show_logs() {
  docker logs -f "${SERVER_NAME}"
}

client_logs() {
  docker logs -f "${CLIENT_NAME}"
}

status() {
  echo "=== containers ==="
  docker ps -a --filter "name=^/${SERVER_NAME}$" --filter "name=^/${CLIENT_NAME}$" || true
  echo
  echo "=== network ${NET_NAME} containers ==="
  if docker network inspect "${NET_NAME}" >/dev/null 2>&1; then
    docker network inspect "${NET_NAME}" --format '{{range $id,$c := .Containers}}{{$c.Name}} {{$c.IPv4Address}}{{"\n"}}{{end}}'
  else
    echo "(network not found)"
  fi
  echo
  if [ "${NET_NAME}" = "bridge" ]; then
    echo "=== host docker0 ==="
    ip link show docker0 || true
    ip addr show docker0 || true
  fi
}

down() {
  echo "[run] stopping/removing client (if any)"
  docker rm -f "${CLIENT_NAME}" >/dev/null 2>&1 || true

  echo "[run] stopping/removing server (if any)"
  docker rm -f "${SERVER_NAME}" >/dev/null 2>&1 || true

  if [ "${NET_NAME}" != "bridge" ]; then
    echo "[run] removing network ${NET_NAME} (if any)"
    docker network rm "${NET_NAME}" >/dev/null 2>&1 || true
  else
    echo "[run] NET_NAME=bridge: not removing default network"
  fi

  echo "[run] down done"
}

cmd="${1:-}"
case "${cmd}" in
  up)
    ensure_network
    start_server
    ;;
  test)
    ensure_network
    start_server
    run_client fg
    ;;
  test-bg)
    ensure_network
    start_server
    run_client bg
    ;;
  logs)
    show_logs
    ;;
  client-logs)
    client_logs
    ;;
  status)
    status
    ;;
  down)
    down
    ;;
  *)
    usage
    exit 1
    ;;
esac

