#!/usr/bin/env bash
#
# Drift guard for the "#9045 the workspaces-LUKS dead-man FIRED" Better Stack Logs alert
# (apps/web-platform/infra/betterstack-logs-alerts.tf, logtail_exploration_alert.workspaces_luks_deadman_fired).
# Plan: knowledge-base/project/plans/archive/20260928-124245-2026-09-28-fix-luks-deadman-host-canary-disarm-and-snapshot-411798619-release-plan.md
# (Phase 2 step 6, §Test Scenarios → Other suites → Alert).
#
# WHAT THE ALERT IS FOR. The cutover's dead-man (a transient systemd timer armed by
# workspaces-cutover.sh arm_dead_man) reverts web-1 to the plaintext volume when it fires. A fire is
# unattended by construction: the SIGKILL residual, or any future path that leaves it armed. On
# 2026-07-20 a fire remounted the plaintext over a healthy LUKS mount and nothing paged for ~6 h
# (#6812). The fire command's FIRST act is a `logger -t luks-monitor` marker carrying
# `op=workspaces-luks-deadman result=fired`; this alert pages on that row.
#
# WHAT THIS FILE NOW PROVES (post-#11720 convention):
#   * CONJUNCT-SET CANON — the predicate is exactly the head + four named AND conjuncts +
#     GROUP BY time, compared as a SET: reordering the conjuncts is a must-PASS edit (the
#     alert's own semantic is order-insensitive), while dropping, weakening, or adding a
#     clause goes red. A /* */- or #-wrapped decoy opener/resource counts and goes red.
#   * BLOCK-SCOPED EXACTLY-ONCE PINS — every alert attribute is asserted inside its own
#     resource block by param(), whole value line anchored both ends, required exactly once.
#     QP/CK are pinned EXACTLY (a duplicated query_period line earlier in the block can no
#     longer steer a first-hit extraction).
#   * THE FIRE COMMAND IS PINNED AT ITS EMITTER — the needle the predicate matches is the
#     literal workspaces-cutover.sh's arm_dead_man logs FIRST; a commented decoy inside the
#     function, a quoting copy outside it, or an uncommented fire-prefixed line planted
#     before the real one all go red.
#   * THE BATTERY CANNOT BE MUTED — MUT_SKIP skips mutation rows on an inner run only; the
#     pristine-child control FATALs (rc 2) if the un-mutated inner run is not green;
#     DEADMAN_GUARD_/MUT_SKIP literals may not reach the workflow's executable text (the
#     seam check below); mutate_floor_red proves the assertion floor fires.
#   * RC DISCRIMINATION — only rc=1 (a real [FAIL] verdict) is a caught mutation;
#     instrument failures (rc>=2) are UNRESOLVED. Floor/ledger trips exit 1;
#     instrument failures exit 2.
#
# Mutation rows live at the bottom. Each one COPIES a source file into a scratch dir, mutates
# the COPY, and re-runs this guard against it through DEADMAN_GUARD_{TF,WF,CUT,IV} overrides.
set -uo pipefail
export TMPDIR="${TMPDIR:-/var/tmp}"

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$DIR/../../../.." && pwd)"
TF="${DEADMAN_GUARD_TF:-$REPO/apps/web-platform/infra/betterstack-logs-alerts.tf}"
WF="${DEADMAN_GUARD_WF:-$REPO/.github/workflows/apply-web-platform-infra.yml}"
CUT="${DEADMAN_GUARD_CUT:-$REPO/apps/web-platform/infra/workspaces-cutover.sh}"
IV="${DEADMAN_GUARD_IV:-$REPO/.github/workflows/infra-validation.yml}"
SUITE_NAME="workspaces-luks-deadman-fired-alert.test.sh"

pass=0; fail=0; FAILED=()
ok() { pass=$((pass + 1)); printf '[ok] %s\n' "$1"; }
no() { fail=$((fail + 1)); FAILED+=("$1"); printf '[FAIL] %s\n' "$1"; }

# P1b (#7708) — byte-identical to every other tracked copy; the P1a suite pins that.
# `$(cd X && pwd)` prints an absolute path but yields EMPTY when the cd fails, which would root
# $TF at `/` — every path this file READS is checked through it, and so is the scratch dir
# the mutation battery WRITES to.
assert_fixture_dir() {
  case "${1-}" in
    "") printf 'FATAL: fixture dir is EMPTY; git -C "" would operate on %s\n' "$PWD" >&2; exit 2 ;;
    */../*|*/..) printf 'FATAL: fixture dir %s contains ..; refusing\n' "$1" >&2; exit 2 ;;
    /proc/*|/sys/*|/dev/*) printf 'FATAL: fixture dir %s is a synthetic-fs path; refusing\n' "$1" >&2; exit 2 ;;
    /|//|/.) printf 'FATAL: fixture dir resolves to the filesystem root; refusing\n' >&2; exit 2 ;;
    /*) : ;;
    *)  printf 'FATAL: fixture dir %s is RELATIVE; refusing\n' "$1" >&2; exit 2 ;;
  esac
}
assert_fixture_dir "$TF"; assert_fixture_dir "$WF"; assert_fixture_dir "$CUT"; assert_fixture_dir "$IV"

# INSTRUMENT SELF-TEST — both helpers must move their own counter before any verdict is trusted.
_p0=$pass; _f0=$fail
{ ok "self-test"; no "self-test"; } >/dev/null
if [ "$pass" -ne $((_p0 + 1)) ] || [ "$fail" -ne $((_f0 + 1)) ] || [ "${#FAILED[@]}" -ne 1 ]; then
  printf '[FATAL] instrument self-test: ok()/no() did not each move their counter\n' >&2; exit 2
fi
pass=$_p0; fail=$_f0; FAILED=()

for f in "$TF" "$WF" "$CUT" "$IV"; do
  [ -r "$f" ] || { printf '[FATAL] unreadable: %s\n' "$f" >&2; exit 2; }
done

NEEDLE='op=workspaces-luks-deadman result=fired'
MARKER='SOLEUR_WORKSPACES_LUKS_DEADMAN'

# ── Extraction helpers ───────────────────────────────────────────────────────────────────────
# sql_local: the heredoc body of `workspaces_luks_deadman_fired_sql = <<[-]SQL` up to its `  SQL`
# closer, from the FIRST UNCOMMENTED opener line.
sql_local() {
  awk '/^[[:space:]]*workspaces_luks_deadman_fired_sql[[:space:]]*=[[:space:]]*<<[-]SQL/{f=1;next} f&&/^  SQL$/{f=0} f' "$TF"
}
# res_block: one resource block from its column-0 header to its column-0 closing brace.
res_block() {
  awk -v h="resource \"$1\" \"$2\" {" '$0 == h {f=1} f{print} f && /^}/{exit}' "$TF"
}
# param <block> <attr> <value-ERE>: whole-line attribute assertion INSIDE a block, anchored
# both ends, required EXACTLY ONCE.
param() {
  # Value-matching exactly-once. Residual gap (accepted): a planted same-attr/different-value
  # line does not move this count — attr-name cardinality cannot apply here because blocks
  # legitimately nest a second `name` (explorations' `variable { name = "source" }`), and HCL
  # itself rejects duplicate attributes at validate. Mute/deletion classes are still covered.
  [ "$(printf '%s\n' "$1" | grep -cE "^[[:space:]]*$2[[:space:]]*=[[:space:]]*$3[[:space:]]*(#.*)?$")" -eq 1 ]
}
conj_has() {  # conj_has <fixed conjunct text, one line of the heredoc>
  grep -qxF -- "      AND $1" <<< "$LOCAL_SQL"
}

LOCAL_SQL="$(sql_local)"
ALERT="$(res_block logtail_exploration_alert workspaces_luks_deadman_fired)"
EXPL="$(res_block logtail_exploration workspaces_luks_deadman_fired)"

[ -n "$LOCAL_SQL" ] \
  && ok "the predicate local is a heredoc this guard can read" \
  || no "workspaces_luks_deadman_fired_sql: heredoc not found — every predicate row below would be vacuous"

# Opener counts — unanchored, file-wide, exactly once (a /* */- or #-wrapped decoy counts/red).
_n_sql_openers="$(grep -cE 'workspaces_luks_deadman_fired_sql[[:space:]]*=[[:space:]]*<<[-]SQL' "$TF")"
[ "$_n_sql_openers" -eq 1 ] \
  && ok "exactly one workspaces_luks_deadman_fired_sql heredoc opener in the file" \
  || no "workspaces_luks_deadman_fired_sql opener count is $_n_sql_openers, want 1 — a decoy local exists"
