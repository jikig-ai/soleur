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
#   11. not inside a worktree → BEHIND auto-sync disabled, poll heartbeats
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
               'sync_out="$(GIT_TRACE=0 git merge origin/main --no-edit 2>&1)" || sync_rc=$?' \
               'merge conflict, aborting sync' 'kind=merge_refused' \
               'kind=merge_in_progress' 'git push failed after merge' \
               'fetch_failures='; do
    if ! grep -qF "$token" "$MIRROR_FILE"; then
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

# The Monitor tool streams STDOUT only (stderr lands in the output file and
# raises no notification), so every tagged exit line must be on stdout.
assert_no_tag_on_stderr() {
  local label="$1" errfile="$2"
  if grep -q 'ship\.phase7\.' "$errfile"; then
    fail "[$label] tagged line on stderr (Monitor streams stdout only): $(grep 'ship\.phase7\.' "$errfile" | head -1 | cut -c1-120)"
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

  (
    set +o pipefail
    [[ "${SCENARIO_SET_E:-0}" == 1 ]] && set -e
    sleep() { return 0; }
    date() { echo "00:00:00"; }
    git() {
      case "$1 ${2:-}" in
        # `rev-parse -q --verify MERGE_HEAD` (the #8339 precondition) must
        # answer "no merge in progress" (rc 1); `--is-inside-work-tree` must
        # print `true` (the block compares the OUTPUT); `--git-dir` points at
        # the per-row state dir so sequencer files can be modelled.
        "rev-parse -q") return 1 ;;
        "rev-parse --is-inside-work-tree") echo true ;;
        "rev-parse --git-dir") echo "$MOCK_STATE" ;;
        "rev-parse "*) echo "test-branch" ;;
        *) return 0 ;;
      esac
    }
    # shellcheck disable=SC1090
    source "$mocks_file"
    # shellcheck disable=SC1090
    source "$block"
  ) > "$logfile" 2> "$errfile"
  local rc=$?
  assert_no_tag_on_stderr "$label" "$errfile"
  # Match over both streams (the block's non-tagged lines may legitimately use
  # stderr), with the exit status recorded for the dump.
  { echo "[scenario exit rc=$rc]"; cat "$errfile"; } >> "$logfile"
  assert_log "$label" "$logfile" "$must_match" "$must_not_match"
  rm -rf "$MOCK_STATE"
  rm -f "$logfile" "$errfile"
}

# Runs a scenario against BOTH blocks with `:ship` / `:merge-pr` label suffixes.
# $1 label, $2 mocks file, $3 must-match list, $4 must-not.
run_scenario_both() {
  run_scenario "$1:ship"     "$2" "$3" "$4" "$BLOCK_FILE"
  run_scenario "$1:merge-pr" "$2" "$3" "$4" "$MIRROR_FILE"
}

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
run_scenario "3-behind-saturation:ship" "$SCEN3" \
  "\[ship\.phase7\.behind_exhausted\] BEHIND budget exhausted after 6 auto-syncs
fetch_failures=0/6
moving faster than this PR" \
  "ship.phase7.(required_failed|dirty)|Every attempt failed at git fetch|UNEXPECTED gh call"
