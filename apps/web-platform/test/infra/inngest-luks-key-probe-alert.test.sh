#!/usr/bin/env bash
#
# Drift guard for the Better Stack Logs alert that reads the on-host LUKS key-continuity probe
# (#9927 item 2; apps/web-platform/infra/betterstack-logs-alerts.tf):
#
#   inngest_luks_key_probe_fail  pages on a FAILED verdict   (token=fail_*)
#
# THE DEAD-MAN IS NOT SHIPPED HERE (CTO ruling D12). The self-arming absence alert
# (`inngest_luks_key_probe_dark`, query_period 2592000) moves to a follow-up PR that lands only after
# an owner-authorized create-and-delete probe proves the Better Stack API accepts that value; that
# follow-up is a blocking prerequisite of the bundle promotion (#11266). The NEGATIVE rows below pin
# the split: no dead-man resource, SQL local or -target line may appear in this change.
#
# WHAT THIS FILE IS, AND IS NOT. Text-level assertions over the Terraform SOURCE and the apply
# workflow's -target allowlist. It pins the SQL and the parameters the CTO rulings D4/D5b/D12 fixed
# (knowledge-base/project/specs/archive/20261027-112122-feat-one-shot-9927-key-continuity-probe/decision-challenges.md). It
# does NOT prove the SQL's BEHAVIOUR (that is the read-only substitution run through
# scripts/betterstack-query.sh) and does NOT prove the alert is unpaused in Better Stack.
#
# WHY EACH ROW EXISTS rather than "the SQL looks right":
#   * The paging SQL carries `token=fail_` and NOT `indeterminate`: an unmeasured verdict must never
#     page on its own (a transient low-memory skip would page a day).
#   * The paging SQL anchors the marker at message position 1 (`position(...)=1`) and never uses a
#     `raw LIKE` prefilter: webhook payloads that QUOTE the marker (a PR body, the runbook) reach
#     this source and would count as live probe rows.
#   * It filters on the `dt` COLUMN, never the `time` alias (the alias is a single end-of-window
#     value; a filter on it would test the wrong thing).
#   * One whole-window aggregate, no GROUP BY: a per-bucket form reads "no bucket" as "no row".
#   * The alert resource has BOTH of its -target= lines in the apply allowlist (#5566: an
#     untargeted resource is never applied and never exists), and exactly those two.
#
# Mutation rows live at the bottom. Each one COPIES a source file into a scratch dir, mutates the
# COPY, and re-runs this guard against the copy through the KEYPROBE_GUARD_{TF,WF} overrides. No
# tracked file is ever written.
set -uo pipefail
export TMPDIR="${TMPDIR:-/var/tmp}"

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$DIR/../../../.." && pwd)"
TF="${KEYPROBE_GUARD_TF:-$REPO/apps/web-platform/infra/betterstack-logs-alerts.tf}"
WF="${KEYPROBE_GUARD_WF:-$REPO/.github/workflows/apply-web-platform-infra.yml}"
FLIP="${KEYPROBE_GUARD_FLIP:-$REPO/apps/web-platform/infra/inngest-cutover-flip.sh}"
RB="${KEYPROBE_GUARD_RB:-$REPO/knowledge-base/engineering/operations/runbooks/inngest-luks-cutover-6894.md}"
CI="${KEYPROBE_GUARD_CI:-$REPO/apps/web-platform/infra/cloud-init-inngest.yml}"

pass=0; fail=0; FAILED=()
ok() { pass=$((pass + 1)); printf '[ok] %s\n' "$1"; }
no() { fail=$((fail + 1)); FAILED+=("$1"); printf '[FAIL] %s\n' "$1"; }

# P1b (#7708) — byte-identical to every other tracked copy; the P1a suite pins that.
# `$(cd X && pwd)` prints an absolute path but yields EMPTY when the cd fails. Every path this
# file READS is checked through it; the scratch dir every mutation WRITES to is checked too.
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
assert_fixture_dir "$TF"; assert_fixture_dir "$WF"; assert_fixture_dir "$FLIP"; assert_fixture_dir "$RB"; assert_fixture_dir "$CI"

# INSTRUMENT SELF-TEST — both helpers must move their own counter before any verdict is trusted.
_p0=$pass; _f0=$fail
{ ok "self-test"; no "self-test"; } >/dev/null
if [ "$pass" -ne $((_p0 + 1)) ] || [ "$fail" -ne $((_f0 + 1)) ] || [ "${#FAILED[@]}" -ne 1 ]; then
  printf '[FATAL] instrument self-test: ok()/no() did not each move their counter\n' >&2; exit 2
fi
pass=$_p0; fail=$_f0; FAILED=()

for f in "$TF" "$WF" "$FLIP" "$RB" "$CI"; do
  [ -r "$f" ] || { printf '[FATAL] unreadable: %s\n' "$f" >&2; exit 2; }
done

MARKER='SOLEUR_INNGEST_LUKS_KEY_PROBE'
FAIL_NAME='inngest_luks_key_probe_fail'
# The census below is MARKER-based: every logtail_exploration(_alert) in the .tf that carries MARKER (inline, or through a
# local whose heredoc carries it), plus every one whose NAME starts with the stem, must be listed here. A resource that
# reads the marker but is missing from this list fails the census with "add it to KEY_PROBE_EXPLORATIONS in this PR";
# adding a legitimate second key-probe pair is that one-line edit, not a rewrite of a hard-coded count.
KEY_PROBE_EXPLORATIONS='inngest_luks_key_probe_fail'
KEY_PROBE_STEM='inngest_luks_key_probe'

