#!/usr/bin/env bash
# Fixture-based tests for pre-merge-rebase.sh. Asserts each of the four deny
# branches calls emit_incident with the expected rule_id + event_type=deny.
#
# Isolation: each test builds its own work-tree (git repo) plus a separate
# "incidents root" directory under mktemp. INCIDENTS_REPO_ROOT redirects
# emit_incident's writes into the incidents root so the operator's real
# .claude/.rule-incidents.jsonl is not polluted.

set -euo pipefail

# Redirect incident telemetry into a per-suite sandbox BEFORE any case runs.
# Inline per-call `INCIDENTS_REPO_ROOT=… bash "$HOOK"` is what leaked here:
# it was set on some invocations and missed on others, which greps identically
# to full isolation. See the helper header.
. "$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/lib/test-incident-sandbox.sh"

# Refuse before writing, rather than let an empty operand retarget a git write at whatever
# repository the caller happens to be standing in. `git -C ""` does NOT error — it silently
# operates on the current directory, which under TEST_GROUP=scripts is the developer's live
# worktree, whose `.git/config` is the SHARED file every worktree on the machine inherits.
#
# Rejects, beyond empty: bare `/` AND its aliases `//` and `/.` (a `/*` arm accepts all three, and
# `rm -rf "/"/*` is the worst outcome in this corpus — a one-character bypass of a stated
# rejection); any path containing `..`, which can resolve back inside the real repo; and
# /proc, /sys, /dev, because `/proc/self/cwd` is absolute, passes every other arm, and resolves
# to precisely "whatever repository the caller happens to be standing in".
#
# Still no `realpath`: it breaks on a symlinked /tmp, which this corpus uses. So a symlink to
# $HOME is ACCEPTED — stated here rather than left implied, because the arms above make this
# look like a containment check and it is not.
#
# The body below is a COPY. The canonical definition lives in
# plugins/soleur/test/test-helpers.sh; plugins/soleur/test/fixture-dir-operand-assert.test.sh
# asserts this copy is byte-equal to it. Do not reword it in one file only. #7652
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

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$SCRIPT_DIR/pre-merge-rebase.sh"

PASS=0
FAIL=0
TOTAL=0

command -v jq >/dev/null 2>&1 || { echo "SKIP: jq missing"; exit 0; }
command -v git >/dev/null 2>&1 || { echo "SKIP: git missing"; exit 0; }

# The hook's `gh` calls resolve the repository from the fixture's remotes (a local
# bare path → "no GitHub remote" → fast, offline failure). GH_REPO/GH_HOST would
# make gh skip the remotes and reach the real API from every case (#8778).
unset GH_REPO GH_HOST

init_git_repo() {
  local dir="$1"
  assert_fixture_dir "$dir"
  git -C "$dir" init -q
  git -C "$dir" symbolic-ref HEAD refs/heads/main
  git -C "$dir" config user.email test@test.local
  git -C "$dir" config user.name "Test User"
  git -C "$dir" config commit.gpgsign false
}

# Attach a local bare origin and publish the current branch as main.
#
# Since #6724 both local review-evidence signals are scoped to
# `origin/main..HEAD`, so a repo with no origin has no resolvable range: every
# signal comes back empty and the gate denies with
# rf-never-skip-qa-review-before-merging, regardless of what the test was
# actually trying to exercise. Any test that needs to get PAST the gate needs a
# real origin. Bare + local keeps it offline-safe.
#
# Call AFTER the initial commit (there must be something to push).
attach_origin() {
  local work="$1" origin="$2"
  assert_fixture_dir "$work"
  git init -q --bare -b main "$origin"
  git -C "$work" remote add origin "$origin"
  git -C "$work" push -q origin HEAD:main
  git -C "$work" fetch --no-tags -q origin
}

# Seed review evidence AS A COMMIT ON THE CURRENT BRANCH.
#
# Under branch scoping, evidence only counts if it lives on a commit unique to
# the branch — an uncommitted or already-on-main todos/ file is precisely what
# the #6724 fix stops honouring. Callers that want the vacuity case (evidence
# present in the tree but NOT introduced by this branch) must seed it on main
# BEFORE forking, via seed_review_evidence_on_main.
seed_review_evidence() {
  local work="$1"
  assert_fixture_dir "$work"
  mkdir -p "$work/todos"
  echo "code-review" > "$work/todos/sample.md"
  git -C "$work" add todos/sample.md
  git -C "$work" commit -q -m "review: findings for this branch"
}

# Seed a long-lived review todo on MAIN, pre-fork. This is the exact state that
# made the old repo-global grep unfailable: the file is present in the working
# tree of every branch forever, so a branch that never ran review still looked
# reviewed.
seed_review_evidence_on_main() {
  local work="$1"
  assert_fixture_dir "$work"
  mkdir -p "$work/todos"
  echo "code-review" > "$work/todos/legacy-finding.md"
  git -C "$work" add todos/legacy-finding.md
  git -C "$work" commit -q -m "chore: long-lived review todo on main"
}

make_payload() {
  local cwd="$1" cmd="$2"
  jq -nc --arg c "$cwd" --arg x "$cmd" \
    '{tool_input: {command: $x}, cwd: $c}'
}

# assert_deny <name> <incidents_root> <stdout> <exit_code> <expected_rule_id>
assert_deny() {
  local name="$1" incidents="$2" out="$3" exit_code="$4" expected="$5"
  local decision jsonl seen_rule seen_event count
  decision=$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecision // ""' 2>/dev/null || echo "")
  jsonl="$incidents/.claude/.rule-incidents.jsonl"
  if [[ ! -f "$jsonl" ]]; then
    echo "FAIL: $name (no incidents jsonl at $jsonl; exit=$exit_code decision=$decision)"
    FAIL=$((FAIL + 1)); TOTAL=$((TOTAL + 1)); return
  fi
  count=$(wc -l < "$jsonl" | tr -d ' ')
  seen_rule=$(jq -r '.rule_id' < "$jsonl" | head -1)
  seen_event=$(jq -r '.event_type' < "$jsonl" | head -1)
  if [[ "$exit_code" -eq 0 && "$decision" == "deny" && "$count" == "1" \
        && "$seen_rule" == "$expected" && "$seen_event" == "deny" ]]; then
    echo "PASS: $name"
    PASS=$((PASS + 1))
  else
    echo "FAIL: $name"
    echo "  exit=$exit_code decision=$decision count=$count rule=$seen_rule event=$seen_event"
    echo "  expected: rule=$expected event=deny count=1 decision=deny"
    FAIL=$((FAIL + 1))
  fi
  TOTAL=$((TOTAL + 1))
}

# assert_no_intercept <name> <incidents_root> <stdout> <exit_code>
# Inverse of assert_deny: the early-exit (no-merge-detected) path must exit 0,
# emit NO stdout, and write NO incidents jsonl (the hook returns before any
# emit_incident). Used by the #4600 false-positive cases and the malformed-JSON
# fail-open case.
assert_no_intercept() {
  local name="$1" incidents="$2" out="$3" exit_code="$4"
  local jsonl="$incidents/.claude/.rule-incidents.jsonl"
  local ok=1
  if [[ "$exit_code" -ne 0 ]]; then ok=0; fi
  if [[ -n "$out" ]]; then ok=0; fi
  if [[ -f "$jsonl" ]]; then ok=0; fi
  if [[ "$ok" -eq 1 ]]; then
    echo "PASS: $name"
    PASS=$((PASS + 1))
  else
    echo "FAIL: $name"
    echo "  exit=$exit_code stdout=${out:-<empty>} jsonl_exists=$([[ -f "$jsonl" ]] && echo yes || echo no)"
    echo "  expected: exit=0 stdout=<empty> jsonl_exists=no"
    FAIL=$((FAIL + 1))
  fi
  TOTAL=$((TOTAL + 1))
}

run_hook() {
  local incidents="$1" payload="$2"
  # Capture stdout; stderr goes to /dev/null to keep test output clean.
  INCIDENTS_REPO_ROOT="$incidents" printf '%s' "$payload" | "$HOOK" 2>/dev/null
}

# --- T1: review-evidence gate (no review evidence present) ---------------
t1_review_evidence_gate() {
  local tmp; tmp=$(mktemp -d)
  local work="$tmp/work" incidents="$tmp/incidents"
  mkdir -p "$work" "$incidents"
  init_git_repo "$work"
  git -C "$work" commit -q --allow-empty -m "init"
  git -C "$work" checkout -q -b feat-no-review
  git -C "$work" commit -q --allow-empty -m "feature work"
  # No todos/, no review commit, no remote with open PR.

  local payload out exit_code=0
  payload=$(make_payload "$work" "gh pr merge 123 --squash")
  out=$(printf '%s' "$payload" | INCIDENTS_REPO_ROOT="$incidents" "$HOOK" 2>/dev/null) || exit_code=$?
  exit_code=${exit_code:-0}
  assert_deny "T1 review-evidence gate" "$incidents" "$out" "$exit_code" \
    "rf-never-skip-qa-review-before-merging"
  rm -rf "$tmp"
}

# --- T2: uncommitted changes ---------------------------------------------
t2_uncommitted_changes() {
  local tmp; tmp=$(mktemp -d)
  local work="$tmp/work" incidents="$tmp/incidents"
  mkdir -p "$work" "$incidents"
  init_git_repo "$work"
  echo "initial" > "$work/file.txt"
  git -C "$work" add file.txt
  git -C "$work" commit -q -m "init"
  # Needs a real origin: the review-evidence signals are scoped to
  # `origin/main..HEAD` since #6724, and without one this test denies at the
  # review gate instead of reaching the uncommitted-changes check it exercises.
  attach_origin "$work" "$tmp/origin.git"
  git -C "$work" checkout -q -b feat-dirty
  seed_review_evidence "$work"
  # Dirty the tree (tracked file modified but not committed).
  echo "dirty" > "$work/file.txt"

  local payload out exit_code=0
  payload=$(make_payload "$work" "gh pr merge 124 --squash")
  out=$(printf '%s' "$payload" | INCIDENTS_REPO_ROOT="$incidents" "$HOOK" 2>/dev/null) || exit_code=$?
  exit_code=${exit_code:-0}
  assert_deny "T2 uncommitted changes" "$incidents" "$out" "$exit_code" \
    "hr-when-a-command-exits-non-zero-or-prints"
  rm -rf "$tmp"
}

