#!/usr/bin/env bash

# Tests for plugins/soleur/skills/schedule/SKILL.md --once flag.
# Run: bash plugins/soleur/test/schedule-skill-once.test.sh
#
# These are content-assertion tests. They catch deletion of load-bearing
# defenses, NOT semantic drift. The post-merge dogfood (TS-dogfood in the plan)
# is the real regression test for end-to-end behavior.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"

REPO_ROOT="$SCRIPT_DIR/../../.."
SKILL_FILE="$REPO_ROOT/plugins/soleur/skills/schedule/SKILL.md"

echo "=== schedule --once SKILL.md content tests ==="
echo ""

assert_file_exists "$SKILL_FILE" "SKILL.md exists"

SKILL_CONTENT="$(cat "$SKILL_FILE")"

# Extract the one-time YAML template block. SKILL.md frames the canonical
# template with HTML comment markers `<!-- once-template-begin -->` and
# `<!-- once-template-end -->`. Anchoring on these markers is more robust
# than "first yaml fence containing FIRE_DATE" — that heuristic silently
# picks the wrong block if SKILL.md ever adds another fence with FIRE_DATE
# (e.g., a doc example, a before/after snippet).
ONCE_BLOCK="$(awk '
  /<!-- once-template-begin -->/ { in_section=1; next }
  /<!-- once-template-end -->/ { in_section=0; next }
  in_section && /^```yaml$/ { in_yaml=1; next }
  in_section && /^```$/ && in_yaml { in_yaml=0; next }
  in_section && in_yaml { print }
' "$SKILL_FILE")"

if [[ -z "$ONCE_BLOCK" ]]; then
  echo "  FAIL: could not find one-time YAML template block (HTML markers <!-- once-template-begin --> / <!-- once-template-end --> missing or empty)"
  FAIL=$((FAIL + 1))
  # Continue running TS1-TS5 against an empty block; cascading failures make
  # the missing-block diagnosis explicit rather than masking it with a bail.
fi

# --- TS1: Token-revocation regression guard (rewritten for neutralization primitive, #3153) ---
# The neutralization (D4 cleanup) MUST be inside the agent prompt — claude-code-action
# revokes the App token after its step, so any post-step would silently fail.
# The previous mechanism `gh workflow disable` was replaced by a YAML-edit-and-push
# primitive because the App's installation token caps actions:* at READ; the
# replacement leans on contents:write (App reliably honors) plus pull-requests:write
# for the branch-protected fallback.
echo "TS1: neutralization primitive is inside agent prompt (token-revocation regression guard)"

assert_contains "$ONCE_BLOCK" "Neutralization primitive" \
  "one-time template references the Neutralization primitive section"

assert_contains "$ONCE_BLOCK" "Final step" \
  "one-time template labels neutralization as the Final step inside the prompt"

assert_contains "$ONCE_BLOCK" "git push origin HEAD:" \
  "neutralization primitive uses direct git push as the canonical leg"

assert_contains "$ONCE_BLOCK" "gh pr create --base" \
  "neutralization primitive includes a PR-create fallback leg"

assert_contains "$ONCE_BLOCK" "git diff --cached --quiet" \
  "neutralization primitive guards against silent no-op commits (per 2026-03-02 learning)"

# claude-code-action@v1 does NOT pre-configure git user.name/user.email inside
# its bash subprocess. Without an explicit git config step, `git commit` aborts
# with "Author identity unknown" and the entire D4 path silently fails — which
# is exactly the regression #3153 set out to fix. All sibling Soleur workflows
# that push inside claude-code-action use this canonical pattern.
assert_contains "$ONCE_BLOCK" 'git config user.name "github-actions[bot]"' \
  "neutralization primitive sets git user.name (otherwise commit aborts at fire time)"

assert_contains "$ONCE_BLOCK" 'git config user.email "41898282+github-actions[bot]@users.noreply.github.com"' \
  "neutralization primitive sets git user.email"

