#!/usr/bin/env bash
#
# Drift guard for the #10321 credential-shape Better Stack Logs alert
# (apps/web-platform/infra/betterstack-logs-alerts.tf, Guard 1 of
# knowledge-base/project/plans/archive/20261015-153536-2026-10-15-fix-dormant-probe-ledger-10321-10136-plan.md).
#
# WHAT THE ALERT IS FOR. zot-log-channel-7440.sh's exit-1 arm was the only automated
# reader of what the registry shipper's redact() emits on source 2457081 — it went
# dormant when tracker #7455 closed (the sweeper's read set is open issues plus a
# 14-day closed lookback). This alert is the standing vehicle for the same three
# shapes: (a) an Authorization value that is neither the `***` mask nor REDACTED,
# (b) a Doppler token prefix dp.(pt|st|sa|ct). with a >=16 non-separator run,
# (c) a bcrypt $2[aby]$ hash. One matching row pages (value = 0, higher_than).
#
# WHAT THIS FILE NOW PROVES (post-#11720 convention):
#   * CANONICAL EQUALITY — the flattened heredoc must EQUAL a canon built from a
#     literal derived out of the emitter (cloud-init-registry.yml's ship call),
#     not a re-pinned literal. Dead text — a /* */- or #-wrapped decoy heredoc —
#     can never satisfy the pin: the extractor reads the live local, the opener
#     counts see the decoy, and the canon pins the body.
#   * BLOCK-SCOPED EXACTLY-ONCE PINS — every alert attribute is asserted inside
#     its own resource block by param(), whole value line anchored both ends,
#     required exactly once. The pinned target is a `*_sql` LOCAL plus two
#     resource blocks; `sql_local()` extracts the local, `res_block()` the blocks.
#   * THE BATTERY CANNOT BE MUTED — MUT_SKIP skips mutation rows on an inner run
#     only; the pristine-child control FATALs (rc 2) if the un-mutated inner run
#     is not green; REGCREDSHAPE_/MUT_SKIP literals may not reach the workflow's
#     executable text (the seam check below); mutate_floor_red proves the floor.
#   * RC DISCRIMINATION — only rc=1 (a real [FAIL] verdict) is a caught mutation;
#     instrument failures (rc>=2) are UNRESOLVED. Floor/ledger trips exit 1;
#     instrument failures exit 2.
#
# Mutation rows live at the bottom. They mutate COPIES in a temp dir and re-run
# this file against them through REGCREDSHAPE_{TF,WF,CI,IV,RB} — tracked files
# are never written.
set -uo pipefail
export TMPDIR="${TMPDIR:-/var/tmp}"

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$DIR/../../../.." && pwd)"
TF="${REGCREDSHAPE_TF:-$REPO/apps/web-platform/infra/betterstack-logs-alerts.tf}"
WF="${REGCREDSHAPE_WF:-$REPO/.github/workflows/apply-web-platform-infra.yml}"
CI="${REGCREDSHAPE_CI:-$REPO/apps/web-platform/infra/cloud-init-registry.yml}"
IV="${REGCREDSHAPE_IV:-$REPO/.github/workflows/infra-validation.yml}"
RB="${REGCREDSHAPE_RB:-$REPO/knowledge-base/engineering/operations/runbooks/registry-zot-credential-shape-10321.md}"
SUITE_NAME="registry-zot-credential-shape-alert.test.sh"

pass=0; fail=0; FAILED=()
ok() { pass=$((pass + 1)); printf '[ok] %s\n' "$1"; }
no() { fail=$((fail + 1)); FAILED+=("$1"); printf '[FAIL] %s\n' "$1"; }

# P1b (#7708) — byte-identical to every other tracked copy; the P1a suite pins that.
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