run_scenario "3-behind-saturation:merge-pr" "$SCEN3" \
  "auto-sync 6/6 pushed
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
    "rev-parse -q") return 1 ;;
    "rev-parse --is-inside-work-tree") echo true ;;
    "rev-parse --git-dir") echo "\$MOCK_STATE" ;;
    "rev-parse "*) echo "test-branch" ;;
    "merge-tree "*) return 1 ;;
    *) return 0 ;;
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
    "rev-parse -q") return 1 ;;
    "rev-parse --is-inside-work-tree") echo true ;;
    "rev-parse --git-dir") echo "\$MOCK_STATE" ;;
    "rev-parse "*) echo "test-branch" ;;
    "fetch "*) echo "fatal: unable to access 'origin'"; return 1 ;;
    *) return 0 ;;
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
# (ok|conflict|refused|inprogress128), MOCK_PUSH_RC, MOCK_ABORT_RC,
# MOCK_FETCH_STARTS_MERGE (the fetch window creates MERGE_HEAD — an operator
# started a merge while the arm was fetching). State crosses `$( … )` via
# files: $MOCK_STATE/MERGE_HEAD (created by a conflicting merge, removed by
# --abort), $MOCK_STATE/pushed (created by a successful push; `gh` flips to
# MERGED once it exists), $MOCK_STATE/detached (symbolic-ref fails),
# $MOCK_STATE/rebase-merge (a sequencer directory under --git-dir). The
# `"rev-parse -q"` case MUST precede the `"rev-parse "*` glob, or
# `rev-parse -q --verify MERGE_HEAD` answers "test-branch" rc 0 and the
# merge_in_progress precondition fires on tick 1. The --abort sentinel is on
# STDOUT: under inherited pipefail (harness row H1) the pre-fix block DOES
# reach its `--abort 2>/dev/null`, and a stderr sentinel would have been
# invisible there.
# ---------------------------------------------------------------------------
SYNC_MOCKS="${PRELUDE}$(cat <<'EOF'
git() {
  case "$1 ${2:-}" in
    "rev-parse -q") [[ -e "$MOCK_STATE/MERGE_HEAD" ]] ;;
    "rev-parse --is-inside-work-tree") echo true ;;
    "rev-parse --git-dir") echo "$MOCK_STATE" ;;
    "rev-parse "*) echo "test-branch" ;;
    "symbolic-ref "*) [[ ! -e "$MOCK_STATE/detached" ]] ;;
    "fetch origin")
      if (( ${MOCK_FETCH_RC:-0} )); then echo "fatal: unable to access 'origin'"; fi
      if (( ${MOCK_FETCH_STARTS_MERGE:-0} )); then : > "$MOCK_STATE/MERGE_HEAD"; fi
      return "${MOCK_FETCH_RC:-0}" ;;
    "merge origin/main")
      case "${MOCK_MERGE:-ok}" in
        ok) echo "Merge made by the 'ort' strategy." ;;
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
    "diff --name-only") [[ -e "$MOCK_STATE/MERGE_HEAD" ]] && echo "foo.md" ;;
    "status --short") echo " M f" ;;
    "push ")
      if (( ${MOCK_PUSH_RC:-0} )); then
        echo "error: failed to push some refs to 'origin'"
      else
        : > "$MOCK_STATE/pushed"
      fi
      return "${MOCK_PUSH_RC:-0}" ;;
    *) return 0 ;;
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
Manual conflict resolution required on test-branch\. Stopping the poll\.
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
^ M f$" \
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
Manual conflict resolution required on test-branch\. Stopping the poll\." \
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
Manual conflict resolution required on test-branch\. Stopping the poll\.
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
  "kind=merge_in_progress — a merge/rebase/cherry-pick/revert is in progress on test-branch" \
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
# Scenario 11 — not inside a worktree (`--is-inside-work-tree` prints
# `false`, rc 0 — a bare repo): the precondition disables the BEHIND arm and
# says so; the poll heartbeats to timeout instead of running git merge in a
# bare repo.
# ---------------------------------------------------------------------------
SCEN11="$(mktemp)"
_TMP_OWNED+=("$SCEN11")
cat > "$SCEN11" <<EOF
${PRELUDE}
git() {
  case "\$1 \${2:-}" in
    "rev-parse --is-inside-work-tree") echo false ;;
    "rev-parse -q") return 1 ;;
    "rev-parse "*) echo "test-branch" ;;
    *) return 0 ;;
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
Merge poll timed out" \
  "BEHIND detected|auto-sync [0-9/]+ pushed|Merge made by|ship\.phase7\.behind_exhausted|UNEXPECTED gh call"
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
kind=merge_in_progress — a merge/rebase/cherry-pick/revert is in progress on HEAD
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
MIN_VERDICTS=191
if (( PASS + FAIL < MIN_VERDICTS )); then
  printf '  FATAL: anti-vacuity: only %s verdicts; the floor is %s (fix the dispatch, do not lower it).\n' "$((PASS + FAIL))" "$MIN_VERDICTS" >&2
  exit 1
fi
[[ "$FAIL" -eq 0 ]] || exit 1
