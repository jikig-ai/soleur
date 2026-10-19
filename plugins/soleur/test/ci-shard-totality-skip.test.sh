#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# Guard — the shard-totality-mutations skip gate cannot skip a diff the battery could be sensitive to
# (#9729, ADR-276 S4 PR A).
#
# PROPERTY. `shard-totality-mutations` in .github/workflows/ci.yml skips its battery step only when
# scripts/ci-shard-totality-classify.sh emits `false`, which it does only on `pull_request` with a
# non-empty changed-file list in which EVERY row is a well-formed `git diff --raw` row of status A (old
# mode 000000) or M (old mode 100644), new mode 100644, on a markdown file under `knowledge-base/` or at the
# repo root (#10416: a symlink, gitlink or exec-bit `.md` runs the battery). Everything else (a shell/py/ts file anywhere, including under
# knowledge-base/, which the battery's census can enumerate as a declarer; a deletion, rename, copy,
# typechange; any other event; an empty or unresolvable diff) emits `true` and runs the battery.
#
# ASSEMBLY. (a) the shipped classifier, executed over fixture `git diff --raw` rows on stdin —
# never a re-implemented mirror; (b) ci.yml wiring anchors scoped to the shard-totality-mutations job
# section: the classify step precedes the battery step, the battery step is gated on the verdict, the
# verdict is validated and emitted, the checkout is full-history on a pull_request (an EXECUTED
# check on the ternary: a sweep for falsy-middle shapes, not an evaluation), and the job carries no job-level if:/needs: beyond the
# two pinned by scripts/ci-push-dedupe.test.sh and scripts/ci-draft-light.test.sh.
#
# SINGLE-SOURCED MACHINERY (#10416). Both classifiers carry a byte-identical `mode-aware-row-parse` block
# (they run from a base-ref copy in $RUNNER_TEMP where scripts/lib is absent, so there is no shared helper). This
# suite therefore drives BOTH scripts through one grammar-derived census, one sed-mutation battery and one parity
# assertion; scripts/ci-e2e-classify.sh is read here as a second subject on purpose.
#
# Auto-discovered by scripts/test-all.sh (`plugins/soleur/test/*.test.sh`).
# ─────────────────────────────────────────────────────────────────────────────
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
CLASSIFIER="$REPO_ROOT/scripts/ci-shard-totality-classify.sh"
CI_YML="$REPO_ROOT/.github/workflows/ci.yml"

PASS=0
FAIL=0
pass() { PASS=$((PASS + 1)); echo "ok   $1"; }
fail() { FAIL=$((FAIL + 1)); echo "FAIL $1"; }

# Instrument self-test (ADR-193): both helpers must move their counter, and the floor below reports
# through printf + exit, never through the helpers it guards.
_p0=$PASS; _f0=$FAIL
pass "instrument self-test (expected)" >/dev/null
fail "instrument self-test (expected, subtracted)" >/dev/null
if [ "$PASS" -ne $((_p0 + 1)) ] || [ "$FAIL" -ne $((_f0 + 1)) ]; then
  printf 'FATAL: pass()/fail() did not each move their counter\n' >&2
  exit 1
fi
PASS=$_p0; FAIL=$_f0

expect_verdict() { # <desc> <true|false> <event> <stdin-rows>
  local desc="$1" expected="$2" event="$3" rows="$4" actual rc
  actual="$(printf '%s' "$rows" | bash "$CLASSIFIER" "$event" 2>/dev/null)"
  rc=$?
  if [ "$rc" -eq 0 ] && [ "$actual" = "$expected" ]; then
    pass "$desc"
  else
    fail "$desc (want=$expected got='${actual}' rc=$rc)"
  fi
}

# raw_row <status> <old-mode> <new-mode> <path> — one `git diff --raw` row (default abbreviation: 7-hex object names).
# A rename/copy passes a path holding a TAB. Rows print with a trailing newline; join several as "$(mrow a; mrow b)".
raw_row() { printf ':%s %s 1111111 2222222 %s\t%s\n' "$2" "$3" "$1" "$4"; }
mrow() { raw_row M 100644 100644 "$1"; }
arow() { raw_row A 000000 100644 "$1"; }

