#!/usr/bin/env bash
# A hook suite that cannot run must never report green (#8616).
#
# Editing this checker? Run the Guard Contract rows M1-M13, H1, H1b, H2 and H3 in
# knowledge-base/project/plans/2026-09-24-test-hook-suite-missing-dep-not-green-plan.md.
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
#   A missing tool is the environment's fault, so it is UNRESOLVED; the runner is contracted
#   to supply jq/git/perl/realpath/python3 (ADR-188's ownership axis), so it is never green.
#   A missing file under test is the TREE's fault, so it is a plain FAIL.
#
# HOW EXIT 3 IS SURFACED (measured 2026-09-24, not assumed). `suite_exit_class 3` returns
# `failed`, so `run_suite` prints `[FAIL] <label>` and counts the suite into `failed`; the
# top-level runner then exits 1. `[KILLED] … UNRESOLVED` is only for signal-shaped rc
# 129..192. Upstream, exit 3 therefore NAMES the verdict without changing it: the suite's
# own `UNRESOLVED:` line streams directly above the `[FAIL]`. The number's value is at
# direct invocation, where `bash <suite>; echo $?` separates "could not run" from "an
# assertion failed".
#
# A developer machine without one of these tools now sees `[FAIL]` for the guarded suites.
# That is intended: the hooks themselves call the same tools and are disarmed on that
# machine. Install the tool; do not reach for --no-verify.
#
# ---------------------------------------------------------------------------------------
# WHAT THIS SUITE CHECKS
#
#   1. POPULATION (derived, never listed). Roots are the `.claude/hooks/` entries of
#      `scripts/test-all.sh --print-suite-globs`. Every guard-shaped line —
#      `(if !)? (command -v|which) <tool>` carrying `||` or opening with `if !` — yields one
#      (suite, tool) pair. A guard whose block contains an `exit` is WHOLE-SUITE; one without
#      (an `if … elif` arm, a per-case skip) is ARM-LEVEL. The class is read from the source.
#   2. BEHAVIOUR. Each pair's suite runs on a PATH farm with that one tool removed, with CI
#      and GITHUB_ACTIONS unset (a guard branching on CI would otherwise pass where this
#      suite runs). Required: rc != 0 (exactly 3 for a whole-suite guard) AND a line
#      matching `^\s*UNRESOLVED: <tool> missing`. The line also proves the guard ran BEFORE
#      the suite's first use of the tool — one that dies earlier never prints it.
#   3. STATIC SWEEP. A string literal containing the skip token, on a line that (or whose
#      next statement) exits 0 or bare-exits, is reported. This covers the file-under-test
#      arms and any guard spelling outside (1). Accepted gap: a spelling outside (1) that
#      exits 0 with no skip literal.
#   4. SELF-TEST. Fixtures run through the same functions: two must-RED rows each caught by
#      only one half of the pair check, two must-RED sweep rows, three must-PASS rows. Any
#      wrong verdict exits 2 before a real pair runs.
#
# Bash 3.2 compatible: no mapfile, no declare -A, no ${var,,}; no realpath (it is one of
# the tools under test and is missing before macOS 13).

set -uo pipefail
export TMPDIR="${TMPDIR:-/var/tmp}"

# ADR-129 rule (c): one owning trap, set before anything is allocated or sourced.
ROOT="$(mktemp -d "${TMPDIR}/hook-dep-unresolved.XXXXXXXX")" || {
  printf '[FATAL] mktemp failed\n' >&2; exit 2; }
trap 'rm -rf "$ROOT"' EXIT

SELF_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd -P "$SELF_DIR/../.." && pwd -P)"
SELF="$SELF_DIR/$(basename "${BASH_SOURCE[0]}")"

