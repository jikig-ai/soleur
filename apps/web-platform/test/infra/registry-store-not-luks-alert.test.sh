#!/usr/bin/env bash
#
# Drift guard for the "#8408 (a) registry store is not on LUKS, or its escrow is not proven"
# Better Stack Logs alert (apps/web-platform/infra/betterstack-logs-alerts.tf, Guard 3 of
# knowledge-base/project/plans/2026-09-21-fix-zot-queue-dead-ghcr-credential-plan.md).
#
# WHAT THE ALERT IS FOR. The registry host's */5 SOLEUR_ZOT_DISK heartbeat carries, in its TRUSTED
# HEAD (everything before ` zot_last_err=`), `store_luks=<yes|…>` and `store_escrow=<token>`. The
# rule pages when the head lacks `store_luks=yes ` (arm A) or carries a `store_escrow=` that is not
# `ok` (arm B). Nothing else notices either: zot serves happily from plaintext, and a dead escrow
# re-test only matters on the next reboot.
#
# WHAT THIS FILE NOW PROVES (post-#11720 convention):
#   * CANONICAL EQUALITY — the flattened heredoc must EQUAL a canon built from literals derived
#     out of the emitter (cloud-init-registry.yml's LINE= statement), not re-pinned literals.
#     Dead text — a /* */- or #-wrapped decoy heredoc — can never satisfy the pin: the extractor
#     reads the live local, the opener counts see the decoy, and the canon pins the body.
#   * BLOCK-SCOPED EXACTLY-ONCE PINS — every alert attribute is asserted inside its own resource
#     block by param(), which requires the whole value line anchored both ends, exactly once.
#     A second matching line inside the block, or a decoy block anywhere, goes red.
#   * THE BATTERY CANNOT BE MUTED — MUT_SKIP skips mutation rows on an inner run only; the
#     pristine-child control exits the suite FATAL (rc 2) if the un-mutated inner run is not
#     green; MUT_SKIP/REGSTORE_* literals may not reach the workflow's executable text (the
#     seam check below); and mutate_floor_red proves the assertion floor itself fires.
#   * RC DISCRIMINATION — only rc=1 (a real [FAIL] verdict) is a caught mutation; an instrument
#     failure (rc>=2) is UNRESOLVED, never evidence. Floor and ledger trips are verdict-class
#     (exit 1); instrument failures are exit 2.
#
# Mutation rows live at the bottom. They mutate COPIES in a temp dir and re-run this file
# against them through REGSTORE_{TF,WF,CI,IV} — the tracked files are never written.
set -uo pipefail
export TMPDIR="${TMPDIR:-/var/tmp}"

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$DIR/../../../.." && pwd)"
TF="${REGSTORE_TF:-$REPO/apps/web-platform/infra/betterstack-logs-alerts.tf}"
WF="${REGSTORE_WF:-$REPO/.github/workflows/apply-web-platform-infra.yml}"
CI="${REGSTORE_CI:-$REPO/apps/web-platform/infra/cloud-init-registry.yml}"
IV="${REGSTORE_IV:-$REPO/.github/workflows/infra-validation.yml}"

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

# INSTRUMENT SELF-TEST — both helpers must move their own counter before any verdict is trusted.
_p0=$pass; _f0=$fail
{ ok "self-test"; no "self-test"; } >/dev/null
if [ "$pass" -ne $((_p0 + 1)) ] || [ "$fail" -ne $((_f0 + 1)) ] || [ "${#FAILED[@]}" -ne 1 ]; then
  printf '[FATAL] instrument self-test: ok()/no() did not each move their counter\n' >&2; exit 2
fi
pass=$_p0; fail=$_f0; FAILED=()
assert_fixture_dir "$TF"; assert_fixture_dir "$WF"; assert_fixture_dir "$CI"; assert_fixture_dir "$IV"

command -v python3 >/dev/null 2>&1 || { printf '[FATAL] python3 missing — the arm parser needs it\n' >&2; exit 2; }
for f in "$TF" "$WF" "$CI" "$IV"; do
  [ -r "$f" ] || { printf '[FATAL] unreadable: %s\n' "$f" >&2; exit 2; }
done

