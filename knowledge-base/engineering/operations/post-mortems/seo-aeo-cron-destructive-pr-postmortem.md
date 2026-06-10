---
title: "Weekly SEO/AEO audit cron opened a destructive PR deleting the plugin tree (#5026)"
date: 2026-06-10
incident_pr: 5026
incident_window: "2026-06-08T11:00Z – 2026-06-08T~12:00Z (single cron run; PR open until triage closed it 2026-06-10)"
recovery_at: "2026-06-10T00:00Z (PR #5026 closed + branch deleted at triage; structural fix merged via PR #5098)"
suspected_change: "TR9 Phase-2 migration of the SEO/AEO audit to the Inngest claude-spawn substrate (ephemeral-workspace rm+symlink of plugins/soleur) combined with the prompt's blanket git add -A"
brand_survival_threshold: aggregate pattern
status: resolved
triggers:
  - scheduled cron fire (0 11 * * 1 UTC, 2026-06-08)
art_33_triggered: false
art_34_triggered: false
art_33_deadline: "n/a — no personal data was accessed, exposed, or lost; the incident concerned repository source content (plugin tree deletions staged into a public PR of an already-public repo)"
---

## Actor key

- `agent` — Claude Code did this autonomously (no operator ack required).
- `agent-with-ack` — Claude Code did this AFTER operator confirmed via menu option per `hr-menu-option-ack-not-prod-write-auth`.
- `human` — Operator did this directly.

# Incident Overview

The weekly SEO/AEO audit cron (Inngest `cron-seo-aeo-audit`, migrated from GHA in TR9 Phase-2) opened PR #5026 on branch `ci/seo-aeo-audit-2026-06-08-113158` containing −107,368 lines: the entire tracked `plugins/soleur/` tree (654 files) deleted plus a modified `.claude/settings.json`. CI's 8 required checks (settings-edit blocker, tc-document-sha-guard, readme-counts, scan, critical-css-gate, test shards) all failed, the PR never became mergeable, and **no damage reached `main`**. Defense-in-depth (required checks) was the only layer that held; two upstream layers (workspace hygiene, staging discipline) had failed silently by design.

## Status

resolved

## Symptom

A bot-authored PR titled "fix(seo): weekly SEO/AEO audit fixes" whose diff deleted the plugin tree instead of containing audit fixes, with the generic body "Automated commit from SEO/AEO audit workflow."

## Incident Timeline

| Actor | Time (UTC) | Action |
|---|---|---|
| agent | 2026-06-08 11:00 | Cron fired; `setupEphemeralWorkspace` cloned the repo, rm-rf'd `repo/plugins/soleur`, symlinked it to the host plugin dir, and overwrote tracked `.claude/settings.json` (per-design scaffolding). |
| agent | 2026-06-08 ~11:30 | Spawned claude ran the audit, then executed the prompt's MANDATORY FINAL STEP: `git add -A` staged the 654 phantom deletions + the settings overlay; PR #5026 opened with auto-merge queued. |
| — | 2026-06-08 ~11:35 | 8 required CI checks failed; auto-merge never fired. |
| human | 2026-06-09/10 | Operator triage (CI-generated PR batch) found #5026, closed it, deleted the branch, filed #5091 (P1). |
| agent | 2026-06-10 | PR #5098: substrate symlink removed (root cause), `safeCommitAndPr()` handler-side persistence + deletion guard, hook blanket-staging deny set, parity test. |

## Participants and Systems Involved

Inngest cron `cron-seo-aeo-audit` (prod Hetzner node), `_cron-claude-eval-substrate.ts` ephemeral workspace, spawned `claude --print` eval, GitHub PR surface, branch-protection required checks.

## Detection (+ MTTD)

- **How detected:** CI required checks failed on the bot PR; surfaced to the operator during routine triage of CI-generated PRs. No paging alert fired (the PR-open path had no destructive-diff monitor).
- **MTTD:** ~1–2 days from PR-open to operator triage (CI blocked the damage at +minutes; human awareness lagged).

## Root Cause

Two layered defects, both deterministic:

1. **Workspace contamination (root cause):** `setupEphemeralWorkspace` replaced the clone's tracked `plugins/soleur` with a host symlink, so clone-git saw every tracked plugin file as DELETED on every run, and `.claude/settings.json` as modified. The symlink was also read-write — bot edits to plugin docs mutated the live host plugin install and were invisible to clone-git.
2. **Blanket staging:** the prompt's `git add -A` staged whatever the workspace looked like, violating `hr-never-git-add-a-in-user-repo-agents`. Two sibling crons carried the same blanket add; four more used scoped adds (safe by luck of write-target, not by construction).

## Remediation

Structural, three independent layers (PR #5098, closes #5091):

1. Substrate symlink removed — the clone's own tracked tree serves `--plugin-dir` (spike-verified under a scrubbed HOME); contamination class dissolved at the source.
2. `safeCommitAndPr()` deterministic handler-side persistence: scoped staging, clean-index precondition, deletion guard (max 10), issue-verified commit gate, non-throwing observability (Sentry ops + scheduled-issue comments), replay idempotency.
3. Containment-hook deny set for blanket staging forms on the live Tier-1 path + self-discovering parity test that blocks re-arming prompt-side persistence at Tier-2 restoration.

## Action Items & Follow-ups

| Issue | Item | Status |
|---|---|---|
| #5111 | Consolidate the remaining 9 bot commit pipelines (4 scoped-prompt + 5 legacy handler-side) onto `safeCommitAndPr`; decide stale-`ci/*`-PR watchdog at Tier-2 restoration; author the write-path ADR | open |

## Lessons

- A guard that "can never fire" in its own config table (allowedPaths describing paths that produce no diff) is a signal the root cause is still alive — fix the contamination, don't instrument it.
- The PR surface needs the same write-boundary discipline as direct pushes: required checks caught this, but only because the deletion shape happened to break 8 checks; a smaller destructive diff could have auto-merged. The deletion guard bounds that class structurally.
- Full learning: `knowledge-base/project/learnings/2026-06-10-bot-cron-safe-commit-substrate-symlink-removal.md`.
