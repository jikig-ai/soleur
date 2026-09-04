#!/usr/bin/env bash
# Guard 1 mutation battery — M1-M7 (helper) + H1-H2 (harness).
#
# Contract, per traps this repo has already paid for:
#   * Restore from a PRISTINE COPY, never `git checkout` — checkout restores to HEAD, a different
#     thing from "what I had a moment ago" when a fix is in flight.
#   * A GREEN unmutated control runs FIRST. A red baseline voids every row.
#   * Each mutation is asserted to have LANDED (diff vs pristine). A mutation that does not land
#     reports the BASELINE, which is indistinguishable from a pass.
#   * Setup failures abort (exit 2). A harness that cannot copy a file must not go on to render a
#     confident verdict about the SUT.
#   * Mutators live in FILES, not inline strings: a python body quoted inside a bash single-quoted
#     string breaks on its own apostrophes, and the failure mode is a mutator that silently does
#     nothing — i.e. a row that reports the baseline as a pass.
export TMPDIR="${TMPDIR:-/var/tmp}"
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
case "$SCRIPT_DIR" in
  ""|/|//|/.) printf 'FATAL: SCRIPT_DIR degenerate (%s); refusing\n' "$SCRIPT_DIR" >&2; exit 2 ;;
  /*) : ;;
  *) printf 'FATAL: SCRIPT_DIR is relative; refusing\n' >&2; exit 2 ;;
esac
readonly SCRIPT_DIR
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)" || exit 2
readonly REPO_ROOT

HELPER="$SCRIPT_DIR/lib/git-fixture-env.ts"
SUITE="$SCRIPT_DIR/git-fixture-env.test.ts"
[[ -f "$HELPER" ]] || { printf 'FATAL: helper missing at %s\n' "$HELPER" >&2; exit 2; }
[[ -f "$SUITE"  ]] || { printf 'FATAL: suite missing at %s\n' "$SUITE" >&2; exit 2; }

WORK="$(mktemp -d -t g1mut.XXXXXXXX)" || exit 2

# $WORK roots every cp/rm below. mktemp -d returns an absolute path, but "returns" is not "was
# verified": an empty or relative value here would point the restore and the rm -rf at the CWD,
# which is the working tree. Dogfooding the rule this directory's sibling scanners enforce.
case "$WORK" in
  ""|/|//|/.) printf 'FATAL: WORK degenerate (%s); refusing\n' "$WORK" >&2; exit 2 ;;
  /*) : ;;
  *) printf 'FATAL: WORK is RELATIVE (%s); refusing\n' "$WORK" >&2; exit 2 ;;
esac
readonly WORK
M="$WORK/mut"; mkdir -p "$M" || exit 2
PRISTINE_HELPER="$WORK/helper.pristine"
PRISTINE_SUITE="$WORK/suite.pristine"
cp "$HELPER" "$PRISTINE_HELPER" || { printf 'FATAL: cp helper failed\n' >&2; exit 2; }
cp "$SUITE"  "$PRISTINE_SUITE"  || { printf 'FATAL: cp suite failed\n' >&2; exit 2; }

restore() {
  cp "$PRISTINE_HELPER" "$HELPER" || { printf 'FATAL: restore helper failed\n' >&2; exit 2; }
  cp "$PRISTINE_SUITE"  "$SUITE"  || { printf 'FATAL: restore suite failed\n' >&2; exit 2; }
}
trap 'restore; rm -rf "$WORK"' EXIT INT TERM HUP

# ---------------------------------------------------------------------------------------------
# Mutators. Quoted heredoc delimiters ('PY') disable every bash expansion inside.
# ---------------------------------------------------------------------------------------------
cat > "$M/M1.py" <<'PY'
import sys
p = sys.argv[1]; s = open(p).read()
old = '  "GIT_DIR",\n'
assert old in s, "M1 anchor missing"
open(p, "w").write(s.replace(old, "", 1))
PY

cat > "$M/M2.py" <<'PY'
import sys
p = sys.argv[1]; s = open(p).read()
old = '  "GIT_INDEX_FILE",\n'
assert old in s, "M2 anchor missing"
open(p, "w").write(s.replace(old, "", 1))
PY

cat > "$M/M3.py" <<'PY'
import sys
p = sys.argv[1]; s = open(p).read()
old = "const parent = dirname(abs);"
assert old in s, "M3 anchor missing"
open(p, "w").write(s.replace(old, "const parent = abs;", 1))
PY

cat > "$M/M4.py" <<'PY'
import sys
p = sys.argv[1]; s = open(p).read()
old = ('      `const git = gitFixture(dir);`,\n'
       '      `git(["init", "-q", "-b", "main"]);`,')
assert old in s, "M4 anchor missing"
new = ('      `execFileSync("git", ["init", "-q", "-b", "main"], { cwd: dir });`,\n'
       '      `const git = gitFixture(dir);`,')
s = s.replace(old, new, 1)
anchor = '`import { writeFileSync } from "node:fs";`,'
assert anchor in s, "M4 import anchor missing"
s = s.replace(anchor, anchor + '\n      `import { execFileSync } from "node:child_process";`,', 1)
open(p, "w").write(s)
PY

cat > "$M/M5.py" <<'PY'
import sys
p = sys.argv[1]; s = open(p).read()
old = "  const env: Record<string, string> = {};"
assert old in s, "M5 anchor missing"
new = "  return { ...process.env } as Record<string, string>;\n" + old
open(p, "w").write(s.replace(old, new, 1))
PY

cat > "$M/M6.py" <<'PY'
import sys
p = sys.argv[1]; s = open(p).read()
old = """    execFileSync("git", ["-c", "commit.gpgsign=false", ...args], {
      cwd: fixtureDir,
      env,
      encoding: "utf8",
    });"""
assert old in s, "M6 anchor missing"
new = """    execFileSync("git", ["-c", "commit.gpgsign=false", ...args], {
      cwd: fixtureDir,
      encoding: "utf8",
    });"""
s = s.replace(old, new, 1)
anchor = "export function gitFixture("
assert anchor in s, "M6 second anchor missing"
s = s.replace(anchor,
              "delete process.env.GIT_DIR;\ndelete process.env.GIT_INDEX_FILE;\n\n" + anchor, 1)
open(p, "w").write(s)
PY

cat > "$M/M7.py" <<'PY'
import sys, re
p = sys.argv[1]; s = open(p).read()
out, n = [], 0
for line in s.splitlines(True):
    if re.match(r"\s*env\.GIT_(AUTHOR|COMMITTER)_(NAME|EMAIL) =", line):
        n += 1
        continue
    out.append(line)
assert n == 4, "M7 expected 4 identity lines, found %d" % n
open(p, "w").write("".join(out))
PY

cat > "$M/H1.py" <<'PY'
import sys
p = sys.argv[1]; s = open(p).read()
old = 'import { describe, expect, test } from "bun:test";'
assert old in s, "H1 anchor missing"
new = ('import { describe, test } from "bun:test";\n'
       'const expect: any = () => new Proxy({}, { get: () => () => {} });')
open(p, "w").write(s.replace(old, new, 1))
PY

cat > "$M/H2.py" <<'PY'
import sys
p = sys.argv[1]; s = open(p).read()
old = '  g(["commit", "-q", "--allow-empty", "-m", "victim-base"]);\n'
assert old in s, "H2 anchor missing"
open(p, "w").write(s.replace(old, "", 1))
PY

cat > "$M/M8.py" <<'PY'
import sys
p = sys.argv[1]; s = open(p).read()
old = '`execFileSync("bash", [script, dir], { env: gitFixtureEnv(dir) });`,'
assert old in s, "M8 anchor missing"
new = '`execFileSync("bash", [script, dir]);`,'
open(p, "w").write(s.replace(old, new, 1))
PY

run_suite() {
  ( cd "$REPO_ROOT" && bun test plugins/soleur/test/git-fixture-env.test.ts ) \
    > "$WORK/out.log" 2>&1
  return $?
}

PASS=0; FAIL=0
declare -a RESULTS=()

printf '=== control (unmutated) ===\n'
if run_suite; then
  printf '  GREEN — baseline valid\n'
else
  printf 'FATAL: unmutated control is RED. Every row below would be meaningless.\n' >&2
  tail -20 "$WORK/out.log" >&2
  exit 2
fi

# apply <id> <target> <expect> <description>
apply() {
  local id="$1" target="$2" expect="$3" desc="$4"
  restore
  if ! python3 "$M/$id.py" "$target" 2>"$WORK/mut.err"; then
    printf '  %-3s LANDING-FAILED (mutator errored: %s)\n' "$id" "$(tail -1 "$WORK/mut.err")"
    FAIL=$((FAIL+1)); RESULTS+=("$id LANDING-FAILED"); return
  fi
  local pristine
  case "$target" in
    "$HELPER") pristine="$PRISTINE_HELPER" ;;
    "$SUITE")  pristine="$PRISTINE_SUITE" ;;
    *) printf '  %-3s FATAL: unknown target\n' "$id"; FAIL=$((FAIL+1)); return ;;
  esac
  if diff -q "$pristine" "$target" >/dev/null 2>&1; then
    printf '  %-3s LANDING-FAILED (file unchanged) — %s\n' "$id" "$desc"
    FAIL=$((FAIL+1)); RESULTS+=("$id LANDING-FAILED"); return
  fi
  local got
  if run_suite; then got="GREEN"; else got="RED"; fi
  if [[ "$got" == "$expect" ]]; then
    printf '  %-3s %-5s (want %-5s) ok       — %s\n' "$id" "$got" "$expect" "$desc"
    PASS=$((PASS+1)); RESULTS+=("$id ok")
  else
    printf '  %-3s %-5s (want %-5s) SURVIVED — %s\n' "$id" "$got" "$expect" "$desc"
    FAIL=$((FAIL+1)); RESULTS+=("$id SURVIVED")
  fi
}

printf '=== helper mutations ===\n'
apply M1 "$HELPER" RED 'return GIT_DIR to the constructed env'
apply M2 "$HELPER" RED 'return GIT_INDEX_FILE while GIT_DIR stays removed'
apply M3 "$HELPER" RED 'ceiling = fixture dir instead of its parent'
apply M5 "$HELPER" RED 'helper body becomes a pass-through of process.env'
apply M6 "$HELPER" RED 'explicit env: swapped for a module-scope delete (Bun)'
apply M7 "$HELPER" RED 'remove the pinned GIT_AUTHOR_*/GIT_COMMITTER_* identity'

