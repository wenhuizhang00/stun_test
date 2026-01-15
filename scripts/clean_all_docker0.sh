#!/usr/bin/env bash
set -euo pipefail

# Match keywords in the IMAGE REPOSITORY field (docker images "REPOSITORY" column)
# turn / ncclient / ncserver / <none>
PATTERN_REPO='^(<none>|.*(turn|ncclient|ncserver).*)$'

# Optional: best-effort cleanup of old user-defined network (do NOT touch default bridge/docker0)
OLD_NET_NAME="${OLD_NET_NAME:-turnnet}"

# Optional: common container names from your scripts
NAME_PATTERNS=(
  '^/turnserver$'
  '^/turnclient$'
  '^/ncserver$'
  '^/ncclient$'
)

echo "[clean] pattern(repo) = ${PATTERN_REPO}"
echo "[clean] old_net_name  = ${OLD_NET_NAME}"
echo

echo "[clean] 0) Remove common test containers by NAME (fast path)..."
for np in "${NAME_PATTERNS[@]}"; do
  docker ps -aq --filter "name=${np}" | xargs -r docker rm -f
done

echo
echo "[clean] 1) Remove containers whose IMAGE repository matches pattern..."

# Build a set of image IDs whose REPOSITORY matches pattern
mapfile -t MATCH_IMAGE_IDS < <(
  docker images --no-trunc --format '{{.Repository}} {{.ID}}' \
  | awk -v re="${PATTERN_REPO}" '$1 ~ re {print $2}' \
  | sort -u
)

if ((${#MATCH_IMAGE_IDS[@]})); then
  ALL_CIDS=$(docker ps -aq || true)
  if [ -n "${ALL_CIDS}" ]; then
    tmpfile="$(mktemp)"
    printf "%s\n" "${MATCH_IMAGE_IDS[@]}" > "${tmpfile}"

    docker inspect --format '{{.Id}} {{.Image}}' ${ALL_CIDS} 2>/dev/null \
      | awk 'NR==FNR{ids[$1]=1; next} ($2 in ids){print $1}' "${tmpfile}" - \
      | xargs -r docker rm -f

    rm -f "${tmpfile}"
  fi
else
  echo "[clean] no matching images found for container cleanup."
fi

echo
echo "[clean] 2) Remove images whose REPOSITORY matches pattern..."

docker images --no-trunc --format '{{.Repository}} {{.ID}}' \
  | awk -v re="${PATTERN_REPO}" '$1 ~ re {print $2}' \
  | sort -u \
  | xargs -r docker image rm -f

echo
echo "[clean] 3) Remove dangling <none> images (extra safety)..."
docker images -f dangling=true -q | xargs -r docker image rm -f

echo
echo "[clean] 4) Remove old user-defined network if present (do NOT touch default bridge)..."
if [ "${OLD_NET_NAME}" != "bridge" ] && docker network inspect "${OLD_NET_NAME}" >/dev/null 2>&1; then
  docker network rm "${OLD_NET_NAME}" >/dev/null 2>&1 || true
  echo "[clean] removed network ${OLD_NET_NAME}"
else
  echo "[clean] skip network removal (not found or is 'bridge')"
fi

echo
echo "[clean] done."

