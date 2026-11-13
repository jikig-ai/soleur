#!/usr/bin/env bash
#
# Drift guard for the "#10538 serving dedicated Inngest host owns no functions" Better Stack Logs
# alert (apps/web-platform/infra/betterstack-logs-alerts.tf, `inngest_registry_empty`). Guard 3 of
# the 2026-11-13 origin-TLS cleanup and Inngest public-poll plan; modelled on
# inngest-luks-wrong-volume-alert.test.sh (same conventions: canonical equality, block-scoped
# parameters, derived needles, scratch-copy mutation rows).
#
# WHAT THE ALERT IS FOR. After #10538 remedy (c) the dedicated host polls the PUBLIC serve URL
# (https://app.soleur.ai/api/inngest). A broken public poll otherwise degrades silently: the server
# answers /health and owns nothing. The alert fires exactly on dedicated probe rows that are serving
# (server_active=active, http_code=200), past the uptime floor (uptime_s > 900), and whose
# `registry_fns` is not a positive integer, from the probe's own emitter (leg A) or its vector-down
# phone-home fallback (leg B), and it is applied at merge (both -target lines).
#
# WHAT THIS FILE PROVES:
#   * CANONICAL EQUALITY. The `inngest_registry_empty_sql` heredoc is extracted, whitespace-stripped,
#     and compared byte-for-byte against REGEMPTY_CANON, built from DERIVED literals: the emitter tag
#     and marker from scripts/lib/inngest-probe-row.sh, the leg-B stage from the phone-home call site
#     in inngest-bootstrap.sh, the shipper from cloud-init-inngest.yml's payload builder, and the five
#     FIELD KEYS (host_role, server_active, http_code, uptime_s, registry_fns) from the probe's own
#     `logger` emit line. A field renamed in the emitter only reds the canon (derived-needle row).
#   * NON-EMPTY EXTRACTION FLOOR. A renamed local extracts nothing; the first row reds, and the
#     canon row cannot pass on an empty body.
#   * NO VOLUME REFERENCE (ADR-282). Neither the SQL nor either resource block may name
#     `local.inngest_luks_wrong_volume_alias` or any `hcloud_volume` address: a copied wrong-volume
#     leg would give every merge apply a second path to the sole-copy LUKS volume (the G2e rows of
#     terraform-target-parity.test.ts).
#   * NO `detail = ''` DISJUNCT (ruling F1): a fieldless row belongs to the probe heartbeat.
#   * BLOCK-SCOPED PARAMETERS, exactly once, anchored at both ends; the -target pair; the runbook
#     anchor and its heading; the .tf-wide pair census.
#
# WHAT THIS FILE DOES NOT PROVE: that the alert parses or is armed in production. The live counts
# recorded in the .tf comment (predicate 0, positive control > 0) are the parse proof; the scheduled
# drift plan compares the applied resource with the file.
#
# Mutation rows live at the bottom. Each one COPIES a source file into a scratch dir, mutates the
# COPY, and re-runs this guard against the copy through the REGEMPTY_GUARD_{TF,WF,BOOT} overrides.
# No tracked file is ever written (an in-place mutation under a restoring trap strands mutations
# under concurrent runs, measured on the sibling guard).
set -uo pipefail
export TMPDIR="${TMPDIR:-/var/tmp}"

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$DIR/../../../.." && pwd)"
TF="${REGEMPTY_GUARD_TF:-$REPO/apps/web-platform/infra/betterstack-logs-alerts.tf}"
WF="${REGEMPTY_GUARD_WF:-$REPO/.github/workflows/apply-web-platform-infra.yml}"
BOOT="${REGEMPTY_GUARD_BOOT:-$REPO/apps/web-platform/infra/inngest-bootstrap.sh}"
# NOT overridable: their literals are derived or read-only context.
CI="$REPO/apps/web-platform/infra/cloud-init-inngest.yml"
RB="$REPO/knowledge-base/engineering/operations/runbooks/inngest-server.md"
VT="$REPO/apps/web-platform/infra/vector.toml"
LIB="$REPO/scripts/lib/inngest-probe-row.sh"

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
assert_fixture_dir "$TF"; assert_fixture_dir "$WF"; assert_fixture_dir "$BOOT"; assert_fixture_dir "$CI"; assert_fixture_dir "$RB"; assert_fixture_dir "$VT"; assert_fixture_dir "$LIB"

# INSTRUMENT SELF-TEST — both helpers must move their own counter before any verdict is trusted.
_p0=$pass; _f0=$fail
{ ok "self-test"; no "self-test"; } >/dev/null
if [ "$pass" -ne $((_p0 + 1)) ] || [ "$fail" -ne $((_f0 + 1)) ] || [ "${#FAILED[@]}" -ne 1 ]; then
  printf '[FATAL] instrument self-test: ok()/no() did not each move their counter\n' >&2; exit 2
fi
pass=$_p0; fail=$_f0; FAILED=()

for f in "$TF" "$WF" "$BOOT" "$CI" "$RB" "$VT" "$LIB"; do
  [ -r "$f" ] || { printf '[FATAL] unreadable: %s\n' "$f" >&2; exit 2; }
done

NAME='inngest_registry_empty'
REGEMPTY_EXPLORATIONS='inngest_registry_empty'
REGEMPTY_STEM='inngest_registry_empty'
RUNBOOK_HEADING='## Registry-empty alert (#10538)'
RUNBOOK_URL='https://github.com/jikig-ai/soleur/blob/main/knowledge-base/engineering/operations/runbooks/inngest-server.md#registry-empty-alert-10538'

