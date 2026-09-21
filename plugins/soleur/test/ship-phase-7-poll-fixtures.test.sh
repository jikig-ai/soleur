#!/usr/bin/env bash
# AC9 fixture for plan 2026-05-25 (issue #4387), extended for #8339: extracts
# the Phase 7 poll bash block from plugins/soleur/skills/ship/SKILL.md (and its
# mirror in merge-pr/SKILL.md §5.2) and exercises scripted scenarios against
# mocked `gh` / `git` / `sleep`:
#
#   0. harness self-check — the scenario subshell runs with pipefail OFF
#      (Monitor shell semantics; under pipefail the #8339 bug is invisible)
#   1. clean MERGED on tick 3
#   2. required-check failure on tick 5 (exit on first failure)
#   3. BEHIND saturation through 6 syncs then structured warning
#   4. DIRTY exit (real conflict: merge-tree rc=1)
#   4b. DIRTY but locally clean (merge-tree rc=0) → BEHIND auto-sync, not dirty-exit
#   4c. DIRTY but the classifying fetch fails → reported as a fetch failure, not a conflict
#   5. absent required check (CI not yet registered) — does NOT exit
#   6. merge conflict during BEHIND auto-sync → abort + stop, never "pushed"
#   6b. merge refused to start (rc 2, no MERGE_HEAD) → truthful message, nothing aborted
#   6c. merge already in progress (MERGE_HEAD pre-exists) → not touched, stop
#   6d. MERGE_HEAD appears during the fetch window (merge rc 128) → not ours, not aborted
#   6e. git merge --abort itself fails → reported, poll still stops
#   6f. scenario 6 under an errexit host shell (`set -e`) → same outcome, shell survives
#   6g. detached HEAD → refused before any fetch
#   6h. rebase in progress (no MERGE_HEAD) → refused before any fetch
#   7. push fails after a clean merge → "git push failed after merge", stop
#   8. fetch fails → attempt skipped and counted, loop continues to behind_exhausted
#   9. success path characterization — one sync, re-fetch sees MERGED, no tick 2
#   10. real git (no mock, ship block): conflict aborts cleanly; pre-staged resolution
#       survives; push rejection retains the merge commit; rebase-in-progress and
#       detached HEAD are refused
#   11. not inside a worktree → BEHIND auto-sync disabled; BEHIND is a named stop
#   13/13b/13c. plugin root with an old script / unset / plugin.json not soleur →
#       precondition line naming the failed check, then [ship.phase7.behind_no_sync]
#   14. PR set to `#4387` → refused before the poll (exit 2)
#   15. fetch fails then a push → the hatch counts pushes, so it does not fire
#   16. sync no-op (exit 11) → sync_noop line, not counted, never "pushed"
#
# Every row also asserts: no git call fell through to the mock catch-all, and no
# temp file (the per-poll snapshot) outlived the block. CLAUDE_PLUGIN_ROOT is a
# temp COPY of the plugin root, never the live checkout.
#
# Every scenario except 0 and 10 runs against BOTH the canonical block and the
# merge-pr mirror (`:ship` / `:merge-pr` label suffixes). Every scenario also
# asserts that no `[ship.phase7.*]` line reached stderr — the Monitor tool
# streams stdout only.
#
# Also asserts mirror-parity between ship/SKILL.md's canonical block and
# merge-pr/SKILL.md's derived mirror so the two state machines do not drift.
#
# Synthesized-only — no live `gh` calls, no network, no real PR
# (per cq-test-fixtures-synthesized-only). Run via:
#
#   bash plugins/soleur/test/ship-phase-7-poll-fixtures.test.sh

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
SKILL="$REPO_ROOT/plugins/soleur/skills/ship/SKILL.md"
MIRROR="$REPO_ROOT/plugins/soleur/skills/merge-pr/SKILL.md"

# ONE owning trap for every tempfile and tempdir this suite allocates (ADR-129,
# enforced by `scripts/lint-trap-tempfile-ownership.py`). Registered at each
# call site in the parent shell — never through a `$(_own …)` helper, which
# runs in a subshell and appends to a copy. Installed BEFORE test-helpers.sh
# is sourced: the helper composes its incident-sandbox cleanup over whatever
# EXIT trap is already present, whereas a trap installed afterwards would
# replace the helper's and leak the sandbox on every run.
_TMP_OWNED=()
trap 'rm -rf "${_TMP_OWNED[@]:-}"' EXIT

# Arms the #7833 git-location tripwire and provides `git_fixture_env` +
# `assert_fixture_dir` for scenario 10's real-git fixture. The helpers enable
# errexit; this suite accumulates verdicts and exits at the end, so it is
# switched back off immediately (pipefail stays on at file scope — the
# scenario subshell turns it off explicitly, and scenario 0 proves that).
# shellcheck source=./test-helpers.sh
source "$REPO_ROOT/plugins/soleur/test/test-helpers.sh"
set +e

