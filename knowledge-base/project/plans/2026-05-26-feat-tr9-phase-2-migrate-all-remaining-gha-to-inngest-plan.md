---
title: "TR9 Phase 2 — Migrate All Remaining GHA Scheduled Workflows to Inngest"
type: enhancement
classification: infrastructure
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
issue: "#3948"
pr: "#4483"
date: 2026-05-26
reviewed: 2026-05-26 (5-agent panel: DHH, Kieran, code-simplicity, architecture-strategist, spec-flow-analyzer)
---

# TR9 Phase 2 — Migrate All Remaining GHA Scheduled Workflows to Inngest

## Overview

Migrate 25 remaining GHA `scheduled-*.yml` workflows to Inngest cron/event functions on the self-hosted Hetzner substrate. Two workflows stay on GHA permanently (terraform-drift, followthrough-sweeper). Two more stay on GHA for dev/prd credential isolation (realtime-probe, dev-migration-drift). Builds on TR9 Phase 1 which successfully migrated 14 agent-loop crons over 5 weeks with zero P1 incidents.

**Scope:** 2 DELETEs + 3 oneshot/event conversions + 5 claude-code-spawn + 13 pure-TS ports = 23 Inngest migrations + 2 DELETEs. 4 workflows stay on GHA.

**Per-workflow PR discipline (K8 carry-forward):** Each migration is one PR. No bundling. K13: delete GHA YAML in same commit Inngest function lands.

**Concurrency model:** Keep the existing single `cron-platform` pool (limit: 1). Stagger Monday heavy-function schedules by ≥90 minutes so queue depth never exceeds 2. Dual pools deferred until empirical evidence of starvation. [Updated 2026-05-26 — 5-agent plan review converged: dual pools are premature optimization; schedule staggering solves the real problem (Monday collision) at zero prerequisite cost.]

## User-Brand Impact

**If this lands broken, the user experiences:** scheduled triage/audit/content-publishing silently stops — work rots for days/weeks until manual discovery. Founder-facing crons (post-PR-G) fail silently.

**If this leaks, the user's credentials are exposed via:** social API tokens (X OAuth, LinkedIn OAuth) or Terraform provider tokens exposed through Inngest event payloads, logs, or misconfigured `process.env` passthrough.

**Brand-survival threshold:** single-user incident (carry-forward from Phase 1 brainstorm; CPO re-affirmed 2026-05-26).

CPO sign-off covered by brainstorm Phase 0.5 triad assessment. `user-impact-reviewer` invoked at review time per `plugins/soleur/skills/review/SKILL.md` conditional-agent block.

## Open Code-Review Overlap

- **#4381** (ADR-034 + ADR-033 I3 amendment) — **Fold in:** the ADR-033 amendment (schedule stagger documentation + I3 timeout tuning) addresses this.
- **#4382**, **#4383**, **#3828** — **Acknowledge:** not blocking. Re-evaluate #3828 after Phase 2 (composite action consumers shrink to 4).

## Implementation

### Prerequisites

**Wait for #4472 (substrate extraction).** Extracts shared helpers into `_cron-claude-eval-substrate.ts` and `_cron-shared.ts`. Hard prerequisite for the 5 claude-spawn items. Everything else (deletes, oneshots, pure-TS ports) can proceed immediately.

**ADR-033 amendment (schedule stagger).** Document the staggering strategy in ADR-033's consequences section. Update re-evaluation criterion: "if Monday drain time exceeds 4 hours or any function waits >120 minutes, split pools." Closes #4381. This is a docs-only PR — no function file edits.

**Doppler secrets:** Provisioned per-PR, not as a batch prerequisite. When migrating a function, verify its required secrets exist in Doppler `prd` (same-name = same-value check per `2026-05-15-token-namespace-divergence-*`). GHA secrets are write-only (values unreadable via API) — operator verifies manually.

Full secret inventory for reference:

