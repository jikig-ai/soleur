---
name: one-shot
description: "This skill should be used when running the full autonomous engineering workflow from plan to merged PR."
---

Run these steps in order. Do not do anything else.

<decision_gate>
**API budget.** This skill runs the full autonomous engineering pipeline: plan → work → review → resolve-pr-parallel → ship. Typical wall-clock 30–90 min; per-run Anthropic credit cost is non-trivial and scales with plan complexity, review-cycle count, and PR comment volume. The pipeline runs autonomously once Step 0a/0a.5 collision checks pass — there are no per-phase approval gates after that. Soleur does not bill or proxy these calls — Anthropic does, against the key in your session. The Soleur LICENSE (BSL 1.1) disclaims warranty for runtime cost; you operate this loop against your own budget.

If running against a tight budget, run `/soleur:plan` instead and review the plan before invoking `/soleur:work` separately.
</decision_gate>

**Step 0a: Linear context preflight.** Before creating the worktree, scan `$ARGUMENTS` for substrings matching `[A-Z]{2,}-[0-9]+` or `linear\.app/[^/]+/issue/`. If any match:

1. Use the **Skill tool**: `skill: soleur:linear-fetch`, args: "$ARGUMENTS". The skill returns two artifacts: `agent_context` (markdown blob + image content blocks, streamed into THIS parent conversation only) and `persist_safe_summary` (the same text with every `uploads.linear.app/*` URL redacted to `[linear-image: REDACTED]`).
2. For the remainder of this skill, **substitute `persist_safe_summary` for `$ARGUMENTS` whenever the value is passed to a Task subagent or to a child skill invocation** (e.g., the subagent prompt template's `ARGUMENTS:` line at the top of Steps 1-2, the subagent's `args: "$ARGUMENTS"` for `skill: soleur:plan`, and the fallback inline `args: "$ARGUMENTS"`). Do NOT pass `agent_context` or any Linear image URL into a subagent prompt — Task subagents inherit prompt text only (`knowledge-base/project/learnings/best-practices/2026-05-12-task-subagent-prompt-text-only.md`); the parent retains the images for Steps 3-8 (work, review, ship). The original `$ARGUMENTS` placeholder remains the slugification source at Step 0b's worktree-name construction; only downstream prompt construction substitutes.

If no Linear references match, this step is a no-op and `$ARGUMENTS` flows through unchanged.

**Step 0a.5: Open-issue collision check.** Before creating the worktree, scan `$ARGUMENTS` for substrings matching `#[0-9]+` (zero or more GitHub issue references). For each distinct match `#<N>`:

1. Run `gh issue view <N> --json state,closedByPullRequestsReferences --jq '{state, closed_by: [.closedByPullRequestsReferences[] | select(.isCrossRepository | not) | .number]}'`. If `gh` exits non-zero (no auth, network failure, issue not found in this repo), warn once on stderr (`WARNING: gh issue view #<N> failed; skipping collision check for this ref`) and continue without aborting — fail open so an infrastructure flake does not silently kill a legitimate run.

2. **If `state == "CLOSED"`:** ABORT one-shot immediately with: `Issue #<N> is already closed (closed by PR #<closed_by[0]> if present). Aborting to avoid duplicate work — the issue's resolution is already in main. If you intend to do follow-on work, pass a plan file path or freeform description instead of #<N>, or re-open the issue first.` This abort fires in BOTH headless and interactive modes — closed-issue is an unambiguous "this work is done" signal and continuing wastes a full plan→work→review→ship cycle. Do NOT create the worktree, do NOT create the draft PR.

3. **If `state == "OPEN"`:** also run `gh pr list --search "linked:issue #<N>" --state open --json number,title --jq '.[] | "  #\(.number): \(.title)"'`. If any PRs are returned, surface a multi-line stderr warning naming each, then continue. In **interactive mode**, additionally pause via AskUserQuestion offering (a) continue (operator accepts collision risk — they may be racing intentionally or producing alternate designs), (b) abort (preferred when the listed PR is clearly the same scope). In **headless mode**, log the warning and continue — the operator will see it in the run log.

If `$ARGUMENTS` contains no `#N` substrings (e.g., a plan file path or freeform description), this step is a no-op.

**Why this gate exists.** The pipeline can run for 30-90 minutes between Step 0b worktree creation and Phase 6.5 mergeability check. In that window, a parallel session OR a manually-merged PR can resolve the same issue, producing a duplicate-implementation PR that has to be closed during ship. The 2026-05-12 `/one-shot #3684` session hit this exact failure mode: PR #3697 had merged + closed #3684 ~90 minutes earlier, but one-shot ran the full pipeline anyway and produced PR #3699 (closed at Phase 6.5 when the conflict-resolution diff surfaced parallel `lint-agents-rule-budget.{sh,py}` implementations). The check is cheap (≤2 `gh` calls per issue ref) and runs before the worktree exists, so the abort path costs nothing. It does NOT prevent the rarer "issue closed mid-flow" case — that would require a global lock; out of scope here.

