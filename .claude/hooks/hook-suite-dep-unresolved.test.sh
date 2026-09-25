#!/usr/bin/env bash
# A hook suite that cannot run must never report green (#8616).
#
# Editing this checker? Re-run the Guard Contract mutation rows in the #8616 plan
# (knowledge-base/project/plans/*-test-hook-suite-missing-dep-not-green-plan.md, §Guard Contract).
#
# ---------------------------------------------------------------------------------------
# THE TAXONOMY (the single home for it; each converted guard's message is self-describing)
#
#   | condition                                        | exit     | line                                                     |
#   |--------------------------------------------------|----------|----------------------------------------------------------|
#   | a TOOL the whole suite needs is off PATH         | 3        | UNRESOLVED: <tool> missing — this suite asserted nothing; install <tool> |
#   | the FILE UNDER TEST is missing (repo-owned)      | 1        | FAIL: <path> not found — …                               |
#   | one ARM hit a missing tool, other arms ran       | non-zero | UNRESOLVED: <tool> missing — <arm> not run               |
#
#   3 is the repo's name for "not measured, not green" (scripts/test-all.sh §EXIT CONTRACT).
#   A missing tool is the environment's fault, so the verdict is UNRESOLVED; a missing file
#   under test is the tree's fault, so it is a plain FAIL. This extends ADR-188's ownership
#   axis to LOCAL runs of the hook suites (ADR-188 itself mandates a hard fail under CI only;
#   see its #8616 addendum).
#
# HOW EXIT 3 IS SURFACED (measured, not assumed). `suite_exit_class 3` returns `failed`, so
# `run_suite` prints `[FAIL] <label>` and the top-level runner exits 1; `[KILLED] …
# UNRESOLVED` is only for signal-shaped rc 129..192. A leaf suite's rc 3 therefore NAMES the
# cause (its `UNRESOLVED:` line streams directly above the `[FAIL]`) without changing the
# aggregate verdict — deliberately (ADR-177's #8616 addendum). At direct invocation,
# `bash <suite>; echo $?` separates "could not run" from "an assertion failed".
# Install the missing tool; do not reach for --no-verify.
#
# ---------------------------------------------------------------------------------------
# WHAT THIS SUITE PROVES, AND WHAT IT DOES NOT
#
#   Covered: every line-initial `command -v <tool>` / `which <tool>` guard spelled `… ||`,
#   `if ! …` or `if … else …`, in a suite under the `.claude/hooks/` roots of
#   `scripts/test-all.sh --print-suite-globs`, exits non-zero and prints
#   `UNRESOLVED: <tool> missing` when that one tool is removed from PATH — exactly 3 for a
#   whole-suite guard — with the environment reduced to a fixed whitelist, so a guard cannot
#   branch on CI markers. And no string literal carrying the skip token is followed by
#   `exit 0` / `return 0` within one statement.
#
#   Not covered, named: a dependency the suite never guards; a guard spelled any other way
#   (probing the tool by running it, an absolute path, a tool held in a variable, a guard in
#   a SOURCED library — e.g. the gitleaks probe ADR-188 keeps as a local skip); a skip message
#   built without the literal token; a tool that resolves but cannot run.
#
# Bash 3.2 compatible: no mapfile, no declare -A, no ${var,,}; no realpath (it is one of the
# tools under test and is missing before macOS 13).

set -uo pipefail
export TMPDIR="${TMPDIR:-/var/tmp}"

# A run killed by SIGKILL skips its EXIT trap; reap this checker's own stale roots first.
find "$TMPDIR" -maxdepth 1 -type d -name 'hook-dep-unresolved.*' -user "$(id -u)" -mmin +180 \
  -exec rm -rf {} + 2>/dev/null || true

# ADR-129 rule (c): one owning trap, set before anything is allocated or sourced.
ROOT="$(mktemp -d "${TMPDIR}/hook-dep-unresolved.XXXXXXXX")" || {
  printf '[FATAL] mktemp failed\n' >&2; exit 2; }
trap 'rm -rf "$ROOT"' EXIT

