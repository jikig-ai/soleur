#!/usr/bin/env bash
#
# Drift guard for the "#6894 store is not on the encrypted volume" Better Stack Logs alert
# (apps/web-platform/infra/betterstack-logs-alerts.tf).
#
# WHAT THE ALERT IS FOR. After the LUKS cutover, the dedicated host's own probe row resolves the
# device backing /mnt/data to a Hetzner by-id alias (`data_mount_devid`, probe_schema=8). If that
# alias is ever NOT the additive volume's, Redis is writing UNENCRYPTED again — and nothing else
# notices, because the scheduler is healthy in exactly those states.
#
# WHAT THIS FILE PROTECTS, and why each row exists rather than "the SQL looks right":
#   * The alias is built from the RESOURCE id. A literal would keep watching an id the volume no
#     longer has after a re-create, and the rule would go quiet — which reads like health.
#   * The field is matched WITH its key and a TRAILING SPACE. `…_1234` is a prefix of `…_12345`.
#   * The predicate is a NEGATION, so a row whose field is missing or renamed FIRES. An
#     unreadable answer is not a clean one — the defect class this repo keeps paying for.
#   * `paused` is the ONE variable-driven paused state in that file, driven by
#     `var.inngest_luks_cutover_complete`. Since #8296 that variable defaults to true (the
#     2026-09-20 cutover put the store on the encrypted volume, so a plaintext alias is now the
#     regression, not the baseline). Before the cutover the same rule would have paged
#     continuously and been muted; that history is why `paused` is a variable at all.
#   * Both resources are in the apply workflow's `-target=` allowlist. Without that they are never
#     applied and never exist (the #5566 silent-un-applied class).
#   * The row set is pinned to the probe's own emitter. A `doppler` event-log row that merely
#     QUOTES the marker verbatim (webhook-delivered issue/PR text about the probe — the #8846
#     defect class, measured 50 quoting rows vs 6 real probe rows in one 6h window) can never
#     count. The start-of-message anchor excluded them only because every such row happens to
#     begin with `{` — a payload-formatting accident, not a control (#8874).
#   * The predicate admits the probe's vector-down PHONE-HOME fallback on its own envelope.
#     While Vector is down the probe POSTs the identical field row curl-direct to the same
#     source under shipper='cloud-init-phone-home' + stage='inngest-server-probe-vector-down'
#     with the field row in `detail` — a second OR leg admits those rows on envelope-field
#     equality, so a Vector outage no longer blinds the alert (#11526). An unreadable
#     fallback row (detail absent or renamed) FIRES, same as leg A's negated devid check.
#
# WHAT THIS FILE DOES NOT PROVE (stated so the name is not read as more than it is): that the
# alert is armed IN PRODUCTION. Armed-ness there is decided by the RESOLVED variable — a Doppler
# `TF_VAR_inngest_luks_cutover_complete` override wins silently, a `lifecycle { ignore_changes }`
# would decouple the declaration from the provider, and a merge with `[skip-web-platform-apply]`
# leaves Better Stack on the old value. None of that is readable from source. The live detector
# for those cases is the reconciler (plugins/soleur/lib/heartbeat-live-reconcile.ts, run twice
# daily by scheduled-terraform-drift.yml), which since #8296 resolves this variable's default and
# reports a live pause as `logs-alert-paused`. This guard pins the SOURCE; the reconciler pins
# the WORLD. Neither substitutes for the other.
#
# Mutation rows live at the bottom. Each one COPIES a source file into a scratch dir, mutates the
# COPY, and re-runs this guard against the copy through the LUKS_GUARD_{TF,VARS,WF} overrides.
# No tracked file is ever written. That is a deliberate design, not a convenience: an earlier
# form mutated the tracked files in place under a restoring trap, and review measured that two
# concurrent runs stranded a mutation in 9 of 24 trials (instance B snapshots A's in-flight
# mutation as its "pristine", then faithfully restores it), and that SIGKILL, a full disk, or a
# Ctrl-C on the last row each left variables.tf — a file the production apply reads on every push
# to main — differing from HEAD with a green or misleading verdict. Copying removes the whole
# class rather than guarding each path.
set -uo pipefail
export TMPDIR="${TMPDIR:-/var/tmp}"

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$DIR/../../../.." && pwd)"
# Overridable so the mutation rows can point an inner run at a mutated COPY. Production values
# are the tracked files; nothing in this file writes to them.
TF="${LUKS_GUARD_TF:-$REPO/apps/web-platform/infra/betterstack-logs-alerts.tf}"
VARS="${LUKS_GUARD_VARS:-$REPO/apps/web-platform/infra/variables.tf}"
WF="${LUKS_GUARD_WF:-$REPO/.github/workflows/apply-web-platform-infra.yml}"

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
assert_fixture_dir "$TF"; assert_fixture_dir "$VARS"; assert_fixture_dir "$WF"

