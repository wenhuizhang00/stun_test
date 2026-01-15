# stun_test

This repo contains **two end-to-end traffic tests** to validate Grimlock RFW TC hooks + userspace outputs.

- **Test 1: STUN/TURN** — expect traffic visible (RX/TX increases) and client prints packets.
- **Test 2: UDP “DDOS-like”** — expect mostly TX only, client prints nothing, RFW prints alerts.

Repository layout:


```
# tree ./
./
├── Dockerfiles
│   ├── Dockerfile.ncclient
│   ├── Dockerfile.ncserver
│   ├── Dockerfile.turnclient
│   └── Dockerfile.turnserver
├── README.md
└── scripts
    ├── build_ddos.sh
    ├── build_stun.sh
    ├── clean_all_docker0.sh
    ├── clean_all_turnnet.sh
    ├── run_ddos_docker0.sh
    ├── run_ddos_turnnet.sh
    ├── run_stun_docker0.sh
    └── run_stun_turnnet.sh

2 directories, 13 files
```

## Prerequisites

- Docker installed and working
- `bpftool` available on host
- You can run RFW on the host (typically `sudo ./rfw ...`)
- Default mode recommended: **docker0 / default bridge** via `*_docker0.sh`

---

## Build images

### STUN/TURN images
```bash
chmod +x scripts/*.sh
./scripts/build_stun.sh
```

### DDOS images
```
chmod +x scripts/*.sh
./scripts/build_ddos.sh

```


## Cleanup
```
./scripts/clean_all_docker0.sh
# or (for old turnnet mode)
./scripts/clean_all_turnnet.sh
```



## Test 1 — STUN/TURN

```
#!/usr/bin/env bash
# test_stun_turn.sh
#
# Test 1 — STUN/TURN
# Goal:
#   Validate that RFW TC hooks capture STUN/TURN-like UDP traffic on docker0/veth
#   and that the *client* prints packet details while counters (RX/TX) increase.
#
# What you should observe:
#   1) RFW attaches TC hooks on docker0/lo/enp*/veth* (bpftool net)
#   2) docker0 + relevant veth* show RX and TX increasing (ip -s link)
#   3) STUN client console prints packets
#   4) RFW logs show:
#        - create probe on interface: ...
#        - [veth hook] attached tc on: ...
#
# Usage:
#   ./test_stun_turn.sh docker0     # recommended (default bridge, docker0)
#   ./test_stun_turn.sh turnnet     # user-defined bridge with static IPs
#
# Notes:
#   - This script DOES NOT launch RFW for you; it prints the exact command.
#   - Run RFW on the host with sudo in another terminal/session.

set -euo pipefail

MODE="${1:-docker0}"   # docker0 | turnnet
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STUN_SCRIPT=""

case "${MODE}" in
  docker0) STUN_SCRIPT="${ROOT_DIR}/scripts/run_stun_docker0.sh" ;;
  turnnet) STUN_SCRIPT="${ROOT_DIR}/scripts/run_stun_turnnet.sh" ;;
  *)
    echo "[ERROR] Unknown mode: ${MODE}. Use: docker0 | turnnet"
    exit 1
    ;;
esac

echo
echo "=============================="
echo " Test 1 — STUN/TURN (${MODE}) "
echo "=============================="
echo

# ----------------------------
# Step A — Start server
# ----------------------------
echo "[Step A] Start STUN/TURN server container"
echo "  -> ${STUN_SCRIPT} up"
"${STUN_SCRIPT}" up

echo
echo "[Info] Server started."
echo "  - If you want to inspect containers: docker ps"
echo "  - If you want server logs:          ${STUN_SCRIPT} logs"
echo

# ----------------------------
# Step B — Run client test
# ----------------------------
echo "[Step B] Run STUN/TURN client test (foreground)"
echo "  -> ${STUN_SCRIPT} test"
"${STUN_SCRIPT}" test

echo
echo "[Expected] Client should print packet details above."
echo

# ----------------------------
# Step C — Start RFW (STUN enabled)
# ----------------------------
cat <<'EOF'

[Step C] Start RFW on the host (STUN enabled) in another terminal:

  cd ~/wenhui/grimlock
  sudo ./rfw \
    -data-center="snc2" \
    -server-type="grimlock-test" \
    -drop-skb=false \
    -stun=true \
    -rule-path="/etc/rfw/rules/"

Expected in RFW logs:
  - create probe on interface: ...
  - [veth hook] attached tc on: ...
EOF

# ----------------------------
# Step D — Verify TC hooks exist (bpftool)
# ----------------------------
cat <<'EOF'

[Step D] Verify TC hooks exist (bpftool):

  sudo bpftool net

Expected: tc ingress/egress programs attached on:
  - docker0 (if using docker0 mode)
  - lo
  - host NIC (e.g. enp*)
  - veth* (container host-side veth)
EOF

# ----------------------------
# Step E — Verify interface counters (RX/TX increases)
# ----------------------------
cat <<'EOF'

[Step E] Verify interface counters increase (RX/TX):

  # docker0 counters
  ip -s link show docker0

  # veth counters (show all veth blocks)
  ip -s link show | grep -A4 -E '^[0-9]+: veth'

Expected (STUN/TURN):
  - docker0 and relevant veth* show RX and TX increasing
  - Client prints packets
  - RFW logs show hook creation
EOF

echo
echo "[Done] Test 1 script finished. If results do not match expectations, compare:"
echo "  - bpftool net output"
echo "  - ip -s link counters"
echo "  - client stdout"
echo "  - RFW logs"
echo

```