# --- T3: merge conflict --------------------------------------------------
t3_merge_conflict() {
  local tmp; tmp=$(mktemp -d)
  local work="$tmp/work" origin="$tmp/origin.git" incidents="$tmp/incidents"
  mkdir -p "$work" "$incidents"
  git init -q --bare -b main "$origin"

  init_git_repo "$work"
  echo "base" > "$work/file.txt"
  git -C "$work" add file.txt
  git -C "$work" commit -q -m "init"
  git -C "$work" remote add origin "$origin"
  git -C "$work" push -q origin main

  # Feature branch with conflicting change.
  git -C "$work" checkout -q -b feat-conflict
  echo "feature side" > "$work/file.txt"
  git -C "$work" commit -aq -m "feature change"
  seed_review_evidence "$work"

  # Update origin/main with a diverging change via a second clone.
  local other="$tmp/other"
  git clone -q "$origin" "$other"
  git -C "$other" config user.email test@test.local
  git -C "$other" config user.name "Test User"
  echo "main side" > "$other/file.txt"
  git -C "$other" commit -aq -m "main change"
  git -C "$other" push -q origin main

  local payload out exit_code=0
  payload=$(make_payload "$work" "gh pr merge 125 --squash")
  out=$(printf '%s' "$payload" | INCIDENTS_REPO_ROOT="$incidents" "$HOOK" 2>/dev/null) || exit_code=$?
  exit_code=${exit_code:-0}
  assert_deny "T3 merge conflict" "$incidents" "$out" "$exit_code" \
    "hr-when-a-command-exits-non-zero-or-prints"
  rm -rf "$tmp"
}

# --- T3b: the resolver's refusal reaches the agent in the deny reason --------
# The hook's stderr is not shown to the agent; the deny reason is. When the regen resolver
# declines, its [regen-on-conflict] line must be in permissionDecisionReason, or the agent is
# told only to "resolve manually" — which for a generated artifact is the wrong remedy.
t3b_regen_diagnosis_in_deny() {
  local tmp; tmp=$(mktemp -d)
  trap 'rm -rf "$tmp"; trap - RETURN' RETURN
  local work="$tmp/work" origin="$tmp/origin.git" incidents="$tmp/incidents"
  assert_fixture_dir "$work"
  mkdir -p "$work/plugins/soleur/scripts" "$incidents"
  git init -q --bare -b main "$origin"
  init_git_repo "$work"
  cp "$SCRIPT_DIR/../../plugins/soleur/scripts/resolve-regenerable-conflicts.sh" "$work/plugins/soleur/scripts/"
  echo "base" > "$work/file.txt"
  git -C "$work" add -A
  git -C "$work" commit -q -m "init"
  git -C "$work" remote add origin "$origin"
  git -C "$work" push -q origin main
  git -C "$work" checkout -q -b feat-conflict-regen
  echo "feature side" > "$work/file.txt"
  git -C "$work" commit -aq -m "feature change"
  seed_review_evidence "$work"
  local other="$tmp/other"
  git clone -q "$origin" "$other"
  git -C "$other" config user.email test@test.local
  git -C "$other" config user.name "Test User"
  echo "main side" > "$other/file.txt"
  git -C "$other" commit -aq -m "main change"
  git -C "$other" push -q origin main

  local payload out exit_code=0 reason
  payload=$(make_payload "$work" "gh pr merge 126 --squash")
  out=$(printf '%s' "$payload" | INCIDENTS_REPO_ROOT="$incidents" XDG_CACHE_HOME="$tmp/xdg" "$HOOK" 2>/dev/null) || exit_code=$?
  reason=$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecisionReason // ""' 2>/dev/null || echo "")
  TOTAL=$((TOTAL + 1))
  if [[ "$reason" == *"[regen-on-conflict] not applicable: conflicted path is not regenerable: file.txt"* ]]; then
    echo "PASS: T3b the resolver's refusal is in the deny reason"; PASS=$((PASS + 1))
  else
    echo "FAIL: T3b the deny reason lacks the resolver's diagnosis: $reason"; FAIL=$((FAIL + 1))
  fi
}

# --- T4: push failure ----------------------------------------------------
t4_push_failure() {
  local tmp; tmp=$(mktemp -d)
  local work="$tmp/work" origin="$tmp/origin.git" incidents="$tmp/incidents"
  mkdir -p "$work" "$incidents"
  git init -q --bare -b main "$origin"

  init_git_repo "$work"
  echo "base" > "$work/file.txt"
  git -C "$work" add file.txt
  git -C "$work" commit -q -m "init"
  git -C "$work" remote add origin "$origin"
  git -C "$work" push -q origin main

  # Feature branch with a non-conflicting change (different file).
  git -C "$work" checkout -q -b feat-pushfail
  echo "feat" > "$work/feature.txt"
  git -C "$work" add feature.txt
  git -C "$work" commit -q -m "feature change"
  seed_review_evidence "$work"

  # Diverge origin/main so the hook actually attempts a merge + push.
  local other="$tmp/other"
  git clone -q "$origin" "$other"
  git -C "$other" config user.email test@test.local
  git -C "$other" config user.name "Test User"
  echo "main-only" > "$other/mainfile.txt"
  git -C "$other" add mainfile.txt
  git -C "$other" commit -q -m "main change"
  git -C "$other" push -q origin main

  # Install pre-receive hook on origin that rejects every push.
  cat > "$origin/hooks/pre-receive" <<'EOF'
#!/bin/sh
echo "rejected by test pre-receive hook" >&2
exit 1
EOF
  chmod +x "$origin/hooks/pre-receive"

  local payload out exit_code=0
  payload=$(make_payload "$work" "gh pr merge 126 --squash")
  out=$(printf '%s' "$payload" | INCIDENTS_REPO_ROOT="$incidents" "$HOOK" 2>/dev/null) || exit_code=$?
  exit_code=${exit_code:-0}
  assert_deny "T4 push failure" "$incidents" "$out" "$exit_code" \
    "hr-when-a-command-exits-non-zero-or-prints"
  rm -rf "$tmp"
}

# --- #4600 false-positive cases: gh pr merge text inside a commit message ---
# These commits document the rule "do not hand-roll gh pr merge"; the hook must
# NOT mistake them for a merge. Each asserts the early-exit (no-intercept) path.

