#!/usr/bin/env bash
# Tests the registry-host zot container-log SHIPPER (#7440, cloud-init-registry.yml).
#
# WHY THIS EXISTS. The `soleur-registry` host emitted exactly ONE telemetry channel: a
# `SOLEUR_ZOT_DISK` marker every five minutes. The zot container's own log stream went nowhere
# off-box, so every count derived from that channel was a lower bound rather than a measurement
# (the reporter samples `docker logs` once per interval and folds a truncated, quote-stripped
# excerpt into one field). Measured 2026-08-11 over 6h: 72 rows mentioning the host, all 72
# heartbeats; `routes.go` and `blobs/uploads` returned 0; `zotregistry.dev` returned 53 rows, all
# 53 inside a heartbeat echo. This suite covers the shipper that closes that gap.
#
# THE LOG SHAPE IS MEASURED, NOT INFERRED — and getting it wrong ships two INERT mechanisms.
# The heartbeat's `zot_last_err` passes its sample through `tr -d '"\\'`, which removes every
# double quote and backslash. So the colon-joined `{time:...,level:info,caller:zotregistry.dev/...}`
# form is the SAMPLER'S RENDERING, not zot's output. Measured against the pinned image
# (ghcr.io/project-zot/zot-linux-amd64:v2.1.20@sha256:95a837a0afac..., run locally 2026-08-11),
# zot emits quoted zerolog JSON:
#   {"time":"...","level":"info","message":"HTTP API","module":"http","component":"session",
#    "clientIP":"...","method":"GET","path":"/v2/","statusCode":401,"latency":"0s","bodySize":253,
#    "headers":{"Accept":["*/*"],"Authorization":["******"],"User-Agent":["curl/8.18.0"]},
#    "caller":"zotregistry.dev/zot/v2/pkg/api/session.go:92","func":"...","goroutine":156}
# Two consequences, both load-bearing:
#   1. A redaction rule shaped like vector.toml's `(?i)(authorization:\s*)bearer\s+\S+` cannot
#      match `"Authorization":["..."]`. Anchoring on the stripped shape ships redaction that is
#      nominally present and actually inert.
#   2. A discriminator anchored on `caller:zotregistry.dev` matches ONLY the heartbeat echo, so
#      it would report genuine=0 forever even after a fully successful delivery.
# The fixture VALUES below are synthesized (cq-test-fixtures-synthesized-only); their SHAPE is
# the measurement above. Synthesized fixtures against a wrong shape are exactly why the existing
# suite could not have caught this.
#
# MEASURED: zot masks the Authorization header ITSELF (`"Authorization":["******"]`) — the literal
# credential appeared 0 times across basic-auth, Bearer and Basic probes. So the backstop rule
# here is DEFENCE IN DEPTH against a future zot that stops masking, not the primary control. Also
# measured: a non-Authorization header IS logged verbatim (`"X-Custom":["plainvalue"]`), so the
# backstop is anchored on the header-object SHAPE rather than on one header name's known masking.
#
# THE STRIP IS APPLIED BEFORE EXECUTION, AND THAT IS THE POINT OF T2.
# `local.registry_rationale_strip` is `"/(?m)^[ \t]*#([ \t][^\n]*)?\n/"` — a blanket whole-line
# comment strip, NOT a delimited region. It reaches INSIDE write_files heredocs, so any line in an
# embedded program that begins with `#` is silently deleted from what the host runs while surviving
# in the repo file a naive test reads. `zot-liveness-heartbeat.test.sh` is the right extraction
# template but does NOT apply the strip (verified), so it exercises a different program than
# production. This suite applies the strip and asserts the result is still valid bash.
#
# TWO layers (mirrors zot-liveness-heartbeat.test.sh / private-nic-guard.test.sh):
#   1. BEHAVIORAL: render the shipper out of the Terraform template and EXECUTE it against
#      synthesized PATH stubs. No live host, no network, no docker, no doppler, no root.
#   2. STRUCTURAL grep assertions anchored on SYNTAX, never a bare token — this file's own
#      rationale legitimately names `CONTAINER_NAME=zot`, so a bare-token grep would be satisfied
#      by the prose above it (cq-assert-anchor-not-bare-token).
#
# NON-VACUITY: T4 is the positive control for the emit path, so every "did NOT ship" assertion
# below cannot pass merely because the shipper died at line 1 — each is paired with a
# "the shipper ran and shipped the control" assert.
#
# Run: bash apps/web-platform/infra/zot-log-shipper.test.sh

set -uo pipefail

# A suite that builds a sandbox must default TMPDIR itself: test-all.sh and
# run-registered-suites.sh both export TMPDIR=/var/tmp, but a DIRECT invocation (the documented
# inner loop while editing the shipper) inherits the bare machine-global /tmp tmpfs, which
# parallel worktrees share. Without this, verdicts become a function of another session's disk use.
export TMPDIR="${TMPDIR:-/var/tmp}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CI="$SCRIPT_DIR/cloud-init-registry.yml"
SHIPPER_PATH="/usr/local/bin/zot-log-shipper.sh"
JOURNALD_DROPIN="/etc/systemd/journald.conf.d/10-zot-log-shipper.conf"
TEST_INGEST_URL="https://s0000000.eu-fsn-3.example-ingest.invalid/"
TEST_HOST="soleur-registry"

# COUNTERS ARE DERIVED FROM AN EMITTED RECORD, never from two increments (#7444 R6).
# A floor over PASS+FAIL certifies the number of assert CALLS, not that any condition was
# evaluated: moving the increment from the else-branch to the if-branch yields
# "=== N passed, 0 failed ===" at rc=0 with N literal "FAIL:" lines on screen, and the
# fully count-preserving form (never evaluate $cond, just increment PASS) does the same.
# Both are one-token edits. Deriving each verdict from a line appended at decision time
# makes the count a function of what actually happened.
RESULTS="$(mktemp)" || { echo "FATAL: mktemp failed" >&2; exit 2; }
assert() {
  local desc="$1" cond="$2"
  if eval "$cond"; then printf 'PASS\n' >> "$RESULTS"; echo "  PASS: $desc"
  else printf 'FAIL\n' >> "$RESULTS"; echo "  FAIL: $desc"; echo "        condition: $cond"; fi
}
_tally() { PASS=$(grep -cx PASS "$RESULTS" || true); FAIL=$(grep -cx FAIL "$RESULTS" || true); }

# HARNESS CANARY. Verifies the instrument before trusting any verdict it produces: one
# assertion that MUST fail and one that MUST pass, both required to register, then the
# record is reset. Without this, a neutered assert() is indistinguishable from a clean run.
assert "canary: a false condition MUST register as FAIL" "false"
assert "canary: a true condition MUST register as PASS"  "true"
_tally
if [[ "$FAIL" -ne 1 || "$PASS" -ne 1 ]]; then
  echo "FATAL: harness canary did not register (PASS=$PASS FAIL=$FAIL) — assert() is neutered;" >&2
  echo "       every verdict from this run would be meaningless." >&2
  exit 2
fi
: > "$RESULTS"
CANARY_OK=1
echo "  [canary ok] assert() registers both verdicts"

# The floor + gate run from an EXIT trap declared HERE, not at EOF (#7444 R7). At EOF they are
# deleted by the very tail-truncation they exist to detect: cutting the suite from T5 onward
# removed the floor, the gate and the summary line, and the runner saw only rc=0.
_final_gate() {
  local rc=$?
  [[ "$rc" -eq 2 ]] && return   # FATAL paths already reported
  # The canary must be LOAD-BEARING, not merely present: without this check, deleting the
  # canary block is itself an undetected mutation that re-opens the count-preserving
  # assert() neutering the canary exists to catch. Measured — M4 in the battery.
  if [[ "${CANARY_OK:-0}" != "1" ]]; then
    echo "  FAIL: harness canary did not run — assert() is unverified for this whole run" >&2
    echo ""; echo "=== 0 passed, 1 failed ==="
    rm -f "$RESULTS"; rm -rf "$TMP"; exit 1
  fi
  _tally
  local ran=$(( PASS + FAIL ))
  if [[ "$ran" -lt "150" ]]; then
    FAIL=$(( FAIL + 1 ))
    echo "  FAIL: assertion floor — ran $ran assertions, expected >= 150"
    echo "        (suite truncated, or assert() neutered — this run certified nothing)"
  fi
  echo ""
  echo "=== $PASS passed, $FAIL failed ==="
  rm -f "$RESULTS"; rm -rf "$TMP"
  [[ "$FAIL" -eq 0 ]] || exit 1
  exit 0
}

TMP="$(mktemp -d)" || { echo "FATAL: mktemp -d failed (TMPDIR=$TMPDIR)" >&2; exit 2; }
# ONE trap: bash keeps only the LAST handler per signal, so a second
# `trap ... EXIT` line would silently discard the gate. Cleanup happens
# inside _final_gate, before it exits.
trap '_final_gate' EXIT

echo "=== registry zot container-log shipper (#7440) tests ==="
assert "cloud-init-registry.yml exists" "[[ -f '$CI' ]]"
for tool in jq flock timeout; do
  assert "the $tool binary is available (the shipper and this suite both need it)" "[[ -n \"\$(command -v $tool)\" ]]"
done

# --- extraction helper: pull one write_files block's content out of the template ----------
extract_block() {
  local want_path="$1" out="$2"
  awk -v want="  - path: $want_path" '
    $0 == want { found = 1; next }
    found && /^    content: \|$/ { incontent = 1; next }
    incontent {
      if ($0 ~ /^      /) { print substr($0, 7); next }
      if ($0 ~ /^[[:space:]]*$/) { print ""; next }
      exit
    }
  ' "$CI" > "$out"
}

# THE RATIONALE STRIP, replicated faithfully from zot-registry.tf's
# `registry_rationale_strip = "/(?m)^[ \t]*#([ \t][^\n]*)?\n/"`.
# `[[:blank:]]` is EXACTLY space+tab, matching RE2's `[ \t]` — `[[:space:]]` would be wider.
# Note what this does NOT strip: `#like-this` (no blank right after `#`) survives and costs bytes.
apply_rationale_strip() {
  sed -E '/^[[:blank:]]*#([[:blank:]].*)?$/d' "$1"
}

