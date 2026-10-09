#!/usr/bin/env bash
# zot-image-rehearse.sh <classic|containerd|host> — the CI rehearsal of the registry host's zot boot
# (#8714 step 5.3b-iii; run by .github/workflows/zot-image-mirror.yml `rehearse`, never on a host).
#
# It proves, on a throwaway runner, the three things the registry host's first boot depends on and
# that no offline suite can reach:
#   1. ANCHOR — the pinned tarball sha256 T and config digest C in zot-registry.tf are what upstream
#      D actually produces: the archive is rebuilt from ghcr.io (BEFORE the deny) and must hash to T,
#      and C must be the manifest's config digest. A PR cannot move T or C without reproducing the
#      upstream bytes. The builder's TAG/ASSET must equal what P6 and the render derive.
#   2. DENY — with the rendered runcmd deny applied to /etc/hosts, ghcr.io is unreachable from the
#      host AND from dockerd (a `docker pull` of the upstream ref fails).
#   3. BOOT — the rendered /etc/default/zot-image and zot-image-fetch.sh, installed at their real
#      paths and invoked by the rendered runcmd entry itself (under its `env -i`), fetch the REAL
#      published asset, verify it and load it into THIS docker image store; the verified ID is the
#      one the store is expected to report (classic: C, containerd: D); zot starts BY THAT ID,
#      `.Config.Image` is that ID (what the heartbeat maps back to D), and /v2/ answers.
# Stores: `classic` and `containerd` pin the runner's Docker to each image store; `host` replaces
# the runner's Docker with Ubuntu's own `docker.io` package at its default store -- exactly what
# cloud-init-registry.yml installs on the registry host.
# The rendered bytes come from registry-userdata-budget.sh — the same terraform render the
# dispatcher compares — so this rehearses what a replaced host would receive.
#
# Requires: sudo, docker, terraform, jq, python3 + PyYAML (ubuntu-24.04 runner). Exit 0 = rehearsed.
set -euo pipefail

# Go's net package caches the hosts file for 5 s without a stat (src/net/hosts.go cacheMaxAge); +2 s margin.
# A deny written within 5 s of a dockerd read of /etc/hosts is invisible to dockerd until the cache expires.
# That is the WORKING HYPOTHESIS for the one intermittent "dockerd could still pull from ghcr.io after the
# deny" failure (run 37863203385, attempt 1), not a measured cause: the failure output below is what tells
# a recurrence apart. This is the REHEARSAL's probe, not a claim about the registry host: that host starts
# dockerd before the deny, never restarts it after, and never pulls from ghcr.io.
HOSTS_CACHE_WAIT_S=7

# assert_dockerd_denied <hosts-file> <ref>: 0 = dockerd cannot pull <ref>; 1 = it could (diagnostics printed).
# Called under `||`, so errexit is OFF inside it: every stop is an explicit return, and the pull's status
# is captured with `&& rc=0 || rc=$?`. Every diagnostic is best-effort (`|| true`) and cannot change the verdict.
assert_dockerd_denied() {
  local hosts="$1" ref="$2" out rc present
  sleep "$HOSTS_CACHE_WAIT_S"
  present=no
  sudo docker image inspect "$ref" >/dev/null 2>&1 && present=yes
  out="$(timeout 120 sudo docker pull "$ref" 2>&1)" && rc=0 || rc=$?
  if (( rc != 0 )); then
    echo "dockerd pull refused (rc=$rc): $(printf '%s\n' "$out" | tail -n 1)"
    return 0
  fi
  echo "dockerd pulled $ref after the deny; evidence follows"
  echo "-- pull output (last 20 lines)"
  printf '%s\n' "$out" | tail -n 20 || true
  echo "-- docker version: $(sudo docker version -f '{{.Server.Version}}' 2>&1 || true)"
  echo "-- hosts file $hosts: $(stat -c 'mtime=%y size=%s age_s=' "$hosts" 2>&1 || true)$(( $(date +%s) - $(stat -c %Y "$hosts" 2>/dev/null || echo 0) ))"
  echo "-- image_present_before_pull=$present"
  echo "-- docker info (proxy, registry mirrors): $(sudo docker info -f 'http={{.HTTPProxy}} https={{.HTTPSProxy}} mirrors={{json .RegistryConfig.Mirrors}}' 2>&1 || true)"
  echo "-- docker unit: $(systemctl show docker -p Environment -p DropInPaths 2>&1 | tr '\n' ' ' || true)"
  return 1
}

