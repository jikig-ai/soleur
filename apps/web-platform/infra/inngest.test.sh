#!/usr/bin/env bash
# Tests for inngest.tf (PR-F follow-up, #3960).
#
# Validates the IaC contract without standing up real providers:
#   - inngest.tf is syntactically valid HCL (`terraform fmt -check` + grep checks).
#   - Required resources are declared (6 random_id, 7 doppler_secret,
#     1 betteruptime_heartbeat, conditional betteruptime_policy).
#   - Distinctness invariants encoded via random_id ensure prd ≠ dev and
#     signing ≠ event by construction.
#   - `betteruptime_policy.inngest` `count` expression is gated on
#     var.betterstack_paid_tier.
#
# `terraform validate` against the live providers is gated to Phase 2 (apply
# time) because it requires `doppler` and `betteruptime` providers initialized
# with real credentials.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INNGEST_TF="$SCRIPT_DIR/inngest.tf"
MAIN_TF="$SCRIPT_DIR/main.tf"
VARS_TF="$SCRIPT_DIR/variables.tf"
OUTPUTS_TF="$SCRIPT_DIR/outputs.tf"
BOOTSTRAP_SH="$SCRIPT_DIR/inngest-bootstrap.sh"

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

echo "=== inngest.tf tests ==="
echo ""

# --- File existence ---
echo "--- File existence ---"
assert "inngest.tf exists"             "[[ -f '$INNGEST_TF' ]]"
assert "main.tf updated with providers" "grep -qE 'DopplerHQ/doppler'    '$MAIN_TF'"
assert "main.tf updated with BetterStack" "grep -qE 'BetterStackHQ/better-uptime' '$MAIN_TF'"
assert "main.tf has doppler provider block" "grep -qE '^provider \"doppler\"' '$MAIN_TF'"
assert "main.tf has betteruptime provider block" "grep -qE '^provider \"betteruptime\"' '$MAIN_TF'"

# --- Variables ---
echo ""
echo "--- Variables (3 new) ---"
assert "doppler_token_tf variable exists"  "grep -qE '^variable \"doppler_token_tf\"'  '$VARS_TF'"
assert "betterstack_api_token variable exists" "grep -qE '^variable \"betterstack_api_token\"' '$VARS_TF'"
assert "betterstack_paid_tier variable exists" "grep -qE '^variable \"betterstack_paid_tier\"' '$VARS_TF'"

# --- random_id resources (6: signing+event × prd+dev + manual-trigger × prd+dev) ---
echo ""
echo "--- random_id resources (6) ---"
assert "random_id.inngest_signing_key_prd" "grep -qE 'resource \"random_id\" \"inngest_signing_key_prd\"' '$INNGEST_TF'"
assert "random_id.inngest_signing_key_dev" "grep -qE 'resource \"random_id\" \"inngest_signing_key_dev\"' '$INNGEST_TF'"
assert "random_id.inngest_event_key_prd"   "grep -qE 'resource \"random_id\" \"inngest_event_key_prd\"'   '$INNGEST_TF'"
assert "random_id.inngest_event_key_dev"   "grep -qE 'resource \"random_id\" \"inngest_event_key_dev\"'   '$INNGEST_TF'"
assert "random_id.inngest_manual_trigger_secret_prd" "grep -qE 'resource \"random_id\" \"inngest_manual_trigger_secret_prd\"' '$INNGEST_TF'"
assert "random_id.inngest_manual_trigger_secret_dev" "grep -qE 'resource \"random_id\" \"inngest_manual_trigger_secret_dev\"' '$INNGEST_TF'"
assert "random_id uses byte_length 32 (>=6)" "[[ \$(grep -c 'byte_length = 32' '$INNGEST_TF') -ge 6 ]]"

# --- doppler_secret resources (7: 4 keys + heartbeat URL prd + 2 manual-trigger) ---
echo ""
echo "--- doppler_secret resources (7) ---"
assert "doppler_secret.inngest_signing_key_prd" "grep -qE 'resource \"doppler_secret\" \"inngest_signing_key_prd\"' '$INNGEST_TF'"
assert "doppler_secret.inngest_signing_key_dev" "grep -qE 'resource \"doppler_secret\" \"inngest_signing_key_dev\"' '$INNGEST_TF'"
assert "doppler_secret.inngest_event_key_prd"   "grep -qE 'resource \"doppler_secret\" \"inngest_event_key_prd\"'   '$INNGEST_TF'"
assert "doppler_secret.inngest_event_key_dev"   "grep -qE 'resource \"doppler_secret\" \"inngest_event_key_dev\"'   '$INNGEST_TF'"
assert "doppler_secret.inngest_heartbeat_url_prd" "grep -qE 'resource \"doppler_secret\" \"inngest_heartbeat_url_prd\"' '$INNGEST_TF'"
assert "doppler_secret.inngest_manual_trigger_secret_prd" "grep -qE 'resource \"doppler_secret\" \"inngest_manual_trigger_secret_prd\"' '$INNGEST_TF'"
assert "doppler_secret.inngest_manual_trigger_secret_dev" "grep -qE 'resource \"doppler_secret\" \"inngest_manual_trigger_secret_dev\"' '$INNGEST_TF'"
assert "INNGEST_MANUAL_TRIGGER_SECRET name present (prd+dev)" "[[ \$(grep -cE 'name[[:space:]]+= \"INNGEST_MANUAL_TRIGGER_SECRET\"' '$INNGEST_TF') -eq 2 ]]"

# Distinctness: signing keys carry signkey-prod-/signkey-test- prefixes ensuring prd ≠ dev.
assert "signkey-prod- prefix on prd signing key" "grep -qE '\"signkey-prod-' '$INNGEST_TF'"
assert "signkey-test- prefix on dev signing key" "grep -qE '\"signkey-test-' '$INNGEST_TF'"

# Every doppler_secret has lifecycle ignore_changes on value (rotation safety).
assert "lifecycle ignore_changes [value] on each doppler_secret" \
  "[[ \$(grep -c 'ignore_changes = \\[value\\]' '$INNGEST_TF') -ge 7 ]]"

# --- BetterStack heartbeat + policy ---
echo ""
echo "--- BetterStack ---"
assert "betteruptime_heartbeat.inngest_prd"   "grep -qE 'resource \"betteruptime_heartbeat\" \"inngest_prd\"' '$INNGEST_TF'"
assert "betteruptime_policy.inngest exists"   "grep -qE 'resource \"betteruptime_policy\" \"inngest\"' '$INNGEST_TF'"
assert "policy count gated on paid_tier"      "grep -qE 'count = var.betterstack_paid_tier \\? 1 : 0' '$INNGEST_TF'"
assert "heartbeat policy_id is ternary on paid_tier" \
  "grep -qE 'policy_id .* var.betterstack_paid_tier' '$INNGEST_TF'"

# --- Outputs ---
echo ""
echo "--- Outputs ---"
assert "inngest_heartbeat_url output (sensitive)" \
  "grep -qzE 'output \"inngest_heartbeat_url\".*sensitive[[:space:]]*=[[:space:]]*true' '$OUTPUTS_TF'"

# --- Inngest CLI locals (Phase 0.3 pin) ---
echo ""
echo "--- Inngest CLI version pin ---"
assert "inngest_cli_version local set"       "grep -qE 'inngest_cli_version *= *\"v[0-9]+\\.[0-9]+\\.[0-9]+\"' '$INNGEST_TF'"
assert "inngest_cli_sha256 local set (64 hex)" "grep -qE 'inngest_cli_sha256 *= *\"[0-9a-f]{64}\"' '$INNGEST_TF'"

# --- Heartbeat unit shape in inngest-bootstrap.sh (#4116) ---
echo ""
echo "--- Heartbeat unit shape (inngest-bootstrap.sh) ---"
assert "inngest-bootstrap.sh exists" "[[ -f '$BOOTSTRAP_SH' ]]"

# Extract the heartbeat unit's heredoc body so the assertions only fire on the
# HEARTBEAT_UNIT block (not the unrelated UNITEOF block for inngest-server).
HEARTBEAT_BLOCK=$(awk '/cat > "\$HEARTBEAT_UNIT" <</,/^HEARTBEATEOF$/' "$BOOTSTRAP_SH")

# Reference the block BY NAME ("$HEARTBEAT_BLOCK"), never by embedding its
# value ('$HEARTBEAT_BLOCK'): the block's comments contain apostrophes
# (e.g. "inngest-server.service's"), which break the single-quoted eval form.
# #6555: the heartbeat unit dropped `--project` — it resolves the Doppler project from
# EnvironmentFile=/etc/default/inngest-server (DOPPLER_PROJECT) at runtime, not a flag. The
# ExecStart is `doppler run --config prd -- ${HEARTBEAT_SCRIPT}` with NO --project.
assert "heartbeat unit uses doppler run --config prd with NO --project (#6555)" \
  "[[ -n \"\$HEARTBEAT_BLOCK\" ]] && printf '%s\n' \"\$HEARTBEAT_BLOCK\" | grep -qE 'run --config prd' && ! printf '%s\n' \"\$HEARTBEAT_BLOCK\" | grep -qE '^ExecStart=.*--project'"
assert "heartbeat unit ExecStart is exactly one line" \
  "[[ \$(printf '%s\n' \"\$HEARTBEAT_BLOCK\" | grep -c '^ExecStart=') -eq 1 ]]"
assert "heartbeat unit ExecStart wraps HEARTBEAT_SCRIPT under doppler run --config prd" \
  "printf '%s\n' \"\$HEARTBEAT_BLOCK\" | grep -qE '^ExecStart=.* run --config prd -- \\\$\\{HEARTBEAT_SCRIPT\\}'"
assert "heartbeat unit reads EnvironmentFile=/etc/default/inngest-server (project delivery, #6555)" \
  "printf '%s\n' \"\$HEARTBEAT_BLOCK\" | grep -qxF 'EnvironmentFile=/etc/default/inngest-server'"
assert "DOPPLER_PROJECT is exported (so inngest-redis-bootstrap.sh inherits it), default soleur" \
  "grep -qF 'export DOPPLER_PROJECT=\"\${DOPPLER_PROJECT:-soleur}\"' '$BOOTSTRAP_SH'"
DOPPLER_BIN_LINE=$(grep -nE 'DOPPLER_BIN=.*command -v doppler' "$BOOTSTRAP_SH" 2>/dev/null | head -1 | cut -d: -f1 || true)
# shellcheck disable=SC2016
# Single-quotes are intentional — the regex matches the literal shell text
# `cat > "$HEARTBEAT_UNIT"` in the bootstrap script's source.
HEARTBEAT_UNIT_LINE=$(grep -nE 'cat > "\$HEARTBEAT_UNIT"' "$BOOTSTRAP_SH" 2>/dev/null | head -1 | cut -d: -f1 || true)
assert "DOPPLER_BIN resolved via command -v before HEARTBEAT_UNIT write" \
  "[[ -n '$DOPPLER_BIN_LINE' && -n '$HEARTBEAT_UNIT_LINE' && '$DOPPLER_BIN_LINE' -lt '$HEARTBEAT_UNIT_LINE' ]]"