_n_exp="$(grep -cE 'resource "logtail_exploration" "workspaces_luks_deadman_fired"' "$TF")"
[ "$_n_exp" -eq 1 ] \
  && ok "exactly one logtail_exploration.workspaces_luks_deadman_fired resource header" \
  || no "logtail_exploration header count is $_n_exp, want 1 — a decoy resource exists"
_n_alr="$(grep -cE 'resource "logtail_exploration_alert" "workspaces_luks_deadman_fired"' "$TF")"
[ "$_n_alr" -eq 1 ] \
  && ok "exactly one logtail_exploration_alert.workspaces_luks_deadman_fired resource header" \
  || no "logtail_exploration_alert header count is $_n_alr, want 1 — a decoy resource exists"

_head="$(head -3 <<< "$LOCAL_SQL" | tr -s ' ' | sed 's/^ //' | paste -sd' ')"
grep -qxF 'SELECT {{time}} AS time, count(*) AS value FROM {{source}} WHERE time BETWEEN {{start_time}} AND {{end_time}}' <<< "$_head" \
  && ok "the head is the per-bucket count shape monitor_send_failed uses (ADR-218)" \
  || no "the predicate head is not SELECT {{time}} … count(*) … WHERE time BETWEEN {{start_time}} AND {{end_time}}"

conj_has "JSONExtractString(raw, 'SYSLOG_IDENTIFIER') = 'luks-monitor'" \
  && ok "the tag conjunct: SYSLOG_IDENTIFIER = 'luks-monitor' (the fire command's logger -t)" \
  || no "the SYSLOG_IDENTIFIER='luks-monitor' conjunct is missing or altered"

conj_has "JSONExtractString(raw, 'host_name') = 'soleur-web-platform'" \
  && ok "the host conjunct: host_name = 'soleur-web-platform' (web-2 ships to the same source)" \
  || no "the host_name='soleur-web-platform' conjunct is missing or altered"

conj_has "position(JSONExtractString(raw, 'message'), '$NEEDLE') > 0" \
  && ok "the result=fired conjunct: the message contains '$NEEDLE'" \
  || no "the '$NEEDLE' conjunct is missing or altered"

conj_has "startsWith(JSONExtractString(raw, 'message'), '$MARKER ')" \
  && ok "the marker anchor: the message STARTS with the dead-man marker (a row merely quoting it cannot page)" \
  || no "the startsWith '$MARKER ' anchor is missing"

# CONJUNCT-SET CANON — exactly the head, the four named conjuncts and GROUP BY time, compared
# as a SET: conjunct order is deliberately irrelevant (the alert's own semantic), so the canon
# sorts the AND lines; a reordered predicate stays green while any added/dropped/altered clause
# goes red. Dead text cannot satisfy it — the set is over the live extraction only.
_body="$(sed -n '4,$p' <<< "$LOCAL_SQL")"
_conj="$(grep '^      AND ' <<< "$_body" | sort)"
_conj_expected="$(printf '%s\n' \
  "      AND JSONExtractString(raw, 'SYSLOG_IDENTIFIER') = 'luks-monitor'" \
  "      AND JSONExtractString(raw, 'host_name') = 'soleur-web-platform'" \
  "      AND position(JSONExtractString(raw, 'message'), '$NEEDLE') > 0" \
  "      AND startsWith(JSONExtractString(raw, 'message'), '$MARKER ')" | sort)"
if [ "$_conj" = "$_conj_expected" ] \
   && [ "$(grep -vc '^      AND ' <<< "$_body")" -eq 1 ] \
   && [ "$(tail -1 <<< "$_body")" = '    GROUP BY time' ] \
   && ! grep -qiE '(^|[^A-Za-z_])(OR|NOT)([^A-Za-z_]|$)|!=|<>' <<< "$LOCAL_SQL"; then
  ok "the predicate is exactly the four named ANDed conjuncts and GROUP BY time (order-insensitive canon)"
else
  no "the predicate carries an OR, a negation, an extra clause, or a conjunct outside the named set"
fi

