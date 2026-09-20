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
#   * `paused` is the ONE variable-driven paused state in that file, and it is armed by
#     `var.inngest_luks_cutover_complete`. Before the cutover the plaintext alias is CORRECT, so an
#     armed rule would page continuously and get muted.
#   * Both resources are in the apply workflow's `-target=` allowlist. Without that they are never
#     applied and never exist (the #5566 silent-un-applied class).
#
# Mutation rows live at the bottom: each edits the Terraform and requires THIS guard to red.
set -uo pipefail
export TMPDIR="${TMPDIR:-/var/tmp}"

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$DIR/../../../.." && pwd)"
TF="$REPO/apps/web-platform/infra/betterstack-logs-alerts.tf"
VARS="$REPO/apps/web-platform/infra/variables.tf"
WF="$REPO/.github/workflows/apply-web-platform-infra.yml"

pass=0; fail=0; FAILED=()
ok() { pass=$((pass + 1)); printf '[ok] %s\n' "$1"; }
no() { fail=$((fail + 1)); FAILED+=("$1"); printf '[FAIL] %s\n' "$1"; }

# P1b (#7708) — byte-identical to every other tracked copy; the P1a suite pins that.
# `$(cd X && pwd)` prints an absolute path but yields EMPTY when the cd fails, which would root
# $TF at `/` — and mutate_red() below writes to $TF on every row.
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

for f in "$TF" "$VARS" "$WF"; do
  [ -r "$f" ] || { printf '[FATAL] unreadable: %s\n' "$f" >&2; exit 2; }
done

# The SQL as the provider receives it: the single-line `sql_query` at the resource site.
SQL_LINE="$(grep -n 'inngest_luks_wrong_volume_sql' "$TF" | tail -1)"
LOCAL_SQL="$(awk '/inngest_luks_wrong_volume_sql = <<-SQL/{f=1;next} f&&/^  SQL$/{f=0} f' "$TF")"

[ -n "$LOCAL_SQL" ] \
  && ok "the predicate local is a heredoc this guard can read" \
  || no "inngest_luks_wrong_volume_sql: heredoc not found — every row below would be vacuous"

grep -qF 'sql_query = replace(trimspace(local.inngest_luks_wrong_volume_sql)' "$TF" \
  && ok "the exploration carries THIS predicate, collapsed to one line (the sibling's perpetual-diff rule)" \
  || no "the exploration does not carry local.inngest_luks_wrong_volume_sql"

grep -qF 'inngest_luks_wrong_volume_alias = "scsi-0HC_Volume_${hcloud_volume.inngest_redis_luks.id}"' "$TF" \
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

grep -qF 'paused = !var.inngest_luks_cutover_complete' "$TF" \
  && ok "paused is driven by var.inngest_luks_cutover_complete (armed after a confirmed cutover)" \
  || no "paused is not variable-driven — it would page continuously from merge, and get muted"

grep -qF 'variable "inngest_luks_cutover_complete"' "$VARS" \
  && grep -A4 'variable "inngest_luks_cutover_complete"' "$VARS" | grep -Eq 'default[[:space:]]+= true' \
  && ok "the arming variable exists and defaults to TRUE (post-cutover, the PLAINTEXT alias is the regression)" \
  || no "variable inngest_luks_cutover_complete is absent or does not default to true"

grep -qF '            -target=logtail_exploration.inngest_luks_wrong_volume \' "$WF" \
  && grep -qF '            -target=logtail_exploration_alert.inngest_luks_wrong_volume \' "$WF" \
  && ok "both resources are in the apply allowlist (#5566: an untargeted resource is never applied)" \
  || no "one or both -target= lines are missing — the alert would never exist in Better Stack"

grep -qF 'on_missing_data     = "treat_as_zero"' "$TF" \
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
# OUTER RUN ONLY. Every mutation row re-invokes this file with MUT_SKIP=1 to grade the mutated
# tree; that inner run only asserts, so it needs no scratch dir, no pristine copy and no trap.
# (A restoring trap in the inner run is NOT a stranding hazard, and this was measured rather
# than reasoned: 8 SIGINT-mid-row trials against the unconditional form stranded 0/8, because
# bash defers a trap until its foreground child exits, so the inner trap always runs first and
# its mutated->mutated copy is a no-op before the outer restores the real pristine. Skipping it
# here is a simplification, not a fix.)
if [ -z "${MUT_SKIP:-}" ]; then
  MUT_DIR="$(mktemp -d -t luksalert.XXXXXX)"
  # Take BOTH pristine copies BEFORE arming the trap, and make the trap RESTORE them. The
  # previous form was `trap 'rm -rf "$MUT_DIR"' EXIT` armed before the copies existed: it
  # deleted the only pristine copy and restored nothing, so any interruption mid-row left a
  # MUTATED tracked file in the worktree with its backup already gone. Survivable while the
  # mutator only touched $TF; extending it to $VARS is what makes it dangerous.
  cp "$TF" "$MUT_DIR/pristine.tf"
  cp "$VARS" "$MUT_DIR/pristine.vars.tf"
  trap 'cp -f "$MUT_DIR/pristine.tf" "$TF" 2>/dev/null || true; cp -f "$MUT_DIR/pristine.vars.tf" "$VARS" 2>/dev/null || true; rm -rf "$MUT_DIR"' EXIT INT TERM HUP
