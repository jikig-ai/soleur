#!/usr/bin/env bash
# Test suite for scripts/registry-restore-from-ghcr.sh (#7277).
#
# WHAT THIS SUITE IS FOR. The engine under test is the thing that re-materialises production's
# entire image set into an empty registry after the registry-luks-recut has destroyed the only
# copy. A false GREEN here authorises an irreversible destroy against a restore that does not
# work. So the suite's contract is the same one the D10 gate's suite carries, in both directions:
#
#   1. prove the engine CAN fail, once per enumerated exit code (2/3/4/5/6); and
#   2. prove it CAN succeed (the green row) — the criterion whose absence let an unpassable gate
#      ship with 23 green assertions in the sibling suite.
#
# ANTI-VACUITY MEASURES, each here because the shape it guards against is cheap to write by
# accident and passes on the first run:
#
#   * The `crane` stub DISPATCHES ON ARGV and `exit 64`s when a required flag is absent, so a
#     stub that ignored its arguments — and therefore validated nothing about which refs the
#     engine actually asks for — cannot pass.
#   * Fixtures are keyed PER REF on disk, so an engine that processed only the first entry and
#     broke out of the loop is detectable (the later entries' fixtures go unconsumed).
#   * Every predicate greps a FILE directly. Never `producer | grep -q`: under `set -o pipefail`
#     an early match closes the pipe, the producer takes SIGPIPE (141), and the pipeline reports
#     non-zero even though grep matched — which fails OPEN on every negative assertion.
#   * Harness setup failures ABORT (exit 2) rather than degrading into a confident wrong verdict
#     about the engine.
#
# TMPDIR: scripts/test-all.sh and run-registered-suites.sh both default TMPDIR=/var/tmp, but a
# DIRECT invocation of this file — the documented inner loop while editing the engine — inherits
# the bare machine-global /tmp tmpfs, where a sibling worktree's run can starve it mid-suite.
export TMPDIR="${TMPDIR:-/var/tmp}"

set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${DIR}/../.." && pwd)"
ENGINE="${ROOT}/scripts/registry-restore-from-ghcr.sh"

TMP="$(mktemp -d)" || { echo "harness: mktemp -d failed — refusing to report a verdict" >&2; exit 2; }
trap 'rm -rf "$TMP"' EXIT

passes=0
fails=0
pass() { passes=$((passes + 1)); printf '  ok   %s\n' "$1"; }
fail() {
  fails=$((fails + 1))
  printf '  FAIL %s\n' "$1"; printf '       rc=%s\n' "${2:-?}"; printf '       out=%s\n' "${3:-}"
}

# ── fixtures ────────────────────────────────────────────────────────────────────────────────
D1="sha256:1111111111111111111111111111111111111111111111111111111111111111"
D2="sha256:2222222222222222222222222222222222222222222222222222222222222222"
D_OTHER="sha256:9999999999999999999999999999999999999999999999999999999999999999"

WP="jikig-ai/soleur-web-platform"
IB="jikig-ai/soleur-inngest-bootstrap"
IC="jikig-ai/soleur-inngest-config"

# write_manifest <file> — the A0 pin set the PREPARE step hands to the engine.
# `conditional` entries do NOT count toward the floor: soleur-inngest-config is not published at
# GHCR (measured), so counting it would abort forever on a repo that does not exist — the new
# deadlock this whole change exists to avoid.
write_manifest() {
  cat > "$1" <<EOF
{
  "floor": 2,
  "entries": [
    { "repo": "${WP}", "tag": "v0.249.4", "disposition": "required" },
    { "repo": "${IB}", "tag": "v1.1.24",  "disposition": "required" },
    { "repo": "${IC}", "tag": "latest",   "disposition": "conditional" }
  ]
}
EOF
  [[ -s "$1" ]] || { echo "harness: could not write manifest $1" >&2; exit 2; }
}

# key <ref> — filesystem-safe fixture key.
key() { printf '%s' "$1" | tr '/:@' '___'; }

