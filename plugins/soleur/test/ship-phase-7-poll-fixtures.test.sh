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
#   3. BEHIND saturation through 6 syncs then structured warning (both blocks)
#   4. DIRTY exit (real conflict: merge-tree rc=1)
#   4b. DIRTY but locally clean (merge-tree rc=0) → BEHIND auto-sync, not dirty-exit
#   5. absent required check (CI not yet registered) — does NOT exit
#   6. merge conflict during BEHIND auto-sync → abort + stop, never "pushed" (both blocks)
#   6b. merge refused to start (rc 2, no MERGE_HEAD) → truthful message, nothing aborted
#   6c. merge already in progress (MERGE_HEAD pre-exists) → not touched, stop
#   7. push fails after a clean merge → "git push failed after merge", stop
#   8. fetch fails → attempt skipped and counted, loop continues to behind_exhausted
#   9. success path characterization — one sync, re-fetch sees MERGED, no tick 2
#   10. real git (no mock): a conflict aborts cleanly; a pre-staged resolution survives
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
               'sync_out="$(git merge origin/main --no-edit 2>&1)"' \
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
# Scenario harness. Each scenario file defines `gh()` (and may override
# `git()` to inject conflict states); `sleep` and `date` are always shadowed
# in the subshell to keep the fixture fast and timestamp-stable.
#
# The subshell runs with pipefail OFF — the Monitor tool's shell does not set
# it, and under pipefail the block's `if ! cmd | tail` guards happen to work,
# so a harness inheriting the file-level `set -o pipefail` is GREEN on the
# very defect #8339 exists to catch (measured). Scenario 0 pins this.
#
# Mock state crosses `$( … )` boundaries via files under $MOCK_STATE, never
# shell variables: the block runs `gh pr view` and all three sync commands
# inside command substitutions, so a variable set inside a mock is lost.
#
# `must_match` is a NEWLINE-separated list, one pass/fail per pattern (AND).
# A single alternation ERE cannot express AND and makes mutation rows vacuous.
# ---------------------------------------------------------------------------
run_scenario() {
  local label="$1"
  local mocks_file="$2"
  local must_match="$3"
  local must_not_match="${4:-}"
  local block="${5:-$BLOCK_FILE}"
  local logfile
  logfile="$(mktemp)"
  MOCK_STATE="$(mktemp -d)"
  export MOCK_STATE

  (
    set +o pipefail
    sleep() { return 0; }
    date() { echo "00:00:00"; }
    git() {
      case "$1" in
        # `rev-parse -q --verify MERGE_HEAD` (the #8339 precondition) must
        # answer "no merge in progress" (rc 1); every other rev-parse answers
        # the branch name.
        rev-parse) [[ "${2:-}" == "-q" ]] && return 1; echo "test-branch" ;;
        *) return 0 ;;
      esac
    }
    # shellcheck disable=SC1090
    source "$mocks_file"
    # shellcheck disable=SC1090
    source "$block"
  ) > "$logfile" 2>&1
  local rc=$?

  local pat
  while IFS= read -r pat; do
    [[ -z "$pat" ]] && continue
    if grep -qE "$pat" "$logfile"; then
      pass "[$label] matched: $pat"
    else
      fail "[$label] did NOT match: $pat (rc=$rc)"
      echo "    --- scenario output ---"
      sed 's/^/      /' "$logfile"
      echo "    --- end output ---"
    fi
  done <<< "$must_match"
  if [[ -n "$must_not_match" ]]; then
    if grep -qE "$must_not_match" "$logfile"; then
      fail "[$label] forbidden pattern present: $must_not_match"
      echo "    --- scenario output ---"
      sed 's/^/      /' "$logfile"
      echo "    --- end output ---"
    else
      pass "[$label] forbidden pattern absent: $must_not_match"
    fi
  fi
  assert_fixture_dir "$MOCK_STATE"
  rm -rf "$MOCK_STATE"
  rm -f "$logfile"
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
run_scenario "1-clean-merged" "$SCEN1" \
  "MERGED CLEAN" \
  "ship.phase7.(required_failed|dirty|behind_exhausted)|UNEXPECTED gh call"