echo "── classifier artifact"
if [ -x "$CLASSIFIER" ]; then
  pass "classifier exists and is executable"
else
  fail "classifier missing/not executable: $CLASSIFIER"
  echo; echo "Guard: $PASS passed, $FAIL failed"
  exit 1
fi

echo "── decision matrix (pull_request)"
expect_verdict "kb markdown only skips"                  false pull_request "$(mrow knowledge-base/project/learnings/x.md)"
expect_verdict "kb markdown added + root md skips"       false pull_request "$(arow knowledge-base/a.md; mrow README.md)"
expect_verdict "bare path (no status column) fails closed" true pull_request $'knowledge-base/a.md\n'
expect_verdict "kb shell file runs (census declarer)"    true  pull_request "$(mrow knowledge-base/x.sh)"
expect_verdict "kb non-md (json) runs"                   true  pull_request "$(mrow knowledge-base/x.json)"
expect_verdict "kb python file runs"                     true  pull_request "$(mrow knowledge-base/x.py)"
expect_verdict "runner edit runs"                        true  pull_request "$(mrow scripts/test-all.sh)"
expect_verdict "ci.yml edit runs"                        true  pull_request "$(mrow .github/workflows/ci.yml)"
expect_verdict "shard legs tsv edit runs"                true  pull_request "$(mrow scripts/suite-shard-legs.tsv)"
expect_verdict "mixed kb md + app path runs"             true  pull_request "$(mrow knowledge-base/a.md; mrow apps/web-platform/x.ts)"
expect_verdict "deleted kb md runs"                      true  pull_request "$(raw_row D 100644 000000 knowledge-base/a.md)"
expect_verdict "renamed kb md runs"                      true  pull_request "$(raw_row R100 100644 100644 $'knowledge-base/a.md\tknowledge-base/b.md')"
expect_verdict "copied kb md runs"                       true  pull_request "$(raw_row C100 100644 100644 $'knowledge-base/a.md\tknowledge-base/b.md')"
expect_verdict "typechange runs"                         true  pull_request "$(raw_row T 100644 120000 knowledge-base/a.md)"
expect_verdict "unmerged runs"                           true  pull_request "$(raw_row U 000000 000000 knowledge-base/a.md)"
expect_verdict "empty changeset runs"                    true  pull_request ''
expect_verdict "subdir md outside kb runs"               true  pull_request "$(mrow plugins/soleur/README.md)"
expect_verdict "knowledge-base-evil prefix runs"         true  pull_request "$(mrow knowledge-base-evil/x.md)"
expect_verdict "C-quoted path runs"                      true  pull_request "$(mrow '"knowledge-base/x\ny.md"')"
# The row-grammar `^`/`$` anchors: a status-M row with a second tab field, and a row with junk before the colon, must not
# be read as a well-formed row by prefix/suffix (a rename row alone cannot pin them: the STATUS guard masks it).
expect_verdict "extra tab field after the path runs"    true  pull_request "$(raw_row M 100644 100644 $'README.md\tx.ts')"
expect_verdict "junk before the row colon runs"         true  pull_request "junk$(mrow README.md)"
expect_verdict "second row after a compliant first runs" true  pull_request "$(mrow knowledge-base/a.md; mrow scripts/test-all.sh)"
# A final row with no trailing newline must still be read (the `|| [ -n "$line" ]` limb); dropping it would skip the battery.
expect_verdict "final row without trailing newline runs"  true  pull_request "$(mrow knowledge-base/a.md; printf '%s' "$(mrow scripts/x.sh)")"
expect_verdict "markdown suffix then more runs"          true  pull_request "$(mrow knowledge-base/x.md.sh)"
expect_verdict "single-slash .md is NOT root-md safe"    true  pull_request "$(mrow apps/README.md)"
expect_verdict "docs/legal md runs (not allowlisted)"    true  pull_request "$(mrow docs/legal/x.md)"
expect_verdict "bare knowledge-base path runs"           true  pull_request "$(mrow knowledge-base)"
expect_verdict "classifier self-edit runs"               true  pull_request "$(mrow scripts/ci-shard-totality-classify.sh)"
expect_verdict "own suite self-edit runs"                true  pull_request "$(mrow plugins/soleur/test/ci-shard-totality-skip.test.sh)"

