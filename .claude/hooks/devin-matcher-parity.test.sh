#!/usr/bin/env bash
# Devin hook-matcher PARITY guard — issue #8205.
#
# WHY THIS EXISTS
#
# `.claude/settings.json` is Claude-canonical: its `Bash`/`Write|Edit`/…
# matchers are dead under Devin, whose wire names are lowercase (`exec`,
# `write`, `edit`, … — measured in
# knowledge-base/project/specs/feat-settings-matcher-devin-audit/envelope-capture.md).
# Devin coverage lives in per-harness registries instead: `.devin/config.json`
# (anchored Devin matchers), anchored lowercase twins inside settings.json
# (which Devin also loads), and plugins/soleur/hooks/hooks.json.
#
# This suite pins the contract that keeps the audit honest:
#
#   1. Every hook registration across the three registries — and every
#      permissions rule — carries a disposition row in
#      `.claude/hooks/devin-dispositions.tsv`.
#   2. Every `bind` row is backed by a live `.devin/config.json` entry whose
#      matcher is anchored and regex-EVALUATES true on a real Devin tool name
#      (jq `test()` — never string-compare; `kb-index-merge-driver-registration`
#      precedent).
#   3. Every `covered-by-twin` row is backed by an anchored lowercase matcher
#      in settings.json that fires under Devin.
#   4. No hook is dispatched by two registries for the same Devin tool —
#      cross-registry double-fire is a measured Devin behavior (envelope-
#      capture §3: identical SessionStart command fired once per source).
#   5. `.devin` SessionStart matchers are `""` only — source matchers
#      (`startup`, `resume`, `clear`, `compact`) are all dead under Devin
#      (envelope-capture §3); claiming otherwise is false coverage.
#
# Run via:  bash .claude/hooks/devin-matcher-parity.test.sh
# Auto-discovered by scripts/test-all.sh via the `.claude/hooks/*.test.sh` glob.

set -uo pipefail

# Redirect incident telemetry into a per-suite sandbox (convention: every
# .claude/hooks suite applies this before any case runs).
. "$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/lib/test-incident-sandbox.sh"

HOOKS_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd "$HOOKS_DIR/../.." && pwd -P)"
SETTINGS="$REPO_ROOT/.claude/settings.json"
DEVIN_CFG="$REPO_ROOT/.devin/config.json"
PLUGIN_HOOKS="$REPO_ROOT/plugins/soleur/hooks/hooks.json"
LEDGER="$HOOKS_DIR/devin-dispositions.tsv"