SELF_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# Every hook suite redirects incident telemetry (incident-sandbox-coverage.test.sh). This one
# emits nothing itself; each suite it spawns sources the helper too.
. "$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/lib/test-incident-sandbox.sh"
REPO_ROOT="$(cd -P "$SELF_DIR/../.." && pwd -P)"
SELF="$SELF_DIR/$(basename "${BASH_SOURCE[0]}")"

passes=0
fails=0
killed=0
pairs_checked=0
runs=0
pass() { passes=$((passes + 1)); printf '  ok   %s\n' "$1"; }
fail() { fails=$((fails + 1)); printf '  RED  %s\n' "$1"; }

# The skip token, assembled so this file never carries the shape it hunts.
SK="SK"; SK="${SK}IP"

canonical_line() { # <tool>
  printf 'command -v %s >/dev/null 2>&1 || { echo "UNRESOLVED: %s missing — this suite asserted nothing; install %s"; exit 3; }' "$1" "$1" "$1"
}

# ---------------------------------------------------------------------------------------
# derive_pairs <file>... -> "file<TAB>tool<TAB>class" per distinct (file, tool).
#   `… || …`           always `whole`.
#   `if ! …`           `whole` when its own line exits or closes with `fi`, or when its block
#                      ends at `fi`; `arm` only when the block reaches `else`/`elif` with no
#                      `exit`. A guard that prints the line and falls through is therefore held
#                      to rc == 3 rather than reclassified.
#   `if … ; then … else` (positive form) is always `arm`.
# When one (file, tool) carries both classes, `whole` wins.
derive_pairs() {
  awk '
    function has_exit(s) { return (s ~ /(^|[^A-Za-z0-9_$])exit([^A-Za-z0-9_]|$)/) }
    { line[FILENAME, FNR] = $0; last[FILENAME] = FNR }
    END {
      for (f in last) {
        for (i = 1; i <= last[f]; i++) {
          s = line[f, i]
          if (!match(s, /^[[:space:]]*(if[[:space:]]+(![[:space:]]*)?)?(command[[:space:]]+-v|which)[[:space:]]+"?[A-Za-z0-9_][A-Za-z0-9_.+-]*/)) continue
          head = substr(s, RSTART, RLENGTH)
          isif = (head ~ /^[[:space:]]*if[[:space:]]/)
          neg = (head ~ /^[[:space:]]*if[[:space:]]+!/)
          if (!isif && index(s, "||") == 0) continue
          tool = head
          sub(/^.*[[:space:]"]/, "", tool)
          whole = 1
          if (isif && !neg) whole = 0
          else if (neg && !has_exit(s) && s !~ /(^|[;[:space:]])fi([;[:space:]]|$)/) {
            for (j = i + 1; j <= last[f]; j++) {
              b = line[f, j]
              if (has_exit(b)) break
              if (b ~ /^[[:space:]]*(else|elif)([^A-Za-z0-9_]|$)/) { whole = 0; break }
              if (b ~ /^[[:space:]]*fi([^A-Za-z0-9_]|$)/) break
            }
          }
          key = f "\t" tool
          if (!(key in cls) || whole) cls[key] = (whole ? "whole" : "arm")
        }
      }
      for (key in cls) print key "\t" cls[key]
    }
  ' "$@" | LC_ALL=C sort
}

# scan_skip_exit0 <file>... -> "file:line: text" per string literal carrying the skip token
# whose terminating statement exits or returns 0 (or bare). Variable references are stripped
# first — the token must be literal text, not `$SKIPPED` — and every structural test reads
# the stripped text, so a `${…}` in the message cannot pose as a block close. A line that
# exits or returns, or closes its own block (`}`, `;;`), terminates there; otherwise the next
# statement (skipping blank and comment lines) is read, stopping at fi/}/else/elif.
scan_skip_exit0() {
  awk -v tok="$SK" -v sq="'" '
    BEGIN {
      q = "[\"" sq "]?"
      re0 = "(^|[^A-Za-z0-9_$])(exit|return)([[:space:]]+" q "0" q ")?[[:space:]]*(;|}|#|[)]|$)"
      reany = "(^|[^A-Za-z0-9_$])(exit|return)([^A-Za-z0-9_]|$)"
    }
    { line[FILENAME, FNR] = $0; last[FILENAME] = FNR }
    END {
      for (f in last) {
        for (i = 1; i <= last[f]; i++) {
          s = line[f, i]
          if (s ~ /^[[:space:]]*#/) continue
          t = s
          gsub(/\$\{[^}]*\}/, "", t)
          gsub(/\$[A-Za-z_][A-Za-z0-9_]*/, "", t)
          stripped = t
          lit = 0
          while (match(t, "\"[^\"]*\"|" sq "[^" sq "]*" sq)) {
            if (index(substr(t, RSTART, RLENGTH), tok) > 0) { lit = 1; break }
            t = substr(t, RSTART + RLENGTH)
          }
          if (!lit) continue
          hit = (stripped ~ re0)
          if (stripped !~ reany && index(stripped, "}") == 0 && index(stripped, ";;") == 0) {
            for (j = i + 1; j <= last[f]; j++) {
              n = line[f, j]
              if (n ~ /^[[:space:]]*(#|$)/) continue
              if (n ~ /^[[:space:]]*(fi|}|else|elif)([^A-Za-z0-9_]|$)/) break
              hit = (n ~ re0)
              break
            }
          }
          if (hit) print f ":" i ": " s
        }
      }
    }
  ' "$@" | LC_ALL=C sort
}

# ---------------------------------------------------------------------------------------
# The PATH farm: every EXECUTABLE REGULAR FILE on PATH (what the shell's lookup accepts —
# a non-executable `~/.local/bin/env` once shadowed /usr/bin/env here and failed seven cases
# at rc 126), from absolute existing directories only, first entry winning (ln without -f
# keeps the first link for a name, which is the shell's own resolution order).
FARM="$ROOT/farm"
ASIDE="$ROOT/aside"
FX="$ROOT/fx"
mkdir -p "$FARM" "$ASIDE" "$FX" || { printf '[FATAL] cannot create the PATH farm\n' >&2; exit 2; }
build_farm() {
  local d e path_list="$ROOT/path.list"
  local -a exe
  printf '%s\n' "$PATH" | tr ':' '\n' > "$path_list"
  shopt -s nullglob
  while IFS= read -r d; do
    case "$d" in /*) ;; *) continue ;; esac
    [[ -d "$d" ]] || continue
    exe=()
    for e in "$d"/*; do
      [[ -f "$e" && -x "$e" ]] && exe+=("$e")
    done
    # Load-bearing: `ln -s <nothing> "$FARM"/` would create a link in the CWD.
    [[ ${#exe[@]} -gt 0 ]] || continue
    ln -s "${exe[@]}" "$FARM"/ 2>/dev/null || true
  done < "$path_list"
  shopt -u nullglob
}
build_farm
toggle_off() { [[ ! -L "$FARM/$1" ]] || mv "$FARM/$1" "$ASIDE/$1"; }
toggle_on()  { [[ ! -L "$ASIDE/$1" ]] || mv "$ASIDE/$1" "$FARM/$1"; }

# The only environment a suite under test sees. `env -i` rather than `-u CI`: a guard keyed
# on RUNNER_OS, GITHUB_RUN_ID or any CI marker would otherwise pass here and exit 0 in CI.
ENV_KEEP=(HOME="$HOME" TMPDIR="$TMPDIR" LANG="${LANG:-C.UTF-8}" USER="${USER:-}")

# check_pair <suite> <tool> <class> <cwd> -> 0 when the pair is not-green AND names its
# cause; 1 when it is green, has the wrong rc, or does not name the tool; 2 when the suite
# was killed by a signal (UNRESOLVED, ADR-187: the checker did not measure it). Output goes
# to a file, never $(…), so a descendant cannot hold a pipe open.
PAIR_WHY=""
check_pair() {
  local suite="$1" tool="$2" class="$3" cwd="$4" out="$ROOT/out" rc=0 lastl
  runs=$((runs + 1))
  ( cd "$cwd" && env -i "${ENV_KEEP[@]}" PATH="$FARM" "$BASH" "$suite" </dev/null >"$out" 2>&1 ) || rc=$?
  lastl="$(tail -n 1 "$out" 2>/dev/null | cut -c1-160)"
  if [[ "$rc" -gt 128 && "$rc" -le 192 ]]; then
    PAIR_WHY="killed by a signal (rc=$rc) — not measured; last line: $lastl"
    return 2
  fi
  if [[ "$rc" -eq 0 ]]; then
    PAIR_WHY="rc=0 (green without $tool); last line: $lastl"
    return 1
  fi
  if [[ "$class" == whole && "$rc" -ne 3 ]]; then
    PAIR_WHY="whole-suite guard rc=$rc, expected 3; last line: $lastl"
    return 1
  fi
  if ! awk -v want="UNRESOLVED: $tool missing" '{ sub(/^[ \t]+/, "") } index($0, want) == 1 { f = 1 } END { exit !f }' "$out"; then
    PAIR_WHY="rc=$rc but no 'UNRESOLVED: $tool missing' line; last line: $lastl"
    return 1
  fi
  PAIR_WHY="rc=$rc"
  return 0
}

# run_pairs <pairs-file> <cwd> — the ONE loop that turns pairs into verdicts. The self-test
# drives it too, so a verdict misrouted at a call site here is caught before a real pair runs.
run_pairs() {
  local pf="$1" cwd="$2" tool suite ptool class rel rcp
  cut -f2 "$pf" | LC_ALL=C sort -u > "$ROOT/tools.cur"
  while IFS= read -r tool; do
    toggle_off "$tool" || { printf '[FATAL] could not move %s out of the farm\n' "$tool" >&2; exit 2; }
    while IFS=$'\t' read -r suite ptool class; do
      [[ "$ptool" == "$tool" ]] || continue
      rel="${suite#"$REPO_ROOT"/}"
      rcp=0
      check_pair "$suite" "$tool" "$class" "$cwd" || rcp=$?
      case "$rcp" in
        0) pass "$rel [$tool, $class] $PAIR_WHY" ;;
        2) killed=$((killed + 1)); printf '  UNRESOLVED  %s [%s, %s] %s\n' "$rel" "$tool" "$class" "$PAIR_WHY" ;;
        *) fail "$rel [$tool, $class] $PAIR_WHY"
           if [[ "$class" == whole ]]; then
             printf '       canonical guard: %s\n' "$(canonical_line "$tool")"
           else
             printf '       arm guard: print "UNRESOLVED: %s missing — <arm> not run" and exit non-zero\n' "$tool"
           fi ;;
      esac
      pairs_checked=$((pairs_checked + 1))
    done < "$pf"
    toggle_on "$tool" || { printf '[FATAL] could not restore %s to the farm\n' "$tool" >&2; exit 2; }
  done < "$ROOT/tools.cur"
}

# report_sweep <file>... — the ONE place sweep hits become verdicts.
report_sweep() {
  local hit
  scan_skip_exit0 "$@" > "$ROOT/sweep"
  if [[ -s "$ROOT/sweep" ]]; then
    while IFS= read -r hit; do
      fail "static sweep: ${hit#"$REPO_ROOT"/} — a skip that exits 0 reports green having asserted nothing"
    done < "$ROOT/sweep"
  else
    pass "static sweep: no skip literal exits 0"
  fi
}

# ---------------------------------------------------------------------------------------
# SELF-TEST (ADR-193): the helpers move, then every fixture gets its expected tool, class and
# verdicts, then the real loop and sweep reporter are driven over fixtures.
pass "instrument" >/dev/null
fail "instrument" >/dev/null
if [[ "$passes" -ne 1 || "$fails" -ne 1 ]]; then
  printf '[FATAL] instrument self-test: pass()/fail() did not each move once (passes=%s fails=%s)\n' "$passes" "$fails" >&2
  exit 2
fi
passes=0
fails=0

G="command -v jq >/dev/null 2>&1 ||"
GOOD="$(canonical_line jq)"
E0="exit 0"
write_fx() { local name="$1"; shift; printf '%s\n' '#!/usr/bin/env bash' "$@" > "$FX/$name.test.sh"; }
write_fx R-a "$G { echo \"UNRESOLVED: jq missing\"; $E0; }" "$E0"
write_fx R-b "$G { echo \"$SK: jq missing\"; exit 3; }" "$E0"
write_fx R-c "which jq >/dev/null || { echo \"$SK\"; $E0; }" "$E0"
write_fx R-d "$GOOD" "echo \"$SK: x\"; exit"
write_fx R-e "$G { echo \"UNRESOLVED: jq missing\"; exit 1; }" "$E0"
write_fx R-f 'if ! command -v jq >/dev/null 2>&1; then echo "UNRESOLVED: jq missing"; exit 1; fi' 'if true; then :; else :; fi' "$E0"
write_fx S-a "$GOOD" "echo \"$SK: \${X:-x} missing\"" "$E0"
write_fx S-b "$GOOD" "echo \"$SK: x\"" '# a comment between' "$E0"
write_fx S-c "$GOOD" "echo \"$SK: x\"" 'exit "0"'
write_fx P-a 'if ! command -v jq  >/dev/null 2>&1; then' '  echo "UNRESOLVED: jq missing — x"' '    exit 3' 'fi' "$E0"
write_fx P-b "$GOOD" "echo \"$SK: could not read peak RSS\"" 'true'
# shellcheck disable=SC2016  # the fixture must carry the literal variable reference
write_fx P-c "$GOOD" 'echo "$SKIPPED skipped"' "$E0"
write_fx A-a 'if ! command -v jq >/dev/null 2>&1; then' '  echo "UNRESOLVED: jq missing — arm not run"' '  X=1' 'else' '  X=0' 'fi' 'exit 1'
write_fx A-b 'if command -v jq >/dev/null 2>&1; then' '  :' 'else' '  echo "UNRESOLVED: jq missing — arm not run"' 'fi' 'exit 1'

# name  tool class  pair  sweep
selftest_bad=0
toggle_off jq
while read -r name want_tool want_class want_pair want_sweep; do
  f="$FX/$name.test.sh"
  derive_pairs "$f" > "$ROOT/fx.pairs"
  n_fx="$(wc -l < "$ROOT/fx.pairs" | tr -d ' ')"
  if [[ "$n_fx" -ne 1 ]]; then
    printf '[FATAL] self-test %s: derived %s pairs, expected exactly 1\n' "$name" "$n_fx" >&2
    selftest_bad=1; continue
  fi
  IFS=$'\t' read -r _f tool class < "$ROOT/fx.pairs"
  got_pair=RED
  rcp=0
  check_pair "$f" "$tool" "$class" "$FX" || rcp=$?
  [[ "$rcp" -eq 0 ]] && got_pair=PASS
  scan_skip_exit0 "$f" > "$ROOT/fx.sweep"
  got_sweep=PASS
  [[ -s "$ROOT/fx.sweep" ]] && got_sweep=RED
  if [[ "$tool" != "$want_tool" || "$class" != "$want_class" || "$got_pair" != "$want_pair" || "$got_sweep" != "$want_sweep" ]]; then
    printf '[FATAL] self-test %s: tool=%s class=%s pair=%s (%s) sweep=%s; want %s %s %s %s\n' \
      "$name" "$tool" "$class" "$got_pair" "$PAIR_WHY" "$got_sweep" "$want_tool" "$want_class" "$want_pair" "$want_sweep" >&2
    selftest_bad=1
  fi
done <<'ROWS'
R-a jq whole RED  PASS
R-b jq whole RED  PASS
R-c jq whole RED  RED
R-d jq whole PASS RED
R-e jq whole RED  PASS
R-f jq whole RED  PASS
S-a jq whole PASS RED
S-b jq whole PASS RED
S-c jq whole PASS RED
P-a jq whole PASS PASS
P-b jq whole PASS PASS
P-c jq whole PASS PASS
A-a jq arm   PASS PASS
A-b jq arm   PASS PASS
ROWS
toggle_on jq

# The real loop and reporter over two pairs (one RED, one PASS) and two sweep files (one hit):
# exactly two RED verdicts, one ok verdict and two pairs must come out of them.
derive_pairs "$FX/R-a.test.sh" "$FX/P-a.test.sh" > "$ROOT/fx.agg"
p0=$passes f0=$fails
run_pairs "$ROOT/fx.agg" "$FX" >/dev/null
report_sweep "$FX/R-d.test.sh" "$FX/P-b.test.sh" >/dev/null
if [[ $((passes - p0)) -ne 1 || $((fails - f0)) -ne 2 || "$pairs_checked" -ne 2 ]]; then
  printf '[FATAL] self-test: the real loop turned 2 pairs + 1 sweep hit into %s ok / %s RED / %s pairs, want 1 / 2 / 2\n' \
    "$((passes - p0))" "$((fails - f0))" "$pairs_checked" >&2
  selftest_bad=1
fi
passes=0
fails=0
killed=0
pairs_checked=0

if [[ "$selftest_bad" -ne 0 ]]; then
  printf '[FATAL] the checker is broken (see above); no real pair was run\n' >&2
  exit 2
fi
echo "self-test: 14 fixtures and the real loop gave their expected tool, class and verdicts"

# ---------------------------------------------------------------------------------------
# REAL POPULATION
GLOBS="$ROOT/globs"
if ! bash "$REPO_ROOT/scripts/test-all.sh" --print-suite-globs > "$GLOBS" 2> "$ROOT/globs.err"; then
  printf '[FATAL] scripts/test-all.sh --print-suite-globs failed:\n' >&2
  cat "$ROOT/globs.err" >&2
  exit 2
fi
SUITE_LIST=()
shopt -s nullglob
while IFS= read -r g; do
  case "$g" in .claude/hooks/*) ;; *) continue ;; esac
  n_root=0
  for s in "$REPO_ROOT"/$g; do
    [[ -f "$s" ]] || continue
    n_root=$((n_root + 1))
    [[ "$s" != "$SELF" ]] && SUITE_LIST+=("$s")
  done
  if [[ "$n_root" -eq 0 ]]; then
    printf '[FATAL] runner glob %s matched no suite — a root that yields nothing cannot be checked\n' "$g" >&2
    exit 1
  fi
done < "$GLOBS"
shopt -u nullglob
if [[ ${#SUITE_LIST[@]} -eq 0 ]]; then
  printf '[FATAL] no .claude/hooks/ suites found under the runner globs\n' >&2
  exit 2
fi

PAIRS="$ROOT/pairs"
derive_pairs "${SUITE_LIST[@]}" > "$PAIRS"

# The checker holds itself to its own taxonomy: a tool the host lacks cannot be toggled, so
# every pair for it would be blamed for the host. That is UNRESOLVED, not RED.
while IFS= read -r t; do
  if [[ ! -L "$FARM/$t" ]]; then
    echo "UNRESOLVED: $t missing — this suite asserted nothing; install $t"
    exit 3
  fi
done < <(cut -f2 "$PAIRS" | LC_ALL=C sort -u)

runs0=$runs
run_pairs "$PAIRS" "$REPO_ROOT"
report_sweep "${SUITE_LIST[@]}"

# Every counted pair must have been MEASURED: a loop that stops calling check_pair still
# counts pairs, so the floor alone cannot see it.
if [[ $((runs - runs0)) -ne "$pairs_checked" ]]; then
  printf '[FATAL] %s pairs counted but %s suite runs made — the loop stopped measuring\n' "$pairs_checked" "$((runs - runs0))" >&2
  exit 1
fi

# Anti-vacuity floor (ADR-193): printf + exit, never through pass()/fail(). If you removed a
# guard or a guarded suite on purpose, lower MIN_PAIRS here and say why in the PR.
MIN_PAIRS=45
if [[ "$pairs_checked" -lt "$MIN_PAIRS" ]]; then
  printf '[FATAL] anti-vacuity floor: found %s pairs < MIN_PAIRS=%s. If you deliberately removed a guard or a guarded suite, lower MIN_PAIRS to %s here and say why in the PR; otherwise the population regex or root derivation broke.\n' "$pairs_checked" "$MIN_PAIRS" "$pairs_checked" >&2
  exit 1
fi

echo "=== hook-suite-dep-unresolved: $pairs_checked pairs (floor $MIN_PAIRS), $passes ok, $fails RED, $killed unresolved ==="
if [[ "$fails" -gt 0 ]]; then
  exit 1
fi
if [[ "$killed" -gt 0 ]]; then
  exit 3
fi
exit 0