echo "── file-mode axis (#10416) — a symlink, gitlink or exec-bit .md is not markdown (the census reads shebang files)"
expect_verdict "added symlinked kb .md runs"             true  pull_request "$(raw_row A 000000 120000 knowledge-base/x.md)"
expect_verdict "added executable kb .md runs"            true  pull_request "$(raw_row A 000000 100755 knowledge-base/x.md)"
expect_verdict "added executable root .md runs"          true  pull_request "$(raw_row A 000000 100755 README.md)"
expect_verdict "added gitlink runs"                      true  pull_request "$(raw_row A 000000 160000 knowledge-base/x.md)"
expect_verdict "exec-bit flip on root .md runs"          true  pull_request "$(raw_row M 100644 100755 README.md)"
expect_verdict "exec-bit removal on kb .md runs"         true  pull_request "$(raw_row M 100755 100644 knowledge-base/x.md)"
expect_verdict "modify of an existing symlink runs"      true  pull_request "$(raw_row M 120000 120000 knowledge-base/x.md)"
expect_verdict "A row with a non-null old mode runs"     true  pull_request "$(raw_row A 100644 100644 knowledge-base/x.md)"
expect_verdict "M99 (unknown status) runs"               true  pull_request "$(raw_row M99 100644 100644 knowledge-base/x.md)"
expect_verdict "compliant first row, symlink second, runs" true pull_request "$(arow knowledge-base/a.md; raw_row A 000000 120000 knowledge-base/b.md)"
expect_verdict "symlink first row, compliant second, runs" true pull_request "$(raw_row A 000000 120000 knowledge-base/b.md; arow knowledge-base/a.md)"
expect_verdict "legacy name-status row fails closed"     true  pull_request $'M\tknowledge-base/a.md\n'
expect_verdict "uppercase-hex raw row fails closed"      true  pull_request $':100644 100644 ABCDEF1 2222222 M\tknowledge-base/a.md\n'
expect_verdict "raw row with a space for the tab fails closed" true pull_request $':100644 100644 1111111 2222222 M knowledge-base/a.md\n'
expect_verdict "raw row with an empty path fails closed" true  pull_request $':100644 100644 1111111 2222222 M\t\n'
expect_verdict "plain 100644 kb .md added+modified skips" false pull_request "$(arow knowledge-base/a/b/c.md; mrow README.md)"
expect_verdict "path with spaces still skips"            false pull_request "$(arow 'knowledge-base/with space/a b.md')"
expect_verdict "40-hex (--no-abbrev) raw row skips"      false pull_request "$(printf ':100644 100644 %040d %040d M\tknowledge-base/a.md\n' 1 2)"

echo "── non-PR events always run"
expect_verdict "push runs"                               true  push             "$(mrow knowledge-base/a.md)"
expect_verdict "merge_group runs"                        true  merge_group      "$(mrow knowledge-base/a.md)"
expect_verdict "workflow_dispatch runs"                  true  workflow_dispatch "$(mrow knowledge-base/a.md)"
expect_verdict "enum-failed verdict emits true"          true  --enum-failed    ''

echo "── broken usage exits non-zero"
if bash "$CLASSIFIER" </dev/null >/dev/null 2>&1; then fail "missing event arg exits non-zero"; else pass "missing event arg exits non-zero"; fi
if bash "$CLASSIFIER" bogus_event </dev/null >/dev/null 2>&1; then fail "unknown event exits non-zero"; else pass "unknown event exits non-zero"; fi

echo "── ci.yml wiring (shard-totality-mutations job section)"
section="$(awk '/^  shard-totality-mutations:/{f=1} f && !/^  shard-totality-mutations:/ && /^  [a-zA-Z0-9_-]+:/{exit} f{print}' "$CI_YML")"
in_section() { printf '%s\n' "$section" | grep -cF -e "$2" >/dev/null && pass "$1" || fail "$1 (missing in section: $2)"; }

