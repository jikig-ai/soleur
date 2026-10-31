#!/usr/bin/env bash
#
# Drift guard for the "#6894 store is not on the encrypted volume" Better Stack Logs alert
# (apps/web-platform/infra/betterstack-logs-alerts.tf), rewritten onto the merged sibling
# guard's conventions (#11528; donor: inngest-luks-key-probe-alert.test.sh, PR #11601).
#
# WHAT THE ALERT IS FOR. After the LUKS cutover, the dedicated host's own probe row resolves the
# device backing /mnt/data to a Hetzner by-id alias (`data_mount_devid`, probe_schema=8). If that
# alias is ever NOT the additive volume's, Redis is writing UNENCRYPTED again — and nothing else
# notices, because the scheduler is healthy in exactly those states.
#
# WHAT THIS FILE NOW PROVES (the #11528 hardening, stated so the name is not over-read):
#   * CANONICAL EQUALITY, not presence needles. The `inngest_luks_wrong_volume_sql` heredoc is
#     extracted, whitespace-stripped, and compared BYTE-FOR-BYTE against WRONGVOLUME_CANON, which
#     is built from the derived emitter/stage/shipper/marker literals (never re-pinned). Any
#     conjunct dropped, weakened, re-ordered, `$$`-escaped, tautology-neutralized, commented, or
#     decoy-concatenated breaks equality — dead text cannot satisfy it. A file-wide opener count
#     (exactly one `…_sql = <<-SQL`) kills the /* */-wrapped decoy-heredoc arm that pure
#     first-match extraction would have read as the live body.
#   * BLOCK-SCOPED PARAMETERS. `res_block()` + `param()` pin every alert-significant whole-line attribute inside
#     each resource block, anchored at both ends and required EXACTLY ONCE — a commented copy no
#     longer satisfies the pin, and a `source_variable`/`values`/`FROM {{source}}` repoint reds.
#     The source pins are scoped to the exploration's own block because the same
#     `source_variable = "source"` / `values = [local.vector_prd_source_id]` pair recurs in ~12
#     explorations in this file — a file-wide match would be vacuous.
#   * THE MUTE KNOBS. `paused`, `on_missing_data`, `operator`/`value`, and the window
#     (`check_period`/`query_period`/`recovery_period` exact, not floors) are param-pinned; a
#     negative row rejects `count`/`for_each`/`lifecycle`/`ignore_changes` inside either block —
#     `ignore_changes = [paused]` would decouple the declaration from the provider silently.
#   * THE ARMING PATH. The variables.tf block must have exactly ONE
#     `variable "inngest_luks_cutover_complete"` opener file-wide (an unanchored count, so a
#     `/* */`- or `#`-wrapped decoy opener still counts) AND default to true.
#   * THE PAIR CENSUS. The .tf-wide census (marker/stem-based, every root *.tf) must equal
#     WRONGVOLUME_EXPLORATIONS: a second alert binding the same exploration, a renamed pair, or a
#     foreign-named resource reading the wrong-volume locals all red.
#   * SCRUB IMMUNITY. None of the needle keys (`data_mount_devid`, `host_role`, `shipper`,
#     `stage`, the marker) may appear in vector.toml's pii_scrub `replace(msg` rewrites — the
#     sibling's `verdict` row mirrored; a scrub that eats a needle kills the alert pre-ingest.
#
# WHAT THIS FILE DOES NOT PROVE: that the alert is armed IN PRODUCTION. Armed-ness there is
# decided by the RESOLVED variable — a Doppler `TF_VAR_inngest_luks_cutover_complete` override
# wins silently, and a merge with `[skip-web-platform-apply]` leaves Better Stack on the old
# value. The live detector is the reconciler (plugins/soleur/lib/heartbeat-live-reconcile.ts,
# run twice daily by scheduled-terraform-drift.yml), which since #8296 resolves this variable's
# default and reports a live pause as `logs-alert-paused`. This guard pins the SOURCE; the
# reconciler pins the WORLD. Neither substitutes for the other.
#
# Mutation rows live at the bottom. Each one COPIES a source file into a scratch dir, mutates the
# COPY, and re-runs this guard against the copy through the LUKS_GUARD_{TF,VARS,WF} overrides —
# the ONLY mutable axes. CI-level muting is barred by the sibling suites' infra-validation.yml
# seam checks (registry-clientip-not-rfc1918 et al. red on ANY MUT_SKIP/*_GUARD_* literal in the
# workflow's executable text), a stronger pin than an `env -u` run-line prefix — which those checks
# forbid by construction. inngest-bootstrap.sh, cloud-init-inngest.yml, the runbook, vector.toml and the
# inngest-probe-row lib are deliberately NOT overridable (their literals are derived, so a real
# rename reddens the canon on the next run; there is no scratch-copy mutation axis to subvert).
# No tracked file is ever written. That is a deliberate design, not a convenience: an earlier
# form mutated the tracked files in place under a restoring trap, and review measured that two
# concurrent runs stranded a mutation in 9 of 24 trials.
set -uo pipefail
export TMPDIR="${TMPDIR:-/var/tmp}"

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$DIR/../../../.." && pwd)"
# Overridable so the mutation rows can point an inner run at a mutated COPY. Production values
# are the tracked files; nothing in this file writes to them.
TF="${LUKS_GUARD_TF:-$REPO/apps/web-platform/infra/betterstack-logs-alerts.tf}"
VARS="${LUKS_GUARD_VARS:-$REPO/apps/web-platform/infra/variables.tf}"
WF="${LUKS_GUARD_WF:-$REPO/.github/workflows/apply-web-platform-infra.yml}"
# NOT overridable by design — see the header contract. These resolve from REPO, so the
# floor-mutation scratch copy below rewrites the REPO line rather than adding an env axis.
BOOT="$REPO/apps/web-platform/infra/inngest-bootstrap.sh"
CI="$REPO/apps/web-platform/infra/cloud-init-inngest.yml"
RB="$REPO/knowledge-base/engineering/operations/runbooks/inngest-luks-cutover-6894.md"
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
assert_fixture_dir "$TF"; assert_fixture_dir "$VARS"; assert_fixture_dir "$WF"; assert_fixture_dir "$BOOT"; assert_fixture_dir "$CI"; assert_fixture_dir "$RB"; assert_fixture_dir "$VT"; assert_fixture_dir "$LIB"

# INSTRUMENT SELF-TEST — both helpers must move their own counter before any verdict is trusted.
_p0=$pass; _f0=$fail
{ ok "self-test"; no "self-test"; } >/dev/null
if [ "$pass" -ne $((_p0 + 1)) ] || [ "$fail" -ne $((_f0 + 1)) ] || [ "${#FAILED[@]}" -ne 1 ]; then
  printf '[FATAL] instrument self-test: ok()/no() did not each move their counter\n' >&2; exit 2
fi
pass=$_p0; fail=$_f0; FAILED=()

for f in "$TF" "$VARS" "$WF" "$BOOT" "$CI" "$RB" "$VT" "$LIB"; do
  [ -r "$f" ] || { printf '[FATAL] unreadable: %s\n' "$f" >&2; exit 2; }
done

NAME='inngest_luks_wrong_volume'
# The census below is MARKER-based: every logtail_exploration(_alert) in any root *.tf that
# carries MARK (inline, or through a local whose body carries it), plus every one whose NAME
# starts with the stem, must be listed here. A resource that reads the wrong-volume locals but
# is missing from this list fails the census with "add it to WRONGVOLUME_EXPLORATIONS in this
# PR"; adding a legitimate second pair is that one-line edit, not a rewrite of a count.
WRONGVOLUME_EXPLORATIONS='inngest_luks_wrong_volume'
WRONGVOLUME_STEM='inngest_luks_wrong_volume'

