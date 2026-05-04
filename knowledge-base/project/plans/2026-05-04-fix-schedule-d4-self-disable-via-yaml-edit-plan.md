---
title: "fix(schedule): replace gh workflow disable (D4) with YAML-edit-and-push self-neutralization"
date: 2026-05-04
issue: 3153
branch: feat-one-shot-3153-schedule-d4-self-disable
worktree: .worktrees/feat-one-shot-3153-schedule-d4-self-disable
status: draft
type: bug-fix
priority: P2
classification: agent-action-only
brand_survival_threshold: aggregate-pattern
requires_cpo_signoff: false
---

# Plan: fix `soleur:schedule --once` D4 self-disable (issue #3153)

## Enhancement Summary

**Deepened on:** 2026-05-04
**Sections enhanced:** Root Cause, Hypotheses, Implementation Phases (1, 2), Test Strategy, Sharp Edges, Out-of-Scope.
**Research sources used:**
- Upstream `anthropics/claude-code-action` docs + GitHub App manifest scope (WebSearch + WebFetch).
- Project learnings: `2026-03-02-claude-code-action-token-revocation-breaks-persist-step.md`, `2026-03-02-github-actions-auto-push-vs-pr-for-bot-content.md`, `2026-05-04-schedule-once-template-missing-id-token.md`.
- Live API: `gh api /repos/jikig-ai/soleur` (`allow_auto_merge: true`).

### Key Improvements
1. **Hypothesis 1 hard-confirmed via upstream search:** The official Anthropic GitHub App's `github-app-manifest.json` requests **`contents: write, issues: write, pull_requests: write, actions: read`** — `actions: write` is NOT in the App's permission set. Workflow `permissions: actions: write` cannot widen the App's effective scope. `gh workflow disable` will NEVER work via the official App, full stop. (See Research Insights under Phase 1.)
2. **PR-fallback path corrected:** Initial draft's PR-fallback assumed `gh pr merge --squash --auto` would just work. Per learning `2026-03-02-github-actions-auto-push-vs-pr-for-bot-content.md`, three blockers can break PR-based fallbacks (`allow_auto_merge` OFF in user repos, GITHUB_TOKEN cascade suppression, branch-protection bypass). However: PRs created by the **Claude App identity** (not GITHUB_TOKEN) DO trigger downstream workflows, partially mitigating blocker #2 — but `allow_auto_merge` and bypass remain unknowable at workflow-generation time.
3. **Direct-push-only with graceful degradation chosen as the canonical path.** PR-fallback is retained as a best-effort secondary, but the failure mode is documented up-front: when both fail, the fallback comment is posted, and D3 remains the load-bearing safety. This matches the brainstorm's spirit (cleanup hygiene, not safety-critical).
4. **Test design tightened:** TS1 rewrite must assert the agent uses Read+Edit (not shell `sed`) for the YAML mutation, since shell-based YAML edits in CI have a long history of corruption (see `2026-04-22` learning about silent YAML drift in CI). TS6 asserts the conditional structure of the fallback chain.

### New Considerations Discovered
- `actions: write` in the workflow permissions block can be **dropped** from the template — keeping it has no effect since the App token doesn't honor it. However, leaving it doesn't HARM either; the brainstorm's spirit is to avoid widening attack surface. **Decision:** drop `actions: write` from the canonical template, document why in the YAML comment, and remove the `actions==write` assertion. (Reversal from initial-draft Phase 2.)
- Custom-GitHub-App workaround exists (deferred to Out-of-Scope): a user could install a custom App with `actions: write` and pass it via `claude-code-action`'s `github_app_*` inputs. Users are unlikely to do this; the YAML-edit path remains the universal fix.
- The 2026-03-02 learning explicitly documented **`git diff --cached --quiet` before commit to avoid silent no-op commits**. The neutralization primitive should adopt this guard — if the YAML is already neutralized (e.g., re-fire of an already-edited file), skip the commit step gracefully.

## Overview

The `--once` template's D4 self-disable instruction (`gh workflow disable "$WORKFLOW_NAME"` as the last step in the agent prompt) **fails at runtime inside `anthropics/claude-code-action@v1`**, observed in run 25314106006 against issue #3049 on 2026-05-04. The agent's catch-handler posted the documented fallback comment ("Workflow ran but auto-disable failed. Manual: gh workflow disable …") and the workflow remained `active` until manually disabled.

The same comment is posted by the agent on every `--once` fire, defeating the entire point of `--once`'s self-cleanup contract. D3 (date guard `[[ "$(date -u +%F)" == "$FIRE_DATE" ]]`) is unaffected and remains the load-bearing primary cross-year defense — this fix is about cleanup hygiene, not safety.