# T-FP1: multi-line `git commit -m` body whose body line STARTS with gh pr merge
# (triggers the `^` anchor of the merge-detection regex against the body text).
t_fp1_commit_body_newline() {
  local tmp; tmp=$(mktemp -d)
  local work="$tmp/work" incidents="$tmp/incidents"
  mkdir -p "$work" "$incidents"
  init_git_repo "$work"
  git -C "$work" commit -q --allow-empty -m "init"
  git -C "$work" checkout -q -b feat-fp1

  local payload out exit_code=0
  payload=$(make_payload "$work" 'git commit -m "do not hand-roll
gh pr merge directly"')
  out=$(printf '%s' "$payload" | INCIDENTS_REPO_ROOT="$incidents" "$HOOK" 2>/dev/null) || exit_code=$?
  exit_code=${exit_code:-0}
  assert_no_intercept "T-FP1 commit body newline-prefixed gh pr merge" "$incidents" "$out" "$exit_code"
  rm -rf "$tmp"
}

# T-FP2: body contains a chain-operator + gh pr merge inside the quoted message.
t_fp2_commit_body_chain_op() {
  local tmp; tmp=$(mktemp -d)
  local work="$tmp/work" incidents="$tmp/incidents"
  mkdir -p "$work" "$incidents"
  init_git_repo "$work"
  git -C "$work" commit -q --allow-empty -m "init"
  git -C "$work" checkout -q -b feat-fp2

  local payload out exit_code=0
  payload=$(make_payload "$work" 'git commit -m "docs: avoid && gh pr merge --auto in runbooks"')
  out=$(printf '%s' "$payload" | INCIDENTS_REPO_ROOT="$incidents" "$HOOK" 2>/dev/null) || exit_code=$?
  exit_code=${exit_code:-0}
  assert_no_intercept "T-FP2 commit body chain-op gh pr merge --auto" "$incidents" "$out" "$exit_code"
  rm -rf "$tmp"
}

# T-FP3: body contains a numbered `gh pr merge 4598` mid-line. NOTE: this case
# already passes against the PRE-FIX hook because the anchor regex requires a
# chain-op/anchor token (^, &&, ||, ;, " -- ") immediately before the verb, and
# a mid-line " ... gh pr merge 4598 ..." has only a space before it. It is kept
# as an ANCHORED-REGEX regression guard: if someone ever loosens the anchor
# group to match the verb anywhere, this case starts failing — and it documents
# why issue option (b) "require a PR-number arg" is insufficient as a sole fix
# (a numbered merge in a body would still match an anchor-free regex).
t_fp3_commit_body_numbered() {
  local tmp; tmp=$(mktemp -d)
  local work="$tmp/work" incidents="$tmp/incidents"
  mkdir -p "$work" "$incidents"
  init_git_repo "$work"
  git -C "$work" commit -q --allow-empty -m "init"
  git -C "$work" checkout -q -b feat-fp3

  local payload out exit_code=0
  payload=$(make_payload "$work" 'git commit -m "docs: never hand-roll gh pr merge 4598 directly"')
  out=$(printf '%s' "$payload" | INCIDENTS_REPO_ROOT="$incidents" "$HOOK" 2>/dev/null) || exit_code=$?
  exit_code=${exit_code:-0}
  assert_no_intercept "T-FP3 commit body numbered gh pr merge 4598" "$incidents" "$out" "$exit_code"
  rm -rf "$tmp"
}

# T-FP4: bare `git commit -F - <<EOF … EOF` heredoc body (NOT wrapped in quotes)
# whose body line starts with the verb. This is the shape the branch is named
# for; the quote-strip alone does not cover it (no surrounding quotes), so the
# heredoc-body strip in the SCAN derivation is what makes this no-intercept.
# True RED against the pre-fix hook (which intercepts via the ^-anchor).
t_fp4_commit_body_heredoc() {
  local tmp; tmp=$(mktemp -d)
  local work="$tmp/work" incidents="$tmp/incidents"
  mkdir -p "$work" "$incidents"
  init_git_repo "$work"
  git -C "$work" commit -q --allow-empty -m "init"
  git -C "$work" checkout -q -b feat-fp4

  local payload out exit_code=0
  payload=$(make_payload "$work" 'git commit -F - <<EOF
do not hand-roll
gh pr merge directly
EOF')
  out=$(printf '%s' "$payload" | INCIDENTS_REPO_ROOT="$incidents" "$HOOK" 2>/dev/null) || exit_code=$?
  exit_code=${exit_code:-0}
  assert_no_intercept "T-FP4 bare heredoc commit body" "$incidents" "$out" "$exit_code"
  rm -rf "$tmp"
}

# --- Anti-regression: real merges must STILL fire the review-evidence gate ---

# T5: bare `gh pr merge 123 --squash`, no review evidence ⇒ deny (same as T1 but
# kept as an explicit anti-regression anchor for the quote-strip change).
t5_bare_merge_fires() {
  local tmp; tmp=$(mktemp -d)
  local work="$tmp/work" incidents="$tmp/incidents"
  mkdir -p "$work" "$incidents"
  init_git_repo "$work"
  git -C "$work" commit -q --allow-empty -m "init"
  git -C "$work" checkout -q -b feat-t5
  git -C "$work" commit -q --allow-empty -m "feature work"

  local payload out exit_code=0
  payload=$(make_payload "$work" "gh pr merge 123 --squash")
  out=$(printf '%s' "$payload" | INCIDENTS_REPO_ROOT="$incidents" "$HOOK" 2>/dev/null) || exit_code=$?
  exit_code=${exit_code:-0}
  assert_deny "T5 bare merge fires" "$incidents" "$out" "$exit_code" \
    "rf-never-skip-qa-review-before-merging"
  # The deny reason is the only text an agent sees. It must name the split-command
  # remedy, because a chained `emit-review-trailer.sh && gh pr merge` is evaluated
  # (and denied) before the trailer commit exists (#8611).
  local reason
  reason=$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecisionReason // ""' 2>/dev/null || echo "")
  TOTAL=$((TOTAL + 1))
  if [[ "$reason" == *"as its own command, then git push, then re-issue gh pr merge"* ]]; then
    echo "PASS: T5b deny reason names the split trailer/push/merge remedy"; PASS=$((PASS + 1))
  else
    echo "FAIL: T5b deny reason lacks the split-command remedy: $reason"; FAIL=$((FAIL + 1))
  fi
  rm -rf "$tmp"
}

# T6: `git commit -m "wip" && gh pr merge 123 --squash` — a REAL chained merge
# after a commit. The quote-strip must blank only "wip" and leave the chained
# `&& gh pr merge` intact so the gate still fires. Guards the boundary the
# rejected leading-`git commit` skip heuristic would have broken.
t6_chained_after_commit_fires() {
  local tmp; tmp=$(mktemp -d)
  local work="$tmp/work" incidents="$tmp/incidents"
  mkdir -p "$work" "$incidents"
  init_git_repo "$work"
  git -C "$work" commit -q --allow-empty -m "init"
  git -C "$work" checkout -q -b feat-t6
  git -C "$work" commit -q --allow-empty -m "feature work"

  local payload out exit_code=0
  payload=$(make_payload "$work" 'git commit -m "wip" && gh pr merge 123 --squash')
  out=$(printf '%s' "$payload" | INCIDENTS_REPO_ROOT="$incidents" "$HOOK" 2>/dev/null) || exit_code=$?
  exit_code=${exit_code:-0}
  assert_deny "T6 chained-after-commit merge fires" "$incidents" "$out" "$exit_code" \
    "rf-never-skip-qa-review-before-merging"
  rm -rf "$tmp"
}

# T7: `with_lock`-wrapped form (`... -- gh pr merge 99 --squash`). The `\s--\s`
# alternative must still fire after the quote-strip.
t7_wrapped_merge_fires() {
  local tmp; tmp=$(mktemp -d)
  local work="$tmp/work" incidents="$tmp/incidents"
  mkdir -p "$work" "$incidents"
  init_git_repo "$work"
  git -C "$work" commit -q --allow-empty -m "init"
  git -C "$work" checkout -q -b feat-t7
  git -C "$work" commit -q --allow-empty -m "feature work"

  local payload out exit_code=0
  payload=$(make_payload "$work" "bash session-state.sh with_lock merge-main 600 -- gh pr merge 99 --squash")
  out=$(printf '%s' "$payload" | INCIDENTS_REPO_ROOT="$incidents" "$HOOK" 2>/dev/null) || exit_code=$?
  exit_code=${exit_code:-0}
  assert_deny "T7 with_lock-wrapped merge fires" "$incidents" "$out" "$exit_code" \
    "rf-never-skip-qa-review-before-merging"
  rm -rf "$tmp"
}

# T8: a REAL `gh pr merge` chained AFTER a heredoc terminator must still fire.
# Guards against the heredoc-body strip over-blanking past the closing
# delimiter (which would silently bypass the review-evidence gate).
t8_merge_after_heredoc_fires() {
  local tmp; tmp=$(mktemp -d)
  local work="$tmp/work" incidents="$tmp/incidents"
  mkdir -p "$work" "$incidents"
  init_git_repo "$work"
  git -C "$work" commit -q --allow-empty -m "init"
  git -C "$work" checkout -q -b feat-t8
  git -C "$work" commit -q --allow-empty -m "feature work"

  local payload out exit_code=0
  payload=$(make_payload "$work" 'git commit -F - <<EOF
release notes body
EOF
git push && gh pr merge 8 --squash')
  out=$(printf '%s' "$payload" | INCIDENTS_REPO_ROOT="$incidents" "$HOOK" 2>/dev/null) || exit_code=$?
  exit_code=${exit_code:-0}
  assert_deny "T8 merge after heredoc terminator fires" "$incidents" "$out" "$exit_code" \
    "rf-never-skip-qa-review-before-merging"
  rm -rf "$tmp"
}

# --- T-MJ1: malformed-JSON stdin fails open, but NO LONGER SILENTLY ---------
# Expectation REFRESHED for #7164 (ADR-157), not relaxed.
#
# Originally this asserted exit 0, no deny, AND no incident row. The first two
# clauses are the fail-open contract and still hold: a PreToolUse hook that
# blocks every command on a jq hiccup bricks the session, because the repair is
# itself a Bash call.
#
# The third clause was the bug. "No incident row" is exactly defect 2 of #7164:
# the hook disarmed every guard it owns and left no trace, so nothing downstream
# could ever know the gate had not run. The row is now REQUIRED. Asserting its
# absence would re-pin the silent disarm this PR exists to remove.
#
# This hook is not the designated `ask` responder (guardrails.sh is), so it still
# emits no JSON of its own — the operator-visible prompt comes from that hook on
# the same tool call.
t_mj1_malformed_json_failopen() {
  local tmp; tmp=$(mktemp -d)
  local incidents="$tmp/incidents"
  mkdir -p "$incidents"

  local out exit_code=0
  out=$(printf 'not json' | INCIDENTS_REPO_ROOT="$incidents" "$HOOK" 2>/dev/null) || exit_code=$?
  exit_code=${exit_code:-0}

  local jsonl="$incidents/.claude/.rule-incidents.jsonl"
  local ok=1 detail=""
  [[ "$exit_code" -ne 0 ]] && { ok=0; detail+=" exit=$exit_code(want 0)"; }
  [[ -n "$out" ]] && { ok=0; detail+=" stdout=$out(want empty)"; }
  if [[ ! -f "$jsonl" ]]; then
    ok=0; detail+=" no incident row (want one — a silent disarm is defect 2)"
  else
    local rid
    rid=$(jq -r 'select(.kind=="hook_self_fault") | .rule_id' < "$jsonl" 2>/dev/null | head -1)
    [[ "$rid" == hook-input-* ]] || { ok=0; detail+=" rule_id=${rid:-<none>}(want hook-input-*)"; }
  fi

  if [[ "$ok" -eq 1 ]]; then
    echo "PASS: T-MJ1 malformed JSON fails open AND records the disarm"
    PASS=$((PASS + 1))
  else
    echo "FAIL: T-MJ1 malformed JSON fails open AND records the disarm"
    echo " $detail"
    FAIL=$((FAIL + 1))
  fi
  TOTAL=$((TOTAL + 1))
  rm -rf "$tmp"
}

# --- T-V1: THE VACUITY REGRESSION (#6724) --------------------------------
#
# This is the case the old gate could not fail, and the reason the fix exists.
#
# `todos/` is a tracked directory on main. Before #6724, Check 1 was a
# repo-global `grep -rl "code-review" "$WORK_DIR/todos/"`, so ONE long-lived
# review todo anywhere in that directory satisfied the gate for EVERY branch,
# forever — including a branch on which review had never run. The gate was
# structurally incapable of denying anything while that file existed.
#
# Fixture: the review todo is seeded on MAIN, PRE-FORK (never on the feature
# branch). The branch itself does real work and runs no review. The tree
# therefore still contains a "code-review"-tagged file at merge time — the old
# grep's exact input — while the branch has introduced no evidence at all.
#
# MUST DENY. If this passes-through, Check 1 has regressed to repo-global.
t_v1_vacuity_todos_on_main_only() {
  local tmp; tmp=$(mktemp -d)
  local work="$tmp/work" incidents="$tmp/incidents"
  mkdir -p "$work" "$incidents"
  init_git_repo "$work"
  echo "base" > "$work/file.txt"
  git -C "$work" add file.txt
  git -C "$work" commit -q -m "init"
  # The long-lived review todo lands on main BEFORE the fork.
  seed_review_evidence_on_main "$work"
  attach_origin "$work" "$tmp/origin.git"

  # Feature branch: real work, no review of any kind.
  git -C "$work" checkout -q -b feat-unreviewed
  echo "feature" > "$work/feature.txt"
  git -C "$work" add feature.txt
  git -C "$work" commit -q -m "feat: unreviewed work"

  # Precondition (non-vacuity of the FIXTURE): the file the old grep would have
  # matched must actually be present in the tree. Without this, the test could
  # pass because there was nothing to find rather than because scoping works.
  if ! grep -rl "code-review" "$work/todos/" >/dev/null 2>&1; then
    echo "FAIL: T-V1 fixture invalid — no code-review todo in the tree, so the"
    echo "      old repo-global grep would have found nothing either."
    FAIL=$((FAIL + 1)); TOTAL=$((TOTAL + 1)); rm -rf "$tmp"; return
  fi

  local payload out exit_code=0
  payload=$(make_payload "$work" "gh pr merge 999 --squash")
  out=$(printf '%s' "$payload" | INCIDENTS_REPO_ROOT="$incidents" "$HOOK" 2>/dev/null) || exit_code=$?
  exit_code=${exit_code:-0}
  assert_deny "T-V1 vacuity: todos/ on main only must NOT count as branch evidence" \
    "$incidents" "$out" "$exit_code" "rf-never-skip-qa-review-before-merging"
  rm -rf "$tmp"
}

# --- T-V2: the zero-finding escape hatch (#6724 P0) ----------------------
#
# The mirror of T-V1. A review that finds nothing produces no todos and no
# `review:` commit — review/SKILL.md explicitly says to skip the artifact commit
# when there are no local changes. Before the trailer existed, the gate denied
# exactly those branches, with no way to proceed: the cleanest branches were the
# ones that could not merge.
#
# emit-review-trailer.sh commits `--allow-empty` with a `Reviewed-By-Soleur:`
# trailer. MUST ALLOW.
t_v2_zero_finding_trailer_allows() {
  local tmp; tmp=$(mktemp -d)
  local work="$tmp/work" incidents="$tmp/incidents"
  mkdir -p "$work" "$incidents"
  init_git_repo "$work"
  echo "base" > "$work/file.txt"
  git -C "$work" add file.txt
  git -C "$work" commit -q -m "init"
  attach_origin "$work" "$tmp/origin.git"

  git -C "$work" checkout -q -b feat-clean
  echo "feature" > "$work/feature.txt"
  git -C "$work" add feature.txt
  git -C "$work" commit -q -m "feat: work with nothing wrong with it"

  # An empty commit whose final paragraph is trailers only.
  #
  # The subject is deliberately NOT "review: ..." here. emit-review-trailer.sh
  # does use that subject in production (so the legacy Signal 2 pattern keeps
  # recognising it), but if this fixture used it too, the LEGACY message grep
  # would satisfy the gate and this test would pass with trailer support
  # entirely removed — proving nothing about the trailer.
  #
  # Verified by mutation: with the "review: " subject, deleting the trailer
  # lookup from the hook left this test GREEN. The neutral subject is what
  # makes the trailer the only signal that can allow this branch through.
  git -C "$work" commit -q --allow-empty -m "chore: post-review checkpoint

Machine-readable evidence that soleur:review ran on this branch.

Reviewed-By-Soleur: soleur:review"

  # Precondition: no todos/ anywhere, so Check 1 cannot be what allows this.
  if [[ -d "$work/todos" ]]; then
    echo "FAIL: T-V2 fixture invalid — todos/ exists, so the trailer is not the"
    echo "      signal under test."
    FAIL=$((FAIL + 1)); TOTAL=$((TOTAL + 1)); rm -rf "$tmp"; return
  fi

  local payload out exit_code=0
  payload=$(make_payload "$work" "gh pr merge 998 --squash")
  out=$(printf '%s' "$payload" | INCIDENTS_REPO_ROOT="$incidents" "$HOOK" 2>/dev/null) || exit_code=$?
  exit_code=${exit_code:-0}
  local decision
  decision=$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecision // ""' 2>/dev/null || echo "")
  if [[ "$decision" == "deny" ]]; then
    echo "FAIL: T-V2 zero-finding review with trailer was DENIED (the P0: clean branches deadlock)"
    FAIL=$((FAIL + 1))
  else
    echo "PASS: T-V2 zero-finding review with trailer is allowed past the gate"
    PASS=$((PASS + 1))
  fi
  TOTAL=$((TOTAL + 1))
  rm -rf "$tmp"
}

# --- T-V3: the REAL emit-review-trailer.sh satisfies the gate ------------
#
# T-V2 uses a hand-written fixture commit, which can drift from what the script
# actually emits — the classic "fixture drawn from what reads well rather than
# from the production artifact" failure. This runs the real script and asserts
# the gate accepts its output, so the two ends stay coupled.
#
# SCOPE, stated precisely because the distinction is easy to misread: this test
# does NOT isolate the trailer. The script's subject is "review: ...", which
# also matches the legacy Signal 2 message pattern, so this passes even with
# trailer support removed from the hook (verified by mutation). That redundancy
# is intentional in production — the script satisfies old and new gates alike —
# but it means the claim here is only "the real script's output is accepted,
# and it carries a parseable trailer" (both asserted below). T-V2 is what
# proves the trailer works on its own.
t_v3_real_script_satisfies_gate() {
  local script="$SCRIPT_DIR/../../plugins/soleur/skills/review/scripts/emit-review-trailer.sh"
  if [[ ! -f "$script" ]]; then
    echo "FAIL: T-V3 emit-review-trailer.sh not found at $script"
    FAIL=$((FAIL + 1)); TOTAL=$((TOTAL + 1)); return
  fi
  local tmp; tmp=$(mktemp -d)
  local work="$tmp/work" incidents="$tmp/incidents"
  mkdir -p "$work" "$incidents"
  init_git_repo "$work"
  echo "base" > "$work/file.txt"
  git -C "$work" add file.txt
  git -C "$work" commit -q -m "init"
  attach_origin "$work" "$tmp/origin.git"
  git -C "$work" checkout -q -b feat-real-script
  echo "feature" > "$work/feature.txt"
  git -C "$work" add feature.txt
  git -C "$work" commit -q -m "feat: work"

  # Run the real script, in the repo, as review would.
  ( cd "$work" && bash "$script" --findings 0 >/dev/null 2>&1 )

  # Precondition: the script must actually have emitted a parseable trailer.
  local trailer
  trailer=$(git -C "$work" log -1 --format='%(trailers:key=Reviewed-By-Soleur,valueonly)' | tr -d '[:space:]')
  if [[ -z "$trailer" ]]; then
    echo "FAIL: T-V3 emit-review-trailer.sh produced no parseable trailer"
    FAIL=$((FAIL + 1)); TOTAL=$((TOTAL + 1)); rm -rf "$tmp"; return
  fi

  local payload out exit_code=0
  payload=$(make_payload "$work" "gh pr merge 997 --squash")
  out=$(printf '%s' "$payload" | INCIDENTS_REPO_ROOT="$incidents" "$HOOK" 2>/dev/null) || exit_code=$?
  exit_code=${exit_code:-0}
  local decision
  decision=$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecision // ""' 2>/dev/null || echo "")
  if [[ "$decision" == "deny" ]]; then
    echo "FAIL: T-V3 real emit-review-trailer.sh output was DENIED by the gate"
    FAIL=$((FAIL + 1))
  else
    echo "PASS: T-V3 real emit-review-trailer.sh output satisfies the gate"
    PASS=$((PASS + 1))
  fi
  TOTAL=$((TOTAL + 1))
  rm -rf "$tmp"
}

# --- T-V1b / T-V1c: the SAME vacuity, for the other two signals -----------
#
# T-V1 seeds todos/ on main and covers Signal 1 only. Mutation-verified gap:
# stripping `origin/main..HEAD` from Signal 2 (legacy subject) and from the
# trailer lookup left the whole suite GREEN, because no fixture puts either of
# those on main pre-fork. One historical `review:` commit or one trailer commit
# anywhere in main's history would then satisfy the gate for EVERY future
# branch forever — the exact regression this PR exists to close, unguarded on
# two of three signals.
#
# This matters more after this PR, not less: emit-review-trailer.sh guarantees
# main's history becomes dense with both shapes.
_vacuity_signal_case() { # <slug> <assert-name> <commit-subject> <extra-commit-body>
  local slug="$1" case_name="$2" subject="$3" body="${4:-}"
  local tmp; tmp=$(mktemp -d)
  local work="$tmp/work" incidents="$tmp/incidents"
  mkdir -p "$work" "$incidents"
  init_git_repo "$work"
  echo "base" > "$work/file.txt"
  git -C "$work" add file.txt
  git -C "$work" commit -q -m "init"
  # The evidence lands on MAIN, pre-fork — never on the feature branch.
  if [[ -n "$body" ]]; then
    git -C "$work" commit -q --allow-empty -m "$subject

$body"
  else
    git -C "$work" commit -q --allow-empty -m "$subject"
  fi
  attach_origin "$work" "$tmp/origin.git"

  git -C "$work" checkout -q -b "feat-unreviewed-${slug}"
  echo "feature" > "$work/feature.txt"
  git -C "$work" add feature.txt
  git -C "$work" commit -q -m "feat: unreviewed work"

  # Precondition: the evidence must really be in main's history, or this test
  # passes because there was nothing to find rather than because scoping works.
  # Herestring, not a pipe: `git log | grep -q` under `set -o pipefail` makes
  # git take SIGPIPE when grep closes on the first match, pipefail propagates
  # the 141, and `!` inverts it into a bogus "fixture invalid". Nondeterministic
  # — it depends on whether git flushed before grep exited. Same class this PR
  # documents in the runbook.
  if ! grep -qF "${subject:0:20}" <<<"$(git -C "$work" log origin/main --oneline)"; then
    echo "FAIL: $case_name fixture invalid — evidence not present on main"
    FAIL=$((FAIL + 1)); TOTAL=$((TOTAL + 1)); rm -rf "$tmp"; return
  fi

  local payload out exit_code=0
  payload=$(make_payload "$work" "gh pr merge 996 --squash")
  out=$(printf '%s' "$payload" | INCIDENTS_REPO_ROOT="$incidents" "$HOOK" 2>/dev/null) || exit_code=$?
  exit_code=${exit_code:-0}
  assert_deny "$case_name" "$incidents" "$out" "$exit_code" \
    "rf-never-skip-qa-review-before-merging"
  rm -rf "$tmp"
}

t_v1b_vacuity_review_subject_on_main() {
  _vacuity_signal_case "subject" \
    "T-V1b vacuity: a review: subject on MAIN is not this branch's evidence" \
    "review: findings from some older branch (P2)"
}

t_v1c_vacuity_trailer_on_main() {
  _vacuity_signal_case "trailer" \
    "T-V1c vacuity: a Reviewed-By-Soleur trailer on MAIN is not this branch's evidence" \
    "chore: older branch checkpoint" \
    "Reviewed-By-Soleur: soleur:review"
}

# =============================================================================
# PR-head evidence range (#8778).
#
# The PreToolUse envelope's `.cwd` is the SESSION anchor, not where an in-command
# `cd` lands. A subagent anchored at the repo root (detached HEAD) that runs
# `cd <worktree> && gh pr merge N` used to have the gate scan the ROOT's HEAD, so a
# reviewed PR was denied — and a session in reviewed worktree A merging unreviewed
# PR B was allowed. The hook now resolves PR N's head via `gh pr view`; these cases
# drive it through a `gh` binstub that replays real gh's contract.
#
# Layout mirrors production: a bare origin, a root checkout left in DETACHED HEAD at
# main, and `git worktree add` worktrees sharing the root's object store.
# =============================================================================

# install_gh_stub <stubdir> [ok|fail]
# Per-PR answers live in <stubdir>/pr-<N>.json (written by _prf_pr), never
# interpolated into the stub source. Every call is appended to gh.log.
install_gh_stub() {
  local d="$1" mode="${2:-ok}"
  assert_fixture_dir "$d"
  mkdir -p "$d"
  printf '%s\n' "$mode" > "$d/mode"
  cat > "$d/gh" <<'STUB'
#!/usr/bin/env bash
d="$(cd "$(dirname "$0")" && pwd)"
printf '%s\n' "$*" >> "$d/gh.log"
mode="$(cat "$d/mode" 2>/dev/null || echo ok)"
case "${1:-} ${2:-}" in
  "pr view")
    n="${3:-}"; json=""
    shift 3 || true
    while [[ $# -gt 0 ]]; do
      case "$1" in --json) json="${2:-}"; shift 2 || shift ;; *) shift ;; esac
    done
    for f in headRefName headRefOid isCrossRepository state; do
      case ",$json," in *",$f,"*) ;; *) echo "STUB-MISS pr view without --json $f" >&2; exit 64 ;; esac
    done
    if [[ "$mode" == "fail" ]]; then echo "HTTP 502" >&2; exit 1; fi
    if [[ "$n" =~ ^[0-9]+$ && -f "$d/pr-$n.json" ]]; then cat "$d/pr-$n.json"; exit 0; fi
    echo "GraphQL: Could not resolve to a PullRequest with the number of $n. (repository.pullRequest)" >&2
    exit 1 ;;
  "issue list")
    # Signal 3: answer only for the exact "PR #<N>" phrase the hook must send,
    # from issue-<N> when present (the hook asks gh for `.[0].number // empty`).
    q=""; prev=""
    for a in "$@"; do [[ "$prev" == "--search" ]] && q="$a"; prev="$a"; done
    if [[ "$q" =~ ^\"PR\ \#([0-9]+)\"$ && -f "$d/issue-${BASH_REMATCH[1]}" ]]; then
      cat "$d/issue-${BASH_REMATCH[1]}"
    fi
    exit 0 ;;
  "pr list")
    h=""; prev=""
    for a in "$@"; do [[ "$prev" == "--head" ]] && h="$a"; prev="$a"; done
    [[ -n "$h" && -f "$d/head-$h" ]] && cat "$d/head-$h"
    exit 0 ;;
  *) echo "STUB-MISS $*" >&2; exit 64 ;;
