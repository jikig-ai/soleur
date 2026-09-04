#!/usr/bin/env bash
# Guard 2 mutation battery — N1-N6 (corpus) + J1-J4 (harness).
#
# Corpus rows run against SCRATCH COPIES of lefthook.yml and scripts/hooks/, injected via the
# guard's SOLEUR_GUARD2_* overrides. That keeps a mutation from ever touching the real hook config:
# a battery that edits the live lefthook.yml and then crashes leaves the developer's commit path
# broken. Rows that must mutate the GUARD ITSELF (or test-all.sh) use a pristine-copy restore.
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
TEST_ALL="$REPO_ROOT/scripts/test-all.sh"
[[ -f "$GUARD" ]] || { printf 'FATAL: guard missing\n' >&2; exit 2; }
[[ -f "$TEST_ALL" ]] || { printf 'FATAL: test-all.sh missing\n' >&2; exit 2; }

WORK="$(mktemp -d -t g2mut.XXXXXXXX)" || exit 2

# $WORK roots every cp/rm below. mktemp -d returns an absolute path, but "returns" is not "was
# verified": an empty or relative value here would point the restore and the rm -rf at the CWD,
# which is the working tree. Dogfooding the rule this directory's sibling scanners enforce.
case "$WORK" in
  ""|/|//|/.) printf 'FATAL: WORK degenerate (%s); refusing\n' "$WORK" >&2; exit 2 ;;
  /*) : ;;
  *) printf 'FATAL: WORK is RELATIVE (%s); refusing\n' "$WORK" >&2; exit 2 ;;
esac
readonly WORK
cp "$GUARD" "$WORK/guard.pristine"       || { printf 'FATAL: cp guard failed\n' >&2; exit 2; }
cp "$TEST_ALL" "$WORK/testall.pristine"  || { printf 'FATAL: cp test-all failed\n' >&2; exit 2; }

restore() {
  cp "$WORK/guard.pristine" "$GUARD"      || { printf 'FATAL: restore guard failed\n' >&2; exit 2; }
  cp "$WORK/testall.pristine" "$TEST_ALL" || { printf 'FATAL: restore test-all failed\n' >&2; exit 2; }
}
trap 'restore; rm -rf "$WORK"' EXIT INT TERM HUP

PASS=0; FAIL=0
declare -a RESULTS=()

# Build a fresh scratch corpus (real content) for each row.
fresh_corpus() {
  local d="$1"
  rm -rf "$d"; mkdir -p "$d/hooks" || return 1
  cp "$REPO_ROOT/lefthook.yml" "$d/lefthook.yml" || return 1
  cp "$REPO_ROOT"/scripts/hooks/* "$d/hooks/" || return 1
}

# run_guard <corpus-dir>  -> 0 green, non-zero red
run_guard() {
  local d="$1"
  ( cd "$REPO_ROOT" \
    && SOLEUR_GUARD2_LEFTHOOK="$d/lefthook.yml" SOLEUR_GUARD2_HOOKS_DIR="$d/hooks" \
       bash "$GUARD" ) > "$WORK/out.log" 2>&1
}

# check <id> <expect> <desc>   (corpus already mutated in $WORK/corpus)
check() {
  local id="$1" expect="$2" desc="$3" got
  if run_guard "$WORK/corpus"; then got="GREEN"; else got="RED"; fi
  # A zero exit is NOT sufficient evidence of a green run: a guard replaced by `exit 0` exits zero
  # having asserted nothing. Require the receipt, with both corpus counters above floor.
  if [[ "$got" == "GREEN" ]]; then
    local receipt
    receipt=$(grep -oE 'SOLEUR_GUARD2_RECEIPT run_lines=[0-9]+ runners=[0-9]+ hook_files=[0-9]+ assertions=[0-9]+' "$WORK/out.log" | tail -1)
    if [[ -z "$receipt" ]]; then
      got="RED"
    else
      local rl rn
      rl=$(printf '%s' "$receipt" | sed -n 's/.*run_lines=\([0-9]*\).*/\1/p')
      rn=$(printf '%s' "$receipt" | sed -n 's/.*runners=\([0-9]*\).*/\1/p')
      if (( rl < 20 || rn < 2 )); then got="RED"; fi
    fi
  fi
  if [[ "$got" == "$expect" ]]; then
    printf '  %-3s %-5s (want %-5s) ok       — %s\n' "$id" "$got" "$expect" "$desc"
    PASS=$((PASS+1)); RESULTS+=("$id ok")
  else
    printf '  %-3s %-5s (want %-5s) SURVIVED — %s\n' "$id" "$got" "$expect" "$desc"
    FAIL=$((FAIL+1)); RESULTS+=("$id SURVIVED")
    tail -6 "$WORK/out.log" | sed 's/^/        /'
  fi
}