# --- T1: the strip replica is faithful ---------------------------------------------------
# Asserted against a fixture rather than trusted, because every assertion below runs on the
# stripped program: a wrong strip makes the whole suite exercise the wrong bytes.
STRIPFIX="$TMP/stripfix"
printf '%s\n' 'keep=1' '# full line comment' '   # indented comment' '#' '#like-this' 'tail=2' '  code # trailing' > "$STRIPFIX"
STRIPPED_FIX="$(apply_rationale_strip "$STRIPFIX")"
assert "T1 strip removes a whole-line comment" "! grep -q 'full line comment' <<<\"\$STRIPPED_FIX\""
assert "T1 strip removes an indented whole-line comment" "! grep -q 'indented comment' <<<\"\$STRIPPED_FIX\""
assert "T1 strip removes a bare '#' line" "[[ \$(grep -cxF '#' <<<\"\$STRIPPED_FIX\") -eq 0 ]]"
assert "T1 strip PRESERVES '#like-this' (no blank after #) — it survives and costs bytes" \
  "grep -qxF '#like-this' <<<\"\$STRIPPED_FIX\""
assert "T1 strip preserves code lines" "grep -qxF 'keep=1' <<<\"\$STRIPPED_FIX\" && grep -qxF 'tail=2' <<<\"\$STRIPPED_FIX\""
assert "T1 strip preserves a trailing comment on a code line" "grep -q 'code # trailing' <<<\"\$STRIPPED_FIX\""

# --- T2: render the shipper, apply the strip, and prove it is still valid bash -----------
RAW="$TMP/shipper.raw.sh"
extract_block "$SHIPPER_PATH" "$RAW"
assert "T2 shipper block extracted from the template (non-empty)" "[[ -s '$RAW' ]]"
assert "T2 extracted block is the shipper (has a shebang)" "head -1 '$RAW' | grep -q '^#!'"

SHIPPER="$TMP/shipper.sh"
apply_rationale_strip "$RAW" > "$SHIPPER"
sed -i "s|\${betterstack_ingest_url}|$TEST_INGEST_URL|g" "$SHIPPER"
# TF-escaped shell expansions: $${VAR} -> ${VAR}; %%{ -> %{ (the templatefile directive escape —
# a `-w '%{http_code}'` MUST be written `%%{...}` or terraform's scanner rejects the render).
sed -i 's|\$\${|${|g' "$SHIPPER"
sed -i 's|%%{|%{|g' "$SHIPPER"
# Charset at least as wide as Terraform's own var names (digits included): a missed digit-bearing
# var never trips `set -u` inside quotes, so the suite would silently execute a broken shipper.
assert "T2 render left no unrendered TF interpolation" "! grep -qE '\\\$\{[A-Za-z0-9_.]+\}' '$SHIPPER'"
assert "T2 render left no unescaped TF directive" "! grep -qF '%%{' '$SHIPPER'"
assert "T2 the COMMENT-STRIPPED shipper is still syntactically valid bash (the strip reaches inside heredocs)" \
  "bash -n '$SHIPPER'"
chmod +x "$SHIPPER"

# The shipper is what the host RUNS, so the strip must not have emptied it of logic.
assert "T2 stripped shipper retains executable content (>=20 non-blank lines)" \
  "[[ \$(grep -cvE '^[[:space:]]*$' '$SHIPPER') -ge 20 ]]"

# --- T3: field-match LOCKSTEP is a VALUE COMPARISON, not two existence checks ------------
# Two independent greps are a union, not a lockstep, and both naive forms mis-fire here:
# `grep -c 'CONTAINER_NAME=zot'` is satisfied by this file's own rationale, and the sharper trap
# is that `grep -- '--name zot'` MATCHES `--name zot-log-shipper` — a name this change introduces.
JMATCH=$(grep -oE 'CONTAINER_NAME=[A-Za-z0-9_.-]+' "$SHIPPER" | head -1 | cut -d= -f2)
DNAME=$(grep -oE -- '--name[[:space:]]+[A-Za-z0-9_.-]+' "$CI" | awk '{print $2}' | grep -x zot | head -1)
assert "T3 shipper's journald match value was extracted" "[[ -n '$JMATCH' ]]"
assert "T3 docker --name value 'zot' was extracted (anchored: must not match --name zot-log-shipper)" \
  "[[ -n '$DNAME' ]]"
assert "T3 journald match == docker container name (lockstep by VALUE: '$JMATCH' vs '$DNAME')" \
  "[[ -n '$JMATCH' && '$JMATCH' == '$DNAME' ]]"
# The match must live on the EXECUTABLE journalctl invocation, not merely somewhere in the file.
assert "T3 the match is on the journalctl invocation (executable anchor, not prose)" \
  "grep -qE 'journalctl[^|]*CONTAINER_NAME=zot' '$SHIPPER'"

# --- T4..T12: BEHAVIORAL — execute the stripped shipper against stubs --------------------
BIN="$TMP/bin"; mkdir -p "$BIN"

# journalctl stub: emits synthesized zot-shaped zerolog JSON with a __CURSOR per entry, modelling
# the real `--output=json` contract. Driven by $STUB_JOURNAL (a file of MESSAGE payloads, one per
# line). It VALIDATES argv and exits 64 on a missing required flag: a stub that answers regardless
# of its arguments puts the fixture seam ABOVE the code under test, so the shipper could query the
# wrong thing and stay green.
cat > "$BIN/journalctl" <<'EOS'
#!/usr/bin/env bash
have_match=0; have_json=0; have_follow=0; since=""; after_cursor=""; prev=""
for a in "$@"; do
  case "$a" in
    CONTAINER_NAME=zot) have_match=1 ;;
    --output=json)      have_json=1 ;;
    --follow|-f)        have_follow=1 ;;
    --since=*)          since="${a#--since=}" ;;
  esac
  [[ "$prev" == "--after-cursor" ]] && after_cursor="$a"
  [[ "$prev" == "--since" ]] && since="$a"
  prev="$a"
done
printf 'match=%s json=%s follow=%s since=%s after=%s\n' \
  "$have_match" "$have_json" "$have_follow" "$since" "$after_cursor" >> "$STUB_JCALLS"
[[ "$have_match" == 1 ]] || { echo "journalctl stub: missing CONTAINER_NAME=zot match" >&2; exit 64; }
[[ "$have_json"  == 1 ]] || { echo "journalctl stub: missing --output=json" >&2; exit 64; }
# A cursor the shipper cannot resume from: model journald's own rejection.
if [[ -n "$after_cursor" && "$after_cursor" == "INVALID-CURSOR" ]]; then
  echo "Failed to seek to cursor: Invalid argument" >&2; exit 1
fi
n=0
while IFS= read -r msg; do
  n=$((n + 1))
  [[ -n "${STUB_SKIP_UNTIL:-}" && "$n" -le "$STUB_SKIP_UNTIL" ]] && continue
  jq -cn --arg m "$msg" --arg c "s=aaa;i=$n;b=bbb" \
    '{__CURSOR:$c, CONTAINER_NAME:"zot", _TRANSPORT:"journal", MESSAGE:$m}'
done < "$STUB_JOURNAL"
# A cron one-shot never passes --follow, so the stub cannot rely on --follow to hold the shipper
# open for the SIGKILL case. $STUB_HANG models the real reason a TICK can be killed mid-flight:
# journald streaming slowly (or the tick simply running long) while an OOM kill or a reboot lands.
# Without this the shipper would exit cleanly on its own and T10b would prove clean-exit
# durability while claiming SIGKILL durability.
[[ -n "${STUB_HANG:-}" ]] && sleep 300
exit 0
EOS
chmod +x "$BIN/journalctl"

# curl stub: records the full POSTed body so the envelope, the redaction and the drop rows are all
# observable. Honours -m (bounded egress) and models a POST failure via $STUB_POST_FAIL.
# The stub VALIDATES argv and exits 64 on anything missing. Recording a value that nothing
# asserts reads as coverage in review and provides none: `url=` was recorded and unread, so a
# combined mutation pointing the POST at an arbitrary third-party host with no auth header kept
# the suite fully green while every zot row - internal 10.0.1.x topology, OCI repo names,
# digests - was redirected off-estate (#7444 R16).
#
# STUB_POST_FAIL_MATCH fails only the rows whose body contains a token, which is what makes the
# F-3 defect instantiable at all: with a global fail switch and a one-row fixture, neither the
# "earlier failure" nor the "later row" half of "the next successful line advances the cursor
# past the hole" can exist (#7444 R17).
cat > "$BIN/curl" <<'EOS'
#!/usr/bin/env bash
body=""; has_m=0; url=""; auth=""; prev=""
for a in "$@"; do
  case "$a" in
    http*://*) url="$a" ;;
    "Authorization: Bearer "*) auth="$a" ;;
  esac
  [[ "$prev" == "--data-raw" ]] && body="$a"
  [[ "$prev" == "-m" || "$prev" == "--max-time" ]] && has_m=1
  prev="$a"
done
printf 'm=%s url=%s auth=%s\n' "$has_m" "$url" "${auth:+yes}" >> "$STUB_CURLARGS"
[[ "$has_m" == 1 ]] || { echo "curl stub: unbounded call (no -m/--max-time)" >&2; exit 64; }
[[ -n "$url"  ]] || { echo "curl stub: no URL argument" >&2; exit 64; }
[[ -n "$auth" ]] || { echo "curl stub: no Authorization: Bearer header" >&2; exit 64; }
if [[ "${STUB_POST_FAIL:-0}" == 1 ]]; then exit 22; fi
if [[ -n "${STUB_POST_FAIL_MATCH:-}" && "$body" == *"$STUB_POST_FAIL_MATCH"* ]]; then exit 22; fi
printf '%s\n' "$body" >> "$STUB_POSTS"
exit 0
EOS
chmod +x "$BIN/curl"

cat > "$BIN/hostname" <<EOS
#!/usr/bin/env bash
printf '%s\n' "$TEST_HOST"
EOS
chmod +x "$BIN/hostname"

# Run the shipper once over a fixture journal. The shipper is a cron ONE-SHOT (ADR-184 §4), so
# there is no ONESHOT override to pass any more — production runs exactly this shape, which is
# what removes the "the suite drives a mode production does not run" seam.
run_shipper() {
  local journal="$1"; shift
  STUB_POSTS="$TMP/posts.$RANDOM"; STUB_CURLARGS="$TMP/curlargs.$RANDOM"
  STUB_JCALLS="$TMP/jcalls.$RANDOM"
  : > "$STUB_POSTS"; : > "$STUB_CURLARGS"; : > "$STUB_JCALLS"
  local state="$TMP/state.$RANDOM"; mkdir -p "$state"
  CASE_RC=0
  env PATH="$BIN:/usr/bin:/bin" \
      STUB_JOURNAL="$journal" STUB_POSTS="$STUB_POSTS" STUB_CURLARGS="$STUB_CURLARGS" \
      STUB_JCALLS="$STUB_JCALLS" \
      BETTERSTACK_LOGS_TOKEN="synthetic-ingest-token-not-a-real-secret" \
      ZOT_LOG_SHIPPER_STATE_DIR="$state" \
      "$@" \
      timeout 25 bash "$SHIPPER" >"$TMP/out.$RANDOM" 2>&1 || CASE_RC=$?
  LAST_STATE="$state"
}