esac
STUB
  chmod +x "$d/gh"
}

# _prf_setup <tmp> — origin + detached root + stub + incidents dir under <tmp>.
_prf_setup() {
  local tmp="$1"
  assert_fixture_dir "$tmp"
  mkdir -p "$tmp/root" "$tmp/incidents"
  init_git_repo "$tmp/root"
  echo "base" > "$tmp/root/file.txt"
  git -C "$tmp/root" add file.txt
  git -C "$tmp/root" commit -q -m "init"
  attach_origin "$tmp/root" "$tmp/origin.git"
  git -C "$tmp/root" checkout -q --detach
  install_gh_stub "$tmp/stub"
}

# _prf_wt <tmp> <branch> — a worktree of the root on a new branch off main.
_prf_wt() {
  local tmp="$1" br="$2"
  assert_fixture_dir "$tmp"
  git -C "$tmp/root" worktree add -q -b "$br" "$tmp/wt-$br" main
}

# _prf_commit <dir> <subject> [trailer] — an empty commit, optionally trailered.
_prf_commit() {
  local dir="$1" subject="$2" trailer="${3:-}"
  assert_fixture_dir "$dir"
  if [[ -n "$trailer" ]]; then
    git -C "$dir" commit -q --allow-empty -m "$subject" -m "$trailer"
  else
    git -C "$dir" commit -q --allow-empty -m "$subject"
  fi
}