PASS=0; FAIL=0
pass() { echo "  pass: $1"; PASS=$((PASS+1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }

# fail() positive control: a counter that cannot move makes every row vacuous.
# Reported via printf+exit, never through pass/fail (the machinery under test).
_fail0=$FAIL
fail "positive control (expected, unwound)" >/dev/null
if [[ "$FAIL" -ne $((_fail0 + 1)) ]]; then printf 'FATAL: fail() did not increment FAIL\n' >&2; exit 1; fi
FAIL=$_fail0

# CLAUDE_PLUGIN_ROOT for every scenario is a TEMP COPY of the plugin's identity file
# and scripts/, never the live checkout: the block runs `cp`/`rm` against paths under
# that root, and a mutant that aliases SYNC_SNAP to SYNC_SH would otherwise delete the
# real sync-pr-behind.sh from the working tree.
PLUGIN_COPY="$(mktemp -d)"
_TMP_OWNED+=("$PLUGIN_COPY")
assert_fixture_dir "$PLUGIN_COPY"
{ cp -R "$REPO_ROOT/plugins/soleur/.claude-plugin" "$PLUGIN_COPY/" \
    && cp -R "$REPO_ROOT/plugins/soleur/scripts" "$PLUGIN_COPY/"; } \
  || { printf 'FATAL: could not copy the plugin root into %s\n' "$PLUGIN_COPY" >&2; exit 1; }

# ---------------------------------------------------------------------------
# Extract the Phase 7 bash block. Two anchors:
#  - structural: the `<!-- phase-7-poll-block:start -->` / `:end` fence
#    markers (also present in the canonical block as comments)
#  - content fingerprint: the block must contain `MAX_BEHIND_SYNCS` AND
#    `mergeStateStatus` AND `bucket == "fail"` — three load-bearing tokens
#    whose absence indicates we extracted the wrong block (or the block
#    was gutted by a future refactor that the fixture has not caught up to)
# ---------------------------------------------------------------------------
extract_block() {
  local source_file="$1"
  awk '
    /<!-- phase-7-poll-block:start -->/ { in_block=1; next }
    /<!-- phase-7-poll-block:end -->/ { in_block=0; next }
    in_block && /^```bash$/ { next }
    in_block && /^```$/ { next }
    in_block { print }
  ' "$source_file"
}

BLOCK_FILE="$(mktemp)"
_TMP_OWNED+=("$BLOCK_FILE" "$BLOCK_FILE.err")
extract_block "$SKILL" | sed 's/<number>/4387/g' > "$BLOCK_FILE"

if [[ ! -s "$BLOCK_FILE" ]]; then
  fail "could not extract Phase 7 bash block from $SKILL"
  exit 1
fi

# Content fingerprint — three independent tokens
for token in 'MAX_BEHIND_SYNCS' 'mergeStateStatus' 'bucket == "fail"'; do
  if ! grep -q "$token" "$BLOCK_FILE"; then
    fail "extracted block missing fingerprint token: $token (extracted wrong section?)"
    exit 1
  fi
done
pass "Phase 7 block extracted ($(wc -l < "$BLOCK_FILE") lines, 3 fingerprint tokens present)"

# Static syntax check (mitigates Risk 3 — bash heredoc fragility)
if ! bash -n "$BLOCK_FILE" 2>"$BLOCK_FILE.err"; then
  fail "Phase 7 block fails bash -n:"
  sed 's/^/    /' "$BLOCK_FILE.err"
  exit 1
fi
pass "Phase 7 block passes bash -n"

# ---------------------------------------------------------------------------
# Mirror parity: merge-pr/SKILL.md §5.2 carries a derived mirror of the
# canonical block. Assert the structural skeleton matches, then execute the
# mirror under the same scenarios as the canonical block (#8339).
# ---------------------------------------------------------------------------
MIRROR_FILE="$(mktemp)"
_TMP_OWNED+=("$MIRROR_FILE" "$MIRROR_FILE.err")
# The `<number>` substitution is what makes the mirror EXECUTABLE: sourced
# verbatim, `gh pr view <number>` parses `<number>` as an input redirect and
# `$s` degrades to `fetch-error:` on tick 1, breaking before the BEHIND arm.
extract_block "$MIRROR" | sed 's/<number>/4387/g' > "$MIRROR_FILE"
if [[ ! -s "$MIRROR_FILE" ]]; then
  fail "could not extract Phase 7 mirror from $MIRROR"
else
  # The mirror trims canonical prose but must preserve the same load-bearing
  # tokens. Skeletal parity: every fingerprint token from the canonical site
  # is also in the mirror, and the two share the same emit-line classes.
  # The #8339 tokens pin the sync arm: a fix applied to ship only leaves the
  # mirror without them (mutation row 5). `git merge --abort` is deliberately
  # NOT a token — the pre-fix mirror already carries it, so it discriminates
  # nothing.
  for token in 'MAX_BEHIND_SYNCS=6' 'mergeStateStatus' 'bucket == "fail"' \
               '[ship.phase7.required_failed]' '[ship.phase7.dirty]' \
               '[ship.phase7.behind_exhausted]' '*DIRTY*' 'mapfile -t REQUIRED_CHECKS' \
               'is-inside-work-tree' \
               'bash "$SYNC_SNAP" "$PR" --step || sync_rc=$?' \
               'sync-pr-behind.sh exited $sync_rc' '--help 2>/dev/null | grep -q -- '"'"'--step'"'"'' \
               'SYNC_ROOT="$(set +u; printf '"'"'%s'"'"' "${CLAUDE_PLUGIN_ROOT}")"' \
               'fetch_failures=' 'PR="4387"' '[[ $PR =~ ^[0-9]+$ ]] ||' \
               'behind_pushes=$((behind_pushes+1))' '(( behind_pushes == 2 ))' \
               '11) behind_syncs=$((behind_syncs-1))' '[ship.phase7.behind_no_sync]' \
               'trap '"'"'rm -f "$SYNC_SNAP"'"'"' EXIT' 'ADR-179 identity check'; do
    if ! grep -qF -- "$token" "$MIRROR_FILE"; then
      fail "merge-pr mirror missing canonical token: $token"
    fi
  done
  [[ "$FAIL" -eq 0 ]] && pass "merge-pr mirror skeleton matches canonical block"
  if bash -n "$MIRROR_FILE" 2>"$MIRROR_FILE.err"; then
    pass "Phase 7 mirror passes bash -n"
  else
    fail "Phase 7 mirror fails bash -n:"
    sed 's/^/    /' "$MIRROR_FILE.err"
  fi
fi

# ---------------------------------------------------------------------------
# Assertion helper shared by run_scenario and scenario 10. `must_match` is a
# NEWLINE-separated list, one pass/fail per pattern (AND); a single alternation
# ERE cannot express AND and makes mutation rows vacuous. On any miss the
# whole log is dumped once.
# ---------------------------------------------------------------------------
assert_log() {
  local label="$1" logfile="$2" must_match="$3" must_not_match="${4:-}"
  local pat dumped=0
  while IFS= read -r pat; do
    [[ -z "$pat" ]] && continue
    if grep -qE "$pat" "$logfile"; then
      pass "[$label] matched: $pat"
    else
      fail "[$label] did NOT match: $pat"
      if (( dumped == 0 )); then
        echo "    --- scenario output ---"; sed 's/^/      /' "$logfile"; echo "    --- end output ---"; dumped=1
      fi
    fi
  done <<< "$must_match"
  if [[ -n "$must_not_match" ]]; then
    if grep -qE "$must_not_match" "$logfile"; then
      fail "[$label] forbidden pattern present: $must_not_match"
      if (( dumped == 0 )); then
        echo "    --- scenario output ---"; sed 's/^/      /' "$logfile"; echo "    --- end output ---"
      fi
    else
      pass "[$label] forbidden pattern absent: $must_not_match"
    fi
  fi
}

# assert_log self-check: a pattern ABSENT from the log must FAIL, and a forbidden
# pattern PRESENT must FAIL. Driven with output suppressed, then unwound.
_selfcheck_log="$(mktemp)"
_TMP_OWNED+=("$_selfcheck_log")
echo "only this line" > "$_selfcheck_log"
_fail0=$FAIL; _pass0=$PASS
assert_log "selfcheck" "$_selfcheck_log" "pattern-that-is-not-there" "only this" >/dev/null
if [[ "$FAIL" -ne $((_fail0 + 2)) ]]; then
  printf 'FATAL: assert_log did not FAIL a known miss and a present forbidden pattern (FAIL moved %s, want 2)\n' "$((FAIL - _fail0))" >&2; exit 1
fi
FAIL=$_fail0; PASS=$_pass0
rm -f "$_selfcheck_log"

# The Monitor tool streams STDOUT only (stderr lands in the output file and
# raises no notification), so every tagged exit line must be on stdout.
assert_no_tag_on_stderr() {
  local label="$1" errfile="$2"
  if grep -qE 'ship\.phase7\.|\[pr-behind-sync\] kind=' "$errfile"; then
    fail "[$label] tagged line on stderr (Monitor streams stdout only): $(grep -E 'ship\.phase7\.|\[pr-behind-sync\] kind=' "$errfile" | head -1 | cut -c1-120)"
  else
    pass "[$label] no tagged line on stderr"
  fi
}

# ---------------------------------------------------------------------------
# Scenario harness. Each scenario file defines `gh()` (and may override
# `git()` to inject conflict states); `sleep` and `date` are always shadowed
# in the subshell to keep the fixture fast and timestamp-stable.
#
# The subshell runs with pipefail OFF — the Monitor tool's shell does not set
# it, and under pipefail the block's `if ! cmd | tail` guards happen to work,
# so a harness inheriting the file-level `set -o pipefail` is GREEN on the
# behavioural rows (abort sentinel, `pushed` forbid) of the very defect #8339
# exists to catch (measured). Scenario 0 pins this. SCENARIO_SET_E=1 adds
# `set -e` — an errexit host shell is the OTHER environment the block is
# pasted into, and a bare `x="$(cmd)"; rc=$?` capture dies there.
#
# Mock state crosses `$( … )` boundaries via files under $MOCK_STATE, never
# shell variables: the block runs `gh pr view` and all three sync commands
# inside command substitutions, so a variable set inside a mock is lost.
# ---------------------------------------------------------------------------
run_scenario() {
  local label="$1"
  local mocks_file="$2"
  local must_match="$3"
  local must_not_match="${4:-}"
  local block="${5:-$BLOCK_FILE}"
  local logfile errfile
  logfile="$(mktemp)"
  _TMP_OWNED+=("$logfile")
  errfile="$(mktemp)"
  _TMP_OWNED+=("$errfile")
  MOCK_STATE="$(mktemp -d)"
  assert_fixture_dir "$MOCK_STATE"
  _TMP_OWNED+=("$MOCK_STATE")
  export MOCK_STATE

  mkdir -p "$MOCK_STATE/cwd" "$MOCK_STATE/tmp"

  (
    set +o pipefail
    [[ "${SCENARIO_SET_E:-0}" == 1 ]] && set -e
    # The BEHIND arm runs `bash "$SYNC_SNAP" --step`, a CHILD process: it sees the
    # mocks only through `export -f` and the MOCK_* knobs only through `set -a`.
    # If an export is ever dropped the child's real git runs from a directory
    # under a git ceiling, finds no repository, and exits 3 — a red row, never a
    # push to the live repo.
    cd "$MOCK_STATE/cwd" || exit 97
    export GIT_CEILING_DIRECTORIES="$MOCK_STATE"
    # The block's per-poll snapshot lands here; its EXIT trap must remove it.
    export TMPDIR="$MOCK_STATE/tmp"
    case "${SCEN_ROOT:-}" in
      unset) unset CLAUDE_PLUGIN_ROOT ;;
      "")    export CLAUDE_PLUGIN_ROOT="$PLUGIN_COPY" ;;
      *)     export CLAUDE_PLUGIN_ROOT="$SCEN_ROOT" ;;
    esac
    sleep() { return 0; }
    date() { echo "00:00:00"; }
    eval "$GIT_BASE_MOCK"
    git() { _git_base "$@"; }
    set -a
    # shellcheck disable=SC1090
    source "$mocks_file"
    set +a
    export -f git gh _git_base
    declare -F _gh_unexpected >/dev/null && export -f _gh_unexpected
    # shellcheck disable=SC1090
    source "$block"
  ) > "$logfile" 2> "$errfile"
  local rc=$?
  assert_no_tag_on_stderr "$label" "$errfile"
  # Any git call no mock arm answered (the child's too — many run under 2>/dev/null,
  # so the record is a FILE, not a line) is a call this row never modelled.
  if [[ -s "$MOCK_STATE/unexpected_git" ]]; then
    sed 's/^/MOCK: unexpected git /' "$MOCK_STATE/unexpected_git" >> "$logfile"
  fi
  # Match over both streams (the block's non-tagged lines may legitimately use
  # stderr), with the exit status recorded for the dump.
  { echo "[scenario exit rc=$rc]"; cat "$errfile"; } >> "$logfile"
  assert_log "$label" "$logfile" "$must_match" "$must_not_match"
  if grep -q 'MOCK: unexpected git' "$logfile"; then
    fail "[$label] unmodelled git call: $(grep -m1 'MOCK: unexpected git' "$logfile" | cut -c1-120)"
  else
    pass "[$label] every git call hit a mock arm"
  fi
  if [[ -n "$(ls -A "$MOCK_STATE/tmp")" ]]; then
    fail "[$label] temp file left behind by the block (snapshot trap): $(ls -A "$MOCK_STATE/tmp" | head -3 | tr '\n' ' ')"
  else
    pass "[$label] no temp file left behind"
  fi
  # ONCE (newline list, optional): each pattern must occur on exactly one line.
  local pat n
  while IFS= read -r pat; do
    [[ -z "$pat" ]] && continue
    n="$(grep -cE "$pat" "$logfile" || true)"
    if [[ "$n" -eq 1 ]]; then pass "[$label] exactly once: $pat"; else fail "[$label] want exactly 1 line matching '$pat', got $n"; fi
  done <<< "${ONCE:-}"
  rm -rf "$MOCK_STATE"
  rm -f "$logfile" "$errfile"
}