# The needle must be what the fire command actually logs: the systemd-run inline command's first
# logger call, on the luks-monitor tag. Read ONLY from arm_dead_man's body, full-line comments
# dropped, and only a line that STARTS with the /bin/sh -c argument: the same text in a comment,
# in another function or after other code on a line is not the fire command.
FIRE_PFX="/bin/sh -c \"logger -t \${LUKS_LOG_TAG} -- '$MARKER feature=workspaces-luks $NEEDLE "
FIRE_LINE="$(awk -v pfx="$FIRE_PFX" '
  /^arm_dead_man\(\)[[:space:]]*\{/ { f = 1; next }
  f && /^\}/ { exit }
  f { l = $0; sub(/^[[:space:]]+/, "", l); if (l ~ /^#/) next; if (index(l, pfx) == 1) { print l; exit } }' "$CUT")"
[ -n "$FIRE_LINE" ] \
  && ok "workspaces-cutover.sh's fire command logs '$MARKER … $NEEDLE ' first, on \${LUKS_LOG_TAG}" \
  || no "the fire command no longer logs '$MARKER … $NEEDLE ' as its first act — the alert would never page"
# FIRE_LINE cardinality: exactly one UNCOMMENTED line inside arm_dead_man may start with the
# fire prefix — an uncommented copy planted BEFORE the real one steers the first-hit read.
_n_fire="$(awk -v pfx="/bin/sh -c \"logger -t " '
  /^arm_dead_man\(\)[[:space:]]*\{/ { f = 1; next }
  f && /^\}/ { exit }
  f { l = $0; sub(/^[[:space:]]+/, "", l); if (l ~ /^#/) next; if (index(l, pfx) == 1) n++ }
  END { print n+0 }' "$CUT")"
[ "$_n_fire" -eq 1 ] \
  && ok "exactly one uncommented logger line inside arm_dead_man (a planted fire-prefixed decoy counts)" \
  || no "arm_dead_man carries $_n_fire uncommented logger lines (want 1) — a decoy fire command exists"
grep -qE '^LUKS_LOG_TAG="\$\{WORKSPACES_LUKS_LOG_TAG:-luks-monitor\}"' "$CUT" \
  && ok "LUKS_LOG_TAG defaults to luks-monitor (the tag the predicate matches, Vector-allowlisted)" \
  || no "LUKS_LOG_TAG no longer defaults to luks-monitor"

param "$EXPL" 'sql_query' 'replace\(trimspace\(local\.workspaces_luks_deadman_fired_sql\), "/\\\\s\+/", " "\)' \
  && ok "the exploration carries THIS predicate, collapsed to one line (the sibling's perpetual-diff rule)" \
  || no "the exploration does not carry local.workspaces_luks_deadman_fired_sql as its sql_query"
param "$EXPL" 'values' '\[local\.vector_prd_source_id\]' \
  && ok "the exploration reads the prd Vector source" \
  || no "the exploration's source variable is not local.vector_prd_source_id"

param "$ALERT" 'exploration_id' 'logtail_exploration\.workspaces_luks_deadman_fired\.id' \
  && ok "the alert watches ITS OWN exploration" \
  || no "the alert's exploration_id is not logtail_exploration.workspaces_luks_deadman_fired.id"
param "$ALERT" 'name' '"soleur-workspaces-luks-deadman-fired-prd"' \
  && param "$EXPL" 'name' '"soleur-workspaces-luks-deadman-fired-prd"' \
  && ok "both are named soleur-workspaces-luks-deadman-fired-prd" \
  || no "the exploration/alert name drifted from soleur-workspaces-luks-deadman-fired-prd"
param "$ALERT" 'alert_type' '"threshold"' \
  && param "$ALERT" 'operator' '"higher_than"' \
  && param "$ALERT" 'value' '0' \
  && ok "threshold, higher_than 0: ONE fired row pages (monitor_send_failed's semantics)" \
  || no "the alert is not threshold/higher_than/0 — a single fire would not page"
param "$ALERT" 'on_missing_data' '"treat_as_zero"' \
  && ok "treat_as_zero, so an open incident can observe recovery" \
  || no "on_missing_data is not treat_as_zero"
param "$ALERT" 'paused' 'false' \
  && ok "paused = false on its own line" \
  || no "the alert is paused (or paused carries a suffix)"
[ "$(printf '%s\n' "$ALERT" | grep -c 'paused')" -eq 1 ] \
  && ok "the string 'paused' occurs exactly once in the alert block (a commented or duplicated decoy counts)" \
  || no "'paused' occurs !=1 time in the alert block — a commented pinned-line decoy exists"
param "$ALERT" 'email' 'true' \
  && ok "email = true (the free-tier paging surface)" \
  || no "email is not true"
param "$ALERT" 'query_period' '300' \
  && param "$ALERT" 'check_period' '60' \
  && param "$ALERT" 'confirmation_period' '0' \
  && param "$ALERT" 'recovery_period' '600' \
  && ok "evaluated every 60s over a 300s window (confirm 0, recovery 600) — exact pins, not first-hit ranges" \
  || no "query/check/confirmation/recovery periods are not exactly 300/60/0/600 (exactly once each)"
param "$ALERT" 'policy_id' 'var\.betterstack_paid_tier \? tonumber\(betteruptime_policy\.uptime\[0\]\.id\) : null' \
  && param "$ALERT" 'team_name' 'var\.betterstack_paid_tier \? null : "Your team"' \
  && ok "the escalation target is the free/paid ternary every sibling uses (ADR-218)" \
  || no "the escalation_target drifted from the sibling ternary"
grep -qF 'Runbook: ${local.workspaces_luks_deadman_runbook_url}' <<< "$ALERT" \
  && param "$ALERT" 'runbook' 'local\.workspaces_luks_deadman_runbook_url' \
  && grep -qE '^[[:space:]]*workspaces_luks_deadman_runbook_url[[:space:]]*=[[:space:]]*"https://github\.com/jikig-ai/soleur/blob/main/knowledge-base/engineering/operations/runbooks/workspaces-luks-cutover-6604\.md[#"]' "$TF" \
  && ok "incident_cause and metadata.runbook carry the cutover runbook URL (the email is what a reader acts on)" \
  || no "the incident has no clickable cutover-runbook URL"

# NEGATIVE row: no count/for_each/lifecycle/ignore_changes token inside EITHER resource block.
if [ "$(printf '%s\n%s\n' "$EXPL" "$ALERT" | grep -cE '^[[:space:]]*(count|for_each|lifecycle|ignore_changes)[[:space:]]*[= {]')" -eq 0 ]; then
  ok "no count/for_each/lifecycle/ignore_changes mute knob inside either resource block"
else
  no "a count/for_each/lifecycle/ignore_changes token sits inside a resource block — a mute knob the provider would honor silently"
fi

APPLY_JOB="$(awk '/^  apply:$/{f=1; print; next} f && /^  [A-Za-z0-9_-]+:$/{f=0} f' "$WF")"
grep -qE '^[[:space:]]*-target=logtail_exploration\.workspaces_luks_deadman_fired \\$' <<< "$APPLY_JOB" \
  && grep -qE '^[[:space:]]*-target=logtail_exploration_alert\.workspaces_luks_deadman_fired \\$' <<< "$APPLY_JOB" \
  && ok "both resources are in the push-triggered apply job's -target allowlist (#5566)" \
  || no "one or both -target= lines are missing — the alert would never exist in Better Stack"

# ── Workflow seam — registered, unconditionally blocking, and no env axis may reach it ─────────
# This suite is registered (a suite that never runs guards nothing): an uncommented step, once.
# Pure-bash helpers (no pipes): has LITERAL TEXT -> TEXT contains LITERAL; cnt LITERAL TEXT -> occurrences.
has() { [[ "$2" == *"$1"* ]]; }
cnt() { local t="${2//"$1"/}"; printf '%s' $(( (${#2} - ${#t}) / ${#1} )); }
REG_RUN="        run: bash apps/web-platform/test/infra/$SUITE_NAME"
if [ "$(cnt "$REG_RUN"$'\n' "$(cat "$IV")"$'\n')" -eq 1 ]; then
  ok "this suite is registered in infra-validation.yml (exactly one uncommented run step)"
else
  no "infra-validation.yml does not run $SUITE_NAME exactly once"
fi

# A CI-dead guard must not pass. The step: no continue-on-error, no `if:`, and ONLY the keys name + run (a `shell:`,
# `env:`, `working-directory:` ... on it can neuter or redirect the run without being `if`/`continue-on-error`). The
# HOSTING JOB is derived from the step's position (the last job header above the registered run line, a header with a
# trailing comment or a quoted id included), never named here, and is read WHOLE (header, steps, anything after them:
# YAML key order is free): its `if:` must be the one known literal, `continue-on-error` must appear nowhere in it, its
# `needs`/`runs-on` must be the known literals, and its own keys are the known set (no `defaults`, `env`, `container`,
# `strategy`, `services` ...). Finally the verdict must REACH the aggregator: the one job that lists the hosting job in
# `needs:` must run under `if: always()` and read `needs.<job>.result` AND carry `"<job>:` in its entries array, so
# dropping the leg from the aggregator is not a quiet way to make this guard CI-dead. Comments are ignored.
# The workflow itself must carry no top-level `defaults:` and no seam env name in executable text.
# hdr LINE -> the job id when LINE is a `jobs:`-level key header (`  id:`, `  "id":`, `  id: # note`), else "".
AWK_HDR='function hdr(l,   n) { if (l ~ /^  [\047"]?[A-Za-z0-9_-]+[\047"]?:[ \t]*(#.*)?$/) { n = l; sub(/^  [\047"]?/, "", n); sub(/[\047"]?:.*$/, "", n); return n } return "" }'
STEP_BLOCK="$(awk -v r="$REG_RUN" "$AWK_HDR"'
  function flush() { if (blk != "" && index(blk, r "\n") > 0) printf "%s", blk; blk = "" }
  /^      - / || hdr($0) != "" { flush() }
  { if ($0 !~ /^[[:space:]]*#/) blk = blk $0 "\n" }
  END { flush() }' "$IV")"
HOST_JOB="$(awk -v r="$REG_RUN" "$AWK_HDR"'{ h = hdr($0); if (h != "") j = h } $0 == r { print j; exit }' "$IV")"
JOB_BLOCK=""
[ -n "$HOST_JOB" ] && JOB_BLOCK="$(awk -v j="$HOST_JOB" "$AWK_HDR"'{ h = hdr($0) } h != "" && h == j { f = 1; print; next } f && h != "" { exit } f && !/^[[:space:]]*#/ { print }' "$IV")"
JOB_IF="$(awk '/^    if:/ { print }' <<<"$JOB_BLOCK")"
JOB_NEEDS="$(awk '/^    needs:/ { print }' <<<"$JOB_BLOCK")"
JOB_RUNS_ON="$(awk '/^    runs-on:/ { print }' <<<"$JOB_BLOCK")"
# Key allowlists: the step is `- name:` + `run:`; the job is the known set. Anything else (or an unrecognised line shape) is listed.
STEP_BAD="$(awk -v allow=" name run " 'NF == 0 { next } { k = "?" }
  /^      - [A-Za-z_-]+:/ { k = $0; sub(/^      - /, "", k); sub(/:.*/, "", k) }
  /^        [A-Za-z_-]+:/ { k = $0; sub(/^        /, "", k); sub(/:.*/, "", k) }
  index(allow, " " k " ") == 0 { print k }' <<<"$STEP_BLOCK")"
JOB_BAD="$(awk -v allow=" name needs if runs-on permissions timeout-minutes steps " '/^    [A-Za-z_-]+:/ { k = $0; sub(/^    /, "", k); sub(/:.*/, "", k); if (index(allow, " " k " ") == 0) print k }' <<<"$JOB_BLOCK")"
IV_CODE="$(awk '!/^[[:space:]]*#/' "$IV")"
WF_BAD=""
[[ $'\n'"$IV_CODE" == *$'\ndefaults:'* ]] && WF_BAD="$WF_BAD top-level-defaults"
# Fragments, not literals (#11899): a runtime-composed name ("MUT_""SKIP", a GUARD-fragment
# prefix) or a shell-injection env (BASH_ENV/SHELLOPTS/BASHOPTS) reaches the step with no
# literal present — MUT_/_SKIP cover MUT_SKIP at either split, GUARD covers every *_GUARD_*
# axis. DEADMAN_GUARD_ stays literal too — redundant (GUARD covers it) but it names the axis.
_seam_frag=""
for _frag in 'MUT_' '_SKIP' 'GUARD' 'BASH_ENV' 'SHELLOPTS' 'BASHOPTS' 'DEADMAN_GUARD_'; do
  has "$_frag" "$IV_CODE" && _seam_frag="$_seam_frag ${_frag}-fragment"
done
[ -n "$_seam_frag" ] && WF_BAD="$WF_BAD suite-seam-in-workflow:$_seam_frag"
# The only DYNAMIC channel: a $GITHUB_ENV/$GITHUB_PATH write or a job-local defaults: inside
# the hosting job. JOB_BLOCK is already derived from the registered run line's position and
# comment-stripped; an empty slice reds the composite below, so the ban cannot pass vacuously.
if [ -z "$JOB_BLOCK" ]; then
  WF_BAD="$WF_BAD job-slice-empty"
else
  _job_seam=""
  has 'GITHUB_ENV' "$JOB_BLOCK" && _job_seam="$_job_seam GITHUB_ENV"
  has 'GITHUB_PATH' "$JOB_BLOCK" && _job_seam="$_job_seam GITHUB_PATH"
  has 'defaults:' "$JOB_BLOCK" && _job_seam="$_job_seam defaults:"
  [ -n "$_job_seam" ] && WF_BAD="$WF_BAD job-scope-env-write:$_job_seam"
fi
# The aggregator: every job (other than the host) whose `needs:` names the host; one of them must carry the facts.
AGG_CANDS="$(awk -v host="$HOST_JOB" "$AWK_HDR"'
  function emit(l,   n, t, i) { sub(/[ \t]#.*$/, "", l); gsub(/[\[\],"\047]/, " ", l); n = split(l, t, /[ \t]+/); for (i = 1; i <= n; i++) if (t[i] == host && job != host) print job }
  /^[[:space:]]*#/ { next }
  { h = hdr($0); if (h != "") { job = h; innd = 0; next } }
  job == "" { next }
  /^    needs:/ { innd = 1; l = $0; sub(/^    needs:/, "", l); emit(l); next }
  innd && /^      -/ { l = $0; sub(/^      -/, "", l); emit(l); next }
  /^    [A-Za-z_-]+:/ { innd = 0 }' <<<"$IV_CODE")"
AGG_OK=0; AGG_NAMES=""
if [ -n "$HOST_JOB" ]; then
  while IFS= read -r _agg; do
    [ -n "$_agg" ] || continue
    AGG_NAMES="$AGG_NAMES $_agg"
    _agg_block="$(awk -v j="$_agg" "$AWK_HDR"'{ h = hdr($0) } h != "" && h == j { f = 1; print; next } f && h != "" { exit } f { print }' <<<"$IV_CODE")"
    if [[ $'\n'"$_agg_block" == *$'\n    if: always()'* ]] && has "needs.${HOST_JOB}.result" "$_agg_block" && has "\"${HOST_JOB}:\$" "$_agg_block"; then AGG_OK=1; fi
  done <<<"$AGG_CANDS"
fi
if [ -n "$STEP_BLOCK" ] && [[ "$STEP_BLOCK" != *continue-on-error* ]] && ! [[ "$STEP_BLOCK" =~ $'\n'[[:space:]]+if: ]] && ! [[ "$STEP_BLOCK" =~ ^[[:space:]]*-[[:space:]]+if: ]] \
   && [ -z "$STEP_BAD" ] && [ -n "$HOST_JOB" ] && [ -n "$JOB_BLOCK" ] && [[ "$JOB_BLOCK" != *continue-on-error* ]] && [ -z "$JOB_BAD" ] && [ -z "$WF_BAD" ] \
   && [ "$JOB_IF" = "    if: needs.detect-changes.outputs.pr_duplicate != 'true'" ] \
   && [ "$JOB_NEEDS" = "    needs: detect-changes" ] && [ "$JOB_RUNS_ON" = "    runs-on: ubuntu-24.04" ] && [ "$AGG_OK" -eq 1 ]; then
  ok "infra-validation.yml: the registered step has only name+run (no continue-on-error / if: / shell / env / ...), its hosting job '$HOST_JOB' (derived from the step's position) has the one known if:, needs and runs-on, the known key set and no continue-on-error anywhere, and its verdict reaches the aggregator ('${AGG_NAMES# }': if: always(), the leg's result, its entries slot): it cannot be skipped, non-blocking, redirected or dropped"
else
  no "infra-validation.yml: the registered step or its hosting job '$HOST_JOB' is conditional, non-blocking, redirected or unaggregated (step keys beyond name/run: '${STEP_BAD//$'\n'/ }'; job keys beyond the known set: '${JOB_BAD//$'\n'/ }'; workflow:${WF_BAD:- none}; aggregator ok=$AGG_OK; continue-on-error anywhere in the job; an if:/needs/runs-on other than the known literals), or could not be located"
fi

echo ""
echo "=== workspaces-luks-deadman-fired-alert guard: $pass passed, $fail failed ==="
if [ "$fail" -gt 0 ]; then
  printf 'FAILED: %s\n' "${FAILED[@]}" >&2
  exit 1
fi

# ── Mutation rows: each must make a row above RED (must-PASS rows stay GREEN) ─────────────────
# OUTER RUN ONLY. Each row copies ONE source file into $MUT_DIR, mutates the copy, and re-runs
# this guard with MUT_SKIP=1 and the matching DEADMAN_GUARD_* override pointing at the copy.
SELF="$DIR/$(basename "${BASH_SOURCE[0]}")"
if [ -z "${MUT_SKIP:-}" ]; then
  MUT_DIR="$(mktemp -d -t deadmanalert.XXXXXX)" || { printf '[FATAL] mktemp failed\n' >&2; exit 2; }
  assert_fixture_dir "$MUT_DIR"
  trap 'rm -rf "$MUT_DIR"' EXIT

  # INSTRUMENT CONTROL — the inner run against the PRISTINE tree must exit 0, or every row below
  # would grade a broken invocation as "mutation RED".
  ctl_rc=0; MUT_SKIP=1 bash "$SELF" >"$MUT_DIR/control.log" 2>&1 || ctl_rc=$?
  if [ "$ctl_rc" -ne 0 ]; then
    printf '[FATAL] instrument control: the inner run exited %s on the PRISTINE tree — the battery cannot be trusted:\n' "$ctl_rc" >&2
    sed 's/^/    /' "$MUT_DIR/control.log" >&2; exit 2
  fi

  PRELUDE='def edit(s, anchor, old, new, end="\n}\n"):
    i = s.index(anchor)
    j = s.index(end, i)
    region = s[i:j]
    assert region.count(old) == 1, "anchor drift: %r occurs %d times" % (old, region.count(old))
    return s[:i] + region.replace(old, new) + s[j:]
def dm_replace(s, old, new):
    # The first occurrence AFTER the dead-man local'\''s opening line: the luks-monitor
    # host-timer predicate earlier in the file carries identical tag/host conjuncts.
    i = s.index("  workspaces_luks_deadman_fired_sql = <<\x2dSQL")
    j = s.index(old, i)
    return s[:j] + new + s[j + len(old):]
SQLLOC = "  workspaces_luks_deadman_fired_sql = <<\x2dSQL"
SQLEND = "\n  SQL\n"
EXPRES = "resource \"logtail_exploration\" \"workspaces_luks_deadman_fired\" {"
ALRRES = "resource \"logtail_exploration_alert\" \"workspaces_luks_deadman_fired\" {"'

  _red_verdict() {
    case "$1" in
      1) if [ -z "$3" ] || { grep -F '[FAIL]' "$2" | grep -F -- "$3" >/dev/null; }; then echo red; else echo wrong; fi ;;
      0) echo survived ;;
      *) echo unresolved ;;
    esac
  }

  # mutate_red <label> <TF|WF|CUT|IV> <python-program-on-s> [expected [FAIL] fragment] [red|wrong]
  mutate_red() {
    local label="$1" which="$2" prog="$3" tag="${4:-}" want="${5:-red}" src copy rc=0 olog="$MUT_DIR/inner.log"
    case "$which" in
      TF)  src="$TF";  copy="$MUT_DIR/betterstack-logs-alerts.tf" ;;
      WF)  src="$WF";  copy="$MUT_DIR/apply-web-platform-infra.yml" ;;
      CUT) src="$CUT"; copy="$MUT_DIR/workspaces-cutover.sh" ;;
      IV)  src="$IV";  copy="$MUT_DIR/infra-validation.yml" ;;
      *) printf '[FATAL] mutate_red: unknown target %s\n' "$which" >&2; exit 2 ;;
    esac
    cp "$src" "$copy" || { printf '[FATAL] mutate_red: cp %s failed\n' "$src" >&2; exit 2; }
    python3 - "$copy" <<PY || { no "mutation '$label' did not land (anchor drifted)"; return 0; }
import sys
p = sys.argv[1]
$PRELUDE
orig = open(p, encoding="utf-8").read()
s = orig
$prog
assert s != orig, "mutation produced no change"
open(p, 'w', encoding="utf-8").write(s)
PY
    env "DEADMAN_GUARD_${which}=$copy" MUT_SKIP=1 bash "$SELF" >"$olog" 2>&1 || rc=$?
    case "$(_red_verdict "$rc" "$olog" "$tag"):$want" in
      red:red) ok "mutation RED: $label" ;;
      wrong:wrong) ok "scorer control: graded WRONG reason as required: $label" ;;
      wrong:red) no "mutation went red for the WRONG reason (no [FAIL] line contains '$tag'): $label" ;;
      red:wrong) no "scorer control: the wrong-reason mutant was graded RED (the fragment check accepts anything): $label" ;;
      survived:*) no "mutation SURVIVED: $label — the rows above pin nothing" ;;
      *) no "mutation UNRESOLVED (inner rc=$rc, not an assertion): $label — instrument, not evidence" ;;
    esac
  }

  mutate_green() {
    local label="$1" which="$2" prog="$3" copy rc=0 src
    case "$which" in
      TF)  src="$TF";  copy="$MUT_DIR/betterstack-logs-alerts.tf" ;;
      WF)  src="$WF";  copy="$MUT_DIR/apply-web-platform-infra.yml" ;;
      CUT) src="$CUT"; copy="$MUT_DIR/workspaces-cutover.sh" ;;
      IV)  src="$IV";  copy="$MUT_DIR/infra-validation.yml" ;;
      *) printf '[FATAL] mutate_green: unknown target %s\n' "$which" >&2; exit 2 ;;
    esac
    cp "$src" "$copy" || { printf '[FATAL] mutate_green: cp failed\n' >&2; exit 2; }
    python3 - "$copy" <<PY || { no "must-PASS '$label' did not land (anchor drifted)"; return 0; }
