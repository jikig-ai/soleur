---
feature: auth-wal-reduction
issue: 5739
branch: feat-5739-auth-wal-reduction
pr: 5762
lane: cross-domain
brand_survival_threshold: single-user incident
status: blocked-on-measurement
date: 2026-06-30
---

# Spec: Reduce Supabase Auth (GoTrue) WAL — #5739

## Problem Statement

#5739 tracks the "~18% Auth/GoTrue WAL" residual from the 2026-06-30 Disk-IO-budget
investigation on prod `soleur-web-platform` (Micro). Live investigation showed the framing
rests on an **unmeasured premise**: the 63%-of-WAL primary fix (#5736) merged but
`pg_stat_statements` had not been reset, so the true post-fix auth share is unknown. The
counts the issue flagged as a possible loop are normal ~30–60/day rates over a 55-day window.

## Goals

- G1: Establish a clean post-#5736 measurement window (DONE — pgss reset 2026-06-30 12:40 UTC).
- G2: After ~7-day soak, re-measure Disk-IO budget + auth WAL share to decide if any auth
  WAL work is warranted at all.
- G3: If warranted, ship the security-neutral `auth.flow_state` expired-row prune (mirror
  the #5738 cron.job_run_details retention pattern).

## Non-Goals

- NG1: Lengthening the JWT/access-token TTL. Deferred — widens the token-revocation window
  (sign-out / ban / `user-set-role` demotion don't take effect until expiry) for ~zero
  user-facing ROI at p3. Revisit only on measured need with recorded CLO sign-off.
- NG2: Pruning active/in-flight `flow_state` rows (breaks live magic-link/OAuth/MFA logins).
- NG3: Checkpoint tuning (max_wal_size/checkpoint_timeout) unless confirmed tunable on Micro.

## Functional Requirements

- FR1: Re-measure WAL distribution and Disk-IO budget after the soak window (turnkey query
  posted to #5739).
- FR2 (conditional on FR1 showing residual pressure): pg_cron job deleting **expired**
  `auth.flow_state` rows only, with an explicit expired-row predicate verified against the
  GoTrue schema (auth_code_issued_at / expiry semantics).

## Technical Requirements

- TR1: All prod reads/writes scoped to project `ifsccnjhymdmidffkzhl`; reads-only until
  the measurement decision; any DELETE is expired-row-predicated and idempotent.
- TR2: If FR2 ships, follow the #5738 retention-pattern (pg_cron DELETE on a low-frequency
  schedule), and re-measure WAL contribution after deploy per the issue's acceptance criteria.
- TR3: Any future JWT-TTL change (out of scope here) requires recorded baseline + chosen TTL
  + revocation-window acceptance + rollback trigger + CLO attestation.

## Acceptance Criteria (from #5739)

- Dominant Auth-WAL driver identified with post-soak evidence (loop vs legitimate volume vs
  short JWT TTL). Investigation to date: **legitimate volume + unpruned flow_state**, no loop.
- Any JWT/session-lifetime change carries explicit security rationale + CLO sign-off (N/A
  under current decision — lever deferred).
- Auth-schema WAL share re-measured after any change.

## Measurement Log

### 2026-07-01 — mid-soak snapshot (day 1 of 7, NOT the decision measurement)

pgss window age **0.98 days** (reset 2026-06-30 12:40:27 UTC). Recorded to track the
trajectory only — the soak completes ~2026-07-07; this reading over-weights transient
activity vs the issue's 55-day/18% baseline and must not be used to decide FR2.

WAL by role (prod `ifsccnjhymdmidffkzhl`):

| Role | WAL | % |
|---|---|---|
| `supabase_auth_admin` (GoTrue) | 21 MB | 47.9% |
| postgres | 10 MB | 23.7% |
| service_role | 7.5 MB | 16.9% |
| authenticated | 3.8 MB | 8.6% |

Auth WAL composition (~214 login flows in 23.5 h ≈ 9/hr): `refresh_tokens` INSERT 6.9 MB ·
`sessions` INSERT 5.3 MB · `mfa_amr_claims` INSERT 2.9 MB · `one_time_tokens` 1.6 MB ·
`flow_state` INSERT 1.1 MB.

Findings (already directionally answering the acceptance question):
- **No loop.** ~1 refresh token per session; ~214 flows/day = legitimate volume, as predicted.
- **flow_state bloat confirmed but is NOT the WAL driver.** `auth.flow_state` = 3,865 rows,
  3,793 older than 1 day, oldest 2026-03-17 (GoTrue never prunes it). But flow_state INSERTs
  are only ~1.1 MB of ~21 MB auth WAL — the FR2 prune is a **table-hygiene** win, not a WAL
  lever. Bulk auth WAL (refresh_tokens/sessions/mfa) is irreducible without breaking sessions.
- No short-JWT-TTL refresh churn observed → confirms NG1 (TTL lever stays deferred).

Provisional post-soak conclusion (to confirm ~2026-07-07): auth WAL is legitimate volume;
no high-ROI WAL reduction exists; ship flow_state prune as bloat cleanup **or** close #5739
as no-actionable-WAL-work.