**Step 0b: Ensure branch isolation.** Check the current branch with `git branch --show-current`. If on the default branch (main or master), create a worktree for the feature branch. Do NOT use `git pull` or `git checkout -b` -- both fail on bare repos (`core.bare=true`).

```bash
SOLEUR_SKILL_NAME=one-shot SOLEUR_EXPECTED_DURATION_MIN=240 \
  bash ./plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh --yes create feat-one-shot-<slugified-arguments>
```

Then `cd` into the worktree path printed by the script. Parallel agents on the same repo cause silent merge conflicts when both work on main.

The `SOLEUR_SKILL_NAME` + `SOLEUR_EXPECTED_DURATION_MIN` env wire a lease on this worktree (see `.claude/hooks/lib/session-state.sh`). A sibling session's `cleanup-merged` invocation refuses to reap any worktree with an active lease. Release on clean exit:

```bash
bash .claude/hooks/lib/session-state.sh release_lease "$(basename "$PWD")"
```

**Step 0c: Create draft PR.** After creating the feature branch, create a draft PR from inside the worktree (the script errors with "Cannot run from bare repo root" otherwise, and the Bash tool does NOT persist CWD across calls — use a single `cd && bash` to be explicit):

```bash
cd <worktree-path> && bash ./plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh draft-pr
```

If this fails (no network, or "No commits between main and <branch>"), print a warning but continue. The branch exists locally and the `/ship` phase will create the PR after implementation commits exist.

**Steps 1-2: Plan + Deepen (Isolated Subagent)**

Spawn a Task general-purpose subagent to run plan and deepen-plan. This creates a compaction boundary -- the subagent's context is discarded after it returns, freeing headroom for implementation.

```text
Task general-purpose: "You are running the planning phase of a one-shot pipeline.

WORKING DIRECTORY: [insert pwd output]
BRANCH: [insert current branch name]
ARGUMENTS: $ARGUMENTS

STEPS:
0. **CWD verification (first tool call):** run `cd <WORKING_DIRECTORY> && pwd`. The output MUST equal the WORKING DIRECTORY value above. If it does not, abort and return an error in the Session Summary — do NOT proceed; the plan will land in the bare-root synced mirror (gets clobbered on next sync) instead of the worktree. Bash CWD is per-agent and does NOT inherit from the parent's persistent `cd`.
1. Use the Skill tool: skill: soleur:plan, args: "$ARGUMENTS"
2. After plan is created, use the Skill tool: skill: soleur:deepen-plan, args: "<plan_file_path>"

RETURN CONTRACT:
When both steps are done, output a summary in this exact format:

## Session Summary

### Plan File
<absolute path to the plan .md file>

### Errors
<list any errors encountered during planning, or 'None'>

### Decisions
<key decisions made during planning, 3-5 bullet points>

### Components Invoked
<list of commands/skills/agents invoked>

Do NOT proceed beyond deepen-plan. Do NOT start work.

CRITICAL: You MUST output the ## Session Summary section in EXACTLY the format above. Place it as the last thing in your output."
```

**Parse subagent output and write session-state.md:**

After the subagent returns, **verify the subagent stayed in scope**: run `git diff origin/main...HEAD --name-only` and confirm only files under `knowledge-base/project/{plans,specs}/` were modified. If files outside that prefix were touched (workflow YAML, source code, CHANGELOG, etc.), the subagent exceeded its plan-only mandate — the Session Summary's "Decisions" became statements of intent rather than fact. Read each out-of-scope file from disk and reconcile against the plan's claims before trusting Step 3 onward; do NOT trust the Session Summary's reconciliation narrative ("Adopted the on-disk output text", "Already applied as uncommitted local changes") without verifying via `git diff <file>` first. **Why:** #3937 — plan-deepen subagent committed source-code edits AND its Session Summary claimed on-disk text it had not actually written (`pre-recorded` vs prescribed `not applicable`), costing two reconciliation commits. See [[2026-05-17-planning-subagent-exceeded-scope-and-summary-vs-disk-drift]].

After the subagent returns, check for a `## Session Summary` heading in the output.

**If present (success):**

1. Extract the plan file path from `### Plan File`
2. Detect the feature branch: run `git branch --show-current`. Use the **full, exact** branch name (including workflow prefixes like `feat-one-shot-`, `feat-fix-`) — do NOT abbreviate. The plan subagent already wrote `tasks.md` to `knowledge-base/project/specs/<exact-branch-name>/`, so session-state.md must go in the same directory to avoid sibling-dir collisions.
3. Write the parsed content to `knowledge-base/project/specs/<exact-branch-name>/session-state.md` (create if needed):