# ── derived needles (#11527): emitter literals are never re-pinned. A coordinated rename that
# updates the emitter sources but misses the .tf conjunct must go RED, which only happens when
# the needle follows the source. Each extraction is FATAL-on-empty: an unreadable needle would
# silently re-pin every row below on a dead literal.
# Leg A's SYSLOG_IDENTIFIER literal: the `readonly LOG_TAG=` call-form in inngest-cutover-flip.sh.
export MUT_TAG
MUT_TAG="$(sed -n 's/^[^#]*readonly LOG_TAG="\([^"]*\)".*/\1/p' "$FLIP" | head -1)"
[ -n "$MUT_TAG" ] || { printf '[FATAL] no readonly LOG_TAG= line in inngest-cutover-flip.sh — the leg-A emitter needle has no canonical source\n' >&2; exit 2; }
# Leg B's `stage` literal is a CALL-SITE literal with no canonical lib — its authority is the
# bounded first arg of the `inngest-boot-phone-home.sh <stage>` call form in
# inngest-cutover-flip.sh. No `#` before the helper name, so a comment carrying the bare
# literal cannot satisfy it, and the bounded pattern yields the arg itself — a rename to a
# superstring (luks-key-probe-v2) extracts the NEW literal, reddening the .tf needle instead of
# silently re-pinning a stale one.
export MUT_STAGE
MUT_STAGE="$(sed -n 's/^[^#]*inngest-boot-phone-home\.sh.\{0,3\}[[:space:]]\+"\(luks-key-probe[A-Za-z0-9_-]*\)"[[:space:]].*/\1/p' "$FLIP" | head -1)"
[ -n "$MUT_STAGE" ] || { printf '[FATAL] no luks-key-probe call site on inngest-boot-phone-home.sh in inngest-cutover-flip.sh — the stage needle has no canonical source\n' >&2; exit 2; }
# The leg-B `shipper` literal is the payload builder's own — its authority is the jq envelope in
# cloud-init-inngest.yml (`shipper:"…"`), derived the same way so a payload-side rename that
# misses the .tf goes red rather than leaving the needle green on a dead literal.
export MUT_SHIPPER
MUT_SHIPPER="$(sed -n 's/^[^#]*shipper:"\([^"]*\)".*/\1/p' "$CI" | head -1)"
[ -n "$MUT_SHIPPER" ] || { printf '[FATAL] no shipper literal in the cloud-init-inngest.yml payload builder — the shipper needle has no canonical source\n' >&2; exit 2; }

# The SQL heredoc local, extracted from its FIRST UNCOMMENTED opening line to the closing `  SQL`.
sql_local() {  # sql_local <local-name>  -> whitespace-stripped SQL on stdout
  awk -v n="$1" '$0 ~ "^[[:space:]]*" n "[[:space:]]*=[[:space:]]*<<-SQL" {f=1; next} f && /^  SQL$/ {f=0} f' "$TF" \
    | tr -d '[:space:]'
}
# One resource block, from its opening line to the closing brace at column 0.
res_block() {  # res_block <type> <name>
  awk -v t="$1" -v n="$2" 'index($0, "resource \"" t "\" \"" n "\" {") == 1 {f=1} f {print} f && /^}/ {exit}' "$TF"
}
# A whole-line attribute assertion inside a block, anchored at both ends and required exactly once.
param() {  # param <block> <key> <value-ERE>
  local n
  n="$(grep -cE "^[[:space:]]*$2[[:space:]]*=[[:space:]]*$3[[:space:]]*(#.*)?$" <<< "$1")"
  [ "$n" -eq 1 ]
}

FAIL_SQL="$(sql_local inngest_luks_key_probe_fail_sql)"

FAIL_CANON="SELECTtoDateTime({{end_time}})AStime,count(*)ASvalueFROM{{source}}WHEREdtBETWEEN{{start_time}}AND{{end_time}}ANDposition(JSONExtractString(raw,'message'),'${MARKER}')=1AND(JSONExtractString(raw,'SYSLOG_IDENTIFIER')='${MUT_TAG}'ANDposition(JSONExtractString(raw,'message'),'token=fail_')>0OR(JSONExtractString(raw,'shipper')='${MUT_SHIPPER}'ANDJSONExtractString(raw,'stage')='${MUT_STAGE}'AND(JSONExtractString(raw,'detail')=''ORposition(JSONExtractString(raw,'detail'),'token=fail_')>0)))"
ANCHOR="position(JSONExtractString(raw,'message'),'${MARKER}')=1"

# ── presence rows: the SQL locals ─────────────────────────────────────────────────────────────
[ -n "$FAIL_SQL" ] \
  && ok "the paging predicate local is a heredoc this guard can read" \
  || no "inngest_luks_key_probe_fail_sql: heredoc not found — every paging-SQL row below would be vacuous"

[ "$FAIL_SQL" = "$FAIL_CANON" ] \
  && ok "paging SQL is exactly the ruled form (whitespace-insensitive)" \
  || no "paging SQL differs from the ruled form: $FAIL_SQL"

# ── presence rows: paging SQL, named properties ───────────────────────────────────────────────
grep -qF "'token=fail_')>0" <<< "$FAIL_SQL" \
  && ok "paging SQL matches token=fail_ (every failed verdict pages)" \
  || no "paging SQL does not match token=fail_"
grep -qiF 'indeterminate' <<< "$FAIL_SQL" \
  && no "paging SQL names indeterminate — an unmeasured verdict would page on its own" \
  || ok "paging SQL does NOT name indeterminate (an unmeasured verdict never pages on its own)"
grep -qF "$ANCHOR" <<< "$FAIL_SQL" \
  && ok "paging SQL anchors the marker at message position 1" \
  || no "paging SQL does not anchor the marker with position(...)=1"
grep -qiE 'LIKE|GROUPBY' <<< "$FAIL_SQL" \
  && no "paging SQL has a LIKE or GROUP BY (a quoting webhook row could page; a bucketed form reads no-bucket as no-row)" \
  || ok "paging SQL has no raw LIKE prefilter and no GROUP BY"
grep -qE '(^|[^A-Za-z_])time(BETWEEN|>|<|=)' <<< "$FAIL_SQL" \
  && no "paging SQL filters on the time alias" \
  || ok "paging SQL filters on the dt column, not the time alias"

# ── presence rows: the two emitters (#11527) — the marker alone admitted ANY emitter, so the
# row set is pinned to the probe's two real emitters: the journald tag on leg A, the phone-home
# envelope identity on leg B. A marker-quoting row under a foreign SYSLOG_IDENTIFIER (a doppler
# event-log row quoting the marker) can never count.
printf '%s' "$FAIL_SQL" | grep -cF >/dev/null "JSONExtractString(raw,'SYSLOG_IDENTIFIER')='${MUT_TAG}'" \
  && ok "leg A pins SYSLOG_IDENTIFIER='${MUT_TAG}' — needle derived from readonly LOG_TAG=, so a tag rename missing this SQL goes red" \
  || no "the leg-A emitter conjunct is missing or pinned to a stale literal: journald rows cannot reach leg A"
printf '%s' "$FAIL_SQL" | grep -cF >/dev/null "JSONExtractString(raw,'shipper')='${MUT_SHIPPER}'" \
  && ok "leg B pins shipper='${MUT_SHIPPER}' — the emitter class of the phone-home envelope, derived from the payload builder" \
  || no "the shipper equality conjunct is missing or pinned to a stale literal: phone-home rows cannot reach leg B"
# The stage literal is a RESERVED token on a shared helper (inngest-boot-phone-home.sh takes
# `stage` as positional $1 at several call sites): a second emit site passing the same stage arg
# is a leg-B identity collision the predicate cannot see — exactly one call site may pass it.
_stage_sites="$(grep -cE '^[^#]*inngest-boot-phone-home\.sh[^[:space:]]*[[:space:]]+"luks-key-probe([[:space:]"]|$)' "$FLIP" || true)"
printf '%s' "$FAIL_SQL" | grep -cF >/dev/null "JSONExtractString(raw,'stage')='${MUT_STAGE}'" \
  && [ "$_stage_sites" = "1" ] \
  && ok "leg B pins stage='${MUT_STAGE}' AND exactly one emit site passes it — the token is reserved (needle derived from the call site, not re-pinned)" \
  || no "the stage equality conjunct is missing/stale, or emit-site count=${_stage_sites} (want 1) — a second emitter would collide on leg-B identity"
printf '%s' "$FAIL_SQL" | grep -cF >/dev/null "position(JSONExtractString(raw,'detail'),'token=fail_')>0" \
  && ok "leg B carries token=fail_ read from detail — the envelope's field row, never the marker-prefixed message" \
  || no "the detail-anchored token=fail_ check is missing on leg B — a phone-home fail row would not count"
# The detail='' disjunct is the piece that makes a detail-ABSENT row fire: position('') = 0
# rejects before any field check, so the conjunct-only form cannot deliver this fail-loud
# (sibling's measured T4 ruling, E3 0→1).
printf '%s' "$FAIL_SQL" | grep -cF >/dev/null "JSONExtractString(raw,'detail')=''" \
  && ok "leg B counts a detail-ABSENT identity-pinned row via the detail='' disjunct — the schema-drop fail-loud arm" \
  || no "the detail='' disjunct is missing — a detail-absent phone-home row would read healthy again"
# The two-leg SHAPE, not just the tokens: one outer AND( group holding leg A plus exactly one
# `OR (` arm, inside which one nested AND( group holds the detail disjunct. "Leg B's tokens
# exist somewhere in the SQL" cannot satisfy this while the arm that admits them is gone.
if [ "$(printf '%s' "$FAIL_SQL" | grep -oF 'OR(' | wc -l)" = "1" ] \
  && [ "$(printf '%s' "$FAIL_SQL" | grep -oF 'AND(' | wc -l)" = "2" ] \
  && printf '%s' "$FAIL_SQL" | grep -cE >/dev/null "OR\(JSONExtractString\(raw,'shipper'\)='${MUT_SHIPPER}'ANDJSONExtractString\(raw,'stage'\)='${MUT_STAGE}'AND\(JSONExtractString\(raw,'detail'\)=''ORposition\(JSONExtractString\(raw,'detail'\),'token=fail_'\)>0\)\)\)$"; then
  ok "the emitter-OR shape: leg A plus exactly one OR arm (shipper+stage identity) holding the detail disjunct group, closed at end of predicate"
else
  no "the OR-arm structure is missing or mis-nested — leg-B tokens may exist as dead text the predicate never admits"
fi

# ── presence rows: resources and parameters ───────────────────────────────────────────────────
FAIL_EX="$(res_block logtail_exploration "$FAIL_NAME")"
FAIL_AL="$(res_block logtail_exploration_alert "$FAIL_NAME")"

if [ -n "$FAIL_EX" ] && [ -n "$FAIL_AL" ]; then
  ok "both resources are declared (one exploration, one alert)"
else
  no "a resource block is missing (fail_ex=${#FAIL_EX} fail_al=${#FAIL_AL}) — every parameter row below would be vacuous"
fi

_k=fail
_ex="$FAIL_EX"
_al="$FAIL_AL"
_nm="inngest_luks_key_probe_$_k"
{
  param "$_ex" sql_query "replace\\(trimspace\\(local\\.${_nm}_sql\\), \"/\\\\\\\\s\\+/\", \" \"\\)" \
    && ok "$_k exploration carries its own predicate local, collapsed to one line (perpetual-diff rule)" \
    || no "$_k exploration does not carry local.${_nm}_sql as its collapsed sql_query"
  grep -qE '^[[:space:]]*values[[:space:]]*=[[:space:]]*\[local\.vector_prd_source_id\]' <<< "$_ex" \
    && ok "$_k exploration reads the shared prd Vector source" \
    || no "$_k exploration is not bound to local.vector_prd_source_id"
  param "$_al" exploration_id "logtail_exploration\\.${_nm}\\.id" \
    && ok "$_k alert is bound to its own exploration" \
    || no "$_k alert exploration_id is not logtail_exploration.${_nm}.id"
  param "$_al" name "\"soleur-inngest-luks-key-probe-${_k}-prd\"" \
    && ok "$_k alert is named soleur-inngest-luks-key-probe-${_k}-prd" \
    || no "$_k alert name is not soleur-inngest-luks-key-probe-${_k}-prd"
  param "$_al" alert_type '"threshold"' && param "$_al" operator '"higher_than"' && param "$_al" value 0 \
    && ok "$_k alert is threshold / higher_than / 0" \
    || no "$_k alert is not threshold higher_than 0"
  param "$_al" on_missing_data '"treat_as_zero"' \
    && ok "$_k alert reads missing data as zero (an open incident can observe recovery)" \
    || no "$_k alert on_missing_data is not treat_as_zero"
  param "$_al" paused false \
    && ok "$_k alert is unpaused (no variable arming route: it is quiet by construction)" \
    || no "$_k alert is not 'paused = false'"
  param "$_al" confirmation_period 0 && param "$_al" email true \
    && ok "$_k alert: confirmation_period 0, email true" \
    || no "$_k alert: confirmation_period is not 0 or email is not true"
  grep -qE '^[[:space:]]*policy_id[[:space:]]*=[[:space:]]*var\.betterstack_paid_tier \? tonumber\(betteruptime_policy\.uptime\[0\]\.id\) : null[[:space:]]*$' <<< "$_al" \
    && grep -qE '^[[:space:]]*team_name[[:space:]]*=[[:space:]]*var\.betterstack_paid_tier \? null : "Your team"[[:space:]]*$' <<< "$_al" \
    && ok "$_k alert carries the escalation block mirrored from the sibling (paid-tier gated)" \
    || no "$_k alert escalation_target is not the sibling's paid-tier-gated block"
  param "$_al" runbook 'local\.inngest_luks_key_probe_runbook_url' \
    && grep -qF 'local.inngest_luks_key_probe_runbook_url' <<< "$(grep -E '^[[:space:]]*incident_cause' <<< "$_al")" \
    && ok "$_k alert points its metadata.runbook and incident_cause at the key-probe runbook local" \
    || no "$_k alert does not point metadata.runbook AND incident_cause at local.inngest_luks_key_probe_runbook_url"
}

param "$FAIL_AL" check_period 300 && param "$FAIL_AL" query_period 900 && param "$FAIL_AL" recovery_period 3600 \
  && ok "paging alert window: check 300 s, query 900 s (15 min), recovery 3600 s" \
  || no "paging alert windows are not check 300 / query 900 / recovery 3600"

grep -qE '^[[:space:]]*inngest_luks_key_probe_runbook_url[[:space:]]*=[[:space:]]*"https://github\.com/jikig-ai/soleur/blob/main/knowledge-base/engineering/operations/runbooks/inngest-luks-cutover-6894\.md#key-continuity-probe-9927-item-2"[[:space:]]*$' "$TF" \
  && ok "the runbook local is the clickable URL of the 'Key-continuity probe (#9927 item 2)' subsection" \
  || no "inngest_luks_key_probe_runbook_url is not the runbook URL with the key-continuity-probe-9927-item-2 anchor"

# ── presence rows: the EMITTER and the runbook agree with the SQL (pairwise pins are not enough) ─
# The SQL, this guard and the probe suite each carry their own copy of the marker and the paging
# prefix; a rename in the script and the probe suite alone would leave this alert matching nothing,
# and on_missing_data=treat_as_zero reads that as health.
grep -qF "\"${MARKER} \${row}\"" "$FLIP" \
  && ok "the script's logger row carries the marker the SQL anchors on" \
  || no "inngest-cutover-flip.sh no longer emits the logger row as \"${MARKER} \${row}\" — the paging SQL would match nothing"
grep -qF "\"luks-key-probe\" \"\$row\" ${MARKER}" "$FLIP" \
  && ok "the script's phone-home call passes the same marker as its message prefix" \
  || no "the phone-home call no longer passes ${MARKER} as the marker override"
_toks="$(grep -oE 'luks_probe_finish [a-z_]+' "$FLIP" | awk '{print $2}' | sort -u | tr '\n' ' ')"
[ "$_toks" = "fail_header fail_key_absent fail_passphrase indeterminate ok " ] \
  && ok "the script emits exactly the closed token set, and every paging token starts with the fail_ prefix the SQL matches" \
  || no "the script's luks_probe_finish tokens drifted from the set the SQL and runbook assume: $_toks"
grep -qxF '### Key-continuity probe (#9927 item 2)' "$RB" \
  && ok "the runbook heading behind the alert's clickable anchor exists" \
  || no "the runbook has no '### Key-continuity probe (#9927 item 2)' heading — the alert's runbook anchor is dead"

# ── presence rows: -target parity with the apply workflow ─────────────────────────────────────
_miss=""
for ty in logtail_exploration logtail_exploration_alert; do
  grep -qE "^[[:space:]]*-target=$ty\\.$FAIL_NAME \\\\\$" "$WF" || _miss="$_miss $ty.$FAIL_NAME"
done
[ -z "$_miss" ] \
  && ok "both resources have an anchored -target= line in the apply workflow (#5566)" \
  || no "missing -target= line(s):$_miss — the resource would never be applied"

# Census over the .tf, MARKER-based. A resource is a key-probe resource when it carries MARKER (an exploration whose block
# names it, or whose sql_query reads a local whose heredoc names it; an alert that binds such an exploration) OR its name starts
# with the bare stem (so `inngest_luks_key_probe2_fail` and the bare stem are counted, #11388). Leading whitespace and a
# trailing comment after the brace do not hide a header. The declared set must equal KEY_PROBE_EXPLORATIONS for BOTH the
# exploration side and the alert side. Every root *.tf is scanned, the key is the substring LUKS_KEY_PROBE, a local name may
# contain a hyphen, a heredoc closer ends the current local, and a single-line local that names a marked local carries the
# marker too (transitively; a reference inside a string interpolation or a multi-line local is NOT followed). A family-wide structural suite
# (apps/web-platform/infra/betterstack-alert-structure.test.sh) independently enforces one alert per exploration.
CENSUS_AWK='function cv(s) { gsub(/"([^"\\]|\\.)*"/, "\"\"", s); sub(/[[:space:]]*(#|\/\/).*$/, "", s); return s }
function hdopen(c) {
  if (match(c, /<<-?[A-Za-z_][A-Za-z0-9_]*[[:space:]]*$/)) { hd = substr(c, RSTART); sub(/^<<-?/, "", hd); sub(/[[:space:]]+$/, "", hd) }
}
FNR == 1 { hd = ""; loc = ""; inb = 0 }
{
  line = $0
  if (hd != "") {
    if (line ~ ("^[[:space:]]*" hd "[[:space:]]*$")) { hd = ""; loc = "" }
    else if (index(line, MARK) > 0) { if (inb) braw[nb] = braw[nb] " " MARK; else if (loc != "") marked[loc] = 1 }
    next
  }
  if (line ~ /^[[:space:]]*(#|\/\/)/) next
  c = cv(line)
  if (!inb) {
    if (match(line, /^[[:space:]]*resource[[:space:]]+"?logtail_exploration(_alert)?"?[[:space:]]+"?[^" {]+"?[[:space:]]*\{/)) {
      kind = (line ~ /logtail_exploration_alert/) ? "A" : "E"
      nm = line
      sub(/^[[:space:]]*resource[[:space:]]+"?logtail_exploration(_alert)?"?[[:space:]]+"?/, "", nm)
      sub(/["[:space:]{].*$/, "", nm)
      nb++; bkind[nb] = kind; bname[nb] = nm; braw[nb] = ""; bcv[nb] = ""; inb = 1; d = 0
    } else {
      if (match(c, /^[[:space:]]*[A-Za-z0-9_-]+[[:space:]]*=[[:space:]]*<<-?[A-Za-z_]/)) {
        loc = c; sub(/^[[:space:]]*/, "", loc); sub(/[[:space:]]*=.*$/, "", loc)
      } else if (line ~ /^[[:space:]]*[A-Za-z0-9_-]+[[:space:]]*=/) {
        l2 = line; sub(/^[[:space:]]*/, "", l2); sub(/[[:space:]]*=.*$/, "", l2); lbody[l2] = line
        if (index(line, MARK) > 0) marked[l2] = 1
      }
      hdopen(c)
      next
    }
  }
  if (inb) {
    braw[nb] = braw[nb] " " line; bcv[nb] = bcv[nb] " " c
    o = gsub(/\{/, "{", c); x = gsub(/\}/, "}", c); d += o - x
    hdopen(cv(line))
    if (d <= 0) { inb = 0 }
  }
}
END {
  do {   # a single-line local that names a marked local carries the marker too, however deep the chain
    ch = 0
    for (l in lbody) if (!(l in marked)) for (m in marked) if (lbody[l] ~ ("local\\." m "([^A-Za-z0-9_-]|$)")) { newm[l] = 1; break }
    for (l in newm) { marked[l] = 1; ch = 1 }
    delete newm
  } while (ch)
  for (i = 1; i <= nb; i++) {
    car[i] = (index(braw[i], MARK) > 0)
    for (l in marked) if (bcv[i] ~ ("local\\." l "([^A-Za-z0-9_-]|$)")) car[i] = 1
  }
  for (i = 1; i <= nb; i++) if (bkind[i] == "E") ecar[bname[i]] = car[i]
  for (i = 1; i <= nb; i++) {
    if (bkind[i] == "E") { printf "E|%s|%d\n", bname[i], car[i]; continue }
    b = ""; t = bcv[i]
    if (match(t, /exploration_id[[:space:]]*=[[:space:]]*logtail_exploration\.[A-Za-z0-9_-]+\.id/)) {
      b = substr(t, RSTART, RLENGTH); sub(/^.*logtail_exploration\./, "", b); sub(/\.id$/, "", b)
    }
    printf "A|%s|%d|%s\n", bname[i], (b != "" && ecar[b]), b
  }
}'
# Every root *.tf is scanned (a local may live in another file than the resource that reads it), and the key is the
# substring LUKS_KEY_PROBE of the marker, so a renamed prefix (SOLEUR_<other>_LUKS_KEY_PROBE) still carries it.
_census="$(awk -v MARK="LUKS_KEY_PROBE" "$CENSUS_AWK" "$(dirname "$TF")"/*.tf 2>/dev/null)"
_dexp="$(while IFS='|' read -r _k _n _c _b; do
  [ "$_k" = E ] || continue
  if [ "$_c" = 1 ] || [[ "$_n" == "$KEY_PROBE_STEM"* ]]; then printf '%s\n' "$_n"; fi
done <<<"$_census" | sort -u | tr '\n' ' ')"
_dal="$(while IFS='|' read -r _k _n _c _b; do
  [ "$_k" = A ] || continue
  if [ "$_c" = 1 ] || [[ "$_n" == "$KEY_PROBE_STEM"* ]] || [[ "$_b" == "$KEY_PROBE_STEM"* ]]; then printf '%s\n' "$_n"; fi
done <<<"$_census" | sort -u | tr '\n' ' ')"
_want="$(printf '%s\n' $KEY_PROBE_EXPLORATIONS | sort -u | tr '\n' ' ')"
_extra_e="$(comm -23 <(printf '%s\n' $_dexp | sort -u) <(printf '%s\n' $_want | sort -u) | tr '\n' ' ')"
_extra_a="$(comm -23 <(printf '%s\n' $_dal | sort -u) <(printf '%s\n' $_want | sort -u) | tr '\n' ' ')"
_gone_e="$(comm -13 <(printf '%s\n' $_dexp | sort -u) <(printf '%s\n' $_want | sort -u) | tr '\n' ' ')"
_gone_a="$(comm -13 <(printf '%s\n' $_dal | sort -u) <(printf '%s\n' $_want | sort -u) | tr '\n' ' ')"
if [ -z "$_extra_e$_extra_a$_gone_e$_gone_a" ] && [ -n "$_want" ]; then
  ok "the .tf declares exactly the KEY_PROBE_EXPLORATIONS pair set (${_want% }), each once as an exploration and once as an alert, by marker and by stem"
else
  no "key-probe census differs from KEY_PROBE_EXPLORATIONS (${_want% }): undeclared exploration(s) [${_extra_e% }], undeclared alert(s) [${_extra_a% }], missing exploration(s) [${_gone_e% }], missing alert(s) [${_gone_a% }]: add it to KEY_PROBE_EXPLORATIONS in this PR"
fi

# ── NEGATIVE rows (D12): the dead-man is a follow-up PR, so nothing of it may exist here ─────────
# Whole-file greps on purpose (comments and strings included): a half-landed dead-man in any form
# is the regression this split must never silently suffer.
grep -qE 'logtail_exploration(_alert)?"[[:space:]]+"inngest_luks_key_probe_dark"' "$TF" \
  && no "the .tf declares an inngest_luks_key_probe_dark resource — the dead-man is NOT shipped in this change (D12)" \
  || ok "the .tf declares NO inngest_luks_key_probe_dark resource (dead-man deferred, D12)"
grep -qE 'inngest_luks_key_probe_dark' "$TF" \
  && no "the .tf names inngest_luks_key_probe_dark (SQL local or reference) — the dead-man is NOT shipped in this change (D12)" \
  || ok "the .tf carries NO inngest_luks_key_probe_dark SQL local or reference (D12)"
grep -qE 'inngest_luks_key_probe_dark' "$WF" \
  && no "the apply workflow carries an inngest_luks_key_probe_dark -target line — the dead-man is NOT shipped in this change (D12)" \
  || ok "the apply workflow carries NO inngest_luks_key_probe_dark -target line (D12)"
[ "$(grep -cE '^[[:space:]]*-target=logtail_exploration(_alert)?\.inngest_luks_key_probe_[A-Za-z0-9_]* \\$' "$WF")" -eq 2 ] \
  && ok "the apply workflow carries exactly the 2 paging -target lines for the key probe" \
  || no "the apply workflow does not carry exactly 2 key-probe -target lines"

# ── Mutation rows: each must make a row above RED ─────────────────────────────────────────────
SELF="${BASH_SOURCE[0]}"
if [ -z "${MUT_SKIP:-}" ]; then
  MUT_DIR="$(mktemp -d -t keyprobealert.XXXXXX)" || { printf '[FATAL] mktemp failed\n' >&2; exit 2; }
  assert_fixture_dir "$MUT_DIR"
  trap 'rm -rf "$MUT_DIR"' EXIT

  # INSTRUMENT CONTROL — the inner run against the PRISTINE tree must exit 0, or every row below
  # would grade a broken invocation as "mutation RED".
  ctl_rc=0; MUT_SKIP=1 bash "$SELF" >"$MUT_DIR/control.log" 2>&1 || ctl_rc=$?
  if [ "$ctl_rc" -ne 0 ]; then
    printf '[FATAL] instrument control: the inner run exited %s on the PRISTINE tree — the battery cannot be trusted:\n' "$ctl_rc" >&2
    sed 's/^/    /' "$MUT_DIR/control.log" >&2; exit 2
  fi

  # Helpers prepended to every mutation program. `Q` is the single quote (programs live inside
  # bash single quotes). `edit(s, anchor, old, new)` replaces `old` exactly once INSIDE the region
  # that starts at `anchor` and ends at the next blank-line-free closing marker (`\n  SQL\n` for a
  # heredoc local, `\n}\n` for a resource), so a literal that occurs in both SQLs is mutated in one.
  PRELUDE='Q = chr(39)
def edit(s, anchor, old, new, end="\n}\n"):
    i = s.index(anchor)
    j = s.index(end, i)
    region = s[i:j]
    assert region.count(old) == 1, "anchor drift: %r occurs %d times" % (old, region.count(old))
    return s[:i] + region.replace(old, new) + s[j:]
FAILSQL = "inngest_luks_key_probe_fail_sql = <<-SQL"
FAILAL = "resource \"logtail_exploration_alert\" \"inngest_luks_key_probe_fail\" {"
SQLEND = "\n  SQL\n"'

  # Scores ONE inner run: prints red | wrong | survived | unresolved. Only rc=1 is a caught mutation; when a fragment is named
  # a [FAIL] line must contain it (a row that reds for the WRONG reason is no evidence). The reader is pipe-free:
  # `grep | grep -q` lets the second grep exit early and the first die of SIGPIPE under pipefail.
  _red_verdict() {  # _red_verdict <rc> <log> <fragment-or-empty>
    case "$1" in
      1) if [ -z "$3" ] || { grep -F '[FAIL]' "$2" | grep -F -- "$3" >/dev/null; }; then echo red; else echo wrong; fi ;;
      0) echo survived ;;
      *) echo unresolved ;;
    esac
  }

  mutate_red() {  # mutate_red <label> <TF|WF|FLIP> <python-program-on-s> [expected [FAIL] fragment] [red|wrong]
    local label="$1" which="$2" prog="$3" tag="${4:-}" want="${5:-red}" src copy rc=0 olog="$MUT_DIR/inner.log"
    rm -f "$MUT_DIR"/zz_*.tf   # a second-file row plants one; it must not leak into the next row's census
    case "$which" in
      TF) src="$TF"; copy="$MUT_DIR/betterstack-logs-alerts.tf" ;;
      WF) src="$WF"; copy="$MUT_DIR/apply-web-platform-infra.yml" ;;
      FLIP) src="$FLIP"; copy="$MUT_DIR/inngest-cutover-flip.sh" ;;
      *) printf '[FATAL] mutate_red: unknown target %s\n' "$which" >&2; exit 2 ;;
    esac
    cp "$src" "$copy" || { printf '[FATAL] mutate_red: cp %s failed\n' "$src" >&2; exit 2; }
    # The program must land its edit and PROVE it: edit() asserts the anchor occurs exactly once
    # in its region, and `assert s != orig` is the floor.
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
    case "$which" in
      TF) KEYPROBE_GUARD_TF="$copy" MUT_SKIP=1 bash "$SELF" >"$olog" 2>&1 || rc=$? ;;
      WF) KEYPROBE_GUARD_WF="$copy" MUT_SKIP=1 bash "$SELF" >"$olog" 2>&1 || rc=$? ;;
      FLIP) KEYPROBE_GUARD_FLIP="$copy" MUT_SKIP=1 bash "$SELF" >"$olog" 2>&1 || rc=$? ;;
    esac
    # rc DISCRIMINATION. rc>=2 is this guard's own FATAL class, rc=126/127 a broken invocation: none is evidence a
    # row pins anything. want=wrong is the scorer's NEGATIVE CONTROL: a mutant that reds a row other than the one the
    # fragment names must be graded WRONG (never RED), or every fragment check above would be decoration.
    case "$(_red_verdict "$rc" "$olog" "$tag"):$want" in
      red:red) ok "mutation RED: $label" ;;
      wrong:wrong) ok "scorer control: graded WRONG reason as required: $label" ;;
      wrong:red) no "mutation went red for the WRONG reason (no [FAIL] line contains '$tag'): $label" ;;
      red:wrong) no "scorer control: the wrong-reason mutant was graded RED (the fragment check accepts anything): $label" ;;
      survived:*) no "mutation SURVIVED: $label — the rows above pin nothing" ;;
      *) no "mutation UNRESOLVED (inner rc=$rc, not an assertion): $label — instrument, not evidence" ;;
    esac
  }

  # A must-PASS row: a legitimate edit (here a comment) must NOT red the guard (rc 0 is the only pass).
  mutate_green() {  # mutate_green <label> <TF> <python-program-on-s>
    local label="$1" which="$2" prog="$3" copy rc=0
    rm -f "$MUT_DIR"/zz_*.tf
    [ "$which" = TF ] || { printf '[FATAL] mutate_green: only TF is wired\n' >&2; exit 2; }
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
    KEYPROBE_GUARD_TF="$copy" MUT_SKIP=1 bash "$SELF" >"$MUT_DIR/green.log" 2>&1 || rc=$?
    case "$rc" in
      0) ok "must-PASS stays green: $label" ;;
      1) no "legitimate edit went RED: $label" ;;
      *) no "must-PASS UNRESOLVED (inner rc=$rc): $label - instrument, not evidence" ;;
    esac
  }

  # Raising PRESENCE_ROWS above what an inner run asserts must trip the assertion floor (the floor is
  # pass+fail >= floor, so only a RAISE reds; lowering it cannot). The scratch copy gets every path through
  # the override env, so nothing resolves relative to its own location.
  mutate_floor_red() {  # mutate_floor_red <label>
    local label="$1" copy rc=0
    copy="$MUT_DIR/floor-mutated.test.sh"
    sed 's/^PRESENCE_ROWS=36$/PRESENCE_ROWS=37/' "$SELF" > "$copy"
    if cmp -s "$SELF" "$copy"; then no "mutation '$label' did not land (PRESENCE_ROWS anchor drifted)"; return 0; fi
    KEYPROBE_GUARD_TF="$TF" KEYPROBE_GUARD_WF="$WF" KEYPROBE_GUARD_FLIP="$FLIP" KEYPROBE_GUARD_RB="$RB" KEYPROBE_GUARD_CI="$CI" \
      MUT_SKIP=1 bash "$copy" >/dev/null 2>&1 || rc=$?
    case "$rc" in
      1) ok "mutation RED: $label" ;;
      0) no "mutation SURVIVED: $label - the assertion floor pins nothing" ;;
      *) no "mutation UNRESOLVED (inner rc=$rc, not an assertion): $label - instrument, not evidence" ;;
    esac
  }

  mutate_red "paging SQL widens to every marker row (token=fail_ dropped)" TF \
    's = edit(s, FAILSQL, "position(JSONExtractString(raw, "+Q+"message"+Q+"), "+Q+"token=fail_"+Q+") > 0", "", SQLEND)'
  mutate_red "paging SQL starts naming indeterminate (an unmeasured verdict would page)" TF \
    's = edit(s, FAILSQL, "position(JSONExtractString(raw, "+Q+"message"+Q+"), "+Q+"token=fail_"+Q+") > 0", "position(JSONExtractString(raw, "+Q+"message"+Q+"), "+Q+"token=fail_"+Q+") > 0 OR position(JSONExtractString(raw, "+Q+"message"+Q+"), "+Q+"indeterminate"+Q+") > 0", SQLEND)'
  mutate_red "paging SQL loses its position-1 marker anchor" TF \
    's = edit(s, FAILSQL, Q+"SOLEUR_INNGEST_LUKS_KEY_PROBE"+Q+") = 1", Q+"SOLEUR_INNGEST_LUKS_KEY_PROBE"+Q+") > 0", SQLEND)'
  mutate_red "paging SQL marker renamed (the rule would watch a row nobody emits)" TF \
    's = edit(s, FAILSQL, "SOLEUR_INNGEST_LUKS_KEY_PROBE", "SOLEUR_INNGEST_LUKS_KEY_PROBX", SQLEND)'
  mutate_red "paging SQL filters on the time alias" TF \
    's = edit(s, FAILSQL, "WHERE dt BETWEEN", "WHERE time BETWEEN", SQLEND)'
  mutate_red "paging window widens to 25 h (an incident would stay open for a day)" TF \
    's = edit(s, FAILAL, "query_period        = 900", "query_period        = 90000")'
  mutate_red "paging alert reads missing data as ok-forever (treat_as_zero dropped)" TF \
    's = edit(s, FAILAL, chr(34)+"treat_as_zero"+chr(34), chr(34)+"treat_as_null"+chr(34))'
  mutate_red "the paging alert is dropped from the apply allowlist" WF \
    'old = "              -target=logtail_exploration_alert.inngest_luks_key_probe_fail \\\n"
