---
title: "Stale task premise + right-sizing an asymmetric security trade: the recurring Supabase RLS advisor on soleur-inngest-prd"
date: 2026-07-01
category: workflow-patterns
module: inngest-rls / one-shot
tags: [supabase, rls, advisor, inngest, one-shot, requires_cpo_signoff, right-sizing, deepen-plan]
related:
  - knowledge-base/engineering/architecture/decisions/ADR-030-inngest-as-durable-trigger-layer.md
  - knowledge-base/project/plans/2026-06-30-security-durable-rls-inngest-event-trigger-plan.md
  - knowledge-base/project/plans/2026-06-29-security-inngest-prd-enable-rls-lockdown-plan.md
pr: 5807
issue: 5813
---

# Learning: stale task premise + right-sizing the recurring RLS advisor on soleur-inngest-prd

## Problem

The operator received a Supabase security digest (dated 2026-06-28) flagging `rls_disabled_in_public`
(CRITICAL) on the Inngest backing project `soleur-inngest-prd` (`pigsfuxruiopinouvjwy`), reporting
"we fixed it yesterday but the alert came back." The `/soleur:go` route framed it as a recurring
*data-exposure hole* and proposed a `ddl_command_end` event trigger to auto-enable RLS on new tables.

## Root Cause — two distinct findings

### 1. The task premise was partly stale (caught by deepen-plan's live verification)

The premise "yesterday's fix was a manual `ALTER TABLE`, not durable — a new Inngest table re-opens
the anon hole" was **false on verification**. The 2026-06-29 lockdown (ADR-030 I8) already ships
`ALTER DEFAULT PRIVILEGES FOR ROLE postgres … REVOKE`, so a **new Inngest table is created with no
`anon`/`authenticated` grant** — anon cannot read it. The data-exposure hole was already closed.

What actually recurs is **only the cosmetic advisor lint**: a new table sits at `relrowsecurity=false`
until the next daily self-heal cron (`apply-inngest-rls.yml`) flips RLS on, so the lint (and its
CRITICAL email) fires for up to the cron interval — even though the table is unreadable by anon. The
recurring *email* was also a stale snapshot: it was dated 2026-06-28, before the 2026-06-29 fix.

### 2. The requested mechanism was an asymmetric trade (caught by review)

The event trigger fires *inside* Inngest's own `CREATE TABLE` transaction (`ddl_command_end`), so a
bug in it would **abort an Inngest goose migration** — a new failure mode on the brand-survival-critical
agentic-run path — purely to remove a *cosmetic* advisor email. The plan's `requires_cpo_signoff`
gate (and the deepen-plan's "right-sizing dissent" from the architecture + simplicity reviewers)
routed the primary-mechanism choice to the operator rather than autonomously building the riskier,
user-named option.

## Solution

CPO chose the cheaper, zero-new-risk alternative: tighten the existing `apply-inngest-rls.yml`
self-heal cron from daily (`17 4 * * *`) to **hourly** (`17 * * * *`). One line, zero new primitive,
zero new failure mode; the cosmetic advisor-recurrence window drops from ≤24h to ≤1h. ADR-030 I8
cadence updated + dated 2026-07-01 amendment-log entry; the event-trigger plan retained as a
rejected-alternative record (⛔ banner + `status: rejected-alternative` frontmatter).

## Key Insight

1. **When an operator says "we fixed it but the alert came back," verify the LIVE state AND read the
   prior fix before accepting the framing.** A recurring vendor security *email* dated before the fix
   is often a stale snapshot + a cosmetic lint lag, not a re-opened hole. The authoritative signal is
   the live catalog/advisor query, not the email.
2. **A one-shot must not silently implement a user-named mechanism when review surfaces it adds a real
   failure mode on a critical path to fix a cosmetic problem.** Surface the cheaper/safer alternative
   and let the operator decide (here, via `requires_cpo_signoff`). Naming a preferred approach in the
   task is not a mandate to build it past a reviewer's asymmetric-trade dissent.

## Session Errors

- **Planning subagent run #1 — transient API rate-limit.** Recovery: retried. Prevention: one-off
  infra flake, no recurrence vector; no workflow change.
- **Planning subagent run #2 — hit the account session limit after ~25 min / 50 tool uses**, returning
  without a `## Session Summary`. Recovery: one-shot's partial-artifact recovery path — the plan +
  deepen artifacts were already on disk (49 KB plan, `tasks.md`), so the pipeline continued from the
  on-disk plan instead of re-running. Prevention: already covered by one-shot Step 1-2 partial-artifact
  recovery; no workflow gap. (Reinforces `2026-05-15-subagent-crash-recovery-via-on-disk-artifacts`.)
- **`gh issue create` rejected — "must include --milestone".** Recovery: re-ran with
  `--milestone "Post-MVP / Later"`. Prevention: already hook-enforced (the BLOCKED message came from
  the pre-existing milestone-gate hook); no action.

## Tags
category: workflow-patterns
module: inngest-rls / one-shot