```markdown
# Session State

## Plan Phase
- Plan file: <path from subagent>
- Status: complete

### Errors
<errors from subagent output>

### Decisions
<decisions from subagent output>

### Components Invoked
<components from subagent output>
```

4. Continue to step 3 using the extracted plan file path.

**If absent or subagent failed (fallback):**

1. **Partial-artifact recovery check.** Before re-running plan inline, look for artifacts the crashed subagent may have written: `ls "knowledge-base/project/plans/$(date -u +%Y-%m-%d)-"*.md 2>/dev/null` and `ls "knowledge-base/project/specs/$(git branch --show-current)/tasks.md" 2>/dev/null`. If a plan file exists with frontmatter + Overview + Acceptance Criteria sections, the subagent completed plan generation before crashing (only the Session Summary emission failed). Load it and continue from `/soleur:plan-review` rather than re-running `/soleur:plan` from scratch. Note in session-state.md: `Status: recovered from partial-artifact (subagent crashed mid-Session-Summary; plan body was on disk).` See `knowledge-base/project/learnings/2026-05-15-subagent-crash-recovery-via-on-disk-artifacts.md`.
2. Write to session-state.md: `## Plan Phase\n- Status: fallback (subagent failed)\n` (or `recovered from partial-artifact` per step 1).
3. If no partial artifact was found, use the **Skill tool**: `skill: soleur:plan`, args: "$ARGUMENTS" and then `skill: soleur:deepen-plan` inline (no compaction benefit, but pipeline continues).
4. Continue to step 3.

**Steps 3-8: Implementation, Review, and Ship**

3. Use the **Skill tool**: `skill: soleur:work`, args: "<plan_file_path>". Work handles implementation only (Phases 0-3). It does NOT invoke ship -- one-shot controls the full lifecycle below.

> **CONTINUATION GATE**: When work outputs `## Work Phase Complete`, that is your signal to continue. Do NOT end your turn. Do NOT treat "Implementation complete" or similar phrases as a stopping point. Immediately proceed to step 4 in the same response.

4. Use the **Skill tool**: `skill: soleur:review`

> **CONTINUATION GATE**: When review outputs `## Code Review Complete` (or any review-summary heading, "Findings Summary", "Next Steps", etc.), that is a **status marker**, not a turn boundary. Do NOT end your turn. Do NOT treat the review summary as a deliverable — your deliverable is the merged PR at step 8. After the summary, immediately proceed to step 5 in the same response. If you find yourself wanting to write a wrap-up sentence, hand off to the user, or wait for confirmation, stop — that is the failure mode this gate exists to block. The same anti-stop rule applies between every subsequent step (5 → 5.5 → 6 → 7 → 8): each skill's exit summary is a checkpoint, never a stopping point.

5. **Resolve ALL review findings (P1, P2, and P3).** Technical debt compounds — fix everything now, not later. List open GitHub issues from this review session:

   ```bash
   gh issue list --label code-review --state open --search "PR #<current_pr_number>" --json number,title,body,labels
   ```

   The `--search` flag scopes results to issues from this review session (the review skill's issue template includes `PR #<number>` in the body). If zero issues match, proceed immediately to Step 5.5.

   For each matching issue (regardless of priority), spawn a parallel `pr-comment-resolver` agent. Pass the issue body's `## Problem`, `## Proposed Fix`, and `Location:` fields as the agent's input. After all agents return, commit fixes and close each resolved issue:

   ```bash
   gh issue close <number> --comment "Fixed in <commit-sha>"
   ```

   Do NOT end your turn after this step. Proceed to Step 5.5.

5.5. Use the **Skill tool**: `skill: soleur:qa`, args: "<plan_file_path>". QA verifies features work end-to-end by executing the plan's Test Scenarios (browser flows via Playwright MCP, API verification via Doppler + curl). If QA fails, fix the issues and re-run QA before proceeding. If the plan has no Test Scenarios section, QA skips gracefully.
6. Use the **Skill tool**: `skill: soleur:compound`
7. Use the **Skill tool**: `skill: soleur:ship`. Ship handles compound re-check (Phase 2), documentation verification (Phase 3), tests (Phase 4), semver label assignment, push, PR creation, CI, merge, and cleanup.
8. Output `<promise>DONE</promise>` when PR is merged and release workflows pass

CRITICAL RULE: If a completion promise is set, you may ONLY output it when the statement is completely and unequivocally TRUE. Do not output false promises to escape the loop.

Start with step 0b now.
