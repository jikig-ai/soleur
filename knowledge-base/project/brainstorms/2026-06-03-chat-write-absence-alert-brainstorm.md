---
date: 2026-06-03
topic: chat-write-absence-liveness-alert
issue: 4849
lane: cross-domain
brand_survival_threshold: single-user incident
status: complete
---

# Brainstorm: Chat Write-Absence Liveness Alert (#4849)

## What We're Building

A liveness alert that fires when the interactive chat write path breaks, so a
silent outage is caught by instrumentation rather than by a user reporting it.

**Inverted framing (the load-bearing decision):** the issue asked to "alert on
the *absence* of writes" (zero `messages` INSERTs over N hours per workspace).
All three domain leaders independently converged on inverting this to **"alert on
attempted-but-*failed* writes."** The absence framing cannot distinguish a broken
write path from a legitimately idle workspace without an out-of-band activity
signal (the documented silence-detector trap), and at 0–1 users a per-workspace
silence timer false-positives constantly and gets muted — reconstructing the
original outage.

**MVP (this PR):** one code-managed Sentry issue-alert keyed on the Sentry op
`persist-user-message` (emitted today on every failed interactive insert, tagged
with the SQLSTATE `pg_code`). It pages the founder-operator on a sustained run of
insert failures. **Deferred (follow-up issue):** the scheduled prod write-absence
probe (the issue's literal Option A) as defense-in-depth for non-throwing
failures, once multi-tenancy / user count justify the prod-read infra.

## Why This Approach

Repo-research established the decisive facts:

- The interactive insert (`apps/web-platform/server/cc-dispatcher.ts:1487-1505`,
  in `dispatchSoleurGo`) runs through a tenant (RLS-scoped) client. An RLS
  WITH-CHECK reject (`pg_code 42501`) or a NOT-NULL violation (`pg_code 23502`)
  returns an `insertErr` → the code calls `reportSilentFallback(insertErr, { op:
  CC_OP_SLUGS.persistUserMessage, ... })` **and** throws. It does **not** silently
  affect 0 rows. So the failure mode that caused the original outage (NULL
  `workspace_id` → RLS reject; later NULL `template_id` → NOT-NULL) reliably emits
  a queryable Sentry signal.
- `reportSilentFallback` (`observability.ts:183-233`) does `Sentry.captureException`
  with a `pg_code` tag — so the signal is queryable by `op:persist-user-message`
  and discriminable by SQLSTATE.
- Code-managed Sentry alerts already exist: `apps/web-platform/infra/sentry/
  issue-alerts.tf` (the `byok_*` resources with `filters_v2` keyed on tags are the
  precedent), applied via `.github/workflows/apply-sentry-infra.yml`, gated by
  `sentry-audit-gate.yml`. The MVP is one new `sentry_issue_alert` — no UI clicks.
- This is inherently high-signal: it fires on *real failures*, never on silence,
  so it has **no idle-false-positive problem** (the CPO's core requirement).
- The original outage's Sentry signature was visible for 3 weeks but (a) buried
  under `history-fetch-404` error-noise (since reduced by #4816) and (b) watched
  by **no alert rule** (PIR factor 2). This alert closes factor 2 directly.

The deferred probe (Option A) is the more-complete-in-the-limit design but needs
net-new prod infra (a prd-scoped read-only Doppler service token —
`DOPPLER_TOKEN_PRD_SCHEDULED` does not exist; every existing `scheduled-*` probe
is dev-only per `hr-dev-prd-distinct-supabase-projects`), a SECURITY DEFINER
aggregates-only RPC, and an out-of-band attempt signal
(`user_concurrency_slots.last_heartbeat_at` — NOT `conversations.last_active`,
which is bumped in the same dispatch flow and would be tautological). Not
justified at 0–1 users (YAGNI).

## Key Decisions

| # | Decision | Rationale |
|---|----------|-----------|
| 1 | Invert "alert on absence" → "alert on attempted-but-failed writes" | Absence can't tell broken from idle; failure-signal is high-signal, zero idle false positives. Unanimous across CPO/CLO/CTO. |
| 2 | MVP = code-managed `sentry_issue_alert` on `op:persist-user-message` | Signal emitted today; reuses `issue-alerts.tf` + `apply-sentry-infra.yml`; no prod read, no privacy surface, no new token. |
| 3 | Discriminate by `pg_code` tag where useful (42501 RLS / 23502 NOT-NULL) | Both original failure layers (workspace_id, template_id) map to these SQLSTATEs; lets the alert/runbook name the class. |
| 4 | Global aggregate, founder-paged; NOT per-workspace | 0 beta users + tenant-zero; per-workspace alerting is premature noise. |
| 5 | Add a test asserting the op fires on insert failure | Guards against a future dispatch refactor silently dropping the op tag (the alert's only input). Pairs with the #4831 grep-sweep guard. |
| 6 | Privacy: alert payloads carry no raw `workspace_id` / content / email | `workspace_id == owner_user_id` for solo workspaces (ADR-038 N2) → it is personal data. Sentry already pseudonymizes userId (PR #3696 path). |
| 7 | Defer the scheduled prod write-absence probe to a follow-up issue | Net-new prod-read infra + out-of-band signal; warranted at multi-tenant scale, not now. |
| 8 | Visual design: N/A (no UI surface) | Pure Terraform + Sentry config + a test. Phase 3.55 trigger boundary, not a skip. |

## Open Questions (plan-time tuning)

1. **Alert threshold.** `EventFrequencyCondition` window/count (e.g. ≥2 events in
   1h, or any event sustained over two consecutive windows) — balance "page on a
   real outage" vs. "don't page on a single transient blip." Each event is a
   real user-facing error bubble, so the bar is low. Tune in the plan against the
   `byok_*` alert shape.
2. **Alert channel target.** `apply-sentry-infra.yml` defines the action targets;
   confirm the founder-paging route (email/Slack/PagerDuty) matches the existing
   `auth_*`/`byok_*` action config. Reuse, don't invent.
3. **op-tag-emission test surface.** Unit test on the `cc-dispatcher` insert
   catch vs. a higher-level assertion — plan to pick the cheapest that pins
   `op:persist-user-message` on an `insertErr`.
4. **Milestone placement.** CPO recommends folding #4849 into roadmap item 4.9
   "Monitoring + error tracking" (#673) and promoting it out of "Post-MVP /
   Later," since it is detection for the core surface. Operator decision.

## Domain Assessments

**Assessed:** Marketing, Engineering, Operations, Product, Legal, Sales, Finance, Support

### Product (CPO)

**Summary:** At 0 beta users (tenant-zero only; the outage was masked by a
service-role cron writing to a *different* workspace), a per-workspace silence
timer is the wrong model — it false-positives and gets muted, recreating the
outage. Invert to "alert on attempted-but-failed writes," global aggregate,
founder-paged. MVP = a Sentry alert on the failure signal; defer per-workspace
granularity and the probe to Phase-4-at-scale. Fold into roadmap 4.9 (#673).

### Engineering (CTO)

**Summary:** Option A (absence) suffers the idle-vs-broken ambiguity and needs an
out-of-band attempt signal outside the chat write boundary (else detection
tautology). Option B (Sentry on the failure op) is signal-viable: the insert
throws → fires `op:persist-user-message` + `pg_code`. Recommend the Sentry alert
as MVP; if a probe is later built, gate it on `user_concurrency_slots` heartbeat
(out-of-band), use an aggregates-only SECURITY DEFINER RPC, and a prd-scoped
read token. Biggest risk: a tautology if the attempt signal shares the chat
write path.

### Legal (CLO)

**Summary:** Founder-grade; no specialist threshold tripped. Load-bearing
guardrail: `workspace_id == owner_user_id` for solo workspaces (ADR-038 N2), so
it is personal data — alert payloads (GitHub issue, ops email, Sentry) must carry
at most a *count* of affected workspaces, never a raw `workspace_id`, never
message content, never email. For the deferred probe: aggregates-only SECURITY
DEFINER RPC (`count` + `max(created_at)`, never the 13 `MESSAGE_REDACT_FIELDS`
columns), CI token gets EXECUTE-only, search_path-pinned per
`cq-pg-security-definer-search-path-pin-pg-temp`; a one-line Article 30 PA-2 TOM
note, not a new processing-activity row.

## User-Brand Impact

- **Artifact:** the interactive chat write path (`messages` INSERT in
  `dispatchSoleurGo`) and its Sentry instrumentation.
- **Vector:** if the alert silently fails to fire (bad threshold, dropped op tag,
  wrong channel target), a future write-path regression goes undetected and users
  silently lose chat messages for an extended period — the exact failure this
  feature exists to prevent.
- **Threshold:** `single-user incident` (a single founder/tenant-zero user losing
  the core surface for weeks is brand-survival, per the source PIR).
- **Guardrails carried to plan:** (1) a test pinning `op:persist-user-message`
  emission on insert failure (the alert's only input); (2) reuse the existing
  Sentry action-target config; (3) no raw `workspace_id`/content/email in any
  alert payload.

## Session Errors

1. **Cited PIR appeared "missing on main."** The premise probe found
   `knowledge-base/engineering/ops/post-mortems/chat-rls-workspace-id-outage-postmortem.md`
   absent on `main`. It is **not** missing — it is in-flight on a sibling worktree
   (`feat-ui-visual-qa-gate`), authored by the same incident response, not yet
   merged. Resolved by reading it from the sibling worktree (read-only). The
   feature premise (real outage; fixes #4831/#4848 merged) held regardless.
   **Prevention:** when a cited artifact is absent on `main`, check sibling
   worktrees before recording it as a gap — in-flight PIRs commonly lag the
   prevention follow-up that references them.
2. **Cited Sentry op `Failed to save user message` "did not exist" (CTO).** A
   literal grep for that string matched only the thrown `Error.message`
   (`cc-dispatcher.ts:1505`), not a Sentry tag — leading to a transient "Option B
   not viable" conclusion. The *alertable* identifier is the op slug
   `persist-user-message` (`CC_OP_SLUGS.persistUserMessage`), which **is** emitted.
   Adjudicated by repo-research grepping the consuming symbol, not the prose
   string. **Prevention:** verify "signal X exists" by grepping the specific
   emitting symbol (op slug / tag constant), not the human-readable message.

## Sources

- Source PIR: `knowledge-base/engineering/ops/post-mortems/chat-rls-workspace-id-outage-postmortem.md` (on `feat-ui-visual-qa-gate`; factor 2 = this follow-up).
- Fixes: PR #4831 (workspace_id), PR #4848 (template_id) — both merged.
- Prior art: `knowledge-base/project/learnings/2026-06-01-silence-detector-needs-out-of-band-liveness-signal.md`; `2026-06-01-best-effort-cron-monitor-liveness-not-success-and-offhost-visible-warn.md`.
- Substrate: `apps/web-platform/infra/sentry/issue-alerts.tf`; `.github/workflows/apply-sentry-infra.yml`, `sentry-audit-gate.yml`; `.github/workflows/scheduled-realtime-probe.yml` (probe pattern for the deferred follow-up).
