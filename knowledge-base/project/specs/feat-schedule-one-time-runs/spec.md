---
feature: schedule-one-time-runs
issue: 3094
pr: 3067
brainstorm: knowledge-base/project/brainstorms/2026-05-03-schedule-one-time-runs-brainstorm.md
status: draft
brand_survival_threshold: single-user incident
---

# Spec: `soleur:schedule --once` (one-time scheduled agent runs)

## Problem Statement

`soleur:schedule` only generates recurring cron workflows. When an agent finishes work that has a natural one-time follow-up — open a cleanup PR for a feature flag in 2 weeks, run a deploy verification, evaluate a staged rollout — there is no way to schedule a single deferred run that acts on the user's repo with their secrets.

The `claude-code` harness has its own `schedule` skill that supports one-time runs, but it executes in Anthropic's managed sandbox and cannot push commits, open PRs, modify branches, or invoke Soleur skills against the user's repo. The Soleur "offer-to-schedule" pattern (CLAUDE.md) tells agents to proactively offer one-time follow-ups, but the offer leads to a dead-end because `soleur:schedule` cannot accept it.

The motivating case: after PR #3062 merged, a follow-up investigation on issue #2688 was needed in ~2 weeks. The agent declined `/soleur:schedule` (recurring-only) and posted the investigation plan as a comment on #2688 — which has no resurfacing or execution mechanism. The plan will rot until someone manually triages hook-related issues.

## Goals