# INSTRUMENT SELF-TEST — both helpers must move their own counter first.
_p0=$pass; _f0=$fail
{ ok "self-test"; no "self-test"; } >/dev/null
if [ "$pass" -ne $((_p0 + 1)) ] || [ "$fail" -ne $((_f0 + 1)) ] || [ "${#FAILED[@]}" -ne 1 ]; then
  printf '[FATAL] instrument self-test: ok()/no() did not each move their counter\n' >&2; exit 2
fi
pass=$_p0; fail=$_f0; FAILED=()
assert_fixture_dir "$TF"; assert_fixture_dir "$WF"; assert_fixture_dir "$CI"; assert_fixture_dir "$IV"; assert_fixture_dir "$RB"

command -v python3 >/dev/null 2>&1 || { printf '[FATAL] python3 missing\n' >&2; exit 2; }
for f in "$TF" "$WF" "$CI" "$IV" "$RB"; do
  [ -r "$f" ] || { printf '[FATAL] unreadable: %s\n' "$f" >&2; exit 2; }
done

# ── Derived literal ──────────────────────────────────────────────────────────────────────────
# The canon's envelope marker is derived from the emitter's ship call in cloud-init-registry.yml
# — never a re-pinned literal: if the emitter renames the marker, the canon moves and the .tf
# drifts red. FATAL-on-empty: a rename reddens instead of silently re-pinning a dead literal.
MUT_TAG="$(sed -n 's/^[^#]*ship "\(SOLEUR_ZOT_LOG\) .*/\1/p' "$CI" | head -1)"
[ "$MUT_TAG" = "SOLEUR_ZOT_LOG" ] || { printf '[FATAL] emitter ship "SOLEUR_ZOT_LOG …" not found in %s\n' "$CI" >&2; exit 2; }

# ── Extraction helpers ───────────────────────────────────────────────────────────────────────
sql_local() {
  awk '/^[[:space:]]*registry_zot_log_credential_shape_sql[[:space:]]*=[[:space:]]*<<[-]SQL/{f=1;next} f&&/^  SQL$/{f=0} f' "$TF"
}
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

LOCAL_SQL="$(sql_local)"
FLAT="$(printf '%s' "$LOCAL_SQL" | tr -s '[:space:]' ' ' | sed 's/^ //; s/ $//')"

if [ -n "$FLAT" ] && grep -qF "'${MUT_TAG} '" <<<"$FLAT"; then
  ok "the predicate local is a heredoc this guard can read, and it carries the ${MUT_TAG} anchor"
else
  no "registry_zot_log_credential_shape_sql: heredoc not found or anchorless — every row below would be vacuous"
fi

# Opener counts — unanchored, file-wide, exactly once (a decoy opener still counts and goes red).
_n_sql_openers="$(grep -cE 'registry_zot_log_credential_shape_sql = <<[-]SQL' "$TF")"
[ "$_n_sql_openers" -eq 1 ] \
  && ok "exactly one registry_zot_log_credential_shape_sql heredoc opener in the file" \
  || no "registry_zot_log_credential_shape_sql opener count is $_n_sql_openers, want 1 — a decoy local exists"
_n_exp="$(grep -cE 'resource "logtail_exploration" "registry_zot_log_credential_shape"' "$TF")"
[ "$_n_exp" -eq 1 ] \
  && ok "exactly one logtail_exploration.registry_zot_log_credential_shape resource header" \
  || no "logtail_exploration header count is $_n_exp, want 1 — a decoy resource exists"
_n_alr="$(grep -cE 'resource "logtail_exploration_alert" "registry_zot_log_credential_shape"' "$TF")"
[ "$_n_alr" -eq 1 ] \
  && ok "exactly one logtail_exploration_alert.registry_zot_log_credential_shape resource header" \
  || no "logtail_exploration_alert header count is $_n_alr, want 1 — a decoy resource exists"

[ "$(res_block logtail_exploration registry_zot_log_credential_shape | grep -cF 'sql_query = replace(trimspace(local.registry_zot_log_credential_shape_sql), "/\\s+/", " ")')" -eq 1 ] \
  && ok "the exploration carries THIS predicate, collapsed to one line" \
  || no "the exploration does not carry local.registry_zot_log_credential_shape_sql exactly once"

