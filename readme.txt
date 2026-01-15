stun_test — Step-by-step Runbook (TXT)

============================================================
Test 1 — STUN/TURN (Expected: RX+TX increase, client prints packets)
============================================================

Step 1. Go to repo root
  cd ~/wenhui/stun_test

Step 2. Make scripts executable (only needed once)
  chmod +x scripts/*.sh

Step 3. Build STUN/TURN images
  ./scripts/build_stun.sh

Step 4. Start STUN/TURN server (docker0 / default bridge; recommended)
  ./scripts/run_stun_docker0.sh up

Step 5. Confirm server container is running
  docker ps

Step 6. Run STUN/TURN client test (foreground)
  ./scripts/run_stun_docker0.sh test

Step 7. Start RFW with STUN enabled (run on host; new terminal)
  cd ~/wenhui/grimlock
  sudo ./rfw \
    -data-center="snc2" \
    -server-type="grimlock-test" \
    -drop-skb=false \
    -stun=true \
    -rule-path="/etc/rfw/rules/"

Step 8. Verify TC hooks are attached (bpftool)
  sudo bpftool net

Expected result for Step 8:
  - tc ingress/egress programs attached on:
      docker0
      lo
      host NIC (e.g. enp*)
      veth* (container host-side veth)

Step 9. Verify docker0 interface counters increase (RX and TX)
  ip -s link show docker0

Expected result for Step 9:
  - RX packets and TX packets increase while the STUN client test runs.

Step 10. Verify veth* interface counters increase (RX and TX)
  ip -s link show | grep -A4 -E '^[0-9]+: veth'

Expected result for Step 10:
  - At least one relevant veth* shows RX and TX increasing.

Step 11. Confirm client output behavior
Expected:
  - STUN/TURN client console prints packet details (you can see packets in client output).

Step 12. Confirm RFW output behavior
Expected:
  - RFW logs include lines such as:
      create probe on interface: ...
      [veth hook] attached tc on: ...

Step 13. (Optional) View server logs
  ./scripts/run_stun_docker0.sh logs

Step 14. Tear down STUN/TURN containers
  ./scripts/run_stun_docker0.sh down


------------------------------------------------------------
Alternative: run Test 1 on turnnet (custom bridge with static IPs)
------------------------------------------------------------

Step A1. Start server using turnnet
  ./scripts/run_stun_turnnet.sh up

Step A2. Run client using turnnet
  ./scripts/run_stun_turnnet.sh test

Step A3. All verification steps are the same:
  sudo bpftool net
  ip -s link show docker0
  ip -s link show | grep -A4 -E '^[0-9]+: veth'

Step A4. Tear down
  ./scripts/run_stun_turnnet.sh down


============================================================
Test 2 — UDP “DDOS-like” (Expected: TX increase only, client prints nothing, RFW alerts)
============================================================

Step 1. Go to repo root
  cd ~/wenhui/stun_test

Step 2. Make scripts executable (only needed once)
  chmod +x scripts/*.sh

Step 3. Build DDOS images
  ./scripts/build_ddos.sh

Step 4. Start UDP server (docker0 / default bridge; recommended)
  ./scripts/run_ddos_docker0.sh up

Step 5. Confirm server container is running
  docker ps

Step 6. Run UDP client test (foreground)
  ./scripts/run_ddos_docker0.sh test

Step 7. Start RFW (alerts expected; run on host; new terminal)
  cd ~/wenhui/grimlock
  sudo ./rfw \
    -data-center="snc2" \
    -server-type="grimlock-test" \
    -drop-skb=false \
    -stun=false \
    -rule-path="/etc/rfw/rules/"

Note:
  - If your alert pipeline depends on STUN parsing, run RFW with:
      -stun=true

Step 8. Verify TC hooks are attached (bpftool)
  sudo bpftool net

Expected result for Step 8:
  - tc ingress/egress programs attached on:
      docker0
      lo
      host NIC (e.g. enp*)
      veth* (container host-side veth)

Step 9. Verify docker0 interface counters (TX increases; RX should not)
  ip -s link show docker0

Expected result for Step 9:
  - TX packets increase
  - RX packets do NOT increase (or increase very little)

Step 10. Verify veth* interface counters (TX increases; RX should not)
  ip -s link show | grep -A4 -E '^[0-9]+: veth'

Expected result for Step 10:
  - Relevant veth* shows TX increasing
  - RX stays flat or nearly flat

Step 11. Confirm client output behavior
Expected:
  - Client console prints nothing (or minimal), i.e., no packet-by-packet prints.

Step 12. Confirm RFW output behavior
Expected:
  - RFW prints alerts (drop/alert log lines).

Step 13. (Optional) View server logs
  ./scripts/run_ddos_docker0.sh logs

Step 14. Tear down DDOS containers
  ./scripts/run_ddos_docker0.sh down


------------------------------------------------------------
Alternative: run Test 2 on turnnet (custom bridge with static IPs)
------------------------------------------------------------

Step B1. Start server using turnnet
  ./scripts/run_ddos_turnnet.sh up

Step B2. Run client using turnnet
  ./scripts/run_ddos_turnnet.sh test

Step B3. All verification steps are the same:
  sudo bpftool net
  ip -s link show docker0
  ip -s link show | grep -A4 -E '^[0-9]+: veth'

Step B4. Tear down
  ./scripts/run_ddos_turnnet.sh down


============================================================
Common utility steps (use anytime)
============================================================

Step U1. Show containers
  docker ps

Step U2. Show all Docker networks
  docker network ls

Step U3. Clean images/containers related to this repo (docker0)
  ./scripts/clean_all_docker0.sh

Step U4. Clean images/containers related to this repo (turnnet)
  ./scripts/clean_all_turnnet.sh

