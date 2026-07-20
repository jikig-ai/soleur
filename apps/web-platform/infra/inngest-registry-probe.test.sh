#!/usr/bin/env bash
# Tests for inngest-registry-probe.sh — the 2.0 pre-flight empty-registry probe
# for the Inngest dedicated-host cutover (#6178, ADR-100). Verifies it returns a
# single pure-JSON OBJECT {registry_empty, function_count, function_ids} on stdout
# (webhook combined-stream purity — the workflow jq-parses the body as an object),
# reports registry_empty correctly for empty vs non-empty registries, and FAILS
# LOUD (non-zero + stderr, never a false-clean empty registry) on a non-array
# `.data.functions` — a fetch failure / GraphQL error / unexpected shape.
#
# Test seam: INNGEST_PROBE_FUNCTIONS_FIXTURE (a /v0/gql functions-query response
# file) short-circuits the curl. No network, no inngest, no root.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="$SCRIPT_DIR/inngest-registry-probe.sh"

PASS=0
FAIL=0

assert_eq() {
  local desc="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then echo "  PASS: $desc"; PASS=$((PASS + 1));
  else echo "  FAIL: $desc"; echo "    expected: $expected"; echo "    actual:   $actual"; FAIL=$((FAIL + 1)); fi
}

# Build a /v0/gql `functions` query response. $1 = JSON array of ids.
make_functions() {
  jq -nc --argjson ids "$1" '{data:{functions:[ $ids[] | {id:.} ]}}'
}

# --- Test 1: empty registry → registry_empty:true, function_count:0 ---
test_empty_registry() {
  echo "TEST: registry-probe — empty registry reports registry_empty:true count:0"
  local fixture; fixture=$(mktemp)
  make_functions '[]' > "$fixture"

  local out; out=$(INNGEST_PROBE_FUNCTIONS_FIXTURE="$fixture" bash "$TARGET")
  assert_eq "stdout is a single JSON object" "object" "$(echo "$out" | jq -r 'type')"
  assert_eq "registry_empty is true" "true" "$(echo "$out" | jq -r '.registry_empty')"
  assert_eq "function_count is 0" "0" "$(echo "$out" | jq -r '.function_count')"
  assert_eq "function_ids is empty array" "0" "$(echo "$out" | jq -r '.function_ids | length')"
  rm -f "$fixture"
}

# --- Test 2: non-empty registry → registry_empty:false, function_count:N ---
test_nonempty_registry() {
  echo "TEST: registry-probe — non-empty registry reports registry_empty:false count:N"
  local fixture; fixture=$(mktemp)
  make_functions '["fn-b","fn-a"]' > "$fixture"

  local out; out=$(INNGEST_PROBE_FUNCTIONS_FIXTURE="$fixture" bash "$TARGET")
  assert_eq "registry_empty is false" "false" "$(echo "$out" | jq -r '.registry_empty')"
  assert_eq "function_count is 2" "2" "$(echo "$out" | jq -r '.function_count')"
  # ids sorted deterministically
  assert_eq "function_ids sorted" "fn-a,fn-b" "$(echo "$out" | jq -r '.function_ids | join(",")')"
  rm -f "$fixture"
}

# --- Test 3: malformed / non-array .data.functions → fail LOUD (non-zero) ---
test_malformed_fails_loud() {
  echo "TEST: registry-probe — non-array .data.functions fails LOUD (non-zero, no false-clean)"
  local fixture; fixture=$(mktemp)
  # A GraphQL error envelope: .data.functions is absent/null, not an array.
  echo '{"errors":[{"message":"server down"}],"data":null}' > "$fixture"

  local rc=0 out
  out=$(INNGEST_PROBE_FUNCTIONS_FIXTURE="$fixture" bash "$TARGET" 2>/dev/null) || rc=$?
  if [[ "$rc" -ne 0 ]]; then echo "  PASS: exits non-zero on malformed response"; PASS=$((PASS + 1));
  else echo "  FAIL: expected non-zero exit on malformed response (got rc=0, out=$out)"; FAIL=$((FAIL + 1)); fi
  # It must NOT emit a false-clean registry_empty:true.
  if echo "$out" | jq -e '.registry_empty == true' >/dev/null 2>&1; then
    echo "  FAIL: emitted a false-clean registry_empty:true on a malformed response"; FAIL=$((FAIL + 1));
  else echo "  PASS: no false-clean empty-registry emitted"; PASS=$((PASS + 1)); fi
  rm -f "$fixture"
}

