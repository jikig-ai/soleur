#!/usr/bin/env bash
# Guard 2 mutation + escape battery.
#
# Two kinds of row, and the second kind is the one that found the real defects:
#
#   MUTATION rows perturb the guard or its dependencies and require the guard to notice. They
#   answer "can this guard fail at all".
#
#   ESCAPE rows leave the guard PRISTINE and feed it a corpus it should refuse. They answer "is the
#   guard's predicate the property it names" — a different question, and the one a mutation battery
#   structurally cannot ask. Ten escape rows below were GREEN against this guard's first revision,
#   including `unset GIT_DIR && bun test` (the shipped fix minus one variable, where an absolute
#   GIT_INDEX_FILE alone still stages into the victim's index) and `bash scripts/test-all.sh &&
#   bun test plugins/` (the #7833 defect shape, waved through by a name-drop). No mutation of the
#   guard could have surfaced either: the guard was working exactly as written.
#
# Contract, per traps this repo has already paid for:
#   * Restore from a PRISTINE COPY, never `git checkout` — checkout restores to HEAD, a different
#     thing from "what I had a moment ago" while a fix is in flight.
#   * A GREEN unmutated control runs FIRST. A red baseline voids every row.
#   * Each mutation is asserted to have LANDED (diff vs pristine). A mutation that does not land
#     reports the BASELINE, which is indistinguishable from a pass.
#   * GREEN requires the RECEIPT, not merely exit 0 — a guard replaced by `exit 0` exits zero
#     having asserted nothing.
#   * Setup failures abort (exit 2). A harness that cannot copy a file must not go on to render a
#     confident verdict about the SUT.
export TMPDIR="${TMPDIR:-/var/tmp}"
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
case "$SCRIPT_DIR" in
  ""|/|//|/.) printf 'FATAL: SCRIPT_DIR degenerate\n' >&2; exit 2 ;;
  /*) : ;;
  *) printf 'FATAL: SCRIPT_DIR is relative\n' >&2; exit 2 ;;
esac
readonly SCRIPT_DIR
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)" || exit 2
readonly REPO_ROOT

GUARD="$SCRIPT_DIR/hook-git-env-coverage.test.sh"
EXTRACTOR="$SCRIPT_DIR/lib/lefthook-commands.py"
TEST_ALL="$REPO_ROOT/scripts/test-all.sh"
for f in "$GUARD" "$EXTRACTOR" "$TEST_ALL"; do
  [[ -f "$f" ]] || { printf 'FATAL: missing %s\n' "$f" >&2; exit 2; }
done

WORK="$(mktemp -d -t g2mut.XXXXXXXX)" || exit 2
case "$WORK" in
  ""|/|//|/.) printf 'FATAL: WORK degenerate (%s); refusing\n' "$WORK" >&2; exit 2 ;;
  /*) : ;;
  *) printf 'FATAL: WORK is RELATIVE (%s); refusing\n' "$WORK" >&2; exit 2 ;;
esac
readonly WORK

cp "$GUARD" "$WORK/guard.pristine"         || { printf 'FATAL: cp guard failed\n' >&2; exit 2; }
cp "$EXTRACTOR" "$WORK/extractor.pristine" || { printf 'FATAL: cp extractor failed\n' >&2; exit 2; }
cp "$TEST_ALL" "$WORK/testall.pristine"    || { printf 'FATAL: cp test-all failed\n' >&2; exit 2; }

restore() {
  cp "$WORK/guard.pristine" "$GUARD"         || { printf 'FATAL: restore guard failed\n' >&2; exit 2; }
  cp "$WORK/extractor.pristine" "$EXTRACTOR" || { printf 'FATAL: restore extractor failed\n' >&2; exit 2; }
  cp "$WORK/testall.pristine" "$TEST_ALL"    || { printf 'FATAL: restore test-all failed\n' >&2; exit 2; }
}
trap 'restore; rm -rf "$WORK"' EXIT INT TERM HUP

PASS=0; FAIL=0
declare -a RESULTS=()

FAMILY="GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_NAMESPACE GIT_TEMPLATE_DIR GIT_EXEC_PATH"

fresh_corpus() {
  rm -rf "$WORK/corpus"; mkdir -p "$WORK/corpus/hooks" || return 1
  cp "$REPO_ROOT/lefthook.yml" "$WORK/corpus/lefthook.yml" || return 1
  cp "$REPO_ROOT"/scripts/hooks/* "$WORK/corpus/hooks/" || return 1
}

run_guard() {
  ( cd "$REPO_ROOT" \
    && SOLEUR_GUARD2_LEFTHOOK="$WORK/corpus/lefthook.yml" SOLEUR_GUARD2_HOOKS_DIR="$WORK/corpus/hooks" \
       bash "$GUARD" ) > "$WORK/out.log" 2>&1
}

verdict() {
  if ! run_guard; then printf 'RED'; return; fi
  local r rl rn
  r=$(grep -oE 'SOLEUR_GUARD2_RECEIPT run_lines=[0-9]+ runners=[0-9]+ hook_files=[0-9]+ assertions=[0-9]+' "$WORK/out.log" | tail -1)
  if [[ -z "$r" ]]; then printf 'RED'; return; fi
  rl=$(printf '%s' "$r" | sed -n 's/.*run_lines=\([0-9]*\).*/\1/p')
  rn=$(printf '%s' "$r" | sed -n 's/.*runners=\([0-9]*\).*/\1/p')
  if (( rl < 26 || rn < 3 )); then printf 'RED'; return; fi
  printf 'GREEN'
}

