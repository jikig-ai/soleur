#!/usr/bin/env bash
# Tests for cat-deploy-state.sh — verifies the JSON merge contract
# (#2185 base + #4116 services.inngest_heartbeat extension).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="$SCRIPT_DIR/cat-deploy-state.sh"

# #6425: MANDATORY, not a convenience. Every test below runs `bash "$TARGET"`, and the target
# now resolves a host_id. Without this override each invocation issues resolve_host_id's
# `curl --max-time 3` at the link-local metadata address, which BLACKHOLES off-host (measured:
# a full 3.0s per call). It also pins determinism: runners have /etc/machine-id, so an unset
# override falls through to a nondeterministic `machine-<id>`. Tests that exercise resolution
# itself set their own value inline (a local assignment wins over this export).
export SOLEUR_HOST_ID_OVERRIDE="hetzner-test-1"

PASS=0
FAIL=0
TOTAL=0

assert() {
  local description="$1"
  local condition="$2"
  TOTAL=$((TOTAL + 1))
  if eval "$condition"; then
    PASS=$((PASS + 1))
    echo "  PASS: $description"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: $description"
    echo "        condition: $condition"
  fi
}

# --- docker mock factory (#5960) ---------------------------------------------
# PORTED from audit-bwrap-uid.test.sh:26 (this suite mocked nothing before).
# Returns DOCKER_INSPECT_FIXTURE contents verbatim for ANY `docker inspect`
# call, so the seccomp_live_json discriminators (and container_restart_json,
# which safe-sentinels on garbage) can be exercised without a real daemon.
FIXTURE_DIR="$SCRIPT_DIR/test-fixtures/audit-bwrap"

create_docker_mock() {
  cat > "$1/docker" << 'MOCK'
#!/usr/bin/env bash
case "$1" in
  inspect)
    if [[ -n "${DOCKER_INSPECT_FIXTURE:-}" && -r "${DOCKER_INSPECT_FIXTURE}" ]]; then
      cat "$DOCKER_INSPECT_FIXTURE"
    else
      exit 1
    fi
    ;;
  *)
    echo "unexpected docker arg: $*" >&2
    exit 99
    ;;
esac
MOCK
  chmod +x "$1/docker"
}

echo "=== cat-deploy-state.sh tests ==="
echo ""

assert "script exists and is executable" "[[ -x '$TARGET' ]]"

# --- no_prior_deploy sentinel + services field ---
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
NO_DEPLOY_OUT=$(CI_DEPLOY_STATE="$TMP/nonexistent.state" bash "$TARGET")
assert "no_prior_deploy sentinel exit_code = -2" \
  "[[ \$(printf '%s' '$NO_DEPLOY_OUT' | jq -r .exit_code) == '-2' ]]"
assert "no_prior_deploy carries services.inngest_heartbeat" \
  "printf '%s' '$NO_DEPLOY_OUT' | jq -e '.services.inngest_heartbeat' >/dev/null"
assert "no_prior_deploy carries services.inngest_heartbeat_timer" \
  "printf '%s' '$NO_DEPLOY_OUT' | jq -e '.services.inngest_heartbeat_timer' >/dev/null"
# #6536 / FR7: the heartbeat's own journal tail. `inngest_heartbeat: failed` says the unit
# broke but never WHY; the tail carries the deciding stderr (curl's rc=2 line, doppler's
# project/auth error, or the dark-arm row) off-box with no SSH. Uses `has` rather than
# truthiness: the tail is legitimately an empty string off-host / when journalctl is absent,
# and an empty value must still prove the FIELD is wired.
assert "no_prior_deploy carries services.inngest_heartbeat_journal_tail (#6536)" \
  "printf '%s' '$NO_DEPLOY_OUT' | jq -e '.services | has(\"inngest_heartbeat_journal_tail\")' >/dev/null"
# #6536: WHICH arm the host rendered. inngest-bootstrap.sh resolves host identity at render
# time, so the dedicated and co-located hosts run different ping scripts — and nothing else
# reports which one a live host carries. Off-host (the CI case) the script does not exist, so
# the field must read `script-missing`: that value is itself the assertion that the -r probe
# ran rather than silently defaulting. Constrained to the closed value set so a future refactor
# cannot quietly widen it to an unhandled state.
assert "no_prior_deploy carries services.inngest_heartbeat_dark_arm (#6536)" \
  "printf '%s' '$NO_DEPLOY_OUT' | jq -e '.services | has(\"inngest_heartbeat_dark_arm\")' >/dev/null"
# `IN` (exact equality), never `inside`: jq's `inside`/`contains` are SUBSTRING matches on
# strings, so `[""] | inside([...])` and `["render"] | inside([...])` both return true — an
# empty/unset value would sail through the very assertion meant to bound the set. Verified.
assert "inngest_heartbeat_dark_arm is one of rendered|absent|script-missing (#6536)" \
  "printf '%s' '$NO_DEPLOY_OUT' | jq -e '.services.inngest_heartbeat_dark_arm | IN(\"rendered\",\"absent\",\"script-missing\")' >/dev/null"