# --- Test 4: a bare array (pre-#5517 wrong assumption) also fails LOUD ---
test_bare_array_fails_loud() {
  echo "TEST: registry-probe — bare-array response (not {data:{functions}}) fails LOUD"
  local fixture; fixture=$(mktemp)
  echo '[{"id":"fn-a"}]' > "$fixture"
  local rc=0
  INNGEST_PROBE_FUNCTIONS_FIXTURE="$fixture" bash "$TARGET" >/dev/null 2>&1 || rc=$?
  if [[ "$rc" -ne 0 ]]; then echo "  PASS: exits non-zero on bare-array shape"; PASS=$((PASS + 1));
  else echo "  FAIL: expected non-zero exit on bare-array shape"; FAIL=$((FAIL + 1)); fi
  rm -f "$fixture"
}

# --- Test 5: script carries curl --max-time (no unbounded network call) ---
test_curl_max_time() {
  echo "TEST: registry-probe — curl carries --max-time"
  if grep -qE 'curl[^|]*--max-time' "$TARGET"; then
    echo "  PASS: curl --max-time present"; PASS=$((PASS + 1));
  else echo "  FAIL: no curl --max-time in $TARGET"; FAIL=$((FAIL + 1)); fi
}

# --- Test 6: targets the dedicated host GQL by default ---
test_default_gql_url() {
  echo "TEST: registry-probe — defaults to the dedicated host 10.0.1.40:8288/v0/gql"
  if grep -q '10.0.1.40:8288/v0/gql' "$TARGET"; then
    echo "  PASS: default INNGEST_REMOTE_GQL_URL targets 10.0.1.40:8288"; PASS=$((PASS + 1));
  else echo "  FAIL: default GQL URL does not target the dedicated host"; FAIL=$((FAIL + 1)); fi
}

# ===========================================================================
# #6258 (ADR-106) — single-shot: START/DONE markers + --connect-timeout (NO deadline/ceiling)
# ===========================================================================

RC=0; STDOUT_CAP=""; MARKERS_CAP=""
run_probe_logcap() {
  local fixture="$1"
  local bindir logout; bindir=$(mktemp -d); logout=$(mktemp)
  cat > "$bindir/logger" <<STUB
#!/usr/bin/env bash
shift 2 2>/dev/null || true
echo "\$*" >> "$logout"
STUB
  chmod +x "$bindir/logger"
  RC=0
  STDOUT_CAP=$(PATH="$bindir:$PATH" INNGEST_PROBE_FUNCTIONS_FIXTURE="$fixture" bash "$TARGET" 2>/dev/null) || RC=$?
  MARKERS_CAP=$(cat "$logout")
  rm -rf "$bindir" "$logout"
}

# --- #6258 T1: happy path emits START (before the query) + DONE, stdout stays pure JSON ---
test_rp_markers_journald_only() {
  echo "TEST: registry-probe — START+DONE journald-only, stdout stays pure JSON"
  local fixture; fixture=$(mktemp)
  make_functions '["fn-a"]' > "$fixture"
  run_probe_logcap "$fixture"
  if [[ "$RC" -eq 0 ]]; then echo "  PASS: happy path exits 0"; PASS=$((PASS+1)); else echo "  FAIL: rc=$RC"; FAIL=$((FAIL+1)); fi
  if echo "$STDOUT_CAP" | jq -e 'has("registry_empty")' >/dev/null 2>&1 && ! echo "$STDOUT_CAP" | grep -q SOLEUR; then
    echo "  PASS: stdout is a pure object, no marker leaked"; PASS=$((PASS+1));
  else echo "  FAIL: stdout polluted (out=$STDOUT_CAP)"; FAIL=$((FAIL+1)); fi
  echo "$MARKERS_CAP" | grep -q 'SOLEUR_INNGEST_PREFLIGHT_START op=verify-registry' \
    && { echo "  PASS: START in journald (before the single query)"; PASS=$((PASS+1)); } || { echo "  FAIL: no START (markers=$MARKERS_CAP)"; FAIL=$((FAIL+1)); }
  echo "$MARKERS_CAP" | grep -q 'SOLEUR_INNGEST_PREFLIGHT_DONE op=verify-registry' \
    && { echo "  PASS: DONE in journald"; PASS=$((PASS+1)); } || { echo "  FAIL: no DONE (markers=$MARKERS_CAP)"; FAIL=$((FAIL+1)); }
  rm -f "$fixture"
}