# --- T4: POSITIVE CONTROL — a genuine zot line ships, enveloped -------------------------
J1="$TMP/j1"
cat > "$J1" <<'EOS'
{"time":"2026-08-11T10:17:25.584625537Z","level":"info","message":"HTTP API","module":"http","component":"session","clientIP":"10.0.1.30:39330","method":"GET","path":"/v2/","statusCode":401,"latency":"0s","bodySize":253,"headers":{"Accept":["*/*"],"User-Agent":["curl/8.5.0"]},"caller":"zotregistry.dev/zot/v2/pkg/api/session.go:92","func":"zotregistry.dev/zot/v2/pkg/api.SessionLogger.func1.1","goroutine":156}
EOS
run_shipper "$J1"
assert "T4 shipper exited cleanly on a well-formed journal (rc=$CASE_RC)" "[[ '$CASE_RC' -eq 0 ]]"
assert "T4 exactly one row was POSTed" "[[ \$(grep -c . '$STUB_POSTS') -eq 1 ]]"
assert "T4 the POSTed row carries the envelope prefix" \
  "grep -q 'SOLEUR_ZOT_LOG shipper=zot-log-shipper host=$TEST_HOST ' '$STUB_POSTS'"
assert "T4 the POSTed row carries the encoding-safe zot-only token the probe greps" \
  "grep -qF 'zotregistry.dev/zot/v2/pkg/api' '$STUB_POSTS'"
assert "T4 the POSTed body is a single-key JSON object (mirrors the proven reporter transport)" \
  "jq -e 'keys == [\"message\"]' < <(head -1 '$STUB_POSTS') >/dev/null"
assert "T4 every egress call went to the configured ingest URL, not an arbitrary host" \
  "[[ \$(grep -c \"url=$TEST_INGEST_URL \" '$STUB_CURLARGS') -eq \$(grep -c . '$STUB_CURLARGS') ]]"
assert "T4 every egress call carried an Authorization: Bearer header" \
  "! grep -q 'auth=$' '$STUB_CURLARGS'"
assert "T4 every egress call was bounded (-m/--max-time present)" \
  "[[ \$(grep -c 'm=1' '$STUB_CURLARGS') -eq \$(grep -c . '$STUB_CURLARGS') ]]"
assert "T4 the journalctl query did NOT pass --follow (a cron one-shot must drain and exit)" \
  "grep -q 'follow=0' '$STUB_JCALLS'"
# A COLD start (no cursor ever persisted) must read from the beginning of the retained journal:
# that host's journal is small and the boot backlog is exactly what the persistence exists to
# preserve. --since is the INVALIDATION bound (T10), not a cold-start one.
assert "T4 a cold start is NOT bounded by --since (the boot backlog must not be discarded)" \
  "grep -q 'since= ' '$STUB_JCALLS'"
assert "T4 the cursor was persisted after the successful POST" \
  "[[ -s '$LAST_STATE/cursor' ]]"

# --- T5: the envelope host token is IN-MESSAGE, never a host_name field -----------------
# Source 2457081 is shared by every host and `host_name` is VECTOR-populated; this channel has no
# Vector, so a direct POST carries no host_name at all. The in-message token is the ONLY isolation.
assert "T5 the host token lives inside the message string" \
  "jq -re '.message' < <(head -1 '$STUB_POSTS') | grep -q 'host=$TEST_HOST'"
assert "T5 the POSTed object carries no host_name key (it would be a phantom on this channel)" \
  "! jq -e 'has(\"host_name\")' < <(head -1 '$STUB_POSTS') >/dev/null"

# --- T6: SANITIZER (payload integrity) vs REDACTION (credential) — asserted SEPARATELY --
# The `tr` pipeline is RFC 8259 payload integrity, NOT redaction, and conflating the two is how
# five dead rules get restored later in the belief they were safety.
J_TAB="$TMP/j_tab"
printf '%s\n' '{"level":"error","message":"panic\tgoroutine 1 [running]:","caller":"zotregistry.dev/zot/v2/pkg/api/routes.go:1"}' > "$J_TAB"
run_shipper "$J_TAB"
assert "T6 sanitizer: a shipped row contains no raw double quote (would corrupt the JSON body)" \
  "[[ \$(jq -re '.message' < <(head -1 '$STUB_POSTS') | grep -c '\"') -eq 0 ]]"
assert "T6 sanitizer: the POSTed body is still valid JSON after a tab-bearing input" \
  "jq -e . < <(head -1 '$STUB_POSTS') >/dev/null"

# The length BOUND was unasserted until this case. `${s:0:MAXLEN}` is a bounded substring rather
# than `head -c` deliberately — under pipefail, head closing the pipe early makes the producer take
# SIGPIPE and the pipeline report 141 — but a bound nothing exercises is a bound nothing pins, and a
# Go panic trace is exactly the input that reaches it. Two directions matter: the row must be
# TRUNCATED (an unbounded line risks a rejected payload) and it must still be valid JSON afterwards
# (truncation must not sever an escape or leave the body malformed).
J_LONG="$TMP/j_long"
LONGMSG="$(printf 'A%.0s' $(seq 1 2000))"
printf '{"level":"error","message":"panic %s","caller":"zotregistry.dev/zot/v2/pkg/api/routes.go:1"}\n' "$LONGMSG" > "$J_LONG"
run_shipper "$J_LONG"
assert "T6 a 2000-char line was truncated (the MAXLEN bound is load-bearing, not decorative)" \
  "[[ \$(jq -re '.message' < <(head -1 '$STUB_POSTS') | wc -c) -lt 1200 ]]"
assert "T6 the truncated row is still valid JSON (truncation did not sever the body)" \
  "jq -e . < <(head -1 '$STUB_POSTS') >/dev/null"
assert "T6 the truncated row still carries the envelope, so it remains attributable" \
  "grep -q 'SOLEUR_ZOT_LOG shipper=zot-log-shipper host=$TEST_HOST ' '$STUB_POSTS'"

# NEGATIVE CONTROL: a clean diagnostic line must survive with its diagnostic content intact.
J_GC="$TMP/j_gc"
printf '%s\n' '{"level":"info","message":"executing gc","component":"gc","caller":"zotregistry.dev/zot/v2/pkg/storage/gc.go:1"}' > "$J_GC"
run_shipper "$J_GC"
assert "T6 negative control: a clean gc line survives sanitisation with its content intact" \
  "grep -qF 'executing gc' '$STUB_POSTS' && grep -qF 'zotregistry.dev/zot/v2/pkg/storage/gc.go:1' '$STUB_POSTS'"

# REDACTION backstop, anchored on the RAW QUOTED shape measured in Phase 0.3. A rule written
# against the quote-stripped form (`authorization: bearer ...`) cannot match this and would ship
# nominally-present, actually-inert redaction.
J_AUTH="$TMP/j_auth"
printf '%s\n' '{"level":"info","message":"HTTP API","headers":{"Accept":["*/*"],"Authorization":["Basic c3ludGhldGljOm5vdC1yZWFs"],"User-Agent":["curl/8.5.0"]},"caller":"zotregistry.dev/zot/v2/pkg/api/session.go:92"}' > "$J_AUTH"
run_shipper "$J_AUTH"
assert "T6 redaction: the synthesized credential value never reaches the wire" \
  "! grep -qF 'c3ludGhldGljOm5vdC1yZWFs' '$STUB_POSTS'"
assert "T6 redaction: the row still ships (redaction must not drop the line)" \
  "[[ \$(grep -c . '$STUB_POSTS') -eq 1 ]]"
assert "T6 redaction: a REDACTED marker is present so the elision is visible, not silent" \
  "grep -q 'REDACTED' '$STUB_POSTS'"
assert "T6 redaction: an ALLOWLISTED routing header is preserved (User-Agent is not a credential)" \
  "grep -qF 'curl/8.5.0' '$STUB_POSTS'"

# INVERTED (#7444 F-10). This assertion previously read "an unrelated header value is preserved"
# and was satisfied by an arbitrary UNKNOWN header surviving — which LOCKED THE GAP IN: the rule
# was header-NAME-anchored on the literal [Aa]uthorization, so Cookie, X-Api-Key and
# X-Amz-Security-Token all shipped verbatim and silently, while Proxy-Authorization shipped and
# THEN tripped the probe's own leak detector. Meanwhile ADR-184 §3 and the cloud-init comment both
# claimed anchoring on "the header-object shape rather than trusting one header name's known
# masking". The redaction is now a name ALLOWLIST over the whole headers object, so the failure
# mode of an unanticipated header is over-redaction rather than silent leakage.
J_HDRS="$TMP/j_hdrs"
printf '%s\n' '{"level":"info","message":"HTTP API","headers":{"Accept":["*/*"],"Cookie":["session=synthetic-cookie-not-real"],"X-Api-Key":["synthetic-apikey-not-real"],"Proxy-Authorization":["Basic c3ludGhldGljOnByb3h5"],"X-Future-Header":["synthetic-future-not-real"],"User-Agent":["curl/8.5.0"]},"caller":"zotregistry.dev/zot/v2/pkg/api/session.go:92"}' > "$J_HDRS"
run_shipper "$J_HDRS"
assert "T6 redaction: the row shipped (non-vacuity for the four assertions below)" \
  "[[ \$(grep -c . '$STUB_POSTS') -eq 1 ]]"
for _leak in synthetic-cookie-not-real synthetic-apikey-not-real c3ludGhldGljOnByb3h5; do
  assert "T6 redaction: a NON-Authorization credential header ($_leak) does not reach the wire" \
    "! grep -qF '$_leak' '$STUB_POSTS'"
done
assert "T6 redaction: an ARBITRARY UNKNOWN header is redacted too (allowlist, not denylist)" \
  "! grep -qF 'synthetic-future-not-real' '$STUB_POSTS'"
assert "T6 redaction: the allowlisted headers still survive this row (not a blanket wipe)" \
  "grep -qF 'curl/8.5.0' '$STUB_POSTS'"

# A `]` INSIDE the Authorization value defeated the previous value class: `[^]]*\]` stopped at the
# first `]`, so the row shipped `Authorization:[REDACTED` with the credential tail three characters
# to its right, and the probe's own subtraction then exonerated the line.
J_BRACKET="$TMP/j_bracket"
printf '%s\n' '{"level":"info","message":"HTTP API","headers":{"Authorization":["Basic synth]etic-bracket-not-real"],"User-Agent":["curl/8.5.0"]},"caller":"zotregistry.dev/zot/v2/pkg/api/session.go:92"}' > "$J_BRACKET"
run_shipper "$J_BRACKET"
assert "T6 redaction: a ']' inside the credential value does not truncate the redaction" \
  "! grep -qF 'etic-bracket-not-real' '$STUB_POSTS'"