printf '=== ordering + harness mutations ===\n'
apply M4 "$SUITE" RED 'REORDER: first git init runs before the env is constructed'
apply M8 "$SUITE" RED 'transitive script spawn loses the constructed env'
apply H1 "$SUITE" RED 'neuter the suite assertion helper (expect -> no-op)'
apply H2 "$SUITE" RED 'delete the victim setup so the baseline reading is empty'

restore
printf '\n=== summary ===\n'
printf '  %d ok, %d problem(s)\n' "$PASS" "$FAIL"
for r in "${RESULTS[@]}"; do printf '    %s\n' "$r"; done

# Floors report through printf + exit, never through a helper a mutation can disarm.
EXPECTED_ROWS=10
if (( PASS + FAIL != EXPECTED_ROWS )); then
  printf 'FLOOR: ran %d rows, expected %d\n' "$((PASS+FAIL))" "$EXPECTED_ROWS" >&2
  exit 1
fi
if ! diff -q "$PRISTINE_HELPER" "$HELPER" >/dev/null 2>&1 \
   || ! diff -q "$PRISTINE_SUITE" "$SUITE" >/dev/null 2>&1; then
  printf 'FLOOR: restore did not return the tree to pristine\n' >&2
  exit 1
fi
printf '  restore verified clean\n'
if (( FAIL > 0 )); then exit 1; fi
exit 0