# _prf_pr <tmp> <n> <headRefName> <headRefOid> [xrepo=false] [state=OPEN]
# — the stub's answer for PR n.
_prf_pr() {
  local tmp="$1" n="$2" ref="$3" oid="$4" xrepo="${5:-false}" state="${6:-OPEN}"
  assert_fixture_dir "$tmp"
  jq -nc --arg r "$ref" --arg o "$oid" --argjson x "$xrepo" --arg st "$state" \
    '{headRefName: $r, headRefOid: $o, isCrossRepository: $x, state: $st}' > "$tmp/stub/pr-$n.json"
}

# _prf_advance_main <tmp> — move origin/main past every branch's merge-base, so a
# "no sync happened" assertion is not satisfied by the "already up-to-date" exit.
_prf_advance_main() {
  local tmp="$1"
  assert_fixture_dir "$tmp"
  git -C "$tmp/root" worktree add -q --detach "$tmp/adv" main
  echo "main moved" > "$tmp/adv/main-only.txt"
  git -C "$tmp/adv" add main-only.txt
  git -C "$tmp/adv" commit -q -m "main: advance"
  git -C "$tmp/adv" push -q origin HEAD:main
  git -C "$tmp/root" worktree remove --force "$tmp/adv"
}

# _prf_run <tmp> <session-cwd> <command> — sets PRF_OUT / PRF_RC / PRF_REASON.
_prf_run() {
  local tmp="$1" cwd="$2" cmd="$3"
  local payload
  payload=$(make_payload "$cwd" "$cmd")
  PRF_RC=0
  PRF_OUT=$(printf '%s' "$payload" | PATH="$tmp/stub:$PATH" INCIDENTS_REPO_ROOT="$tmp/incidents" "$HOOK" 2>/dev/null) || PRF_RC=$?
  PRF_REASON=$(jq -r '.hookSpecificOutput.permissionDecisionReason // ""' <<<"${PRF_OUT:-}" 2>/dev/null || true)
}

_prf_decision() { jq -r '.hookSpecificOutput.permissionDecision // ""' <<<"${PRF_OUT:-}" 2>/dev/null || true; }
_prf_context()  { jq -r '.hookSpecificOutput.additionalContext // ""' <<<"${PRF_OUT:-}" 2>/dev/null || true; }

# _verdict <name> <1|0> <detail-on-fail>
_verdict() {
  TOTAL=$((TOTAL + 1))
  if [[ "$2" == "1" ]]; then echo "PASS: $1"; PASS=$((PASS + 1))
  else echo "FAIL: $1 — $3"; FAIL=$((FAIL + 1)); fi
}

# _assert_allowed <name> — exit 0 and no deny decision.
_assert_allowed() {
  local ok=1
  [[ "$PRF_RC" -eq 0 ]] || ok=0
  [[ "$(_prf_decision)" != "deny" ]] || ok=0
  _verdict "$1" "$ok" "rc=$PRF_RC decision=$(_prf_decision) reason=${PRF_REASON:0:300}"
}

_gh_logged() { grep -qxF -- "$2" "$1/stub/gh.log" 2>/dev/null; }
_gh_logged_any() { grep -qF -- "$2" "$1/stub/gh.log" 2>/dev/null; }

PR_VIEW_ARGV_4242="pr view 4242 --json headRefName,headRefOid,isCrossRepository,state"

# --- T-PR1 / 1b / 1c: root session, PR head carries the evidence -------------
# One helper, three evidence shapes, so each of the four evidence reads is driven
# by a case only the PR-head range can satisfy.
_t_pr1_case() { # <label> <kind: trailer|subject|todo>
  local label="$1" kind="$2"
  local tmp; tmp=$(mktemp -d)
  trap 'rm -rf "$tmp"; trap - RETURN' RETURN
  _prf_setup "$tmp"
  _prf_wt "$tmp" feat-x
  local wt="$tmp/wt-feat-x"
  case "$kind" in
    trailer) _prf_commit "$wt" "chore: checkpoint" "Reviewed-By-Soleur: soleur:review" ;;
    subject) _prf_commit "$wt" "review(8778): findings (P2)" ;;
    todo)
      mkdir -p "$wt/todos"; echo "code-review" > "$wt/todos/x.md"
      git -C "$wt" add todos/x.md; git -C "$wt" commit -q -m "chore: notes" ;;
  esac
  git -C "$wt" push -q origin feat-x
  _prf_pr "$tmp" 4242 feat-x "$(git -C "$wt" rev-parse HEAD)"
  # Precondition: the root's own legacy range is EMPTY, so a legacy pass is impossible.
  if [[ -n "$(git -C "$tmp/root" log --oneline origin/main..HEAD)" || -e "$tmp/root/todos" ]]; then
    _verdict "$label" 0 "precondition: root legacy range must be empty and carry no todos/"; return
  fi
  _prf_run "$tmp" "$tmp/root" "cd $wt && gh pr merge 4242 --squash"
  _assert_allowed "$label"
  local ok=1; _gh_logged "$tmp" "$PR_VIEW_ARGV_4242" || ok=0
  _verdict "$label: gh.log has the exact pr view argv" "$ok" "$(cat "$tmp/stub/gh.log" 2>/dev/null)"
  ok=1; [[ "$(_prf_context)" == *"is not PR #4242's checkout"* ]] || ok=0
  _verdict "$label: the root session is told the sync was skipped" "$ok" "context=$(_prf_context)"
}
t_pr1_root_session_trailer() { _t_pr1_case "T-PR1 root session, PR head trailer → allowed" trailer; }
t_pr1b_root_session_subject() { _t_pr1_case "T-PR1b root session, PR head review subject → allowed" subject; }
t_pr1c_root_session_todo() { _t_pr1_case "T-PR1c root session, PR head code-review todo → allowed" todo; }

# --- T-PR-C: control — same layout, no evidence, and the resolver RAN ----------
t_pr_c_control_denies() {
  local tmp; tmp=$(mktemp -d)
  trap 'rm -rf "$tmp"; trap - RETURN' RETURN
  _prf_setup "$tmp"
  _prf_wt "$tmp" feat-x
  _prf_commit "$tmp/wt-feat-x" "chore: unreviewed work"
  _prf_pr "$tmp" 4242 feat-x "$(git -C "$tmp/wt-feat-x" rev-parse HEAD)"
  _prf_run "$tmp" "$tmp/root" "cd $tmp/wt-feat-x && gh pr merge 4242 --squash"
  assert_deny "T-PR-C control: unreviewed PR head denied" "$tmp/incidents" "$PRF_OUT" "$PRF_RC" \
    "rf-never-skip-qa-review-before-merging"
  local ok=1
  [[ "$PRF_REASON" == *"PR #4242 head per GitHub"* ]] || ok=0
  _gh_logged "$tmp" "$PR_VIEW_ARGV_4242" || ok=0
  _verdict "T-PR-C control: the deny came from the PR-head range" "$ok" "reason=${PRF_REASON:0:300}"
}

