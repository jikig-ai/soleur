#!/usr/bin/env bash
# Fixture-based tests for guardrails.sh — scoped to the require-milestone gate.
# Asserts gh issue create against OUR repo requires --milestone, while creation
# against an EXTERNAL repo (different owner) is exempt (their milestone sets
# differ; the backlog-hygiene rule applies only to our own issues).
#
# Isolation: the hook is invoked via stdin with synthetic Bash tool payloads;
# no real gh call is made. INCIDENTS_REPO_ROOT redirects emit_incident writes.

set -uo pipefail

# Redirect incident telemetry into a per-suite sandbox BEFORE any case runs.
# Inline per-call `INCIDENTS_REPO_ROOT=… bash "$HOOK"` is what leaked here:
# it was set on some invocations and missed on others, which greps identically
# to full isolation. See the helper header.
. "$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/lib/test-incident-sandbox.sh"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$SCRIPT_DIR/guardrails.sh"

PASS=0
FAIL=0
TOTAL=0

command -v jq >/dev/null 2>&1 || { echo "SKIP: jq missing"; exit 0; }

mk_payload() {
  local cmd="$1"
  jq -nc --arg c "$cmd" '{tool_name:"Bash", tool_input:{command:$c}}'
}

# Returns the permissionDecision or "<none>" when the hook emits no JSON (allow).
# Runs the hook from the non-git $tmp CWD (not the test process CWD). This
# isolates the require-milestone / block-stash gates under test from the
# ORTHOGONAL, branch-dependent block-commit-on-main gate: a `git commit`-based
# fixture (AC1/AC3/AC4) resolves its branch from the hook's CWD, so on the
# `main` branch (post-merge CI) block-commit-on-main denies the commit and masks
# the gate the fixture is actually exercising. A non-git CWD makes branch
# resolution empty → block-commit-on-main no-ops → the fixture is branch- and
# environment-independent (passes identically on a feature branch and on main).
# See #5192 — these fixtures passed on a feature-branch worktree but failed on
# main-CI until this isolation landed.
decision_of() {
  local cmd="$1" tmp; tmp="$(mktemp -d)"
  local out
  out="$(cd "$tmp" && mk_payload "$cmd" | INCIDENTS_REPO_ROOT="$tmp" bash "$HOOK" 2>/dev/null)"
  rm -rf "$tmp"
  # An allow is empty hook output (no JSON emitted); normalize to "<none>".
  if [[ -z "${out//[[:space:]]/}" ]]; then echo "<none>"; return; fi
  echo "$out" | jq -r '.hookSpecificOutput.permissionDecision // "<none>"' 2>/dev/null || echo "<jq-fail>"
}

assert() {
  local label="$1" want="$2" cmd="$3"
  TOTAL=$((TOTAL + 1))
  local got; got="$(decision_of "$cmd")"
  if [[ "$got" == "$want" ]]; then
    PASS=$((PASS + 1)); echo "PASS: $label → $got"
  else
    FAIL=$((FAIL + 1)); echo "FAIL: $label"; echo "  want: $want"; echo "  got:  $got"
  fi
}

# Returns the permissionDecisionReason, or "<none>" on an allow. Same
# isolation as decision_of (non-git tmp CWD, sandboxed incidents).
reason_of() {
  local cmd="$1" tmp; tmp="$(mktemp -d)"
  local out
  out="$(cd "$tmp" && mk_payload "$cmd" | INCIDENTS_REPO_ROOT="$tmp" bash "$HOOK" 2>/dev/null)"
  rm -rf "$tmp"
  if [[ -z "${out//[[:space:]]/}" ]]; then echo "<none>"; return; fi
  echo "$out" | jq -r '.hookSpecificOutput.permissionDecisionReason // "<none>"' 2>/dev/null || echo "<jq-fail>"
}

# Asserts a deny whose reason CONTAINS $want. A verdict-only row cannot tell
# "denied for the reason under test" from "denied by an upstream gate for a
# different reason"; where two denies are reachable, pin the text.
assert_reason() {
  local label="$1" want="$2" cmd="$3"
  TOTAL=$((TOTAL + 1))
  local got; got="$(reason_of "$cmd")"
  if [[ "$got" == *"$want"* ]]; then
    PASS=$((PASS + 1)); echo "PASS: $label → contains '$want'"
  else
    FAIL=$((FAIL + 1)); echo "FAIL: $label"; echo "  want reason containing: $want"; echo "  got:  ${got:0:160}"
  fi
}

# Our repo (implicit) without --milestone → deny.
assert "implicit repo, no milestone denies" "deny" \
  'gh issue create --title "x" --body "y"'

# Our repo (implicit) with --milestone but NO filing justification → deny.
# MIGRATED: before guardrails:require-filing-justification, --milestone alone
# was sufficient to allow. It is now NECESSARY BUT NOT SUFFICIENT -- a filing
# must additionally take one of the three justification exits. This fixture is
# the visible record of that contract change, not a regression.
assert "implicit repo, milestone alone no longer allows" "deny" \
  'gh issue create --title "x" --body "y" --milestone "Post-MVP / Later"'

# Explicit OUR repo without --milestone → deny (still gated).
assert "explicit jikig-ai repo, no milestone denies" "deny" \
  'gh issue create --repo jikig-ai/soleur --title "x" --body "y"'

# External repo without --milestone → allow (exempt: different owner).
assert "external repo, no milestone allows" "<none>" \
  'gh issue create --repo highagency/pencil-desktop-releases --title "x" --body-file /tmp/b.md'

# External repo with --repo=owner/name form → allow.
assert "external repo (=form), no milestone allows" "<none>" \
  'gh issue create --repo=highagency/pencil-desktop-releases --title "x"'

# QUOTED our repo without --milestone → deny (quote-aware: must not be read as external).
assert "quoted jikig-ai repo, no milestone denies" "deny" \
  'gh issue create --repo "jikig-ai/soleur" --title x'

# Embedded --repo string inside a quoted --body, no real --repo → deny (no bypass).
assert "embedded --repo in body, no milestone denies" "deny" \
  'gh issue create --title real --body "see --repo evil/x for context"'

# -R short form targeting OUR repo while an embedded external string sits in title → deny.
assert "short -R our repo wins over embedded external denies" "deny" \
  'gh issue create --title "--repo evil/x" -R jikig-ai/soleur'

# Genuine external via short -R form, no milestone → allow.
assert "external via -R short form allows" "<none>" \
  'gh issue create -R highagency/pencil-desktop-releases --title x'

# ---------------------------------------------------------------------------
# #5192 — commit-body / heredoc false-positive fixes (require-milestone + stash)
# A `git commit` whose MESSAGE documents a trigger phrase must NOT be blocked:
# the strip blanks quoted/heredoc bodies before the detection grep. Real bare
# invocations stay gated.
# ---------------------------------------------------------------------------

# AC1 — commit-body `gh issue create` at a line-start (no --milestone in body)
# is NOT blocked. Pre-fix this denied (the exact #5085 foot-gun).
assert "AC1 commit-body gh issue create allows (FP fixed)" "<none>" \
  $'git add . && git commit -m "fix the digest\ngh issue create for the operator-digest feature\n"'