# Runs a scenario against BOTH blocks with `:ship` / `:merge-pr` label suffixes.
# $1 label, $2 mocks file, $3 must-match list, $4 must-not.
run_scenario_both() {
  run_scenario "$1:ship"     "$2" "$3" "$4" "$BLOCK_FILE"
  run_scenario "$1:merge-pr" "$2" "$3" "$4" "$MIRROR_FILE"
}

# The shared git mock. Scenario mocks define `git()` with their own arms and fall
# through to `_git_base "$@"`. Keyed exactly as dispatched: "$1 ${2:-}". HEAD and
# @{u} are modelled as counters so the script's no-op check (merge moved nothing AND
# nothing unpushed, exit 11) sees a real merge move HEAD and a real push move @{u}.
# The catch-all records the call in $MOCK_STATE/unexpected_git; run_scenario fails
# every row that leaves one behind.
GIT_BASE_MOCK="$(cat <<'EOF'
_git_base() {
  case "$1 ${2:-}" in
    "rev-parse -q") [[ -e "$MOCK_STATE/MERGE_HEAD" ]] ;;
    "rev-parse --is-inside-work-tree") echo true ;;
    "rev-parse --git-dir") echo "$MOCK_STATE" ;;
    "rev-parse --abbrev-ref") echo "test-branch" ;;
    "rev-parse HEAD") echo "sha-$(cat "$MOCK_STATE/merges" 2>/dev/null || echo 0)" ;;
    "rev-parse @{u}") echo "sha-$(cat "$MOCK_STATE/upstream" 2>/dev/null || echo 0)" ;;
    "symbolic-ref -q") [[ ! -e "$MOCK_STATE/detached" ]] ;;
    "fetch origin"|"fetch --no-tags") return 0 ;;
    "merge-tree --write-tree") return 0 ;;
    "merge origin/main")
      echo $(( $(cat "$MOCK_STATE/merges" 2>/dev/null || echo 0) + 1 )) > "$MOCK_STATE/merges"
      echo "Merge made by the 'ort' strategy." ;;
    "merge --abort") echo "MOCK: git merge --abort observed"; rm -f "$MOCK_STATE/MERGE_HEAD" ;;
    "diff --name-only") [[ -e "$MOCK_STATE/MERGE_HEAD" ]] && echo "foo.md" ;;
    "status --short") echo " M f" ;;
    "push ")
      cp "$MOCK_STATE/merges" "$MOCK_STATE/upstream" 2>/dev/null || true
      : > "$MOCK_STATE/pushed" ;;
    *) echo "$*" >> "$MOCK_STATE/unexpected_git"; echo "MOCK: unexpected git $*" >&2; return 0 ;;
  esac
}
EOF
)"

# Shared mock prelude: every scenario installs a default fall-through arm
# for `gh` calls the scenario did not handle, so future SKILL.md edits that
# introduce a new `gh` subcommand fail loudly instead of silently no-op'ing.
PRELUDE='
_gh_unexpected() {
  echo "UNEXPECTED gh call: $*" >&2
  return 2
}
'

# ---------------------------------------------------------------------------
# Scenario 0 — harness self-check: pipefail is OFF inside the scenario
# subshell. QUOTED heredoc: an unquoted one expands `$?` at file-creation
# time in the harness shell and the row passes regardless of the subshell's
# options (the vacuity trap this row exists to close).
# ---------------------------------------------------------------------------
SCEN0="$(mktemp)"
_TMP_OWNED+=("$SCEN0")
cat > "$SCEN0" <<'EOF'
false | true; echo "harness-pipefail-status=$?"
gh() {
  case "$1 $2" in
    "pr view")   echo "MERGED CLEAN" ;;
    "pr checks") : ;;
    "api "*)     : ;;
    *) echo "UNEXPECTED gh call: $*" >&2; return 2 ;;
  esac
}
EOF
run_scenario "0-harness-pipefail-off" "$SCEN0" \
  "harness-pipefail-status=0" \
  "harness-pipefail-status=1|UNEXPECTED gh call"
rm -f "$SCEN0"

# ---------------------------------------------------------------------------
# Scenario 1 — clean MERGED on tick 3
# ---------------------------------------------------------------------------
SCEN1="$(mktemp)"
_TMP_OWNED+=("$SCEN1")
cat > "$SCEN1" <<EOF
${PRELUDE}
gh() {
  case "\$1 \$2" in
    "pr view")
      case "\$i" in
        1) echo "OPEN BLOCKED" ;;
        2) echo "OPEN CLEAN" ;;
        *) echo "MERGED CLEAN" ;;
      esac
      ;;
    "pr checks") : ;;
    "api "*)     : ;;
    *) _gh_unexpected "\$@" ;;
  esac
}
EOF
run_scenario_both "1-clean-merged" "$SCEN1" \
  "MERGED CLEAN" \
  "ship.phase7.(required_failed|dirty|behind_exhausted)|UNEXPECTED gh call"
rm -f "$SCEN1"

# ---------------------------------------------------------------------------
# Scenario 2 — required-check failure on tick 5
# ---------------------------------------------------------------------------
SCEN2="$(mktemp)"
_TMP_OWNED+=("$SCEN2")
cat > "$SCEN2" <<EOF
${PRELUDE}
gh() {
  case "\$1 \$2" in
    "pr view") echo "OPEN BLOCKED" ;;
    "pr checks")
      if [[ "\$i" -ge 5 ]]; then
        echo "test"
      fi
      ;;
    "api "*)
      echo "test"
      echo "e2e"
      ;;
    *) _gh_unexpected "\$@" ;;
  esac
}
EOF
run_scenario_both "2-required-ci-fail" "$SCEN2" \
  "\[ship\.phase7\.required_failed\] check='test'" \
  "Merge poll timed out|UNEXPECTED gh call"
rm -f "$SCEN2"

# ---------------------------------------------------------------------------
# Scenario 3 — BEHIND saturation (6 syncs, then structured warning, heartbeat
# continues to tick 15). Run against BOTH blocks; the mirror row asserts a
# mirror-only success spelling (`auto-sync 6/6 pushed`) and forbids the
# canonical one, which is the behavioural proof that the mirror file — not
# the canonical block — was executed (harness row H3).
# ---------------------------------------------------------------------------
SCEN3="$(mktemp)"
_TMP_OWNED+=("$SCEN3")
cat > "$SCEN3" <<EOF
${PRELUDE}
gh() {
  case "\$1 \$2" in
    "pr view")   echo "OPEN BEHIND" ;;
    "pr checks") : ;;
    "api "*)     : ;;
    *) _gh_unexpected "\$@" ;;
  esac
}
EOF
ONCE='ship\.phase7\.hatch_check' run_scenario "3-behind-saturation:ship" "$SCEN3" \
  "\[ship\.phase7\.behind_exhausted\] BEHIND budget exhausted after 6 auto-syncs
fetch_failures=0/6
\[2/60\] \[ship\.phase7\.hatch_check\] 2 BEHIND syncs pushed — read .*/skills/ship/references/settle-then-admin-merge\.md now; it classifies eligibility
moving faster than this PR" \
  "ship.phase7.(required_failed|dirty)|Every attempt failed at git fetch|UNEXPECTED gh call"
ONCE='ship\.phase7\.hatch_check' run_scenario "3-behind-saturation:merge-pr" "$SCEN3" \
  "auto-sync 6/6 pushed
\[2/60\] \[ship\.phase7\.hatch_check\] 2 BEHIND syncs pushed — read .*/skills/ship/references/settle-then-admin-merge\.md now; it classifies eligibility
\[ship\.phase7\.behind_exhausted\] BEHIND budget exhausted after 6 auto-syncs
fetch_failures=0/6
moving faster than this PR" \
  "auto-sync 6 pushed|ship.phase7.(required_failed|dirty)|Every attempt failed at git fetch|UNEXPECTED gh call" \
  "$MIRROR_FILE"
rm -f "$SCEN3"

