---
title: Brainstorm must re-derive option space + inventory from code; issue body is stale framing, not ground truth
date: 2026-05-12
category: best-practices
module: brainstorm
component: soleur-brainstorm-skill
problem_type: process_issue
severity: medium
tags: [brainstorm, issue-body-staleness, inventory-grep, option-space, pino, pseudonymization, hash-cli, sentry-setUser]
related_issues: ["#3698", "#3638", "#3685", "#3696", "#3701", "#3708"]
related_pr: "#3701"
source_session: brainstorm of #3698 (pino userId pseudonymisation) on 2026-05-12
---

# Brainstorm must re-derive option space + inventory from code; issue body is stale framing, not ground truth

## Problem

Issue #3698 was a multi-agent-review follow-up to PR #3685 (server-side userId pseudonymisation). The issue body authored 6 hours earlier enumerated three named approaches (A — per-site migration, B — pino-level redaction, C — hybrid) with C marked **recommended** and included a verified-at-merge inventory of "~24-27 sites across `server/` + `app/`."

If the brainstorm had accepted the issue-body framing as ground truth, it would have:

- Routed the work onto Option C with its known operator-grep regression.
- Sized sub-issues against a 27-site inventory.
- Missed that `Sentry.setUser()` is not called anywhere server-side today.
- Missed the operator-runbook prerequisite (no `hash-user-id` CLI exists).
- Locked PA8 §(c) wording into a two-path "[Redacted] + userIdHash" explanation that requires durable mid-migration carry.

The brainstorm instead re-derived four things from the live codebase, and the recommended option changed.

## Investigation

Five agents ran in parallel (CTO, CLO, CPO triad per `USER_BRAND_CRITICAL=true`; repo-research-analyst; learnings-researcher).

### Finding 1 — Option space was incomplete

Both CTO and learnings-researcher independently surfaced a **4th option** the issue body did not enumerate:

> Pino `formatters.log()` rename hook in `apps/web-platform/server/logger.ts` — runs before `redact`, can transform `{userId}` → `{userIdHash}` in place via the existing `hashUserId()` helper, single source of truth at logger boundary.