# ── derived needles: never re-pinned. Each extraction is FATAL-on-empty. ─────────────────────
unset INNGEST_PROBE_ROW_JQ INNGEST_PROBE_EMITTER INNGEST_PROBE_MARKER
# shellcheck source=scripts/lib/inngest-probe-row.sh
source "$LIB" || { printf '[FATAL] cannot source scripts/lib/inngest-probe-row.sh — the emitter needle has no canonical source\n' >&2; exit 2; }
export MUT_EMITTER="$INNGEST_PROBE_EMITTER"
[ -n "$MUT_EMITTER" ] && [ -n "${INNGEST_PROBE_MARKER:-}" ] \
  || { printf '[FATAL] the canonical lib yielded an empty emitter or marker\n' >&2; exit 2; }

export MUT_STAGE
MUT_STAGE="$(sed -n 's/^[^#]*inngest-boot-phone-home\.sh[[:space:]]\+\(inngest-server-probe-[A-Za-z0-9_-]*\).*/\1/p' "$BOOT" | head -1)"
[ -n "$MUT_STAGE" ] || { printf '[FATAL] no inngest-server-probe-* call site on inngest-boot-phone-home.sh in inngest-bootstrap.sh — the stage needle has no canonical source\n' >&2; exit 2; }

export MUT_SHIPPER
MUT_SHIPPER="$(sed -n 's/^[^#]*shipper:"\([^"]*\)".*/\1/p' "$CI" | head -1)"
[ -n "$MUT_SHIPPER" ] || { printf '[FATAL] no shipper literal in the cloud-init-inngest.yml payload builder — the shipper needle has no canonical source\n' >&2; exit 2; }

# The probe's own emit line (the uncommented `logger -t "$LOG_TAG" "<marker> …"` line) and its
# phone-home twin (the uncommented call that passes MUT_STAGE). Field KEYS are read off the emit
# line by the shell variable each one carries, so a key renamed in the emitter yields the NEW key
# and reddens the canon rather than leaving a stale needle green.
EMIT_LINE="$(grep -E "^[[:space:]]*logger -t \"\\\$LOG_TAG\" \"${INNGEST_PROBE_MARKER} " "$BOOT" | head -1)"
[ -n "$EMIT_LINE" ] || { printf '[FATAL] no logger emit line for %s in inngest-bootstrap.sh — the field keys have no canonical source\n' "$INNGEST_PROBE_MARKER" >&2; exit 2; }
PH_LINE="$(grep -E "^[^#]*inngest-boot-phone-home\\.sh[[:space:]]+${MUT_STAGE}[[:space:]]" "$BOOT" | head -1)"
[ -n "$PH_LINE" ] || { printf '[FATAL] no phone-home call line for stage %s\n' "$MUT_STAGE" >&2; exit 2; }
field_key() {  # field_key <shell-var> -> the key emitted as ` <key>=$<var> ` on EMIT_LINE
  printf '%s\n' "$EMIT_LINE" | grep -oE "[[:space:]][A-Za-z_]+=\\\$$1[[:space:]\"]" | head -1 \
    | sed -e 's/^[[:space:]]//' -e 's/=.*$//'
}
K_ROLE="$(field_key host_role)"; K_SA="$(field_key server_active)"; K_HC="$(field_key http_code)"
K_UP="$(field_key uptime_s)"; K_REG="$(field_key registry_fns)"
for _k in K_ROLE K_SA K_HC K_UP K_REG; do
  [ -n "${!_k}" ] || { printf '[FATAL] field key %s not derivable from the probe emit line\n' "$_k" >&2; exit 2; }
done

# The SQL heredoc local, raw and whitespace-stripped. The collapsed form (every whitespace run to
# ONE space) is what the named-property rows read: it keeps the load-bearing trailing space inside
# 'host_role=dedicated ' and is indifferent to line wrapping (the resource collapses whitespace).
sql_local_raw() {  # sql_local_raw <local-name> -> heredoc body as written
  awk -v n="$1" '$0 ~ "^[[:space:]]*" n "[[:space:]]*=[[:space:]]*<<-SQL" {f=1; next} f && /^  SQL$/ {f=0} f' "$TF"
}
res_block() {  # res_block <type> <name>
  awk -v t="$1" -v n="$2" 'index($0, "resource \"" t "\" \"" n "\" {") == 1 {f=1} f {print} f && /^}/ {exit}' "$TF"
}
param() {  # param <block> <key> <value-ERE>
  local n
  n="$(grep -cE "^[[:space:]]*$2[[:space:]]*=[[:space:]]*$3[[:space:]]*(#.*)?$" <<< "$1")"
  [ "$n" -eq 1 ]
}

LOCAL_SQL="$(sql_local_raw "${NAME}_sql")"
RG_SQL="$(printf '%s' "$LOCAL_SQL" | tr -d '[:space:]')"
RG_COL="$(printf '%s' "$LOCAL_SQL" | tr -s '[:space:]' ' ')"

# The canon, per leg, from the derived literals. `field_conj <col>` is the five serving / floor /
# negated-registry conjuncts on one column (message on leg A, detail on leg B).
field_conj() {
  printf "ANDposition(JSONExtractString(raw,'%s'),'%s=dedicated')>0" "$1" "$K_ROLE"
  printf "ANDposition(JSONExtractString(raw,'%s'),'%s=active')>0" "$1" "$K_SA"
  printf "ANDposition(JSONExtractString(raw,'%s'),'%s=200')>0" "$1" "$K_HC"
  printf "ANDtoUInt64OrZero(extract(JSONExtractString(raw,'%s'),'%s=([0-9]+)'))>900" "$1" "$K_UP"
  printf "ANDNOTmatch(JSONExtractString(raw,'%s'),'%s=[1-9][0-9]*')" "$1" "$K_REG"
}
LEG_A="JSONExtractString(raw,'SYSLOG_IDENTIFIER')='${MUT_EMITTER}'ANDposition(JSONExtractString(raw,'message'),'${INNGEST_PROBE_MARKER}')=1$(field_conj message)"
LEG_B_FIELDS="$(field_conj detail)"
LEG_B="JSONExtractString(raw,'shipper')='${MUT_SHIPPER}'ANDJSONExtractString(raw,'stage')='${MUT_STAGE}'${LEG_B_FIELDS}"
REGEMPTY_CANON="SELECT{{time}}AStime,count(*)ASvalueFROM{{source}}WHEREtimeBETWEEN{{start_time}}AND{{end_time}}AND(${LEG_A}OR(${LEG_B}))GROUPBYtime"

# ── presence rows: extraction floor, canonical equality, the decoy-opener count ──────────────
[ -n "$LOCAL_SQL" ] && [ "${#RG_SQL}" -gt 200 ] \
  && ok "the predicate local is a non-empty heredoc this guard can read (extraction floor)" \
  || no "inngest_registry_empty_sql: heredoc not found or empty — every row below would be vacuous"

[ -n "$RG_SQL" ] && [ "$RG_SQL" = "$REGEMPTY_CANON" ] \
  && ok "the predicate is exactly the ruled form (whitespace-insensitive canonical equality, derived needles)" \
  || no "the predicate differs from the ruled form: ${RG_SQL:-<empty>}"

_sql_openers="$(grep -cE 'inngest_registry_empty_sql[[:space:]]*=[[:space:]]*<<-SQL' "$TF" || true)"
[ "$_sql_openers" = "1" ] \
  && ok "exactly one inngest_registry_empty_sql heredoc opener in the file (no decoy heredoc)" \
  || no "inngest_registry_empty_sql opener count=${_sql_openers} (want exactly one) — a decoy heredoc can feed extraction dead text"

# ── presence rows: named properties on the COLLAPSED extraction (clarity + intra-literal space) ─
has() { [ -n "$RG_COL" ] && grep -cF -- "$1" <<< "$RG_COL" >/dev/null; }
has "JSONExtractString(raw, 'SYSLOG_IDENTIFIER') = '${MUT_EMITTER}'" \
  && ok "leg A is scoped to the probe's own emitter (derived from INNGEST_PROBE_EMITTER)" \
  || no "the emitter conjunct is missing or pinned to a stale literal: marker-quoting rows would count (#8874)"
has "position(JSONExtractString(raw, 'message'), '${INNGEST_PROBE_MARKER}') = 1" \
  && ok "leg A is scoped to the probe marker, anchored at message position 1" \
  || no "the marker scope is missing or unanchored"
for _col in message detail; do
  _leg=A; [ "$_col" = detail ] && _leg=B
  has "position(JSONExtractString(raw, '${_col}'), '${K_ROLE}=dedicated ') > 0" \
    && ok "leg ${_leg} scopes ${K_ROLE}=dedicated (space-terminated) on ${_col}" \
    || no "leg ${_leg}: no space-terminated ${K_ROLE}=dedicated scope on ${_col} — web rows would drive this alert"
  has "position(JSONExtractString(raw, '${_col}'), '${K_SA}=active ') > 0" \
    && has "position(JSONExtractString(raw, '${_col}'), '${K_HC}=200 ') > 0" \
    && ok "leg ${_leg} requires a SERVING row (${K_SA}=active and ${K_HC}=200, space-terminated) on ${_col}" \
    || no "leg ${_leg}: the serving scope (${K_SA}=active, ${K_HC}=200) is missing on ${_col} — not-serving rows belong to the heartbeat"
  has "toUInt64OrZero(extract(JSONExtractString(raw, '${_col}'), '${K_UP}=([0-9]+) ')) > 900" \
    && ok "leg ${_leg} carries the uptime floor (${K_UP} > 900) on ${_col}" \
    || no "leg ${_leg}: the uptime floor is missing on ${_col} — the first probe after a replace would page"
  has "AND NOT match(JSONExtractString(raw, '${_col}'), '${K_REG}=[1-9][0-9]* ')" \
    && ok "leg ${_leg} NEGATES the positive-integer test on ${_col}: a missing, renamed, 0 or __UNREADABLE__ field FIRES" \
    || no "leg ${_leg}: the ${K_REG} test on ${_col} is not a negated positive-integer match — the rule would go quiet on a dropped field"
done
has "JSONExtractString(raw, 'shipper') = '${MUT_SHIPPER}'" \
  && has "JSONExtractString(raw, 'stage') = '${MUT_STAGE}'" \
  && ok "leg B pins shipper='${MUT_SHIPPER}' and stage='${MUT_STAGE}' (derived from the payload builder and the emit site)" \
  || no "leg B's shipper/stage identity is missing or pinned to a stale literal — the vector-down fallback is invisible"

_stage_sites="$(grep -chE "^[^#]*inngest-boot-phone-home\.sh[^[:space:]]*[[:space:]]+[\"']?${MUT_STAGE}[\"']?([[:space:]]|\$)" "$BOOT" "$CI" 2>/dev/null | awk '{s+=$1} END{print s+0}')"
[ "$_stage_sites" = "1" ] \
  && ok "exactly one emit site passes the stage literal to inngest-boot-phone-home.sh — the token is reserved" \
  || no "stage-literal emit-site count=${_stage_sites} (want 1) — a second emitter collides on leg-B identity"

# The phone-home detail must carry the same `key=$var ` tokens leg B reads, or leg B is dead text.
_ph_miss=""
for _pair in "$K_ROLE:host_role" "$K_SA:server_active" "$K_HC:http_code" "$K_UP:uptime_s" "$K_REG:registry_fns"; do
  grep -qE "[[:space:]\"]${_pair%%:*}=\\\$${_pair#*:}[[:space:]\"]" <<< "$PH_LINE" || _ph_miss="$_ph_miss ${_pair%%:*}"
done
[ -z "$_ph_miss" ] \
  && ok "the phone-home fallback detail carries every field key leg B reads (same key=\$var tokens as the emit line)" \
  || no "the phone-home fallback detail lacks field key(s):${_ph_miss} — leg B would read nothing"

grep -qE '(^[[:space:]]*|&&[[:space:]]+)host_role=dedicated[[:space:]]*$' "$BOOT" \
  && ok "the emitter assigns host_role=dedicated on the dedicated arm (the value leg A/B scope on)" \
  || no "inngest-bootstrap.sh no longer assigns host_role=dedicated — the scope value is stale"

# ── negative rows: ruling F1 and ADR-282 ──────────────────────────────────────────────────────
RG_EX="$(res_block logtail_exploration "$NAME")"
RG_AL="$(res_block logtail_exploration_alert "$NAME")"
_runbook_line="$(grep -E '^[[:space:]]*inngest_registry_empty_runbook_url[[:space:]]*=' "$TF" || true)"
if printf '%s\n%s\n%s\n%s\n' "$LOCAL_SQL" "$RG_EX" "$RG_AL" "$_runbook_line" | grep -qE 'inngest_luks_wrong_volume_alias|hcloud_volume'; then
  no "the registry-empty SQL or a resource block references a volume (inngest_luks_wrong_volume_alias / hcloud_volume) — a second apply path to the sole-copy LUKS volume (ADR-282)"
else
  ok "no volume reference in the SQL, the resource blocks or the runbook local (ADR-282: no second apply path to the LUKS volume)"
fi
if has "JSONExtractString(raw, 'detail') = ''"; then
  no "a detail='' disjunct is present — a fieldless row belongs to the probe heartbeat (ruling F1), not this alert"
else
  ok "no detail='' disjunct (ruling F1: fieldless / not-serving rows are the heartbeat's)"
fi

printf '%s' "$RG_SQL" | grep -cF >/dev/null 'WHEREtimeBETWEEN{{start_time}}AND{{end_time}}' \
  && ok "the window filter WHERE time BETWEEN {{start_time}} AND {{end_time}} is present" \
  || no "the WHERE time BETWEEN window is missing or altered"

! grep -qE "replace\\(msg.*(${K_REG}|${K_UP}|${K_HC}|${K_SA}|${K_ROLE}|shipper|stage|${INNGEST_PROBE_MARKER})" "$VT" \
  && ok "the needle keys are absent from vector.toml's scrub rewrites" \
  || no "a needle key now appears in a pii_scrub replace() — the needle is dead before ingest"

# ── presence rows: resources and block-scoped parameters ─────────────────────────────────────
if [ -n "$RG_EX" ] && [ -n "$RG_AL" ]; then
  ok "both resources are declared (one exploration, one alert)"
else
  no "a resource block is missing (ex=${#RG_EX} al=${#RG_AL}) — every parameter row below would be vacuous"
fi
param "$RG_EX" name '"soleur-inngest-registry-empty-prd"' \
  && ok "exploration is named soleur-inngest-registry-empty-prd" \
  || no "exploration name is not soleur-inngest-registry-empty-prd"
param "$RG_EX" source_variable '"source"' && param "$RG_EX" name '"source"' && param "$RG_EX" variable_type '"source"' \
  && ok "exploration binds the {{source}} template variable (source_variable, variable.name, variable_type)" \
  || no "exploration source binding repointed (source_variable / variable.name / variable_type)"
param "$RG_EX" values '\[local\.vector_prd_source_id\]' \
  && ok "exploration reads the shared prd Vector source (values=[local.vector_prd_source_id])" \
  || no "exploration is not bound to local.vector_prd_source_id"
param "$RG_EX" query_type '"sql_expression"' \
  && ok "exploration: query_type is sql_expression" \
  || no "exploration: query_type is not sql_expression"
param "$RG_EX" sql_query "replace\\(trimspace\\(local\\.${NAME}_sql\\), \"/\\\\\\\\s\\+/\", \" \"\\)" \
  && ok "exploration carries THIS predicate local, collapsed to one line (the perpetual-diff rule)" \
  || no "exploration does not carry local.${NAME}_sql as its collapsed sql_query"

param "$RG_AL" exploration_id "logtail_exploration\\.${NAME}\\.id" \
  && ok "alert is bound to THIS exploration" \
  || no "alert exploration_id is not logtail_exploration.${NAME}.id"
param "$RG_AL" name '"soleur-inngest-registry-empty-prd"' \
  && ok "alert is named soleur-inngest-registry-empty-prd" \
  || no "alert name is not soleur-inngest-registry-empty-prd"
param "$RG_AL" alert_type '"threshold"' && param "$RG_AL" operator '"higher_than"' && param "$RG_AL" value 0 \
  && ok "alert is threshold / higher_than / 0 — one matching row pages" \
  || no "alert is not threshold / higher_than / 0 — an operator or value flip is a silent mute"
param "$RG_AL" check_period 300 \
  && ok "alert check_period is exactly 300" \
  || no "alert check_period is not exactly 300"
param "$RG_AL" query_period 900 \
  && ok "alert query_period is exactly 900 (the ceiling for a new logs alert; three checks per hourly row)" \
  || no "alert query_period is not exactly 900"
param "$RG_AL" recovery_period 7200 \
  && ok "alert recovery_period is exactly 7200 (two emissions)" \
  || no "alert recovery_period is not exactly 7200"
param "$RG_AL" confirmation_period 0 && param "$RG_AL" on_missing_data '"treat_as_zero"' \
  && ok "alert: confirmation_period 0, on_missing_data treat_as_zero" \
  || no "alert: confirmation_period is not 0 or on_missing_data is not treat_as_zero"
param "$RG_AL" paused false \
  && ok "alert: paused = false (armed at the apply)" \
  || no "alert: paused is not false"
param "$RG_AL" email true && param "$RG_AL" push true && param "$RG_AL" call false && param "$RG_AL" sms false \
  && ok "alert: email and push on, call and sms off" \
  || no "alert: channels are not email+push on / call+sms off"
grep -qE '^[[:space:]]*escalation_target[[:space:]]*\{' <<< "$RG_AL" \
  && param "$RG_AL" policy_id 'var\.betterstack_paid_tier \? tonumber\(betteruptime_policy\.uptime\[0\]\.id\) : null' \
  && param "$RG_AL" team_name 'var\.betterstack_paid_tier \? null : "Your team"' \
  && ok "alert carries the siblings' paid-tier-gated escalation_target block" \
  || no "alert escalation_target is not the siblings' paid-tier-gated block"
_cause="$(grep -E '^[[:space:]]*incident_cause' <<< "$RG_AL")"
param "$RG_AL" runbook "local\\.${NAME}_runbook_url" \
  && grep -qF "local.${NAME}_runbook_url" <<< "$_cause" \
  && ok "alert points metadata.runbook and incident_cause at the registry-empty runbook local" \
  || no "alert does not point metadata.runbook AND incident_cause at local.${NAME}_runbook_url"
grep -qF 'does NOT detect a stale non-zero registry' <<< "$_cause" \
  && ok "incident_cause states the stale-registry residual (#12742)" \
  || no "incident_cause no longer says it does NOT detect a stale non-zero registry"
if [ "$(printf '%s\n%s\n' "$RG_EX" "$RG_AL" | grep -cE '^[[:space:]]*(count|for_each|lifecycle|ignore_changes)[[:space:]]*[= {]')" -eq 0 ]; then
  ok "no count/for_each/lifecycle/ignore_changes token inside either resource block"
else
  no "a count/for_each/lifecycle/ignore_changes token sits inside a resource block — a silent mute knob"
fi

[ "$(grep -cxE "[[:space:]]*${NAME}_runbook_url[[:space:]]*=[[:space:]]*\"${RUNBOOK_URL//./\\.}\"" "$TF")" = "1" ] \
  && ok "the runbook local is the clickable URL of inngest-server.md#registry-empty-alert-10538, exactly once" \
  || no "${NAME}_runbook_url is not exactly the inngest-server.md#registry-empty-alert-10538 URL"
grep -qxF "$RUNBOOK_HEADING" "$RB" \
  && ok "the runbook carries the '${RUNBOOK_HEADING}' heading behind the alert's anchor" \
  || no "the runbook has no '${RUNBOOK_HEADING}' heading — the alert's runbook link is dead"

# ── presence rows: -target parity with the apply workflow ────────────────────────────────────
_miss=""
for ty in logtail_exploration logtail_exploration_alert; do
  [ "$(grep -cE "^[[:space:]]*-target=$ty\\.$NAME \\\\\$" "$WF")" = "1" ] || _miss="$_miss $ty.$NAME"
done
[ -z "$_miss" ] \
  && ok "both resources have exactly one anchored -target= line in the apply workflow (applied at merge)" \
  || no "missing -target= line(s):$_miss — the resource would never be applied"

# ── presence row: the .tf-wide pair census (copied from the sibling guard) ───────────────────
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
  do {
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
CENSUS="$(awk -v MARK="$REGEMPTY_STEM" "$CENSUS_AWK" "$(dirname "$TF")"/*.tf 2>/dev/null)"
_dexp="$(while IFS='|' read -r _k _n _c _b; do
  [ "$_k" = E ] || continue
  if [ "$_c" = 1 ] || [[ "$_n" == "$REGEMPTY_STEM"* ]]; then printf '%s\n' "$_n"; fi
done <<<"$CENSUS" | sort -u | tr '\n' ' ')"
_dal="$(while IFS='|' read -r _k _n _c _b; do
  [ "$_k" = A ] || continue
  if [ "$_c" = 1 ] || [[ "$_n" == "$REGEMPTY_STEM"* ]] || [[ "$_b" == "$REGEMPTY_STEM"* ]]; then printf '%s\n' "$_n"; fi
done <<<"$CENSUS" | sort -u | tr '\n' ' ')"
_want="$(printf '%s\n' $REGEMPTY_EXPLORATIONS | sort -u | tr '\n' ' ')"
CENSUS_EXTRA_E="$(comm -23 <(printf '%s\n' $_dexp | sort -u) <(printf '%s\n' $_want | sort -u) | tr '\n' ' ')"
CENSUS_EXTRA_A="$(comm -23 <(printf '%s\n' $_dal | sort -u) <(printf '%s\n' $_want | sort -u) | tr '\n' ' ')"
CENSUS_GONE_E="$(comm -13 <(printf '%s\n' $_dexp | sort -u) <(printf '%s\n' $_want | sort -u) | tr '\n' ' ')"
CENSUS_GONE_A="$(comm -13 <(printf '%s\n' $_dal | sort -u) <(printf '%s\n' $_want | sort -u) | tr '\n' ' ')"
if [ -z "$CENSUS_EXTRA_E$CENSUS_EXTRA_A$CENSUS_GONE_E$CENSUS_GONE_A" ] && [ -n "$_want" ]; then
  ok "the .tf declares exactly the REGEMPTY_EXPLORATIONS pair set (${_want% }), by marker and by stem"
else
  no "registry-empty census differs from REGEMPTY_EXPLORATIONS (${_want% }): undeclared exploration(s) [${CENSUS_EXTRA_E% }], undeclared alert(s) [${CENSUS_EXTRA_A% }], missing exploration(s) [${CENSUS_GONE_E% }], missing alert(s) [${CENSUS_GONE_A% }]: add it to REGEMPTY_EXPLORATIONS in this PR"
fi

echo ""
echo "=== inngest-registry-empty-alert guard: $pass passed, $fail failed ==="
if [ "$fail" -gt 0 ]; then
  printf 'FAILED: %s\n' "${FAILED[@]}" >&2
  exit 1
fi

# ── Mutation rows: each must make a row above RED ──────────────────────────────────────────
# OUTER RUN ONLY. Each row copies ONE source file into $MUT_DIR, mutates the copy, and re-runs
# this guard with MUT_SKIP=1 and the matching REGEMPTY_GUARD_* override pointing at the copy.
SELF="$DIR/$(basename "${BASH_SOURCE[0]}")"
if [ -z "${MUT_SKIP:-}" ]; then
  MUT_DIR="$(mktemp -d -t regemptyalert.XXXXXX)" || { printf '[FATAL] mktemp failed\n' >&2; exit 2; }
  assert_fixture_dir "$MUT_DIR"
  trap 'rm -rf "$MUT_DIR"' EXIT

  # INSTRUMENT CONTROL (must-PASS: the real tree) — the inner run against the PRISTINE tree must
  # exit 0, or every row below would grade a broken invocation as "mutation RED".
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
RGSQL = "inngest_registry_empty_sql = <<-SQL"
RGEX = "resource \"logtail_exploration\" \"inngest_registry_empty\" {"
RGAL = "resource \"logtail_exploration_alert\" \"inngest_registry_empty\" {"
SQLEND = "\n  SQL\n"'

  _red_verdict() {  # _red_verdict <rc> <log> <fragment-or-empty>
    case "$1" in
      1) if [ -z "$3" ] || { grep -F '[FAIL]' "$2" | grep -F -- "$3" >/dev/null; }; then echo red; else echo wrong; fi ;;
      0) echo survived ;;
      *) echo unresolved ;;
    esac
  }

  # _mutate <TF|WF|BOOT> <python-program-on-s> -> prints the copy path; rc 1 when the edit did not land
  _mutate() {
    local which="$1" prog="$2" src copy
    rm -f "$MUT_DIR"/zz_*.tf
    case "$which" in
      TF)   src="$TF";   copy="$MUT_DIR/betterstack-logs-alerts.tf" ;;
      WF)   src="$WF";   copy="$MUT_DIR/apply-web-platform-infra.yml" ;;
      BOOT) src="$BOOT"; copy="$MUT_DIR/inngest-bootstrap.sh" ;;
      *) printf '[FATAL] _mutate: unknown target %s\n' "$which" >&2; exit 2 ;;
    esac
    cp "$src" "$copy" || { printf '[FATAL] _mutate: cp %s failed\n' "$src" >&2; exit 2; }
    python3 - "$copy" >/dev/null 2>&1 <<PY || return 1