fi
SELF="${BASH_SOURCE[0]}"
mutate_red() {  # mutate_red <label> <target-file> <pristine-copy> <python-expr-on-s>
  local label="$1" target="$2" pristine="$3" prog="$4" rc=0
  assert_fixture_dir "$target"   # P1b: every arm writes to $target, whose root is a $(cd … && pwd)
  python3 - "$pristine" "$target" <<PY || { no "mutation '$label' did not land (anchor drifted)"; cp "$pristine" "$target"; return 0; }
import sys
s = open(sys.argv[1]).read()
$prog
open(sys.argv[2], 'w').write(s)
PY
  MUT_SKIP=1 bash "$SELF" >/dev/null 2>&1 || rc=$?
  cp "$pristine" "$target"
  if [ "$rc" -ne 0 ]; then ok "mutation RED: $label"; else no "mutation SURVIVED: $label — the row above pins nothing"; fi
}
if [ -z "${MUT_SKIP:-}" ]; then
  mutate_red "the alias becomes a literal id" "$TF" "$MUT_DIR/pristine.tf" \
    's = s.replace("scsi-0HC_Volume_${hcloud_volume.inngest_redis_luks.id}", "scsi-0HC_Volume_106261946")
assert "106261946" in s'
  mutate_red "the devid match loses its trailing space" "$TF" "$MUT_DIR/pristine.tf" \
    'old = "data_mount_devid=${local.inngest_luks_wrong_volume_alias} \x27) = 0"
assert s.count(old) == 1
s = s.replace(old, "data_mount_devid=${local.inngest_luks_wrong_volume_alias}\x27) = 0")'
  mutate_red "the negation flips to a positive match (fires on the RIGHT volume)" "$TF" "$MUT_DIR/pristine.tf" \
    'old = "inngest_luks_wrong_volume_alias} \x27) = 0"
assert s.count(old) == 1
s = s.replace(old, "inngest_luks_wrong_volume_alias} \x27) > 0")'
  mutate_red "the host_role scope is dropped (web-1 rows drive the alert)" "$TF" "$MUT_DIR/pristine.tf" \
    'old = "      AND position(JSONExtractString(raw, \x27message\x27), \x27host_role=dedicated \x27) > 0\n"
assert s.count(old) == 1
s = s.replace(old, "")'
  mutate_red "paused becomes a constant true (armed never)" "$TF" "$MUT_DIR/pristine.tf" \
    's = s.replace("paused = !var.inngest_luks_cutover_complete", "paused = true")
assert "paused = true" in s'
  mutate_red "the window shrinks below the probe cadence" "$TF" "$MUT_DIR/pristine.tf" \
    'old = "  query_period        = 5400"
assert s.count(old) == 1
s = s.replace(old, "  query_period        = 300")'
  # Row 7 targets $VARS, not $TF, and is the whole reason the mutator became parameterised.
  # The arming default reverting to false is the silent-disarm this guard now exists to catch:
  # the .tf still reads `paused = !var…`, so every $TF-anchored row above stays green while
  # the RESOLVED value is `paused = true` and Better Stack never fires.
  mutate_red "the arming default reverts to false (alert silently disarmed)" "$VARS" "$MUT_DIR/pristine.vars.tf" \
    'old = "  default     = true\n}"
assert s.count(old) >= 1
s = s.replace(old, "  default     = false\n}", 1)'
  mutate_red "paused becomes a constant false (armed unconditionally, variable ignored)" "$TF" "$MUT_DIR/pristine.tf" \
    's = s.replace("paused = !var.inngest_luks_cutover_complete", "paused = false")
assert "paused = false" in s'
fi

# 21 = 19 + the two rows added in #8296 (arming default reverts; paused becomes constant false).
# The MUT_SKIP floor stays 13 DELIBERATELY: an inner run asserts only the non-mutation rows, so
# raising it to 14 makes every inner run exit 1 on this FATAL check, which would make mutate_red
# read RED for every row — including vacuous ones — and print green over a dead battery.
_floor=21
[ -n "${MUT_SKIP:-}" ] && _floor=13
_ran=$((pass + fail))
if [ "$_ran" -lt "$_floor" ]; then printf '[FATAL] assertion floor: %s ran, floor %s\n' "$_ran" "$_floor" >&2; exit 1; fi
if [ "${#FAILED[@]}" -ne "$fail" ]; then printf '[FATAL] ledger %s != fail counter %s\n' "${#FAILED[@]}" "$fail" >&2; exit 1; fi
printf '\n=== inngest-luks-wrong-volume-alert: %s passed, %s failed (%s assertions, floor %s) ===\n' "$pass" "$fail" "$_ran" "$_floor"
[ "$fail" -eq 0 ]
