#!/usr/bin/env bash
# Guard 1 (P1a) — a git write must not be retargetable at the caller's repository by an EMPTY
# directory operand (#7652).
#
# THE MECHANISM, because it is not obvious and the intuition is wrong in the dangerous direction.
# `git -C ""` does not error. It silently operates on the current directory:
#
#     d=$(mktemp -d); cd "$d" && git init -q .
#     git -C "" config user.name probe-value     # rc=0
#     git -C "$d" config --get user.name         # -> probe-value
#
# So a fixture helper that takes its directory positionally and is called with an empty argument
# writes into whatever repository the caller happens to be standing in. Under TEST_GROUP=scripts
# that is the developer's live worktree, and its `--local` config is the SHARED bare-repo file
# every worktree on the machine inherits. That is not hypothetical: on 2026-08-20 `commit.gpgsign`
# was flipped to false there and six commits were created unsigned before anyone noticed — a write
# that is invisible until somebody audits signatures, unlike a stray commit which shows in
# `git log`.
#
# WHY THE SIBLING GUARD CANNOT SEE THIS. `fixture-cd-containment.test.sh` forbids the shape where a
# failed `cd` redirects a write. Here there is no `cd` at all, so `cdx()` is inapplicable and the
# containment scanner — which keys on cd-then-write — never fires. Two rules, one shared corpus
# walk (`lib/fixture-scan.py`), so the composition is code rather than a comment asking two files
# to stay in step.
#
# SCOPE: P1a, the EMPTY operand, only. P1b — a RELATIVE operand, and the `rm -rf ""` / `mv a ""` /
# redirection families — is tracked separately and deliberately, because the verbs do not share a
# failure mode: measured, only `git -C` WIDENS on an empty operand; `rm -rf ""` is a silent no-op
# and `mv a ""` errors. Folding them in silently would claim coverage this does not have.
set -uo pipefail
export TMPDIR="${TMPDIR:-/var/tmp}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
SCANNER="$SCRIPT_DIR/lib/fixture-scan.py"
BASELINE="$SCRIPT_DIR/fixture-dir-operand-assert.baseline.txt"
HELPERS="$SCRIPT_DIR/test-helpers.sh"

[[ -f "$SCANNER" ]]  || { echo "FATAL: missing $SCANNER" >&2; exit 2; }
[[ -f "$BASELINE" ]] || { echo "FATAL: missing $BASELINE" >&2; exit 2; }
[[ -f "$HELPERS" ]]  || { echo "FATAL: missing $HELPERS" >&2; exit 2; }

scan_counts() { # scan_counts <repo-root> -> "<count>\t<path>" rows, sorted by path
  python3 "$SCANNER" --rule operand --repo "$1" 2>/dev/null \
    | grep -E '^[^ ]+:[0-9]+:' | cut -d: -f1 | sort | uniq -c \
    | awk '{printf "%d\t%s\n", $1, $2}' | LC_ALL=C sort -k2
}

if [[ "${1:-}" == "--write-baseline" ]]; then
  tmp="$(mktemp)"
  grep '^#' "$BASELINE" > "$tmp"
  scan_counts "$REPO_ROOT" >> "$tmp"
  mv "$tmp" "$BASELINE"
  echo "baseline rewritten: $(grep -vc '^#' "$BASELINE") files"
  exit 0
fi