# INSTRUMENT SELF-TEST — both helpers must move their own counter before any verdict is trusted.
_p0=$pass; _f0=$fail
{ ok "self-test"; no "self-test"; } >/dev/null
if [ "$pass" -ne $((_p0 + 1)) ] || [ "$fail" -ne $((_f0 + 1)) ] || [ "${#FAILED[@]}" -ne 1 ]; then
  printf '[FATAL] instrument self-test: ok()/no() did not each move their counter\n' >&2; exit 2
fi
pass=$_p0; fail=$_f0; FAILED=()

for f in "$TF" "$VARS" "$WF"; do
  [ -r "$f" ] || { printf '[FATAL] unreadable: %s\n' "$f" >&2; exit 2; }
done

# The emitter literal is DERIVED from the canonical lib, never re-pinned (#8874 review): a
# coordinated probe-tag rename that updates LOG_TAG + the lib but misses the .tf conjunct must
# go red, which only happens when the needle follows the lib. MUT_EMITTER feeds the python
# mutation needles below; a bare literal here would be a third uncoupled copy. The unset is the
# lib's documented load contract — an env-inherited name must not silently substitute for a
# failed source.
unset INNGEST_PROBE_ROW_JQ INNGEST_PROBE_EMITTER INNGEST_PROBE_MARKER
# shellcheck source=scripts/lib/inngest-probe-row.sh
source "$REPO/scripts/lib/inngest-probe-row.sh" || { printf '[FATAL] cannot source scripts/lib/inngest-probe-row.sh — the emitter needle has no canonical source\n' >&2; exit 2; }
export MUT_EMITTER="$INNGEST_PROBE_EMITTER"

# The leg-B `stage` literal is a CALL-SITE literal with no canonical lib — its authority is the
# emit site in inngest-bootstrap.sh (#11526). The extraction is anchored on the
# `inngest-boot-phone-home.sh <stage>` CALL FORM with no `#` before the helper name, so a comment
# carrying the bare literal cannot satisfy it, and it yields the arg BOUNDED — a rename to a
# superstring (-v2) extracts the NEW literal, reddening the .tf needle instead of silently
# re-pinning a stale one. Unlike MUT_EMITTER this cannot flow through a lib.
export MUT_STAGE
MUT_STAGE="$(sed -n 's/^[^#]*inngest-boot-phone-home\.sh[[:space:]]\+\(inngest-server-probe-[A-Za-z0-9_-]*\).*/\1/p' "$REPO/apps/web-platform/infra/inngest-bootstrap.sh" | head -1)"
[ -n "$MUT_STAGE" ] || { printf '[FATAL] no inngest-server-probe-* call site on inngest-boot-phone-home.sh in inngest-bootstrap.sh — the stage needle has no canonical source\n' >&2; exit 2; }