passes=0
fails=0
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
# derive_pairs <file>... -> "file<TAB>tool<TAB>class" per distinct (file, tool); class is
# `whole` when any guard block for that tool contains an `exit`, else `arm`.
derive_pairs() {
  awk '
    function has_exit(s) { return (s ~ /(^|[^A-Za-z0-9_$])exit([^A-Za-z0-9_]|$)/) }
    { line[FILENAME, FNR] = $0; last[FILENAME] = FNR }
    END {
      for (f in last) {
        for (i = 1; i <= last[f]; i++) {
          s = line[f, i]
          if (s !~ /^[[:space:]]*(if[[:space:]]+![[:space:]]*)?(command[[:space:]]+-v|which)[[:space:]]+[A-Za-z0-9_.+-]+/) continue
          isif = (s ~ /^[[:space:]]*if[[:space:]]+!/)
          if (!isif && index(s, "||") == 0) continue
          t = s
          sub(/^[[:space:]]*(if[[:space:]]+![[:space:]]*)?(command[[:space:]]+-v|which)[[:space:]]+/, "", t)
          match(t, /^[A-Za-z0-9_.+-]+/)
          tool = substr(t, RSTART, RLENGTH)
          whole = 0
          if (isif) {
            for (j = i + 1; j <= last[f]; j++) {
              b = line[f, j]
              if (b ~ /^[[:space:]]*(fi|else|elif)([^A-Za-z0-9_]|$)/) break
              if (has_exit(b)) { whole = 1; break }
            }
          } else {
            rest = substr(s, index(s, "||") + 2)
            if (has_exit(rest)) whole = 1
            else if (index(rest, "{") > 0 && index(rest, "}") == 0) {
              for (j = i + 1; j <= last[f]; j++) {
                b = line[f, j]
                if (has_exit(b)) { whole = 1 }
                if (index(b, "}") > 0) break
              }
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
# whose own line (when it exits at all), else next statement before fi/}/else/elif, exits 0
# or bare-exits. Variable
# references are stripped first: the token must be literal text, not `$SKIPPED`.
scan_skip_exit0() {
  awk -v tok="$SK" '
    function exits0(s) { return (s ~ /(^|[^A-Za-z0-9_$])exit([[:space:]]+0)?[[:space:]]*(;|}|#|$)/) }
    function has_exit(s) { return (s ~ /(^|[^A-Za-z0-9_$])exit([^A-Za-z0-9_]|$)/) }
    { line[FILENAME, FNR] = $0; last[FILENAME] = FNR }
    END {
      for (f in last) {
        for (i = 1; i <= last[f]; i++) {
          s = line[f, i]
          if (s ~ /^[[:space:]]*#/) continue
          t = s
          gsub(/\$\{[^}]*\}/, "", t)
          gsub(/\$[A-Za-z_][A-Za-z0-9_]*/, "", t)
          lit = 0
          while (match(t, /"[^"]*"|\047[^\047]*\047/)) {
            if (index(substr(t, RSTART, RLENGTH), tok) > 0) { lit = 1; break }
            t = substr(t, RSTART + RLENGTH)
          }
          if (!lit) continue
          # An exit on the same line as the literal is the terminating statement. A line
          # that closes its own block (a one-line function or case arm) ends there too.
          # Only an open line is followed to its next statement.
          hit = exits0(s)
          if (!has_exit(s) && index(s, "}") == 0 && index(s, ";;") == 0) {
            for (j = i + 1; j <= last[f]; j++) {
              n = line[f, j]
              if (n ~ /^[[:space:]]*$/) continue
              if (n ~ /^[[:space:]]*(fi|}|else|elif)([^A-Za-z0-9_]|$)/) break
              hit = exits0(n)
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
# The PATH farm: every executable on PATH, first entry wins (ln without -f keeps the first
# link for a name, which is the shell's own resolution order). Only absolute, existing
# directories are linked — a relative entry would leave dangling links that can shadow a
# later directory's real tool.
FARM="$ROOT/farm"
ASIDE="$ROOT/aside"
mkdir -p "$FARM" "$ASIDE" || { printf '[FATAL] cannot create the PATH farm\n' >&2; exit 2; }
build_farm() {
  local d old_ifs="$IFS" path_list="$ROOT/path.list"
  printf '%s\n' "$PATH" | tr ':' '\n' > "$path_list"
  shopt -s nullglob
  while IFS= read -r d; do
    case "$d" in /*) ;; *) continue ;; esac
    [[ -d "$d" ]] || continue
    set -- "$d"/*
    [[ $# -gt 0 ]] || continue
    ln -s "$@" "$FARM"/ 2>/dev/null || true
  done < "$path_list"
  shopt -u nullglob
  IFS="$old_ifs"
}
build_farm
toggle_off() { if [[ -e "$FARM/$1" || -L "$FARM/$1" ]]; then mv "$FARM/$1" "$ASIDE/$1"; fi; }
toggle_on()  { if [[ -e "$ASIDE/$1" || -L "$ASIDE/$1" ]]; then mv "$ASIDE/$1" "$FARM/$1"; fi; }

# check_pair <suite> <tool> <class> <cwd> -> 0 when the pair is not-green AND names its
# cause; 1 otherwise, with the reason in $PAIR_WHY. Output goes to a file, never $(…), so a
# descendant cannot hold a pipe open.
PAIR_WHY=""
check_pair() {
  local suite="$1" tool="$2" class="$3" cwd="$4" out rc=0 lastl
  runs=$((runs + 1))
  out="$ROOT/out.$runs"
  ( cd "$cwd" && env -u CI -u GITHUB_ACTIONS PATH="$FARM" "$BASH" "$suite" </dev/null >"$out" 2>&1 ) || rc=$?
  lastl="$(tail -n 1 "$out" 2>/dev/null | cut -c1-160)"
  if [[ "$rc" -eq 0 ]]; then
    PAIR_WHY="rc=0 (green without $tool); last line: $lastl"
    return 1
  fi
  if [[ "$class" == whole && "$rc" -ne 3 ]]; then
    PAIR_WHY="whole-suite guard rc=$rc, expected 3; last line: $lastl"
    return 1
  fi
  if ! grep -qE "^[[:space:]]*UNRESOLVED: ${tool} missing" "$out"; then
    PAIR_WHY="rc=$rc but no 'UNRESOLVED: $tool missing' line; last line: $lastl"
    return 1
  fi
  PAIR_WHY="rc=$rc"
  return 0
}

# ---------------------------------------------------------------------------------------
# SELF-TEST (ADR-193): the helpers move, then every fixture gets its expected verdict.
pass "instrument: pass() moves"
fail "instrument: fail() moves (expected)"
if [[ "$passes" -ne 1 || "$fails" -ne 1 ]]; then
  printf '[FATAL] instrument self-test: pass()/fail() did not each move once (passes=%s fails=%s)\n' "$passes" "$fails" >&2
  exit 2
fi
passes=0
fails=0

FX="$ROOT/fx"
mkdir -p "$FX" || { printf '[FATAL] cannot create fixture dir\n' >&2; exit 2; }
G="command -v jq >/dev/null 2>&1 ||"
GOOD="$(canonical_line jq)"
E0="exit"; E0="$E0 0"
write_fx() { local name="$1"; shift; printf '%s\n' '#!/usr/bin/env bash' "$@" > "$FX/$name.test.sh"; }
write_fx R-a "$G { echo \"UNRESOLVED: jq missing\"; $E0; }" "$E0"
write_fx R-b "$G { echo \"$SK: jq missing\"; exit 3; }" "$E0"
write_fx R-c "which jq >/dev/null || { echo \"$SK\"; $E0; }" "$E0"
write_fx R-d "$GOOD" "echo \"$SK: x\"; exit"
write_fx P-a 'if ! command -v jq  >/dev/null 2>&1; then' '  echo "UNRESOLVED: jq missing — x"' '    exit 3' 'fi' "$E0"
write_fx P-b "$GOOD" "echo \"$SK: could not read peak RSS\"" 'true'
write_fx P-c "$GOOD" '_skipnote=x' 'echo "$_skipnote"' "$E0"

# name  expected-pair  expected-sweep
selftest_bad=0
toggle_off jq
while read -r name want_pair want_sweep; do
  f="$FX/$name.test.sh"
  derive_pairs "$f" > "$ROOT/fx.pairs"
  n_fx="$(wc -l < "$ROOT/fx.pairs" | tr -d ' ')"
  if [[ "$n_fx" -ne 1 ]]; then
    printf '[FATAL] self-test %s: derived %s pairs, expected exactly 1\n' "$name" "$n_fx" >&2
    selftest_bad=1; continue
  fi
  IFS=$'\t' read -r _f tool class < "$ROOT/fx.pairs"
  got_pair=RED
  if check_pair "$f" "$tool" "$class" "$FX"; then got_pair=PASS; fi
  scan_skip_exit0 "$f" > "$ROOT/fx.sweep"
  got_sweep=PASS
  [[ -s "$ROOT/fx.sweep" ]] && got_sweep=RED
  if [[ "$got_pair" != "$want_pair" || "$got_sweep" != "$want_sweep" ]]; then
    printf '[FATAL] self-test %s: pair=%s (want %s: %s) sweep=%s (want %s)\n' \
      "$name" "$got_pair" "$want_pair" "$PAIR_WHY" "$got_sweep" "$want_sweep" >&2
    selftest_bad=1
  fi
done <<'ROWS'
R-a RED PASS
R-b RED PASS
R-c RED RED
R-d PASS RED
P-a PASS PASS
P-b PASS PASS
P-c PASS PASS
ROWS
toggle_on jq
if [[ "$selftest_bad" -ne 0 ]]; then
  printf '[FATAL] the checker is broken (see above); no real pair was run\n' >&2
  exit 2
fi
echo "self-test: R-a R-b R-c R-d RED as required; P-a P-b P-c PASS"

# ---------------------------------------------------------------------------------------
# REAL POPULATION
GLOBS="$ROOT/globs"
if ! bash "$REPO_ROOT/scripts/test-all.sh" --print-suite-globs > "$GLOBS" 2>&1; then
  printf '[FATAL] scripts/test-all.sh --print-suite-globs failed:\n' >&2
  cat "$GLOBS" >&2
  exit 2
fi
SUITES="$ROOT/suites"
: > "$SUITES"
shopt -s nullglob
while IFS= read -r g; do
  case "$g" in .claude/hooks/*) ;; *) continue ;; esac
  for s in "$REPO_ROOT"/$g; do
    [[ -f "$s" && "$s" != "$SELF" ]] && printf '%s\n' "$s" >> "$SUITES"
  done
done < "$GLOBS"
shopt -u nullglob
if [[ ! -s "$SUITES" ]]; then
  printf '[FATAL] no .claude/hooks/ suites found under the runner globs\n' >&2
  exit 2
fi

PAIRS="$ROOT/pairs"
derive_pairs $(cat "$SUITES") > "$PAIRS"

cut -f2 "$PAIRS" | LC_ALL=C sort -u > "$ROOT/tools"
while IFS= read -r tool; do
  toggle_off "$tool"
  while IFS=$'\t' read -r suite ptool class; do
    [[ "$ptool" == "$tool" ]] || continue
    rel="${suite#"$REPO_ROOT"/}"
    if check_pair "$suite" "$tool" "$class" "$REPO_ROOT"; then
      pass "$rel [$tool, $class] $PAIR_WHY"
    else
      fail "$rel [$tool, $class] $PAIR_WHY"
      printf '       canonical guard: %s\n' "$(canonical_line "$tool")"
    fi
    pairs_checked=$((pairs_checked + 1))
  done < "$PAIRS"
  toggle_on "$tool"
done < "$ROOT/tools"

# STATIC SWEEP over the same population.
scan_skip_exit0 $(cat "$SUITES") > "$ROOT/sweep"
if [[ -s "$ROOT/sweep" ]]; then
  while IFS= read -r hit; do
    fail "static sweep: ${hit#"$REPO_ROOT"/} — a skip that exits 0 reports green having asserted nothing"
  done < "$ROOT/sweep"
else
  pass "static sweep: no skip literal exits 0"
fi

# Anti-vacuity floor (ADR-193): printf + exit, never through pass()/fail(). If you removed a
# guard or a guarded suite on purpose, lower MIN_PAIRS here and say why in the PR.
MIN_PAIRS=40
if [[ "$pairs_checked" -lt "$MIN_PAIRS" ]]; then
  printf '[FATAL] anti-vacuity floor: found %s pairs < MIN_PAIRS=%s. If you deliberately removed a guard or a guarded suite, lower MIN_PAIRS to %s here and say why in the PR; otherwise the population regex or root derivation broke.\n' "$pairs_checked" "$MIN_PAIRS" "$pairs_checked" >&2
  exit 1
fi

echo "=== hook-suite-dep-unresolved: $pairs_checked pairs (floor $MIN_PAIRS), $passes ok, $fails RED ==="
if [[ "$fails" -gt 0 ]]; then
  exit 1
fi
exit 0
