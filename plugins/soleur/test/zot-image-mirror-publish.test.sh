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
# stub gh — routed on ARGV POSITION, refusing anything it was not told to expect (refusals go to
# $STUB_ERR, which every row checks). STUB_MODE: absent (tag 404), draft (tag 404 + a leftover draft),
# present (published + uploaded asset), noasset (published, asset absent), partial (asset state
# "starter" — a failed upload), apierr (non-404 read error). STUB_DIGEST: digest the final read returns.
cat > "$TMP/bin/gh" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$GH_LOG"
refuse() { printf 'stub-gh: %s\n' "$*" >> "$STUB_ERR"; exit 64; }
TAG=TAGV; ASSET=ASSETV; R=repos/jikig-ai/soleur
case "$*" in *--clobber*) refuse "clobber is forbidden: $*" ;; esac
arg_after() { local k="$1"; shift; local prev=""; for a in "$@"; do [[ "$prev" == "$k" ]] && { printf '%s' "$a"; return; }; prev="$a"; done; }
case "${1:-} ${2:-}" in
  "api $R/releases/tags/$TAG")
    if [[ " $* " == *" --jq "* ]]; then
      [[ -f "$STUB_STATE/published" ]] || refuse "digest read before the release is published"
      q="$(arg_after --jq "$@")"
      [[ "$q" == *'.name == "'"$ASSET"'"'* && "$q" == *'.state == "uploaded"'* ]] || refuse "digest read not selecting the asset by name+state: $q"
      printf '%s\n' "${STUB_DIGEST}"; exit 0
    fi
    case "$STUB_MODE" in
      absent|draft) echo "gh: Not Found (HTTP 404)" >&2; exit 1 ;;
      apierr) echo "gh: Bad Gateway (HTTP 502)" >&2; exit 1 ;;
      present) echo "{\"assets\":[{\"name\":\"other.txt\",\"state\":\"uploaded\"},{\"name\":\"$ASSET\",\"state\":\"uploaded\"}]}"; exit 0 ;;
      noasset) echo '{"assets":[{"name":"other.txt","state":"uploaded"}]}'; exit 0 ;;
      partial) echo "{\"assets\":[{\"name\":\"$ASSET\",\"state\":\"starter\"}]}"; exit 0 ;;
    esac ;;
  "api --paginate")
    [[ "${3:-}" == "$R/releases?per_page=100" ]] || refuse "draft listing on an unexpected url: $*"
    [[ "$STUB_MODE" == draft ]] && echo 4242
    exit 0 ;;
  "api -X")
    [[ "${3:-} ${4:-}" == "DELETE $R/releases/4242" && "$STUB_MODE" == draft ]] || refuse "unexpected delete: $*"
    touch "$STUB_STATE/deleted"; exit 0 ;;
  "release create")
    [[ "${3:-}" == "$TAG" ]] || refuse "create for tag [${3:-}]"
    [[ "$STUB_MODE" == absent || ( "$STUB_MODE" == draft && -f "$STUB_STATE/deleted" ) ]] || refuse "create in mode $STUB_MODE (stale draft not deleted?)"
    [[ " $* " == *" --draft "* && " $* " == *" --prerelease "* ]] || refuse "create not as a draft prerelease: $*"
    [[ "$(arg_after --target "$@")" == abc123 ]] || refuse "create without --target abc123: $*"
    touch "$STUB_STATE/created"; exit 0 ;;
  "release upload")
    [[ "${3:-}" == "$TAG" && -f "$STUB_STATE/created" ]] || refuse "upload for tag [${3:-}] or before create"
    [[ "${4:-}" == "$RUNNER_TEMP/$ASSET" ]] || refuse "upload of [${4:-}] (want the renamed asset)"
    touch "$STUB_STATE/uploaded"; exit 0 ;;
  "release edit")
    [[ "${3:-}" == "$TAG" && -f "$STUB_STATE/uploaded" ]] || refuse "edit for tag [${3:-}] or before upload"
    [[ " $* " == *" --draft=false "* && " $* " == *" --prerelease "* && " $* " == *" --latest=false "* ]] || refuse "publish flags: $*"
    touch "$STUB_STATE/published"; exit 0 ;;
  "release download")
    [[ "$STUB_MODE" == present && "${3:-}" == "$TAG" && "$(arg_after --pattern "$@")" == "$ASSET" ]] || refuse "download: $*"
    d="$(arg_after --dir "$@")"; printf 'DOWNLOADED-BYTES' > "$d/$ASSET"
    touch "$STUB_STATE/published"; exit 0 ;;
esac
refuse "unrouted gh call: $*"
STUB
sed -i "s|TAGV|zot-image-v9.9.9-dddddddddddd|; s|ASSETV|zot-linux-amd64-v9.9.9.oci.tar|" "$TMP/bin/gh"
chmod +x "$TMP/bin/gh"