# The leg-B `shipper` literal is the payload builder's own — its authority is the jq envelope in
# cloud-init-inngest.yml (`shipper:"…"`), derived the same way so a payload-side rename that
# misses the .tf goes red rather than leaving the needle green on a dead literal.
export MUT_SHIPPER
MUT_SHIPPER="$(sed -n 's/^[^#]*shipper:"\([^"]*\)".*/\1/p' "$REPO/apps/web-platform/infra/cloud-init-inngest.yml" | head -1)"
[ -n "$MUT_SHIPPER" ] || { printf '[FATAL] no shipper literal in the cloud-init-inngest.yml payload builder — the shipper needle has no canonical source\n' >&2; exit 2; }

# The predicate heredoc, extracted from the FIRST UNCOMMENTED opening line. An earlier form
# started at the first match anywhere, so a commented-out copy of the heredoc above `locals {`
# would have become the extracted body and let the live one be gutted freely.
LOCAL_SQL="$(awk '/^[[:space:]]*inngest_luks_wrong_volume_sql[[:space:]]*=[[:space:]]*<<-SQL/{f=1;next} f&&/^  SQL$/{f=0} f' "$TF")"

# Every whole-line assertion below is anchored at line start and at line end. A bare substring
# grep (`grep -qF 'paused = !var…'`) is satisfied by the same text inside a comment, and by the
# same text with a suffix that inverts it (`paused = !var.x || true`). Both were measured escapes.
line_is() {  # line_is <file> <ERE for the whole line, without anchors>
  grep -qE "^[[:space:]]*$2[[:space:]]*(#.*)?$" "$1"
}

[ -n "$LOCAL_SQL" ] \
  && ok "the predicate local is a heredoc this guard can read" \
  || no "inngest_luks_wrong_volume_sql: heredoc not found — every row below would be vacuous"

line_is "$TF" 'sql_query[[:space:]]*=[[:space:]]*replace\(trimspace\(local\.inngest_luks_wrong_volume_sql\), "/\\\\s\+/", " "\)' \
  && ok "the exploration carries THIS predicate, collapsed to one line (the sibling's perpetual-diff rule)" \
  || no "the exploration does not carry local.inngest_luks_wrong_volume_sql as its sql_query"

line_is "$TF" 'exploration_id[[:space:]]*=[[:space:]]*logtail_exploration\.inngest_luks_wrong_volume\.id' \
  && ok "the alert is bound to THIS exploration — every sibling guard pins this identity link" \
  || no "the alert's exploration_id does not name this exploration — a repoint decouples it silently"

line_is "$TF" 'inngest_luks_wrong_volume_alias[[:space:]]*=[[:space:]]*"scsi-0HC_Volume_\$\{hcloud_volume\.inngest_redis_luks\.id\}"' \
  && ok "the watched alias is built from hcloud_volume.inngest_redis_luks.id, never a literal id" \
  || no "the alias is not derived from the resource id — a re-created volume would silence the rule"

# Anchored on the message leg specifically — a bare `data_mount_devid=<alias> ` needle matches
# BOTH legs now, so a dropped trailing space on either could hide behind the other's copy.
printf '%s' "$LOCAL_SQL" | grep -cF >/dev/null "JSONExtractString(raw, 'message'), 'data_mount_devid=\${local.inngest_luks_wrong_volume_alias} '" \
  && ok "the field is matched WITH its key and a trailing space on leg A (…_1234 is a prefix of …_12345)" \
  || no "the devid match is not key-anchored and space-terminated"

printf '%s' "$LOCAL_SQL" | grep -cE >/dev/null "position\(JSONExtractString\(raw, 'message'\), 'data_mount_devid=[^']*'\) = 0" \
  && ok "the devid predicate is a NEGATION: a row whose field is missing or renamed FIRES" \
  || no "the devid predicate is not '= 0' — a schema change would make this rule go quiet"

printf '%s' "$LOCAL_SQL" | grep -cF >/dev/null "position(JSONExtractString(raw, 'message'), '${INNGEST_PROBE_MARKER}') = 1" \
  && ok "scoped to the probe marker (derived from INNGEST_PROBE_MARKER), anchored at position 1 (not a substring anywhere in the row)" \
  || no "the marker scope is missing or unanchored"

printf '%s' "$LOCAL_SQL" | grep -cF >/dev/null "JSONExtractString(raw, 'SYSLOG_IDENTIFIER') = '${INNGEST_PROBE_EMITTER}'" \
  && ok "scoped to the probe's own emitter (needle derived from INNGEST_PROBE_EMITTER — a coordinated tag rename that misses this SQL goes red, not quiet) — a doppler row merely QUOTING the marker can never count" \
  || no "the emitter conjunct is missing: marker-quoting rows under another SYSLOG_IDENTIFIER would count (#8874)"

# Anchored on the message leg specifically — a bare `host_role=dedicated ` needle matches BOTH
# legs now, so dropping leg A's conjunct would hide behind leg B's `detail` copy (measured:
# the mutation survived while this row was unanchored).
printf '%s' "$LOCAL_SQL" | grep -cF >/dev/null "position(JSONExtractString(raw, 'message'), 'host_role=dedicated ') > 0" \
  && ok "leg A scopes host_role=dedicated on message — the co-located web host emits the same marker" \
  || no "no host_role=dedicated scope on the journald leg: web-1 rows would drive this alert"

# ── Leg B (#11526): the vector-down phone-home fallback ────────────────────────────────────────
# While Vector is down the probe POSTs the identical field row curl-direct to the same source.
# The envelope carries shipper/stage/detail, never SYSLOG_IDENTIFIER and never the position-1
# marker — so leg B pins row identity on the ENVELOPE fields and reads the probe fields out of
# `detail`, the same identity contract the inngest-tls-soak-10136.sh phone-home consumer selects
# on. An unreadable fallback row (identity fields present, detail absent) fails LOUD: the
# negated devid check evaluates position('') = 0 and counts it — the schema-drop class must page,
# never read healthy (the jq-failure payload carries no shipper at all and is recorded as a
# silently-uncounted residual edge, per the CTO's T1 dissent).
printf '%s' "$LOCAL_SQL" | grep -cF >/dev/null "JSONExtractString(raw, 'shipper') = '${MUT_SHIPPER}'" \
  && ok "leg B pins shipper='${MUT_SHIPPER}' — the emitter class of the phone-home envelope, derived from the payload builder" \
  || no "the shipper equality conjunct is missing or pinned to a stale literal: phone-home rows cannot reach leg B"

# The stage literal is a RESERVED token on a shared helper (inngest-boot-phone-home.sh takes
# `stage` as positional $1 at ~16 call sites): a second emit site passing the same stage arg is a
# leg-B identity collision the predicate cannot see — exactly one call site may pass it.
_stage_sites="$(grep -cE '^[^#]*inngest-boot-phone-home\.sh[[:space:]]+inngest-server-probe-vector-down([[:space:]"]|$)' "$REPO/apps/web-platform/infra/inngest-bootstrap.sh" || true)"
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

