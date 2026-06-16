# Learning: LB-rotated egress drops need grace-window IP retention, not provider CIDRs

## Problem

Six heavy Claude-eval crons (`cron-community-monitor`, `cron-content-generator`,
`cron-follow-through`, `cron-bug-fixer`, `cron-roadmap-review`,
`cron-agent-native-audit`) silently stopped completing for days — Sentry cron
monitors showed **`missed`** check-ins (not `failed`), and the live signal was
`egress-blocked: container egress denied` (654 hits, ongoing). The blocked
`DST=<ip>` set mapped via `ipinfo.io` to Cloudflare (`104.18.x`), AWS
(`198.x`/`64.239.x`), and Google-LB (`34.149.x`) — every one fronting a host
that was **already** in `cron-egress-allowlist.txt` (`hn.algolia.com`,
`discord.com`, `api.x.com`, `api.linkedin.com`, `bsky.social`, …).

This is the **non-GitHub analogue of incident 5516336** (the api.github.com
`/meta` CIDR gap, see [[2026-06-14-github-egress-cidr-must-cover-full-meta-not-just-big-blocks]]):
the ADR-052 container egress firewall default-drops anything not in the
`soleur_egress_allow` nftables set, and `cron-egress-resolve.sh` rebuilt that set
every minute from a **single-A-record snapshot** of each allowlisted hostname.
LB-fronted hosts round-robin across large IP pools, so a container connect to a
freshly-rotated IP before the next 1-min tick captured it was default-dropped.

## Solution

**Resolve-and-retain (grace-window IP retention).** The resolver now records the
last-seen epoch for every IP DNS returns for an allowlisted host, persists it in a
`StateDirectory`-backed store (`/var/lib/cron-egress-resolve/seen`), and unions
back every stored IP seen within `GRACE_WINDOW_SECS` (default 24h). The allow set
accumulates each host's full rotation pool. Eviction of past-window entries is
gated on the prune tick (`FAILED_HOSTS==0`) so the additive-only invariant
extends to the store. All other resolver invariants are preserved (atomic
add-then-prune, fail-safe-on-empty, DNS pin, self-heal).

The GitHub fix was a bounded CIDR file (`/meta` is a GitHub-owned, enumerable
range list). **That approach does NOT generalize** — the security-preserving fix
for non-GitHub LB hosts is retention of *observed DNS answers for already-trusted
hosts*, never the wholesale provider ranges.

## Key Insight

**For an LB host on a default-drop egress firewall, the single-IP resolver is the
wrong layer — but the right fix depends on who owns the pool.** If the provider
publishes a bounded, provider-owned range list (GitHub `/meta`), CIDR-cover it. If
the host sits behind a shared cloud LB (Cloudflare/AWS/Google), do NOT allowlist
the provider's ranges — that would let a compromised cron egress to any tenant on
that cloud and defeat the boundary. Instead **retain the IPs DNS actually returned
for the already-allowlisted host over a rolling window** — tight (only trusted-host
answers), rotation-proof, and bounded exposure (a rotated-away IP lingers ≤ one
window, a bounded extension of the accepted CDN shared-IP residual).

**Diagnostic corollary:** `missed`-not-`failed` cron check-ins are the
firewall-drop fingerprint (the heartbeat is the last step, gated on the egress
call succeeding). And a freshly-deployed durable run-log cannot answer historical
questions — `public.routine_runs` had 9 rows all from the deploy day, so the
**Sentry cron-monitor check-in history** (per-monitor `/checkins/`) was the only
week-spanning source. Pull it directly; do not eyeball a dashboard.

## Session Errors

- **Planning subagent Edit failed on a Unicode-character mismatch** — Recovery:
  re-read the anchor and re-applied. Prevention: re-read before editing when an
  Edit anchor spans non-ASCII (em-dashes, arrows) — already covered by
  `hr-always-read-a-file-before-editing-it`. One-off.
- **Sentry issues API `statsPeriod=7d` → HTTP 400** ("Valid choices are '', '24h',
  '14d'") — Recovery: used `14d`. Prevention: already covered by the qa skill
  sharp edge ("use `statsPeriod=24h` not `1h`; Sentry only accepts 24h/14d") and
  the incident skill's Sentry toolchain. Recurring class, already skill-enforced.
- **Sentry API host stored without scheme** (`jikigai-eu.sentry.io`) → curl
  defaulted to http and got a 301 — Recovery: prepend `https://`. Prevention:
  always `https://${SENTRY_API_HOST}` when reading the Doppler value. One-off.
- **`psql` not installed locally** — Recovery: queried prod Supabase via PostgREST
  (`$SUPABASE_URL/rest/v1/...` + service-role key, injected via `doppler run`).
  Prevention: PostgREST + service-role is the no-psql path for read-only prod
  queries. One-off (env).
- **shellcheck SC2034 (unused `OUT3`)** in a test scenario asserting on store-file
  state — Recovery: discarded to `>/dev/null`. Prevention: run shellcheck as the
  bash-only deterministic gate (already the review substitute for semgrep). One-off.

## Tags
category: bug-fixes
module: apps/web-platform/infra/cron-egress-firewall
related: [[2026-06-14-github-egress-cidr-must-cover-full-meta-not-just-big-blocks]]