assert s.count(old) == 1
s = s.replace(old, "")'
  mutate_red "the dead-man is smuggled back: a dark -target line joins the apply allowlist" WF \
    'old = "              -target=logtail_exploration_alert.inngest_luks_key_probe_fail \\\n"
assert s.count(old) == 1
s = s.replace(old, old + "              -target=logtail_exploration.inngest_luks_key_probe_dark \\\n")'
  mutate_red "the dead-man is smuggled back: a dark resource joins the .tf" TF \
    's = s + "\nresource " + chr(34) + "logtail_exploration" + chr(34) + " " + chr(34) + "inngest_luks_key_probe_dark" + chr(34) + " {\n}\n"'
  mutate_red "the script's marker is reworded in the emitter only (the SQL would watch a row nobody emits)" FLIP \
    's = s.replace("SOLEUR_INNGEST_LUKS_KEY_PROBE ${row}", "SOLEUR_INNGEST_LUKS_KEY_PROBX ${row}")'
  mutate_red "the script renames a paging token away from the fail_ prefix" FLIP \
    's = s.replace("luks_probe_finish fail_header 1 uuid", "luks_probe_finish bad_header 1 uuid")'
  # #11388 declared-set census (widened stem): a sibling whose name only STARTS with the stem escaped the old
  # `inngest_luks_key_probe_` census (probe2), as did the bare stem and a header with a trailing comment.
  mutate_red "a second pair named inngest_luks_key_probe2_fail joins the .tf (the old census stem missed it)" TF \
    's = s + "\nresource \"logtail_exploration\" \"inngest_luks_key_probe2_fail\" {\n}\n\nresource \"logtail_exploration_alert\" \"inngest_luks_key_probe2_fail\" {\n}\n"'
  mutate_red "a pair named by the bare stem inngest_luks_key_probe joins the .tf after the compliant first" TF \
    's = s + "\nresource \"logtail_exploration\" \"inngest_luks_key_probe\" {\n}\n\nresource \"logtail_exploration_alert\" \"inngest_luks_key_probe\" {\n}\n"'
  mutate_red "the paging alert check_period widens from 300 to 3600" TF \
    's = edit(s, FAILAL, "check_period        = 300", "check_period        = 3600")'
  mutate_red "a probe2 header with a trailing comment after the opening brace (the census sed was anchored on the brace)" TF \
    's = s + "\nresource \"logtail_exploration\" \"inngest_luks_key_probe2_fail\" { # trailing comment\n}\n"'
  # #11483 review: the census is MARKER-based, so a pair that merely READS the marker is caught whatever it is named.
  mutate_red "an exploration NOT named after the stem reads the marker through the key-probe SQL local (the stem census missed it)" TF \
    's = s + "\nresource \"logtail_exploration\" \"zz_other_pair\" {\n  sql_query = replace(trimspace(local.inngest_luks_key_probe_fail_sql), \"/\\\\s+/\", \" \")\n}\n"' \
    "add it to KEY_PROBE_EXPLORATIONS in this PR"
  mutate_red "an alert NOT named after the stem binds the key-probe exploration (a second page on the same SQL)" TF \
    's = s + "\nresource \"logtail_exploration_alert\" \"zz_other_alert\" {\n  exploration_id = logtail_exploration.inngest_luks_key_probe_fail.id\n}\n"' \
    "add it to KEY_PROBE_EXPLORATIONS in this PR"
  mutate_red "an exploration names the marker inline in a string (no local involved)" TF \
    's = s + "\nresource \"logtail_exploration\" \"zz_inline\" {\n  sql_query = \"SELECT 1 WHERE position(raw, SOLEUR_INNGEST_LUKS_KEY_PROBE) = 1\"\n}\n"' \
    "add it to KEY_PROBE_EXPLORATIONS in this PR"
  mutate_red "an INDENTED stem header (leading whitespace does not hide it from the census)" TF \
    's = s + "\n  resource \"logtail_exploration\" \"inngest_luks_key_probe2_fail\" {\n  }\n"' \
    "add it to KEY_PROBE_EXPLORATIONS in this PR"
  mutate_red "the declared key-probe pair is renamed away from KEY_PROBE_EXPLORATIONS (the constant no longer matches the .tf)" TF \
    's = s.replace("\"inngest_luks_key_probe_fail\" {", "\"inngest_luks_key_probe_failx\" {")' \
    "add it to KEY_PROBE_EXPLORATIONS in this PR"
  mutate_floor_red "DISPATCH: PRESENCE_ROWS raised by one trips the assertion floor"
  mutate_green "the declared set is still the one pair; only a comment above the paging alert is reworded" TF \
    's = s.replace("# Presence-only, so safe before the probe is delivered", "# Presence-only (reworded), so safe before the probe is delivered")'
  # #11483 review round 1 (census): each branch of the awk gets a row. The repro for a branch the old awk got WRONG is a
  # must-PASS (a stale local was marked) or a mutation it MISSED (hyphenated name, renamed prefix, a chain, a second file).
  mutate_green "a heredoc that is NOT a local's body (base64encode(<<-EOT) names the marker: the previous local must not inherit it)" TF \
    's = s + "\nlocals {\n  zz_plain = <<-EOT\n    plain\n  EOT\n  zz_wrapped = base64encode(<<-EOT\n    SOLEUR_INNGEST_LUKS_KEY_PROBE\n  EOT\n  )\n}\nresource \"logtail_exploration\" \"zz_use\" {\n  sql_query = local.zz_plain\n}\n"'
  mutate_red "an exploration reads the marker through a HYPHENATED local name (the old name class stopped at underscore)" TF \
    's = s + "\nlocals {\n  zz-hy = <<-SQL\n    SOLEUR_INNGEST_LUKS_KEY_PROBE\n  SQL\n}\nresource \"logtail_exploration\" \"zz_hy\" {\n  sql_query = local.zz-hy\n}\n"' \
    "add it to KEY_PROBE_EXPLORATIONS in this PR"
  mutate_red "an exploration names a marker with a RENAMED prefix (SOLEUR_RENAMED_LUKS_KEY_PROBE: the census keys on LUKS_KEY_PROBE)" TF \
    's = s + "\nresource \"logtail_exploration\" \"zz_sub\" {\n  sql_query = \"SELECT 1 WHERE position(raw, SOLEUR_RENAMED_LUKS_KEY_PROBE) = 1\"\n}\n"' \
    "add it to KEY_PROBE_EXPLORATIONS in this PR"
  mutate_red "an exploration reads the marker through a local that WRAPS the key-probe local (transitive carry)" TF \
    's = s + "\nlocals {\n  zz_wrap = replace(trimspace(local.inngest_luks_key_probe_fail_sql), \"x\", \"y\")\n}\nresource \"logtail_exploration\" \"zz_tr\" {\n  sql_query = local.zz_wrap\n}\n"' \
    "add it to KEY_PROBE_EXPLORATIONS in this PR"
  mutate_red "a SECOND root *.tf declares an exploration that reads the key-probe local (the census scans every root file)" TF \
    'import os
