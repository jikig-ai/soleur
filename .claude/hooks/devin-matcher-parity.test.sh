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
#      (jq `test()` — never string-compare; a matcher that string-compares passes
#      for an exact tool name and silently fails every prefixed variant).
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
  jq -r '(.hooks // {}) | to_entries[] | .key as $e | .value[]? | select(type == "object") | ((.matcher // "(none)") | if . == "" then "\"\"" else . end) as $m | (.hooks // [])[] | [$e, $m, (.command // "(no-command)")] | @tsv' "$1" \
    | while IFS=$'\t' read -r ev m cmd; do
        # canon() extracts the first hook-path token; a compound command whose
        # second hook path differs would execute code the ledger never sees.
        n_paths=$(printf '%s' "$cmd" | grep -oE '(\.claude|plugins/soleur)/hooks/[A-Za-z0-9_./-]+\.(sh|py)|scripts/[A-Za-z0-9_./-]+\.(sh|py)' | sort -u | wc -l)
        if [[ "$n_paths" -gt 1 ]]; then
          printf 'CANONFAIL\t%s\t%s\n' "$ev" "multi-path command (canon sees only the first): $cmd"
          continue
        fi
        p="$(canon "$cmd")" || { printf 'CANONFAIL\t%s\t%s\n' "$ev" "$cmd"; continue; }
        printf '%s\t%s\t%s\n' "$ev" "$m" "$p"
      done
}

