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
UNIT_PATH="/etc/systemd/system/zot-log-shipper.service"
JOURNALD_DROPIN="/etc/systemd/journald.conf.d/10-zot-log-shipper.conf"
TEST_INGEST_URL="https://s0000000.eu-fsn-3.example-ingest.invalid/"
TEST_HOST="soleur-registry"

PASS=0
FAIL=0
assert() {
  local desc="$1" cond="$2"
  if eval "$cond"; then PASS=$((PASS + 1)); echo "  PASS: $desc"
  else FAIL=$((FAIL + 1)); echo "  FAIL: $desc"; echo "        condition: $cond"; fi
}

TMP="$(mktemp -d)" || { echo "FATAL: mktemp -d failed (TMPDIR=$TMPDIR)" >&2; exit 2; }
trap 'rm -rf "$TMP"' EXIT

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
have_match=0; have_json=0; have_notail=0; after_cursor=""; prev=""
for a in "$@"; do
  case "$a" in
    CONTAINER_NAME=zot) have_match=1 ;;
    --output=json)      have_json=1 ;;
    --no-tail)          have_notail=1 ;;
  esac
  [[ "$prev" == "--after-cursor" ]] && after_cursor="$a"
  prev="$a"
done
printf 'match=%s json=%s notail=%s after=%s\n' "$have_match" "$have_json" "$have_notail" "$after_cursor" >> "$STUB_JCALLS"
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
# Model --follow faithfully: real journalctl BLOCKS after draining the backlog rather than
# exiting. Without this the SIGKILL case below could not exist — the shipper would exit cleanly
# on its own and the test would prove clean-exit durability while claiming SIGKILL durability.
for a in "$@"; do
  if [[ "$a" == "--follow" ]]; then sleep 300; fi
done
exit 0
EOS
chmod +x "$BIN/journalctl"

# curl stub: records the full POSTed body so the envelope, the redaction and the drop rows are all
# observable. Honours -m (bounded egress) and models a POST failure via $STUB_POST_FAIL.
cat > "$BIN/curl" <<'EOS'
#!/usr/bin/env bash
body=""; has_m=0; url=""; prev=""
for a in "$@"; do
  case "$a" in
    http*://*) url="$a" ;;
  esac
  [[ "$prev" == "--data-raw" ]] && body="$a"
  [[ "$prev" == "-m" || "$prev" == "--max-time" ]] && has_m=1
  prev="$a"
done
printf 'm=%s url=%s\n' "$has_m" "$url" >> "$STUB_CURLARGS"
[[ "$has_m" == 1 ]] || { echo "curl stub: unbounded call (no -m/--max-time)" >&2; exit 64; }
if [[ "${STUB_POST_FAIL:-0}" == 1 ]]; then exit 22; fi
printf '%s\n' "$body" >> "$STUB_POSTS"
exit 0
EOS
chmod +x "$BIN/curl"

cat > "$BIN/hostname" <<EOS
#!/usr/bin/env bash
printf '%s\n' "$TEST_HOST"
EOS
chmod +x "$BIN/hostname"

# Run the shipper once over a fixture journal. Bounded so a runaway --follow cannot wedge CI.
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
      ZOT_LOG_SHIPPER_STATE_DIR="$state" ZOT_LOG_SHIPPER_ONESHOT=1 \
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
assert "T4 every egress call was bounded (-m/--max-time present)" \
  "[[ \$(grep -c 'm=1' '$STUB_CURLARGS') -eq \$(grep -c . '$STUB_CURLARGS') ]]"
assert "T4 the journalctl query passed --no-tail (cold start must not discard the boot backlog)" \
  "grep -q 'notail=1' '$STUB_JCALLS'"
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
assert "T6 redaction: an unrelated header value is preserved (the rule is scoped, not a blanket wipe)" \
  "grep -qF 'curl/8.5.0' '$STUB_POSTS'"