import sys
p = sys.argv[1]
$PRELUDE
orig = open(p, encoding="utf-8").read()
s = orig
$prog
assert s != orig, "mutation produced no change"
open(p, 'w', encoding="utf-8").write(s)
PY
    env "DEADMAN_GUARD_${which}=$copy" MUT_SKIP=1 bash "$SELF" >"$MUT_DIR/green.log" 2>&1 || rc=$?
    case "$rc" in
      0) ok "must-PASS stays green: $label" ;;
      1) no "legitimate edit went RED: $label" ;;
      *) no "must-PASS UNRESOLVED (inner rc=$rc): $label - instrument, not evidence" ;;
    esac
  }

  mutate_floor_red() {
    local label="$1" copy rc=0 cur
    copy="$MUT_DIR/floor-mutated.test.sh"
    cur="$(grep -oE '^PRESENCE_ROWS=[0-9]+$' "$SELF" | cut -d= -f2)"
    [ -n "$cur" ] || { no "mutation '$label' did not land (no PRESENCE_ROWS declaration)"; return 0; }
    sed -e "s/^PRESENCE_ROWS=${cur}$/PRESENCE_ROWS=$((cur + 1))/" \
        -e "s|^REPO=.*|REPO=\"$REPO\"|" "$SELF" > "$copy"
    if cmp -s "$SELF" "$copy"; then no "mutation '$label' did not land (PRESENCE_ROWS anchor drifted)"; return 0; fi
    MUT_SKIP=1 bash "$copy" >/dev/null 2>&1 || rc=$?
    case "$rc" in
      1) ok "mutation RED: $label" ;;
      0) no "mutation SURVIVED: $label - the assertion floor pins nothing" ;;
      *) no "mutation UNRESOLVED (inner rc=$rc, not an assertion): $label - instrument, not evidence" ;;
    esac
  }

  # ── Dead-text / extraction-class rows ──────────────────────────────────────────────────────
  mutate_red "a /* */-wrapped decoy heredoc sits before the live local while the live body is gutted" TF \
    's = edit(s, SQLLOC, "count(*) AS value", "count(*) * 0 AS value", SQLEND)