# --- T6b: REDACTION POSITIONAL COVERAGE (#7444 R8) --------------------------------------
# The jq rewrite keyed on a TOP-LEVEL, lowercase, object-valued `headers` and returned every
# other shape unmodified at rc=0 — a REGRESSION, since the sed it replaced matched
# "Authorization":[...] anywhere in the line text. Every fixture below is a shape that leaked.
# Note the axis this closes: all 131 prior fixtures were well-formed top-level JSON objects, so
# the non-JSON branch and the nested/capitalised/array shapes were dead code w.r.t. the suite.
_SECRET='SECRETVALUE123'
redaction_case() {   # label, journal-line
  local label="$1" line="$2"
  local j="$TMP/j_red.$RANDOM"
  printf '%s\n' "$line" > "$j"
  run_shipper "$j"
  assert "T6b $label: the credential never reaches the wire" \
    "! grep -qF '$_SECRET' '$STUB_POSTS'"
}
redaction_case "nested request.headers" \
  '{"request":{"headers":{"Authorization":["Basic SECRETVALUE123"]}}}'
redaction_case "capitalised Headers key" \
  '{"Headers":{"Authorization":["Basic SECRETVALUE123"]}}'
redaction_case "bare top-level Authorization" \
  '{"Authorization":["Basic SECRETVALUE123"]}'
redaction_case "top-level array" \
  '[{"headers":{"Cookie":["SECRETVALUE123"]}}]'
# journald splits a line exceeding the log driver's buffer, and header size is client-controlled,
# so a private-net client with a large Cookie chooses whether the line arrives as invalid JSON.
redaction_case "truncated JSON fragment" \
  '{"level":"info","headers":{"Cookie":["SECRETVALUE123"],"Authorization":["Bearer SECRETVALUE123'
# How a panic trace or a pre-logger startup error actually renders. Neither previous sed rule
# matched the bare form, and the probe's leak arm greps `Authorization:[` so it could not see it.
redaction_case "bare Authorization in plaintext" \
  'panic: config load failed; GET /v2/ Authorization: Basic SECRETVALUE123 from 10.0.1.30'

# NON-VACUITY, and the direction the fixtures above cannot see: an over-aggressive redactor
# would satisfy every one of them. A clean plaintext line must still ship with content intact,
# and an allowlisted routing header must survive.
J_CLEAN="$TMP/j_clean"
printf '%s\n' 'panic: runtime error: index out of range [3] with length 3' > "$J_CLEAN"
run_shipper "$J_CLEAN"
assert "T6b non-vacuity: a credential-free plaintext line still ships, content intact" \
  "grep -qF 'index out of range' '$STUB_POSTS'"

# --- T7: FEEDBACK-LOOP guard ------------------------------------------------------------
# Measured: a `zot-log-shipper`-tagged journal entry carries NO CONTAINER_NAME, and
# `journalctl CONTAINER_NAME=zot` excludes it (0 hits). Asserted on BOTH sides of the filter.
# Under cron there is no SyslogIdentifier= to set, and none is needed: the match field is
# CONTAINER_NAME, which ONLY the journald container log driver populates. The shipper runs
# directly from cron on the host, never inside a container, so its own stderr breadcrumbs cannot
# carry that field — the exclusion is structural rather than configured.
assert "T7 the shipper is invoked directly on the host, not through docker (its lines cannot carry CONTAINER_NAME)" \
  "! grep -qE '^[[:space:]]*[0-9*/,-]+ .*docker .*zot-log-shipper\.sh' '$CI'"
assert "T7 the shipper matches CONTAINER_NAME (a field its own journald lines cannot carry)" \
  "grep -qE 'journalctl[^|]*CONTAINER_NAME=zot' '$SHIPPER'"
assert "T7 the shipper does not match on its own SyslogIdentifier (that would be a feedback loop)" \
  "! grep -qE 'journalctl[^|]*(-t|--identifier)[[:space:]=]*zot-log-shipper' '$SHIPPER'"

# --- T8: SINGLETON — flock -n, mirroring the NIC guard (the disk heartbeat has none) ----
# Under Restart=always systemd already guaranteed a single instance, so flock was decorative.
# Under cron it is load-bearing: a tick that outruns its 5-minute slot would otherwise overlap the
# next one and double-ship every row between their cursors.
assert "T8 the shipper's cron line is flock -n guarded (a tick overrun would double-ship)" \
  "grep -qE '^[[:space:]]*[0-9*/,-]+ .*flock[[:space:]]+-n[[:space:]].*zot-log-shipper\.sh' '$CI'"

# --- T9: RATE CAP + cap-exempt evidence classes -----------------------------------------
# The four classes are the measured evidence vocabulary the downstream disk-attribution question
# needs. Without the exemption the cap drops them preferentially during exactly the flood
# (crash-loop / pull storm) that accompanies disk growth.
J_FLOOD="$TMP/j_flood"
: > "$J_FLOOD"
for i in $(seq 1 40); do
  printf '%s\n' "{\"level\":\"info\",\"message\":\"HTTP API\",\"path\":\"/v2/ordinary-$i\",\"caller\":\"zotregistry.dev/zot/v2/pkg/api/session.go:92\"}" >> "$J_FLOOD"
done
printf '%s\n' '{"level":"info","message":"executing gc","component":"gc","caller":"zotregistry.dev/zot/v2/pkg/storage/gc.go:1"}' >> "$J_FLOOD"
printf '%s\n' '{"level":"info","message":"gc successfully completed","component":"gc","caller":"zotregistry.dev/zot/v2/pkg/storage/gc.go:2"}' >> "$J_FLOOD"
printf '%s\n' '{"level":"info","message":"garbage collected blobs","component":"gc","caller":"zotregistry.dev/zot/v2/pkg/storage/gc.go:3"}' >> "$J_FLOOD"
printf '%s\n' '{"level":"error","message":"PatchBlobUpload i/o timeout","caller":"zotregistry.dev/zot/v2/pkg/api/routes.go:1"}' >> "$J_FLOOD"
run_shipper "$J_FLOOD" ZOT_LOG_SHIPPER_CAP_PER_INTERVAL=5
assert "T9 the cap dropped ordinary rows under a flood (shipped < offered)" \
  "[[ \$(grep -c 'ordinary-' '$STUB_POSTS') -lt 40 ]]"
for cls in 'executing gc' 'gc successfully completed' 'garbage collected blobs' 'PatchBlobUpload'; do
  assert "T9 cap-exempt class survived the flood: '$cls'" "grep -qF '$cls' '$STUB_POSTS'"
done
assert "T9 a DROPPED accounting row was emitted" \
  "grep -q 'SOLEUR_ZOT_LOG_DROPPED' '$STUB_POSTS'"
for f in 'n=' 'interval_s=' 'boot_id=' 'seq=' 'cum=' 'reason=rate_cap'; do
  assert "T9 the DROPPED row carries '$f'" \
    "grep 'SOLEUR_ZOT_LOG_DROPPED' '$STUB_POSTS' | grep -qF '$f'"
done
# `n` is scoped to the interval the row CLOSES — an 'exact count' against an undefined denominator
# is what a fixture would silently pin to whatever the implementation happened to do.
DROP_N=$(grep -o 'SOLEUR_ZOT_LOG_DROPPED n=[0-9]*' "$STUB_POSTS" | head -1 | grep -o '[0-9]*$')
SHIPPED_ORD=$(grep -c 'ordinary-' "$STUB_POSTS")
assert "T9 dropped n + shipped ordinary == offered ordinary (n is interval-scoped, not a free number)" \
  "[[ -n '$DROP_N' && \$(( DROP_N + SHIPPED_ORD )) -eq 40 ]]"

# --- T10: CURSOR durability + invalidation ----------------------------------------------
assert "T10 the cursor is written atomically (a torn cursor would replay or gap silently)" \
  "grep -qE 'mv[[:space:]]+(-f[[:space:]]+)?\"?\\\$[A-Za-z_]*(CURSOR|TMP)' '$SHIPPER'"
# Resume: a seeded cursor must be passed as --after-cursor, and only newer entries ship.
run_shipper "$J1"
SEEDED="$LAST_STATE"
J2="$TMP/j2"
cat "$J1" > "$J2"
printf '%s\n' '{"level":"info","message":"HTTP API","path":"/v2/second","caller":"zotregistry.dev/zot/v2/pkg/api/session.go:92"}' >> "$J2"
STUB_POSTS="$TMP/posts.resume"; STUB_CURLARGS="$TMP/curlargs.resume"; STUB_JCALLS="$TMP/jcalls.resume"
: > "$STUB_POSTS"; : > "$STUB_CURLARGS"; : > "$STUB_JCALLS"
RESUME_RC=0
env PATH="$BIN:/usr/bin:/bin" STUB_JOURNAL="$J2" STUB_POSTS="$STUB_POSTS" \
    STUB_CURLARGS="$STUB_CURLARGS" STUB_JCALLS="$STUB_JCALLS" STUB_SKIP_UNTIL=1 \
    BETTERSTACK_LOGS_TOKEN="synthetic-ingest-token-not-a-real-secret" \
    ZOT_LOG_SHIPPER_STATE_DIR="$SEEDED" \
    timeout 25 bash "$SHIPPER" >/dev/null 2>&1 || RESUME_RC=$?
assert "T10 the resume run exited cleanly (rc=$RESUME_RC) — without this the asserts below could pass on a crashed shipper" \
  "[[ '$RESUME_RC' -eq 0 ]]"
assert "T10 resume passed the persisted cursor as --after-cursor" \
  "grep -qE 'after=s=aaa' '$STUB_JCALLS'"
assert "T10 resume shipped only the newer entry (no replay of the already-delivered row)" \
  "[[ \$(grep -c . '$STUB_POSTS') -eq 1 ]] && grep -qF '/v2/second' '$STUB_POSTS'"
# An unusable cursor must say so and restart from the tail, never gap silently.
BADSTATE="$TMP/badstate"; mkdir -p "$BADSTATE"; printf 'INVALID-CURSOR' > "$BADSTATE/cursor"
STUB_POSTS="$TMP/posts.badcur"; STUB_CURLARGS="$TMP/curlargs.badcur"; STUB_JCALLS="$TMP/jcalls.badcur"
: > "$STUB_POSTS"; : > "$STUB_CURLARGS"; : > "$STUB_JCALLS"
BAD_RC=0
env PATH="$BIN:/usr/bin:/bin" STUB_JOURNAL="$J1" STUB_POSTS="$STUB_POSTS" \
    STUB_CURLARGS="$STUB_CURLARGS" STUB_JCALLS="$STUB_JCALLS" \
    BETTERSTACK_LOGS_TOKEN="synthetic-ingest-token-not-a-real-secret" \
    ZOT_LOG_SHIPPER_STATE_DIR="$BADSTATE" \
    timeout 25 bash "$SHIPPER" >/dev/null 2>&1 || BAD_RC=$?