import sys
p = sys.argv[1]
$PRELUDE
orig = open(p, encoding="utf-8").read()
s = orig
$prog
assert s != orig, "mutation produced no change"
open(p, 'w', encoding="utf-8").write(s)
PY
    printf '%s' "$copy"
  }
  _inner() {  # _inner <TF|WF|BOOT> <copy> <log> -> the inner rc
    local rc=0
    case "$1" in
      TF)   REGEMPTY_GUARD_TF="$2"   MUT_SKIP=1 bash "$SELF" >"$3" 2>&1 || rc=$? ;;
      WF)   REGEMPTY_GUARD_WF="$2"   MUT_SKIP=1 bash "$SELF" >"$3" 2>&1 || rc=$? ;;
      BOOT) REGEMPTY_GUARD_BOOT="$2" MUT_SKIP=1 bash "$SELF" >"$3" 2>&1 || rc=$? ;;
    esac
    printf '%s' "$rc"
  }

  mutate_red() {  # mutate_red <label> <TF|WF|BOOT> <python-program-on-s> [expected [FAIL] fragment]
    local label="$1" which="$2" prog="$3" tag="${4:-}" copy rc olog="$MUT_DIR/inner.log"
    copy="$(_mutate "$which" "$prog")" || { no "mutation '$label' did not land (anchor drifted)"; return 0; }
    rc="$(_inner "$which" "$copy" "$olog")"
    case "$(_red_verdict "$rc" "$olog" "$tag")" in
      red) ok "mutation RED: $label" ;;
      wrong) no "mutation went red for the WRONG reason (no [FAIL] line contains '$tag'): $label" ;;
      survived) no "mutation SURVIVED: $label — the rows above pin nothing" ;;
      *) no "mutation UNRESOLVED (inner rc=$rc, not an assertion): $label — instrument, not evidence" ;;
    esac
  }
  mutate_green() {  # mutate_green <label> <TF> <python-program-on-s>
    local label="$1" which="$2" prog="$3" copy rc
    copy="$(_mutate "$which" "$prog")" || { no "must-PASS '$label' did not land (anchor drifted)"; return 0; }
    rc="$(_inner "$which" "$copy" "$MUT_DIR/green.log")"
    case "$rc" in
      0) ok "must-PASS stays green: $label" ;;
      1) no "legitimate edit went RED: $label" ;;
      *) no "must-PASS UNRESOLVED (inner rc=$rc): $label — instrument, not evidence" ;;
    esac
  }
  # A HARNESS row: a copy of THIS suite with one line rewritten (sed program) must exit 1. The
  # copy's REPO line is rewritten to the real repo so its reads resolve.
  mutate_self_red() {  # mutate_self_red <label> <sed-expression>
    local label="$1" expr="$2" copy="$MUT_DIR/self-mutated.test.sh" rc=0
    sed -e "$expr" -e "s|^REPO=.*|REPO=\"$REPO\"|" "$SELF" > "$copy"
    if [ "$(grep -cvxFf "$SELF" "$copy")" -lt 2 ]; then no "harness mutation '$label' did not land (anchor drifted)"; return 0; fi
    MUT_SKIP=1 bash "$copy" >/dev/null 2>&1 || rc=$?
    case "$rc" in
      1) ok "harness mutation RED: $label" ;;
      0) no "harness mutation SURVIVED: $label" ;;
      *) no "harness mutation UNRESOLVED (inner rc=$rc): $label — instrument, not evidence" ;;
    esac
  }

  # ── Guard 3 mutation matrix ─────────────────────────────────────────────────────────────
  # 1. the negation is dropped on leg A
  mutate_red "1: leg A's negation is dropped (match un-negated: pages on a HEALTHY registry)" TF \
    's = edit(s, RGSQL, "AND NOT match(JSONExtractString(raw, "+Q+"message"+Q+")", "AND match(JSONExtractString(raw, "+Q+"message"+Q+")", SQLEND)' \
    "ruled form"
  # 2. the emitter conjunct is dropped
  mutate_red "2: the SYSLOG_IDENTIFIER emitter conjunct is dropped (quoting rows count again)" TF \
    'import os