# AC3 — commit-body `git stash` is NOT blocked …
assert "AC3 commit-body git stash allows (FP fixed)" "<none>" \
  $'git commit -m "doc\ngit stash is banned in worktrees\n"'
# … but a real `git stash` STILL denies.
assert "AC3 real git stash still denies" "deny" \
  'git stash'

# AC4 — bare heredoc (`-F - <<EOF … EOF`) body is NOT blocked …
assert "AC4 bare-heredoc gh issue create allows (FP fixed)" "<none>" \
  $'git commit -F - <<EOF\nnote\ngh issue create for the digest\nEOF\n'
# … but a real chained `gh issue create` AFTER the closing EOF STILL denies
# (no --milestone, implicit our repo): proves the post-terminator preservation.
assert "AC4 real create after heredoc still denies" "deny" \
  $'git commit -F - <<EOF\nbody\nEOF\n && gh issue create --title x --body y'

# Sweep (#5192) — block-delete-branch is also phrase-class. A commit body
# documenting `gh pr merge --delete-branch` must NOT be blocked (pre-fix it
# denied whenever >1 worktree exists). Note: the gate's deny is worktree-count-
# gated, so a real-invocation deny is not asserted here (untestable in a single-
# worktree CI checkout); the strip non-vacuity below proves detection survives.
assert "sweep commit-body gh pr merge --delete-branch allows (FP fixed)" "<none>" \
  $'git commit -m "doc\ngh pr merge --delete-branch orphans worktrees\n"'

# Non-vacuity: the strip preserves a REAL invocation's flags so the
# delete-branch detection still fires (only quoted bodies are blanked).
# shellcheck source=lib/incidents.sh
source "$SCRIPT_DIR/lib/incidents.sh" 2>/dev/null || true
TOTAL=$((TOTAL + 1))
if strip_command_bodies 'gh pr merge 7 --squash --delete-branch' \
     | grep -qE 'gh\s+pr\s+merge.*--delete-branch'; then
  PASS=$((PASS + 1)); echo "PASS: strip preserves real --delete-branch (detection non-vacuous)"
else
  FAIL=$((FAIL + 1)); echo "FAIL: strip dropped real --delete-branch flags"
fi

# ===========================================================================
# #5988 — hardened recursive-delete ownership proof (b) + freeze edit-lock (a)
# ===========================================================================

# Build an Edit-tool payload (file_path, no command).
mk_edit_payload() {
  local path="$1"
  jq -nc --arg p "$path" '{tool_name:"Edit", tool_input:{file_path:$p}}'
}

# Run the hook with a given payload from a given CWD, redirecting incident +
# freeze state to $root. Echoes the permissionDecision or "<none>".
run_decision() {
  local payload="$1" cwd="$2" root="$3"
  local out
  out="$(cd "$cwd" 2>/dev/null && printf '%s' "$payload" \
    | INCIDENTS_REPO_ROOT="$root" FREEZE_LOCK_REPO_ROOT="$root" bash "$HOOK" 2>/dev/null)"
  if [[ -z "${out//[[:space:]]/}" ]]; then echo "<none>"; return; fi
  echo "$out" | jq -r '.hookSpecificOutput.permissionDecision // "<none>"' 2>/dev/null || echo "<jq-fail>"
}

assert_run() {
  local label="$1" want="$2" payload="$3" cwd="$4" root="$5"
  TOTAL=$((TOTAL + 1))
  local got; got="$(run_decision "$payload" "$cwd" "$root")"
  if [[ "$got" == "$want" ]]; then
    PASS=$((PASS + 1)); echo "PASS: $label → $got"
  else
    FAIL=$((FAIL + 1)); echo "FAIL: $label"; echo "  want: $want"; echo "  got:  $got"
  fi
}

# --- Delete guard: protected targets deny; non-protected allow -------------
DG="$(mktemp -d)"; git init -q "$DG/repo"
mkdir -p "$DG/other/.git" "$DG/scratch-abc123"
ln -s "$DG/repo" "$DG/link"

# repo root (resolved via git worktree list from the command cwd) → deny
assert_run "delete: repo root denies" "deny" \
  "$(mk_payload "rm -rf $DG/repo")" "$DG/repo" "$DG"
# symlink resolving onto a .git-bearing checkout → deny
assert_run "delete: symlink-to-repo-root denies" "deny" \
  "$(mk_payload "rm -rf $DG/link")" "$DG/repo" "$DG"
# arbitrary .git-bearing dir (not the cwd repo) → deny
assert_run "delete: .git-bearing dir denies" "deny" \
  "$(mk_payload "rm -rf $DG/other")" "$DG" "$DG"
# filesystem root → deny (constant protected)
assert_run "delete: / denies" "deny" \
  "$(mk_payload "rm -rf /")" "$DG" "$DG"
# \$HOME → deny (constant protected)
assert_run "delete: \$HOME denies" "deny" \
  "$(mk_payload "rm -rf $HOME")" "$DG" "$DG"
# non-protected scratch dir → allow (default-allow-except-protected; the staging
# ALLOW needs no marker today — a non-protected target is already permitted)
assert_run "delete: non-protected scratch allows" "<none>" \
  "$(mk_payload "rm -rf $DG/scratch-abc123")" "$DG" "$DG"
# ordinary build artifact → allow (guard must not brick normal cleanup)
assert_run "delete: node_modules allows" "<none>" \
  "$(mk_payload "rm -rf $DG/repo/node_modules")" "$DG/repo" "$DG"
rm -rf "$DG"

# --- Freeze edit-lock ------------------------------------------------------
FZ="$(mktemp -d)"
mkdir -p "$FZ/apps" "$FZ/other"
# Activate a VALID freeze via the CLI (writes a realpath-canonical prefix).
FREEZE_LOCK_REPO_ROOT="$FZ" bash "$SCRIPT_DIR/lib/freeze-lock.sh" set "$FZ/apps" >/dev/null 2>&1

# Edit inside the allowed prefix → allow
assert_run "freeze: edit inside prefix allows" "<none>" \
  "$(mk_edit_payload "$FZ/apps/foo.ts")" "$FZ" "$FZ"
# Edit outside the allowed prefix → deny
assert_run "freeze: edit outside prefix denies" "deny" \
  "$(mk_edit_payload "$FZ/other/bar.ts")" "$FZ" "$FZ"

# Malformed freeze state (two lines) → fail-open (edit allowed)
printf '%s\n%s\n' "$FZ/apps" "$FZ/extra" > "$FZ/.claude/.freeze-lock"
assert_run "freeze: malformed state fails open (edit allows)" "<none>" \
  "$(mk_edit_payload "$FZ/other/bar.ts")" "$FZ" "$FZ"

# Absent freeze state → edit allowed
rm -f "$FZ/.claude/.freeze-lock"
assert_run "freeze: absent state allows edit" "<none>" \
  "$(mk_edit_payload "$FZ/other/bar.ts")" "$FZ" "$FZ"
rm -rf "$FZ"

# --- TR3: freeze ACTIVE must NOT shadow the Bash sentinels -----------------
TR="$(mktemp -d)"
FREEZE_LOCK_REPO_ROOT="$TR" bash "$SCRIPT_DIR/lib/freeze-lock.sh" set "$TR/apps" >/dev/null 2>&1
# rm -rf on a worktree path → still denied by the narrow sentinel
assert_run "TR3: freeze active, rm -rf .worktrees still denies" "deny" \
  "$(mk_payload 'rm -rf ./.worktrees/foo')" "$TR" "$TR"