# ---------------------------------------------------------------------------
# Scenario 4 — DIRTY (real conflict): merge-tree rc=1 → dirty-exit
# ---------------------------------------------------------------------------
SCEN4="$(mktemp)"
_TMP_OWNED+=("$SCEN4")
cat > "$SCEN4" <<EOF
${PRELUDE}
git() {
  case "\$1 \${2:-}" in
    "merge-tree "*) return 1 ;;
    *) _git_base "\$@" ;;
  esac
}
gh() {
  case "\$1 \$2" in
    "pr view")
      case "\$i" in
        1) echo "OPEN BLOCKED" ;;
        *) echo "OPEN DIRTY" ;;
      esac
      ;;
    "pr checks") : ;;
    "api "*)     : ;;
    *) _gh_unexpected "\$@" ;;
  esac
}
EOF
run_scenario_both "4-dirty-exit" "$SCEN4" \
  "\[ship\.phase7\.dirty\] PR is DIRTY \(merge conflict\)" \
  "Merge poll timed out|ship\.phase7\.behind_exhausted|UNEXPECTED gh call"
rm -f "$SCEN4"

# Scenario 4b — DIRTY but locally clean: merge-tree rc=0 → BEHIND auto-sync.
# The "seen DIRTY once" flag is a FILE under $MOCK_STATE: `gh pr view` runs
# inside `$( … )`, so a shell-variable flag set there is lost and the mock
# answers DIRTY forever — which lands on `behind_exhausted`, the path this
# row does NOT document. Forbidding `behind_exhausted` is what proves the
# flip actually happened.
# ---------------------------------------------------------------------------
SCEN4B="$(mktemp)"
_TMP_OWNED+=("$SCEN4B")
cat > "$SCEN4B" <<EOF
${PRELUDE}
gh() {
  case "\$1 \$2" in
    "pr view")
      if [[ -e "\$MOCK_STATE/dirty_seen" ]]; then
        echo "OPEN BLOCKED"
      else
        : > "\$MOCK_STATE/dirty_seen"
        echo "OPEN DIRTY"
      fi
      ;;
    "pr checks") : ;;
    "api "*)     : ;;
    *) _gh_unexpected "\$@" ;;
  esac
}
EOF
run_scenario_both "4b-dirty-locally-clean" "$SCEN4B" \
  "auto-sync 1(/6)? pushed" \
  "\[ship\.phase7\.dirty\]|ship\.phase7\.behind_exhausted|UNEXPECTED gh call"
rm -f "$SCEN4B"

# Scenario 4c — DIRTY, but the fetch that classifies it fails. A fetch outage
# is not a conflict: the arm must report kind=fetch and let the next tick
# retry, never print the DIRTY exit over an empty merge-tree output.
# ---------------------------------------------------------------------------
SCEN4C="$(mktemp)"
_TMP_OWNED+=("$SCEN4C")
cat > "$SCEN4C" <<EOF
${PRELUDE}
git() {
  case "\$1 \${2:-}" in
    "fetch "*) echo "fatal: unable to access 'origin'"; return 1 ;;
    *) _git_base "\$@" ;;
  esac
}
gh() {
  case "\$1 \$2" in
    "pr view")
      if [[ -e "\$MOCK_STATE/dirty_seen" ]]; then
        echo "MERGED CLEAN"
      else
        : > "\$MOCK_STATE/dirty_seen"
        echo "OPEN DIRTY"
      fi
      ;;
    "pr checks") : ;;
    "api "*)     : ;;
    *) _gh_unexpected "\$@" ;;
  esac
}
EOF
run_scenario_both "4c-dirty-fetch-fails" "$SCEN4C" \
  "kind=fetch rc=1 — fetch origin main failed while classifying DIRTY" \
  "\[ship\.phase7\.dirty\]|BEHIND detected|auto-sync|UNEXPECTED gh call"
rm -f "$SCEN4C"

# ---------------------------------------------------------------------------
# Scenario 5 — absent required check (CI not yet registered) does NOT exit.
# Required set = ["test", "e2e"]; `gh pr checks` returns only "test" with
# bucket=pass (no fail event). The loop must heartbeat through to timeout
# rather than treating an unregistered required check as a failure.
# ---------------------------------------------------------------------------
SCEN5="$(mktemp)"
_TMP_OWNED+=("$SCEN5")
cat > "$SCEN5" <<EOF
${PRELUDE}
gh() {
  case "\$1 \$2" in
    "pr view")   echo "OPEN BLOCKED" ;;
    "pr checks") : ;;  # no failures returned
    "api "*)
      echo "test"
      echo "e2e"
      ;;
    *) _gh_unexpected "\$@" ;;
  esac
}
EOF
run_scenario_both "5-absent-required-check" "$SCEN5" \
  "Merge poll timed out" \
  "ship\.phase7\.(required_failed|dirty|behind_exhausted)|UNEXPECTED gh call"
rm -f "$SCEN5"

# ---------------------------------------------------------------------------
# Shared BEHIND sync-arm mock for scenarios 6*/7/8/9 (#8339).
#
# Knobs (plain variables in the mocks file): MOCK_FETCH_RC, MOCK_MERGE
# (ok|noop|conflict|refused|inprogress128), MOCK_PUSH_RC, MOCK_ABORT_RC,
# MOCK_FETCH_STARTS_MERGE (the fetch window creates MERGE_HEAD — an operator
# started a merge while the arm was fetching). State crosses `$( … )` via
# files: $MOCK_STATE/MERGE_HEAD (created by a conflicting merge, removed by
# --abort), $MOCK_STATE/pushed (created by a successful push; `gh` flips to
# MERGED once it exists), $MOCK_STATE/detached (symbolic-ref fails),
# $MOCK_STATE/rebase-merge (a sequencer directory under --git-dir). Arms not
# overridden here fall through to _git_base (GIT_BASE_MOCK above), which models
# HEAD/@{u} as counters. MOCK_MERGE=noop leaves HEAD where it is (exit 11);
# MOCK_FETCH_FAIL_ONCE fails only the first fetch. The --abort sentinel is on
# STDOUT: under inherited pipefail (harness row H1) the pre-fix block DOES
# reach its `--abort 2>/dev/null`, and a stderr sentinel would have been
# invisible there.
# ---------------------------------------------------------------------------
SYNC_MOCKS="${PRELUDE}$(cat <<'EOF'
git() {
  case "$1 ${2:-}" in
    "fetch origin"|"fetch --no-tags")
      if (( ${MOCK_FETCH_FAIL_ONCE:-0} )) && [[ ! -e "$MOCK_STATE/fetch_failed_once" ]]; then
        : > "$MOCK_STATE/fetch_failed_once"; echo "fatal: unable to access 'origin'"; return 1
      fi
      if (( ${MOCK_FETCH_RC:-0} )); then echo "fatal: unable to access 'origin'"; fi
      if (( ${MOCK_FETCH_STARTS_MERGE:-0} )); then : > "$MOCK_STATE/MERGE_HEAD"; fi
      return "${MOCK_FETCH_RC:-0}" ;;
    "merge origin/main")
      case "${MOCK_MERGE:-ok}" in
        ok) _git_base "$@" ;;
        noop) echo "Already up to date." ;;
        conflict)
          echo "CONFLICT (content): Merge conflict in foo.md"
          echo "Automatic merge failed; fix conflicts and then commit the result."
          : > "$MOCK_STATE/MERGE_HEAD"
          return 1 ;;
        refused)
          echo "error: Your local changes would be overwritten by merge."
          return 2 ;;
        inprogress128)
          echo "fatal: You have not concluded your merge (MERGE_HEAD exists)."
          return 128 ;;
      esac ;;
    "merge --abort")
      echo "MOCK: git merge --abort observed"
      if (( ${MOCK_ABORT_RC:-0} )); then echo "fatal: mock abort failure"; return "${MOCK_ABORT_RC}"; fi
      rm -f "$MOCK_STATE/MERGE_HEAD" ;;
    "status --short")
      echo " M f"
      if (( ${MOCK_STATUS_LINES:-0} )); then
        n=0; while (( n < MOCK_STATUS_LINES )); do echo "?? untracked-padding-file-$n.txt"; n=$((n+1)); done
      fi ;;
    "push ")
      if (( ${MOCK_PUSH_RC:-0} )); then
        echo "error: failed to push some refs to 'origin'"
        return "${MOCK_PUSH_RC}"
      fi
      _git_base "$@" ;;
    *) _git_base "$@" ;;
  esac
}
gh() {
  case "$1 $2" in
    "pr view")
      if [[ -e "$MOCK_STATE/pushed" ]]; then echo "MERGED CLEAN"; else echo "OPEN BEHIND"; fi ;;
    "pr checks") : ;;
    "api "*)     : ;;
    *) _gh_unexpected "$@" ;;
  esac
}
EOF
)"

STOP_FORBID='auto-sync [0-9/]+ pushed|ship\.phase7\.behind_exhausted|Merge poll timed out|UNEXPECTED gh call'

# ---------------------------------------------------------------------------
# Scenario 6 — merge conflict during BEHIND auto-sync. RED on the pre-#8339
# block: `git merge | tail -5` reports tail's 0, the conflict branch is
# unreachable, and the block prints "auto-sync 1 pushed" over a conflicted
# tree. `merge conflict` is anchored to the new line, not a bare token — the
# DIRTY arm already prints "PR is DIRTY (merge conflict)".
# ---------------------------------------------------------------------------
SCEN6="$(mktemp)"
_TMP_OWNED+=("$SCEN6")
cat > "$SCEN6" <<EOF
MOCK_MERGE=conflict
${SYNC_MOCKS}
EOF
run_scenario_both "6-merge-conflict-in-sync" "$SCEN6" \
  "MOCK: git merge --abort observed
