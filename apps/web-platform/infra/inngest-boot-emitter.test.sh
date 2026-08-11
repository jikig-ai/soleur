#!/usr/bin/env bash
# Tests inngest-boot-phone-home.sh — the boot-trace emitter embedded in cloud-init-inngest.yml
# (#7228 Phase 2; the plan's "loud emitter", a real cq-silent-fallback-must-mirror-to-sentry
# violation that every plan reviewer independently voted to KEEP).
#
# THE DEFECT. The emitter is the SINGLE delivery path for all eight SOLEUR_INNGEST_BOOT_STAGE
# markers — the entire diagnosis of a boot failure on a host with no SSH. It opened with
#
#     [ -r "$tok_file" ] || exit 0
#     [ -n "$bs_token" ] || exit 0
#     curl ... >/dev/null 2>&1
#     exit 0
#
# so all three of its failure modes were EXIT 0 WITH NO OUTPUT. It could not report its own death
# by construction. Combined with the tmpfs defect (every write of /run/inngest-bs-logs-token lives
# in `runcmd:`, which cloud-init runs on FIRST BOOT ONLY, and /run is cleared every reboot), a
# host that reboots once is dark FOREVER and the silence is indistinguishable from health. That is
# the #7228 shape exactly: a signal whose absence reads as "nothing to report".
#
# WHY journald AND NOT the emitter's own POST. Because the POST is the thing that failed. The two
# channels are INDEPENDENT at the credential level, which is what makes this defense-in-depth
# rather than a loop: the emitter reads /run/inngest-bs-logs-token (staged by cloud-init), while
# vector.service resolves BETTERSTACK_LOGS_TOKEN from Doppler at ExecStart (inngest-bootstrap.sh,
# vector.toml:526). So the exact failure that silences the emitter — a missing/empty token file —
# leaves the journald->Vector->Better Stack path fully operational.
#
# DEVIATION FROM THE PLAN, RECORDED. The plan said to emit on an ALREADY-ALLOWLISTED identifier
# specifically to avoid opening a fresh Source-4 quota decision. That is not available here:
# journald-config.test.sh CF-4 asserted, in BOTH directions, that this emitter never calls
# `logger` and that "inngest-boot-phone-home" is absent from the allowlist — and reusing some
# OTHER script's tag would misattribute these rows to a producer that did not emit them. CF-4's
# rationale is explicitly conditional ("it never calls logger, SO an allowlist entry would be a
# permanently-dead no-op"), so the correct move is the one that file already makes for ci-deploy
# at R1-1.8: flip the negative pair into a POSITIVE pair. The quota cost of the new tag is bounded
# by construction — the emitter is SILENT ON SUCCESS, so a healthy host pays zero rows, and a
# fully-dark one pays one row per phone-home call site per boot (~15).
#
# NO SECRET RIDES THE NEW CHANNEL. The rows carry the stage name plus a numeric reason (curl rc /
# HTTP code) and NEVER $detail — which matters most on the missing-token arm, where the emitter
# exits BEFORE the redaction at :125 has run. This is the P1-SEC lesson from the inngest-redis
# allowlist entry in journald-config.test.sh: opening a Source-4 tag opens a route from that
# producer's output to Better Stack, so the producer's output is what has to be safe.
#
# Run: bash apps/web-platform/infra/inngest-boot-emitter.test.sh

set -uo pipefail
export TMPDIR="${TMPDIR:-/var/tmp}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLOUD_INIT="$SCRIPT_DIR/cloud-init-inngest.yml"
VECTOR_TOML="$SCRIPT_DIR/vector.toml"

PASS=0
FAIL=0
pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }
assert() {
  local desc="$1" cond="$2"
  if eval "$cond" >/dev/null 2>&1; then pass "$desc"; else fail "$desc"; fi
}

[[ -r "$CLOUD_INIT" ]] || { echo "FATAL: $CLOUD_INIT unreadable"; exit 2; }
[[ -r "$VECTOR_TOML" ]] || { echo "FATAL: $VECTOR_TOML unreadable"; exit 2; }

WORK="$(mktemp -d)" || { echo "FATAL: mktemp failed"; exit 2; }
HEALTH_PID=""
cleanup() { rm -rf "$WORK"; [[ -n "$HEALTH_PID" ]] && kill "$HEALTH_PID" 2>/dev/null; }
trap cleanup EXIT

echo "--- #7228: inngest-boot-phone-home.sh must never fail silently ---"