# The two-leg SHAPE, not just the tokens: two `OR (` groups inside the single grouped predicate
# (the leg-B arm plus its nested detail-check group), the first opened right after leg A's last
# conjunct (next line is the shipper conjunct) and the whole structure closed before
# `GROUP BY time`. "Leg B's tokens exist somewhere in the file" cannot satisfy this while the
# arm that admits them is gone.
_or_open="$(printf '%s' "$LOCAL_SQL" | grep -cE '^[[:space:]]+OR \($' || true)"
_or_next="$(printf '%s' "$LOCAL_SQL" | grep -m1 -A1 -E '^[[:space:]]+OR \($' | tail -1 || true)"
if [ "$_or_open" = "2" ] \
  && printf '%s' "$_or_next" | grep -qF "JSONExtractString(raw, 'shipper') = '${MUT_SHIPPER}'" \
  && [ "$(printf '%s' "$LOCAL_SQL" | tail -5 | head -1)" = "            )" ] \
  && [ "$(printf '%s' "$LOCAL_SQL" | tail -4 | head -1)" = "          )" ] \
  && [ "$(printf '%s' "$LOCAL_SQL" | tail -3 | head -1)" = "        )" ] \
  && [ "$(printf '%s' "$LOCAL_SQL" | tail -2 | head -1)" = "      )" ] \
  && [ "$(printf '%s' "$LOCAL_SQL" | tail -1)" = "    GROUP BY time" ]; then
  ok "the predicate is one grouped (leg-A journald) OR (leg-B phone-home) pair under the shared time filter"
else
  no "the OR-arm structure is broken (OR( lines=${_or_open:-?}) — leg-B tokens outside the arm count nothing"
fi

line_is "$TF" 'paused[[:space:]]*=[[:space:]]*!var\.inngest_luks_cutover_complete' \
  && ok "paused is exactly !var.inngest_luks_cutover_complete on its own line (no suffix, not a comment)" \
  || no "paused is not driven by var.inngest_luks_cutover_complete alone — the arm/disarm route is gone or inverted"

