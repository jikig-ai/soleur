---
name: sentry-dsn-cluster-substring-authoritative-residency
description: Sentry DSN of shape o<orgInternalId>.ingest.<cluster>.sentry.io carries authoritative region binding in the <cluster> segment — orgs are region-bound, the substring is faster than the /organizations API probe (which 403s on sntrys_ org-auth tokens) and lower-scope
date: 2026-05-15
category: integration-issues
tags: [sentry, gdpr, residency, dsn, probe, article-30]
related_issue: "#3861"
related_pr: "#3863"
related_learnings:
  - 2026-05-04-sentry-org-token-region-probe-and-dashboards-scope-guard.md
  - 2026-05-15-sentry-iac-billing-and-quirks.md
---

# Learning: Sentry DSN cluster substring as authoritative residency signal

## Problem

When investigating a Sentry residency contradiction (#3861 — Article 30 register claimed DE, AC14 audit artifact said `API host: sentry.io`), the canonical probe pattern documented in `2026-05-04-sentry-org-token-region-probe-and-dashboards-scope-guard.md` is `GET /organizations/{org}/` + read `links.regionUrl`. That probe returned HTTP 403 on both `sentry.io` and `de.sentry.io` for the Doppler `prd` `SENTRY_AUTH_TOKEN` — the token's `sntrys_` (org-auth, releases-only scope) prefix lacks `org:read`.

Re-attempting against `/projects/`, `/projects/jikigai/soleur-web-platform/keys/`, `/customers/jikigai/`, and `/organizations/jikigai/monitors/` all returned 403. The token scope is too narrow for any read-side residency probe.

## Solution

Sentry DSNs encode the cluster in the host segment: `o<orgInternalId>.ingest.<cluster>.sentry.io`. The `<orgInternalId>` (e.g., `o4511123328466944`) is region-bound — Sentry orgs cannot span clusters; the org-internal-id is allocated on one specific cluster's database. Reading the DSN's cluster substring from Doppler `prd` `SENTRY_DSN` (or `NEXT_PUBLIC_SENTRY_DSN`, which must match in a same-cluster deployment) is:

1. **Authoritative** for runtime event-ingest residency — the DSN is what the SDK actually uses at runtime.
2. **Faster** than the API probe — single substring match, no HTTP round-trip.
3. **Lower-scope** — reading a DSN from Doppler does not require any Sentry API permission.
4. **Available** even when no Sentry token is in hand (e.g., reading the production Doppler `prd` config from a development laptop).

Substring matching ladder:

```bash
DSN=$(doppler secrets get SENTRY_DSN --plain --project soleur --config prd)
case "$DSN" in
  *ingest.de.sentry.io*)  cluster=de ;;
  *ingest.us.sentry.io*)  cluster=us ;;       # new-style tenant subdomain
  *.ingest.sentry.io*)    cluster=us ;;       # legacy US shape
  *)                       cluster=unknown ;;
esac
```

The legacy US shape lacks an explicit `us.` infix — Sentry's older DSNs used `o<id>.ingest.sentry.io`, where the bare `ingest.sentry.io` (no region prefix) means US. New-style DSNs explicitly carry `us.` or `de.`; new orgs default to the explicit form.

## Key Insight

For a residency-correctness probe, the canonical order should be:

1. **DSN cluster substring** (5 seconds, no auth, authoritative for runtime ingest)
2. `GET /organizations/{org}/` → `links.regionUrl` (only if DSN is unavailable AND a `sntryu_` user token or sufficiently-scoped org token is in hand)
3. Endpoint-shape differential (a 401 on cluster A vs 403 on cluster B is a weak signal of cluster binding)

The 2026-05-04 learning's probe pattern is correct for region-detection from a CI script with no DSN context, but for any residency *audit* (where a DSN is by definition available), the DSN substring beats it on every axis.

This is the FIRST step of the deferred `/soleur:sentry-residency-check` skill (issue #3865). The skill compares the DSN cluster substring against the Article 30 register PA8 §(e) residency claim and fails-closed on mismatch — catches the exact bug class that produced #3861.

## Session Errors

1. **First Doppler call failed silently** — `doppler secrets get SENTRY_AUTH_TOKEN --plain --config prd` from the worktree returned exit code 1 with no output because the worktree CWD has no `.doppler/config.yaml` and the global token has no project binding. **Recovery:** added `--project soleur --config prd` explicitly. **Prevention:** from a fresh worktree, always pass both `--project <name> --config <name>` to `doppler secrets get` (or pre-bind via `doppler setup --project soleur --config prd --no-interactive` once at worktree creation time).

2. **API probe 403'd on both clusters** — token scope too narrow for `/organizations/{org}/`, `/projects/`, `/customers/`. **Recovery:** pivoted to DSN cluster-substring (this learning). **Prevention:** in any future Sentry residency probe, attempt the DSN substring first; reach for the API only when the DSN isn't readable.

## Tags

category: integration-issues
module: observability
component: apps/web-platform/sentry.{client,server}.config.ts