TMP_ROOT=$(mktemp -d -t fixtureoperand.XXXXXXXX) || { echo "FATAL: no scratch root" >&2; exit 2; }
: "${TMP_ROOT:?}"
[[ "$TMP_ROOT" == /* && -d "$TMP_ROOT" ]] || { echo "FATAL: bad scratch root" >&2; exit 2; }
readonly TMP_ROOT
trap 'rm -rf -- "$TMP_ROOT"' EXIT INT TERM

passes=0; fails=0; asserted=0
pass() { echo "  PASS: $1"; passes=$((passes + 1)); }
fail() { echo "  FAIL: $1"; fails=$((fails + 1)); }
# Incremented at the CALL SITE. A counter living inside the helper it polices cannot detect that
# helper being neutered, which is the whole point of the conservation check at the bottom (ADR-193).
ck() { asserted=$((asserted + 1)); }

echo "fixture-dir-operand-assert.test.sh"

# --- A. The live corpus, against the shrink-only baseline ----------------------------------------

# ROW 6 — the guard's own dispatch. A scanner pointed at an empty corpus reports SITES=0, which is
# byte-identical to a clean tree and is the shape in which this whole family of guards fails.
#
# Reported DIRECTLY, never through pass()/fail(): an anti-vacuity check routed through the verdict
# machinery it exists to police cannot fire when that machinery is what broke. Measured — routing
# this one through fail() made the whole suite exit 0 under `guard-vacuity-floor.test.sh`'s neutered
# -helper mutant, which is the same defect one level up (ADR-193).
FILES_SCANNED=$(python3 "$SCANNER" --rule operand --repo "$REPO_ROOT" 2>/dev/null | sed -n 's/^FILES=//p')
if [[ "${FILES_SCANNED:-0}" -le 100 ]]; then
  printf '[FATAL] corpus is empty or tiny (FILES=%s) — SITES=0 over no files is not a clean tree.\n' \
    "${FILES_SCANNED:-unset}" >&2
  exit 1
fi
echo "  (corpus: ${FILES_SCANNED} tracked *.sh files scanned)"

ck
live="$TMP_ROOT/live.txt"; base="$TMP_ROOT/base.txt"
scan_counts "$REPO_ROOT" > "$live"
grep -v '^#' "$BASELINE" | grep -v '^[[:space:]]*$' | LC_ALL=C sort -k2 > "$base"
violations=""
while IFS=$'\t' read -r n f; do
  [[ -n "$f" ]] || continue
  bn=$(awk -F'\t' -v p="$f" '$2==p {print $1}' "$base")
  if [[ -z "$bn" ]]; then
    violations="$violations
    NEW FILE  $f ($n site(s)) — not in the baseline at all"
  elif (( n > bn )); then
    violations="$violations
    REGREW    $f ($bn -> $n)"
  fi
done < "$live"
if [[ -z "$violations" ]]; then
  pass "no file exceeds its baseline and no new file appeared"
else
  fail "the P1a ratchet was violated:$violations"
fi

# --- B. ROW 7 — the ratchet is enforced, not merely documented ------------------------------------
# Shrink the baseline for one file with no matching remediation and the check must red. Without
# this row the baseline is a comment.
ck
sandbox_base="$TMP_ROOT/shrunk.txt"
awk -F'\t' 'BEGIN{OFS="\t"} /^#/{print; next} NR>0 && $1>1 && !done {print $1-1, $2; done=1; next} {print}' "$base" > "$sandbox_base"
shrunk_violation=""
while IFS=$'\t' read -r n f; do
  [[ -n "$f" ]] || continue
  bn=$(awk -F'\t' -v p="$f" '$2==p {print $1}' "$sandbox_base")
  if [[ -z "$bn" ]] || (( n > bn )); then shrunk_violation="yes"; fi
done < "$live"
if [[ -n "$shrunk_violation" ]]; then
  pass "a baseline shrunk without remediation is detected (the ratchet bites)"
else
  fail "shrinking the baseline changed nothing — the ratchet is decorative"
fi

# --- C. Definition equality: every copy of the assertion is the SAME assertion ----------------------
# The scanner recognises a NAME TOKEN, so a file could satisfy it with an empty shell called
# `assert_fixture_dir`. `cdx()` — the precedent this inlining follows — has exactly that gap.
# Bodies are compared with comments and blank lines stripped: a copy is allowed to carry different
# surrounding prose, never different behaviour.
extract_body() { # extract_body <file>
  awk '/^assert_fixture_dir\(\) \{/,/^\}/' "$1" \
    | sed -e 's/[[:space:]]*#.*$//' -e '/^[[:space:]]*$/d' -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//'
}
ck
canon="$(extract_body "$HELPERS")"
if [[ -n "$canon" ]] && grep -q 'exit 2' <<<"$canon"; then
  pass "the canonical assertion is defined in test-helpers.sh and refuses with exit 2"
else
  fail "canonical assertion missing or does not refuse"
fi

ck
drift=""; copies=0
while IFS= read -r f; do
  [[ "$f" == "$HELPERS" ]] && continue
  copies=$((copies + 1))
  b="$(extract_body "$f")"
  [[ "$b" == "$canon" ]] || drift="$drift
    $(realpath --relative-to="$REPO_ROOT" "$f")"
done < <(grep -rl '^assert_fixture_dir() {' "$REPO_ROOT" --include='*.sh' 2>/dev/null)
# Same reasoning as the corpus floor above: zero inline copies makes the drift comparison
# vacuous, so it is reported directly rather than through the helper it would be policing.
if [[ $copies -lt 1 ]]; then
  printf '[FATAL] no inline assert_fixture_dir copies found — the drift arm would pass vacuously.\n' >&2
  exit 1
fi
if [[ -z "$drift" ]]; then
  pass "all $copies inline definition(s) are byte-equal to the canonical body"
else
  fail "inline definition drift:$drift"
fi

# --- D. ROW 5 — a WEAKENED inline body is caught by the equality rule --------------------------------
ck
weak="$TMP_ROOT/weak.sh"
{ printf '#!/usr/bin/env bash\n'; printf 'assert_fixture_dir() {\n  [[ -n "${1-}" ]] || exit 2\n}\n'; } > "$weak"
if [[ "$(extract_body "$weak")" != "$canon" ]]; then
  pass "a weakened (non-empty-only) body is not byte-equal to the canonical one"
else
  fail "a weakened body compared equal — the name token is satisfiable by an empty shell"
fi

# --- E. The scanner's own behaviour, on synthetic fixtures ------------------------------------------
# Written here rather than extracted from tracked files by name: a by-name extraction is the
# substring-splice shape this guard rejects everywhere else.
# Fixture bodies arrive on STDIN via a quoted heredoc, never as a single-quoted argument.
# That is not style: a multi-line single-quoted string is CODE LINES as far as any line-oriented
# scanner is concerned, so this suite's own fixtures registered as four live P1a sites and the
# ratchet flagged the guard as a new offender. A heredoc body is data, which is what they are —
# and it is the same convention `fixture-cd-containment.test.sh` already uses for its A5 case.
synth() { # synth <name>  (body on stdin)
  local d="$TMP_ROOT/synth-$1"; mkdir -p "$d"
  cat > "$d/case.sh"
  python3 "$SCANNER" --rule operand "$d/case.sh" 2>/dev/null | sed -n 's/^SITES=//p'
}

# ROW 1/2 — the canonical instance, and a SECOND file after the first is compliant. A check that
# stops at the first member is itself an instance of this family.
ck
n=$(synth row1 <<'SYNTHEOF'
helper() {
  local dir="$1"
  git -C "$dir" config commit.gpgsign false
}
SYNTHEOF
)
if [[ "$n" == "1" ]]; then pass "ROW 1: an unasserted positional binding is flagged"
else fail "ROW 1: expected 1 site, got ${n:-none}"; fi

ck
d2="$TMP_ROOT/two"; mkdir -p "$d2"
cat > "$d2/clean.sh" <<'SYNTHEOF'
a() {
  local dir="$1"
  assert_fixture_dir "$dir"
  git -C "$dir" commit --allow-empty -m x
}
SYNTHEOF
cat > "$d2/dirty.sh" <<'SYNTHEOF'
b() {
  local dir="$1"
  git -C "$dir" commit --allow-empty -m x
}
SYNTHEOF
n=$(python3 "$SCANNER" --rule operand "$d2/clean.sh" "$d2/dirty.sh" 2>/dev/null | sed -n 's/^SITES=//p')
if [[ "$n" == "1" ]]; then pass "ROW 2: a second offending file is still found after the first is clean"
else fail "ROW 2: expected 1 site across two files, got ${n:-none}"; fi

# ROW 3 — positional at the USE site, with no intermediate variable. Live in two files today.
ck
n=$(synth row3 <<'SYNTHEOF'
commit_all() { git -C "$1" add -A && git -C "$1" commit -m x; }
SYNTHEOF
)
if [[ "${n:-0}" -ge 1 ]]; then pass "ROW 3: git -C \"\$1\" at the use site is flagged"
else fail "ROW 3: expected >=1 site, got ${n:-none}"; fi

# ROW 4 — bound from a command substitution in its LIVE shape, not the mktemp special case.
ck
n=$(synth row4 <<'SYNTHEOF'
p=$(new_repo fixture)
git -C "$p" checkout -q -b probe
SYNTHEOF
)
if [[ "$n" == "1" ]]; then pass "ROW 4: a \$(helper ...) binding is flagged"
else fail "ROW 4: expected 1 site, got ${n:-none}"; fi

# `init` is named explicitly in the verb list: it returns 0 and REINITIALISES the caller's
# repository, which the intuition "re-init is harmless" would otherwise cull.
ck
n=$(synth init <<'SYNTHEOF'
h() {
  local d="$1"
  git -C "$d" init -q
}
SYNTHEOF
)
if [[ "$n" == "1" ]]; then pass "git -C \"\" init is a write verb (it reinitialises the caller's repo)"
else fail "init not treated as a write verb, got ${n:-none}"; fi

# --- F. Must-PASS. None of these is the canonical shape, and each would be a false positive. --------
ck
n=$(synth guarded <<'SYNTHEOF'
h() {
  local d
  d=$(mktemp -d) || return 1
  git -C "$d" commit --allow-empty -m x
}
SYNTHEOF
)
if [[ "$n" == "0" ]]; then pass "must-PASS: \`d=\$(mktemp -d) || return 1\` is guarded"
else fail "must-PASS regression: guarded mktemp flagged (${n})"; fi

ck
n=$(synth reads <<'SYNTHEOF'
h() {
  local d="$1"
  git -C "$d" status
  git -C "$d" worktree list
  git -C "$d" rev-parse HEAD
}
SYNTHEOF
)
if [[ "$n" == "0" ]]; then pass "must-PASS: reads are not writes"
else fail "must-PASS regression: a read was flagged (${n})"; fi

ck
n=$(synth derived <<'SYNTHEOF'
h() {
  local d="$1"
  git -C "$d/work" commit --allow-empty -m x
}
SYNTHEOF
)
if [[ "$n" == "0" ]]; then pass "must-PASS: a DERIVED operand (\$d/work) is outside P1a"
else fail "must-PASS regression: derived operand flagged (${n})"; fi

ck
n=$(synth heredoc <<'SYNTHEOF'
cat > /tmp/x <<EOS
h() {
  local d="$1"
  git -C "$d" commit --allow-empty -m x
}
EOS
SYNTHEOF
)
if [[ "$n" == "0" ]]; then pass "must-PASS: the forbidden shape inside a heredoc body is data, not code"
else fail "must-PASS regression: heredoc body flagged (${n})"; fi

ck
n=$(synth absolute <<'SYNTHEOF'
h() {
  local d="/tmp/fixture-abs"
  git -C "$d" commit --allow-empty -m x
}
SYNTHEOF
)
if [[ "$n" == "0" ]]; then pass "must-PASS: a literal binding cannot be empty"
else fail "must-PASS regression: literal binding flagged (${n})"; fi

ck
n=$(synth trapstr <<'SYNTHEOF'
WORK=$(mktemp -d)
trap '"'"'rm -rf "$WORK"'"'"' EXIT
git -C "$WORK" commit --allow-empty -m x
SYNTHEOF
)
# Stated explicitly rather than left to the regex: the `trap` string is a P1b concern (a relative
# or empty operand to `rm -rf`), and the git write on the following line IS in scope and flagged.
if [[ "${n:-0}" -ge 1 ]]; then pass "a trap string does not suppress the git write beside it (P1b stays P1b)"
else fail "expected the git write to be flagged alongside the trap string, got ${n:-none}"; fi

# --- G. GUARD 3 — the canonical body refuses, and refuses BEFORE it writes ---------------------------
# Exercised on a synthetic helper carrying the canonical bytes. Guard 1 (arm C) guarantees the token
# is present at every site and that inline copies match canonical; this guarantees canonical
# refuses. The two compose without a hand-maintained (file, function) table.
probe_repo() {
  local d="$TMP_ROOT/g3-$1"; mkdir -p "$d"
  git -C "$d" init -q -b main >/dev/null 2>&1
  git -C "$d" config user.email t@t.dev; git -C "$d" config user.name t
  printf '%s\n' "$d"
}
run_canon() { # run_canon <operand> ; sets G3_RC, and runs with CWD inside the probe repo
  local repo="$1" operand="$2"
  ( cd "$repo" && bash -c '
      '"$canon_raw"'
      assert_fixture_dir "$1"
      git -C "$1" config commit.gpgsign false
    ' _ "$operand" ) >/dev/null 2>&1
  G3_RC=$?
}
canon_raw="$(awk '/^assert_fixture_dir\(\) \{/,/^\}/' "$HELPERS")"

for case_name in empty relative bareslash; do
  ck
  r=$(probe_repo "$case_name")
  case "$case_name" in
    empty)     op="" ;;
    relative)  op="relative/path" ;;
    bareslash) op="/" ;;
  esac
  before=$(git -C "$r" config --local --list | LC_ALL=C sort | sha256sum)
  run_canon "$r" "$op"
  after=$(git -C "$r" config --local --list | LC_ALL=C sort | sha256sum)
  # BOTH halves: a non-zero rc with the write already done is exactly the "assertion below the
  # first write" mutation, and post-return state is the only thing that can see it.
  if [[ "$G3_RC" -ne 0 && "$before" == "$after" ]]; then
    pass "GUARD 3: a $case_name operand is refused and the probe repo is byte-identical after"
  else
    fail "GUARD 3: $case_name — rc=$G3_RC, config changed=$([[ "$before" == "$after" ]] && echo no || echo YES)"
  fi
done

ck
r=$(probe_repo absolute)
run_canon "$r" "$r"
if [[ "$G3_RC" -eq 0 ]]; then pass "GUARD 3: an absolute fixture dir is accepted (the guard is not a blanket refusal)"
else fail "GUARD 3: an absolute operand was refused (rc=$G3_RC)"; fi

# --- H. ROW 8 — the harness row. Neuter fail() and conservation must fire first. ---------------------
# Not a mutation of the SUT: a suite whose only gate is a failure counter exits 0 having asserted
# nothing, and that is invisible to every row above.
ck
if [[ "$(type -t fail)" == "function" ]] && declare -f fail | grep -q 'fails=\$((fails + 1))'; then
  pass "fail() still moves its counter (the conservation check below can therefore fire)"
else
  fail "fail() no longer increments — every verdict above is unreportable"
fi

# --- Accounting. Emitted DIRECTLY, never through pass()/fail(). ---------------------------------------
if [[ $((passes + fails)) -ne $asserted ]]; then
  printf '\n[FATAL] accounting: passes+fails (%d) != asserted (%d).\n' "$((passes + fails))" "$asserted" >&2
  if [[ $((passes + fails)) -lt $asserted ]]; then
    printf '  An assertion was counted but its verdict was not recorded — that is what a neutered pass()/fail() looks like.\n' >&2
  else
    printf '  A verdict was recorded without a counted case — a call site is missing its increment.\n' >&2
  fi
  exit 1
fi

MIN_ASSERTIONS=17
if [[ $passes -lt $MIN_ASSERTIONS ]]; then
  echo "[FAIL] only ${passes} assertion(s) PASSED, below the floor of ${MIN_ASSERTIONS}" >&2
  exit 1
fi

echo
echo "fixture-dir-operand-assert.test.sh: ${passes} passed, ${fails} failed, ${asserted} assertion(s) executed (floor ${MIN_ASSERTIONS})"
[[ $fails -eq 0 ]] || exit 1
