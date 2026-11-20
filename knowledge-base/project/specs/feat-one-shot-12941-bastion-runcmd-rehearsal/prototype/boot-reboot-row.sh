#!/usr/bin/env bash
# boot.sh <name> <user-data.yml> [wait_s]
set -u
P="$(cd "$(dirname "$0")" && pwd)"; N="$1"; UD="$2"; W="${3:-420}"
NET=bproto-net; docker network inspect $NET >/dev/null 2>&1 || docker network create --subnet 198.18.0.0/24 $NET >/dev/null
docker rm -f "$N" "$N-stub" "$N-decoy" >/dev/null 2>&1
R="$P/run-$N"; rm -rf "$R"; mkdir -p "$R/seed" "$R/out" "$R/decoyout"; chmod 777 "$R/out" "$R/decoyout"
cp "$UD" "$R/seed/user-data"; printf 'instance-id: i-%s\nlocal-hostname: soleur-bastion\n' "$N" > "$R/seed/meta-data"
docker run -d --name "$N-stub" --network $NET --ip 198.18.0.20 -v "$P/stub.py:/stub.py:ro" -v "$P/pki:/pki:ro" -v "$R/out:/out" bproto:img python3 /stub.py >/dev/null
docker run -d --name "$N-decoy" --network $NET --ip 198.18.0.21 -v "$P/stub.py:/stub.py:ro" -v "$P/pki:/pki:ro" -v "$R/decoyout:/out" bproto:img python3 /stub.py >/dev/null
for i in $(seq 1 20); do [ -f "$R/out/stub.ready" ] && break; sleep 0.5; done
AH=()
for h in archive.ubuntu.com security.ubuntu.com; do ip=$(getent ahostsv4 $h | awk '{print $1}' | sort -u | head -1); AH+=(--add-host "$h:$ip"); done
AH+=(--add-host "o1.ingest.de.sentry.io:198.18.0.20" --add-host "decoy.example:198.18.0.21")
T0=$(date +%s)
docker run -d --name "$N" --network $NET --ip 198.18.0.10 --privileged --cgroupns=private \
  --tmpfs /run --tmpfs /run/lock --tmpfs /tmp "${AH[@]}" \
  -v "$R/seed:/var/lib/cloud/seed/nocloud:ro" -v "$P/mode-reboot:/etc/brh/uname-mode:ro" -v "$P/bundle.crt:/etc/ssl/certs/ca-certificates.crt:ro" \
  bproto:img2 /lib/systemd/systemd >/dev/null
# hot-attach the private address (the real host's private NIC)
for i in $(seq 1 20); do docker exec "$N" true 2>/dev/null && break; sleep 0.5; done
docker exec "$N" sh -c 'ip link add priv0 type dummy && ip addr add 10.0.1.70/32 dev priv0 && ip link set priv0 up'
s=""; for i in $(seq 1 "$W"); do s=$(docker exec "$N" cloud-init status 2>/dev/null | awk '/^status:/{print $2}'); case "$s" in done|error) break;; esac; sleep 1; done
echo "[$N] status=$s elapsed=$(( $(date +%s)-T0 ))s"