git merge origin/main failed — merge conflict, aborting sync\. Conflicted paths:
^foo\.md$
Manual conflict resolution required on test-branch\.
sync-pr-behind\.sh exited 6 \(see its line above\)\. Stopping the poll\.
kind=merge rc=1" \
  "$STOP_FORBID"

# ---------------------------------------------------------------------------
# Scenario 6b — merge REFUSED to start (rc 2: dirty tracked file / untracked
# overwrite; no MERGE_HEAD). Not a conflict: nothing to abort, so an
# unconditional `--abort` here is the wrong (and previously swallowed) call.
# ---------------------------------------------------------------------------
SCEN6B="$(mktemp)"
_TMP_OWNED+=("$SCEN6B")
cat > "$SCEN6B" <<EOF
MOCK_MERGE=refused
${SYNC_MOCKS}
EOF
run_scenario_both "6b-merge-refused" "$SCEN6B" \
  "kind=merge_refused rc=2
refused to start \(nothing to abort
^ M f$
sync-pr-behind\.sh exited 10 \(see its line above\)" \
  "$STOP_FORBID|MOCK: git merge --abort observed|Manual conflict resolution required"
rm -f "$SCEN6B"

# ---------------------------------------------------------------------------
# Scenario 6c — a merge is ALREADY in progress when the arm runs (operator
# mid-resolution). The arm must not run `git merge` (rc 128 on a real repo)
# and must not `--abort` a merge it did not start — that discards the
# operator's staged resolution (measured on real git; scenario 10 sub-row B).
# ---------------------------------------------------------------------------
SCEN6C="$(mktemp)"
_TMP_OWNED+=("$SCEN6C")
cat > "$SCEN6C" <<EOF
: > "\$MOCK_STATE/MERGE_HEAD"
${SYNC_MOCKS}
EOF
run_scenario_both "6c-merge-in-progress" "$SCEN6C" \
  "kind=merge_in_progress" \
  "$STOP_FORBID|MOCK: git merge --abort observed|Manual conflict resolution required|Merge made by"
rm -f "$SCEN6C"

# ---------------------------------------------------------------------------
# Scenario 6d — MERGE_HEAD appears DURING the fetch window (the operator
# started a merge between the precondition and `git merge`; git answers rc
# 128). Not a conflict this arm produced: it must not be aborted.
# ---------------------------------------------------------------------------
SCEN6D="$(mktemp)"
_TMP_OWNED+=("$SCEN6D")
cat > "$SCEN6D" <<EOF
MOCK_FETCH_STARTS_MERGE=1
MOCK_MERGE=inprogress128
${SYNC_MOCKS}
EOF
run_scenario_both "6d-merge-head-appears-during-fetch" "$SCEN6D" \
  "kind=merge_in_progress rc=128" \
  "$STOP_FORBID|MOCK: git merge --abort observed|Manual conflict resolution required|kind=merge rc=|kind=merge_refused"
rm -f "$SCEN6D"

# ---------------------------------------------------------------------------
# Scenario 6e — the conflict abort itself fails. The failure is printed (not
# swallowed) and the poll still stops.
# ---------------------------------------------------------------------------
SCEN6E="$(mktemp)"
_TMP_OWNED+=("$SCEN6E")
cat > "$SCEN6E" <<EOF
MOCK_MERGE=conflict
MOCK_ABORT_RC=1
${SYNC_MOCKS}
EOF
run_scenario_both "6e-abort-fails" "$SCEN6E" \
  "MOCK: git merge --abort observed
git merge --abort failed \(rc=1\)
Manual conflict resolution required on test-branch\.
sync-pr-behind\.sh exited 6 \(see its line above\)\. Stopping the poll\." \
  "$STOP_FORBID"
rm -f "$SCEN6E"

# ---------------------------------------------------------------------------
# Scenario 6f — scenario 6 under an errexit host shell. A bare
# `x="\$(cmd)"; rc=\$?` capture dies at the merge assignment under `set -e`
# (the shell exits before --abort, leaving MERGE_HEAD — the #8339 outcome by
# another route); the `|| sync_rc=\$?` form survives. The exit rc of the
# subshell is recorded in the log; a shell killed by errexit exits 1 with no
# "Stopping the poll." line.
# ---------------------------------------------------------------------------
SCENARIO_SET_E=1 run_scenario_both "6f-conflict-under-errexit" "$SCEN6" \
  "MOCK: git merge --abort observed
Manual conflict resolution required on test-branch\.
sync-pr-behind\.sh exited 6 \(see its line above\)\. Stopping the poll\.
kind=merge rc=1
\[scenario exit rc=0\]" \
  "$STOP_FORBID"
rm -f "$SCEN6"

# ---------------------------------------------------------------------------
# Scenario 6g — detached HEAD: refused before any fetch (git push would have
# no branch to update).
# ---------------------------------------------------------------------------
SCEN6G="$(mktemp)"
_TMP_OWNED+=("$SCEN6G")
cat > "$SCEN6G" <<EOF
: > "\$MOCK_STATE/detached"
${SYNC_MOCKS}
EOF
run_scenario_both "6g-detached-head" "$SCEN6G" \
  "kind=detached_head" \
  "$STOP_FORBID|Merge made by|MOCK: git merge --abort observed|kind=merge"
rm -f "$SCEN6G"

# ---------------------------------------------------------------------------
# Scenario 6h — a rebase is in progress (sequencer dir under --git-dir, no
# MERGE_HEAD): refused before any fetch, nothing aborted.
# ---------------------------------------------------------------------------
SCEN6H="$(mktemp)"
_TMP_OWNED+=("$SCEN6H")
cat > "$SCEN6H" <<EOF
mkdir -p "\$MOCK_STATE/rebase-merge"
${SYNC_MOCKS}
EOF
run_scenario_both "6h-rebase-in-progress" "$SCEN6H" \
  "kind=merge_in_progress rc=9 — a merge/rebase/cherry-pick/revert is in progress on test-branch" \
  "$STOP_FORBID|Merge made by|MOCK: git merge --abort observed|kind=merge rc=|kind=merge_refused"
rm -f "$SCEN6H"

# ---------------------------------------------------------------------------
# Scenario 7 — push fails after a clean merge. RED on the pre-#8339 block for
# the same reason as 6 (`git push | tail -2`).
# ---------------------------------------------------------------------------
SCEN7="$(mktemp)"
_TMP_OWNED+=("$SCEN7")
cat > "$SCEN7" <<EOF
MOCK_PUSH_RC=1
${SYNC_MOCKS}
EOF
run_scenario_both "7-push-fails-after-merge" "$SCEN7" \
  "kind=push rc=1
git push failed after merge" \
  "$STOP_FORBID|MOCK: git merge --abort observed"
rm -f "$SCEN7"

# ---------------------------------------------------------------------------
# Scenario 8 — fetch fails: the attempt is skipped AND counted; the loop
# continues, and after six the behind_exhausted line carries
# `fetch_failures=6/6` so a fetch outage is not read as "main moving faster
# than CI". RED on the pre-#8339 block: `git fetch | tail -2` reports 0, the
# merge+push run, and the loop prints "pushed".
# ---------------------------------------------------------------------------
SCEN8="$(mktemp)"
_TMP_OWNED+=("$SCEN8")
cat > "$SCEN8" <<EOF
MOCK_FETCH_RC=1
${SYNC_MOCKS}
EOF
run_scenario_both "8-fetch-fails-skips-attempt" "$SCEN8" \
  "kind=fetch rc=1
fetch origin main failed
ship\.phase7\.behind_exhausted
fetch_failures=6/6
Every attempt failed at git fetch" \
  "auto-sync [0-9/]+ pushed|MOCK: git merge --abort observed|git push failed after merge|moving faster than this PR|UNEXPECTED gh call"
rm -f "$SCEN8"

# ---------------------------------------------------------------------------
# Scenario 9 — success path characterization (GREEN before and after the fix).
# One sync pushes, the post-push re-fetch sees MERGED and breaks before tick
# 2. This is the net under the if/elif → nested refactor: dropping the
# re-fetch, or renaming the success echo, reddens it.
# ---------------------------------------------------------------------------
SCEN9="$(mktemp)"
_TMP_OWNED+=("$SCEN9")
cat > "$SCEN9" <<EOF
${SYNC_MOCKS}
EOF
SUCCESS_FORBID='\[2/60\]|auto-sync attempt 2/|ship\.phase7\.behind_exhausted|Merge poll timed out|MOCK: git merge --abort observed|UNEXPECTED gh call'
run_scenario "9-success-path:ship" "$SCEN9" \
  "\[1/60\] auto-sync 1 pushed — auto-merge will re-evaluate" \
  "$SUCCESS_FORBID" "$BLOCK_FILE"
run_scenario "9-success-path:merge-pr" "$SCEN9" \
  "\[1/60\] auto-sync 1/6 pushed" \
  "$SUCCESS_FORBID" "$MIRROR_FILE"
rm -f "$SCEN9"

# ---------------------------------------------------------------------------
# Scenario 6i — merge refused with a ≥100 KB worktree status (#8383). The
# script runs under `set -euo pipefail`; `git status --short | head -20` then
# outlives head and takes SIGPIPE (141), which — without its `|| true` — would
# kill the script before it reports. 20000 lines make the SIGPIPE deterministic
# (a 25-line status fits in the pipe buffer and never trips it). Measured: the
# `|| true` is NOT load-bearing today (errexit is suspended inside sync_step,
# which both callers run under `||`); this row pins exit 10 over a huge status
# and would catch a future bare `sync_step` call.
# ---------------------------------------------------------------------------
SCEN6I="$(mktemp)"
_TMP_OWNED+=("$SCEN6I")
cat > "$SCEN6I" <<EOF
MOCK_MERGE=refused
MOCK_STATUS_LINES=20000
${SYNC_MOCKS}
EOF
run_scenario_both "6i-refused-huge-status" "$SCEN6I" \
  "kind=merge_refused rc=2
Clear the worktree state on test-branch shown above
sync-pr-behind\.sh exited 10 \(see its line above\)" \
  "$STOP_FORBID|MOCK: git merge --abort observed"
rm -f "$SCEN6I"

# ---------------------------------------------------------------------------
# Scenario 13 — version skew: the plugin root carries an OLDER sync script that
# ignores --step (it would run a full standalone sync and exit 0 on "no sync
# needed", which the arm would print as `pushed`). The --help probe must refuse
# it at loop entry; BEHIND auto-sync is disabled, and the first BEHIND tick is a
# named stop (behind_no_sync) carrying the manual command, not 60 min of heartbeats.
# ---------------------------------------------------------------------------
SKEW_ROOT="$(mktemp -d)"
assert_fixture_dir "$SKEW_ROOT"
_TMP_OWNED+=("$SKEW_ROOT")
mkdir -p "$SKEW_ROOT/.claude-plugin" "$SKEW_ROOT/scripts"
printf '{ "name": "soleur" }\n' > "$SKEW_ROOT/.claude-plugin/plugin.json"
printf '#!/usr/bin/env bash\necho "usage: sync-pr-behind.sh <pr-number> [--max-attempts N]"\nexit 0\n' \
  > "$SKEW_ROOT/scripts/sync-pr-behind.sh"
SCEN13="$(mktemp)"
_TMP_OWNED+=("$SCEN13")
cat > "$SCEN13" <<EOF
${SYNC_MOCKS}
EOF
SCEN_ROOT="$SKEW_ROOT" run_scenario_both "13-version-skew" "$SCEN13" \
  "\[ship\.phase7\.precondition\] sync-pr-behind\.sh not usable at '[^']*': its --help has no --step
\[1/60\] \[ship\.phase7\.behind_no_sync\] PR 4387 is BEHIND and auto-sync is disabled
sync-pr-behind\.sh\"? 4387 .*re-arm the poll\. Stopping the poll\.
\[scenario exit rc=0\]" \
  "BEHIND detected|auto-sync [0-9/]+ pushed|Merge made by|Merge poll timed out|\[2/60\]|UNEXPECTED gh call"
rm -f "$SCEN13"

# ---------------------------------------------------------------------------
# Scenario 13b — CLAUDE_PLUGIN_ROOT unset (the Devin-cloud / Codex shape: the
# token is neither substituted nor exported). A missing script must not read as
# success: precondition line naming the unset root, no sync, and the BEHIND tick is
# the named behind_no_sync stop.
# ---------------------------------------------------------------------------
SCEN13B="$(mktemp)"
_TMP_OWNED+=("$SCEN13B")
cat > "$SCEN13B" <<EOF
${PRELUDE}
gh() {
  case "\$1 \$2" in
    "pr view")
      if (( i >= 3 )); then echo "MERGED CLEAN"; else echo "OPEN BEHIND"; fi ;;
    "pr checks") : ;;
    "api "*)     : ;;
    *) _gh_unexpected "\$@" ;;
  esac
}
EOF
SCEN_ROOT='unset' run_scenario_both "13b-plugin-root-unset" "$SCEN13B" \
  "\[ship\.phase7\.precondition\] sync-pr-behind\.sh not usable at '/scripts/sync-pr-behind\.sh': CLAUDE_PLUGIN_ROOT is unset