# Anti-regression: PR-fallback must check for an existing open neutralization
# PR before opening a new one. Otherwise N fires on a branch-protected repo
# without auto-merge produce N stale PRs.
assert_contains "$ONCE_BLOCK" 'gh pr list --search "head:chore/neutralize-$WORKFLOW_NAME"' \
  "PR-fallback checks for stale open neutralization PR before opening a duplicate"

# Anti-regression: the operative `gh workflow disable "$WORKFLOW_NAME"` line
# must NOT appear as an executable command in the prompt. Comments referencing
# the previous mechanism are acceptable; line-anchored shell calls are not.
DISABLE_LINE_HITS=$(printf '%s\n' "$ONCE_BLOCK" | grep -cE '^[[:space:]]*gh workflow disable "\$WORKFLOW_NAME"' || true)
assert_eq "0" "${DISABLE_LINE_HITS:-0}" \
  "no executable 'gh workflow disable \"\$WORKFLOW_NAME\"' line (App token does not honor actions:write — #3153)"

# Verify no post-step appears after the claude-code-action step. Step entries
# at this level are indented exactly 6 spaces ("      - "). Sub-keys (env:,
# with:, prompt:) and prompt-body lines are indented deeper, so they do not
# match this pattern.
POST_STEP_COUNT=$(printf '%s\n' "$ONCE_BLOCK" | awk '
  /^        uses: anthropics\/claude-code-action/ { found=1; next }
  found && /^      - / { count++ }
  END { print count+0 }
')
assert_eq "0" "$POST_STEP_COUNT" \
  "no step appears after claude-code-action (a post-step would defeat self-neutralization)"

echo ""

# --- TS2: Date guard is FIRST agent-prompt step (D3, primary cross-year defense) ---
echo "TS2: date guard [[ \"\$(date -u +%F)\" == \"\$FIRE_DATE\" ]] is FIRST agent-prompt step"

assert_contains "$ONCE_BLOCK" '[[ "$(date -u +%F)" == "$FIRE_DATE" ]]' \
  "literal date guard line present in one-time template"

# Date guard line must appear BEFORE the Final step (neutralization invocation)
# inside the block. Anchoring on "## Final step" — the heading marking D4 — is
# more robust than grepping for a specific shell command.
DATE_GUARD_LINE=$( { printf '%s\n' "$ONCE_BLOCK" | grep -nF '[[ "$(date -u +%F)" == "$FIRE_DATE" ]]' || true; } | head -1 | cut -d: -f1)
FINAL_STEP_LINE=$( { printf '%s\n' "$ONCE_BLOCK" | grep -nE '^[[:space:]]*## Final step' || true; } | tail -1 | cut -d: -f1)

if [[ -n "$DATE_GUARD_LINE" && -n "$FINAL_STEP_LINE" && "$DATE_GUARD_LINE" -lt "$FINAL_STEP_LINE" ]]; then
  echo "  PASS: date guard appears before Final step (FIRST vs LAST ordering)"
  PASS=$((PASS + 1))
else
  echo "  FAIL: date guard line ($DATE_GUARD_LINE) must precede Final step heading ($FINAL_STEP_LINE)"
  FAIL=$((FAIL + 1))
fi
echo ""

# --- TS3: Stale-context preamble (D2) ---
# Each assertion anchors on the OPERATIVE line shape (the actual gh command or
# the actual shell condition), not just a stray token. A reviewer can't satisfy
# these by leaving the word "OPEN" in a comment after deleting the real check.
echo "TS3: stale-context preamble (issue OPEN, same repo, comment matches issue, observation on failure)"

assert_contains "$ONCE_BLOCK" 'gh issue view "$ISSUE_NUMBER" --json state,repository_url' \
  "preamble fetches issue state and repository_url via gh issue view"

assert_contains "$ONCE_BLOCK" 'must be OPEN' \
  "preamble asserts issue state must be OPEN"

assert_contains "$ONCE_BLOCK" 'isArchived' \
  "preamble checks repo is not archived"

# Idempotency check rewired in #3153 — was a `gh workflow view ... --state`
# probe, now checks the workflow file's `on:` block for `schedule:` (since the
# neutralization primitive STRIPS the schedule trigger; the workflow stays
# `active` but has no cron after a successful neutralization).
assert_contains "$ONCE_BLOCK" 'already neutralized' \
  "preamble runs idempotency check (on: block no longer contains schedule:)"

assert_contains "$ONCE_BLOCK" 'gh api "repos/${{ github.repository }}/issues/comments/$COMMENT_ID" --jq .issue_url' \
  "preamble fetches comment.issue_url with quoted COMMENT_ID"

assert_contains "$ONCE_BLOCK" 'observation comment' \
  "preamble posts observation comment on pre-flight failure"

echo ""

# --- TS5: D5 comment-author-pin + input-validation regex regression guard ---
# These assertions catch the highest-blast-radius regressions that TS1-TS4
# don't cover: deleting the D5 comment-pin defense, deleting input regex
# validators (re-opening shell injection), or widening --allowedTools.
echo "TS5: D5 comment-author-pin and input-validation defenses present"

# D5 author-pin and immutability — assert the equality checks (which subsume
# the env-var-name presence checks: a check referencing $EXPECTED_AUTHOR must
# imply the env var exists).
assert_contains "$ONCE_BLOCK" '"$actual_author" == "$EXPECTED_AUTHOR"' \
  "preamble asserts comment author equals EXPECTED_AUTHOR (D5 author-pin)"

assert_contains "$ONCE_BLOCK" 'created_at == updated_at' \
  "preamble asserts comment unedited (D5 immutability pin)"

assert_contains "$ONCE_BLOCK" 'EXPECTED_CREATED_AT' \
  "EXPECTED_CREATED_AT env var present in template"

# Tool-surface allowlist (regression vs recurring template)
assert_contains "$ONCE_BLOCK" '--allowedTools Bash,Read,Write,Edit,Glob,Grep' \
  "claude_args includes least-privilege --allowedTools allowlist"

# id-token: write is required by anthropics/claude-code-action@v1 OIDC
# handshake — without it the action exits before the agent prompt runs (issue
# #3134). Guard against the comment from the recurring-template precedent
# accidentally being copy-pasted back in.
assert_contains "$ONCE_BLOCK" 'id-token: write' \
  "id-token: write present in --once permissions block (claude-code-action OIDC requirement, #3134)"

# Input regex validators (load-bearing against shell/YAML injection)
assert_contains "$SKILL_CONTENT" '^[1-9][0-9]{0,8}$' \
  "Step 0c specifies --issue regex validator"

assert_contains "$SKILL_CONTENT" '^[1-9][0-9]{0,18}$' \
  "Step 0c specifies --comment regex validator"

assert_contains "$SKILL_CONTENT" '^[a-z][a-z0-9-]{0,49}$' \
  "Step 0c specifies --name regex validator"

assert_contains "$SKILL_CONTENT" '^\d{4}-\d{2}-\d{2}$' \
  "Step 0c specifies --at strict ISO regex validator"

# FIRE_DATE non-empty / format guard inside the prompt
assert_contains "$ONCE_BLOCK" '"$FIRE_DATE" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$' \
  "preamble guards against empty/malformed FIRE_DATE before equality check"

echo ""

# --- TS4: Disambiguation section (namespace conflation regression) ---
echo "TS4: disambiguation section present with examples for both skills"

assert_contains "$SKILL_CONTENT" "When to use this skill vs harness" \
  "disambiguation section header present"

# Count example bullets under each skill's examples block. We accept any line
# starting with "- " between an "Examples for ..." marker and the next "## "
# heading or "Examples for" marker.
SOLEUR_EXAMPLES=$(awk '
  /Examples for `soleur:schedule`/ { in_block=1; count=0; next }
  in_block && /^- / { count++ }
  in_block && /Examples for `harness/ { print count; exit }
  in_block && /^## / { print count; exit }
  END { if (in_block) print count }
' "$SKILL_FILE" | head -1)

HARNESS_EXAMPLES=$(awk '
  /Examples for `harness/ { in_block=1; count=0; next }
  in_block && /^- / { count++ }
  in_block && /^## / { print count; exit }
  END { if (in_block) print count }
' "$SKILL_FILE" | head -1)

SOLEUR_EXAMPLES=${SOLEUR_EXAMPLES:-0}
HARNESS_EXAMPLES=${HARNESS_EXAMPLES:-0}

if [[ "$SOLEUR_EXAMPLES" -ge 2 ]]; then
  echo "  PASS: at least 2 examples for soleur:schedule ($SOLEUR_EXAMPLES found)"
  PASS=$((PASS + 1))
else
  echo "  FAIL: need >=2 examples for soleur:schedule, found $SOLEUR_EXAMPLES"
  FAIL=$((FAIL + 1))
fi

if [[ "$HARNESS_EXAMPLES" -ge 2 ]]; then
  echo "  PASS: at least 2 examples for harness schedule ($HARNESS_EXAMPLES found)"
  PASS=$((PASS + 1))
else
  echo "  FAIL: need >=2 examples for harness schedule, found $HARNESS_EXAMPLES"
  FAIL=$((FAIL + 1))
fi

echo ""

# --- TS6: Fallback-comment conditional structure (#3153) ---
# The neutralization primitive's fallback comment must fire ONLY when BOTH the
# direct push leg AND the PR-create leg fail. A future "simplification" that
# always posts the fallback comment is a regression — every successful --once
# fire would post user-visible cleanup-failed noise.
echo "TS6: fallback comment is conditional on both push AND PR-create failing"

# The new fallback-comment text MUST replace the previous "auto-disable failed"
# wording — leaving the old wording in place would suggest the previous
# mechanism is still operative.
assert_contains "$ONCE_BLOCK" "auto-cleanup failed" \
  "fallback comment uses new 'auto-cleanup failed' wording (was 'auto-disable failed')"

# Anti-regression: previous wording must be gone.
OLD_WORDING_HITS=$(printf '%s\n' "$ONCE_BLOCK" | grep -cF 'auto-disable failed' || true)
assert_eq "0" "${OLD_WORDING_HITS:-0}" \
  "previous 'auto-disable failed' wording removed from one-time template"

# Conditional gating: the prompt must explicitly say BOTH legs must fail before
# posting the comment. Match a sentence near the fallback wording that gates on
# "both" or "5a ... AND ... 5b" or similar.
if printf '%s\n' "$ONCE_BLOCK" | grep -iE '(both[^.]*fail|5a[^.]*5b|direct push[^.]*AND[^.]*PR)' >/dev/null; then
  echo "  PASS: fallback comment is gated on both push and PR-create failing"
  PASS=$((PASS + 1))
else
  echo "  FAIL: prompt does not explicitly gate fallback comment on BOTH legs failing"
  FAIL=$((FAIL + 1))
fi

echo ""

# --- TS7: Permissions block reflects new neutralization mechanism (#3153) ---
echo "TS7: permissions block has contents:write + pull-requests:write, no actions:write"

assert_contains "$ONCE_BLOCK" 'contents: write' \
  "contents: write present (D4 neutralization commit)"

assert_contains "$ONCE_BLOCK" 'pull-requests: write' \
  "pull-requests: write present (D4 PR-fallback)"

# Anti-regression: actions: write must NOT be in the permissions block. The
# Anthropic GitHub App's installation manifest caps actions:* at READ; declaring
# it gave maintainers false confidence that gh workflow disable would work.
ACTIONS_WRITE_HITS=$(printf '%s\n' "$ONCE_BLOCK" | grep -cE '^[[:space:]]+actions:[[:space:]]+write' || true)
assert_eq "0" "${ACTIONS_WRITE_HITS:-0}" \
  "actions: write is NOT in --once permissions block (App token does not honor it — #3153)"

echo ""

print_results