# #6536 / FR4: without SyslogIdentifier=, systemd derives SYSLOG_IDENTIFIER from the
# ExecStart basename -> `doppler`, which matches NO vector.toml source. The unit's own
# stderr (doppler's AND curl's) then never leaves the host, and a
# _SYSTEMD_UNIT='inngest-heartbeat.service' query returns zero rows -- the state that made
# 3,724 failures undiagnosable off-box. This retag onto Source 4's `inngest-heartbeat`
# channel is what makes the "no row at all + unit failed" signature readable with no SSH.
assert "heartbeat unit sets SyslogIdentifier=inngest-heartbeat (AC1, #6536)" \
  "printf '%s\n' \"\$HEARTBEAT_BLOCK\" | grep -qE '^SyslogIdentifier=inngest-heartbeat$'"

# #6556 Part 2 — the OnFailure alarm unit (push-less, queryable-only). The heartbeat unit
# declares OnFailure=; the target unit reuses the inngest-heartbeat Source 4 tag and emits a
# bare `logger` ERR line with NO `doppler run` wrapper (a wrapper would hardcode a project,
# wrong on the soleur-inngest host, re-introducing the #6555 project-resolution surface).
assert "heartbeat unit declares OnFailure=inngest-heartbeat-failure-log.service (#6556)" \
  "printf '%s\n' \"\$HEARTBEAT_BLOCK\" | grep -qE '^OnFailure=inngest-heartbeat-failure-log\\.service$'"
FAILLOG_BLOCK=$(awk '/cat > "\$HEARTBEAT_FAILURE_LOG_UNIT" <</,/^FAILLOGEOF$/' "$BOOTSTRAP_SH")
assert "failure-log unit block extraction is non-empty (non-vacuity)" \
  "[[ -n \"\$FAILLOG_BLOCK\" ]]"
assert "failure-log unit is Type=oneshot" \
  "printf '%s\n' \"\$FAILLOG_BLOCK\" | grep -qE '^Type=oneshot$'"
assert "failure-log unit reuses SyslogIdentifier=inngest-heartbeat (no new Source 4 entry)" \
  "printf '%s\n' \"\$FAILLOG_BLOCK\" | grep -qE '^SyslogIdentifier=inngest-heartbeat$'"
# Anchor on the ExecStart LINE (not the whole block, whose comments mention doppler/--project):
# the command must BE /usr/bin/logger and must NOT be a `doppler run`/`--project` wrapper.
FAILLOG_EXECSTART=$(printf '%s\n' "$FAILLOG_BLOCK" | grep -E '^ExecStart=')
assert "failure-log ExecStart is exactly one line" \
  "[[ \$(printf '%s\n' \"\$FAILLOG_BLOCK\" | grep -c '^ExecStart=') -eq 1 ]]"
assert "failure-log ExecStart command is /usr/bin/logger (bare)" \
  "printf '%s\n' \"\$FAILLOG_EXECSTART\" | grep -qE '^ExecStart=/usr/bin/logger '"
assert "failure-log ExecStart carries NO doppler run / --project wrapper (#6555 surface)" \
  "! printf '%s\n' \"\$FAILLOG_EXECSTART\" | grep -qE 'doppler|--project'"
assert "failure-log ExecStart emits at ERR priority on the inngest-heartbeat tag" \
  "printf '%s\n' \"\$FAILLOG_EXECSTART\" | grep -qE '^ExecStart=/usr/bin/logger -t inngest-heartbeat -p err '"

# #6536 ROUND 2: EVERY doppler-wrapped unit MUST set PrivateTmp=true.
#
# Not a style rule — a correctness one. /etc/default/inngest-server sets
# DOPPLER_CONFIG_DIR=/tmp/.doppler for all of them, and cloud-init-inngest.yml's boot
# isolation self-check runs `doppler secrets` as ROOT against that same path
# (cloud-init-inngest.yml:212/226/289), so /tmp/.doppler is ROOT-OWNED from first boot.
# A unit with a private /tmp never sees it and the CLI recreates it as `deploy`; a unit on
# the shared /tmp gets `permission denied`, and `doppler run` dies BEFORE exec — the child
# never runs. That is measured, not theorised: it is verbatim what the heartbeat's channel
# shipped on the fresh host, and it is why this unit failed every 60s for 3 days while its
# two siblings (which already set PrivateTmp) were fine.
#
# ALL-MEMBERS, derived — not a spot-check of the one unit we just fixed. The heartbeat was
# the lone omission out of three; the next doppler unit added here inherits the same trap,
# and nothing else would catch it (the failure is invisible off-box by construction — that
# is #6536's whole thesis). Enumerating from the source means a NEW unit is guarded the day
# it lands, not the day it breaks.
PRIVATE_TMP_VIOLATORS=$(python3 - "$BOOTSTRAP_SH" <<'PYEOF'
import re, sys
src = open(sys.argv[1]).read()
bad = []
# Each unit is written by `cat > "$VAR" <<'MARKER' ... MARKER`.
for m in re.finditer(r'cat > "?\$\{?(\w+)\}?"? <<\'?(\w+EOF)\'?\n(.*?)\n\2', src, re.S):
    var, body = m.group(1), m.group(3)
    if '[Service]' not in body:
        continue
    execstart = re.search(r'^ExecStart=(.*)$', body, re.M)
    if not execstart:
        continue
    # doppler-wrapped = the ExecStart runs the doppler CLI (literally or via ${DOPPLER_BIN}).
    if 'doppler' not in execstart.group(1).lower() and 'DOPPLER_BIN' not in execstart.group(1):
        continue
    if not re.search(r'^PrivateTmp=true$', body, re.M):
        bad.append(var)
print(' '.join(bad))
PYEOF
)
assert "every doppler-wrapped unit sets PrivateTmp=true (#6536 — root-owned /tmp/.doppler kills the child before exec)" \
  "[[ -z '$PRIVATE_TMP_VIOLATORS' ]]"
if [[ -n "$PRIVATE_TMP_VIOLATORS" ]]; then
  echo "        VIOLATORS: $PRIVATE_TMP_VIOLATORS"
  echo "        These units run doppler with DOPPLER_CONFIG_DIR=/tmp/.doppler on the SHARED"
  echo "        /tmp, where cloud-init's root-run boot self-check already created that dir."
  echo "        doppler run will exit 'permission denied' BEFORE exec and the child never runs."
fi
# Non-vacuity: the enumeration must actually FIND the units. A regex that matches nothing
# reports zero violators and passes forever — the exact false-green this guard exists to
# prevent. Three doppler units ship today (heartbeat, inngest-server, vector).
DOPPLER_UNIT_COUNT=$(python3 - "$BOOTSTRAP_SH" <<'PYEOF'
import re, sys
src = open(sys.argv[1]).read()
n = 0
for m in re.finditer(r'cat > "?\$\{?(\w+)\}?"? <<\'?(\w+EOF)\'?\n(.*?)\n\2', src, re.S):
    body = m.group(3)
    if '[Service]' not in body:
        continue
    e = re.search(r'^ExecStart=(.*)$', body, re.M)
    if e and ('doppler' in e.group(1).lower() or 'DOPPLER_BIN' in e.group(1)):
        n += 1
print(n)
PYEOF
)
assert "PrivateTmp guard is non-vacuous: it found >=3 doppler-wrapped units (found $DOPPLER_UNIT_COUNT)" \
  "[[ '$DOPPLER_UNIT_COUNT' -ge 3 ]]"

# --- #6536 / FR3: heartbeat ping-script render split (@@DARK_ARM@@) ---
echo ""
echo "--- Heartbeat ping-script render split (@@DARK_ARM@@, #6536) ---"

PING_TMP="$(mktemp -d)"
trap 'rm -rf "$PING_TMP"' EXIT

# The bearer-URL control: :156-159 indirects the curl through a script file so systemd never
# journals a resolved ExecStart=. That control survives ONLY while the heredoc stays QUOTED --
# unquoting it to expand a dark arm would also expand $INNGEST_HEARTBEAT_URL into a 0755
# world-readable file. AC3's canary asserts runtime OUTPUT, not file CONTENTS, so AC3 is
# structurally blind to that leak. This assertion is the only guard for it.
# shellcheck disable=SC2016
assert "ping-script heredoc is QUOTED (bearer URL never baked into the 0755 file)" \
  "grep -qF 'cat > \"\$HEARTBEAT_SCRIPT\" <<'\"'\"'HEARTBEATSCRIPTEOF'\"'\"'' '$BOOTSTRAP_SH'"

PING_BODY="$PING_TMP/ping-body.sh"
# shellcheck disable=SC2016
awk '/^cat > "\$HEARTBEAT_SCRIPT" <</{f=1;next} /^HEARTBEATSCRIPTEOF$/{f=0} f' \
  "$BOOTSTRAP_SH" > "$PING_BODY"

# Extract the PRODUCTION render block verbatim between its markers and execute it, rather
# than re-typing the sed expressions here: a re-typed copy drifts, and the guard would then
# pass against a broken bootstrap (the drift-guard-extraction-mirrors-the-producer rule).
DARK_ARM_RENDER_BLOCK=$(
  awk '/^# @@DARK_ARM@@ render begin/{f=1;next} /^# @@DARK_ARM@@ render end/{f=0} f' "$BOOTSTRAP_SH"
)

assert "ping-script heredoc body extracted (carries the curl exec)" \
  "[[ -s '$PING_BODY' ]] && grep -qF 'exec /usr/bin/curl' '$PING_BODY'"
# Anchored on the STANDALONE sentinel line, mirroring the production sed's own `^...$`
# anchors: the sentinel is also named in the heredoc's explanatory comment, so a bare-token
# grep would match the prose and pass vacuously against a deleted sentinel.
assert "ping-script carries the @@DARK_ARM@@ sentinel line (render-time split, not a runtime if)" \
  "grep -qE '^@@DARK_ARM@@$' '$PING_BODY'"
assert "@@DARK_ARM@@ render block extracted from the bootstrap (non-empty)" \
  "[[ -n \"\$DARK_ARM_RENDER_BLOCK\" ]] && printf '%s\n' \"\$DARK_ARM_RENDER_BLOCK\" | grep -qF 'sed -i'"

# LOG_TAG must be a REAL assignment, never a bare `logger -t inngest-heartbeat` literal:
# vector-pii-scrub.test.sh:392-404 derives EXPECTED_TAGS from
# `^\s*(readonly\s+)?LOG_TAG="..."` across infra/*.sh, and its `logger -t` probe is
# heredoc-blind -- so a literal pulls this file into the fixture's loop and yields NO tag,
# hard-failing that fixture's exact-set equality.
assert "ping script assigns LOG_TAG=\"inngest-heartbeat\" (drift-fixture contract)" \
  "grep -qE '^LOG_TAG=\"inngest-heartbeat\"$' '$PING_BODY'"