\[ship\.phase7\.behind_no_sync\] PR 4387 is BEHIND" \
  "BEHIND detected|auto-sync [0-9/]+ pushed|Merge poll timed out|UNEXPECTED gh call"
rm -f "$SCEN13B"

# ---------------------------------------------------------------------------
# Scenario 13c — a root whose plugin.json names another plugin ("evil") but whose
# scripts/ holds a VALID --step script (ADR-179 decision 11): the identity check
# alone must refuse it. Precondition line names that check; no sync runs.
# ---------------------------------------------------------------------------
EVIL_ROOT="$(mktemp -d)"
assert_fixture_dir "$EVIL_ROOT"
_TMP_OWNED+=("$EVIL_ROOT")
mkdir -p "$EVIL_ROOT/.claude-plugin" "$EVIL_ROOT/scripts"
printf '{ "name": "evil" }\n' > "$EVIL_ROOT/.claude-plugin/plugin.json"
cp "$PLUGIN_COPY/scripts/sync-pr-behind.sh" "$EVIL_ROOT/scripts/sync-pr-behind.sh"
SCEN13C="$(mktemp)"
_TMP_OWNED+=("$SCEN13C")
cat > "$SCEN13C" <<EOF
${SYNC_MOCKS}
EOF
SCEN_ROOT="$EVIL_ROOT" run_scenario_both "13c-plugin-json-not-soleur" "$SCEN13C" \
  "\[ship\.phase7\.precondition\] sync-pr-behind\.sh not usable at '[^']*': .*does not name soleur \(ADR-179 identity check\)
\[ship\.phase7\.behind_no_sync\]" \
  "BEHIND detected|auto-sync [0-9/]+ pushed|Merge made by|UNEXPECTED gh call"
rm -f "$SCEN13C"

# ---------------------------------------------------------------------------
# Scenario 14 — a pasted `#4387` (or any non-digit PR) is refused before the poll
# starts: unvalidated, `bash "$SYNC_SNAP" #4387 --step || sync_rc=$?` comments out
# the rc capture and the arm prints a false "pushed".
# ---------------------------------------------------------------------------
HASH_BLOCK="$(mktemp)"
_TMP_OWNED+=("$HASH_BLOCK")
sed 's/^PR="4387"/PR="#4387"/' "$BLOCK_FILE" > "$HASH_BLOCK"
HASH_MIRROR="$(mktemp)"
_TMP_OWNED+=("$HASH_MIRROR")
sed 's/^PR="4387"/PR="#4387"/' "$MIRROR_FILE" > "$HASH_MIRROR"
SCEN14="$(mktemp)"
_TMP_OWNED+=("$SCEN14")
cat > "$SCEN14" <<EOF
${SYNC_MOCKS}
EOF
for pair in "ship:$HASH_BLOCK" "merge-pr:$HASH_MIRROR"; do
  if grep -q '^PR="#4387"' "${pair#*:}"; then
    run_scenario "14-pr-not-digits:${pair%%:*}" "$SCEN14" \
      "\[ship\.phase7\.precondition\] PR='#4387' is not a bare PR number
\[scenario exit rc=2\]" \
      "BEHIND detected|auto-sync|PR #4387 |UNEXPECTED gh call" "${pair#*:}"
  else
    fail "[14-pr-not-digits:${pair%%:*}] could not build the #4387 variant (no ^PR=\"4387\" line in the block)"
  fi
done
rm -f "$SCEN14" "$HASH_BLOCK" "$HASH_MIRROR"

# ---------------------------------------------------------------------------
# Scenario 15 — the hatch counts PUSHES, not attempts: attempt 1 fails at fetch,
# attempt 2 pushes and the PR merges. The old `behind_syncs == 2` fired the hatch
# here with one sync ever pushed.
# ---------------------------------------------------------------------------
SCEN15="$(mktemp)"
_TMP_OWNED+=("$SCEN15")
cat > "$SCEN15" <<EOF
MOCK_FETCH_FAIL_ONCE=1
${SYNC_MOCKS}
EOF
run_scenario_both "15-hatch-counts-pushes" "$SCEN15" \
  "kind=fetch rc=1
auto-sync 2(/6)? pushed
\[scenario exit rc=0\]" \
  "ship\.phase7\.hatch_check|ship\.phase7\.behind_exhausted|Merge poll timed out|UNEXPECTED gh call"
rm -f "$SCEN15"

# ---------------------------------------------------------------------------
# Scenario 16 — the sync is a no-op (origin/main already merged and pushed;
# GitHub's BEHIND lags): the arm prints sync_noop, never "pushed", and a no-op is
# not counted — the budget never exhausts and the hatch never fires.
# ---------------------------------------------------------------------------
SCEN16="$(mktemp)"
_TMP_OWNED+=("$SCEN16")
cat > "$SCEN16" <<EOF
MOCK_MERGE=noop
${SYNC_MOCKS}
EOF
run_scenario_both "16-sync-noop" "$SCEN16" \
  "kind=noop rc=11
\[1/60\] \[ship\.phase7\.sync_noop\] main already merged and pushed
\[60/60\] \[ship\.phase7\.sync_noop\]
Merge poll timed out" \
  "auto-sync [0-9/]+ pushed|ship\.phase7\.(hatch_check|behind_exhausted|sync_failed)|auto-sync attempt 2/|UNEXPECTED gh call"