# --- T7: FEEDBACK-LOOP guard ------------------------------------------------------------
# Measured: a `zot-log-shipper`-tagged journal entry carries NO CONTAINER_NAME, and
# `journalctl CONTAINER_NAME=zot` excludes it (0 hits). Asserted on BOTH sides of the filter.
assert "T7 the unit sets SyslogIdentifier=zot-log-shipper (so its own lines are tagged, not container-named)" \
  "grep -qE '^[[:space:]]*SyslogIdentifier=zot-log-shipper[[:space:]]*$' '$CI'"
assert "T7 the shipper matches CONTAINER_NAME (a field its own journald lines cannot carry)" \
  "grep -qE 'journalctl[^|]*CONTAINER_NAME=zot' '$SHIPPER'"
assert "T7 the shipper does not match on its own SyslogIdentifier (that would be a feedback loop)" \
  "! grep -qE 'journalctl[^|]*(-t|--identifier)[[:space:]=]*zot-log-shipper' '$SHIPPER'"

# --- T8: SINGLETON — flock -n, mirroring both cron siblings on this host ----------------
assert "T8 the unit's ExecStart is flock -n guarded (a double-run would double-ship)" \
  "grep -qE 'ExecStart=.*flock[[:space:]]+-n[[:space:]]' '$CI'"

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
    ZOT_LOG_SHIPPER_STATE_DIR="$SEEDED" ZOT_LOG_SHIPPER_ONESHOT=1 \
    timeout 25 bash "$SHIPPER" >/dev/null 2>&1 || RESUME_RC=$?
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
    ZOT_LOG_SHIPPER_STATE_DIR="$BADSTATE" ZOT_LOG_SHIPPER_ONESHOT=1 \
    timeout 25 bash "$SHIPPER" >/dev/null 2>&1 || BAD_RC=$?
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
    ZOT_LOG_SHIPPER_STATE_DIR="$KSTATE" ZOT_LOG_SHIPPER_ONESHOT=0 \
    bash "$SHIPPER" >/dev/null 2>&1 &
SHIP_PID=$!
# Wait for the cursor to land (i.e. a POST succeeded), bounded so a hang cannot wedge CI.
for _ in $(seq 1 60); do [[ -s "$KSTATE/cursor" ]] && break; sleep 0.25; done
CURSOR_BEFORE="$(cat "$KSTATE/cursor" 2>/dev/null || true)"
assert "T10b the shipper was still ALIVE when killed (a clean exit would void this case)" \
  "kill -0 '$SHIP_PID' 2>/dev/null"
assert "T10b it ran with --follow (so it was blocked on the journal, as in production)" \
  "grep -q 'notail=1' '$KJC'"
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
    ZOT_LOG_SHIPPER_STATE_DIR="$KSTATE" ZOT_LOG_SHIPPER_ONESHOT=1 \
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
assert "T11 a POST failure did not wedge the shipper (it exits for the next tick)" \
  "[[ '$CASE_RC' -eq 0 ]]"
assert "T11 the post-failure counter was written to the shipper's state file" \
  "grep -qE 'post_fail=[1-9]' '$LAST_STATE/state'"
assert "T11 a last-ok timestamp is tracked so the reporter can compute an age" \
  "grep -qE 'last_ok_epoch=[0-9]+' '$LAST_STATE/state'"
assert "T11 the POST was retried before giving up (retry once, then breadcrumb)" \
  "[[ \$(grep -c . '$STUB_CURLARGS') -ge 2 ]]"
assert "T11 the 5-min reporter carries the shipper's post-fail counter on its own working path" \
  "grep -qF 'log_shipper_post_fail=' '$CI'"
assert "T11 the 5-min reporter carries the shipper's last-ok age" \
  "grep -qF 'log_shipper_last_ok_age_s=' '$CI'"
