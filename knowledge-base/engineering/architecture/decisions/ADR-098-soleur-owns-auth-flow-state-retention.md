# ADR-098: Soleur owns `auth.flow_state` retention via a daily pg_cron DELETE run as `postgres`

- **Status:** Accepted
- **Date:** 2026-07-07
- **Issue:** [#5739](https://github.com/jikig-ai/soleur/issues/5739)
- **Migration:** `apps/web-platform/supabase/migrations/124_prune_auth_flow_state.sql`
- **Precedent (mechanism):** [ADR-030](./ADR-030-inngest-as-durable-trigger-layer.md) (Inngest is the durable trigger layer for *application* scheduled work; a DB-internal retention sweep with no app context is pg_cron's job); retention siblings `103_github_events_retention_7day.sql`, `115_prune_cron_job_run_details.sql`, `094`, `076`, `038` (all pg_cron, all `public.*`).

## Context

The 2026-06-30 Supabase Disk-IO-budget investigation flagged Supabase Auth (GoTrue)
as ~18% of prod WAL (#5739). Post-soak live measurement (2026-07-07, prod
`ifsccnjhymdmidffkzhl`) found the bulk of that WAL is **legitimate, irreducible login
volume** (`refresh_tokens`/`sessions`/`mfa` INSERTs — no loop, no short-JWT-TTL churn),
so no WAL lever ships (JWT-TTL deferred, plan NG1). What the investigation *did* surface
is a distinct problem: `auth.flow_state` grows **unbounded** — GoTrue never prunes it.
Live: 4,303 rows, 3,796 older than 7 days, oldest ~3.7 months, **99.6% abandoned** flows
(`auth_code_issued_at IS NULL`). Abandoned rows retain `provider_access_token` /
`provider_refresh_token`, so months-stale third-party OAuth credentials sit in the DB —
a security / GDPR data-minimization concern on top of bloat.

The pg_cron retention *mechanism* is well-established (5 sibling crons). The **novel
axis** here is the target schema: this is the **first** in-repo cron to own retention on
a **GoTrue-managed `auth` schema** table — every prior retention cron targets `public.*`.
That makes it a cross-boundary decision (Soleur taking over the lifecycle of a
vendor-component-owned table) and precedent-setting for the next auth-schema prune, which
is why it warrants an ADR rather than a silent pattern application.

## Decision

Soleur owns `auth.flow_state` retention via a **daily pg_cron DELETE** (`0 4 * * *`,
predicate `created_at < now() - interval '7 days'`) run as **`postgres`** — which holds
an explicit `DELETE` grant on `auth.flow_state` **and** `rolbypassrls` (both live-verified
2026-07-07), exactly like all 14 existing retention crons. **No SECURITY DEFINER function
is introduced.** A one-time in-transaction backlog purge (same predicate) ships in the
migration so relief lands at deploy.

**7-day window + floor-invariant.** The window matches siblings 103/115. The unexchangeable
floor is ~10 min (PKCE `FlowStateExpiryDuration` 5 min; live `mailer_otp_exp` 600 s at
`configure-auth.sh:52`), so a >7-day-old row is unexchangeable by construction (~1000×
margin) and a pruned row can never break an in-flight login. **Invariant: the window MUST
exceed the highest configured OTP/link expiry** — re-derive if `mailer_otp_exp` is ever
raised toward days; never lower below 1 day. Predicate uses `created_at` because
`auth.flow_state` has no `expires_at` column (GoTrue computes expiry lazily; its `IsExpired()`
reads `created_at`).

## Alternatives Considered

- **(A) SECURITY DEFINER function owned by `supabase_auth_admin`.** Rejected — `postgres`
  already has explicit `DELETE` + `rolbypassrls`, so a DEFINER wrapper adds a larger
  standing attack surface for zero benefit. The DEFINER fallback is reserved for the day
  grants tighten.
- **(B) Lengthen JWT/access-token TTL to cut refresh churn (the issue's literal ask).**
  Deferred (plan NG1) — widens the token-revocation window for ~zero p3 ROI, and the
  measurement shows no short-TTL churn to fix. Revisit only on measured need with recorded
  CLO sign-off.
- **(C) Do nothing / close as no-actionable-WAL-work.** Rejected — under-delivers: the
  flow_state bloat + 3.7-month stale-OAuth-token retention is genuinely actionable and
  security-relevant.

## Consequences

- **Fails OPEN, accepted in writing at p3.** A future Supabase/GoTrue platform upgrade
  could reset the `postgres` DELETE grant. On revocation the cron simply errors (visible in
  `cron.job_run_details`) with **no data risk**, but it fails *open* — it stops pruning and
  stale `provider_*` tokens silently re-accumulate; it does not fail closed. The standing
  signal is **row-count creep** on the discoverability query (`cron.job_run_details`
  self-deletes after 7 days). Accepted for a p3 hygiene cron rather than wiring a dedicated
  Sentry/Better Stack alert. A row-count tripwire (mirroring migration 095's
  `processed_github_events` monitor) is the follow-up if the security weight grows.
- **Scope boundary.** This touches `flow_state` (PKCE/OAuth/magic-link/SSO web flows) only.
  MFA/AAL2 challenges live in `auth.mfa_challenges` — untouched.
- **Precedent for the next auth-schema prune.** Future retention on a GoTrue/platform-owned
  table should follow this shape (run as `postgres` on an explicit grant, re-verify the grant
  read-only at plan time, no DEFINER) unless the grant has since tightened.
- **No C4 impact** — `auth.flow_state` is an internal table of the already-modeled
  `supabase` database (`model.c4:156`); `postgres → auth.flow_state` DELETE is intra-database,
  below C4 element granularity.