# The step calls the builder by repo-relative path; the sandbox cwd carries a stub that logs the
# path it was handed AND the sha256 of that file, so a verify of the wrong file is observable.
SB="$TMP/sb"; mkdir -p "$SB/apps/web-platform/infra"
cat > "$SB/apps/web-platform/infra/zot-image-oci-archive.sh" <<'STUB'
printf '%s %s\n' "$*" "$(sha256sum "${2:-/dev/null}" 2>/dev/null | cut -c1-12)" >> "$BUILDER_LOG"
[[ "${1:-}" == verify && "${STUB_VERIFY_FAIL:-}" == 1 ]] && exit 1
exit 0
STUB

BUILT="$(printf 'e%.0s' {1..64})"
run_step() { # run_step <mode> [extra env...] → rc
  local mode="$1"; shift
  rm -rf "$TMP/state" "$TMP/rt"; mkdir -p "$TMP/state" "$TMP/rt"
  : > "$TMP/gh.log"; : > "$TMP/stub.err"; : > "$TMP/builder.log"; : > "$TMP/summary"
  printf 'LOCALLY-BUILT-BYTES' > "$TMP/rt/zot.oci.tar"
  ( cd "$SB" && env STUB_DIGEST="sha256:$BUILT" "$@" STUB_MODE="$mode" STUB_STATE="$TMP/state" GH_LOG="$TMP/gh.log" STUB_ERR="$TMP/stub.err" \
      BUILDER_LOG="$TMP/builder.log" PATH="$TMP/bin:$PATH" RUNNER_TEMP="$TMP/rt" \
      GITHUB_REPOSITORY=jikig-ai/soleur GITHUB_SHA=abc123 GITHUB_STEP_SUMMARY="$TMP/summary" \
      TAG=zot-image-v9.9.9-dddddddddddd ASSET=zot-linux-amd64-v9.9.9.oci.tar VERSION=v9.9.9 \
      BUILT_SHA256="$BUILT" MANIFEST="$(printf 'd%.0s' {1..64})" \
      bash --noprofile --norc -eo pipefail "$TMP/publish.sh" > "$TMP/out.txt" 2>&1 )
}
clean() { [[ ! -s "$TMP/stub.err" ]]; }
why() { printf '%s | stub:%s | gh:%s' "$(tr '\n' ' ' < "$TMP/out.txt")" "$(tr '\n' ' ' < "$TMP/stub.err")" "$(tr '\n' ';' < "$TMP/gh.log")"; }

# P1 — no release: draft prerelease created at the merge sha, the RENAMED asset uploaded, then published
# not-latest; nothing downloaded; the GitHub-computed digest is reported.
if run_step absent && clean && [[ -f "$TMP/state/published" ]] && ! grep -q '^release download' "$TMP/gh.log" \
   && grep -qx "PUBLISHED_T=$BUILT" "$TMP/out.txt" && grep -q 'published T' "$TMP/summary"; then
  pass "P1 release absent -> draft prerelease, asset uploaded, published not-latest, PUBLISHED_T reported"
else fail "P1 absent arm: $(why)"; fi

# P2 — a leftover DRAFT for the tag (an interrupted run) is deleted before the create.
if run_step draft && clean && [[ -f "$TMP/state/deleted" && -f "$TMP/state/published" ]]; then
  pass "P2 a leftover draft for the tag is deleted, then the release is created and published"
else fail "P2 draft arm: $(why)"; fi

# P3 — published with the asset: download it and verify THE DOWNLOADED FILE, never upload.
dl_sha="$(printf 'DOWNLOADED-BYTES' | sha256sum | cut -c1-12)"
if run_step present && clean && ! grep -q '^release upload' "$TMP/gh.log" \
   && grep -qx "verify $TMP/rt/dl/zot-linux-amd64-v9.9.9.oci.tar $dl_sha" "$TMP/builder.log"; then
  pass "P3 asset present -> the DOWNLOADED file is verified by content, never re-uploaded"
else fail "P3 present arm: $(why) builder=[$(cat "$TMP/builder.log")]"; fi

# P4 — the downloaded asset fails content verification: the step fails.
if run_step present STUB_VERIFY_FAIL=1; then fail "P4 a published asset failing verify was accepted"
else pass "P4 a published asset that fails content verification fails the step"; fi

# P5 — a non-404 release read error fails closed, never creating anything.
if run_step apierr; then fail "P5 an API error was treated as release-absent"
elif grep -q '^release create' "$TMP/gh.log"; then fail "P5 created a release on an API error"
else pass "P5 a non-404 release read error fails closed without creating"; fi