1. Add a `--once --at <ISO-date>` flag to `soleur:schedule create` that generates a one-time GitHub Actions workflow.
2. The workflow fires at the specified date, fetches its task spec from a referenced issue + comment, executes the documented work, and self-disables.
3. Stale-context guardrails are enforced in the agent prompt: verify OPEN issue/PR + existing branch + existing comment before acting; if stale, post observation comment and abort.
4. `/soleur:schedule list` distinguishes recurring vs one-time runs and shows fire status (pending / fired-disabled / fired-failed).
5. Documentation clearly explains when to use `soleur:schedule` (act-on-repo, runs in user's GHA) vs the harness `schedule` skill (think-and-report, runs in Anthropic sandbox).

## Non-Goals

- Generic reminder system. The harness `schedule` skill covers think-and-report cases.
- Self-deleting workflow files. The workflow stays on disk after firing (disabled-but-on-disk = audit trail; cleanup via separate `prune` command tracked as follow-on).
- Connected-repo path (`apps/web-platform/server/session-sync.ts` writing schedules into customer repos). Tracked as a separate issue requiring full CLO guardrail set.
- Replacing `feat-follow-through`. Condition-driven (HTTP/DNS predicate polling) and date-driven (fire at run_at) are different abstractions. Date-driven items in follow-through MAY migrate to `--once` at the operator's discretion; condition-driven stay.
- Recurring-to-one-shot conversion mode.
- PR output mode (current GitHub-issue output is sufficient).
- Discord/Slack notifications.
- Authorization TTL / re-confirmation for runs >14 days out (CLO recommendation; deferred to connected-repo issue).

## Functional Requirements

**FR1 — `--once` mode in `create`.** `/soleur:schedule create --once --at <ISO-date> --skill <name> --issue <N> [--comment <id>] [--name <name>]` generates `.github/workflows/scheduled-<name>.yml` with `schedule: cron` set to fire once at the specified date and `workflow_dispatch: {}` for manual triggering.

**FR2 — Issue + comment context reference.** The generated workflow stores `ISSUE_NUMBER` and `COMMENT_ID` as workflow `env` values. The agent prompt fetches the comment body at runtime via `gh api repos/{owner}/{repo}/issues/comments/${COMMENT_ID}` and uses it as the task spec. No prompt content is committed inline in the YAML.

**FR3 — Stale-context preamble.** The agent prompt template begins with verification steps that MUST pass before any action:
- Issue/PR `state` is OPEN (`gh issue view ${ISSUE_NUMBER} --json state`)
- Referenced comment still exists (`gh api .../comments/${COMMENT_ID}`)
- Any branch referenced in the spec still exists (`git ls-remote --heads origin <branch>`)
If any verification fails, the agent posts an observation comment to the originating issue describing the stale state and aborts without taking action.

**FR4 — Self-disable inside agent prompt.** The last instruction in the agent prompt is `gh workflow disable scheduled-<name>.yml`. This runs inside the agent's authenticated step, not as a post-step (post-steps lose App-token authentication per `2026-03-02-claude-code-action-token-revocation-breaks-persist-step`). If the disable call fails, the agent posts a fallback comment to the originating issue with the workflow name and a manual-disable hint.

**FR5 — `list` command distinguishes modes.** `/soleur:schedule list` parses workflow YAML to identify mode (recurring if cron expression matches recurring patterns; one-time if cron is a single fire-date) and reads `gh workflow view --json state` to show fire status. Output format:
```
[recurring] weekly-audit (runs Mondays 09:00)
[one-time]  verify-hook-fires (fires 2026-05-17, pending)
[one-time]  cleanup-flag-x (fired 2026-04-12, disabled)
```

**FR6 — Documentation: when to use which.** `plugins/soleur/skills/schedule/SKILL.md` adds a "When to use this skill vs the harness `schedule`" section. AGENTS.md adds a workflow-gate or Communication-section pointer to this distinction so future agents do not conflate the two.

**FR7 — Cron expression generation from `--at`.** `--at <ISO-date>` (format `YYYY-MM-DD` for the first iteration) generates a cron expression that fires exactly once on that date at 09:00 UTC. Accept `--at <YYYY-MM-DDTHH:MM>` as a future enhancement.

**FR8 — Idempotency.** Generated workflow includes `concurrency.group: schedule-once-<name>` (no `cancel-in-progress`). The first agent step verifies the workflow has not already been disabled (`gh workflow view --json state`); if it has, exit 0. Disable runs at the END of the prompt, BEFORE any destructive action — better to skip a retry than double-fire.

## Technical Requirements

**TR1 — Caps tighter than recurring defaults.** `timeout-minutes: 20` (vs 30 default). `--max-turns 25` (vs 30 default). `permissions: { contents: read, issues: write }` only — drop `id-token: write` unless explicitly required by the invoked skill.

**TR2 — SHA pinning preserved.** `actions/checkout@v4` and `anthropics/claude-code-action@v1` resolved via `gh api` and pinned to commit SHAs at create time, identical to the recurring path.

**TR3 — Reuse template.** The one-time template differs from the recurring template only in: the cron expression (single fire-date), the env block (ISSUE_NUMBER + COMMENT_ID), and the prompt preamble (verification steps). Avoid duplicating the entire YAML template — extract a shared base and override the differences.

**TR4 — `--at` validation.** Reject dates in the past. Reject dates more than 90 days out (sanity bound; revisit if needed). Use Python's `datetime.fromisoformat` or shell `date -d` with explicit format to parse, NOT `date -d` with arbitrary phrasing (per `2026-02-21-github-actions-workflow-security-patterns`: `date -d "last year"` is accepted and dangerous).

**TR5 — Comment fetch at runtime.** Workflow does NOT pre-fetch comment content at create time. The agent fetches `gh api repos/{owner}/{repo}/issues/comments/${COMMENT_ID}` inside its own prompt. This means the comment is editable until fire time and prevents stale content from being baked in.

**TR6 — Verify YAML write succeeded.** After writing the workflow file, `grep` for the cron expression and the env block to confirm content landed. Per `2026-03-26-milestone-enforcement-workflow-edits` and `2026-03-18-security-reminder-hook-blocks-workflow-edits`: hooks can soft-fail Edit/Write on `.yml` files — never trust the tool return.

**TR7 — Brand-survival threshold inheritance.** This spec's plan inherits `Brand-survival threshold: single-user incident` per `hr-weigh-every-decision-against-target-user-impact`. The plan's User-Brand Impact section is NOT re-authored; it carries forward verbatim from the brainstorm. Plan Phase 2.6 (template), deepen-plan Phase 4.6 (halt), preflight Check 6 (ship gate), and `user-impact-reviewer` (review companion) all gate on this threshold.

## Test Scenarios

**TS1 — Happy path: create, fire, self-disable.** Create a `--once` schedule for a date 1 day in the future against a test issue. Trigger via `workflow_dispatch`. Verify: agent fetches comment, executes task, calls `gh workflow disable`, posts result comment to issue. Verify post-fire: `gh workflow view --json state` returns `disabled_manually`.

**TS2 — Stale context: issue closed before fire.** Create a `--once` schedule. Close the referenced issue. Trigger fire. Verify: agent's preamble detects CLOSED state, posts an observation comment to the (now-closed) issue, exits without taking action.

**TS3 — Stale context: comment deleted.** Create a `--once` schedule. Delete the referenced comment. Trigger fire. Verify: agent detects missing comment, posts observation to the issue, aborts.

**TS4 — Idempotency: double fire.** Create a `--once` schedule, fire it once successfully (workflow disabled). Manually re-enable via `gh workflow enable`. Trigger again. Verify: agent's first step detects the already-disabled state in workflow history and exits 0 without re-acting.

**TS5 — Self-disable failure.** Mock `gh workflow disable` to fail. Trigger fire. Verify: agent posts fallback comment to originating issue with workflow name and manual-disable hint.

**TS6 — `list` output.** Create one recurring + one pending one-time + one fired one-time. Run `list`. Verify output groups correctly with status labels.

**TS7 — `--at` validation.** `--at 2025-01-01` (past) → rejected. `--at 2027-01-01` (>90 days out) → rejected. `--at 2026-05-17` (valid) → accepted.

**TS8 — Token revocation regression.** Confirm the self-disable runs inside the prompt, not as a post-step. Test by adding a deliberate post-step that calls `gh` and verifying it fails with auth error (regression guard for the token-revocation learning).

## Acceptance Criteria

- [ ] `/soleur:schedule create --once --at <date> --skill <name> --issue <N>` generates a working `.github/workflows/scheduled-<name>.yml`
- [ ] All 8 test scenarios above pass in CI
- [ ] `plugins/soleur/skills/schedule/SKILL.md` updated with `--once` documentation and "when to use this vs harness `schedule`" section
- [ ] AGENTS.md or constitution.md cross-references the harness-vs-soleur-schedule distinction (sized to fit byte budget)
- [ ] Brainstorm + spec committed and pushed; PR #3067 marked ready when implementation complete
- [ ] No regression in recurring-cron path (existing 22 scheduled workflows unaffected)
- [ ] User-impact-reviewer agent passes the PR (per `single-user incident` threshold)

## Open Implementation Questions

- Strict ISO date format only, or accept `--in '2 weeks'` syntactic sugar? Decide at plan time (lean strict for implementation; relative is a docs alias).
- Comment ID resolution UX: paste comment URL (skill parses) vs `--issue N` + auto-pick most recent operator comment. Lean URL parsing for explicitness.
- Should `/soleur:schedule create` without `--cron` and without `--once` error explicitly, or default to recurring? Lean explicit error.
