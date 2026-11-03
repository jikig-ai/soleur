#!/usr/bin/env bash
#
# Drift guard for the "web NIC guard refused to POST to an unpinned ingest URL" Better Stack
# Logs alert (apps/web-platform/infra/betterstack-logs-alerts.tf,
# logtail_exploration_alert.web_nic_guard_unpinned_url) — #9639 F8.
#
# WHAT THE ALERT IS FOR. web-private-nic-guard.sh refuses to send the Better Stack token to a
# destination other than the pinned ingest URL: on its `[nic] unpinned_url:` stderr line the POST
# is withheld AND the liveness beat lapses (a guard that cannot report must not claim health).
# The line is journald-tagged SYSLOG_IDENTIFIER='web-nic-guard' at PRIORITY 6 — NOT a SOLEUR_*
# PRIORITY-2 marker, so monitor_send_failed's predicate cannot see it. Without this alert the
# refusal mode was visible only through a post-merge query (betterstack-log-query.md's decode).
#
# WHAT THIS FILE PROTECTS, and why each row exists:
#   * The needle is PINNED TO THE EMITTER: the `unpinned_url` literal is read from
#     web-private-nic-guard.sh's own stderr line, so a one-sided reword in the .tf reds here
#     instead of silently disarming the alert (a COORDINATED rename needs a guard edit too).
#   * The predicate is compared WHOLE, whitespace-normalised, against the string built from that
#     needle: SYSLOG_IDENTIFIER='web-nic-guard' AND position(message,'unpinned_url') > 0, and NO
#     host_name conjunct — the guard timer runs on web-1 and is baked for web-2-class hosts, and
#     either can refuse (the #8706 host-conjunct trap in reverse: a threshold-any-row alert).
#   * The paging semantics are monitor_send_failed's (check 60 / query 300 / confirmation 0 /
#     recovery 600, higher_than 0, treat_as_zero, unpaused, email, the free/paid escalation
#     ternary, critical_alert=false).
#   * Both resources are in the apply workflow's MAIN plan -target= allowlist. This guard is the
#     ONLY enforcement of that for logtail resources (terraform-target-parity.test.ts covers
#     terraform_data only).
#   * The runbook exists, the standing-alarms table in betterstack-log-query.md names the alert,
#     and infra-validation.yml runs this guard in a blocking step with the runbook path in
#     pull_request paths.
#
# WHAT THIS FILE NOW PROVES (post-#11720 convention):
#   * CANONICAL EQUALITY — the flattened heredoc must EQUAL the string built from the emitter's
#     own needle (derived, never re-pinned), so dead text and arithmetic edits go red; decoy
#     heredoc and resource openers are counted file-wide and red.
#   * BLOCK-SCOPED EXACTLY-ONCE PINS — every alert attribute is asserted inside its own resource
#     block by param(), whole value line anchored both ends, required exactly once.
#   * THE BATTERY CANNOT BE MUTED — MUT_SKIP skips mutation rows on an inner run only; the
#     pristine-child control FATALs (rc 2) otherwise; UNPINNED_GUARD_/MUT_SKIP literals may not
#     reach the workflow's executable text (the seam check).
#   * RC DISCRIMINATION — only rc=1 (a real [FAIL] verdict) is a caught mutation; instrument
#     failures (rc>=2) are UNRESOLVED. Floor/ledger trips exit 1.
#
# WHAT THIS FILE DOES NOT PROVE: that the alert is armed IN PRODUCTION (created by an apply; the
# reconciler's `logs_alert` arm reads the live world twice daily), nor that a real row reaches
# Better Stack. It compares values one diff can edit together — consistency, not integrity; the
# live-probe step in the .tf comment (betterstack-query.sh positive control) is the anchor
# outside this file.
#
# Mutation rows live at the bottom. Each COPIES one source file into a scratch dir, mutates the
# COPY, and re-runs this guard against it through the UNPINNED_GUARD_* overrides. No tracked
# file is written.
set -uo pipefail
export TMPDIR="${TMPDIR:-/var/tmp}"

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
command -v python3 >/dev/null 2>&1 || { printf '[FATAL] python3 missing — the mutation battery needs it\n' >&2; exit 2; }
REPO="$(cd "$DIR/../../../.." && pwd)"
TF="${UNPINNED_GUARD_TF:-$REPO/apps/web-platform/infra/betterstack-logs-alerts.tf}"
WF="${UNPINNED_GUARD_WF:-$REPO/.github/workflows/apply-web-platform-infra.yml}"
EM="${UNPINNED_GUARD_EM:-$REPO/apps/web-platform/infra/web-private-nic-guard.sh}"
RB="${UNPINNED_GUARD_RB:-$REPO/knowledge-base/engineering/operations/runbooks/web-nic-guard-unpinned-url-alert.md}"
LQ="${UNPINNED_GUARD_LQ:-$REPO/knowledge-base/engineering/operations/runbooks/betterstack-log-query.md}"
IV="${UNPINNED_GUARD_IV:-$REPO/.github/workflows/infra-validation.yml}"

pass=0; fail=0; FAILED=()
ok() { pass=$((pass + 1)); printf '[ok] %s\n' "$1"; }
no() { fail=$((fail + 1)); FAILED+=("$1"); printf '[FAIL] %s\n' "$1"; }

# Byte-identical to the ghcr-blocked-alert copy (the P1b assert_fixture_dir shape): a cd-failed
# override yields EMPTY and would root every read at /.
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
assert_fixture_dir "$TF"; assert_fixture_dir "$WF"; assert_fixture_dir "$EM"; assert_fixture_dir "$RB"; assert_fixture_dir "$LQ"; assert_fixture_dir "$IV"

# INSTRUMENT SELF-TEST — both helpers must move their own counter before any verdict is trusted.
_p0=$pass; _f0=$fail
{ ok "self-test"; no "self-test"; } >/dev/null
if [ "$pass" -ne $((_p0 + 1)) ] || [ "$fail" -ne $((_f0 + 1)) ] || [ "${#FAILED[@]}" -ne 1 ]; then
  printf '[FATAL] instrument self-test: ok()/no() did not each move their counter\n' >&2; exit 2
