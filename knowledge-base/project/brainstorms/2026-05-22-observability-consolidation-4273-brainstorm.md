---
title: Observability provider consolidation — Sentry, Better Stack, Datadog
date: 2026-05-22
issue: 4273
pr: 4293
branch: feat-observability-consolidation-4273
lane: cross-domain
brand_survival_threshold: single-user incident
status: decision-captured
---

# Observability provider consolidation #4273

## What We're Building

A staged execution of the observability strategy question opened by TR9 PR-5 (#4250):

1. **Phase 1 (this PR / immediate) — P0 compliance gap closure.** Add a PII-redacting VRL transform to `apps/web-platform/infra/vector.toml` before any further Better Stack ingest. Register Better Stack as a sub-processor in the Article 30 register, Vendor DPA table, Privacy Policy §5.10, Data Protection Disclosure §2.3(m), and GDPR Policy. Pin Better Stack ingestion endpoint to the EU region (currently unverified). Verify the OAuth canary heartbeat path end-to-end (verified live during brainstorm — TR9 PR-3 / #4211 routes via Inngest `cron-oauth-probe.ts`).
2. **Phase 2 (within ~1 week) — Path D-native.** Bump Vector ≥0.44.0 (or whichever release first carries the native `better_stack_logs` sink) and rewrite `vector.toml` to use the native sink. Pre-flight via `vector validate` in CI before the binary flip on prd. Tag as `vinngest-v1.2.0`.
3. **Phase 3 (60 days, ~2026-07-21) — Re-decide.** Pull (a) Sentry log-ingestion bill at observed volume, (b) Better Stack Logs paid-tier monthly cost at observed volume, (c) Sentry envelope silent-ingestion incident count, (d) operator-SSH-RCA incident count, (e) progress on #3814 / #3815 / #3865 / #3866. Decide whether to stay multi-provider or consolidate to Sentry (Path A).

Path B (Datadog) is **dead** — unanimous rejection across CFO ($150-200/mo + $3-4.5k upfront), CTO (throws away 135 SDK call sites + 10 cron monitors), CLO (Datadog APM ingests request bodies by default), CPO (migration window IS the user-impact window), COO (only path with contracted SLA but cost-floor disqualifies at alpha scale).

Path C (defer Layer 3+4) is **dead** — violates `hr-no-ssh-fallback-in-runbooks` (kernel oops / inngest panics require SSH).

## Why This Approach

The original framing presented A vs B vs C vs D as a one-shot strategic choice with limited cost evidence. Five domain leaders and two research agents converged on three findings that re-shape the decision:

1. **Path D-fallback is the de-facto state right now.** Post-#4277/#4278/#4279 (all merged 2026-05-21), Vector 0.43.1 ships journald + host_metrics to Better Stack Logs via the generic `http` sink. The "tonight's interim fix" the issue body anticipated already shipped, in a fallback shape (generic HTTP instead of native sink), because Vector 0.43.1 lacks the native sink. So **the choice is not "do D or not"; it's "stay where we are vs commit forward (D-native) vs commit back (A) vs leap (B)"**.
2. **The Article 30 / PII redaction gap is independent of path choice.** Better Stack receives unredacted journald (workspace IDs, OAuth callback URLs, error stack frames with email substrings) without sub-processor disclosure. This is a present-tense compliance gap that must remediate regardless. Closing it dissolves much of CLO's preference for Path A.
3. **60-day evidence dominates speculation.** The CFO ledger lookup showed observability spend today is $29/mo (Sentry Team, net $0 after pending credit). Datadog projections of $150-200/mo at 6-operator scale collapse Path B on cost-asymmetry. Sentry log-ingestion cost AT VOLUME is the only unknown that could re-open Path A consolidation. Collecting that evidence is cheaper than guessing.

D-native is the cheapest reversible path that preserves OAuth canary fidelity, narrows EU residency surface, exits the Vector↔Sentry envelope coupling that burned 6 PRs (#4271-#4279), and keeps optionality for issue #25 (observability-alerts-spawning-AI-agents).

## Key Decisions

| # | Decision | Rationale |
|---|----------|-----------|
| 1 | **Path D-native + 60-day evidence window.** | Convergence of CTO + CPO + COO + CFO. Reversible. Preserves L1+2+5 Sentry investment. |
| 2 | **P0 compliance gap closes in Phase 1, independent of long-term path.** | CLO load-bearing finding: Better Stack is currently un-disclosed in Article 30. Journald PII flows un-redacted. Must remediate regardless. |
| 3 | **Path B (Datadog) rejected unconditionally at alpha-internal scale.** | CFO: +$140-155/mo recurring + $3-4.5k migration. CTO: 135 SDK call sites + 10 TF cron monitors to rewrite. CLO: Datadog APM ingests OAuth tokens by default. Re-open only if a paying customer ever requires APM/distributed tracing AND the cost floor is amortized. |
| 4 | **Path C rejected** — violates `hr-no-ssh-fallback-in-runbooks` for kernel/inngest-panic class. |
| 5 | **PII redaction VRL transform must ship BEFORE any further Better Stack ingest tuning.** | CTO: "gdpr gate should have caught this on #4277." `tag_journald` forwards raw `message`/`host` with zero redaction. Pause-or-fix question for the operator (see Open Questions). |
| 6 | **Vector substrate bump (0.43.1 → ≥0.44.0) gated on `vector validate` in CI.** | CTO: Vector has historically broken VRL syntax on minor bumps. No staging VM exists (capability gap). Pre-flight validation is the cheap mitigation. |
| 7 | **Sentry-envelope contract test deferred to a follow-up issue, not in this scope.** | If we ever revisit Path A as the 60-day decision, that contract test is the prerequisite that makes A safe. File now to capture intent; do not build in this PR. |
| 8 | **`/soleur:gdpr-gate` fires at plan Phase 2.7 of the implementing plan.** | CLO: PA8 §(d) sub-processor list change + Art. 13(1)(e) Privacy Policy disclosure + Art. 30(1)(d) register entry are mandatory. |

## User-Brand Impact

**Brand-survival threshold:** `single-user incident`.

**Artifacts at risk:**
- **OAuth canary** (`cron-oauth-probe.ts` → Sentry monitor slug `scheduled-oauth-probe`) — load-bearing detection mechanism for "a user's OAuth token broke and they don't know." Verified live during brainstorm. Multi-provider isolation (Sentry handles the canary monitor; Better Stack handles journald) reduces single-vendor outage blast radius vs Path A.
- **Journald PII surface** — `inngest-server` stderr at WARN+ may carry workspace IDs, OAuth callback URLs, email substrings in stack frames. Currently shipped un-redacted to Better Stack (un-disclosed sub-processor). Single-user log-egress / region leak is live today. **Phase 1 of this brainstorm IS the remediation.**
- **Datadog APM was the worst PII pipeline** of any path considered — would ingest auth-callback request bodies by default. Rejected to protect single-user OAuth-token exposure.

**Vector → User-impact mapping:**
- Silent failure → OAuth canary regression visible via Sentry cron monitor alert AND Better Stack heartbeat. Two independent paths today; Path A would have collapsed to one.
- Log egress → Better Stack endpoint EU pinning is the load-bearing control (Phase 1).
- Billing surprise → CFO projections (D-native ~$39-45/mo at 3 operators) sit well inside burn-rate tolerance; trigger re-evaluation only if Better Stack Logs exceeds $15/mo.

## Open Questions

1. **Pause-or-fix.** Should we pause `vector.service` until PII redaction VRL ships, or accept the open window and bundle redaction with the Phase 1 PR? Recommend bundle — operator-incident class (kernel oops without redaction) is bounded; full pause loses Layer 3+4 observability for the duration.
2. **Better Stack EU endpoint verification.** `https://in.logs.betterstack.com/` resolves to which region? Single-line pin in `vector.toml` once verified. If EU ingestion is not available on current tier, that materially changes the residency story.
3. **Article 33 anchor-of-record.** CLO recommends documenting which provider is the canonical breach-detection time anchor when capture is split. Sentry holds it today (PA8 §(b)(ii)). D-native preserves; Path A simplifies; needs explicit ADR if multi-provider beyond 60 days.
4. **Sentry Team-tier log volume ceiling.** Path A 60-day re-decision needs Sentry's per-GB Logs pricing at expected volume (~150-400 MB/mo per CFO estimate). Where do we read that — Sentry billing dashboard or API?
5. **Vector staging VM gap.** No `soleur-inngest-dev` exists. Should we provision it before Phase 2 (D-native) or rely on `vector validate` in CI? Capability gap, low priority unless Phase 2 stumbles.

## Domain Assessments

**Assessed:** Engineering, Product, Legal, Finance, Operations (5 of 8). Marketing, Sales, Support not relevant for internal observability substrate decision.

### Engineering (CTO)

**Summary:** Path D-native is the cheapest reversible path that preserves L1+2+5 investment and exits the Vector↔Sentry envelope coupling. Two prerequisites are non-negotiable: PII redaction VRL transform (gap on #4277), and `vector validate` CI gate for the substrate bump.

### Product (CPO)

**Summary:** Path D-native preserves OAuth canary fidelity TODAY, keeps EU-residency surface narrow, and buys evidence rather than guessing. Path A re-enters the silent-ingestion failure class (envelope coupling) that burned 6 PRs — exactly the OAuth-canary-failure-mode the brand-survival framing protects against. Defer A/B/C consolidation 60 days.

### Legal (CLO)

**Summary:** Path A is the lowest-legal-risk path in isolation (drops un-disclosed Better Stack), BUT the Article 30 / Vendor DPA gap exists TODAY independent of path choice and must remediate regardless. Once remediated, CLO's preference for A weakens substantially. Phase 1 compliance work closes the gap.

### Finance (CFO)

**Summary:** Recommend D-fallback / D-native (status quo cheapest at $39-45/mo at 3 operators). Path B (Datadog) rejected unconditionally — recurring delta +$140-155/mo + one-time $3-4.5k migration. Sentry next renewal 2026-06-17 is $0 net (credit from canceled `jikigai` org applies).

### Operations (COO)

**Summary:** Stay on D-fallback (today's state, zero new spend); decide D-native vs Path A after one Sentry billing cycle + one Better Stack volume sample (~30 days). Path B deferred indefinitely at alpha-internal scale. Note: today neither active vendor owes us anything contractually if they go dark (Sentry Team + Better Stack free tier are both best-effort SLA).

## Capability Gaps

- **PII redaction VRL transform in `vector.toml`** — required regardless of path. `tag_journald` (`apps/web-platform/infra/vector.toml:48-55`) forwards raw `message` + `host` fields with zero redaction. **Evidence:** `grep -n "redact\|scrub\|hmac\|sanitize" apps/web-platform/infra/vector.toml` returns nothing. Belongs to engineering with GDPR gate review at plan Phase 2.7.
- **Better Stack EU endpoint verification** — `https://in.logs.betterstack.com/` region unknown. **Evidence:** `vector.toml:99` hardcodes URI; no comment confirming EU residency; no Article 30 entry; no `compliance-posture.md` Vendor-DPA row for Better Stack. Belongs to operations + legal.
- **Better Stack residency-check skill (analogue of #3865 Sentry skill)** — if multi-provider beyond 60 days, we need it. Defer to follow-up. **Evidence:** `find plugins/soleur/skills -name "*better*" -o -name "*residency*"` returns only Sentry skill. Belongs to engineering.
- **Sentry-envelope contract test** — required if Path A is ever chosen at the 60-day decision. **Evidence:** no `apps/web-platform/test/sentry-envelope*.test.{ts,sh}` exists. Defer to follow-up issue.
- **Vector staging VM (`soleur-inngest-dev`)** — no second host exists for safe Vector substrate bumps. **Evidence:** `find apps/web-platform/infra -name "*.tf" -exec grep -l "hcloud_server\|inngest.*dev\|inngest.*staging" {} \;` returns no dev/staging server resource (only `inngest_prd`). Mitigated for Phase 2 by `vector validate` in CI. Defer formal provisioning to follow-up.

## Session Errors

1. **Premise discrepancy in issue body.** Issue #4273's "Operational state right now" claimed Layer 3+4 was failing with HTTP 400 to Sentry and the interim fix was switching to `better_stack_logs` native sink. Reality after #4277/#4278/#4279 (all merged 2026-05-21): Vector ships to Better Stack Logs via **generic HTTP sink** (Vector 0.43.1 lacks the native sink). The issue body was stale by ~12 hours. Caught at brainstorm Phase 1.0.5 via PR-state probe. **Rule:** when issue body cites named architectural mechanism, grep `main` for the implementing artifact before accepting framing.
2. **Issue body undercounted Sentry cron monitors.** Body said 4; TF declares 10 (`apps/web-platform/infra/sentry/cron-monitors.tf`). Caught by repo-research-analyst. **Rule:** numerical claims in issue bodies need verification against current TF source before sizing migration cost.
3. **Repo-research-analyst false-alarmed on OAuth canary.** Reported `scheduled-oauth-probe.yml` missing from `.github/workflows/` and inferred the canary "may be silently un-pinged." Resolution: TR9 PR-3 / #4211 migrated the workflow to Inngest function `cron-oauth-probe.ts` which still POSTs to the Sentry cron monitor at the same slug. The GHA workflow file was deleted in the same commit. **Rule:** when a workflow-file is "missing," check whether it migrated to another substrate before concluding the heartbeat is broken.

## Productize Candidate

None for this brainstorm. The remediation work is single-shot Vector config + Article 30 entries. The 60-day re-decision is a calendar follow-up tracked via a scheduled GitHub issue (see Deferred Items).

## Deferred Items

- **Sentry-envelope contract test in CI** (capability gap; prerequisite if Path A re-opened at 60-day decision). New issue.
- **Vector staging VM `soleur-inngest-dev`** (capability gap). New issue.
- **Better Stack residency-check skill** (analogue of #3865). New issue.
- **60-day re-evaluation of consolidation** (scheduled for ~2026-07-21). New issue with calendar trigger.
- **#3814 Sentry Monitors/Alerts Terraform split** — existing open issue, not deferred-from-this; flagged as upstream constraint for the 60-day re-decision.
- **#3866 Doppler TF_VAR_sentry_region** — existing open issue, blocks the 60-day Path-A re-decision if not landed.

## References

- Verified merged on 2026-05-21: #4250 (TR9 PR-5 observability stack), #4271 (envelope debug sink), #4272 (drop framing.method), #4277 (Vector→Better Stack pivot, title misleading), #4278 (propagation fix), #4279 (generic HTTP sink due to Vector 0.43.1 limit).
- Open constraints: #3814 (Sentry Monitors/Alerts split, p1-high), #3815 (multi-tenant Sentry DPA), #3865 (Sentry residency check skill), #3866 (Doppler TF_VAR_sentry_region), #4211 (Inngest cron substrate, in-progress), #25 (north-star: observability-alerts spawning agents).
- Domain leaders (Phase 0.5): CTO, CPO, CLO, CFO, COO — all ran 2026-05-22, reports embedded under Domain Assessments above.
- Research (Phase 1.1): repo-research-analyst (135 Sentry SDK call sites; 10 TF cron monitors; 8 GH Actions Sentry heartbeats; zero Datadog footprint), learnings-researcher (14 load-bearing prior learnings; Sentry-PII shim + cron-billing quirks + no-SSH RCA rule are the binding KB constraints).