The replacement: have the agent **commit a YAML edit that removes the `schedule:` trigger from the generated workflow file** (replacing it with `workflow_dispatch:` only). This uses `claude-code-action`'s repo-write capability (verified working — the agent already posts comments via `gh api` in the same prompt), survives token revocation (the commit/push happens inside the prompt, not in a post-step), and preserves the file on disk as audit trail per brainstorm decision #9.

## Root Cause (verified)

In run [25314106006](https://github.com/jikig-ai/soleur/actions/runs/25314106006):

- Job: `run-once` — conclusion `success` (the agent's overall step exited 0 because it caught the disable failure).
- Agent successfully ran `gh api` calls (preflight checks, comment fetch, follow-up comment posting at [comment 4370328376](https://github.com/jikig-ai/soleur/issues/3049#issuecomment-4370328376)).
- `gh workflow disable scheduled-dogfood-once-3049-v2.yml` returned non-zero, triggering the documented fallback comment.

The split — `gh api` (issues:write) succeeded but `gh workflow disable` (actions:write) failed — confirms hypothesis 1 in the issue body: **`claude-code-action` substitutes its own short-lived App installation token for `GH_TOKEN`, and that App token's permission set doesn't include `actions: write` regardless of the workflow's `permissions:` block.** The post-step comment in SKILL.md line 360-362 already acknowledges that post-step disables fail because `claude-code-action` revokes its token after the step; what we now know is the **inside-prompt** disable fails too, for a related but different reason — the App token never had actions:write capability, even while live.

### Research Insights — Upstream confirmation (deepen-plan)

The official Anthropic GitHub App's `github-app-manifest.json` (per WebSearch results 2026-05-04 against `https://github.com/anthropics/claude-code-action`) declares its requested install-time permissions as:

| Permission | Scope |
|---|---|
| `contents` | write |
| `issues` | write |
| `pull_requests` | write |
| `actions` | **read** (not write) |

**Implications for this plan:**
- `gh workflow disable` requires `actions: write`. The Claude App was never granted that scope at installation. Workflow-level `permissions: actions: write` cannot widen the App's effective install-time scope — it can only *narrow* what the App is allowed to do in this run.
- Claude Code Action docs (per upstream `docs/security.md` and `docs/setup.md`) recommend custom GitHub App installation for users who need permissions beyond the official App's set. This is the only documented escape hatch for the actions:write requirement and is impractical to require of plugin users.
- `contents: write` IS in the App's scope — meaning the YAML-edit-and-push primitive WILL work, contingent on:
  - Branch protection / rulesets allowing the Claude App to push (App can be added as bypass-actor via the GitHub UI, but not via API per `2026-03-02-claude-code-action-token-revocation-breaks-persist-step.md`).
  - Or, if direct push is blocked, PR creation works (App also has `pull_requests: write`), and the PR can be merged either by `gh pr merge --squash --auto` (when `allow_auto_merge: true` on the user's repo — verified `true` for `jikig-ai/soleur` via `gh api /repos/jikig-ai/soleur --jq .allow_auto_merge`) or by a human reviewer.

This is consistent with the [2026-03-02 claude-code-action learning](../learnings/2026-03-02-claude-code-action-token-revocation-breaks-persist-step.md) observation that `claude-code-action` uses its own App identity inside the agent (not the workflow's `GITHUB_TOKEN`), and the App's installed permissions ≠ workflow's declared `permissions:` block.

### Research Insights — Sister bug `--once` template (deepen-plan)

The recently-merged fix for [`--once` template missing id-token write](../learnings/2026-05-04-schedule-once-template-missing-id-token.md) (#3134) gives us a **direct precedent for the test-design pattern** to use here: regression-guard the `--once` template by anchoring on `<indentation> + <key>:` (per session error #4 in that learning). My plan's TS1/TS6 must follow the same anchoring discipline — bare-content matches will produce false positives against the YAML's permissions-block COMMENT vs. its actual key.

The same learning also flagged **a parallel "permission asymmetry between recurring-cron and `--once` templates"** as a class-bug worth scrutinizing whenever the two diverge. After this fix, the divergence widens (recurring-cron likely retains `gh workflow disable` patterns; `--once` switches to YAML-edit-and-push). That's intentional: recurring crons fire forever by design; one-time fires need the cleanup. But the divergence should be CALLED OUT in the SKILL.md comment so a future copy-paste from one template to the other doesn't re-introduce the bug class.

## Research Reconciliation — Spec vs. Codebase

| Spec / Issue Claim | Codebase Reality | Plan Response |
|---|---|---|
| "D4 section ~line 247-248" of SKILL.md | Confirmed: line 247 is the D4 defense summary; D4 prompt body at lines 350-362. | Edit both regions in lockstep. |
| "Suggested alternative: agent commits a YAML edit setting cron to far-future/impossible expression" | No such cron expression exists — GHA cron grammar has no "never" sentinel. Closest options: (a) remove `schedule:` trigger entirely, (b) delete the workflow file, (c) move to a date >60 days in future (GHA auto-disables after 60d inactivity). | Use option (a) — strip `schedule:` block, leave `workflow_dispatch:`. Preserves audit trail (brainstorm decision #9). |
| Brainstorm decision #9: "Workflow file persists post-fire (not deleted) — Self-deletion would require a commit (collides with branch protection, token revocation)" | Half-true. Token revocation is real for post-steps but NOT for pushes inside `claude-code-action` (per 2026-03-02 learning, App identity has bypass when configured). Branch protection IS a real concern for plugin users without App-bypass configured. | YAML-edit-and-push as primary; PR-and-auto-merge as fallback when direct push fails. Same-commit complexity but preserves the brainstorm's audit-trail invariant. |
| Brainstorm decision #6: "Self-disable inside agent prompt is forced by token revocation; last instruction is `gh workflow disable`" | The premise (revocation forces in-prompt) is sound; the implementation (`gh workflow disable`) was wrong because the in-prompt App token also lacks `actions: write`. | Keep the inside-prompt principle; replace the operative call with a `git` mutation that uses repo-write (App token DOES have contents:write to its install scope). |

## User-Brand Impact

**If this lands broken, the user experiences:** A `--once` workflow that runs successfully, posts the user-visible "auto-disable failed. Manual: …" follow-up comment on every fire, and remains `active` in the user's `gh workflow list` until either (a) manually disabled or (b) GHA's 60-day inactivity timer fires. For multi-year cron `0 9 D M *` patterns, the file would re-fire next year on the same calendar date — D3 (date guard) blocks any action but the agent still consumes a turn budget and posts no harmful state.

**If this leaks, the user's data/workflow/money is exposed via:** N/A. This is a cleanup-hygiene fix on the cleanup path, not the action path. No new attack surface.

**Brand-survival threshold:** `aggregate-pattern`. A single missed disable is hygiene noise; the pattern of every `--once` user seeing the failure comment erodes trust in `--once`'s contract. This is below the `single-user-incident` bar that triggers CPO sign-off (D3 still protects the brand-survival vector — wrong action against drifted state — and D3 is unchanged by this plan). Inherited from the brainstorm User-Brand Impact framing for `feat-schedule-one-time-runs` which set `single-user-incident` for the act-on-repo path; this fix lives strictly on the cleanup path post-action and does not widen blast radius.

## Acceptance Criteria

### Pre-merge (PR)

- [x] `plugins/soleur/skills/schedule/SKILL.md` D4 section (line 247) updated to reflect new mechanism: cron-trigger removal via in-prompt git commit, NOT `gh workflow disable`.
- [x] D3 + idempotency-check sites in the prompt (line 311, 314, 338) that call `gh workflow disable` for early-abort paths are likewise updated to the new neutralization mechanism (cron-trigger removal). Same call site, same fix — otherwise cross-year-fire abort path fails identically.
- [x] Final-step prompt body (lines 350-362) rewritten with the new sequence: (1) edit YAML to strip `schedule:` block, (2) commit, (3) push to default branch (or open PR + auto-merge if branch-protected), (4) post fallback comment only if both push and PR paths fail.
- [x] `permissions:` block updated: `actions: write` dropped, `contents: write` + `pull-requests: write` added.
- [x] YAML-write verification updated: drop the `actions==write` assertion, add `contents==write` and `pull-requests==write` assertions plus an anti-regression check.
- [x] `plugins/soleur/test/schedule-skill-once.test.sh` TS1 (token-revocation regression guard) rewritten to assert the NEW mechanism. The "no post-step after claude-code-action" invariant stays.
- [x] All existing TS2-TS5 tests pass (TS2 ordering anchor switched from `gh workflow disable` to the `## Final step` heading; TS3 idempotency anchor switched to the new `already neutralized` check).
- [x] New TS6: asserts the prompt instructs a fallback path (PR + auto-merge) when direct push fails, and that the fallback comment is posted ONLY when both direct push and PR-create fail. Also added TS7 covering the new permissions block.
- [x] `bash plugins/soleur/test/schedule-skill-once.test.sh` exits 0 — 35 PASS, 0 FAIL.
- [ ] `Closes #3153` in PR body (not title).
- [ ] PR body has `## Changelog` section, `semver:patch` label.

### Post-merge (operator)

- [ ] Re-run the dogfood pattern: schedule a fresh `--once` against an open issue with `--at` set to today, watch the workflow fire, verify the file commits a `schedule:`-trigger removal AND the workflow shows up as still-active-but-no-cron in `gh workflow list` (or disabled, depending on GHA behavior with `workflow_dispatch:`-only).
- [ ] Verify the originating issue receives a single comment (the task result), NOT the "auto-disable failed. Manual: …" comment.
- [ ] Manually clean up the dogfood workflow file (separate cleanup PR or `/soleur:schedule prune` if available).
- [ ] Close #3153 only after the post-merge dogfood passes.

## Hypotheses (root-cause investigation summary)

The issue body listed 3 hypotheses. The post-merge dogfood + comment-vs-disable split (above) confirms hypothesis 1. Documenting all three for the record:

1. **(CONFIRMED)** `claude-code-action` supplies its own App installation token for `GH_TOKEN` inside the agent's bash, and that token does not carry `actions: write` — independent of what the workflow's `permissions:` block declares. Evidence: `gh api` to issues endpoints (issues:write) succeeded in the same agent run; `gh workflow disable` (actions:write) failed.
2. **(NOT CONFIRMED, but partially relevant)** `claude-code-action` revokes the App token before the bash subprocess returns. Per the 2026-03-02 learning, this is the failure mode for **post-steps**, not for in-prompt commands. The dogfood timing (agent posted a follow-up comment AFTER the failed disable) shows the token was still live at disable-call time.
3. **(LIKELY)** `actions: write` propagation requires a `claude-code-action` input the template doesn't invoke (similar to how `id-token: write` propagation only works because the action consumes the workflow's OIDC capability via a documented input). No such input is documented for actions:write at the time of writing. Tracking upstream awareness as a deferred follow-up issue (see Out-of-Scope).

## Files to Edit

- `plugins/soleur/skills/schedule/SKILL.md` — sections at L247 (D4 defense summary), L262-271 (permissions block + YAML comment), L304-314 (D3 abort path uses `gh workflow disable`), L317-319 (idempotency check), L336-338 (preflight-failure path uses `gh workflow disable`), L350-362 (final-step / D4 prompt body), L367-381 (YAML-write verification asserts).
- `plugins/soleur/test/schedule-skill-once.test.sh` — TS1 rewrite (token-revocation guard mechanism check), add TS6 (fallback-path assertion). TS5 line 143 (`id-token: write present`) stays. TS5 line 144 has a comment referencing #3134 — leave intact.

## Files to Create

- `knowledge-base/project/learnings/integration-issues/<topic>.md` — capture the actions-write-not-propagated pattern as a learning. Date filename at write time per the `cq-tasks-md-no-prescribed-dates`-style convention. Topic suggestion: `claude-code-action-app-token-lacks-actions-write`.

## Implementation Phases

### Phase 1 — Replace operative `gh workflow disable` calls in SKILL.md prompt body

Update SKILL.md lines 304-362 (the prompt body) to replace each `gh workflow disable "$WORKFLOW_NAME"` call site with the new neutralization mechanism. There are FOUR call sites:

- L311 — D3 empty/malformed FIRE_DATE early abort
- L314 — D3 cross-year-fire abort
- L319 — Idempotency check (workflow already disabled — exit 0; no neutralization needed here, can stay as a no-op exit)
- L338 — Pre-flight-failure abort path (each of issue-state, comment-id, author-pin, immutability checks fail through here)
- L352 — Final D4 step

Define a single named primitive in the prompt (e.g., "neutralize the workflow") that the four call sites can reference, instead of repeating the multi-step git sequence inline at each call site. Skeleton (refined per upstream-research findings — direct-push canonical, PR fallback graceful, no false confidence in auto-merge):

```yaml
prompt: |
  ## Neutralization primitive (referenced by D3 abort, preflight-failure abort, and D4 final step)

  To neutralize the workflow (prevent any future cron fires), do the following IN ORDER:

  1. **Idempotency precheck.** Read `.github/workflows/$WORKFLOW_NAME`. If the `on:` block already has `schedule:` removed (or only contains `workflow_dispatch:`), the workflow is already neutralized — skip to step 6 (success, no-op).
  2. **Edit YAML.** Use Read+Edit tools (NOT shell `sed`/`awk` — shell-based YAML mutation has a long history of corrupting workflow files in CI) to remove the `schedule:` key and its child list under `on:`. Leave any other triggers (`workflow_dispatch:`, `push:`, etc.) intact. If `schedule:` is the ONLY trigger, replace the entire `on:` block with `on:\n  workflow_dispatch:` so the file remains a valid GHA workflow that can be manually invoked for forensic purposes.
  3. **Stage and guard against no-op commit.** `git add .github/workflows/$WORKFLOW_NAME` then `git diff --cached --quiet`. If the diff is empty (exit 0), the file was already neutralized between step 1 and step 2 — skip to step 6. (See learning `2026-03-02-github-actions-auto-push-vs-pr-for-bot-content.md` "Also Learned" — `git commit` does not fail on empty diff; explicit guard is required.)
  4. **Commit.** `git commit -m "chore(schedule): neutralize one-time workflow $WORKFLOW_NAME (post-fire cleanup, #$ISSUE_NUMBER)"`. Use the `claude[bot]` identity that `claude-code-action` already configures (no separate `git config user.*` step needed).
  5. **Push — direct first, PR fallback.**
     - **5a.** Try direct push: `git push origin HEAD:${{ github.event.repository.default_branch }}`. If exit 0, neutralization succeeded — go to step 6.
     - **5b.** If direct push fails (branch protection / required status checks): create an ephemeral branch `chore/neutralize-$WORKFLOW_NAME-$(date -u +%Y%m%d%H%M%S)`, push it, open a PR via `gh pr create --base "${{ github.event.repository.default_branch }}" --head "$BRANCH" --title "chore(schedule): neutralize $WORKFLOW_NAME" --body "Auto-cleanup after one-time fire of #$ISSUE_NUMBER. Removes the schedule: trigger from the generated --once workflow file. See plugins/soleur/skills/schedule/SKILL.md (D4 defense)."`. Then attempt auto-merge: `gh pr merge --squash --auto "$PR_URL" 2>/tmp/merge.err`. If `merge.err` contains `auto-merge is not allowed`, the user repo has `allow_auto_merge: false` — the PR is open and waiting on a human reviewer; that's still a successful neutralization handoff (the workflow can re-fire one more time before the PR lands, but D3 catches that).
  6. **Success.** No fallback comment posted; the task-result comment from the main work suffices.
  7. **Both failed.** If step 5a errored AND step 5b PR-creation errored (NOT auto-merge — auto-merge unavailability is acceptable), post the fallback comment to issue #$ISSUE_NUMBER: "Workflow ran but auto-cleanup failed (direct push: <err>; PR create: <err>). Manual: edit `.github/workflows/$WORKFLOW_NAME` to remove the `schedule:` trigger, OR install the Anthropic Claude GitHub App as a bypass-actor on your default branch ruleset, OR install a custom GitHub App with `actions: write` and re-run with `gh workflow disable`."

  ## Pre-flight ...
  ...
  - On D3 cross-year mismatch: invoke neutralization primitive, exit 0.
  - On preflight-failure: post observation comment, invoke neutralization primitive, exit 0.

  ## Task ...

  ## Final step (mandatory, last)
  Invoke the neutralization primitive. This is D4 — the secondary self-cleanup. D3 (date guard above) is the primary cross-year defense; D3 is structural (cron AND date both must match) and cannot fail silently.
```

**Why the refined design:**
- **Direct-push canonical** — single round-trip, no PR-state to monitor, no auto-merge dependency. Works for Soleur (App is bypass-configured) and for any user who follows the documented setup that adds the Claude App to their bypass-actor list.
- **PR fallback retained but graceful** — covers the "user has branch protection but didn't add Claude App as bypass" common case. Even if `allow_auto_merge` is OFF (which `2026-03-02` learning warned about), an OPEN PR is a recoverable state — a human can merge it.
- **`claude[bot]` identity, not GITHUB_TOKEN** — per upstream-research and `2026-03-02-claude-code-action-token-revocation-breaks-persist-step.md`, the App identity has bypass when configured; GITHUB_TOKEN cannot. PRs created by the Claude App also DO trigger downstream workflows (unlike GITHUB_TOKEN cascade-suppressed PRs), so CI will run on the cleanup PR — required-status-check gates pass without operator help.
- **`git diff --cached --quiet` guard** — caught explicitly in the 2026-03-02 learning.
- **No false confidence in auto-merge** — distinguish "PR creation failed" (true failure) from "auto-merge unavailable" (recoverable). Initial-draft Phase 1 conflated these.

Edit the L262-265 YAML comment to reflect the new mechanism. The comment must clarify:
- `actions: write` is **dropped** from the canonical template (App token doesn't honor it; previous comment was misleading).
- `contents: write` is **mandatory** (D4 neutralization commit).
- `pull-requests: write` is **mandatory** (D4 PR-fallback).
- `id-token: write` is unchanged (claude-code-action OIDC handshake; #3134).
- A copy-paste-warning note: "If you copy this template's permissions block to a recurring-cron workflow, REVERT `contents:` to `read` and DROP `pull-requests:` — recurring crons don't self-neutralize, so the wider permissions are unnecessary attack surface."

### Phase 2 — Update permissions block + YAML-write verification

In the canonical template (L266-271):

```yaml
permissions:
  contents: write       # was: read — needed for git push (D4 neutralization)
  issues: write         # unchanged — preflight comments + task-result comment
  id-token: write       # unchanged — claude-code-action OIDC handshake (#3134)
  pull-requests: write  # NEW — needed for PR-fallback path on branch-protected default branches
  # actions: write was removed in #3153 — the official Anthropic GitHub App's
  # installation permissions cap actions:* at READ. Workflow-level actions:write
  # cannot widen the App's effective scope, so declaring it gave false confidence.
  # If you have installed a CUSTOM GitHub App with actions:write and configured
  # claude-code-action to use it (see upstream docs/setup.md), you may add
  # `actions: write` back and switch the D4 primitive to `gh workflow disable`.
```

**Decision change vs. initial draft:** `actions: write` is **dropped from the canonical template** (not retained as belt-and-suspenders). Reasoning: per upstream research, declaring `actions: write` on a workflow whose action-step uses the App identity does NOT widen the App's effective scope — the declaration is purely cosmetic and creates false confidence for future maintainers. This reverses my initial-draft Phase 2 decision. The Sharp Edges section is updated to match.

Update L379 verification:

```python
# Drop:
# assert d['permissions']['actions'] == 'write', 'actions:write missing (gh workflow disable will fail)'
# Add:
assert d['permissions']['contents'] == 'write', 'contents:write missing (D4 neutralization commit will fail)'
assert d['permissions']['pull-requests'] == 'write', 'pull-requests:write missing (D4 PR-fallback will fail)'
# Anti-regression:
assert 'actions' not in d['permissions'] or d['permissions']['actions'] != 'write', \
    'actions:write should not be in --once template (App token does not honor it; see #3153)'
```

### Phase 3 — Update D4 defense summary at L247

Rewrite the D4 bullet:

> **D4 — in-prompt self-neutralization (SECONDARY).** The agent's last prompt instruction edits the generated workflow YAML to strip the `schedule:` trigger and pushes (direct or via PR + auto-merge). MUST live inside the prompt — `claude-code-action` revokes its App token after this step. Replaces `gh workflow disable`, which fails at runtime because `claude-code-action`'s App installation token does not honor the workflow's `actions: write` declaration (#3153). `contents: write` + `pull-requests: write` are the load-bearing permissions.

### Phase 4 — Test updates (TDD-first per Acceptance Criteria)

Per the project TDD gate (`cq-write-failing-tests-before`), modify `schedule-skill-once.test.sh` BEFORE Phase 1's SKILL.md edits would land:

- TS1 rewrite — replace assertion `gh workflow disable` is in the agent prompt with: assert prompt contains the literal string `Neutralization primitive` AND `git push origin HEAD:` AND `gh pr merge --squash --auto`. Keep the "no post-step after claude-code-action" check.
- TS6 add — assert prompt contains the fallback-comment text "Workflow ran but auto-cleanup failed" AND that this comment is conditional on push AND PR both failing.

Run `bash plugins/soleur/test/schedule-skill-once.test.sh` between phases. RED before Phase 1; GREEN after Phase 1+2+3.

### Phase 5 — Capture learning + update plan/spec artifacts

Write `knowledge-base/project/learnings/integration-issues/<topic>.md` documenting:
- The split-permission failure mode (issues:write works, actions:write doesn't, both via the App installation token).
- Cross-reference to 2026-03-02 token-revocation learning (different bug, related root surface — claude-code-action's token strategy).
- Mitigation pattern: prefer `contents: write` (which the App reliably honors) for any in-prompt cleanup over `actions: write`.

### Phase 6 — Post-merge dogfood

Same pattern as the round-3 dogfood that surfaced #3153. Schedule a `--once` against a live test issue with `--at` = today; verify the new neutralization path works end-to-end. Recurring acceptance bar: workflow file's `schedule:` block is stripped after one fire; no "auto-cleanup failed" comment on the issue.

## Domain Review

**Domains relevant:** Engineering (CTO).

### Engineering (CTO)

**Status:** assessed-from-brainstorm-carryforward + plan-time delta.

**Assessment:** This is a within-bounds tactical fix to the cleanup path of `feat-schedule-one-time-runs`. The architectural decision (in-prompt cleanup, not post-step) was made and validated at brainstorm time; this plan corrects the *implementation* of that decision, not the architecture. Trade-offs:

- `git push` from inside `claude-code-action` is a known-working pattern (per 2026-03-02 learning) — this fix uses an existing primitive, doesn't invent one.
- Permission widening (`contents: write` + `pull-requests: write`) is the minimum viable set for the fix; both are commonly granted to `--once` workflows already in similar Soleur GHA workflows. No widening of attack surface beyond what `feat-schedule-one-time-runs` already justified.
- PR-fallback path adds one extra workflow run for branch-protected repos, but auto-merge keeps the operator out of the loop.
- D3 (load-bearing safety) is unchanged. The fix touches only the cleanup path.

CTO sign-off: implicit — fix is bounded to within-spec correction, not a new architectural commitment.

### Product/UX Gate

**Tier:** none. No user-facing UI; this is plumbing inside a generated GHA workflow.

## Open Code-Review Overlap

`gh issue list --label code-review --state open` (31 issues) checked against `plugins/soleur/skills/schedule/SKILL.md` and `plugins/soleur/test/schedule-skill-once.test.sh`. **None.**

## Out-of-Scope / Deferred

- **Upstream `claude-code-action` issue: undocumented App token permission scope.** The action's docs do not say which workflow `permissions:` are honored vs. dropped by the App-token substitution. After deepen-plan research (WebSearch 2026-05-04), the App's `github-app-manifest.json` is documented to request `contents: write, issues: write, pull_requests: write, actions: read` — but the docs at `docs/security.md` and `docs/setup.md` do NOT say "workflow-level `actions: write` cannot widen this." File an upstream documentation request issue (anthropics/claude-code-action) titled something like "Document install-time vs. workflow-level permission interaction" and link to #3153 as the failure case. Track as a separate Soleur GitHub issue with a re-evaluation criterion: "If upstream adds an `actions-write` passthrough OR adds documentation explicitly noting the install-time cap, re-evaluate whether to revert to `gh workflow disable`."
- **Custom-GitHub-App workaround (documented out-of-scope).** Per upstream `docs/setup.md`, users CAN install a custom GitHub App with `actions: write` and pass it to `claude-code-action` via `github_app_*` inputs. This is a valid escape hatch but requires user action AT install time. Document this in the SKILL.md "Known Limitations" section with a one-paragraph note. Do NOT make it the default — the YAML-edit-and-push primitive works for all users without requiring custom-App setup.
- **`/soleur:schedule prune` cleanup utility.** Tracked already in #3094 follow-on work (per brainstorm Out-of-Scope). Out of scope for this fix.
- **Same-day re-fire in 24h race window.** A `--once` workflow with `--at 2026-05-04` and cron `0 9 4 5 *` whose cleanup PR sits in CI for >24h could in theory get re-fired on the next year's May 4 — but D3 catches it. No new mitigation needed.

## Sharp Edges

- **A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6.** This plan declares threshold `aggregate-pattern` with reasoning; do not rewrite it during deepen-plan without re-running the carry-forward check against the brainstorm.
- **Branch protection on plugin users' default branch is unknowable at workflow-generation time.** The PR-fallback path is mandatory because we cannot assume direct push works. Don't simplify the prompt by removing the fallback "just for Soleur self-dogfood."
- **`actions: write` is DROPPED from the canonical template** (not "kept as cosmetic"). Per upstream research the App's installation manifest caps `actions:*` at READ; workflow-level `actions: write` does not widen the App's effective scope. Declaring it gave maintainers false confidence ("the workflow has the permission, so disable should work"). The anti-regression assertion in Phase 2 prevents copy-paste re-introduction. If a future user installs a custom App with `actions: write` and re-introduces `gh workflow disable`, they should also remove the assertion in their fork.
- **The neutralization primitive's `Edit` tool invocation must use the agent's Read+Edit, not a shell `sed -i`.** Shell-based YAML mutation in CI has a long history of corrupting workflow files; the agent's Edit tool round-trips through validated read+write.
- **Same-PR fix may surface a SECOND failure mode**: the PR-fallback's `gh pr create` may fail for the same App-permission-scope reason `gh workflow disable` fails. Verify in Phase 6 dogfood that `gh pr create` works inside `claude-code-action` (existing claude-code-action workflows that open PRs prove this works for App-bypass-configured repos like Soleur; user-repo case is trickier and should be a Phase 6 explicit verification).
- **When the cleanup PR is opened and queued for auto-merge, the workflow file MAY be re-fired between PR creation and merge if the merge takes >1 calendar day AND the cron's date predicate matches.** D3 + idempotency check handle this — the re-fire gets D3'd into a no-op. Document this race clearly in the SKILL.md so future operators don't try to "tighten" the path.

## Test Strategy

- **Content-assertion tests (existing pattern in `schedule-skill-once.test.sh`):** TS1 + TS6 cover the regression. The test pattern matches against literal strings in the canonical YAML template extracted between `<!-- once-template-begin -->` markers — same pattern as today.

### TS1 (rewritten) — neutralization-primitive presence

The existing TS1 asserts `gh workflow disable` is in the agent prompt (token-revocation regression guard). Rewrite to:

- Assert the prompt contains the literal string `Neutralization primitive` (anchor on the heading).
- Assert the prompt contains `git push origin HEAD:` (direct-push leg).
- Assert the prompt contains `gh pr create --base` (PR-fallback leg).
- Assert the prompt contains `git diff --cached --quiet` (no-op-commit guard from `2026-03-02-github-actions-auto-push-vs-pr-for-bot-content.md`).
- Assert the prompt does NOT contain `gh workflow disable "$WORKFLOW_NAME"` as the operative cleanup call (a comment may reference it as "the previous mechanism" but no executable line should call it). To distinguish: assert the count of `^[[:space:]]*gh workflow disable "\$WORKFLOW_NAME"` (line-anchored, not in a fenced/quoted comment) is ZERO.
- Keep the existing "no post-step after claude-code-action" check unchanged.

### TS6 (new) — fallback-comment conditional structure

- Assert the prompt contains the literal fallback-comment text "Workflow ran but auto-cleanup failed" (NOT "auto-disable failed" — that's the previous mechanism's text).
- Assert the comment is conditional: there must be a sentence in the prompt body that gates the fallback comment on BOTH (5a direct push failed) AND (5b PR creation failed). Pattern match: regex like `[Bb]oth.*failed` or `5a.*AND.*5b` near the fallback-comment line. (This protects against a future regression where someone "simplifies" by always posting the fallback comment.)

### TS5 update — assertions block

In addition to the changes flagged in Phase 2:
- Drop `assert d['permissions']['actions'] == 'write'` from L379 verification example.
- Add `assert d['permissions']['contents'] == 'write'`.
- Add `assert d['permissions']['pull-requests'] == 'write'`.
- Add anti-regression assertion: `assert 'actions' not in d['permissions'] or d['permissions']['actions'] != 'write'`.
- The TS5 test file's existing assertions (`assert_contains "$ONCE_BLOCK" 'id-token: write'` at line 143-144) MUST stay — the OIDC requirement is unchanged.

### YAML-content-test anchoring discipline (carried forward from #3134)

Per session error #4 in the [`--once` template missing id-token learning](../learnings/2026-05-04-schedule-once-template-missing-id-token.md), bare-content matches against YAML produce false positives when the same string appears in a comment. ALL TS1 / TS6 assertions that target a YAML key MUST anchor on `<indentation> + <key>:` patterns (e.g., `^        uses: anthropics/claude-code-action`), never bare content match. The existing TS1 pattern uses this; preserve it.

- **Post-merge dogfood (Phase 6):** Real end-to-end test. Cannot be run pre-merge because the SKILL.md changes need to be on default branch for a fresh `--once` to use them.

The TDD gate's "Infrastructure-only tasks (config, CI, scaffolding) are exempt" applies in part — the SKILL.md changes ARE config-shaped, but the test file is the spec for SKILL.md content, so we still write/update tests first.

## Resume Prompt

```
/soleur:work knowledge-base/project/plans/2026-05-04-fix-schedule-d4-self-disable-via-yaml-edit-plan.md
Branch: feat-one-shot-3153-schedule-d4-self-disable
Worktree: .worktrees/feat-one-shot-3153-schedule-d4-self-disable/
Issue: #3153
Plan reviewed, implementation next.
```