# gh issue create without --milestone → still denied by require-milestone
assert_run "TR3: freeze active, gh issue create no-milestone still denies" "deny" \
  "$(mk_payload 'gh issue create --title x --body y')" "$TR" "$TR"
# git stash → still denied by block-stash
assert_run "TR3: freeze active, git stash still denies" "deny" \
  "$(mk_payload 'git stash')" "$TR" "$TR"
# benign Bash command → allowed (freeze never applies to Bash)
assert_run "TR3: freeze active, benign Bash allows" "<none>" \
  "$(mk_payload 'ls -la')" "$TR" "$TR"
rm -rf "$TR"

# ===========================================================================
# #5988 review hardening — variable/tilde expansion, wrapper forms, heredoc
# false-positive, MultiEdit/NotebookEdit freeze coverage, ancestor deny.
# ===========================================================================

mk_multiedit_payload() { jq -nc --arg p "$1" '{tool_name:"MultiEdit", tool_input:{file_path:$p}}'; }
mk_notebook_payload()  { jq -nc --arg p "$1" '{tool_name:"NotebookEdit", tool_input:{notebook_path:$p}}'; }

# HOME-aware runner: overrides HOME so the $HOME/~ deny assertions are hermetic
# (never resolves onto the test operator's real home).
run_decision_home() {
  local payload="$1" cwd="$2" root="$3" home="$4" out
  out="$(cd "$cwd" 2>/dev/null && printf '%s' "$payload" \
    | HOME="$home" INCIDENTS_REPO_ROOT="$root" FREEZE_LOCK_REPO_ROOT="$root" bash "$HOOK" 2>/dev/null)"
  if [[ -z "${out//[[:space:]]/}" ]]; then echo "<none>"; return; fi
  echo "$out" | jq -r '.hookSpecificOutput.permissionDecision // "<none>"' 2>/dev/null || echo "<jq-fail>"
}
assert_run_home() {
  local label="$1" want="$2" payload="$3" cwd="$4" root="$5" home="$6"
  TOTAL=$((TOTAL + 1))
  local got; got="$(run_decision_home "$payload" "$cwd" "$root" "$home")"
  if [[ "$got" == "$want" ]]; then PASS=$((PASS + 1)); echo "PASS: $label → $got"
  else FAIL=$((FAIL + 1)); echo "FAIL: $label"; echo "  want: $want"; echo "  got:  $got"; fi
}

# --- variable/tilde expansion bypass (3 agents flagged; the earlier
#     "delete: \$HOME denies" fixture MASKED this by pre-expanding \$HOME in the
#     test shell). These fixtures pass the LITERAL token via single quotes. ---
VX="$(mktemp -d)"; git init -q "$VX/repo"; VXHOME="$(mktemp -d)"
assert_run_home "delete: literal \$HOME denies (unmasked)" "deny" \
  "$(mk_payload 'rm -rf $HOME')" "$VX/repo" "$VX" "$VXHOME"
assert_run_home "delete: literal \${HOME} denies" "deny" \
  "$(mk_payload 'rm -rf ${HOME}')" "$VX/repo" "$VX" "$VXHOME"
assert_run_home "delete: quoted \"\$HOME\" denies" "deny" \
  "$(mk_payload 'rm -rf "$HOME"')" "$VX/repo" "$VX" "$VXHOME"
assert_run_home "delete: tilde ~ denies" "deny" \
  "$(mk_payload 'rm -rf ~')" "$VX/repo" "$VX" "$VXHOME"
assert_run_home "delete: tilde ~/ denies" "deny" \
  "$(mk_payload 'rm -rf ~/')" "$VX/repo" "$VX" "$VXHOME"
# \$PWD from the repo root resolves onto the repo root → deny.
assert_run_home "delete: \$PWD (repo root) denies" "deny" \
  "$(mk_payload 'rm -rf $PWD')" "$VX/repo" "$VX" "$VXHOME"
# a benign \$HOME-relative subdir is still a delete UNDER home; home itself is
# protected, and node_modules under a non-home cwd stays allowed.
assert_run_home "delete: node_modules still allows (no over-deny)" "<none>" \
  "$(mk_payload 'rm -rf node_modules')" "$VX/repo" "$VX" "$VXHOME"
rm -rf "$VX" "$VXHOME"

# --- wrapper / path-qualified / escaped rm forms deny on a protected target ---
WR="$(mktemp -d)"; git init -q "$WR/repo"
assert_run "delete: /bin/rm on repo root denies" "deny" \
  "$(mk_payload "/bin/rm -rf $WR/repo")" "$WR/repo" "$WR"
assert_run "delete: env rm on repo root denies" "deny" \
  "$(mk_payload "env rm -rf $WR/repo")" "$WR/repo" "$WR"
assert_run "delete: command rm on repo root denies" "deny" \
  "$(mk_payload "command rm -rf $WR/repo")" "$WR/repo" "$WR"
rm -rf "$WR"

# --- heredoc / commit-message body must NOT false-deny (detection on $SCAN),
#     while a real chained rm and a quoted literal target still deny. ---
HD="$(mktemp -d)"; git init -q "$HD/repo"
assert_run "delete: commit heredoc body mentioning rm -rf / allows" "<none>" \
  "$(mk_payload $'git commit -F - <<EOF\nfix\nrm -rf /\nEOF')" "$HD/repo" "$HD"
assert_run "delete: commit -m body mentioning ; rm -rf / allows" "<none>" \
  "$(mk_payload 'git commit -m "note; rm -rf /"')" "$HD/repo" "$HD"
assert_run "delete: real chained rm after commit still denies" "deny" \
  "$(mk_payload $'git commit -m x && rm -rf /')" "$HD/repo" "$HD"
assert_run "delete: quoted literal protected target still denies" "deny" \
  "$(mk_payload "rm -rf \"$HD/repo\"")" "$HD/repo" "$HD"
rm -rf "$HD"

# --- ancestor-of-a-real-worktree deny (the "$_pr == $_res/*" branch) ---
AN="$(mktemp -d)"; git init -q "$AN/repo"
( cd "$AN/repo" && git -c user.email=t@t -c user.name=t commit -q --allow-empty -m init \
    && git worktree add -q "$AN/repo/wt/feat-x" -b feat-x ) >/dev/null 2>&1
assert_run "delete: ancestor of a registered worktree denies" "deny" \
  "$(mk_payload "rm -rf $AN/repo/wt")" "$AN/repo" "$AN"
rm -rf "$AN"

# --- freeze covers MultiEdit + NotebookEdit (not just Write|Edit) ---
FZ2="$(mktemp -d)"; mkdir -p "$FZ2/apps" "$FZ2/other"
FREEZE_LOCK_REPO_ROOT="$FZ2" bash "$SCRIPT_DIR/lib/freeze-lock.sh" set "$FZ2/apps" >/dev/null 2>&1
assert_run "freeze: MultiEdit outside prefix denies" "deny" \
  "$(mk_multiedit_payload "$FZ2/other/bar.ts")" "$FZ2" "$FZ2"
assert_run "freeze: MultiEdit inside prefix allows" "<none>" \
  "$(mk_multiedit_payload "$FZ2/apps/bar.ts")" "$FZ2" "$FZ2"