# ── derived needles (#8874/#11526): emitter/stage/shipper literals are never re-pinned. A
# coordinated rename that updates the sources but misses the .tf conjunct must go RED, which
# only happens when the needle follows the source. Each extraction is FATAL-on-empty.
# The emitter + marker literals come from the canonical lib (#8846): the `unset` is the lib's
# documented load contract — an env-inherited name must not silently substitute for a failed
# source.
unset INNGEST_PROBE_ROW_JQ INNGEST_PROBE_EMITTER INNGEST_PROBE_MARKER
# shellcheck source=scripts/lib/inngest-probe-row.sh
source "$LIB" || { printf '[FATAL] cannot source scripts/lib/inngest-probe-row.sh — the emitter needle has no canonical source\n' >&2; exit 2; }
export MUT_EMITTER="$INNGEST_PROBE_EMITTER"

# The leg-B `stage` literal is a CALL-SITE literal with no canonical lib — its authority is the
# `inngest-boot-phone-home.sh <stage>` call form in inngest-bootstrap.sh (#11526). No `#` before
# the helper name, so a comment carrying the bare literal cannot satisfy it, and the bounded
# pattern yields the arg itself — a rename to a superstring (-v2) extracts the NEW literal,
# reddening the .tf needle instead of silently re-pinning a stale one.
export MUT_STAGE
MUT_STAGE="$(sed -n 's/^[^#]*inngest-boot-phone-home\.sh[[:space:]]\+\(inngest-server-probe-[A-Za-z0-9_-]*\).*/\1/p' "$BOOT" | head -1)"
[ -n "$MUT_STAGE" ] || { printf '[FATAL] no inngest-server-probe-* call site on inngest-boot-phone-home.sh in inngest-bootstrap.sh — the stage needle has no canonical source\n' >&2; exit 2; }