_M="JSONExtractString(raw, 'message')"
EXPECTED_FLAT="SELECT {{time}} AS time, count(*) AS value FROM {{source}} WHERE time BETWEEN {{start_time}} AND {{end_time}} AND startsWith(raw, '{\"message\":\"${MUT_TAG} ') AND position($_M, '${MUT_TAG} ') = 1 AND ( arrayExists( v -> v != 'Authorization:[' AND NOT match(v, '^Authorization:\\\\[(\\\\*\\\\*\\\\*|REDACTED)'), extractAll($_M, 'Authorization:\\\\[[^\\\\]\\\\s]*') ) OR match($_M, 'Authorization:\\\\[\\\\s') OR arrayExists( t -> length(replaceRegexpAll(t, '^dp\\\\.(?:pt|st|sa|ct)\\\\.|[._-]', '')) >= 16, extractAll($_M, 'dp\\\\.(?:pt|st|sa|ct)\\\\.[A-Za-z0-9._-]+') ) OR match($_M, '\\\\\$2[aby]\\\\\$[0-9][0-9]\\\\\$') ) GROUP BY time"
[ "$FLAT" = "$EXPECTED_FLAT" ] \
  && ok "the whole predicate is byte-exact (SELECT, aggregate, all three disjuncts, GROUP BY)" \
  || no "the predicate drifted from the pinned text — diff FLAT against EXPECTED_FLAT"

# Column form: every row read goes through JSONExtractString(raw, 'message'), never a bare msg.
n_col="$(printf '%s' "$FLAT" | grep -oF "JSONExtractString(raw, 'message')" | wc -l | tr -d ' ')"
if [ "$n_col" -ge 5 ] && ! grep -qE '\bmsg\b' <<<"$FLAT"; then
  ok "all ${n_col} row reads use JSONExtractString(raw, 'message'); no bare msg column"
else
  no "column form drifted: ${n_col} JSONExtractString(raw, 'message') reads (want >=5) or a bare msg"
fi

grep -qF "AND startsWith(raw, '{\"message\":\"${MUT_TAG} ')" <<<"$FLAT" \
  && ok "envelope-anchored to the direct-POST shape (a journald row quoting the marker cannot match)" \
  || no "the startsWith(raw, '{\"message\":\"${MUT_TAG} ') envelope conjunct is missing"

grep -qF "AND position(JSONExtractString(raw, 'message'), '${MUT_TAG} ') = 1" <<<"$FLAT" \
  && ok "the marker is anchored at position 1 of the message, with its trailing space" \
  || no "the message-level marker anchor is missing or unanchored"

# Arm (a): per-occurrence Authorization values through extractAll + arrayExists, with
# the exact mask exemption and the empty-vs-malformed split.
grep -qF "extractAll(JSONExtractString(raw, 'message'), 'Authorization:\\\\[[^\\\\]\\\\s]*')" <<<"$FLAT" \
  && grep -qF "arrayExists( v -> v != 'Authorization:[' AND NOT match(v, '^Authorization:\\\\[(\\\\*\\\\*\\\\*|REDACTED)')" <<<"$FLAT" \
  && ok "arm (a) walks EVERY Authorization:[ value (no decoy masking); exemption is exactly (***|REDACTED)" \
  || no "arm (a) lost the per-occurrence extractAll/arrayExists shape or the mask exemption"
grep -qF "OR match(JSONExtractString(raw, 'message'), 'Authorization:\\\\[\\\\s')" <<<"$FLAT" \
  && ok "arm (a') flags 'Authorization:[<whitespace>' — a value empty after the space cut fails loud (tab too, matching the probe)" \
  || no "the malformed-unmasked conjunct (Authorization:[\\s) is missing"