em = os.environ["MUT_EMITTER"]
s = edit(s, RGSQL, "        JSONExtractString(raw, "+Q+"SYSLOG_IDENTIFIER"+Q+") = "+Q+em+Q+"\n        AND position", "        position", SQLEND)' \
    "ruled form"
  # 3. leg B is dropped after a compliant leg A
  mutate_red "3: leg B (the phone-home OR arm) is deleted after a compliant leg A" TF \
    'i = s.index(RGSQL); j = s.index(SQLEND, i)
region = s[i:j]
a = region.index("        OR (\n"); b = region.index("\n        )\n", a) + len("\n        )\n")
s = s[:i] + region[:a] + region[b:] + s[j:]' \
    "ruled form"
  # 4. one of the two -target lines is removed (the second, after the compliant first)
  mutate_red "4: the alert's -target= line is removed while the exploration's stays" WF \
    'old = "              -target=logtail_exploration_alert.inngest_registry_empty \\\n"
assert s.count(old) == 1
s = s.replace(old, "")' \
    "-target="
  # 5. dispatch: the local is renamed, so the guard extracts no SQL
  mutate_red "5: DISPATCH: the SQL local is renamed (the guard extracts nothing; the extraction floor reds)" TF \
    'old = "  inngest_registry_empty_sql = <<-SQL\n"