# The leg-B `shipper` literal is the payload builder's own — its authority is the jq envelope in
# cloud-init-inngest.yml (`shipper:"…"`), derived the same way so a payload-side rename that
# misses the .tf goes red rather than leaving the needle green on a dead literal.
export MUT_SHIPPER
MUT_SHIPPER="$(sed -n 's/^[^#]*shipper:"\([^"]*\)".*/\1/p' "$CI" | head -1)"
[ -n "$MUT_SHIPPER" ] || { printf '[FATAL] no shipper literal in the cloud-init-inngest.yml payload builder — the shipper needle has no canonical source\n' >&2; exit 2; }

# The SQL heredoc local, extracted from its FIRST UNCOMMENTED-looking opening line to the
# closing `  SQL`. The /* */-decoy arm is NOT closed by first-match extraction alone — the
# exactly-one-opener count row below is what makes a shadow opener red.
sql_local() {  # sql_local <local-name>  -> whitespace-stripped SQL on stdout
  awk -v n="$1" '$0 ~ "^[[:space:]]*" n "[[:space:]]*=[[:space:]]*<<-SQL" {f=1; next} f && /^  SQL$/ {f=0} f' "$TF" \
    | tr -d '[:space:]'
}
# Same extraction WITHOUT the strip — the raw needle rows must see intra-literal whitespace
# (the trailing space inside 'data_mount_devid=<alias> ' and 'host_role=dedicated ' is
# load-bearing; the whitespace-insensitive canon cannot see it drop).
sql_local_raw() {  # sql_local_raw <local-name> -> heredoc body as written
  awk -v n="$1" '$0 ~ "^[[:space:]]*" n "[[:space:]]*=[[:space:]]*<<-SQL" {f=1; next} f && /^  SQL$/ {f=0} f' "$TF"
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

LOCAL_SQL="$(sql_local_raw "${NAME}_sql")"
WV_SQL="$(sql_local "${NAME}_sql")"
# The canon is the whitespace-stripped SQL byte-for-byte, built from the derived literals plus
# the literal `${local.inngest_luks_wrong_volume_alias}` interpolation text (the \$ escape is
# load-bearing — bash would otherwise eat it). Any added, dropped, re-ordered, escaped, or
# tautology-neutralized text breaks equality; the named-property rows below exist only for
# failure-message clarity (this row fails first with the extracted body).
WRONGVOLUME_CANON="SELECT{{time}}AStime,count(*)ASvalueFROM{{source}}WHEREtimeBETWEEN{{start_time}}AND{{end_time}}AND(JSONExtractString(raw,'SYSLOG_IDENTIFIER')='${MUT_EMITTER}'ANDposition(JSONExtractString(raw,'message'),'${INNGEST_PROBE_MARKER}')=1ANDposition(JSONExtractString(raw,'message'),'host_role=dedicated')>0ANDposition(JSONExtractString(raw,'message'),'data_mount_devid=\${local.inngest_luks_wrong_volume_alias}')=0OR(JSONExtractString(raw,'shipper')='${MUT_SHIPPER}'ANDJSONExtractString(raw,'stage')='${MUT_STAGE}'AND(JSONExtractString(raw,'detail')=''OR(position(JSONExtractString(raw,'detail'),'host_role=dedicated')>0ANDposition(JSONExtractString(raw,'detail'),'data_mount_devid=\${local.inngest_luks_wrong_volume_alias}')=0))))GROUPBYtime"

# ── presence rows: the predicate local, canonical equality, and the decoy-opener count ────────
[ -n "$LOCAL_SQL" ] \
  && ok "the predicate local is a heredoc this guard can read" \
  || no "inngest_luks_wrong_volume_sql: heredoc not found — every row below would be vacuous"

[ "$WV_SQL" = "$WRONGVOLUME_CANON" ] \
  && ok "the predicate is exactly the ruled form (whitespace-insensitive canonical equality)" \
  || no "the predicate differs from the ruled form: $WV_SQL"

# Exactly one `…_sql = <<-SQL` opener FILE-WIDE, unanchored so a `/* */`- or `#`-wrapped decoy
# opener still counts: a decoy heredoc placed ahead of the live local would otherwise be read
# by first-match extraction as the live body while the real body is gutted.
_sql_openers="$(grep -cE 'inngest_luks_wrong_volume_sql[[:space:]]*=[[:space:]]*<<-SQL' "$TF" || true)"
[ "$_sql_openers" = "1" ] \
  && ok "exactly one inngest_luks_wrong_volume_sql heredoc opener in the file (no decoy heredoc)" \
  || no "inngest_luks_wrong_volume_sql opener count=${_sql_openers} (want exactly one) — a decoy heredoc can feed extraction dead text"

# The watched alias is built from the RESOURCE id, never a literal: a re-created volume gets a
# new id, and a literal keeps watching the old one — the rule goes quiet, which reads like health.
# Anchored at line start AND required exactly once: a `#`-commented real line next to a literal
# is a miss, and a decoy copy anywhere is a second opener.
_alias_lines="$(grep -cE '^[[:space:]]*inngest_luks_wrong_volume_alias[[:space:]]*=[[:space:]]*"scsi-0HC_Volume_\$\{hcloud_volume\.inngest_redis_luks\.id\}"[[:space:]]*(#.*)?$' "$TF" || true)"
[ "$_alias_lines" = "1" ] \
  && ok "the watched alias is built from hcloud_volume.inngest_redis_luks.id, exactly once (never a literal id, never a decoy line)" \
  || no "the inngest_luks_wrong_volume_alias resource-id line count=${_alias_lines} (want exactly one) — a literal id or a shadow copy would silence the rule"

# ── presence rows: named properties on the RAW extraction (clarity + intra-literal space) ─────
printf '%s' "$LOCAL_SQL" | grep -cF >/dev/null "position(JSONExtractString(raw, 'message'), '${INNGEST_PROBE_MARKER}') = 1" \
  && ok "scoped to the probe marker (derived from INNGEST_PROBE_MARKER), anchored at position 1 (not a substring anywhere in the row)" \
  || no "the marker scope is missing or unanchored"

printf '%s' "$LOCAL_SQL" | grep -cF >/dev/null "JSONExtractString(raw, 'SYSLOG_IDENTIFIER') = '${MUT_EMITTER}'" \
  && ok "scoped to the probe's own emitter (needle derived from INNGEST_PROBE_EMITTER — a coordinated tag rename that misses this SQL goes red, not quiet) — a doppler row merely QUOTING the marker can never count" \
  || no "the emitter conjunct is missing or pinned to a stale literal: marker-quoting rows under another SYSLOG_IDENTIFIER would count (#8874)"

# Anchored on the message leg specifically — a bare `host_role=dedicated ` needle matches BOTH
# legs now, so dropping leg A's conjunct would hide behind leg B's `detail` copy (measured:
# the mutation survived while this row was unanchored).
printf '%s' "$LOCAL_SQL" | grep -cF >/dev/null "position(JSONExtractString(raw, 'message'), 'host_role=dedicated ') > 0" \
  && ok "leg A scopes host_role=dedicated on message — the co-located web host emits the same marker" \
  || no "no host_role=dedicated scope on the journald leg: web-1 rows would drive this alert"

# The field is matched WITH its key and a TRAILING SPACE on leg A (`…_1234` is a prefix of
# `…_12345`). Raw-extraction needle on purpose: the whitespace-stripped canon cannot see the
# space drop.
printf '%s' "$LOCAL_SQL" | grep -cF >/dev/null "JSONExtractString(raw, 'message'), 'data_mount_devid=\${local.inngest_luks_wrong_volume_alias} '" \
  && ok "the devid match is key-anchored and space-terminated on leg A" \
  || no "the devid match is not key-anchored and space-terminated on leg A"

printf '%s' "$LOCAL_SQL" | grep -cE >/dev/null "position\(JSONExtractString\(raw, 'message'\), 'data_mount_devid=[^']*'\) = 0" \
  && ok "the leg-A devid predicate is a NEGATION: a row whose field is missing or renamed FIRES" \
  || no "the leg-A devid predicate is not '= 0' — a schema change would make this rule go quiet"

# ── leg B (#11526): the vector-down phone-home fallback on its own envelope. While Vector is
# down the probe POSTs the identical field row curl-direct to the same source under
# shipper='cloud-init-phone-home' + stage='inngest-server-probe-vector-down' with the field row
# in `detail`. An unreadable fallback row (detail absent or renamed) FIRES, same as leg A.
printf '%s' "$LOCAL_SQL" | grep -cF >/dev/null "JSONExtractString(raw, 'shipper') = '${MUT_SHIPPER}'" \
  && ok "leg B pins shipper='${MUT_SHIPPER}' — the emitter class of the phone-home envelope, derived from the payload builder" \
  || no "the shipper equality conjunct is missing or pinned to a stale literal: phone-home rows cannot reach leg B"

# The stage literal is a RESERVED token on a shared helper (inngest-boot-phone-home.sh takes
# `stage` as positional $1 across many call sites): a second emit site passing the same stage
# arg is a leg-B identity collision the predicate cannot see — exactly one call site may pass it.
_stage_sites="$(grep -chE "^[^#]*inngest-boot-phone-home\.sh[^[:space:]]*[[:space:]]+[\"']?${MUT_STAGE}[\"']?([[:space:]]|\$)" "$BOOT" "$CI" 2>/dev/null | awk '{s+=$1} END{print s+0}')"
[ "$_stage_sites" = "1" ] \
  && ok "exactly one emit site passes the stage literal to inngest-boot-phone-home.sh — the token is reserved" \
  || no "stage-literal emit-site count=${_stage_sites} (want 1) — a second emitter collides on leg-B identity"

printf '%s' "$LOCAL_SQL" | grep -cF >/dev/null "JSONExtractString(raw, 'stage') = '${MUT_STAGE}'" \
  && ok "leg B pins stage='${MUT_STAGE}' — needle derived from the emit site, not re-pinned" \
  || no "the stage equality conjunct is missing or pinned to a stale literal"

printf '%s' "$LOCAL_SQL" | grep -cF >/dev/null "position(JSONExtractString(raw, 'detail'), 'host_role=dedicated ') > 0" \
  && ok "leg B scopes host_role=dedicated read from detail — the envelope's field row, never the marker-prefixed message" \
  || no "the detail-anchored host_role scope is missing on leg B"

printf '%s' "$LOCAL_SQL" | grep -cF >/dev/null "position(JSONExtractString(raw, 'detail'), 'data_mount_devid=\${local.inngest_luks_wrong_volume_alias} ') = 0" \
  && ok "leg B carries the same NEGATED devid check on detail — an identity-pinned row with detail absent/renamed FIRES" \
  || no "the detail-anchored negated devid check is missing — a malformed fallback row would read healthy"

# The detail='' disjunct is the piece that makes a detail-ABSENT row fire: on an empty detail
# BOTH field checks evaluate position('') = 0, and the host_role `> 0` gate would reject the row
# before the negated devid could count it (measured on synthetic raw pre-merge — the
# conjunct-only form returned 0 for that arm, exactly the class this arm exists to page on).
printf '%s' "$LOCAL_SQL" | grep -cF >/dev/null "JSONExtractString(raw, 'detail') = ''" \
  && ok "leg B counts a detail-ABSENT identity-pinned row via the detail='' disjunct — the schema-drop fail-loud arm" \
  || no "the detail='' disjunct is missing — a detail-absent fallback row would read healthy again"

# The window filter must be the full `WHERE time BETWEEN {{start_time}} AND {{end_time}}` — the
# canon pins it too; this row exists so a dropped window names itself in the failure.
printf '%s' "$WV_SQL" | grep -cF >/dev/null 'WHEREtimeBETWEEN{{start_time}}AND{{end_time}}' \
  && ok "the window filter WHERE time BETWEEN {{start_time}} AND {{end_time}} is present" \
  || no "the WHERE time BETWEEN window is missing or altered — the query would scan outside its window"

# Scrub immunity (#11528, mirroring the sibling's verdict row): none of the needle keys may
# appear in vector.toml's pii_scrub `replace(msg` rewrites — the scrub rewrites `token=<v>` to
# `token=[redacted]` BEFORE ingest, which is how a needle dies upstream of the predicate.
# LIMITATION: anchored to the `replace(msg` idiom — a scrub spelled `del(`, `map_values` or
# `replace(.message` evades it; that is the file's current rewrite style.
# LIMITATION: the stem census counts /* */-commented resource blocks as live (dead-text
# intolerance — a legitimately retired resource reds; mutate_green covers only `#` edits).
# Family remainder: sibling guards still carry the pre-#11601 idiom — tracked at #11720.
! grep -qE "replace\\(msg.*(data_mount_devid|host_role|shipper|stage|${INNGEST_PROBE_MARKER})" "$VT" \
  && ok "the needle keys (data_mount_devid, host_role, shipper, stage, marker) are absent from vector.toml's scrub rewrites" \
  || no "a needle key now appears in a pii_scrub replace() — the needle is dead before ingest (the pre-rename defect class)"

# ── presence rows: resources and block-scoped parameters ────────────────────────────────────
WV_EX="$(res_block logtail_exploration "$NAME")"
WV_AL="$(res_block logtail_exploration_alert "$NAME")"

if [ -n "$WV_EX" ] && [ -n "$WV_AL" ]; then
  ok "both resources are declared (one exploration, one alert)"
else
  no "a resource block is missing (ex=${#WV_EX} al=${#WV_AL}) — every parameter row below would be vacuous"
fi

param "$WV_EX" source_variable '"source"' \
  && ok "exploration binds source_variable=\"source\" — the {{source}} template variable" \
  || no "exploration source_variable is not \"source\" — the FROM {{source}} template would resolve to nothing"
param "$WV_EX" values '\[local\.vector_prd_source_id\]' \
  && ok "exploration reads the shared prd Vector source (values=[local.vector_prd_source_id])" \
  || no "exploration is not bound to local.vector_prd_source_id — a source repoint decouples it silently"
param "$WV_EX" sql_query "replace\\(trimspace\\(local\\.${NAME}_sql\\), \"/\\\\\\\\s\\+/\", \" \"\\)" \
  && ok "exploration carries THIS predicate local, collapsed to one line (the perpetual-diff rule)" \
  || no "exploration does not carry local.${NAME}_sql as its collapsed sql_query"

param "$WV_AL" exploration_id "logtail_exploration\\.${NAME}\\.id" \
  && ok "alert is bound to THIS exploration — the identity link every sibling guard pins" \
  || no "alert exploration_id is not logtail_exploration.${NAME}.id — a repoint decouples it silently"
param "$WV_AL" name '"soleur-inngest-luks-wrong-volume-prd"' \
  && ok "alert is named soleur-inngest-luks-wrong-volume-prd" \
  || no "alert name is not soleur-inngest-luks-wrong-volume-prd"
param "$WV_AL" alert_type '"threshold"' && param "$WV_AL" operator '"higher_than"' && param "$WV_AL" value 0 \
  && ok "alert is threshold / higher_than / 0 — any wrong-volume row pages" \
  || no "alert is not threshold / higher_than / 0 — an operator or value flip is a silent mute"
param "$WV_AL" check_period 300 \
  && ok "alert check_period is exactly 300" \
  || no "alert check_period is not exactly 300 — a widened check delays the page"
param "$WV_AL" query_period 5400 \
  && ok "alert query_period is exactly 5400 (covers the hourly probe cadence plus slack)" \
  || no "alert query_period is not exactly 5400 — below the cadence it reads 'no rows' as healthy; above it an incident stays stale"
param "$WV_AL" recovery_period 10800 \
  && ok "alert recovery_period is exactly 10800 (covers two emissions)" \
  || no "alert recovery_period is not exactly 10800 — one good row must not close an incident the next re-opens"
param "$WV_AL" on_missing_data '"treat_as_zero"' \
  && ok "alert reads missing data as zero (an open incident can observe recovery)" \
  || no "alert on_missing_data is not treat_as_zero"
param "$WV_AL" paused '!var\.inngest_luks_cutover_complete' \
  && ok "paused is exactly !var.inngest_luks_cutover_complete on its own line (no suffix, not a comment)" \
  || no "paused is not driven by var.inngest_luks_cutover_complete alone — the arm/disarm route is gone, inverted, or commented"
param "$WV_AL" confirmation_period 0 && param "$WV_AL" email true \
  && ok "alert: confirmation_period 0, email true" \
  || no "alert: confirmation_period is not 0 or email is not true"
grep -qE '^[[:space:]]*escalation_target[[:space:]]*\{' <<< "$WV_AL" \
  && param "$WV_AL" policy_id 'var\.betterstack_paid_tier \? tonumber\(betteruptime_policy\.uptime\[0\]\.id\) : null' \
  && param "$WV_AL" team_name 'var\.betterstack_paid_tier \? null : "Your team"' \
  && ok "alert carries the escalation_target block mirrored from the sibling (paid-tier gated, attributes exactly-once)" \
  || no "alert escalation_target is not the sibling's paid-tier-gated block"
param "$WV_EX" query_type '"sql_expression"' \
  && ok "exploration: query_type is sql_expression" \
  || no "exploration: query_type is not sql_expression (semantic mute path)"
param "$WV_EX" name '"source"' \
  && ok "exploration: variable.name is source" \
  || no "exploration: variable.name repointed — dangles the source_variable/{{source}} binding"
param "$WV_EX" variable_type '"source"' \
  && ok "exploration: variable_type is source" \
  || no "exploration: variable_type is not source"
param "$WV_AL" push 'true' \
  && ok "alert: push channel armed (push = true)" \
  || no "alert: push is not true — the push notification channel is muted"
param "$WV_AL" runbook 'local\.inngest_luks_wrong_volume_runbook_url' \
  && grep -qF 'local.inngest_luks_wrong_volume_runbook_url' <<< "$(grep -E '^[[:space:]]*incident_cause' <<< "$WV_AL")" \
  && ok "alert points its metadata.runbook and incident_cause at the wrong-volume runbook local" \
  || no "alert does not point metadata.runbook AND incident_cause at local.inngest_luks_wrong_volume_runbook_url"

# NEGATIVE row: no count/for_each/lifecycle/ignore_changes token inside EITHER resource block.
# `lifecycle { ignore_changes = [paused] }` would decouple the declaration from the provider;
# `count`/`for_each` would multiply or zero the resource — each a silent mute the param rows
# cannot see.
if [ "$(printf '%s\n%s\n' "$WV_EX" "$WV_AL" | grep -cE '^[[:space:]]*(count|for_each|lifecycle|ignore_changes)[[:space:]]*[= {]')" -eq 0 ]; then
  ok "no count/for_each/lifecycle/ignore_changes token inside either resource block"
else
  no "a count/for_each/lifecycle/ignore_changes token sits inside a resource block — a mute knob the provider would honor silently"
fi

grep -qE '^[[:space:]]*inngest_luks_wrong_volume_runbook_url[[:space:]]*=[[:space:]]*"https://github\.com/jikig-ai/soleur/blob/main/knowledge-base/engineering/operations/runbooks/inngest-luks-cutover-6894\.md"[[:space:]]*(#.*)?$' "$TF" \
  && ok "the runbook local is the clickable URL of the LUKS cutover runbook" \
  || no "inngest_luks_wrong_volume_runbook_url is not the inngest-luks-cutover-6894.md URL"
grep -qxF '# Inngest LUKS cutover (#6894)' "$RB" \
  && ok "the runbook file behind the alert's URL exists and carries its '# Inngest LUKS cutover (#6894)' heading" \
  || no "the runbook has no '# Inngest LUKS cutover (#6894)' heading — the alert's runbook link is dead"

# ── presence rows: the arming variable ──────────────────────────────────────────────────────
# Exactly ONE `variable "inngest_luks_cutover_complete" {` opener FILE-WIDE, unanchored so a
# `/* */`- or `#`-wrapped decoy opener still counts against the real block.
_var_openers="$(grep -cE 'variable[[:space:]]+"inngest_luks_cutover_complete"[[:space:]]*\{' "$VARS" || true)"
[ "$_var_openers" = "1" ] \
  && ok "exactly one variable \"inngest_luks_cutover_complete\" opener in variables.tf (no decoy block)" \
  || no "variable \"inngest_luks_cutover_complete\" opener count=${_var_openers} (want exactly one) — a decoy block can feed the block assertion dead text"

# The variable block, extracted by its opening line and closing brace — not `grep -A4`, whose
# window is one inserted line away from missing `default` and whose bare-token grep was
# satisfied by a commented-out `# default = true` inside it.
VAR_BLOCK="$(awk '/^[[:space:]]*variable "inngest_luks_cutover_complete"[[:space:]]*\{/{f=1} f{print} f&&/^[[:space:]]*\}/{exit}' "$VARS")"
[ -n "$VAR_BLOCK" ] \
  && [ "$(printf '%s\n' "$VAR_BLOCK" | grep -cE '^[[:space:]]*default[[:space:]]*=[[:space:]]*true[[:space:]]*(#.*)?$')" = "1" ] \
  && ok "the arming variable exists and defaults to TRUE (post-cutover, the PLAINTEXT alias is the regression)" \
  || no "variable inngest_luks_cutover_complete is absent or does not default to true"

# ── presence rows: -target parity with the apply workflow ───────────────────────────────────
_miss=""
for ty in logtail_exploration logtail_exploration_alert; do
  grep -qE "^[[:space:]]*-target=$ty\\.$NAME \\\\\$" "$WF" || _miss="$_miss $ty.$NAME"
done
[ -z "$_miss" ] \
  && ok "both resources have an anchored -target= line in the apply workflow (#5566)" \
  || no "missing -target= line(s):$_miss — the resource would never be applied"

# ── presence row: the .tf-wide pair census ──────────────────────────────────────────────────
# MARKER-based, copied from the sibling guard. A resource is a wrong-volume resource when its
# raw block names the stem (the header itself always does), or when it reads a local whose body
# carries the stem (`…_sql` via the alias interpolation, `…_alias`/`…_runbook_url` via their
# own names). Leading whitespace and a trailing comment after the brace do not hide a header.
# The declared set must equal WRONGVOLUME_EXPLORATIONS on BOTH the exploration and alert sides.
# A family-wide structural suite (betterstack-alert-structure.test.sh) independently enforces
# one alert per exploration.
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
_census="$(awk -v MARK="$WRONGVOLUME_STEM" "$CENSUS_AWK" "$(dirname "$TF")"/*.tf 2>/dev/null)"
_dexp="$(while IFS='|' read -r _k _n _c _b; do
  [ "$_k" = E ] || continue
  if [ "$_c" = 1 ] || [[ "$_n" == "$WRONGVOLUME_STEM"* ]]; then printf '%s\n' "$_n"; fi
done <<<"$_census" | sort -u | tr '\n' ' ')"
_dal="$(while IFS='|' read -r _k _n _c _b; do
  [ "$_k" = A ] || continue
  if [ "$_c" = 1 ] || [[ "$_n" == "$WRONGVOLUME_STEM"* ]] || [[ "$_b" == "$WRONGVOLUME_STEM"* ]]; then printf '%s\n' "$_n"; fi
done <<<"$_census" | sort -u | tr '\n' ' ')"
_want="$(printf '%s\n' $WRONGVOLUME_EXPLORATIONS | sort -u | tr '\n' ' ')"
_extra_e="$(comm -23 <(printf '%s\n' $_dexp | sort -u) <(printf '%s\n' $_want | sort -u) | tr '\n' ' ')"
_extra_a="$(comm -23 <(printf '%s\n' $_dal | sort -u) <(printf '%s\n' $_want | sort -u) | tr '\n' ' ')"
_gone_e="$(comm -13 <(printf '%s\n' $_dexp | sort -u) <(printf '%s\n' $_want | sort -u) | tr '\n' ' ')"
_gone_a="$(comm -13 <(printf '%s\n' $_dal | sort -u) <(printf '%s\n' $_want | sort -u) | tr '\n' ' ')"
if [ -z "$_extra_e$_extra_a$_gone_e$_gone_a" ] && [ -n "$_want" ]; then
  ok "the .tf declares exactly the WRONGVOLUME_EXPLORATIONS pair set (${_want% }), each once as an exploration and once as an alert, by marker and by stem"
else
  no "wrong-volume census differs from WRONGVOLUME_EXPLORATIONS (${_want% }): undeclared exploration(s) [${_extra_e% }], undeclared alert(s) [${_extra_a% }], missing exploration(s) [${_gone_e% }], missing alert(s) [${_gone_a% }]: add it to WRONGVOLUME_EXPLORATIONS in this PR"
fi

# ── Mutation rows: each must make a row above RED ─────────────────────────────────────────
# OUTER RUN ONLY. Each row copies ONE source file into $MUT_DIR, mutates the copy, and re-runs
# this guard with MUT_SKIP=1 and the matching LUKS_GUARD_* override pointing at the copy. The
# inner run reads; it never writes. Nothing here touches a tracked file.
SELF="${BASH_SOURCE[0]}"
if [ -z "${MUT_SKIP:-}" ]; then
  MUT_DIR="$(mktemp -d -t luksalert.XXXXXX)" || { printf '[FATAL] mktemp failed\n' >&2; exit 2; }
  assert_fixture_dir "$MUT_DIR"
  trap 'rm -rf "$MUT_DIR"' EXIT

  # INSTRUMENT CONTROL — the inner run against the PRISTINE tree must exit 0, or every row
  # below would grade a broken invocation as "mutation RED". Measured: SELF=/nonexistent
  # reported 21 passed, 0 failed.
  ctl_rc=0; MUT_SKIP=1 bash "$SELF" >"$MUT_DIR/control.log" 2>&1 || ctl_rc=$?
  if [ "$ctl_rc" -ne 0 ]; then
    printf '[FATAL] instrument control: the inner run exited %s on the PRISTINE tree — the battery cannot be trusted:\n' "$ctl_rc" >&2
    sed 's/^/    /' "$MUT_DIR/control.log" >&2; exit 2
  fi

  # Helpers prepended to every mutation program. `Q` is the single quote (programs live inside
  # bash single quotes). `edit(s, anchor, old, new)` replaces `old` exactly once INSIDE the
  # region that starts at `anchor` and ends at the next blank-line-free closing marker
  # (`\n  SQL\n` for the heredoc local, `\n}\n` for a resource), so a literal that occurs in
  # both legs or both files is mutated in exactly one.
  PRELUDE='Q = chr(39)
def edit(s, anchor, old, new, end="\n}\n"):
    i = s.index(anchor)
    j = s.index(end, i)
    region = s[i:j]
    assert region.count(old) == 1, "anchor drift: %r occurs %d times" % (old, region.count(old))
    return s[:i] + region.replace(old, new) + s[j:]
WVSQL = "inngest_luks_wrong_volume_sql = <<-SQL"
WVEX = "resource \"logtail_exploration\" \"inngest_luks_wrong_volume\" {"
WVAL = "resource \"logtail_exploration_alert\" \"inngest_luks_wrong_volume\" {"
SQLEND = "\n  SQL\n"'

  # Scores ONE inner run: prints red | wrong | survived | unresolved. Only rc=1 is a caught
  # mutation; when a fragment is named a [FAIL] line must contain it (a row that reds for the
  # WRONG reason is no evidence). The reader is pipe-free of `grep -q`: `-q` exits early and
  # the upstream grep would die of SIGPIPE under pipefail; plain `grep -F >/dev/null` reads
  # the whole stream, so it cannot.
  _red_verdict() {  # _red_verdict <rc> <log> <fragment-or-empty>
    case "$1" in
      1) if [ -z "$3" ] || { grep -F '[FAIL]' "$2" | grep -F -- "$3" >/dev/null; }; then echo red; else echo wrong; fi ;;
      0) echo survived ;;
      *) echo unresolved ;;
    esac
  }

  mutate_red() {  # mutate_red <label> <TF|VARS|WF> <python-program-on-s> [expected [FAIL] fragment] [red|wrong]
    local label="$1" which="$2" prog="$3" tag="${4:-}" want="${5:-red}" src copy rc=0 olog="$MUT_DIR/inner.log"
    rm -f "$MUT_DIR"/zz_*.tf   # a second-file row plants one; it must not leak into the next row's census
    case "$which" in
      TF)   src="$TF";   copy="$MUT_DIR/betterstack-logs-alerts.tf" ;;
      VARS) src="$VARS"; copy="$MUT_DIR/variables.tf" ;;
      WF)   src="$WF";   copy="$MUT_DIR/apply-web-platform-infra.yml" ;;
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
      TF)   LUKS_GUARD_TF="$copy"   MUT_SKIP=1 bash "$SELF" >"$olog" 2>&1 || rc=$? ;;
      VARS) LUKS_GUARD_VARS="$copy" MUT_SKIP=1 bash "$SELF" >"$olog" 2>&1 || rc=$? ;;
      WF)   LUKS_GUARD_WF="$copy"   MUT_SKIP=1 bash "$SELF" >"$olog" 2>&1 || rc=$? ;;
    esac
    # rc DISCRIMINATION. rc>=2 is this guard's own FATAL class, rc=126/127 a broken invocation:
    # none is evidence a row pins anything. want=wrong is the scorer's NEGATIVE CONTROL: a
    # mutant that reds a row other than the one the fragment names must be graded WRONG (never
    # RED), or every fragment check above would be decoration.
    case "$(_red_verdict "$rc" "$olog" "$tag"):$want" in
      red:red) ok "mutation RED: $label" ;;
      wrong:wrong) ok "scorer control: graded WRONG reason as required: $label" ;;
      wrong:red) no "mutation went red for the WRONG reason (no [FAIL] line contains '$tag'): $label" ;;
      red:wrong) no "scorer control: the wrong-reason mutant was graded RED (the fragment check accepts anything): $label" ;;
      survived:*) no "mutation SURVIVED: $label — the rows above pin nothing" ;;
      *) no "mutation UNRESOLVED (inner rc=$rc, not an assertion): $label — instrument, not evidence" ;;
    esac
  }

  # A must-PASS row: a legitimate edit must NOT red the guard (rc 0 is the only pass).
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
    LUKS_GUARD_TF="$copy" MUT_SKIP=1 bash "$SELF" >"$MUT_DIR/green.log" 2>&1 || rc=$?
    case "$rc" in
      0) ok "must-PASS stays green: $label" ;;
      1) no "legitimate edit went RED: $label" ;;
      *) no "must-PASS UNRESOLVED (inner rc=$rc): $label - instrument, not evidence" ;;
    esac
  }

  # Raising PRESENCE_ROWS above what an inner run asserts must trip the assertion floor (the
  # floor is pass+fail >= floor, so only a RAISE reds; lowering it cannot). The scratch copy
  # gets its REPO line rewritten to the real repo, so its non-overridable reads (BOOT/CI/RB/
  # VT/LIB) resolve — no fourth env axis exists to subvert.
  mutate_floor_red() {  # mutate_floor_red <label>
    local label="$1" copy rc=0
    copy="$MUT_DIR/floor-mutated.test.sh"
    sed -e 's/^PRESENCE_ROWS=43$/PRESENCE_ROWS=44/' \
        -e "s|^REPO=.*|REPO=\"$REPO\"|" "$SELF" > "$copy"
    if cmp -s "$SELF" "$copy"; then no "mutation '$label' did not land (PRESENCE_ROWS anchor drifted)"; return 0; fi
    LUKS_GUARD_TF="$TF" LUKS_GUARD_VARS="$VARS" LUKS_GUARD_WF="$WF" \
      MUT_SKIP=1 bash "$copy" >/dev/null 2>&1 || rc=$?
    case "$rc" in
      1) ok "mutation RED: $label" ;;
      0) no "mutation SURVIVED: $label - the assertion floor pins nothing" ;;
      *) no "mutation UNRESOLVED (inner rc=$rc, not an assertion): $label - instrument, not evidence" ;;
    esac
  }

  # ── Mutation matrix rows (#11528): dead-text satisfaction, wiring, mute knobs, window ──────
  mutate_red "a /* */-wrapped decoy heredoc with a verbatim conjunct copy sits before the live local while the live body is gutted" TF \
    'i = s.index("  inngest_luks_wrong_volume_sql = <<-SQL\n")