# --- #6258 T2: START emitted even when the single query fails (absence-of-START = host-down) ---
test_rp_start_on_failure() {
  echo "TEST: registry-probe — START emitted even on a malformed/failed query"
  local fixture; fixture=$(mktemp)
  # DSN in the error message (#6258 review P1) — the fn_errs diagnostic must scrub it.
  echo '{"errors":[{"message":"FATAL password for postgres://u:p@10.0.1.40:5432/db"}],"data":null}' > "$fixture"
  run_probe_logcap "$fixture"
  if [[ "$RC" -eq 1 ]]; then echo "  PASS: exits 1 on failure"; PASS=$((PASS+1)); else echo "  FAIL: rc=$RC"; FAIL=$((FAIL+1)); fi
  echo "$MARKERS_CAP" | grep -q 'SOLEUR_INNGEST_PREFLIGHT_START op=verify-registry' \
    && { echo "  PASS: START marker still emitted on a failed probe"; PASS=$((PASS+1)); } || { echo "  FAIL: no START on failure (markers=$MARKERS_CAP)"; FAIL=$((FAIL+1)); }
  # The FATAL line legitimately prints the credential-less internal $GQL_URL
  # (http://10.0.1.40:8288/…), so assert on the credential-bearing DSN shape, not bare '://'.
  assert_eq "no user:pass@host:port DSN in ANY journald line (incl. fn_errs diagnostic)" "0" "$(echo "$MARKERS_CAP" | grep -cE '@[^ ]+:[0-9]+' || true)"
  assert_eq "no user:pass@host:port DSN on stdout (run log)" "0" "$(echo "$STDOUT_CAP" | grep -cE '@[^ ]+:[0-9]+' || true)"
  assert_eq "DSN host:port scrubbed from fn_errs (10.0.1.40:5432 gone)" "0" "$(echo "$MARKERS_CAP $STDOUT_CAP" | grep -c '10.0.1.40:5432' || true)"
  rm -f "$fixture"
}

# --- #6258 T3: --connect-timeout on the single curl; NO deadline/ceiling (single-shot) ---
test_rp_connect_timeout_no_loop() {
  echo "TEST: registry-probe — --connect-timeout present; single-shot (no pagination loop)"
  if grep -qE 'curl[^|]*--connect-timeout' "$TARGET"; then echo "  PASS: --connect-timeout present"; PASS=$((PASS+1));
  else echo "  FAIL: no --connect-timeout"; FAIL=$((FAIL+1)); fi
  # Single-shot: no `while :` cursor loop, no PREFLIGHT_DEADLINE_S (Finding 12 / Phase 0.3).
  if ! grep -qE 'while[[:space:]]*:' "$TARGET"; then echo "  PASS: no pagination loop (single-shot)"; PASS=$((PASS+1));
  else echo "  FAIL: unexpected pagination loop in a single-shot probe"; FAIL=$((FAIL+1)); fi
  if ! grep -q 'PREFLIGHT_DEADLINE_S' "$TARGET"; then echo "  PASS: no deadline seam (single-shot needs none)"; PASS=$((PASS+1));
  else echo "  FAIL: unexpected deadline seam in a single-shot probe"; FAIL=$((FAIL+1)); fi
}

# --- #6258 T4: marker tag present in vector.toml allowlist (drift guard) ---
test_rp_marker_tag_in_vector() {
  echo "TEST: registry-probe — inngest-registry-probe tag in vector.toml allowlist"
  local vector="$SCRIPT_DIR/vector.toml"
  if grep -qE '^[[:space:]]*"inngest-registry-probe",' "$vector"; then echo "  PASS: tag in vector.toml"; PASS=$((PASS+1));
  else echo "  FAIL: tag NOT in vector.toml"; FAIL=$((FAIL+1)); fi
}