# Assert a scratch-corpus edit actually landed before judging it.
landed() {
  local id="$1" file="$2" pattern="$3"
  if ! grep -qF -- "$pattern" "$file"; then
    printf '  %-3s LANDING-FAILED — %s not found in %s\n' "$id" "$pattern" "$(basename "$file")"
    FAIL=$((FAIL+1)); RESULTS+=("$id LANDING-FAILED"); return 1
  fi
  return 0
}

printf '=== control ===\n'
fresh_corpus "$WORK/corpus" || { printf 'FATAL: corpus setup failed\n' >&2; exit 2; }
if run_guard "$WORK/corpus"; then
  printf '  GREEN — baseline valid\n'
else
  printf 'FATAL: unmutated control is RED; every row below is meaningless\n' >&2
  tail -20 "$WORK/out.log" >&2
  exit 2
fi

printf '\n=== corpus mutations (N) ===\n'

# N1 — a NEW unscrubbed test-runner run: line.
fresh_corpus "$WORK/corpus"
printf '    new-unscrubbed-suite:\n      run: bun test some/other/dir/\n' >> "$WORK/corpus/lefthook.yml"
landed N1 "$WORK/corpus/lefthook.yml" 'run: bun test some/other/dir/' \
  && check N1 RED 'a new unscrubbed test-runner run: line'

# N3 — delete the unset from scripts/hooks/pre-push.
fresh_corpus "$WORK/corpus"
sed -i 's/^unset GIT_DIR GIT_INDEX_FILE GIT_WORK_TREE$//' "$WORK/corpus/hooks/pre-push"
if grep -qE '^unset GIT_DIR' "$WORK/corpus/hooks/pre-push"; then
  printf '  N3  LANDING-FAILED — unset still present in pre-push\n'
  FAIL=$((FAIL+1)); RESULTS+=("N3 LANDING-FAILED")
else
  check N3 RED 'scripts/hooks/pre-push loses its unset'
fi

# N4 — a SECOND unscrubbed runner in a hook that already has a scrubbed one.
fresh_corpus "$WORK/corpus"
python3 - "$WORK/corpus/lefthook.yml" <<'PY'
import sys
p = sys.argv[1]; s = open(p).read()
anchor = "      run: unset GIT_DIR GIT_INDEX_FILE GIT_WORK_TREE && bun test plugins/soleur/test/\n"
assert anchor in s, "N4 anchor missing"
extra = anchor + "    second-unscrubbed:\n      priority: 99\n      run: npx vitest run\n"
open(p, "w").write(s.replace(anchor, extra, 1))
PY
landed N4 "$WORK/corpus/lefthook.yml" 'run: npx vitest run' \
  && check N4 RED 'a second unscrubbed runner after an already-scrubbed one'