if printf '%s\n' "$section" | grep -cE '^[[:space:]]+id: detect[[:space:]]*$' >/dev/null; then pass "classify step id: detect (line-anchored)"; else fail "classify step id: detect missing"; fi
in_section "classifier invoked from the workflow"        "scripts/ci-shard-totality-classify.sh"
in_section "base-ref classifier judged, not the PR's"    'git show "origin/${GITHUB_BASE_REF}:scripts/ci-shard-totality-classify.sh"'
in_section "diff range is the PR merge-base, as raw rows" 'git diff --raw --no-color --no-ext-diff --ignore-submodules=none "origin/${GITHUB_BASE_REF}...HEAD" 2>>"$GIT_ERR")"'
in_section "invalid verdict is a red job"                '::error::shard-totality classifier emitted invalid verdict'
in_section "verdict emitted to GITHUB_OUTPUT"            'applicable=$APPLICABLE" >> "$GITHUB_OUTPUT'
in_section "enum-failure fallback is a literal true"     'APPLICABLE=true'
in_section "git stderr is captured, not discarded"       'GIT_ERR'

if grep -qE '2> *(/dev/null|&-)|&>' < <(grep -E 'git (diff|show)' <<<"$section"); then
  fail "a git diff/show in the classify step discards stderr (the e2e enum-failed cause was invisible for that reason)"
else
  pass "no git diff/show line discards stderr"
fi

detect_step="$(printf '%s\n' "$section" | awk '/^      - name: Classify shard-totality applicability/{f=1; print; next} f && /^      - /{exit} f{print}')"
if [ -n "$detect_step" ] && ! printf '%s\n' "$detect_step" | grep -cE '^\s+if:' >/dev/null; then
  pass "classify step carries no if: (verdict always populated)"
else
  fail "classify step is conditional or not found"
fi

battery_step="$(printf '%s\n' "$section" | awk '/^      - name: Guard 1 — shard-totality mutation battery/{f=1; print; next} f && /^      - /{exit} f{print}')"
if grep -qxE "        if: steps\.detect\.outputs\.applicable != 'false'" <<<"$battery_step"; then
  pass "the battery step itself carries the fail-closed gate (!= 'false')"
else
  fail "the battery step lacks its own 'if: steps.detect.outputs.applicable != false' line"
fi
skip_step="$(printf '%s\n' "$section" | awk '/^      - name: Record shard-totality skip verdict/{f=1; print; next} f && /^      - /{exit} f{print}')"
if grep -qxE "        if: steps\.detect\.outputs\.applicable == 'false'" <<<"$skip_step"; then
  pass "the skip-verdict step is gated on == 'false'"
else
  fail "the skip-verdict step lacks its == 'false' gate"
fi

# The classifier's allowlist arms are the security boundary: pin them lexically and by count (fixtures cannot enumerate widenings).
grep -qF 'knowledge-base/*.md) ;;' "$CLASSIFIER" && pass "allowlist arm: knowledge-base/*.md" || fail "allowlist arm knowledge-base/*.md missing/widened"
grep -qF '*.md)' "$CLASSIFIER" && pass "allowlist arm: root *.md" || fail "allowlist arm *.md missing"
path_arms="$(awk '/^  case "\$path" in/,/^  esac/' "$CLASSIFIER" | grep -cE '^ {4}[^ ]' || true)"
if [ "$path_arms" -eq 3 ]; then pass "path-case arm count is exactly 3"; else fail "path-case arm count is $path_arms, want 3 (allowlist widened or catch-all lost?)"; fi

classify_line="$(printf '%s\n' "$section" | grep -n 'ci-shard-totality-classify' | head -1 | cut -d: -f1)"
battery_line="$(printf '%s\n' "$section" | grep -n 'scripts-shard-totality-mutations.sh --rows' | head -1 | cut -d: -f1)"
if [ -n "$classify_line" ] && [ -n "$battery_line" ] && [ "$classify_line" -lt "$battery_line" ]; then
  pass "classify step precedes the battery step"