| Secret | Consumer |
|---|---|
| `PLAUSIBLE_API_KEY`, `PLAUSIBLE_SITE_ID` | weekly-analytics, plausible-goals |
| `DISCORD_BLOG_WEBHOOK_URL`, `DISCORD_WEBHOOK_URL` | content-publisher |
| `X_API_KEY`, `X_API_SECRET`, `X_ACCESS_TOKEN`, `X_ACCESS_TOKEN_SECRET` | content-publisher |
| `LINKEDIN_ACCESS_TOKEN`, `LINKEDIN_PERSON_URN`, `LINKEDIN_ORG_ID`, `LINKEDIN_ORG_ACCESS_TOKEN` | content-publisher, linkedin-token-check |
| `BSKY_HANDLE`, `BSKY_APP_PASSWORD` | content-publisher |
| `CF_API_TOKEN` | cf-token-expiry-check |
| `GH_APP_DRIFTGUARD_APP_ID`, `GH_APP_DRIFTGUARD_PRIVATE_KEY_B64` | ruleset-bypass-audit |

Note: `RESEND_API_KEY` is NOT provisioned — K24 drops email notifications. Sentry-only observability.

### Migration Items (flat list, only dependency: #4472 blocks claude-spawn items)

**DELETEs (no Inngest function needed):**

| # | Action | Rationale |
|---|--------|-----------|
| D1 | DELETE `scheduled-dogfood-3155.yml` | One-shot fired 2026-05-05. `workflow_dispatch` only. |
| D2 | DELETE `scheduled-gdpr-gate-preflight-eval-50d.yml` | Inngest oneshot `oneshot-gdpr-gate-50d-eval.ts` already on main. Cleanup miss from PR-G #4461. |

**Oneshot/event conversions (no Sentry cron monitor — use error alerting only):**

| # | Create | Delete | Archetype | Pool |
|---|--------|--------|-----------|------|
| E1 | `oneshot-f2-defer-gate-review.ts` | `scheduled-f2-defer-gate-review.yml` | Claude-eval spawn (PR-7) | `cron-platform` |
| E2 | `oneshot-recheck-4217-calibration.ts` | `scheduled-recheck-4217-calibration.yml` | Claude-eval spawn (PR-7) | `cron-platform` |
| E3 | `event-ship-merge.ts` | `scheduled-ship-merge.yml` | Claude-eval spawn (PR-7) | `cron-platform` |

**E1 timing fallback:** If conversion doesn't land before May 29 09:00 UTC, the GHA fires and self-neutralizes. E1 then becomes a DELETE (like D2). State explicitly in the PR: "if GHA has already fired, skip conversion and delete."

**E3 trigger UX:** After migration, operator triggers via `inngest send '{"name":"ship-merge.manual-trigger","data":{}}'` or via the Inngest dashboard "Send Event" UI. Document in `knowledge-base/engineering/ops/runbooks/`.

**E1-E3: No `sentry_cron_monitor` resource.** Oneshots and event-triggered functions don't have a recurring schedule. Sentry cron monitors would permanently false-alert on missed check-ins. Use `reportSilentFallback` for error reporting only. [Review fix: Kieran P0-2, P0-3.]

**BYOK sweep:** Extend glob in `cron-no-byok-lease-sweep.test.ts` (line 38) from `{cron,oneshot}-*.ts` to `{cron,oneshot,event}-*.ts` to cover `event-ship-merge.ts`. [Review fix: Kieran P0-4.]