# ===========================================================================
# #6295 — _pf_scrub must redact the libpq KEYWORD-CONNSTRING DSN form
#
# The two original rules cover the URI form (scheme://…) and the credential
# form (user:pass@host). The libpq keyword form carries NEITHER a scheme nor
# an `@`, so a DSN in a GraphQL errors[].message leaked the prd Supabase
# project ref straight into stdout (the Actions run log) and stderr.
#
# All fixtures are SYNTHESIZED (cq-test-fixtures-synthesized-only) — the ref
# below is a fixed non-existent 20-char string, never a real project ref.
# ===========================================================================

# A synthetic project ref: same shape as a real Supabase ref (20 lowercase
# letters) but not allocated to any project.
SYNTH_REF="qzwxecrvtbynumikolpa"

# Drive a DSN-bearing GraphQL error envelope through the REAL _pf_scrub call
# site (run_probe's non-array branch at inngest-registry-probe.sh:107), and
# capture stdout and stderr SEPARATELY so each can be asserted independently.
# $1 = the errors[].message string to embed.
run_probe_errmsg() {
  local msg="$1" fixture out err rc
  fixture=$(mktemp); out=$(mktemp); err=$(mktemp)
  jq -nc --arg m "$msg" '{errors:[{message:$m}],data:null}' > "$fixture"
  set +e
  INNGEST_PROBE_FUNCTIONS_FIXTURE="$fixture" bash "$TARGET" > "$out" 2> "$err"
  rc=$?
  set -e
  # rc is expected non-zero (fail-loud branch); the payload is what we assert.
  RP_OUT=$(cat "$out"); RP_ERR=$(cat "$err"); RP_RC=$rc
  rm -f "$fixture" "$out" "$err"
}

# --- #6295 T1: libpq keyword form — ref must leak to NEITHER stdout nor stderr ---
test_pf_scrub_libpq_keyword_form() {
  echo "TEST: _pf_scrub — libpq keyword-connstring DSN is redacted (#6295)"
  run_probe_errmsg "connection to server failed: host=db.${SYNTH_REF}.supabase.co port=5432 dbname=postgres user=postgres password=hunter2sentinel"

  if ! grep -qF "$SYNTH_REF" <<<"$RP_OUT"; then echo "  PASS: synthetic ref absent from stdout"; PASS=$((PASS+1));
  else echo "  FAIL: synthetic ref LEAKED to stdout"; FAIL=$((FAIL+1)); fi
  if ! grep -qF "$SYNTH_REF" <<<"$RP_ERR"; then echo "  PASS: synthetic ref absent from stderr"; PASS=$((PASS+1));
  else echo "  FAIL: synthetic ref LEAKED to stderr"; FAIL=$((FAIL+1)); fi
  # The password must not survive either.
  if ! grep -qF "hunter2sentinel" <<<"$RP_OUT$RP_ERR"; then echo "  PASS: password absent from both streams"; PASS=$((PASS+1));
  else echo "  FAIL: password LEAKED"; FAIL=$((FAIL+1)); fi
  # Fail-loud contract still holds — the redaction must not swallow the exit code.
  if [[ "$RP_RC" -ne 0 ]]; then echo "  PASS: still fails loud (rc=$RP_RC)"; PASS=$((PASS+1));
  else echo "  FAIL: expected non-zero exit on the error branch"; FAIL=$((FAIL+1)); fi
  # POSITIVE CONTROL (F4): absence-only assertions pass just as happily when the
  # redaction DESTROYS the diagnostic as when it scrubs it. A rule widened to
  # nuke the whole line would satisfy every assertion above. Pin the surrounding
  # prose so scrub-vs-annihilate are distinguishable.
  if grep -qF "connection to server failed" <<<"$RP_OUT"; then echo "  PASS: diagnostic prose survived the redaction"; PASS=$((PASS+1));
  else echo "  FAIL: redaction ANNIHILATED the diagnostic (over-redaction, not scrubbing)"; FAIL=$((FAIL+1)); fi
}

# --- #6295 T2: over-redaction control through the REAL call site ---
# v1 of this plan used a SOLEUR_* marker as the control, but markers reach
# _pf_sanitize and never _pf_scrub — that control tested an impossible path
# and would have passed against any implementation. This drives benign
# diagnostic prose through the same errors[].message seam as T1.
test_pf_scrub_no_over_redaction() {
  echo "TEST: _pf_scrub — benign diagnostic text survives intact (over-redaction control)"
  run_probe_errmsg "function sync incomplete: 3 of 7 handlers registered, retry scheduled"

  for token in "function sync incomplete" "3 of 7 handlers registered" "retry scheduled"; do
    if grep -qF "$token" <<<"$RP_OUT"; then echo "  PASS: preserved \"$token\""; PASS=$((PASS+1));
    else echo "  FAIL: over-redacted \"$token\""; FAIL=$((FAIL+1)); fi
  done
}