fi
pass=$_p0; fail=$_f0; FAILED=()

for f in "$TF" "$WF" "$EM" "$RB" "$LQ" "$IV"; do
  [ -r "$f" ] || { printf '[FATAL] unreadable: %s\n' "$f" >&2; exit 2; }
done

# Extract a <<[-]SQL heredoc local by name: first line after `name = <<[-]SQL` to its `  SQL` terminator.
sql_local() {  # sql_local <local-name>
  awk -v n="$1" '
    $0 ~ "^[[:space:]]*" n "[[:space:]]*=[[:space:]]*<<[-]SQL" { f=1; next }
    f && /^  SQL$/ { f=0 }
    f { print }
  ' "$TF"
}
# res_block: one resource block from its column-0 header to its column-0 closing brace.
res_block() {  # res_block <type> <name>
  awk -v h="resource \"$1\" \"$2\" {" '$0 == h {f=1} f{print} f && /^}/{exit}' "$TF"
}
# param <block> <attr> <value-ERE>: whole-line attribute assertion INSIDE a block, anchored
# both ends, required EXACTLY ONCE — a decoy or duplicated line is a red, not a shrug.
param() {
  # Value-matching exactly-once. Residual gap (accepted): a planted same-attr/different-value
  # line does not move this count — attr-name cardinality cannot apply here because blocks
  # legitimately nest a second `name` (explorations' `variable { name = "source" }`), and HCL
  # itself rejects duplicate attributes at validate. Mute/deletion classes are still covered.
  [ "$(printf '%s\n' "$1" | grep -cE "^[[:space:]]*$2[[:space:]]*=[[:space:]]*$3[[:space:]]*(#.*)?$")" -eq 1 ]
}

# The predicate heredoc, from the FIRST UNCOMMENTED opening line to its own terminator.
LOCAL_SQL="$(sql_local web_nic_guard_unpinned_url_sql)"
# Layout-independent view: every run of whitespace is one space, and no space sits inside a
# parenthesis pair (the resource collapses it the same way).
SQL_1="$(tr '\n' ' ' <<< "$LOCAL_SQL" | sed 's/[[:space:]][[:space:]]*/ /g; s/( /(/g; s/ )/)/g; s/^ //; s/ $//')"
ALERT="$(res_block logtail_exploration_alert web_nic_guard_unpinned_url)"
EXPL="$(res_block logtail_exploration web_nic_guard_unpinned_url)"
# The push-triggered MAIN plan: from the first `terraform plan -no-color` to the first `rc=` line-start
# (the step's rc=${PIPESTATUS[0]} capture — the only rc= line-start inside the step). The workflow has
# other plan commands whose -target lists never run on a push to main, so the allowlist rows below read
# THIS region, not the whole file — and the terminator itself is asserted, so a deleted or moved rc
# line fails loud instead of silently re-opening a run-past-the-step slice.
MAIN_PLAN="$(awk '/^[[:space:]]*terraform plan -no-color/{f=1} f{print} f&&/^[[:space:]]*rc=/{exit}' "$WF")"
[ "$(printf '%s\n' "$MAIN_PLAN" | tail -1 | grep -cE '^[[:space:]]*rc=\$\{PIPESTATUS\[0\]\}$')" -eq 1 ] \
  && ok "the MAIN plan slice ends on the rc=\${PIPESTATUS[0]} capture line (the -target= rows grade exactly the plan step's span)" \
  || no "the MAIN plan slice does not end on the rc=\${PIPESTATUS[0]} capture line — the -target= pins below would grade a run-past span"

# Opener/header counts — unanchored, file-wide, exactly once each. A /* */- or #-wrapped
# decoy opener still counts and goes red; dead text can never satisfy the live local.
_n="$(grep -cE 'web_nic_guard_unpinned_url_sql[[:space:]]*=[[:space:]]*<<[-]SQL' "$TF")"
[ "$_n" -eq 1 ] \
  && ok "exactly one web_nic_guard_unpinned_url_sql heredoc opener in the file (decoy copies count)" \
  || no "web_nic_guard_unpinned_url_sql opener count is $_n, want 1 — a decoy local exists"
for _r in "logtail_exploration web_nic_guard_unpinned_url" "logtail_exploration_alert web_nic_guard_unpinned_url"; do
  _n="$(grep -cE "resource \"${_r%% *}\" \"${_r##* }\"" "$TF")"
  [ "$_n" -eq 1 ] \
    && ok "exactly one resource ${_r} header in the file" \
    || no "resource ${_r} header count is $_n, want 1 — a decoy resource exists"
done

[ -n "$LOCAL_SQL" ] \
  && ok "the predicate local is a heredoc this guard can read" \
  || no "web_nic_guard_unpinned_url_sql: heredoc not found — every predicate row below would be vacuous"

# ── the emitter: the needle is READ, not retyped ──────────────────────────────────────────────
# The refusal line is `echo "[nic] unpinned_url: refusing to send the Better Stack token to an
# unpinned destination — …"` on stderr in the unpinned arm. The needle the alert matches is the
# `unpinned_url` literal INSIDE that line; a reworded emitter (or a reworded .tf) reds below.
EMIT_LINE="$(grep -nE 'unpinned_url' "$EM" | grep 'echo' | grep -vE '^[0-9]+:[[:space:]]*#' | head -1)"
EMIT_NEEDLE="$(sed -n 's/.*\[nic\] \([a-z_]*\):.*/\1/p' <<< "$EMIT_LINE" | head -1)"
if [ -n "$EMIT_LINE" ] && [ "$EMIT_NEEDLE" = "unpinned_url" ]; then
  ok "web-private-nic-guard.sh emits exactly the '[nic] unpinned_url:' refusal line; needle captured from it"
else
  no "web-private-nic-guard.sh no longer emits a '[nic] unpinned_url:' refusal line — the alert would silently stop matching (got needle '${EMIT_NEEDLE:-<none>}')"
fi
# The refusal withholds the beat: the unpinned arm must sit inside a SHIP_REFUSED=true branch, or
# a page would mean "alert on a healthy POST". Read the arm ordering: SHIP_REFUSED=true must be
# assigned in the arm that echoes the needle.
if grep -qE 'SHIP_REFUSED=true' < <(grep -nB6 'unpinned_url' "$EM"); then
  ok "the unpinned_url arm withholds the beat (SHIP_REFUSED=true sits in the same arm)"
else
  no "the unpinned_url arm no longer sets SHIP_REFUSED — the alert would page on a beat the guard still sends"
fi

# ── the predicate, compared whole ─────────────────────────────────────────────────────────────
_msg="JSONExtractString(raw, 'message')"
EXPECT_SQL="SELECT {{time}} AS time, count(*) AS value FROM {{source}} WHERE time BETWEEN {{start_time}} AND {{end_time}}"
EXPECT_SQL+=" AND JSONExtractString(raw, 'SYSLOG_IDENTIFIER') = 'web-nic-guard' AND position(${_msg}, 'unpinned_url') > 0 GROUP BY time"
if [ -n "$EMIT_NEEDLE" ] && [ "$EMIT_NEEDLE" = "unpinned_url" ] && [ "$SQL_1" = "$EXPECT_SQL" ]; then
  ok "the predicate equals the string built from the emitter's own needle (tag + position, nothing else)"
else
  no "the predicate is not the expected conjunct pair built from the emitter's needle"
fi
grep -qF "JSONExtractString(raw, 'SYSLOG_IDENTIFIER') = 'web-nic-guard'" <<< "$SQL_1" \
  && ok "the tag conjunct: SYSLOG_IDENTIFIER = 'web-nic-guard'" \
  || no "the SYSLOG_IDENTIFIER='web-nic-guard' conjunct is missing or altered"
grep -qF "position(${_msg}, 'unpinned_url') > 0" <<< "$SQL_1" \
  && ok "the needle conjunct: position(message, 'unpinned_url') > 0 (a row merely absent the marker cannot alert)" \
  || no "the unpinned_url needle conjunct is missing or altered"
if grep -qiE '(^|[^A-Za-z_])NOT([^A-Za-z_]|$)|!=|<>' <<< "$LOCAL_SQL"; then
  no "the predicate carries a negation — an unreadable row would read as a refusal"
else
  ok "the predicate has no negation"
fi
grep -qi 'host_name' <<< "$LOCAL_SQL" \
  && no "the predicate carries a host_name conjunct — it would blind the OTHER web host's refusals (the #8706 trap in reverse)" \
  || ok "no host_name conjunct: a refusal on web-1 or web-2 alerts"

param "$EXPL" 'sql_query' 'replace\(trimspace\(local\.web_nic_guard_unpinned_url_sql\), "/\\\\s\+/", " "\)' \
  && ok "the exploration carries THIS predicate, collapsed to one line (the sibling's perpetual-diff rule)" \
  || no "the exploration does not carry local.web_nic_guard_unpinned_url_sql as its sql_query"
param "$EXPL" 'values' '\[local\.vector_prd_source_id\]' \
  && ok "the exploration reads the prd Vector source" \
  || no "the exploration's source variable is not local.vector_prd_source_id"
[ "$(grep -cE '^  query \{' <<< "$EXPL")" -eq 1 ] && [ "$(grep -cE '^  variable \{' <<< "$EXPL")" -eq 1 ] \
  && param "$EXPL" 'source_variable' '"source"' \
  && param "$EXPL" 'query_type' '"sql_expression"' \
  && param "$EXPL" 'name' '"source"' \
  && ok "the exploration has exactly one query and one variable block, wired source_variable=source -> variable source" \
  || no "the exploration's query/variable wiring is not exactly one sql_expression query reading variable \"source\""

[ -n "$ALERT" ] && ok "logtail_exploration_alert.web_nic_guard_unpinned_url exists (exact header)" \
  || no "logtail_exploration_alert.web_nic_guard_unpinned_url is missing"
param "$ALERT" 'exploration_id' 'logtail_exploration\.web_nic_guard_unpinned_url\.id' \
  && ok "the alert watches ITS OWN exploration" \
  || no "the alert's exploration_id is not logtail_exploration.web_nic_guard_unpinned_url.id"
param "$ALERT" 'name' '"soleur-web-nic-guard-unpinned-url-prd"' \
  && param "$EXPL" 'name' '"soleur-web-nic-guard-unpinned-url-prd"' \
  && ok "both are named soleur-web-nic-guard-unpinned-url-prd" \
  || no "the exploration/alert name drifted from soleur-web-nic-guard-unpinned-url-prd"
param "$ALERT" 'alert_type' '"threshold"' \
  && param "$ALERT" 'operator' '"higher_than"' \
  && param "$ALERT" 'value' '0' \
  && ok "threshold, higher_than 0: ONE unpinned_url row alerts" \
  || no "the alert is not threshold/higher_than/0 — a single refusal row would not alert"
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
  && param "$ALERT" 'push' 'false' \
  && param "$ALERT" 'call' 'false' \
  && param "$ALERT" 'sms' 'false' \
  && param "$ALERT" 'critical_alert' 'false' \
  && ok "email = true, push/call/sms/critical_alert = false (the free-tier sibling channel set)" \
  || no "the channel set drifted from the sibling shape (email-only, critical_alert=false)"
param "$ALERT" 'confirmation_period' '0' \
  && param "$ALERT" 'check_period' '60' \
  && param "$ALERT" 'query_period' '300' \
  && param "$ALERT" 'recovery_period' '600' \
  && ok "check 60 / query 300 / recovery 600 with no confirmation delay (monitor_send_failed's combination)" \
  || no "the paging windows drifted from check 60 / query 300 / confirmation 0 / recovery 600"
if grep -qE '^[[:space:]]*(count|for_each|lifecycle|ignore_changes)\b' <<< "$ALERT"$'\n'"$EXPL"; then
  no "the alert or exploration carries count/for_each/lifecycle/ignore_changes — the resource could silently not exist or never reconcile"
else
  ok "no count/for_each/lifecycle/ignore_changes on the alert or exploration (the resource exists and reconciles)"
fi
param "$ALERT" 'policy_id' 'var\.betterstack_paid_tier \? tonumber\(betteruptime_policy\.uptime\[0\]\.id\) : null' \
  && param "$ALERT" 'team_name' 'var\.betterstack_paid_tier \? null : "Your team"' \
  && ok "the escalation target is the free/paid ternary every sibling uses (ADR-218)" \
  || no "the escalation_target drifted from the sibling ternary"
# The incident text must not claim resolution means a fix: the alert auto-resolves after quiet minutes.
grep -qE '^  incident_cause[[:space:]]*=.*does NOT mean' <<< "$ALERT" \
  && ok "the incident text says resolution does NOT mean the cause was fixed" \
  || no "the incident text no longer warns that auto-resolution is not a fix"

RB_URL_RE='^[[:space:]]*web_nic_guard_unpinned_url_runbook_url[[:space:]]*=[[:space:]]*"https://github\.com/jikig-ai/soleur/blob/main/knowledge-base/engineering/operations/runbooks/web-nic-guard-unpinned-url-alert\.md"'
grep -qE '^  incident_cause[[:space:]]*=.*[Rr]unbook: \$\{local\.web_nic_guard_unpinned_url_runbook_url\}"[[:space:]]*$' <<< "$ALERT" \
  && param "$ALERT" 'runbook' 'local\.web_nic_guard_unpinned_url_runbook_url' \
  && grep -qE "$RB_URL_RE" "$TF" \
  && ok "incident_cause and metadata.runbook carry the alert's runbook URL (the email is what a reader acts on)" \
  || no "the incident has no clickable web-nic-guard-unpinned-url runbook URL"

[ -f "$RB" ] \
  && ok "the runbook file exists (knowledge-base/engineering/operations/runbooks/web-nic-guard-unpinned-url-alert.md)" \
  || no "the runbook file is missing"
[ -f "$RB" ] && grep -qF 'unpinned_url' "$RB" && grep -qF 'web-nic-guard' "$RB" \
  && ok "the runbook names the marker and the SYSLOG_IDENTIFIER an operator reads" \
  || no "the runbook no longer names unpinned_url / web-nic-guard"
grep -qF 'logtail_exploration_alert.web_nic_guard_unpinned_url' "$LQ" \
  && ok "betterstack-log-query.md's standing-alarms table names the alert" \
  || no "the standing-alarms row in betterstack-log-query.md is missing"

grep -qE '^[[:space:]]*-target=logtail_exploration\.web_nic_guard_unpinned_url \\$' <<< "$MAIN_PLAN" \
  && grep -qE '^[[:space:]]*-target=logtail_exploration_alert\.web_nic_guard_unpinned_url \\$' <<< "$MAIN_PLAN" \
  && ok "both resources are in the push-triggered MAIN plan's -target= allowlist (#5566: an untargeted resource is never applied)" \
  || no "one or both -target= lines are missing — the alert would never exist in Better Stack"
# Reachability: -target= lines only matter if a merge to main runs this plan at all.
WF_PUSH="$(awk '/^on:$/{o=1;next} o&&/^[a-z]/{exit} o&&/^  push:$/{p=1;next} o&&p&&/^  [a-z_]+:/{exit} p{print}' "$WF")"
if grep -qxF '    branches: [main]' <<< "$WF_PUSH" && grep -qxF '      - "apps/web-platform/infra/**"' <<< "$WF_PUSH" \
   && [ -z "$(grep -E '^      - "!' <<< "$WF_PUSH" | grep -vxF -e '      - "!apps/web-platform/infra/rung2-rehearsal/**"' -e '      - "!apps/web-platform/infra/git-data-root-key/**"' -e '      - "!apps/web-platform/infra/inngest-provision-rehearsal/**"' -e '      - "!apps/web-platform/infra/lb-staging/**"' || true)" ] \
   && [ "$(grep -cxF "      (github.event_name == 'push' || inputs.apply_target == 'manual-rerun')" "$WF")" -eq 1 ]; then
  ok "apply-web-platform-infra.yml's push block runs on main for apps/web-platform/infra/** with no path negation beyond the four known sub-roots, and the apply job runs on push (the alert is created by the merge, not by hand)"
else
  no "apply-web-platform-infra.yml no longer triggers the apply on push to main for apps/web-platform/infra/** (branch, path, a negation of the alert's file, or the apply job's push clause changed) — the alert would not be created on merge"
fi

# This guard only runs in CI if infra-validation.yml runs it, and re-runs on a runbook edit or an
# edit of the apply workflow (both read from the pull_request block, not anywhere in the file).
IV_PR="$(awk '/^  pull_request:$/{p=1;next} p&&/^  [a-z_]+:/{exit} p{print}' "$IV")"
IV_JOB="$(awk '/^  deploy-script-tests-fixed:$/{f=1;print;next} f&&/^  [A-Za-z0-9_-]+:$/{exit} f{print}' "$IV")"
IV_STEP="$(awk '/^      - name: Run web NIC guard unpinned ingest URL refusal alert drift guard \(#9639\)$/{f=1;print;next} f&&/^      - name:/{exit} f{print}' <<< "$IV_JOB")"
IV_HDR="$(awk '/^    steps:$/{exit} {print}' <<< "$IV_JOB")"
if [ "$(grep -cxF '      - "knowledge-base/engineering/operations/runbooks/web-nic-guard-unpinned-url-alert.md"' <<< "$IV_PR")" -eq 1 ] \
   && [ "$(grep -cxF '      - ".github/workflows/apply-web-platform-infra.yml"' <<< "$IV_PR")" -eq 1 ] \
   && [ "$(grep -cxF '        run: bash apps/web-platform/test/infra/web-nic-guard-unpinned-url-alert.test.sh' <<< "$IV_STEP")" -eq 1 ] \
   && ! grep -qE '^        (if|continue-on-error):' <<< "$IV_STEP" \
   && [ "$(grep -cxF "    if: needs.detect-changes.outputs.pr_duplicate != 'true'" <<< "$IV_HDR")" -eq 1 ] \
   && ! grep -qE '^    continue-on-error:' <<< "$IV_HDR"; then
  ok "infra-validation.yml's pull_request paths list the runbook and the apply workflow, and deploy-script-tests-fixed runs this guard in an unconditional, blocking step"
else
  no "infra-validation.yml no longer wires this guard: runbook or apply-workflow path missing from pull_request paths, the step missing/conditional/non-blocking, or its job conditional/non-blocking"
fi

# ── Workflow seam — registered exactly once, and no env axis reaches executable text ─────────
IV_CODE="$(awk '!/^[[:space:]]*#/' "$IV")"
REG_RUN='        run: bash apps/web-platform/test/infra/web-nic-guard-unpinned-url-alert.test.sh'
n_run="$(printf '%s\n' "$IV_CODE" | grep -cFx "$REG_RUN")"
[ "$n_run" -eq 1 ] \
  && ok "this suite's run line is registered in infra-validation.yml exactly once" \
  || no "run line count is $n_run, want 1 — the suite is unregistered or double-registered"
# Fragments, not literals (#11899): a runtime-composed name — "MUT_""SKIP" or a *_GUARD_* built
# from quoted pieces — reaches the battery with no full literal ever present. MUT_/_SKIP catch
# MUT_SKIP split at either boundary; bare GUARD catches any *_GUARD_* prefix; BASH_ENV/SHELLOPTS/
# BASHOPTS bar the shell-injection envs a composer could smuggle the name through.
seam_bad=""
for _frag in 'MUT_' '_SKIP' 'GUARD' 'BASH_ENV' 'SHELLOPTS' 'BASHOPTS'; do
  printf '%s\n' "$IV_CODE" | grep -nF "$_frag" >/dev/null && seam_bad="$seam_bad ${_frag}-fragment"
done
# The only remaining channel is dynamic: a $GITHUB_ENV/$GITHUB_PATH write or a defaults: shell
# inside THIS suite's enclosing job (env: keys are static — the fragments above already cover them).
# The job slice is derived from the pinned run line — walk back to its `^  name:` header, forward
# to the next — never a hardcoded job name. An empty or missliced slice would pass the ban
# vacuously, so it must be non-empty AND contain the run line before the ban applies.
IV_JOB_SEAM="$(printf '%s\n' "$IV_CODE" | awk -v run="$REG_RUN" '
  /^  [a-zA-Z_][a-zA-Z0-9_-]*:/ { hdr = NR }
  $0 == run { rl = NR; encl = hdr }
  { L[NR] = $0 }
  END {
    if (!rl) exit 1
    for (i = encl; i <= NR; i++) {
      if (i > rl && L[i] ~ /^  [a-zA-Z_][a-zA-Z0-9_-]*:/) break
      print L[i]
    }
  }')"
if [ -n "$IV_JOB_SEAM" ] && [ "$(printf '%s\n' "$IV_JOB_SEAM" | grep -cFx "$REG_RUN")" -eq 1 ]; then
  for _jb in 'GITHUB_ENV' 'GITHUB_PATH' 'defaults:'; do
    printf '%s\n' "$IV_JOB_SEAM" | grep -nF "$_jb" >/dev/null && seam_bad="$seam_bad in-job-${_jb}"
  done
else
  seam_bad="$seam_bad job-slice-miss"
fi
[ -z "$seam_bad" ] \
  && ok "no guard/battery env fragment reaches the workflow's executable text, and this suite's job writes no \$GITHUB_ENV/\$GITHUB_PATH and sets no defaults: (env muting is barred)" \
  || no "workflow seam violated:$seam_bad — a guard env axis is reachable from infra-validation.yml"

echo "=== web-nic-guard-unpinned-url-alert guard: $pass passed, $fail failed ==="
if [ "$fail" -gt 0 ]; then
  printf 'FAILED: %s\n' "${FAILED[@]}" >&2
  exit 1
fi

# ── Mutation rows: each must make a row above RED ─────────────────────────────────────────────
# OUTER RUN ONLY. Each row copies ONE source file into $MUT_DIR, mutates the copy, and re-runs this
# guard with MUT_SKIP=1 and the matching UNPINNED_GUARD_* override pointing at the copy.
SELF="$DIR/$(basename "${BASH_SOURCE[0]}")"
if [ -z "${MUT_SKIP:-}" ]; then
  MUT_DIR="$(mktemp -d -t unpinnedalert.XXXXXX)" || { printf '[FATAL] mktemp failed\n' >&2; exit 2; }
  trap 'rm -rf "$MUT_DIR"' EXIT
  assert_fixture_dir "$MUT_DIR"

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
def sql_replace(s, old, new):
    # The first occurrence AFTER the predicate local opener: other alerts in this file carry
    # identical conjuncts earlier on.
    i = s.index("  web_nic_guard_unpinned_url_sql = <<\x2dSQL")
    j = s.index(old, i)
    return s[:j] + new + s[j + len(old):]
SQLLOC = "  web_nic_guard_unpinned_url_sql = <<\x2dSQL"
SQLEND = "\n  SQL\n"
ALRRES = "resource \"logtail_exploration_alert\" \"web_nic_guard_unpinned_url\" {"'

  _red_verdict() {
    case "$1" in
      1) if [ -z "$3" ] || { grep -F '[FAIL]' "$2" | grep -F -- "$3" >/dev/null; }; then echo red; else echo wrong; fi ;;
      0) echo survived ;;
      *) echo unresolved ;;
    esac
  }

  # mutate_red <label> <TF|WF|EM|RB|LQ|IV> <python-program-on-s> [expected [FAIL] fragment] [red|wrong]
  mutate_red() {
    local label="$1" which="$2" prog="$3" tag="${4:-}" want="${5:-red}" src copy rc=0 olog="$MUT_DIR/inner.log"
    MUT_ROWS_RUN=$((MUT_ROWS_RUN + 1))
    case "$which" in
      TF) src="$TF"; copy="$MUT_DIR/betterstack-logs-alerts.tf" ;;
      WF) src="$WF"; copy="$MUT_DIR/apply-web-platform-infra.yml" ;;
      EM) src="$EM"; copy="$MUT_DIR/web-private-nic-guard.sh" ;;
      RB) src="$RB"; copy="$MUT_DIR/web-nic-guard-unpinned-url-alert.md" ;;
      LQ) src="$LQ"; copy="$MUT_DIR/betterstack-log-query.md" ;;
      IV) src="$IV"; copy="$MUT_DIR/infra-validation.yml" ;;
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
    env "UNPINNED_GUARD_${which}=$copy" MUT_SKIP=1 bash "$SELF" >"$olog" 2>&1 || rc=$?
    case "$(_red_verdict "$rc" "$olog" "$tag"):$want" in
      red:red) ok "mutation RED: $label" ;;
      wrong:wrong) ok "scorer control: graded WRONG reason as required: $label" ;;
      wrong:red) no "mutation went red for the WRONG reason (no [FAIL] line contains '$tag'): $label" ;;
      red:wrong) no "scorer control: the wrong-reason mutant was graded RED (the fragment check accepts anything): $label" ;;
      survived:*) no "mutation SURVIVED: $label — the rows above pin nothing" ;;
      *) no "mutation UNRESOLVED (inner rc=$rc, not an assertion): $label — instrument, not evidence" ;;
    esac
  }

  # mutate_green <label> <python-program-on-s> [TF|WF|EM|RB|LQ|IV] — a legitimate edit on one
  # fixture that must stay green on the inner run (the over-breadth controls). Default target is
  # TF, matching the predicate-layout rows.
  mutate_green() {
    local label="$1" prog="$2" which="${3:-TF}" src copy rc=0
    MUT_ROWS_RUN=$((MUT_ROWS_RUN + 1))
    case "$which" in
      TF) src="$TF"; copy="$MUT_DIR/green-betterstack-logs-alerts.tf" ;;
      WF) src="$WF"; copy="$MUT_DIR/green-apply-web-platform-infra.yml" ;;
      EM) src="$EM"; copy="$MUT_DIR/green-web-private-nic-guard.sh" ;;
      RB) src="$RB"; copy="$MUT_DIR/green-web-nic-guard-unpinned-url-alert.md" ;;
      LQ) src="$LQ"; copy="$MUT_DIR/green-betterstack-log-query.md" ;;
      IV) src="$IV"; copy="$MUT_DIR/green-infra-validation.yml" ;;
      *) printf '[FATAL] mutate_green: unknown target %s\n' "$which" >&2; exit 2 ;;
    esac
    cp "$src" "$copy" || { printf '[FATAL] mutate_green: cp %s failed\n' "$src" >&2; exit 2; }
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
    env "UNPINNED_GUARD_${which}=$copy" MUT_SKIP=1 bash "$SELF" >"$MUT_DIR/green.log" 2>&1 || rc=$?
    case "$rc" in
      0) ok "must-PASS edit stays green: $label" ;;
      1) no "legitimate edit went RED: $label" ;;
      *) no "must-PASS UNRESOLVED (inner rc=$rc): $label - instrument, not evidence" ;;
    esac
  }

  mutate_floor_red() {
    local label="$1" copy rc=0 cur
    MUT_ROWS_RUN=$((MUT_ROWS_RUN + 1))
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
  MUT_ROWS_RUN=0

  # A1 — the tag conjunct is dropped: unpinned_url rows under ANY identifier could alert.
  mutate_red "A1 the SYSLOG_IDENTIFIER conjunct is dropped (rows from any identifier could alert)" TF \
    's = sql_replace(s, "JSONExtractString(raw, \x27SYSLOG_IDENTIFIER\x27) = \x27web-nic-guard\x27\n      AND ", "")' \
    "the SYSLOG_IDENTIFIER='web-nic-guard' conjunct is missing"
  # A2 — the needle is reworded in the .tf while the emitter's line is untouched.
  mutate_red "A2 the needle is reworded in the .tf only (the alert would silently disarm)" TF \
    's = sql_replace(s, "\x27unpinned_url\x27", "\x27unpinned_dest\x27")' \
    "the unpinned_url needle conjunct is missing"
  # A3 — a -target= line is dropped from the apply allowlist.
  mutate_red "A3 the alert is dropped from the apply allowlist" WF \
    'old = "              -target=logtail_exploration_alert.web_nic_guard_unpinned_url \\\n"
assert s.count(old) == 1
s = s.replace(old, "")' \
    "one or both -target= lines are missing"
  # The MAIN_PLAN slice ends at the plan step's rc= capture: -target lines moved just below it, a
  # deleted capture, or a renamed capture each re-open the run-past-the-step overshoot (#11899).
  mutate_red "A3b the -target= lines move just below the plan step's rc= capture (the overshoot shape)" WF \
    'a = "              -target=logtail_exploration.web_nic_guard_unpinned_url \\\n"
b = "              -target=logtail_exploration_alert.web_nic_guard_unpinned_url \\\n"
assert s.count(a) == 1 and s.count(b) == 1
s = s.replace(a, "").replace(b, "")
i = s.index("          rc=\x24{PIPESTATUS[0]}\n") + len("          rc=\x24{PIPESTATUS[0]}\n")
s = s[:i] + a + b + s[i:]' \
    "one or both -target= lines are missing"
  mutate_red "A3c the plan step's rc= capture line is deleted (the slice terminator must not go silent)" WF \
    'old = "          rc=\x24{PIPESTATUS[0]}\n"
i = s.index(old)
s = s[:i] + s[i + len(old):]' \
    "does not end on the rc="
  mutate_red "A3d the plan step's rc= capture is renamed to plan_rc= (line-start no longer rc=)" WF \
    'old = "          rc=\x24{PIPESTATUS[0]}\n"
i = s.index(old)
s = s[:i] + "          plan_rc=\x24{PIPESTATUS[0]}\n" + s[i + len(old):]' \
    "does not end on the rc="
  mutate_green "A3e a second terraform plan block with decoy -target= lines after the real step (the slice grades the first span only)" \
    's = s + "\n            terraform plan -no-color -input=false \\\n              -target=logtail_exploration.web_nic_guard_unpinned_url \\\n              -target=logtail_exploration_alert.web_nic_guard_unpinned_url \\\n              -target=betteruptime_policy.decoy\n"' \
    WF
  # A4 — on_missing_data is no longer treat_as_zero: an open incident can never observe recovery.
  mutate_red "A4 on_missing_data is no longer treat_as_zero" TF \
    'import re
m = re.search(r"(resource \"logtail_exploration_alert\" \"web_nic_guard_unpinned_url\" \{.*?\n  on_missing_data\s*=\s*)\"treat_as_zero\"", s, re.S)
assert m
s = s[:m.end(1)] + "\"keep_last_value\"" + s[m.end():]' \
    "on_missing_data is not treat_as_zero"
  # A5 — the guard's OWN dispatch: the run: step goes non-blocking in infra-validation.yml.
  mutate_red "A5 the guard step becomes non-blocking (continue-on-error)" IV \
    'old = "        run: bash apps/web-platform/test/infra/web-nic-guard-unpinned-url-alert.test.sh\n"
assert s.count(old) == 1
s = s.replace(old, "        continue-on-error: true\n" + old)' \
    "infra-validation.yml no longer wires this guard"
  # A6 — the alert's exploration_id is repointed to another exploration.
  mutate_red "A6 the alert's exploration_id is repointed (identity row)" TF \
    'old = "  exploration_id = logtail_exploration.web_nic_guard_unpinned_url.id"
assert s.count(old) == 1
s = s.replace(old, "  exploration_id = logtail_exploration.monitor_send_failed.id")' \
    "the alert's exploration_id is not"
  # A7 — a host_name conjunct is added: the OTHER web host's refusals go silent.
  mutate_red "A7 a host_name conjunct is added (web-2's refusals would go silent)" TF \
    's = sql_replace(s, "\n    GROUP BY time", "\n      AND JSONExtractString(raw, \x27host_name\x27) = \x27soleur-web-platform\x27\n    GROUP BY time")' \
    "the predicate carries a host_name conjunct"
  # Must-PASS: layout is not part of the contract (the resource flattens the predicate with
  # replace(…, "/\\s+/", " ")).
  mutate_green "A8 every heredoc line is re-indented far deeper (layout is not part of the contract)" \
    'import re
i = s.index(SQLLOC)
j = s.index("\n  SQL\n", i)
head, rest = s[i:j].split("\n", 1)
s = s[:i] + head + "\n" + re.sub(r"(?m)^\s+", "                    ", rest) + s[j:]'

  # ── Dead-text / extraction-class rows ──────────────────────────────────────────────────────────
  mutate_red "a /* */-wrapped decoy heredoc sits before the live local while the live body is gutted" TF \
    's = edit(s, SQLLOC, "count(*) AS value", "count(*) * 0 AS value", SQLEND)
i = s.index(SQLLOC)
s = s[:i] + "/*\n  web_nic_guard_unpinned_url_sql = <<\x2dSQL\n  SELECT legit\n  SQL\n*/\n" + s[i:]' \
    "decoy local exists"
  mutate_red "a #-commented decoy opener line sits above the live local" TF \
    'i = s.index(SQLLOC)
s = s[:i] + "  # web_nic_guard_unpinned_url_sql = <<\x2dSQL\n" + s[i:]' \
    "decoy local exists"
  # EM dead-text row: a #-commented copy of the live refusal echo must NOT satisfy the needle —
  # the selector above filters `^[0-9]+:[[:space:]]*#` lines, so a silenced emitter reads as absent.
  mutate_red "the live refusal echo is commented out (dead-text disarm of the emitter needle)" EM \
    'hits = [l for l in s.splitlines(keepends=True) if "unpinned_url" in l and "echo" in l and not l.lstrip().startswith("#")]
assert hits, "no live echo needle line"
s = "".join("# " + l if l in hits else l for l in s.splitlines(keepends=True))' \
    "no longer emits a '[nic] unpinned_url:' refusal line"
  mutate_red "a commented-out paused=false decoy line appears inside the alert block" TF \
    's = edit(s, ALRRES, "  paused = false\n", "  paused = false\n  # paused = false\n")' \
    "decoy exists"
  mutate_red "an inline tautology is appended inside the predicate" TF \
    's = edit(s, SQLLOC, "GROUP BY time", "GROUP BY time OR 1=1", SQLEND)' \
    "the predicate is not the expected conjunct pair"
  mutate_red "a doubled-dollar escape literal appears inside the heredoc" TF \
    's = edit(s, SQLLOC, "count(*) AS value", "count(*) AS value /* \x24\x24escaped */", SQLEND)' \
    "the predicate is not the expected conjunct pair"
  mutate_red "the live predicate local is gutted to a placeholder while the resource keeps its name" TF \
    'i = s.index(SQLLOC); j = s.index(SQLEND, i)
blk = s[i:j]
assert "count(*) AS value" in blk
s = s[:i] + SQLLOC + "\n    SELECT 1" + s[j:]' \
    "the predicate is not the expected conjunct pair"

  # ── Workflow seam rows ────────────────────────────────────────────────────────────────────────
  mutate_red "a MUT_SKIP literal reaches the workflow's executable text" IV \
    'old = "        run: bash apps/web-platform/test/infra/web-nic-guard-unpinned-url-alert.test.sh\n"
assert s.count(old) == 1
s = s.replace(old, "        env:\n          MUT_SKIP: \"1\"\n" + old)' \
    "workflow seam"
  mutate_red "a UNPINNED_GUARD_ literal reaches the workflow's executable text" IV \
    'old = "        run: bash apps/web-platform/test/infra/web-nic-guard-unpinned-url-alert.test.sh\n"
assert s.count(old) == 1
s = s.replace(old, old + "        env:\n          UNPINNED_GUARD_TF: /dev/null\n")' \
    "workflow seam"
  mutate_red "the suite's own run line is dropped from the workflow" IV \
    'old = "        run: bash apps/web-platform/test/infra/web-nic-guard-unpinned-url-alert.test.sh\n"
assert s.count(old) == 1
s = s.replace(old, "")' \
    "unregistered or double-registered"
  # Composed/injected env names — no literal ever reaches the file (#11899 fragment coverage).
  mutate_red "a MUT_/SKIP-split composed env write inside this suite's job (no literal ever present)" IV \
    'old = "        run: bash apps/web-platform/test/infra/web-nic-guard-unpinned-url-alert.test.sh\n"
assert s.count(old) == 1
s = s.replace(old, "      - run: echo \x22MUT_\x22\x22SKIP=1\x22 >> \x22\x24GITHUB_ENV\x22\n" + old)' \
    "workflow seam"
  mutate_red "a *_GUARD_* env under a different prefix reaches the workflow" IV \
    'old = "        run: bash apps/web-platform/test/infra/web-nic-guard-unpinned-url-alert.test.sh\n"
assert s.count(old) == 1
s = s.replace(old, old + "        env:\n          FOO_GUARD_X: /dev/null\n")' \
    "workflow seam"
  mutate_red "a BASH_ENV shell-injection env reaches the workflow" IV \
    'old = "        run: bash apps/web-platform/test/infra/web-nic-guard-unpinned-url-alert.test.sh\n"
assert s.count(old) == 1
s = s.replace(old, old + "        env:\n          BASH_ENV: /tmp/x\n")' \
    "workflow seam"
  mutate_red "a \$GITHUB_ENV write inside this suite's own job (the dynamic channel)" IV \
    'old = "        run: bash apps/web-platform/test/infra/web-nic-guard-unpinned-url-alert.test.sh\n"
assert s.count(old) == 1
s = s.replace(old, "      - run: echo \x22SENT=1\x22 >> \x22\x24GITHUB_ENV\x22\n" + old)' \
    "workflow seam"
  mutate_green "a \$GITHUB_ENV write in a different job (plan:) — the ban is job-scoped" \
    'i = s.index("          printf \x27AWS_SECRET_ACCESS_KEY=")
e = s.index("\n", i)
s = s[:e + 1] + "          printf \x27SENTINEL=1\x27 >> \x22\x24GITHUB_ENV\x22\n" + s[e + 1:]' \
    IV

  # ── Scorer negative control ────────────────────────────────────────────────────────────────────
  mutate_red "scorer control: paused-flip reds a different row than the named fragment" TF \
    's = edit(s, ALRRES, "  paused = false\n", "  paused = true\n")' \
    "this-fragment-does-not-exist" wrong

  # ── Floor row ────────────────────────────────────────────────────────────────────────────────
  mutate_floor_red "assertion floor trips when PRESENCE_ROWS is bumped one past the real count"
fi

# ── Assertion floor + ledger (constructible: pure assignments only inside the window) ────────────
# Instrument failures exit 2 (the MUT_ROWS_RUN conservation ledger); floor/ledger trips exit 1 —
# the battery grades an inner rc 1 as a CAUGHT mutation.
# Floor self-reference (accepted residual, #11899 — CTO ruling: document-and-keep): these constants
# are written by this same file — decrementing one alongside a row deletion stays green+FIRES; review covers it.
PRESENCE_ROWS=36
MUT_ROWS=29
_eff=${MUT_SKIP:+0}
_eff=${_eff:-$MUT_ROWS}
_floor=$((PRESENCE_ROWS + _eff))
_ran=$((pass + fail))
if [ "$_ran" -lt "$_floor" ]; then
  printf '[FATAL] assertion floor: %s ran, floor %s\n' "$_ran" "$_floor" >&2
  exit 1
fi
if [ -z "${MUT_SKIP:-}" ] && [ "${MUT_ROWS_RUN:-0}" -ne "$MUT_ROWS" ]; then
  printf '[FATAL] mutation rows: %s ran, %s expected — a row was added or dropped without updating MUT_ROWS\n' "${MUT_ROWS_RUN:-0}" "$MUT_ROWS" >&2
  exit 2
fi
if [ "${#FAILED[@]}" -ne "$fail" ]; then
  printf '[FATAL] ledger %s != fail counter %s\n' "${#FAILED[@]}" "$fail" >&2
  exit 1
fi
[ -n "${MUT_SKIP:-}" ] && printf '[note] MUT_SKIP active — mutation rows skipped (floor %s); UNPINNED_GUARD_{TF,WF,EM,RB,LQ,IV}=%s,%s,%s,%s,%s,%s\n' "$_floor" "${UNPINNED_GUARD_TF:-unset}" "${UNPINNED_GUARD_WF:-unset}" "${UNPINNED_GUARD_EM:-unset}" "${UNPINNED_GUARD_RB:-unset}" "${UNPINNED_GUARD_LQ:-unset}" "${UNPINNED_GUARD_IV:-unset}"
printf '\n=== web-nic-guard-unpinned-url-alert: %s passed, %s failed (%s assertions, floor %s) ===\n' "$pass" "$fail" "$_ran" "$_floor"
[ "$fail" -eq 0 ]
