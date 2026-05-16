---
date: 2026-05-16
category: process
module: brainstorm, repo-research, credential-rotation
tags:
  - repo-research
  - credential-rotation
  - secret-stores
  - atomic-swap
  - blast-radius
  - scheduled-workflows
  - brainstorm
  - sentry
related_issues:
  - "#3861"
  - "#3904"
related_learnings:
  - 2026-05-15-token-namespace-divergence-across-secret-stores
  - 2026-03-25-doppler-secret-audit-before-creation
  - 2026-05-16-brainstorm-premise-cascade-and-playwright-handoff-discipline
---

# Learning: Repo-research for "rotate everywhere" features must inventory scheduled CI workflows, not just runtime config

When a brainstorm proposes a "rotate the credential everywhere" feature (DSN swap, API-key rotation, vendor migration), the operator's feature description typically lists 3-5 runtime config surfaces (Doppler/Vault, GH secrets, Vercel/Netlify envs, .env.template, docker-compose). Repo-research must reflexively grep `.github/workflows/scheduled-*.yml` (or equivalent cron-runner directory) because scheduled CI workflows commonly hold a SEPARATE credential triple (an ingest-only key, a probe-only token, or a checkin-only API key) that runtime config does NOT reference. Missing these in the atomic-swap scope produces the exact partial-rotation failure mode the swap was designed to prevent — credentials get half-rotated, scheduled beacons keep firing to the old destination, and the audit gate (which checks runtime DSN only) reports green.

## Problem

Sentry residency A2 Branch C brainstorm received a feature description listing C2's atomic-swap scope as 4 surfaces: Doppler `prd` (3 DSN vars), GH secrets (4 token-related), Vercel envs, .env.template / docker-compose / CI workflow. Repo-research-analyst spawned in parallel uncovered 4 ADDITIONAL surfaces the description missed:

1. **Cron-checkin secrets triple** (`SENTRY_INGEST_DOMAIN` + `SENTRY_PROJECT_ID` + `SENTRY_PUBLIC_KEY`) consumed by **11 scheduled GH workflows** (`scheduled-terraform-drift.yml`, `scheduled-github-app-drift-guard.yml`, `scheduled-daily-triage.yml`, `scheduled-community-monitor.yml`, `scheduled-oauth-probe.yml`, `scheduled-realtime-probe.yml`, `scheduled-content-vendor-drift.yml`, `scheduled-skill-freshness.yml`, `scheduled-followthrough-sweeper.yml`, etc.). Each posts cron beacons to Sentry; if not rotated, beacons keep firing to the phantom org.

2. **`SENTRY_URL` / `SENTRY_API_HOST` env** for `sentry-cli` in `reusable-release.yml` + `Dockerfile` build-args. Currently absent; defaults to US edge. Will silently target the wrong region on the new DE org if not explicitly set to `https://eu.sentry.io/`.

3. **CSP `report-uri` swap** requires Cloudflare edge cache purge after Doppler/Vercel propagation. Otherwise browsers POST CSP violations to the dead phantom DSN for the TTL window.

4. **Source-map artifacts on the phantom org** are orphaned debug evidence for any pre-swap prod error. Not a swap target per se, but a PIR-disclosure surface that must be documented as a known forensic gap.

The feature description's 4-surface inventory was ~50% of true blast radius. Without the parallel repo-research, the resulting plan would have shipped a "complete" atomic swap that left 11 scheduled workflows beaconing to the phantom org — exactly the failure mode Branch C is meant to fix, just for a different secret.

## Solution

**Default repo-research checklist for any "rotate credential X everywhere" brainstorm:**

1. **Runtime config files** (already obvious): `.env*`, `docker-compose*`, framework-specific config (`next.config.ts`, `astro.config.mjs`, etc.).
2. **Secret-store consumers** (already obvious): grep call sites of `process.env.X_*` / equivalent in the languages used.
3. **Build-time / Dockerfile** (semi-obvious): `Dockerfile` `ARG`/`ENV` directives, build scripts.
4. **Per-deploy CI workflows** (semi-obvious): `.github/workflows/{deploy,release}*.yml`.
5. **Scheduled CI workflows** (REFLEXIVE — this learning): `.github/workflows/scheduled-*.yml`, `.github/workflows/cron-*.yml`, or equivalent cron-runner directory in other CI systems (GitLab `.gitlab-ci.yml` schedules, CircleCI `triggers`, BuildKite `schedules.yml`). These commonly hold credential triples distinct from runtime.
6. **One-off/operator scripts** (often missed): `scripts/`, `bin/`, `tasks/` directories. Look for shell scripts that source `.env` or invoke vendor CLIs with hardcoded env.
7. **Documentation/examples** (often missed): `README.md`, `docs/`, `examples/`. These may carry stale credentials that mislead future operators.
8. **Vendor-specific implicit defaults** (the catch in this case): vendor CLIs and SDKs may default to a specific region/endpoint. Grep for the SDK's env-var-naming conventions even if not currently set — they MAY need to be explicitly set during the rotation to override defaults.

**Repo-research prompt template (add this paragraph to any rotate-everywhere brainstorm):**

> "Inventory every surface that consumes credential `X`. For each surface, output file path + line + which env var. Distinguish: (a) runtime SDK init, (b) build-time injection, (c) per-deploy CI, (d) scheduled CI (grep `.github/workflows/scheduled-*.yml` and equivalent), (e) operator scripts, (f) documentation/examples. Also report any vendor-specific implicit default that must be explicitly overridden during rotation (e.g., `SENTRY_URL` defaults to US edge if not set)."

## Key Insight

**Atomic-swap blast radius is reliably underestimated by 2x when the inventory source is the feature description alone.** Operators write feature descriptions from the runtime-rotation mental model; the scheduled-CI consumer set is invisible from that vantage. Repo-research-analyst-as-parallel-spawn is the cheapest correction: 60-180s for a complete inventory while domain leaders are still assessing.

**Scheduled CI workflows are the most common hidden surface in credential rotations.** They hold credentials that are: (a) write-only (beacons, telemetry, status reports), (b) often distinct-namespace from runtime credentials (a Sentry "cron checkin" triple vs the runtime DSN), (c) rarely surfaced in deploy-time logs because cron runs happen out-of-band. The combination makes them perfect ghosts — invisible until they keep posting to the rotated-away destination for weeks.

**The "rotate everywhere" anti-pattern: enumerate-and-stop.** Any inventory that stops at the first 4-5 surfaces named in the feature description is incomplete by default. The right discipline is "inventory by source-of-truth (the codebase), not by source-of-instruction (the feature description)." Treat the feature description as a starting hypothesis to be verified against repo-research, not as a scope ceiling.

**Generalizes beyond Sentry:** any vendor with a separate "send-only" credential class (cron beacons, webhook signatures, telemetry tokens, deployment notifications, error-reporting public keys) will produce this failure mode under rotation. Examples: Datadog cron-checkin keys, Honeycomb ingest keys, Loki write-tokens, Datadog Synthetics monitoring tokens, PagerDuty integration keys, Slack webhook URLs (each surface a separate key class).

## Tags

category: process
module: brainstorm, repo-research, credential-rotation