# --- #6295 T3: a LONE libpq keyword must NOT trigger redaction (A-AC3) ---
# The rule requires >=2 co-occurring keywords. A single `host=` in prose is
# ordinary diagnostic text and must survive; redacting it would be the
# over-redaction failure the co-occurrence requirement exists to prevent.
test_pf_scrub_lone_keyword_not_redacted() {
  echo "TEST: _pf_scrub — a lone libpq keyword does not trigger redaction"
  run_probe_errmsg "resolver could not determine host=unset for the upstream pool"

  if grep -qF "host=unset" <<<"$RP_OUT"; then echo "  PASS: lone host= survived"; PASS=$((PASS+1));
  else echo "  FAIL: lone host= was redacted (over-redaction)"; FAIL=$((FAIL+1)); fi
}

# --- #6295 T4: the two ORIGINAL rules still redact (no regression) ---
test_pf_scrub_original_rules_intact() {
  echo "TEST: _pf_scrub — URI and credential forms still redacted (no regression)"
  run_probe_errmsg "dial failed for postgresql://postgres:pw@db.${SYNTH_REF}.supabase.co:5432/postgres"
  if ! grep -qF "$SYNTH_REF" <<<"$RP_OUT$RP_ERR"; then echo "  PASS: URI form still redacted"; PASS=$((PASS+1));
  else echo "  FAIL: URI form REGRESSED"; FAIL=$((FAIL+1)); fi

  run_probe_errmsg "auth rejected for postgres:secretpw@db.${SYNTH_REF}.supabase.co"
  if ! grep -qF "$SYNTH_REF" <<<"$RP_OUT$RP_ERR"; then echo "  PASS: credential form still redacted"; PASS=$((PASS+1));
  else echo "  FAIL: credential form REGRESSED"; FAIL=$((FAIL+1)); fi
}

# --- #6295 T6: ENCODING-SHAPE regression battery (the leaks the first cut missed) ---
#
# The original rule required >=2 libpq keywords separated by [[:space:]]+, and
# every fixture used the ONE shape it was written against: space-separated,
# unquoted values. Three encodings defeated it, all verified leaking BEFORE the
# fix (ref AND password reaching stdout + stderr):
#
#   A2  jq -c re-encodes a real newline as the two-character escape \n, which
#       [[:space:]] cannot match; the greedy value class then swallowed the
#       whole remainder as ONE token so the co-occurrence group never fired.
#   A3  same for \t.
#   B1  a double quote TERMINATES [^[:space:]"]*, so a legal double-quoted
#       libpq value killed the chain at the first keyword.
#   E   the sibling raw path (doublefire/inventory) used tr -d on newlines,
#       WELDING host=X and password=Y into one token — same failure, opposite
#       cause. Fixed by translating control chars to SPACE instead of deleting.
#
# Each case asserts BOTH the project ref and the password are absent.
test_pf_scrub_encoding_shapes() {
  echo "TEST: _pf_scrub — encoding-shape battery (json-escaped / quoted / welded)"
  local -a cases=(
    "A2-json-newline|connection failed:\\nhost=db.${SYNTH_REF}.supabase.co\\npassword=hunter2sentinel"
    "A3-json-tab|failed: host=db.${SYNTH_REF}.supabase.co\\tpassword=hunter2sentinel"
    "B1-json-quoted|failed: host=\\\"db.${SYNTH_REF}.supabase.co\\\" password=\\\"hunter2sentinel\\\""
    "B3-single-quoted|failed: host='db.${SYNTH_REF}.supabase.co' password='hunter2sentinel'"
    "D-lone-host|host=db.${SYNTH_REF}.supabase.co"
    "F-uppercase-kw|failed: HOST=db.${SYNTH_REF}.supabase.co PASSWORD=hunter2sentinel"
    # RAW control bytes (F3): the cases above are all JSON-ESCAPED forms handled
    # by the \\[nrt] alternation — none of them ever reach the `tr` stage. This
    # one carries a real 0x0A, which is what `tr` exists to neutralise. Deleting
    # the tr stage must redden the suite.
    "G-raw-newline|$(printf 'failed:\nhost=db.%s.supabase.co\npassword=hunter2sentinel' "$SYNTH_REF")"
    "H-raw-esc|$(printf 'failed:\x1bhost=db.%s.supabase.co\x1bpassword=hunter2sentinel' "$SYNTH_REF")"
    "I-u2028|$(printf 'failed:\u2028host=db.%s.supabase.co\u2028password=hunter2sentinel' "$SYNTH_REF")"
  )
  local n=0 entry label msg
  for entry in "${cases[@]}"; do
    label="${entry%%|*}"; msg="${entry#*|}"
    run_probe_errmsg "$msg"
    n=$((n+1))
    if ! grep -qF "$SYNTH_REF" <<<"$RP_OUT$RP_ERR"; then echo "  PASS: $label — ref redacted"; PASS=$((PASS+1));
    else echo "  FAIL: $label — ref LEAKED"; FAIL=$((FAIL+1)); fi
    if ! grep -qF "hunter2sentinel" <<<"$RP_OUT$RP_ERR"; then echo "  PASS: $label — password redacted"; PASS=$((PASS+1));
    else echo "  FAIL: $label — password LEAKED"; FAIL=$((FAIL+1)); fi
  done
  # Minimum-cardinality guard: an empty case array must not pass vacuously.
  if [[ "$n" -eq "${#cases[@]}" && "$n" -ge 9 ]]; then echo "  PASS: all $n encoding shapes exercised"; PASS=$((PASS+1));
  else echo "  FAIL: only $n shape(s) exercised"; FAIL=$((FAIL+1)); fi
}