assert s.count(old) == 1
s = s.replace(old, "  inngest_registry_emptied_sql = <<-SQL\n")' \
    "heredoc not found or empty"
  # 6. the emitter renames its registry_fns= field (and its phone-home twin); the .tf is untouched
  mutate_red "6: the probe renames registry_fns= in the EMITTER only (derived needle: the canon follows the source)" BOOT \
    'import re
n = 0
for old in ("registry_fns=$registry_fns data_luks", ):
    n = s.count(old)
assert n == 2, "expected the emit line and the phone-home line, got %d" % n
s = s.replace("registry_fns=$registry_fns data_luks", "registry_count=$registry_fns data_luks")' \
    "ruled form"
  # 7. a copied wrong-volume leg brings a volume reference
  mutate_red "7: the SQL gains a reference to local.inngest_luks_wrong_volume_alias (a copied leg; ADR-282)" TF \
    's = edit(s, RGSQL, "        AND position(JSONExtractString(raw, "+Q+"message"+Q+"), "+Q+"host_role=dedicated "+Q+") > 0\n", "        AND position(JSONExtractString(raw, "+Q+"message"+Q+"), "+Q+"host_role=dedicated "+Q+") > 0\n        AND position(JSONExtractString(raw, "+Q+"message"+Q+"), "+Q+"data_mount_devid=${local.inngest_luks_wrong_volume_alias} "+Q+") = 0\n", SQLEND)' \
    "volume"
  mutate_red "7b: the alert block gains an hcloud_volume address (a second apply path to the LUKS volume)" TF \
    's = edit(s, RGAL, "  paused = false\n", "  paused = false\n  # volume: ${hcloud_volume.inngest_redis_luks.id}\n  depends_on = [hcloud_volume.inngest_redis_luks]\n")' \
    "volume"

  # ── extra rows: mute knobs, scope, ruling F1, census ────────────────────────────────────
  mutate_red "the uptime floor is dropped on leg A (the first probe after a replace pages)" TF \
    's = edit(s, RGSQL, "        AND toUInt64OrZero(extract(JSONExtractString(raw, "+Q+"message"+Q+"), "+Q+"uptime_s=([0-9]+) "+Q+")) > 900\n", "", SQLEND)' \
    "uptime floor"
  mutate_red "the serving scope http_code=200 is dropped on leg B" TF \
    's = edit(s, RGSQL, "          AND position(JSONExtractString(raw, "+Q+"detail"+Q+"), "+Q+"http_code=200 "+Q+") > 0\n", "", SQLEND)' \
    "serving scope"
  mutate_red "a detail='' disjunct joins leg B (ruling F1: fieldless rows are the heartbeat's)" TF \
    's = edit(s, RGSQL, "          AND position(JSONExtractString(raw, "+Q+"detail"+Q+"), "+Q+"host_role=dedicated "+Q+") > 0\n", "          AND (JSONExtractString(raw, "+Q+"detail"+Q+") = "+Q+Q+" OR position(JSONExtractString(raw, "+Q+"detail"+Q+"), "+Q+"host_role=dedicated "+Q+") > 0)\n", SQLEND)' \
    "detail="
  mutate_red "the query_period widens 900 -> 1800 (above the new-alert ceiling)" TF \
    's = edit(s, RGAL, "  query_period        = 900\n", "  query_period        = 1800\n")' \
    "query_period"
  mutate_red "push flips to false" TF \
    's = edit(s, RGAL, "  push           = true\n", "  push           = false\n")' \
    "email+push"
  mutate_red "paused flips to true" TF \
    's = edit(s, RGAL, "  paused = false\n", "  paused = true\n")' \
    "paused"
  mutate_red "the threshold value flips 0 -> 999999" TF \
    's = edit(s, RGAL, "  value               = 0\n", "  value               = 999999\n")' \
    "threshold"
  mutate_red "a lifecycle { ignore_changes = [paused] } block joins the alert" TF \
    's = edit(s, RGAL, "  paused = false\n", "  paused = false\n\n  lifecycle {\n    ignore_changes = [paused]\n  }\n")' \
    "ignore_changes"
  mutate_red "the runbook anchor drifts off the section heading" TF \
    'old = "inngest-server.md#registry-empty-alert-10538\""