STORE="${1:-}"
case "$STORE" in classic | containerd | host) ;; *) echo "usage: $0 <classic|containerd|host>" >&2; exit 2 ;; esac
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$DIR/../../.." && pwd)"
W="$(mktemp -d)"
case "$W" in /*) : ;; *) echo "FATAL: scratch dir is not absolute: $W" >&2; exit 2 ;; esac
# sudo throughout: the `host` leg reinstalls docker, and the runner user's socket access is not
# guaranteed across that.
dk() { sudo docker "$@"; }
cleanup() { dk rm -f zot-rehearse >/dev/null 2>&1 || true; rm -rf "$W"; }
trap cleanup EXIT

die() { echo "::error::rehearse[$STORE]: $*" >&2; exit 1; }
step() { echo "== rehearse[$STORE]: $*"; }

# ── 1. ANCHOR (ghcr.io is still reachable here, on purpose) ──────────────────────────────────────
step "rebuild the archive from upstream D and compare against the pins"
bash "$DIR/zot-image-oci-archive.sh" build "$W/rebuilt.tar" > "$W/build.txt"
cat "$W/build.txt"
b() { sed -n "s/^$1=//p" "$W/build.txt"; }
bash "$ROOT/scripts/registry-replace-preflight.sh" --print-asset > "$W/asset.txt"
cat "$W/asset.txt"
a() { sed -n "s/^$1=//p" "$W/asset.txt"; }
PIN_C="$(grep -E '^[[:space:]]*zot_config_digest_amd64[[:space:]]*=[[:space:]]*"[0-9a-f]{64}"[[:space:]]*$' "$DIR/zot-registry.tf" | grep -oE '[0-9a-f]{64}' || true)"
[[ "$PIN_C" =~ ^[0-9a-f]{64}$ ]] || die "could not read zot_config_digest_amd64 from zot-registry.tf"
[[ "$(b T)" == "$(a sha256)" ]] || die "the rebuilt archive hashes to $(b T), but zot-registry.tf pins T=$(a sha256). Upstream D does not reproduce the pinned tarball."
[[ "$(b C)" == "$PIN_C" ]] || die "upstream D's config digest is $(b C), but zot-registry.tf pins C=$PIN_C"
D="$(b D)"
[[ "$D" =~ ^[0-9a-f]{64}$ ]] || die "builder printed no D"

# ── render: the bytes a replaced host would boot ────────────────────────────────────────────────
step "render the user_data with terraform (registry-userdata-budget.sh)"
bash "$DIR/registry-userdata-budget.sh" "$W/rendered.yml"
python3 - "$W/rendered.yml" "$W" <<'PY'
import sys, yaml
d = yaml.safe_load(open(sys.argv[1])); out = sys.argv[2]
files = {f["path"]: f["content"] for f in d["write_files"]}
open(out + "/zot-image.env", "w").write(files["/etc/default/zot-image"])
open(out + "/zot-image-fetch.sh", "w").write(files["/usr/local/bin/zot-image-fetch.sh"])
deny = [e for e in d["runcmd"] if isinstance(e, str) and "for h in ghcr.io" in e]
assert len(deny) == 1, "expected exactly one deny entry in runcmd, found %d" % len(deny)
open(out + "/deny.sh", "w").write(deny[0])
fetch = [e for e in d["runcmd"] if isinstance(e, str) and e.rstrip().endswith("/usr/local/bin/zot-image-fetch.sh >/dev/null")]
assert len(fetch) == 1, "expected exactly one fetch entry in runcmd, found %d" % len(fetch)
open(out + "/fetch-entry.sh", "w").write(fetch[0] + "\n")
PY
grep -qx "ZOT_ASSET_URL=$(a url)" "$W/zot-image.env" || die "the rendered ZOT_ASSET_URL is not $(a url)"

# ── the docker image store under test ───────────────────────────────────────────────────────────
step "configure the docker image store: $STORE"
if [[ "$STORE" == host ]]; then
  mapfile -t OLD < <(dpkg-query -W -f='${Package}\n' | grep -E '^(docker|containerd|moby|runc)' || true)
  (( ${#OLD[@]} == 0 )) || sudo DEBIAN_FRONTEND=noninteractive apt-get remove -y "${OLD[@]}"
  sudo apt-get update -q
  sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -q docker.io
  sudo systemctl enable --now docker
else
  if [[ "$STORE" == containerd ]]; then SNAP=true; else SNAP=false; fi
  printf '{"features":{"containerd-snapshotter":%s}}\n' "$SNAP" | sudo tee /etc/docker/daemon.json >/dev/null
  sudo systemctl restart docker
fi
for _ in $(seq 1 30); do dk info >/dev/null 2>&1 && break; sleep 2; done
DS="$(dk info -f '{{json .DriverStatus}}')"
echo "docker $(dk version -f '{{.Server.Version}}') driver=$(dk info -f '{{.Driver}}') status=$DS"
case "$STORE" in
  containerd) grep -q 'io.containerd.snapshotter' <<<"$DS" || die "the containerd image store is not active" ;;
  classic)    grep -q 'io.containerd.snapshotter' <<<"$DS" && die "the classic image store is not active" ;;
  host)       echo "host leg: Ubuntu docker.io at its default store" ;;
esac

# ── 2. DENY: the rendered runcmd entry, verbatim, under /bin/sh like cloud-init runs it ─────────
step "apply the rendered ghcr.io deny"
sudo sh "$W/deny.sh"
getent ahosts ghcr.io | awk '{print $1}' | sort -u | tee "$W/ghcr-addrs.txt"
if [[ ! -s "$W/ghcr-addrs.txt" ]] || grep -qvxE '0\.0\.0\.0|::' "$W/ghcr-addrs.txt"; then
  die "ghcr.io does not resolve ONLY to the deny's 0.0.0.0/:: after the deny"
fi
if curl -sS -o /dev/null --max-time 15 https://ghcr.io/v2/ 2>/dev/null; then die "https://ghcr.io/ is still reachable from the host"; fi
assert_dockerd_denied /etc/hosts "ghcr.io/project-zot/zot-linux-amd64@sha256:$D" \
  || die "dockerd could still pull from ghcr.io after the deny (diagnostics above)"
echo "ghcr.io denied for the host and for dockerd"

# ── 3. BOOT: the rendered fetch, at its real paths, against the real published asset ────────────
step "fetch + verify + load the published asset"
sudo install -m 0644 -o root -g root "$W/zot-image.env" /etc/default/zot-image
sudo install -m 0755 -o root -g root "$W/zot-image-fetch.sh" /usr/local/bin/zot-image-fetch.sh
dk image rm -f "$(sed -n 's/^ZOT_LOCAL_REF=//p' "$W/zot-image.env")" >/dev/null 2>&1 || true
# The rendered runcmd entry, verbatim (its `env -i` included), under /bin/sh as cloud-init runs it.
sudo sh "$W/fetch-entry.sh" || die "zot-image-fetch.sh refused: $(sudo cat /var/lib/soleur/zot-image-fetch.state 2>/dev/null | tr '\n' ' ')"
[[ "$(sudo sed -n 1p /var/lib/soleur/zot-image-fetch.state)" == ok ]] || die "fetch exited 0 without verdict ok"
ID="$(sudo cat /run/soleur/zot-image-id)"
case "$STORE" in
  containerd) WANTS="sha256:$D" ;;
  classic)    WANTS="sha256:$PIN_C" ;;
  host)       WANTS="sha256:$PIN_C sha256:$D" ;;
esac
[[ " $WANTS " == *" $ID "* ]] || die "the $STORE store loaded ID $ID, expected one of: $WANTS"
echo "verified ID $ID"

step "start zot BY ID and probe /v2/"
mkdir -p "$W/zot-data"
printf '%s\n' '{"distSpecVersion":"1.1.0","storage":{"rootDirectory":"/var/lib/zot"},"http":{"address":"0.0.0.0","port":"5000"},"log":{"level":"info"}}' > "$W/config.json"
dk run -d --name zot-rehearse -p 127.0.0.1:5000:5000 \
  -v "$W/config.json:/etc/zot/config.json:ro" -v "$W/zot-data:/var/lib/zot" \
  "$ID" serve /etc/zot/config.json >/dev/null
[[ "$(dk inspect -f '{{.Config.Image}}' zot-rehearse)" == "$ID" ]] \
  || die ".Config.Image is $(dk inspect -f '{{.Config.Image}}' zot-rehearse), not the ID the heartbeat maps from"
code=""
for _ in $(seq 1 30); do
  code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 http://127.0.0.1:5000/v2/ || true)"
  [[ "$code" == 200 ]] && break
  sleep 2
done
[[ "$code" == 200 ]] || { dk logs zot-rehearse 2>&1 | tail -20; die "zot /v2/ answered '$code', not 200"; }
echo "rehearse[$STORE]: OK — T and C anchored to upstream, ghcr.io denied, asset fetched and verified ($ID), zot serving /v2/"