assert "T10 the invalid-cursor run exited cleanly (rc=$BAD_RC) — an abort here would make the asserts below vacuous" \
  "[[ '$BAD_RC' -eq 0 ]]"
assert "T10 an invalidated cursor emits reason=cursor_invalidated rather than gapping silently" \
  "grep -q 'reason=cursor_invalidated' '$STUB_POSTS'"
assert "T10 after cursor invalidation the shipper still ships (it restarted from the tail)" \
  "grep -q 'SOLEUR_ZOT_LOG shipper=' '$STUB_POSTS'"

# --- T10b: cursor durability across SIGKILL, not merely a clean stop --------------------
# THE WHOLE REASON journalctl's own --cursor-file was rejected. Measured on systemd 259: that file
# is written at clean exit only — SIGTERM writes it, SIGKILL leaves it stale — because the flag is
# built for sequential one-shot invocations, not a Restart=always daemon. On an OOM-kill (and this
# host has an OOM restart-loop history) the shipper would resume from the last CLEAN-EXIT cursor and
# re-ship everything since, unbounded: the runaway-volume mode created by the mechanism meant to
# prevent gaps. Self-persisting __CURSOR after each successful POST is what makes SIGKILL survivable,
# and a clean-stop test cannot tell the two designs apart — so this case is the discriminator.
KSTATE="$TMP/kstate"; mkdir -p "$KSTATE"
KPOSTS="$TMP/posts.kill"; KCURL="$TMP/curlargs.kill"; KJC="$TMP/jcalls.kill"
: > "$KPOSTS"; : > "$KCURL"; : > "$KJC"
env PATH="$BIN:/usr/bin:/bin" \
    STUB_JOURNAL="$J1" STUB_POSTS="$KPOSTS" STUB_CURLARGS="$KCURL" STUB_JCALLS="$KJC" \
    BETTERSTACK_LOGS_TOKEN="synthetic-ingest-token-not-a-real-secret" \
    ZOT_LOG_SHIPPER_STATE_DIR="$KSTATE" STUB_HANG=1 \
    bash "$SHIPPER" >/dev/null 2>&1 &
SHIP_PID=$!
# Wait for the cursor to land (i.e. a POST succeeded), bounded so a hang cannot wedge CI.
for _ in $(seq 1 60); do [[ -s "$KSTATE/cursor" ]] && break; sleep 0.25; done
CURSOR_BEFORE="$(cat "$KSTATE/cursor" 2>/dev/null || true)"
assert "T10b the shipper was still ALIVE when killed (a clean exit would void this case)" \
  "kill -0 '$SHIP_PID' 2>/dev/null"
assert "T10b it was mid-tick when killed, not idling (the journal read had not returned)" \
  "grep -q 'follow=0' '$KJC'"
kill -KILL "$SHIP_PID" 2>/dev/null
wait "$SHIP_PID" 2>/dev/null
CURSOR_AFTER="$(cat "$KSTATE/cursor" 2>/dev/null || true)"
assert "T10b a cursor was persisted BEFORE the kill (written per successful POST, not at exit)" \
  "[[ -n '$CURSOR_BEFORE' ]]"
assert "T10b the cursor SURVIVED SIGKILL intact (--cursor-file would be stale or absent here)" \
  "[[ -n '$CURSOR_AFTER' && '$CURSOR_AFTER' == '$CURSOR_BEFORE' ]]"
assert "T10b the surviving cursor is the DELIVERED entry's cursor, not a placeholder" \
  "[[ '$CURSOR_AFTER' == 's=aaa;i=1;b=bbb' ]]"
# And the payoff: resuming from that cursor must not replay the already-delivered row.
KPOSTS2="$TMP/posts.kill2"; KJC2="$TMP/jcalls.kill2"; : > "$KPOSTS2"; : > "$KJC2"
env PATH="$BIN:/usr/bin:/bin" \
    STUB_JOURNAL="$J1" STUB_POSTS="$KPOSTS2" STUB_CURLARGS="$TMP/curlargs.kill2" STUB_JCALLS="$KJC2" \
    STUB_SKIP_UNTIL=1 \
    BETTERSTACK_LOGS_TOKEN="synthetic-ingest-token-not-a-real-secret" \
    ZOT_LOG_SHIPPER_STATE_DIR="$KSTATE" \
    timeout 25 bash "$SHIPPER" >/dev/null 2>&1
assert "T10b post-SIGKILL resume passed the surviving cursor as --after-cursor" \
  "grep -q 'after=s=aaa;i=1' '$KJC2'"
assert "T10b post-SIGKILL resume replayed NOTHING (the runaway-volume mode is closed)" \
  "[[ \$(grep -c . '$KPOSTS2') -eq 0 ]]"

# --- T11: POST failure telemetry rides an INDEPENDENT path ------------------------------
# A counter surfaced on the channel it monitors is unobservable exactly when it is non-zero: when
# the POST path is the fault, the row carrying the counter never arrives. So the counter is written
# to a state file that the 5-min SOLEUR_ZOT_DISK reporter reads and carries in ITS line.
run_shipper "$J1" STUB_POST_FAIL=1
FAILSTATE="$LAST_STATE"
# THE CURSOR MUST NOT ADVANCE PAST AN UNDELIVERED ROW (#7444 F-3). Before this, a failed POST
# only incremented POST_FAIL and the loop carried on, so the NEXT successful row advanced the
# cursor past the hole: a transient Better Stack outage became permanent, silent, unaccounted
# loss. Executed then: offered 3, shipped 2, dropped_cum=0, cursor at i=3 — violating this very
# suite's T9 "dropped + shipped == offered" invariant with no test covering it.
assert "T11 a tick that left a row undelivered exits NON-ZERO (visible without SSH)" \
  "[[ '$CASE_RC' -ne 0 ]]"
assert "T11 a FAILED POST did NOT advance the cursor" \
  "[[ ! -s '$FAILSTATE/cursor' ]]"
assert "T11 the post-failure counter was written to the shipper's state file" \
  "grep -qE 'post_fail=[1-9]' '$FAILSTATE/state'"
assert "T11 a last-ok timestamp is tracked so the reporter can compute an age" \
  "grep -qE 'last_ok_epoch=[0-9]+' '$FAILSTATE/state'"
# POST ONCE: every row is replayable from the cursor, so a back-to-back second attempt against a
# briefly-500ing ingest buys nothing the five-minute gap does not buy better.
assert "T11 the row was POSTed exactly once (no back-to-back retry against a transient fault)" \
  "[[ \$(grep -c . '$STUB_CURLARGS') -eq 1 ]]"
# THE RESUME LEG — the payoff, and the half an exit-code assertion cannot prove: the undelivered
# row must still be REACHABLE on the next tick. Same state dir, sink now healthy, nothing skipped.
R11P="$TMP/posts.f3resume"; R11J="$TMP/jcalls.f3resume"; : > "$R11P"; : > "$R11J"
R11_RC=0
env PATH="$BIN:/usr/bin:/bin" \
    STUB_JOURNAL="$J1" STUB_POSTS="$R11P" STUB_CURLARGS="$TMP/curlargs.f3resume" STUB_JCALLS="$R11J" \
    BETTERSTACK_LOGS_TOKEN="synthetic-ingest-token-not-a-real-secret" \
    ZOT_LOG_SHIPPER_STATE_DIR="$FAILSTATE" \
    timeout 25 bash "$SHIPPER" >/dev/null 2>&1 || R11_RC=$?
assert "T11 the recovery tick exited cleanly once the sink recovered (rc=$R11_RC)" \
  "[[ '$R11_RC' -eq 0 ]]"
assert "T11 the previously-undelivered row WAS delivered on the next tick (no silent discard)" \
  "grep -q 'SOLEUR_ZOT_LOG shipper=' '$R11P'"
assert "T11 the recovery tick did NOT resume from a cursor (none was ever persisted past the hole)" \
  "grep -q 'after= ' '$R11J' || grep -qE 'after=$' '$R11J'"
assert "T11 the 5-min reporter carries the shipper's post-fail counter on its own working path" \
  "grep -qF 'log_shipper_post_fail=' '$CI'"
assert "T11 the 5-min reporter carries the shipper's last-ok age" \
  "grep -qF 'log_shipper_last_ok_age_s=' '$CI'"
assert "T11 the reporter's SOLEUR_ZOT_DISK LINE includes both shipper fields (not just defined nearby)" \
  "grep -E '^[[:space:]]*LINE=\"SOLEUR_ZOT_DISK' '$CI' | grep -qF 'log_shipper_post_fail='"

# --- T11b: THE HOLE (#7444 R17) -----------------------------------------------------------
# T11 named the F-3 defect - "the next successful line advances the cursor past the hole" - and
# could not instantiate it: one row in the fixture, and a GLOBAL fail switch. Measured, reverting
# the fix (break -> continue) left the whole suite green while row 1 was permanently lost.
# This fixture has an earlier failing row AND a later succeeding one, which is the only shape
# where the two implementations differ.
J_HOLE="$TMP/j_hole"
printf '%s\n' '{"level":"info","message":"FAILME first row"}' > "$J_HOLE"
printf '%s\n' '{"level":"info","message":"second row would ship"}' >> "$J_HOLE"
run_shipper "$J_HOLE" STUB_POST_FAIL_MATCH=FAILME
HOLESTATE="$LAST_STATE"
assert "T11b the tick stopped at the hole and did NOT ship the later row" \
  "[[ \$(grep -c 'SOLEUR_ZOT_LOG shipper=' '$STUB_POSTS') -eq 0 ]]"
assert "T11b the tick exited non-zero" "[[ '$CASE_RC' -ne 0 ]]"
assert "T11b NO cursor was persisted, so the next tick cannot skip the hole" \
  "[[ ! -s '$HOLESTATE/cursor' ]]"
# The payoff: with the sink healthy, BOTH rows arrive, in order, exactly once.
H2P="$TMP/posts.hole2"; : > "$H2P"
H2_RC=0
env PATH="$BIN:/usr/bin:/bin" \
    STUB_JOURNAL="$J_HOLE" STUB_POSTS="$H2P" STUB_CURLARGS="$TMP/curlargs.hole2" \
    STUB_JCALLS="$TMP/jcalls.hole2" \
    BETTERSTACK_LOGS_TOKEN="synthetic-ingest-token-not-a-real-secret" \
    ZOT_LOG_SHIPPER_STATE_DIR="$HOLESTATE" \
    timeout 25 bash "$SHIPPER" >/dev/null 2>&1 || H2_RC=$?