assert "T11 the reporter's SOLEUR_ZOT_DISK LINE includes both shipper fields (not just defined nearby)" \
  "grep -E '^[[:space:]]*LINE=\"SOLEUR_ZOT_DISK' '$CI' | grep -qF 'log_shipper_post_fail='"

# --- T12: UNIT HARDENING — resource governance is the only containment available ---------
# This is the registry host's FIRST Restart=always unit (every existing unit is Type=oneshot). With
# no in-place execution path there is no kill switch, so the unit must be incapable of needing one.
UNITBLK="$TMP/unit"
extract_block "$UNIT_PATH" "$UNITBLK"
assert "T12 the systemd unit block was extracted" "[[ -s '$UNITBLK' ]]"
for kv in 'MemoryMax=' 'CPUQuota=' 'IOWeight=' 'RestartSec=' 'Restart=always'; do
  assert "T12 unit pins $kv" "grep -qE '^[[:space:]]*${kv}' '$UNITBLK'"
done
# An EXISTENCE grep cannot see a MALFORMED value, and this one has a template trap behind it:
# Terraform's directive escape is `%%{`, so a bare `%%` is NOT an escape and `CPUQuota=20%%` would
# render literally as `20%%` — which systemd rejects, on the host with no in-place fix path. Assert
# the VALUE SHAPE, and assert no doubled percent survives anywhere in the rendered unit.
assert "T12 CPUQuota is a well-formed single-percent value (a bare %% is not a TF escape and systemd rejects it)" \
  "grep -qE '^[[:space:]]*CPUQuota=[0-9]+%[[:space:]]*$' '$UNITBLK'"
assert "T12 MemoryMax is a well-formed byte value" \
  "grep -qE '^[[:space:]]*MemoryMax=[0-9]+[KMG]?[[:space:]]*$' '$UNITBLK'"
assert "T12 the unit block contains no doubled percent (would survive the render verbatim)" \
  "! grep -qF '%%' '$UNITBLK'"
# Bare Restart=always inherits RestartSec=100ms with StartLimitBurst=5 in StartLimitIntervalSec=10s,
# so a unit that fails fast at boot (Doppler or network not yet up) latches `failed` in under a
# second and stays dead until the next boot — indistinguishable from "not provisioned".
assert "T12 unit disables the start-limit latch (StartLimitIntervalSec=0)" \
  "grep -qE '^[[:space:]]*StartLimitIntervalSec=0[[:space:]]*$' '$UNITBLK'"
assert "T12 RestartSec is >= 1s (100ms default would latch failed before the network is up)" \
  "[[ \$(grep -oE '^[[:space:]]*RestartSec=[0-9]+' '$UNITBLK' | grep -oE '[0-9]+$') -ge 1 ]]"
# The Doppler CLI errors with '\$HOME is not defined' even when DOPPLER_CONFIG_DIR is set, and a
# unit inherits no login environment.
assert "T12 unit sets HOME explicitly (the Doppler CLI needs it; a unit inherits no login env)" \
  "grep -qE '^[[:space:]]*Environment=.*HOME=/' '$UNITBLK'"
assert "T12 unit sets DOPPLER_CONFIG_DIR" "grep -qE 'DOPPLER_CONFIG_DIR=' '$UNITBLK'"
# A unit with PrivateTmp=true gets a private /tmp, so the cron convention resolves elsewhere.
DCD=$(grep -oE 'DOPPLER_CONFIG_DIR=[^ "]+' "$UNITBLK" | head -1 | cut -d= -f2-)
assert "T12 DOPPLER_CONFIG_DIR has no /tmp component (the measured PrivateTmp= defect class)" \
  "[[ -n '$DCD' ]] && ! grep -qE '(^|/)tmp(/|$)' <<<'$DCD'"