# --- successful state file merge ---
echo '{"exit_code":0,"target":"inngest","tag":"vinngest-v1.2.3"}' > "$TMP/ok.state"
OK_OUT=$(CI_DEPLOY_STATE="$TMP/ok.state" bash "$TARGET")
assert "OK state preserves exit_code" \
  "[[ \$(printf '%s' '$OK_OUT' | jq -r .exit_code) == '0' ]]"
assert "OK state preserves target field" \
  "[[ \$(printf '%s' '$OK_OUT' | jq -r .target) == 'inngest' ]]"
assert "OK state injects services.inngest_heartbeat" \
  "printf '%s' '$OK_OUT' | jq -e '.services.inngest_heartbeat' >/dev/null"
assert "OK state injects services.inngest_heartbeat_timer" \
  "printf '%s' '$OK_OUT' | jq -e '.services.inngest_heartbeat_timer' >/dev/null"

# --- pre-existing services.* keys preserved ---
echo '{"exit_code":0,"services":{"web":"healthy"}}' > "$TMP/svc.state"
SVC_OUT=$(CI_DEPLOY_STATE="$TMP/svc.state" bash "$TARGET")
assert "pre-existing services.web preserved" \
  "[[ \$(printf '%s' '$SVC_OUT' | jq -r .services.web) == 'healthy' ]]"
assert "services.inngest_heartbeat still added alongside services.web" \
  "printf '%s' '$SVC_OUT' | jq -e '.services.inngest_heartbeat' >/dev/null"
assert "services.inngest_heartbeat_timer still added alongside services.web" \
  "printf '%s' '$SVC_OUT' | jq -e '.services.inngest_heartbeat_timer' >/dev/null"

# --- corrupt state sentinel ---
echo 'not valid json {' > "$TMP/corrupt.state"
CORRUPT_OUT=$(CI_DEPLOY_STATE="$TMP/corrupt.state" bash "$TARGET")
assert "corrupt_state sentinel exit_code = -3" \
  "[[ \$(printf '%s' '$CORRUPT_OUT' | jq -r .exit_code) == '-3' ]]"
assert "corrupt_state carries services.inngest_heartbeat" \
  "printf '%s' '$CORRUPT_OUT' | jq -e '.services.inngest_heartbeat' >/dev/null"
assert "corrupt_state carries services.inngest_heartbeat_timer" \
  "printf '%s' '$CORRUPT_OUT' | jq -e '.services.inngest_heartbeat_timer' >/dev/null"

# --- #5417 container restart / OOM observability fields (AC7) ---
# Use a guaranteed-absent container so docker inspect fails → safe sentinels,
# and a non-existent rate file so the rolling rate defaults to 0.
CR_OUT=$(CI_DEPLOY_STATE="$TMP/ok.state" CONTAINER_NAME="soleur-absent-test-xyz" \
  CONTAINER_RESTART_RATE_FILE="$TMP/nope.rate" bash "$TARGET")
# Collision guard: the top-level exit_code MUST remain the DEPLOY sentinel (0),
# NOT the container's State.ExitCode (which is exposed as container_exit_code).
assert "deploy exit_code preserved (container exit code did NOT clobber it)" \
  "[[ \$(printf '%s' '$CR_OUT' | jq -r .exit_code) == '0' ]]"
assert "restart_count present with absent-container sentinel -1" \
  "[[ \$(printf '%s' '$CR_OUT' | jq -r .restart_count) == '-1' ]]"
assert "oom_killed present (boolean false sentinel)" \
  "[[ \$(printf '%s' '$CR_OUT' | jq -r .oom_killed) == 'false' ]]"
assert "container_exit_code present (distinct key from deploy exit_code)" \
  "printf '%s' '$CR_OUT' | jq -e 'has(\"container_exit_code\")' >/dev/null"
assert "restart_rate_per_hour present (0 when no rate file)" \
  "[[ \$(printf '%s' '$CR_OUT' | jq -r .restart_rate_per_hour) == '0' ]]"
assert "oom_journal_tail present and a string" \
  "printf '%s' '$CR_OUT' | jq -e '.oom_journal_tail | type == \"string\"' >/dev/null"

# Rolling-rate passthrough from the container-restart-monitor's persisted file.
echo '7' > "$TMP/has.rate"
RATE_OUT=$(CI_DEPLOY_STATE="$TMP/ok.state" CONTAINER_NAME="soleur-absent-test-xyz" \
  CONTAINER_RESTART_RATE_FILE="$TMP/has.rate" bash "$TARGET")
assert "restart_rate_per_hour reads the monitor's persisted rate (7)" \
  "[[ \$(printf '%s' '$RATE_OUT' | jq -r .restart_rate_per_hour) == '7' ]]"

# --- #5669 cron-drain observability fields (ADR-078) ---
# Absent drain-state file → safe sentinels (wait -1, timed_out false), so a
# deploy that never reached the drain is distinguishable from a real 0-wait drain.
CD_ABSENT=$(CI_DEPLOY_STATE="$TMP/ok.state" CRON_DRAIN_STATE_FILE="$TMP/no-drain.json" bash "$TARGET")
assert "cron_drain_wait_secs sentinel -1 when no drain state file" \
  "[[ \$(printf '%s' '$CD_ABSENT' | jq -r .cron_drain_wait_secs) == '-1' ]]"