open(os.path.join(os.path.dirname(p), "zz_second.tf"), "w").write("resource \"logtail_exploration\" \"zz_second\" {\n  sql_query = local.inngest_luks_key_probe_fail_sql\n}\n")
s = s + "\n# second-file row\n"' \
    "add it to KEY_PROBE_EXPLORATIONS in this PR"
  # Scorer NEGATIVE CONTROL: the mutant reds ONLY the runbook-anchor row, so a fragment naming the paging SQL must grade it WRONG.
  mutate_red "scorer control: a mutant that reds only the runbook-anchor row, scored against a paging-SQL fragment" TF \
    's = s.replace("#key-continuity-probe-9927-item-2", "#key-continuity-probe-9927-item-2x")' \
    "paging SQL differs" wrong
  mutate_red "the dead-man is smuggled back: a dark SQL local joins the .tf" TF \
    'old = "  inngest_luks_key_probe_runbook_url ="
assert s.count(old) == 1
s = s.replace(old, "  inngest_luks_key_probe_dark_sql = <<-SQL\n    SELECT 1\n  SQL\n" + old)'
  # #11527 emitter-pin rows — the row set is pinned to the probe's two emitters. Each mutation
  # must redden the presence row that pins it, never just move dead text.
  mutate_red "the leg-A emitter conjunct is dropped (any journald emitter's marker row counts)" TF \
    'import os