j = s.index("\n  SQL\n", i) + len("\n  SQL\n")
body = s[i:j]
gutted = "  inngest_luks_wrong_volume_sql = <<-SQL\n    SELECT 1\n  SQL\n"
s = s[:i] + "  /*\n" + body + "  */\n" + gutted + s[j:]' \
    "opener count"
  mutate_red "paused is commented out and a constant paused = true added (commented copy must not satisfy the pin)" TF \
    's = edit(s, WVAL, "  paused = !var.inngest_luks_cutover_complete\n", "  # paused = !var.inngest_luks_cutover_complete\n  paused = true\n")' \
    "paused"
  mutate_red "on_missing_data is commented out (the commented copy must not satisfy the pin)" TF \
    's = edit(s, WVAL, "  on_missing_data     = \"treat_as_zero\"\n", "  # on_missing_data     = \"treat_as_zero\"\n")' \
    "on_missing_data"
  mutate_red "exploration_id is commented out (the commented copy must not satisfy the pin)" TF \
    's = edit(s, WVAL, "  exploration_id = logtail_exploration.inngest_luks_wrong_volume.id\n", "  # exploration_id = logtail_exploration.inngest_luks_wrong_volume.id\n")' \
    "exploration_id"
  mutate_red "count(*) becomes 0 in the SELECT (the alert could never observe a row)" TF \
    's = edit(s, WVSQL, "count(*) AS value", "0 AS value", SQLEND)' \
    "ruled form"
  mutate_red "the exploration's values is repointed at another source local" TF \
    's = edit(s, WVEX, "    values        = [local.vector_prd_source_id]\n", "    values        = [local.vector_dev_source_id]\n")' \
    "vector_prd_source_id"
  mutate_red "FROM {{source}} is repointed at a different template variable" TF \
    's = edit(s, WVSQL, "FROM {{source}}", "FROM {{other}}", SQLEND)' \
    "ruled form"
  mutate_red "query_type is repointed off sql_expression (the stored query could change semantics)" TF \
    's = edit(s, WVEX, "    query_type      = \"sql_expression\"\n", "    query_type      = \"chart_expression\"\n")' \
    "query_type"
  mutate_red "variable.name is repointed off source (dangles the source_variable/{{source}} binding)" TF \
    's = edit(s, WVEX, "    name          = \"source\"\n", "    name          = \"dst\"\n")' \
    "variable.name"
  mutate_red "variable_type is repointed off source" TF \
    's = edit(s, WVEX, "    variable_type = \"source\"\n", "    variable_type = \"data\"\n")' \
    "variable_type"
  mutate_red "push flips to false (the push notification channel is muted; email alone remains)" TF \
    's = edit(s, WVAL, "  push           = true\n", "  push           = false\n")' \
    "push"
  mutate_red "WHERE time BETWEEN {{start_time}} AND {{end_time}} is dropped (the window is gone)" TF \
    's = edit(s, WVSQL, "    WHERE time BETWEEN {{start_time}} AND {{end_time}}\n", "", SQLEND)' \
    "ruled form"
  mutate_red "operator flips to lower_than (the rule would page on the RIGHT volume)" TF \
    's = edit(s, WVAL, "  operator            = \"higher_than\"\n", "  operator            = \"lower_than\"\n")' \
    "higher_than"
  mutate_red "the threshold value flips 0 -> 999999 (no count ever pages)" TF \
    's = edit(s, WVAL, "  value               = 0\n", "  value               = 999999\n")' \
    "threshold"
  mutate_red "the check_period widens from 300 to 3600" TF \
    's = edit(s, WVAL, "  check_period        = 300\n", "  check_period        = 3600\n")' \
    "check_period"
  mutate_red "the query_period widens from 5400 to 54000" TF \
    's = edit(s, WVAL, "  query_period        = 5400\n", "  query_period        = 54000\n")' \
    "query_period"
  mutate_red "the recovery_period widens from 10800 to 108000" TF \
    's = edit(s, WVAL, "  recovery_period     = 10800\n", "  recovery_period     = 108000\n")' \
    "recovery_period"
  mutate_red "a lifecycle { ignore_changes = [paused] } block joins the alert (the provider would stop honoring the declaration)" TF \
    's = edit(s, WVAL, "  paused = !var.inngest_luks_cutover_complete\n", "  paused = !var.inngest_luks_cutover_complete\n\n  lifecycle {\n    ignore_changes = [paused]\n  }\n")' \
    "ignore_changes"
  mutate_red "a for_each meta-argument joins the exploration block" TF \
    's = edit(s, WVEX, "  name      = \"soleur-inngest-luks-wrong-volume-prd\"\n", "  for_each = { x = 1 }\n  name      = \"soleur-inngest-luks-wrong-volume-prd\"\n")' \
    "for_each"
  mutate_red "a count meta-argument joins the alert block" TF \
    's = edit(s, WVAL, "  exploration_id = logtail_exploration.inngest_luks_wrong_volume.id\n", "  count = 1\n  exploration_id = logtail_exploration.inngest_luks_wrong_volume.id\n")' \
    "count"
  mutate_red "a /* */-wrapped decoy variable block sits ahead of the real arming variable" VARS \
    'old = "variable \"inngest_luks_cutover_complete\" {"