assert_run "freeze: NotebookEdit outside prefix denies" "deny" \
  "$(mk_notebook_payload "$FZ2/other/n.ipynb")" "$FZ2" "$FZ2"
assert_run "freeze: NotebookEdit inside prefix allows" "<none>" \
  "$(mk_notebook_payload "$FZ2/apps/n.ipynb")" "$FZ2" "$FZ2"
rm -rf "$FZ2"

# --- Conflict-marker gate ---------------------------------------------------
# This gate had ZERO coverage, which is how the single-marker false positive
# shipped and made `git merge origin/main` uncommittable repo-wide.
#
# EVERY fixture below is BUILT with printf from variables -- no marker literal
# appears at column 0 in this file. That is not style: a first draft embedded
# them in heredocs, and the file then staged as added lines carrying all three
# marker types, so merging main into any branch without this commit would trip
# the guard on THIS FILE. That is the reported bug reintroduced at full
# three-marker strength, where the per-file rule cannot discriminate it. The
# same reasoning is why tests/hooks/test_hook_emissions.sh builds its fixture
# with printf; see its comment.
CM="$(mktemp -d)"
# Owning trap. The suite's `exit 2` instrument-guard below and the `exit 1` on
# any failure both bypass the inline `rm -rf "$CM"` at the end of this block, so
# without this the fixture repo leaks on exactly the paths that matter. Scoped
# to $CM only: the sibling fixture dirs above are pre-existing accepted debt
# (scripts/lint-trap-tempfile-ownership.highwater), and paying that off here
# would be the "touch a file, inherit its debt" failure the lint's own header
# says switched earlier gates off.
trap 'rm -rf "$CM"' EXIT
git init -q "$CM/repo"
git -C "$CM/repo" config user.email t@t.local
git -C "$CM/repo" config user.name t
# Not on `main`: block-commit-on-main is orthogonal and would mask every result.
git -C "$CM/repo" checkout -q -b feat-cm

MK_LT="$(printf '%s' '<<<<' ; printf '%s' '<<<')"
MK_EQ="$(printf '%s' '====' ; printf '%s' '===')"
MK_GT="$(printf '%s' '>>>>' ; printf '%s' '>>>')"

cm_stage() {  # $1 = file content, $2 = optional path (default f.md)
  local rel="${2:-f.md}"
  mkdir -p "$CM/repo/$(dirname "$rel")"
  printf '%s\n' "$1" > "$CM/repo/$rel"
  git -C "$CM/repo" add "$rel"
}

# INSTRUMENT SELF-TEST — run before any assertion below, because every "allow"
# case here is satisfied by EMPTY hook output, and a hook that crashed, was
# mispathed, or never executed also produces empty output. Without this, the
# allow assertions certify nothing. Drive both arms once and refuse to continue
# unless each moved. (Mirrors the dispatcher guard used earlier in this file.)
cm_stage "$MK_LT HEAD
ours
$MK_EQ
theirs
$MK_GT other"
_cm_pos="$(run_decision "$(mk_payload 'git commit -m x')" "$CM/repo" "$CM/repo")"
cm_stage 'plain content, no markers'
_cm_neg="$(run_decision "$(mk_payload 'git commit -m x')" "$CM/repo" "$CM/repo")"
if [[ "$_cm_pos" != "deny" || "$_cm_neg" != "<none>" ]]; then
  echo "GUARD FAIL: conflict-marker instrument is not wired — known-positive gave '$_cm_pos' (expected deny), known-negative gave '$_cm_neg' (expected <none>). Every conflict assertion below would be unobservable." >&2
  exit 2
fi

# A REAL unresolved conflict: all three markers in one file → deny.
cm_stage "$MK_LT HEAD
ours
$MK_EQ
theirs
$MK_GT other"
assert_run "conflict: full marker triple denies" "deny" \
  "$(mk_payload 'git commit -m x')" "$CM/repo" "$CM/repo"

# Partial resolution — `=======` deleted, two types left → still deny.
cm_stage "$MK_LT HEAD
ours
theirs
$MK_GT other"
assert_run "conflict: partial resolution (2 of 3) still denies" "deny" \
  "$(mk_payload 'git commit -m x')" "$CM/repo" "$CM/repo"

# THE FALSE POSITIVE this fix exists for: prose quoting ONE marker → allow.
# Shape taken from the kb-index merge-driver plan now on origin/main.
cm_stage "Example sentinel the driver writes:

