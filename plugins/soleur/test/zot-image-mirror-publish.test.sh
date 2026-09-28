#!/usr/bin/env bash
# zot-image-mirror-publish.test.sh — behavioural rows for the `publish` step of
# .github/workflows/zot-image-mirror.yml (#8714 step 5.3b-iii).
#
# The step decides whether to CREATE a release, UPLOAD an asset, or VERIFY an existing one, and it
# must never overwrite a published asset (a registry host boots from it by pinned sha256). Grep-shaped
# checks pin its spelling, not its decisions, so the step's `run:` body is extracted with PyYAML and
# executed under the runner's own shell (`bash --noprofile --norc -eo pipefail`) with a stub `gh` that
# REFUSES any call it was not told to expect (refusals go to a file each row checks).
set -uo pipefail
export TMPDIR="${TMPDIR:-/var/tmp}"

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$DIR/../../.." && pwd)"
WF="$ROOT/.github/workflows/zot-image-mirror.yml"

PASS=0; FAIL=0; FAILURES=()
pass() { echo "  pass: $1"; PASS=$((PASS+1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); FAILURES+=("$1"); }

TMP="$(mktemp -d)" || exit 2
trap 'rm -rf "$TMP"' EXIT

python3 - "$WF" "$TMP/publish.sh" <<'PY' || { echo "  FATAL: could not extract the publish step"; exit 2; }
import sys, yaml
steps = yaml.safe_load(open(sys.argv[1]))["jobs"]["publish"]["steps"]
body = [s["run"] for s in steps if s.get("name", "").startswith("Publish or verify the release asset")]
assert len(body) == 1, body
open(sys.argv[2], "w").write(body[0])
PY
[[ -s "$TMP/publish.sh" ]] || { echo "  FATAL: empty publish body"; exit 2; }

mkdir -p "$TMP/bin"
# stub gh — modes via STUB_MODE: absent (release 404), noasset (release exists, asset missing),
# present (release + asset exist), apierr (release read fails with a non-404 error).
cat > "$TMP/bin/gh" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$GH_LOG"
refuse() { printf 'stub-gh: %s\n' "$*" >> "$STUB_ERR"; exit 64; }
case "$*" in
  *--clobber*) refuse "clobber is forbidden: $*" ;;
esac
case "${1:-} ${2:-}" in
  "api repos/jikig-ai/soleur/releases/tags/zot-image-v9.9.9")
    if [[ "$*" == *"--jq"* ]]; then
      [[ -f "$STUB_STATE/published" ]] || refuse "digest read before any asset exists"
      echo "sha256:$(printf 'e%.0s' {1..64})"; exit 0
    fi
    case "$STUB_MODE" in
      absent) [[ -f "$STUB_STATE/created" ]] || { echo "gh: Not Found (HTTP 404)" >&2; exit 1; }
              echo '{"assets":[]}'; exit 0 ;;
      apierr) echo "gh: Bad Gateway (HTTP 502)" >&2; exit 1 ;;
      noasset) echo '{"assets":[{"name":"other.txt"}]}'; exit 0 ;;
      present) echo '{"assets":[{"name":"zot-linux-amd64-v9.9.9.oci.tar"}]}'; exit 0 ;;
    esac ;;
  "release create")
    [[ "$STUB_MODE" == absent ]] || refuse "create in mode $STUB_MODE"
    [[ "$*" == *"--prerelease"* && "$*" == *"--latest=false"* ]] || refuse "create without --prerelease --latest=false"
    touch "$STUB_STATE/created"; exit 0 ;;
  "release upload")
    [[ "$STUB_MODE" == absent || "$STUB_MODE" == noasset ]] || refuse "upload in mode $STUB_MODE"
    touch "$STUB_STATE/published"; exit 0 ;;
  "release download")
    [[ "$STUB_MODE" == present ]] || refuse "download in mode $STUB_MODE"
    d=""; prev=""; for a in "$@"; do [[ "$prev" == "--dir" ]] && d="$a"; prev="$a"; done
    printf 'downloaded' > "$d/zot-linux-amd64-v9.9.9.oci.tar"
    touch "$STUB_STATE/published"; exit 0 ;;
esac
refuse "unrouted gh call: $*"
STUB
chmod +x "$TMP/bin/gh"

# The step calls the builder by repo-relative path; the sandbox cwd carries a stub that logs.
SB="$TMP/sb"; mkdir -p "$SB/apps/web-platform/infra"
cat > "$SB/apps/web-platform/infra/zot-image-oci-archive.sh" <<'STUB'
printf '%s\n' "$*" >> "$BUILDER_LOG"
[[ "${1:-}" == verify && "${STUB_VERIFY_FAIL:-}" == 1 ]] && exit 1
exit 0
STUB