# Any CANONFAIL row in an enumerated registry is a hard failure — a command
# spelling canon() can't extract is a registration the audit never sees.
check_canonfail() { # $1 = registry label, $2 = tsv file, $3 = flag var name
  local bad
  bad=$(grep -c '^CANONFAIL' "$2" || true)
  if [[ "$bad" -gt 0 ]]; then
    grep '^CANONFAIL' "$2" | cut -f2- | while IFS= read -r l; do
      echo "  uncanonicalizable $1 command — extend canon() or re-spell: $l" >&2
    done
    printf -v "$3" '%s' 1
  fi
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
check_canonfail "claude-settings" "$WORK/settings.tsv" t1_fail
check_canonfail "devin-config" "$WORK/devin.tsv" t1_fail
check_canonfail "soleur-plugin" "$WORK/plugin.tsv" t1_fail
while IFS=$'\t' read -r ev m p; do
  [[ "$ev" == CANONFAIL ]] && continue
  if ! ledger_rows | grep -F "claude-settings	$p	$ev	$m	" >/dev/null; then
    echo "  missing ledger row in devin-dispositions.tsv: claude-settings $p $ev $m" >&2; t1_fail=1
  fi
done < "$WORK/settings.tsv"

while IFS=$'\t' read -r ev m p; do
  [[ "$ev" == CANONFAIL ]] && continue
  if ! ledger_rows | grep -F "soleur-plugin	$p	$ev	$m	" >/dev/null; then
    echo "  missing ledger row in devin-dispositions.tsv: soleur-plugin $p $ev $m" >&2; t1_fail=1
  fi
done < "$WORK/plugin.tsv"

# devin-config registrations are accounted for either by their own row or by a
# `bind` row from the hook's home registry (same path + event).
while IFS=$'\t' read -r ev m p; do
  [[ "$ev" == CANONFAIL ]] && continue
  if ! { ledger_rows | grep -F "devin-config	$p	$ev	" >/dev/null \
      || ledger_rows | grep -F "	$p	$ev	" | grep -F '	bind	' >/dev/null; }; then
    echo "  missing ledger row in devin-dispositions.tsv: devin-config $p $ev $m" >&2; t1_fail=1
  fi
done < "$WORK/devin.tsv"

# permissions: every allow/deny rule in BOTH registries needs a ledger row —
# a .devin-only Exec() allow is an unaudited auto-approval channel otherwise.
for bucket in allow deny; do
  while IFS= read -r rule; do
    [[ -z "$rule" || "$rule" == null ]] && continue
    if ! ledger_rows | grep -F "claude-permissions	$bucket	$rule	" >/dev/null; then
      echo "  missing ledger row in devin-dispositions.tsv: claude-permissions $bucket $rule" >&2; t1_fail=1
    fi
  done < <(jq -r --arg b "$bucket" '.permissions[$b][]? // empty' "$SETTINGS")
  while IFS= read -r rule; do
    [[ -z "$rule" || "$rule" == null ]] && continue
    if ! ledger_rows | grep -F "devin-permissions	$bucket	$rule	" >/dev/null; then
      echo "  missing ledger row in devin-dispositions.tsv: devin-permissions $bucket $rule" >&2; t1_fail=1
    fi
  done < <(jq -r --arg b "$bucket" '.permissions[$b][]? // empty' "$DEVIN_CFG")
done

# Every enumerated canon path must be a live file — a repointed command
# otherwise passes coverage on a dead target.
while IFS=$'\t' read -r ev m p; do
  [[ "$ev" == CANONFAIL ]] && continue
  [[ -f "$REPO_ROOT/$p" ]] || { echo "  registration points at missing file: $p" >&2; t1_fail=1; }
done < <(cat "$WORK/settings.tsv" "$WORK/devin.tsv" "$WORK/plugin.tsv")

# anti-vacuity: the enumeration must actually have found rows. 50 is a floor,
# not a count assertion — ~100 registrations exist today; the floor only
# catches a wholesale enumeration collapse (empty jq output, moved files).
n_reg=$(( $(wc -l < "$WORK/settings.tsv") + $(wc -l < "$WORK/devin.tsv") + $(wc -l < "$WORK/plugin.tsv") ))
[[ $n_reg -ge 50 ]] || { echo "  vacuous: only $n_reg registrations enumerated" >&2; t1_fail=1; }

if [[ $t1_fail -eq 0 ]]; then pass "T1 coverage: all $n_reg registrations + permission rules have ledger rows"; else fail "T1 coverage"; fi

echo "=== T2: every \`bind\` row is backed by an anchored live .devin entry ==="

t2_fail=0
while IFS=$'\t' read -r reg p ev m disp reason rest; do
  [[ "$disp" == "bind" && "$reg" != "claude-permissions" && "$reg" != "devin-permissions" ]] || continue
  # The intended Devin tool is carried in the reason column as `devin-tool=X`;
  # a bind satisfied by a matcher that never fires on X is the audit's own
  # dead-dispatch class one layer down.
  want_tool="${reason##*devin-tool=}"
  [[ "$want_tool" == "$reason" ]] && want_tool=""
  want_tool="${want_tool%%[^A-Za-z_]*}"
  # Tool-event binds must name their target, and it must be a measured member
  # of the Devin vocabulary — `^bogus$` regex-matching "bogus" is trivially
  # true for a tool that doesn't exist (speculative arms like multi_edit are
  # measured absent: envelope-capture §7).
  if [[ "$ev" == "PreToolUse" || "$ev" == "PostToolUse" ]]; then
    [[ -n "$want_tool" ]] || { echo "  bind row lacks devin-tool= in reason column: $reg $p $ev" >&2; t2_fail=1; continue; }
    [[ " $DEVIN_TOOLS " == *" $want_tool "* ]] || { echo "  devin-tool=$want_tool is not in the measured Devin vocabulary: $p $ev" >&2; t2_fail=1; continue; }
  fi
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
      # A hook may hold several .devin bindings (one per tool class) — a
      # registration that doesn't fire on the claimed tool isn't an error;
      # only absence of ANY matching registration is.
      matches "$m2" "$want_tool" && { found=1; break; }
      continue
    fi
    for t in $DEVIN_TOOLS; do
      matches "$m2" "$t" && { found=1; break; }
    done
    [[ $found -eq 1 ]] && break
  done < "$WORK/devin.tsv"
  [[ $found -eq 1 ]] || { echo "  bind row lacks live .devin entry${want_tool:+ firing on devin-tool=$want_tool}: $p $ev" >&2; t2_fail=1; }
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
# Bound: registration granularity — every registry ROW that would dispatch
# counts, so two overlapping matcher groups inside one registry (e.g.
# `.devin` `^edit$` + `^(edit|…)$`) are caught the same way cross-registry
# overlaps are.
: > "$WORK/dispatch.tsv"
for src in settings devin plugin; do
  f="$WORK/$src.tsv"
  while IFS=$'\t' read -r sev sm sp; do
    [[ "$sev" == "PreToolUse" || "$sev" == "PostToolUse" ]] || continue
    [[ "$sev" == CANONFAIL ]] && continue
    for t in $DEVIN_TOOLS; do
      matches "$sm" "$t" && printf '%s\t%s\t%s\t%s\t%s\n' "$sev" "$t" "$sp" "$src" "$sm" >> "$WORK/dispatch.tsv"
    done
  done < "$f"
done

t4_fail=0
awk -F'\t' '{k=$1"|"$2"|"$3; cnt[k]++} END {for (k in cnt) if (cnt[k] > 1) print k}' \
  "$WORK/dispatch.tsv" > "$WORK/double.tsv"
while IFS='|' read -r ev t p; do
  if ledger_rows | grep -F "	$p	$ev	" | grep -F '	covered-by-plugin	' >/dev/null; then
    continue # documented conditional exemption
  fi
  echo "  double-fire: $p dispatches on '$t' ($ev) from multiple registrations" >&2; t4_fail=1
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
check_row() {
  local disp="$1" reason="$2"
  case "$disp" in
    bind|covered-by-twin|covered-by-plugin|already-fires|n/a|skip) ;;
    *) return 1 ;;
  esac
  case "$disp" in skip|n/a) [[ -n "$reason" ]] || return 1 ;; esac
  return 0
}
# The production loop calls check_row so the must-fail controls below exercise
# the real validator, not a copy that can drift.
while IFS=$'\t' read -r reg p ev m disp reason rest; do
  check_row "$disp" "$reason" || { echo "  invalid disposition/reason: $reg $p $ev $m disp=$disp" >&2; t6_fail=1; }