assert "cron_drain_timed_out sentinel false when no drain state file" \
  "[[ \$(printf '%s' '$CD_ABSENT' | jq -r .cron_drain_timed_out) == 'false' ]]"
assert "deploy exit_code preserved alongside cron_drain fields (not clobbered)" \
  "[[ \$(printf '%s' '$CD_ABSENT' | jq -r .exit_code) == '0' ]]"

# Present drain-state file → fields reflect the recorded drain outcome.
echo '{"cron_drain_wait_secs":3000,"cron_drain_timed_out":true}' > "$TMP/drain.json"
CD_PRESENT=$(CI_DEPLOY_STATE="$TMP/ok.state" CRON_DRAIN_STATE_FILE="$TMP/drain.json" bash "$TARGET")
assert "cron_drain_wait_secs read from drain state file (3000)" \
  "[[ \$(printf '%s' '$CD_PRESENT' | jq -r .cron_drain_wait_secs) == '3000' ]]"
assert "cron_drain_timed_out read from drain state file (true)" \
  "[[ \$(printf '%s' '$CD_PRESENT' | jq -r .cron_drain_timed_out) == 'true' ]]"

# Malformed drain-state content → cron_drain_json's regex guards reject the bad
# values and fall back to the safe sentinels (never emit a non-numeric wait or a
# non-boolean timed_out into the webhook payload).
echo '{"cron_drain_wait_secs":"not-a-number","cron_drain_timed_out":"maybe"}' > "$TMP/bad-drain.json"
CD_BAD=$(CI_DEPLOY_STATE="$TMP/ok.state" CRON_DRAIN_STATE_FILE="$TMP/bad-drain.json" bash "$TARGET")
assert "malformed cron_drain_wait_secs falls back to sentinel -1" \
  "[[ \$(printf '%s' '$CD_BAD' | jq -r .cron_drain_wait_secs) == '-1' ]]"
assert "malformed cron_drain_timed_out falls back to sentinel false" \
  "[[ \$(printf '%s' '$CD_BAD' | jq -r .cron_drain_timed_out) == 'false' ]]"

# Faithful sandbox canary verdict (#5875 / ADR-079) surfaced under sandbox_canary.
# Absent state file → verdict "unknown" sentinel (a deploy that never ran the canary).
SC_ABSENT=$(CI_DEPLOY_STATE="$TMP/ok.state" SANDBOX_CANARY_STATE_FILE="$TMP/no-canary.json" bash "$TARGET")
assert "sandbox_canary.verdict sentinel 'unknown' when no canary state file" \
  "[[ \$(printf '%s' '$SC_ABSENT' | jq -r .sandbox_canary.verdict) == 'unknown' ]]"
assert "deploy exit_code preserved alongside sandbox_canary (not clobbered)" \
  "[[ \$(printf '%s' '$SC_ABSENT' | jq -r .exit_code) == '0' ]]"
# Present state file → fields reflect the recorded canary verdict.
echo '{"verdict":"sandbox_broken","reason":"bwrap_operation_not_permitted","sdk_version":"0.3.197","checked_at":1751000000}' > "$TMP/canary.json"
SC_PRESENT=$(CI_DEPLOY_STATE="$TMP/ok.state" SANDBOX_CANARY_STATE_FILE="$TMP/canary.json" bash "$TARGET")
assert "sandbox_canary.verdict read from state file (sandbox_broken)" \
  "[[ \$(printf '%s' '$SC_PRESENT' | jq -r .sandbox_canary.verdict) == 'sandbox_broken' ]]"
assert "sandbox_canary.reason read from state file" \
  "[[ \$(printf '%s' '$SC_PRESENT' | jq -r .sandbox_canary.reason) == 'bwrap_operation_not_permitted' ]]"
assert "sandbox_canary.sdk_version read from state file" \
  "[[ \$(printf '%s' '$SC_PRESENT' | jq -r .sandbox_canary.sdk_version) == '0.3.197' ]]"
# Soak accumulators (consecutive_pass / first_pass_at) surface for the follow-through.
echo '{"verdict":"pass","reason":"ok","sdk_version":"0.3.197","checked_at":1751000500,"consecutive_pass":5,"first_pass_at":1750740500}' > "$TMP/soak-canary.json"
SC_SOAK=$(CI_DEPLOY_STATE="$TMP/ok.state" SANDBOX_CANARY_STATE_FILE="$TMP/soak-canary.json" bash "$TARGET")
assert "sandbox_canary.consecutive_pass surfaced (5)" \
  "[[ \$(printf '%s' '$SC_SOAK' | jq -r .sandbox_canary.consecutive_pass) == '5' ]]"
assert "sandbox_canary.first_pass_at surfaced" \
  "[[ \$(printf '%s' '$SC_SOAK' | jq -r .sandbox_canary.first_pass_at) == '1750740500' ]]"