run_step() { # run_step <mode> [extra env] → rc
  local mode="$1"; shift
  rm -rf "$TMP/state" "$TMP/rt"; mkdir -p "$TMP/state" "$TMP/rt"
  : > "$TMP/gh.log"; : > "$TMP/stub.err"; : > "$TMP/builder.log"; : > "$TMP/summary"
  printf 'built' > "$TMP/rt/zot.oci.tar"
  ( cd "$SB" && env "$@" STUB_MODE="$mode" STUB_STATE="$TMP/state" GH_LOG="$TMP/gh.log" STUB_ERR="$TMP/stub.err" \
      BUILDER_LOG="$TMP/builder.log" PATH="$TMP/bin:$PATH" RUNNER_TEMP="$TMP/rt" \
      GITHUB_REPOSITORY=jikig-ai/soleur GITHUB_SHA=abc123 GITHUB_STEP_SUMMARY="$TMP/summary" \
      TAG=zot-image-v9.9.9 ASSET=zot-linux-amd64-v9.9.9.oci.tar VERSION=v9.9.9 \
      BUILT_SHA256="$(printf 'e%.0s' {1..64})" MANIFEST="$(printf 'd%.0s' {1..64})" \
      bash --noprofile --norc -eo pipefail "$TMP/publish.sh" > "$TMP/out.txt" 2>&1 )
}
clean() { [[ ! -s "$TMP/stub.err" ]]; }

# P1 — no release: create a PRERELEASE (not latest), upload, never verify a download.
if run_step absent && clean && grep -q '^release create' "$TMP/gh.log" && grep -q '^release upload' "$TMP/gh.log" \
   && ! grep -q '^release download' "$TMP/gh.log"; then
  pass "P1 release absent -> prerelease created (--latest=false) and the asset uploaded"
else fail "P1 absent arm: $(tr '\n' ' ' < "$TMP/out.txt") $(cat "$TMP/stub.err")"; fi

# P2 — release exists, asset missing: upload only (no second create).
if run_step noasset && clean && grep -q '^release upload' "$TMP/gh.log" && ! grep -q '^release create' "$TMP/gh.log"; then
  pass "P2 asset absent -> uploaded into the existing release, no re-create"
else fail "P2 noasset arm: $(tr '\n' ' ' < "$TMP/out.txt") $(cat "$TMP/stub.err")"; fi

# P3 — asset present: download + VERIFY BY CONTENT, never upload.
if run_step present && clean && grep -q '^release download' "$TMP/gh.log" && ! grep -q '^release upload' "$TMP/gh.log" \
   && grep -qE '^verify .*/zot-linux-amd64-v9\.9\.9\.oci\.tar$' "$TMP/builder.log"; then
  pass "P3 asset present -> downloaded and verified by content, never re-uploaded"
else fail "P3 present arm: $(tr '\n' ' ' < "$TMP/out.txt") $(cat "$TMP/stub.err") builder=[$(cat "$TMP/builder.log")]"; fi

# P4 — asset present but fails verification: the step fails.
if run_step present STUB_VERIFY_FAIL=1; then fail "P4 a published asset failing verify was accepted"
else pass "P4 a published asset that fails content verification fails the step"; fi

# P5 — the release read fails with a non-404 error: fail closed, never create.
if run_step apierr; then fail "P5 an API error was treated as release-absent"
else ! grep -q '^release create' "$TMP/gh.log" && pass "P5 a non-404 release read error fails closed without creating" \
       || fail "P5 created a release on an API error"; fi

# P6 — the published digest is printed as PUBLISHED_T and written to the step summary.
run_step noasset >/dev/null 2>&1
grep -qx "PUBLISHED_T=$(printf 'e%.0s' {1..64})" "$TMP/out.txt" && grep -q 'published T' "$TMP/summary" \
  && pass "P6 the GitHub-computed asset digest is reported (PUBLISHED_T + step summary)" \
  || fail "P6 PUBLISHED_T not reported: $(tr '\n' ' ' < "$TMP/out.txt")"

# P7 — static: the workflow never passes --clobber and publish is the only job with contents: write.
python3 - "$WF" <<'PY' && pass "P7 no --clobber anywhere; contents: write only on publish; top-level permissions empty" || fail "P7 workflow permissions/clobber shape"
import sys, yaml
d = yaml.safe_load(open(sys.argv[1]))
# Anchored on the executed run: bodies, not the file text (the header comment says "never --clobber").
runs = [s.get("run", "") for j in d["jobs"].values() for s in j["steps"]]
assert runs and not any("--clobber" in r for r in runs)
assert d.get("permissions") == {}
for name, job in d["jobs"].items():
    w = (job.get("permissions") or {}).get("contents") == "write"
    assert w == (name == "publish"), name
PY

# --- anti-vacuity ---------------------------------------------------------------------------------
_cp=$PASS; _cf=$FAIL; _cl=${#FAILURES[@]}
pass "canary: pass() counts"; fail "canary: fail() counts (EXPECTED)"
if [[ "$PASS" -ne $((_cp+1)) || "$FAIL" -ne $((_cf+1)) || "${#FAILURES[@]}" -ne $((_cl+1)) ]]; then
  printf '  FATAL: the assertion helpers are not counting — every verdict above is void.\n' >&2; exit 2
fi
PASS=$((PASS-1)); FAIL=$((FAIL-1)); unset 'FAILURES[-1]'
if [[ "$((PASS + FAIL))" -ne 7 ]]; then
  printf '  FATAL: anti-vacuity: %s assertions ran; exactly 7 are expected.\n' "$((PASS + FAIL))" >&2
  exit 1
fi
echo "=== Results: $PASS/$((PASS+FAIL)) passed, $FAIL failed ==="
[[ "${#FAILURES[@]}" -eq 0 ]]