## Test 2 — UDP “DDOS-like”

```
#!/usr/bin/env bash
# test_ddos_udp.sh
#
# Test 2 — UDP “DDOS-like”
# Goal:
#   Validate that high-rate UDP sending triggers RFW alerts while client prints nothing,
#   and interface counters show mostly TX increases (little/no RX on the expected path).
#
# What you should observe:
#   1) RFW attaches TC hooks on docker0/lo/enp*/veth* (bpftool net)
#   2) docker0 + relevant veth* show TX increasing; RX should not increase (or very small)
#   3) DDOS client console prints nothing
#   4) RFW prints alerts (drop/alert log lines)
#
# Usage:
#   ./test_ddos_udp.sh docker0     # recommended (default bridge, docker0)
#   ./test_ddos_udp.sh turnnet     # user-defined bridge with static IPs
#
# Notes:
#   - This script DOES NOT launch RFW for you; it prints the exact command.
#   - If your alert pipeline depends on STUN parsing, run RFW with -stun=true instead.

set -euo pipefail

MODE="${1:-docker0}"   # docker0 | turnnet
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DDOS_SCRIPT=""

case "${MODE}" in
  docker0) DDOS_SCRIPT="${ROOT_DIR}/scripts/run_ddos_docker0.sh" ;;
  turnnet) DDOS_SCRIPT="${ROOT_DIR}/scripts/run_ddos_turnnet.sh" ;;
  *)
    echo "[ERROR] Unknown mode: ${MODE}. Use: docker0 | turnnet"
    exit 1
    ;;
esac

echo
echo "================================="
echo " Test 2 — UDP DDOS-like (${MODE}) "
echo "================================="
echo

# ----------------------------
# Step A — Start server
# ----------------------------
echo "[Step A] Start UDP server container (nc + optional tcpdump inside image)"
echo "  -> ${DDOS_SCRIPT} up"
"${DDOS_SCRIPT}" up

echo
echo "[Info] Server started."
echo "  - If you want to inspect containers: docker ps"
echo "  - If you want server logs:          ${DDOS_SCRIPT} logs"
echo

# ----------------------------
# Step B — Run client test
# ----------------------------
echo "[Step B] Run UDP client test (foreground)"
echo "  -> ${DDOS_SCRIPT} test"
"${DDOS_SCRIPT}" test

echo
echo "[Expected] Client should print nothing (or minimal), because it's a send-only style load."
echo

# ----------------------------
# Step C — Start RFW (alerts expected)
# ----------------------------
cat <<'EOF'

[Step C] Start RFW on the host (alerts expected) in another terminal:

  cd ~/wenhui/grimlock
  sudo ./rfw \
    -data-center="snc2" \
    -server-type="grimlock-test" \
    -drop-skb=false \
    -stun=true \
    -rule-path="/etc/rfw/rules/"

If your alert pipeline depends on STUN parsing, run with:
  -stun=true

Expected in RFW logs:
  - tc hooks created (docker0/lo/enp*/veth*)
  - alerts printed (drop/alert log lines)
EOF

# ----------------------------
# Step D — Verify TC hooks exist (bpftool)
# ----------------------------
cat <<'EOF'

[Step D] Verify TC hooks exist (bpftool):

  sudo bpftool net

Expected: same as Test 1 — tc hooks on docker0/lo/enp*/veth*.
EOF

# ----------------------------
# Step E — Verify interface counters (TX increases, no RX)
# ----------------------------
cat <<'EOF'

[Step E] Verify interface counters (TX increases, no RX):

  ip -s link show docker0
  ip -s link show | grep -A4 -E '^[0-9]+: veth'

Expected (DDOS-like):
  - TX increases on relevant interfaces (egress)
  - RX does NOT increase (or only very small) on the same path
  - Client prints nothing
  - RFW prints alerts (drop/alert log lines)
EOF

echo
echo "[Done] Test 2 script finished. If results do not match expectations, compare:"
echo "  - bpftool net output"
echo "  - ip -s link counters"
echo "  - client stdout"
echo "  - RFW logs"
echo

```