# Arm (b): Doppler prefix + >=16 non-separator substance.
grep -qF "extractAll(JSONExtractString(raw, 'message'), 'dp\\\\.(?:pt|st|sa|ct)\\\\.[A-Za-z0-9._-]+')" <<<"$FLAT" \
  && grep -qF "replaceRegexpAll(t, '^dp\\\\.(?:pt|st|sa|ct)\\\\.|[._-]', '')) >= 16" <<<"$FLAT" \
  && ok "arm (b) requires >=16 non-separator chars after dp.(pt|st|sa|ct). — padding cannot fire it" \
  || no "arm (b) lost the prefix extract or the substance floor"

# Arm (c): bcrypt.
grep -qF "match(JSONExtractString(raw, 'message'), '\\\\\$2[aby]\\\\\$[0-9][0-9]\\\\\$')" <<<"$FLAT" \
  && ok "arm (c) is the bcrypt \$2[aby]\$<2d>\$ prefix" \
  || no "arm (c) bcrypt disjunct is missing or deformed"

# ── Resource-block scoped, exactly-once attribute pins ───────────────────────────────────────
EXP_BLOCK="$(res_block logtail_exploration registry_zot_log_credential_shape)"
ALR_BLOCK="$(res_block logtail_exploration_alert registry_zot_log_credential_shape)"

param "$EXP_BLOCK" 'values' '\[local\.vector_prd_source_id\]' \
  && ok "the exploration reads local.vector_prd_source_id (source 2457081)" \
  || no "the exploration's source variable is not local.vector_prd_source_id (exactly once)"

param "$ALR_BLOCK" 'exploration_id' 'logtail_exploration\.registry_zot_log_credential_shape\.id' \
  && ok "the alert is attached to this exploration" \
  || no "the alert's exploration_id does not reference this exploration"

param "$ALR_BLOCK" 'paused' 'false' \
  && ok "paused = false (it arms at merge)" \
  || no "the alert is not 'paused = false' — it would exist and never page"
[ "$(printf '%s\n' "$ALR_BLOCK" | grep -c 'paused')" -eq 1 ] \
  && ok "the string 'paused' occurs exactly once in the alert block (a commented or duplicated decoy counts)" \
  || no "'paused' occurs !=1 time in the alert block — a commented pinned-line decoy exists"

param "$ALR_BLOCK" 'value' '0' \
  && ok "value = 0" \
  || no "value is not 0 (exactly once) — one-row-is-an-incident semantics lost"
param "$ALR_BLOCK" 'operator' '"higher_than"' \
  && ok "operator = higher_than: ONE credential-shaped row is a page" \
  || no "operator is not \"higher_than\" (exactly once)"
param "$ALR_BLOCK" 'check_period' '300' \
  && ok "check_period = 300" \
  || no "check_period is not 300 (exactly once)"
param "$ALR_BLOCK" 'query_period' '900' \
  && ok "query_period = 900" \
  || no "query_period is not 900 (exactly once)"
param "$ALR_BLOCK" 'on_missing_data' '"treat_as_zero"' \
  && ok "treat_as_zero, so an open incident can observe recovery" \
  || no "on_missing_data is not \"treat_as_zero\" (exactly once)"
param "$ALR_BLOCK" 'confirmation_period' '0' \
  && ok "confirmation_period = 0 (one row pages immediately, no dwell)" \
  || no "confirmation_period is not 0 (exactly once)"
param "$ALR_BLOCK" 'recovery_period' '1800' \
  && ok "recovery_period = 1800 (two query windows before an incident closes)" \
  || no "recovery_period is not 1800 (exactly once)"
param "$ALR_BLOCK" 'critical_alert' 'false' \
  && param "$ALR_BLOCK" 'email' 'true' \
  && ok "email=true, critical_alert=false — the siblings' severity, not a page-escalation" \
  || no "alert channel drifted (email/critical_alert, exactly once each)"