# The variable block, extracted by its opening line and closing brace — not `grep -A4`, whose
# window is one inserted line away from missing `default` and whose bare-token grep was satisfied
# by a commented-out `# default = true` inside it.
VAR_BLOCK="$(awk '/^[[:space:]]*variable "inngest_luks_cutover_complete"[[:space:]]*\{/{f=1} f{print} f&&/^[[:space:]]*\}/{exit}' "$VARS")"
[ -n "$VAR_BLOCK" ] \
  && printf '%s\n' "$VAR_BLOCK" | grep -cE >/dev/null '^[[:space:]]*default[[:space:]]*=[[:space:]]*true[[:space:]]*(#.*)?$' \
  && ok "the arming variable exists and defaults to TRUE (post-cutover, the PLAINTEXT alias is the regression)" \
  || no "variable inngest_luks_cutover_complete is absent or does not default to true"

grep -qE '^[[:space:]]*-target=logtail_exploration\.inngest_luks_wrong_volume \\$' "$WF" \
  && grep -qE '^[[:space:]]*-target=logtail_exploration_alert\.inngest_luks_wrong_volume \\$' "$WF" \
  && ok "both resources are in an apply allowlist (#5566: an untargeted resource is never applied)" \
  || no "one or both -target= lines are missing — the alert would never exist in Better Stack"

line_is "$TF" 'on_missing_data[[:space:]]*=[[:space:]]*"treat_as_zero"' \
  && ok "treat_as_zero is set, so an open incident can observe recovery" \
  || no "on_missing_data is not treat_as_zero"

# The window must cover the emitter's cadence. The probe is HOURLY; a query_period below 3600
# reports "no rows" between emissions, which treat_as_zero reads as healthy — measuring nothing.
QP="$(awk '/resource "logtail_exploration_alert" "inngest_luks_wrong_volume"/,/^}/' "$TF" | grep -oE 'query_period *= *[0-9]+' | grep -oE '[0-9]+')"
RP="$(awk '/resource "logtail_exploration_alert" "inngest_luks_wrong_volume"/,/^}/' "$TF" | grep -oE 'recovery_period *= *[0-9]+' | grep -oE '[0-9]+')"
if [ -n "$QP" ] && [ "$QP" -ge 3600 ] && [ -n "$RP" ] && [ "$RP" -gt "$QP" ]; then
  ok "query_period ${QP}s covers the hourly probe cadence, recovery_period ${RP}s exceeds it"
else
  no "window too narrow for an hourly emitter (query_period=${QP:-?} recovery_period=${RP:-?})"
fi

grep -qF 'inngest-luks-cutover-6894.md' "$TF" \
  && ok "the incident carries a clickable runbook URL (the email is what a reader acts on)" \
  || no "no runbook URL on the incident_cause/metadata"

# ── Mutation rows: each must make the rows above RED ───────────────────────────────────────────
# OUTER RUN ONLY. Each row copies ONE source file into $MUT_DIR, mutates the copy, and re-runs
# this guard with MUT_SKIP=1 and the matching LUKS_GUARD_* override pointing at the copy. The
# inner run reads; it never writes. Nothing here touches a tracked file.
SELF="${BASH_SOURCE[0]}"
if [ -z "${MUT_SKIP:-}" ]; then
  MUT_DIR="$(mktemp -d -t luksalert.XXXXXX)" || { printf '[FATAL] mktemp failed\n' >&2; exit 2; }
  assert_fixture_dir "$MUT_DIR"
  trap 'rm -rf "$MUT_DIR"' EXIT

  # INSTRUMENT CONTROL — the inner run against the PRISTINE tree must exit 0. Without this, a
  # broken inner invocation (a missing $SELF, an inner floor raised past the presence-row count,
  # an unreadable file) exits non-zero on every row, every row grades "mutation RED", and the
  # outer run prints green over a battery that never executed. Measured: SELF=/nonexistent
  # reported 21 passed, 0 failed.
  ctl_rc=0; MUT_SKIP=1 bash "$SELF" >"$MUT_DIR/control.log" 2>&1 || ctl_rc=$?
  if [ "$ctl_rc" -ne 0 ]; then
    printf '[FATAL] instrument control: the inner run exited %s on the PRISTINE tree — the battery cannot be trusted:\n' "$ctl_rc" >&2
    sed 's/^/    /' "$MUT_DIR/control.log" >&2; exit 2
  fi

  mutate_red() {  # mutate_red <label> <TF|VARS|WF> <python-expr-on-s>
    local label="$1" which="$2" prog="$3" src copy rc=0
    case "$which" in
      TF)   src="$TF";   copy="$MUT_DIR/betterstack-logs-alerts.tf" ;;
      VARS) src="$VARS"; copy="$MUT_DIR/variables.tf" ;;
      WF)   src="$WF";   copy="$MUT_DIR/apply-web-platform-infra.yml" ;;
      *) printf '[FATAL] mutate_red: unknown target %s\n' "$which" >&2; exit 2 ;;
    esac
    cp "$src" "$copy" || { printf '[FATAL] mutate_red: cp %s failed\n' "$src" >&2; exit 2; }
    # The python program must land its edit and PROVE it: `assert s != orig` is the minimum, and
    # each row also asserts the specific construct it changed occurs exactly once afterwards.
    python3 - "$copy" <<PY || { no "mutation '$label' did not land (anchor drifted)"; return 0; }
