#!/usr/bin/env bash
# Mutation battery for betterstack-send-failed-alert.test.sh (#8097 Guard 1).
#
# The guard is GREEN the day it lands, as every drift guard is; green says nothing about
# whether it CAN go red. Each row below breaks one invariant on a SANDBOX copy of the guard's
# inputs and requires a RED attributed to the specific [FAIL] string that check prints — a bare
# non-zero exit would credit crashes as detections. Harness rows (H*) prove the guard does not
# over-fire on legitimate edits and that its non-vacuity floor is load-bearing.
#
# Registered in infra-validation.yml next to the guard: an unrun battery is a claim.
#
# Axes this battery edits: the predicate anchors (M1, M6), the needle SET in both directions
# (M2 widens, M4 narrows), the emitter severity (M3a/M3b), the resource identity (M5, M11),
# population GROWTH (M7, M10 add a definer; H4 adds a compliant one), the source-id pin (M8),
# the probe_rev shape (M9), the probe trigger (M11/M12), and the guard's OWN floor (H1a/H1b).
# Axes NOT edited: the guard's assertion helpers themselves (ok()/no() dispatch) and its
# comment-stripper — both inherited verbatim from the parity guard, whose battery covers them.

set -uo pipefail
export TMPDIR="${TMPDIR:-/var/tmp}"

ROOT="$(git rev-parse --show-toplevel)" || exit 2
# Overridable so this battery can be pointed at a deliberately-broken guard copy and PROVED to
# red against it (a guard that has never been shown to fail is not evidence; same seam shape
# as lint-orphan-test-suites.test.sh's LINT_ORPHAN_TARGET_OVERRIDE). CI never sets it.
GUARD="${SFA_GUARD_OVERRIDE:-$ROOT/apps/web-platform/test/infra/betterstack-send-failed-alert.test.sh}"
INFRA="$ROOT/apps/web-platform/infra"
[[ -f "$GUARD" ]] || { echo "FATAL: guard not found at $GUARD" >&2; exit 2; }

# The guard's seams are its INPUT CONTRACT. Every input this battery sandboxes must be reachable
# through one of these four; a fifth read path would let a row pass over a check that never ran.
for seam in GUARD_TF GUARD_SCRIPTS_DIR GUARD_SERVER_TF GUARD_VECTOR_TOML; do
  grep -qE "^${seam}=\"\\\$\{${seam}:-" "$GUARD" || { echo "FATAL: guard lost the $seam seam" >&2; exit 2; }
done
n_default_paths=$(grep -cE '^GUARD_[A-Z_]+="\$\{GUARD_[A-Z_]+:-\$INFRA' "$GUARD")
[[ "$n_default_paths" == "4" ]] || { echo "FATAL: expected 4 seam defaults, found $n_default_paths" >&2; exit 2; }
grep -qF 'SEND_FAILED_ALERT_FLOOR_CHECK' "$GUARD" || { echo "FATAL: floor-check marker line missing from the guard" >&2; exit 2; }

pass=0; fail=0; cases=0
ok() { pass=$((pass + 1)); echo "[ok] $1"; }
no() { fail=$((fail + 1)); echo "[FAIL] $1" >&2; }

SB="$(mktemp -d -t sfa-mut.XXXXXXXX)" || exit 2
PR="$(mktemp -d -t sfa-pristine.XXXXXXXX)" || exit 2
OUT="$(mktemp -t sfa-out.XXXXXXXX)" || exit 2
trap 'rm -rf "$SB" "$PR" "$OUT"' EXIT INT TERM HUP
mkdir -p "$SB/scripts" "$PR/scripts" || exit 2