param "$ALR_BLOCK" 'policy_id' 'var\.betterstack_paid_tier \? tonumber\(betteruptime_policy\.uptime\[0\]\.id\) : null' \
  && param "$ALR_BLOCK" 'team_name' 'var\.betterstack_paid_tier \? null : "Your team"' \
  && ok "escalation_target is the siblings' free/paid-tier ternary" \
  || no "escalation_target drifted from the siblings' routing"

grep -qF 'registry_zot_log_credential_shape_runbook_url = "https://github.com/jikig-ai/soleur/blob/main/knowledge-base/' "$TF" \
  && grep -qF '${local.registry_zot_log_credential_shape_runbook_url}' <<<"$ALR_BLOCK" \
  && ok "the incident carries a clickable runbook URL" \
  || no "no clickable runbook URL on the incident"

[ -s "$RB" ] \
  && ok "the runbook the incident links to exists (non-empty) in the repo" \
  || no "runbook $(basename "$RB") missing or empty — the incident link would 404"

# NEGATIVE row: no count/for_each/lifecycle/ignore_changes token inside EITHER resource block.
if [ "$(printf '%s\n%s\n' "$EXP_BLOCK" "$ALR_BLOCK" | grep -cE '^[[:space:]]*(count|for_each|lifecycle|ignore_changes)[[:space:]]*[= {]')" -eq 0 ]; then
  ok "no count/for_each/lifecycle/ignore_changes mute knob inside either resource block"
else
  no "a count/for_each/lifecycle/ignore_changes token sits inside a resource block — a mute knob the provider would honor silently"
fi

# Both -target lines, INSIDE the push-triggered `apply:` job.
APPLY_JOB="$(awk '/^  apply:$/{f=1; print; next} f && /^  [A-Za-z0-9_-]+:$/{f=0} f' "$WF")"
grep -qxF '              -target=logtail_exploration.registry_zot_log_credential_shape \' <<<"$APPLY_JOB" \
  && grep -qxF '              -target=logtail_exploration_alert.registry_zot_log_credential_shape \' <<<"$APPLY_JOB" \
  && ok "both resources are in the push-triggered apply job's -target allowlist (#5566)" \
  || no "one or both -target= lines are missing — the alert would never exist"

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
# axis. REGCREDSHAPE_ stays literal (its prefix carries no GUARD fragment).
_seam_frag=""
for _frag in 'MUT_' '_SKIP' 'GUARD' 'BASH_ENV' 'SHELLOPTS' 'BASHOPTS' 'REGCREDSHAPE_'; do
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
echo "=== registry-zot-credential-shape-alert guard: $pass passed, $fail failed ==="
if [ "$fail" -gt 0 ]; then
  printf 'FAILED: %s\n' "${FAILED[@]}" >&2
  exit 1
fi

# ── Mutation rows: each must make the rows above RED (must-PASS rows stay GREEN) ─────────────
if [ -z "${MUT_SKIP:-}" ]; then
  MUT_DIR="$(mktemp -d -t regcredshape.XXXXXX)" || { printf '[FATAL] mktemp failed\n' >&2; exit 2; }
  assert_fixture_dir "$MUT_DIR"
  trap 'rm -rf "$MUT_DIR"' EXIT

  # INSTRUMENT CONTROL — the inner run against the PRISTINE tree must exit 0.
  SELF="$DIR/$(basename "${BASH_SOURCE[0]}")"
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
SQLLOC = "registry_zot_log_credential_shape_sql = <<\x2dSQL"
SQLEND = "\n  SQL\n"
EXPRES = "resource \"logtail_exploration\" \"registry_zot_log_credential_shape\" {"
ALRRES = "resource \"logtail_exploration_alert\" \"registry_zot_log_credential_shape\" {"'

  _red_verdict() {
    case "$1" in
      1) if [ -z "$3" ] || { grep -F '[FAIL]' "$2" | grep -F -- "$3" >/dev/null; }; then echo red; else echo wrong; fi ;;
      0) echo survived ;;
      *) echo unresolved ;;
    esac
  }

  # mutate_red <label> <TF|WF|CI|IV|RB> <python-program-on-s> [expected [FAIL] fragment] [red|wrong]
  mutate_red() {
    local label="$1" which="$2" prog="$3" tag="${4:-}" want="${5:-red}" src copy rc=0 olog="$MUT_DIR/inner.log"
    case "$which" in
      TF) src="$TF"; copy="$MUT_DIR/betterstack-logs-alerts.tf" ;;
      WF) src="$WF"; copy="$MUT_DIR/apply-web-platform-infra.yml" ;;
      CI) src="$CI"; copy="$MUT_DIR/cloud-init-registry.yml" ;;
      IV) src="$IV"; copy="$MUT_DIR/infra-validation.yml" ;;
      RB) src="$RB"; copy="$MUT_DIR/runbook.md" ;;
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
    env "REGCREDSHAPE_${which}=$copy" MUT_SKIP=1 bash "$SELF" >"$olog" 2>&1 || rc=$?
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
      TF) src="$TF"; copy="$MUT_DIR/betterstack-logs-alerts.tf" ;;
      WF) src="$WF"; copy="$MUT_DIR/apply-web-platform-infra.yml" ;;
      CI) src="$CI"; copy="$MUT_DIR/cloud-init-registry.yml" ;;
      IV) src="$IV"; copy="$MUT_DIR/infra-validation.yml" ;;
      RB) src="$RB"; copy="$MUT_DIR/runbook.md" ;;
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
    env "REGCREDSHAPE_${which}=$copy" MUT_SKIP=1 bash "$SELF" >"$MUT_DIR/green.log" 2>&1 || rc=$?
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
s = s[:i] + "/*\n  registry_zot_log_credential_shape_sql = <<\x2dSQL\n  SELECT legit\n  SQL\n*/\n" + s[i:]' \
    "decoy local exists"
  mutate_red "a #-commented decoy opener line sits above the live local" TF \
    'i = s.index(SQLLOC)