# Anchored on the CALL shape (`logger -t <bare-word>`), not the tag token: the heredoc's own
# comment explains this contract, and a token-grep would false-match that prose.
assert "ping script never inlines the tag literal in a logger call (drift-fixture contract)" \
  "! grep -qE '^[[:space:]]*logger[[:space:]]+-t[[:space:]]+[a-z]' '$PING_BODY'"

# `logger` is PATH-resolved by the ping script, so a stub records the emitted rows.
# `curl` is deliberately NOT stubbed: the script execs the ABSOLUTE /usr/bin/curl, so the
# URL-present cases drive the real binary against a closed loopback port -- rc=7 in ~0ms,
# no DNS and no network, which keeps the leg hermetic in CI.
mkdir -p "$PING_TMP/bin"
cat > "$PING_TMP/bin/logger" <<'LOGGEREOF'
#!/bin/sh
printf '%s\n' "$*" >> "$LOGGER_OUT"
LOGGEREOF
chmod +x "$PING_TMP/bin/logger"

# `log()` is the bootstrap's own stderr helper, defined far above the render block; stub it
# so the extracted block runs standalone. This is the ONLY seam the extraction stubs.
render_ping_script() {
  local project="$1" out="$2"
  cp "$PING_BODY" "$out"
  DOPPLER_PROJECT="$project" HEARTBEAT_SCRIPT="$out" \
    bash -c "log() { :; }; $DARK_ARM_RENDER_BLOCK"
}

run_ping() {
  # $1 = rendered script, $2 = INNGEST_HEARTBEAT_URL, $3 = logger sink
  : > "$3"
  PATH="$PING_TMP/bin:$PATH" LOGGER_OUT="$3" INNGEST_HEARTBEAT_URL="$2" \
    sh "$1" 2>&1
}

DEDICATED_PING="$PING_TMP/ping-dedicated.sh"
WEB_PING="$PING_TMP/ping-web.sh"
render_ping_script "soleur-inngest" "$DEDICATED_PING"
render_ping_script "soleur" "$WEB_PING"

assert "rendered scripts are POSIX-clean under sh -n (both hosts)" \
  "sh -n '$DEDICATED_PING' && sh -n '$WEB_PING'"
assert "no unrendered @@DARK_ARM@@ sentinel LINE survives either render" \
  "! grep -qE '^@@DARK_ARM@@$' '$DEDICATED_PING' && ! grep -qE '^@@DARK_ARM@@$' '$WEB_PING'"
# The sed replacement's own logger call must use "$LOG_TAG" too -- the rendered dedicated
# script is the artifact the drift fixture's contract ultimately has to hold for.
assert "rendered dark arm calls logger via \"\$LOG_TAG\", not an inlined tag literal" \
  "! grep -qE '^[[:space:]]*logger[[:space:]]+-t[[:space:]]+[a-z]' '$DEDICATED_PING'"

# AC5b case 1 -- dedicated render, URL absent: exit 0 + exactly one url_present=no row.
DED_LOG="$PING_TMP/logger-dedicated-absent.txt"
DED_ABSENT_OUT=$(run_ping "$DEDICATED_PING" "" "$DED_LOG") && DED_ABSENT_RC=0 || DED_ABSENT_RC=$?
assert "AC5b/1 dedicated render + URL absent -> exit 0 (was rc=2, the 60s storm)" \
  "[[ '$DED_ABSENT_RC' -eq 0 ]]"
assert "AC5b/1 dedicated render + URL absent -> exactly one url_present=no row (never silent)" \
  "[[ \$(grep -c 'url_present=no' '$DED_LOG') -eq 1 ]]"
assert "AC5b/1 dedicated render + URL absent -> curl never ran (no curl error on output)" \
  "! printf '%s' \"\$DED_ABSENT_OUT\" | grep -qi 'curl'"

# --- #6617b (A6): the dark arm is RATE-LIMITED, not ELIMINATED (plan CF-9) ---
# The dark arm fires every 60s and each fire ships a row through Source 4 (which applies no
# PRIORITY filter): ~1,440 rows/day against a ~25k/day Better Stack quota, for a message whose
# content never changes. The obvious fix -- emit once per boot, or only on transition -- is the
# one ADR-117 forbids: it deletes the positive control, after which a dead pusher and a healthy
# quiet one are the same observation (no rows), which is #6617 itself. So: a LOW PERIODIC
# CADENCE. ~24 rows/day, and the host still says "I am alive and deliberately dark" every hour.
#
# Asserted BEHAVIOURALLY against the real rendered script, not by grepping for a constant: the
# property is "repeat fires inside the window emit once AND the window reopens", and only
# executing it can distinguish rate-limiting from suppression.
echo ""
echo "--- #6617b (A6): dark-arm hourly rate limit (CF-9 positive control preserved) ---"
A6_STAMP="$PING_TMP/a6-run/dark.stamp"
mkdir -p "$(dirname "$A6_STAMP")"
A6_LOG="$PING_TMP/logger-a6.txt"
: > "$A6_LOG"
rm -f "$A6_STAMP"
a6_fire() {
  PATH="$PING_TMP/bin:$PATH" LOGGER_OUT="$A6_LOG" INNGEST_HEARTBEAT_URL="" \
    INNGEST_HEARTBEAT_DARK_STAMP="$A6_STAMP" sh "$DEDICATED_PING" >/dev/null 2>&1
}
a6_fire && A6_RC1=0 || A6_RC1=$?
a6_fire; a6_fire; a6_fire
A6_BURST_ROWS=$(grep -c 'url_present=no' "$A6_LOG" || true)
assert "A6 dark arm still exits 0 (the #6536 storm fix is intact)" \
  "[[ '$A6_RC1' -eq 0 ]]"
assert "A6 four fires inside one window emit exactly ONE row (was one per 60s fire)" \
  "[[ '$A6_BURST_ROWS' -eq 1 ]]"
# CF-9 -- the load-bearing half. Age the stamp past the interval: the marker MUST return. An
# assertion that only checks suppression passes just as happily against "emit once, ever",
# which is the elimination this rejects.
printf '%s' "$(( $(date +%s) - 7200 ))" > "$A6_STAMP"
a6_fire
A6_AFTER_ROWS=$(grep -c 'url_present=no' "$A6_LOG" || true)
assert "A6/CF-9 an aged stamp RE-EMITS (rate-limited, not transition-only/once-per-boot)" \
  "[[ '$A6_AFTER_ROWS' -eq 2 ]]"
# The window is an hour, not an arbitrary number: pin it so a later edit to 24h (which would
# pass both behavioural legs above) has to justify itself.
assert "A6 the dark-arm window is 3600s (hourly)" \
  "grep -qE '^[[:space:]]*_interval=\\\$\\{INNGEST_HEARTBEAT_DARK_INTERVAL:-3600\\}$' '$PING_BODY'"
# ...but that grep pins the ASSIGNMENT LINE, and nothing in it reaches the `-ge "$_interval"`
# comparison the dark arm actually runs. Measured: mutating that comparison to a literal
# `-ge 60` restores the full ~1,440 rows/day bug and still passes 138/138 here, because every
# leg above uses inputs (0s and 7200s) that fall on the same side of both windows.
#
# Half a window is the discriminating input: 1800s is >= 60 but < 3600, so a too-small window
# re-emits and the real one stays silent. Deterministic — the stamp is computed relative to
# now, so there is no sleep and no wall-clock coupling.
printf '%s' "$(( $(date +%s) - 1800 ))" > "$A6_STAMP"
a6_fire
assert "A6/CF-9 a half-window-old stamp does NOT re-emit (the CONSUMED window is >=3600, not 60s)" \
  "[[ \$(grep -c 'url_present=no' '$A6_LOG') -eq 2 ]]"

# The override seam: dark_arm_emit_due declares INNGEST_HEARTBEAT_DARK_INTERVAL, and the test
# harness above names it in a comment, but no leg ever DRIVES it — so a comparison against a
# hardcoded 3600 would satisfy everything so far. Explicit helper rather than a
# `VAR=v a6_fire` prefix: bash leaves assignments that prefix a FUNCTION call set in the shell
# afterwards, which would silently re-window every later leg.
a6_fire_with_interval() {
  PATH="$PING_TMP/bin:$PATH" LOGGER_OUT="$A6_LOG" INNGEST_HEARTBEAT_URL="" \
    INNGEST_HEARTBEAT_DARK_STAMP="$A6_STAMP" INNGEST_HEARTBEAT_DARK_INTERVAL="$1" \
    sh "$DEDICATED_PING" >/dev/null 2>&1
}
# One stamp age, two windows, two outcomes -- that pair is what proves the env var is READ
# rather than decorative. 3s is inside the default window and outside a 2s one.
printf '%s' "$(( $(date +%s) - 3 ))" > "$A6_STAMP"
a6_fire
assert "A6 a 3s-old stamp does NOT re-emit under the DEFAULT window" \
  "[[ \$(grep -c 'url_present=no' '$A6_LOG') -eq 2 ]]"
a6_fire_with_interval 2
assert "A6 the SAME 3s-old stamp DOES re-emit under INNGEST_HEARTBEAT_DARK_INTERVAL=2 (override seam is consumed)" \
  "[[ \$(grep -c 'url_present=no' '$A6_LOG') -eq 3 ]]"
# P3-3: the function's comment claims it FAILS OPEN. That held for read/write failure but NOT
# for a FUTURE-DATED stamp, which is neither. Boot before NTP writes `now+skew`; timesyncd
# steps the clock BACK; `_now - _last` goes NEGATIVE, never reaches the interval, and the
# marker is suppressed for the whole skew — on a host whose liveness signal IS this marker, a
# routine clock correction would read as a dead pusher. 2h ahead is a realistic pre-NTP skew.
printf '%s' "$(( $(date +%s) + 7200 ))" > "$A6_STAMP"
a6_fire
assert "A6/P3-3 a FUTURE-dated stamp (boot-before-NTP, clock stepped back) still emits — fails OPEN" \
  "[[ \$(grep -c 'url_present=no' '$A6_LOG') -eq 4 ]]"
# ...and the recovery write must leave a SANE stamp behind, or the next fire re-enters the
# same suppressed state and the fix only papers over one cycle.
assert "A6/P3-3 the recovering fire overwrites the future stamp with a non-future value" \
  "[[ \$(cat '$A6_STAMP') -le \$(date +%s) ]]"
# The stamp lives in a systemd-managed RuntimeDirectory: the unit runs User=deploy, and /run
# itself is root-owned 0755, so without this the write fails every fire, the rate limit
# silently never engages, and the quota fix is a no-op that tests-in-CI cannot see (the test
# above supplies its own writable dir). RuntimeDirectoryPreserve=yes is equally load-bearing:
# this is a ONESHOT, so systemd would otherwise delete the directory -- and the stamp -- the
# instant it exits, on every single fire.
assert "A6 heartbeat unit declares RuntimeDirectory=inngest-heartbeat (deploy cannot write bare /run)" \
  "printf '%s\n' \"\$HEARTBEAT_BLOCK\" | grep -qE '^RuntimeDirectory=inngest-heartbeat$'"