else
  fail "ordering (classify=${classify_line:-none} battery=${battery_line:-none})"
fi

# EXECUTED evaluation of the checkout ternary. A text pin on the spelling certified `&& 0 || 1` for weeks while
# the expression evaluated to 1 (0 is falsy in an Actions expression, so `A && 0 || 1` is always 1) and e2e's
# classify step ran on a depth-1 clone. Model the evaluation rather than the spelling: an `A && B || C` whose B is
# falsy (0, false, '', null) collapses to C, so any such shape is forbidden anywhere in a workflow.
falsy_hits="$(grep -rnE '&&[[:space:]]*(0|false|null|'"''"'|"")[[:space:]]*\|\|' "$REPO_ROOT/.github/workflows" 2>/dev/null | grep -vE '^[^:]+:[0-9]+:[[:space:]]*#' || true)"
if [ -z "$falsy_hits" ]; then
  pass "no falsy-middle ternary (A && 0 || C) in any workflow"
else
  fail "falsy-middle ternary found (always evaluates to the right operand): $falsy_hits"
fi
e2e_section="$(awk '/^  e2e:/{f=1} f && !/^  e2e:/ && /^  [a-zA-Z0-9_-]+:/{exit} f{print}' "$CI_YML")"
if grep -qF "fetch-depth: \${{ github.event_name == 'pull_request' && '0' || '1' }}" <<<"$e2e_section"; then
  pass "e2e checkout depth ternary yields the truthy string '0' on pull_request"
else
  fail "e2e fetch-depth ternary is not the quoted-'0' form"
fi