# Absent-file sentinels include the soak accumulators at 0.
assert "sandbox_canary.consecutive_pass sentinel 0 when no state file" \
  "[[ \$(printf '%s' '$SC_ABSENT' | jq -r .sandbox_canary.consecutive_pass) == '0' ]]"

# Malformed checked_at → falls back to numeric sentinel 0 (never a non-numeric).
echo '{"verdict":"pass","reason":"ok","sdk_version":"0.3.197","checked_at":"not-a-number"}' > "$TMP/bad-canary.json"
SC_BAD=$(CI_DEPLOY_STATE="$TMP/ok.state" SANDBOX_CANARY_STATE_FILE="$TMP/bad-canary.json" bash "$TARGET")
assert "malformed sandbox_canary.checked_at falls back to sentinel 0" \
  "[[ \$(printf '%s' '$SC_BAD' | jq -r .sandbox_canary.checked_at) == '0' ]]"

# --- #5960 live seccomp loaded/host discriminators (Phase 1) ------------------
# seccomp_profile_loaded_matches_host (reload leg, host-jq skew-immune),
# seccomp_profile_host_sha256 (raw sha256sum — delivery leg), and
# seccomp_profile_host_present. Mock docker; env-override SECCOMP_PROFILE_HOST_PATH
# to a fixture; run against ok.state so top-level exit_code stays 0.
VALID_SECCOMP="$FIXTURE_DIR/valid-seccomp.json"
HOST_RAW_SHA=$(sha256sum "$VALID_SECCOMP" | cut -d' ' -f1)

# Case 1: loaded == host. Inlined seccomp (inspect-pass.txt, different key order)
# canonical-equals the on-host file after jq -cS; host fields populated.
MOCK1=$(mktemp -d)
create_docker_mock "$MOCK1"
SL1=$(PATH="$MOCK1:$PATH" CI_DEPLOY_STATE="$TMP/ok.state" \
  DOCKER_INSPECT_FIXTURE="$FIXTURE_DIR/inspect-pass.txt" \
  SECCOMP_PROFILE_HOST_PATH="$VALID_SECCOMP" bash "$TARGET")
rm -rf "$MOCK1"
assert "case1 loaded==host → seccomp_profile_loaded_matches_host true" \
  "[[ \$(printf '%s' '$SL1' | jq -r .seccomp_profile_loaded_matches_host) == 'true' ]]"
assert "case1 seccomp_profile_host_present true" \
  "[[ \$(printf '%s' '$SL1' | jq -r .seccomp_profile_host_present) == 'true' ]]"
assert "case1 seccomp_profile_host_sha256 is the RAW sha256sum of the host file" \
  "[[ \$(printf '%s' '$SL1' | jq -r .seccomp_profile_host_sha256) == '$HOST_RAW_SHA' ]]"

# Case 2: loaded != host (drift fixture — defaultAction differs) → matches false.
MOCK2=$(mktemp -d)
create_docker_mock "$MOCK2"
SL2=$(PATH="$MOCK2:$PATH" CI_DEPLOY_STATE="$TMP/ok.state" \
  DOCKER_INSPECT_FIXTURE="$FIXTURE_DIR/inspect-drift.txt" \
  SECCOMP_PROFILE_HOST_PATH="$VALID_SECCOMP" bash "$TARGET")
rm -rf "$MOCK2"
assert "case2 drift → seccomp_profile_loaded_matches_host false" \
  "[[ \$(printf '%s' '$SL2' | jq -r .seccomp_profile_loaded_matches_host) == 'false' ]]"
assert "case2 host_present still true (host file exists; only reload leg drifted)" \
  "[[ \$(printf '%s' '$SL2' | jq -r .seccomp_profile_host_present) == 'true' ]]"

# Case 3: literal-path seccomp entry (Docker did not resolve the flag) → matches false.
MOCK3=$(mktemp -d)
create_docker_mock "$MOCK3"
SL3=$(PATH="$MOCK3:$PATH" CI_DEPLOY_STATE="$TMP/ok.state" \
  DOCKER_INSPECT_FIXTURE="$FIXTURE_DIR/inspect-literal-path.txt" \
  SECCOMP_PROFILE_HOST_PATH="$VALID_SECCOMP" bash "$TARGET")
rm -rf "$MOCK3"
assert "case3 literal-path entry → seccomp_profile_loaded_matches_host false" \
  "[[ \$(printf '%s' '$SL3' | jq -r .seccomp_profile_loaded_matches_host) == 'false' ]]"

# Case 4: container down / docker inspect fails (no fixture) → matches false, but
# the host-file discriminators are still populated (delivery leg is docker-free).
MOCK4=$(mktemp -d)
create_docker_mock "$MOCK4"
SL4=$(PATH="$MOCK4:$PATH" CI_DEPLOY_STATE="$TMP/ok.state" \
  SECCOMP_PROFILE_HOST_PATH="$VALID_SECCOMP" bash "$TARGET")
rm -rf "$MOCK4"
assert "case4 container-down → seccomp_profile_loaded_matches_host false" \
  "[[ \$(printf '%s' '$SL4' | jq -r .seccomp_profile_loaded_matches_host) == 'false' ]]"