assert "A6 heartbeat unit declares RuntimeDirectoryPreserve=yes (a oneshot would else drop the stamp each fire)" \
  "printf '%s\n' \"\$HEARTBEAT_BLOCK\" | grep -qE '^RuntimeDirectoryPreserve=yes$'"

# --- #6617b task 1.6.2: this change provisions NO heartbeat URL ---
# Writing the URL early would put TWO pushers on one monitor -- the co-located web host (live
# today) and the dedicated host -- which is precisely the dual-pusher state #6552 exists to
# prevent. Provisioning it is `op=arm`'s job at cutover (G4), and nothing before it.
# Anchored on ASSIGNMENT constructs, not the bare name: this repo is full of prose and
# `name = "INNGEST_HEARTBEAT_URL"` definitions that a token grep would match.
assert "1.6.2 no INNGEST_HEARTBEAT_URL is assigned a literal URL anywhere in infra/" \
  "! grep -rIE '^[^#]*INNGEST_HEARTBEAT_URL[[:space:]]*=[[:space:]]*\"?https?://' '$SCRIPT_DIR'"
# `--exclude=*.test.sh`: zot-liveness-heartbeat.test.sh carries a SYNTHETIC
# `.../heartbeat/synthetic-liveness` fixture (cq-test-fixtures-synthesized-only). Excluding
# the suites keeps this assertion pointed at DELIVERED artifacts -- cloud-init, units,
# bootstrap, HCL -- which is where a baked URL would actually arm a second pusher.
assert "1.6.2 no Better Stack heartbeat URL literal is baked into a delivered infra artifact" \
  "! grep -rIE --exclude='*.test.sh' 'uptime\\.betterstack\\.com/api/v[0-9]+/heartbeat/[A-Za-z0-9]' '$SCRIPT_DIR'"

# AC5b case 3 -- web render, URL absent: NO dark arm, so the absent URL reaches curl and
# exits 2, loudly. This is what makes CPO P1-1 STRUCTURALLY unreachable rather than gated:
# the live co-located pusher's script has no exit-0 branch to reach at all.
assert "AC5b/3 web render carries NO dark arm (no exit-0 branch on the live pusher)" \
  "! grep -qF 'url_present=no' '$WEB_PING'"
WEB_LOG="$PING_TMP/logger-web-absent.txt"
WEB_ABSENT_OUT=$(run_ping "$WEB_PING" "" "$WEB_LOG") && WEB_ABSENT_RC=0 || WEB_ABSENT_RC=$?
# The contract is LOUD (non-zero) and CURL-attributable — NOT a specific exit code. curl's
# empty-URL code is version-dependent: 8.18 exits 2 ("option : blank argument where content is
# expected"), while #4116 recorded exit 3 ("URL using bad/illegal format or missing URL") on an
# older curl. #6536's prod host measured 2, so an `-eq 2` assertion looks right on a modern box
# and hard-fails on any runner shipping an older curl — it pins the AUTHOR'S curl build, not the
# behaviour under test. Both halves are load-bearing:
#   - `-ne 0` is the actual property (the live pusher must not silently succeed with no URL);
#   - `^curl:` proves curl RAN and rejected the URL. Without it a missing binary would exit 127
#     (`sh: exec: /usr/bin/curl: not found` — sh's message, not curl's) and satisfy a bare
#     `-ne 0`, passing this assertion for the one reason that would mean the test proved nothing.
assert "AC5b/3 web render + URL absent -> non-zero AND curl is what rejected it (loud; absent URL on the live pusher is a fault)" \
  "[[ '$WEB_ABSENT_RC' -ne 0 && '$WEB_ABSENT_RC' -ne 127 ]] && printf '%s' \"\$WEB_ABSENT_OUT\" | grep -q '^curl:'"
assert "AC5b/3 web render + URL absent -> emitted no dark-arm row" \
  "[[ ! -s '$WEB_LOG' ]]"

# AC5b case 2 + AC3 (leak gate) -- dedicated render, URL PRESENT: the happy path is
# unchanged (exec curl runs), AND the canary value never appears in stdout+stderr+logger.
# Value-based by design: v2's source-grep caught 1 of 3 leak shapes (it missed the brace
# form ${INNGEST_HEARTBEAT_URL} -- this repo's own house style -- and printf '%s'), and is
# blind to set -x / curl -v / --write-out '%{url}'. Asserting the VALUE's absence in the
# real output cannot be defeated by any of those shapes.
CANARY_URL="http://127.0.0.1:1/api/v1/heartbeat/CANARY_SENTINEL"
DED_PRESENT_LOG="$PING_TMP/logger-dedicated-present.txt"
DED_PRESENT_OUT=$(run_ping "$DEDICATED_PING" "$CANARY_URL" "$DED_PRESENT_LOG") \
  && DED_PRESENT_RC=0 || DED_PRESENT_RC=$?
assert "AC5b/2 dedicated render + URL present -> exec curl runs (rc=7 vs closed port, happy path intact)" \
  "[[ '$DED_PRESENT_RC' -eq 7 ]]"
assert "AC5b/2 dedicated render + URL present -> dark arm NOT taken" \
  "! grep -q 'url_present=no' '$DED_PRESENT_LOG'"
assert "AC3 leak gate: canary value appears ZERO times in stdout+stderr" \
  "[[ \$(printf '%s' \"\$DED_PRESENT_OUT\" | grep -c 'CANARY_SENTINEL') -eq 0 ]]"
assert "AC3 leak gate: canary value appears ZERO times in logger output" \
  "[[ \$(grep -c 'CANARY_SENTINEL' '$DED_PRESENT_LOG') -eq 0 ]]"
# Non-vacuity: prove the canary WOULD be observable if the script leaked it. Without this,
# the two assertions above pass against a harness that simply cannot see the value -- the
# laundered-target/vacuous-green class. Uses the printf leak shape v2's source-grep missed.
assert "AC3 non-vacuity: the harness observes a leaked canary when one IS emitted" \
  "[[ \$(INNGEST_HEARTBEAT_URL='$CANARY_URL' sh -c 'printf \"url=%s\n\" \"\$INNGEST_HEARTBEAT_URL\"' 2>&1 | grep -c CANARY_SENTINEL) -eq 1 ]]"
# Cheap secondary (AC3): no logger/echo/printf line may reference the URL value. Asserted on
# the RENDERED scripts (not the heredoc body) so it also covers the sed replacement's text.
assert "AC3 secondary: no logger/echo/printf line references the URL value (both renders)" \
  "! grep -qE '^[[:space:]]*(logger|echo|printf)[[:space:]].*INNGEST_HEARTBEAT_URL' '$DEDICATED_PING' '$WEB_PING'"

# --- #6617a (A4): the inngest-server POSITIVE liveness probe -------------------------
# The probe ships three artifacts (script, .service, .timer) plus an `enable --now`, and had
# exactly two string assertions against it (both in journald-config.test.sh, both about the
# SyslogIdentifier tag). Measured: deleting the whole timer heredoc AND the enable line AND
# gutting the script body still passed both. That is a positive control with no coverage —
# the same class of hole this probe exists to close.
#
# Behavioural where it can be (the script is executed against stubs, mirroring the heartbeat
# harness above), structural where it must be (unit/timer/enable are systemd's contract).
echo ""
echo "--- #6617a (A4): inngest-server liveness probe (script + unit + timer + enable) ---"

PROBE_BODY="$PING_TMP/probe-body.sh"
# shellcheck disable=SC2016
awk '/^cat > "\$PROBE_SCRIPT" <</{f=1;next} /^PROBESCRIPTEOF$/{f=0} f' "$BOOTSTRAP_SH" > "$PROBE_BODY"
PROBE_UNIT_BLOCK="$(awk '/^cat > "\$PROBE_UNIT" <</{f=1;next} /^PROBEUNITEOF$/{f=0} f' "$BOOTSTRAP_SH")"
PROBE_TIMER_BLOCK="$(awk '/^cat > "\$PROBE_TIMER" <</{f=1;next} /^PROBETIMEREOF$/{f=0} f' "$BOOTSTRAP_SH")"

assert "A4 probe script heredoc body extracted (non-empty)" \
  "[[ -s '$PROBE_BODY' ]]"
assert "A4 probe UNIT block extracted from the bootstrap (non-empty)" \
  "[[ -n \"\$PROBE_UNIT_BLOCK\" ]]"
assert "A4 probe TIMER block extracted from the bootstrap (non-empty)" \
  "[[ -n \"\$PROBE_TIMER_BLOCK\" ]]"

# Oneshot, not simple: a `simple` probe would be considered "running" forever and
# OnUnitActiveSec would never re-arm, silently reducing the hourly probe to one fire per boot.
assert "A4 probe unit is Type=oneshot (a 'simple' unit never re-arms OnUnitActiveSec)" \
  "grep -qE '^Type=oneshot$' <<<\"\$PROBE_UNIT_BLOCK\""
assert "A4 probe unit ExecStart points at the probe script" \
  "grep -qE '^ExecStart=/usr/local/bin/inngest-server-probe\.sh$' <<<\"\$PROBE_UNIT_BLOCK\""

# HOURLY is load-bearing in BOTH directions: Source 4 applies no PRIORITY filter, so a 60s
# cadence would cost ~1,440 rows/day against a ~25k/day quota (the exact cost #6617b is
# removing from the heartbeat in this same change), while a daily cadence would make the
# positive control too coarse to catch a replace that failed to bind :8288.
assert "A4 probe timer re-arms HOURLY (OnUnitActiveSec=1h)" \
  "grep -qE '^OnUnitActiveSec=1h$' <<<\"\$PROBE_TIMER_BLOCK\""
# Reboot survival for a MONOTONIC timer is OnBootSec=, not Persistent=. systemd honours
# Persistent= only for OnCalendar= timers — inngest-bootstrap.sh says so itself about the
# heartbeat timer ("a no-op for a monotonic timer"), so asserting it here would have forced a
# directive systemd ignores into the unit and read as coverage while buying nothing.
# OnBootSec is also the stronger property for this probe: the highest-value fire is the one
# right after a replace.
assert "A4 probe timer fires shortly after every boot (OnBootSec — the monotonic reboot-survival seam)" \
  "grep -qE '^OnBootSec=[0-9]+s?$' <<<\"\$PROBE_TIMER_BLOCK\""
assert "A4 probe timer installs into timers.target (else enable --now is a no-op)" \
  "grep -qE '^WantedBy=timers\.target$' <<<\"\$PROBE_TIMER_BLOCK\""
# A timer that is written but never enabled ships zero rows — indistinguishable from a dead
# host, which is #6617 itself.
assert "A4 bootstrap actually enables the timer (systemctl enable --now inngest-server-probe.timer)" \
  "grep -qE '^systemctl enable --now inngest-server-probe\.timer$' '$BOOTSTRAP_SH'"