tag = os.environ["MUT_TAG"]
old = "        JSONExtractString(raw, \x27SYSLOG_IDENTIFIER\x27) = \x27" + tag + "\x27\n"
assert s.count(old) == 1
s = s.replace(old, "")'
  mutate_red "the leg-A emitter literal flips to doppler (the marker-quoting offender becomes the counted set)" TF \
    'import os
tag = os.environ["MUT_TAG"]
old = "JSONExtractString(raw, \x27SYSLOG_IDENTIFIER\x27) = \x27" + tag + "\x27"
assert s.count(old) == 1
s = s.replace(old, "JSONExtractString(raw, \x27SYSLOG_IDENTIFIER\x27) = \x27doppler\x27")'
  mutate_red "the leg-B shipper conjunct is dropped (any stage of phone-home row counts)" TF \
    'import os
shipper = os.environ["MUT_SHIPPER"]
s = edit(s, FAILSQL, "          JSONExtractString(raw, "+Q+"shipper"+Q+") = "+Q+"" + shipper + Q+"\n", "", SQLEND)'
  mutate_red "the leg-B stage conjunct is dropped (every phone-home row counts)" TF \
    'import os
stage = os.environ["MUT_STAGE"]
old = "          AND JSONExtractString(raw, \x27stage\x27) = \x27" + stage + "\x27\n"
assert s.count(old) == 1
s = s.replace(old, "")'
  mutate_red "the leg-B stage literal flips to a foreign stage" TF \
    'import os