# Sandbox inputs: the .tf, server.tf, vector.toml, and EVERY non-test infra/*.sh (the guard
# discovers definers by directory walk, so the walk must see the same population).
EMITTERS=()
for f in "$INFRA"/*.sh; do
  b="$(basename "$f")"; [[ "$b" == *.test.sh ]] && continue
  cp "$f" "$SB/scripts/$b" && cp "$f" "$PR/scripts/$b" || exit 2
  EMITTERS+=("$b")
done
for f in betterstack-logs-alerts.tf server.tf vector.toml; do
  cp "$INFRA/$f" "$SB/$f" && cp "$INFRA/$f" "$PR/$f" || exit 2
done
# The four crit units must be in the population or H1a's "delete every call" edits nothing.
for u in disk-monitor.sh resource-monitor.sh container-restart-monitor.sh cron-egress-alarm.sh; do
  [[ -f "$SB/scripts/$u" ]] || { echo "FATAL: $u missing from the sandbox population" >&2; exit 2; }
done

run_guard() { # [guard-path]
  GUARD_TF="$SB/betterstack-logs-alerts.tf" GUARD_SCRIPTS_DIR="$SB/scripts" \
  GUARD_SERVER_TF="$SB/server.tf" GUARD_VECTOR_TOML="$SB/vector.toml" \
    bash "${1:-$GUARD}" >"$OUT" 2>&1
}
restore() {
  local f
  for f in betterstack-logs-alerts.tf server.tf vector.toml; do
    cp "$PR/$f" "$SB/$f" || { echo "FATAL: could not restore $f — run void, not red" >&2; exit 2; }
  done
  rm -f "$SB"/scripts/*.sh
  for f in "${EMITTERS[@]}"; do
    cp "$PR/scripts/$f" "$SB/scripts/$f" || { echo "FATAL: could not restore scripts/$f — run void" >&2; exit 2; }
  done
}
# mutate <relative-file> <python-body operating on `s`>
mutate() {
  local file="$1" script="$2"
  python3 - "$SB/$file" <<PYEOF
import sys
p = sys.argv[1]
s = open(p).read()
$script
open(p, 'w').write(s)
PYEOF
}
landed() { # <relative-file> -> 0 if the sandbox copy differs from pristine
  ! cmp -s "$SB/$1" "$PR/$1"
}

# expect_red <label> <file> <anchor>... -- the mutation script is read from MUT
expect_red() {
  local label="$1" file="$2"; shift 2
  cases=$((cases + 1)); restore
  if ! mutate "$file" "$MUT"; then no "$label: mutator errored (anchor drifted?) — never landed"; restore; return; fi
  if ! landed "$file"; then no "$label: mutation did NOT land ($file byte-identical to pristine)"; restore; return; fi
  if run_guard; then
    no "$label: guard still PASSED with the invariant broken — it cannot detect this"
  else
    local a missing=""
    for a in "$@"; do grep -F '[FAIL]' "$OUT" | grep -qF -- "$a" || missing="$missing | $a"; done
    if [[ -z "$missing" ]]; then ok "$label: guard went RED on '$*'"
    else no "$label: guard went red but NOT via '${missing# | }'. Output: $(<"$OUT")"; fi
  fi
  restore
}
expect_green() {
  local label="$1" file="$2"
  cases=$((cases + 1)); restore
  if ! mutate "$file" "$MUT"; then no "$label: mutator errored"; restore; return; fi
  if ! landed "$file"; then no "$label: control edit did not land — proves nothing"; restore; return; fi
  if run_guard; then ok "$label: guard stayed GREEN (no over-fire)"
  else no "$label: guard went RED on a legitimate edit — it over-fires. Output: $(<"$OUT")"; fi
  restore
}
# add_file <relative-file> <content> (population growth; no pristine counterpart → always "landed")
expect_red_added() {
  local label="$1" file="$2" content="$3"; shift 3
  cases=$((cases + 1)); restore
  printf '%s' "$content" > "$SB/$file" || exit 2
  if run_guard; then no "$label: guard still PASSED with a non-compliant member added"
  else
    local a missing=""
    for a in "$@"; do grep -F '[FAIL]' "$OUT" | grep -qF -- "$a" || missing="$missing | $a"; done
    if [[ -z "$missing" ]]; then ok "$label: guard went RED on '$*'"
    else no "$label: guard went red but NOT via '${missing# | }'. Output: $(<"$OUT")"; fi
  fi
  restore
}
expect_green_added() {
  local label="$1" file="$2" content="$3"
  cases=$((cases + 1)); restore
  printf '%s' "$content" > "$SB/$file" || exit 2
  if run_guard; then ok "$label: guard stayed GREEN (compliant member joined without a suite edit)"
  else no "$label: guard went RED on a compliant member. Output: $(<"$OUT")"; fi
  restore
}

# ── Baseline: the UNMUTATED control must be GREEN or every RED below is meaningless ──────
restore; cases=$((cases + 1))
if run_guard; then ok "baseline: guard is GREEN against the unmutated sandbox"
else no "baseline: guard is RED against the UNMUTATED sandbox; every RED below is meaningless. Output: $(<"$OUT")"
  echo "=== betterstack-send-failed-alert mutation: $pass passed, $fail failed ($cases cases) ===" >&2; exit 1; fi
grep -qE '^=== Summary: [0-9]+ passed, 0 failed \(6 cases\) ===$' "$OUT" \
  && ok "baseline: summary reports 6 cases (the four units' distinct crit markers)" \
  || no "baseline: summary line is not the expected '6 cases' shape: $(grep '=== Summary' "$OUT")"

# ── M1: PRIORITY clause removed ───────────────────────────────────────────────────────
MUT='
old = "      AND JSONExtractString(raw, '"'"'PRIORITY'"'"') = '"'"'2'"'"'\n"
assert s.count(old) == 1, "anchor"
s = s.replace(old, "")'
expect_red "M1 (PRIORITY clause removed)" betterstack-logs-alerts.tf "anchor absent: PRIORITY"

# ── M2: needle set WIDENED with _SEND_ (matches SEND_SKIPPED) ─────────────────────────
MUT='
old = "['"'"'_SEND_FAILED'"'"', '"'"'_REFUSED'"'"']"
assert s.count(old) == 1, "anchor"
s = s.replace(old, "['"'"'_SEND_FAILED'"'"', '"'"'_REFUSED'"'"', '"'"'_SEND_'"'"']")'
expect_red "M2 (needle _SEND_ added)" betterstack-logs-alerts.tf \
  "needle set {_REFUSED,_SEND_,_SEND_FAILED} != {_REFUSED,_SEND_FAILED}" \
  "forbidden match: SOLEUR_CRON_EGRESS_ALARM_SEND_SKIPPED"

# ── M3a: an emitter downgraded from user.crit ─────────────────────────────────────────
MUT='
old = "  logger -p user.crit -t \"$LOG_TAG\" \"$1\""
assert s.count(old) == 1, "anchor"
s = s.replace(old, "  logger -p user.warning -t \"$LOG_TAG\" \"$1\"")'
expect_red "M3a (disk-monitor.sh emit_refusal at user.warning)" scripts/disk-monitor.sh "emitter not crit: disk-monitor.sh"

# ── M3b: the probe line downgraded ────────────────────────────────────────────────────
MUT='
old = "\"logger -p user.crit -t disk-monitor '"'"'SOLEUR_DISK_MONITOR_SEND_FAILED"
assert s.count(old) == 1, "anchor"
s = s.replace(old, "\"logger -p user.warning -t disk-monitor '"'"'SOLEUR_DISK_MONITOR_SEND_FAILED")'
expect_red "M3b (probe line at user.warning)" server.tf "probe line not crit"

# ── M4: needle set NARROWED (_REFUSED dropped) ────────────────────────────────────────
MUT='
old = "['"'"'_SEND_FAILED'"'"', '"'"'_REFUSED'"'"']"
assert s.count(old) == 1, "anchor"
s = s.replace(old, "['"'"'_SEND_FAILED'"'"']")'
expect_red "M4 (needle _REFUSED dropped)" betterstack-logs-alerts.tf \
  "needle set {_SEND_FAILED} != {_REFUSED,_SEND_FAILED}" \
  "crit marker matches no needle: SOLEUR_CONTAINER_RESTART_MONITOR_REFUSED"

# ── M5: the exploration resource renamed ──────────────────────────────────────────────
MUT='
old = "resource \"logtail_exploration\" \"monitor_send_failed\" {"
assert s.count(old) == 1, "anchor"
s = s.replace(old, "resource \"logtail_exploration\" \"monitor_send_failed_v2\" {")'
expect_red "M5 (exploration resource renamed)" betterstack-logs-alerts.tf "sql_query: expected exactly 1 extraction, got 0"

# ── M6: SOLEUR_ prefix clause removed ─────────────────────────────────────────────────
MUT='
old = "      AND startsWith(JSONExtractString(raw, '"'"'message'"'"'), '"'"'SOLEUR_'"'"')\n"
assert s.count(old) == 1, "anchor"
s = s.replace(old, "")'
expect_red "M6 (SOLEUR_ prefix clause removed)" betterstack-logs-alerts.tf "anchor absent: SOLEUR_ prefix"

# ── M7: a fifth definer that logs WITHOUT -p user.crit (population growth, non-compliant) ─
expect_red_added "M7 (foo-monitor.sh logs without -p user.crit)" scripts/foo-monitor.sh \
'#!/usr/bin/env bash
LOG_TAG=foo
emit_refusal() {
  printf "%s\n" "$1"
  logger -t foo "$1"
}
emit_refusal "SOLEUR_FOO_SEND_FAILED channel=resend http_code=000 rc=7"
' "emitter not crit: foo-monitor.sh"

# ── M8: source id no longer the vector.toml sink ──────────────────────────────────────
MUT='
old = "vector_prd_source_id = \"2457081\""
assert s.count(old) == 1, "anchor"
s = s.replace(old, "vector_prd_source_id = \"2457082\"")'
expect_red "M8 (source id 2457082)" betterstack-logs-alerts.tf "source id != vector.toml sink"

# ── M9: probe_rev not digits ──────────────────────────────────────────────────────────
MUT='
old = "monitor_send_failed_probe_rev = \"1\""
assert s.count(old) == 1, "anchor"
s = s.replace(old, "monitor_send_failed_probe_rev = \"1a\"")'
expect_red "M9 (probe_rev = \"1a\")" betterstack-logs-alerts.tf "probe_rev not digits"

# ── M10: a definer that NEVER calls logger and is not allowlisted ─────────────────────
expect_red_added "M10 (baz-monitor.sh emit_refusal never calls logger, not allowlisted)" scripts/baz-monitor.sh \
'#!/usr/bin/env bash
emit_refusal() {
  printf "%s\n" "$1"
}
emit_refusal "SOLEUR_BAZ_MONITOR_SEND_FAILED channel=resend"
' "emitter not crit: baz-monitor.sh"

# ── M11: the probe trigger no longer the rev local ────────────────────────────────────
MUT='
old = "  triggers_replace = local.monitor_send_failed_probe_rev\n"
assert s.count(old) == 1, "anchor"
s = s.replace(old, "  triggers_replace = timestamp()\n")'
expect_red "M11 (probe trigger = timestamp())" server.tf "probe trigger not probe_rev" "probe block carries a per-run value"

# ── M12: the probe marker no longer needle-matched ────────────────────────────────────
MUT='
old = "'"'"'SOLEUR_DISK_MONITOR_SEND_FAILED channel=resend http_code=000 rc=7 synthetic=1"
assert s.count(old) == 1, "anchor"
s = s.replace(old, "'"'"'SOLEUR_DISK_MONITOR_SEND_SKIPPED channel=resend http_code=000 rc=7 synthetic=1")'
expect_red "M12 (probe emits SEND_SKIPPED)" server.tf "probe marker matches no needle"

# ── H1a: every emit_refusal CALL deleted from the four units → floor fires ────────────
h1a_apply() {
  local u
  for u in disk-monitor.sh resource-monitor.sh container-restart-monitor.sh cron-egress-alarm.sh; do
    MUT='
import re
before = s
s = re.sub(r"^[ \t]*emit_refusal \"SOLEUR_[^\n]*\n", "", s, flags=re.M)
assert s != before, "no emit_refusal call lines in this unit"'
    mutate "scripts/$u" "$MUT" || return 1
    landed "scripts/$u" || return 1
  done
}
cases=$((cases + 1)); restore
if h1a_apply; then
  if run_guard; then no "H1a: guard PASSED with zero crit markers — the floor is not load-bearing"
  elif grep -F '[FAIL]' "$OUT" | grep -qF 'markers=0 < floor 6'; then ok "H1a: guard went RED on 'markers=0 < floor 6'"
  else no "H1a: guard went red but not via the floor. Output: $(<"$OUT")"; fi
else no "H1a: mutator could not delete the calls"; fi

# ── H1b: same input, floor REMOVED from a suite copy → GREEN (the vacuity the floor prevents)
cases=$((cases + 1))
NOFLOOR="$(mktemp -t sfa-nofloor.XXXXXXXX)" || exit 2
sed -E 's/^if cases < MIN_CASES: .*SEND_FAILED_ALERT_FLOOR_CHECK$/if False: pass/' "$GUARD" > "$NOFLOOR"
if cmp -s "$NOFLOOR" "$GUARD"; then no "H1b: floor-removal edit did not land on the suite copy"; rm -f "$NOFLOOR"
else
  if run_guard "$NOFLOOR"; then ok "H1b: floor-less suite copy is GREEN over zero markers — recorded as the vacuity the floor prevents"
  else no "H1b: floor-less suite copy still RED — H1a's RED is not attributable to the floor alone. Output: $(<"$OUT")"; fi
  rm -f "$NOFLOOR"
fi
restore

# ── H2: needles reordered → must PASS (set comparison) ────────────────────────────────
MUT='
old = "['"'"'_SEND_FAILED'"'"', '"'"'_REFUSED'"'"']"
assert s.count(old) == 1, "anchor"
s = s.replace(old, "['"'"'_REFUSED'"'"', '"'"'_SEND_FAILED'"'"']")'
expect_green "H2 (needles reordered)" betterstack-logs-alerts.tf

# ── H3: whitespace re-flow of the SQL → must PASS ─────────────────────────────────────
MUT='
old = "      AND JSONExtractString(raw, '"'"'PRIORITY'"'"') = '"'"'2'"'"'\n      AND startsWith(JSONExtractString(raw, '"'"'message'"'"'), '"'"'SOLEUR_'"'"')\n"
assert s.count(old) == 1, "anchor"
s = s.replace(old, "      AND JSONExtractString( raw ,'"'"'PRIORITY'"'"' )='"'"'2'"'"' AND\n        startsWith(JSONExtractString(raw,'"'"'message'"'"'),'"'"'SOLEUR_'"'"')\n")'
expect_green "H3 (SQL whitespace re-flow)" betterstack-logs-alerts.tf

# ── H4: a compliant fifth unit joins without a suite edit → must PASS ─────────────────
expect_green_added "H4 (bar-monitor.sh at user.crit emitting SOLEUR_BAR_SEND_FAILED)" scripts/bar-monitor.sh \
'#!/usr/bin/env bash
LOG_TAG=bar
emit_refusal() {
  printf "%s\n" "$1"
  logger -p user.crit -t "$LOG_TAG" "$1"
}
emit_refusal "SOLEUR_BAR_SEND_FAILED channel=resend http_code=000 rc=7"
emit_refusal "SOLEUR_BAR_SEND_SKIPPED channel=resend reason=unset"
'

# ── Floor on the battery itself ───────────────────────────────────────────────────────
MIN_ROWS=18
if [[ "$cases" -lt "$MIN_ROWS" ]]; then no "battery ran only $cases rows (floor $MIN_ROWS) — rows were skipped"; fi

echo "=== betterstack-send-failed-alert mutation: $pass passed, $fail failed ($cases cases) ==="
[[ "$fail" -eq 0 ]] || exit 1
exit 0
