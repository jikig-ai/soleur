#!/usr/bin/env bash
# Fixture-based tests for guardrails.sh — mostly the filing gate
# (require-milestone + require-filing-justification, lexer per ADR-256), plus
# the stash, rm-rf and delete-branch guards it shares a hook with.
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

command -v jq >/dev/null 2>&1 || { echo "UNRESOLVED: jq missing — this suite asserted nothing; install jq"; exit 3; }

mk_payload() {
  # Through stdin, not --arg: one argv string is capped at 128 KiB
  # (MAX_ARG_STRLEN), and the AC6 row feeds the hook 300 KiB.
  printf '%s' "$1" | jq -Rsc '{tool_name:"Bash", tool_input:{command:.}}'
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
  local out rc=0
  out="$(cd "$tmp" && mk_payload "$cmd" | INCIDENTS_REPO_ROOT="$tmp" bash "$HOOK" 2>/dev/null)" || rc=$?
  # A row that passes only because the filing LEXER failed (and the floor or
  # the ask path caught it) is not a witness for the lexer. Every row reds on a
  # guardrails-filing-lexer-failure incident unless it opts in with
  # FS_ALLOW_LEXER_INCIDENT=1 -- the failure-path (F) rows, which exist to
  # make the lexer fail. This turns every existing deny row into a lexer row.
  if [[ -z "${FS_ALLOW_LEXER_INCIDENT:-}" ]] \
     && grep -qF '"guardrails-filing-lexer-failure"' "$tmp/.claude/.rule-incidents.jsonl" 2>/dev/null; then
    rm -rf "$tmp"; echo "<lexer-failure-incident>"; return
  fi
  rm -rf "$tmp"
  # A non-zero hook exit BLOCKS the tool call in Claude Code (exit 2) or is a
  # crash -- either way it is not the empty-output allow, so never read it as one.
  if [[ "$rc" != 0 ]]; then echo "<rc=$rc>"; return; fi
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
  local out rc=0
  out="$(cd "$tmp" && mk_payload "$cmd" | INCIDENTS_REPO_ROOT="$tmp" bash "$HOOK" 2>/dev/null)" || rc=$?
  # Same lexer-incident check as decision_of: a reason twin must not pass on
  # a text the failure path produced when the row claims the lexer's verdict.
  if [[ -z "${FS_ALLOW_LEXER_INCIDENT:-}" ]] \
     && grep -qF '"guardrails-filing-lexer-failure"' "$tmp/.claude/.rule-incidents.jsonl" 2>/dev/null; then
    rm -rf "$tmp"; echo "<lexer-failure-incident>"; return
  fi
  rm -rf "$tmp"
  # A non-zero hook exit BLOCKS the tool call in Claude Code (exit 2) or is a
  # crash -- either way it is not the empty-output allow, so never read it as one.
  if [[ "$rc" != 0 ]]; then echo "<rc=$rc>"; return; fi
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

# INSTRUMENT SELF-TEST. Every verdict-owning helper must be able to FAIL, or
# a gutted `assert` (always PASS) satisfies every row and the floor alike.
# Driven once each with a known-wrong expectation, then unwound; reported with
# printf + exit, never through the helpers under test.
_ctl_p=$PASS; _ctl_f=$FAIL; _ctl_t=$TOTAL
assert "self-test: assert can fail" "deny" 'echo harmless' >/dev/null
assert_reason "self-test: assert_reason can fail" "no such refusal text" 'echo harmless' >/dev/null
assert "self-test: assert can pass" "<none>" 'echo harmless' >/dev/null
if (( FAIL != _ctl_f + 2 || PASS != _ctl_p + 1 )); then
  printf 'INSTRUMENT: assert/assert_reason did not report a known FAIL and a known PASS (PASS %s->%s FAIL %s->%s)\n' \
    "$_ctl_p" "$PASS" "$_ctl_f" "$FAIL" >&2
  exit 1
fi
PASS=$_ctl_p; FAIL=$_ctl_f; TOTAL=$_ctl_t

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

# run_decision with git config injected into the HOOK's environment only, as
# GIT_CONFIG_COUNT/KEY_n/VALUE_n. Never exported suite-wide: the fixture repo is
# built with plain git, and a suite-wide GIT_CONFIG_COUNT would also collide with
# any helper that sets its own. Trailing args are KEY VALUE pairs.
run_decision_cfg() {
  local payload="$1" cwd="$2" root="$3"; shift 3
  local -a cfg=()
  local i=0
  while (( $# >= 2 )); do
    cfg+=("GIT_CONFIG_KEY_$i=$1" "GIT_CONFIG_VALUE_$i=$2"); i=$((i + 1)); shift 2
  done
  local out
  out="$(cd "$cwd" 2>/dev/null && printf '%s' "$payload" \
    | env "GIT_CONFIG_COUNT=$i" "${cfg[@]}" \
        INCIDENTS_REPO_ROOT="$root" FREEZE_LOCK_REPO_ROOT="$root" bash "$HOOK" 2>/dev/null)"
  if [[ -z "${out//[[:space:]]/}" ]]; then echo "<none>"; return; fi
  echo "$out" | jq -r '.hookSpecificOutput.permissionDecision // "<none>"' 2>/dev/null || echo "<jq-fail>"
}

assert_run_cfg() {  # label want payload cwd root KEY VALUE [KEY VALUE...]
  local label="$1" want="$2" payload="$3" cwd="$4" root="$5"; shift 5
  TOTAL=$((TOTAL + 1))
  local got; got="$(run_decision_cfg "$payload" "$cwd" "$root" "$@")"
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
# Documentation that shows a conflict marker inside a fenced block is ordinary
# in this repo — every runbook that explains resolving one does it.
cm_stage "Example of what an unresolved hunk looks like:

\`\`\`
$MK_LT HEAD
\`\`\`

Nothing above is an unresolved conflict."
assert_run "conflict: single quoted marker in prose allows" "<none>" \
  "$(mk_payload 'git commit -m x')" "$CM/repo" "$CM/repo"

# THE RETIRED SENTINEL ARM, pinned as ABSENCE (#8377 / ADR-235).
#
# Until this change the awk carried an extra rule: a lone `<<<<<<< kb-index:`
# opener denied, but ONLY in knowledge-base/INDEX.md, because the retired merge
# driver wrote that sentinel when it failed and git itself writes no markers in
# that case. The driver, the file's tracked copy and the sentinel are all gone,
# so the generic asymmetry governs: a LONE opener allows (it has a large
# false-positive class — every doc that quotes one), and only a lone TERMINATOR
# or two marker types deny.
#
# These two rows are the regression guard on the DELETION. Re-adding any
# path-conditional arm makes them RED, which is the point: the next reader of
# that awk should have to delete a passing assertion to bring the sentinel back.
cm_stage "$MK_LT ours
A lone opener at column 0, in an ordinary file."
assert_run "conflict: lone opener alone allows (no path-conditional arm)" "<none>" \
  "$(mk_payload 'git commit -m x')" "$CM/repo" "$CM/repo"

cm_stage "$MK_LT kb-index: merge driver could not resolve (driver exited 3)
- [Some Entry](project/x.md)" "knowledge-base/INDEX.md"
assert_run "conflict: lone opener in knowledge-base/INDEX.md allows — the kb-index sentinel arm is retired" "<none>" \
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
# A global counter would deny this pair. The opener sits at COLUMN 0: an earlier
# revision put it mid-line ("Doc A quotes <marker> once."), which the `^\+<{7}`
# anchor never matches, so the per-file reset was never exercised at all.
cm_stage "$MK_LT ours
Doc A quotes an opener." "a.md"
cm_stage "Doc B has a rule:
$MK_EQ
end" "b.md"
assert_run "conflict: two types split across two files allows" "<none>" \
  "$(mk_payload 'git commit -m x')" "$CM/repo" "$CM/repo"
# USER GIT CONFIG must not change the verdict (#8263). The awk keys on the
# `+++ b/` header, and a developer's global config can rewrite it:
# diff.mnemonicprefix=true prints `+++ i/…`, diff.noprefix=true prints `+++ …`,
# and diff.relative=true from a subdirectory drops INDEX.md from the diff
# entirely. Each silently disarmed the sentinel arm on a developer host while CI
# (default config) stayed green. One config per row, so a pin that covers one
# config and not another is visible.
#
# HARNESS CHECK first: prove the injected config actually reaches git in this
# fixture, or every row below would silently test default config.
# Captured, then matched from a herestring: `git diff | grep -q` under pipefail can
# SIGPIPE git on an early match and read as NO match.
_cm_hdr=$(env GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=diff.mnemonicprefix GIT_CONFIG_VALUE_0=true \
  git -C "$CM/repo" diff --cached --no-color --no-ext-diff)
if ! grep -q '^+++ i/' <<<"$_cm_hdr"; then
  echo "GUARD FAIL: injected GIT_CONFIG_* did not change the fixture's diff header — the config rows below would test nothing." >&2
  exit 2
fi
# SECOND HARNESS CHECK — the one above proves git honours the config, NOT that
# the config reaches the HOOK. It injects into a direct `git -C … diff`, which is
# a sibling command, not the command under test: deleting the `env … "${cfg[@]}"`
# from run_decision_cfg leaves it green and every row below silently reverts to
# default config (measured: suite stayed 127/127 with the injection removed).
# The rows below assert the default-config verdict, so they cannot notice either.
# This check drives the REAL invocation path and requires the verdict to MOVE.
# A deliberately malformed count (declared 1, no keys) makes git fail inside the
# hook; what matters is only that the answer differs from the uninjected one.
_cm_stub="$CM/echo-cfg-hook.sh"
cat > "$_cm_stub" <<'STUB'
#!/usr/bin/env bash
# Reports what GIT_CONFIG_* the CALLER actually put in this process's env.
cat >/dev/null
printf '{"hookSpecificOutput":{"permissionDecision":"count=%s key0=%s"}}\n' \
  "${GIT_CONFIG_COUNT:-unset}" "${GIT_CONFIG_KEY_0:-unset}"
STUB
chmod +x "$_cm_stub"
_cm_saved_hook="$HOOK"
HOOK="$_cm_stub"
_cm_seen=$(run_decision_cfg "$(mk_payload 'git commit -m x')" "$CM/repo" "$CM/repo" diff.noprefix true)
HOOK="$_cm_saved_hook"
if [[ "$_cm_seen" != "count=1 key0=diff.noprefix" ]]; then
  echo "GUARD FAIL: run_decision_cfg did not deliver the injected config to the process it runs (saw '$_cm_seen', want 'count=1 key0=diff.noprefix'); every config row below is a duplicate of its default-config sibling." >&2
  exit 2
fi
# Under diff.noprefix the `+++ b/` header never matches, the per-file reset never
# runs, and counting goes global — an over-fire that denies a clean pair (#8263).
# ONE CONFIG PER ROW, so a hardening that covers one and not another is visible.
# The hook defends against all three by passing --src-prefix/--dst-prefix and
# --no-relative explicitly, which override diff.noprefix, diff.mnemonicprefix and
# diff.relative respectively; each row is the regression guard on one of those.
assert_run_cfg "conflict: two types split across two files allows under diff.noprefix=true" "<none>" \
  "$(mk_payload 'git commit -m x')" "$CM/repo" "$CM/repo" diff.noprefix true
assert_run_cfg "conflict: two types split across two files allows under diff.mnemonicprefix=true" "<none>" \
  "$(mk_payload 'git commit -m x')" "$CM/repo" "$CM/repo" diff.mnemonicprefix true
mkdir -p "$CM/repo/sub"
assert_run_cfg "conflict: two types split across two files allows under diff.relative=true from a subdirectory" "<none>" \
  "$(mk_payload 'git commit -m x')" "$CM/repo/sub" "$CM/repo" diff.relative true
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
assert "filing-justification: gh issue create -F (short --body-file) reaches exit 3" "<none>" \
  "gh issue create --title t -F $BF_MAND $MS"
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
# gh api has NO --label flag (gh rejects it: unknown flag), so it is not an
# exit; the per-filing field parser credits only the api spelling, -f
# 'labels[]=…'. Flipped from <none> by #9089 -- stricter, never weaker.
assert_reason "filing-justification: gh api --label is not an exit; the refusal names the api spelling" \
  "-f labels[]=meta/machinery (the gh api spelling)" \
  'gh api -X POST repos/jikig-ai/soleur/issues -f title=x --label meta/machinery'

# NARROWS ONLY. gh api takes no --milestone, so the milestone arm stays scoped
# to the create form; a GET and a POST to another endpoint are untouched.
assert "filing-justification: gh api GET issues is untouched" "<none>" \
  'gh api repos/jikig-ai/soleur/issues --paginate'
assert "filing-justification: gh api POST to another endpoint is untouched" "<none>" \
  'gh api -X POST repos/jikig-ai/soleur/labels -f name=x'

# --- CLASS 4 endpoint scope: only the COLLECTION endpoint creates an issue.
# `repos/[^[:space:]]+/issues\b` spanned `/`, so a POST to an EXISTING issue's
# sub-resource (labels, comments, assignees) was denied as a new filing.
assert "filing-justification: POST to issues/<N>/labels is not a filing" "<none>" \
  "gh api -X POST repos/jikig-ai/soleur/issues/123/labels -f 'labels[]=type/bug'"
assert "filing-justification: POST to issues/<N>/comments is not a filing" "<none>" \
  'gh api -X POST repos/jikig-ai/soleur/issues/123/comments -f body=hi'
assert "filing-justification: --method POST to issues/<N>/assignees is not a filing" "<none>" \
  "gh api --method POST repos/jikig-ai/soleur/issues/123/assignees -f 'assignees[]=me'"
assert "filing-justification: templated \$REPO/\$N sub-resource POST is not a filing" "<none>" \
  "gh api -X POST repos/\$REPO/issues/\$N/labels -f 'labels[]=x'"
assert "filing-justification: {number} placeholder sub-resource POST is not a filing" "<none>" \
  "gh api -X POST repos/{owner}/{repo}/issues/{number}/labels --input l.json"
# The endpoint and the POST signal must sit in the SAME command segment, so
# listing issues and labelling them in one command is not a filing.
assert "filing-justification: list-then-label loop is not a filing" "<none>" \
  "for n in \$(gh api repos/jikig-ai/soleur/issues?labels=x --jq '.[].number'); do gh api -X POST repos/jikig-ai/soleur/issues/\$n/labels -f 'labels[]=y'; done"
assert "filing-justification: list piped into a labelling xargs is not a filing" "<none>" \
  "gh api repos/jikig-ai/soleur/issues --jq '.[].number' | xargs -I{} gh api -X POST repos/jikig-ai/soleur/issues/{}/labels -f 'labels[]=y'"
# Since #9089 the lexer SEES both quoted endpoints (quoting no longer hides a
# filing); the row stays <none> because neither is one -- a POST to a comments
# sub-resource and a GET of the collection, each in its own command.
assert "filing-justification: quoted endpoints on both sides of && are blanked, not a filing" "<none>" \
  'gh api -X POST "repos/jikig-ai/soleur/issues/5/comments" -f body=x && gh api "repos/jikig-ai/soleur/issues?per_page=5"'
# The collection endpoint still gates in every unquoted spelling gh routes to it.
assert "filing-justification: collection ?query still gates" "deny" \
  'gh api repos/jikig-ai/soleur/issues?x=1 -X POST -f title=x -f body=y'
assert "filing-justification: collection trailing slash still gates" "deny" \
  'gh api repos/jikig-ai/soleur/issues/ -X POST -f title=x -f body=y'
assert "filing-justification: leading-slash /repos path still gates" "deny" \
  'gh api /repos/jikig-ai/soleur/issues -X POST -f title=x -f body=y'
assert "filing-justification: full api.github.com URL still gates" "deny" \
  'gh api https://api.github.com/repos/jikig-ai/soleur/issues -X POST -f title=x -f body=y'
assert "filing-justification: {owner}/{repo} placeholders still gate" "deny" \
  'gh api repos/{owner}/{repo}/issues -X POST -f title=x -f body=y'
assert "filing-justification: a single \$REPO word still gates" "deny" \
  'gh api repos/$REPO/issues -X POST -f title=x -f body=y'
assert "filing-justification: a variable glued after the collection still gates" "deny" \
  'gh api repos/jikig-ai/soleur/issues$QS -X POST -f title=x -f body=y'
assert "filing-justification: \${EP:-…} default-expansion endpoint still gates" "deny" \
  'gh api ${EP:-repos/jikig-ai/soleur/issues} -X POST -f title=x -f body=y'
assert "filing-justification: collection path glued to a redirect still gates" "deny" \
  'gh api -X POST -f title=x -f body=y repos/jikig-ai/soleur/issues>out.json'
assert "filing-justification: a quoted pipe in --jq does not split the create" "deny" \
  "gh api -X POST --jq '.number|tostring' repos/jikig-ai/soleur/issues -f title=x -f body=y"
assert "filing-justification: an escaped separator does not split the create" "deny" \
  'gh api repos/jikig-ai/soleur/issues -f x=\; -X POST -f body=y'
assert "filing-justification: create after a sub-resource POST still gates" "deny" \
  "gh api -X POST repos/jikig-ai/soleur/issues/5/labels -f 'labels[]=x' && gh api repos/jikig-ai/soleur/issues -X POST -f title=x -f body=y"
assert "filing-justification: backslash-continued gh api gates" "deny" \
  $'gh api \\\n  repos/jikig-ai/soleur/issues \\\n  -X POST -f title=x -f body=y'
# POST spellings gh honours that the trigger did not read (measured on main: all ALLOWED).
assert "filing-justification: -XPOST gates" "deny" \
  'gh api repos/jikig-ai/soleur/issues -XPOST -f body=y'
assert "filing-justification: --method=POST gates" "deny" \
  'gh api repos/jikig-ai/soleur/issues --method=POST -f body=y'
assert "filing-justification: --input (gh defaults to POST) gates" "deny" \
  'gh api repos/jikig-ai/soleur/issues --input b.json'
assert_reason "filing-justification: an --input filing gets the --input refusal" \
  "uses --input, so this gate cannot read its body or labels" \
  'gh api repos/jikig-ai/soleur/issues -X POST --input b.json'
assert "filing-justification: -F title= gates" "deny" \
  'gh api repos/jikig-ai/soleur/issues -F title=x -f body=y'
assert_reason "filing-justification: -F title= is refused for the justification, not as a --body-file" \
  "names no user-visible consequence" \
  'gh api repos/jikig-ai/soleur/issues -X POST -F title=x -f body=y'
assert "filing-justification: api -F title= with a Mandated-By body reaches exit 3" "<none>" \
  "gh api repos/jikig-ai/soleur/issues -X POST -F title=x -f 'body=Mandated-By: wg-block-pr-ready-on-undeferred-operator-steps'"
assert "filing-justification: --raw-field title= gates" "deny" \
  'gh api repos/jikig-ai/soleur/issues --raw-field title=x -f body=y'
assert "filing-justification: attached short flag -ftitle= gates" "deny" \
  'gh api repos/jikig-ai/soleur/issues -ftitle=x -f body=y'
# Prose stays prose: quoted spans and heredoc bodies are blanked ($SCAN).
assert "filing-justification: sub-resource POST whose body names the collection path is not a filing" "<none>" \
  'gh api -X POST repos/jikig-ai/soleur/issues/5/comments -f body="use gh api repos/jikig-ai/soleur/issues -X POST to file"'
assert "filing-justification: an api create inside a heredoc body is prose" "<none>" \
  $'cat > /tmp/soleur-note.md <<\'EOF\'\nrun: gh api repos/jikig-ai/soleur/issues -X POST -f title=x\nEOF\ngh api repos/jikig-ai/soleur/labels --jq length'
# The segment loop must not end the hook: gates after CLASS 4 still run.
assert_reason "filing-justification: a later gate still runs after a non-filing gh api" \
  "git stash is not allowed" \
  'gh api repos/jikig-ai/soleur/labels --jq length; git stash'

# --- Review round (#9088): one row per alternation member, so no member of the
# terminator, POST-signal or splitter lists is covered only by accident.
assert "filing-justification: endpoint LAST in the command still gates" "deny" \
  'gh api -X POST -f title=x -f body=y repos/jikig-ai/soleur/issues'
assert "filing-justification: create inside an unquoted \$(...) gates" "deny" \
  'n=$(gh api -X POST -f title=x -f body=y repos/jikig-ai/soleur/issues)'
assert "filing-justification: create inside backticks gates" "deny" \
  'n=`gh api -X POST -f title=x -f body=y repos/jikig-ai/soleur/issues`'
assert "filing-justification: collection glued to an input redirect gates" "deny" \
  'gh api repos/jikig-ai/soleur/issues<in.txt -X POST -f title=x -f body=y'
assert "filing-justification: collection with an escaped ? gates" "deny" \
  'gh api repos/jikig-ai/soleur/issues\?x=1 -X POST -f title=x -f body=y'
assert "filing-justification: collection #fragment gates (gh strips it)" "deny" \
  'gh api repos/jikig-ai/soleur/issues#x -f title=x -f body=y'
assert "filing-justification: -f=title= gates" "deny" \
  'gh api repos/jikig-ai/soleur/issues -f=title=x -f body=y'
assert "filing-justification: --field title= gates" "deny" \
  'gh api repos/jikig-ai/soleur/issues --field title=x -f body=y'
assert "filing-justification: --field=title= gates" "deny" \
  'gh api repos/jikig-ai/soleur/issues --field=title=x -f body=y'
assert "filing-justification: --raw-field=title= gates" "deny" \
  'gh api repos/jikig-ai/soleur/issues --raw-field=title=x -f body=y'
assert "filing-justification: --input=file gates" "deny" \
  'gh api repos/jikig-ai/soleur/issues --input=b.json'
assert "filing-justification: an escaped | does not split the create" "deny" \
  'gh api repos/jikig-ai/soleur/issues -f q=a\|b -X POST -f body=y'
assert "filing-justification: an escaped & does not split the create" "deny" \
  'gh api repos/jikig-ai/soleur/issues -f q=a\&b -X POST -f body=y'
# A redirect's & or | is not a command separator.
assert "filing-justification: 2>&1 mid-command does not split the create" "deny" \
  'gh api repos/jikig-ai/soleur/issues 2>&1 -X POST -f title=x -f body=y'
assert "filing-justification: 2>&1 before the endpoint does not split the create" "deny" \
  'gh api 2>&1 repos/jikig-ai/soleur/issues -X POST -f title=x -f body=y'
assert "filing-justification: &>file mid-command does not split the create" "deny" \
  'gh api repos/jikig-ai/soleur/issues &>/dev/null -X POST -f title=x -f body=y'
assert "filing-justification: >&2 mid-command does not split the create" "deny" \
  'gh api repos/jikig-ai/soleur/issues >&2 -X POST -f title=x -f body=y'
assert "filing-justification: >| mid-command does not split the create" "deny" \
  'gh api repos/jikig-ai/soleur/issues >|/tmp/o -X POST -f title=x -f body=y'
assert "filing-justification: <&0 mid-command does not split the create" "deny" \
  'gh api repos/jikig-ai/soleur/issues <&0 -X POST -f title=x -f body=y'
# A $(...) argument's separators belong to the substitution, not the command.
assert "filing-justification: a piped \$(...) argument does not split the create" "deny" \
  'gh api repos/jikig-ai/soleur/issues -f body=$(cat a.md | head -50) -X POST -f title=x'
assert "filing-justification: a ;-list \$(...) argument does not split the create" "deny" \
  'gh api repos/jikig-ai/soleur/issues -f body=$(cat a.md; true) -X POST -f title=x'
# The POST signal is unanchored: an escape or an empty expansion reaches gh as -f/-X.
assert "filing-justification: \\-f title= gates" "deny" \
  'gh api repos/jikig-ai/soleur/issues \-f title=x -f body=y'
assert "filing-justification: \${E}-f title= gates" "deny" \
  'gh api repos/jikig-ai/soleur/issues ${E}-f title=x -f body=y'
assert "filing-justification: \$E-X POST gates" "deny" \
  'gh api repos/jikig-ai/soleur/issues $E-X POST -f body=y'
# Padding cannot hide a create: the whole match is one perl pass, not a fork per segment.
_pad="$(printf '; true%.0s' $(seq 1 2000))"
assert "filing-justification: 2000 padding segments do not hide a create" "deny" \
  "gh api repos/jikig-ai/soleur/labels --jq length${_pad}; gh api repos/jikig-ai/soleur/issues -X POST -f title=x -f body=y"
# --input moves -f fields to the query string, so a label passed that way is not an exit.
assert_reason "filing-justification: --input plus -f labels[]=meta/machinery is refused" \
  "uses --input, so this gate cannot read its body or labels" \
  "gh api repos/jikig-ai/soleur/issues --input b.json -f 'labels[]=meta/machinery'"
# The refusal names the exit-1 spelling for the form actually used.
assert_reason "filing-justification: the api-form refusal names the api label spelling" \
  "-f labels[]=meta/machinery (the gh api spelling)" \
  'gh api repos/jikig-ai/soleur/issues -X POST -f title=x -f body=y'
assert "filing-justification: a piped backtick argument does not split the create" "deny" \
  'gh api repos/jikig-ai/soleur/issues -f body=`cat a.md | head -5` -X POST -f title=x'
assert_reason "filing-justification: the gh issue create refusal keeps the --label spelling" \
  "add --label meta/machinery. That ledger" \
  "gh issue create --title t --body b $MS"
# Must stay ALLOWED: sub-resources and non-issue paths around the new rules.
assert "filing-justification: sub-resource POST with a trailing 2>&1 is not a filing" "<none>" \
  "gh api -X POST repos/jikig-ai/soleur/issues/123/labels -f 'labels[]=x' 2>&1"
assert "filing-justification: sub-resource number glued to >&2 is not a filing" "<none>" \
  "gh api -X POST -f 'labels[]=x' repos/jikig-ai/soleur/issues/123>&2"
assert "filing-justification: a redirect target named issues is not a filing" "<none>" \
  'gh api -X POST repos/jikig-ai/soleur/pulls/5/comments -f body=x >logs/issues'
assert "filing-justification: a backgrounded list beside a label POST is not a filing" "<none>" \
  'gh api repos/jikig-ai/soleur/issues --jq length & gh api -X POST repos/jikig-ai/soleur/issues/5/labels -f x=y'
# Perl unavailable: the fallback is a whole-command match that errs toward gating.
_nopl="$CM/no-perl"; mkdir -p "$_nopl"
printf '#!/bin/sh\nexit 127\n' > "$_nopl/perl"; chmod +x "$_nopl/perl"
_pl_got="$(PATH="$_nopl:$PATH" FS_ALLOW_LEXER_INCIDENT=1 decision_of 'gh api repos/jikig-ai/soleur/issues -X POST -f title=x -f body=y')"
TOTAL=$((TOTAL + 1))
if [[ "$_pl_got" == "deny" ]]; then
  PASS=$((PASS + 1)); echo "PASS: filing-justification: without perl the fallback still gates a create"
else
  FAIL=$((FAIL + 1)); echo "FAIL: filing-justification: without perl the fallback still gates a create"; echo "  want: deny  got: $_pl_got"
fi

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
FS_ALLOW_LEXER_INCIDENT=1 assert_reason "guard3: apostrophe inside --title (unbalanced, no heredoc) denies with the tokenizer message" \
  "$TOK_MSG" \
  "gh issue create --title 'its unbalanced --body b --label meta/machinery $MS"

# Mutation 2 pin: a whitespace-split fallback would read the --label inside
# this quoted --body as a real flag and reopen the bare-token escape.
FS_ALLOW_LEXER_INCIDENT=1 assert_reason "guard3: unbalanced quote + --label inside quoted --body denies (no whitespace-split fallback)" \
  "$TOK_MSG" \
  "gh issue create --title 'x --body \"x --label meta/machinery y\" $MS"

# Third member of the same class, found while fixing (a): the former xargs
# tokenizer could not carry a quoted token across a line, so a multi-line inline
# --body hid a --label AFTER it. The lexer (lib/filing-shape.pl, ADR-256) reads
# a quoted newline as part of the word; this row is the pin.
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
# body is not a filing (the lexer skips heredoc bodies that no command reads as
# a script). Pinned so a tokenizer change cannot regress it.
assert "guard3: gh issue create only inside a heredoc body is not a filing" "<none>" \
  $'cat > notes.md <<\'EOF\'\ngh issue create --title x --body y\nEOF'

# strip_heredocs blanks ONLY the heredoc body: quoted spans survive (the helper
# predates the filing lexer, which no longer calls it; pinned while it ships).
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
# #9089 — the filing gate LEXES the command (lib/filing-shape.pl, ADR-256).
# Row IDs are the plan's Test Scenarios IDs; lexing detail lives in
# lib/filing-shape.test.sh, spellings in lib/filing-shape-corpus.json. These
# rows pin VERDICTS and refusal TEXT. `[base-deny]` marks a row the base hook
# (4170460eea) already denied — excluded from the RED check (AC2).
# Every row here runs through decision_of's lexer-incident check, so a row
# that only passes because the lexer FAILED (and the floor caught it) reds.
# ---------------------------------------------------------------------------
EP=repos/jikig-ai/soleur/issues
J=' --milestone "Post-MVP / Later" --label meta/machinery'
K=' --milestone M --label meta/machinery'
IN_CMD="Its exit belongs to that same filing -- a flag on its own gh invocation, or a line in its own body -- not to another command on the line."

# Substitutions and runners
assert "D1 unquoted \$(…) create denies"            "deny" 'URL=$(gh issue create --title x --body y)'
assert_reason "D1 twin: names the filing and \$(…)"  'Refused filing: `gh issue create` inside $(…). '"$IN_CMD" 'URL=$(gh issue create --title x --body y)'
assert "D2 quoted \"\$(…)\" create denies"          "deny" 'URL="$(gh issue create --title x --body y)"'
assert "D3 api inside quoted \$(…) denies"          "deny" "N=\"\$(gh api $EP -X POST -f title=x -f body=y)\""
assert_reason "D3 twin: api spelling + ctx"         "-f labels[]=meta/machinery (the gh api spelling)" "N=\"\$(gh api $EP -X POST -f title=x -f body=y)\""
assert "D4 bash -c \"…\" denies"                    "deny" 'bash -c "gh issue create --title x --body y"'
assert_reason "D4 twin: inside a bash -c string"    'Refused filing: `gh issue create` inside a bash -c string' 'bash -c "gh issue create --title x --body y"'
assert "D5 sh -c '…' denies"                        "deny" "sh -c 'gh issue create --title x --body y'"
assert "D6 bash -lc cluster denies"                 "deny" "bash -lc 'gh issue create --title x --body y'"
assert "D7 backticks deny"                          "deny" 'echo `gh issue create --title x --body y`'
assert_reason "D7 twin: prose hint for backticks"   "If that text is prose rather than a command, quote it" 'echo `gh issue create --title x --body y`'
assert "D19 eval denies"                            "deny" 'eval "gh issue create --title x --body y"'
assert "D20 escaped \$( inside bash -c denies"      "deny" 'bash -c "URL=\$(gh issue create --title x --body y)"'
assert "D23 \$(…) inside \${:-} denies"             "deny" 'X="${Y:-$(gh issue create --title x --body y)}"'
assert "D31a bash -c -- denies"                     "deny" "bash -c -- 'gh issue create --title x --body y'"
assert "D31b bash --norc -c denies"                 "deny" "bash --norc -c 'gh issue create --title x --body y'"
assert "D31c sudo sh -c denies"                     "deny" "sudo sh -c 'gh issue create --title x --body y'"

# Quoted spellings and deliberate over-fire
assert "D8 quoted endpoint denies"                  "deny" "gh api \"$EP\" -X POST -f title=x -f body=y"
assert "D9 repos/\"\$REPO\"/issues denies"          "deny" 'gh api repos/"$REPO"/issues -X POST -f title=x'
assert "D10 single-quoted endpoint + quoted title denies" "deny" "gh api '$EP' -f \"title=a b\""
assert "D32a g\\h denies"                           "deny" 'g\h issue create --title x --body y'
assert "D32b g''h denies"                           "deny" "g''h issue create --title x --body y"
assert "D32c unquoted echo gh issue create over-fires (DC-2)" "deny" 'echo gh issue create --title x'
assert "D32d bash -c 'echo gh issue create' over-fires (DC-2)" "deny" "bash -c 'echo gh issue create'"

# Command positions
assert "D11 pipeline stage denies"                  "deny" 'printf x | gh issue create --title x --body-file -'
assert "D12 subshell denies"                        "deny" '( gh issue create --title x --body y )'
assert "D13 group denies"                           "deny" '{ gh issue create --title x --body y; }'
assert "D14 if/then denies"                         "deny" 'if true; then gh issue create --title x --body y; fi'
assert "D15 for/do denies"                          "deny" 'for i in 1; do gh issue create --title x --body y; done'
for _pre in 'sudo' 'sudo --' 'env A=1' 'env --' 'command' 'timeout -k 5 10' 'nohup' 'nice -5' 'setsid' \
            'flock /tmp/l' 'doppler run --' '/usr/bin/time -v' 'strace -f' 'xargs -r0'; do
  assert "D16 launcher '$_pre' denies" "deny" "$_pre gh issue create --title x --body y"
done
assert "D16 find -exec denies"                      "deny" 'find /dev/null -maxdepth 0 -exec gh issue create --title x --body y \;'
assert "D16 /usr/bin/gh denies"                     "deny" '/usr/bin/gh issue create --title x --body y'

# Subcommand forms
assert "D17 gh issue new denies"                    "deny" 'gh issue new --title x --body y'
assert "D18a gh issue -R … create denies"           "deny" 'gh issue -R jikig-ai/soleur create --title x --body y'
assert "D18b root --repo denies"                    "deny" 'gh --repo jikig-ai/soleur issue create --title x --body y'

# Heredocs
assert "D21 filing on the heredoc opener line denies" "deny" $'cat <<\'EOF\' > b.md && gh issue create --title x --body-file b.md\nbody\nEOF'
assert "D27a unquoted heredoc runs \$(…)"           "deny" $'cat <<EOF\n$(gh issue create --title x --body y)\nEOF'
assert "D27b two heredocs on one line"              "deny" $'cat <<A <<\'B\'\n$(gh issue create --title x --body y)\nA\nplain text\nB'

# Exits scoped per filing (Guard 2)
assert_reason "D24 another command's --repo is not this filing's" "must include --milestone" \
  'gh issue list --repo cli/cli && gh issue create --title x --body y'
assert_reason "D25 another command's --milestone is not this filing's" "must include --milestone" \
  'gh issue list --milestone x && gh issue create --title x --body y --label meta/machinery'
assert_reason "D26 another command's --label is not this filing's" "names no user-visible consequence" \
  "gh issue list --label meta/machinery && gh api $EP -X POST -f title=x"
assert_reason "D35 another command's body text is not this filing's corpus" "names no user-visible consequence" \
  'echo "User-Impact: docs page Fix-Size: 200 lines / 5 files"; bash -c "gh issue create --title x --body y --milestone M"'
assert_reason "D36 [base-deny] -mx as a --title value is not a milestone" "must include --milestone" \
  'gh issue create --title -mx --body y --label meta/machinery'
assert_reason "D37 --label=… as a --body value is not a label" "names no user-visible consequence" \
  'gh issue create --title x --body --label=meta/machinery --milestone M'
assert_reason "D38 a \$-valued --repo is never external" "must include --milestone" \
  'gh issue create --repo "$OWNER/soleur" --title x --body y'
assert "D40 bare \$EP endpoint denies"              "deny" 'EP=repos/jikig-ai/soleur/issues; gh api "$EP" -X POST -f title=x'

# POST spellings, multiple filings and parsing
assert "D28a [base-deny] -X=POST denies"            "deny" "gh api $EP -X=POST -f title=x"
assert "D28b [base-deny] -ftitle= denies"           "deny" "gh api $EP -ftitle=x"
assert "D28c [base-deny] --input= denies"           "deny" "gh api $EP --input=b.json"
assert "D28d -X \"\$M\" denies"                     "deny" "gh api $EP -X \"\$M\" -f body=y"
assert "D28e -iXPOST denies"                        "deny" "gh api $EP -iXPOST -f body=y"
assert "D28f -iftitle= denies"                      "deny" "gh api $EP -iftitle=x"
assert_reason "D44 bodyvar corpus is not another command's args" "names no user-visible consequence" \
  'echo "Mandated-By: wg-x" >/dev/null; gh issue create --title x --body "$B" -m M'
assert_reason "D45 find -exec: a later action's --label is not the filing's" "names no user-visible consequence" \
  'find /dev/null -maxdepth 0 -exec gh issue create --title x --body y -m M \; -exec echo --label meta/machinery \;'
assert_reason "D46 gh keeps the LAST --body" "names no user-visible consequence" \
  'gh issue create --title x --body "Mandated-By: wg-x" --body y -m M'
assert_reason "D47 api body=@file is a body file" "which this gate cannot read" \
  "gh api $EP -f title=x -F 'body=@/tmp/j Mandated-By: wg-x'"
assert_reason "D48a labels[]= in a create --title is not a label" "names no user-visible consequence" \
  "gh issue create --title 'labels[]=meta/machinery' --body y -m M"
assert_reason "D48b create -F labels[]= is a body file" "which this gate cannot read" \
  "gh issue create --title x -F 'labels[]=meta/machinery' -m M"
assert_reason "D48b twin: relative body file names the absolute-path hint" "Pass an absolute path" \
  "gh issue create --title x -F 'labels[]=meta/machinery' -m M"
assert_reason "D49a -R JIKIG-AI/soleur is ours"     "must include --milestone" 'gh issue create -R JIKIG-AI/soleur --title x --body y'
assert_reason "D49b -R github.com/… is ours"         "must include --milestone" 'gh issue create -R github.com/jikig-ai/soleur --title x --body y'
assert_reason "D49c -R https://github.com/… is ours" "must include --milestone" 'gh issue create -R https://github.com/jikig-ai/soleur --title x --body y'
assert "D50a repositories/<id>/issues denies"       "deny" 'gh api repositories/1143547205/issues -X POST -f title=x'
assert "D50b [base-deny] .. segment denies"                     "deny" 'gh api repos/jikig-ai/soleur/labels/../issues -X POST -f title=x'
assert "D50c \"\$B/issues\" denies"                 "deny" 'B=repos/jikig-ai/soleur; gh api "$B/issues" -X POST -f title=x'
assert "D51 bash -c -o posix denies"                "deny" "bash -c -o posix 'gh issue create --title x --body y'"
assert "D52a [base-deny] \$'\\'' ends where bash ends it"       "deny" "echo \$'\\''; gh issue create --title x --body y -m M # '"
assert "D52b \$\"\$(…)\" is live"                   "deny" 'echo $"$(gh issue create --title x --body y)"'
assert "D54 [base-deny] \$E-X POST inside \$(…) denies"         "deny" "X=\$(gh api $EP \$E-X POST -f body=y)"
assert_reason "D29 the SECOND filing is gated too"  'Refused filing: `gh issue create` inside a bash -c string' \
  "gh issue create --title a --body b$J; bash -c \"gh issue create --title x --body y\""
assert "D30 create && api: the api filing is gated" "deny" "gh issue create --title a --body b$J && gh api $EP -X POST -f title=x"
assert "D34 [base-deny] OK/RC as argument values"   "deny" 'gh issue create --title OK --body RC'
assert_reason "D43 | is a separator: tee's --label is not the filing's" "names no user-visible consequence" \
  'gh issue create --title x --body y --milestone M | tee --label meta/machinery'

# Must-PASS (PR3 prose, and justified filings in every new position)
_HOSTILE=$'fix: it\'s done, see 1) and an unclosed ( plus `code` and a literal $( and a " quote'
assert "P1 commit <<'EOF' inside \$(…)"  "<none>" $'git commit -m "$(cat <<\'EOF\'\n'"$_HOSTILE"$'\nEOF\n)"'
assert "P2 commit <<\"EOF\""             "<none>" $'git commit -m "$(cat <<"EOF"\n'"$_HOSTILE"$'\nEOF\n)"'
assert "P3 commit <<\\EOF"               "<none>" $'git commit -m "$(cat <<\\EOF\n'"$_HOSTILE"$'\nEOF\n)"'
assert "P4 commit <<-'EOF' tab terminator" "<none>" $'git commit -m "$(cat <<-\'EOF\'\n'"$_HOSTILE"$'\n\tEOF\n)"'
assert "P5 commit -F - body starts with a filing" "<none>" $'git commit -F - <<\'EOF\'\ngh issue create --title x --body y\nEOF'
assert "P6 heredoc body lines are data"  "<none>" $'git commit -m "$(cat <<\'EOF\'\ngh issue create --title x --body y\n$(gh issue create --title z)\nEOF\n)"'
assert "P7a single-quoted ; is prose"    "<none>" "echo 'done; gh issue create --title x --body y'"
assert "P7b double-quoted ; is prose"    "<none>" 'echo "a; gh issue create --title x"'
assert "P8 \${…} text is not a script"   "<none>" 'echo "${M:-a; gh issue create --title x}"'
assert "P9 a comment hides \$(…)"        "<none>" 'echo x # $(gh issue create --title x)'
assert "P10 --body \"\$BODY\" reads the heredoc variable corpus" "<none>" \
  $'BODY=$(cat <<\'EOF\'\nUser-Impact: the docs page\nFix-Size: 200 lines / 5 files\nEOF\n); gh issue create --title x --body "$BODY" --milestone "Post-MVP / Later"'
assert "P11 commit message mentions it"  "<none>" 'git commit -m "fix(hooks): don'"'"'t run gh issue create (#9089)"'
assert "P12a this PR's commit shape"     "<none>" 'git add -A x && git commit -F /var/tmp/msg.txt && git log --oneline -1'
assert "P12b this PR's pr-create shape"  "<none>" 'gh pr create --title "fix(hooks): the filing gate lexes gh issue create" --body-file /var/tmp/pr.md --draft'
assert "P13a quoted echo"                "<none>" 'echo "gh issue create --title x"'
assert "P13b grep pattern"               "<none>" 'grep -n "gh issue create" notes.md'
assert "P13c pr title"                   "<none>" 'gh pr create --title "gh issue create" --body x'
assert "P13d printf to a file"           "<none>" "printf '%s\n' 'gh issue create --title x' > notes.md"
assert "P14a justified filing inside \$(…)"   "<none>" "URL=\$(gh issue create --title x --body y$J)"
assert "P14b justified filing inside bash -c" "<none>" "bash -c \"gh issue create --title x --body y$K\""
assert "P15 literal external --repo"     "<none>" 'gh issue create --repo cli/cli --title x --body y'
assert "P16 [base-deny] -m short form"   "<none>" 'gh issue create -m "Post-MVP / Later" --title x --body y --label meta/machinery'
assert "P17 --jq program"                "<none>" $'gh issue list --json title --jq \'.[] | "it\'\\\'\'s"\''
assert "P18 list | xargs label"          "<none>" "gh api \"$EP?labels=x\" --jq '.[].number' | xargs -I{} gh api -X POST $EP/{}/labels -f 'labels[]=y'"
assert "P19 list-then-label loop"        "<none>" "for n in \$(gh api \"$EP?labels=x\" --jq '.[].number'); do gh api -X POST $EP/\$n/labels -f 'labels[]=y'; done"
assert "P20 {owner} GET"                 "<none>" 'gh api repos/{owner}/{repo}/issues --jq length'
assert "P21 two --label flags: the machinery one counts" "<none>" "gh issue create --title x --body y --label type/bug$J"

# ---------------------------------------------------------------------------
# Failure path (Guard 1 dispatch). Shims replace the LEXER in a sandbox copy of
# the hook tree — never `perl` on PATH, which would also blind $SCAN and the
# floor. Each shim touches a marker the row asserts, so a row cannot pass on a
# sandbox the hook did not actually use. Default command: `URL=$(gh issue
# create …)`, which the floor cannot see.
# ---------------------------------------------------------------------------
FS_SB="$(mktemp -d)"
cp -R -- "$SCRIPT_DIR/lib" "$FS_SB/lib"
cp -- "$HOOK" "$FS_SB/guardrails.sh"
chmod -R u+w "$FS_SB"
# fs_shim NAME RC PERL-PRINT-EXPR — install a lexer shim that consumes stdin,
# prints the given bytes and exits RC.
fs_shim() {
  local marker="$FS_SB/marker.$1"
  rm -f -- "$marker"
  printf '#!/usr/bin/env perl\nopen(my $m, ">", "%s"); close $m; local $/; my $in = <STDIN>; binmode STDOUT; print %s; exit %s;\n' \
    "$marker" "$3" "$2" > "$FS_SB/lib/filing-shape.pl"
  FS_MARKER="$marker"
}
# fs_row LABEL WANT CMD [ENV…] — decision through the sandbox hook, with the
# lexer-incident check waived (these rows EXIST to make the lexer fail), plus
# the marker assertion.
fs_row() {
  local label="$1" want="$2" cmd="$3"; shift 3
  local got
  got="$(HOOK="$FS_SB/guardrails.sh"; export FS_ALLOW_LEXER_INCIDENT=1; for _e in "$@"; do export "${_e?}"; done; decision_of "$cmd")"
  TOTAL=$((TOTAL + 1))
  if [[ "$got" == "$want" && -f "$FS_MARKER" ]]; then
    PASS=$((PASS + 1)); echo "PASS: $label → $got"
  else
    FAIL=$((FAIL + 1)); echo "FAIL: $label"; echo "  want: $want (shim ran)"; echo "  got:  $got (shim ran: $([[ -f "$FS_MARKER" ]] && echo yes || echo NO))"
  fi
}
SUB='URL=$(gh issue create --title x --body y)'
fs_shim exit2 2 '"E\0exit2\0"';                 fs_row "F-exit2 exit 2 on a \$(…) filing denies" "deny" "$SUB"
fs_shim exit3 3 '"E\0depth\0"';                 fs_row "F-exit3 exit 3 on a \$(…) filing asks" "ask" "$SUB"
fs_shim exit3k 3 '"E\0budget\0"';               fs_row "F-exit3 kill switch turns the ask into an allow" "<none>" "$SUB" SOLEUR_DISABLE_HOOK_INPUT_ASK=1
fs_shim exit3b 3 '"E\0alarm\0"';                fs_row "F-exit3-bare exit 3 on a bare create denies (floor)" "deny" 'gh issue create --title x --body y'
fs_shim nonfiling 2 '"E\0exit2\0"';             fs_row "F-nonfiling an exit-2 failure without the indicator allows" "<none>" 'echo hello world'
fs_shim nonfilingb 3 '"E\0depth\0"';           fs_row "F-nonfiling-bound a bound trip asks even without the indicator" "ask" 'echo hello world'
fs_shim trunc 0 '"F\0create\0top\0"';           fs_row "F-trunc a partial record asks" "ask" "$SUB"
fs_shim empty 0 '""';                           fs_row "F-empty no output at all asks" "ask" "$SUB"
fs_shim floor 0 '"OK\0"';                       fs_row "F-floor lexer says nothing, floor sees a bare create: deny" "deny" 'gh issue create --title x --body y'
fs_shim count2 0 '"F\0create\0top\0" . "3\0head=gh issue create\0milestone=1\0label=meta/machinery\0OK\0"'
fs_row "F-count2 one justified record vs two top-level creates: deny" "deny" 'gh issue create --title a -m M --label meta/machinery; gh issue create --title b'
fs_shim count 0 '"F\0create\0top\0" . "4\0head=gh issue create\0milestone=1\0label=meta/machinery\0OK\0" . "F\0create\0subst\0" . "1\0head=gh issue create\0OK\0"'
fs_row "F-count records parse by COUNT: a field reading OK does not end the stream" "deny" "$SUB"
# The unshimmed lexer on the no-perl rows is exercised above (PATH shim rows).
rm -rf "$FS_SB"

# F-exit3 records its cause in the incident, and nothing else (payload-free).
_ic_tmp="$(mktemp -d)"; _ic_sb="$(mktemp -d)"
cp -R -- "$SCRIPT_DIR/lib" "$_ic_sb/lib"; cp -- "$HOOK" "$_ic_sb/guardrails.sh"; chmod -R u+w "$_ic_sb"
printf '#!/usr/bin/env perl\nlocal $/; <STDIN>; print "E\\0depth\\0"; exit 3;\n' > "$_ic_sb/lib/filing-shape.pl"
(cd "$_ic_tmp" && mk_payload "$SUB" | INCIDENTS_REPO_ROOT="$_ic_tmp" bash "$_ic_sb/guardrails.sh" >/dev/null 2>&1)
_ic_line="$(grep -h '"guardrails-filing-lexer-failure"' "$_ic_tmp/.claude/.rule-incidents.jsonl" 2>/dev/null | head -1)"
TOTAL=$((TOTAL + 1))
if [[ "$(jq -r '.rule_text_prefix' <<<"$_ic_line" 2>/dev/null)" == "cause=depth" && "$(jq -r '.command_snippet' <<<"$_ic_line" 2>/dev/null)" == "" ]]; then
  PASS=$((PASS + 1)); echo "PASS: F-exit3 incident carries cause=depth and no command payload"
else
  FAIL=$((FAIL + 1)); echo "FAIL: F-exit3 incident carries cause=depth and no command payload"; echo "  got: ${_ic_line:-<no incident>}"
fi
rm -rf "$_ic_tmp" "$_ic_sb"

# F-noperl-sub: no perl at all and a filing the floor cannot see asks.
_pl_sub="$(PATH="$_nopl:$PATH" FS_ALLOW_LEXER_INCIDENT=1 decision_of "$SUB")"
TOTAL=$((TOTAL + 1))
if [[ "$_pl_sub" == "ask" ]]; then
  PASS=$((PASS + 1)); echo "PASS: F-noperl-sub without perl a \$(…) filing asks"
else
  FAIL=$((FAIL + 1)); echo "FAIL: F-noperl-sub without perl a \$(…) filing asks"; echo "  want: ask  got: $_pl_sub"
fi

# The real lexer's bounds, through the hook (AC6).
_deep='gh issue create --title x --body y'
for _ in $(seq 1 17); do _deep=": \$($_deep)"; done
FS_ALLOW_LEXER_INCIDENT=1 assert "D53 [base-deny] depth bound trips; the floor still denies a continued top-level api filing" "deny" \
  "$_deep; gh api \\"$'\n'"$EP -X POST -f title=x -f body=y"
_big="$(head -c 300000 /dev/zero | tr '\0' 'a')"
assert "AC6 a 300 KiB padded command ending in a bare create denies" "deny" "echo $_big; gh issue create --title x --body y"
_t0=$(date +%s%N)
_deep12='gh issue create --title x --body y'
for _ in $(seq 1 12); do _deep12="bash -c \"\$($_deep12)\""; done
_d12="$(decision_of "$_deep12")"
_ms=$(( ($(date +%s%N) - _t0) / 1000000 ))
TOTAL=$((TOTAL + 1))
if [[ "$_d12" == "deny" && "$_ms" -lt 8000 ]]; then
  PASS=$((PASS + 1)); echo "PASS: 12-deep bash -c \"\$(…)\" denies in ${_ms} ms (tripwire < 8000)"
else
  FAIL=$((FAIL + 1)); echo "FAIL: 12-deep bash -c \"\$(…)\" denies in < 8 s"; echo "  got: $_d12 in ${_ms} ms"
fi

# ---------------------------------------------------------------------------
# #9089 REVIEW ROUND — one row per reproduced finding (security, structural,
# quality, SAST, performance, agent-native seats). Each is a shape the first
# lexer let through or mis-gated.
# ---------------------------------------------------------------------------
# Grammar: bash's blanks, heredoc scope, arithmetic, case, funsubs, clusters.
assert "R-CR: \\r is a word character, so it cannot forge a milestone" "deny" \
  $'gh issue create --title x --label meta/machinery --body=x\r-mPost'
assert "R-FF: a form feed is a word character, not a 2 s stall" "<none>" $'echo a\fb'
assert "R-HDQ: a newline inside \$(…) does not drain an outer heredoc" "deny" \
  $'cat <<\'EOF\'; X="$(:\ngh issue create --title x --body y\nEOF\n)"\nEOF'
assert "R-ARITH: (( … << … )) is a shift, not a heredoc" "deny" \
  $'(( x = 1 << y ))\ntrue | gh issue create --title x --body y'
assert "R-ARITH2: the line after (( … << … )) is still lexed" "deny" \
  $'(( n = 1 << 2 ))\nbash -c \'gh issue create --title t --body b\''
assert "R-CASE: a case pattern ) does not close \$(…)" "deny" \
  'x="$(case $y in a|b) gh issue create --title t;; *) :;; esac)"'
assert "R-FUNSUB: \${ cmd; } is a script" "deny" 'X=${ gh issue create --title x --body y; }'
assert "R-OC: -oc takes its o's value before the script" "deny" \
  "bash -oc pipefail 'gh issue create --title x --body y'"
assert "R-ANSI: \$'…' is decoded, so \\n splits the eval string" "deny" \
  "eval \$'gh issue create --title x --body y -l meta/machinery \\n -m M'"
# Exits: every credit must come from the filing's own argv, as bash passes it.
assert_reason "R-BTDQ: \\\" inside backticks in \"…\" keeps --label inside the title" \
  "names no user-visible consequence" \
  'X="`gh issue create --title \"a --label meta/machinery \" --milestone M`"'
assert_reason "R-FIND: a later -exec cannot supply the filing's exits" "must include --milestone" \
  'find /dev/null -exec timeout 9 gh issue create --title x --body y \; -exec echo -m M -l meta/machinery \;'
assert_reason "R-SCP: git@github.com:jikig-ai/soleur is OUR repo" "must include --milestone" \
  'gh issue create -R git@github.com:jikig-ai/soleur --title t --body x'
assert_reason "R-EMPTYM: an empty --milestone value is not a milestone" "must include --milestone" \
  'gh issue create --title x --body y --milestone "" --label meta/machinery'
assert_reason "R-TRUE: substitution TEXT is not body corpus" "names no user-visible consequence" \
  'gh issue create --title x -m M --body "$(true Mandated-By: hr-foo)"'
assert_reason "R-RAWAT: -f body=@x sends @x literally, it is no body file" "names no user-visible consequence" \
  "gh api repos/jikig-ai/soleur/issues -f title=x -f 'body=@/tmp/soleur-no-such-body.md'"
# ... and the literal it sends IS the body: a Mandated-By: line in it is real.
assert "R-RAWAT2: the literal -f body=@… text is the corpus gh sends" "<none>" \
  "gh api repos/jikig-ai/soleur/issues -f title=x -f 'body=@/tmp/j Mandated-By: wg-x'"
assert_reason "R-COMMA: an api labels[]= value is one label, compared exactly" "names no user-visible consequence" \
  "gh api repos/jikig-ai/soleur/issues -X POST -f title=x -f 'labels[]=meta/machinery,x'"
assert_reason "R-VARPATH: a \$-valued --body-file names the expansion, not a relative path" "does not expand" \
  'gh issue create --title x --body-file "$F" --milestone M'
assert "R-DUP: two identical justified substitutions are two allowed filings" "<none>" \
  "a=\$(gh api repos/jikig-ai/soleur/issues -f title=x -f 'labels[]=meta/machinery'); b=\$(gh api repos/jikig-ai/soleur/issues -f title=x -f 'labels[]=meta/machinery')"
assert "R-PULLS: a \$-valued --jq on a pulls POST is not an issues endpoint" "<none>" \
  'gh api repos/jikig-ai/soleur/pulls -X POST -f title=x -f head=b -f base=main --jq "$Q"'
assert "R-DOTSEMI: a ..; segment is a dot segment" "deny" \
  "gh api 'repos/jikig-ai/soleur/labels/..;/issues' -X POST -f title=x"
# The body corpus agents actually use (agent-native F1: counted twice before).
assert "R-HDBODY: --body \"\$(cat <<'EOF' …)\" carrying exit 2 allows" "<none>" \
  $'gh issue create --title "Login flake" --milestone "Post-MVP / Later" --body "$(cat <<\'BODY\'\nLogin flakes.\nUser-Impact: login page flakes\nFix-Size: 300 lines / 5 files\nBODY\n)"'
assert "R-HDBODY-API: -f body=\"\$(cat <<'EOF' …)\" carrying exit 2 allows" "<none>" \
  $'gh api repos/jikig-ai/soleur/issues -f title=x -f body="$(cat <<\'EOF\'\nUser-Impact: the login page\nFix-Size: 300 lines / 5 files\nEOF\n)"'
assert "R-READ: read … B <<EOF binds the heredoc to \$B" "<none>" \
  $'read -r -d \'\' B <<\'EOF\'\nUser-Impact: the docs page\nFix-Size: 200 lines / 5 files\nEOF\ngh issue create --title x --body "$B" -m M'
assert "R-BT-OK: a justified filing in backticks allows" "<none>" "echo \`gh issue create --title x --body y$K\`"
assert "R-EVAL-OK: a justified filing in an eval string allows" "<none>" "eval \"gh issue create --title x --body y$K\""
# The floor counts only what it can see: a decoy in quotes cannot cancel it.
FS_ALLOW_LEXER_INCIDENT=1 assert "R-DECOY: a quoted decoy cannot offset a real top-level filing" "deny" \
  $'false && : "$(gh issue create --title t -m M -l meta/machinery)"\ngh issue create --title x --body y'
FS_ALLOW_LEXER_INCIDENT=1 assert_reason "R-FLOORMSG: a comment the old detector reads names that detector" \
  "older filing detector" 'git log --oneline -1 # ; gh issue create'
# A forced lexer failure plus a split word still reaches the indicator.
_deep17='gh issue c'"''"'reate --title x --body y'
for _ in $(seq 1 17); do _deep17=": \$($_deep17)"; done
FS_ALLOW_LEXER_INCIDENT=1 assert "R-SPLIT: a bound trip + c''reate is not an allow" "ask" "$_deep17"
# A computed word only the lexer decodes, plus a bound trip, is not an allow
# either: a defeated lexer asks unconditionally (ship advisor, PR #9099).
_nest17='true'
for _ in $(seq 1 17); do _nest17=": \$($_nest17)"; done
FS_ALLOW_LEXER_INCIDENT=1 assert "R-ANSIBOUND: \$'\\x69ssue' + a bound trip asks" "ask" \
  "gh \$'\\x69ssue' create --title x --body-file /tmp/b; $_nest17"
FS_ALLOW_LEXER_INCIDENT=1 assert "R-EMPTYEXP: is\$(:)sue + a bound trip asks" "ask" \
  "gh is\$(:)sue create --title x --body-file /tmp/b; $_nest17"
FS_ALLOW_LEXER_INCIDENT=1 assert "R-BOUNDANY: a bound trip with no filing word still asks" "ask" "$_nest17"
_padapi="$(printf '/repos/%.0s' $(seq 1 10000))"
assert "R-PAD: 60 KB of /repos/ padding does not stall the lexer past a \$EP filing" "deny" \
  "gh api -H \"X-Pad: ${_padapi}!\" \"\$EP\" -X POST -f title=x"
# The stash guard runs before the filing gate's ask.
assert_reason "R-STASH: git stash is denied even where the filing gate would ask" "git stash is not allowed" \
  "git stash; $_deep17"
# decision_of's lexer-incident check can fire (its positive control).
_pc_sb="$(mktemp -d)"
cp -R -- "$SCRIPT_DIR/lib" "$_pc_sb/lib"; cp -- "$HOOK" "$_pc_sb/guardrails.sh"; chmod -R u+w "$_pc_sb"
printf '#!/usr/bin/env perl\nlocal $/; <STDIN>; print "E\\0exit2\\0"; exit 2;\n' > "$_pc_sb/lib/filing-shape.pl"
_pc_got="$(HOOK="$_pc_sb/guardrails.sh"; decision_of 'URL=$(gh issue create --title x --body y)')"
TOTAL=$((TOTAL + 1))
if [[ "$_pc_got" == "<lexer-failure-incident>" ]]; then
  PASS=$((PASS + 1)); echo "PASS: decision_of reds a row whose lexer failed (positive control)"
else
  FAIL=$((FAIL + 1)); echo "FAIL: decision_of reds a row whose lexer failed (positive control)"; echo "  got: $_pc_got"
fi
rm -rf "$_pc_sb"

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
# Floor tracks the CURRENT count (127), not the pre-PR one. It sat at 106+17=123
# while the suite ran 127, so the four config rows this PR adds had zero cover:
# deleting all four left 123/123 green, exactly at the floor. Slack in a floor is
# attack budget, not padding — bump it in the same commit that adds rows.
# 127 + 33 CLASS 4 endpoint-scope rows (sub-resource allows, collection denies,
# newly read POST spellings, segment scoping) = 160, + 33 review-round rows (one
# per terminator/POST-signal/splitter member, redirects, $(...), --input, the
# api refusal spellings, gh issue create -F, the perl-absent fallback) = 195.
# + 128 #9089 lexer rows (the D/P verdict rows and their refusal twins, 11
# failure-path shim rows, the incident-payload row, F-noperl-sub, D53, the
# 300 KiB row and the 12-deep tripwire) = 323, + 32 review-round rows (one
# per reproduced finding, the R-RAWAT2 counter-row, and decision_of's
# positive control) = 355.
MIN_ASSERTIONS=359
if [[ "$TOTAL" -lt "$MIN_ASSERTIONS" ]]; then
  printf 'FLOOR: only %s assertions ran, expected at least %s. A suite that\n' "$TOTAL" "$MIN_ASSERTIONS" >&2
  printf 'asserts nothing exits 0 and reads as a pass -- refusing to report one.\n' >&2
  exit 1
fi

echo
echo "Total: $TOTAL  Pass: $PASS  Fail: $FAIL"
[[ $FAIL -eq 0 ]] || exit 1
