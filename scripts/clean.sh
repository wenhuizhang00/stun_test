#!/usr/bin/env bash
set -euo pipefail

NET_NAME="${NET_NAME:-turnnet}"
SERVER_NAME="${SERVER_NAME:-turnserver}"

echo "[clean] removing known containers"
docker rm -f "${SERVER_NAME}" >/dev/null 2>&1 || true
docker rm -f turnclient >/dev/null 2>&1 || true

if docker network inspect "${NET_NAME}" >/dev/null 2>&1; then
  echo "[clean] network ${NET_NAME} exists, removing all attached containers..."
  # 列出所有挂在 network 上的容器名并强制删除
  mapfile -t NAMES < <(docker network inspect "${NET_NAME}" \
    --format '{{range $id,$c := .Containers}}{{$c.Name}}{{"\n"}}{{end}}')

  for n in "${NAMES[@]}"; do
    [ -z "$n" ] && continue
    echo "  - rm -f $n"
    docker rm -f "$n" >/dev/null 2>&1 || true
  done

  echo "[clean] removing network ${NET_NAME}"
  docker network rm "${NET_NAME}" >/dev/null 2>&1 || true
else
  echo "[clean] network ${NET_NAME} not found"
fi

echo "[clean] done"