PASS=0; FAIL=0
pass() { echo "  pass: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }

# Devin tool vocabulary measured in the Phase-0 child sessions
# (envelope-capture.md §7). `multi_edit` and `apply_patch` are absent there;
# they are kept out of the firing set deliberately.
DEVIN_TOOLS="exec read write edit glob todo_write get_output ask_user_question run_subagent read_subagent skill"

WORK=""
cleanup() { [[ -n "$WORK" && -d "$WORK" ]] && rm -rf "$WORK"; return 0; }
trap cleanup EXIT INT TERM HUP
WORK="$(mktemp -d -t devinparity.XXXXXXXX)"

# --- helpers ---------------------------------------------------------------

# Extract a canonical repo-relative hook path from a registry command string.
# Three spellings exist across registries:
#   "$CLAUDE_PROJECT_DIR"/.claude/hooks/foo.sh
#   bash "$(git rev-parse --show-toplevel)/.claude/hooks/foo.sh"
#   ${CLAUDE_PLUGIN_ROOT}/hooks/foo.sh          -> plugins/soleur/hooks/foo.sh
#   python3 "<root>/.claude/hooks/foo.py"
canon() {
  local cmd="$1" p
  if printf '%s' "$cmd" | grep -q 'PLUGIN_ROOT'; then
    p="$(printf '%s' "$cmd" | grep -oE 'hooks/[A-Za-z0-9_.-]+\.(sh|py)' | head -1)"
    [[ -n "$p" ]] && printf 'plugins/soleur/%s' "$p" && return 0
  else
    p="$(printf '%s' "$cmd" | grep -oE '(\.claude|plugins/soleur|scripts)/[A-Za-z0-9_./-]+\.(sh|py)' | head -1)"
    [[ -n "$p" ]] && { printf '%s' "$p"; return 0; }
  fi
  return 1
}

# Enumerate a registry's hook registrations as: event<TAB>matcher<TAB>canon-path
enum_registry() { # $1 = json file
  # Empty matchers serialize to an empty TSV field, which collapses under
  # IFS=tab read — emit the two-character sentinel "" instead.
  jq -r '.hooks | to_entries[] | .key as $e | .value[] | ((.matcher // "(none)") | if . == "" then "\"\"" else . end) as $m | .hooks[] | [$e, $m, .command] | @tsv' "$1" \
    | while IFS=$'\t' read -r ev m cmd; do
        p="$(canon "$cmd")" || { echo "FAIL-canon: $cmd" >&2; continue; }
        printf '%s\t%s\t%s\n' "$ev" "$m" "$p"
      done
}

# jq test() driver — regex-evaluate a matcher against a tool name.
matches() { # $1 = matcher regex, $2 = tool name
  # Absent matcher ("(none)") and empty matcher ('""') both fire on EVERY tool
  # under both harnesses — treating either as never-dispatching would let a
  # matcherless PreToolUse entry evade T4 while dispatching everywhere.
  [[ "$1" == "(none)" || "$1" == '""' ]] && return 0
  jq -n --arg t "$2" --arg m "$1" '$t | test($m)' 2>/dev/null | grep -q true
}

# Ledger rows as emitted by grep — comments and blank lines stripped.
ledger_rows() {
  grep -v '^#' "$LEDGER" | grep -v '^[[:space:]]*$'
}

for f in "$SETTINGS" "$DEVIN_CFG" "$PLUGIN_HOOKS" "$LEDGER"; do
  [[ -f "$f" ]] || { echo "FAIL: missing $f" >&2; exit 1; }
done

echo "=== T1: every registry registration + permission rule has a ledger row ==="

enum_registry "$SETTINGS" > "$WORK/settings.tsv"
enum_registry "$DEVIN_CFG" > "$WORK/devin.tsv"
enum_registry "$PLUGIN_HOOKS" > "$WORK/plugin.tsv"

t1_fail=0
while IFS=$'\t' read -r ev m p; do
  if ! ledger_rows | grep -F "claude-settings	$p	$ev	$m	" >/dev/null; then
    echo "  missing ledger row: claude-settings $p $ev $m" >&2; t1_fail=1
  fi
done < "$WORK/settings.tsv"

while IFS=$'\t' read -r ev m p; do
  if ! ledger_rows | grep -F "soleur-plugin	$p	$ev	$m	" >/dev/null; then
    echo "  missing ledger row: soleur-plugin $p $ev $m" >&2; t1_fail=1
  fi
done < "$WORK/plugin.tsv"

# devin-config registrations are accounted for either by their own row or by a
# `bind` row from the hook's home registry (same path + event).
while IFS=$'\t' read -r ev m p; do
  if ! { ledger_rows | grep -F "devin-config	$p	$ev	" >/dev/null \
      || ledger_rows | grep -F "	$p	$ev	" | grep -F '	bind	' >/dev/null; }; then
    echo "  missing ledger row: devin-config $p $ev $m" >&2; t1_fail=1
  fi
done < "$WORK/devin.tsv"

# permissions: every allow/deny rule in settings.json needs a ledger row.
for bucket in allow deny; do
  while IFS= read -r rule; do
    [[ -z "$rule" || "$rule" == null ]] && continue
    if ! ledger_rows | grep -F "claude-permissions	$bucket	$rule	" >/dev/null; then
      echo "  missing ledger row: claude-permissions $bucket $rule" >&2; t1_fail=1
    fi
  done < <(jq -r --arg b "$bucket" '.permissions[$b][]? // empty' "$SETTINGS")
done

# anti-vacuity: the enumeration must actually have found rows. 50 is a floor,
# not a count assertion — ~100 registrations exist today; the floor only
# catches a wholesale enumeration collapse (empty jq output, moved files).
n_reg=$(( $(wc -l < "$WORK/settings.tsv") + $(wc -l < "$WORK/devin.tsv") + $(wc -l < "$WORK/plugin.tsv") ))
[[ $n_reg -ge 50 ]] || { echo "  vacuous: only $n_reg registrations enumerated" >&2; t1_fail=1; }

if [[ $t1_fail -eq 0 ]]; then pass "T1 coverage: all $n_reg registrations + permission rules have ledger rows"; else fail "T1 coverage"; fi

echo "=== T2: every \`bind\` row is backed by an anchored live .devin entry ==="

t2_fail=0
while IFS=$'\t' read -r reg p ev m disp reason rest; do
  [[ "$disp" == "bind" && "$reg" != "claude-permissions" && "$reg" != "devin-config" ]] || continue
  # The intended Devin tool is carried in the reason column as `devin-tool=X`;
  # a bind satisfied by a matcher that never fires on X is the audit's own
  # dead-dispatch class one layer down.
  want_tool="${reason##*devin-tool=}"
  [[ "$want_tool" == "$reason" ]] && want_tool=""
  want_tool="${want_tool%%[^A-Za-z_]*}"
  found=0
  while IFS=$'\t' read -r dev m2 p2; do
    [[ "$dev" == "$ev" && "$p2" == "$p" ]] || continue
    # SessionStart honesty: the .devin matcher must be empty — source matchers
    # are dead under Devin (envelope-capture §3).
    if [[ "$ev" == "SessionStart" ]]; then
      [[ -z "$m2" || "$m2" == "(none)" || "$m2" == '""' ]] && { found=1; break; }
      continue
    fi
    if [[ ! "$m2" =~ ^\^.*\$$ ]]; then
      echo "  unanchored .devin matcher for $p: '$m2'" >&2; t2_fail=1; continue
    fi
    if [[ -n "$want_tool" ]]; then
      matches "$m2" "$want_tool" || { echo "  .devin matcher '$m2' never fires on claimed devin-tool=$want_tool ($p)" >&2; t2_fail=1; continue; }
      found=1; break
    fi
    for t in $DEVIN_TOOLS; do
      matches "$m2" "$t" && { found=1; break; }
    done
    [[ $found -eq 1 ]] && break
  done < "$WORK/devin.tsv"
  [[ $found -eq 1 ]] || { echo "  bind row lacks live .devin entry: $p $ev" >&2; t2_fail=1; }
done < <(ledger_rows)

if [[ $t2_fail -eq 0 ]]; then pass "T2: every bind row resolves to an anchored .devin registration that fires on a real Devin tool"; else fail "T2 bind backing"; fi

echo "=== T3: every \`covered-by-twin\` row is backed by an anchored settings twin ==="

t3_fail=0
while IFS=$'\t' read -r reg p ev m disp reason rest; do
  [[ "$disp" == "covered-by-twin" && "$reg" == "claude-settings" ]] || continue
  found=0
  while IFS=$'\t' read -r sev sm sp; do
    [[ "$sev" == "$ev" && "$sp" == "$p" ]] || continue
    [[ "$sm" =~ ^\^[a-z_]+\$$ ]] || continue
    # The twin must name a real Devin tool — `^x$` regex-matching `x` is
    # trivially true, so the load-bearing check is vocabulary membership.
    tool="${sm#^}"; tool="${tool%\$}"
    [[ " $DEVIN_TOOLS " == *" $tool "* ]] && { found=1; break; }
  done < "$WORK/settings.tsv"
  [[ $found -eq 1 ]] || { echo "  covered-by-twin lacks anchored settings twin: $p $ev" >&2; t3_fail=1; }
done < <(ledger_rows)

if [[ $t3_fail -eq 0 ]]; then pass "T3: every covered-by-twin row has an anchored lowercase twin that fires under Devin"; else fail "T3 twin backing"; fi

echo "=== T4: no cross-registry double-fire for any Devin tool ==="

# Build the dispatch map: for every (event, tool, path), record which registry
# sources would dispatch it under Devin. A path reachable from 2+ distinct
# registries on the same tool double-fires — measured behavior, envelope-
# capture §3. `covered-by-plugin` rows are the single documented exemption:
# the command is registered in both settings.json and hooks.json under Claude
# already, and the plugin registry is its declared Devin carrier (#8155
# merged).
# Bound: cross-REGISTRY only. Two overlapping matcher groups inside one
# registry (e.g. `^edit$` + `^(edit|…)$` in .devin) also double-fire; anchoring
# discipline keeps that from happening today but this arm does not detect it.
: > "$WORK/dispatch.tsv"
for src in settings devin plugin; do
  f="$WORK/$src.tsv"
  while IFS=$'\t' read -r sev sm sp; do
    [[ "$sev" == "PreToolUse" || "$sev" == "PostToolUse" ]] || continue
    for t in $DEVIN_TOOLS; do
      matches "$sm" "$t" && printf '%s\t%s\t%s\t%s\n' "$sev" "$t" "$sp" "$src" >> "$WORK/dispatch.tsv"
    done
  done < "$f"
done

t4_fail=0
sort -u "$WORK/dispatch.tsv" > "$WORK/dispatch.u.tsv"
awk -F'\t' '{k=$1"|"$2"|"$3; cnt[k]++} END {for (k in cnt) if (cnt[k] > 1) print k}' \
  "$WORK/dispatch.u.tsv" > "$WORK/double.tsv"
while IFS='|' read -r ev t p; do
  if ledger_rows | grep -F "	$p	$ev	" | grep -F '	covered-by-plugin	' >/dev/null; then
    continue # documented conditional exemption
  fi
  echo "  double-fire: $p dispatches on '$t' ($ev) from multiple registries" >&2; t4_fail=1
done < "$WORK/double.tsv"

# over-bind spot check: anchored ^write$ must not match todo_write (measured
# over-bind, envelope-capture §1).
matches '^write$' 'todo_write' && { echo "  ^write\$ over-binds todo_write" >&2; t4_fail=1; }

if [[ $t4_fail -eq 0 ]]; then pass "T4: no hook double-dispatches from two registries on any Devin tool; anchoring blocks todo_write over-bind"; else fail "T4 double-fire"; fi

echo "=== T5: .devin SessionStart matchers are empty (source matchers are dead) ==="

t5_fail=0
while IFS=$'\t' read -r ev m p; do
  [[ "$ev" == "SessionStart" ]] || continue
  if [[ -n "$m" && "$m" != "(none)" && "$m" != '""' ]]; then
    echo "  dead SessionStart source matcher in .devin: '$m' ($p)" >&2; t5_fail=1
  fi
done < "$WORK/devin.tsv"
if [[ $t5_fail -eq 0 ]]; then pass "T5: no .devin SessionStart entry claims a dead source matcher"; else fail "T5 SessionStart matcher"; fi

echo "=== T6: ledger hygiene — dispositions + reasons ==="

t6_fail=0
while IFS=$'\t' read -r reg p ev m disp reason rest; do
  case "$disp" in
    bind|covered-by-twin|covered-by-plugin|already-fires|n/a|skip) ;;
    *) echo "  unknown disposition '$disp': $reg $p $ev" >&2; t6_fail=1 ;;
  esac
  case "$disp" in
    skip|n/a) [[ -n "${reason:-}" ]] || { echo "  $disp row missing reason: $reg $p $ev" >&2; t6_fail=1; } ;;
  esac