# ─────────────────────────────────────────────────────────────────────────────
# SINGLE-SOURCED MACHINERY over BOTH classifiers (#10416): grammar-derived census, sed-mutation battery, parity.
# Every mutation is applied to a COPY under a mktemp root, never to the repository file.
# ─────────────────────────────────────────────────────────────────────────────
assert_fixture_dir() {
  case "${1-}" in
    "") printf 'FATAL: fixture dir is EMPTY; git -C "" would operate on %s\n' "$PWD" >&2; exit 2 ;;
    */../*|*/..) printf 'FATAL: fixture dir %s contains ..; refusing\n' "$1" >&2; exit 2 ;;
    /proc/*|/sys/*|/dev/*) printf 'FATAL: fixture dir %s is a synthetic-fs path; refusing\n' "$1" >&2; exit 2 ;;
    /|//|/.) printf 'FATAL: fixture dir resolves to the filesystem root; refusing\n' >&2; exit 2 ;;
    /*) : ;;
    *)  printf 'FATAL: fixture dir %s is RELATIVE; refusing\n' "$1" >&2; exit 2 ;;
  esac
}
SBX="$(mktemp -d "${TMPDIR:-/var/tmp}/ci-shard-skip.XXXXXXXX")" || { echo "FATAL: mktemp failed" >&2; exit 2; }
assert_fixture_dir "$SBX"
trap 'rm -rf "$SBX"' EXIT

CLASSIFIERS=("scripts/ci-shard-totality-classify.sh" "scripts/ci-e2e-classify.sh")
if [ "${#CLASSIFIERS[@]}" -ne 2 ]; then printf 'FATAL: classifier list must hold exactly 2 members\n' >&2; exit 1; fi

echo "── GUARD tags: each present exactly once, at the end of its own line, in both classifiers"
GUARD_TAGS=(ROW-GRAMMAR MODE-OLD-ADD MODE-OLD-MOD STATUS MODE-NEW)
for c in "${CLASSIFIERS[@]}"; do
  for tag in "${GUARD_TAGS[@]}"; do
    n="$(grep -cE "# GUARD:${tag}\$" "$REPO_ROOT/$c" || true)"
    if [ "$n" -eq 1 ]; then pass "$c carries # GUARD:$tag exactly once"; else fail "$c carries # GUARD:$tag $n times, want 1"; fi
  done
done

echo "── census (grammar-derived cross product, both classifiers)"
CENSUS_STATUSES=(A M D R100 C100 T U M99)
CENSUS_MODES=(000000 100644 100755 120000 160000)
census_expect() { # <status> <old> <new> — only the two ordinary-markdown tuples may skip
  case "$1" in A|M|D|R100|C100|T|U|M99) ;; *) echo unclassified; return ;; esac
  if { [ "$1" = A ] && [ "$2" = 000000 ] && [ "$3" = 100644 ]; } || { [ "$1" = M ] && [ "$2" = 100644 ] && [ "$3" = 100644 ]; }; then
    echo false
  else
    echo true
  fi
}
for c in "${CLASSIFIERS[@]}"; do
  checked=0; bad=0; falses=0
  for st in "${CENSUS_STATUSES[@]}"; do
    case "$st" in R100|C100) cpath=$'knowledge-base/a.md\tknowledge-base/b.md' ;; *) cpath="knowledge-base/a.md" ;; esac
    for om in "${CENSUS_MODES[@]}"; do
      for nm in "${CENSUS_MODES[@]}"; do
        want="$(census_expect "$st" "$om" "$nm")"
        got="$(raw_row "$st" "$om" "$nm" "$cpath" | bash "$REPO_ROOT/$c" pull_request 2>/dev/null)"
        checked=$((checked + 1))
        [ "$got" = false ] && falses=$((falses + 1))
        [ "$got" = "$want" ] || bad=$((bad + 1))
      done
    done
  done
  want_n=$(( ${#CENSUS_STATUSES[@]} * ${#CENSUS_MODES[@]} * ${#CENSUS_MODES[@]} ))
  if [ "$checked" -eq "$want_n" ] && [ "$bad" -eq 0 ] && [ "$falses" -eq 2 ]; then
    pass "$c census: $checked tuples, exactly 2 skip, 0 mismatches"
  else
    fail "$c census: checked=$checked (want $want_n) mismatches=$bad skips=$falses (want 2)"
  fi
done

echo "── mutation battery (sed mutants on mktemp copies, both classifiers)"
PROBE_WANT=(); PROBE_ROWS=()
probe() { PROBE_WANT+=("$1"); PROBE_ROWS+=("$2"); }
probe false "$(arow knowledge-base/a.md)"
probe false "$(mrow README.md)"
probe true  "$(raw_row A 000000 120000 knowledge-base/x.md)"
probe true  "$(raw_row A 000000 160000 knowledge-base/x.md)"
probe true  "$(raw_row A 000000 100755 knowledge-base/x.md)"
probe true  "$(raw_row M 100644 100755 README.md)"
probe true  "$(raw_row M 100755 100644 knowledge-base/x.md)"
probe true  "$(raw_row A 100644 100644 knowledge-base/x.md)"
probe true  "$(raw_row T 100644 100644 knowledge-base/x.md)"
probe true  "$(raw_row D 100644 100644 knowledge-base/x.md)"
probe true  "$(raw_row M99 100644 100644 knowledge-base/x.md)"
probe true  $'M\tknowledge-base/a.md\n'
probe true  $'knowledge-base/a.md\n'
probe true  ''
probe true  "$(arow knowledge-base/a.md; raw_row A 000000 120000 knowledge-base/b.md)"
probe true  "$(raw_row A 000000 120000 knowledge-base/b.md; arow knowledge-base/a.md)"
probe_mismatches() { # <script> -> prints the number of probes whose verdict differs from the expectation
  local script="$1" i got n=0
  for i in "${!PROBE_ROWS[@]}"; do
    got="$(printf '%s' "${PROBE_ROWS[$i]}" | bash "$script" pull_request 2>/dev/null)"
    [ "$got" = "${PROBE_WANT[$i]}" ] || n=$((n + 1))
  done
  echo "$n"
}
n_false=0; n_true=0
for w in "${PROBE_WANT[@]}"; do if [ "$w" = false ]; then n_false=$((n_false + 1)); else n_true=$((n_true + 1)); fi; done
if [ "$n_false" -ge 1 ] && [ "$n_true" -ge 1 ]; then pass "probe set holds both polarities (false=$n_false true=$n_true)"; else fail "probe set lacks a polarity (false=$n_false true=$n_true)"; fi
for pol in false true; do
  assert_fixture_dir "$SBX"
  printf '#!/usr/bin/env bash\nprintf "%s\\n"\n' "$pol" > "$SBX/stub-$pol.sh"
  if [ "$(probe_mismatches "$SBX/stub-$pol.sh")" -gt 0 ]; then pass "probe set rejects an always-$pol classifier"; else fail "probe set cannot tell an always-$pol classifier from the real one"; fi
done

path_arm_count() { awk '/^  case "\$path" in/,/^  esac/' "$1" | grep -cE '^ {4}[^ ]' || true; }
MUTANT_IDS=(modenew-deleted old-mod-open old-add-open mode-widened grammar-fallthrough saw-any-deleted first-row-only status-open fourth-arm)
if [ "${#MUTANT_IDS[@]}" -ne 9 ]; then printf 'FATAL: mutant list length %s, want exactly 9\n' "${#MUTANT_IDS[@]}" >&2; exit 1; fi
mutate() { # <id> <in> <out>
  case "$1" in
    modenew-deleted)     sed '/# GUARD:MODE-NEW$/d' "$2" > "$3" ;;
    old-mod-open)        sed '/# GUARD:MODE-OLD-MOD$/c\    M) ;;                  # GUARD:MODE-OLD-MOD' "$2" > "$3" ;;
    old-add-open)        sed '/# GUARD:MODE-OLD-ADD$/c\    A) ;;                  # GUARD:MODE-OLD-ADD' "$2" > "$3" ;;
    mode-widened)        sed '/# GUARD:MODE-NEW$/c\  [[ "$nm" == 100[67]* ]] || emit true   # GUARD:MODE-NEW' "$2" > "$3" ;;
    grammar-fallthrough) sed '/# GUARD:ROW-GRAMMAR$/c\  [[ "$line" =~ $row_re ]] || BASH_REMATCH=(z 100644 100644 M "$line")   # GUARD:ROW-GRAMMAR' "$2" > "$3" ;;
    saw-any-deleted)     sed '/\[ "\$saw_any" -eq 1 \] || emit true/d' "$2" > "$3" ;;
    first-row-only)      sed '/^done$/i\  break' "$2" > "$3" ;;
    status-open)         sed '/# GUARD:STATUS$/c\    *) ;;                  # GUARD:STATUS' "$2" > "$3" ;;
    fourth-arm)          sed '/^  case "\$path" in/a\    docs/*) ;;' "$2" > "$3" ;;
    *) return 2 ;;
  esac
}
for c in "${CLASSIFIERS[@]}"; do
  cname="$(basename "$c" .sh)"
  ctl="$SBX/$cname.control.sh"
  assert_fixture_dir "$SBX"
  cp "$REPO_ROOT/$c" "$ctl"
  ctl_mm="$(probe_mismatches "$ctl")"; ctl_arms="$(path_arm_count "$ctl")"
  if [ "$ctl_mm" -eq 0 ] && [ "$ctl_arms" -eq 3 ]; then pass "$cname: unmutated control passes the probe set (3 path arms)"; else fail "$cname: unmutated control is not green (mismatches=$ctl_mm arms=$ctl_arms)"; fi
  for id in "${MUTANT_IDS[@]}"; do
    mut="$SBX/$cname.$id.sh"
    mutate "$id" "$ctl" "$mut"
    if cmp -s "$ctl" "$mut"; then fail "$cname/$id: mutation did NOT land (file unchanged)"; continue; fi
    if ! bash -n "$mut" 2>/dev/null; then fail "$cname/$id: mutant is not valid bash"; continue; fi
    if ! { printf '%s' "$(arow knowledge-base/a.md)" | bash "$mut" pull_request >/dev/null 2>&1; }; then fail "$cname/$id: mutant crashes on an ordinary row (would count RED for the wrong reason)"; continue; fi
    mm="$(probe_mismatches "$mut")"; arms="$(path_arm_count "$mut")"
    if [ "$mm" -gt 0 ] || [ "$arms" -ne 3 ]; then pass "$cname/$id: RED (mismatches=$mm arms=$arms)"; else fail "$cname/$id: SURVIVED (mismatches=0 arms=3)"; fi
  done
done

echo "── parity (the two duplicated parse blocks are byte-identical)"
block_of() { awk '/^  # BEGIN mode-aware-row-parse$/{f=1; next} /^  # END mode-aware-row-parse$/{f=0} f{print}' "$1"; }
parity_ok() { # <a> <b>
  local f
  for f in "$1" "$2"; do
    [ "$(grep -cE '^  # BEGIN mode-aware-row-parse$' "$f")" -eq 1 ] || return 1
    [ "$(grep -cE '^  # END mode-aware-row-parse$' "$f")" -eq 1 ] || return 1
  done
  assert_fixture_dir "$SBX"
  block_of "$1" > "$SBX/block.a"; block_of "$2" > "$SBX/block.b"
  [ -s "$SBX/block.a" ] && cmp -s "$SBX/block.a" "$SBX/block.b"
}
PA="$REPO_ROOT/${CLASSIFIERS[0]}"; PB="$REPO_ROOT/${CLASSIFIERS[1]}"
if parity_ok "$PA" "$PB"; then pass "the two mode-aware-row-parse blocks are present once each and byte-identical"; else fail "mode-aware-row-parse blocks differ, are missing, or are duplicated"; fi
assert_fixture_dir "$SBX"
cp "$PB" "$SBX/par.b"
assert_fixture_dir "$SBX"
sed 's/\[ "\$nm" = 100644 \]/[ "$nm" = 100645 ]/' "$PA" > "$SBX/par.a1"
if cmp -s "$PA" "$SBX/par.a1"; then fail "parity mutant 1 did not land"; elif parity_ok "$SBX/par.a1" "$SBX/par.b"; then fail "parity mutant 1 (one literal edited in one block) SURVIVED"; else pass "parity mutant 1: a literal edited in one block is detected"; fi
assert_fixture_dir "$SBX"
sed '/^  # END mode-aware-row-parse$/d' "$PA" > "$SBX/par.a2"
if cmp -s "$PA" "$SBX/par.a2"; then fail "parity mutant 2 did not land"; elif parity_ok "$SBX/par.a2" "$SBX/par.b"; then fail "parity mutant 2 (END marker deleted) SURVIVED"; else pass "parity mutant 2: a deleted END marker is detected"; fi
assert_fixture_dir "$SBX"
{ cat "$PA"; printf '  # BEGIN mode-aware-row-parse\n  :\n  # END mode-aware-row-parse\n'; } > "$SBX/par.a3"
if parity_ok "$SBX/par.a3" "$SBX/par.b"; then fail "parity mutant 3 (second marker pair) SURVIVED"; else pass "parity mutant 3: a second marker pair is detected"; fi
assert_fixture_dir "$SBX"
printf '#!/usr/bin/env bash\n:\n' > "$SBX/par.a4"
if parity_ok "$SBX/par.a4" "$SBX/par.b"; then fail "parity mutant 4 (no markers at all) SURVIVED"; else pass "parity mutant 4: a file without markers is detected"; fi
assert_fixture_dir "$SBX"
sed '2s/.*/# a header line that differs outside the markers/' "$PA" > "$SBX/par.a5"
if cmp -s "$PA" "$SBX/par.a5"; then fail "parity control did not land"; elif parity_ok "$SBX/par.a5" "$SBX/par.b"; then pass "parity control: a header differing OUTSIDE the markers still passes"; else fail "parity is over-strict: a header edit outside the markers failed it"; fi

total=$((PASS + FAIL))
if [ "$total" -lt 113 ]; then
  printf '[FATAL] assertion floor: only %s assertions ran, want >=113\n' "$total" >&2
  exit 1
fi
echo
echo "Guard: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