rm -f "$SCEN1"

# ---------------------------------------------------------------------------
# Scenario 2 — required-check failure on tick 5
# ---------------------------------------------------------------------------
SCEN2="$(mktemp)"
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
run_scenario "2-required-ci-fail" "$SCEN2" \
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
  "\[ship\.phase7\.behind_exhausted\] BEHIND budget exhausted after 6 auto-syncs" \
  "ship.phase7.(required_failed|dirty)|UNEXPECTED gh call"
run_scenario "3-behind-saturation:merge-pr" "$SCEN3" \
  "auto-sync 6/6 pushed
\[ship\.phase7\.behind_exhausted\] BEHIND budget exhausted after 6 auto-syncs" \
  "auto-sync 6 pushed|ship.phase7.(required_failed|dirty)|UNEXPECTED gh call" \
  "$MIRROR_FILE"
rm -f "$SCEN3"

# ---------------------------------------------------------------------------
# Scenario 4 — DIRTY (real conflict): merge-tree rc=1 → dirty-exit
# ---------------------------------------------------------------------------
SCEN4="$(mktemp)"
cat > "$SCEN4" <<EOF
${PRELUDE}
git() {
  case "\$1" in
    rev-parse) [[ "\${2:-}" == "-q" ]] && return 1; echo "test-branch" ;;
    merge-tree) return 1 ;;
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
run_scenario "4-dirty-exit" "$SCEN4" \
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
run_scenario "4b-dirty-locally-clean" "$SCEN4B" \
  "BEHIND detected — auto-sync attempt" \
  "\[ship\.phase7\.dirty\]|ship\.phase7\.behind_exhausted|UNEXPECTED gh call"
rm -f "$SCEN4B"

# ---------------------------------------------------------------------------
# Scenario 5 — absent required check (CI not yet registered) does NOT exit.
# Required set = ["test", "e2e"]; `gh pr checks` returns only "test" with
# bucket=pass (no fail event). The loop must heartbeat through to timeout
# rather than treating an unregistered required check as a failure.
# ---------------------------------------------------------------------------
SCEN5="$(mktemp)"
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
run_scenario "5-absent-required-check" "$SCEN5" \
  "Merge poll timed out" \
  "ship\.phase7\.(required_failed|dirty|behind_exhausted)|UNEXPECTED gh call"
rm -f "$SCEN5"

# ---------------------------------------------------------------------------
# Shared BEHIND sync-arm mock for scenarios 6/6b/6c/7/8/9 (#8339).
#
# Knobs (plain variables in the mocks file): MOCK_FETCH_RC, MOCK_MERGE
# (ok|conflict|refused), MOCK_PUSH_RC. State crosses `$( … )` via files:
# $MOCK_STATE/MERGE_HEAD (created by a conflicting merge, removed by
# --abort) and $MOCK_STATE/pushed (created by a successful push; `gh` flips
# to MERGED once it exists). The `"rev-parse -q"` case MUST precede the
# `"rev-parse "*` glob, or `rev-parse -q --verify MERGE_HEAD` answers
# "test-branch" rc 0 and the merge_in_progress precondition fires on tick 1.
# The --abort sentinel is on STDOUT: the pre-fix block ran `--abort
# 2>/dev/null`, so a stderr sentinel would have been invisible.
# ---------------------------------------------------------------------------
SYNC_MOCKS="$(cat <<'EOF'
_gh_unexpected() {
  echo "UNEXPECTED gh call: $*" >&2
  return 2
}
git() {
  case "$1 ${2:-}" in
    "rev-parse -q") [[ -e "$MOCK_STATE/MERGE_HEAD" ]] ;;
    "rev-parse "*) echo "test-branch" ;;
    "fetch origin")
      if (( ${MOCK_FETCH_RC:-0} )); then echo "fatal: unable to access 'origin'"; fi
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
      esac ;;
    "merge --abort") echo "MOCK: git merge --abort observed"; rm -f "$MOCK_STATE/MERGE_HEAD" ;;
    "diff --name-only") [[ -e "$MOCK_STATE/MERGE_HEAD" ]] && echo "foo.md" ;;
    "status --short") echo " M f" ;;
    "push "|"push")
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