# LOG_TAG must be a REAL assignment and the logger call must go through it — same
# drift-fixture contract the heartbeat script is held to above (vector-pii-scrub.test.sh
# derives EXPECTED_TAGS from `LOG_TAG="..."` across infra/*.sh and is heredoc-blind).
# The probe's health URL is a FLEET contract, not a free choice. #6617's review flagged
# /health as an "unverified route" that appears nowhere else and asked for a switch to the
# bare root. That premise is false, and acting on it would have made this probe the only
# :8288 consumer on a different path and desynced it from #6407's watchdog semantics.
# /health is verified against the running router by production evidence:
#   - ci-deploy.sh gates the quiesce probe on `curl -sf http://127.0.0.1:8288/health`; -f
#     FAILS on 404 and a SERVED /health is its "STILL RUNNING" signal, so a 404 route would
#     have wedged the deploy path long ago;
#   - inngest-inventory.sh defaults INNGEST_HEALTH_URL to the same loopback path;
#   - #6407's soak gate calls a `mode=down health_code=200` row a CONTRADICTION, i.e.
#     health_code=200 is routinely observed in prod.
# Pinned on BOTH sides so drift in either direction fails CI rather than silently hardcoding
# http_code to 404 — the unit's own comment calls http_code "the single most diagnostic value
# here", and a permanently-404 positive control is a muted alert, the exact outcome #6617
# exists to prevent.
assert "A4 probe curls the fleet-standard loopback /health route" \
  "grep -qF 'http://127.0.0.1:8288/health' '$PROBE_BODY'"
assert "A4 ci-deploy.sh gates on the SAME loopback /health route (probe is not a lone snowflake)" \
  "grep -qF 'curl -sf --max-time 5 http://127.0.0.1:8288/health' '$SCRIPT_DIR/ci-deploy.sh'"
assert "A4 inngest-inventory.sh defaults INNGEST_HEALTH_URL to the same loopback /health route" \
  "grep -qF 'INNGEST_HEALTH_URL:-http://127.0.0.1:8288/health' '$SCRIPT_DIR/inngest-inventory.sh'"

assert "A4 probe script assigns LOG_TAG=\"inngest-server-probe\" (drift-fixture contract)" \
  "grep -qE '^LOG_TAG=\"inngest-server-probe\"$' '$PROBE_BODY'"
assert "A4 probe script never inlines the tag literal in a logger call (drift-fixture contract)" \
  "! grep -qE '^[[:space:]]*logger[[:space:]]+-t[[:space:]]+[a-z]' '$PROBE_BODY'"

# --- behavioural: execute the probe against stubs ---
# `curl` and `systemctl` are stubbed (the script calls both unqualified, unlike the
# heartbeat's absolute /usr/bin/curl) so the leg is hermetic: no network, no host services.
PROBE_BIN="$PING_TMP/probe-bin"
mkdir -p "$PROBE_BIN"
cp "$PING_TMP/bin/logger" "$PROBE_BIN/logger"
# Exit 7 + empty stdout = "could not connect", the realistic failure the probe must survive.
cat > "$PROBE_BIN/curl" <<'CURLEOF'
#!/bin/sh
exit 7
CURLEOF
cat > "$PROBE_BIN/systemctl" <<'SYSTEMCTLEOF'
#!/bin/sh
echo active
SYSTEMCTLEOF
chmod +x "$PROBE_BIN/curl" "$PROBE_BIN/systemctl"

PROBE_LOG="$PING_TMP/logger-probe.txt"
: > "$PROBE_LOG"
PATH="$PROBE_BIN:$PATH" LOGGER_OUT="$PROBE_LOG" sh "$PROBE_BODY" >/dev/null 2>&1 \
  && PROBE_RC=0 || PROBE_RC=$?

assert "A4 probe script is POSIX-clean under sh -n" \
  "sh -n '$PROBE_BODY'"
assert "A4 probe exits 0 even when curl cannot connect (observability, never a gate)" \
  "[[ '$PROBE_RC' -eq 0 ]]"
# The whole point of the unit: exactly ONE marker row per fire, unconditionally.
assert "A4 probe emits exactly one SOLEUR_INNGEST_SERVER_PROBE marker per fire" \
  "[[ \$(grep -c 'SOLEUR_INNGEST_SERVER_PROBE' '$PROBE_LOG') -eq 1 ]]"
# The stub records logger's full argv, so this pins the RESOLVED tag: `-t <tag>` proves
# "$LOG_TAG" expanded to the value vector.toml's Source 4 allowlist matches on. A tag that
# drifts from that allowlist is a silent no-op — the marker never leaves the host (#6536).
assert "A4 probe emits the marker under the resolved inngest-server-probe tag (logger -t \"\$LOG_TAG\")" \
  "grep -qE '^-t inngest-server-probe SOLEUR_INNGEST_SERVER_PROBE ' '$PROBE_LOG'"
# A degraded capture must degrade a FIELD, never the event: curl exited 7 with no stdout, and
# http_code — the unit's own comment calls it "the single most diagnostic value here" — must
# still be a VALUE (000), not an empty field that reads as missing data.
assert "A4 a failed curl degrades http_code to the literal 000, not to an empty field" \
  "grep -qE 'http_code=000( |\$)' '$PROBE_LOG'"
# Every field present and non-empty. An empty field silently reads as "no data" in Better
# Stack, which is the same ambiguity a missing row creates.
for _f in server_active vector_active redis_active uptime_s boot_id image_ref; do
  assert "A4 probe marker carries a non-empty $_f= field" \
    "grep -qE '$_f=[^ ]+' '$PROBE_LOG'"
done
# The field is named for what it CONTAINS. cloud-init-inngest.yml writes
# INNGEST_BOOTSTRAP_IMAGE=$IREF, and $IREF is the FULL ref (registry/repo:tag@sha256:...), not
# a bare digest. Under the old `image_sha=` name a Better Stack consumer keying on
# `image_sha=sha256:` matched nothing, forever — a silent gap of exactly the class this probe
# exists to close. Both sides pinned so a rename on either drifts loudly.
assert "A4 the image field is named image_ref (it carries a full ref, not a bare sha)" \
  "grep -qE 'image_ref=' '$PROBE_LOG' && ! grep -qE 'image_sha=' '$PROBE_LOG'"
assert "A4 cloud-init writes INNGEST_BOOTSTRAP_IMAGE from the full \$IREF (what image_ref reports)" \
  "grep -qF \"printf 'INNGEST_BOOTSTRAP_IMAGE=%s\\\\n' \\\"\\\$IREF\\\"\" '$SCRIPT_DIR/cloud-init-inngest.yml'"

# --- P2-B: vector_active is unobservable through the channel it describes ---
# This marker reaches Better Stack via journald -> Vector Source 4. So vector_active is the ONE
# field whose only off-box path is Vector ITSELF: precisely when it carries information
# (Vector down), the row cannot ship, and the result is indistinguishable from a dead host —
# the #6536 ambiguity. The non-active branch must therefore ALSO fire the direct-curl
# phone-home, which bypasses Vector entirely.
#
# The probe calls the emitter by ABSOLUTE path, so the leg runs a copy with that path rewritten
# to a stub. Rewriting (not stubbing PATH) is what keeps the assertion honest: it proves the
# script invokes THAT path, not merely some command named phone-home.
PROBE_PH_LOG="$PING_TMP/probe-phonehome.txt"
: > "$PROBE_PH_LOG"
cat > "$PROBE_BIN/phone-home-stub.sh" <<PHSTUBEOF
#!/bin/sh
printf '%s\n' "\$*" >> "$PROBE_PH_LOG"
exit 0
PHSTUBEOF
chmod +x "$PROBE_BIN/phone-home-stub.sh"
PROBE_PH_BODY="$PING_TMP/probe-body-phonehome.sh"
sed "s#/usr/local/bin/inngest-boot-phone-home.sh#$PROBE_BIN/phone-home-stub.sh#g" \
  "$PROBE_BODY" > "$PROBE_PH_BODY"

# Vector DOWN: systemctl reports inactive for vector.service, active for everything else.
cat > "$PROBE_BIN/systemctl" <<'SYSDOWNEOF'
#!/bin/sh
case "$*" in *vector.service*) echo inactive ;; *) echo active ;; esac
SYSDOWNEOF
chmod +x "$PROBE_BIN/systemctl"
PROBE_DOWN_LOG="$PING_TMP/logger-probe-vector-down.txt"
: > "$PROBE_DOWN_LOG"
PATH="$PROBE_BIN:$PATH" LOGGER_OUT="$PROBE_DOWN_LOG" sh "$PROBE_PH_BODY" >/dev/null 2>&1 \
  && PROBE_DOWN_RC=0 || PROBE_DOWN_RC=$?

assert "P2-B probe still exits 0 with Vector down (second channel is never a gate)" \
  "[[ '$PROBE_DOWN_RC' -eq 0 ]]"
# ADR-117: the unconditional journald emit happens REGARDLESS. The new `if` sits after it and
# adds a channel; it must not have become a branch that replaces the emit.
assert "P2-B the unconditional journald emit STILL fires with Vector down (ADR-117 intact)" \
  "[[ \$(grep -c 'SOLEUR_INNGEST_SERVER_PROBE' '$PROBE_DOWN_LOG') -eq 1 ]]"
assert "P2-B vector_active=inactive ALSO reaches the Vector-independent phone-home channel" \
  "[[ -s '$PROBE_PH_LOG' ]] && grep -qF 'vector_active=inactive' '$PROBE_PH_LOG'"
# Same fields on both channels — an off-box consumer reading only the phone-home row must be
# able to make the same call as one reading the journald row.
for _f in http_code server_active redis_active uptime_s boot_id image_ref; do
  assert "P2-B the phone-home payload carries the same $_f= field as the journald marker" \
    "grep -qE '$_f=[^ ]+' '$PROBE_PH_LOG'"
done

# Vector UP: the second channel must stay silent, or the steady-state row cost is not zero and
# this fix re-creates the quota problem #6617b is removing.
cat > "$PROBE_BIN/systemctl" <<'SYSUPEOF'
#!/bin/sh
echo active
SYSUPEOF
chmod +x "$PROBE_BIN/systemctl"
: > "$PROBE_PH_LOG"
PATH="$PROBE_BIN:$PATH" LOGGER_OUT="$PING_TMP/logger-probe-vector-up.txt" \
  sh "$PROBE_PH_BODY" >/dev/null 2>&1
assert "P2-B a HEALTHY vector fires NO phone-home (second channel costs zero in steady state)" \
  "[[ ! -s '$PROBE_PH_LOG' ]]"
# The guard that keeps this fail-open on the co-located web host, where the emitter is absent.
assert "P2-B the phone-home call is guarded by [ -x ] (absent emitter must not fail the probe)" \
  "grep -qF '[ -x /usr/local/bin/inngest-boot-phone-home.sh ]' '$PROBE_BODY'"