stage = os.environ["MUT_STAGE"]
old = "JSONExtractString(raw, \x27stage\x27) = \x27" + stage + "\x27"
assert s.count(old) == 1
s = s.replace(old, "JSONExtractString(raw, \x27stage\x27) = \x27cutover-flip-other\x27")'
  mutate_red "the whole OR arm is deleted (the #11527 regression — legs collapse to journald-only)" TF \
    'import os
shipper = os.environ["MUT_SHIPPER"]
stage = os.environ["MUT_STAGE"]
old = ("        OR (\n"
       "          JSONExtractString(raw, \x27shipper\x27) = \x27" + shipper + "\x27\n"
       "          AND JSONExtractString(raw, \x27stage\x27) = \x27" + stage + "\x27\n"
       "          AND (\n"
       "            JSONExtractString(raw, \x27detail\x27) = \x27\x27\n"
       "            OR position(JSONExtractString(raw, \x27detail\x27), \x27token=fail_\x27) > 0\n"
       "          )\n"
       "        )\n")
assert s.count(old) == 1
s = s.replace(old, "")'
  mutate_red "the detail='' fail-loud disjunct is neutralized (detail-absent rows go quiet again)" TF \
    's = edit(s, FAILSQL, "JSONExtractString(raw, "+Q+"detail"+Q+") = "+Q+Q, "false", SQLEND)'
fi

# PRESENCE_ROWS is exactly the count of presence rows an inner (MUT_SKIP) run asserts; the outer run
# adds one row per mutation. The instrument control above is what catches a floor that drifts past
# the presence rows (that control, not this comment, is the guard against a dead battery).
PRESENCE_ROWS=36
MUT_ROWS=37
_floor=$((PRESENCE_ROWS + MUT_ROWS))
[ -n "${MUT_SKIP:-}" ] && _floor=$PRESENCE_ROWS
_ran=$((pass + fail))
if [ "$_ran" -lt "$_floor" ]; then printf '[FATAL] assertion floor: %s ran, floor %s\n' "$_ran" "$_floor" >&2; exit 1; fi
if [ "${#FAILED[@]}" -ne "$fail" ]; then printf '[FATAL] ledger %s != fail counter %s\n' "${#FAILED[@]}" "$fail" >&2; exit 1; fi
printf '\n=== inngest-luks-key-probe-alert: %s passed, %s failed (%s assertions, floor %s) ===\n' "$pass" "$fail" "$_ran" "$_floor"
[ "$fail" -eq 0 ]
