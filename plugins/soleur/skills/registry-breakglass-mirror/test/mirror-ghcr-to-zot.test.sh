#!/usr/bin/env bash
# Network-free fixture suite for mirror-ghcr-to-zot.sh (#11424, review coverage
# P3 — the engine's declared CRANE_CMD/PATH seams are exercised here).
#
# Method: a stub `curl` on PATH serves canned responses by URL shape (DoH JSON,
# token exchange, manifest GETs); a stub `crane` proves the binary is never
# invoked under --dry-run. The whole resolve→exchange→count→report path runs
# offline; nothing contacts GHCR, zot, or the internet.
#
# Run: bash plugins/soleur/skills/registry-breakglass-mirror/scripts/mirror-ghcr-to-zot.test.sh
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$DIR/../scripts/mirror-ghcr-to-zot.sh"
passes=0; fails=0
pass() { passes=$((passes + 1)); }
fail() { fails=$((fails + 1)); echo "FAIL: $1" >&2; }

[ -f "$SCRIPT" ] || { echo "FAIL: engine not found at $SCRIPT" >&2; exit 1; }
[ -x "$SCRIPT" ] || { echo "FAIL: engine not executable at $SCRIPT" >&2; exit 1; }

WORK_T="$(mktemp -d)"; trap 'rm -rf "$WORK_T"' EXIT
STUB="$WORK_T/bin"; mkdir -p "$STUB"
FIX="$WORK_T/fix";  mkdir -p "$FIX"

# --- fixtures -----------------------------------------------------------------
# A manifest: config(702) + 2 layers (100+200) → blobs=3 bytes=1002. Its sha256
# is computed at stub-serve time so the script's digest checks pass.
cat > "$FIX/manifest.json" <<'EOF'
{"schemaVersion":2,"mediaType":"application/vnd.oci.image.manifest.v1+json","config":{"mediaType":"application/vnd.oci.image.config.v1+json","digest":"sha256:00000000000000000000000000000000000000000000000000000000000000c0","size":702},"layers":[{"mediaType":"application/vnd.oci.image.layer.v1.tar+gzip","digest":"sha256:000000000000000000000000000000000000000000000000000000000000001a","size":100},{"mediaType":"application/vnd.oci.image.layer.v1.tar+gzip","digest":"sha256:000000000000000000000000000000000000000000000000000000000000002a","size":200}]}
EOF
# A signature index whose child binds the manifest digest.
cat > "$FIX/sig.json" <<'EOF'
{"schemaVersion":2,"mediaType":"application/vnd.oci.image.index.v1+json","manifests":[]}
EOF
cat > "$FIX/token.json" <<'EOF'
{"token":"test-bearer"}
EOF
cat > "$FIX/doh.json" <<'EOF'
{"Status":0,"Answer":[{"name":"ghcr.io","type":1,"data":"140.82.121.34"}]}
EOF

# --- stubs --------------------------------------------------------------------
cat > "$STUB/curl" <<EOF
#!/usr/bin/env bash
# Serve canned bodies by URL shape; -o FILE is the last-but-two arg convention
# the engine uses. http_code is printed to stdout by -w.
url=""; out=""; wfmt=""
while [[ \$# -gt 0 ]]; do
  case "\$1" in
    -o) out="\$2"; shift 2 ;;
    -w) wfmt="\$2"; shift 2 ;;
    http*|ghcr.io*|pkg-containers*) url="\$1"; shift ;;
    *) shift ;;
  esac