assert "T11b the recovery tick exited cleanly (rc=$H2_RC)" "[[ '$H2_RC' -eq 0 ]]"
assert "T11b BOTH rows were delivered on recovery — nothing was skipped" \
  "[[ \$(grep -c 'SOLEUR_ZOT_LOG shipper=' '$H2P') -eq 2 ]]"
assert "T11b the previously-failing row came FIRST (order preserved, no reordering)" \
  "head -1 '$H2P' | grep -qF 'FAILME first row'"

# --- T12: CRON CONTRACT — the shape that replaced the daemon (ADR-184 §4) ----------------
# This block used to assert a Restart=always unit's resource governance, on the reasoning that
# caps were "the only containment available" on a host with no in-place execution path. Review
# disproved the containment itself: IOWeight was a no-op without BFQ and on the wrong cgroup,
# RuntimeMaxUse RAISED the volatile ceiling it was meant to lower, the reserve it spent against
# was mis-derived, and every cap magnitude survived mutation. The CTO ruling replaced the daemon
# with a cron one-shot: the containment is now that there is no long-lived process to contain.
CRONBLK="$TMP/cron"
extract_block "/etc/cron.d/zot-log-shipper" "$CRONBLK"
assert "T12 the shipper's cron.d block was extracted" "[[ -s '$CRONBLK' ]]"

CRONLINE="$(grep -E '^[[:space:]]*[0-9*][0-9*/,-]* ' "$CRONBLK" | head -1)"
assert "T12 the cron block carries exactly one schedule line" \
  "[[ \$(grep -cE '^[[:space:]]*[0-9*][0-9*/,-]* ' '$CRONBLK') -eq 1 ]]"
assert "T12 the schedule line names the shipper" \
  "grep -qF '/usr/local/bin/zot-log-shipper.sh' '$CRONBLK'"
assert "T12 the cron line declares the root user (cron.d format requires it)" \
  "grep -qE '^[[:space:]]*[0-9*][0-9*/,-]*( +[0-9*][0-9*/,-]*){4} +root ' '$CRONBLK'"

# THE MINUTE OFFSET IS LOAD-BEARING, not cosmetic. zot-disk-heartbeat holds */5 (0,5,10…) and
# soleur-private-nic-guard holds 2-59/5 (2,7,12…). That guard's own comment records why: the host
# budgets ~1024 MB for "cron+doppler+sshd+OS" and must not have these `doppler run` invocations
# concurrently resident. A third at */5 would reintroduce the daemon's RAM risk through the
# SCHEDULE on a host with an OOM restart-loop history (#6288).
#
# Asserted as a real DISJOINTNESS check over the minutes each line actually fires, not as a string
# compare against a remembered literal — a sibling's schedule can change without this file knowing.
CRON_MINUTE="$(printf '%s' "$CRONLINE" | awk '{print $1}')"
assert "T12 the shipper's minute field parses as an offset stride (not a bare */5)" \
  "[[ '$CRON_MINUTE' =~ ^[0-9]+-59/5$ ]]"
expand_minutes() {
  printf '%s' "$1" | awk '
    /^\*\/[0-9]+$/      { step=substr($0,3)+0; for (m=0; m<60; m+=step) print m; next }
    /^[0-9]+-59\/[0-9]+$/ { split($0, a, "[-/]"); for (m=a[1]+0; m<60; m+=a[3]+0) print m; next }
    /^[0-9]+$/          { print $0+0; next }
  ' | sort -n | uniq
}
SIB_MINUTES="$TMP/sibmins"; : > "$SIB_MINUTES"
while IFS= read -r sched; do
  expand_minutes "$sched" >> "$SIB_MINUTES"
done < <(grep -hE '^[[:space:]]*[0-9*][0-9*/,-]*( +[0-9*][0-9*/,-]*){4} +root ' "$CI" \
         | grep -vF 'zot-log-shipper.sh' | awk '{print $1}')
MINE_MINUTES="$TMP/minemins"
expand_minutes "$CRON_MINUTE" > "$MINE_MINUTES"
COLLISIONS="$(comm -12 <(sort -n "$SIB_MINUTES" | uniq) <(sort -n "$MINE_MINUTES" | uniq) | tr '\n' ' ')"
assert "T12 at least one sibling cron line was found (otherwise the disjointness check is vacuous)" \
  "[[ -s '$SIB_MINUTES' ]]"
assert "T12 the shipper's minutes are DISJOINT from every sibling doppler-run cron (collisions: '$COLLISIONS')" \
  "[[ -z \"\$(printf '%s' '$COLLISIONS' | tr -d ' ')\" ]]"

# EVERY ABSOLUTE PATH THE CRON LINE EXECUTES MUST BE INSTALLED BY THIS SAME TEMPLATE. This
# assertion exists because its absence shipped a dead unit: the daemon's ExecStart named
# /usr/bin/doppler, which this template never creates (it installs to /usr/local/bin and, unlike
# the inngest template, writes no symlink). systemd-analyze verify did not catch it — it DOES
# reject a missing ExecStart binary, but resolved against the RUNNER's filesystem, which has
# /usr/bin/doppler and lacks /usr/local/bin/doppler: the exact inverse of production. The lesson
# is retargeted here rather than deleted with the unit.
while IFS= read -r _abs; do
  [[ -n "$_abs" ]] || continue
  case "$_abs" in
    */zot-log-shipper.sh) continue ;;              # written by this template, asserted above
    /run/lock/*)          continue ;;              # a lock PATH argument, not a binary
  esac
  if [[ "$_abs" == *doppler* ]]; then
    assert "T12 the cron line's doppler path is the one THIS template installs (tar -C /usr/local/bin)" \
      "grep -qE 'tar[^\n]*-C[[:space:]]+/usr/local/bin[[:space:]]+doppler' '$CI' || grep -qE 'ln -sf[^\n]*doppler' '$CI'"
  else
    assert "T12 cron-executed binary '$_abs' is installed or symlinked by this same template" \
      "[[ -x '$_abs' ]] || grep -qF '$_abs' '$CI'"
  fi
done < <(printf '%s\n' "$CRONLINE" | grep -oE '/[A-Za-z0-9/._-]+' | sort -u)

# The daemon named an absolute /usr/bin/doppler; the cron line resolves doppler through PATH, as
# both siblings on this host already do.
# PATH, timeout and the logger pipe are each load-bearing and each was absent (#7444 R10/R11).
assert "T12 the cron block declares a PATH covering /usr/local/bin (where doppler actually is)" \
  "grep -qE '^[[:space:]]*PATH=.*(/usr/local/bin)' '$CRONBLK'"
# Scoped to $CRONLINE, the executable schedule line — NOT $CRONBLK. The rationale comment above
# these directives contains the literal "timeout 240", so a block-wide grep matched the comment
# as well as the code and returned two values. Exactly the class this suite pins elsewhere.
assert "T12 the tick is time-bounded below the cadence (no cgroup bound exists under cron)" \
  "grep -qE 'timeout[[:space:]]+[0-9]+[[:space:]]' <<<\"\$CRONLINE\""
TMO="$(printf '%s' "$CRONLINE" | grep -oE 'timeout[[:space:]]+[0-9]+' | grep -oE '[0-9]+$' || true)"
assert "T12 the timeout (${TMO}s) is strictly below the 300s cadence, so ticks cannot overlap" \
  "[[ -n '$TMO' && '$TMO' -lt 300 ]]"
assert "T12 the tick's stderr reaches journald via logger (cron has no MTA on this host)" \
  "grep -qE '\\|[[:space:]]*logger[[:space:]]+-t[[:space:]]+zot-log-shipper' <<<\"\$CRONLINE\""
assert "T12 the cron line does NOT name /usr/bin/doppler (this template creates no such symlink)" \
  "! grep -qF '/usr/bin/doppler' '$CRONBLK'"
assert "T12 flock's absolute path exists on this platform (util-linux ships it)" \
  "command -v flock >/dev/null 2>&1"

# THE DAEMON IS GONE — asserted as an absence, because a leftover unit would be enabled by a
# leftover runcmd and would race the cron line for the same lock.
assert "T12 no zot-log-shipper systemd unit is written any more" \
  "! grep -qE '^[[:space:]]*-[[:space:]]*path:[[:space:]]*/etc/systemd/system/zot-log-shipper\.service' '$CI'"
assert "T12 no runcmd arms a zot-log-shipper unit" \
  "! grep -qE 'systemctl[^\n]*(enable|start|restart)[^\n]*zot-log-shipper' '$CI'"
assert "T12 the template declares no Restart= directive for the shipper (the host keeps zero always-on units)" \
  "! grep -qE '^[[:space:]]*Restart=always' '$CI'"

# SECRET SCOPE (#7444 F-13/F-14). A daemon held the WHOLE soleur-registry/prd set — including
# REGISTRY_LUKS_KEY — in a permanently-resident process env, and its StateDirectory-rooted
# DOPPLER_CONFIG_DIR made this the first persistent doppler fallback cache on the estate. A tick's
# env lives seconds, but the scope is still narrowed explicitly rather than left to inheritance.
# Both flags verified against the installed CLI (doppler v3.75.3 `run --help`).
assert "T12 the cron line narrows the injected secret set to the one secret it needs" \
  "grep -qE 'only-secrets[[:space:]]+BETTERSTACK_LOGS_TOKEN' '$CRONBLK'"
assert "T12 the cron line declines the on-disk doppler fallback cache" \
  "grep -qF -- '--no-fallback' '$CRONBLK'"
assert "T12 the cron line does not resurrect a DOPPLER_CONFIG_DIR under a state directory" \
  "! grep -qF 'DOPPLER_CONFIG_DIR' '$CRONBLK'"

# --- T13: JOURNALD sizing — set UNCONDITIONALLY so the literals are assertable -----------
# The template sets no Storage=, no SystemMaxUse= and no /var/log/journal, so behaviour is the
# base-image default: Ubuntu ships Storage=auto with no /var/log/journal present, which means
# VOLATILE — the journal lives in /run/log/journal, a tmpfs bounded by RuntimeMaxUse ~10% of /run.
# On a 3,814 MB host where zot is capped at 3,072 MB and the documented reserve is 1,024 MB, that
# is RAM pressure on the host whose OOM history is why the cap exists.
JDROP="$TMP/jdrop"
extract_block "$JOURNALD_DROPIN" "$JDROP"
assert "T13 the journald drop-in block was extracted" "[[ -s '$JDROP' ]]"
assert "T13 journald Storage=persistent (moves the buffer off the /run tmpfs)" \
  "grep -qE '^[[:space:]]*Storage=persistent[[:space:]]*$' '$JDROP'"