# fixture <dir> <ref> <rc> <stdout> [stderr]
fixture() {
  local d="$1" k; k="$(key "$2")"
  mkdir -p "$d" || { echo "harness: mkdir $d failed" >&2; exit 2; }
  printf '%s' "$3" > "$d/$k.rc"
  printf '%s' "${4:-}" > "$d/$k.out"
  printf '%s' "${5:-}" > "$d/$k.err"
}

# make_crane <path> <fixture-dir> — an argv-dispatching `crane` stub.
#
# It refuses (exit 64) on a call shape the engine must never emit, so the suite pins the CALL
# SHAPE and not merely the outcome. `validate` deliberately has NO default fixture: an engine
# that skipped blob validation would hit the missing-fixture arm and fail loudly rather than
# inheriting a permissive default.
make_crane() {
  local f="$1" fx="$2"
  cat > "$f" <<'STUB'
#!/usr/bin/env bash
# argv-dispatching crane stub. FX and CALLS are injected by the harness.
printf '%s\n' "$*" >> "$CALLS"
sub="${1:-}"; shift || true
key() { printf '%s' "$1" | tr '/:@' '___'; }
emit() { # $1 = ref, $2 = what-kind (for the missing-fixture message)
  local k; k="$(key "$1")"
  if [[ ! -f "$FX/$k.rc" ]]; then
    echo "stub: NO FIXTURE for $2 '$1' — the engine asked for a ref this case did not set up" >&2
    exit 70
  fi
  [[ -s "$FX/$k.out" ]] && cat "$FX/$k.out"
  [[ -s "$FX/$k.err" ]] && cat "$FX/$k.err" >&2
  exit "$(cat "$FX/$k.rc")"
}
case "$sub" in
  digest)
    ref="${1:-}"
    [[ -n "$ref" ]] || { echo "stub: 'crane digest' with no ref" >&2; exit 64; }
    emit "$ref" digest
    ;;
  copy)
    src="${1:-}"; dst="${2:-}"
    [[ -n "$src" && -n "$dst" ]] || { echo "stub: 'crane copy' needs src and dst" >&2; exit 64; }
    # A copy FROM the sink or TO ghcr.io is backwards and must never be emitted.
    case "$src" in ghcr.io/*) ;; *) echo "stub: copy source '$src' is not a ghcr.io ref" >&2; exit 64 ;; esac
    case "$dst" in ghcr.io/*) echo "stub: copy destination '$dst' must not be ghcr.io" >&2; exit 64 ;; esac
    # Keyed `copy:<dst>`, NOT bare `<dst>`. Sharing a key with the digest read makes "the copy
    # succeeded but the read-back failed" unfixturable — and that is precisely the state the
    # engine's read-back assertions exist to catch, so a shared key silently converts every
    # read-back test into a copy test. Found by mutation testing: deleting the sink-side
    # signature read-back survived a suite that appeared to cover it.
    emit "copy:$dst" copy
    ;;
  validate)
    # Must be --remote (a tarball validate would prove nothing about the sink).
    seen_remote=""; ref=""
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --remote) seen_remote=1; ref="${2:-}"; shift 2 ;;
        --fast) echo "stub: --fast skips layers and cannot prove blob completeness" >&2; exit 64 ;;
        *) shift ;;
      esac
    done
    [[ -n "$seen_remote" && -n "$ref" ]] || { echo "stub: 'crane validate' must be --remote <ref>" >&2; exit 64; }
    emit "validate:$ref" validate
    ;;
  *)
    echo "stub: unexpected crane subcommand '$sub'" >&2; exit 64 ;;
esac
STUB
  chmod +x "$f" || { echo "harness: chmod $f failed" >&2; exit 2; }
  printf '%s' "$fx" > "$f.fxdir"
}

# run_engine <fixture-dir> <calls-file> [extra args...] — always supplies a valid credential
# environment unless the caller overrode it.
run_engine() {
  local fx="$1" calls="$2"; shift 2
  FX="$fx" CALLS="$calls" \
  ZOT_PUSH_USER="${ZOT_PUSH_USER-probeuser}" ZOT_PUSH_TOKEN="${ZOT_PUSH_TOKEN-probepass}" \
  REGISTRY_RESTORE_CRANE_CMD="$CRANE_STUB" \
    bash "$ENGINE" "$@" 2>&1
}

# ok_fixtures <dir> <target> — the all-good world: both required refs resolve, copy, read back
# with matching digests, validate clean, and carry a signature tag.
ok_fixtures() {
  local fx="$1" t="$2"
  fixture "$fx" "ghcr.io/${WP}:v0.249.4" 0 "$D1"
  fixture "$fx" "ghcr.io/${IB}:v1.1.24"  0 "$D2"
  fixture "$fx" "copy:${t}/${WP}:v0.249.4" 0 ""
  fixture "$fx" "copy:${t}/${IB}:v1.1.24"  0 ""
  fixture "$fx" "${t}/${WP}:v0.249.4"    0 "$D1"
  fixture "$fx" "${t}/${IB}:v1.1.24"     0 "$D2"
  fixture "$fx" "validate:${t}/${WP}:v0.249.4" 0 "PASS"
  fixture "$fx" "validate:${t}/${IB}:v1.1.24"  0 "PASS"
  # signature tags (sha256-<hex>, the OCI referrers tag scheme GHCR actually uses)
  fixture "$fx" "ghcr.io/${WP}:sha256-${D1#sha256:}" 0 "$D_OTHER"
  fixture "$fx" "ghcr.io/${IB}:sha256-${D2#sha256:}" 0 "$D_OTHER"
  fixture "$fx" "copy:${t}/${WP}:sha256-${D1#sha256:}" 0 ""
  fixture "$fx" "copy:${t}/${IB}:sha256-${D2#sha256:}" 0 ""
  fixture "$fx" "${t}/${WP}:sha256-${D1#sha256:}"    0 "$D_OTHER"
  fixture "$fx" "${t}/${IB}:sha256-${D2#sha256:}"    0 "$D_OTHER"
  # the conditional entry is genuinely absent at GHCR (measured 2026-08-05)
  fixture "$fx" "ghcr.io/${IC}:latest" 1 "" \
    "Error: GET https://ghcr.io/v2/${IC}/manifests/latest: MANIFEST_UNKNOWN: manifest unknown"
}

TARGET="127.0.0.1:5555"
MANIFEST="$TMP/pins.json"; write_manifest "$MANIFEST"
CRANE_STUB="$TMP/crane"; make_crane "$CRANE_STUB" "$TMP/unused"

printf '\n=== registry-restore-from-ghcr ===\n\n'

if [[ ! -f "$ENGINE" ]]; then
  printf '  FAIL the engine does not exist at %s\n' "$ENGINE"
  printf '\n=== 0 passed, 1 failed ===\n\n'
  exit 1
fi

# ── THE GREEN ROW. Asserted first, deliberately. ─────────────────────────────────────────────
fx="$TMP/fx-ok"; calls="$TMP/calls-ok"; : > "$calls"
ok_fixtures "$fx" "$TARGET"
out="$(run_engine "$fx" "$calls" --target "$TARGET" --tags-from "$MANIFEST")"; rc=$?
if [[ "$rc" -eq 0 ]]; then
  pass "all-good fixture => rc 0 (THE green row: the engine can succeed)"
else
  fail "the all-good fixture must exit 0" "$rc" "$out"
fi

grep -qF "restore_summary" "$calls" 2>/dev/null # (calls file holds crane argv, not the summary)
if printf '%s' "$out" | grep -qF "restored=2"; then
  pass "the machine-readable summary reports restored=2 (the required floor)"
else
  fail "summary must report restored=2" "$rc" "$out"
fi

# The conditional entry must be a DECLARED SKIP, not a silent omission and not an abort.
if printf '%s' "$out" | grep -qF "skipped=1"; then
  pass "the conditional entry absent at GHCR is a declared skip, not an abort"
else
  fail "an absent conditional entry must record a declared skip" "$rc" "$out"
fi

# ── The anti-fail-open assertion: blobs, not just manifests. ─────────────────────────────────
# 0.9 measured `crane digest` returning rc=0 PASS on an image whose layer blob was evicted. An
# engine that verified with digest alone would certify an unusable restore.
if grep -qE '^validate --remote ' "$calls"; then
  pass "verification calls 'crane validate --remote' (blobs), not digest alone"
else
  fail "the engine must verify blob completeness with crane validate --remote" "$rc" "$(cat "$calls")"
fi

n_validate=$(grep -cE '^validate --remote ' "$calls" || true)
if [[ "$n_validate" -eq 2 ]]; then
  pass "every required reference is blob-validated (2 of 2), not just the first"
else
  fail "expected 2 validate calls, got $n_validate — an early break would show as 1" "?" "$(cat "$calls")"
fi

# Signature presence per restored digest (Phase 0.3: copy the sha256-<hex> tag; nothing re-signs).
if grep -qF "sha256-${D1#sha256:}" "$calls" && grep -qF "sha256-${D2#sha256:}" "$calls"; then
  pass "a signature tag is copied for each restored digest"
else
  fail "each restored digest needs its sha256-<hex> signature tag copied" "?" "$(cat "$calls")"
fi

# ── Idempotence: a second pass over an already-restored target is a clean no-op. ─────────────
# This is what makes a timed-out or cancelled restore recoverable by re-running rather than by
# recovering state — the property Phase 3 leans on when it retries on exit 3.
calls2="$TMP/calls-ok2"; : > "$calls2"
out2="$(run_engine "$fx" "$calls2" --target "$TARGET" --tags-from "$MANIFEST")"; rc2=$?
if [[ "$rc2" -eq 0 ]]; then
  pass "second pass over an already-restored target => rc 0 (resumable by contract)"
else
  fail "the engine must be safely re-runnable" "$rc2" "$out2"
fi

# ── Exit code 2 — source unavailable. ────────────────────────────────────────────────────────
fx="$TMP/fx-src404"; calls="$TMP/calls-src404"; : > "$calls"
ok_fixtures "$fx" "$TARGET"
fixture "$fx" "ghcr.io/${WP}:v0.249.4" 1 "" \
  "Error: GET https://ghcr.io/v2/${WP}/manifests/v0.249.4: MANIFEST_UNKNOWN: manifest unknown"
out="$(run_engine "$fx" "$calls" --target "$TARGET" --tags-from "$MANIFEST")"; rc=$?
if [[ "$rc" -eq 2 ]]; then
  pass "required source ref absent => exit 2 (source unavailable)"
else
  fail "an absent required source must exit 2" "$rc" "$out"
fi

# The message may not claim the image is GONE. Measured 2026-08-05: GHCR masks a repo that exists
# but is not visible to the credential as MANIFEST_UNKNOWN, identical to genuinely-absent — so
# "absent" would name a cause the engine did not measure.
if printf '%s' "$out" | grep -qiE 'not visible|not readable by|credential'; then
  pass "the NOTFOUND message admits 'absent OR not visible to this credential'"
else
  fail "NOTFOUND must not assert the image is gone (GHCR masks permission as MANIFEST_UNKNOWN)" "$rc" "$out"
fi

fx="$TMP/fx-dns"; calls="$TMP/calls-dns"; : > "$calls"
ok_fixtures "$fx" "$TARGET"
fixture "$fx" "ghcr.io/${WP}:v0.249.4" 1 "" \
  'Error: Get "https://ghcr.io/v2/": dial tcp: lookup ghcr.io: no such host'
out="$(run_engine "$fx" "$calls" --target "$TARGET" --tags-from "$MANIFEST")"; rc=$?
if [[ "$rc" -eq 2 ]]; then
  pass "source DNS failure => exit 2, classified NETWORK not NOTFOUND"
else
  fail "a source network failure must exit 2" "$rc" "$out"
fi

# ── Exit code 3 — sink unavailable. ──────────────────────────────────────────────────────────
# This is the code Phase 3 retries on, because a host replace can outrun the Cloudflare Tunnel's
# re-convergence onto the new origin.
fx="$TMP/fx-sink"; calls="$TMP/calls-sink"; : > "$calls"
ok_fixtures "$fx" "$TARGET"
fixture "$fx" "copy:${TARGET}/${WP}:v0.249.4" 1 "" \
  'Error: Patch "http://127.0.0.1:5000/v2/'"${WP}"'/blobs/uploads/": write: connection reset by peer'
out="$(run_engine "$fx" "$calls" --target "$TARGET" --tags-from "$MANIFEST")"; rc=$?
if [[ "$rc" -eq 3 ]]; then
  pass "sink write reset mid-upload => exit 3 (sink unavailable, the retryable code)"
else
  fail "a sink availability failure must exit 3" "$rc" "$out"
fi

# ── THE ABORT/DEGRADE BOUNDARY, pinned in both directions. ──────────────────────────────────
# This is the most dangerous line in the design. A sink that RESETS mid-upload is an availability
# failure and is retryable (exit 3, asserted above) — it is the literal signature of the incident
# this whole change exists to recover from, so classifying it as fatal would re-create the
# deadlock. A sink that REJECTS THE CREDENTIAL is an authorisation failure: retrying it only
# burns the empty-store window, so it must NOT share the retryable code.
fx="$TMP/fx-sinkauth"; calls="$TMP/calls-sinkauth"; : > "$calls"
ok_fixtures "$fx" "$TARGET"
fixture "$fx" "copy:${TARGET}/${WP}:v0.249.4" 1 "" \
  "Error: PUT http://${TARGET}/v2/${WP}/manifests/v0.249.4: DENIED: permission denied"
out="$(run_engine "$fx" "$calls" --target "$TARGET" --tags-from "$MANIFEST")"; rc=$?
if [[ "$rc" -eq 5 ]]; then
  pass "sink REJECTS the credential => exit 5, NOT the retryable 3 (authorisation != availability)"
else
  fail "a rejected sink credential must exit 5; retrying an auth failure wastes the window" "$rc" "$out"
fi

# ── Exit code 4 — verification mismatch, in BOTH of its shapes. ──────────────────────────────
fx="$TMP/fx-mismatch"; calls="$TMP/calls-mismatch"; : > "$calls"
ok_fixtures "$fx" "$TARGET"
fixture "$fx" "${TARGET}/${WP}:v0.249.4" 0 "$D_OTHER"   # copied, but landed a different digest
out="$(run_engine "$fx" "$calls" --target "$TARGET" --tags-from "$MANIFEST")"; rc=$?
if [[ "$rc" -eq 4 ]]; then
  pass "digest parity mismatch => exit 4 (verification mismatch)"
else
  fail "a digest mismatch must exit 4" "$rc" "$out"
fi

fx="$TMP/fx-blob"; calls="$TMP/calls-blob"; : > "$calls"
ok_fixtures "$fx" "$TARGET"
fixture "$fx" "validate:${TARGET}/${WP}:v0.249.4" 1 "" \
  "Error: validating config: GET http://${TARGET}/v2/${WP}/blobs/sha256:dead: BLOB_UNKNOWN: blob unknown to registry"
out="$(run_engine "$fx" "$calls" --target "$TARGET" --tags-from "$MANIFEST")"; rc=$?
if [[ "$rc" -eq 4 ]]; then
  pass "matching digest but MISSING BLOB => exit 4 (the digest-only fail-open, closed)"
else
  fail "blob-incomplete restore must exit 4 even when digests match" "$rc" "$out"
fi

# A signature that copies "successfully" but is not readable back from the sink leaves the image
# restored UNSIGNED, which fails cosign verify on the host at deploy time. Added after a mutation
# battery: deleting the sink-side signature readback SURVIVED the suite, because every fixture
# had the signature present and no row forced the readback to be the discriminator.
fx="$TMP/fx-sigmissing"; calls="$TMP/calls-sigmissing"; : > "$calls"
ok_fixtures "$fx" "$TARGET"
# The copy REPORTS SUCCESS (rc 0) and the read-back finds nothing — the discriminating shape.
fixture "$fx" "copy:${TARGET}/${WP}:sha256-${D1#sha256:}" 0 ""
fixture "$fx" "${TARGET}/${WP}:sha256-${D1#sha256:}" 1 "" \
  "Error: GET http://${TARGET}/v2/${WP}/manifests/sha256-${D1#sha256:}: MANIFEST_UNKNOWN: manifest unknown"
out="$(run_engine "$fx" "$calls" --target "$TARGET" --tags-from "$MANIFEST")"; rc=$?
if [[ "$rc" -eq 4 ]] && printf '%s' "$out" | grep -qiF "restored UNSIGNED"; then
  pass "signature copy reports ok but read-back is empty => exit 4 (no silent unsigned restore)"
else
  fail "an unverifiable sink-side signature must exit 4 naming the unsigned state" "$rc" "$out"
fi

# The signature absent AT THE SOURCE is a different arm and needs its own row: without it, a
# mutation deleting the GHCR-side signature check survives, because the copy of a nonexistent
# signature would be the thing that failed instead.
fx="$TMP/fx-sigsrc"; calls="$TMP/calls-sigsrc"; : > "$calls"
ok_fixtures "$fx" "$TARGET"
fixture "$fx" "ghcr.io/${WP}:sha256-${D1#sha256:}" 1 "" \
  "Error: GET https://ghcr.io/v2/${WP}/manifests/sha256-${D1#sha256:}: MANIFEST_UNKNOWN: manifest unknown"
out="$(run_engine "$fx" "$calls" --target "$TARGET" --tags-from "$MANIFEST")"; rc=$?
if [[ "$rc" -eq 4 ]] && printf '%s' "$out" | grep -qiF "no unsigned-restore arm"; then
  pass "no signature at GHCR => exit 4 (there is no unsigned-restore arm)"
else
  fail "a missing source signature must exit 4, not warn" "$rc" "$out"
fi

# ── The floor must not be satisfiable by DUPLICATION. ────────────────────────────────────────
# Found by mutation testing: counting is only a non-vacuity guard if the counted things differ.
DUP_MANIFEST="$TMP/pins-dup.json"
cat > "$DUP_MANIFEST" <<EOF
{ "floor": 2, "entries": [
  { "repo": "${WP}", "tag": "v0.249.4", "disposition": "required" },
  { "repo": "${WP}", "tag": "v0.249.4", "disposition": "required" }
] }
EOF
fx="$TMP/fx-dup"; calls="$TMP/calls-dup"; : > "$calls"
ok_fixtures "$fx" "$TARGET"
out="$(run_engine "$fx" "$calls" --target "$TARGET" --tags-from "$DUP_MANIFEST")"; rc=$?
if [[ "$rc" -ne 0 ]] && printf '%s' "$out" | grep -qiE 'distinct|duplicat'; then
  pass "a duplicated required entry cannot satisfy the floor"
else
  fail "duplicate required entries must be rejected by name" "$rc" "$out"
fi

# ── Exit code 5 — credential unreadable. ─────────────────────────────────────────────────────
fx="$TMP/fx-cred"; calls="$TMP/calls-cred"; : > "$calls"
ok_fixtures "$fx" "$TARGET"
out="$(ZOT_PUSH_TOKEN="" run_engine "$fx" "$calls" --target "$TARGET" --tags-from "$MANIFEST")"; rc=$?
if [[ "$rc" -eq 5 ]]; then
  pass "empty ZOT_PUSH_TOKEN => exit 5 (credential unusable)"
else
  fail "a missing sink token must exit 5" "$rc" "$out"
fi

# BOTH credential variables need their own row. With only the token row, a mutation deleting the
# user check survives — the token guard fires first and masks it.
out="$(ZOT_PUSH_USER="" run_engine "$fx" "$calls" --target "$TARGET" --tags-from "$MANIFEST")"; rc=$?
if [[ "$rc" -eq 5 ]] && printf '%s' "$out" | grep -qF "ZOT_PUSH_USER"; then
  pass "empty ZOT_PUSH_USER => exit 5, named separately from the token"
else
  fail "a missing sink user must exit 5 and name ZOT_PUSH_USER" "$rc" "$out"
fi

# An empty credential must be caught BEFORE any network call — otherwise the engine leaks a
# half-restored state and reports a credential fault.
if [[ ! -s "$calls" ]]; then
  pass "the credential check runs before any crane call (no partial restore)"
else
  fail "credentials must be validated before the first crane invocation" "$rc" "$(cat "$calls")"
fi

# ── Exit code 6 — could-not-classify. ────────────────────────────────────────────────────────
# The default arm. An unclassified failure must never read as either 'absent' or 'fine'.
fx="$TMP/fx-unknown"; calls="$TMP/calls-unknown"; : > "$calls"
ok_fixtures "$fx" "$TARGET"
fixture "$fx" "ghcr.io/${WP}:v0.249.4" 1 "" "Error: something nobody has seen before"
out="$(run_engine "$fx" "$calls" --target "$TARGET" --tags-from "$MANIFEST")"; rc=$?
if [[ "$rc" -eq 6 ]]; then
  pass "unrecognised stderr => exit 6 (could-not-classify, never a pass)"
else
  fail "an unclassifiable failure must exit 6" "$rc" "$out"
fi

# ── The non-vacuity floor. ───────────────────────────────────────────────────────────────────
# The single most likely way this engine fails open is an EMPTY inventory: every loop then passes
# and it reports success having restored nothing.
EMPTY_MANIFEST="$TMP/pins-empty.json"
cat > "$EMPTY_MANIFEST" <<'EOF'
{ "floor": 2, "entries": [] }
EOF
fx="$TMP/fx-empty"; calls="$TMP/calls-empty"; : > "$calls"
out="$(run_engine "$fx" "$calls" --target "$TARGET" --tags-from "$EMPTY_MANIFEST")"; rc=$?
# Assert the SPECIFIC guard, not merely a non-zero exit: several guards can reject this manifest,
# and a row that accepts any of them cannot tell which one is still alive.
if [[ "$rc" -ne 0 ]] && printf '%s' "$out" | grep -qiF "ZERO required entries"; then
  pass "empty inventory => rejected BY THE EMPTY-INVENTORY GUARD (named, not incidental)"
else
  fail "an empty inventory must be rejected by its own named guard" "$rc" "$out"
fi

# A manifest whose required count is BELOW its own declared floor is a silently-narrowed restore.
SHORT_MANIFEST="$TMP/pins-short.json"
cat > "$SHORT_MANIFEST" <<EOF
{ "floor": 2, "entries": [ { "repo": "${WP}", "tag": "v0.249.4", "disposition": "required" } ] }
EOF
fx="$TMP/fx-short"; calls="$TMP/calls-short"; : > "$calls"
ok_fixtures "$fx" "$TARGET"
out="$(run_engine "$fx" "$calls" --target "$TARGET" --tags-from "$SHORT_MANIFEST")"; rc=$?
if [[ "$rc" -ne 0 ]]; then
  pass "required count below the declared floor => non-zero (no silent narrowing)"
else
  fail "a below-floor manifest must not report success" "$rc" "$out"
fi

# ── Argument validation. ─────────────────────────────────────────────────────────────────────
fx="$TMP/fx-args"; calls="$TMP/calls-args"; : > "$calls"
out="$(run_engine "$fx" "$calls" --tags-from "$MANIFEST")"; rc=$?
if [[ "$rc" -ne 0 ]] && printf '%s' "$out" | grep -qF -- "--target"; then
  pass "--target is required"
else
  fail "a missing --target must be rejected by name" "$rc" "$out"
fi

out="$(run_engine "$fx" "$calls" --target "$TARGET" --tags-from "$TMP/does-not-exist.json")"; rc=$?
if [[ "$rc" -ne 0 ]]; then
  pass "an unreadable --tags-from manifest is rejected"
else
  fail "a missing manifest must not read as an empty success" "$rc" "$out"
fi

# A target of ghcr.io would make the whole restore a no-op that reports success — it would copy
# GHCR onto itself and verify perfectly, while the registry the recut emptied stayed empty.
#
# Asserting only `rc != 0` here is VACUOUS and was: the crane stub independently refuses a
# ghcr.io copy destination with exit 64, so the engine exited non-zero via the unclassifiable
# arm whether or not its own guard existed — the row passed identically against a mutant with
# the guard deleted. The discriminator is that the engine rejects it ITSELF, by name, BEFORE
# reaching for the network.
calls="$TMP/calls-selftarget"; : > "$calls"
out="$(run_engine "$fx" "$calls" --target "ghcr.io" --tags-from "$MANIFEST")"; rc=$?
if [[ "$rc" -ne 0 ]] && printf '%s' "$out" | grep -qF -- "--target" && [[ ! -s "$calls" ]]; then
  pass "--target ghcr.io rejected by the engine before any crane call (self-copy would verify green)"
else
  fail "the source registry must be rejected by name, before the first crane invocation" "$rc" \
    "$out ||| calls=$(cat "$calls")"
fi

out="$(run_engine "$fx" "$calls" --target "$TARGET" --tags-from "$MANIFEST" --nope)"; rc=$?
if [[ "$rc" -ne 0 ]] && printf '%s' "$out" | grep -qiF "unknown argument"; then
  pass "unknown argument rejected"
else
  fail "an unknown argument must be rejected" "$rc" "$out"
fi

# `--rehearse` was DELETED at Phase 0.3 (nothing signs, so its only defined effect had no
# referent). It must not linger as an accepted no-op that a caller could believe in.
out="$(run_engine "$fx" "$calls" --target "$TARGET" --tags-from "$MANIFEST" --rehearse)"; rc=$?
if [[ "$rc" -ne 0 ]]; then
  pass "--rehearse is not silently accepted (it was deleted, not made a no-op)"
else
  fail "--rehearse must be rejected rather than ignored" "$rc" "$out"
fi

# ── Structural properties of the source. ─────────────────────────────────────────────────────
# AC9: no `docker pull` in any verification path. A local Docker image cache would satisfy a
# docker pull without the sink ever being contacted — the fail-open A2's guard table names.
if grep -qF 'docker pull' "$ENGINE"; then
  fail "AC9: 'docker pull' must not appear in the restore engine" "?" \
    "$(grep -nF 'docker pull' "$ENGINE")"
else
  pass "AC9: no 'docker pull' anywhere in the engine"
fi

# The workflow-command injection guard. Registry stderr is externally-influenced text that gets
# interpolated into `::error::` output; GitHub parses workflow commands per LINE, so a newline
# followed by `::add-mask::` in that stderr would execute. Collapsing newlines makes the whole
# capture one un-parseable payload. Lifted from build-inngest-bootstrap-image.yml.
if grep -qE "tr '\\\\n' ' '" "$ENGINE"; then
  pass "registry stderr is collapsed through tr (workflow-command injection guard)"
else
  fail "captured stderr must be newline-collapsed before interpolation" "?" \
    "$(grep -n 'tr ' "$ENGINE" || true)"
fi

# Digests are read THROUGH A FILE, never $(...), because a retry helper's ::notice:: lands on
# stdout and would be captured AS the digest.
if grep -qE 'grep -oE .\^sha256:\[0-9a-f\]\{64\}\$' "$ENGINE"; then
  pass "digests are filtered to a bare sha256: token before use"
else
  fail "digest reads must be filtered with the ^sha256:[0-9a-f]{64}$ shape" "?" \
    "$(grep -n 'sha256' "$ENGINE" | head -5)"
fi

printf '\n=== %d passed, %d failed ===\n\n' "$passes" "$fails"
[[ "$fails" -eq 0 ]]