\`\`\`
$MK_LT kb-index: merge driver could not resolve — re-run the merge
\`\`\`

Nothing above is an unresolved conflict."
assert_run "conflict: single quoted marker in prose allows" "<none>" \
  "$(mk_payload 'git commit -m x')" "$CM/repo" "$CM/repo"

# THE REGRESSION A TWO-OF-THREE RULE WOULD CAUSE. scripts/merge-kb-index.sh
# writes a LONE sentinel when the driver fails, because git itself writes NO
# markers in that case (it marks the path UU and leaves ours-content in place,
# so the file reads clean). The sentinel is the only visible signal, and it must
# still deny -- but ONLY in the file it can legitimately appear in.
cm_stage "$MK_LT kb-index: merge driver could not resolve (driver exited 3)
- [Some Entry](project/x.md)" "knowledge-base/INDEX.md"
assert_run "conflict: lone kb-index sentinel in INDEX.md denies" "deny" \
  "$(mk_payload 'git commit -m x')" "$CM/repo" "$CM/repo"
git -C "$CM/repo" rm -q --cached knowledge-base/INDEX.md
rm -f "$CM/repo/knowledge-base/INDEX.md"

# Second false-positive class: a Markdown setext underline is 7+ `=` at line
# start, which the unanchored `={7}` matched.
cm_stage 'A Heading
=========

Body text.'
assert_run "conflict: setext heading underline allows" "<none>" \
  "$(mk_payload 'git commit -m x')" "$CM/repo" "$CM/repo"

# Exactly seven `=` alone, no other marker type in the file → allow.
cm_stage "Rule below:
$MK_EQ
done"
assert_run "conflict: lone seven-equals line allows" "<none>" \
  "$(mk_payload 'git commit -m x')" "$CM/repo" "$CM/repo"

# PER-FILE counting: two types split across two files is NOT a conflict.
# A global counter would deny this pair.
cm_stage "Doc A quotes $MK_LT once." "a.md"
cm_stage "Doc B has a rule:
$MK_EQ
end" "b.md"
assert_run "conflict: two types split across two files allows" "<none>" \
  "$(mk_payload 'git commit -m x')" "$CM/repo" "$CM/repo"
git -C "$CM/repo" rm -q --cached a.md b.md; rm -f "$CM/repo/a.md" "$CM/repo/b.md"

# The gate must also cover `git merge --continue`, the command in the real bug.
cm_stage "$MK_LT HEAD
ours
$MK_EQ
theirs
$MK_GT other"
assert_run "conflict: merge --continue is gated too" "deny" \
  "$(mk_payload 'git merge --continue')" "$CM/repo" "$CM/repo"

# ASYMMETRIC ARM: a stray terminator alone denies. This is the commonest botched
# resolution — opener and `=======` deleted, trailer missed — and it has no
# false-positive class here (zero `^>{7}( |$)` lines on origin/main).
cm_stage "some text
$MK_GT origin/main
more text"
assert_run "conflict: lone stray terminator denies" "deny" \
  "$(mk_payload 'git commit -m x')" "$CM/repo" "$CM/repo"

# Symmetry check: a lone OPENER does not deny (it has a real FP class — prose
# quoting it — which is the bug this whole change exists to fix).
cm_stage "prose mentioning $MK_LT once, nothing else"
assert_run "conflict: lone opener still allows" "<none>" \
  "$(mk_payload 'git commit -m x')" "$CM/repo" "$CM/repo"

# THE `^+` ANCHOR: the gate must fire on ADDED markers only, so REMOVING a
# conflict is never blocked. Untestable until now for a fixture-shape reason
# worth naming: the repo had no initial commit, so every staged line was an
# addition and the direction constraint was unconstrained by construction.
# Commit the triple first, then stage its removal.
cm_stage "$MK_LT HEAD
ours
$MK_EQ
theirs
$MK_GT other" "resolved.md"
git -C "$CM/repo" -c core.hooksPath=/dev/null commit -q -m "base with conflict" 2>/dev/null
printf '%s\n' 'ours and theirs, reconciled' > "$CM/repo/resolved.md"
git -C "$CM/repo" add resolved.md
assert_run "conflict: REMOVING markers is allowed (^+ anchor)" "<none>" \
  "$(mk_payload 'git commit -m x')" "$CM/repo" "$CM/repo"

# The production dispatch branch. Claude Code always supplies `.cwd`, so the
# `git -C "$CONFLICT_MARKERS_DIR"` arm is what actually runs in production —
# every case above exercises only the fallback arm, because mk_payload omits it.
mk_payload_cwd() {
  jq -nc --arg c "$1" --arg d "$2" '{tool_name:"Bash", tool_input:{command:$c}, cwd:$d}'
}
cm_stage "$MK_LT HEAD
ours
$MK_EQ
theirs
$MK_GT other"
assert_run "conflict: denies via the .cwd dispatch arm too" "deny" \
  "$(mk_payload_cwd 'git commit -m x' "$CM/repo")" "$CM/repo" "$CM/repo"

# The trigger must cover every verb that commits a conflict resolution. Only
# `commit` and `merge --continue` were gated; rebase/cherry-pick/revert
# `--continue` create commits from a resolution too and were entirely ungated.
cm_stage "$MK_LT HEAD
ours
$MK_EQ
theirs
$MK_GT other"
assert_run "conflict: rebase --continue is gated" "deny" \
  "$(mk_payload 'git rebase --continue')" "$CM/repo" "$CM/repo"
assert_run "conflict: cherry-pick --continue is gated" "deny" \
  "$(mk_payload 'git cherry-pick --continue')" "$CM/repo" "$CM/repo"

# Ordinary content → allow (control: proves the gate is not denying everything).
cm_stage 'nothing to see here'
assert_run "conflict: clean content allows" "<none>" \
  "$(mk_payload 'git commit -m x')" "$CM/repo" "$CM/repo"
rm -rf "$CM"

# ---------------------------------------------------------------------------
# guardrails:require-filing-justification — Guard 1 mutation matrix.
#
# Every row below was derived from the DESIGN before the guard was written. A
# matrix derived from finished code tests the code; a matrix derived from the
# design tests the property.
#
# Each fixture carries --milestone so it clears the require-milestone gate
# first: these rows must exercise the justification gate, not be masked by an
# upstream deny that happens to produce the same verdict for a different reason.
# ---------------------------------------------------------------------------

MS='--milestone "Post-MVP / Later"'

# AC7 — the floor: no exit taken at all → deny.
assert "filing-justification: no exit taken denies" "deny" \
  "gh issue create --title \"guard checks assertion SHAPE\" --body \"the guard is imperfect\" $MS"

# AC8 exit 1 — the machinery ledger. Free, always available.
assert "filing-justification: exit 1 (meta/machinery) allows" "<none>" \
  "gh issue create --title \"live-arm ledger records reachability\" --body \"b\" --label meta/machinery $MS"

# AC8 exit 1 — the = form of the flag must work too.
assert "filing-justification: exit 1 (--label=meta/machinery) allows" "<none>" \
  "gh issue create --title \"t\" --body \"b\" --label=meta/machinery $MS"

# AC8 exit 2 — a named surface AND a measured size ABOVE the inline threshold.
assert "filing-justification: exit 2 (User-Impact + large Fix-Size) allows" "<none>" \
  "gh issue create --title \"t\" --body \"User-Impact: the /dashboard route 500s for org owners
Fix-Size: 240 lines / 9 files\" $MS"

# AC8 exit 3 — a rule mandates the filing (ADR-155 vocabulary).
assert "filing-justification: exit 3 (Mandated-By) allows" "<none>" \
  "gh issue create --title \"t\" --body \"Mandated-By: wg-block-pr-ready-on-undeferred-operator-steps\" $MS"

# AC9 — THE row this gate exists for. A measured size INSIDE the inline
# threshold is refused: the 19-lines-in-1-file deferral that was justified as
# "a separate change with its own blast radius" and measured otherwise.
assert "filing-justification: Fix-Size inside inline threshold denies" "deny" \
  "gh issue create --title \"t\" --body \"User-Impact: the /settings page mislabels the plan
Fix-Size: 19 lines / 1 file\" $MS"

# Boundary — exactly at the threshold is INSIDE it (<=100 AND <=4).
assert "filing-justification: Fix-Size exactly 100/4 denies (boundary is inclusive)" "deny" \
  "gh issue create --title \"t\" --body \"User-Impact: the /billing page shows a stale total
Fix-Size: 100 lines / 4 files\" $MS"

# Boundary, other side — one file past the cap is OUTSIDE it.
assert "filing-justification: Fix-Size 100/5 allows (files past cap)" "<none>" \
  "gh issue create --title \"t\" --body \"User-Impact: the /billing page shows a stale total
Fix-Size: 100 lines / 5 files\" $MS"

# The allow-list is POSITIVE: a User-Impact naming no surface from the shared
# taxonomy does not satisfy exit 2. This is the row a deny-list of bad phrasings
# could never fail, which is why the taxonomy is an allow-list.
assert "filing-justification: User-Impact naming no surface denies" "deny" \
  "gh issue create --title \"t\" --body \"User-Impact: the system is less rigorous
Fix-Size: 500 lines / 20 files\" $MS"

# Fix-Size is required alongside User-Impact, not optional.
assert "filing-justification: User-Impact without Fix-Size denies" "deny" \
  "gh issue create --title \"t\" --body \"User-Impact: the /dashboard route 500s\" $MS"

# Fix-Size must PARSE. An adjective is not a measurement.
assert "filing-justification: non-numeric Fix-Size denies" "deny" \
  "gh issue create --title \"t\" --body \"User-Impact: the /dashboard route 500s
Fix-Size: small / a few files\" $MS"

# Derivable-inputs is a DENY PREDICATE on an otherwise-passing filing: the claim
# itself is the trigger. Without this row the predicate could be deleted and the
# suite would stay green, because every other row passes it vacuously.
assert "filing-justification: missing-numbers claim without a source denies" "deny" \
  "gh issue create --title \"t\" --body \"User-Impact: the /reports page is wrong
Fix-Size: 300 lines / 12 files
We would have to choose 19 timeout values first.\" $MS"

# ... and the same body WITH a concrete source class passes.
assert "filing-justification: missing-numbers claim with Inputs-Derived allows" "<none>" \
  "gh issue create --title \"t\" --body \"User-Impact: the /reports page is wrong
Fix-Size: 300 lines / 12 files
We would have to choose 19 timeout values first.
Inputs-Derived: ten successful main workflow runs\" $MS"

# The machinery exit must NOT be satisfied by the label name merely appearing in
# prose -- only by a real --label flag. Anchor on the flag, not the bare token
# (cq-assert-anchor-not-bare-token).
assert "filing-justification: meta/machinery in prose only still denies" "deny" \
  "gh issue create --title \"t\" --body \"this is arguably meta/machinery work\" $MS"

# DOCUMENTED RESIDUAL, pinned so it is a known state rather than a surprise: a
# mid-sentence Mandated-By passes HERE and is refused at the merge boundary,
# which anchors it whole-line over the issue body. A whole-line anchor here is
# unmatchable (this hook's corpus for an inline --body is the one-line $COMMAND),
# so the remediation TEXT carries the fix instead. If this row ever flips to
# deny, the corpus changed and the residual is closed -- update the deny text.
assert "filing-justification: mid-sentence Mandated-By still passes the hook (known residual)" "<none>" \
  "gh issue create --title t --body \"this is Mandated-By: wg-block-pr-ready-on-undeferred-operator-steps per the rule\" $MS"

# Mandated-By must carry a WELL-FORMED rule id, not any text.
assert "filing-justification: malformed Mandated-By denies" "deny" \
  "gh issue create --title \"t\" --body \"Mandated-By: because I said so\" $MS"

# INHERITED for free from living inside the require-milestone block -- asserted
# rather than assumed, because the inheritance is the reason the block was
# extended instead of duplicated.
assert "filing-justification: external repo stays exempt" "<none>" \
  'gh issue create --repo acme/widgets --title "t" --body "no justification"'

# #5192 class: a commit MESSAGE documenting a filing is not a filing. $SCAN has
# heredocs/quotes stripped, so this must not deny.
assert "filing-justification: commit body documenting gh issue create allows" "<none>" \
  'git commit -m "docs: explain that gh issue create needs a justification"'

# --- The PRESCRIBED --body-file form (P1, found at review).
# review/SKILL.md says "Use `gh issue create --body-file <path>` -- never
# `--body \"$VAR\"`". Reading only $COMMAND made exits 2 and 3 structurally
# unreachable for that shape, so every correctly-formed user-facing filing was
# denied unless it took exit 1 -- which would have pushed real product issues
# onto the machinery ledger and corrupted the separation this gate creates.
# The guard must accept the command shape the guard itself prescribes.
BF_OK="$(mktemp -t gr-body.XXXXXXXX.md)"
printf 'User-Impact: the /dashboard route 500s for org owners\nFix-Size: 240 lines / 9 files\n' > "$BF_OK"
BF_MAND="$(mktemp -t gr-body.XXXXXXXX.md)"
printf 'Mandated-By: wg-block-pr-ready-on-undeferred-operator-steps\n' > "$BF_MAND"
BF_SMALL="$(mktemp -t gr-body.XXXXXXXX.md)"
printf 'User-Impact: the /settings page mislabels the plan\nFix-Size: 19 lines / 1 file\n' > "$BF_SMALL"