done
body=""
case "\$url" in
  *dns-query*|*dns.google*|*resolve?*) body="$FIX/doh.json" ;;
  *"/token?"*) body="$FIX/token.json" ;;
  */manifests/sha256-*) body="$FIX/sig.json" ;;
  */manifests/*) body="$FIX/manifest.json" ;;
  *) body="" ;;
esac
if [[ -n "\$out" ]]; then
  [[ -n "\$body" ]] && cp "\$body" "\$out" || printf '{}' > "\$out"
elif [[ -n "\$body" ]]; then
  cat "\$body"   # no -o: caller (DoH probe) reads the body on stdout
fi
[[ "\$wfmt" == *http_code* ]] && printf '200'
exit 0
EOF
cat > "$STUB/crane" <<'EOF'
#!/usr/bin/env bash
echo "STUB-CRANE-INVOKED $*" >> "$CRANE_LOG"
exit 0
EOF
chmod +x "$STUB/curl" "$STUB/crane"

run_dry() { # <args...> → OUT/RC; stub PATH + token + CRANE_CMD
  CRANE_LOG="$WORK_T/crane.log"; : > "$CRANE_LOG"; export CRANE_LOG
  OUT="$(env PATH="$STUB:$PATH" GHCR_TOKEN="test-pat" CRANE_CMD="$STUB/crane" GHCR_IP="" PKGC_IP="" \
        bash "$SCRIPT" --dry-run "$@" 2>/dev/null)"
  RC=$?
}

# ── (a) a manifest ref dry-runs with measured blob counts — kills the
# `[.layers | .size]` array-index bug class (must print blobs=3 bytes=1002) ──
HEX="$(sha256sum "$FIX/manifest.json" | cut -d' ' -f1)"
run_dry jikig-ai/soleur-web-platform "jikig-ai/soleur-web-platform@sha256:${HEX}"
if [[ "$RC" -eq 0 ]] && echo "$OUT" | grep -q "blobs=3 declared_bytes=1002"; then pass; else fail "(a) manifest dry-run → expected rc=0 blobs=3 bytes=1002, got rc=$RC OUT='$OUT'"; fi

# ── (b) crane is never invoked under --dry-run (the fetch is gated) ──
if [[ ! -s "$CRANE_LOG" ]]; then pass; else fail "(b) dry-run invoked crane: $(cat "$CRANE_LOG")"; fi

# ── (c) tokenless dry-run prints blobs=unmeasured and exits 0 ──
OUT="$(env PATH="$STUB:$PATH" CRANE_CMD="$STUB/crane" bash "$SCRIPT" --dry-run jikig-ai/soleur-web-platform v1.2.3 2>/dev/null)"
RC=$?
if [[ "$RC" -eq 0 ]] && echo "$OUT" | grep -q "blobs=unmeasured"; then pass; else fail "(c) tokenless dry-run → expected rc=0 blobs=unmeasured, got rc=$RC OUT='$OUT'"; fi

# ── (d) malformed ref dies 1 (usage), never reaches the network leg ──
OUT="$(env PATH="$STUB:$PATH" bash "$SCRIPT" --dry-run jikig-ai/soleur-web-platform 'not a ref' 2>&1 >/dev/null)"
RC=$?
if [[ "$RC" -eq 1 ]] && echo "$OUT" | grep -q "mirror-ghcr-to-zot:"; then pass; else fail "(d) malformed ref → expected rc=1 + diagnostic, got rc=$RC OUT='$OUT'"; fi

# ── (e) ZOT_TARGET shape guard fails closed on a hostile value ──
OUT="$(env PATH="$STUB:$PATH" GHCR_TOKEN="x" ZOT_TARGET="evil host:5000" bash "$SCRIPT" --dry-run jikig-ai/soleur-web-platform v1.2.3 2>&1 >/dev/null)"
RC=$?
if [[ "$RC" -eq 1 ]] && echo "$OUT" | grep -q "ZOT_TARGET"; then pass; else fail "(e) hostile ZOT_TARGET → expected rc=1 naming ZOT_TARGET, got rc=$RC OUT='$OUT'"; fi

# ── (f) GHCR_USER charset guard fails closed ──
OUT="$(env PATH="$STUB:$PATH" GHCR_TOKEN="x" GHCR_USER='bad"user' bash "$SCRIPT" --dry-run jikig-ai/soleur-web-platform "jikig-ai/soleur-web-platform@sha256:${HEX}" 2>&1 >/dev/null)"
RC=$?
if [[ "$RC" -eq 5 ]] && echo "$OUT" | grep -q "GHCR_USER"; then pass; else fail "(f) bad GHCR_USER → expected rc=5 naming GHCR_USER, got rc=$RC OUT='$OUT'"; fi

echo "mirror-ghcr-to-zot: $passes passed, $fails failed"
[ "$fails" -eq 0 ] || exit 1