assert s.count(old) == 1
s = s.replace(old, "inngest-server.md#registry-empty-alert\"")' \
    "runbook_url is not exactly"
  mutate_red "the stale-registry residual is dropped from incident_cause" TF \
    's = edit(s, RGAL, "This alert does NOT detect a stale non-zero registry (#12742 adds that field). ", "")' \
    "stale non-zero registry"
  mutate_red "a second alert inngest_registry_empty_x binds the same exploration (the census must see it)" TF \
    's = s + "\nresource \"logtail_exploration_alert\" \"inngest_registry_empty_x\" {\n  exploration_id = logtail_exploration.inngest_registry_empty.id\n}\n"' \
    "REGEMPTY_EXPLORATIONS"
  mutate_red "a /* */-wrapped decoy heredoc sits before the live local while the live body is gutted" TF \
    'i = s.index("  inngest_registry_empty_sql = <<-SQL\n")
j = s.index("\n  SQL\n", i) + len("\n  SQL\n")
body = s[i:j]
gutted = "  inngest_registry_empty_sql = <<-SQL\n    SELECT 1\n  SQL\n"
s = s[:i] + "  /*\n" + body + "  */\n" + gutted + s[j:]' \
    "opener count"

  # ── harness rows ───────────────────────────────────────────────────────────────────────
  mutate_self_red "the extraction is replaced with an empty string (the floor and canon rows must red)" \
    's|^LOCAL_SQL="$(sql_local_raw "${NAME}_sql")"$|LOCAL_SQL=""|'
  mutate_self_red "DISPATCH: PRESENCE_ROWS raised by one trips the assertion floor" \
    's/^PRESENCE_ROWS=44$/PRESENCE_ROWS=45/'

  # ── must-PASS variants ─────────────────────────────────────────────────────────────────
  mutate_green "the SQL is reformatted across lines (leg A's uptime conjunct wrapped; the resource collapses whitespace)" TF \
    's = edit(s, RGSQL, "        AND toUInt64OrZero(extract(JSONExtractString(raw, "+Q+"message"+Q+"), "+Q+"uptime_s=([0-9]+) "+Q+")) > 900\n", "        AND toUInt64OrZero(extract(JSONExtractString(raw, "+Q+"message"+Q+"),\n            "+Q+"uptime_s=([0-9]+) "+Q+"))\n          > 900\n", SQLEND)'
  mutate_green "a # comment line naming no pinned token is added inside the locals block" TF \
    'old = "  inngest_registry_empty_runbook_url ="