# --- extract the emitter from the write_files block ------------------------------------------
# Same awk boundary journald-config.test.sh:307 uses (path line to the next `- path:`), then drop
# the `content: |` line and dedent the 6-space YAML block scalar. A harness that silently produced
# an EMPTY script would make every "exits 0" assertion below pass vacuously, so the extraction is
# asserted before anything is driven through it.
EMITTER="$WORK/inngest-boot-phone-home.sh"
awk '/^  - path: \/usr\/local\/bin\/inngest-boot-phone-home\.sh$/{f=1;next} f&&/^  - path: /{f=0} f' \
  "$CLOUD_INIT" | sed -e '/^    content: |$/d' -e 's/^      //' \
  | sed -e '/^    owner:/d' -e '/^    permissions:/d' > "$EMITTER"
chmod +x "$EMITTER"

assert "extraction: the emitter body was recovered (non-empty, has the shebang and the POST)" \
  "[[ -s '$EMITTER' ]] && head -1 '$EMITTER' | grep -q '^#!' && grep -q 'betterstackdata.com' '$EMITTER'"
assert "extraction: the emitter is syntactically valid bash (dedent did not corrupt it)" \
  "bash -n '$EMITTER'"

# --- the tag is DERIVED from the emitter, never restated --------------------------------------
# Two hardcoded copies of the tag would agree with each other while both disagreeing with the
# script — a guard that passes precisely when it is wrong (journald-config.test.sh R1-1.8).
EMITTER_TAG="$(grep -oE '^[[:space:]]*logger -t [A-Za-z0-9._-]+' "$EMITTER" | head -1 | awk '{print $3}' || true)"
assert "the emitter declares a logger tag at all (this is the whole fix: it used to be silent)" \
  "[[ -n \"\$EMITTER_TAG\" ]]"
# The positive half of the pair. An emitter whose tag is not allowlisted is silence that READS AS
# HEALTH — the #6536 defect, where a unit's stderr never left the host because its identifier
# matched no source. Derived tag on one side, the real vector.toml on the other.
assert "the emitter's tag ('${EMITTER_TAG:-<none>}') IS in the vector Source 4 allowlist (else the row never leaves the box)" \
  "[[ -n \"\$EMITTER_TAG\" ]] && grep -qE \"^[[:space:]]*\\\"\$EMITTER_TAG\\\",?\$\" '$VECTOR_TOML'"

# --- the harness's own stubs -------------------------------------------------------------------
# `logger` and `curl` are PATH-resolved by the emitter, so stubs record what it emitted and what
# it tried to send. The curl stub is NOT a blanket no-op: it FAILS on a missing required flag, so
# a future emitter that stops sending the Authorization header cannot pass by accident.
mkdir -p "$WORK/bin"
cat > "$WORK/bin/logger" <<'LOGEOF'
#!/bin/sh
printf '%s\n' "$*" >> "$LOGGER_OUT"
LOGEOF
cat > "$WORK/bin/curl" <<'CURLEOF'
#!/bin/sh
printf '%s\n' "$*" >> "$CURL_OUT"
case "$*" in
  *Authorization*) ;;
  *) echo "curl-stub: refusing a POST with no Authorization header" >&2; exit 64 ;;
esac
exit "${CURL_STUB_RC:-0}"
CURLEOF
chmod +x "$WORK/bin/logger" "$WORK/bin/curl"

LOGGER_OUT="$WORK/logger.txt"
CURL_OUT="$WORK/curl.txt"

fire() {
  # $1 = token-file path (may not exist), $2 = CURL_STUB_RC, $3 = stage
  : > "$LOGGER_OUT"
  : > "$CURL_OUT"
  PATH="$WORK/bin:$PATH" LOGGER_OUT="$LOGGER_OUT" CURL_OUT="$CURL_OUT" \
    CURL_STUB_RC="$2" SOLEUR_INNGEST_BS_TOKEN_FILE="$1" \
    bash "$EMITTER" "$3" "detail-value-must-not-ship"
}

# --- ARM 1: token file ABSENT (the tmpfs defect — every boot after the first) ------------------
TOK="$WORK/token"
rm -f "$TOK"
fire "$TOK" 0 "runcmd-entered" && RC1=0 || RC1=$?
assert "ARM1 missing token -> still exits 0 (fail-OPEN: a broken emitter must never brick a boot)" \
  "[[ '$RC1' -eq 0 ]]"
assert "ARM1 missing token -> emits a LOUD logger row (was: a silent \`|| exit 0\`)" \
  "[[ -s '$LOGGER_OUT' ]]"
assert "ARM1 missing token -> the row names the stage, so the trace says WHERE the boot was" \
  "grep -q 'runcmd-entered' '$LOGGER_OUT'"