i = s.index(SQLLOC)
s = s[:i] + "/*\n  workspaces_luks_deadman_fired_sql = <<\x2dSQL\n  SELECT legit\n  SQL\n*/\n" + s[i:]' \
    "decoy local exists"
  mutate_red "a #-commented decoy opener line sits above the live local" TF \
    'i = s.index(SQLLOC)
s = s[:i] + "  # workspaces_luks_deadman_fired_sql = <<\x2dSQL\n" + s[i:]' \
    "decoy local exists"
  mutate_red "a commented-out paused=false decoy line appears inside the alert block" TF \
    's = edit(s, ALRRES, "  paused = false\n", "  paused = false\n  # paused = false\n")' \
    "decoy exists"
  mutate_red "an inline tautology is appended inside the predicate" TF \
    's = edit(s, SQLLOC, "GROUP BY time", "GROUP BY time OR 1=1", SQLEND)' \
    "carries an OR"
  mutate_red "the live predicate local is gutted to a placeholder while the resource keeps its name" TF \
    's = edit(s, SQLLOC, "SELECT {{time}} AS time, count(*) AS value", "SELECT 1", SQLEND)' \
    "predicate head"
  mutate_red "an uncommented fire-prefixed logger line is planted BEFORE the real one inside arm_dead_man" CUT \
    'i = s.index("arm_dead_man() {")