assert "case4 host fields still populated (present true, raw sha set)" \
  "[[ \$(printf '%s' '$SL4' | jq -r .seccomp_profile_host_present) == 'true' \
    && \$(printf '%s' '$SL4' | jq -r .seccomp_profile_host_sha256) == '$HOST_RAW_SHA' ]]"

# Case 5: host file absent → present false, host_sha256 "", matches false.
MOCK5=$(mktemp -d)
create_docker_mock "$MOCK5"
SL5=$(PATH="$MOCK5:$PATH" CI_DEPLOY_STATE="$TMP/ok.state" \
  DOCKER_INSPECT_FIXTURE="$FIXTURE_DIR/inspect-pass.txt" \
  SECCOMP_PROFILE_HOST_PATH="$TMP/no-such-seccomp.json" bash "$TARGET")
rm -rf "$MOCK5"
assert "case5 host-absent → seccomp_profile_host_present false" \
  "[[ \$(printf '%s' '$SL5' | jq -r .seccomp_profile_host_present) == 'false' ]]"
assert "case5 host-absent → seccomp_profile_host_sha256 empty string" \
  "[[ \$(printf '%s' '$SL5' | jq -r .seccomp_profile_host_sha256) == '' ]]"
assert "case5 host-absent → seccomp_profile_loaded_matches_host false" \
  "[[ \$(printf '%s' '$SL5' | jq -r .seccomp_profile_loaded_matches_host) == 'false' ]]"

# Case 6: merge integrity — new fields present AND top-level deploy exit_code (0)
# NOT clobbered by any live-seccomp read.
assert "case6 top-level deploy exit_code preserved (0) alongside seccomp fields" \
  "[[ \$(printf '%s' '$SL1' | jq -r .exit_code) == '0' ]]"
assert "case6 all three seccomp_profile_* live keys present" \
  "printf '%s' '$SL1' | jq -e 'has(\"seccomp_profile_loaded_matches_host\") and has(\"seccomp_profile_host_sha256\") and has(\"seccomp_profile_host_present\")' >/dev/null"
assert "case6 recorded seccomp_profile_sha256 diagnostic field still emitted" \
  "printf '%s' '$SL1' | jq -e 'has(\"seccomp_profile_sha256\")' >/dev/null"

# Case 7: empty-hash guard. Host file is NON-JSON (raw sha exists so the reload
# leg runs) and the inlined entry is also non-JSON+non-path — BOTH jq -cS calls
# fail and hash the empty stream to sha256(""). Without the `!= EMPTY_HASH` guard
# that reads as loaded==host (empty==empty); the guard must force matches=false.
NONJSON_HOST=$(mktemp --suffix=.json)
printf 'not valid json at all\n' > "$NONJSON_HOST"
NONJSON_INSPECT=$(mktemp)
printf 'apparmor=soleur-bwrap\nseccomp=also-not-json\n' > "$NONJSON_INSPECT"
MOCK7=$(mktemp -d)
create_docker_mock "$MOCK7"
SL7=$(PATH="$MOCK7:$PATH" CI_DEPLOY_STATE="$TMP/ok.state" \
  DOCKER_INSPECT_FIXTURE="$NONJSON_INSPECT" \
  SECCOMP_PROFILE_HOST_PATH="$NONJSON_HOST" bash "$TARGET")
rm -rf "$MOCK7"; rm -f "$NONJSON_HOST" "$NONJSON_INSPECT"
assert "case7 empty-hash guard → matches false (not a sha256(\"\") true-match)" \
  "[[ \$(printf '%s' '$SL7' | jq -r .seccomp_profile_loaded_matches_host) == 'false' ]]"

# --- #6425: host_id on the read surface ---
# deploy.soleur.ai is a tunnel hostname whose connector Cloudflare picks per edge colo, so a
# response that does not identify its own emitter cannot be told apart from a wrong-host answer.
# SOLEUR_HOST_ID_OVERRIDE is MANDATORY here: CI runners have /etc/machine-id, so an unset
# override falls through to a nondeterministic `machine-<id>`.
HID_OUT=$(CI_DEPLOY_STATE="$TMP/ok.state" SOLEUR_HOST_ID_OVERRIDE="hetzner-4242" bash "$TARGET")
assert "host_id is emitted top-level" \
  "[[ \$(printf '%s' '$HID_OUT' | jq -r .host_id) == 'hetzner-4242' ]]"
assert "host_id does not disturb the exit_code sentinel (#2205)" \
  "[[ \$(printf '%s' '$HID_OUT' | jq -r .exit_code) == '0' ]]"

# A state file is written by ci-deploy.sh but is attacker-shaped input to THIS reader: it is
# merged in as $base. jq's `+` is right-wins and the host_id literal is last in the merge chain,
# so a state file carrying its own host_id must NOT be able to forge the answer.
printf '%s\n' '{"exit_code":0,"host_id":"evil-forged","services":{}}' > "$TMP/hostile-hid.state"
HID_CLOBBER=$(CI_DEPLOY_STATE="$TMP/hostile-hid.state" SOLEUR_HOST_ID_OVERRIDE="hetzner-4242" bash "$TARGET")
assert "a state-file host_id CANNOT clobber the resolved one" \
  "[[ \$(printf '%s' '$HID_CLOBBER' | jq -r .host_id) == 'hetzner-4242' ]]"