# --- #6295 T7: over-redaction controls for the WIDENED rules ---
# The hardened rules redact more aggressively (a lone supabase host, any
# password=). These pin the boundary so the widening cannot creep into
# ordinary diagnostics.
test_pf_scrub_widened_over_redaction() {
  echo "TEST: _pf_scrub — widened rules do not over-redact ordinary diagnostics"
  local -a controls=(
    "upstream_host=web1 port=8080 healthcheck returned 200"
    "myhost=alpha xuser=beta"
    "resolver could not determine host=unset for the upstream pool"
  )
  local c
  for c in "${controls[@]}"; do
    run_probe_errmsg "$c"
    if grep -qF "$c" <<<"$RP_OUT"; then echo "  PASS: preserved \"${c:0:40}...\""; PASS=$((PASS+1));
    else echo "  FAIL: over-redacted \"$c\" -> $RP_OUT"; FAIL=$((FAIL+1)); fi
  done
}

# --- #6295 T8: RAW control bytes, driven straight into _pf_scrub ---
#
# The encoding battery above cannot reach the `tr` stage: run_probe_errmsg
# builds its fixture with `jq --arg`, which RE-ENCODES a real 0x0A back into
# the two-character escape \n. So every "raw" case arrives escaped, and
# deleting the tr stage entirely left the suite green.
#
# This harness pipes raw bytes directly into the extracted _pf_scrub, which is
# the only way to exercise the stage that unwelds control-separated tokens.
# Deleting `tr` must redden this block.
scrub_raw() {
  printf '%b' "$1" | (
    eval "$(sed -n '/^_pf_scrub() {$/,/^}$/p' "$TARGET")"
    _pf_scrub
  )
}