assert "ARM1 missing token -> the row never carries \$detail (redaction at :125 has not run yet)" \
  "! grep -q 'detail-value-must-not-ship' '$LOGGER_OUT'"
assert "ARM1 missing token -> no POST was attempted (there is no credential to send)" \
  "[[ ! -s '$CURL_OUT' ]]"

# --- ARM 2: token file present but EMPTY --------------------------------------------------------
# Same silent-exit shape one line down, and a REAL state: cloud-init writes the file before it
# knows whether the Doppler fetch produced anything, so `printf '' > file` leaves exactly this.
: > "$TOK"
fire "$TOK" 0 "doppler-token-fetched" && RC2=0 || RC2=$?
assert "ARM2 empty token -> still exits 0 (fail-open)" \
  "[[ '$RC2' -eq 0 ]]"
assert "ARM2 empty token -> emits a LOUD logger row (the second silent \`|| exit 0\`)" \
  "[[ -s '$LOGGER_OUT' ]]"
assert "ARM2 empty token -> the row is DISTINGUISHABLE from the missing-file arm" \
  "grep -qi 'empty' '$LOGGER_OUT'"
assert "ARM2 empty token -> no POST attempted" \
  "[[ ! -s '$CURL_OUT' ]]"

# --- ARM 3: token present, POST FAILS -----------------------------------------------------------
printf '%s' 'synthetic-token-value' > "$TOK"
fire "$TOK" 7 "oci-pull-rc-1" && RC3=0 || RC3=$?
assert "ARM3 failed POST -> still exits 0 (fail-open)" \
  "[[ '$RC3' -eq 0 ]]"
assert "ARM3 failed POST -> a POST WAS attempted (proves the arm is reached, not short-circuited)" \
  "[[ -s '$CURL_OUT' ]]"
assert "ARM3 failed POST -> emits a LOUD logger row (was: \`curl ... >/dev/null 2>&1\`)" \
  "[[ -s '$LOGGER_OUT' ]]"
assert "ARM3 failed POST -> the row carries curl's exit code, so the failure is diagnosable" \
  "grep -q 'rc=7' '$LOGGER_OUT'"
assert "ARM3 failed POST -> the row never carries the bearer token value" \
  "! grep -q 'synthetic-token-value' '$LOGGER_OUT'"
assert "ARM3 failed POST -> the row never carries \$detail" \
  "! grep -q 'detail-value-must-not-ship' '$LOGGER_OUT'"

# --- ARM 4: the happy path stays SILENT ---------------------------------------------------------
# The load-bearing negative. Without it every assertion above is satisfied by an emitter that logs
# unconditionally — which would ship a row for all ~15 call sites on EVERY boot of a HEALTHY host,
# turning a bounded failure channel into a permanent quota cost. Success is already observable via
# the POST itself; a journald row would be pure duplication.
fire "$TOK" 0 "net-health" && RC4=0 || RC4=$?
assert "ARM4 successful POST -> exits 0" \
  "[[ '$RC4' -eq 0 ]]"
assert "ARM4 successful POST -> a POST was attempted" \
  "[[ -s '$CURL_OUT' ]]"
assert "ARM4 successful POST -> emits NO logger row (silent on success; the quota stays bounded)" \
  "[[ ! -s '$LOGGER_OUT' ]]"

# --- the stub's own non-vacuity ------------------------------------------------------------------
# If the curl stub could not distinguish success from failure, ARM3 and ARM4 would be the same
# test run twice. Prove the seam is consumed.
assert "harness: the curl stub's rc seam is CONSUMED (ARM3 rc=7 and ARM4 rc=0 took different arms)" \
  "[[ '$RC3' -eq 0 && '$RC4' -eq 0 ]] && [[ \$(grep -c . '$LOGGER_OUT') -eq 0 ]]"
# And that the stub would catch a dropped Authorization header rather than passing it through.
CURL_AUTH_PROBE=$(PATH="$WORK/bin:$PATH" CURL_OUT="$WORK/probe.txt" sh -c 'curl -X POST https://x/ -d {} >/dev/null 2>&1; echo $?')
assert "harness: the curl stub REFUSES a POST with no Authorization header (exit 64, not a no-op)" \
  "[[ '$CURL_AUTH_PROBE' -eq 64 ]]"

echo ""
if [[ "$FAIL" -eq 0 ]]; then
  echo "OK inngest-boot-emitter: all assertions passed ($PASS)"
  exit 0
fi
echo "=== Results: $PASS passed, $FAIL failed ==="
exit 1