# Fail-soft: resolve_host_id return-1s when metadata is unreachable AND machine-id is unreadable.
# `set -euo pipefail` + a bare assignment would abort the hook (non-200), losing the entire state
# read to protect one field. Point the metadata seam at a closed port to prove the read survives
# an unreachable metadata service and still exits 0 with parseable JSON.
# `|| NOMETA_RC=$?` is load-bearing: this suite is `set -euo pipefail`, so a bare
# `X=$(cmd); RC=$?` ABORTS the whole suite the moment cmd is non-zero — meaning RC could only
# ever hold 0 and the "exit 0" assertion below could never fail. That is a false-PASS anchor
# (the fea871b40 class), not a test. The `||` catches the failure so the rc is real.
NOMETA_RC=0
HID_NOMETA=$(CI_DEPLOY_STATE="$TMP/ok.state" SOLEUR_HOST_ID_OVERRIDE="" \
  SOLEUR_HOST_ID_METADATA_URL="http://127.0.0.1:1/dead" bash "$TARGET") || NOMETA_RC=$?
assert "unreachable metadata does not abort the hook (exit 0)" "[[ '$NOMETA_RC' == '0' ]]"
assert "unreachable metadata still emits parseable JSON with a host_id key" \
  "printf '%s' '$HID_NOMETA' | jq -e 'has(\"host_id\")' >/dev/null"

echo ""
echo "--- #7286: services.inngest_redis* probe fields ---"
#
# WHY THESE FIELDS EXIST. #7286 spent 16 hours knowing exactly one bit about the failing
# component: it exited non-zero. inngest-redis.service's stderr was unreadable from every remote
# surface, so the watchdog printed a hard-coded GUESS at the cause and the operator had no way to
# adjudicate it. These fields make the unit self-report over the already-authenticated
# /hooks/deploy-status read, with no SSH.
#
# ALL fixtures below are SYNTHESIZED (cq-test-fixtures-synthesized-only). The secret-shaped
# strings are deliberately non-conforming to real token grammars so they cannot trip push
# protection while still exercising every scrub rule.

# Mock factory: a systemctl that answers is-active / show / is-enabled.
# The `show` output deliberately returns properties in systemd's OWN canonical order rather than
# the caller's requested order, and omits MemoryPeak entirely (systemd < 253 emits a BLANK line
# for an unsupported property). Both are the exact conditions under which a positional `--value`
# parse silently MISALIGNS — pinning them here is what makes the by-key parse load-bearing rather
# than stylistic.
create_systemctl_mock() {
  cat > "$1/systemctl" << 'MOCK'
#!/usr/bin/env bash
case "$1" in
  is-active)
    case "$2" in
      inngest-redis.service) echo "${MOCK_REDIS_ACTIVE:-activating}"; exit 3 ;;
      *) echo "active"; exit 0 ;;
    esac
    ;;
  show)
    if [[ "$*" == *"DropInPaths"* ]]; then
      echo "EnvironmentFiles=${MOCK_REDIS_ENVFILES:-/etc/default/inngest-server (ignore_errors=no)}"
      echo "DropInPaths=${MOCK_REDIS_DROPINS:-}"
      exit 0
    fi
    echo "ExecMainCode=1"
    echo "NRestarts=${MOCK_REDIS_NRESTARTS:-11704}"
    echo "Result=exit-code"
    echo "ActiveEnterTimestamp="
    echo "ExecMainStatus=1"
    echo "ExecMainStartTimestamp=Wed 2026-08-05 22:39:35 UTC"
    exit 0
    ;;
  is-enabled)
    echo "${MOCK_DISTRO_REDIS_ENABLED:-masked}"; exit 1
    ;;
esac
exit 0
MOCK
  chmod +x "$1/systemctl"
}

# Mock journalctl. Emits a synthesized redis crash tail carrying one instance of EVERY secret
# class the extended scrubber must neutralize. No single quotes (the assert helper eval's its
# condition through a single-quoted expansion).
create_journalctl_mock() {
  cat > "$1/journalctl" << 'MOCK'
#!/usr/bin/env bash
if [[ "$*" == *"--header"* ]]; then echo "File path: /var/log/journal/x/system.journal"; exit 0; fi
if [[ "$*" == *"-k"* ]]; then exit 0; fi
if [[ "$*" == *"inngest-redis.service"* ]]; then
  if [[ "${MOCK_REDIS_TAIL_EMPTY:-0}" == "1" ]]; then exit 0; fi
  echo "*** FATAL CONFIG FILE ERROR (Redis 7.0.15) ***"
  echo "Reading the configuration file, at line 12"
  echo ">>> requirepass hunter2synthetic"
  echo "Bad directive or wrong number of arguments"
  echo "connecting to redis://:hunter2synthetic@127.0.0.1:6379 failed"
  echo "Doppler Error: Invalid Auth token dp.st.prd.SYNTHETIC_NOT_A_REAL_TOKEN"
  echo "AUTH hunter2synthetic"
  echo "masterauth hunter2synthetic"
  exit 0
fi
exit 0
MOCK
  chmod +x "$1/journalctl"
}

