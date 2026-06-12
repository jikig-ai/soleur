# Learning: a GitHub App permission 403 in a cron is scoped to the shared helper, not the one cron the Sentry title names

## Problem

Production Sentry (`17933ec4…`, web-platform prod) fired
`HttpError: Resource not accessible by integration` on
`POST /api/inngest` with `fnId=soleur-runtime-cron-content-publisher`. The
error is handled (`handled=yes`, `pino-mirror`) — it does not crash the cron —
but it floods Sentry daily AND means the synthetic check-runs the `CI Required`
ruleset needs are never posted, so the bot PRs these crons open can't auto-merge
cleanly.

The Sentry event names exactly ONE cron (`cron-content-publisher`), which
undersells the blast radius.

## Root cause

`apps/web-platform/infra/github-app-manifest.json` declared `"checks": "read"`.
`POST /repos/{owner}/{repo}/check-runs` requires `checks: write`. The
installation token minted from the App therefore 403s on every check-run POST.

The POST is NOT in the cron body — it's in the shared helper
`apps/web-platform/server/inngest/functions/_cron-safe-commit.ts:683`
(`safeCommitAndPr`, gated by `config.syntheticChecks`). **Five** crons pass
`syntheticChecks` through that helper (content-publisher, compound-promote,
content-vendor-drift, rule-prune, weekly-analytics), so all five were 403-ing —
the single manifest value flip fixes all five.

## Solution

The documented **two-plane** pattern (precedent PRs #4174 / #4189, the
`issues: read→write` fix):

1. **Code plane (this PR):** flip the manifest value `read`→`write`, and add a
   value-assertion regression test next to the `issues`/`administration`
   siblings in `github-app-manifest-parity.test.ts` (the exact-key-set test only
   checks key *presence* — `checks` was already in `EXPECTED_PERMISSION_KEYS`, so
   a `write`→`read` regress would ship green without the value lock).
2. **Live-grant plane (post-merge):** App permissions + installation
   re-acceptance is a GitHub-UI-only plane — **no GitHub API / Terraform** to
   widen App permissions or accept an installation update. Per
   `hr-never-label-any-step-as-manual-without`, the authenticated-session consent
   click is Playwright-MCP-driven, not punted to the operator. Closure is
   hard-gated on the read-only `gh api … .permissions.checks == write`, never on
   Playwright's apparent success.
3. **Drift-suppress sequencing:** `MANIFEST_DRIFT_SUPPRESS_UNTIL` (strict
   ISO-8601 UTC, ≤30-day cap) suppresses the self-inflicted
   `installation_permission_drift` alert in the deploy→re-accept window. Anchor
   it to **deploy** + ~24h, NOT merge — the drift guard reads the manifest +
   suppress file from the running container filesystem, so both go live only on
   deploy. The suppress gate is GLOBAL (blinds ALL installation drift, not just
   `checks`), so delete it promptly post-re-accept; it is fail-safe (self-expiring
   → at worst an inert dead file, never permanent drift-blindness).

## Key Insight

When a handled 403 (or any auth/permission error) surfaces in a cron/job with a
specific `fnId`, **trace the failing call to its definition before scoping the
fix.** If the call lives in a shared helper, the blast radius is every caller of
that helper, not the one job the telemetry names. `git grep` the config key that
gates the call (`syntheticChecks`) to enumerate the real caller set. A
single-source fix (the manifest) then resolves the whole set — and the PR
title/scope should say "5 crons", not echo the Sentry event's single name.

Corollary: GitHub App permissions are a two-plane resource (declarative manifest
JSON vs. live installation grant). The manifest PR alone does NOT stop the error;
do not `Closes #N` — use `Ref #N` and close only after `gh api` verifies the live
grant.

## Session Errors

1. **Referenced `Ref #5227` in the commit message before the tracking issue
   existed** (guessed the next issue number). `gh issue create` actually returned
   `#5229`, requiring a `git commit --amend`. **Recovery:** amended before push
   (wrong number never reached the remote). **Prevention:** create the tracking
   issue FIRST, then write the commit referencing the returned number — or use a
   `Ref #<TBD>` placeholder and amend once the number is known. Mirrors the
   ID-reconciliation discipline in
   `2026-05-22-parallel-gh-issue-create-scrambles-id-mapping-and-review-agent-producer-consumer-symmetry.md`.

## Tags
category: bug-fixes
module: github-app / inngest-crons