# P6 — a published release WITHOUT the asset (or with a half-uploaded one) fails: it is immutable.
r6=""
for m in noasset partial; do
  if run_step "$m"; then r6="$r6 $m:accepted"; fi
  grep -q '^release upload' "$TMP/gh.log" && r6="$r6 $m:uploaded"
  grep -q 'cannot take an upload' "$TMP/out.txt" || r6="$r6 $m:no-reason"
done
[[ -z "$r6" ]] && pass "P6 a published release lacking an uploaded asset (absent or state!=uploaded) fails without uploading" || fail "P6:$r6"

# P7 — the final digest must be a sha256; a different (legal) digest is surfaced as a warning.
r7=""
run_step absent STUB_DIGEST="" && r7="$r7 empty-digest-accepted"
run_step absent STUB_DIGEST="sha256:$(printf 'f%.0s' {1..64})" || r7="$r7 other-digest-failed"
grep -q '::warning::published' "$TMP/out.txt" || r7="$r7 no-warning"
grep -qx "PUBLISHED_T=$(printf 'f%.0s' {1..64})" "$TMP/out.txt" || r7="$r7 wrong-published-T"
[[ -z "$r7" ]] && pass "P7 an empty digest fails; a digest differing from the rebuild is reported as the PUBLISHED T with a warning" || fail "P7:$r7"

# P8 — the BUILD step's output parsing: canned builder output -> GITHUB_OUTPUT; a malformed TAG fails.
python3 - "$WF" "$TMP/build.sh" <<'PY' || { echo "  FATAL: could not extract the build step"; exit 2; }
import sys, yaml
steps = yaml.safe_load(open(sys.argv[1]))["jobs"]["publish"]["steps"]
body = [s["run"] for s in steps if s.get("id") == "build"]
assert len(body) == 1, body
open(sys.argv[2], "w").write(body[0])
PY
mkdir -p "$TMP/bsb/apps/web-platform/infra"
cat > "$TMP/bsb/apps/web-platform/infra/zot-image-oci-archive.sh" <<'STUB'
printf 'D=%s\nC=%s\nT=%s\nBYTES=10\nLOCAL_REF=localhost/soleur-mirror/zot-linux-amd64:v9.9.9\nTAG=%s\nASSET=zot-linux-amd64-v9.9.9.oci.tar\n' \
  "$(printf 'd%.0s' {1..64})" "$(printf 'c%.0s' {1..64})" "$(printf 'e%.0s' {1..64})" "${STUB_TAG:-zot-image-v9.9.9-dddddddddddd}"
STUB
r8=""; : > "$TMP/gho"
( cd "$TMP/bsb" && env RUNNER_TEMP="$TMP/rt" GITHUB_OUTPUT="$TMP/gho" bash --noprofile --norc -eo pipefail "$TMP/build.sh" >/dev/null 2>&1 ) || r8="$r8 canned-failed"
for kv in "tag=zot-image-v9.9.9-dddddddddddd" "asset=zot-linux-amd64-v9.9.9.oci.tar" "version=v9.9.9" "sha256=$(printf 'e%.0s' {1..64})" "manifest=$(printf 'd%.0s' {1..64})"; do
  grep -qx "$kv" "$TMP/gho" || r8="$r8 missing:${kv%%=*}"
done
( cd "$TMP/bsb" && env STUB_TAG="zot-image-latest" RUNNER_TEMP="$TMP/rt" GITHUB_OUTPUT="$TMP/gho2" bash --noprofile --norc -eo pipefail "$TMP/build.sh" >/dev/null 2>&1 ) && r8="$r8 malformed-tag-accepted"
[[ -z "$r8" ]] && pass "P8 the build step maps builder output to tag/asset/version/sha256/manifest and refuses a malformed TAG" || fail "P8:$r8"

# P9 — static: the workflow never passes --clobber and publish is the only job with contents: write.
python3 - "$WF" <<'PY' && pass "P9 no --clobber anywhere; contents: write only on publish; top-level permissions empty; run shell is bash (pipefail)" || fail "P9 workflow permissions/clobber shape"
import sys, yaml
d = yaml.safe_load(open(sys.argv[1]))
# Anchored on the executed run: bodies, not the file text (the header comment says "never --clobber").
runs = [s.get("run", "") for j in d["jobs"].values() for s in j["steps"]]
assert runs and not any("--clobber" in r for r in runs)
assert d.get("permissions") == {}
assert (d.get("defaults") or {}).get("run", {}).get("shell") == "bash"  # pipefail for every run: block
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
if [[ "$((PASS + FAIL))" -ne 9 ]]; then
  printf '  FATAL: anti-vacuity: %s assertions ran; exactly 9 are expected.\n' "$((PASS + FAIL))" >&2
  exit 1
fi
echo "=== Results: $PASS/$((PASS+FAIL)) passed, $FAIL failed ==="
[[ "${#FAILURES[@]}" -eq 0 ]]