create_redis_server_mock() {
  mkdir -p "$1/usr/bin"
  cat > "$1/usr/bin/redis-server" << 'MOCK'
#!/usr/bin/env bash
echo "Redis server v=7.0.15 sha=00000000:0 malloc=jemalloc bits=64 build=synthetic"
MOCK
  chmod +x "$1/usr/bin/redis-server"
}

REDIS_MOCK=$(mktemp -d)
create_systemctl_mock "$REDIS_MOCK"
create_journalctl_mock "$REDIS_MOCK"
create_docker_mock "$REDIS_MOCK"
create_redis_server_mock "$REDIS_MOCK"

REDIS_OUT=$(PATH="$REDIS_MOCK:$PATH" \
  SOLEUR_REDIS_SERVER_BIN="$REDIS_MOCK/usr/bin/redis-server" \
  CI_DEPLOY_STATE="$TMP/ok.state" bash "$TARGET")

for k in inngest_redis inngest_redis_journal_tail inngest_redis_result inngest_redis_dropin \
         inngest_redis_credfile inngest_redis_datadir inngest_redis_binary \
         inngest_redis_tail_status vector_config_identity; do
  assert "services.$k is wired" \
    "printf '%s' '$REDIS_OUT' | jq -e '.services | has(\"$k\")' >/dev/null"
done

# The three fields that distinguish "still looping" from "recently fixed". A single `is-active`
# sample on a unit restarting every 5s is a coin flip — #7286 measured `degraded, degraded,
# durable` from three probes 8s apart — so any AC keyed on is-active alone asserts a proxy.
for prop in NRestarts ExecMainStartTimestamp ActiveEnterTimestamp Result ExecMainStatus; do
  assert "inngest_redis_result carries $prop" \
    "printf '%s' '$REDIS_OUT' | jq -r '.services.inngest_redis_result' | grep -qF '$prop='"
done
# By-key parse, NOT positional: the mock returns properties in systemd's canonical order and
# omits MemoryPeak. A positional read would bind NRestarts to whatever sits at that index.
assert "inngest_redis_result binds NRestarts to its VALUE, not a positional neighbour" \
  "printf '%s' '$REDIS_OUT' | jq -r '.services.inngest_redis_result' | grep -qF 'NRestarts=11704'"
assert "inngest_redis_result tolerates an unsupported MemoryPeak (systemd < 253) without shifting" \
  "printf '%s' '$REDIS_OUT' | jq -r '.services.inngest_redis_result' | grep -qF 'Result=exit-code'"

# --- Scrub: no secret class may reach the HTTP response body -----------------
# This is load-bearing, not hygiene. On a config-parse failure redis echoes the offending
# argument VERBATIM, and that is the predicted tail for two of the seven #7286 hypotheses.
# The response body is a different path from Vector's pii_scrub (which covers log SHIPPING),
# so it needs its own coverage.
REDIS_TAIL=$(printf '%s' "$REDIS_OUT" | jq -r '.services.inngest_redis_journal_tail')
for secret in "hunter2synthetic" "SYNTHETIC_NOT_A_REAL_TOKEN"; do
  assert "scrubbed from inngest_redis_journal_tail: $secret" \
    "! printf '%s' \"\$REDIS_TAIL\" | grep -qF '$secret'"
done
assert "the redis tail is non-empty (scrub proves something, not nothing)" \
  "[[ -n \"\$REDIS_TAIL\" ]]"
# The scrubber must be the SHARED one, so hardening it hardens all six tails at once — and so a
# future rule added for one tail cannot silently miss the others. Asserted structurally rather
# than by call-site spelling: exactly ONE unit-journal reader exists in the file (`journalctl -k`
# in container_restart_json is a different, kernel-ring reader and is excluded by the `-u`
# anchor), and the redis tail is assigned from it.
assert "exactly one unit-journal reader exists (no second scrubber was introduced)" \
  "[[ \$(grep -c 'journalctl -u' '$TARGET') == '1' ]]"
# AC2, anchored on the INVOCATION shape rather than on the bare word. A `grep -c journalctl`
# also counts comment prose, a `command -v journalctl` availability guard, and the literal
# string "no-journalctl" — so the bare-token form moves for reasons that are not new calls and
# would force this AC to be restated on every doc edit. Three invocations: the shared unit tail,
# journald_storage_json's --header, and container_restart_json's -k kernel ring. Adding a
# fourth is what this pins against; #7286 added none.
assert "no new standalone journalctl invocation was introduced (exactly 3)" \
  "[[ \$(grep -vE '^[[:space:]]*#' '$TARGET' | grep -cE '(\\\$\\(|^[[:space:]]*|\\|[[:space:]]*)journalctl[[:space:]]+(-|--)') == '3' ]]"
assert "the redis tail is assigned from the shared service_journal_tail" \
  "grep -qE 'INNGEST_REDIS_JOURNAL_TAIL=\"\\\$\\(service_journal_tail' '$TARGET'"