assert "filing-justification: --body-file reaches exit 2" "<none>" \
  "gh issue create --title t --body-file $BF_OK $MS"
assert "filing-justification: --body-file reaches exit 3" "<none>" \
  "gh issue create --title t --body-file $BF_MAND $MS"
assert "filing-justification: --body-file still refuses inside the inline threshold" "deny" \
  "gh issue create --title t --body-file $BF_SMALL $MS"
assert "filing-justification: unreadable --body-file fails TOWARD gating" "deny" \
  "gh issue create --title t --body-file /nonexistent/soleur-no-such-body.md $MS"
assert "filing-justification: an EMPTY body-file still denies (no vacuous pass)" "deny" \
  "gh issue create --title t --body-file /dev/null $MS"
rm -f "$BF_OK" "$BF_MAND" "$BF_SMALL"

# --- CLASS 4: `gh api .../issues -X POST` creates an issue with the word
# "create" nowhere in it. This repo has a DOCUMENTED instance of an agent taking
# that route after guardrails:require-milestone denied the create form.
assert "filing-justification: gh api POST issues without justification denies" "deny" \
  'gh api -X POST repos/jikig-ai/soleur/issues -f title=x -f body=y'
assert "filing-justification: gh api --method POST form also denies" "deny" \
  'gh api --method POST repos/jikig-ai/soleur/issues -f title=x'
assert "filing-justification: gh api POST with the machinery label allows" "<none>" \
  'gh api -X POST repos/jikig-ai/soleur/issues -f title=x --label meta/machinery'

# NARROWS ONLY. gh api takes no --milestone, so the milestone arm stays scoped
# to the create form; a GET and a POST to another endpoint are untouched.
assert "filing-justification: gh api GET issues is untouched" "<none>" \
  'gh api repos/jikig-ai/soleur/issues --paginate'
assert "filing-justification: gh api POST to another endpoint is untouched" "<none>" \
  'gh api -X POST repos/jikig-ai/soleur/labels -f name=x'

# --- Harness rows: the guard's OWN failure modes ---
#
# Row H1 — FAIL TOWARD GATING when the shared taxonomy is unreadable. A gate
# that silently stops matching is indistinguishable from a gate that passed.
# This row is why the taxonomy read is not a bare `grep ... || true`.
# EXERCISED AGAINST A COPY, NOT THE REPO. An earlier form emptied the tracked
# taxonomy in place and restored it afterwards. Three things were wrong with
# that, and only the third is visible from inside this suite:
#   * a relative path truncates some OTHER file when the suite runs from a
#     different CWD;
#   * an exit between the truncate and the restore leaves the real taxonomy
#     empty, and an empty allow-list makes the gate deny every exit-2 filing
#     from then on, for everyone;
#   * preflight Check 10 executes this suite as the plan's declared
#     discoverability probe inside a bubblewrap sandbox that binds the repo
#     READ-ONLY, so the truncate simply fails there -- the probe the plan
#     declares could not pass in the sandbox it is declared for. Measured: 105/106
#     in-sandbox, and a chmod -a-w rehearsal reproduces it outside.
# The gate resolves its taxonomy from its OWN ${BASH_SOURCE[0]%/*}/lib/, so a
# copy of the hook in a writable temp tree reads the COPY's taxonomy. That
# exercises the unreadable-allow-list path against the real gate code while
# writing nothing into the repository.
TAXO_SANDBOX="$(mktemp -d)"
cp -R -- "$SCRIPT_DIR/lib" "$TAXO_SANDBOX/lib"
cp -- "$HOOK" "$TAXO_SANDBOX/guardrails.sh"
# `cp -R` carries the SOURCE mode bits, so a repo checked out read-only yields a
# read-only copy and the truncate below fails -- the row then reports <none> and
# reads as "the gate did not fail toward gating" when in fact the fixture never
# got set up. Force the copy writable; it lives in a temp dir we own.
chmod -R u+w "$TAXO_SANDBOX"
: > "$TAXO_SANDBOX/lib/user-surface-taxonomy.txt"
# Setup, not an assertion: if the truncate did not take, the row below would be
# testing a POPULATED taxonomy and passing for the wrong reason.
[[ -s "$TAXO_SANDBOX/lib/user-surface-taxonomy.txt" ]] && {
  printf 'FATAL: taxonomy fixture did not truncate; the row below would be vacuous.\n' >&2
  exit 1
}
_HOOK_REAL="$HOOK"
HOOK="$TAXO_SANDBOX/guardrails.sh"
assert "filing-justification: unreadable taxonomy fails TOWARD gating" "deny" \
  "gh issue create --title \"t\" --body \"User-Impact: the /dashboard route 500s
