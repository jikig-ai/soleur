#!/usr/bin/env bash
# Fixture-based tests for pre-merge-rebase.sh. Asserts each of the four deny
# branches calls emit_incident with the expected rule_id + event_type=deny.
#
# Isolation: each test builds its own work-tree (git repo) plus a separate
# "incidents root" directory under mktemp. INCIDENTS_REPO_ROOT redirects
# emit_incident's writes into the incidents root so the operator's real
# .claude/.rule-incidents.jsonl is not polluted.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$SCRIPT_DIR/pre-merge-rebase.sh"

PASS=0
FAIL=0
TOTAL=0

command -v jq >/dev/null 2>&1 || { echo "SKIP: jq missing"; exit 0; }
command -v git >/dev/null 2>&1 || { echo "SKIP: git missing"; exit 0; }

init_git_repo() {
  local dir="$1"
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
  git init -q --bare -b main "$origin"
  git -C "$work" remote add origin "$origin"
  git -C "$work" push -q origin HEAD:main
  git -C "$work" fetch -q origin
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

# --- T-MJ1: malformed-JSON stdin must fail open (exit 0, no deny) -----------
# Before the fix, jq exits 5 under `set -eo pipefail` and the hook aborts with
# no JSON. After the fix (`|| true`), CMD="" ⇒ no merge detected ⇒ exit 0.
t_mj1_malformed_json_failopen() {
  local tmp; tmp=$(mktemp -d)
  local incidents="$tmp/incidents"
  mkdir -p "$incidents"

  local out exit_code=0
  out=$(printf 'not json' | INCIDENTS_REPO_ROOT="$incidents" "$HOOK" 2>/dev/null) || exit_code=$?
  exit_code=${exit_code:-0}
  assert_no_intercept "T-MJ1 malformed JSON fails open" "$incidents" "$out" "$exit_code"
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

t1_review_evidence_gate
t_v1_vacuity_todos_on_main_only
t_v1b_vacuity_review_subject_on_main
t_v1c_vacuity_trailer_on_main
t_v2_zero_finding_trailer_allows
t_v3_real_script_satisfies_gate
t2_uncommitted_changes
t3_merge_conflict
t4_push_failure
t_fp1_commit_body_newline
t_fp2_commit_body_chain_op
t_fp3_commit_body_numbered
t_fp4_commit_body_heredoc
t5_bare_merge_fires
t6_chained_after_commit_fires
t7_wrapped_merge_fires
t8_merge_after_heredoc_fires
t_mj1_malformed_json_failopen

echo
echo "PASS=$PASS FAIL=$FAIL TOTAL=$TOTAL"
[[ "$FAIL" -eq 0 ]] || exit 1