# Runs a sync-arm scenario against BOTH blocks with `:ship` / `:merge-pr`
# label suffixes. $1 label, $2 mocks file, $3 must-match list, $4 must-not.
run_sync_scenario_both() {
  run_scenario "$1:ship"     "$2" "$3" "$4" "$BLOCK_FILE"
  run_scenario "$1:merge-pr" "$2" "$3" "$4" "$MIRROR_FILE"
}

STOP_FORBID='auto-sync [0-9/]+ pushed|ship\.phase7\.behind_exhausted|Merge poll timed out|UNEXPECTED gh call'

# ---------------------------------------------------------------------------
# Scenario 6 — merge conflict during BEHIND auto-sync. RED on the pre-#8339
# block: `git merge | tail -5` reports tail's 0, the conflict branch is
# unreachable, and the block prints "auto-sync 1 pushed" over a conflicted
# tree. `merge conflict` is anchored to the new line, not a bare token — the
# DIRTY arm already prints "PR is DIRTY (merge conflict)".
# ---------------------------------------------------------------------------
SCEN6="$(mktemp)"
cat > "$SCEN6" <<EOF
MOCK_MERGE=conflict
${SYNC_MOCKS}
EOF
run_sync_scenario_both "6-merge-conflict-in-sync" "$SCEN6" \
  "MOCK: git merge --abort observed
git merge origin/main failed — merge conflict, aborting sync\. Conflicted paths:
^foo\.md$
Manual conflict resolution required on test-branch\. Stopping the poll\.
kind=merge rc=1" \
  "$STOP_FORBID"
rm -f "$SCEN6"

# ---------------------------------------------------------------------------
# Scenario 6b — merge REFUSED to start (rc 2: dirty tracked file / untracked
# overwrite; no MERGE_HEAD). Not a conflict: nothing to abort, so an
# unconditional `--abort` here is the wrong (and previously swallowed) call.
# ---------------------------------------------------------------------------
SCEN6B="$(mktemp)"
cat > "$SCEN6B" <<EOF
MOCK_MERGE=refused
${SYNC_MOCKS}
EOF
run_sync_scenario_both "6b-merge-refused" "$SCEN6B" \
  "kind=merge_refused rc=2
refused to start
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
cat > "$SCEN6C" <<EOF
: > "\$MOCK_STATE/MERGE_HEAD"
${SYNC_MOCKS}
EOF
run_sync_scenario_both "6c-merge-in-progress" "$SCEN6C" \
  "kind=merge_in_progress" \
  "$STOP_FORBID|MOCK: git merge --abort observed|Manual conflict resolution required|Merge made by"
rm -f "$SCEN6C"

# ---------------------------------------------------------------------------
# Scenario 7 — push fails after a clean merge. RED on the pre-#8339 block for
# the same reason as 6 (`git push | tail -2`).
# ---------------------------------------------------------------------------
SCEN7="$(mktemp)"
cat > "$SCEN7" <<EOF
MOCK_PUSH_RC=1
${SYNC_MOCKS}
EOF
run_sync_scenario_both "7-push-fails-after-merge" "$SCEN7" \
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
cat > "$SCEN8" <<EOF
MOCK_FETCH_RC=1
${SYNC_MOCKS}
EOF
run_sync_scenario_both "8-fetch-fails-skips-attempt" "$SCEN8" \
  "kind=fetch rc=1
fetch origin main failed
ship\.phase7\.behind_exhausted
fetch_failures=6/6" \
  "auto-sync [0-9/]+ pushed|MOCK: git merge --abort observed|git push failed after merge|UNEXPECTED gh call"