done < <(ledger_rows)

# must-PASS / must-FAIL controls — prove the validator neither rejects
# everything nor accepts garbage (SpecFlow: a passing guard that can't fail is
# vacuous).
ctl_fail=0
check_row() {
  local disp="$1" reason="$2"
  case "$disp" in
    bind|covered-by-twin|covered-by-plugin|already-fires|n/a|skip) ;;
    *) return 1 ;;
  esac
  case "$disp" in skip|n/a) [[ -n "$reason" ]] || return 1 ;; esac
  return 0
}
check_row "skip" "no-tool" || ctl_fail=1   # non-canonical reason must PASS
check_row "skip" "" && ctl_fail=1          # empty reason must FAIL
check_row "bogus" "x" && ctl_fail=1        # unknown disposition must FAIL
if [[ $ctl_fail -eq 0 && $t6_fail -eq 0 ]]; then pass "T6: dispositions valid, skip/n/a rows carry reasons (controls exercised)"; else fail "T6 ledger hygiene"; fi

echo "=== T7: permissions parity — settings rules ported to .devin syntax ==="
# Direction is settings → .devin only: a .devin-only rule (no Claude analog)
# passes silently. Intentional — the .devin set may legitimately carry
# Devin-specific rules — but documented so a divergence is a choice, not a
# blind spot.