done < <(ledger_rows)

# must-PASS / must-FAIL controls — prove the validator neither rejects
# everything nor accepts garbage (SpecFlow: a passing guard that can't fail is
# vacuous).
ctl_fail=0
check_row "skip" "no-tool" || ctl_fail=1   # non-canonical reason must PASS
check_row "skip" "" && ctl_fail=1          # empty reason must FAIL
check_row "bogus" "x" && ctl_fail=1        # unknown disposition must FAIL

# TSV arity: IFS=$'\t' read collapses consecutive delimiters, so an empty
# field silently shifts columns. awk with a single-char FS preserves empties.
awk -F'\t' '!/^#/ && NF > 0 && NF != 7 {print FILENAME ":" NR ": " NF " fields"}' "$LEDGER" > "$WORK/arity.txt"
[[ -s "$WORK/arity.txt" ]] && { cat "$WORK/arity.txt" >&2; echo "  ledger rows must have exactly 7 tab-separated fields" >&2; ctl_fail=1; }

if [[ $ctl_fail -eq 0 && $t6_fail -eq 0 ]]; then pass "T6: dispositions valid, skip/n/a rows carry reasons, TSV arity clean (controls exercised)"; else fail "T6 ledger hygiene"; fi

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

echo "=== T9: claimed-coverage rows are backed; bound bodies are kind-normalized; no stale rows ==="

t9_fail=0

# (a) already-fires: the claim "fires under Devin unchanged" is checkable —
# the matcher must be match-all ((none)/""), an mcp__ wire-name (passes
# through verbatim), or regex-fire on a measured Devin tool.
while IFS=$'\t' read -r reg p ev m disp reason rest; do
  [[ "$disp" == "already-fires" ]] || continue
  [[ "$m" == "permission" ]] && continue # permission rows repurpose the columns
  case "$m" in '(none)'|'""'|mcp__*) continue ;; esac
  ok=0
  for t in $DEVIN_TOOLS; do matches "$m" "$t" && { ok=1; break; }; done
  [[ $ok -eq 1 ]] || { echo "  already-fires row has no Devin-live matcher: $reg $p $ev '$m'" >&2; t9_fail=1; }
done < <(ledger_rows)