# MAGNITUDE, not shape (#7444 R15). A `[0-9]+[KMG]?` regex accepts 512M -> 1K and 512M -> 4G
# alike, so the literal every sizing argument in this file rests on was unpinned. Bound it.
SMU="$(grep -oE '^[[:space:]]*SystemMaxUse=[0-9]+[KMG]?' "$JDROP" | grep -oE '[0-9]+[KMG]?$' || true)"
assert "T13 journald SystemMaxUse is exactly 512M (the retention arithmetic depends on it)" \
  "[[ '$SMU' == '512M' ]]"
# RuntimeMaxUse is ABSENT ON PURPOSE. journald's default is 10% of /run = ~38MB on this 3,814MB
# host, so the previous RuntimeMaxUse=64M RAISED the volatile ceiling it was documented as
# lowering — ADR-184 cites that defect as an argument for deleting the daemon while the template
# shipped the identical line. Under Storage=persistent the volatile journal is only a fallback,
# so the correct value is no line at all.
assert "T13 journald sets NO RuntimeMaxUse (64M raised the ~38M default it claimed to lower)" \
  "! grep -qE '^[[:space:]]*RuntimeMaxUse=' '$JDROP'"

# --- T14: BOOT MARKER — in-surface 'was this ever delivered?' signal ---------------------
# Absent boot marker + unchanged SOLEUR_ZOT_DISK boot_id = not delivered. This is what lets the
# probe discriminate "not delivered" from "delivered and dead" instead of collapsing both.
assert "T14 a one-shot boot marker is fired from runcmd (mirrors both existing reporters)" \
  "grep -qF 'SOLEUR_ZOT_LOG_BOOT' '$CI'"
assert "T14 the boot marker carries boot_id (the discriminator the probe compares against)" \
  "grep 'SOLEUR_ZOT_LOG_BOOT' '$CI' | grep -qF 'boot_id='"

# --- T15: the stale liveness-cadence comment is corrected -------------------------------
# The row-volume floor (~1,440/day) is derived from the 60s timer; a comment claiming 5 min makes
# the floor look 5x smaller and would justify a wrong cap.
assert "T15 the timer really is 60s (the authority for the ~1,440/day floor)" \
  "grep -qE '^[[:space:]]*OnUnitActiveSec=60s[[:space:]]*$' '$CI'"
assert "T15 no comment still claims the liveness probe GETs /v2/ 'every 5 min'" \
  "! grep -qE 'liveness.*every 5 min|/v2/ every 5 min' '$CI'"

# --- T16: cap-exempt ceiling + parsed-field matching (#7444 F-5) -------------------------
# Cap-exempt classes previously faced NO ceiling at all: is_cap_exempt returned before WIN_COUNT
# was consulted. PatchBlobUpload fires per blob-upload CHUNK, so exempt volume is proportional to
# push traffic, and the measured crash-loop case (6,912 restarts/day x ~10 repos x ~2 gc lines)
# is ~138,000 rows/day against a 5,000/day budget — 28x, in the exact scenario the exemption was
# sized against. Source 2457081 is shared with the web hosts, the Inngest node and this host's own
# disk alarms, so the observer can starve the observed.
J_EXEMPT_FLOOD="$TMP/j_exempt_flood"
: > "$J_EXEMPT_FLOOD"
for _ in $(seq 1 40); do
  printf '%s\n' '{"level":"info","message":"executing gc","component":"gc","caller":"zotregistry.dev/zot/v2/pkg/storage/gc.go:1"}' >> "$J_EXEMPT_FLOOD"
done
run_shipper "$J_EXEMPT_FLOOD" ZOT_LOG_SHIPPER_CAP_EXEMPT_PER_INTERVAL=10
EXEMPT_SHIPPED=$(grep -c 'SOLEUR_ZOT_LOG shipper=' "$STUB_POSTS" || true)
assert "T16 the exempt ceiling BOUNDS exempt rows (shipped $EXEMPT_SHIPPED of 40 offered, cap 10)" \
  "[[ '$EXEMPT_SHIPPED' -eq 10 ]]"
assert "T16 the overflow is ACCOUNTED as a drop row, not silently discarded" \
  "grep -q 'SOLEUR_ZOT_LOG_DROPPED' '$STUB_POSTS'"
assert "T16 the exempt overflow carries its OWN reason, not the ordinary rate_cap reason" \
  "grep -q 'reason=exempt_cap' '$STUB_POSTS'"
EXEMPT_DROP_N=$(grep -oE 'SOLEUR_ZOT_LOG_DROPPED n=[0-9]+[^\"]*reason=exempt_cap' "$STUB_POSTS" | grep -oE 'n=[0-9]+' | head -1 | cut -d= -f2 || true)
assert "T16 dropped n + shipped == offered for the exempt class (n=$EXEMPT_DROP_N + $EXEMPT_SHIPPED == 40)" \
  "[[ -n '$EXEMPT_DROP_N' && \$(( EXEMPT_DROP_N + EXEMPT_SHIPPED )) -eq 40 ]]"

# THE BYPASS. is_cap_exempt matched the WHOLE LINE, so any private-net client sending
# `User-Agent: executing gc` made EVERY one of its request lines cap-exempt — an
# externally-controlled hole in the rate cap on a shared 5,000/day source. Matching zerolog's
# PARSED `message` field closes it: these rows carry message "HTTP API", not "executing gc".
J_BYPASS="$TMP/j_bypass"
: > "$J_BYPASS"
for _ in $(seq 1 40); do
  printf '%s\n' '{"level":"info","message":"HTTP API","headers":{"User-Agent":["executing gc"]},"caller":"zotregistry.dev/zot/v2/pkg/api/session.go:92"}' >> "$J_BYPASS"
done
run_shipper "$J_BYPASS" ZOT_LOG_SHIPPER_CAP_PER_INTERVAL=5
BYPASS_SHIPPED=$(grep -c 'SOLEUR_ZOT_LOG shipper=' "$STUB_POSTS" || true)
assert "T16 a 'executing gc' string in a HEADER does not buy cap exemption (shipped $BYPASS_SHIPPED, cap 5)" \
  "[[ '$BYPASS_SHIPPED' -eq 5 ]]"
assert "T16 those capped rows are accounted under the ORDINARY rate cap" \
  "grep -q 'reason=rate_cap' '$STUB_POSTS'"

# --- T17: cursor invalidation replays a BOUNDED window (#7444 F-9) -----------------------
# On invalidation the shipper cleared CURSOR and re-read with no bound. journalctl's default with
# no --lines/--follow is ALL retained entries, and this same change raises SystemMaxUse to 512M —
# so the recovery path re-read the entire retained journal. That is the runaway-volume mode the
# design cites as its reason for rejecting --cursor-file, re-entered by a different door, and the
# block's own comment claimed it "restarts from the tail" while the code did the opposite.
BADSTATE2="$TMP/badstate2"; mkdir -p "$BADSTATE2"; printf 'INVALID-CURSOR' > "$BADSTATE2/cursor"
BJC="$TMP/jcalls.bounded"; BPOSTS="$TMP/posts.bounded"; : > "$BJC"; : > "$BPOSTS"
BND_RC=0
env PATH="$BIN:/usr/bin:/bin" STUB_JOURNAL="$J1" STUB_POSTS="$BPOSTS" \
    STUB_CURLARGS="$TMP/curlargs.bounded" STUB_JCALLS="$BJC" \
    BETTERSTACK_LOGS_TOKEN="synthetic-ingest-token-not-a-real-secret" \
    ZOT_LOG_SHIPPER_STATE_DIR="$BADSTATE2" \
    timeout 25 bash "$SHIPPER" >/dev/null 2>&1 || BND_RC=$?
assert "T17 the invalidation run exited cleanly (rc=$BND_RC) — otherwise the asserts below are vacuous" \
  "[[ '$BND_RC' -eq 0 ]]"
assert "T17 the RECOVERY read is bounded by --since (not an unbounded whole-journal replay)" \
  "grep -vE 'since=[[:space:]]' '$BJC' | grep -qE 'since=-?[0-9]+[smhd]'"
assert "T17 the recovery still shipped (the bound must not silence the channel)" \
  "grep -q 'SOLEUR_ZOT_LOG shipper=' '$BPOSTS'"
# And the bound must NOT apply to a genuine cold start: a fresh host's journal is small and the
# boot backlog is exactly what the cursor persistence exists to preserve (asserted in T4).
assert "T17 the bound is keyed on INVALIDATION, not on cursor-emptiness (cold start stays unbounded)" \
  "grep -qE 'CURSOR_WAS_INVALIDATED' '$SHIPPER'"

# --- T18: a missing jq is a LOUD failure, never a silent zero (#7444 F-11) ---------------
# jq is a hard per-line dependency and lives in `packages:`, whose own comment records that the
# stage is NON-FATAL. Measured with jq off PATH before this guard: 0 of 2 rows delivered, rc=0, no
# stderr, state all zeros, no drop rows, unit active forever — 100% silent loss, which the
# reporter then rendered as post_fail=unknown, so the probe reported the INVERTED root cause.
# The PATH must contain everything the shipper needs EXCEPT jq — a PATH so narrow that `mkdir`
# is missing would abort before the guard and the case would pass for the wrong reason.
NOJQ_BIN="$TMP/nojq"; mkdir -p "$NOJQ_BIN"
for _t in journalctl curl hostname; do cp "$BIN/$_t" "$NOJQ_BIN/$_t"; done
while IFS= read -r _real; do
  [[ -n "$_real" ]] || continue
  ln -sf "$_real" "$NOJQ_BIN/$(basename "$_real")" 2>/dev/null || true
done < <(for _b in bash mkdir cat mv rm date sed tr sleep timeout; do command -v "$_b" 2>/dev/null; done)
assert "T18 the no-jq PATH really lacks jq (otherwise this case proves nothing)" \
  "[[ -z \"\$(PATH='$NOJQ_BIN' command -v jq 2>/dev/null)\" ]]"
assert "T18 the no-jq PATH still has mkdir (so the shipper reaches its jq guard, not an earlier abort)" \
  "[[ -n \"\$(PATH='$NOJQ_BIN' command -v mkdir 2>/dev/null)\" ]]"
NOJQ_STATE="$TMP/nojqstate"; mkdir -p "$NOJQ_STATE"
NOJQ_POSTS="$TMP/posts.nojq"; : > "$NOJQ_POSTS"
NOJQ_RC=0
env PATH="$NOJQ_BIN" \
    STUB_JOURNAL="$J1" STUB_POSTS="$NOJQ_POSTS" STUB_CURLARGS="$TMP/curlargs.nojq" \
    STUB_JCALLS="$TMP/jcalls.nojq" \
    BETTERSTACK_LOGS_TOKEN="synthetic-ingest-token-not-a-real-secret" \
    ZOT_LOG_SHIPPER_STATE_DIR="$NOJQ_STATE" \
    timeout 25 bash "$SHIPPER" >"$TMP/out.nojq" 2>&1 || NOJQ_RC=$?