# ── Derived literals ─────────────────────────────────────────────────────────────────────────
# The canon is built from literals derived out of the EMITTER's LINE= statement — never
# re-pinned literals: if the emitter renames a field, the canon moves and the .tf drifts red.
# Each extraction is FATAL-on-empty so a rename reddens instead of silently re-pinning a dead
# literal (the derive-the-needle convention, not a third uncoupled copy).
EMIT_LINE="$(sed -n 's/^[^#]*\(LINE="SOLEUR_ZOT_DISK [^"]*"\).*/\1/p' "$CI" | head -1)"
[ -n "$EMIT_LINE" ] || { printf '[FATAL] emitter LINE="SOLEUR_ZOT_DISK …" not found in %s\n' "$CI" >&2; exit 2; }
MUT_TAG="$(printf '%s' "$EMIT_LINE" | sed -E 's/^LINE="([A-Z_]+) .*/\1/')"
[ "$MUT_TAG" = "SOLEUR_ZOT_DISK" ] || { printf '[FATAL] emitter tag is %s, want SOLEUR_ZOT_DISK\n' "$MUT_TAG" >&2; exit 2; }
MUT_LUKS_F="$(printf '%s' "$EMIT_LINE" | grep -oE '[a-z_]+=\$STORE_LUKS' | head -1 | sed 's/=\$STORE_LUKS/=/')"
[ -n "$MUT_LUKS_F" ] || { printf '[FATAL] no <field>=$STORE_LUKS in emitter line\n' >&2; exit 2; }
MUT_ESC_F="$(printf '%s' "$EMIT_LINE" | grep -oE '[a-z_]+=\$STORE_ESCROW' | head -1 | sed 's/=\$STORE_ESCROW/=/')"
[ -n "$MUT_ESC_F" ] || { printf '[FATAL] no <field>=$STORE_ESCROW in emitter line\n' >&2; exit 2; }
MUT_ERR_F="$(printf '%s' "$EMIT_LINE" | grep -oE ' [a-z_]+=\$ZOT_LAST_ERR' | head -1 | sed 's/=\$ZOT_LAST_ERR/=/')"
[ -n "$MUT_ERR_F" ] || { printf '[FATAL] no <field>=$ZOT_LAST_ERR tail field in emitter line\n' >&2; exit 2; }