# --- Inngest-SERVER unit ExecStart: poll-interval + sdk-url (#4652) ---
echo ""
echo "--- Inngest-server unit ExecStart (#4652 poll-interval/sdk-url) ---"
# Extract the inngest-SERVER unit's heredoc body (single-quoted 'UNITEOF'
# marker, distinct from the heartbeat HEARTBEATEOF block). Start anchor is the
# literal `cat > "$UNIT_FILE" <<'UNITEOF'`; end anchor is a line that is exactly
# `UNITEOF` (no self-match — the start line ends in `<<'UNITEOF'`, not `UNITEOF`
# alone).
# shellcheck disable=SC2016
SERVER_UNIT_BLOCK=$(awk '/cat > "\$UNIT_FILE" <</,/^UNITEOF$/' "$BOOTSTRAP_SH")
# Reference BY NAME ("$SERVER_UNIT_BLOCK") — the server ExecStart contains
# single quotes (`bash -c '...'`), so the value-embedded '$VAR' form would
# break the eval (same fragility fixed in the heartbeat assert above).
assert "inngest-server unit block extracted (non-empty)" \
  "[[ -n \"\$SERVER_UNIT_BLOCK\" ]] && [[ \$(printf '%s\n' \"\$SERVER_UNIT_BLOCK\" | wc -l) -ge 5 ]]"
# AC1: each new flag asserted independently (flag-order-insensitive).
assert "server ExecStart sets --poll-interval 60" \
  "printf '%s\n' \"\$SERVER_UNIT_BLOCK\" | grep -qE 'inngest start .*--poll-interval 60'"
# #6178: --sdk-url is now TEMPLATED (@@SDK_URL@@ sentinel, same bash-param-expansion
# mechanism as @@BACKEND_*@@) so the dedicated inngest host can point at a remote web
# backend's private interface. The heredoc carries the sentinel; a substitution strips
# it; the SDK_URL DEFAULT preserves the exact co-located loopback literal (the web-host
# regression guard — cross-consumer behavior-preservation, hr-type-widening-cross-consumer-grep).
assert "server ExecStart carries the @@SDK_URL@@ sentinel (templated, #6178)" \
  "printf '%s\n' \"\$SERVER_UNIT_BLOCK\" | grep -qF 'sdk-url @@SDK_URL@@'"
assert "the @@SDK_URL@@ sentinel is substituted (bash param expansion, not sed)" \
  "grep -qE '@@SDK_URL@@/' \"\$BOOTSTRAP_SH\""
assert "SDK_URL default PRESERVES the co-located loopback app route (web regression guard, #6178)" \
  "grep -qF 'SDK_URL=\"\${SDK_URL:-http://127.0.0.1:3000/api/inngest}\"' \"\$BOOTSTRAP_SH\""
# #6555: the server ExecStart dropped `--project` — it resolves the Doppler project from
# EnvironmentFile=/etc/default/inngest-server (DOPPLER_PROJECT) at runtime, not a sentinel flag.
assert "server ExecStart is doppler run --config prd with NO --project (#6555)" \
  "printf '%s\n' \"\$SERVER_UNIT_BLOCK\" | grep -qF 'run --config prd' && ! printf '%s\n' \"\$SERVER_UNIT_BLOCK\" | grep -qE '^ExecStart=.*--project'"
# No @@DOPPLER_PROJECT@@ SUBSTITUTION (`${var//@@DOPPLER_PROJECT@@/...}`) survives anywhere in the
# bootstrap — a lingering render mechanism could silently re-introduce a hardcoded --project.
# Anchored on the substitution syntax, NOT the bare sentinel (comments legitimately name it).
assert "no @@DOPPLER_PROJECT@@ substitution mechanism remains in bootstrap (#6555)" \
  "! grep -qF '//@@DOPPLER_PROJECT@@/' \"\$BOOTSTRAP_SH\""
assert "DOPPLER_PROJECT default PRESERVES 'soleur' for the co-located web host (regression guard, #6178)" \
  "grep -qF 'DOPPLER_PROJECT=\"\${DOPPLER_PROJECT:-soleur}\"' \"\$BOOTSTRAP_SH\""
# Regression guard: the signing-key strip survives the edit as an ENV export (#5560 —
# inngest reads INNGEST_SIGNING_KEY from env; the `signkey-prod-` strip is preserved so
# the self-hosted server gets the bare hex). The systemd `$$` escape must not be
# accidentally unescaped (Sharp Edge). INNGEST_EVENT_KEY is no longer on the ExecStart
# at all (read from the doppler env by name) — asserted absent by the #5560 security
# invariant below.
assert "server ExecStart re-exports the stripped signing-key (env-delivered, #5560)" \
  "printf '%s\n' \"\$SERVER_UNIT_BLOCK\" | grep -qF 'export INNGEST_SIGNING_KEY=\"\$\${INNGEST_SIGNING_KEY#signkey-prod-}\"'"
# --- #5547 Gap 2: REDIS_READY-gated durable/SQLite-fail-safe ExecStart ---
# The durable backend flags (#5450) moved OUT of the single-quoted server-unit
# heredoc into a REDIS_READY-gated BACKEND_FLAGS fragment that is substituted
# into the written unit (the heredoc carries a literal @@BACKEND_FLAGS@@
# sentinel). This keeps inngest-server AVAILABLE on a SQLite-only ExecStart when
# Redis is unprovisioned instead of crash-looping on 127.0.0.1:6379 (the ~3.5h
# #5542 outage). The asserts below therefore scope the durable-flag checks to
# the fragment ASSIGNMENT line, not SERVER_UNIT_BLOCK (AC8 reconcile).
echo ""
echo "--- #5547 Gap 2: REDIS_READY-gated durable/SQLite ExecStart fragment ---"

# AC2 — REDIS_READY is assigned AFTER the /etc/default/inngest-server env-file
# materialization (the Redis unit reads it for the Doppler-injected password —
# the load-bearing ordering dependency) AND BEFORE the server-unit cat> (so the
# substitution can branch the ExecStart on it).
ENV_FILE_LINE=$(grep -nE 'cat > /etc/default/inngest-server <<DOPPLEREOF' "$BOOTSTRAP_SH" | head -1 | cut -d: -f1 || true)
REDIS_READY_LINE=$(grep -nE '^[[:space:]]*REDIS_READY=' "$BOOTSTRAP_SH" | head -1 | cut -d: -f1 || true)
SERVER_CAT_LINE=$(grep -nE 'cat > "\$UNIT_FILE" <<' "$BOOTSTRAP_SH" | head -1 | cut -d: -f1 || true)
TOTAL=$((TOTAL + 1))
if [[ -n "$ENV_FILE_LINE" && -n "$REDIS_READY_LINE" && -n "$SERVER_CAT_LINE" \
      && "$ENV_FILE_LINE" -lt "$REDIS_READY_LINE" && "$REDIS_READY_LINE" -lt "$SERVER_CAT_LINE" ]]; then
  PASS=$((PASS + 1))
  echo "  PASS: REDIS_READY assigned after env-file materialization, before server-unit cat> (#5547 AC2)"
else
  FAIL=$((FAIL + 1))
  echo "  FAIL: ordering env-file($ENV_FILE_LINE) < REDIS_READY($REDIS_READY_LINE) < server-cat($SERVER_CAT_LINE) (#5547 AC2)"
fi

# AC3 — the heredoc carries BOTH the @@BACKEND_ENV@@ and @@BACKEND_FLAGS@@ sentinels
# on the inngest start line, --sqlite-dir /var/lib/inngest is in the SHARED prefix
# (present in BOTH branches), and a (non-sed) substitution strips each sentinel so
# none survives in the written unit (#5547 AC3 + #5560 env-delivery).
ENV_SENTINEL_IN_HEREDOC=$(printf '%s\n' "$SERVER_UNIT_BLOCK" | grep -cE '@@BACKEND_ENV@@exec /usr/local/bin/inngest start' || true)
FLAGS_SENTINEL_IN_HEREDOC=$(printf '%s\n' "$SERVER_UNIT_BLOCK" | grep -cE 'inngest start .*@@BACKEND_FLAGS@@' || true)
SQLITE_IN_HEREDOC=$(printf '%s\n' "$SERVER_UNIT_BLOCK" | grep -cF -- '--sqlite-dir /var/lib/inngest' || true)
ENV_SUBST=$(grep -cE '@@BACKEND_ENV@@/' "$BOOTSTRAP_SH" || true)
FLAGS_SUBST=$(grep -cE '@@BACKEND_FLAGS@@/' "$BOOTSTRAP_SH" || true)
TOTAL=$((TOTAL + 1))
if [[ "$ENV_SENTINEL_IN_HEREDOC" -ge 1 && "$FLAGS_SENTINEL_IN_HEREDOC" -ge 1 && "$SQLITE_IN_HEREDOC" -ge 1 && "$ENV_SUBST" -ge 1 && "$FLAGS_SUBST" -ge 1 ]]; then
  PASS=$((PASS + 1))
  echo "  PASS: heredoc carries @@BACKEND_ENV@@ + @@BACKEND_FLAGS@@ sentinels + --sqlite-dir shared prefix; both substitutions strip them (#5547 AC3 / #5560)"
else
  FAIL=$((FAIL + 1))
  echo "  FAIL: AC3 (env_sentinel=$ENV_SENTINEL_IN_HEREDOC flags_sentinel=$FLAGS_SENTINEL_IN_HEREDOC sqlite_shared=$SQLITE_IN_HEREDOC env_subst=$ENV_SUBST flags_subst=$FLAGS_SUBST)"
fi

# Durable env + flags (#5450/#5560 build-time guard, reconciled to the env-delivery
# shape — AC8). Secrets are delivered via the ENVIRONMENT, never argv: the durable
# BACKEND_ENV exports INNGEST_REDIS_URI from the password (loopback :6379, NEVER the
# pooler :6543); the durable BACKEND_FLAGS carries ONLY the non-secret
# --postgres-max-open-conns sentinel (NO --postgres-uri/--redis-uri flags).
DURABLE_ENV=$(grep -E "^[[:space:]]*BACKEND_ENV='export INNGEST_REDIS_URI=" "$BOOTSTRAP_SH" | head -1 || true)
DURABLE_FLAGS=$(grep -E "^[[:space:]]*BACKEND_FLAGS='--postgres-max-open-conns" "$BOOTSTRAP_SH" | head -1 || true)
TOTAL=$((TOTAL + 1))
if printf '%s\n' "$DURABLE_ENV" | grep -qF -- 'export INNGEST_REDIS_URI="redis://:' \
   && printf '%s\n' "$DURABLE_ENV" | grep -qF -- '@127.0.0.1:6379' \
   && ! printf '%s\n' "$DURABLE_ENV" | grep -qF ':6543' \
   && printf '%s\n' "$DURABLE_FLAGS" | grep -qE -- '--postgres-max-open-conns [0-9]+' \
   && ! printf '%s\n' "$DURABLE_FLAGS" | grep -qE -- '--(postgres|redis)-uri'; then
  PASS=$((PASS + 1))
  echo "  PASS: durable backend delivers INNGEST_REDIS_URI via env (loopback :6379, never :6543); BACKEND_FLAGS is sentinel-only, no secret flags (#5450/#5560)"
