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
# Axes this battery edits (a battery is bounded by its axes, not its row count):
#   predicate ANCHORS (M1, M6) · needle SET both directions (M2 widens, M4 narrows) ·
#   predicate WIDENING with every anchor still present (G1 AND→OR, G2 NOT, G4 appended OR) ·
#   emitter SEVERITY (M3a definer, M3b probe) · definer SHAPE (M13 `function`, M16 last-wins) ·
#   population GROWTH — non-compliant (M7 no -p, M10 no logger, M15 `<2>` prefix outside a
#   definer) and compliant (H4, H5 `function` form) · ROUTING (M14 allowlisted non-paging marker
#   promoted to crit, M21 needle literal on a crit logger outside emit_refusal, M22 a new
#   unclassified crit class) · IDENTITY pins (M5 rename, M8 source id, M17 values literal, M20
#   exploration_id re-pointed, M9 rev shape, M11 trigger, M12 probe marker) · the direct-ingest
#   PRIORITY key (M18) · the comment STRIPPER in the vacuity direction (M19: a commented-out crit
#   logger must not count) · the guard's OWN floor (H1a RED / H1b GREEN) · the baseline's EXACT
#   pass count (a whole-check deletion is a count change).
# Axes NOT edited: the guard's assertion helpers (`ok()`/`no()` dispatch) — covered by the exact
# baseline count below only insofar as a neutered `no()` changes it; a `no()` rewritten to call
# `ok()` is the one shape this battery cannot see, and is the reason the infra-validation step
# runs the guard itself as well.

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
# through one of these five; a sixth read path would let a row pass over a check that never ran.
for seam in GUARD_TF GUARD_SCRIPTS_DIR GUARD_SERVER_TF GUARD_VECTOR_TOML GUARD_POSTER_DIRS; do
  grep -qE "^${seam}=\"\\\$\{${seam}:-" "$GUARD" || { echo "FATAL: guard lost the $seam seam" >&2; exit 2; }
done
n_default_paths=$(grep -cE '^GUARD_[A-Z_]+="\$\{GUARD_[A-Z_]+:-\$(INFRA|GUARD_SCRIPTS_DIR)' "$GUARD")
[[ "$n_default_paths" == "5" ]] || { echo "FATAL: expected 5 seam defaults, found $n_default_paths" >&2; exit 2; }
grep -qE '^if cases < MIN_CASES: .*SEND_FAILED_ALERT_FLOOR_CHECK$' "$GUARD" || { echo "FATAL: floor-check line missing from the guard" >&2; exit 2; }

pass=0; fail=0; cases=0
ok() { pass=$((pass + 1)); echo "[ok] $1"; }
no() { fail=$((fail + 1)); echo "[FAIL] $1" >&2; }

SB="$(mktemp -d -t sfa-mut.XXXXXXXX)" || exit 2
PR="$(mktemp -d -t sfa-pristine.XXXXXXXX)" || exit 2
OUT="$(mktemp -t sfa-out.XXXXXXXX)" || exit 2
trap 'rm -rf "$SB" "$PR" "$OUT"' EXIT INT TERM HUP
mkdir -p "$SB/scripts" "$PR/scripts" || exit 2