t7_fail=0
while IFS= read -r rule; do
  [[ -z "$rule" ]] && continue
  # Bash(prefix:*) -> Exec(prefix)
  inner="${rule#Bash(}"; inner="${inner%:*}"
  exp="Exec(${inner})"
  jq -e --arg e "$exp" '.permissions.allow | index($e)' "$DEVIN_CFG" >/dev/null \
    || { echo "  missing .devin allow: $exp (from $rule)" >&2; t7_fail=1; }
done < <(jq -r '.permissions.allow[]? | select(startswith("Bash("))' "$SETTINGS")

while IFS= read -r rule; do
  [[ -z "$rule" ]] && continue
  jq -e --arg e "$rule" '.permissions.deny | index($e)' "$DEVIN_CFG" >/dev/null \
    || { echo "  missing .devin deny: $rule" >&2; t7_fail=1; }
done < <(jq -r '.permissions.deny[]? | select(startswith("Read("))' "$SETTINGS")

if [[ $t7_fail -eq 0 ]]; then pass "T7: every settings Bash(...)/Read(...) permission has its .devin analog"; else fail "T7 permissions parity"; fi

echo "=== T8: no SessionStart/Stop cross-registry double-fire ==="

# T4 covers tool events; SessionStart/Stop matchers are event-scoped, not
# tool-scoped, so they need their own arm (plan: the 3-source
# devin-session-start double-registration is permanently unguarded without
# it). Under Devin a SessionStart/Stop registration fires iff its matcher is
# absent or "" — source matchers (startup|resume|…) are measured dead. Same
# canon-path firing from 2+ registries double-dispatches (envelope-capture §3:
# identical SessionStart command fired once per source).
: > "$WORK/lifecycle.tsv"
for src in settings devin plugin; do
  while IFS=$'\t' read -r sev sm sp; do
    [[ "$sev" == "SessionStart" || "$sev" == "Stop" ]] || continue
    [[ "$sm" == "(none)" || "$sm" == '""' ]] || continue
    printf '%s\t%s\t%s\n' "$sev" "$sp" "$src" >> "$WORK/lifecycle.tsv"
  done < "$WORK/$src.tsv"
