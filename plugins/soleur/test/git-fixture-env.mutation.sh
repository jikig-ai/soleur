#!/usr/bin/env bash
# Guard 1 mutation battery — the fixture git-write containment suite.
#
# Rewritten when the helper changed shape. It used to build the env from a NAME LIST of dangerous
# variables; review found four omissions in a single pass (GIT_TEMPLATE_DIR and GIT_EXEC_PATH, both
# proven to execute arbitrary code; GIT_SSH, which a `GIT_SSH_COMMAND` prefix rule structurally
# cannot match because the prefix is longer than the name; and the GIT_TRACE family, which writes
# outside the fixture). The helper now layers on `lib/git-clean-env.ts`'s namespace sweep, which is
# the rule that module states in caps — EXCLUSION BY PREFIX, NEVER BY NAME LIST — so the rows below
# target the layering, the ceiling and the identity rather than list membership.
#
# Contract, per traps this repo has already paid for:
#   * Restore from a PRISTINE COPY, never `git checkout` — checkout restores to HEAD, a different
#     thing from "what I had a moment ago" while a fix is in flight.
#   * A GREEN unmutated control runs FIRST. A red baseline voids every row.
#   * Each mutation is asserted to have LANDED (diff vs pristine). A mutation that does not land
#     reports the BASELINE, which is indistinguishable from a pass — and every stale-anchor row in
#     the previous revision of this file did exactly that.
#   * Mutators live in FILES, not inline strings: a python body quoted inside a bash single-quoted
#     string breaks on its own apostrophes, and the failure mode is a silent no-op.
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

# --- mutators (quoted heredocs disable every bash expansion inside) ----------------------------

cat > "$M/M1.py" <<'PY'
import sys
p = sys.argv[1]; s = open(p).read()
old = "  const env = gitCleanEnv({"
assert old in s, "M1 anchor missing"
# Bypass the namespace sweep entirely: keep the ambient env and merely layer the overrides on top.
open(p, "w").write(s.replace(old, "  const env = Object.assign({ ...process.env } as Record<string,string>, {", 1))
PY

cat > "$M/M2.py" <<'PY'
import sys
p = sys.argv[1]; s = open(p).read()
old = "  const physical = existsSync(abs) ? realpathSync(abs) : abs;\n  const ceiling = dirname(physical);"
assert old in s, "M2 anchor missing"
# Resolve the LEXICAL parent instead of the fixture: the spelling that lets a symlinked fixture
# directory escape its ceiling.
new = "  const ceiling = existsSync(dirname(abs)) ? realpathSync(dirname(abs)) : dirname(abs);"
open(p, "w").write(s.replace(old, new, 1))
PY

cat > "$M/M3.py" <<'PY'
import sys
p = sys.argv[1]; s = open(p).read()
anchor = '  if (!ceiling.startsWith("/") || ceiling === "/" || ceiling.includes(":")) {'
i = s.index(anchor)
j = s.index("  }\n", s.index("  }\n", i) ) + 4
open(p, "w").write(s[:i] + s[j:])
PY

cat > "$M/M4.py" <<'PY'
import sys, re
p = sys.argv[1]; s = open(p).read()
n = len(re.findall(r'\n    GIT_(?:AUTHOR|COMMITTER)_(?:NAME|EMAIL): "[^"]*",', s))
assert n == 4, "M4 expected 4 identity lines, found %d" % n
open(p, "w").write(re.sub(r'\n    GIT_(?:AUTHOR|COMMITTER)_(?:NAME|EMAIL): "[^"]*",', "", s))
PY

cat > "$M/M5.py" <<'PY'
import sys
p = sys.argv[1]; s = open(p).read()
old = "  for (const key of NON_GIT_SCRUBBED_VARS) delete env[key];"
assert old in s, "M5 anchor missing"
# SSH_ASKPASS carries no GIT_ prefix, so the namespace sweep cannot reach it by shape. Dropping
# this line leaves an inherited value naming a program git will run.
open(p, "w").write(s.replace(old, "", 1))
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
# The in-process scrub that looks equivalent and is not: under Bun a `delete process.env.X` does
# not reach a child spawned without an explicit `env`.
s = s.replace(anchor, "delete process.env.GIT_DIR;\ndelete process.env.GIT_INDEX_FILE;\n\n" + anchor, 1)
open(p, "w").write(s)
PY

cat > "$M/M7.py" <<'PY'
import sys
p = sys.argv[1]; s = open(p).read()
old = '`execFileSync("bash", [script, dir], { env: gitFixtureEnv(dir) });`,'
assert old in s, "M7 anchor missing"
# The transitive arm: a suite that shells out to a script which itself runs git. No helper-call
# grep and no source scan can reach this.
open(p, "w").write(s.replace(old, '`execFileSync("bash", [script, dir]);`,', 1))
PY