j = s.index("/bin/sh -c", i)
line_start = s.rindex("\n", 0, j) + 1
line_end = s.index("\n", j) + 1
s = s[:line_start] + s[line_start:line_end] + s[line_start:]' \
    "decoy fire command"

  # ── Conjunct-set canon rows ────────────────────────────────────────────────────────────────
  mutate_red "the tag conjunct is dropped" TF \
    's = dm_replace(s, "      AND JSONExtractString(raw, \x27SYSLOG_IDENTIFIER\x27) = \x27luks-monitor\x27\n", "")' \
    "missing or altered"
  mutate_red "the host conjunct is dropped (web-2 rows would page)" TF \
    's = dm_replace(s, "      AND JSONExtractString(raw, \x27host_name\x27) = \x27soleur-web-platform\x27\n", "")' \
    "missing or altered"
  mutate_red "the result=fired conjunct is dropped (every dead-man row would page)" TF \
    'old = "      AND position(JSONExtractString(raw, \x27message\x27), \x27op=workspaces-luks-deadman result=fired\x27) > 0\n"
assert s.count(old) == 1
s = s.replace(old, "")' \
    "missing or altered"
  mutate_red "the needle is reworded to result=ok (pages on the recovery, never on the fire)" TF \
    'old = "\x27op=workspaces-luks-deadman result=fired\x27"
assert s.count(old) == 1
s = s.replace(old, "\x27op=workspaces-luks-deadman result=ok\x27")' \
    "result=fired"
  mutate_red "a conjunct is OR-joined (the predicate widens to every luks-monitor row)" TF \
    's = dm_replace(s, "      AND JSONExtractString(raw, \x27SYSLOG_IDENTIFIER\x27) = \x27luks-monitor\x27\n", "      OR JSONExtractString(raw, \x27SYSLOG_IDENTIFIER\x27) = \x27luks-monitor\x27\n")' \
    "carries an OR"
  mutate_red "the marker anchor loses its trailing space (SOLEUR_WORKSPACES_LUKS_DEADMAN_X rows would page)" TF \
    's = dm_replace(s, "\x27SOLEUR_WORKSPACES_LUKS_DEADMAN \x27)", "\x27SOLEUR_WORKSPACES_LUKS_DEADMAN\x27)")' \
    "anchor is missing"

  # ── Emitter rows (workspaces-cutover.sh) ──────────────────────────────────────────────────
  mutate_red "the fire command's marker is reworded in workspaces-cutover.sh only" CUT \
    'old = "op=workspaces-luks-deadman result=fired reason=timer_elapsed"
