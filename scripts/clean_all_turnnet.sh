#!/usr/bin/env bash
set -euo pipefail

# Match keywords in the IMAGE REPOSITORY field (docker images "REPOSITORY" column)
# turn / ncclient / ncserver / <none>
PATTERN_REPO='^(<none>|.*(turn|ncclient|ncserver).*)$'

echo "[clean] pattern(repo) = ${PATTERN_REPO}"

echo
echo "[clean] 1) Remove containers whose IMAGE repository matches pattern..."

# Build a set of image IDs whose REPOSITORY matches pattern
mapfile -t MATCH_IMAGE_IDS < <(
  docker images --no-trunc --format '{{.Repository}} {{.ID}}' \
  | awk -v re="${PATTERN_REPO}" '$1 ~ re {print $2}' \
  | sort -u
)

if ((${#MATCH_IMAGE_IDS[@]})); then
  # Remove containers that are based on those image IDs
  # docker ps -a can show .Image as name; we need image ID per container -> use docker inspect
  # Faster: list container IDs, inspect their Image field, match against IDs set.
  ALL_CIDS=$(docker ps -aq || true)
  if [ -n "${ALL_CIDS}" ]; then
    # Create a lookup file for image IDs
    tmpfile="$(mktemp)"
    printf "%s\n" "${MATCH_IMAGE_IDS[@]}" > "${tmpfile}"

    # For each container, print: <cid> <imageID>
    # Then match imageID in tmpfile, remove those containers.
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

# Remove matching images (by ID)
docker images --no-trunc --format '{{.Repository}} {{.ID}}' \
  | awk -v re="${PATTERN_REPO}" '$1 ~ re {print $2}' \
  | sort -u \
  | xargs -r docker image rm -f

echo
echo "[clean] 3) Remove dangling <none> images (extra safety)..."
docker images -f dangling=true -q | xargs -r docker image rm -f

echo
echo "[clean] done."