else
  FAIL=$((FAIL + 1))
  echo "  FAIL: durable env/flags shape (env: $DURABLE_ENV | flags: $DURABLE_FLAGS)"
fi

# #6258 AC1 — the durable BACKEND_FLAGS bounds TOTAL Postgres footprint + drains idle
# conns: it carries all THREE pool knobs, with --postgres-max-open-conns FIRST (the
# durability sentinel; the parsers use a substring match but this test + the #5560
# drift-guard anchor on the flag being first). Conservative fixed values safe for any
# per-subsystem pool count P ≤ 4 (worst-case total 4×5 = 20 < pool_size 30). NOTE the
# unit trap (#6258, verified against inngest v1.19.4 cmd/start): --postgres-conn-max-idle-time
# is an IntFlag in MINUTES (default 5), NOT seconds — so `1` = drain idle conns after 1 min
# (fast release of the pinned Supavisor session), NOT the plan's mis-labelled "30s".
DURABLE_FLAGS_FULL=$(grep -E "^[[:space:]]*BACKEND_FLAGS='--postgres-max-open-conns" "$BOOTSTRAP_SH" | head -1 || true)
TOTAL=$((TOTAL + 1))
if printf '%s\n' "$DURABLE_FLAGS_FULL" | grep -qE -- "BACKEND_FLAGS='--postgres-max-open-conns 5 --postgres-max-idle-conns 2 --postgres-conn-max-idle-time 1'"; then
  PASS=$((PASS + 1))
  echo "  PASS: durable BACKEND_FLAGS bounds total footprint (open 5 / idle 2 / idle-time 1min), sentinel --postgres-max-open-conns FIRST (#6258 AC1)"
else
  FAIL=$((FAIL + 1))
  echo "  FAIL: durable BACKEND_FLAGS must be '--postgres-max-open-conns 5 --postgres-max-idle-conns 2 --postgres-conn-max-idle-time 1' (sentinel first) (#6258 AC1) — got: $DURABLE_FLAGS_FULL"
fi

# AC4 — the durable env fragment preserves the LITERAL $${INNGEST_REDIS_PASSWORD}
# Doppler token, and the ExecStart re-exports the stripped $${INNGEST_SIGNING_KEY}
# (systemd unescapes $$→$, then bash -c expands the doppler-injected env). grep -F
# single-quoted so the $$ is matched literally (never the shell PID). #5560: the
# postgres URI + event key are read from the env by name with NO bootstrap token.
EXECSTART_LINE=$(grep -E '^ExecStart=.*doppler run' "$BOOTSTRAP_SH" | head -1 || true)
TOTAL=$((TOTAL + 1))
if printf '%s\n' "$DURABLE_ENV" | grep -qF '$${INNGEST_REDIS_PASSWORD}' \
   && printf '%s\n' "$EXECSTART_LINE" | grep -qF '$${INNGEST_SIGNING_KEY#signkey-prod-}'; then
  PASS=$((PASS + 1))
  echo "  PASS: durable env preserves literal \$\${INNGEST_REDIS_PASSWORD}; ExecStart re-exports stripped \$\${INNGEST_SIGNING_KEY} (#5560 AC4)"
else
  FAIL=$((FAIL + 1))
  echo "  FAIL: must preserve literal \$\${INNGEST_REDIS_PASSWORD} (env: $DURABLE_ENV) + \$\${INNGEST_SIGNING_KEY} re-export (execstart: $EXECSTART_LINE)"
fi

# #5560 SECURITY INVARIANT (negative): the ExecStart template carries NO secret on
# argv — no --signing-key/--event-key flags, and no --postgres-uri/--redis-uri flags
# (those are env-delivered). The only $${...} on the ExecStart line is the signing-key
# re-export (an env export, not an argv flag).
TOTAL=$((TOTAL + 1))
if printf '%s\n' "$EXECSTART_LINE" | grep -qF 'exec /usr/local/bin/inngest start' \
   && ! printf '%s\n' "$EXECSTART_LINE" | grep -qE -- '--signing-key|--event-key' \
   && ! printf '%s\n' "$EXECSTART_LINE" | grep -qE -- '--(postgres|redis)-uri'; then
  PASS=$((PASS + 1))
  echo "  PASS: ExecStart passes NO secret on argv (no --signing-key/--event-key/--postgres-uri/--redis-uri); uses exec (#5560 security invariant)"
else
  FAIL=$((FAIL + 1))
  echo "  FAIL: ExecStart must carry no secret flags + use exec (line: $EXECSTART_LINE)"
fi

# SQLite-only fail-safe: an EMPTY BACKEND_FLAGS + an `unset INNGEST_POSTGRES_URI`
# BACKEND_ENV are assigned when Redis is not ready, so the written ExecStart omits
# the durable sentinel AND inngest does not pick up INNGEST_POSTGRES_URI from the
# doppler env (the unset is load-bearing — #5560). inngest stays available on SQLite
# (verify_inngest_health then SKIPs the durable gate).
TOTAL=$((TOTAL + 1))
if grep -qE "^[[:space:]]*BACKEND_FLAGS=(''|\"\")[[:space:]]*\$" "$BOOTSTRAP_SH" \
   && grep -qE "^[[:space:]]*BACKEND_ENV='unset INNGEST_POSTGRES_URI; '" "$BOOTSTRAP_SH"; then
  PASS=$((PASS + 1))
  echo "  PASS: SQLite-only fail-safe assigns empty BACKEND_FLAGS + 'unset INNGEST_POSTGRES_URI' BACKEND_ENV when REDIS_READY=0 (#5547 AC3 / #5560)"
else
  FAIL=$((FAIL + 1))
  echo "  FAIL: fail-safe must set empty BACKEND_FLAGS AND unset INNGEST_POSTGRES_URI (#5547/#5560)"
fi

# AC2: an ExecStart change must take effect on redeploy. Two guarantees:
#   (a) reconcile-always — the server unit write lives OUTSIDE the
#       SKIP_BINARY_INSTALL guard (so a same-CLI-version redeploy still
#       rewrites the unit), matching the heartbeat/Vector precedent; and
#   (b) explicit `systemctl restart inngest-server.service` (a running unit
#       ignores a new ExecStart until restart — the Vector enable→restart fix).
echo ""
echo "--- Inngest-server unit reconcile-always + restart (#4652 AC2) ---"
# shellcheck disable=SC2016
GUARD_CLOSE_LINE=$(grep -nE '^fi  # end SKIP_BINARY_INSTALL guard' "$BOOTSTRAP_SH" 2>/dev/null | head -1 | cut -d: -f1 || true)
# shellcheck disable=SC2016
SERVER_UNIT_WRITE_LINE=$(grep -nE 'cat > "\$UNIT_FILE" <<' "$BOOTSTRAP_SH" 2>/dev/null | head -1 | cut -d: -f1 || true)
assert "server unit write is OUTSIDE the SKIP_BINARY_INSTALL guard (reconcile-always)" \
  "[[ -n '$GUARD_CLOSE_LINE' && -n '$SERVER_UNIT_WRITE_LINE' && '$GUARD_CLOSE_LINE' -lt '$SERVER_UNIT_WRITE_LINE' ]]"
assert "bootstrap restarts inngest-server.service (new ExecStart loads on redeploy)" \
  "grep -qE '^systemctl restart inngest-server.service' '$BOOTSTRAP_SH'"
# The upgrade-drain resume must still run after the restart (R2 — restart must
# not orphan the pause/resume pairing). Match the actual resume COMMAND
# (`"$INSTALL_PATH" resume`) precisely — no broad `|| grep resume` fallback,
# which would vacuously pass on any comment line merely mentioning "resume".
assert "upgrade-drain resume command still present (pause/resume pairing intact)" \
  "grep -qE '\"\\\$INSTALL_PATH\" resume' '$BOOTSTRAP_SH'"

# --- Durable backend assets (#5450) ---
echo ""
echo "--- Durable backend: Redis assets + secrets (#5450) ---"
REDIS_CONF="$SCRIPT_DIR/inngest-redis.conf"
REDIS_SERVICE="$SCRIPT_DIR/inngest-redis.service"
REDIS_BOOTSTRAP="$SCRIPT_DIR/inngest-redis-bootstrap.sh"
assert "inngest-redis.conf exists"        "[[ -f '$REDIS_CONF' ]]"
assert "inngest-redis.service exists"     "[[ -f '$REDIS_SERVICE' ]]"
assert "inngest-redis-bootstrap.sh exists + executable" "[[ -x '$REDIS_BOOTSTRAP' ]]"
# redis.conf required durability settings (AC).
assert "redis.conf appendonly yes"        "grep -qE '^appendonly yes' '$REDIS_CONF'"
assert "redis.conf appendfsync everysec"  "grep -qE '^appendfsync everysec' '$REDIS_CONF'"
assert "redis.conf maxmemory-policy noeviction" "grep -qE '^maxmemory-policy noeviction' '$REDIS_CONF'"
assert "redis.conf bounds maxmemory"      "grep -qE '^maxmemory [0-9]' '$REDIS_CONF'"
assert "redis.conf bounds AOF rewrite"    "grep -qE '^auto-aof-rewrite-percentage' '$REDIS_CONF' && grep -qE '^auto-aof-rewrite-min-size' '$REDIS_CONF'"
assert "redis.conf dir on /mnt/data"      "grep -qE '^dir /mnt/data/redis' '$REDIS_CONF'"
assert "redis.conf loopback bind"         "grep -qE '^bind 127.0.0.1' '$REDIS_CONF'"
# The unit MUST pin to the persistent mount (architecture P1-2) + inject the
# password via doppler (never a literal in the file).
assert "redis.service RequiresMountsFor=/mnt/data" "grep -qE '^RequiresMountsFor=/mnt/data' '$REDIS_SERVICE'"
assert "redis.service requirepass injected from Doppler" "grep -qF 'requirepass \"\$INNGEST_REDIS_PASSWORD\"' '$REDIS_SERVICE'"
# #6555: the redis.service ExecStart dropped `--project` — it resolves the Doppler project from
# EnvironmentFile=/etc/default/inngest-server (DOPPLER_PROJECT) at runtime. The bootstrap installs
# the unit verbatim (no @@DOPPLER_PROJECT@@ substitution round-trip).
assert "redis.service runs under doppler run --config prd with NO --project (#6555)" \
  "grep -qF 'doppler run --config prd' '$REDIS_SERVICE' && ! grep -qE '^ExecStart=.*--project' '$REDIS_SERVICE'"
assert "redis.service reads EnvironmentFile=/etc/default/inngest-server (project delivery, #6555)" \
  "grep -qxF 'EnvironmentFile=/etc/default/inngest-server' '$REDIS_SERVICE'"