rm -f "$SCEN8"

# ---------------------------------------------------------------------------
# Scenario 9 — success path characterization (GREEN before and after the fix).
# One sync pushes, the post-push re-fetch sees MERGED and breaks before tick
# 2. This is the net under the if/elif → nested refactor: dropping the
# re-fetch, or renaming the success echo, reddens it.
# ---------------------------------------------------------------------------
SCEN9="$(mktemp)"
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
# Scenario 10 — REAL git, no `git` mock (the retroactive application #8339
# asks for, as a repeatable row). A bare origin + clone `a` (feat branch
# editing `f`) + clone `b` (pushes a conflicting main). The ship block is
# sourced in `a` with `gh` a marker-file stub.
#
#   A. conflict: the arm names `f`, aborts, and leaves `a` clean —
#      MERGE_HEAD gone, porcelain empty, both remote refs unchanged.
#   B. a pre-staged resolution (operator mid-merge): the arm reports
#      merge_in_progress and the staged file is still staged afterwards.
#
# Everything lives under a throwaway dir beside $BLOCK_FILE, never the
# worktree; `git_fixture_env` sweeps inherited GIT_* and pins config/identity
# so the throwaway `git init` cannot land in the real repository (#7833).
# Verdicts are printed as `POST:` lines from inside the subshell (pass/fail
# counters do not survive it) and asserted with the same grep as the stream.
# ---------------------------------------------------------------------------
# `mktemp -d -t` lands beside $BLOCK_FILE (same TMPDIR), never in the worktree.
SCEN10_TMP="$(mktemp -d -t ship-phase7-realgit.XXXXXX)"
assert_fixture_dir "$SCEN10_TMP"
SCEN10_LOG="$(mktemp)"
(
  set +o pipefail
  git_fixture_env "$SCEN10_TMP" || exit 2
  tmp="$SCEN10_TMP"
  assert_fixture_dir "$tmp"
  git init -q --bare -b main "$tmp/origin" || exit 2
  git init -q -b main "$tmp/a" || exit 2
  cd "$tmp/a" || exit 2
  git remote add origin "$tmp/origin"
  echo base > f && git add f && git commit -qm base && git push -q origin main || exit 2
  git checkout -q -b feat && echo feat > f && git commit -qam feat && git push -q -u origin feat || exit 2
  git clone -q -b main "$tmp/origin" "$tmp/b" || exit 2
  ( cd "$tmp/b" && echo other > f && git commit -qam other && git push -q origin main ) || exit 2
  cd "$tmp/a" || exit 2
  git fetch -q origin
  before_main="$(git rev-parse origin/main)"; before_feat="$(git rev-parse origin/feat)"

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

  echo "=== sub-row A: real conflict ==="
  # shellcheck disable=SC1090
  source "$BLOCK_FILE"
  git rev-parse -q --verify MERGE_HEAD >/dev/null 2>&1; echo "POST-A: merge_head_rc=$?"
  if [[ -z "$(git status --porcelain)" ]]; then echo "POST-A: porcelain=clean"; else echo "POST-A: porcelain=dirty"; git status --porcelain; fi
  git fetch -q origin
  [[ "$(git rev-parse origin/main)" == "$before_main" ]] && echo "POST-A: origin_main=unchanged" || echo "POST-A: origin_main=CHANGED"
  [[ "$(git rev-parse origin/feat)" == "$before_feat" ]] && echo "POST-A: origin_feat=unchanged" || echo "POST-A: origin_feat=CHANGED"

  echo "=== sub-row B: pre-staged resolution ==="
  # Leave the tree exactly as a real run would (abort if A did not), then
  # reproduce an operator mid-resolution and re-run the arm.
  git merge --abort >/dev/null 2>&1 || true
  rm -f "$tmp/tick"
  git merge origin/main --no-edit >/dev/null 2>&1
  echo resolved > f && git add f
  # shellcheck disable=SC1090
  source "$BLOCK_FILE"
  if [[ -n "$(git diff --cached --name-only)" ]]; then echo "POST-B: staged=present"; else echo "POST-B: staged=DISCARDED"; fi
  [[ "$(cat f)" == "resolved" ]] && echo "POST-B: f=resolved" || echo "POST-B: f=$(cat f)"
) > "$SCEN10_LOG" 2>&1
scen10_rc=$?

