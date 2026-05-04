---
title: claude-code-action App installation token caps `actions:*` at READ — workflow-level `actions: write` is cosmetic
date: 2026-05-04
pr: "#3155"
issue: "#3153"
tags: [github-actions, claude-code-action, permissions, schedule-skill]
---

## Problem

The `--once` template's D4 cleanup (`gh workflow disable "$WORKFLOW_NAME"` as the last instruction inside the agent prompt) **failed at runtime** despite the workflow declaring `permissions: actions: write`. Every successful `--once` fire posted a user-visible "Workflow ran but auto-disable failed. Manual: …" comment, and the workflow remained `active` until manually disabled.

Surfaced via the round-3 dogfood against issue #3049 ([run 25314106006](https://github.com/jikig-ai/soleur/actions/runs/25314106006), 2026-05-04 ~10:32 UTC). The same agent run successfully invoked `gh api` on issues endpoints (`issues: write`) but failed on `gh workflow disable` (`actions: write`) — a clean split confirming the failure is not transient.

## Root Cause

`anthropics/claude-code-action@v1` substitutes its **own short-lived GitHub App installation token** for `GH_TOKEN` inside the agent's bash subprocess. The official Anthropic GitHub App's `github-app-manifest.json` requests these install-time permissions:

| Permission | Scope |
|---|---|
| `contents` | write |
| `issues` | write |
| `pull_requests` | write |
| `actions` | **read** (not write) |

Workflow-level `permissions: actions: write` cannot **widen** the App's effective install-time scope — it can only **narrow** what the App is allowed to do in this run. So `gh workflow disable` (which requires `actions: write`) returns 403 regardless of what the workflow's `permissions:` block declares. The declaration is purely cosmetic.

The action's docs at `docs/security.md` and `docs/setup.md` recommend custom GitHub App installation for users who need permissions beyond the official App's set, but do NOT explicitly document this install-time-vs-workflow-level cap.

## Resolution

Replaced `gh workflow disable` with a **YAML-edit-and-push** primitive in the agent prompt (#3155):

1. Read+Edit the workflow YAML to strip the `schedule:` trigger.
2. `git add` + `git diff --cached --quiet` (no-op guard).
3. `git commit` with the `claude[bot]` identity.
4. Direct push to default branch; if blocked by branch protection, fall back to ephemeral branch + PR + `gh pr merge --squash --auto`.
5. Fallback comment posted ONLY when both direct push and PR creation fail.

This uses `contents: write` (which the App reliably honors) and `pull-requests: write` (App also has). `actions: write` is **dropped from the canonical template** with an anti-regression assertion to prevent copy-paste re-introduction.

## Lesson

When designing a `claude-code-action` workflow that needs to mutate the repo or its surroundings, lean on permissions the App's installation manifest grants:

- ✅ `contents: write` (commits, pushes)
- ✅ `issues: write` (`gh api`, `gh issue comment`)
- ✅ `pull-requests: write` (`gh pr create`, `gh pr merge`)
- ❌ `actions: write` (App caps at READ)
- ❌ `id-token: write` — required for OIDC handshake; without it the action exits before the prompt body runs ([#3134 learning](../../2026-05-04-schedule-once-template-missing-id-token.md))

If a future capability needs `actions: write` (e.g., re-running other workflows, deleting workflow runs), document that the user must install a **custom GitHub App** with `actions: write` and pass it via `claude-code-action`'s `github_app_*` inputs. Don't ship a default that requires it.

## Related

- [2026-03-02 — claude-code-action token revocation breaks persist step](../2026-03-02-claude-code-action-token-revocation-breaks-persist-step.md) — different bug, related root surface (claude-code-action's token strategy diverges from workflow GITHUB_TOKEN expectations).
- [2026-03-02 — github-actions auto-push vs PR for bot content](../2026-03-02-github-actions-auto-push-vs-pr-for-bot-content.md) — supplies the `git diff --cached --quiet` no-op-commit guard adopted by the neutralization primitive.
- [2026-05-04 — schedule-once template missing id-token](../2026-05-04-schedule-once-template-missing-id-token.md) — sister bug in the same `--once` template; supplied the YAML-content-test anchoring discipline used in TS1/TS6.