assert "inngest-redis-bootstrap.sh no longer renders a @@DOPPLER_PROJECT@@ substitution (#6555)" \
  "! grep -qF '//@@DOPPLER_PROJECT@@/' '$SCRIPT_DIR/inngest-redis-bootstrap.sh'"
# #5450 F1 regression guard: the conf MUST live under /mnt/data/redis, NOT
# /etc/redis — on the existing-host deploy the bootstrap runs inside
# webhook.service's ProtectSystem=strict namespace where /etc is read-only and
# only ReadWritePaths (incl. /mnt/data) are writable. A conf install to
# /etc/redis fails-closed at cutover. Lock both the unit's read path and the
# bootstrap's write path to /mnt/data/redis.
assert "redis.service reads conf from /mnt/data/redis (not /etc/redis)" \
  "grep -qF '/mnt/data/redis/inngest-redis.conf' '$REDIS_SERVICE' && ! grep -qF '/etc/redis' '$REDIS_SERVICE'"
assert "redis-bootstrap installs conf under /mnt/data (never /etc/redis)" \
  "grep -qF '\$REDIS_DATA_DIR/inngest-redis.conf' '$REDIS_BOOTSTRAP' && ! grep -qE 'install .* /etc/redis' '$REDIS_BOOTSTRAP'"
assert "inngest-bootstrap does not write the conf into /etc/redis (namespace trap)" \
  "! grep -qE 'install .* /etc/redis|mkdir -p /etc/redis' '$BOOTSTRAP_SH'"
# Secrets: random_password (not operator-mint) + doppler_secret.
assert "random_password.inngest_redis_password_prd" "grep -qE 'resource \"random_password\" \"inngest_redis_password_prd\"' '$INNGEST_TF'"
assert "INNGEST_REDIS_PASSWORD doppler_secret"      "grep -qE 'name[[:space:]]+= \"INNGEST_REDIS_PASSWORD\"' '$INNGEST_TF'"
# inngest-bootstrap runs the redis bootstrap (the REDIS_READY probe) BEFORE the
# inngest-server restart (the ExecStart is branched on REDIS_READY). Anchor on
# the INVOCATION line (`if /usr/local/bin/inngest-redis-bootstrap.sh; then`), not
# the `install …` line — after the #5547 reorder the install line still ends in
# `inngest-redis-bootstrap.sh` and a `$`-anchored `tail -1` could pick it; the
# invocation is the line whose ordering vs the restart actually matters.
REDIS_RUN_LINE=$(grep -nE 'if /usr/local/bin/inngest-redis-bootstrap.sh; then' "$BOOTSTRAP_SH" 2>/dev/null | head -1 | cut -d: -f1 || true)
RESTART_LINE=$(grep -nE '^systemctl restart inngest-server.service' "$BOOTSTRAP_SH" 2>/dev/null | head -1 | cut -d: -f1 || true)
assert "bootstrap runs inngest-redis-bootstrap.sh (REDIS_READY probe) BEFORE the inngest-server restart" \
  "[[ -n '$REDIS_RUN_LINE' && -n '$RESTART_LINE' && '$REDIS_RUN_LINE' -lt '$RESTART_LINE' ]]"

# --- #6090: webhook.service ReadWritePaths /var/lib/inngest must be `-`-optional ---
# On web_colocate_inngest=false (default since the co-located-inngest gate), the
# inngest-bootstrap runcmd block that CREATES /var/lib/inngest is gated off, so a
# MANDATORY RWP token makes systemd fail webhook.service with 226/NAMESPACE on a
# fresh host (:9000 never binds -> ok_peer_fanout_degraded -> web-2 undeployed).
# The `-` prefix marks the dir optional (systemd ignores it if absent), mirroring
# the -/var/lib/vector precedent (PR #4257). Both lockstep copies must match:
#   - cloud-init.yml (baked at first boot)
#   - webhook.service (base64-delivered to running web-1 via deploy_pipeline_fix).
echo ""
echo "--- #6090: webhook RWP /var/lib/inngest -optional (both lockstep copies) ---"
CLOUD_INIT="$SCRIPT_DIR/cloud-init.yml"
WEBHOOK_SERVICE="$SCRIPT_DIR/webhook.service"
assert "cloud-init.yml + webhook.service exist" "[[ -f '$CLOUD_INIT' && -f '$WEBHOOK_SERVICE' ]]"

# Exactly ONE ReadWritePaths= line per file — makes the head -1 extraction below safe.
# systemd ACCUMULATES RWP directives, so a future 2nd (mandatory) `/var/lib/inngest` line
# would slip past the token asserts and silently re-open the 226/NAMESPACE bug; a REMOVED
# line would abort under set -e/pipefail instead of a labeled FAIL. (#6363 review: security
# + architecture + code-quality converged.)
# shellcheck disable=SC2034  # consumed via assert's eval, below
CI_RWP_COUNT="$(grep -cE '^[[:space:]]*ReadWritePaths=' "$CLOUD_INIT" || true)"
# shellcheck disable=SC2034
WS_RWP_COUNT="$(grep -cE '^[[:space:]]*ReadWritePaths=' "$WEBHOOK_SERVICE" || true)"
assert "cloud-init.yml has exactly one ReadWritePaths= line (head -1 safety)" "[[ \"\$CI_RWP_COUNT\" -eq 1 ]]"
assert "webhook.service has exactly one ReadWritePaths= line (head -1 safety)" "[[ \"\$WS_RWP_COUNT\" -eq 1 ]]"

# CI_RWP/WS_RWP are consumed inside assert's `eval "$condition"` (SC can't see through eval).
# shellcheck disable=SC2034
CI_RWP="$(grep -E '^[[:space:]]*ReadWritePaths=' "$CLOUD_INIT" | head -1 | sed -E 's/^[[:space:]]*ReadWritePaths=//' || true)"
# shellcheck disable=SC2034
WS_RWP="$(grep -E '^[[:space:]]*ReadWritePaths=' "$WEBHOOK_SERVICE" | head -1 | sed -E 's/^[[:space:]]*ReadWritePaths=//' || true)"

assert "cloud-init RWP marks /var/lib/inngest optional (-prefix)" \
  "grep -qE -- '(^|[[:space:]])-/var/lib/inngest([[:space:]]|\$)' <<< \"\$CI_RWP\""
assert "cloud-init RWP has NO mandatory (bare) /var/lib/inngest" \
  "! grep -qE -- '(^|[[:space:]])/var/lib/inngest([[:space:]]|\$)' <<< \"\$CI_RWP\""
assert "webhook.service RWP marks /var/lib/inngest optional (-prefix)" \
  "grep -qE -- '(^|[[:space:]])-/var/lib/inngest([[:space:]]|\$)' <<< \"\$WS_RWP\""
assert "webhook.service RWP has NO mandatory (bare) /var/lib/inngest" \
  "! grep -qE -- '(^|[[:space:]])/var/lib/inngest([[:space:]]|\$)' <<< \"\$WS_RWP\""
assert "RWP token lists byte-identical across both lockstep copies" \
  "[[ -n \"\$CI_RWP\" && \"\$CI_RWP\" == \"\$WS_RWP\" ]]"

# --- `terraform fmt -check` for HCL hygiene ---
echo ""
echo "--- terraform fmt -check ---"
if command -v terraform >/dev/null 2>&1; then
  if (cd "$SCRIPT_DIR" && terraform fmt -check -diff=false inngest.tf >/dev/null 2>&1); then
    PASS=$((PASS + 1)); TOTAL=$((TOTAL + 1))
    echo "  PASS: inngest.tf is properly formatted"
  else
    FAIL=$((FAIL + 1)); TOTAL=$((TOTAL + 1))
    echo "  FAIL: inngest.tf needs 'terraform fmt' (run: terraform fmt apps/web-platform/infra/inngest.tf)"
  fi
else
  echo "  SKIP: terraform not installed locally"
fi

# --- #6555: DOPPLER_PROJECT via EnvironmentFile (the units dropped --project) ---
echo ""
echo "--- #6555: DOPPLER_PROJECT env-file delivery + --project removal ---"
CLOUD_INIT_INNGEST="$SCRIPT_DIR/cloud-init-inngest.yml"
CUTOVER_FLIP_SERVICE="$SCRIPT_DIR/inngest-cutover-flip.service"
SUDOERS_SRC="$SCRIPT_DIR/deploy-inngest-bootstrap.sudoers"
CI_DEPLOY="$SCRIPT_DIR/ci-deploy.sh"
assert "cloud-init pre-create writes DOPPLER_PROJECT=soleur-inngest into the env-file (dedicated path)" \
  "grep -qE \"printf 'DOPPLER_TOKEN=.*DOPPLER_PROJECT=soleur-inngest\" '$CLOUD_INIT_INNGEST'"
assert "bootstrap heredoc writes DOPPLER_PROJECT into the env-file (web path)" \
  "grep -qxF 'DOPPLER_PROJECT=\$DOPPLER_PROJECT' '$BOOTSTRAP_SH'"
assert "bootstrap fail-closes on a missing/empty DOPPLER_PROJECT env-file line (#6555 AC6)" \
  "grep -qF 'no non-empty DOPPLER_PROJECT= line' '$BOOTSTRAP_SH'"
assert "bootstrap augments a preserved env-file with DOPPLER_PROJECT (in-place re-bootstrap safety)" \
  "grep -qF 'appended DOPPLER_PROJECT=' '$BOOTSTRAP_SH'"
# Negative anchored on ExecStart / FLIP_GUARD assignment lines only — comments legitimately
# name `run --project …` (e.g. the failure-log unit's do-NOT-wrap rationale).
assert "no ExecStart --project remains in inngest-bootstrap.sh units (#6555)" \
  "! grep -qE '^ExecStart=.*--project' '$BOOTSTRAP_SH' && ! grep -qE 'FLIP_GUARD_LINE=.*--project' '$BOOTSTRAP_SH'"
assert "inngest-cutover-flip.service ExecStart has NO --project (#6555)" \
  "grep -qF 'doppler run --config prd' '$CUTOVER_FLIP_SERVICE' && ! grep -qE '^ExecStart=.*--project' '$CUTOVER_FLIP_SERVICE'"
assert "deploy-inngest-bootstrap.sudoers env_keep drops DOPPLER_PROJECT (#6555)" \
  "! grep -qE '^Defaults!INNGEST_BOOTSTRAP env_keep.*DOPPLER_PROJECT' '$SUDOERS_SRC'"
assert "cloud-init.yml inline sudoers env_keep drops DOPPLER_PROJECT (#6555)" \
  "! grep -qE 'Defaults!INNGEST_BOOTSTRAP env_keep.*DOPPLER_PROJECT' '$CLOUD_INIT'"
assert "ci-deploy.sh --preserve-env drops DOPPLER_PROJECT (#6555)" \
  "! grep -qE 'preserve-env=.*DOPPLER_PROJECT' '$CI_DEPLOY'"

echo ""
echo "=== Results: $PASS/$TOTAL passed, $FAIL failed ==="
if [[ "$FAIL" -gt 0 ]]; then exit 1; fi