# Each sub-row is asserted against ITS OWN section of the log: sub-row A
# legitimately prints "Manual conflict resolution required", which sub-row B
# forbids, so an unscoped grep would red B on A's output.
scen10_section() {
  case "$1" in
    A) sed -n '/^=== sub-row A/,/^=== sub-row B/p' "$SCEN10_LOG" ;;
    B) sed -n '/^=== sub-row B/,$p' "$SCEN10_LOG" ;;
  esac
}
scen10_check() {
  local row="$1" label="$2" pat="$3"
  if scen10_section "$row" | grep -qE "$pat"; then
    pass "[10-real-git-conflict] $row: $label"
  else
    fail "[10-real-git-conflict] $row: $label — pattern absent: $pat (rc=$scen10_rc)"
  fi
}
scen10_forbid() {
  local row="$1" label="$2" pat="$3"
  if scen10_section "$row" | grep -qE "$pat"; then
    fail "[10-real-git-conflict] $row: $label — forbidden pattern present: $pat"
  else
    pass "[10-real-git-conflict] $row: $label"
  fi
}
if [[ "$scen10_rc" -eq 2 ]]; then
  fail "[10-real-git-conflict] fixture setup failed (rc=2)"
  sed 's/^/      /' "$SCEN10_LOG"
else
  scen10_check  A "conflict reported with rc"        'kind=merge rc=1'
  scen10_check  A "conflicted path named"            '^f$'
  scen10_check  A "poll stopped on feat"             'Manual conflict resolution required on feat'
  scen10_forbid A "never reported as pushed"         'auto-sync [0-9/]+ pushed'
  scen10_check  A "MERGE_HEAD absent after abort"    'POST-A: merge_head_rc=1'
  scen10_check  A "worktree clean after abort"       'POST-A: porcelain=clean'
  scen10_check  A "origin/main unchanged"            'POST-A: origin_main=unchanged'
  scen10_check  A "origin/feat unchanged"            'POST-A: origin_feat=unchanged'
  scen10_check  B "in-progress merge reported"       'kind=merge_in_progress'
  scen10_forbid B "in-progress merge not aborted"    'Manual conflict resolution required|auto-sync [0-9/]+ pushed|Merge made by'
  scen10_check  B "staged resolution survived"       'POST-B: staged=present'
  scen10_check  B "resolved content survived"        'POST-B: f=resolved'
fi
if [[ "$FAIL" -gt 0 ]] && grep -q 'POST-A: porcelain=dirty\|DISCARDED\|UNEXPECTED' "$SCEN10_LOG"; then
  echo "    --- scenario 10 output ---"
  sed 's/^/      /' "$SCEN10_LOG"
  echo "    --- end output ---"
fi
assert_fixture_dir "$SCEN10_TMP"
rm -rf "$SCEN10_TMP"
rm -f "$SCEN10_LOG"

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
stale=$(grep -rlE '\-ge 15 \]|timed out after 15 minutes' "$SHIP_MD" "$MERGE_MD" 2>/dev/null | wc -l)
if [[ "$stale" -eq 0 ]]; then
  pass "no hardcoded 15-minute budget remains in either file"
else
  fail "a hardcoded 15-minute budget survives in $stale file(s) beside MAX_POLL_MIN"
fi

# ---------------------------------------------------------------------------
rm -f "$BLOCK_FILE" "$BLOCK_FILE.err" "$MIRROR_FILE" "$MIRROR_FILE.err"
echo
echo "ship-phase-7 fixture: $PASS pass, $FAIL fail"
[[ "$FAIL" -eq 0 ]] || exit 1
