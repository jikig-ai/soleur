---
name: one-shot
description: "This skill should be used when running the full autonomous engineering workflow from plan to merged PR."
---

Run these steps in order. Do not do anything else.

<!-- one-shot-anti-bypass-protocol:start -->
## Anti-bypass protocol (load-bearing — especially Grok Build)

You are the **pipeline runner** for this skill. Whether entered via `/go` → `/one-shot` or direct `/one-shot`:

- **FORBIDDEN:** Cherry-picking steps (e.g. 0b worktree + inline implementation + push, then stopping).
- **FORBIDDEN:** Using Write/Edit/Shell on product code **before** Steps 1–2 (plan) complete — unless Step 1 recovered an on-disk plan and Step 3 (`/work`) is next.
- **FORBIDDEN:** Treating a draft PR or pushed branch as done. Deliverable = **merged PR** + `<promise>DONE</promise>` (Step 8).
- **REQUIRED (Grok Build):** Invoke child skills via slash commands — `/plan`, `/deepen-plan`, `/work`, `/review`, `/qa`, `/compound`, `/ship` (ship chains `/postmerge`). Do not read their SKILL.md and improvise.
- **REQUIRED before `git push` (Grok Build):** Run `bash plugins/soleur/scripts/grok-pre-push-gate.sh` from repo root — local CI parity (`test-all.sh` + fast required checks + `grok-fidelity`). Abort push on non-zero exit; inspect `EXIT=$rc` explicitly (no `| tail`).
- **Merge → deploy:** YOU poll merge/release/deploy — never ask the operator to watch CI. Grok: **AwaitShell** + `pattern`; Claude: **Monitor tool**. See `harness.ts` `pollInstructions()`.
- **Continuation gates:** `## Work Phase Complete`, `## Code Review Complete`, and similar exit summaries mean **proceed to the next step in this same turn** — never hand off to the operator.

See `plugins/soleur/lib/workflow-fidelity.ts` (`IMPLEMENTATION_TAIL`, `ONE_SHOT_CHILD_SKILLS`) and `go.md` Step 2.1 (`go-post-route` block).

**Harness adapter (Steps 1–8 child skills):** Use `plugins/soleur/lib/harness.ts` — Grok Build invokes `/plan`, `/work`, `/review`, `/ship`, etc.; Claude Code uses the **Skill tool** (`soleur:plan`, `soleur:work`, …). Never substitute ad-hoc Write/Edit/Shell loops for a registered child skill.
<!-- one-shot-anti-bypass-protocol:end -->

**Step 0 (pre): Workspace readiness gate.** Before anything else, confirm a usable git repository exists — `one-shot` can be invoked directly (not only via `/soleur:go`), so it must self-guard. Run `git rev-parse --is-bare-repository 2>/dev/null || true; git rev-parse --is-inside-work-tree 2>/dev/null || true`. If **neither** prints `true`, the workspace has no git checkout (in the Soleur web / Concierge env, a connected repo still cloning in the background or a failed setup leaves a repo-less `/workspaces/<id>`). STOP immediately — do NOT run the collision checks, do NOT create a worktree, do NOT spawn the planning subagent. Reply with the honest, no-wait message: "Your workspace isn't ready yet — its repository is still being set up, or its setup didn't finish. Please try again in a moment. If this keeps happening, reconnect your repository in **Settings → Repository**." This prevents the missing-repo flail where the agent improvised dozens of exploration commands.

<decision_gate>
**API budget.** This skill runs the full autonomous engineering pipeline: plan → work → review → resolve-pr-parallel → ship. Typical wall-clock 30–90 min; per-run Anthropic credit cost is non-trivial and scales with plan complexity, review-cycle count, and PR comment volume. The pipeline runs autonomously once Step 0a/0a.5 collision checks pass — there are no per-phase approval gates after that. Soleur does not bill or proxy these calls — Anthropic does, against the key in your session. The Soleur LICENSE (BSL 1.1) disclaims warranty for runtime cost; you operate this loop against your own budget.

If running against a tight budget, run `/soleur:plan` instead and review the plan before invoking `/soleur:work` separately.
</decision_gate>