cat > "$M/M8.py" <<'PY'
import sys
p = sys.argv[1]; s = open(p).read()
old = ('      `const git = gitFixture(dir);`,\n'
       '      `git(["init", "-q", "-b", "main"]);`,')
assert old in s, "M8 anchor missing"
# REORDER, not delete: run the first `git init` BEFORE the env is constructed. A delete-only
# battery cannot see an ordering defect.
new = ('      `execFileSync("git", ["init", "-q", "-b", "main"], { cwd: dir });`,\n'
       '      `const git = gitFixture(dir);`,')
s = s.replace(old, new, 1)
imp = '`import { writeFileSync } from "node:fs";`,'
assert imp in s, "M8 import anchor missing"
s = s.replace(imp, imp + '\n      `import { execFileSync } from "node:child_process";`,', 1)
open(p, "w").write(s)
PY

cat > "$M/H1.py" <<'PY'
import sys
p = sys.argv[1]; s = open(p).read()
old = 'import { afterAll, describe, expect, test } from "bun:test";'
assert old in s, "H1 anchor missing"
# A FAITHFUL neuter: a chainable no-op proxy. A naive stub whose `.not` returns a function makes
# `.not.toBe` undefined and the arm crashes — which reads as "caught" while proving nothing.
new = ('import { afterAll, describe, test } from "bun:test";\n'
       'const _noop: any = new Proxy(function () {}, { get: () => _noop, apply: () => undefined });\n'
       'const expect: any = () => _noop;')
open(p, "w").write(s.replace(old, new, 1))
PY

cat > "$M/H2.py" <<'PY'
import sys
p = sys.argv[1]; s = open(p).read()
old = '  g(["commit", "-q", "--allow-empty", "-m", "victim-base"]);\n'
assert old in s, "H2 anchor missing"
# Delete the victim setup so the "before" reading is empty: the suite must fail CLOSED on a missing
# baseline, never pass on "" === "".
open(p, "w").write(s.replace(old, "", 1))
PY

# GREEN requires exit 0 AND a floor on Bun's OWN `expect() calls` figure.
#
# Exit code alone is not evidence. The suite's internal `ledger` array records that each arm's body
# RAN, which is positional — it fires whether or not the expects inside it asserted anything. So
# neutering `expect` to a chainable no-op left the suite reporting 8 pass / 0 fail, and the ledger
# floor passed with it. Bun's reported expect-call count is the independent observable the ledger
# is not: it drops to 0 the moment the assertions stop being real, and nothing inside the suite
# can forge it.
readonly MIN_EXPECT_CALLS=40
run_suite() {
  ( cd "$REPO_ROOT" && bun test plugins/soleur/test/git-fixture-env.test.ts ) > "$WORK/out.log" 2>&1
  local rc=$?
  (( rc != 0 )) && return "$rc"
  local calls
  calls=$(grep -oE '[0-9]+ expect\(\) calls' "$WORK/out.log" | grep -oE '^[0-9]+' | tail -1)
  if [[ -z "$calls" ]] || (( calls < MIN_EXPECT_CALLS )); then
    printf 'expect-call floor breached: %s < %d\n' "${calls:-none}" "$MIN_EXPECT_CALLS" >> "$WORK/out.log"
    return 1
  fi
  return 0
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
apply M1 "$HELPER" RED 'the gitCleanEnv() namespace sweep is bypassed'
apply M2 "$HELPER" RED 'ceiling = realpath(dirname(x)) — a symlinked fixture escapes'
apply M3 "$HELPER" RED 'the unenforceable-ceiling refusal is removed'
apply M4 "$HELPER" RED 'the pinned synthesized identity is removed'
apply M5 "$HELPER" RED 'SSH_ASKPASS (no GIT_ prefix) is no longer scrubbed'
apply M6 "$HELPER" RED 'explicit env: swapped for a module-scope delete (Bun)'

printf '=== suite / ordering / harness mutations ===\n'
apply M7 "$SUITE" RED 'the transitive script spawn loses the constructed env'
apply M8 "$SUITE" RED 'REORDER: first git init runs before the env is constructed'
apply H1 "$SUITE" RED 'assertion helper neutered with a chainable no-op'
apply H2 "$SUITE" RED 'victim setup deleted so the baseline reading is empty'

restore
printf '\n=== summary ===\n'
printf '  %d ok, %d problem(s)\n' "$PASS" "$FAIL"
for r in "${RESULTS[@]}"; do printf '    %s\n' "$r"; done

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
