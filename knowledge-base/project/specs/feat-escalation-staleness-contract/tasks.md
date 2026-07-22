---
feature: action-required escalation staleness contract
issue: 6836
lane: cross-domain
brand_survival_threshold: single-user incident
plan: knowledge-base/project/plans/2026-07-22-feat-action-required-staleness-contract-plan.md
---

# Tasks: action-required Escalation Staleness Contract

> Recommended: run `/deepen-plan` before `/work` (single-user-incident threshold;
> the close-authority cron warrants the data-integrity + architecture substance pass).

## Phase 0 — Preconditions (verify)
- [ ] 0.1 Re-confirm public asset + live private workflow use `--assignee "${OPERATOR_GH_LOGIN}"` (`operator-digest.workflow.yml:117,122`).
- [ ] 0.2 `gh variable list -R jikig-ai/operator-digest` → `OPERATOR_GH_LOGIN` set; `gh api repos/jikig-ai/operator-digest/assignees/deruelle` exits 0.
- [ ] 0.3 Read `cron-content-publisher.ts` end-to-end as the cron structural template (dedup read, auto-close, `op:` emit, workspace-root resolution).

## Phase 1 — Layer 1: Delivery verify + failed-run self-report
- [ ] 1.1 Add `if: failure()` self-report step to `plugins/soleur/skills/operator-digest/assets/operator-digest.workflow.yml` — files ONE idempotent `action-required` issue assigned to `${OPERATOR_GH_LOGIN}` ("⚠️ Weekly digest run FAILED — no digest this week (run <id>)").
- [ ] 1.2 Document/execute re-provision to the private repo (`provision-operator-digest-repo.sh`).
- [ ] 1.3 (Post-merge) `gh workflow run "Operator weekly digest" -R jikig-ai/operator-digest`; confirm digest issue `assignees=[deruelle]`. Ref #6836.

## Phase 2 — Layer 2: Triage render (de-pollute at predicate)
- [ ] 2.1 Rewrite `operator-digest/SKILL.md` §4 harvest: `--json number,title,url,createdAt,labels`.
- [ ] 2.2 Action-list predicate excludes labels `decision-challenge`/`content`/`content-publisher` (keep `content-starvation`).
- [ ] 2.3 Sort by (priority desc, age desc); "🔴 Open longest" mini-block with per-item age (days); cap action list at 8 + "+M more".
- [ ] 2.4 New separated informational block: open `decision-challenge` issues, capped 5 + "+M more".
- [ ] 2.5 Update `plugins/soleur/test/operator-digest-skill.test.sh` for the new §4 contract; run `components.test.ts` if the description line changed.

## Phase 3 — Layer 4: SLA lifecycle cron (fail-safe close authority)
> Architecture = dispatcher/worker fan-out (see plan `## Deepening` D1–D6). Read cron-content-publisher.ts first as the precedent.
- [ ] 3.1 **Dispatcher** `cron-action-required-sla.ts`: (a) read + **paginate to exhaustion** the open `action-required` backlog (Octokit `.paginate`, or oldest-N cursor) — NOT a single `per_page` page (D2/fatal); (b) `step.sendEvent` one `sla/issue.process` per issue with idempotency key `sla-${n}-${action}-${threshold}` (D1); (c) own Sentry heartbeat.
- [ ] 3.2 **Worker** `sla-issue-process.ts` (`inngest.createFunction` on `sla/issue.process`): process ONE issue; own Sentry monitor slug + top-level `reportSilentFallback` (D6). Each side-effecting write in its OWN `step.run` with deterministic id `escalate-${n}-${threshold}`/`expire-${n}`; comment split into its own step (D2).
- [ ] 3.3 Classify by agent-owned allowlist: OPS (default, never close); DEAD-CONTENT = `content-publisher` AND NOT `content-starvation` (NOT broad `content`); DECISION-CHALLENGE = `decision-challenge`; unclassified → OPS.
- [ ] 3.4 Human-engagement veto: abort close on non-bot assignee / non-bot comment/reaction / human-set priority (attribute the `labeled` actor via events/timeline API — D5; else gate on assignee + non-bot-comment only).
- [ ] 3.5 OPS escalation ladder (age from memoized `runStartedAt` vs `createdAt`): 14d→≥p2; 30d→p1+comment; 60d→p0+comment. Idempotent: bump upward only; **sentinel `<!-- sla:escalate:${threshold} -->` in the comment body**, GET-guarded (D2), NOT a trailing label.
- [ ] 3.6 Expiry (DEAD-CONTENT/DECISION-CHALLENGE): inactivity from **last NON-BOT timeline event** (same predicate as the veto), NOT raw `updatedAt` (D3/fatal). ≥30d non-bot-inactive → close `not planned` + `wontfix-stale` + reason comment. Skip if already closed / already `wontfix-stale`.
- [ ] 3.7 TOCTOU: before each close re-fetch + re-classify + re-veto; abort if raw ISO `updatedAt` string changed since snapshot (not a re-parsed Date — D2).
- [ ] 3.8 Reopen guard (D4): on reopen strip `wontfix-stale` + reset activity; require ≥1 fresh non-bot signal before re-closing a `wontfix-stale`-bearing issue.
- [ ] 3.9 Emit `op:"action-required-sla"` per action (from the WORKER) with `{issue, ageDays, inactiveDays, class, action, priorityBefore, priorityAfter, humanEngaged}`.
- [ ] 3.10 Register BOTH functions at the `serve()`/`functions: [...]` site (grep where cron-content-publisher registers).
- [ ] 3.11 Tests (dispatcher + worker): OPS@999d never closed; `content`-tagged ops → OPS; DEAD-CONTENT@30d-non-bot-inactive closed not @29d; bot-commented-every-7d issue still expires (D3); DECISION-CHALLENGE@30d; human-veto (assignee/comment/priority); pagination >1 page drops nothing (D2); sentinel dedup posts no 2nd comment; reopen guard (D4); TOCTOU abort; idempotent bump.

## Phase 4 — Observability, ADR, backfill
- [ ] 4.1 Add Sentry rule (`apps/web-platform/infra/sentry/issue-alerts.tf`) on `op:"action-required-sla"` action:"expire" where `humanEngaged:true`/TOCTOU-changed, and on action:"error".
- [ ] 4.2 Author ADR (close-authority boundary) via `/soleur:architecture`; Alternatives Considered = aggressive auto-close (rejected), nag-only (rejected).
- [ ] 4.3 (Post-merge) First SLA cron run = FR5 backfill; verify next digest action list is clean (no content/decision-challenge; per-item age shown).

## Phase 5 — Verify & ship
- [ ] 5.1 `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`.
- [ ] 5.2 `scripts/test-all.sh` green (no orphan guard suites broken).
- [ ] 5.3 File ONE follow-up issue (net-issue-flow): producer relabeling (stop double-stamping `action-required` on decision-challenge/content) so the label regains literal meaning.
- [ ] 5.4 `/review` → `/ship`.