# Pinned to the GUARD's own exit code, not merely "non-zero": a PATH so narrow that bash itself
# was unreachable also exits non-zero (127), which passed this case while never reaching the
# guard at all. Measured while writing it.
assert "T18 a missing jq exits 1 from the guard itself (rc=$NOJQ_RC; 127 would mean bash was unreachable)" \
  "[[ '$NOJQ_RC' -eq 1 ]]"
assert "T18 it says WHY on stderr rather than dying mutely" \
  "grep -qi 'jq' '$TMP/out.nojq'"
assert "T18 it ships nothing rather than shipping empty rows" \
  "[[ \$(grep -c . '$NOJQ_POSTS') -eq 0 ]]"
# `.*` NOT `[^\n]*`: in a POSIX ERE `[^\n]` is a bracket expression excluding backslash and the
# LETTER n, so it cannot cross "install" — the assertion would be unmatchable, and as a NEGATIVE
# it would have passed vacuously forever.
assert "T18 the template also re-ensures jq in runcmd (packages: alone is non-fatal)" \
  "grep -qE 'dpkg -s jq.*apt-get install -y jq' '$CI'"


# --- T19: GUARD 2 (#7555) — the paired upload-failure row survives the cap ----------------
# zot reports a failed blob upload as TWO rows: the `PatchBlobUpload` error line (cap-exempt
# since #7440) and an ordinary HTTP-API row carrying statusCode/latency/Content-Length. Only
# the PAIRING carries the numbers that separate a DEADLINE from an origin fault, and only the
# first half was surviving. Measured in the 2026-08-13 failure tick: dropped_cum=5841 vs
# shipped_cum=5151, so the deciding evidence survived by luck of its class.
J_PAIR="$TMP/j_pair"
: > "$J_PAIR"
for i in $(seq 1 40); do
  printf '%s\n' "{\"level\":\"info\",\"message\":\"HTTP API\",\"path\":\"/v2/ordinary-$i\",\"statusCode\":200,\"caller\":\"zotregistry.dev/zot/v2/pkg/api/session.go:92\"}" >> "$J_PAIR"
done
# The pairing's HTTP-API half. `pairA` is the discriminating substring.
printf '%s\n' '{"level":"info","message":"HTTP API","module":"http","method":"PATCH","path":"/v2/jikig-ai/soleur-web-platform/blobs/uploads/pairA","statusCode":500,"latency":"1m0s","bodySize":0,"caller":"zotregistry.dev/zot/v2/pkg/api/session.go:92","goroutine":156}' >> "$J_PAIR"
run_shipper "$J_PAIR" ZOT_LOG_SHIPPER_CAP_PER_INTERVAL=5
assert "T19 the ordinary cap still bit under the flood (otherwise this case proves nothing)" \
  "[[ \$(grep -c 'ordinary-' '$STUB_POSTS') -lt 40 ]]"
assert "T19 the HTTP-API half of an upload-failure pairing survived the cap" \
  "grep -qF 'pairA' '$STUB_POSTS'"

# Row 4 — 502/503/504 are as much a cut upload as 500. A predicate pinned to 500 alone is blind
# to exactly the proxy-side shapes, and no 500-only fixture can see that.
J_5XX="$TMP/j_5xx"
: > "$J_5XX"
for i in $(seq 1 40); do
  printf '%s\n' "{\"level\":\"info\",\"message\":\"HTTP API\",\"path\":\"/v2/ordinary-$i\",\"statusCode\":200,\"caller\":\"c\"}" >> "$J_5XX"
done
for code in 502 503 504; do
  printf '%s\n' "{\"level\":\"info\",\"message\":\"HTTP API\",\"method\":\"PATCH\",\"path\":\"/v2/x/blobs/uploads/code$code\",\"statusCode\":$code,\"latency\":\"1m0s\",\"caller\":\"c\"}" >> "$J_5XX"
done
run_shipper "$J_5XX" ZOT_LOG_SHIPPER_CAP_PER_INTERVAL=5
for code in 502 503 504; do
  assert "T19 a $code upload-failure pairing is exempt too (not just 500)" \
    "grep -qF 'code$code' '$STUB_POSTS'"
done

# Row 7 — admitting the pairing must NOT starve the crash class out of the shared exempt lane.
# 17 ordinary 5xx rows on a NON-upload path ahead of a panic trace: the panic must still ship.
# This is the #7444 R12 priority inversion, one layer down, and it is what bounds the predicate
# to the `/blobs/uploads/` pairing rather than to 5xx generally.
J_STARVE="$TMP/j_starve"
: > "$J_STARVE"
for i in $(seq 1 17); do
  printf '%s\n' "{\"level\":\"error\",\"message\":\"HTTP API\",\"path\":\"/v2/health-probe-$i\",\"statusCode\":503,\"caller\":\"c\"}" >> "$J_STARVE"
done
printf '%s\n' 'panic: runtime error: invalid memory address or nil pointer dereference' >> "$J_STARVE"
run_shipper "$J_STARVE" ZOT_LOG_SHIPPER_CAP_PER_INTERVAL=1
assert "T19 a panic trace still ships behind 17 ordinary 5xx rows (exempt lane not starved)" \
  "grep -qF 'panic: runtime error' '$STUB_POSTS'"
assert "T19 non-upload 5xx rows are NOT exempt (they are ordinary; a broad 5xx arm would admit them)" \
  "[[ \$(grep -c 'health-probe-' '$STUB_POSTS') -lt 17 ]]"

# Row 6 — SECOND MEMBER. Exempting the first pairing in a tick and dropping the second is the
# defect a single-member fixture cannot see.
J_TWO="$TMP/j_two"
: > "$J_TWO"
for i in $(seq 1 40); do
  printf '%s\n' "{\"level\":\"info\",\"message\":\"HTTP API\",\"path\":\"/v2/ordinary-$i\",\"statusCode\":200,\"caller\":\"c\"}" >> "$J_TWO"
done
printf '%s\n' '{"level":"info","message":"HTTP API","method":"PATCH","path":"/v2/x/blobs/uploads/firstMember","statusCode":500,"latency":"1m0s","caller":"c"}' >> "$J_TWO"
printf '%s\n' '{"level":"info","message":"HTTP API","method":"PATCH","path":"/v2/x/blobs/uploads/secondMember","statusCode":500,"latency":"1m0s","caller":"c"}' >> "$J_TWO"
run_shipper "$J_TWO" ZOT_LOG_SHIPPER_CAP_PER_INTERVAL=5
assert "T19 the FIRST pairing in a tick survived" "grep -qF 'firstMember' '$STUB_POSTS'"
assert "T19 the SECOND pairing in a tick survived too (second-member row)" \
  "grep -qF 'secondMember' '$STUB_POSTS'"

# H1 — MUST-PASS non-canonical. A synthesized pairing with a different path suffix and a
# different goroutine than the canonical fixture must be exempt: the guard enforces the
# `/blobs/uploads/` + 5xx property, not the fixture's literal bytes.
J_H1="$TMP/j_h1"
: > "$J_H1"
for i in $(seq 1 40); do
  printf '%s\n' "{\"level\":\"info\",\"message\":\"HTTP API\",\"path\":\"/v2/ordinary-$i\",\"statusCode\":200,\"caller\":\"c\"}" >> "$J_H1"
done
printf '%s\n' '{"level":"info","message":"HTTP API","method":"PATCH","path":"/v2/some-other-org/other-image/blobs/uploads/9f3c-NONCANON","statusCode":503,"latency":"55s","bodySize":17,"caller":"zotregistry.dev/zot/v2/pkg/api/other.go:7","goroutine":99999}' >> "$J_H1"
run_shipper "$J_H1" ZOT_LOG_SHIPPER_CAP_PER_INTERVAL=5
assert "T19 H1 a non-canonical pairing (different path, goroutine, code) is still exempt" \
  "grep -qF 'NONCANON' '$STUB_POSTS'"

# The tick record's ARITY. Row 1's fail-open is a widened JQ_TICK against an unwidened
# `read -r`: the extra fields fold into zmsg, prefix matching still returns 0, and the suite
# stays green over a corrupted record. Pin the two together at the source so they cannot drift
# apart silently -- the count is derived from the field list, not written down twice.
JQ_FIELDS=$(grep -m1 "^      JQ_TICK=" "$CI" | grep -o '| s)' | wc -l)
READ_VARS=$(grep -m1 "while IFS=\$'\\\\t' read -r " "$CI" | sed "s/.*read -r //; s/;.*//" | wc -w)
assert "T19 JQ_TICK emits >= 5 sentinelled fields (got $JQ_FIELDS)" "[[ '$JQ_FIELDS' -ge 5 ]]"
assert "T19 the read -r arity MATCHES the JQ_TICK field count ($READ_VARS vars vs $JQ_FIELDS fields)" \
  "[[ '$READ_VARS' -eq '$JQ_FIELDS' ]]"
# Every optional field must be sentinelled: with IFS=tab (an IFS-WHITESPACE char) one empty
# field shifts all later fields one position left, so an unsentinelled record corrupts silently.
assert "T19 JQ_TICK sentinels empty fields (tab is IFS-whitespace; empties would shift fields left)" \
  "grep -m1 '^      JQ_TICK=' '$CI' | grep -qF 'then \"-\" else'"

# T19 — the F-5 bypass must stay CLOSED while plaintext crash evidence becomes exempt. These two
# assertions are the pair: without the second, the fix above is indistinguishable from reverting
# to a whole-line match. An HTTP-API row whose User-Agent contains an exempt-class literal parses
# as JSON, so its zmsg is "HTTP API" and it never reaches the plaintext fallback.
J_BYPASS="$TMP/j_bypass"
: > "$J_BYPASS"
for i in $(seq 1 40); do
  printf '%s\n' "{\"level\":\"info\",\"message\":\"HTTP API\",\"path\":\"/v2/bypass-$i\",\"statusCode\":200,\"headers\":{\"User-Agent\":[\"executing gc\"]},\"caller\":\"c\"}" >> "$J_BYPASS"
done
run_shipper "$J_BYPASS" ZOT_LOG_SHIPPER_CAP_PER_INTERVAL=5
assert "T19 F-5 bypass stays closed: a User-Agent carrying 'executing gc' does NOT make rows exempt" \
  "[[ \$(grep -c 'bypass-' '$STUB_POSTS') -le 6 ]]"