# Sandbox inputs: the .tf, server.tf, vector.toml, and EVERY non-test infra/*.sh + cloud-init*.yml
# (the guard walks the directory, so the walk must see the same population).
EMITTERS=()
for f in "$INFRA"/*.sh "$INFRA"/cloud-init*.yml; do
  b="$(basename "$f")"; [[ "$b" == *.test.sh ]] && continue
  cp "$f" "$SB/scripts/$b" && cp "$f" "$PR/scripts/$b" || exit 2
  EMITTERS+=("$b")
done
for f in betterstack-logs-alerts.tf server.tf vector.toml; do
  cp "$INFRA/$f" "$SB/$f" && cp "$INFRA/$f" "$PR/$f" || exit 2
done
for u in disk-monitor.sh resource-monitor.sh container-restart-monitor.sh cron-egress-alarm.sh inngest-cutover-flip.sh web-private-nic-guard.sh; do
  [[ -f "$SB/scripts/$u" ]] || { echo "FATAL: $u missing from the sandbox population" >&2; exit 2; }
done

run_guard() { # [guard-path]
  GUARD_TF="$SB/betterstack-logs-alerts.tf" GUARD_SCRIPTS_DIR="$SB/scripts" GUARD_POSTER_DIRS="$SB/scripts" \
  GUARD_SERVER_TF="$SB/server.tf" GUARD_VECTOR_TOML="$SB/vector.toml" \
    bash "${1:-$GUARD}" >"$OUT" 2>&1
}
restore() {
  local f
  for f in betterstack-logs-alerts.tf server.tf vector.toml; do
    cp "$PR/$f" "$SB/$f" || { echo "FATAL: could not restore $f — run void, not red" >&2; exit 2; }
  done
  rm -f "$SB"/scripts/*
  for f in "${EMITTERS[@]}"; do
    cp "$PR/scripts/$f" "$SB/scripts/$f" || { echo "FATAL: could not restore scripts/$f — run void" >&2; exit 2; }
  done
}
mutate() { # <relative-file> <python-body operating on `s`>
  local file="$1" script="$2"
  python3 - "$SB/$file" <<PYEOF
import sys
p = sys.argv[1]
s = open(p).read()
$script
open(p, 'w').write(s)
PYEOF
}
landed() { ! cmp -s "$SB/$1" "$PR/$1"; }
attributed() { # <anchor>... -> 0 when every anchor is on a [FAIL] line of $OUT
  local a
  for a in "$@"; do grep -F '[FAIL]' "$OUT" | grep -qF -- "$a" || return 1; done
}

# expect_red <label> <file> <anchor>... -- the mutation script is read from MUT
expect_red() {
  local label="$1" file="$2"; shift 2
  cases=$((cases + 1)); restore
  if ! mutate "$file" "$MUT"; then no "$label: mutator errored (anchor drifted?) — never landed"; restore; return; fi
  if ! landed "$file"; then no "$label: mutation did NOT land ($file byte-identical to pristine)"; restore; return; fi
  if run_guard; then no "$label: guard still PASSED with the invariant broken — it cannot detect this"
  elif attributed "$@"; then ok "$label: guard went RED on '$*'"
  else no "$label: guard went red but NOT via '$*'. Output: $(<"$OUT")"; fi
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
# Population growth: a file with no pristine counterpart is always "landed".
expect_red_added() {
  local label="$1" file="$2" content="$3"; shift 3
  cases=$((cases + 1)); restore
  printf '%s' "$content" > "$SB/$file" || exit 2
  if run_guard; then no "$label: guard still PASSED with a non-compliant member added"
  elif attributed "$@"; then ok "$label: guard went RED on '$*'"
  else no "$label: guard went red but NOT via '$*'. Output: $(<"$OUT")"; fi
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

# ── Baseline: the UNMUTATED control must be GREEN with the EXACT pass count ─────────────────
# (no slack: a whole check deleted from the guard is a count change, and nothing else sees it)
BASELINE_PASSES=58
restore; cases=$((cases + 1))
if run_guard; then ok "baseline: guard is GREEN against the unmutated sandbox"
else no "baseline: guard is RED against the UNMUTATED sandbox; every RED below is meaningless. Output: $(<"$OUT")"
  echo "=== betterstack-send-failed-alert mutation: $pass passed, $fail failed ($cases cases) ===" >&2; exit 1; fi
if grep -qE "^=== Summary: ${BASELINE_PASSES} passed, 0 failed \(6 cases\) ===$" "$OUT"; then ok "baseline: summary is exactly '${BASELINE_PASSES} passed, 0 failed (6 cases)'"
else no "baseline: summary drifted from '${BASELINE_PASSES} passed, 0 failed (6 cases)' — a check was added or deleted; re-pin deliberately: $(grep '=== Summary' "$OUT")"; fi

# ── Predicate anchors ────────────────────────────────────────────────────────────────
MUT='
old = "      AND JSONExtractString(raw, '"'"'PRIORITY'"'"') = '"'"'2'"'"'\n"
assert s.count(old) == 1, "anchor"
s = s.replace(old, "")'
expect_red "M1 (PRIORITY clause removed)" betterstack-logs-alerts.tf "anchor absent: PRIORITY"

MUT='
old = "      AND startsWith(JSONExtractString(raw, '"'"'message'"'"'), '"'"'SOLEUR_'"'"')\n"
assert s.count(old) == 1, "anchor"
s = s.replace(old, "")'
expect_red "M6 (SOLEUR_ prefix clause removed)" betterstack-logs-alerts.tf "anchor absent: SOLEUR_ prefix"

# ── Needle set, both directions ──────────────────────────────────────────────────────
MUT='
old = "['"'"'_SEND_FAILED'"'"', '"'"'_REFUSED'"'"']"
assert s.count(old) == 1, "anchor"
s = s.replace(old, "['"'"'_SEND_FAILED'"'"', '"'"'_REFUSED'"'"', '"'"'_SEND_'"'"']")'
expect_red "M2 (needle _SEND_ added)" betterstack-logs-alerts.tf \
  "needle set {_REFUSED,_SEND_,_SEND_FAILED} != {_REFUSED,_SEND_FAILED}" \
  "forbidden match: SOLEUR_CRON_EGRESS_ALARM_SEND_SKIPPED"

MUT='
old = "['"'"'_SEND_FAILED'"'"', '"'"'_REFUSED'"'"']"
assert s.count(old) == 1, "anchor"
s = s.replace(old, "['"'"'_SEND_FAILED'"'"']")'
expect_red "M4 (needle _REFUSED dropped)" betterstack-logs-alerts.tf \
  "needle set {_SEND_FAILED} != {_REFUSED,_SEND_FAILED}" \
  "crit marker matches no needle: SOLEUR_CONTAINER_RESTART_MONITOR_REFUSED"

# ── Predicate WIDENING with every anchor still present ───────────────────────────────
MUT='
old = "      AND JSONExtractString(raw, '"'"'PRIORITY'"'"') = '"'"'2'"'"'\n"
assert s.count(old) == 1, "anchor"
s = s.replace(old, "      OR JSONExtractString(raw, '"'"'PRIORITY'"'"') = '"'"'2'"'"'\n")'
expect_red "G1 (AND PRIORITY → OR PRIORITY)" betterstack-logs-alerts.tf "predicate widened: OR in WHERE"

MUT='
old = "      AND startsWith("
assert s.count(old) == 1, "anchor"
s = s.replace(old, "      AND NOT startsWith(")'
expect_red "G2 (NOT startsWith)" betterstack-logs-alerts.tf "predicate widened: NOT in WHERE"

MUT='
old = "['"'"'_SEND_FAILED'"'"', '"'"'_REFUSED'"'"'])\n"
assert s.count(old) == 1, "anchor"
s = s.replace(old, old + "      OR multiSearchAny(JSONExtractString(raw, '"'"'message'"'"'), ['"'"'_SEND_SKIPPED'"'"'])\n")'
expect_red "G4 (appended OR multiSearchAny SKIPPED — every anchor still present)" betterstack-logs-alerts.tf \
  "predicate widened: OR in WHERE" "anchor absent: multiSearchAny (expected exactly 1 occurrence, got 2)"

MUT='
old = "      AND multiSearchAny("
assert s.count(old) == 1, "anchor"
s = s.replace(old, "      AND JSONExtractString(raw, '"'"'message'"'"') ILIKE '"'"'%_SEND_%'"'"' AND multiSearchAny(")'
expect_red "G5 (ILIKE wildcard added)" betterstack-logs-alerts.tf "predicate widened: LIKE/ILIKE in WHERE"

# ── Emitter severity ─────────────────────────────────────────────────────────────────
MUT='
old = "  logger -p user.crit -t \"$LOG_TAG\" \"$1\""
assert s.count(old) == 1, "anchor"
s = s.replace(old, "  logger -p user.warning -t \"$LOG_TAG\" \"$1\"")'
expect_red "M3a (disk-monitor.sh emit_refusal at user.warning)" scripts/disk-monitor.sh "emitter not crit: disk-monitor.sh"

MUT='
old = "\"logger -p user.crit -t disk-monitor '"'"'SOLEUR_DISK_MONITOR_SEND_FAILED"
assert s.count(old) == 1, "anchor"
s = s.replace(old, "\"logger -p user.warning -t disk-monitor '"'"'SOLEUR_DISK_MONITOR_SEND_FAILED")'
expect_red "M3b (probe line at user.warning)" server.tf "probe line not crit"

# ── Identity pins ────────────────────────────────────────────────────────────────────
MUT='
old = "resource \"logtail_exploration\" \"monitor_send_failed\" {"
assert s.count(old) == 1, "anchor"
s = s.replace(old, "resource \"logtail_exploration\" \"monitor_send_failed_v2\" {")'
expect_red "M5 (exploration resource renamed)" betterstack-logs-alerts.tf "sql_query: expected exactly 1 extraction, got 0"

MUT='
old = "vector_prd_source_id = \"2457081\""
assert s.count(old) == 1, "anchor"
s = s.replace(old, "vector_prd_source_id = \"2457082\"")'
expect_red "M8 (source id 2457082)" betterstack-logs-alerts.tf "source id != vector.toml sink"

MUT='
old = "    values        = [local.vector_prd_source_id]"
assert s.count(old) == 1, "anchor"
s = s.replace(old, "    values        = [\"2734275\"]")'
expect_red "M17 (exploration values literal, not the pinned local)" betterstack-logs-alerts.tf "exploration source not pinned"

MUT='
old = "  exploration_id = logtail_exploration.monitor_send_failed.id"
assert s.count(old) == 1, "anchor"
s = s.replace(old, "  exploration_id = logtail_exploration.other.id")'
expect_red "M20 (alert exploration_id re-pointed)" betterstack-logs-alerts.tf "alert exploration_id not pinned"

MUT='
old = "monitor_send_failed_probe_rev = \"1\""
assert s.count(old) == 1, "anchor"
s = s.replace(old, "monitor_send_failed_probe_rev = \"1a\"")'
expect_red "M9 (probe_rev = \"1a\")" betterstack-logs-alerts.tf "probe_rev not digits"

MUT='
old = "  triggers_replace = local.monitor_send_failed_probe_rev\n"
assert s.count(old) == 1, "anchor"
s = s.replace(old, "  triggers_replace = timestamp()\n")'
expect_red "M11 (probe trigger = timestamp())" server.tf "probe trigger not probe_rev" "probe block carries a per-run value"

MUT='
old = "'"'"'SOLEUR_DISK_MONITOR_SEND_FAILED channel=resend http_code=000 rc=7 synthetic=1"
assert s.count(old) == 1, "anchor"
s = s.replace(old, "'"'"'SOLEUR_DISK_MONITOR_SEND_SKIPPED channel=resend http_code=000 rc=7 synthetic=1")'
expect_red "M12 (probe emits SEND_SKIPPED)" server.tf "probe marker matches no needle"

# ── Population growth: non-compliant members, every definer shape ────────────────────
expect_red_added "M7 (foo-monitor.sh logs without a crit priority)" scripts/foo-monitor.sh \
'#!/usr/bin/env bash
LOG_TAG=foo
emit_refusal() {
  printf "%s\n" "$1"
  logger -t foo "$1"
}
emit_refusal "SOLEUR_FOO_SEND_FAILED channel=resend http_code=000 rc=7"
' "emitter not crit: foo-monitor.sh"

expect_red_added "M10 (baz-monitor.sh emit_refusal never calls logger, not allowlisted)" scripts/baz-monitor.sh \
'#!/usr/bin/env bash
emit_refusal() {
  printf "%s\n" "$1"
}
emit_refusal "SOLEUR_BAZ_MONITOR_SEND_FAILED channel=resend"
' "emitter not crit: baz-monitor.sh"

expect_red_added "M13 (qux-monitor.sh: function-keyword definer form, no crit)" scripts/qux-monitor.sh \
'#!/usr/bin/env bash
function emit_refusal {
  printf "%s\n" "$1"; logger -t qux "$1"
}
emit_refusal "SOLEUR_QUX_MONITOR_SEND_FAILED channel=resend"
' "emitter not crit: qux-monitor.sh"

expect_red_added "M15 (quux-monitor.sh: <2> SyslogLevelPrefix literal, no definer)" scripts/quux-monitor.sh \
'#!/usr/bin/env bash
printf "<2>SOLEUR_QUUX_MONITOR_REFUSED channel=sentry reason=shape\n" >&2
' "needle marker not routed through emit_refusal: SOLEUR_QUUX_MONITOR_REFUSED (quux-monitor.sh)"

expect_red_added "M23 (lib-monitor.sh calls emit_refusal it never defines — sourced from a lib)" scripts/lib-monitor.sh \
'#!/usr/bin/env bash
. /usr/local/lib/soleur-emit.sh
emit_refusal "SOLEUR_LIB_MONITOR_SEND_FAILED channel=resend"
' "emitter unparseable: lib-monitor.sh mentions emit_refusal but no recognised definition shape"

# ── Definer shape: LAST definition wins ──────────────────────────────────────────────
MUT='
s = s + "\nemit_refusal() {\n  printf \"%s\\n\" \"$1\"\n  logger -t disk-monitor \"$1\"\n}\n"'
expect_red "M16 (second, overriding non-crit emit_refusal appended to disk-monitor.sh)" scripts/disk-monitor.sh "emitter not crit: disk-monitor.sh"

# ── Routing ──────────────────────────────────────────────────────────────────────────
MUT='
old = "logger -t \"$LOG_TAG\" \\\n"
assert s.count(old) >= 1, "anchor"
i = s.index("SOLEUR_INNGEST_CUTOVER_SEAM_REFUSED")
j = s.rfind(old, 0, i)
assert j != -1, "logger before the marker"
s = s[:j] + "logger -p user.crit -t \"$LOG_TAG\" \\\n" + s[j + len(old):]'
expect_red "M14 (allowlisted non-paging _REFUSED promoted to crit in inngest-cutover-flip.sh)" scripts/inngest-cutover-flip.sh \
  "allowlisted non-paging marker emitted at crit: SOLEUR_INNGEST_CUTOVER_SEAM_REFUSED"

MUT='
s = s + "\nlogger -p user.crit -t disk-monitor \"SOLEUR_DISK_MONITOR_REFUSED channel=sentry reason=shape\"\n"'
expect_red "M21 (needle literal on a crit logger outside emit_refusal, in a definer file)" scripts/disk-monitor.sh \
  "needle marker not routed through emit_refusal: SOLEUR_DISK_MONITOR_REFUSED (disk-monitor.sh)"

MUT='
s = s + "\nlogger -p daemon.crit -t disk-monitor '"'"'SOLEUR_DISK_MONITOR_SEND_ERROR channel=resend'"'"'\n"'
expect_red "M22 (new crit class that is neither paging nor never-page, daemon.crit spelling)" scripts/disk-monitor.sh \
  "unclassified crit marker: SOLEUR_DISK_MONITOR_SEND_ERROR (disk-monitor.sh)"

MUT='
s = s + "\nlogger -p 2 -t disk-monitor \"$SOME_MESSAGE\"\n"'
expect_red "M24 (crit logger with a variable message outside emit_refusal, numeric priority)" scripts/disk-monitor.sh \
  "crit logger with a variable message outside emit_refusal: disk-monitor.sh"

# ── Direct-ingest PRIORITY key ───────────────────────────────────────────────────────
MUT='
old = "--data-raw \"{\\\"message\\\":\\\"$LINE\\\"}\""
if s.count(old) != 1:
    old = "{\\\"message\\\":\\\"$LINE\\\"}"
assert s.count(old) >= 1, "anchor: payload shape"
s = s.replace(old, old.replace("\\\"message\\\":", "\\\"PRIORITY\\\":\\\"2\\\",\\\"message\\\":"), 1)'
expect_red "M18 (direct-ingest payload gains a PRIORITY key in web-private-nic-guard.sh)" scripts/web-private-nic-guard.sh \
  "direct-ingest payload carries a PRIORITY field: web-private-nic-guard.sh"

# ── Comment stripper, vacuity direction ──────────────────────────────────────────────
MUT='
old = "  logger -p user.crit -t \"$LOG_TAG\" \"$1\""
assert s.count(old) == 1, "anchor"
s = s.replace(old, "  # " + old.strip())'
expect_red "M19 (the crit logger inside disk-monitor.sh's definer commented out)" scripts/disk-monitor.sh "emitter not crit: disk-monitor.sh"

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
  elif attributed 'markers=0 < floor 6'; then ok "H1a: guard went RED on 'markers=0 < floor 6'"
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

# ── Legitimate edits must stay GREEN ─────────────────────────────────────────────────
MUT='
old = "['"'"'_SEND_FAILED'"'"', '"'"'_REFUSED'"'"']"
assert s.count(old) == 1, "anchor"
s = s.replace(old, "['"'"'_REFUSED'"'"', '"'"'_SEND_FAILED'"'"']")'
expect_green "H2 (needles reordered)" betterstack-logs-alerts.tf

MUT='
old = "      AND JSONExtractString(raw, '"'"'PRIORITY'"'"') = '"'"'2'"'"'\n      AND startsWith(JSONExtractString(raw, '"'"'message'"'"'), '"'"'SOLEUR_'"'"')\n"
assert s.count(old) == 1, "anchor"
s = s.replace(old, "      AND JSONExtractString( raw ,'"'"'PRIORITY'"'"' )='"'"'2'"'"' AND\n        startsWith(JSONExtractString(raw,'"'"'message'"'"'),'"'"'SOLEUR_'"'"')\n")'
expect_green "H3 (SQL whitespace re-flow)" betterstack-logs-alerts.tf

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

expect_green_added "H5 (baz2-monitor.sh: function-keyword definer at crit, indented under an if)" scripts/baz2-monitor.sh \
'#!/usr/bin/env bash
LOG_TAG=baz2
if true; then
  function emit_refusal {
    printf "%s\n" "$1"
    logger --priority user.crit -t "$LOG_TAG" "$1"
  }
fi
emit_refusal "SOLEUR_BAZ2_REFUSED channel=sentry reason=shape"
'

# ── Floor on the battery itself — exact, no slack ────────────────────────────────────
EXPECTED_ROWS=36
if [[ "$cases" -ne "$EXPECTED_ROWS" ]]; then no "battery ran $cases rows, expected exactly $EXPECTED_ROWS — a row was added or skipped; re-pin deliberately"; fi

echo "=== betterstack-send-failed-alert mutation: $pass passed, $fail failed ($cases cases) ==="
[[ "$fail" -eq 0 ]] || exit 1
exit 0