# THE ASSERTION ABOVE IS NECESSARY BUT ASSERTS LESS THAN IT NAMES, so this pins the EFFECTIVE value.
# The unit also pulls EnvironmentFile=/etc/default/registry-doppler, and that file — written by
# runcmd — sets DOPPLER_CONFIG_DIR=/tmp/.doppler. So two sources compete for the variable this host
# has a measured defect class around, and a grep that stops at the first good-looking line cannot
# see the loser. systemd resolves it by a PRECEDENCE LIST, not by file order: `Environment=` ranks
# after `EnvironmentFile=` and therefore WINS regardless of which line appears first. Verified
# empirically with real unit files on systemd 259 (both orders resolved to the Environment= value);
# note that `systemd-run -p` does NOT reproduce this faithfully, so a transient-unit probe is the
# wrong instrument here. Pin the mechanism: the override must come from `Environment=`, because that
# is the only form that wins.
assert "T12 DOPPLER_CONFIG_DIR is set via Environment= (the form that WINS over EnvironmentFile=)" \
  "grep -qE '^[[:space:]]*Environment=DOPPLER_CONFIG_DIR=[^[:space:]]+' '$UNITBLK'"
assert "T12 the competing EnvironmentFile is still declared (if it vanished, the note above is stale)" \
  "grep -qE '^[[:space:]]*EnvironmentFile=/etc/default/registry-doppler[[:space:]]*$' '$UNITBLK'"
assert "T12 the envfile really does set a /tmp value, so the override is load-bearing rather than decorative" \
  "grep -qF 'DOPPLER_CONFIG_DIR=/tmp/.doppler' '$CI'"

# systemd's own parser is the authority on whether this unit can start at all — a syntax error here
# is otherwise discovered at BOOT, on the host that is the fleet's sole image-pull path. Skipped
# with a STATED reason rather than vacuously when systemd-analyze is unavailable.
if [[ -n "$(command -v systemd-analyze)" ]]; then
  SA_OUT="$TMP/sa.out"
  ( cd "$TMP" && cp "$UNITBLK" zot-log-shipper.service \
      && systemd-analyze verify ./zot-log-shipper.service ) >"$SA_OUT" 2>&1
  SA_RC=$?
  assert "T12 systemd-analyze verify accepts the unit (rc=$SA_RC; catches CPUQuota=20%% and friends)" \
    "[[ '$SA_RC' -eq 0 ]]"
else
  echo "  SKIP: T12 systemd-analyze verify — binary not available in this environment (stated, not vacuous)"
fi
assert "T12 the PrivateTmp choice is EXPLICIT either way (not left to the default)" \
  "grep -qE '^[[:space:]]*PrivateTmp=(true|false)[[:space:]]*$' '$UNITBLK'"
assert "T12 unit owns a StateDirectory (the cursor must not live in a world-writable path)" \
  "grep -qE '^[[:space:]]*StateDirectory=' '$UNITBLK'"
# `doppler run` resolves the environment once at ExecStart, so a token rotation breaks a
# long-running shipper until restart, where a 5-min cron re-resolves every tick.
assert "T12 unit bounds its own lifetime so a token rotation is picked up (RuntimeMaxSec=)" \
  "grep -qE '^[[:space:]]*RuntimeMaxSec=[0-9]+' '$UNITBLK'"
assert "T12 the unit is armed in runcmd" \
  "grep -qE '^[[:space:]]*- systemctl.*enable.*zot-log-shipper\\.service' '$CI'"

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
assert "T13 journald SystemMaxUse is pinned to a literal (assertable; a conditional one is not)" \
  "grep -qE '^[[:space:]]*SystemMaxUse=[0-9]+[KMG]?[[:space:]]*$' '$JDROP'"
assert "T13 journald RuntimeMaxUse is pinned to a literal (bounds the tmpfs side too)" \
  "grep -qE '^[[:space:]]*RuntimeMaxUse=[0-9]+[KMG]?[[:space:]]*$' '$JDROP'"

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

echo ""
echo "=== $PASS passed, $FAIL failed ==="
[[ "$FAIL" -eq 0 ]] || exit 1