s = s[:i] + "  # registry_zot_log_credential_shape_sql = <<\x2dSQL\n" + s[i:]' \
    "decoy local exists"
  mutate_red "a commented-out paused=false decoy line appears inside the alert block" TF \
    's = edit(s, ALRRES, "  paused = false\n", "  paused = false\n  # paused = false\n")' \
    "decoy exists"
  mutate_red "an inline tautology is appended inside the predicate" TF \
    's = edit(s, SQLLOC, "GROUP BY time", "GROUP BY time OR 1=1", SQLEND)' \
    "drifted from the pinned"
  mutate_red "a doubled-dollar escape literal appears inside the heredoc" TF \
    's = edit(s, SQLLOC, "count(*) AS value", "count(*) AS value /* \x24\x24escaped */", SQLEND)' \
    "drifted from the pinned"
  mutate_red "the live predicate local is gutted to a placeholder while the resource keeps its name" TF \
    's = edit(s, SQLLOC, "SELECT {{time}} AS time, count(*) AS value", "SELECT 1", SQLEND)' \
    "drifted from the pinned"

  # ── Canon/arm rows ─────────────────────────────────────────────────────────────────────────
  mutate_red "delete the bcrypt disjunct" TF \
    'i = s.index(SQLLOC); j = s.index(SQLEND, i)
blk = s[i:j]
old = "\n        OR match(JSONExtractString(raw, \x27message\x27), \x27\\\\$2[aby]\\\\$[0-9][0-9]\\\\$\x27)"
assert blk.count(old) == 1
s = s[:i] + blk.replace(old, "") + s[j:]' \
    "drifted from the pinned"
  mutate_red "drop the mask exemption" TF \
    'old = " AND NOT match(v, \x27^Authorization:\\\\[(\\\\*\\\\*\\\\*|REDACTED)\x27)"
assert s.count(old) == 1
s = s.replace(old, "")' \
    "mask exemption"
  mutate_red "remove the envelope anchor" TF \
    'i = s.index(SQLLOC); j = s.index(SQLEND, i)
