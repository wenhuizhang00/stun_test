#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DOCKERFILES_DIR="${ROOT_DIR}/Dockerfiles"

SERVER_IMAGE="${SERVER_IMAGE:-ncserver}"
CLIENT_IMAGE="${CLIENT_IMAGE:-ncclient}"

echo "[build] ROOT_DIR=${ROOT_DIR}"
echo "[build] DOCKERFILES_DIR=${DOCKERFILES_DIR}"
echo "[build] SERVER_IMAGE=${SERVER_IMAGE}"
echo "[build] CLIENT_IMAGE=${CLIENT_IMAGE}"

NO_CACHE="${NO_CACHE:-0}"
CACHE_ARG=()
if [[ "${NO_CACHE}" == "1" ]]; then
  CACHE_ARG=(--no-cache)
  echo "[build] no-cache enabled"
fi

# Build server
docker build "${CACHE_ARG[@]}" \
  -f "${DOCKERFILES_DIR}/Dockerfile.ncserver" \
  -t "${SERVER_IMAGE}" \
  "${ROOT_DIR}"

# Build client
docker build "${CACHE_ARG[@]}" \
  -f "${DOCKERFILES_DIR}/Dockerfile.ncclient" \
  -t "${CLIENT_IMAGE}" \
  "${ROOT_DIR}"

echo "[build] done"

