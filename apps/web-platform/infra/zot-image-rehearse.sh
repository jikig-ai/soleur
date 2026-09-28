#!/usr/bin/env bash
# zot-image-rehearse.sh <classic|containerd> — the CI rehearsal of the registry host's zot boot
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
#      paths, fetch the REAL published asset, verify it and load it into THIS docker image store;
#      the verified ID is the one the store is expected to report (classic: C, containerd: D); zot
#      starts BY THAT ID, `.Config.Image` is that ID (what the heartbeat maps back to D), and /v2/
#      answers.
# The rendered bytes come from registry-userdata-budget.sh — the same terraform render the
# dispatcher compares — so this rehearses what a replaced host would receive.
#
# Requires: sudo, docker, terraform, jq, python3 + PyYAML (ubuntu-24.04 runner). Exit 0 = rehearsed.
set -euo pipefail

STORE="${1:-}"
case "$STORE" in classic | containerd) ;; *) echo "usage: $0 <classic|containerd>" >&2; exit 2 ;; esac
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$DIR/../../.." && pwd)"
W="$(mktemp -d)"
case "$W" in /*) : ;; *) echo "FATAL: scratch dir is not absolute: $W" >&2; exit 2 ;; esac
cleanup() { docker rm -f zot-rehearse >/dev/null 2>&1 || true; rm -rf "$W"; }
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
PIN_C="$(grep -E '^[[:space:]]*zot_config_digest_amd64[[:space:]]*=[[:space:]]*"[0-9a-f]{64}"[[:space:]]*$' "$DIR/zot-registry.tf" | grep -oE '[0-9a-f]{64}')"
[[ "$PIN_C" =~ ^[0-9a-f]{64}$ ]] || die "could not read zot_config_digest_amd64 from zot-registry.tf"
[[ "$(b T)" == "$(a sha256)" ]] || die "the rebuilt archive hashes to $(b T), but zot-registry.tf pins T=$(a sha256). Upstream D does not reproduce the pinned tarball."
[[ "$(b C)" == "$PIN_C" ]] || die "upstream D's config digest is $(b C), but zot-registry.tf pins C=$PIN_C"
[[ "$(b TAG)" == "$(a tag)" && "$(b ASSET)" == "$(a asset)" ]] \
  || die "the builder names $(b TAG)/$(b ASSET) but P6/the render derive $(a tag)/$(a asset)"
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
PY
grep -qx "ZOT_ASSET_URL=$(a url)" "$W/zot-image.env" || die "the rendered ZOT_ASSET_URL is not $(a url)"

# ── the docker image store under test ───────────────────────────────────────────────────────────
step "configure the docker image store: $STORE"
if [[ "$STORE" == containerd ]]; then SNAP=true; else SNAP=false; fi
printf '{"features":{"containerd-snapshotter":%s}}\n' "$SNAP" | sudo tee /etc/docker/daemon.json >/dev/null
sudo systemctl restart docker
for _ in $(seq 1 30); do docker info >/dev/null 2>&1 && break; sleep 2; done
DS="$(docker info -f '{{json .DriverStatus}}')"
echo "docker $(docker version -f '{{.Server.Version}}') driver=$(docker info -f '{{.Driver}}') status=$DS"
if [[ "$STORE" == containerd ]]; then
  grep -q 'io.containerd.snapshotter' <<<"$DS" || die "the containerd image store is not active"
else
  grep -q 'io.containerd.snapshotter' <<<"$DS" && die "the classic image store is not active"
fi

# ── 2. DENY: the rendered runcmd entry, verbatim, under /bin/sh like cloud-init runs it ─────────
step "apply the rendered ghcr.io deny"
sudo sh "$W/deny.sh"
getent ahosts ghcr.io | awk '{print $1}' | sort -u | tee "$W/ghcr-addrs.txt"
if [[ ! -s "$W/ghcr-addrs.txt" ]] || grep -qvxE '0\.0\.0\.0|::' "$W/ghcr-addrs.txt"; then
  die "ghcr.io does not resolve ONLY to the deny's 0.0.0.0/:: after the deny"
fi
if curl -sS -o /dev/null --max-time 15 https://ghcr.io/v2/ 2>/dev/null; then die "https://ghcr.io/ is still reachable from the host"; fi
if timeout 120 docker pull "ghcr.io/project-zot/zot-linux-amd64@sha256:$D" >/dev/null 2>&1; then
  die "dockerd could still pull from ghcr.io after the deny"
fi
echo "ghcr.io denied for the host and for dockerd"

# ── 3. BOOT: the rendered fetch, at its real paths, against the real published asset ────────────
step "fetch + verify + load the published asset"
sudo install -m 0644 -o root -g root "$W/zot-image.env" /etc/default/zot-image
sudo install -m 0755 -o root -g root "$W/zot-image-fetch.sh" /usr/local/bin/zot-image-fetch.sh
docker image rm -f "$(sed -n 's/^ZOT_LOCAL_REF=//p' "$W/zot-image.env")" >/dev/null 2>&1 || true
ID="$(sudo /usr/local/bin/zot-image-fetch.sh)" || die "zot-image-fetch.sh refused: verdict $(sudo cat /var/lib/soleur/zot-image-fetch.state 2>/dev/null || echo not_run)"
[[ "$(sudo cat /var/lib/soleur/zot-image-fetch.state)" == ok ]] || die "fetch exited 0 without verdict ok"
[[ "$(sudo cat /run/soleur/zot-image-id)" == "$ID" ]] || die "the hand-off file does not carry the printed ID"
if [[ "$STORE" == containerd ]]; then WANT="sha256:$D"; else WANT="sha256:$PIN_C"; fi
[[ "$ID" == "$WANT" ]] || die "the $STORE store loaded ID $ID, expected $WANT"
echo "verified ID $ID"

step "start zot BY ID and probe /v2/"
mkdir -p "$W/zot-data"
printf '%s\n' '{"distSpecVersion":"1.1.0","storage":{"rootDirectory":"/var/lib/zot"},"http":{"address":"0.0.0.0","port":"5000"},"log":{"level":"info"}}' > "$W/config.json"
docker run -d --name zot-rehearse -p 127.0.0.1:5000:5000 \
  -v "$W/config.json:/etc/zot/config.json:ro" -v "$W/zot-data:/var/lib/zot" \
  "$ID" serve /etc/zot/config.json >/dev/null
[[ "$(docker inspect -f '{{.Config.Image}}' zot-rehearse)" == "$ID" ]] \
  || die ".Config.Image is $(docker inspect -f '{{.Config.Image}}' zot-rehearse), not the ID the heartbeat maps from"
code=""
for _ in $(seq 1 30); do
  code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 http://127.0.0.1:5000/v2/ || true)"
  [[ "$code" == 200 ]] && break
  sleep 2
done
[[ "$code" == 200 ]] || { docker logs zot-rehearse 2>&1 | tail -20; die "zot /v2/ answered '$code', not 200"; }
echo "rehearse[$STORE]: OK — T and C anchored to upstream, ghcr.io denied, asset fetched and verified ($ID), zot serving /v2/"