blk = s[i:j]
old = "      AND startsWith(raw, \x27{\"message\":\"SOLEUR_ZOT_LOG \x27)\n"
assert blk.count(old) == 1
s = s[:i] + blk.replace(old, "") + s[j:]' \
    "envelope conjunct is missing"
  mutate_red "drop the exploration_alert -target= line" WF \
    'old = "              -target=logtail_exploration_alert.registry_zot_log_credential_shape \\\n"
assert s.count(old) == 1
s = s.replace(old, "")' \
    "-target= lines are missing"
  mutate_red "the Doppler substance floor is zeroed" TF \
    'old = ")) >= 16"
assert s.count(old) == 1
s = s.replace(old, ")) >= 0")' \
    "substance floor"
  mutate_red "value = 0 becomes value = 1 (a single leak no longer pages)" TF \
    's = edit(s, ALRRES, "  value               = 0\n", "  value               = 1\n")' \
    "value is not 0"
  mutate_red "the heredoc the extractor reads is renamed (extracted SQL empty)" TF \
    'assert s.count(SQLLOC) == 1
s = s.replace(SQLLOC, "registry_zot_log_credential_shape_sql_v2 = <<\x2dSQL")' \
    "heredoc not found"
  mutate_red "the count = 0 mute knob is added inside the alert resource" TF \
    's = edit(s, ALRRES, "  paused = false\n", "  count = 0\n  paused = false\n")' \
    "mute knob"

  mutate_red "the linked runbook is emptied (the incident link would 404)" RB \
    's = ""' \
    "runbook"

  # ── Workflow seam rows ─────────────────────────────────────────────────────────────────────
  # IV_ANCH — the shared anchors the key-shape / key-order rows below mutate through: RUN is
  # the registered run line, HOSTH the hosting job's exact four-line header, AFTER the first
  # bytes of the comment block that follows the job's steps (the post-steps insertion slot).
  IV_ANCH='Q = chr(39)
RUN = "        run: bash apps/web-platform/test/infra/registry-zot-credential-shape-alert.test.sh\n"
HOSTH = "  deploy-script-tests-fixed:\n    needs: detect-changes\n    if: needs.detect-changes.outputs.pr_duplicate != " + Q + "true" + Q + "\n    runs-on: ubuntu-24.04\n"
AFTER = "          fi\n\n  # Aggregator (#8736): the single verdict"
'
  mutate_red "a MUT_SKIP literal reaches the workflow's executable text" IV \
    'old = "        run: bash apps/web-platform/test/infra/registry-zot-credential-shape-alert.test.sh\n"
assert s.count(old) == 1
s = s.replace(old, "        env:\n          MUT_SKIP: \"1\"\n" + old)' \
    "suite-seam-in-workflow"
  mutate_red "a REGCREDSHAPE_ literal reaches the workflow's executable text" IV \
    'old = "        run: bash apps/web-platform/test/infra/registry-zot-credential-shape-alert.test.sh\n"
assert s.count(old) == 1
s = s.replace(old, old + "        env:\n          REGCREDSHAPE_TF: /dev/null\n")' \
    "suite-seam-in-workflow"
  mutate_red "the suite's own run line is dropped from the workflow" IV \
    'old = "        run: bash apps/web-platform/test/infra/registry-zot-credential-shape-alert.test.sh\n"
assert s.count(old) == 1
s = s.replace(old, "")' \
    "does not run registry-zot-credential-shape-alert.test.sh exactly once"
  mutate_red "a composed MUT_ / _SKIP env name reaches the workflow through an in-job GITHUB_ENV write" IV \
    'old = "        run: bash apps/web-platform/test/infra/registry-zot-credential-shape-alert.test.sh\n"
assert s.count(old) == 1
s = s.replace(old, old + "        run: echo \"MUT_\"\"SKIP=1\" >> \"\x24GITHUB_ENV\"\n")' \
    "suite-seam-in-workflow"
  mutate_red "a GUARD-fragment env name is planted on the suite's step" IV \
    'old = "        run: bash apps/web-platform/test/infra/registry-zot-credential-shape-alert.test.sh\n"
