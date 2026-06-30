---
date: 2026-06-30
topic: auth-wal-reduction
issue: 5739
branch: feat-5739-auth-wal-reduction
pr: 5762
lane: cross-domain
brand_survival_threshold: single-user incident
status: brainstorm-complete
---

# Brainstorm: Reduce Supabase Auth (GoTrue) WAL — #5739

## What We're Building

A **measure-first** response to #5739, not a blind churn-reduction change. #5739 was filed
as the "second-largest residual WAL source (~18%, Auth/GoTrue tables)" follow-up to the
2026-06-30 Disk-IO-budget depletion investigation on prod `soleur-web-platform`
(ref `ifsccnjhymdmidffkzhl`, Micro / 1 GB RAM). Live investigation during this brainstorm
showed the issue's framing rests on an unmeasured premise, so the deliverable is:

1. **Reset `pg_stat_statements`** to start a clean post-#5736 measurement window (the gating action).
2. **Soak ~7 days**, then re-measure the Disk-IO budget and the auth WAL share.
3. **Ship only the security-neutral `flow_state` prune** (expired rows only) — bundle the
   pattern with #5738 (cron.job_run_details prune).
4. **Hold the JWT/session-TTL lever off** unless post-soak data proves WAL still exceeds target.

## Why This Approach

The user selected **measure-first + cheap prune**; the CTO/CLO/CPO triad converged on the
same posture independently. Rationale anchored in live evidence (not the issue body):

- **The "suspicious" counts are not a loop.** `pg_stat_statements` was last reset
  **2026-05-06**; measured **2026-06-30** → all call counts span a **55-day window**.
  Re-derived rates (16 users, 5 active/7d): recovery-token UPDATE ~29/day, flow_state
  ~63/day, refresh_tokens ~35/day, sessions ~30/day. ~7 refreshes/active-user/day is
  consistent with the **default ~1hr JWT TTL** under normal usage. The issue's "verify no
  recovery loop" lead resolves to **no loop**.
- **The residual auth share is unmeasured.** #5736 (the 63%-of-WAL webhook-dedup fix)
  merged at current `main` HEAD (`3ac94bd25`), but pgss has **not** been reset since, so
  cumulative stats still show `processed_github_events` at **62.9%**. The true post-#5736
  auth share cannot be known until a clean window is measured. Optimizing an unquantified
  ~18% before confirming the budget is still pressured is premature.
- **WAL is FPI-dominated.** Full-page images dominate every auth query (e.g. refresh_tokens
  ≈4.8 FPI/call). The cross-cutting lever is checkpoint distance (max_wal_size /
  checkpoint_timeout) — but that's a managed-Supabase param on Micro, likely not tunable.
- **One clear, safe win exists now:** `flow_state` is accumulating **3,793 live rows**,
  not auto-pruned (vs one_time_tokens = 5, cleaned). Structurally identical to #5738's
  `cron.job_run_details`. Pruning **expired** rows is hygiene, security-neutral, near-zero
  marginal cost when bundled with #5738.
- **The JWT lever carries real risk for ~zero p3 benefit.** Lengthening the access-token
  TTL widens the revocation window: a signed-out/banned/role-demoted user's stateless JWT
  stays accepted for the full TTL (Supabase does not recheck the sessions table per
  request; this also defers `user-set-role` demotions). Off the table unless measured need.

## Key Decisions

| # | Decision | Rationale |
|---|----------|-----------|
| 1 | Reset `pg_stat_statements` now (concluded action) | Start a clean post-#5736 window; current window is 55d contaminated with pre-fix WAL. Snapshot recorded below first. |
| 2 | Soak ~7 days, re-measure Disk-IO budget + auth share before any auth change | Confirm whether #5736 already relieved the budget; avoid optimizing a moot ~18%. |
| 3 | `flow_state` prune = expired rows only | Deleting active rows breaks in-flight magic-link/OAuth/MFA flows (CPO + CLO + CTO). |
| 4 | Bundle the prune pattern with #5738 | Shared pg_cron retention pattern; near-zero marginal cost. |
| 5 | JWT/session-TTL lengthening: **deferred**, not adopted | Security tradeoff (wider revocation window) for ~zero user-facing ROI at p3; requires CLO sign-off + recorded rationale if ever revisited. |
| 6 | #5739: **defer (keep open)**, blocked on Decision 2 measurement; do not close | #5736 likely already relieved the budget, but close only on evidence. |
| 7 | Visual design (Phase 3.55): skipped — no UI surface (pure DB infra) | Legitimate trigger boundary, not a silent skip. |