# --- inngest_redis_dropin reads systemd's LOADED view, not the filesystem ----
# A filesystem-presence check here would be a FALSE GREEN: after delivery the file is on disk
# whether or not daemon-reload merged it, so "fix landed and working" and "fix landed inert"
# would be byte-identical. DropInPaths is the only form that adjudicates the credential
# hypothesis rather than restating the push.
assert "inngest_redis_dropin is empty when systemd has loaded no drop-in" \
  "[[ -z \$(printf '%s' '$REDIS_OUT' | jq -r '.services.inngest_redis_dropin') ]]"
REDIS_OUT_LOADED=$(PATH="$REDIS_MOCK:$PATH" \
  MOCK_REDIS_DROPINS="/etc/systemd/system/inngest-redis.service.d/10-inngest-redis-doppler-token.conf" \
  CI_DEPLOY_STATE="$TMP/ok.state" bash "$TARGET")
assert "inngest_redis_dropin names the loaded drop-in by basename" \
  "printf '%s' '$REDIS_OUT_LOADED' | jq -r '.services.inngest_redis_dropin' | grep -qF '10-inngest-redis-doppler-token.conf'"
assert "inngest_redis_dropin emits basenames only (never drop-in CONTENT)" \
  "! printf '%s' '$REDIS_OUT_LOADED' | jq -r '.services.inngest_redis_dropin' | grep -qF 'EnvironmentFile='"

# --- tail_status disambiguates the four states service_journal_tail collapses ---
assert "inngest_redis_tail_status is ok when the tail has content" \
  "[[ \$(printf '%s' '$REDIS_OUT' | jq -r '.services.inngest_redis_tail_status') == 'ok' ]]"
REDIS_OUT_EMPTY=$(PATH="$REDIS_MOCK:$PATH" MOCK_REDIS_TAIL_EMPTY=1 \
  CI_DEPLOY_STATE="$TMP/ok.state" bash "$TARGET")
assert "inngest_redis_tail_status is empty when the unit logged nothing" \
  "[[ \$(printf '%s' '$REDIS_OUT_EMPTY' | jq -r '.services.inngest_redis_tail_status') == 'empty' ]]"

# --- The probe must never be able to take the endpoint down ------------------
# The PR that adds these fields is the same PR that deletes the runbook's last-resort host
# login, so a probe that can 500 the one remaining diagnostic surface would be a strict
# regression.
#
# The fixture removes exactly the three binaries the new fields depend on — systemctl,
# journalctl, redis-server — while keeping the interpreter's own toolchain (jq, coreutils)
# present. A bare empty PATH would ALSO remove jq, and the resulting 127 would say nothing
# about this script's robustness: it would be the harness failing, not the SUT. That
# distinction matters because the over-broad version of this fixture LOOKS stricter.
BARE_PATH_DIR=$(mktemp -d)
for _b in jq sed tr awk basename stat df sha256sum cut head tail date du grep cat timeout env; do
  _p=$(command -v "$_b" 2>/dev/null || true)
  [[ -n "$_p" ]] && ln -sf "$_p" "$BARE_PATH_DIR/$_b"
done
# Precondition self-check: if the loop silently linked nothing, every assertion below would pass
# or fail for reasons unrelated to the SUT.
assert "bare-PATH fixture linked its toolchain (guard against a vacuous fixture)" \
  "[[ -x '$BARE_PATH_DIR/jq' ]]"
assert "bare-PATH fixture genuinely removes systemctl/journalctl/redis-server" \
  "[[ ! -e '$BARE_PATH_DIR/systemctl' && ! -e '$BARE_PATH_DIR/journalctl' && ! -e '$BARE_PATH_DIR/redis-server' ]]"

# The interpreter is resolved BEFORE the narrowed PATH takes effect and is not part of what is
# under test — an unfound `bash` would exit 127 and read as an SUT failure.
BARE_BASH=$(command -v bash)
BARE_RC=0
BARE_OUT=$(PATH="$BARE_PATH_DIR" CI_DEPLOY_STATE="$TMP/ok.state" \
  SOLEUR_REDIS_SERVER_BIN="$BARE_PATH_DIR/redis-server" \
  "$BARE_BASH" "$TARGET" 2>/dev/null) || BARE_RC=$?
assert "exits 0 with systemctl/journalctl/redis-server absent from PATH" "[[ '$BARE_RC' == '0' ]]"
assert "still emits parseable JSON with the redis keys present" \
  "printf '%s' \"\$BARE_OUT\" | jq -e '.services | has(\"inngest_redis\") and has(\"inngest_redis_tail_status\")' >/dev/null"
assert "tail_status reports no-journalctl rather than a bare empty string" \
  "[[ \$(printf '%s' \"\$BARE_OUT\" | jq -r '.services.inngest_redis_tail_status') == 'no-journalctl' ]]"

rm -rf "$REDIS_MOCK" "$BARE_PATH_DIR"

echo ""
echo "=== Results: $PASS/$TOTAL passed, $FAIL failed ==="
if [[ "$FAIL" -gt 0 ]]; then exit 1; fi