assert s.count(old) == 1
s = s.replace(old, "/*\nvariable \"inngest_luks_cutover_complete\" {\n  default = true\n}\n*/\n" + old)' \
    "opener count"
  mutate_red "the devid interpolation gains a dollar-dollar escape (the literal alias text never reaches the query)" TF \
    'i = s.index(WVSQL); j = s.index("\n  SQL\n", i); region = s[i:j]
old = "data_mount_devid=${local.inngest_luks_wrong_volume_alias}"
assert region.count(old) == 2
s = s[:i] + region.replace(old, "data_mount_devid=$${local.inngest_luks_wrong_volume_alias}") + s[j:]' \
    "ruled form"
  mutate_red "the leg-A devid negation is neutralized by an inline tautology (= 0 OR > 0)" TF \
    's = edit(s, WVSQL, "position(JSONExtractString(raw, "+Q+"message"+Q+"), "+Q+"data_mount_devid=${local.inngest_luks_wrong_volume_alias} "+Q+") = 0", "(position(JSONExtractString(raw, "+Q+"message"+Q+"), "+Q+"data_mount_devid=${local.inngest_luks_wrong_volume_alias} "+Q+") = 0 OR position(JSONExtractString(raw, "+Q+"message"+Q+"), "+Q+"data_mount_devid=${local.inngest_luks_wrong_volume_alias} "+Q+") > 0)", SQLEND)' \
    "ruled form"
  mutate_red "the metadata.runbook local reference is wrapped in a # comment" TF \
    's = edit(s, WVAL, "    runbook = local.inngest_luks_wrong_volume_runbook_url\n", "    # runbook = local.inngest_luks_wrong_volume_runbook_url\n")' \
    "runbook"
  mutate_red "a second alert inngest_luks_wrong_volume_x binds the same exploration (the pair census must see it)" TF \
    's = s + "\nresource \"logtail_exploration_alert\" \"inngest_luks_wrong_volume_x\" {\n  exploration_id = logtail_exploration.inngest_luks_wrong_volume.id\n}\n"' \
    "WRONGVOLUME_EXPLORATIONS"
  mutate_floor_red "DISPATCH: PRESENCE_ROWS raised by one trips the assertion floor"
  mutate_green "a # comment outside any resource block is reworded (legitimate edits stay green)" TF \
    'old = "watched alias = the live encrypted alias"