Repo-research confirmed pino exposes both `formatters.log()` and `serializers` (per `pino.d.ts:366,470`); the current `logger.ts:15-30` uses neither, so the API surface is fully available. The 4th option (Option D in the brainstorm) is strictly better than the issue-body Option C: same compliance posture, preserves operator grep via hash (vs. C's default-censor `[Redacted]` which drops the value), single PR instead of "1-line + N sub-issues."

### Finding 2 — Inventory was 2.5× too high

The issue body listed "~24-27 sites." A fresh `git grep -nE '(log|logger)\.(error|warn|info|debug).*\buserId\b' apps/web-platform/server/ apps/web-platform/app/` against the worktree's `main` HEAD returned **10 hits across 7 files**, all in `app/api/**/route.ts` and `app/(auth)/callback/route.ts`. Zero `server/` raw sites remain.

The drift is explained by what the issue body counted: pre-#3685 inventory (server/ sites that the helper module migration already absorbed) was carried forward into the issue body when the helper PR landed.

### Finding 3 — Sentry.setUser() is not called anywhere

CPO + repo-research both independently grepped `Sentry.setUser` and `setTag.*user` across all source: zero hits. The issue body and parent #3638 brainstorm implicitly assumed Sentry would be a "fallback identification channel" during any migration window. It isn't. Adding `Sentry.setUser({id: hashUserId(user.id)})` server middleware is a hidden-prerequisite, not a nice-to-have — without it, *any* approach (A/B/C/D) leaves a window where direct call sites' Sentry events have no user identity at all.

### Finding 4 — Operator runbook regression is real

CPO + CTO both surfaced: no `apps/web-platform/scripts/hash-user-id.ts` exists; operators currently `grep <raw-uuid> <hetzner-stdout>`. After redaction (Option B/C/D), they need a CLI to convert raw UUID → hash before grep can work. The CLI is 5 lines but its absence silently breaks oncall the moment the redaction PR merges, mid-incident.

## Solution

The brainstorm output reshaped #3698's scope substantially:

- **Selected approach:** Option D (pino `formatters.log()` rename hook), not the issue-body's recommended Option C.
- **Bundled deliverables in the same PR:** hash-user-id CLI, `Sentry.setUser` middleware binding, recursive nested-userId walker, helper migration of the 10 (not 27) call sites, PA8 §(c) single-path rewrite, PA8 §(f) Hetzner retention pin.
- **DPD §(l) telemetry entry** — pre-existing user-facing-disclosure gap CLO surfaced — filed as **#3708** out of scope.

Documented in:

- Brainstorm: `knowledge-base/project/brainstorms/2026-05-12-pino-userid-formatters-log-brainstorm.md`
- Spec: `knowledge-base/project/specs/feat-pino-userid-redaction-3698/spec.md`
- Issue #3698 body updated with Artifacts section (`gh issue edit 3698`)

## Key Insight

**Issue bodies authored at code-review time are framing, not ground truth.** They carry the reviewer's option enumeration, the count they saw at PR-merge, and the assumed prerequisite landscape. Each of these decays:

- **Option space decays slowest but is most consequential** — a 4th option the reviewer didn't know about can dominate the listed three. The brainstorm's Phase 1.1 "verifying issue-body architectural constraints" check covers *over-claimed* constraints; this learning extends it to *under-enumerated* options. Grep the actual API surface (`formatters`, `serializers`, `hooks`) of any library named in the issue body before accepting the option space.
- **Inventory decays fastest** — between issue body authoring and brainstorm execution, parallel PRs migrate, refactor, or absorb call sites. The brainstorm's "re-run the grep before starting" rule is correct; this case shows the drift can be 2.5×, not just a couple of sites.
- **Prerequisite landscape decays silently** — the issue body lists code prerequisites (helper module, pepper secret) but rarely lists operational prerequisites (CLIs, runbooks, dashboards, middleware bindings that would be load-bearing post-merge). The brainstorm's domain triad (CPO + CTO + CLO under `USER_BRAND_CRITICAL=true`) is the surfacing mechanism — CPO caught the missing Sentry.setUser; CTO caught the missing hash CLI. Neither would have surfaced from issue-body reading alone.

**For brainstorms triggered by an issue with named options:** treat the option list as a recall prompt, not the answer space. The "Recommended" tag is the reviewer's vote against the alternatives they thought of — not a vote against alternatives they missed.

## Prevention

Brainstorm skill behavior to keep:

1. **Phase 1.1 "verifying issue-body architectural constraints" check applies to options too.** When the issue body names "Option A / B / C," grep the relevant library's actual API surface (`pino.d.ts`, framework types, MCP schemas) for additional degrees of freedom before accepting the listed three. Specifically: when an issue body names a library config primitive (`redact`, `formatters`, `serializers`, `hooks`, `middleware`), the corresponding `.d.ts` is the source of truth for the option space.

2. **Always re-run the issue-body inventory grep against worktree `main`** before accepting any count or file list. Drift between issue creation and brainstorm execution is the norm, not the exception. For #3698, drift was 27 → 10 in 6 hours.

3. **For `USER_BRAND_CRITICAL=true` brainstorms, the CPO assessment must enumerate operational prerequisites** (CLIs, middleware bindings, runbook entries) separately from code prerequisites. A migration window with a working code primitive but a broken operator workflow is a brand-survival-threshold incident in itself.

4. **Treat "Sentry as fallback channel" claims as testable hypotheses.** Grep `Sentry.setUser` / `setTag.*user` / `setExtra.*user` before reasoning about Sentry-vs-pino migration tradeoffs. If `setUser` is absent, Sentry is NOT a fallback channel — it's an additional emit path that has the same identity gap as pino.

## Session Errors

**AskUserQuestion max-4-options validation error** — Initial scope-bundle question constructed 5 options; the tool rejected with `Too big: maximum 4 items`. Recovery: split into two AskUserQuestion calls (multi-select scope + single-select retention). **Prevention:** the brainstorm skill at `plugins/soleur/skills/brainstorm/SKILL.md` Phase 0.1 Step 1 already documents the 4-option cap explicitly. The rule exists; the violation is operator-side discipline. No workflow change warranted — tool-side enforcement already catches it.

## Cross-References

- `2026-05-07-brainstorm-verify-referenced-pr-state-and-leader-infra-claims.md` — sibling pattern: verify cited PR state before accepting sequencing claims from the issue body.
- `2026-05-11-brainstorm-grep-approach-hook-before-spawning-leaders.md` — sibling pattern: grep `main` for the approach-symbol before spawning leaders.
- `2026-05-12-brainstorm-defer-decision-issue-body-rule-drift-and-oauth-only-bundling-scope-bound.md` — sibling pattern: verify issue-body architectural constraints against the plugin-wide rule corpus.
- `2026-05-12-centralized-at-helper-boundary-transforms-overclaim-in-acs-and-disclosures.md` — names #3698 as the explicit follow-up of #3685; this learning extends it with the option-space pivot.
- `2026-05-12-multi-agent-review-catches-load-bearing-redaction-primitive-bypasses.md` — the multi-agent review pattern that originally produced #3698.
- `2026-05-12-plan-time-api-contract-verification-and-pipeline-via-package-json.md` — pino does NOT ship to Better Stack (Hetzner stdout only); informed the retention framing.
- `plugins/soleur/skills/brainstorm/SKILL.md` Phase 1.1 — existing "verifying issue-body architectural constraints" check (this learning is an extension, not a contradiction).
- AGENTS.md `hr-weigh-every-decision-against-target-user-impact` — the rule that triggered the triad spawn for this brainstorm.
- Issue #3698 — pino userId pseudonymisation (the issue this brainstorm processed).
- Issue #3708 — DPD §(l) telemetry user-facing entry follow-up (filed at Phase 3.6).
- PR #3701 — draft PR opened by Phase 0 worktree setup.