# --- T-PR2: the head is only reachable via refs/pull/<N>/head ------------------
t_pr2_fetch_pull_ref() {
  local tmp; tmp=$(mktemp -d)
  trap 'rm -rf "$tmp"; trap - RETURN' RETURN
  _prf_setup "$tmp"
  _prf_wt "$tmp" feat-x
  _prf_commit "$tmp/wt-feat-x" "chore: checkpoint" "Reviewed-By-Soleur: soleur:review"
  local oid; oid=$(git -C "$tmp/wt-feat-x" rev-parse HEAD)
  # Published ONLY as a pull ref, as a fork PR would be — never as refs/heads/feat-x.
  git -C "$tmp/wt-feat-x" push -q origin "HEAD:refs/pull/4242/head"
  _prf_pr "$tmp" 4242 feat-x "$oid"
  # --no-local: a local-path clone hardlinks the whole object store and would already hold $oid.
  git clone -q --no-local --single-branch --branch main "$tmp/origin.git" "$tmp/clone"
  git -C "$tmp/clone" checkout -q --detach
  if git -C "$tmp/clone" cat-file -e "${oid}^{commit}" 2>/dev/null; then
    _verdict "T-PR2 pull-ref fetch" 0 "precondition: the clone must not hold the PR head yet"; return
  fi
  _prf_run "$tmp" "$tmp/clone" "gh pr merge 4242 --squash"
  _assert_allowed "T-PR2 head fetched from refs/pull/4242/head → allowed"
}

# --- T-PR3: reviewed cwd branch must not vouch for an unreviewed PR ------------
t_pr3_reviewed_cwd_unreviewed_pr() {
  local tmp; tmp=$(mktemp -d)
  trap 'rm -rf "$tmp"; trap - RETURN' RETURN
  _prf_setup "$tmp"
  _prf_wt "$tmp" feat-a; _prf_wt "$tmp" feat-b
  _prf_commit "$tmp/wt-feat-a" "chore: a" "Reviewed-By-Soleur: soleur:review"
  _prf_commit "$tmp/wt-feat-b" "chore: b unreviewed"
  _prf_pr "$tmp" 4243 feat-b "$(git -C "$tmp/wt-feat-b" rev-parse HEAD)"
  _prf_run "$tmp" "$tmp/wt-feat-a" "cd $tmp/wt-feat-b && gh pr merge 4243 --squash"
  assert_deny "T-PR3 reviewed cwd feat-a, unreviewed PR feat-b → denied" "$tmp/incidents" \
    "$PRF_OUT" "$PRF_RC" "rf-never-skip-qa-review-before-merging"
}

# --- T-PR4: never sync or dirty-check a checkout that is not the PR's ---------
t_pr4_no_sync_on_other_branch() {
  local tmp; tmp=$(mktemp -d)
  trap 'rm -rf "$tmp"; trap - RETURN' RETURN
  _prf_setup "$tmp"
  _prf_wt "$tmp" feat-a; _prf_wt "$tmp" feat-b
  _prf_commit "$tmp/wt-feat-a" "chore: a"
  git -C "$tmp/wt-feat-a" push -q origin feat-a
  _prf_commit "$tmp/wt-feat-b" "chore: b" "Reviewed-By-Soleur: soleur:review"
  _prf_pr "$tmp" 4244 feat-b "$(git -C "$tmp/wt-feat-b" rev-parse HEAD)"
  _prf_advance_main "$tmp"
  echo "dirty" > "$tmp/wt-feat-a/file.txt"
  local a_head a_remote; a_head=$(git -C "$tmp/wt-feat-a" rev-parse HEAD)
  a_remote=$(git -C "$tmp/origin.git" rev-parse refs/heads/feat-a)
  _prf_run "$tmp" "$tmp/wt-feat-a" "cd $tmp/wt-feat-b && gh pr merge 4244 --squash"
  _assert_allowed "T-PR4 dirty unrelated cwd branch is not denied"
  local ok=1
  [[ "$(git -C "$tmp/wt-feat-a" rev-parse HEAD)" == "$a_head" ]] || ok=0
  [[ "$(git -C "$tmp/origin.git" rev-parse refs/heads/feat-a)" == "$a_remote" ]] || ok=0
  [[ "$(_prf_context)" == *"skipped the uncommitted-changes check and the origin/main auto-sync"* ]] || ok=0
  _verdict "T-PR4 feat-a untouched and the skip is reported" "$ok" "context=$(_prf_context)"
}

# --- T-PR5 / 5b: the PR's own checkout keeps today's range and sync ------------
_t_pr5_case() { # <label> <unpushed: 0|1>
  local label="$1" unpushed="$2"
  local tmp; tmp=$(mktemp -d)
  trap 'rm -rf "$tmp"; trap - RETURN' RETURN
  _prf_setup "$tmp"
  _prf_wt "$tmp" feat-x
  local wt="$tmp/wt-feat-x"
  if [[ "$unpushed" == "1" ]]; then
    _prf_commit "$wt" "chore: work"
    git -C "$wt" push -q origin feat-x
    _prf_pr "$tmp" 4242 feat-x "$(git -C "$wt" rev-parse HEAD)"
    # The trailer commit is LOCAL ONLY: HEAD is one commit ahead of the PR head.
    _prf_commit "$wt" "chore: review done" "Reviewed-By-Soleur: soleur:review"
  else
    _prf_commit "$wt" "chore: work" "Reviewed-By-Soleur: soleur:review"
    git -C "$wt" push -q origin feat-x
    _prf_pr "$tmp" 4242 feat-x "$(git -C "$wt" rev-parse HEAD)"
  fi
  local head; head=$(git -C "$wt" rev-parse HEAD)
  _prf_advance_main "$tmp"
  _prf_run "$tmp" "$wt" "gh pr merge 4242 --squash"
  _assert_allowed "$label"
  local ok=1
  [[ "$(_prf_context)" == *"merged origin/main into feat-x and pushed"* ]] || ok=0
  git -C "$tmp/origin.git" merge-base --is-ancestor "$head" refs/heads/feat-x 2>/dev/null || ok=0
  _verdict "$label: synced and pushed" "$ok" "context=$(_prf_context)"
}
t_pr5_own_checkout_syncs() { _t_pr5_case "T-PR5 own checkout at PR head → allowed" 0; }
t_pr5b_own_checkout_unpushed_trailer() { _t_pr5_case "T-PR5b own checkout, unpushed trailer commit → allowed" 1; }

# --- T-PR6: a non-hex headRefOid never becomes a revision ---------------------
t_pr6_non_hex_oid() {
  local tmp; tmp=$(mktemp -d)
  trap 'rm -rf "$tmp"; trap - RETURN' RETURN
  _prf_setup "$tmp"
  _prf_wt "$tmp" feat-a
  _prf_commit "$tmp/wt-feat-a" "chore: a" "Reviewed-By-Soleur: soleur:review"
  _prf_pr "$tmp" 4242 feat-x "feat-a"
  _prf_run "$tmp" "$tmp/root" "gh pr merge 4242 --squash"
  assert_deny "T-PR6 non-hex headRefOid → legacy range → denied" "$tmp/incidents" \
    "$PRF_OUT" "$PRF_RC" "rf-never-skip-qa-review-before-merging"
  local ok=1; [[ "$PRF_REASON" == *"not resolved"* ]] || ok=0
  _verdict "T-PR6 reason says the head was not resolved" "$ok" "reason=${PRF_REASON:0:300}"
}

# --- T-PR7: gh failing keeps today's behaviour (legacy range), not fail-closed --
t_pr7_gh_fails_legacy() {
  local tmp; tmp=$(mktemp -d)
  trap 'rm -rf "$tmp"; trap - RETURN' RETURN
  _prf_setup "$tmp"
  install_gh_stub "$tmp/stub" fail
  _prf_wt "$tmp" feat-a; _prf_wt "$tmp" feat-b
  _prf_commit "$tmp/wt-feat-a" "chore: a" "Reviewed-By-Soleur: soleur:review"
  _prf_commit "$tmp/wt-feat-b" "chore: b unreviewed"
  # Were the stub to answer, PR 4242 is the unreviewed feat-b and this would deny;
  # only the gh failure keeps the legacy (reviewed cwd) verdict.
  _prf_pr "$tmp" 4242 feat-b "$(git -C "$tmp/wt-feat-b" rev-parse HEAD)"
  _prf_run "$tmp" "$tmp/wt-feat-a" "gh pr merge 4242 --squash"
  _assert_allowed "T-PR7 gh fails, reviewed cwd branch → allowed (legacy)"
  local ok=1; _gh_logged "$tmp" "$PR_VIEW_ARGV_4242" || ok=0
  _verdict "T-PR7 the resolver did try gh" "$ok" "$(cat "$tmp/stub/gh.log" 2>/dev/null)"
}

# --- T-PR8: on the PR's branch name but NOT descending from its head -----------
t_pr8_same_name_diverged() {
  local tmp; tmp=$(mktemp -d)
  trap 'rm -rf "$tmp"; trap - RETURN' RETURN
  _prf_setup "$tmp"
  _prf_wt "$tmp" feat-x
  local wt="$tmp/wt-feat-x"
  _prf_commit "$wt" "chore: reviewed" "Reviewed-By-Soleur: soleur:review"
  git -C "$wt" push -q origin feat-x
  local oid; oid=$(git -C "$wt" rev-parse HEAD)
  _prf_pr "$tmp" 4242 feat-x "$oid"
  git -C "$wt" reset -q --hard main
  _prf_commit "$wt" "chore: local only, unreviewed"
  _prf_advance_main "$tmp"
  _prf_run "$tmp" "$wt" "gh pr merge 4242 --squash"
  _assert_allowed "T-PR8 same name, diverged checkout → verdict from the PR head"
  local ok=1
  [[ "$(git -C "$tmp/origin.git" rev-parse refs/heads/feat-x)" == "$oid" ]] || ok=0
  [[ "$(_prf_context)" == *"skipped the uncommitted-changes check"* ]] || ok=0
  _verdict "T-PR8 origin/feat-x unchanged and the skip is reported" "$ok" "context=$(_prf_context)"
}