# N6 — the corpus itself disappears.
fresh_corpus "$WORK/corpus"
rm -f "$WORK/corpus/hooks"/*
check N6 RED 'scripts/hooks/ becomes empty (corpus asserted non-empty per source)'

printf '\n=== must-PASS rows (J2, J3, J4) — the contract permits these ===\n'

# J2 — the `env -u` spelling is measured-equivalent and must be accepted.
fresh_corpus "$WORK/corpus"
python3 - "$WORK/corpus/lefthook.yml" <<'PY'
import sys
p = sys.argv[1]; s = open(p).read()
old = "      run: unset GIT_DIR GIT_INDEX_FILE GIT_WORK_TREE && bun test plugins/soleur/test/"
assert old in s, "J2 anchor missing"
new = "      run: env -u GIT_DIR -u GIT_INDEX_FILE -u GIT_WORK_TREE bun test plugins/soleur/test/"
open(p, "w").write(s.replace(old, new, 1))
PY
landed J2 "$WORK/corpus/lefthook.yml" 'run: env -u GIT_DIR' \
  && check J2 GREEN 'the env -u spelling is accepted (measured-equivalent, §M-6)'

# J3 — a non-test run: line with no scrub. 24 of the 26 lines are exactly this.
fresh_corpus "$WORK/corpus"
printf '    some-linter:\n      run: markdownlint --fix docs/\n' >> "$WORK/corpus/lefthook.yml"
landed J3 "$WORK/corpus/lefthook.yml" 'run: markdownlint --fix docs/' \
  && check J3 GREEN 'a non-test run: line needs no scrub'

# J4 — a COMMENT containing the literal `bun test` must not register as an entry point.
fresh_corpus "$WORK/corpus"
printf '    # a comment mentioning bun test plugins/soleur/test/ must not count\n' \
  >> "$WORK/corpus/lefthook.yml"
landed J4 "$WORK/corpus/lefthook.yml" '# a comment mentioning bun test' \
  && check J4 GREEN 'a comment naming bun test is not an entry point (cq-assert-anchor-not-bare-token)'

printf '\n=== guard-self mutations (N2, N5, J1) — pristine-restore ===\n'

# N2 — delete the unset from the real scripts/test-all.sh.
restore
fresh_corpus "$WORK/corpus"
python3 - "$TEST_ALL" <<'PY'
import sys, re
p = sys.argv[1]; s = open(p).read()
n = 0
out = []
for line in s.splitlines(True):
    if re.match(r"^\s*unset\s+GIT_DIR\b", line):
        n += 1
        continue
    out.append(line)
assert n >= 1, "N2 anchor missing (no unset GIT_DIR in test-all.sh)"
open(p, "w").write("".join(out))
PY
if grep -qE '^\s*unset\s+GIT_DIR' "$TEST_ALL"; then
  printf '  N2  LANDING-FAILED — unset still present in test-all.sh\n'
  FAIL=$((FAIL+1)); RESULTS+=("N2 LANDING-FAILED")
else
  check N2 RED 'scripts/test-all.sh loses its internal git-location unset'
fi
restore

# N5 — make the runner matcher match nothing.
restore
fresh_corpus "$WORK/corpus"
python3 - "$GUARD" <<'PY'
import sys
p = sys.argv[1]; s = open(p).read()
old = "RUNNER_RE='"
i = s.index(old)
j = s.index("'\n", i + len(old))
open(p, "w").write(s[:i] + "RUNNER_RE='zzz_never_matches_zzz'" + s[j+1:])
PY
landed N5 "$GUARD" 'zzz_never_matches_zzz' \
  && check N5 RED 'the runner matcher matches nothing (guard examines 0 commands)'
restore

# J1 — replace the guard body with exit 0.
restore
fresh_corpus "$WORK/corpus"
python3 - "$GUARD" <<'PY'
import sys
p = sys.argv[1]; s = open(p).read()
lines = s.splitlines(True)
open(p, "w").write(lines[0] + "exit 0\n")
PY
landed J1 "$GUARD" 'exit 0' \
  && check J1 RED 'guard body replaced with exit 0 (floors must catch a no-op guard)'
restore

printf '\n=== summary ===\n'
printf '  %d ok, %d problem(s)\n' "$PASS" "$FAIL"
for r in "${RESULTS[@]}"; do printf '    %s\n' "$r"; done

EXPECTED_ROWS=10
if (( PASS + FAIL != EXPECTED_ROWS )); then
  printf 'FLOOR: ran %d rows, expected %d\n' "$((PASS+FAIL))" "$EXPECTED_ROWS" >&2
  exit 1
fi
if ! diff -q "$WORK/guard.pristine" "$GUARD" >/dev/null 2>&1 \
   || ! diff -q "$WORK/testall.pristine" "$TEST_ALL" >/dev/null 2>&1; then
  printf 'FLOOR: restore did not return the tree to pristine\n' >&2
  exit 1
fi
printf '  restore verified clean\n'
if (( FAIL > 0 )); then exit 1; fi
exit 0
