---
title: Ship pipeline silently dropped local commits when origin/main was already in sync
date: 2026-05-12
category: workflow-patterns
tags: [integration-issues, claude-hooks, ship, fail-open]
related_prs: [3624, 3627, 3630, 3632, 3633]
related_rules: [wg-ship-push-before-merge, wg-after-a-pr-merges-to-main-verify-all]
---

# Ship pipeline silently dropped local commits when origin/main was already in sync

## Problem

The `/soleur:ship` orchestrator queued `gh pr merge --squash --auto` on PR #3627 without verifying that all local commits were pushed to the remote. Two of the five branch commits — the actual workflow fix and the review fix — were committed locally and never reached `origin/<branch>`. The squash-merge consumed only the three pushed commits (planning artifacts), producing a `MERGED` PR that contained none of the fix it was meant to ship.

| PR | Intent | What landed | How the gap surfaced |
| --- | --- | --- | --- |
| #3624 | Fix `critical-css-gate` path filter + Playwright cache | initial fix — scoping + cache-key changes | merged green |
| #3627 | Recover lost #3624 fix (workflow file + cache-key) | **only planning artifacts** — actual `ci.yml` and cache-key edits never pushed | post-merge `critical-css-gate` on `main` failed with the same chromium error #3624 was meant to fix |
| #3630 | Cherry-pick orphaned commits from reflog | actual workflow fix + cache-key | caught by post-merge CI on `main`, NOT by the ship pipeline |

This is a **fail-open** class — the worst kind: the orchestrator believed it had shipped the PR, GitHub returned `MERGED`, and only a coincidentally-aligned post-merge gate (which re-exercised the same code path) surfaced the discrepancy. A different class of fix (security headers, copy change, anything without a post-merge gate that re-runs the affected code) would have shipped a successful "fix" PR containing nothing of substance and gone undetected indefinitely.

## Root cause — three layers of fail-open

1. **Hook layer:** `pre-merge-rebase.sh:167-170` early-exits when `origin/main` is already merged into the feature branch (i.e., `merge-base HEAD origin/main == origin/main`). It checks branch-vs-`main` sync but never compares `HEAD` against `origin/<branch>`. The auto-sync-and-push path would have pushed any local commits as part of the merge — but the no-sync path exits silently.
2. **Skill layer:** `plugins/soleur/skills/ship/SKILL.md` Phase 6 step 1 documents `git push -u origin <branch>`, but Phase 6 runs **early** in the pipeline; subsequent commits (review fixes, ship's own preflight commits) never re-push. The orchestrator's path through `preflight → gh pr edit → gh pr ready → gh pr merge --squash --auto` skipped the push.
3. **API layer:** `gh pr merge --auto` (and the GitHub UI merge button) consume the PR head ref on origin — local-only commits are invisible to the queue. GitHub's `MERGED` state reflects what's on origin, not what the agent committed locally. There is no API signal for "the PR merged but didn't carry the diff you expected."

## Solution — three-layer defense, hook is primary

| Layer | Surface | Bypass cost |
| --- | --- | --- |
| Layer 1 (mechanical) | `.claude/hooks/ship-unpushed-commits-gate.sh` PreToolUse hook | Cannot be bypassed by an agent in degraded reasoning; fires even outside the ship skill. |
| Layer 2 (prose) | `plugins/soleur/skills/ship/SKILL.md` Phase 6.4 | Skill loader injects into ship's working context; instructs the agent + provides a headless shell snippet. |
| Layer 3 (rule) | `AGENTS.core.md` `wg-ship-push-before-merge` | SessionStart hook injects into every session preamble; cross-surface contract for non-Soleur invocations. |

The hook intercepts every `gh pr merge` (including chained forms like `gh pr ready && gh pr merge`), runs `git rev-list origin/<branch>..HEAD --count`, and denies the tool call with a message listing the unpushed SHAs when the count is > 0. Ordered AFTER `pre-merge-rebase.sh` in `.claude/settings.json` so the sync-then-push path (when it fires) runs first and the gate then sees the post-push state.

**Why all three layers when one would catch the bug?** The original incident had Phase 6's prose-level `git push -u origin <branch>` instruction in place — and was bypassed by an orchestrator path that skipped Phase 6 entirely. Prose alone is insufficient because reasoning can degrade or skip; the hook is fail-closed by mechanism. The skill+rule layers backstop the hook for surfaces where it cannot fire (headless shells outside the harness, GitHub Actions workers, manual `gh` invocations from an operator terminal).

## Key Insight

**GitHub's `MERGED` state reflects what's on origin, not what the agent committed locally.** Any fail-open class on the push step is invisible to GitHub and to the orchestrator. Trust-the-API verdicts must be paired with local-state verification — `gh pr merge` returning success says nothing about whether the merge SHA contains the diff you expected.

A complementary follow-up (out of scope for this PR) would extend `wg-after-a-pr-merges-to-main-verify-all` from "release workflows verified" to "merge-SHA diff verified against the local pre-merge tree." That gate catches the bug AFTER `main` is corrupted, not before — but it closes the silent-success path for fix classes that have no post-merge gate exercising the same code.

## Out-of-scope (filed as follow-up)

The PreToolUse hook protects only `gh pr merge` invocations dispatched through Claude Code's Bash tool. `.github/workflows/scheduled-*.yml` has 14 additional `gh pr merge` call sites running inside GitHub Actions runners. These are not protected by the hook — the runner's job typically writes a file, `git add`/`commit`/`push`, then `gh pr merge --auto` in the same step (the push is sequential, so the unpushed-commits class observed in #3624 does not arise the same way). The AGENTS.md rule is the cross-surface contract; an audit follow-up will assess per-workflow risk empirically once the hook has accumulated 30 days of telemetry.

## Session Errors

None during implementation — the hook was a straightforward extension of the `pre-merge-rebase.sh` pattern. T9 (fetch network failure → PASS fail-open) initially looked like it might want a deny (so we don't silently miss the bug on a flaky fetch), but the sibling hook's convention (`pre-merge-rebase.sh:142-145`) is fail-open on fetch failure, and matching that convention won. The trade-off: false-negative (rare, only on a network failure) vs false-positive (operator confusion on every network blip). Honoring the sibling convention keeps the hook family's behavior consistent.