# --- T-PR9: two distinct PR numbers → legacy, nothing resolved -----------------
t_pr9_two_prs_legacy() {
  local tmp; tmp=$(mktemp -d)
  trap 'rm -rf "$tmp"; trap - RETURN' RETURN
  _prf_setup "$tmp"
  _prf_wt "$tmp" feat-a; _prf_wt "$tmp" feat-b
  _prf_commit "$tmp/wt-feat-a" "chore: a" "Reviewed-By-Soleur: soleur:review"
  _prf_commit "$tmp/wt-feat-b" "chore: b"
  _prf_pr "$tmp" 4242 feat-a "$(git -C "$tmp/wt-feat-a" rev-parse HEAD)"
  _prf_pr "$tmp" 4243 feat-b "$(git -C "$tmp/wt-feat-b" rev-parse HEAD)"
  _prf_run "$tmp" "$tmp/root" "gh pr merge 4242 --squash && gh pr merge 4243 --squash"
  assert_deny "T-PR9 two distinct PR numbers from root → denied" "$tmp/incidents" \
    "$PRF_OUT" "$PRF_RC" "rf-never-skip-qa-review-before-merging"
  local ok=1; _gh_logged_any "$tmp" "pr view" && ok=0
  _verdict "T-PR9 no PR head was resolved" "$ok" "$(cat "$tmp/stub/gh.log" 2>/dev/null)"
}

# --- T-PR10: a PR number inside a quoted body never chooses the PR -------------
t_pr10_quoted_number_ignored() {
  local tmp; tmp=$(mktemp -d)
  trap 'rm -rf "$tmp"; trap - RETURN' RETURN
  _prf_setup "$tmp"
  _prf_wt "$tmp" feat-a; _prf_wt "$tmp" feat-b
  _prf_commit "$tmp/wt-feat-a" "chore: a" "Reviewed-By-Soleur: soleur:review"
  _prf_commit "$tmp/wt-feat-b" "chore: b"
  _prf_pr "$tmp" 4242 feat-a "$(git -C "$tmp/wt-feat-a" rev-parse HEAD)"
  _prf_pr "$tmp" 4243 feat-b "$(git -C "$tmp/wt-feat-b" rev-parse HEAD)"
  _prf_run "$tmp" "$tmp/root" 'git commit --allow-empty -m "see gh pr merge 4242" && gh pr merge 4243 --squash'
  assert_deny "T-PR10 quoted 4242, real 4243 unreviewed → denied" "$tmp/incidents" \
    "$PRF_OUT" "$PRF_RC" "rf-never-skip-qa-review-before-merging"
  local ok=1
  _gh_logged_any "$tmp" "pr view 4243" || ok=0
  _gh_logged_any "$tmp" "pr view 4242" && ok=0
  _verdict "T-PR10 resolved 4243 only" "$ok" "$(cat "$tmp/stub/gh.log" 2>/dev/null)"
}

# --- T-PR11: unfetchable PR head → Signal 3 only, never the cwd's evidence -----
t_pr11_unfetchable_head() {
  local tmp; tmp=$(mktemp -d)
  trap 'rm -rf "$tmp"; trap - RETURN' RETURN
  _prf_setup "$tmp"
  _prf_wt "$tmp" feat-a
  _prf_commit "$tmp/wt-feat-a" "chore: a" "Reviewed-By-Soleur: soleur:review"
  local ghost="0123456789abcdef0123456789abcdef01234567"
  if git -C "$tmp/root" cat-file -e "${ghost}^{commit}" 2>/dev/null; then
    _verdict "T-PR11 unfetchable head" 0 "precondition: the synthetic oid must not exist"; return
  fi
  _prf_pr "$tmp" 4245 feat-b "$ghost"
  _prf_run "$tmp" "$tmp/wt-feat-a" "gh pr merge 4245 --squash"
  assert_deny "T-PR11 unfetchable PR head from reviewed cwd → denied" "$tmp/incidents" \
    "$PRF_OUT" "$PRF_RC" "rf-never-skip-qa-review-before-merging"
  local ok=1; [[ "$PRF_REASON" == *"not fetchable"* ]] || ok=0
  _verdict "T-PR11 reason names the unfetchable head" "$ok" "reason=${PRF_REASON:0:300}"
}

# --- T-PR12: anything pointing gh at another repository → legacy, not resolved --
t_pr12_repo_override_legacy() {
  local tmp; tmp=$(mktemp -d)
  trap 'rm -rf "$tmp"; trap - RETURN' RETURN
  _prf_setup "$tmp"
  _prf_wt "$tmp" feat-a; _prf_wt "$tmp" feat-b
  _prf_commit "$tmp/wt-feat-a" "chore: a" "Reviewed-By-Soleur: soleur:review"
  _prf_commit "$tmp/wt-feat-b" "chore: b"
  # If the resolver wrongly ran, it would read THIS repo's PR 4242 (unreviewed feat-b).
  _prf_pr "$tmp" 4242 feat-b "$(git -C "$tmp/wt-feat-b" rev-parse HEAD)"
  local cmd
  for cmd in "gh pr merge 4242 -R other/repo --squash" "gh pr merge 4242 --repo other/repo" \
             "gh pr merge 4242 --repo=other/repo" "gh pr merge 4242 -Rother/repo" \
             "gh pr merge 4242 -sdR other/repo" "export GH_REPO=other/repo; gh pr merge 4242 --squash"; do
    : > "$tmp/stub/gh.log"
    _prf_run "$tmp" "$tmp/wt-feat-a" "$cmd"
    _assert_allowed "T-PR12 [$cmd] from reviewed cwd → legacy allow"
    local ok=1; _gh_logged_any "$tmp" "pr view" && ok=0
    [[ "$PRF_OUT" != *"deny"* ]] || ok=0
    _verdict "T-PR12 [$cmd] no PR head was resolved" "$ok" "$(cat "$tmp/stub/gh.log" 2>/dev/null)"
  done
  # Control: a -R elsewhere in the command is not the merge's own flag.
  : > "$tmp/stub/gh.log"
  _prf_run "$tmp" "$tmp/wt-feat-a" "grep -R x . ; gh pr merge 4242 --squash"
  local ok=1; _gh_logged "$tmp" "$PR_VIEW_ARGV_4242" || ok=0
  [[ "$(_prf_decision)" == "deny" ]] || ok=0
  _verdict "T-PR12 control: -R outside the merge still resolves PR 4242 (and denies it)" "$ok" "rc=$PRF_RC reason=${PRF_REASON:0:200}"
}

# --- T-PR13: #7409's repeated number (locked/unlocked arms) resolves ONCE --------
t_pr13_repeated_number() {
  local tmp; tmp=$(mktemp -d)
  trap 'rm -rf "$tmp"; trap - RETURN' RETURN
  _prf_setup "$tmp"
  _prf_wt "$tmp" feat-x
  _prf_commit "$tmp/wt-feat-x" "chore: checkpoint" "Reviewed-By-Soleur: soleur:review"
  _prf_pr "$tmp" 4242 feat-x "$(git -C "$tmp/wt-feat-x" rev-parse HEAD)"
  _prf_run "$tmp" "$tmp/root" "gh pr merge 4242 --squash --auto || gh pr merge 4242 --squash"
  _assert_allowed "T-PR13 repeated PR number from root → allowed"
  local n; n=$(grep -cxF -- "$PR_VIEW_ARGV_4242" "$tmp/stub/gh.log" 2>/dev/null || true)
  _verdict "T-PR13 exactly one pr view call" "$([[ "$n" == "1" ]] && echo 1 || echo 0)" "count=$n"
}

# --- T-PR14: a branch STACKED on the PR is not the PR's own checkout -------------
t_pr14_stacked_branch() {
  local tmp; tmp=$(mktemp -d)
  trap 'rm -rf "$tmp"; trap - RETURN' RETURN
  _prf_setup "$tmp"
  _prf_wt "$tmp" feat-x
  _prf_commit "$tmp/wt-feat-x" "chore: unreviewed PR work"
  git -C "$tmp/wt-feat-x" push -q origin feat-x
  _prf_pr "$tmp" 4242 feat-x "$(git -C "$tmp/wt-feat-x" rev-parse HEAD)"
  git -C "$tmp/root" worktree add -q -b feat-y "$tmp/wt-feat-y" feat-x
  _prf_commit "$tmp/wt-feat-y" "chore: y" "Reviewed-By-Soleur: soleur:review"
  _prf_advance_main "$tmp"
  _prf_run "$tmp" "$tmp/wt-feat-y" "gh pr merge 4242 --squash"
  assert_deny "T-PR14 stacked feat-y's trailer does not vouch for PR 4242" "$tmp/incidents" \
    "$PRF_OUT" "$PRF_RC" "rf-never-skip-qa-review-before-merging"
  local ok=1
  git -C "$tmp/origin.git" rev-parse -q --verify refs/heads/feat-y >/dev/null && ok=0
  _verdict "T-PR14 feat-y was not pushed" "$ok" "origin/feat-y exists"
}

# --- T-PR15: state N still allows on Signal 3 (a code-review issue) -------------
t_pr15_signal3_allows_in_state_n() {
  local tmp; tmp=$(mktemp -d)
  trap 'rm -rf "$tmp"; trap - RETURN' RETURN
  _prf_setup "$tmp"
  _prf_pr "$tmp" 4245 feat-b "0123456789abcdef0123456789abcdef01234567"
  printf '901\n' > "$tmp/stub/issue-4245"
  _prf_run "$tmp" "$tmp/root" "gh pr merge 4245 --squash"
  _assert_allowed "T-PR15 unfetchable head + code-review issue → allowed"
  local ok=1; _gh_logged_any "$tmp" '--search "PR #4245"' || ok=0
  _verdict "T-PR15 Signal 3 searched the resolved PR number" "$ok" "$(cat "$tmp/stub/gh.log" 2>/dev/null)"
}

# --- T-PR16: several distinct numbers → Signal 3 is not guessed -----------------
t_pr16_multi_number_skips_signal3() {
  local tmp; tmp=$(mktemp -d)
  trap 'rm -rf "$tmp"; trap - RETURN' RETURN
  _prf_setup "$tmp"
  printf '901\n' > "$tmp/stub/issue-4242"
  _prf_run "$tmp" "$tmp/root" "gh pr merge 4242 --squash && gh pr merge 4243 --squash"
  assert_deny "T-PR16 two PR numbers, issue for the first → denied" "$tmp/incidents" \
    "$PRF_OUT" "$PRF_RC" "rf-never-skip-qa-review-before-merging"
  local ok=1; _gh_logged_any "$tmp" "issue list" && ok=0
  _verdict "T-PR16 no Signal 3 lookup" "$ok" "$(cat "$tmp/stub/gh.log" 2>/dev/null)"
}