check() {
  local id="$1" expect="$2" desc="$3" got
  got="$(verdict)"
  if [[ "$got" == "$expect" ]]; then
    printf '  %-4s %-5s (want %-5s) ok       — %s\n' "$id" "$got" "$expect" "$desc"
    PASS=$((PASS+1)); RESULTS+=("$id ok")
  else
    printf '  %-4s %-5s (want %-5s) SURVIVED — %s\n' "$id" "$got" "$expect" "$desc"
    FAIL=$((FAIL+1)); RESULTS+=("$id SURVIVED")
    tail -5 "$WORK/out.log" | sed 's/^/        /'
  fi
}

printf '=== control (unmutated guard, pristine corpus) ===\n'
fresh_corpus || { printf 'FATAL: corpus setup failed\n' >&2; exit 2; }
if [[ "$(verdict)" == "GREEN" ]]; then
  printf '  GREEN — baseline valid\n'
else
  printf 'FATAL: unmutated control is RED; every row below is meaningless\n' >&2
  tail -20 "$WORK/out.log" >&2
  exit 2
fi

escape() {
  local id="$1" want="$2" desc="$3" snippet="$4" last
  fresh_corpus || { printf 'FATAL: corpus setup failed\n' >&2; exit 2; }
  printf '%s\n' "$snippet" >> "$WORK/corpus/lefthook.yml"
  last="$(printf '%s' "$snippet" | tail -1 | sed 's/^ *//')"
  if ! grep -qF -- "$last" "$WORK/corpus/lefthook.yml"; then
    printf '  %-4s LANDING-FAILED — snippet absent from corpus\n' "$id"
    FAIL=$((FAIL+1)); RESULTS+=("$id LANDING-FAILED"); return
  fi
  check "$id" "$want" "$desc"
}

printf '\n=== escape rows (guard PRISTINE; the corpus is the mutation) ===\n'
escape E1 RED 'test-all.sh name-drop + unscrubbed bun test' '    e1:
      run: bash scripts/test-all.sh && bun test plugins/soleur/test/'
escape E2 RED 'npm test reaches vitest via package.json' '    e2:
      run: cd apps/web-platform && npm test'
escape E3 RED 'bun run test:ci (one level of indirection)' '    e3:
      run: cd apps/web-platform && bun run test:ci'
escape E4 RED 'python3 -m unittest (the spelling test-all.sh uses)' '    e4:
      run: python3 -m unittest tests.scripts.test_lint_rule_ids'
escape E5 RED 'folded scalar (run: >) hiding a runner' '    e5:
      run: >
        bun test plugins/soleur/test/'
escape E6 RED 'runner after a blank line inside a block scalar' '    e6:
      run: |
        echo warming up

        bun test plugins/soleur/test/'
escape E7 RED 'scrub placed AFTER the runner' "    e7:
      run: bun test plugins/soleur/test/ && unset $FAMILY"
escape E8 RED 'scrub confined to a SUBSHELL' "    e8:
      run: ( unset $FAMILY ) ; bun test plugins/soleur/test/"
escape E9 RED 'scrub is a quoted string, not a statement' '    e9:
      run: echo "unset GIT_DIR" && bun test plugins/soleur/test/'
escape E10 RED 'GIT_DIR-only scrub — the shipped fix minus one variable' '    e10:
      run: unset GIT_DIR && bun test plugins/soleur/test/'

printf '\n=== must-PASS rows (the contract permits these) ===\n'
escape J1 GREEN 'correct MULTI-LINE scrub (was fail-CLOSED before)' "    j1:
      run: |
        unset $FAMILY
        bun test plugins/soleur/test/"
escape J2 GREEN 'env -u spelling' "    j2:
      run: env $(for v in $FAMILY; do printf -- '-u %s ' "$v"; done)bun test plugins/soleur/test/"
escape J3 GREEN 'a non-test run: line needs no scrub' '    j3:
      run: markdownlint --fix docs/'
escape J4 GREEN 'a comment naming bun test is not an entry point' '    # a comment mentioning bun test plugins/soleur/test/'

