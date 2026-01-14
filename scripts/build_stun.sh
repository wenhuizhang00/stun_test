#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DOCKERFILES_DIR="${ROOT_DIR}/Dockerfiles"

SERVER_IMAGE="${SERVER_IMAGE:-my-turnserver}"
CLIENT_IMAGE="${CLIENT_IMAGE:-my-turnclient}"

echo "[build] ROOT_DIR=${ROOT_DIR}"
echo "[build] DOCKERFILES_DIR=${DOCKERFILES_DIR}"
echo "[build] SERVER_IMAGE=${SERVER_IMAGE}"
echo "[build] CLIENT_IMAGE=${CLIENT_IMAGE}"

docker build -t "${SERVER_IMAGE}" -f "${DOCKERFILES_DIR}/Dockerfile.turnserver" "${ROOT_DIR}"
docker build -t "${CLIENT_IMAGE}" -f "${DOCKERFILES_DIR}/Dockerfile.turnclient" "${ROOT_DIR}"

echo "[build] done"