# --- T-PR17: another PR's evidence can never be borrowed ------------------------
# PR 4242 is reviewed; every command merges something else. From the root (empty
# legacy range) each must deny without resolving any PR head.
t_pr17_donor_pr_refused() {
  local tmp; tmp=$(mktemp -d)
  trap 'rm -rf "$tmp"; trap - RETURN' RETURN
  _prf_setup "$tmp"
  _prf_wt "$tmp" feat-a
  _prf_commit "$tmp/wt-feat-a" "chore: a" "Reviewed-By-Soleur: soleur:review"
  _prf_pr "$tmp" 4242 feat-a "$(git -C "$tmp/wt-feat-a" rev-parse HEAD)"
  _prf_pr "$tmp" 424 feat-a "$(git -C "$tmp/wt-feat-a" rev-parse HEAD)"
  local cmd i=0
  for cmd in 'gh pr merge --squash 4243 # gh pr merge 4242' \
             'echo gh pr merge 4242; gh pr merge feat-b --squash' \
             'gh pr merge 4242 --squash || gh pr merge --squash 4243' \
             'gh pr merge 4242; gh pr merge "4243" --squash' \
             'gh pr merge 4242-hotfix --squash' \
             'gh pr merge 424"2" --squash'; do
    i=$((i + 1))
    rm -rf "$tmp/incidents"; mkdir -p "$tmp/incidents"; : > "$tmp/stub/gh.log"
    _prf_run "$tmp" "$tmp/root" "$cmd"
    assert_deny "T-PR17.$i [$cmd] → denied" "$tmp/incidents" "$PRF_OUT" "$PRF_RC" \
      "rf-never-skip-qa-review-before-merging"
    local ok=1; _gh_logged_any "$tmp" "pr view" && ok=0
    _verdict "T-PR17.$i no PR head was resolved" "$ok" "$(cat "$tmp/stub/gh.log" 2>/dev/null)"
  done
}

# --- T-PR18: a fork PR's own trailer is self-asserted, not evidence -------------
t_pr18_fork_pr() {
  local tmp; tmp=$(mktemp -d)
  trap 'rm -rf "$tmp"; trap - RETURN' RETURN
  _prf_setup "$tmp"
  _prf_wt "$tmp" feat-x
  _prf_commit "$tmp/wt-feat-x" "chore: fork work" "Reviewed-By-Soleur: soleur:review"
  _prf_pr "$tmp" 4242 feat-x "$(git -C "$tmp/wt-feat-x" rev-parse HEAD)" true
  # Even from a same-named local branch that descends from the head.
  _prf_run "$tmp" "$tmp/wt-feat-x" "gh pr merge 4242 --squash"
  assert_deny "T-PR18 fork PR with a self-written trailer → denied" "$tmp/incidents" \
    "$PRF_OUT" "$PRF_RC" "rf-never-skip-qa-review-before-merging"
  local ok=1; [[ "$PRF_REASON" == *"from a fork"* ]] || ok=0
  _verdict "T-PR18 reason names the fork" "$ok" "reason=${PRF_REASON:0:200}"
}

# --- T-PR19: a PR that is not OPEN lends no evidence -----------------------------
t_pr19_not_open() {
  local tmp; tmp=$(mktemp -d)
  trap 'rm -rf "$tmp"; trap - RETURN' RETURN
  _prf_setup "$tmp"
  _prf_wt "$tmp" feat-x
  _prf_commit "$tmp/wt-feat-x" "chore: merged work" "Reviewed-By-Soleur: soleur:review"
  _prf_pr "$tmp" 4242 feat-x "$(git -C "$tmp/wt-feat-x" rev-parse HEAD)" false MERGED
  _prf_run "$tmp" "$tmp/root" "gh pr merge 4242 --squash"
  assert_deny "T-PR19 MERGED PR's evidence is not borrowed" "$tmp/incidents" \
    "$PRF_OUT" "$PRF_RC" "rf-never-skip-qa-review-before-merging"
  local ok=1; [[ "$PRF_REASON" == *"is MERGED, not OPEN"* ]] || ok=0
  _verdict "T-PR19 reason names the state" "$ok" "reason=${PRF_REASON:0:200}"
}

# --- T-PR20: cd into a checkout of ANOTHER repository → legacy -------------------
t_pr20_cd_other_repo() {
  local tmp; tmp=$(mktemp -d)
  trap 'rm -rf "$tmp"; trap - RETURN' RETURN
  _prf_setup "$tmp"
  _prf_wt "$tmp" feat-a; _prf_wt "$tmp" feat-b
  _prf_commit "$tmp/wt-feat-a" "chore: a" "Reviewed-By-Soleur: soleur:review"
  _prf_commit "$tmp/wt-feat-b" "chore: b"
  _prf_pr "$tmp" 4242 feat-b "$(git -C "$tmp/wt-feat-b" rev-parse HEAD)"
  mkdir -p "$tmp/other"
  init_git_repo "$tmp/other"
  git -C "$tmp/other" remote add origin "$tmp/other-origin.git"
  _prf_run "$tmp" "$tmp/wt-feat-a" "cd $tmp/other && gh pr merge 4242 --squash"
  _assert_allowed "T-PR20 cd into another repo's checkout → legacy allow"
  local ok=1; _gh_logged_any "$tmp" "pr view" && ok=0
  _verdict "T-PR20 no PR head was resolved" "$ok" "$(cat "$tmp/stub/gh.log" 2>/dev/null)"
}

# --- T-PR21: own branch name but BEHIND the pushed head → P, no sync ------------
t_pr21_own_branch_behind() {
  local tmp; tmp=$(mktemp -d)
  trap 'rm -rf "$tmp"; trap - RETURN' RETURN
  _prf_setup "$tmp"
  _prf_wt "$tmp" feat-x
  local wt="$tmp/wt-feat-x"
  _prf_commit "$wt" "chore: work"
  git -C "$wt" push -q origin feat-x
  # The reviewed head exists on origin (pushed from elsewhere); local is behind it.
  git -C "$tmp/root" worktree add -q --detach "$tmp/elsewhere" feat-x
  _prf_commit "$tmp/elsewhere" "chore: reviewed" "Reviewed-By-Soleur: soleur:review"
  git -C "$tmp/elsewhere" push -q origin HEAD:feat-x
  local oid; oid=$(git -C "$tmp/elsewhere" rev-parse HEAD)
  _prf_pr "$tmp" 4242 feat-x "$oid"
  _prf_advance_main "$tmp"
  _prf_run "$tmp" "$wt" "gh pr merge 4242 --squash"
  _assert_allowed "T-PR21 behind own branch → verdict from the pushed head"
  local ok=1
  [[ "$(git -C "$tmp/origin.git" rev-parse refs/heads/feat-x)" == "$oid" ]] || ok=0
  [[ "$(_prf_context)" == *"is PR #4242's branch but is not at or ahead of its pushed head"* ]] || ok=0
  _verdict "T-PR21 no push and the context names the stale branch" "$ok" "context=$(_prf_context)"
}

# --- Instrument self-test: _verdict must move PASS on 1 and FAIL on 0 -----------
# Reported with printf + exit, never through the helpers under test (ADR-193).
_verdict_selftest() {
  local p0="$PASS" f0="$FAIL" t0="$TOTAL"
  _verdict "self-test pass" 1 "" >/dev/null
  _verdict "self-test fail" 0 "" >/dev/null
  if [[ "$PASS" != "$((p0 + 1))" || "$FAIL" != "$((f0 + 1))" || "$TOTAL" != "$((t0 + 2))" ]]; then
    printf 'FATAL: anti-vacuity: _verdict did not move its counters (PASS %s->%s FAIL %s->%s)\n' \
      "$p0" "$PASS" "$f0" "$FAIL" >&2
    exit 2
  fi
  PASS="$p0"; FAIL="$f0"; TOTAL="$t0"
}

_verdict_selftest

# Counted at the CALL SITE, never inside a helper, so deleting a case or its call
# cannot keep the count (ADR-193).
CASES=0
for _case in \
  t1_review_evidence_gate \
  t_v1_vacuity_todos_on_main_only \
  t_v1b_vacuity_review_subject_on_main \
  t_v1c_vacuity_trailer_on_main \
  t_v2_zero_finding_trailer_allows \
  t_v3_real_script_satisfies_gate \
  t2_uncommitted_changes \
  t3_merge_conflict \
  t3b_regen_diagnosis_in_deny \
  t4_push_failure \
  t_fp1_commit_body_newline \
  t_fp2_commit_body_chain_op \
  t_fp3_commit_body_numbered \
  t_fp4_commit_body_heredoc \
  t5_bare_merge_fires \
  t6_chained_after_commit_fires \
  t7_wrapped_merge_fires \
  t8_merge_after_heredoc_fires \
  t_mj1_malformed_json_failopen \
  t_pr1_root_session_trailer \
  t_pr1b_root_session_subject \
  t_pr1c_root_session_todo \
  t_pr_c_control_denies \
  t_pr2_fetch_pull_ref \
  t_pr3_reviewed_cwd_unreviewed_pr \
  t_pr4_no_sync_on_other_branch \
  t_pr5_own_checkout_syncs \
  t_pr5b_own_checkout_unpushed_trailer \
  t_pr6_non_hex_oid \
  t_pr7_gh_fails_legacy \
  t_pr8_same_name_diverged \
  t_pr9_two_prs_legacy \
  t_pr10_quoted_number_ignored \
  t_pr11_unfetchable_head \
  t_pr12_repo_override_legacy \
  t_pr13_repeated_number \
  t_pr14_stacked_branch \
  t_pr15_signal3_allows_in_state_n \
  t_pr16_multi_number_skips_signal3 \
  t_pr17_donor_pr_refused \
  t_pr18_fork_pr \
  t_pr19_not_open \
  t_pr20_cd_other_repo \
  t_pr21_own_branch_behind; do
  "$_case"
  CASES=$((CASES + 1))
done

echo
echo "PASS=$PASS FAIL=$FAIL TOTAL=$TOTAL CASES=$CASES"
# Anti-vacuity floor (ADR-193): the bound is a literal directly above its `if`,
# and the report is printf + exit, not a helper the floor exists to backstop.
EXPECTED_CASES=44
if [[ "$CASES" -lt "$EXPECTED_CASES" ]]; then
  printf 'FATAL: anti-vacuity: %d case(s) executed, floor is %d. The suite ran but did not assert what it claims to.\n' \
    "$CASES" "$EXPECTED_CASES" >&2
  exit 1
fi
[[ "$FAIL" -eq 0 ]] || exit 1