assert s.count(old) == 1
s = s.replace(old, "  # no pinned token on this comment line\n" + old)'
fi

# PRESENCE_ROWS is exactly the count of presence rows an inner (MUT_SKIP) run asserts; the outer
# run adds one row per mutation. The instrument control above catches a floor that drifts past the
# presence rows.
PRESENCE_ROWS=44
MUT_ROWS=24
_floor=$((PRESENCE_ROWS + MUT_ROWS))
[ -n "${MUT_SKIP:-}" ] && _floor=$PRESENCE_ROWS
_ran=$((pass + fail))
if [ "$_ran" -lt "$_floor" ]; then printf '[FATAL] assertion floor: %s ran, floor %s\n' "$_ran" "$_floor" >&2; exit 1; fi
if [ "${#FAILED[@]}" -ne "$fail" ]; then printf '[FATAL] ledger %s != fail counter %s\n' "${#FAILED[@]}" "$fail" >&2; exit 1; fi
[ -n "${MUT_SKIP:-}" ] && printf '[note] MUT_SKIP active — mutation rows skipped (floor %s); REGEMPTY_GUARD_{TF,WF,BOOT}=%s,%s,%s\n' "$_floor" "${REGEMPTY_GUARD_TF:-unset}" "${REGEMPTY_GUARD_WF:-unset}" "${REGEMPTY_GUARD_BOOT:-unset}"
printf '\n=== inngest-registry-empty-alert: %s passed, %s failed (%s assertions, floor %s) ===\n' "$pass" "$fail" "$_ran" "$_floor"
[ "$fail" -eq 0 ]