assert s.count(old) == 1
s = s.replace(old, "op=workspaces-luks-deadman result=engaged reason=timer_elapsed")' \
    "fire command"
  mutate_red "the fire line survives only as a COMMENT inside arm_dead_man (the real one reworded)" CUT \
    'import re
m = re.search(r"(?m)^([ \t]*)(/bin/sh -c \"logger -t \$\{LUKS_LOG_TAG\} -- \x27SOLEUR_WORKSPACES_LUKS_DEADMAN feature=workspaces-luks op=workspaces-luks-deadman result=fired reason=timer_elapsed\x27;.*)$", s)
assert m and s.count("result=fired reason=timer_elapsed") == 1
real = m.group(0)
s = s.replace(real, m.group(1) + "# " + m.group(2) + "\n" + real.replace("result=fired reason=timer_elapsed", "result=engaged reason=timer_elapsed"), 1)' \
    "fire command"
  mutate_red "the fire text is quoted OUTSIDE arm_dead_man (the real one reworded)" CUT \
    'old = "result=fired reason=timer_elapsed"
assert s.count(old) == 1
s = s.replace(old, "result=engaged reason=timer_elapsed") + "\n_fire_doc() {\n    /bin/sh -c \"logger -t ${LUKS_LOG_TAG} -- \x27SOLEUR_WORKSPACES_LUKS_DEADMAN feature=workspaces-luks op=workspaces-luks-deadman result=fired reason=timer_elapsed\x27\"\n}\n"' \
    "fire command"

  # ── Alert-attribute rows ──────────────────────────────────────────────────────────────────
  mutate_red "the alert is paused" TF \
    's = edit(s, ALRRES, "  paused = false\n", "  paused = true\n")' \
    "paused"
  mutate_red "on_missing_data is no longer treat_as_zero" TF \
    's = edit(s, ALRRES, "on_missing_data     = \"treat_as_zero\"", "on_missing_data     = \"keep_last_value\"")' \
    "treat_as_zero"
  mutate_red "the operator flips to lower_than (silence pages, a fire does not)" TF \
    's = edit(s, ALRRES, "operator            = \"higher_than\"", "operator            = \"lower_than\"")' \
    "higher_than"
  mutate_red "the alert watches another exploration" TF \
    'old = "exploration_id = logtail_exploration.workspaces_luks_deadman_fired.id"
assert s.count(old) == 1
s = s.replace(old, "exploration_id = logtail_exploration.monitor_send_failed.id")' \
    "exploration_id"
  mutate_red "a duplicated query_period line is planted inside the alert block" TF \
    's = edit(s, ALRRES, "  query_period        = 300\n", "  query_period        = 300\n  query_period        = 300\n")' \
    "exactly once each"
  mutate_red "the count = 0 mute knob is added inside the alert resource" TF \
    's = edit(s, ALRRES, "  paused = false\n", "  count = 0\n  paused = false\n")' \
    "mute knob"
  mutate_red "the alert is dropped from the apply allowlist" WF \
    'old = "            -target=logtail_exploration_alert.workspaces_luks_deadman_fired \\\n"
assert s.count(old) == 1
s = s.replace(old, "")' \
    "-target= lines are missing"

  # ── Workflow seam rows ─────────────────────────────────────────────────────────────────────
  # IV_ANCH — the shared anchors the key-shape / key-order rows below mutate through: RUN is
  # the registered run line, HOSTH the hosting job's exact four-line header, AFTER the first
  # bytes of the comment block that follows the job's steps (the post-steps insertion slot).
  IV_ANCH='Q = chr(39)
RUN = "        run: bash apps/web-platform/test/infra/workspaces-luks-deadman-fired-alert.test.sh\n"
HOSTH = "  deploy-script-tests-fixed:\n    needs: detect-changes\n    if: needs.detect-changes.outputs.pr_duplicate != " + Q + "true" + Q + "\n    runs-on: ubuntu-24.04\n"
AFTER = "          fi\n\n  # Aggregator (#8736): the single verdict"
'
  mutate_red "a MUT_SKIP literal reaches the workflow's executable text" IV \
    'old = "        run: bash apps/web-platform/test/infra/workspaces-luks-deadman-fired-alert.test.sh\n"
assert s.count(old) == 1
s = s.replace(old, "        env:\n          MUT_SKIP: \"1\"\n" + old)' \
    "suite-seam-in-workflow"
  mutate_red "a DEADMAN_GUARD_ literal reaches the workflow's executable text" IV \
    'old = "        run: bash apps/web-platform/test/infra/workspaces-luks-deadman-fired-alert.test.sh\n"
assert s.count(old) == 1
s = s.replace(old, old + "        env:\n          DEADMAN_GUARD_TF: /dev/null\n")' \
    "suite-seam-in-workflow"
  mutate_red "the suite's own run line is dropped from the workflow" IV \
    'old = "        run: bash apps/web-platform/test/infra/workspaces-luks-deadman-fired-alert.test.sh\n"
assert s.count(old) == 1
s = s.replace(old, "")' \
    "does not run workspaces-luks-deadman-fired-alert.test.sh exactly once"
  mutate_red "a composed MUT_ / _SKIP env name reaches the workflow through an in-job GITHUB_ENV write" IV \
    'old = "        run: bash apps/web-platform/test/infra/workspaces-luks-deadman-fired-alert.test.sh\n"
assert s.count(old) == 1
s = s.replace(old, old + "        run: echo \"MUT_\"\"SKIP=1\" >> \"\x24GITHUB_ENV\"\n")' \
    "suite-seam-in-workflow"
  mutate_red "a GUARD-fragment env name is planted on the suite's step" IV \
    'old = "        run: bash apps/web-platform/test/infra/workspaces-luks-deadman-fired-alert.test.sh\n"
assert s.count(old) == 1
s = s.replace(old, "        env:\n          FOO_GUARD_X: /dev/null\n" + old)' \
    "suite-seam-in-workflow"
  mutate_red "a BASH_ENV shell-injection name is planted inside the job" IV \
    'old = "        run: bash apps/web-platform/test/infra/workspaces-luks-deadman-fired-alert.test.sh\n"
assert s.count(old) == 1
s = s.replace(old, "        env:\n          BASH_ENV: /tmp/x\n" + old)' \
    "suite-seam-in-workflow"
  mutate_red "a benign GITHUB_ENV write lands inside the suite's own job" IV \
    'old = "        run: bash apps/web-platform/test/infra/workspaces-luks-deadman-fired-alert.test.sh\n"
assert s.count(old) == 1
s = s.replace(old, old + "        run: echo \"SEAM_PROBE=1\" >> \"\x24GITHUB_ENV\"\n")' \
    "job-scope-env-write"
  mutate_red "the suite's step gains an if: (a conditional step can be skipped green)" IV \
    'old = "        run: bash apps/web-platform/test/infra/workspaces-luks-deadman-fired-alert.test.sh\n"