**Claude-code-spawn crons (5 items — blocked on #4472):**

| # | Create | Delete | Sentry slug | Cron (staggered) |
|---|--------|--------|-------------|------|
| C1 | `cron-campaign-calendar.ts` | `scheduled-campaign-calendar.yml` | `scheduled-campaign-calendar` | `0 16 * * 1` |
| C2 | `cron-content-generator.ts` | `scheduled-content-generator.yml` | `scheduled-content-generator` | `0 10 * * 2,4` |
| C3 | `cron-growth-audit.ts` | `scheduled-growth-audit.yml` | `scheduled-growth-audit` | `0 7 * * 1` (staggered from 09:00 to avoid Monday pile-up) |
| C4 | `cron-growth-execution.ts` | `scheduled-growth-execution.yml` | `scheduled-growth-execution` | `0 10 1,15 * *` |
| C5 | `cron-seo-aeo-audit.ts` | `scheduled-seo-aeo-audit.yml` | `scheduled-seo-aeo-audit` | `0 11 * * 1` (staggered from 10:00) |

**Pure-TS port crons (13 items — can proceed immediately, no #4472 dependency):**

| # | Create | Delete | Cron | Notes |
|---|--------|--------|------|-------|
| T1 | `cron-membership-health.ts` | `scheduled-membership-health.yml` | `17 * * * *` (hourly) | |
| T2 | `cron-weekly-analytics.ts` | `scheduled-weekly-analytics.yml` | `0 6 * * 1` | **Migrate AFTER C2, C4, C5** (cascade targets). Convert `gh workflow run` dispatch to `inngest.send("cron/<target>.manual-trigger")`. |
| T3 | `cron-ruleset-bypass-audit.ts` | `scheduled-ruleset-bypass-audit.yml` | `13 6 * * *` | GH App auth (driftguard) |
| T4 | `cron-gh-pages-cert-state.ts` | `scheduled-gh-pages-cert-state.yml` | `0 3 * * *` | Tighten Sentry `checkin_margin_minutes` from 240→30 |
| T5 | `cron-cloud-task-heartbeat.ts` | `scheduled-cloud-task-heartbeat.yml` | `30 9 * * *` | |
| T6 | `cron-content-publisher.ts` | `scheduled-content-publisher.yml` | `0 14 * * *` | **High complexity.** 12 social API secrets. Doppler provisioning required first. |
| T7 | `cron-content-vendor-drift.ts` | `scheduled-content-vendor-drift.yml` | `17 11 * * MON` | Uses `bot-pr-with-synthetic-checks` pattern |
| T8 | `cron-linkedin-token-check.ts` | `scheduled-linkedin-token-check.yml` | `0 11 * * 1` (staggered from 09:00) | |
| T9 | `cron-nag-4216-readiness.ts` | `scheduled-nag-4216-readiness.yml` | `0 14 * * 1` | |
| T10 | `event-cf-token-expiry-check.ts` | `scheduled-cf-token-expiry-check.yml` | manual dispatch | Named `event-` not `cron-` (no schedule). No Sentry cron monitor. |
| T11 | `cron-plausible-goals.ts` | `scheduled-plausible-goals.yml` | `0 7 1 * *` | |
| T12 | `cron-rule-prune.ts` | `scheduled-rule-prune.yml` | `0 9 1 1,4,7,10 *` | Uses `bot-pr-with-synthetic-checks` pattern |
| T13 | `cron-skill-freshness.ts` | `scheduled-skill-freshness.yml` | `0 2 1 * *` | |

**Cascade ordering constraint (T2):** `weekly-analytics` dispatches `seo-aeo-audit` (C5), `growth-execution` (C4), and `content-generator` (C2) on KPI miss. These targets must be on Inngest BEFORE T2 migrates. Otherwise, the still-live GHA dispatcher fires `gh workflow run` against deleted YAMLs during the gap window. T2 uses `inngest.send()` for the cascade — no bridge needed if targets are already migrated.

**KPI-miss notifications:** K24 drops the RESEND email path. Weekly-analytics currently emails on KPI miss (a business signal, not a technical failure — Sentry won't catch it). File a follow-up issue for KPI-miss alerting via Discord webhook or Sentry custom metric. The cascade dispatch to CMO workflows IS the automated remediation; the email was a supplementary notification.

### GHA Exceptions (4 workflows stay permanently)

| Workflow | Rationale |
|---------|-----------|
| `scheduled-terraform-drift.yml` | Credential isolation: Terraform binary + provider plugins + SSH key material require ephemeral GHA runners. Art. 32 TOM. K20. |
| `scheduled-followthrough-sweeper.yml` | Secret isolation: selective `secrets=` injection defeated by shared `process.env`. Art. 32 + Art. 25(1). K21. |
| `scheduled-realtime-probe.yml` | Dev/prd boundary: accesses dev Supabase via `DOPPLER_TOKEN_DEV_SCHEDULED`. Pure-TS function runs inline in the prd worker — no `buildSpawnEnv()` boundary to scope env. Injecting dev token into prd Doppler violates `hr-dev-prd-distinct-supabase-projects`. |
| `scheduled-dev-migration-drift.yml` | Same dev/prd boundary concern as realtime-probe. Uses `DOPPLER_TOKEN_DEV_SCHEDULED` for dev Supabase migration state comparison. |

[Updated 2026-05-26 — realtime-probe and dev-migration-drift added as GHA exceptions per spec-flow P0-4 and arch-strategist P1-3. Both access dev Supabase from the prd worker process; no subprocess env boundary exists for pure-TS functions. Scope reduced from 25→23 Inngest migrations. SC2 updated to "exactly 4".]

### Per-PR Migration Checklist

Follow the template file (`cron-roadmap-review.ts` for claude-spawn, `cron-strategy-review.ts` for pure-TS). Non-obvious steps only:

**All migrations:**
1. Add `sentry_cron_monitor` resource + `-target=` entry (skip for oneshots/event-triggered)
2. Register in `route.ts` (alphabetical)
3. `git rm` GHA YAML in same commit
4. `vitest run` passes
5. Provision Doppler secrets before merging (verify same-name = same-value)
6. If migrating a function whose Sentry monitor already exists, tighten `checkin_margin_minutes` to 30

**Claude-spawn only:**
7. Backtick escaping: `\`` not `\\\``
8. `--` end-of-options separator in `CLAUDE_CODE_FLAGS` is load-bearing
9. `buildSpawnEnv()` allowlist — only secrets the prompt needs

**Pure-TS only:**
10. `gh` → Octokit, `curl` → `fetch`, `jq` → JS
11. gray-matter dates: `coerceFrontmatterDate()`
12. If GHA uses `bot-pr-with-synthetic-checks`: port via Octokit + `spawnGitChecked` + synthetic check-runs (follow `cron-compound-promote.ts` pattern)

### Rollback

If a migration PR is reverted:
1. `git revert` restores the GHA YAML (including its `schedule:` trigger) — GHA re-enables the cron. This is correct.
2. The Sentry monitor created by Terraform persists in Sentry's state. On next `apply-sentry-infra.yml` run, Terraform will destroy it (the `-target=` entry is also reverted). The reverted GHA workflow's Sentry heartbeat code may auto-create a new monitor with default settings (depends on Sentry project config).
3. The Inngest route.ts registration is also reverted — the function stops being served.

No operator action needed beyond the revert. Sentry monitor will self-heal on next heartbeat if auto-creation is enabled; otherwise, re-apply terraform manually.

## Observability

```yaml
liveness_signal:
  what: Sentry cron monitor per scheduled function (not oneshots/event-triggered)
  cadence: matches each function's cron schedule
  alert_target: ops@jikigai.com (verify Sentry alert rules include email delivery)
  configured_in: apps/web-platform/infra/sentry/cron-monitors.tf

error_reporting:
  destination: Sentry (via reportSilentFallback) + Better Stack (via Vector shipper)
  fail_loud: postSentryHeartbeat at end-of-step.run. No || true silencers.

failure_modes:
  - mode: function fails to fire on schedule
    detection: Sentry cron monitor shows missed check-in
    alert_route: Sentry → ops email
  - mode: claude-code spawn crashes
    detection: step.run throws → Inngest retries (retries: 1) → Sentry error
    alert_route: Sentry error alert
  - mode: queue starvation (Monday pile-up)
    detection: synthetic Sentry monitor "cron-platform-monday-drain" expects heartbeat by 18:00 Monday — if queue hasn't drained, missed check-in fires
    alert_route: Sentry → ops email
  - mode: dual-fire during migration window
    detection: impossible per K13 (delete GHA YAML in same commit)
    alert_route: N/A

logs:
  where: Better Stack Logs (via Vector on Hetzner)
  retention: 30 days (Better Stack default)

discoverability_test:
  command: curl -sf https://soleur.ai/api/inngest | jq '.functions | length'
  expected_output: function count increases by 1 per migrated function (baseline 19)
```

## Acceptance Criteria

### Pre-merge (per-PR)

- AC1: New function file created in `apps/web-platform/server/inngest/functions/`
- AC2: Import + registration added to `route.ts` (alphabetical order)
- AC3: For cron functions: `sentry_cron_monitor` resource + `-target=` entry added. For oneshots/event: no Sentry cron monitor.
- AC4: GHA YAML deleted in same commit
- AC5: `vitest run` passes (includes `cron-no-byok-lease-sweep.test.ts` with extended `{cron,oneshot,event}-*.ts` glob)
- AC6: No `|| true` silencers wrapping `postSentryHeartbeat` or error-handling paths
- AC7: Doppler secrets verified before merge (same-name = same-value)

### Post-merge (program completion)

- AC8: `ls .github/workflows/scheduled-*.yml | wc -l` returns exactly 4 (terraform-drift, followthrough-sweeper, realtime-probe, dev-migration-drift)
- AC9: All new Sentry cron monitors show ≥1 successful heartbeat within their first fire window
- AC10: Monday 09:00-18:00 UTC: queue drains by 18:00 (synthetic Sentry monitor verifies)
- AC11: GHA secret audit: list remaining secrets vs remaining workflow consumers, file pruning issue for orphaned secrets

## Test Strategy

**Per-function tests:** Each function gets a co-located test in `apps/web-platform/test/server/inngest/`. Use `vitest` (not `bun test`). Test `step.run` return shape, env allowlist (claude-spawn only), and Sentry heartbeat URL construction.

**Sweep tests (auto-cover new files):**
- `cron-no-byok-lease-sweep.test.ts` — extended glob `{cron,oneshot,event}-*.ts`
- gray-matter: real `matter(...)` call per handler (not hand-mocked)
- Route.ts registration sweep: glob `{cron,oneshot,event}-*.ts` and assert each has a corresponding import in route.ts

**Integration:** First-fire verification per function via Sentry monitor.

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Monday queue starvation | Medium | High | Stagger schedules by ≥90min. Synthetic Sentry monitor at 18:00 Monday. If starvation observed, split to dual pools (30min find-and-replace). |
| Social API token rotation (LinkedIn 60-day TTL) | Medium | Medium | Pre-existing gap. File separate issue. |
| Shared process.env exposes social tokens to all functions | Low | High | Accepted residual risk. Document in ADR-033 amendment. content-publisher's 12 tokens are write-path marketing credentials (not PII), below the threshold that justifies keeping terraform-drift on GHA. |
| Cascade dead zone (weekly-analytics targets deleted before dispatcher) | High | Medium | T2 must migrate AFTER C2, C4, C5. Explicit ordering constraint. |
| gray-matter date coercion | High | Low | `coerceFrontmatterDate()` + real `matter()` vitest case. |
| Secret namespace divergence | Medium | Medium | Per-PR verification. Operator manual check (GHA secrets write-only). |

## Sharp Edges

- Binary name is `claude` not `claude-code` (ADR-033 I4).
- `--` end-of-options separator in `CLAUDE_CODE_FLAGS` is load-bearing (bug #8/8).
- `bunfig.toml` has `pathIgnorePatterns = ["**"]` — use `vitest`, not `bun test`.
- Oneshots and event-triggered functions do NOT get Sentry cron monitors (permanent false-alert).
- `event-` file prefix is new convention. Document in ADR-033 amendment alongside `cron-` and `oneshot-`.
- Weekly-analytics cascade: targets MUST be on Inngest before dispatcher migrates.
- `retries: 1` doubles worst-case queue depth on failure days. If Monday starvation observed, consider `retries: 0` for heavy functions with manual re-trigger.

## Domain Review

**Domains relevant:** Engineering, Product, Legal. Carried forward from brainstorm triad (2026-05-26).

- **CTO:** Schedule staggering over dual pools. #4472 prerequisite. 10-14 days estimate.
- **CPO:** 5-week evidence sufficient. Promote #3948 from Post-MVP. Productize skill after Phase 2.
- **CLO:** No Article 30 changes. 4 GHA exceptions preserve Art. 32 TOM posture. K16-K19 carry forward.
- **Product/UX Gate:** Tier none. No user-facing impact.