Fix-Size: 900 lines / 40 files\" $MS"
HOOK="$_HOOK_REAL"
rm -rf "$TAXO_SANDBOX"

# --- Escape rows (found by feeding the PRISTINE guard corpora it must refuse).
# Neither of these is reachable by mutating the guard: it was working exactly as
# written, so every mutation row stayed green. They took an escape corpus.

# E1 — the machinery exit must read a REAL --label token. Merely NAMING the flag
# inside a quoted --body previously satisfied the free exit.
assert "filing-justification: --label named in PROSE does not open the machinery exit" "deny" \
  "gh issue create --title t --body \"we should use --label meta/machinery here\" $MS"

# E1 control — a genuine flag still opens it, so the fix did not just deny more.
assert "filing-justification: a REAL --label token still opens the machinery exit" "<none>" \
  "gh issue create --title t --body \"b\" --label meta/machinery $MS"

# E3 — two Fix-Size lines is MALFORMED. bash =~ binds the FIRST match, so a large
# size first and the honest small size second evaded the threshold refusal.
assert "filing-justification: two Fix-Size lines denies (large first, small last)" "deny" \
  "gh issue create --title t --body \"User-Impact: the /dashboard route 500s
Fix-Size: 900 lines / 40 files
Fix-Size: 19 lines / 1 file\" $MS"

# E3 control — the small-first ordering still denies, and a single large size
# still passes, so the fix discriminates rather than blanket-denying.
assert "filing-justification: two Fix-Size lines denies (small first, large last)" "deny" \
  "gh issue create --title t --body \"User-Impact: the /dashboard route 500s
Fix-Size: 19 lines / 1 file
Fix-Size: 900 lines / 40 files\" $MS"

# Row H2 — the REAL gate still reads a populated taxonomy. H1 now mutates only
# a copy, so this row's job shifts from "did the restore run" to "did H1 leak" --
# if H1 ever regains a repo write, or $HOOK is left pointing at the temp copy,
# this row denies and says so.
assert "filing-justification: taxonomy restored after H1" "<none>" \
  "gh issue create --title \"t\" --body \"User-Impact: the /dashboard route 500s
Fix-Size: 900 lines / 40 files\" $MS"

# --- Ship-time escape rows: the gate refused two shapes gh itself produces.
#
# S1 — `--label` is a cobra StringSlice, so `--label a,b` is ordinary documented
# gh syntax. Exact-equality against the whole value denied it, and the refusal
# told the filer to add the flag they had just passed. The consequence is the
# --body-file consequence one syntax over: an honest machinery filing is pushed
# onto the product ledger, corrupting the separation this gate creates.
assert "filing-justification: comma-joined --label (machinery first)" "<none>" \
  "gh issue create --title t --body \"b\" --label meta/machinery,type/bug $MS"
assert "filing-justification: comma-joined --label (machinery last)" "<none>" \
  "gh issue create --title t --body \"b\" --label type/bug,meta/machinery $MS"
assert "filing-justification: comma-joined --label without machinery denies" "deny" \
  "gh issue create --title t --body \"b\" --label type/bug,type/chore $MS"

# S1 near-misses — the comma anchor must not widen into a substring match.
assert "filing-justification: foo/meta/machinery is not the label" "deny" \
  "gh issue create --title t --body \"b\" --label foo/meta/machinery $MS"
assert "filing-justification: meta/machineryX is not the label" "deny" \
  "gh issue create --title t --body \"b\" --label meta/machineryX $MS"

# S2 — the `gh api` POST form the trigger already covers has NO --label flag; it
# spells the same thing `-f labels[]=...`. Reading only --label left exit 1
# structurally unreachable on that route, so every api-form machinery filing was
# denied with no honest exit but 2 or 3.
assert "filing-justification: api labels[]=meta/machinery opens the machinery exit" "<none>" \
  "gh api repos/jikig-ai/soleur/issues -X POST -f title=x -f 'labels[]=meta/machinery' -f body=y"
assert "filing-justification: api labels[]=type/bug still denies" "deny" \
  "gh api repos/jikig-ai/soleur/issues -X POST -f title=x -f 'labels[]=type/bug' -f body=y"

# ---------------------------------------------------------------------------
# Guard 3 — interactive-gate tokenizer and ordering (FR7; two false denies on
# honest exit-1 filings, learning 2026-09-11 §Session Errors 3).
#
# PROPERTY. For any command whose REAL flag tokens carry --label meta/machinery,
# the gate passes exit 1 regardless of heredoc-body content or the readability
# of --body-file; a command that cannot be tokenized is denied with an
# actionable message, never passed on a guess.
#
# (a) A heredoc body containing an apostrophe ("Soleur's") made `xargs -n1`
#     abort on an unmatched quote, so the --label token was never read and the
#     refusal told the filer to add the flag they had just passed. The tokenizer
#     now reads strip_heredocs "$COMMAND" -- bodies blanked, quoting preserved.
# (b) The unreadable --body-file deny fired BEFORE exit 1 was honoured, so an
#     exit-1 filing was refused for a body it does not need.
# ---------------------------------------------------------------------------

HD_APOS=$'cat > body.md <<\'EOF\'\nSoleur\'s guard fired twice\nEOF'

# (a) heredoc apostrophe + real --label + --body-file (the exact shape denied).
assert "guard3: heredoc apostrophe + real --label meta/machinery allows" "<none>" \
  "$HD_APOS
gh issue create --title t --body-file body.md --label meta/machinery $MS"

# (a) isolated to the tokenizer: same heredoc, inline --body, no body-file at
# all -- so this row cannot pass through the ordering fix in (b).
assert "guard3: heredoc apostrophe + inline --body + real --label allows" "<none>" \
  "$HD_APOS
gh issue create --title t --body b --label meta/machinery $MS"

# (a) control: blanking the heredoc must not OPEN the exit -- the same heredoc
# with no label is still denied.
assert "guard3: heredoc apostrophe without the label still denies" "deny" \
  "$HD_APOS
gh issue create --title t --body b $MS"

# (a′) the two other heredoc spellings share the same regex: dash-heredoc
# (`<<-`, tab-indented terminator) and a double-quoted delimiter. Dropping the
# `-?` or the quote class survived the rows above (#8074 review).
assert "guard3: <<-'EOF' dash-heredoc apostrophe + real --label allows" "<none>" \
  "cat > body.md <<-'EOF'
	Soleur's guard
	EOF