mutate() {
  local id="$1" want="$2" desc="$3" target="$4" py="$5" pristine="$6" snippet="${7:-}"
  restore
  fresh_corpus || { printf 'FATAL: corpus setup failed\n' >&2; exit 2; }
  # A weakening mutation needs a corpus that EXERCISES the weakened predicate. The live corpus is
  # 100% compliant, so against it every rejection branch is unreachable and the mutation is
  # invisible — which is a fact about the corpus, not about the guard.
  [[ -n "$snippet" ]] && printf '%s\n' "$snippet" >> "$WORK/corpus/lefthook.yml"
  if ! python3 -c "$py" "$target" 2>"$WORK/mut.err"; then
    printf '  %-4s LANDING-FAILED (mutator errored: %s)\n' "$id" "$(tail -1 "$WORK/mut.err")"
    FAIL=$((FAIL+1)); RESULTS+=("$id LANDING-FAILED"); restore; return
  fi
  if diff -q "$pristine" "$target" >/dev/null 2>&1; then
    printf '  %-4s LANDING-FAILED (file unchanged) — %s\n' "$id" "$desc"
    FAIL=$((FAIL+1)); RESULTS+=("$id LANDING-FAILED"); restore; return
  fi
  check "$id" "$want" "$desc"
  restore
}

printf '\n=== mutation rows (corpus pristine; the guard is the mutation) ===\n'

mutate N1 RED 'the runner matcher matches nothing' "$GUARD" '
import sys
p=sys.argv[1]; s=open(p).read()
i=s.index("RUNNER_RE=")
j=s.index("\n", i)
open(p,"w").write(s[:i]+"RUNNER_RE=zzz_never_matches_zzz"+s[j:])
' "$WORK/guard.pristine"

mutate N2 RED 'scripts/test-all.sh loses its internal scrub' "$TEST_ALL" '
import sys, re
p=sys.argv[1]; s=open(p).read()
lines=s.splitlines(True)
out=[l for l in lines if not re.match(r"^\s*unset\s+GIT_DIR\b", l)]
assert len(out) < len(lines), "N2 anchor missing"
open(p,"w").write("".join(out))
' "$WORK/testall.pristine"

# GREEN is the expected verdict here, and that is the point: the pristine guard REJECTS this
# corpus (row E10). If removing the full-family requirement makes it accepted, the requirement is
# load-bearing. A row that stayed RED would mean the predicate does no work.
mutate N3 GREEN 'full-family requirement is load-bearing (E10 corpus now accepted)' "$GUARD" '
import sys
p=sys.argv[1]; s=open(p).read()
i=s.index("readonly REQUIRED_SCRUB_VARS=(")
j=s.index(")", i)+1
open(p,"w").write(s[:i]+"readonly REQUIRED_SCRUB_VARS=(GIT_DIR)"+s[j:])
' "$WORK/guard.pristine" '    n3:
      run: unset GIT_DIR && bun test plugins/soleur/test/'

# Same polarity as N3: the pristine guard rejects an after-the-runner scrub (row E7).
mutate N4 GREEN 'ordering check is load-bearing (E7 corpus now accepted)' "$GUARD" '
import sys
p=sys.argv[1]; s=open(p).read()
old="      (( scrubbed == 1 )) && return 0\n      return 1"
assert old in s, "N4 anchor missing"
open(p,"w").write(s.replace(old, "      return 0", 1))
' "$WORK/guard.pristine" "    n4:
      run: bun test plugins/soleur/test/ && unset $FAMILY"

mutate N5 RED 'the YAML extractor truncates its output' "$EXTRACTOR" '
import sys
p=sys.argv[1]; s=open(p).read()
old="    commands = walk(doc)"
assert old in s, "N5 anchor missing"
open(p,"w").write(s.replace(old, old+"\n    commands = commands[:1]", 1))
' "$WORK/extractor.pristine"

mutate N6 RED 'guard body replaced with exit 0 (no receipt)' "$GUARD" '
import sys
p=sys.argv[1]; lines=open(p).readlines()
open(p,"w").write(lines[0]+"exit 0\n")
' "$WORK/guard.pristine"

restore
printf '\n=== summary ===\n'
printf '  %d ok, %d problem(s)\n' "$PASS" "$FAIL"
for r in "${RESULTS[@]}"; do printf '    %s\n' "$r"; done

EXPECTED_ROWS=20
if (( PASS + FAIL != EXPECTED_ROWS )); then
  printf 'FLOOR: ran %d rows, expected %d\n' "$((PASS+FAIL))" "$EXPECTED_ROWS" >&2
  exit 1
fi
if ! diff -q "$WORK/guard.pristine" "$GUARD" >/dev/null 2>&1 \
   || ! diff -q "$WORK/extractor.pristine" "$EXTRACTOR" >/dev/null 2>&1 \
   || ! diff -q "$WORK/testall.pristine" "$TEST_ALL" >/dev/null 2>&1; then
  printf 'FLOOR: restore did not return the tree to pristine\n' >&2
  exit 1
fi
printf '  restore verified clean\n'
if (( FAIL > 0 )); then exit 1; fi
exit 0