rm -f "$SCEN16"

# ---------------------------------------------------------------------------
# AC1 — one BEHIND implementation (#8383). Neither fence may carry a merge/push
# of its own; each runs the script exactly once per attempt. Comment and echo
# lines are excluded, so the DIRTY arm's `git merge-tree` and its
# (and `-C <dir>` / `-c <k=v>` are stripped first, so they cannot hide a push)
# `echo "Resolve locally: git merge origin/main"` do not count.
# ---------------------------------------------------------------------------
for pair in "ship:$BLOCK_FILE" "merge-pr:$MIRROR_FILE"; do
  lbl="${pair%%:*}"; f="${pair#*:}"
  # Global options first: `git -C "$PWD" push` / `git -c k=v merge origin/main` are
  # still an inline merge/push.
  inline="$(grep -vE '^[[:space:]]*(#|echo )' "$f" \
    | sed -E "s/git( +-[Cc] +(\"[^\"]*\"|'[^']*'|[^ ]+))+/git/g" \
    | grep -nE '(^|[;&|([:space:]`])git (merge( |$)(origin|--abort|--no-edit)|push( |$))' || true)"
  calls="$(grep -cF 'bash "$SYNC_SNAP" "$PR" --step' "$f" || true)"
  if [[ -z "$inline" && "$calls" -eq 1 ]]; then
    pass "[$lbl] no inline git merge/push; exactly one sync-pr-behind.sh --step call"
  else
    fail "[$lbl] inline merge/push: ${inline:-none}; --step calls: $calls (want 1)"
  fi
done

# Every `git <sub> <arg>` the script's sync_step() makes must have an arm in
# GIT_BASE_MOCK or SYNC_MOCKS — the catch-all fails the row at run time, and this
# static check names the missing arm up front. `tag`/`echo` message lines name git
# commands as next actions and are excluded. Keyed exactly as the mock dispatches:
# "$1 ${2:-}", matched against a quoted exact key or a `"<sub> "*` glob.
SYNC_SCRIPT="$REPO_ROOT/plugins/soleur/scripts/sync-pr-behind.sh"
keys="$(awk '/^sync_step\(\) \{/{f=1} f&&/^\}/{exit} f' "$SYNC_SCRIPT" \
  | grep -vE '^[[:space:]]*(#|echo |tag )' \
  | grep -oE '(^|[^a-z-])git [a-z-]+( [^ ;|)"&>]+)?' \
  | sed -E "s/^[^g]*git //; s/ [0-9].*\$//; s/'//g" | sort -u)"
nkeys=0; missing=""
while IFS= read -r k; do
  [[ -z "$k" ]] && continue
  nkeys=$((nkeys+1))
  sub="${k%% *}"; arg=""; [[ "$k" == *" "* ]] && arg="${k#* }"
  if grep -qE "\"$sub $arg\"[|)]" <<<"$GIT_BASE_MOCK$SYNC_MOCKS" || grep -qF "\"$sub \"*)" <<<"$GIT_BASE_MOCK$SYNC_MOCKS"; then :; else missing+="[$sub $arg] "; fi
done <<<"$keys"
if [[ "$nkeys" -ge 10 && -z "$missing" ]]; then
  pass "every git call in sync_step() ($nkeys) has a mock arm"
else
  fail "sync_step() git calls without a mock arm: ${missing:-none} (calls found: $nkeys, want >= 10)"
fi

# ---------------------------------------------------------------------------
# Scenario 11 — not inside a worktree (`--is-inside-work-tree` prints
# `false`, rc 0 — a bare repo): the precondition disables the BEHIND arm and
# says so, and the first BEHIND tick is the named behind_no_sync stop instead of
# running git merge in a bare repo (or heartbeating for 60 min).
# ---------------------------------------------------------------------------
SCEN11="$(mktemp)"
_TMP_OWNED+=("$SCEN11")
cat > "$SCEN11" <<EOF
${PRELUDE}
git() {
  case "\$1 \${2:-}" in
    "rev-parse --is-inside-work-tree") echo false ;;
    *) _git_base "\$@" ;;
  esac
}
gh() {
  case "\$1 \$2" in
    "pr view")   echo "OPEN BEHIND" ;;
    "pr checks") : ;;
    "api "*)     : ;;
    *) _gh_unexpected "\$@" ;;
  esac
}
EOF
run_scenario_both "11-not-a-worktree" "$SCEN11" \
  "\[ship\.phase7\.precondition\] not inside a worktree — BEHIND auto-sync disabled
\[1/60\] \[ship\.phase7\.behind_no_sync\] PR 4387 is BEHIND" \
  "BEHIND detected|auto-sync [0-9/]+ pushed|Merge made by|ship\.phase7\.behind_exhausted|Merge poll timed out|UNEXPECTED gh call"
rm -f "$SCEN11"

# ---------------------------------------------------------------------------
# Scenario 10 — REAL git, no `git` mock (the retroactive application #8339
# asks for, as a repeatable row). A bare origin + clone `a` (feat branch
# editing `f`) + clone `b` (pushes to main). The ship block is sourced in `a`
# with `gh` a marker-file stub (OPEN BEHIND once, then MERGED).
#
#   A. conflict: the arm names `f`, aborts, and leaves `a` clean —
#      MERGE_HEAD gone, porcelain clean, local HEAD and both remote refs unchanged.
#   B. a pre-staged resolution (operator mid-merge): the arm reports
#      merge_in_progress and the staged file is still staged afterwards.
#   C. push rejected by a pre-receive hook after a clean merge: kind=push,
#      the local merge commit (two parents) is retained.
#   D. a rebase stopped on a conflict: refused as in progress; REBASE state
#      and the unmerged path survive.
#   E. detached HEAD: refused before any fetch; HEAD unchanged.
#
# `mktemp -d -t` lands beside $BLOCK_FILE (same TMPDIR), never in the
# worktree; `git_fixture_env` sweeps inherited GIT_* and pins config/identity
# so the throwaway `git init` cannot land in the real repository (#7833).
# State verdicts are printed as `POST-X:` lines from inside the subshell
# (pass/fail counters do not survive it); each sub-row's section of the log is
# then asserted with the same assert_log the mocked rows use.
# ---------------------------------------------------------------------------
SCEN10_TMP="$(mktemp -d -t ship-phase7-realgit.XXXXXX)"
assert_fixture_dir "$SCEN10_TMP"
_TMP_OWNED+=("$SCEN10_TMP")
SCEN10_LOG="$(mktemp)"
_TMP_OWNED+=("$SCEN10_LOG")
SCEN10_ERR="$(mktemp)"
_TMP_OWNED+=("$SCEN10_ERR")
(
  set +o pipefail
  git_fixture_env "$SCEN10_TMP" || exit 2
  export CLAUDE_PLUGIN_ROOT="$PLUGIN_COPY"
  tmp="$SCEN10_TMP"
  assert_fixture_dir "$tmp"
  git init -q --bare -b main "$tmp/origin" || exit 2
  git init -q -b main "$tmp/a" || exit 2
  cd "$tmp/a" || exit 2
  git remote add origin "$tmp/origin"
  echo base > f && echo base > g && git add f g && git commit -qm base && git push -q origin main || exit 2
  git checkout -q -b feat && echo feat > f && git commit -qam feat && git push -q -u origin feat || exit 2
  git clone -q -b main "$tmp/origin" "$tmp/b" || exit 2
  main_commit() { ( cd "$tmp/b" && git pull -q --no-tags origin main && echo "$2" > "$1" && git commit -qam "main-$1-$2" && git push -q origin main ) || exit 2; }
  main_commit f other
  cd "$tmp/a" || exit 2
  git fetch -q --no-tags origin
  before_main="$(git rev-parse origin/main)"; before_feat="$(git rev-parse origin/feat)"; before_head="$(git rev-parse HEAD)"
  refs_unchanged() {
    git fetch -q --no-tags origin
    [[ "$(git rev-parse origin/main)" == "$before_main" ]] && echo "POST-$1: origin_main=unchanged" || echo "POST-$1: origin_main=CHANGED"
    [[ "$(git rev-parse origin/feat)" == "$before_feat" ]] && echo "POST-$1: origin_feat=unchanged" || echo "POST-$1: origin_feat=CHANGED"
    [[ "$(git rev-parse HEAD)" == "$before_head" ]] && echo "POST-$1: head=unchanged" || echo "POST-$1: head=CHANGED"
  }

  sleep() { return 0; }
  date() { echo "00:00:00"; }
  gh() {
    case "$1 $2" in
      "pr view")
        if [[ -e "$tmp/tick" ]]; then echo "MERGED CLEAN"; else : > "$tmp/tick"; echo "OPEN BEHIND"; fi ;;
      "pr checks") : ;;
      "api "*)     : ;;
      *) echo "UNEXPECTED gh call: $*" >&2; return 2 ;;
    esac
  }
  # shellcheck disable=SC1090
  arm() { rm -f "$tmp/tick"; echo "=== sub-row $1 ==="; [[ -n "${2:-}" ]] && echo "$2"; source "$BLOCK_FILE"; }

  arm A
  git rev-parse -q --verify MERGE_HEAD >/dev/null 2>&1; echo "POST-A: merge_head_rc=$?"
  if [[ -z "$(git status --porcelain)" ]]; then echo "POST-A: porcelain=clean"; else echo "POST-A: porcelain=dirty"; git status --porcelain; fi
  refs_unchanged A

  # B: reproduce an operator mid-resolution, then re-run the arm.
  git merge --abort >/dev/null 2>&1 || true
  git merge origin/main --no-edit >/dev/null 2>&1
  echo resolved > f && git add f
  arm B
  if [[ -n "$(git diff --cached --name-only)" ]]; then echo "POST-B: staged=present"; else echo "POST-B: staged=DISCARDED"; fi
  [[ "$(cat f)" == "resolved" ]] && echo "POST-B: f=resolved" || echo "POST-B: f=$(cat f)"
  git merge --abort >/dev/null 2>&1 || true

  # C: resolve the conflict for real so main merges cleanly, advance main on a
  # different file, then reject the push with a pre-receive hook.
  git merge origin/main --no-edit >/dev/null 2>&1; echo merged > f && git add f && git commit -qm merged
  git push -q origin feat || exit 2
  main_commit g other
  cd "$tmp/a" || exit 2
  printf '#!/bin/sh\necho "pre-receive: rejected by fixture" >&2\nexit 1\n' > "$tmp/origin/hooks/pre-receive"; chmod +x "$tmp/origin/hooks/pre-receive"
  before_head="$(git rev-parse HEAD)"
  arm C
  rm -f "$tmp/origin/hooks/pre-receive"
  [[ "$(git rev-parse HEAD)" != "$before_head" ]] && echo "POST-C: head=advanced" || echo "POST-C: head=UNCHANGED"
  [[ "$(git log -1 --format=%P | wc -w)" -eq 2 ]] && echo "POST-C: head=merge-commit" || echo "POST-C: head=NOT-A-MERGE"
  git rev-parse -q --verify MERGE_HEAD >/dev/null 2>&1; echo "POST-C: merge_head_rc=$?"
  git push -q origin feat || exit 2

  # D: a rebase stopped on a conflict (no MERGE_HEAD, .git/rebase-merge present).
  main_commit f other2
  cd "$tmp/a" || exit 2
  git fetch -q --no-tags origin
  git rebase origin/main >/dev/null 2>&1
  pre_d="$([[ -d "$(git rev-parse --git-dir)/rebase-merge" ]] && echo "PRE-D: rebase=in-progress" || echo "PRE-D: rebase=NOT-STARTED")"
  arm D "$pre_d"
  [[ -d "$(git rev-parse --git-dir)/rebase-merge" ]] && echo "POST-D: rebase=in-progress" || echo "POST-D: rebase=GONE"
  git status --porcelain | grep -q '^UU f$' && echo "POST-D: unmerged=f" || echo "POST-D: unmerged=NONE"
  git rebase --abort >/dev/null 2>&1 || true

  # E: detached HEAD.
  git checkout -q --detach
  before_head="$(git rev-parse HEAD)"
  arm E
  [[ "$(git rev-parse HEAD)" == "$before_head" ]] && echo "POST-E: head=unchanged" || echo "POST-E: head=CHANGED"
  git checkout -q feat
) > "$SCEN10_LOG" 2> "$SCEN10_ERR"
scen10_rc=$?