assert s.count(old) == 1
s = s.replace(old, "        if: false\n" + old)' \
    "conditional, non-blocking, redirected or unaggregated"
  mutate_red "the suite's step becomes non-blocking (continue-on-error:)" IV \
    'old = "        run: bash apps/web-platform/test/infra/workspaces-luks-deadman-fired-alert.test.sh\n"
assert s.count(old) == 1
s = s.replace(old, "        continue-on-error: true\n" + old)' \
    "conditional, non-blocking, redirected or unaggregated"
  mutate_red "the suite's job header gains continue-on-error:" IV \
    'old = "        run: bash apps/web-platform/test/infra/workspaces-luks-deadman-fired-alert.test.sh\n"
assert s.count(old) == 1
j = s.rindex("    steps:\n", 0, s.index(old))
s = s[:j] + "    continue-on-error: true\n" + s[j:]' \
    "conditional, non-blocking, redirected or unaggregated"
  # Key-shape / key-order rows (#11899 convention): each new axis the composite's allowlists
  # and literals pin — a static env: on the step or the job, an if: carried on the dash line,
  # a post-steps continue-on-error:, a second if:, and a file-wide defaults:.
  mutate_red "the registered step gains a static env: key (a step key beyond name/run is listed)" IV \
    "$IV_ANCH"'assert s.count(RUN) == 1
s = s.replace(RUN, "        env:\n          INNOCENT_STEP_KEY: x\n" + RUN)' \
    "conditional, non-blocking, redirected or unaggregated"
  mutate_red "the hosting job gains a job-level env: key (a job key beyond the known set is listed)" IV \
    "$IV_ANCH"'assert s.count(HOSTH) == 1
s = s.replace(HOSTH, HOSTH + "    env:\n      INNOCENT_JOB_KEY: x\n")' \
    "conditional, non-blocking, redirected or unaggregated"
  mutate_red "the registered step's condition moves onto its dash line (      - if:)" IV \
    "$IV_ANCH"'old = "      - name: Run workspaces-LUKS dead-man fired alert drift guard (#9045)\n"
assert s.count(old) == 1
s = s.replace(old, "      - if: false\n        name: Run workspaces-LUKS dead-man fired alert drift guard (#9045)\n")' \
    "conditional, non-blocking, redirected or unaggregated"
  mutate_red "a job-level continue-on-error: lands AFTER the job's steps (YAML key order is free)" IV \
    "$IV_ANCH"'assert s.count(AFTER) == 1
s = s.replace(AFTER, "          fi\n    continue-on-error: true\n\n  # Aggregator (#8736): the single verdict")' \
    "conditional, non-blocking, redirected or unaggregated"
  mutate_red "the hosting job gains a SECOND if: key (the one-literal equality must see two)" IV \
    "$IV_ANCH"'assert s.count(HOSTH) == 1
s = s.replace(HOSTH, HOSTH + "    if: false\n")' \
    "conditional, non-blocking, redirected or unaggregated"
  mutate_red "the workflow gains a top-level defaults: (a run-shell redirect for every step)" IV \
    'old = "\nenv:\n  TERRAFORM_VERSION"
assert s.count(old) == 1
s = s.replace(old, "\ndefaults:\n  run:\n    shell: /bin/true {0}\nenv:\n  TERRAFORM_VERSION")' \
    "top-level-defaults"

  # ── Scorer negative control ────────────────────────────────────────────────────────────────
  mutate_red "scorer control: paused-flip reds a different row than the named fragment" TF \
    's = edit(s, ALRRES, "  paused = false\n", "  paused = true\n")' \
    "this-fragment-does-not-exist" wrong

  # ── Floor row ──────────────────────────────────────────────────────────────────────────────
  mutate_floor_red "assertion floor trips when PRESENCE_ROWS is bumped one past the real count"

  # ── must-PASS rows ─────────────────────────────────────────────────────────────────────────
  # Over-breadth control: a $GITHUB_ENV write is legitimate in ANOTHER job — the job-scope
  # ban binds only the slice enclosing THIS suite's run line (the plan: job carries real
  # writes today).
  mutate_green "a GITHUB_ENV write lands in the plan: job (outside this suite's enclosing job)" IV \
    'old = "          } >> \"\x24GITHUB_ENV\"\n"
assert s.count(old) == 1
s = s.replace(old, old + "          echo \"CROSS_JOB_PROBE=1\" >> \"\x24GITHUB_ENV\"\n")'
  mutate_green "the four conjuncts reordered (the canon is a set, order-insensitive by design)" TF \
    'i = s.index(SQLLOC); j = s.index(SQLEND, i)
blk = s[i:j]
a = "      AND JSONExtractString(raw, \x27SYSLOG_IDENTIFIER\x27) = \x27luks-monitor\x27\n"
b = "      AND position(JSONExtractString(raw, \x27message\x27), \x27op=workspaces-luks-deadman result=fired\x27) > 0\n"
assert blk.count(a) == 1 and blk.count(b) == 1
s = s[:i] + blk.replace(a, "@@A@@").replace(b, a).replace("@@A@@", b) + s[j:]'
fi

# ── Assertion floor + ledger (constructible: pure assignments only inside the window) ────────
# PRESENCE_ROWS is exactly the count of rows an inner (MUT_SKIP) run asserts; the outer run adds
# one row per mutation. The instrument control is what catches a floor drifting past the rows.
# Floor/ledger trips exit 1 (verdict-class: the battery grades inner rc 1 as a CAUGHT mutation);
# instrument failures exit 2.
# Self-reference (accepted residual, #11899 item 8): PRESENCE_ROWS/MUT_ROWS are written only
# in THIS file — a row deletion paired with a decrement stays green+FIRES; review covers it.
PRESENCE_ROWS=29
MUT_ROWS=42
_eff=${MUT_SKIP:+0}
_eff=${_eff:-$MUT_ROWS}
_floor=$((PRESENCE_ROWS + _eff))
_ran=$((pass + fail))
if [ "$_ran" -lt "$_floor" ]; then
  printf '[FATAL] assertion floor: %s ran, floor %s\n' "$_ran" "$_floor" >&2
  exit 1
fi
if [ "${#FAILED[@]}" -ne "$fail" ]; then
  printf '[FATAL] ledger %s != fail counter %s\n' "${#FAILED[@]}" "$fail" >&2
  exit 1
fi
[ -n "${MUT_SKIP:-}" ] && printf '[note] MUT_SKIP active — mutation rows skipped (floor %s); DEADMAN_GUARD_{TF,WF,CUT,IV}=%s,%s,%s,%s\n' "$_floor" "${DEADMAN_GUARD_TF:-unset}" "${DEADMAN_GUARD_WF:-unset}" "${DEADMAN_GUARD_CUT:-unset}" "${DEADMAN_GUARD_IV:-unset}"
printf '\n=== workspaces-luks-deadman-fired-alert: %s passed, %s failed (%s assertions, floor %s) ===\n' "$pass" "$fail" "$_ran" "$_floor"
[ "$fail" -eq 0 ]
