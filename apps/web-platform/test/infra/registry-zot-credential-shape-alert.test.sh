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
  awk '/registry_zot_log_credential_shape_sql = <<-SQL/{f=1;next} f&&/^  SQL$/{f=0} f' "$TF"
}
res_block() {
  awk -v h="resource \"$1\" \"$2\" {" '$0 == h {f=1} f{print} f && /^}/{exit}' "$TF"
}
# param <block> <attr> <value-ERE>: whole-line attribute assertion INSIDE a block, anchored
# both ends, required EXACTLY ONCE.
param() {
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
_n_sql_openers="$(grep -cE 'registry_zot_log_credential_shape_sql = <<-SQL' "$TF")"
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

grep -cF 'sql_query = replace(trimspace(local.registry_zot_log_credential_shape_sql), "/\\s+/", " ")' <<<"$(res_block logtail_exploration registry_zot_log_credential_shape)" | grep -qx '1' \
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

[ -r "$RB" ] \
  && ok "the runbook the incident links to exists in the repo" \
  || no "runbook $(basename "$RB") missing — the incident link would 404"

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

# ── Workflow seam — registered exactly once, and no env axis reaches executable text ─────────
REG_RUN='        run: bash apps/web-platform/test/infra/registry-zot-credential-shape-alert.test.sh'
IV_CODE="$(awk '!/^[[:space:]]*#/' "$IV")"
n_run="$(printf '%s\n' "$IV_CODE" | grep -cFx "$REG_RUN")"
[ "$n_run" -eq 1 ] \
  && ok "this suite's run line is registered in infra-validation.yml exactly once" \
  || no "run line count is $n_run, want 1 — the suite is unregistered or double-registered"

seam_bad=""
printf '%s\n' "$IV_CODE" | grep -nE 'REGCREDSHAPE_' >/dev/null && seam_bad="$seam_bad REGCREDSHAPE_-literal"
printf '%s\n' "$IV_CODE" | grep -nE 'MUT_SKIP' >/dev/null && seam_bad="$seam_bad MUT_SKIP-literal"
[ -z "$seam_bad" ] \
  && ok "no REGCREDSHAPE_/MUT_SKIP literal reaches the workflow's executable text (env muting is barred)" \
  || no "workflow seam violated:$seam_bad — a guard env axis is reachable from infra-validation.yml"

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

  PRELUDE='Q = chr(39)
def edit(s, anchor, old, new, end="\n}\n"):
    i = s.index(anchor)
    j = s.index(end, i)
    region = s[i:j]
    assert region.count(old) == 1, "anchor drift: %r occurs %d times" % (old, region.count(old))
    return s[:i] + region.replace(old, new) + s[j:]
SQLLOC = "registry_zot_log_credential_shape_sql = <<-SQL"
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
    local label="$1" prog="$2" copy rc=0
    copy="$MUT_DIR/betterstack-logs-alerts.tf"
    cp "$TF" "$copy" || { printf '[FATAL] mutate_green: cp failed\n' >&2; exit 2; }
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
    REGCREDSHAPE_TF="$copy" MUT_SKIP=1 bash "$SELF" >"$MUT_DIR/green.log" 2>&1 || rc=$?
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
s = s[:i] + "/*\n  registry_zot_log_credential_shape_sql = <<-SQL\n  SELECT legit\n  SQL\n*/\n" + s[i:]' \
    "decoy local exists"
  mutate_red "a #-commented decoy opener line sits above the live local" TF \
    'i = s.index(SQLLOC)
s = s[:i] + "  # registry_zot_log_credential_shape_sql = <<-SQL\n" + s[i:]' \
    "decoy local exists"
  mutate_red "a commented-out `paused = false` decoy line appears inside the alert block" TF \
    's = edit(s, ALRRES, "  paused = false\n", "  paused = false\n  # paused = false\n")' \
    "decoy exists"
  mutate_red "an inline tautology is appended inside the predicate" TF \
    's = edit(s, SQLLOC, "GROUP BY time", "GROUP BY time OR 1=1", SQLEND)' \
    "drifted from the pinned"
  mutate_red "a doubled-dollar escape literal appears inside the heredoc" TF \
    's = edit(s, SQLLOC, "count(*) AS value", "count(*) AS value /* $$escaped */", SQLEND)' \
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
s = s.replace(SQLLOC, "registry_zot_log_credential_shape_sql_v2 = <<-SQL")' \
    "heredoc not found"
  mutate_red "the count = 0 mute knob is added inside the alert resource" TF \
    's = edit(s, ALRRES, "  paused = false\n", "  count = 0\n  paused = false\n")' \
    "mute knob"

  # ── Workflow seam rows ─────────────────────────────────────────────────────────────────────
  mutate_red "a MUT_SKIP literal reaches the workflow's executable text" IV \
    'old = "        run: bash apps/web-platform/test/infra/registry-zot-credential-shape-alert.test.sh\n"
assert s.count(old) == 1
s = s.replace(old, "        env:\n          MUT_SKIP: \"1\"\n" + old)' \
    "workflow seam"
  mutate_red "a REGCREDSHAPE_ literal reaches the workflow's executable text" IV \
    'old = "        run: bash apps/web-platform/test/infra/registry-zot-credential-shape-alert.test.sh\n"
assert s.count(old) == 1
s = s.replace(old, old + "        env:\n          REGCREDSHAPE_TF: /dev/null\n")' \
    "workflow seam"
  mutate_red "the suite's own run line is dropped from the workflow" IV \
    'old = "        run: bash apps/web-platform/test/infra/registry-zot-credential-shape-alert.test.sh\n"
assert s.count(old) == 1
s = s.replace(old, "")' \
    "unregistered or double-registered"

  # ── Scorer negative control ────────────────────────────────────────────────────────────────
  mutate_red "scorer control: value-drop reds a different row than the named fragment" TF \
    's = edit(s, ALRRES, "  value               = 0\n", "  value               = 1\n")' \
    "this-fragment-does-not-exist" wrong

  # ── Floor row ──────────────────────────────────────────────────────────────────────────────
  mutate_floor_red "assertion floor trips when PRESENCE_ROWS is bumped one past the real count"

  # ── must-PASS rows ─────────────────────────────────────────────────────────────────────────
  mutate_green "whitespace reflow of the heredoc" \
    'old = "\n        OR match(JSONExtractString(raw, \x27message\x27), \x27Authorization:\\\\[\\\\s\x27)"
assert s.count(old) == 1
s = s.replace(old, " OR\n          match(JSONExtractString(raw, \x27message\x27), \x27Authorization:\\\\[\\\\s\x27)")'
fi

# ── Assertion floor + ledger (constructible: pure assignments only inside the window) ────────
PRESENCE_ROWS=29
MUT_ROWS=23
_eff=${MUT_SKIP:+0}
_eff=${_eff:-$MUT_ROWS}
_floor=$((PRESENCE_ROWS + _eff))
_ran=$((pass + fail))
if [ "$_ran" -lt "$_floor" ]; then printf '[FATAL] assertion floor: %s ran, floor %s\n' "$_ran" "$_floor" >&2; exit 1; fi
if [ "${#FAILED[@]}" -ne "$fail" ]; then printf '[FATAL] ledger %s != fail counter %s\n' "${#FAILED[@]}" "$fail" >&2; exit 1; fi
[ -n "${MUT_SKIP:-}" ] && printf '[note] MUT_SKIP active — mutation rows skipped (floor %s); REGCREDSHAPE_{TF,WF,CI,IV,RB}=%s,%s,%s,%s,%s\n' "$_floor" "${REGCREDSHAPE_TF:-unset}" "${REGCREDSHAPE_WF:-unset}" "${REGCREDSHAPE_CI:-unset}" "${REGCREDSHAPE_IV:-unset}" "${REGCREDSHAPE_RB:-unset}"
printf '\n=== registry-zot-credential-shape-alert: %s passed, %s failed (%s assertions, floor %s) ===\n' "$pass" "$fail" "$_ran" "$_floor"
[ "$fail" -eq 0 ]