# Each sub-row is asserted against ITS OWN section of the log: sub-row A
# legitimately prints "Manual conflict resolution required", which B forbids.
scen10_section() { awk -v r="$1" '/^=== sub-row /{p=($3==r)} p' "$SCEN10_LOG"; }
scen10_row() {  # <row> <must_match> <must_not_match>
  local sec; sec="$(mktemp)"; _TMP_OWNED+=("$sec")
  scen10_section "$1" > "$sec"
  assert_log "10-real-git:$1" "$sec" "$2" "$3"
  rm -f "$sec"
}
if [[ "$scen10_rc" -eq 2 ]]; then
  fail "[10-real-git] fixture setup failed (rc=2)"
  sed 's/^/      /' "$SCEN10_LOG" "$SCEN10_ERR"
else
  assert_no_tag_on_stderr "10-real-git" "$SCEN10_ERR"
  scen10_row A "kind=merge rc=1
^f$
Manual conflict resolution required on feat
POST-A: merge_head_rc=1
POST-A: porcelain=clean
POST-A: origin_main=unchanged
POST-A: origin_feat=unchanged
POST-A: head=unchanged" \
    'auto-sync [0-9/]+ pushed|UNEXPECTED gh call'
  scen10_row B "kind=merge_in_progress
POST-B: staged=present
POST-B: f=resolved" \
    'Manual conflict resolution required|auto-sync [0-9/]+ pushed|Merge made by|UNEXPECTED gh call'
  scen10_row C "kind=push rc=1
failed to push some refs
POST-C: head=advanced
POST-C: head=merge-commit
POST-C: merge_head_rc=1" \
    'auto-sync [0-9/]+ pushed|Manual conflict resolution required|UNEXPECTED gh call'
  scen10_row D "PRE-D: rebase=in-progress
kind=merge_in_progress rc=9 — a merge/rebase/cherry-pick/revert is in progress on HEAD
POST-D: rebase=in-progress
POST-D: unmerged=f" \
    'Manual conflict resolution required|kind=merge_refused|auto-sync [0-9/]+ pushed|Merge made by|UNEXPECTED gh call'
  scen10_row E "kind=detached_head
POST-E: head=unchanged" \
    'Manual conflict resolution required|auto-sync [0-9/]+ pushed|Merge made by|UNEXPECTED gh call'
fi
assert_fixture_dir "$SCEN10_TMP"
rm -rf "$SCEN10_TMP"
rm -f "$SCEN10_LOG" "$SCEN10_ERR"

# ---------------------------------------------------------------------------
# The poll budget must stay above the repo's own CI wall-clock.
#
# It was 15 minutes, which is BELOW the fastest full CI run ever observed here
# (min 22 / median 32 / p90 43 / max 54, measured over 12 runs on main). A budget
# that cannot outlast CI does not merely give up early — it reports
# "Merge poll timed out" on a PR that is merging perfectly well, which reads as a
# failure and invites someone to intervene by hand. Floor is 45: above the
# measured p90, so an ordinary run finishes inside it.
#
# Asserted on BOTH the canonical block and the mirror, and asserted EQUAL —
# a budget that drifts between them is the same defect wearing a mirror.
budget_of() { grep -oE '^MAX_POLL_MIN=[0-9]+' "$1" | head -1 | cut -d= -f2; }
SHIP_MD="$REPO_ROOT/plugins/soleur/skills/ship/SKILL.md"
MERGE_MD="$REPO_ROOT/plugins/soleur/skills/merge-pr/SKILL.md"
ship_budget=$(budget_of "$SHIP_MD")
merge_budget=$(budget_of "$MERGE_MD")

if [[ -z "$ship_budget" || -z "$merge_budget" ]]; then
  fail "MAX_POLL_MIN not found in ship (got '${ship_budget:-}') and/or merge-pr (got '${merge_budget:-}')"
else
  if [[ "$ship_budget" == "$merge_budget" ]]; then
    pass "poll budget agrees across canonical and mirror ($ship_budget min)"
  else
    fail "poll budget DRIFTED: ship=$ship_budget merge-pr=$merge_budget"
  fi
  if [[ "$ship_budget" -ge 45 ]]; then
    pass "poll budget ($ship_budget min) is above the measured CI p90 (43 min)"
  else
    fail "poll budget $ship_budget min is at or below the measured CI p90 (43 min) — CI outlasts the poll, so it reports a spurious timeout"
  fi
fi

# No stale hardcoded budget may survive alongside the variable.
stale=$(grep -rlE '\-ge 15 \]|timed out after 15 minutes|15[- ]minute|15 iterations' "$SHIP_MD" "$MERGE_MD" 2>/dev/null | wc -l)
if [[ "$stale" -eq 0 ]]; then
  pass "no hardcoded 15-minute budget remains in either file"
else
  fail "a hardcoded 15-minute budget survives in $stale file(s) beside MAX_POLL_MIN"
fi

# ---------------------------------------------------------------------------
rm -f "$BLOCK_FILE" "$BLOCK_FILE.err" "$MIRROR_FILE" "$MIRROR_FILE.err"
echo
echo "ship-phase-7 fixture: $PASS pass, $FAIL fail"
# Anti-vacuity floor: every row is a fixed pattern list, so the verdict count
# is deterministic. A dispatch that silently stops running rows (a no-op'd
# run_scenario, a deleted call) must not read as green. Reported directly —
# never through pass/fail, which is the machinery it backstops. Ratchet the
# literal up when rows are added; never down.
MIN_VERDICTS=380
if (( PASS + FAIL < MIN_VERDICTS )); then
  printf '  FATAL: anti-vacuity: only %s verdicts; the floor is %s (fix the dispatch, do not lower it).\n' "$((PASS + FAIL))" "$MIN_VERDICTS" >&2
  exit 1
fi
[[ "$FAIL" -eq 0 ]] || exit 1