assert s.count(old) == 1
s = s.replace(old, "watched alias = the live encrypted volume")'
  mutate_green "a # comment line naming no pinned token is added inside the locals block" TF \
    'old = "  inngest_luks_wrong_volume_runbook_url ="
assert s.count(old) == 1
s = s.replace(old, "  # no pinned token on this comment line\n" + old)'

  # ── Carried-forward rows (the pre-#11528 battery, re-scored through _red_verdict) ─────────
  mutate_red "the alias becomes a literal id" TF \
    'old = "inngest_luks_wrong_volume_alias = \"scsi-0HC_Volume_${hcloud_volume.inngest_redis_luks.id}\""
assert s.count(old) == 1
s = s.replace(old, "inngest_luks_wrong_volume_alias = \"scsi-0HC_Volume_106261946\"")' \
    "resource-id line"
  # The devid needle is anchored on the `message` extraction: the bare
  # `data_mount_devid=<alias> ') = 0` occurs TWICE (leg A `message` AND leg B `detail`), so an
  # unanchored needle would trip edit()'s count==1 self-check.
  mutate_red "the leg-A devid match loses its trailing space (…_1234 would match …_12345)" TF \
    's = edit(s, WVSQL, "JSONExtractString(raw, "+Q+"message"+Q+"), "+Q+"data_mount_devid=${local.inngest_luks_wrong_volume_alias} "+Q+") = 0", "JSONExtractString(raw, "+Q+"message"+Q+"), "+Q+"data_mount_devid=${local.inngest_luks_wrong_volume_alias}"+Q+") = 0", SQLEND)' \
    "space-terminated"
  mutate_red "the leg-A devid negation flips to a positive match (fires on the RIGHT volume)" TF \
    's = edit(s, WVSQL, "JSONExtractString(raw, "+Q+"message"+Q+"), "+Q+"data_mount_devid=${local.inngest_luks_wrong_volume_alias} "+Q+") = 0", "JSONExtractString(raw, "+Q+"message"+Q+"), "+Q+"data_mount_devid=${local.inngest_luks_wrong_volume_alias} "+Q+") > 0", SQLEND)' \
    "ruled form"
  mutate_red "the leg-A host_role scope is dropped (web-1 rows drive the alert)" TF \
    's = edit(s, WVSQL, "        AND position(JSONExtractString(raw, "+Q+"message"+Q+"), "+Q+"host_role=dedicated "+Q+") > 0\n", "", SQLEND)' \
    "ruled form"
  mutate_red "paused becomes a constant true (armed never)" TF \
    's = edit(s, WVAL, "  paused = !var.inngest_luks_cutover_complete\n", "  paused = true\n")' \
    "paused"
  mutate_red "paused keeps the variable but gains an inverting suffix (|| true)" TF \
    's = edit(s, WVAL, "  paused = !var.inngest_luks_cutover_complete\n", "  paused = !var.inngest_luks_cutover_complete || true\n")' \
    "paused"
  mutate_red "the window shrinks below the probe cadence" TF \
    's = edit(s, WVAL, "  query_period        = 5400\n", "  query_period        = 300\n")' \
    "query_period"
  # The arming default reverting to false is the silent-disarm this guard exists to catch — the
  # .tf still reads `paused = !var…`, so every TF-anchored row stays green while the RESOLVED
  # value is `paused = true`. The edit is scoped to the variable BLOCK.
  mutate_red "the arming default reverts to false (alert silently disarmed)" VARS \
    'import re