# (b) covered-by-plugin: a soleur-plugin registration for the same path+event
# must exist and be Devin-live (match-all or fires on a Devin tool).
while IFS=$'\t' read -r reg p ev m disp reason rest; do
  [[ "$disp" == "covered-by-plugin" ]] || continue
  ok=0
  while IFS=$'\t' read -r pev pm pp; do
    [[ "$pev" == "$ev" && "$pp" == "$p" ]] || continue
    case "$pm" in '(none)'|'""') ok=1; break ;; esac
    for t in $DEVIN_TOOLS; do matches "$pm" "$t" && { ok=1; break; }; done
    [[ $ok -eq 1 ]] && break
  done < "$WORK/plugin.tsv"
  [[ $ok -eq 1 ]] || { echo "  covered-by-plugin row lacks a Devin-live plugin registration: $p $ev" >&2; t9_fail=1; }
done < <(ledger_rows)

# (c) reverse arm: every ledger row for an enumerated registry must match a
# live registration — a removed hook otherwise leaves a row reading as
# coverage forever. devin-config rows key on path+event only (matcher column
# informational); permissions and other-harness rows are outside scope.
while IFS=$'\t' read -r reg p ev m disp reason rest; do
  case "$reg" in
    claude-settings) f="$WORK/settings.tsv" ;;
    soleur-plugin)   f="$WORK/plugin.tsv" ;;
    devin-config)    f="$WORK/devin.tsv" ;;
    *) continue ;;
  esac
  if [[ "$reg" == "devin-config" ]]; then
    awk -F'\t' -v ev="$ev" -v p="$p" '$1 == ev && $3 == p {f=1} END{exit !f}' "$f" \
      || { echo "  stale ledger row (no live $reg registration): $p $ev" >&2; t9_fail=1; }
  else
    awk -F'\t' -v ev="$ev" -v m="$m" -v p="$p" '$1 == ev && $2 == m && $3 == p {f=1} END{exit !f}' "$f" \
      || { echo "  stale ledger row (no live $reg registration): $p $ev $m" >&2; t9_fail=1; }
  fi
done < <(ledger_rows)

# (d) body-gate normalization: a hook claiming Devin coverage (bind /
# covered-by-*) must not gate on the RAW tool name against a canonical kind —
# `[ "$HOOK_TOOL_NAME" = "Bash" ]` in a bound hook is exactly the
# fire-then-no-op class one layer down. Lines invoking hook_tool_kind are the
# normalization itself, not a raw gate.
seen_paths=""
while IFS=$'\t' read -r reg p ev m disp reason rest; do
  case "$disp" in bind|covered-by-twin|covered-by-plugin) ;; *) continue ;; esac
  [[ "$p" == *.sh || "$p" == *.py ]] || continue
  case " $seen_paths " in *" $p "*) continue ;; esac
  seen_paths="$seen_paths $p"
  [[ -f "$REPO_ROOT/$p" ]] || continue # T1 reports the missing file itself
  hits=$(grep -nE '\$\{?(HOOK_TOOL_NAME|TOOL_NAME|tool_name|TOOL)\}?["[:space:]]*(!?=|=)["[:space:]]*"?(Bash|Write|Edit|AskUserQuestion|NotebookEdit|MultiEdit|Agent|Task|Skill|Monitor|CronCreate)\b|case +["'"'"']?\$?(HOOK_TOOL_NAME|TOOL_NAME|tool_name|TOOL)\}?["'"'"']? +in' "$REPO_ROOT/$p" \
    | grep -v 'hook_tool_kind' || true)
  [[ -z "$hits" ]] || { echo "  raw-name gate in a Devin-bound hook (use HOOK_TOOL_KIND): $p" >&2; echo "$hits" >&2; t9_fail=1; }
done < <(ledger_rows)

if [[ $t9_fail -eq 0 ]]; then pass "T9: already-fires/covered-by-plugin rows backed; no stale rows; bound bodies kind-normalized"; else fail "T9 claim backing"; fi

echo
echo "PASS=$PASS FAIL=$FAIL"
[[ $FAIL -eq 0 ]]