import sys
p = sys.argv[1]
orig = open(p, encoding="utf-8").read()
s = orig
$prog
assert s != orig, "mutation produced no change"
open(p, 'w', encoding="utf-8").write(s)
PY
    case "$which" in
      TF)   LUKS_GUARD_TF="$copy"   MUT_SKIP=1 bash "$SELF" >/dev/null 2>&1 || rc=$? ;;
      VARS) LUKS_GUARD_VARS="$copy" MUT_SKIP=1 bash "$SELF" >/dev/null 2>&1 || rc=$? ;;
      WF)   LUKS_GUARD_WF="$copy"   MUT_SKIP=1 bash "$SELF" >/dev/null 2>&1 || rc=$? ;;
    esac
    # rc DISCRIMINATION. Only rc=1 (an assertion went red) is a caught mutation. rc>=2 is this
    # guard's own FATAL class (unreadable input, floor, instrument), rc=126/127 is a broken
    # invocation — none of those is evidence the row above pins anything, and an earlier form
    # that accepted any non-zero rc as RED is how a dead battery printed green.
    case "$rc" in
      1) ok "mutation RED: $label" ;;
      0) no "mutation SURVIVED: $label — the row above pins nothing" ;;
      *) no "mutation UNRESOLVED (inner rc=$rc, not an assertion): $label — instrument, not evidence" ;;
    esac
  }

  mutate_red "the alias becomes a literal id" TF \
    'old = "scsi-0HC_Volume_${hcloud_volume.inngest_redis_luks.id}"
assert s.count(old) == 1
s = s.replace(old, "scsi-0HC_Volume_106261946")
assert s.count("inngest_luks_wrong_volume_alias = \"scsi-0HC_Volume_106261946\"") == 1'
  # The two devid needles are anchored on the `message` extraction: the bare
  # `data_mount_devid=<alias> ') = 0` now occurs TWICE (leg A `message` AND leg B `detail`),
  # so an unanchored needle would trip the count==1 self-check and FATAL every run.
  mutate_red "the devid match loses its trailing space" TF \
    'old = "JSONExtractString(raw, \x27message\x27), \x27data_mount_devid=${local.inngest_luks_wrong_volume_alias} \x27) = 0"
assert s.count(old) == 1
s = s.replace(old, "JSONExtractString(raw, \x27message\x27), \x27data_mount_devid=${local.inngest_luks_wrong_volume_alias}\x27) = 0")'
  mutate_red "the negation flips to a positive match (fires on the RIGHT volume)" TF \
    'old = "JSONExtractString(raw, \x27message\x27), \x27data_mount_devid=${local.inngest_luks_wrong_volume_alias} \x27) = 0"
assert s.count(old) == 1
s = s.replace(old, "JSONExtractString(raw, \x27message\x27), \x27data_mount_devid=${local.inngest_luks_wrong_volume_alias} \x27) > 0")'
  mutate_red "the host_role scope is dropped (web-1 rows drive the alert)" TF \
    'old = "        AND position(JSONExtractString(raw, \x27message\x27), \x27host_role=dedicated \x27) > 0\n"
assert s.count(old) == 1
s = s.replace(old, "")'
  mutate_red "paused becomes a constant true (armed never)" TF \
    'old = "  paused = !var.inngest_luks_cutover_complete\n"
assert s.count(old) == 1
s = s.replace(old, "  paused = true\n")'
  mutate_red "paused keeps the variable but gains an inverting suffix (|| true)" TF \
    'old = "  paused = !var.inngest_luks_cutover_complete\n"
