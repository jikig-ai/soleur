---
title: Extend soleur:schedule with --once for one-time scheduled agent runs
date: 2026-05-03
status: complete
issue: 3094
pr: 3067
worktree: .worktrees/feat-schedule-one-time-runs
---

# Brainstorm: `soleur:schedule --once`

## What We're Building

A `--once --at <ISO-date>` flag on `soleur:schedule create` that generates a one-time GitHub Actions workflow. The workflow fires at the specified date, fetches its task spec from a referenced issue + comment, executes the documented work, and self-disables inside the agent prompt.

Scope is **act-on-repo use cases for plugin users running Soleur in their own repo**: open cleanup PRs, run migration checks, deploy verification, post-launch evaluations, feature-flag cleanup. Generic reminders ("ping me in 2 weeks") are out of scope — the harness `schedule` skill already covers think-and-report use cases.

## User-Brand Impact

**Artifact:** `soleur:schedule --once` — generated `.github/workflows/scheduled-*.yml` files committed to the user's repo, executed by `claude-code-action` against the user's secrets.

**Vector:** Token/secret leak via inlined prompts in workflow YAML; cross-tenant or wrong-repo execution; stale-context wrong action 2 weeks after authoring; reminder silently fails to fire.

**Threshold:** `single-user incident` — a single misfire posting an incorrect comment to a public issue, leaking context to git history forever, or executing on stale state would damage user trust irrecoverably. Brand-survival threshold flagged at brainstorm Phase 0.1; plan inherits this threshold per `hr-weigh-every-decision-against-target-user-impact`.

## Why This Approach

**Same skill, `--once` flag (not separate skill).** Code reuse with the recurring path; `list` and `delete` commands work for both modes; CTO and learnings researcher both recommended this; CMO's "Defer" verb branding is preserved as user-facing copy without splitting the skill surface.

**Issue + comment ID reference for task context (not inline prompt).** The motivating case had the investigation plan as a comment on issue #2688 — that pattern is directly reusable. Workflow stores `ISSUE_NUMBER` + `COMMENT_ID` env vars; the agent fetches the comment body at runtime via `gh api`. Survives `git revert` of unrelated changes; comment is editable post-schedule; no sensitive context lands in committed YAML.

**Self-disable inside the agent prompt (not a post-step).** Forced by `2026-03-02-claude-code-action-token-revocation-breaks-persist-step` learning: `claude-code-action` revokes the App token before subsequent steps run. The agent's last prompt instruction is `gh workflow disable scheduled-<name>.yml`; if the disable call fails, the agent posts a fallback comment to the originating issue.

**Stale-context guardrails non-negotiable.** Per CPO user-brand-critical mandate, the agent prompt template embeds a verification preamble: target issue/PR is OPEN, referenced branch exists, comment still exists. If any check fails, the agent posts an observation comment and aborts instead of acting on stale state.

**Don't merge with `feat-follow-through`.** Considered and rejected: condition-driven (HTTP/DNS predicate polling) and date-driven (fire at run_at) are different abstractions. Replacing follow-through with `--once` would force users to pre-guess when conditions will be met or rebuild polling inside `--once` agents. Date-driven items currently in follow-through can migrate to `--once`; condition-driven items stay.

## Key Decisions