**Step 0a: Linear context preflight.** Before creating the worktree, scan `$ARGUMENTS` for substrings matching `[A-Z]{2,}-[0-9]+` or `linear\.app/[^/]+/issue/`. If any match:

1. Use the **Skill tool**: `skill: soleur:linear-fetch`, args: "$ARGUMENTS". The skill returns two artifacts: `agent_context` (markdown blob + image content blocks, streamed into THIS parent conversation only) and `persist_safe_summary` (the same text with every `uploads.linear.app/*` URL redacted to `[linear-image: REDACTED]`).
2. For the remainder of this skill, **substitute `persist_safe_summary` for `$ARGUMENTS` whenever the value is passed to a Task subagent or to a child skill invocation** (e.g., the subagent prompt template's `ARGUMENTS:` line at the top of Steps 1-2, the subagent's `args: "$ARGUMENTS"` for `skill: soleur:plan`, and the fallback inline `args: "$ARGUMENTS"`). Do NOT pass `agent_context` or any Linear image URL into a subagent prompt — Task subagents inherit prompt text only (`knowledge-base/project/learnings/best-practices/2026-05-12-task-subagent-prompt-text-only.md`); the parent retains the images for Steps 3-8 (work, review, ship). The original `$ARGUMENTS` placeholder remains the slugification source at Step 0b's worktree-name construction; only downstream prompt construction substitutes.

If no Linear references match, this step is a no-op and `$ARGUMENTS` flows through unchanged.

**Step 0a.5: Open-issue collision check.** Before creating the worktree, scan `$ARGUMENTS` for substrings matching `#[0-9]+` (zero or more GitHub issue references).