## Evidence Snapshot (recorded 2026-06-30, before pgss reset)

`pg_stat_statements` window: reset 2026-05-06 20:53 UTC → 2026-06-30 12:32 UTC (~55 days).
Users: 16 total, 5 active/7d. DB 46 MB, 100% cached, write-dominated.

Top WAL contributors (cumulative — pre-#5736-soak):

| Query | WAL | % | calls | wal_fpi |
|---|---|---|---|---|
| `processed_github_events` INSERT | 742 MB | 62.9% | 190,191 | 172,252 |
| `cron.job_run_details` INSERT (#5738) | 55 MB | 4.7% | 6,699 | 10,630 |
| `refresh_tokens` INSERT | 49 MB | 4.2% | 1,984 | 9,548 |
| `flow_state` INSERT | 45 MB | 3.8% | 3,478 | 8,022 |
| `processed_github_events` DELETE (retention) | 42 MB | 3.6% | 29 | 10,583 |
| `sessions` INSERT | 36 MB | 3.1% | 1,695 | 7,134 |
| `mfa_amr_claims` INSERT | 19 MB | 1.6% | 1,693 | 4,241 |
| `users` recovery_token UPDATE | 14 MB | 1.2% | 1,618 | 7,953 |
| `one_time_tokens` INSERT | 14 MB | 1.2% | 1,620 | 6,826 |

Live row counts: sessions 653, refresh_tokens 777, flow_state **3,793** (accumulating),
one_time_tokens 5 (cleaned).

## Open Questions

1. After the 7-day soak, does the Disk-IO budget still exceed target? (Gates all auth work.)
2. Is `auth.flow_state` safe to prune via pg_cron, or does GoTrue's own cleanup just need
   a frequency bump? Confirm the expired-row predicate (auth_code_issued_at / expiry).
3. Is `max_wal_size` / `checkpoint_timeout` tunable on the Micro plan? (Dashboard check.)

## User-Brand Impact

- **Artifact:** the Supabase Auth (GoTrue) JWT/session-lifetime configuration for prod
  `soleur-web-platform`.
- **Vector:** lengthening JWT/session TTL widens the token-revocation window — a compromised,
  signed-out, or role-demoted user's stateless access token stays valid for the full TTL.
- **Threshold:** single-user incident.

This brainstorm's chosen posture (defer the JWT lever) keeps the artifact untouched; the
only shipped change (expired-flow_state prune) does not affect the revocation window.

## Domain Assessments

**Assessed:** Marketing, Engineering, Operations, Product, Legal, Sales, Finance, Support

### Engineering (CTO)

**Summary:** Measure-first is the gating action (high confidence) — reset pgss, soak 7d,
re-check budget, which is very likely already relieved by #5736. Only the `flow_state`
prune is worth bundling opportunistically with #5738; checkpoint tuning is likely
not tunable on Micro; JWT TTL deferred. Recommend defer (keep open), no new ADR, no
capability gaps.

### Legal (CLO)

**Summary:** Keep the JWT lever off at p3 — a longer TTL means sign-out/ban/role-demotion
don't take effect until expiry (stateless JWT, no per-request sessions-table recheck);
worst-case single-user blast radius triples/quadruples. Pruning *expired* flow_state and
cron logs is security-neutral hygiene. If TTL is ever changed, record baseline + chosen
TTL + revocation-window acceptance + rollback trigger; CLO attests, operator retains veto.

### Product (CPO)

**Summary:** User-facing ROI ≈ zero at 16 users on Micro; defer until WAL approaches an
instance limit. Any flow_state prune must be expired-rows-only (deleting active rows breaks
in-flight magic-link/OAuth; pruning active sessions logs users out). Measure-first posture
has no user-facing downside.