| # | Decision | Rationale |
|---|----------|-----------|
| 1 | Extend `soleur:schedule` with `--once`, not a new skill | Code reuse; single user mental model; CTO + learnings researcher converge here. CMO "Defer" branding lives in user-facing copy without splitting the skill. |
| 2 | Same skill vs host `schedule` — keep both, document the fork | Host runs in Anthropic sandbox (think-and-report); `soleur:schedule` runs in user's GHA with their secrets (act-on-repo). They serve different jobs. SKILL.md gets a "when to use which" section. |
| 3 | Scope: plugin users in their own repo (this PR) | Skips heavy CLO guardrails for connected-repo. Connected-repo case tracked as a separate issue (TOS clause, prompt-redaction gate, authorization TTL). |
| 4 | API shape: `--once --at <ISO-date>` | One mode flag, structured date input. `list` shows `[recurring]` vs `[one-time, fires <date>]` vs `[one-time, fired <date>, disabled]`. |
| 5 | Context passing: issue + comment ID reference | No inline prompts in YAML (CLO concern: git history is permanent). Comment is editable post-schedule. Mirrors the motivating-case pattern (#2688 had its plan as a comment). |
| 6 | Self-disable inside agent prompt | Token revocation learning: post-steps can't authenticate. Last instruction in prompt: `gh workflow disable`. |
| 7 | Tightened caps for one-time runs | `timeout-minutes: 20` (vs 30 default), `--max-turns 25` (vs 30 default), `permissions: contents: read, issues: write` only. Drop `id-token: write` unless explicitly needed. |
| 8 | Stale-context preamble in agent prompt | Verify OPEN issue/PR + existing branch + existing comment; if stale, post observation comment and abort. Non-negotiable per user-brand-critical mandate. |
| 9 | Workflow file persists post-fire (not deleted) | Self-deletion would require a commit (collides with branch protection, token revocation). Disabled-but-on-disk = audit trail; cleanup via separate `/soleur:schedule prune` command. |
| 10 | Don't subsume `feat-follow-through` | Different abstractions (condition-driven vs date-driven). Migrate date-driven items only. |
| 11 | Naming: skill stays `schedule`; user-facing copy can use "Defer" | CMO branding for the announcement; skill API stays consistent. |
| 12 | Tracking: new feature issue #3094, not #2688 | #2688 is closed; reusing it would muddle scope. |

## Non-Goals

- Generic reminder system (host `schedule` covers it)
- Self-deleting workflow files (audit trail > zero-cost cleanup; disable-on-disk is correct)
- Connected-repo path (separate issue, requires full CLO guardrail set)
- Replacing `feat-follow-through` for condition-driven cases
- Recurring-to-one-shot conversion (YAGNI)
- PR output mode (current GitHub-issue output is sufficient)
- Discord/Slack notifications (out of scope; the issue comment IS the notification)
- Authorization TTL / re-confirmation for runs >14 days out (CLO recommendation, deferred to connected-repo issue)

## Open Questions

1. **Migration audit for `feat-follow-through`.** Which currently-registered follow-through items are date-driven (eligible for `--once` migration) vs condition-driven (stay)? Audit happens at plan time, not now.
2. **`--at` date format.** Strict ISO `YYYY-MM-DD` only, or accept relative phrasing (`--in '2 weeks'`)? CMO copy preference is the latter; CTO simplicity preference is the former. Decide at plan time; lean strict for the implementation, accept relative as a syntactic-sugar alias.
3. **Comment ID resolution UX.** Operator pastes a comment URL → skill parses out issue + comment IDs. Or operator passes `--issue N` and skill picks the most recent comment by the operator. Pick the simpler one at plan time.
4. **`/soleur:schedule prune` command.** Cleanup utility for fired-and-disabled one-time workflows. Out of scope for the first PR; tracked in #3094 as a follow-on.

## Domain Assessments

**Assessed:** Marketing, Engineering, Operations, Product, Legal, Sales, Finance, Support

### Engineering (CTO)

**Summary:** Self-disable via `gh workflow disable` is the right approach but must run inside the agent prompt (not a post-step) due to claude-code-action token revocation. Argument passing via issue + comment ID env vars is robust to drift. Tighten caps for one-time runs (timeout 20m, max-turns 25, drop `id-token: write`). Recommends an ADR for the self-disable + prompt-by-reference rationale.

### Product (CPO)

**Summary:** Initially recommended punting to host `schedule`, then aligned on extending `soleur:schedule` once act-on-repo cases were named. User-brand threshold is `single-user incident`; non-negotiable guardrails are: target ref exists, issue OPEN, prompt embeds verify-state-before-acting. YAGNI cuts: argument-passing complexity, PR output mode, recurring-to-one-shot conversion.

### Legal (CLO)

**Summary:** For plugin-user-in-own-repo scope (this PR), legal exposure is bounded — the user is consenting to themselves. For connected-repo (deferred), full guardrail set required: TOS "Scheduled Agent Authorization" clause, privacy-policy update, prompt-redaction gate, authorization TTL >14d, audit trail outside YAML. Non-inline prompt-passing (issue+comment ref) addresses CLO's biggest concern: no sensitive context in committed YAML.

### Marketing (CMO)

**Summary:** "Agents that come back" is a category-defining narrative beat aligned with Soleur's agent-native positioning. User-facing verb should be "Defer" or "Follow-up" (not "Remind/Wakeup/Snooze"). Channel plan: blog post + X thread + Discord + LinkedIn personal + changelog. Audience for one-time is broader than recurring (product-flavored, not ops-flavored). Skill name stays `schedule`; user-facing copy differentiates.

## Capability Gaps

None for this scope. Implementation surface is covered by existing primitives: `gh workflow disable`, `gh api` for comment fetch, existing `claude-code-action` integration, current `soleur:schedule create` template.

## Out-of-Scope Issues Tracked

- **#3093** — workflow improvement: thread Soleur-user + vision lens through plan/work/review/ship (surfaced during brainstorm)
- **TBD** — connected-repo path for `soleur:schedule --once` (CLO heavy guardrails); file at plan time once the act-on-repo path is shipped
- **TBD** — `/soleur:schedule prune` cleanup command for fired-and-disabled one-time workflows; file at plan time

## Resume Prompt

```
/soleur:plan #3094 — extend soleur:schedule with --once flag for one-time scheduled agent runs.
Brainstorm: knowledge-base/project/brainstorms/2026-05-03-schedule-one-time-runs-brainstorm.md
Spec: knowledge-base/project/specs/feat-schedule-one-time-runs/spec.md
Branch: feat-schedule-one-time-runs
Worktree: .worktrees/feat-schedule-one-time-runs/
PR: #3067 (draft)
Brand-survival threshold: single-user incident
```