test_pf_scrub_raw_control_bytes() {
  echo "TEST: _pf_scrub — RAW control bytes reach the tr stage (#6617)"
  # Harness liveness: the extraction must yield a callable function.
  local probe; probe=$(scrub_raw 'plain text' 2>/dev/null || true)
  if [[ "$probe" == "plain text" ]]; then echo "  PASS: raw harness is live"; PASS=$((PASS+1));
  else echo "  FAIL: raw harness is vacuous (got '$probe')"; FAIL=$((FAIL+1)); fi

  local -a raw=(
    "RAW-newline|failed:\nhost=db.${SYNTH_REF}.supabase.co\npassword=hunter2sentinel"
    "RAW-tab|failed:\thost=db.${SYNTH_REF}.supabase.co\tpassword=hunter2sentinel"
    "RAW-esc|failed:\x1bhost=db.${SYNTH_REF}.supabase.co\x1bpassword=hunter2sentinel"
    "RAW-vtab|failed:\vhost=db.${SYNTH_REF}.supabase.co\vpassword=hunter2sentinel"
  )
  local n=0 e label msg out
  for e in "${raw[@]}"; do
    label="${e%%|*}"; msg="${e#*|}"; n=$((n+1))
    out=$(scrub_raw "$msg")
    if ! grep -qF "$SYNTH_REF" <<<"$out"; then echo "  PASS: $label — ref redacted"; PASS=$((PASS+1));
    else echo "  FAIL: $label — ref LEAKED ($out)"; FAIL=$((FAIL+1)); fi
    if ! grep -qF "hunter2sentinel" <<<"$out"; then echo "  PASS: $label — password redacted"; PASS=$((PASS+1));
    else echo "  FAIL: $label — password LEAKED ($out)"; FAIL=$((FAIL+1)); fi
    # No raw control byte may survive into a journald/stdout line.
    if ! grep -qP '[\x00-\x1f\x7f]' <<<"$out" 2>/dev/null; then echo "  PASS: $label — no control byte survives"; PASS=$((PASS+1));
    else echo "  FAIL: $label — control byte SURVIVED (log-injection risk)"; FAIL=$((FAIL+1)); fi
  done
  if [[ "$n" -eq "${#raw[@]}" && "$n" -ge 4 ]]; then echo "  PASS: all $n raw shapes exercised"; PASS=$((PASS+1));
  else echo "  FAIL: only $n raw shape(s)"; FAIL=$((FAIL+1)); fi
}

# --- #6295 T5: PERMANENT identity guard across all three _pf_scrub copies ---
# The function is triplicated across the three cutover-path probes. The cost
# of triplication is DRIFT; this test converts that from silent divergence
# into a mechanical check. Extraction is deferred until a fourth consumer
# appears (see the tracking issue in the PR body).
test_pf_scrub_bodies_byte_identical() {
  echo "TEST: _pf_scrub — all three copies byte-identical (anti-drift guard)"
  local files=(inngest-registry-probe.sh inngest-doublefire-probe.sh inngest-inventory.sh)
  local ref_body="" f body n=0
  for f in "${files[@]}"; do
    local path="$SCRIPT_DIR/$f"
    if [[ ! -f "$path" ]]; then echo "  FAIL: missing $f"; FAIL=$((FAIL+1)); continue; fi
    body=$(sed -n '/^_pf_scrub() {$/,/^}$/p' "$path")
    if [[ -z "$body" ]]; then echo "  FAIL: no _pf_scrub body extracted from $f"; FAIL=$((FAIL+1)); continue; fi
    n=$((n+1))
    if [[ -z "$ref_body" ]]; then ref_body="$body"; continue; fi
    if [[ "$body" == "$ref_body" ]]; then echo "  PASS: $f identical to reference"; PASS=$((PASS+1));
    else echo "  FAIL: $f DRIFTED from reference"; FAIL=$((FAIL+1)); fi
  done
  # Minimum-cardinality guard: an empty/unreadable file set must not pass vacuously.
  if [[ "$n" -eq "${#files[@]}" ]]; then echo "  PASS: all ${#files[@]} copies extracted"; PASS=$((PASS+1));
  else echo "  FAIL: extracted only $n of ${#files[@]} copies"; FAIL=$((FAIL+1)); fi
}

echo "=== inngest-registry-probe.sh test suite ==="
test_empty_registry
test_nonempty_registry
test_malformed_fails_loud
test_bare_array_fails_loud
test_curl_max_time
test_default_gql_url
test_rp_markers_journald_only
test_rp_start_on_failure
test_rp_connect_timeout_no_loop
test_rp_marker_tag_in_vector
test_pf_scrub_libpq_keyword_form
test_pf_scrub_no_over_redaction
test_pf_scrub_lone_keyword_not_redacted
test_pf_scrub_original_rules_intact
test_pf_scrub_encoding_shapes
test_pf_scrub_raw_control_bytes
test_pf_scrub_widened_over_redaction
test_pf_scrub_bodies_byte_identical
echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
if [[ "$FAIL" -gt 0 ]]; then exit 1; fi