assert s.count(old) == 1
s = s.replace(old, "  paused = !var.inngest_luks_cutover_complete || true\n")'
  mutate_red "the window shrinks below the probe cadence" TF \
    'old = "  query_period        = 5400\n  confirmation_period = 0\n  recovery_period     = 10800"
assert s.count(old) == 1
s = s.replace(old, "  query_period        = 300\n  confirmation_period = 0\n  recovery_period     = 10800")'
  # Row 8 targets variables.tf: the arming default reverting to false is the silent-disarm this
  # guard now exists to catch — the .tf still reads `paused = !var…`, so every TF-anchored row
  # stays green while the RESOLVED value is `paused = true`. The edit is scoped to the variable
  # BLOCK, not the first `default = true` in the file, so a future aligned boolean declared
  # earlier cannot redirect it.
  mutate_red "the arming default reverts to false (alert silently disarmed)" VARS \
    'import re
m = re.search(r"(variable \"inngest_luks_cutover_complete\"[^{]*\{)(.*?)(\n\})", s, re.S)
assert m, "variable block not found"
block = m.group(2)
assert block.count("default     = true") == 1
s = s[:m.start(2)] + block.replace("default     = true", "default     = false") + s[m.end(2):]'
  # Row 9 is a different AXIS from row 8: the declaration is renamed so `var.inngest_luks_cutover_complete`
  # dangles. The VARS-side existence row catches it; nothing in the TS suite would.
  mutate_red "the variable declaration is renamed (the reference dangles)" VARS \
    'old = "variable \"inngest_luks_cutover_complete\" {"
assert s.count(old) == 1
s = s.replace(old, "variable \"inngest_luks_cutover_compleet\" {")'
  mutate_red "the alert is dropped from the apply allowlist" WF \
    'old = "            -target=logtail_exploration_alert.inngest_luks_wrong_volume \\\n"
assert s.count(old) == 1
s = s.replace(old, "")'
  # #8874 rows — the row set is pinned to the probe's own emitter, so a marker-quoting row under
  # any other SYSLOG_IDENTIFIER can never satisfy the predicate. Three different weakenings; each
  # must redden the presence row above, never just move it. Since #11526 the emitter conjunct is
  # the FIRST line inside the parenthesized group — it carries no leading `AND` and sits at the
  # deeper indent, which is the shape these needles now target.
  mutate_red "the emitter conjunct is dropped (quoting rows count again)" TF \
    'import os
em = os.environ["MUT_EMITTER"]
old = "        JSONExtractString(raw, \x27SYSLOG_IDENTIFIER\x27) = \x27" + em + "\x27\n"
assert s.count(old) == 1
s = s.replace(old, "")'
  mutate_red "the emitter literal flips to doppler (the offender becomes the counted set)" TF \
    'import os
em = os.environ["MUT_EMITTER"]
old = "        JSONExtractString(raw, \x27SYSLOG_IDENTIFIER\x27) = \x27" + em + "\x27"
assert s.count(old) == 1
s = s.replace(old, "        JSONExtractString(raw, \x27SYSLOG_IDENTIFIER\x27) = \x27doppler\x27")'
  mutate_red "the emitter equality weakens to a containment check" TF \
    'import os
em = os.environ["MUT_EMITTER"]
old = "        JSONExtractString(raw, \x27SYSLOG_IDENTIFIER\x27) = \x27" + em + "\x27"
assert s.count(old) == 1
s = s.replace(old, "        position(JSONExtractString(raw, \x27SYSLOG_IDENTIFIER\x27), \x27" + em + "\x27) > 0")'
  mutate_red "the alert is repointed at a different exploration" TF \
    'old = "exploration_id = logtail_exploration.inngest_luks_wrong_volume.id"
assert s.count(old) == 1
s = s.replace(old, "exploration_id = logtail_exploration.monitor_send_failed.id")'

  # #11526 rows — the phone-home fallback arm. Eight weakenings; each must redden a presence row.
  mutate_red "the leg-B shipper conjunct is dropped (any stage's phone-home row counts)" TF \
    'import os