done

t8_fail=0
sort -u "$WORK/lifecycle.tsv" > "$WORK/lifecycle.u.tsv"
awk -F'\t' '{k=$1"|"$2; cnt[k]++} END {for (k in cnt) if (cnt[k] > 1) print k}' \
  "$WORK/lifecycle.u.tsv" > "$WORK/lifecycle-double.tsv"
while IFS='|' read -r ev p; do
  echo "  lifecycle double-fire: $p ($ev) dispatches from multiple registries" >&2; t8_fail=1
done < "$WORK/lifecycle-double.tsv"

# must-fail control: the awk above must actually flag a duplicated pair.
printf 'Stop\tplugins/soleur/hooks/stop-hook.sh\tdup\nStop\tplugins/soleur/hooks/stop-hook.sh\tdup2\n' \
  | awk -F'\t' '{k=$1"|"$2; cnt[k]++} END {for (k in cnt) if (cnt[k] > 1) print k}' \
  | grep -q 'stop-hook' || { echo "  T8 control: dedup awk failed to flag a known duplicate" >&2; t8_fail=1; }

# Sentinel invariant (review P1): devin-session-start.sh MUST be plugin-bound,
# never .devin-bound — only plugin dispatch exports CLAUDE_PLUGIN_ROOT, and a
# repo-dispatched write records hook_source:"repo", which flips cloud-detect
# to not-local:non-plugin-source on every LOCAL session. Dedup alone cannot
# catch a single-registration .devin binding, so assert placement directly.
grep -F $'SessionStart\t""\tplugins/soleur/hooks/devin-session-start.sh' "$WORK/plugin.tsv" >/dev/null \
  || { echo "  devin-session-start.sh missing plugin '' SessionStart binding" >&2; t8_fail=1; }
if grep -F $'plugins/soleur/hooks/devin-session-start.sh' "$WORK/devin.tsv" | grep -q '^SessionStart'; then
  echo "  devin-session-start.sh is .devin-bound — writes hook_source:repo sentinels, breaking cloud-detect local classification" >&2; t8_fail=1
fi

if [[ $t8_fail -eq 0 ]]; then pass "T8: no SessionStart/Stop hook dispatches from two registries; devin-session-start sentinel stays plugin-sourced"; else fail "T8 lifecycle double-fire"; fi

echo
echo "PASS=$PASS FAIL=$FAIL"
[[ $FAIL -eq 0 ]]