gh issue create --title t --body-file body.md --label meta/machinery $MS"
assert "guard3: <<\"EOF\" double-quoted delimiter apostrophe + real --label allows" "<none>" \
  "cat > body.md <<\"EOF\"
Soleur's guard
EOF
gh issue create --title t --body-file body.md --label meta/machinery $MS"

# (a″) a here-STRING is not a heredoc: `<<<word` must not blank the rest of
# the command up to a later line starting with `word` (it did — every real
# token after it vanished and the leftover quote denied as unbalanced).
assert "guard3: <<< here-string before a real --label allows" "<none>" \
  "gh issue create --title t --body \"\$(cat <<<foo)\" --label meta/machinery $MS
echo foo"

# (a‴) must-DENY: the label as PROSE inside a heredoc body is not a flag —
# identity stripping (no blanking at all) would read it as one.
assert "guard3: --label meta/machinery only inside the heredoc body denies" "deny" \
  "cat > body.md <<'EOF'
please add --label meta/machinery to this
EOF
gh issue create --title t --body-file body.md $MS"

# (b) exit 1 is honoured before the body-file read: the corpus is not needed.
assert "guard3: exit 1 + nonexistent --body-file allows" "<none>" \
  "gh issue create --title t --body-file /nonexistent/soleur-no-such-body.md --label meta/machinery $MS"

# (c) ... and a filing NOT on exit 1 still fails toward gating on the SAME
# unreadable file, with the body-file reason (not the no-exit floor).
assert_reason "guard3: exit-2-shaped filing + nonexistent --body-file still denies on the body" \
  "which this gate cannot read" \
  "gh issue create --title t --body-file /nonexistent/soleur-no-such-body.md --label type/bug $MS"

# (d) unbalanced quoting OUTSIDE any heredoc: fail-closed, actionable.
TOK_MSG="BLOCKED: the command could not be tokenized (unbalanced quoting); write the body to a file and pass --body-file"
assert_reason "guard3: apostrophe inside --title (unbalanced, no heredoc) denies with the tokenizer message" \
  "$TOK_MSG" \
  "gh issue create --title 'its unbalanced --body b --label meta/machinery $MS"

# Mutation 2 pin: a whitespace-split fallback would read the --label inside
# this quoted --body as a real flag and reopen the bare-token escape.
assert_reason "guard3: unbalanced quote + --label inside quoted --body denies (no whitespace-split fallback)" \
  "$TOK_MSG" \
  "gh issue create --title 'x --body \"x --label meta/machinery y\" $MS"

# Third member of the same class, found while fixing (a): GNU xargs cannot
# carry a quoted token across a line, so a multi-line inline --body stopped the
# tokenizer and a --label AFTER it was never read (measured on main: denied).
# Newlines are folded to spaces before xargs; this row is the pin.
assert "guard3: multi-line inline --body followed by --label meta/machinery allows" "<none>" \
  "gh issue create --title t --body \"line one
line two\" --label meta/machinery $MS"

# ... and the fold must not flatten quoting: the label INSIDE a multi-line
# quoted body is still prose, not a flag.
assert "guard3: --label inside a multi-line quoted --body is still prose (denies)" "deny" \
  "gh issue create --title t --body \"line one
--label meta/machinery in prose\" $MS"

# (e) must-PASS non-canonical (H2): comma-joined label, machinery last, with an
# apostrophe in the heredoc body.
assert "guard3: --label type/bug,meta/machinery with heredoc apostrophe allows" "<none>" \
  "$HD_APOS
gh issue create --title t --body-file body.md --label type/bug,meta/machinery $MS"

# (f) regression pin: a `gh issue create` that appears ONLY inside a heredoc
# body is not a filing (_gh_create reads \$SCAN). Already true; pinned so the
# tokenizer change cannot regress it.
assert "guard3: gh issue create only inside a heredoc body is not a filing" "<none>" \
  $'cat > notes.md <<\'EOF\'\ngh issue create --title x --body y\nEOF'

# strip_heredocs blanks ONLY the heredoc body: quoted spans survive, because
# xargs needs them to tokenize `--milestone "Post-MVP / Later"` as one value.
TOTAL=$((TOTAL + 1))
_sh_got="$(strip_heredocs "$HD_APOS
gh issue create --milestone \"Post-MVP / Later\" --label 'meta/machinery'")"
_sh_want=$'cat > body.md <<\'EOF\'\nEOF\ngh issue create --milestone "Post-MVP / Later" --label \'meta/machinery\''
if [[ "$_sh_got" == "$_sh_want" ]]; then
  PASS=$((PASS + 1)); echo "PASS: strip_heredocs blanks the body and preserves quoted spans"
else
  FAIL=$((FAIL + 1)); echo "FAIL: strip_heredocs"; echo "  want: $_sh_want"; echo "  got:  $_sh_got"
fi

# strip_command_bodies is BYTE-IDENTICAL to its pre-factor form (six other
# hooks consume it). Expected string captured from the pre-change lib.
TOTAL=$((TOTAL + 1))
_scb_got="$(strip_command_bodies $'git commit -F - <<EOF\nbody\nEOF\n && gh issue create --title "x y" --body \'z\'')"
_scb_want=$'git commit -F - <<EOF\nEOF\n && gh issue create --title   --body  '
if [[ "$_scb_got" == "$_scb_want" ]]; then
  PASS=$((PASS + 1)); echo "PASS: strip_command_bodies unchanged after the heredoc-regex factor"
else
  FAIL=$((FAIL + 1)); echo "FAIL: strip_command_bodies drifted"; echo "  want: $_scb_want"; echo "  got:  $_scb_got"
fi

# ---------------------------------------------------------------------------
# AC6b — ASSERTION-COUNT FLOOR.
#
# This suite had none. A run that executed ZERO assertions exited 0 and read as
# a pass, so every guard in this file was one dispatch bug away from being
# certified by a suite that asserted nothing. The floor is derived as
# "main's count + the rows this change adds" rather than pinned to a literal a
# sibling PR would silently invalidate, and it is reported with printf + exit
# rather than through the pass/fail helpers it exists to backstop -- a floor
# that calls fail() is disarmed by the same edit that disarms fail().
# Derived, not guessed: 65 rows on main at the merge base + 19 added by this
# change + 4 escape rows + 1 residual row + 5 body-file rows + 5 class-4 rows found at review
# + 7 ship-time escape rows (comma-joined --label, its two near-misses, and the
# api `labels[]=` spelling of exit 1) = 106, + 13 Guard 3 rows (FR7: the
# tokenizer and ordering false denies -- 11 hook rows and 2 direct
# strip_heredocs/strip_command_bodies rows) = 119. Stated as the sum so a
# sibling PR that adds a row makes this stale LOUDLY (the floor trips) rather
# than silently.
MIN_ASSERTIONS=$((106 + 17))
if [[ "$TOTAL" -lt "$MIN_ASSERTIONS" ]]; then
  printf 'FLOOR: only %s assertions ran, expected at least %s. A suite that\n' "$TOTAL" "$MIN_ASSERTIONS" >&2
  printf 'asserts nothing exits 0 and reads as a pass -- refusing to report one.\n' >&2
  exit 1
fi

echo
echo "Total: $TOTAL  Pass: $PASS  Fail: $FAIL"
[[ $FAIL -eq 0 ]] || exit 1