m = re.search(r"(variable \"inngest_luks_cutover_complete\"[^{]*\{)(.*?)(\n\})", s, re.S)
assert m, "variable block not found"
block = m.group(2)
assert block.count("default     = true") == 1
s = s[:m.start(2)] + block.replace("default     = true", "default     = false") + s[m.end(2):]' \
    "does not default to true"
  mutate_red "the variable declaration is renamed (the reference dangles)" VARS \
    'old = "variable \"inngest_luks_cutover_complete\" {"
assert s.count(old) == 1
s = s.replace(old, "variable \"inngest_luks_cutover_compleet\" {")' \
    "opener count"
  mutate_red "the alert is dropped from the apply allowlist" WF \
    'old = "            -target=logtail_exploration_alert.inngest_luks_wrong_volume \\\n"
assert s.count(old) == 1
s = s.replace(old, "")' \
    "-target="
  # #8874 rows — the row set is pinned to the probe's own emitter.
  mutate_red "the leg-A emitter conjunct is dropped (quoting rows count again)" TF \
    'import os
em = os.environ["MUT_EMITTER"]
s = edit(s, WVSQL, "        JSONExtractString(raw, "+Q+"SYSLOG_IDENTIFIER"+Q+") = "+Q+"" + em + Q+"\n", "", SQLEND)' \
    "ruled form"
  mutate_red "the leg-A emitter literal flips to doppler (the offender becomes the counted set)" TF \
    'import os
em = os.environ["MUT_EMITTER"]
s = edit(s, WVSQL, "JSONExtractString(raw, "+Q+"SYSLOG_IDENTIFIER"+Q+") = "+Q+"" + em, "JSONExtractString(raw, "+Q+"SYSLOG_IDENTIFIER"+Q+") = "+Q+"doppler", SQLEND)' \
    "ruled form"
  mutate_red "the leg-A emitter equality weakens to a containment check" TF \
    'import os
