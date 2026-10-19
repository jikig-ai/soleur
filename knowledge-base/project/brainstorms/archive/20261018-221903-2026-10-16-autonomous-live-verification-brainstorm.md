---
date: 2026-10-16
topic: autonomous-live-verification
branch: feat-qa-autonomous-live-verification
pr: 10446
issue: 10449
lane: cross-domain
brand_survival_threshold: single-user incident
status: brainstorm-complete
---

# Brainstorm: Soleur drives its own live verification (no "go click this" hand-off)

## What We're Building

Soleur performs the live, post-deploy verification step itself through Playwright, including flows that need an
agent (Concierge) session, instead of pausing with "ask the Concierge in the web app… only you can start that
session." Trigger case: after the `egress-audit-collection` flag flip for a canary org, the agent stopped because
the first CONNECT had to come from a web-using Concierge session in the canary workspace.

Scope chosen (operator, 2026-10-16): **Soleur-first + contract.** v1 makes Soleur verify its own app end to end.
The user-app contract (`qa-fixtures` manifest) is specified and recorded in an ADR now; its parser and any
customer-app provisioning are built when a second app needs it.

## Why This Approach

A harness already exists (ADR-064, `apps/web-platform/scripts/live-verify/run.ts`, #5452 closed by #5453). The
"no harness / need a new QA agent" framing is stale. The gap is narrower:

1. `run.ts` drives ONE hardcoded flow (new chat → Recent Conversations rail, `run.ts:1195-1303`). It cannot start
   a Concierge web-fetch, and has no flag-segment awareness or Sentry/Better Stack/DB assertions.
2. The synthetic principal is a user with zero `scope_grants`; the agent Send route is designed to 403 for it
   (`I-action-send-free`, `run.ts:14-30`). Whether a plain Concierge URL-fetch crosses that line is unverified.
3. `postmerge/SKILL.md` (~lines 239, 387-393, 593, 620) still calls the gate REPORT-ONLY. CI has been **blocking
   since 2026-06-18** (`web-platform-release.yml` "Enforce live-verify gate", #5463 CLOSED). Agents read the skill,
   so the doc misleads them. (CPO and CTO each described the gate state wrongly; re-derived from the workflow.)
4. Nothing in `flag-set-role` / `postmerge` / `ship` tells the agent that "run a live session" is automatable, so it
   falls back to the operator.

Rejected: a new QA agent/skill. Existing split is clean (`qa` = pre-merge, mock/local; `postmerge` = post-deploy
orchestrator and tri-state recorder; `test-browser`/`agent-browser` = agent-driven smoke, no cookie injection,
excluded from the gate). A fourth browser driver would duplicate all three.

## Key Decisions

| Decision | Choice | Rationale |
|---|---|---|
| New QA agent? | **No.** Extend harness + `postmerge` | CPO + CTO converge; avoids a duplicate of qa/test-browser/postmerge. |
| Architecture | `run.ts` becomes a runner of declared **flow specs** (`scripts/live-verify/flows/<name>.ts`); first new flow = Concierge URL-fetch with a Sentry/DB assertion | CTO ruling. Plan-time emission of flow specs (executable AC) stays deferred from #5452. |
| Prod test org | **Reuse ONE long-lived synthetic workspace.** No new prod accounts per run | ADR-064 allows one principal; `hr-dev-prd-distinct-supabase-projects`; CLO no-go on service-role teardown; WORM audit rows block `deleteUser`. |
| Dev/staging test org | Fresh org per run via Supabase admin API, torn down by marker | Deterministic, CAPTCHA-free; avoids signup-flow Playwright (CAPTCHA, email confirm, ToS). Deferred past slice 1. |
| Flag-segment membership | The synthetic org is added at flip time: the operator's one typed-`yes` flip carries `--org <synthetic-org-id>` alongside the canary org. The verifier performs no flag write | ADR-249: agent shells get exit 64 on `flag-set-role` writes (migration to staged approval is #9387). |
| Teardown | `finally` block deletes by `lv-<runid>` marker as the user's own RLS session; read-back asserts zero residue. `CANT-TEARDOWN` escalates, never reaps | ADR-064 invariants. Scheduled reaper deferred. |
| Credentials | Doppler only (`doppler run -c prd`), redact-before-persist (`redact.ts`), no `!` prefix for secrets; new Sentry/Better Stack read scope for assertions | `hr-never-paste-secrets-via-bang-prefix`; CTO. |
| Honest limits | CAPTCHA, third-party OAuth, 2FA, payment, email-only signup → `CANT-RUN:operator-only:<capability>` + filed issue, never PASS/skip | `hr-never-label-any-step-as-manual-without`. |
| User-app contract | Committed `qa-fixtures` manifest (personas, seed entry, auth mode, flag keys, base URLs, teardown entry, assertion sources, `unautomatable` list). Spec + ADR now, parser later | Soleur-first + contract (operator choice). |
| Customer apps | Non-prod by default; customer **prod** only with explicit opt-in + Art. 28 instrument | CLO: DPA/tenant register empty (#4330, #3723). |
| Enforcement | Rule/skill wording first (postmerge, flag-set-role, ship, hr-exhaust/hr-never-label); hook lint on hand-off phrases deferred | Technical fork delegated to CTO per `hr-technical-fork-is-not-an-operator-question`. |

## User-Brand Impact

- **Artifact:** the live-verification harness, its provisioning/segment-join path and the `postmerge` gate.
- **Vector:** a verifier that mints, mutates or leaks a real user's session/data, or that emails/bills a real
  third party, or leaves synthetic rows in prod analytics/billing.
- **Threshold:** `single-user incident`.

## Open Questions

- **Does a Concierge URL-fetch run under a principal with zero `scope_grants`?** `I-action-send-free` says agent
  Send 403s. If so, the flow needs either a scoped read-only grant (ADR-064 amendment) or a different trigger.
  Verify in the plan phase (CTO + `run.ts:14-30` + the agent send route).
- Which assertion sources are readable without new credential classes (Sentry token scope, Better Stack from
  Doppler `prd_terraform`, DB read via the synthetic RLS session)?
- Synthetic email: controlled domain + reserved prefix + per-run nonce; outbound-mail suppression for the
  synthetic org (Resend retains 30 days, no delete API).
- Stripe test-mode only; confirm no live-key path from the synthetic workspace.
- `seed-qa-user.sh` has no Article 30 register entry (CLO grep); register line + `gdpr-gate` before first ship.
- (out of scope) Migrating `flag-set-role` to the staged agent-run approval gate: tracked #9387.
- (out of scope) Per-run org creation in prod.

## Domain Assessments

**Assessed:** Marketing, Engineering, Operations, Product, Legal, Sales, Finance, Support

### Product (CPO)

**Summary:** Extend, don't add an agent. Soleur-own app is v1; "any user's app" waits for demand (3+ asks). Risks
are emails to real addresses, billing, analytics pollution, minting a real user's session. No roadmap row exists;
add one (`wg-every-feature-listed-in-a-roadmap-phase`).

### Engineering (CTO)

**Summary:** Flow-spec layer in `scripts/live-verify/`; Supabase admin API provisioning (not signup via Playwright,
not a new SECURITY DEFINER RPC); one long-lived prod org; marker teardown; keep tri-state in `postmerge`;
ADR-064 addendum + ADR for the `qa-fixtures` contract (`soleur:architecture`).

### Legal (CLO)

**Summary:** GO for Soleur's own dev/prod behind ADR-064 guardrails; GO-later for customer non-prod once a DPA
exists; NO-GO for customer prod without opt-in, real/third-party emails, Stripe live mode, automated OAuth/CAPTCHA,
service-role teardown. New principal class needs register line + exclusion duty first.

## Capability Gaps

- Flow-spec runner, Concierge-fetch flow, flag-segment-aware provisioning: evidence `run.ts:1102-1533` (single
  hardcoded flow), `seed-live-verify-user.sh:238-459` (no org/segment code), `flag-set-role/SKILL.md:50,75-102`
  (agent writes removed).
- Stale `postmerge` gate wording vs `web-platform-release.yml` (blocking since 2026-06-18).
- Hard-coded Soleur assumptions in `qa`/`test-browser`/`run.ts` (`apps/web-platform`, port 3000, `api.soleur.ai`,
  `@soleur.ai`): blocks reuse for other apps; addressed by the contract, not v1 code.
