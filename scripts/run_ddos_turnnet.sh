#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Network / IPs
NET_NAME="${NET_NAME:-turnnet}"
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
  $(basename "$0") up           # create network, start UDP server (tcpdump+nc)
  $(basename "$0") test         # run client once (fg)
  $(basename "$0") test-bg      # run client in background (container kept)
  $(basename "$0") logs         # tail server logs
  $(basename "$0") client-logs  # tail client logs (when test-bg)
  $(basename "$0") status       # show containers + network
  $(basename "$0") down         # stop server + remove network (best-effort)

Env overrides:
  NET_NAME=turnnet SUBNET=10.244.0.0/24 \\
  SERVER_IP=10.244.0.24 CLIENT_IP=10.244.0.25 \\
  SERVER_IMAGE=ncserver CLIENT_IMAGE=ncclient \\
  PORT=3478 IFACE=any \\
  COUNT=1000 PPS=500 PAYLOAD_BYTES=128 \\
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

  # remove stopped server if any
  if docker ps -a --format '{{.Names}}' | grep -qx "${SERVER_NAME}"; then
    echo "[run] removing existing stopped container ${SERVER_NAME}"
    docker rm -f "${SERVER_NAME}" >/dev/null
  fi

  echo "[run] starting server ${SERVER_NAME} @ ${SERVER_IP}:${PORT}"
  docker run -d --name "${SERVER_NAME}" --network "${NET_NAME}" --ip "${SERVER_IP}" \
    --cap-add=NET_ADMIN --cap-add=NET_RAW \
    -e PORT="${PORT}" -e IFACE="${IFACE}" \
    "${SERVER_IMAGE}" >/dev/null

  echo "[run] server started"
  echo "[run] tail logs: ./run.sh logs"
}

run_client() {
  local mode="${1:-fg}" # fg|bg

  echo "[run] running client (${mode}) ${CLIENT_IP} -> ${SERVER_IP}:${PORT} (COUNT=${COUNT} PPS=${PPS} BYTES=${PAYLOAD_BYTES})"

  # remove any old client container to avoid IP conflicts
  docker rm -f "${CLIENT_NAME}" >/dev/null 2>&1 || true

  if [[ "${mode}" == "bg" ]]; then
    docker run -d --name "${CLIENT_NAME}" --network "${NET_NAME}" --ip "${CLIENT_IP}" \
      -e DST_HOST="${SERVER_IP}" \
      -e DST_PORT="${PORT}" \
      -e COUNT="${COUNT}" \
      -e PPS="${PPS}" \
      -e PAYLOAD_BYTES="${PAYLOAD_BYTES}" \
      "${CLIENT_IMAGE}" >/dev/null
    echo "[run] client started in background as '${CLIENT_NAME}'"
    echo "[run] tail logs: ./run.sh client-logs"
  else
    docker run --rm --name "${CLIENT_NAME}" --network "${NET_NAME}" --ip "${CLIENT_IP}" \
      -e DST_HOST="${SERVER_IP}" \
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
}

down() {
  echo "[run] stopping/removing client (if any)"
  docker rm -f "${CLIENT_NAME}" >/dev/null 2>&1 || true

  echo "[run] stopping/removing server (if any)"
  docker rm -f "${SERVER_NAME}" >/dev/null 2>&1 || true

  echo "[run] removing network ${NET_NAME} (if any)"
  docker network rm "${NET_NAME}" >/dev/null 2>&1 || true

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

