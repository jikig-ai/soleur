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

line_is "$TF" 'inngest_luks_wrong_volume_alias[[:space:]]*=[[:space:]]*"scsi-0HC_Volume_\$\{hcloud_volume\.inngest_redis_luks\.id\}"' \
  && ok "the watched alias is built from hcloud_volume.inngest_redis_luks.id, never a literal id" \
  || no "the alias is not derived from the resource id — a re-created volume would silence the rule"

printf '%s' "$LOCAL_SQL" | grep -qF "data_mount_devid=\${local.inngest_luks_wrong_volume_alias} " \
  && ok "the field is matched WITH its key and a trailing space (…_1234 is a prefix of …_12345)" \
  || no "the devid match is not key-anchored and space-terminated"

printf '%s' "$LOCAL_SQL" | grep -qE "position\(JSONExtractString\(raw, 'message'\), 'data_mount_devid=[^']*'\) = 0" \
  && ok "the devid predicate is a NEGATION: a row whose field is missing or renamed FIRES" \
  || no "the devid predicate is not '= 0' — a schema change would make this rule go quiet"

printf '%s' "$LOCAL_SQL" | grep -qF "position(JSONExtractString(raw, 'message'), 'SOLEUR_INNGEST_SERVER_PROBE') = 1" \
  && ok "scoped to the probe marker, anchored at position 1 (not a substring anywhere in the row)" \
  || no "the marker scope is missing or unanchored"

printf '%s' "$LOCAL_SQL" | grep -qF "host_role=dedicated " \
  && ok "scoped to host_role=dedicated — the co-located web host emits the same marker" \
  || no "no host_role=dedicated scope: web-1 rows would drive this alert"

line_is "$TF" 'paused[[:space:]]*=[[:space:]]*!var\.inngest_luks_cutover_complete' \
  && ok "paused is exactly !var.inngest_luks_cutover_complete on its own line (no suffix, not a comment)" \
  || no "paused is not driven by var.inngest_luks_cutover_complete alone — the arm/disarm route is gone or inverted"

# The variable block, extracted by its opening line and closing brace — not `grep -A4`, whose
# window is one inserted line away from missing `default` and whose bare-token grep was satisfied
# by a commented-out `# default = true` inside it.
VAR_BLOCK="$(awk '/^[[:space:]]*variable "inngest_luks_cutover_complete"[[:space:]]*\{/{f=1} f{print} f&&/^[[:space:]]*\}/{exit}' "$VARS")"
[ -n "$VAR_BLOCK" ] \
  && printf '%s\n' "$VAR_BLOCK" | grep -qE '^[[:space:]]*default[[:space:]]*=[[:space:]]*true[[:space:]]*(#.*)?$' \
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
  mutate_red "the devid match loses its trailing space" TF \
    'old = "data_mount_devid=${local.inngest_luks_wrong_volume_alias} \x27) = 0"
assert s.count(old) == 1
s = s.replace(old, "data_mount_devid=${local.inngest_luks_wrong_volume_alias}\x27) = 0")'
  mutate_red "the negation flips to a positive match (fires on the RIGHT volume)" TF \
    'old = "inngest_luks_wrong_volume_alias} \x27) = 0"
assert s.count(old) == 1
s = s.replace(old, "inngest_luks_wrong_volume_alias} \x27) > 0")'
  mutate_red "the host_role scope is dropped (web-1 rows drive the alert)" TF \
    'old = "      AND position(JSONExtractString(raw, \x27message\x27), \x27host_role=dedicated \x27) > 0\n"
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
    'old = "  query_period        = 5400"
assert s.count(old) == 1
s = s.replace(old, "  query_period        = 300")'
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
fi

# 23 = 13 presence rows + 10 mutation rows. The MUT_SKIP floor is exactly the presence-row count:
# an inner run asserts only those, and the instrument control above is what catches a floor that
# drifts past them (that control, not this comment, is the guard against a dead battery).
_floor=23
[ -n "${MUT_SKIP:-}" ] && _floor=13
_ran=$((pass + fail))
if [ "$_ran" -lt "$_floor" ]; then printf '[FATAL] assertion floor: %s ran, floor %s\n' "$_ran" "$_floor" >&2; exit 1; fi
if [ "${#FAILED[@]}" -ne "$fail" ]; then printf '[FATAL] ledger %s != fail counter %s\n' "${#FAILED[@]}" "$fail" >&2; exit 1; fi
printf '\n=== inngest-luks-wrong-volume-alert: %s passed, %s failed (%s assertions, floor %s) ===\n' "$pass" "$fail" "$_ran" "$_floor"
[ "$fail" -eq 0 ]