# ── Extraction helpers ───────────────────────────────────────────────────────────────────────
# sql_local: the heredoc body of `registry_store_not_luks_sql = <<[-]SQL` up to its `  SQL` closer.
sql_local() {
  awk '/^[[:space:]]*registry_store_not_luks_sql[[:space:]]*=[[:space:]]*<<[-]SQL/{f=1;next} f&&/^  SQL$/{f=0} f' "$TF"
}
# res_block: one resource block from its column-0 header to its column-0 closing brace.
res_block() {
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

LOCAL_SQL="$(sql_local)"
FLAT="$(printf '%s' "$LOCAL_SQL" | tr -s '[:space:]' ' ' | sed 's/^ //; s/ $//')"

# H1: an extractor that finds nothing would make every row below vacuous — so it must find the
# anchor, not merely "something".
if [ -n "$FLAT" ] && grep -qF "'${MUT_TAG} '" <<<"$FLAT"; then
  ok "the predicate local is a heredoc this guard can read, and it carries the ${MUT_TAG} anchor"
else
  no "registry_store_not_luks_sql: heredoc not found or anchorless — every row below would be vacuous"
fi

# Opener counts — an unanchored file-wide count must equal exactly 1, so a /* */- or #-wrapped
# decoy opener still counts and goes red.
_n_sql_openers="$(grep -cE 'registry_store_not_luks_sql = <<[-]SQL' "$TF")"
[ "$_n_sql_openers" -eq 1 ] \
  && ok "exactly one registry_store_not_luks_sql heredoc opener in the file (decoy copies count)" \
  || no "registry_store_not_luks_sql opener count is $_n_sql_openers, want 1 — a decoy local exists"
_n_exp="$(grep -cE 'resource "logtail_exploration" "registry_store_not_luks"' "$TF")"
[ "$_n_exp" -eq 1 ] \
  && ok "exactly one logtail_exploration.registry_store_not_luks resource header" \
  || no "logtail_exploration header count is $_n_exp, want 1 — a decoy resource exists"
_n_alr="$(grep -cE 'resource "logtail_exploration_alert" "registry_store_not_luks"' "$TF")"
[ "$_n_alr" -eq 1 ] \
  && ok "exactly one logtail_exploration_alert.registry_store_not_luks resource header" \
  || no "logtail_exploration_alert header count is $_n_alr, want 1 — a decoy resource exists"

[ "$(res_block logtail_exploration registry_store_not_luks | grep -cF 'sql_query = replace(trimspace(local.registry_store_not_luks_sql), "/\\s+/", " ")')" -eq 1 ] \
  && ok "the exploration carries THIS predicate, collapsed to one line (the siblings' perpetual-diff rule)" \
  || no "the exploration does not carry local.registry_store_not_luks_sql exactly once"

# EXACT PIN — canonical equality. The per-arm rows below say WHY each piece matters; this row
# says nothing else is there. The canon is assembled from the emitter-derived literals above.
_M="JSONExtractString(raw, 'message')"
EXPECTED_FLAT="SELECT {{time}} AS time, count(*) AS value FROM {{source}} WHERE time BETWEEN {{start_time}} AND {{end_time}} AND startsWith(raw, '{\"message\":\"${MUT_TAG} ') AND position($_M, '${MUT_TAG} ') = 1 AND ( NOT (position($_M, '${MUT_LUKS_F}yes ') > 0 AND position($_M, '${MUT_LUKS_F}yes ') < position($_M, '${MUT_ERR_F}')) OR (position($_M, '${MUT_ESC_F}') > 0 AND position($_M, '${MUT_ESC_F}') < position($_M, '${MUT_ERR_F}') AND position($_M, '${MUT_ESC_F}ok ') != position($_M, '${MUT_ESC_F}') AND position($_M, '${MUT_ESC_F}pending ') != position($_M, '${MUT_ESC_F}')) ) GROUP BY time"
[ "$FLAT" = "$EXPECTED_FLAT" ] \
  && ok "the whole predicate is byte-exact (SELECT, aggregate, both arms, GROUP BY)" \
  || no "the predicate drifted from the pinned text — diff FLAT against EXPECTED_FLAT"

# Column form. Every position() reads JSONExtractString(raw, 'message'); a bare column is an
# unknown-identifier error at query time, i.e. a rule that never pages.
n_pos="$(printf '%s' "$FLAT" | grep -oF 'position(' | wc -l | tr -d ' ')"
n_col="$(printf '%s' "$FLAT" | grep -oF "position(JSONExtractString(raw, 'message'), " | wc -l | tr -d ' ')"
if [ "$n_pos" -ge 7 ] && [ "$n_pos" -eq "$n_col" ] && ! grep -qE '\bmsg\b' <<<"$FLAT"; then
  ok "all ${n_pos} position() calls read JSONExtractString(raw, 'message'); no bare msg column"
else
  no "column form drifted: ${n_col}/${n_pos} position() calls use JSONExtractString(raw, 'message')"
fi

grep -qF "AND startsWith(raw, '{\"message\":\"${MUT_TAG} ')" <<<"$FLAT" \
  && ok "envelope-anchored to the direct-POST shape (a journald row quoting the marker cannot match)" \
  || no "the startsWith(raw, '{\"message\":\"${MUT_TAG} ') envelope conjunct is missing"

grep -qF "AND position(JSONExtractString(raw, 'message'), '${MUT_TAG} ') = 1" <<<"$FLAT" \
  && ok "the marker is anchored at position 1 of the message, with its trailing space" \
  || no "the message-level marker anchor is missing or unanchored"

# Per-arm parse. Arm A is the NOT(...) before the one top-level OR; arm B is the rest of the group.
ARMS="$(printf '%s' "$FLAT" | python3 -c '
import re, sys
s = sys.stdin.read()
m = re.search(r"AND \( ?NOT \((.*?)\) ?OR \((.*)\) ?\) GROUP BY time$", s)
if not m:
    sys.exit(1)
print(m.group(1)); print(m.group(2))
')" || ARMS=""
ARM_A="$(printf '%s\n' "$ARMS" | sed -n 1p)"
ARM_B="$(printf '%s\n' "$ARMS" | sed -n 2p)"

if [ -n "$ARM_A" ] && [ -n "$ARM_B" ]; then
  ok "the predicate parses as AND ( NOT (arm A) OR (arm B) )"
else
  no "the predicate no longer has the AND ( NOT (A) OR (B) ) shape — the per-arm rows below are vacuous"
fi

a_cut="$(printf '%s' "$ARM_A" | grep -oF "'${MUT_ERR_F}'" | wc -l | tr -d ' ')"
b_cut="$(printf '%s' "$ARM_B" | grep -oF "'${MUT_ERR_F}'" | wc -l | tr -d ' ')"
[ "$a_cut" -eq 1 ] \
  && ok "arm A is head-scoped: exactly one ordering comparison against '${MUT_ERR_F}'" \
  || no "arm A carries ${a_cut} '${MUT_ERR_F}' references (want 1) — tail text could satisfy it"
[ "$b_cut" -eq 1 ] \
  && ok "arm B is head-scoped: exactly one ordering comparison against '${MUT_ERR_F}'" \
  || no "arm B carries ${b_cut} '${MUT_ERR_F}' references (want 1) — tail text could suppress it"

grep -qF "position(JSONExtractString(raw, 'message'), '${MUT_LUKS_F}yes ') < position(JSONExtractString(raw, 'message'), '${MUT_ERR_F}')" <<<"$ARM_A" \
  && grep -qF "position(JSONExtractString(raw, 'message'), '${MUT_LUKS_F}yes ') > 0" <<<"$ARM_A" \
  && ok "arm A is the negation of '${MUT_LUKS_F}yes ' (WITH its trailing space) found before the tail" \
  || no "arm A lost the exact '${MUT_LUKS_F}yes ' literal or its before-the-tail ordering"

grep -qF "position(JSONExtractString(raw, 'message'), '${MUT_ESC_F}') > 0" <<<"$ARM_B" \
  && grep -qF "position(JSONExtractString(raw, 'message'), '${MUT_ESC_F}') < position(JSONExtractString(raw, 'message'), '${MUT_ERR_F}')" <<<"$ARM_B" \
  && ok "arm B requires a ${MUT_ESC_F} field in the head (pre-delivery rows cannot fire it)" \
  || no "arm B's ${MUT_ESC_F} presence test, or its before-the-tail ordering, is missing"

grep -qF "position(JSONExtractString(raw, 'message'), '${MUT_ESC_F}ok ') != position(JSONExtractString(raw, 'message'), '${MUT_ESC_F}')" <<<"$ARM_B" \
  && ok "arm B's only quiet state is '${MUT_ESC_F}ok ' at the head field's own position (any other token pages)" \
  || no "arm B no longer negates the exact '${MUT_ESC_F}ok ' literal — stale/none/indeterminate would go silent"

grep -qF "position(JSONExtractString(raw, 'message'), '${MUT_ESC_F}pending ') != position(JSONExtractString(raw, 'message'), '${MUT_ESC_F}')" <<<"$ARM_B" \
  && ok "arm B also exempts '${MUT_ESC_F}pending ' (the first-boot window before the deferred run lands)" \
  || no "arm B pages on 'pending' — every registry replace would page for its first 15+ minutes"

# ── Resource-block scoped, exactly-once attribute pins ───────────────────────────────────────
EXP_BLOCK="$(res_block logtail_exploration registry_store_not_luks)"
ALR_BLOCK="$(res_block logtail_exploration_alert registry_store_not_luks)"

param "$EXP_BLOCK" 'values' '\[local\.vector_prd_source_id\]' \
  && ok "the exploration reads local.vector_prd_source_id (the source the heartbeat POSTs to)" \
  || no "the exploration's source variable is not local.vector_prd_source_id (exactly once)"

param "$ALR_BLOCK" 'exploration_id' 'logtail_exploration\.registry_store_not_luks\.id' \
  && ok "the alert is attached to this exploration" \
  || no "the alert's exploration_id does not reference logtail_exploration.registry_store_not_luks"

param "$ALR_BLOCK" 'paused' 'false' \
  && ok "paused = false (the rule is quiet on the live fleet, so it arms at merge)" \
  || no "the alert is not 'paused = false' — it would exist and never page"
[ "$(printf '%s\n' "$ALR_BLOCK" | grep -c 'paused')" -eq 1 ] \
  && ok "the string 'paused' occurs exactly once in the alert block (a commented or duplicated decoy counts)" \
  || no "'paused' occurs !=1 time in the alert block — a commented pinned-line decoy exists"

param "$ALR_BLOCK" 'query_period' '900' \
  && ok "query_period = 900 (three */5 heartbeats; the API snaps the bucket to it)" \
  || no "query_period is not 900 (exactly once)"

param "$ALR_BLOCK" 'value' '1' \
  && ok "value = 1" \
  || no "value is not 1 (exactly once)"
param "$ALR_BLOCK" 'operator' '"higher_than"' \
  && ok "operator = higher_than: >= 2 matching rows per bucket, one transient row does not page" \
  || no "operator is not \"higher_than\" (exactly once)"

param "$ALR_BLOCK" 'check_period' '300' \
  && ok "check_period = 300" \
  || no "check_period is not 300 (exactly once)"

param "$ALR_BLOCK" 'on_missing_data' '"treat_as_zero"' \
  && ok "treat_as_zero, so an open incident can observe recovery" \
  || no "on_missing_data is not \"treat_as_zero\" (exactly once)"

param "$ALR_BLOCK" 'policy_id' 'var\.betterstack_paid_tier \? tonumber\(betteruptime_policy\.uptime\[0\]\.id\) : null' \
  && param "$ALR_BLOCK" 'team_name' 'var\.betterstack_paid_tier \? null : "Your team"' \
  && ok "escalation_target is the siblings' free/paid-tier ternary" \
  || no "escalation_target drifted from the siblings' routing"

grep -qF 'registry_store_not_luks_runbook_url = "https://github.com/jikig-ai/soleur/blob/main/knowledge-base/' "$TF" \
  && grep -qF '${local.registry_store_not_luks_runbook_url}' <<<"$ALR_BLOCK" \
  && ok "the incident carries a clickable runbook URL" \
  || no "no clickable runbook URL on the incident"

# The engine-level evidence lives in the .tf comment; its absence means the SQL was never run.
grep -qE '^#   \(ii\) +.store_luks=yes . -> .store_luks=nope . +-> [1-9][0-9]*' "$TF" \
  && grep -qE '^#   \(iii\) arm-B presence' "$TF" \
  && ok "the live-probe controls (ii) and (iii) are recorded with a non-zero count" \
  || no "the live-probe positive controls are not recorded in the .tf comment"

# NEGATIVE row: no count/for_each/lifecycle/ignore_changes token inside EITHER resource block.
# `lifecycle { ignore_changes = [paused] }` would decouple the declaration from the provider;
# `count`/`for_each` would multiply or zero the resource — each a silent mute the param rows
# cannot see. Line-anchored: a comment mentioning the words does not count.
if [ "$(printf '%s\n%s\n' "$EXP_BLOCK" "$ALR_BLOCK" | grep -cE '^[[:space:]]*(count|for_each|lifecycle|ignore_changes)[[:space:]]*[= {]')" -eq 0 ]; then
  ok "no count/for_each/lifecycle/ignore_changes mute knob inside either resource block"
else
  no "a count/for_each/lifecycle/ignore_changes token sits inside a resource block — a mute knob the provider would honor silently"
fi

# Both -target lines, INSIDE the push-triggered `apply:` job (not a dispatch-only job).
APPLY_JOB="$(awk '/^  apply:$/{f=1; print; next} f && /^  [A-Za-z0-9_-]+:$/{f=0} f' "$WF")"
grep -qxF '              -target=logtail_exploration.registry_store_not_luks \' <<<"$APPLY_JOB" \
  && grep -qxF '              -target=logtail_exploration_alert.registry_store_not_luks \' <<<"$APPLY_JOB" \
  && ok "both resources are in the push-triggered apply job's -target allowlist (#5566)" \
  || no "one or both -target= lines are missing from the apply job — the alert would never exist"

# ── Workflow seam — the suite is registered, and no env axis may reach the workflow ──────────
# The run line pins byte-exact (exactly once) so a rename/moved step cannot silently unregister
# the suite; and no REGSTORE_ or MUT_SKIP literal may appear in the workflow's executable text —
# the shipped convention's seam check, strictly stronger than an `env -u` prefix (which the
# sibling registry-clientip pin forbids by construction anyway). Whole-line comments are
# stripped; an inline ` # MUT_SKIP` still reds — deliberate over-caution.
REG_RUN='        run: bash apps/web-platform/test/infra/registry-store-not-luks-alert.test.sh'
IV_CODE="$(awk '!/^[[:space:]]*#/' "$IV")"
n_run="$(printf '%s\n' "$IV_CODE" | grep -cFx "$REG_RUN")"
[ "$n_run" -eq 1 ] \
  && ok "this suite's run line is registered in infra-validation.yml exactly once" \
  || no "run line count is $n_run, want 1 — the suite is unregistered or double-registered"

seam_bad=""
printf '%s\n' "$IV_CODE" | grep -nE 'REGSTORE_' >/dev/null && seam_bad="$seam_bad REGSTORE_-literal"
printf '%s\n' "$IV_CODE" | grep -nE 'MUT_SKIP' >/dev/null && seam_bad="$seam_bad MUT_SKIP-literal"
[ -z "$seam_bad" ] \
  && ok "no REGSTORE_/MUT_SKIP literal reaches the workflow's executable text (env muting is barred)" \
  || no "workflow seam violated:$seam_bad — a guard env axis is reachable from infra-validation.yml"

# ── Mutation rows: each must make the rows above RED (must-PASS rows stay GREEN) ─────────────
if [ -z "${MUT_SKIP:-}" ]; then
  MUT_DIR="$(mktemp -d -t regstorealert.XXXXXX)" || { printf '[FATAL] mktemp failed\n' >&2; exit 2; }
  assert_fixture_dir "$MUT_DIR"
  trap 'rm -rf "$MUT_DIR"' EXIT

  # INSTRUMENT CONTROL — the inner run against the PRISTINE tree must exit 0, or every row
  # below would grade a broken invocation as "mutation RED".
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
SQLLOC = "registry_store_not_luks_sql = <<\x2dSQL"
SQLEND = "\n  SQL\n"
EXPRES = "resource \"logtail_exploration\" \"registry_store_not_luks\" {"
ALRRES = "resource \"logtail_exploration_alert\" \"registry_store_not_luks\" {"'

  # _red_verdict <rc> <log> <fragment>: prints red | wrong | survived | unresolved. Only rc=1
  # is a caught mutation; when a fragment is named a [FAIL] line must contain it. Pipe-free of
  # `grep -q` upstream (SIGPIPE under pipefail); plain grep -F >/dev/null reads the whole stream.
  _red_verdict() {
    case "$1" in
      1) if [ -z "$3" ] || { grep -F '[FAIL]' "$2" | grep -F -- "$3" >/dev/null; }; then echo red; else echo wrong; fi ;;
      0) echo survived ;;
      *) echo unresolved ;;
    esac
  }

  # mutate_red <label> <TF|WF|CI|IV> <python-program-on-s> [expected [FAIL] fragment] [red|wrong]
  mutate_red() {
    local label="$1" which="$2" prog="$3" tag="${4:-}" want="${5:-red}" src copy rc=0 olog="$MUT_DIR/inner.log"
    case "$which" in
      TF) src="$TF"; copy="$MUT_DIR/betterstack-logs-alerts.tf" ;;
      WF) src="$WF"; copy="$MUT_DIR/apply-web-platform-infra.yml" ;;
      CI) src="$CI"; copy="$MUT_DIR/cloud-init-registry.yml" ;;
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
    env "REGSTORE_${which}=$copy" MUT_SKIP=1 bash "$SELF" >"$olog" 2>&1 || rc=$?
    # rc DISCRIMINATION: rc>=2 is this guard's own FATAL class, never evidence. want=wrong is
    # the scorer's NEGATIVE CONTROL: a mutant that reds a row other than the one the fragment
    # names must grade WRONG, or every fragment check is decoration.
    case "$(_red_verdict "$rc" "$olog" "$tag"):$want" in
      red:red) ok "mutation RED: $label" ;;
      wrong:wrong) ok "scorer control: graded WRONG reason as required: $label" ;;
      wrong:red) no "mutation went red for the WRONG reason (no [FAIL] line contains '$tag'): $label" ;;
      red:wrong) no "scorer control: the wrong-reason mutant was graded RED (the fragment check accepts anything): $label" ;;
      survived:*) no "mutation SURVIVED: $label — the rows above pin nothing" ;;
      *) no "mutation UNRESOLVED (inner rc=$rc, not an assertion): $label — instrument, not evidence" ;;
    esac
  }

  # mutate_green <label> <python-program-on-tf-copy>: a legitimate edit must NOT red the guard.
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
    REGSTORE_TF="$copy" MUT_SKIP=1 bash "$SELF" >"$MUT_DIR/green.log" 2>&1 || rc=$?
    case "$rc" in
      0) ok "must-PASS stays green: $label" ;;
      1) no "legitimate edit went RED: $label" ;;
      *) no "must-PASS UNRESOLVED (inner rc=$rc): $label - instrument, not evidence" ;;
    esac
  }

  # mutate_floor_red: bumping PRESENCE_ROWS +1 in a scratch copy of SELF must trip the floor —
  # proves the floor is not dead text. The copy's REPO line is rewritten so its reads resolve.
  mutate_floor_red() {
    local label="$1" copy rc=0
    copy="$MUT_DIR/floor-mutated.test.sh"
    local cur
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
  mutate_red "a /* */-wrapped decoy heredoc carrying a verbatim conjunct copy sits before the live local while the live body is gutted" TF \
    's = edit(s, SQLLOC, "count(*) AS value", "count(*) * 0 AS value", SQLEND)
i = s.index(SQLLOC)
s = s[:i] + "/*\n  registry_store_not_luks_sql = <<\x2dSQL\n  SELECT legit\n  SQL\n*/\n" + s[i:]' \
    "decoy local exists"
  mutate_red "a #-commented decoy opener line sits above the live local" TF \
    'i = s.index(SQLLOC)
s = s[:i] + "  # registry_store_not_luks_sql = <<\x2dSQL\n" + s[i:]' \
    "decoy local exists"
  mutate_red "a commented-out paused=false decoy line appears inside the alert block" TF \
    's = edit(s, ALRRES, "  paused = false\n", "  paused = false\n  # paused = false\n")' \
    "decoy exists"
  mutate_red "an inline tautology disjunct is appended inside the predicate" TF \
    's = edit(s, SQLLOC, "GROUP BY time", "GROUP BY time OR 1=1", SQLEND)' \
    "drifted from the pinned"
  mutate_red "a doubled-dollar escape literal appears inside the heredoc" TF \
    's = edit(s, SQLLOC, "count(*) AS value", "count(*) AS value /* $$escaped */", SQLEND)' \
    "drifted from the pinned"
  mutate_red "the live predicate local is gutted to a placeholder while the resource keeps its name" TF \
    's = edit(s, SQLLOC, "SELECT {{time}} AS time, count(*) AS value", "SELECT 1", SQLEND)' \
    "drifted from the pinned"

  # ── Canon/arm rows ─────────────────────────────────────────────────────────────────────────
  Q="JSONExtractString(raw, \\x27message\\x27)"
  mutate_red "drop arm A's ordering conjunct against the tail delimiter" TF \
    's = edit(s, SQLLOC, " AND position('"$Q"', \x27'"${MUT_LUKS_F}"'yes \x27) < position('"$Q"', \x27'"${MUT_ERR_F}"'\x27))", ")", SQLEND)' \
    "arm A carries"
  mutate_red "paused = false becomes paused = true" TF \
    's = edit(s, ALRRES, "  paused = false\n", "  paused = true\n")' \
    "paused = false"
  mutate_red "drop the exploration_alert -target= line" WF \
    'old = "              -target=logtail_exploration_alert.registry_store_not_luks \\\n"
assert s.count(old) == 1
s = s.replace(old, "")' \
    "-target= lines are missing"
  mutate_red "the trailing-space field terminator is dropped" TF \
    'i = s.index(SQLLOC); j = s.index(SQLEND, i)
blk = s[i:j]
old = "\x27'"${MUT_LUKS_F}"'yes \x27"
assert blk.count(old) == 2, blk.count(old)
s = s[:i] + blk.replace(old, "\x27'"${MUT_LUKS_F}"'yes\x27") + s[j:]' \
    "drifted from the pinned"
  mutate_red "arm B narrowed back to ${MUT_ESC_F}fail" TF \
    'i = s.index(SQLLOC); j = s.index(SQLEND, i)
blk = s[i:j]
old = "\n          AND position('"$Q"', \x27'"${MUT_ESC_F}"'ok \x27) != position('"$Q"', \x27'"${MUT_ESC_F}"'\x27)\n          AND position('"$Q"', \x27'"${MUT_ESC_F}"'pending \x27) != position('"$Q"', \x27'"${MUT_ESC_F}"'\x27))"
assert blk.count(old) == 1
blk2 = blk.replace(old, ")")
assert blk2.count("\x27'"${MUT_ESC_F}"'\x27") == 2
s = s[:i] + blk2.replace("\x27'"${MUT_ESC_F}"'\x27", "\x27'"${MUT_ESC_F}"'fail\x27") + s[j:]' \
    "no longer negates"
  mutate_red "JSONExtractString(raw, 'message') becomes a bare msg" TF \
    'i = s.index(SQLLOC); j = s.index(SQLEND, i)
blk = s[i:j]
assert blk.count("JSONExtractString(raw, \x27message\x27)") >= 7
s = s[:i] + blk.replace("JSONExtractString(raw, \x27message\x27)", "msg") + s[j:]' \
    "column form"
  mutate_red "arm B drops the pending exemption" TF \
    's = edit(s, SQLLOC, "\n          AND position('"$Q"', \x27'"${MUT_ESC_F}"'pending \x27) != position('"$Q"', \x27'"${MUT_ESC_F}"'\x27))", ")", SQLEND)' \
    "pending"
  mutate_red "arithmetic on arm A's ordering comparison (+ 100000)" TF \
    's = edit(s, SQLLOC, "\x27'"${MUT_LUKS_F}"'yes \x27) < position('"$Q"', \x27'"${MUT_ERR_F}"'\x27))", "\x27'"${MUT_LUKS_F}"'yes \x27) < position('"$Q"', \x27'"${MUT_ERR_F}"'\x27) + 100000)", SQLEND)' \
    "drifted from the pinned"
  mutate_red "the aggregate is zeroed (count(*) * 0)" TF \
    's = edit(s, SQLLOC, "SELECT {{time}} AS time, count(*) AS value", "SELECT {{time}} AS time, count(*) * 0 AS value", SQLEND)' \
    "drifted from the pinned"
  mutate_red "the heredoc the extractor reads is renamed (extracted SQL empty)" TF \
    'assert s.count(SQLLOC) == 1
s = s.replace(SQLLOC, "registry_store_not_luks_sql_v2 = <<\x2dSQL")' \
    "heredoc not found"

  # ── Emitter/wiring rows ────────────────────────────────────────────────────────────────────
  # (No emitter-mutation row: a renamed emitter literal FATALs the derivation at rc 2 — the
  # FATAL-on-empty contract is the guard; rc 2 is instrument-class, not a gradeable verdict.)
  mutate_red "the count=0 mute knob is added inside the alert resource" TF \
    's = edit(s, ALRRES, "  paused = false\n", "  count = 0\n  paused = false\n")' \
    "mute knob"

  # ── Workflow seam rows ─────────────────────────────────────────────────────────────────────
  mutate_red "a MUT_SKIP literal reaches the workflow's executable text" IV \
    'old = "        run: bash apps/web-platform/test/infra/registry-store-not-luks-alert.test.sh\n"
assert s.count(old) == 1
s = s.replace(old, "        env:\n          MUT_SKIP: \"1\"\n" + old)' \
    "workflow seam"
  mutate_red "a REGSTORE_ literal reaches the workflow's executable text" IV \
    'old = "        run: bash apps/web-platform/test/infra/registry-store-not-luks-alert.test.sh\n"
assert s.count(old) == 1
s = s.replace(old, old + "        env:\n          REGSTORE_TF: /dev/null\n")' \
    "workflow seam"
  mutate_red "the suite's own run line is dropped from the workflow" IV \
    'old = "        run: bash apps/web-platform/test/infra/registry-store-not-luks-alert.test.sh\n"
assert s.count(old) == 1
s = s.replace(old, "")' \
    "unregistered or double-registered"

  # ── Scorer negative control — a mutant that reds a row other than the named one must grade
  # WRONG (never RED), or the fragment check is decoration.
  mutate_red "scorer control: arm-B drop reds a different row than the named fragment" TF \
    's = edit(s, SQLLOC, "\n          AND position('"$Q"', \x27'"${MUT_ESC_F}"'pending \x27) != position('"$Q"', \x27'"${MUT_ESC_F}"'\x27))", ")", SQLEND)' \
    "this-fragment-does-not-exist" wrong

  # ── Floor row ──────────────────────────────────────────────────────────────────────────────
  mutate_floor_red "assertion floor trips when PRESENCE_ROWS is bumped one past the real count"

  # ── must-PASS rows ─────────────────────────────────────────────────────────────────────────
  mutate_green "whitespace reflow of the heredoc" \
    'i = s.index(SQLLOC); j = s.index(SQLEND, i)
blk = s[i:j]
old = "\n          AND position('"$Q"', \x27'"${MUT_ESC_F}"'ok \x27)"
assert blk.count(old) == 1
blk = blk.replace(old, " AND\n              position('"$Q"', \x27'"${MUT_ESC_F}"'ok \x27)")
old2 = "\n        OR (position("
assert blk.count(old2) == 1
s = s[:i] + blk.replace(old2, "\n  OR   (position(") + s[j:]'
fi

# ── Assertion floor + ledger (constructible: pure assignments only inside the window) ────────
# PRESENCE_ROWS is exactly the count of rows an inner (MUT_SKIP) run asserts; the outer run adds
# one row per mutation. The instrument control is what catches a floor drifting past the rows.
PRESENCE_ROWS=32
MUT_ROWS=23
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
[ -n "${MUT_SKIP:-}" ] && printf '[note] MUT_SKIP active — mutation rows skipped (floor %s); REGSTORE_{TF,WF,CI,IV}=%s,%s,%s,%s\n' "$_floor" "${REGSTORE_TF:-unset}" "${REGSTORE_WF:-unset}" "${REGSTORE_CI:-unset}" "${REGSTORE_IV:-unset}"
printf '\n=== registry-store-not-luks-alert: %s passed, %s failed (%s assertions, floor %s) ===\n' "$pass" "$fail" "$_ran" "$_floor"
[ "$fail" -eq 0 ]
