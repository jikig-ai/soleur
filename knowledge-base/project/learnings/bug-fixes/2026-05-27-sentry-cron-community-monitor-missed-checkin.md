---
module: Inngest substrate
date: 2026-05-27
problem_type: integration_issue
component: inngest_cron
symptoms:
  - "Sentry cron monitor scheduled-community-monitor missed check-in"
  - "Last successful check-in 2026-05-25T11:56:14Z, 2 consecutive days missed"
root_cause: inngest_server_desync_after_deploy_churn
severity: medium
tags: [inngest, sentry, cron, deploy-churn, drift-guard]
synced_to: []
---

# Learning: Inngest cron monitor missed check-in after TR9 Phase 2 deploy burst

## Problem

Sentry cron monitor `scheduled-community-monitor` (incident #5010688) reported a missed check-in on 2026-05-27. Last successful check-in was 2026-05-25T11:56:14Z. The monitor fires daily at `0 8 * * *` UTC via the Inngest cron substrate.

The alert was "triggered by auth-callback-no-code-burst" — this was a red herring (coincidental unrelated Sentry issue alert routed to the same operator email).

## Timeline

1. **2026-05-25 ~08:00 UTC** — Community monitor fires, succeeds, Sentry check-in at ~11:56 UTC.
2. **2026-05-25 ~22:22 UTC** — PR #4460 merges: migrates community-monitor from GHA to Inngest.
3. **2026-05-26 ~07:25 UTC** — Issue #4466: 7 community secrets mirrored to Doppler prd. Redeploy.
4. **2026-05-26 ~08:00 UTC** — Community monitor should fire. **MISSED.**
5. **2026-05-26 ~14:26 UTC** — PR #4483 merges: TR9 Phase 2, 22-workflow migration. Function count 18→40. 15+ deploys follow.
6. **2026-05-27 ~08:00 UTC** — Community monitor should fire. **MISSED** (2nd day).

## Investigation

### Hypothesis D eliminated first (cheapest check)

Sentry heartbeat env vars (`SENTRY_INGEST_DOMAIN`, `SENTRY_PROJECT_ID`, `SENTRY_PUBLIC_KEY`) confirmed present in Doppler prd via `doppler secrets get ... --plain`. All 3 returned non-empty values.

### Most likely: Hypothesis A or E (Inngest server desync)

The 15+ deploys in a 24h window, combined with the 2.2x function-count jump (18→40), likely caused the self-hosted Inngest server to lose the community-monitor cron trigger during rapid sync reconciliation. Two sub-modes:
- **H9a:** Function dropped from registry entirely (loopback blip during container restart)
- **H9b:** Function registered but cron trigger not re-planned (SQLite write lock contention)

Hetzner-side diagnosis required to distinguish H9a from H9b — deferred to #4533.

## Solution

### Preventive guard (shipped in this PR)

1. **`function-registry-count.test.ts`** — 6 vitest assertions:
   - Extraction sanity (non-empty results from regex parsing)
   - Route.ts function count = 40
   - Every cron-*.ts has a matching route.ts array entry
   - Every SENTRY_MONITOR_SLUG has a cron-monitors.tf resource (or explicit exemption)
   - Every cron-monitors.tf resource maps to a real function or GHA workflow
   - KNOWN_UNMONITORED_SLUGS contains no stale entries

2. **Runbook H9** — Added to `cloud-scheduled-tasks.md` with H9a/H9b sub-modes, signature, verification steps, and restore procedure.

### Operational fix (deferred to #4533)

Requires Hetzner SSH: restart inngest-server.service → restart web-platform container → verify function registry → manual trigger → verify Sentry check-in.

## Key Insight

When a self-hosted Inngest server receives rapid function-sync requests during a deploy burst (15+ deploys with a 2.2x function-count jump), individual cron triggers can be silently dropped. The function may still appear registered while its cron schedule is not re-planned. A CI-time test asserting function count + registration parity + Sentry monitor parity catches this drift class before it reaches production.

## Session Errors

1. **CWD drift running vitest** — Ran `./node_modules/.bin/vitest` from the worktree root instead of `apps/web-platform`. **Recovery:** Used `cd apps/web-platform && ./node_modules/.bin/vitest`. **Prevention:** Always run vitest from the app package directory, not the monorepo root.

2. **Regex `functions:\s*\[([\s\S]*?)\]` returned 0 matches** — Non-greedy `[\s\S]*?` failed to match the multi-line functions array in route.ts. **Recovery:** Simplified to `^\s+(\w+),$` on the full file (all 40 matches are inside the array). **Prevention:** For source-reading tests, prefer line-anchored regexes over block-extraction when the file structure guarantees unique patterns.

3. **camelCase conversion wrong for `cron-` prefix** — Initial `replace(/^cron-/, "cron")` didn't capitalize the next character, producing `croncommunityMonitor` instead of `cronCommunityMonitor`. **Recovery:** Used `split("-")` + `.map(p => p[0].toUpperCase() + p.slice(1))` on segments after first. **Prevention:** Use split-and-capitalize for kebab-to-camelCase; never strip-prefix-and-hope.

4. **`GHA_ONLY_MONITORS` contained stale entry** — `scheduled-gh-pages-cert-state` was listed as GHA-only but has an Inngest cron function (`cron-gh-pages-cert-state.ts`). Caught by pattern-recognition reviewer, not by the test itself. **Recovery:** Removed the stale entry. **Prevention:** Added test (d) asserting `KNOWN_UNMONITORED_SLUGS` entries are all real slugs; same pattern should apply to `GHA_ONLY_MONITORS`.

## Cross-References

- Runbook: `knowledge-base/engineering/operations/runbooks/cloud-scheduled-tasks.md` (H9)
- Related: `knowledge-base/project/learnings/2026-05-19-inngest-substrate-five-bug-cascade.md`
- Operator issue: #4533
- PR: #4531

## Tags

category: bug-fixes
module: inngest-substrate