assert s.count(old) == 1
s = s.replace(old, "        env:\n          FOO_GUARD_X: /dev/null\n" + old)' \
    "suite-seam-in-workflow"
  mutate_red "a BASH_ENV shell-injection name is planted inside the job" IV \
    'old = "        run: bash apps/web-platform/test/infra/registry-zot-credential-shape-alert.test.sh\n"
assert s.count(old) == 1
s = s.replace(old, "        env:\n          BASH_ENV: /tmp/x\n" + old)' \
    "suite-seam-in-workflow"
  mutate_red "a benign GITHUB_ENV write lands inside the suite's own job" IV \
    'old = "        run: bash apps/web-platform/test/infra/registry-zot-credential-shape-alert.test.sh\n"
assert s.count(old) == 1
s = s.replace(old, old + "        run: echo \"SEAM_PROBE=1\" >> \"\x24GITHUB_ENV\"\n")' \
    "job-scope-env-write"
  mutate_red "the suite's step gains an if: (a conditional step can be skipped green)" IV \
    'old = "        run: bash apps/web-platform/test/infra/registry-zot-credential-shape-alert.test.sh\n"
assert s.count(old) == 1
s = s.replace(old, "        if: false\n" + old)' \
    "conditional, non-blocking, redirected or unaggregated"
  mutate_red "the suite's step becomes non-blocking (continue-on-error:)" IV \
    'old = "        run: bash apps/web-platform/test/infra/registry-zot-credential-shape-alert.test.sh\n"
assert s.count(old) == 1
s = s.replace(old, "        continue-on-error: true\n" + old)' \
    "conditional, non-blocking, redirected or unaggregated"
  mutate_red "the suite's job header gains continue-on-error:" IV \
    'old = "        run: bash apps/web-platform/test/infra/registry-zot-credential-shape-alert.test.sh\n"
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
    "$IV_ANCH"'old = "      - name: Run registry zot credential-shape alert drift guard (#10321)\n"
assert s.count(old) == 1
s = s.replace(old, "      - if: false\n        name: Run registry zot credential-shape alert drift guard (#10321)\n")' \
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
  mutate_red "scorer control: value-drop reds a different row than the named fragment" TF \
    's = edit(s, ALRRES, "  value               = 0\n", "  value               = 1\n")' \
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
  mutate_green "whitespace reflow of the heredoc" TF \
    'old = "\n        OR match(JSONExtractString(raw, \x27message\x27), \x27Authorization:\\\\[\\\\s\x27)"
assert s.count(old) == 1
s = s.replace(old, " OR\n          match(JSONExtractString(raw, \x27message\x27), \x27Authorization:\\\\[\\\\s\x27)")'
fi

# ── Assertion floor + ledger (constructible: pure assignments only inside the window) ────────
# Self-reference (accepted residual, #11899 item 8): PRESENCE_ROWS/MUT_ROWS are written only
# in THIS file — a row deletion paired with a decrement stays green+FIRES; review covers it.
PRESENCE_ROWS=32
MUT_ROWS=35
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
[ -n "${MUT_SKIP:-}" ] && printf '[note] MUT_SKIP active — mutation rows skipped (floor %s); REGCREDSHAPE_{TF,WF,CI,IV,RB}=%s,%s,%s,%s,%s\n' "$_floor" "${REGCREDSHAPE_TF:-unset}" "${REGCREDSHAPE_WF:-unset}" "${REGCREDSHAPE_CI:-unset}" "${REGCREDSHAPE_IV:-unset}" "${REGCREDSHAPE_RB:-unset}"
printf '\n=== registry-zot-credential-shape-alert: %s passed, %s failed (%s assertions, floor %s) ===\n' "$pass" "$fail" "$_ran" "$_floor"
[ "$fail" -eq 0 ]