shipper = os.environ["MUT_SHIPPER"]
old = "          JSONExtractString(raw, \x27shipper\x27) = \x27" + shipper + "\x27\n"
assert s.count(old) == 1
s = s.replace(old, "")'
  mutate_red "the leg-B shipper literal flips to a foreign shipper (leg B reads zero rows silently)" TF \
    'import os
shipper = os.environ["MUT_SHIPPER"]
old = "JSONExtractString(raw, \x27shipper\x27) = \x27" + shipper + "\x27"
assert s.count(old) == 1
s = s.replace(old, "JSONExtractString(raw, \x27shipper\x27) = \x27cloud-init-phone-other\x27")'
  mutate_red "the leg-B stage conjunct is dropped (every phone-home row counts)" TF \
    'import os
stage = os.environ["MUT_STAGE"]
old = "          AND JSONExtractString(raw, \x27stage\x27) = \x27" + stage + "\x27\n"
assert s.count(old) == 1
s = s.replace(old, "")'
  mutate_red "the leg-B detail host_role scope is dropped (a web-host fallback row counts)" TF \
    'old = "              position(JSONExtractString(raw, \x27detail\x27), \x27host_role=dedicated \x27) > 0\n"
assert s.count(old) == 1
s = s.replace(old, "")'
  mutate_red "the leg-B stage literal flips to a foreign stage" TF \
    'import os
stage = os.environ["MUT_STAGE"]
old = "JSONExtractString(raw, \x27stage\x27) = \x27" + stage + "\x27"
assert s.count(old) == 1
s = s.replace(old, "JSONExtractString(raw, \x27stage\x27) = \x27inngest-server-probe-other\x27")'
  mutate_red "the leg-B detail devid check flips to a positive match (fires on the RIGHT volume via the fallback)" TF \
    'old = "JSONExtractString(raw, \x27detail\x27), \x27data_mount_devid=${local.inngest_luks_wrong_volume_alias} \x27) = 0"
assert s.count(old) == 1
s = s.replace(old, "JSONExtractString(raw, \x27detail\x27), \x27data_mount_devid=${local.inngest_luks_wrong_volume_alias} \x27) > 0")'
  mutate_red "the detail='' fail-loud disjunct is neutralized (detail-absent rows go quiet again)" TF \
    'old = "JSONExtractString(raw, \x27detail\x27) = \x27\x27"
assert s.count(old) == 1
s = s.replace(old, "false")'
  mutate_red "the whole OR arm is deleted (the #11526 regression — legs collapse to journald-only)" TF \
    'import os
stage = os.environ["MUT_STAGE"]
shipper = os.environ["MUT_SHIPPER"]
old = ("        OR (\n"
       "          JSONExtractString(raw, \x27shipper\x27) = \x27" + shipper + "\x27\n"
       "          AND JSONExtractString(raw, \x27stage\x27) = \x27" + stage + "\x27\n"
       "          AND (\n"
       "            JSONExtractString(raw, \x27detail\x27) = \x27\x27\n"
       "            OR (\n"
       "              position(JSONExtractString(raw, \x27detail\x27), \x27host_role=dedicated \x27) > 0\n"
       "              AND position(JSONExtractString(raw, \x27detail\x27), \x27data_mount_devid=${local.inngest_luks_wrong_volume_alias} \x27) = 0\n"
       "            )\n"
       "          )\n"
       "        )\n")
assert s.count(old) == 1
s = s.replace(old, "")'
fi

# 44 = 22 presence rows + 22 mutation rows. The MUT_SKIP floor is exactly the presence-row count:
# an inner run asserts only those, and the instrument control above is what catches a floor that
# drifts past them (that control, not this comment, is the guard against a dead battery).
_floor=44
[ -n "${MUT_SKIP:-}" ] && _floor=22
_ran=$((pass + fail))
if [ "$_ran" -lt "$_floor" ]; then printf '[FATAL] assertion floor: %s ran, floor %s\n' "$_ran" "$_floor" >&2; exit 1; fi
if [ "${#FAILED[@]}" -ne "$fail" ]; then printf '[FATAL] ledger %s != fail counter %s\n' "${#FAILED[@]}" "$fail" >&2; exit 1; fi
printf '\n=== inngest-luks-wrong-volume-alert: %s passed, %s failed (%s assertions, floor %s) ===\n' "$pass" "$fail" "$_ran" "$_floor"
[ "$fail" -eq 0 ]