em = os.environ["MUT_EMITTER"]
s = edit(s, WVSQL, "JSONExtractString(raw, "+Q+"SYSLOG_IDENTIFIER"+Q+") = "+Q+"" + em, "position(JSONExtractString(raw, "+Q+"SYSLOG_IDENTIFIER"+Q+"), "+Q+"" + em + Q+") > 0", SQLEND)' \
    "ruled form"
  mutate_red "the alert is repointed at a different exploration" TF \
    's = edit(s, WVAL, "exploration_id = logtail_exploration.inngest_luks_wrong_volume.id", "exploration_id = logtail_exploration.monitor_send_failed.id")' \
    "exploration_id"
  # #11526 rows — the phone-home fallback arm.
  mutate_red "the leg-B shipper conjunct is dropped (any stage's phone-home row counts)" TF \
    'import os
shipper = os.environ["MUT_SHIPPER"]
s = edit(s, WVSQL, "          JSONExtractString(raw, "+Q+"shipper"+Q+") = "+Q+"" + shipper + Q+"\n", "", SQLEND)' \
    "ruled form"
  mutate_red "the leg-B shipper literal flips to a foreign shipper (leg B reads zero rows silently)" TF \
    'import os
shipper = os.environ["MUT_SHIPPER"]
s = edit(s, WVSQL, "shipper"+Q+") = "+Q+"" + shipper, "shipper"+Q+") = "+Q+"cloud-init-phone-other", SQLEND)' \
    "ruled form"
  mutate_red "the leg-B stage conjunct is dropped (every phone-home row counts)" TF \
    'import os
stage = os.environ["MUT_STAGE"]
s = edit(s, WVSQL, "          AND JSONExtractString(raw, "+Q+"stage"+Q+") = "+Q+"" + stage + Q+"\n", "", SQLEND)' \
    "ruled form"
  mutate_red "the leg-B stage literal flips to a foreign stage" TF \
    'import os
stage = os.environ["MUT_STAGE"]
s = edit(s, WVSQL, "JSONExtractString(raw, "+Q+"stage"+Q+") = "+Q+"" + stage, "JSONExtractString(raw, "+Q+"stage"+Q+") = "+Q+"inngest-server-probe-other", SQLEND)' \
    "ruled form"
  mutate_red "the leg-B detail host_role scope is dropped (a web-host fallback row counts)" TF \
    's = edit(s, WVSQL, "              position(JSONExtractString(raw, "+Q+"detail"+Q+"), "+Q+"host_role=dedicated "+Q+") > 0\n", "", SQLEND)' \
    "ruled form"
  mutate_red "the leg-B detail devid check flips to a positive match (fires on the RIGHT volume via the fallback)" TF \
    's = edit(s, WVSQL, "JSONExtractString(raw, "+Q+"detail"+Q+"), "+Q+"data_mount_devid=${local.inngest_luks_wrong_volume_alias} "+Q+") = 0", "JSONExtractString(raw, "+Q+"detail"+Q+"), "+Q+"data_mount_devid=${local.inngest_luks_wrong_volume_alias} "+Q+") > 0", SQLEND)' \
    "ruled form"
  mutate_red "the detail='' fail-loud disjunct is neutralized (detail-absent rows go quiet again)" TF \
    's = edit(s, WVSQL, "JSONExtractString(raw, "+Q+"detail"+Q+") = "+Q+Q, "false", SQLEND)' \
    "ruled form"
  mutate_red "the whole OR arm is deleted (the #11526 regression — legs collapse to journald-only)" TF \
    'import os
stage = os.environ["MUT_STAGE"]
shipper = os.environ["MUT_SHIPPER"]
old = ("        OR (\n"
       "          JSONExtractString(raw, "+Q+"shipper"+Q+") = "+Q+"" + shipper + Q+"\n"
       "          AND JSONExtractString(raw, "+Q+"stage"+Q+") = "+Q+"" + stage + Q+"\n"
       "          AND (\n"
       "            JSONExtractString(raw, "+Q+"detail"+Q+") = "+Q+Q+"\n"
       "            OR (\n"
       "              position(JSONExtractString(raw, "+Q+"detail"+Q+"), "+Q+"host_role=dedicated "+Q+") > 0\n"
       "              AND position(JSONExtractString(raw, "+Q+"detail"+Q+"), "+Q+"data_mount_devid=${local.inngest_luks_wrong_volume_alias} "+Q+") = 0\n"
       "            )\n"
       "          )\n"
       "        )\n")
s = edit(s, WVSQL, old, "", SQLEND)' \
    "ruled form"

  # ── Census rows: the declared set is pinned, not just the pair's name ─────────────────────
  mutate_red "the declared pair is renamed away from WRONGVOLUME_EXPLORATIONS (the constant no longer matches the .tf)" TF \
    'old = "\"inngest_luks_wrong_volume\" {"
assert s.count(old) == 2
s = s.replace(old, "\"inngest_luks_wrong_volumex\" {")' \
    "resource block is missing"
  mutate_red "an exploration NOT named after the stem reads the wrong-volume SQL local (the stem census must still see it)" TF \
    's = s + "\nresource \"logtail_exploration\" \"zz_other_pair\" {\n  sql_query = local.inngest_luks_wrong_volume_sql\n}\n"' \
    "WRONGVOLUME_EXPLORATIONS"
  mutate_red "a SECOND root *.tf declares an exploration that reads the wrong-volume local (the census scans every root file)" TF \
    'import os
open(os.path.join(os.path.dirname(p), "zz_second.tf"), "w").write("resource \"logtail_exploration\" \"zz_second\" {\n  sql_query = local.inngest_luks_wrong_volume_sql\n}\n")
s = s + "\n# second-file row\n"' \
    "WRONGVOLUME_EXPLORATIONS"
  # Scorer NEGATIVE CONTROL: the mutant reds ONLY the -target row, so a fragment naming the
  # paused pin must grade it WRONG.
  mutate_red "scorer control: a mutant that reds only the -target row, scored against a paused fragment" WF \
    'old = "            -target=logtail_exploration.inngest_luks_wrong_volume \\\n"
assert s.count(old) == 1
s = s.replace(old, "")' \
    "paused" wrong
fi

# PRESENCE_ROWS is exactly the count of presence rows an inner (MUT_SKIP) run asserts; the
# outer run adds one row per mutation. The instrument control above is what catches a floor
# that drifts past the presence rows (that control, not this comment, is the guard against a
# dead battery).
PRESENCE_ROWS=43
MUT_ROWS=54
_floor=$((PRESENCE_ROWS + MUT_ROWS))
[ -n "${MUT_SKIP:-}" ] && _floor=$PRESENCE_ROWS
_ran=$((pass + fail))
if [ "$_ran" -lt "$_floor" ]; then printf '[FATAL] assertion floor: %s ran, floor %s\n' "$_ran" "$_floor" >&2; exit 1; fi
if [ "${#FAILED[@]}" -ne "$fail" ]; then printf '[FATAL] ledger %s != fail counter %s\n' "${#FAILED[@]}" "$fail" >&2; exit 1; fi
[ -n "${MUT_SKIP:-}" ] && printf '[note] MUT_SKIP active — mutation rows skipped (floor %s); LUKS_GUARD_{TF,VARS,WF}=%s,%s,%s\n' "$_floor" "${LUKS_GUARD_TF:-unset}" "${LUKS_GUARD_VARS:-unset}" "${LUKS_GUARD_WF:-unset}"
printf '\n=== inngest-luks-wrong-volume-alert: %s passed, %s failed (%s assertions, floor %s) ===\n' "$pass" "$fail" "$_ran" "$_floor"
[ "$fail" -eq 0 ]