**File-path target detection (pre-scan).** Default `FILE_PATH_TARGET=false`. Split `$ARGUMENTS` on whitespace; for each token, full-match against the anchored regex `^[^\s]+\.(md|json)$` (anchors are load-bearing — without them `spec.md.bak` / `bad.json5` would substring-match), then run `test -f "$token"` (resolved from the invocation CWD, which is the bare repo root since Step 0a.5 runs before Step 0b's worktree creation). If any token matches and resolves, set `FILE_PATH_TARGET=true` — the operator's target is the file, and any `#N` refs in the args are contextual citations, not work targets. In `FILE_PATH_TARGET=true` mode, the closed-issue abort in step 2 is downgraded to an advisory warning; the pipeline continues.

For each distinct `#<N>` match:

1. Run `gh issue view <N> --json state,closedByPullRequestsReferences --jq '{state, closed_by: [.closedByPullRequestsReferences[] | select(.isCrossRepository | not) | .number]}'`. If `gh` exits non-zero (no auth, network failure, issue not found in this repo), warn once on stderr (`WARNING: gh issue view #<N> failed; skipping collision check for this ref`) and continue without aborting — fail open so an infrastructure flake does not silently kill a legitimate run.

2. **If `state == "CLOSED"` and `FILE_PATH_TARGET=false`:** ABORT one-shot immediately with: `Issue #<N> is already closed (closed by PR #<closed_by[0]> if present). Aborting to avoid duplicate work — the issue's resolution is already in main. If you intend to do follow-on work, pass a plan file path or freeform description instead of #<N>, or re-open the issue first.` This abort fires in BOTH headless and interactive modes — closed-issue is an unambiguous "this work is done" signal and continuing wastes a full plan→work→review→ship cycle. Do NOT create the worktree, do NOT create the draft PR.

   **If `state == "CLOSED"` and `FILE_PATH_TARGET=true`:** Emit an advisory warning on stderr (`WARNING: #<N> is closed — treating as contextual reference, not a work target`) and continue. Do NOT abort.

   **If `state == "MERGED"`:** `gh issue view` resolved `<N>` to a PR, not an issue — `closedByPullRequestsReferences` does not apply to a PR ref, so treat this as its own branch rather than folding it into the CLOSED cases above. A merged PR is never a valid work target (the work is already done and in `main`), so this is unconditional — it does not depend on `FILE_PATH_TARGET`. Emit an advisory warning on stderr (`WARNING: #<N> is a merged PR, not an open issue — treating as a contextual citation, not a work target`) and continue. Do NOT abort.

3. **If `state == "OPEN"`:** run a linked-PR probe with NO state filter — `gh pr list --search "linked:issue #<N>" --state all --json number,title,state --jq '.[] | "  #\(.number) [\(.state)]: \(.title)"'`. Partition the results:
   - **Any `MERGED` PR linked to the OPEN issue** is the high-signal collision: the implementation already landed and the issue stayed open only for residual (often operator-only) follow-up. Do NOT trust a name match — the merging PR's branch is frequently NOT `feat-<this issue>` (it may be a `feat-one-shot-<id>-*` or a renamed branch), so a `--head <branch>` probe misses it. Treat a MERGED linked PR as a near-certain "this work is already done" signal. In **interactive mode**, ABORT-by-default: pause via AskUserQuestion naming the merged PR, offering (a) abort (preferred — verify what residual keeps the issue open before spending a dispatch), (b) continue (only if the operator confirms genuinely new scope beyond the merged PR). In **headless mode**, log a prominent warning naming the merged PR and continue — but the operator must treat a merged-linked-PR line in the run log as "verify before trusting this dispatch." **Cited-predecessor false-positive:** `linked:issue #N` matches body cross-references, so a follow-up issue that names its predecessor PR in prose ("Follow-up to #M", "not fixed in #M") surfaces #M as MERGED even though #M closed a DIFFERENT issue. Discriminate with `gh pr view <surfaced-PR> --json closingIssuesReferences` — if #N is ABSENT from the closing refs, the link is a citation (continue, genuinely new scope), not a collision. **This discriminator is valid ONLY for `linked:issue` hits.** It is vacuous for body-probe hits (next bullet), where an empty `closingIssuesReferences` is the defining property rather than a signal — so when dedupe puts one PR in both sets, the body-probe disposition wins. See `knowledge-base/project/learnings/workflow-patterns/2026-06-15-one-shot-collision-gate-false-positives-on-cited-predecessor-merged-pr.md` (#5356 follow-up to merged #5350).
   - **Prose-`Ref #N` blind spot (the `linked:issue` probe alone is insufficient).** GitHub's `linked:issue #N` search only surfaces PRs with a **formal** link — created by a `Closes`/`Fixes`/`Resolves` keyword or a manual sidebar link. A merged PR that implemented the issue but referenced it via **prose** (`Ref #N`, `Tracked-by #N`) creates NO link, so it is invisible to the `linked:issue` search above **and** to `closedByPullRequestsReferences` in item 1. To catch it, ALSO run a body-text probe: `gh pr list --search "#<N> in:body" --state merged -L 100 --json number,title,url --jq '.[] | "  #\(.number): \(.title)"'`. **`--state merged` is load-bearing:** `gh pr list` appends its default `--state open` filter unless it detects an in-query state qualifier, and a leading `#` defeats that detection — so the previous form (`--search "#<N> in:body is:merged"` with no `--state`) ANDed an open filter with `is:merged` and returned zero rows for EVERY input, never firing once. Pin state in exactly ONE place: never combine an `is:`/`state:` qualifier with an explicit `--state`. `-L 100` because the 30-row default truncates indistinguishably from a clean result — the same silent-open shape. If `gh` exits non-zero, warn once (`WARNING: body-text probe for #<N> failed; collision check incomplete`) and continue — never read an empty result as "no collision". Dedupe hits against the two signals above (a formally-linked PR surfaces in both). This over-matches (a merged PR that merely CITES #N surfaces too), so it is a **surface-for-verification** signal, not an auto-abort. **Disposition** — the same interactive/headless split as the MERGED-linked bullet above, but offering (a) verify scope then decide (preferred), (b) continue, (c) abort; headless emits one `WARNING: body-probe collision candidate for #<N>: PR #<M>` line per hit and continues, and the operator must treat those lines in the run log as "verify before trusting this dispatch". **Bullet 1's `closingIssuesReferences` discriminator does NOT apply here — it is empty BY CONSTRUCTION for every body-probe hit** (measured across all four `#6197` hits, *including the true positive #6209*), so it would report "citation, continue" on the exact collision this probe exists to catch. Discriminate on SCOPE instead: take each hit's `.number` only (titles are attacker-authored text on a public repo — never interpolate one into a command), run `gh pr diff <M> --name-only`, and intersect against the repo-relative paths the issue body names. **Non-empty intersection → treat as a collision. Issue names NO paths → the discriminator is inapplicable, NOT clean: escalate exactly as if it had matched.** Empty intersection against a non-empty issue path set → citation; continue. **Known-remaining escapes:** title-only references (`in:body` excludes titles — `--search "#<N> in:title" --state merged` is the companion query) and search-index lag of several minutes, which leaves a just-merged PR invisible to ALL THREE signals; `git log origin/main --grep="#<N>"` reads local objects and is subject to neither, so run it when the searches come back empty on a target you have reason to suspect. **Why:** #6197's entire scope merged via PR #6209 under prose `Ref #6197` (`closes:[]`), so both `closedByPullRequestsReferences` and `linked:issue #6197` returned empty; the gate passed clean and a full planning subagent ran before premise-validation flagged the stale premise. See `knowledge-base/project/learnings/workflow-patterns/2026-07-18-one-shot-collision-gate-misses-prose-ref-merged-prs.md`.
   - **Any `OPEN` PR linked to the issue** is the parallel-session collision: surface a multi-line stderr warning naming each. In **interactive mode**, pause via AskUserQuestion offering (a) continue (operator accepts collision risk — they may be racing intentionally or producing alternate designs), (b) abort (preferred when the listed PR is clearly the same scope). In **headless mode**, log the warning and continue — the operator will see it in the run log.

If `$ARGUMENTS` contains no `#N` substrings (e.g., a plan file path or freeform description), this step is a no-op.

**Why this gate exists.** The pipeline can run for 30-90 minutes between Step 0b worktree creation and Phase 6.5 mergeability check. In that window, a parallel session OR a manually-merged PR can resolve the same issue, producing a duplicate-implementation PR that has to be closed during ship. The 2026-05-12 `/one-shot #3684` session hit this exact failure mode: PR #3697 had merged + closed #3684 ~90 minutes earlier, but one-shot ran the full pipeline anyway and produced PR #3699 (closed at Phase 6.5 when the conflict-resolution diff surfaced parallel `lint-agents-rule-budget.{sh,py}` implementations). The check is cheap (≤2 `gh` calls per issue ref) and runs before the worktree exists, so the abort path costs nothing. It does NOT prevent the rarer "issue closed mid-flow" case — that would require a global lock; out of scope here. **Merged-PR-under-open-issue variant:** an issue legitimately stays OPEN after its implementing PR merges when residual (often operator-only) follow-up remains. The 2026-05-29 `/one-shot #4232` session hit this — PR-B had merged via #4508 under branch `feat-one-shot-4232-byok-delegations-pr-b` (renamed, then squash-deleted), so neither `--state open` nor a `--head feat-byok-delegations-4232` probe saw it; the worktree + empty draft PR were created before the plan subagent's reconciliation halted the run. Item 3 now probes `--state all` and aborts-by-default on a MERGED linked PR. See `knowledge-base/project/learnings/workflow-patterns/2026-05-29-one-shot-collision-gate-must-probe-merged-prs.md`. Carve-out: when `$ARGUMENTS` resolves to a file on disk (see file-path pre-scan above), closed-issue `#N` refs are treated as contextual citations and the abort is downgraded to an advisory warning — the operator's stated target is the file, not the cited issues. See #4363 for the original false-positive that motivated the carve-out. **Sharp edge for freeform-prose invocations:** the `#N` regex matches WORK-TARGET refs and CONTEXTUAL CITATIONS indistinguishably (predecessor PRs, parent issues, dependent specs). When invoking with prose args that include closed predecessor context, scrub closed `#N` refs from the args (use date-anchored phrasing like "merged 2026-05-16" instead of `PR #3922`) — only OPEN work-target refs should appear in `#N` form. Alternative: invoke with a plan-file path to trigger the `FILE_PATH_TARGET=true` carve-out. PR #4418 hit this on first invoke; see `knowledge-base/project/learnings/workflow-patterns/2026-05-25-one-shot-closed-issue-gate-fires-on-contextual-refs.md`.

**Step 0b: Ensure branch isolation.** Check the current branch with `git branch --show-current`. If on the default branch (main or master), create a worktree for the feature branch. Do NOT use `git pull` or `git checkout -b` -- both fail on bare repos (`core.bare=true`).

```bash
SOLEUR_SKILL_NAME=one-shot SOLEUR_EXPECTED_DURATION_MIN=240 \
  bash ${CLAUDE_PLUGIN_ROOT:-./plugins/soleur}/skills/git-worktree/scripts/worktree-manager.sh --yes create feat-one-shot-<slugified-arguments>
```

If the script exits non-zero and its output contains `NO_GIT_REPOSITORY`, the workspace lost its git checkout between the Step 0 (pre) gate and now (e.g. a reclaim). STOP — do NOT spawn the planning subagent. Reply with the same honest, no-wait message from Step 0 (pre). Do not retry or improvise alternative worktree paths.

**Stale orphan branch from a prior aborted run: do NOT hand-clean, do NOT strand.** `create` auto-heals a stale EMPTY remote branch (`origin/feat-one-shot-<same-name>` with 0 commits ahead of main and no live PR) that a prior aborted attempt left behind — it deletes it and proceeds, logging `auto-healed stale empty remote branch`. So a re-run of the same issue is expected to just work; never conclude the run is blocked and ask the operator to `git push origin --delete` by hand (the 2026-07-05 stranding). A branch with real commits or a live PR is NOT auto-deleted — that surfaces as a genuine collision (see Step 0a.5), which is a signal to verify, not a cleanup to force.

Then `cd` into the worktree path printed by the script. Parallel agents on the same repo cause silent merge conflicts when both work on main.

The `SOLEUR_SKILL_NAME` + `SOLEUR_EXPECTED_DURATION_MIN` env wire a lease on this worktree (see `.claude/hooks/lib/session-state.sh`). A sibling session's `cleanup-merged` invocation refuses to reap any worktree with an active lease. Release on clean exit:

```bash
bash .claude/hooks/lib/session-state.sh release_lease "$(basename "$PWD")"
```

**Step 0c: Create draft PR.** After creating the feature branch, create a draft PR from inside the worktree (the script errors with "Cannot run from bare repo root" otherwise — use a single `cd && bash` so the target tree is explicit and cannot be silently redirected by a prior call that `cd`d elsewhere; CWD persists across Bash calls, but relying on ambient CWD is fragile):

```bash
cd <worktree-path> && bash ${CLAUDE_PLUGIN_ROOT:-./plugins/soleur}/skills/git-worktree/scripts/worktree-manager.sh draft-pr
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
0. **CWD verification (first tool call):** run `cd <WORKING_DIRECTORY> && pwd`. The output MUST equal the WORKING DIRECTORY value above. If it does not, **retry at most 3 times** — and if `pwd` still mismatches after the third attempt, STOP and abort with an error in the Session Summary. Do NOT keep re-running the verification command in a loop (#5313: that loop hung a Concierge session; the runtime detector now surfaces a `worktree_enter_failed` status after 3 mismatched `cd … && pwd` commands, but do not rely on it — fail loud here too). Do NOT proceed; the plan will land in the bare-root synced mirror (gets clobbered on next sync) instead of the worktree. Bash CWD is per-agent and does NOT inherit from the parent's persistent `cd`.
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

After the subagent returns, **verify the subagent stayed in scope**: run `git diff origin/main...HEAD --name-only` and confirm only files under `knowledge-base/project/{plans,specs}/` were modified. **Bare-repo stale-ref guard:** the local `origin/main` ref can lag the actual main HEAD, making the three-dot diff list files from unrelated already-merged branches — a false scope-breach signal. If the diff shows files you never touched, re-diff against the branch's actual base SHA (`git diff <base-sha>..HEAD --name-only`, where `<base-sha>` is the fresh branch's parent) or `git fetch origin main` first, before concluding the subagent breached scope. **Why:** #4587 — stale `origin/main` listed an unrelated feature's files; recovery was a re-diff against the verified base SHA. If files outside that prefix were touched (workflow YAML, source code, CHANGELOG, etc.), the subagent exceeded its plan-only mandate — the Session Summary's "Decisions" became statements of intent rather than fact. Read each out-of-scope file from disk and reconcile against the plan's claims before trusting Step 3 onward; do NOT trust the Session Summary's reconciliation narrative ("Adopted the on-disk output text", "Already applied as uncommitted local changes") without verifying via `git diff <file>` first. **Why:** #3937 — plan-deepen subagent committed source-code edits AND its Session Summary claimed on-disk text it had not actually written (`pre-recorded` vs prescribed `not applicable`), costing two reconciliation commits. See [[2026-05-17-planning-subagent-exceeded-scope-and-summary-vs-disk-drift]].

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
   gh issue list --label code-review --state open -L 200 --search "PR #<current_pr_number>" --json number,title,body,labels
   ```

   The `--search` flag scopes results to issues from this review session (the review skill's issue template includes `PR #<number>` in the body). If zero issues match, proceed immediately to Step 5.5.

   For each matching issue (regardless of priority), spawn a parallel `pr-comment-resolver` agent. Pass the issue body's `## Problem`, `## Proposed Fix`, and `Location:` fields as the agent's input. After all agents return, commit fixes and close each resolved issue:

   ```bash
   gh issue close <number> --comment "Fixed in <commit-sha>"
   ```

   Do NOT end your turn after this step. Proceed to Step 5.5.

5.5. Use the **Skill tool**: `skill: soleur:qa`, args: "<plan_file_path>". QA verifies features work end-to-end by executing the plan's Test Scenarios (browser flows via Playwright MCP, API verification via Doppler + curl). If QA fails, fix the issues and re-run QA before proceeding. If the plan has no Test Scenarios section, QA skips gracefully.

   > **Diagnostic loops here are self-serve — never hand the operator a data-fetch.** When QA (or any review/verification step above) surfaces a failure on a server/cron/prod surface, self-pull the error: Better Stack `SOLEUR_*` markers via `doppler run -p soleur -c prd_terraform -- scripts/betterstack-query.sh --since <N> --grep <marker>` and Sentry — never ask the operator to paste error output, run probes, or eyeball logs (the operator decides, doesn't fetch). If the needed signal is missing from telemetry, ADD a monitored stdout `SOLEUR_*` marker in the emitting code so it self-reports; do not escalate to the operator for it. Cite `hr-no-dashboard-eyeball-pull-data-yourself`. See `knowledge-base/project/learnings/workflow-patterns/2026-07-08-self-pull-observability-in-diagnostic-loops-never-ask-operator-to-fetch.md` (#5934).
6. Use the **Skill tool**: `skill: soleur:compound`
7. Use the **Skill tool**: `skill: soleur:ship` (Grok: `/ship`). Ship handles compound re-check (Phase 2), documentation verification (Phase 3), tests (Phase 4), semver label assignment, push, PR creation, CI, merge, release-workflow polling, **postmerge verification (Step 3.8)**, and cleanup.

   **The merge → deploy wait is owned by ship — never hand-roll it and never ask the operator.** Do NOT skip invoking `soleur:ship`, do NOT issue `gh pr merge` yourself, and do NOT end the turn at MERGED. Ship Phase 7 polls merge + release workflows; Step 3.8 invokes `soleur:postmerge` before cleanup.

   **Harness polling:** Claude → **Monitor tool** (NEVER Bash `run_in_background`). Grok → **AwaitShell** with `pattern` matching terminal poll output, or Shell with adequate `block_until_ms`. Canonical: `plugins/soleur/lib/harness.ts` → `pollInstructions()`.

   > **CONTINUATION GATE:** When ship finishes (including postmerge Step 3.8), proceed immediately to step 8 — do NOT ask "want me to monitor deploy?" or hand off to the operator.

8. Output `<promise>DONE</promise>` **only when** PR is merged, release workflows passed, and **postmerge Phase 7** printed `postmerge verification complete!`. If ship returned without postmerge, invoke `/postmerge <PR-number>` (Grok) or `soleur:postmerge` (Claude) before emitting DONE.

CRITICAL RULE: If a completion promise is set, you may ONLY output it when the statement is completely and unequivocally TRUE. Do not output false promises to escape the loop.

Start with step 0b now.
