---
name: feat-tr9-phase-2-inngest-migration
title: "TR9 Phase 2 — Migrate All Remaining GHA Scheduled Workflows to Inngest"
lane: cross-domain
brand_survival_threshold: single-user incident
status: brainstorm-complete
issue: "#3948"
pr: "#4483"
date: 2026-05-26
---

# TR9 Phase 2 — Migrate All Remaining GHA Scheduled Workflows to Inngest

## Problem Statement

27 GHA `scheduled-*.yml` files remain on `main` after TR9 Phase 1 migrated 14 agent-loop crons to Inngest. Dual-substrate scheduling creates operational overhead (which cron is where?), inconsistent observability (Inngest gets Sentry correlation + Better Stack automatically; GHA relies on per-workflow wiring), metered GHA runner costs vs fixed-cost Hetzner, and 5-20 minute GHA cron jitter vs deterministic Inngest fire times.

## Goals

- G1: Zero GHA `scheduled-*.yml` files requiring cron-based scheduling (2 documented exceptions remain for execution-only).
- G2: All scheduling consolidated on Inngest (self-hosted Hetzner).
- G3: Each migrated function has a Sentry cron monitor.
- G4: No dual-fire window for any workflow during migration.
- G5: `cron-no-byok-lease-sweep.test.ts` passes with the expanded function set.
- G6: Dual concurrency pools prevent Monday 09:00 queue pile-up.

## Non-Goals

- NG1: Migrating `scheduled-terraform-drift` to Inngest (stays on GHA for credential isolation — K20).
- NG2: Migrating `scheduled-followthrough-sweeper` to Inngest (stays on GHA for secret isolation — K21).
- NG3: Building the `/soleur:migrate-cron-to-inngest` skill (#3990) before Phase 2 completes (K26).
- NG4: Adding email notification (RESEND) to Inngest crons (K24).
- NG5: Installing Terraform binary on the Hetzner Docker image.

## Functional Requirements

- FR1: Wave 0 — DELETE `scheduled-dogfood-3155.yml` and `scheduled-gdpr-gate-preflight-eval-50d.yml`. CONVERT `scheduled-f2-defer-gate-review.yml` and `scheduled-recheck-4217-calibration.yml` to Inngest event-triggered oneshots.
- FR2: Wave 1 — Migrate 5 claude-code-spawn workflows (campaign-calendar, content-generator, growth-audit, growth-execution, seo-aeo-audit) using PR-7 archetype. Heavy concurrency pool.
- FR3: Wave 2 — Convert `scheduled-ship-merge.yml` to event-triggered Inngest function.
- FR4: Wave 3 — Port 15 shell-only workflows to pure-TS Inngest functions using PR-6 archetype (Octokit + node:fs). Light concurrency pool.
- FR5: Each migration deletes the GHA YAML in the same commit the Inngest function lands (I13).
- FR6: Each migration adds a `sentry_cron_monitor` resource to `cron-monitors.tf` and updates the `-target=` list in `apply-sentry-infra.yml`.
- FR7: `/soleur:gdpr-gate` invoked at plan time for `scheduled-realtime-probe` and `scheduled-dev-migration-drift` (CLO bucket-ii).
- FR8: `scheduled-weekly-analytics` and its 3 cascade targets migrate as a batch with cascade converted to `inngest.send()` events.

## Technical Requirements

- TR1: ADR-033 amendment: split `cron-platform` into `cron-platform-heavy` (limit:1) and `cron-platform-light` (limit:3).
- TR2: #4472 substrate extraction (`_cron-claude-eval-substrate.ts`) must merge before Wave 1 begins.
- TR3: All Group C ports use Octokit — `gh` CLI is NOT in the production Dockerfile.
- TR4: New secrets (social API tokens, Plausible, CF, LinkedIn org, GH App driftguard) provisioned in Doppler `prd` before each dependent function migrates.
- TR5: Per-workflow PR discipline (K8). Each migration is one PR.
- TR6: `actor: "platform"` event-payload tag on every new function (I6).
- TR7: `cron-no-byok-lease-sweep.test.ts` glob automatically covers new `cron-*.ts` and `oneshot-*.ts` files.
- TR8: gray-matter date fields wrapped with `coerceFrontmatterDate()` in any handler parsing frontmatter.
- TR9: Backtick escaping in YAML prompt extraction uses `\`` not `\\\``.

## Success Criteria

- SC1: Zero GHA `scheduled-*.yml` files with active `schedule:` triggers (terraform-drift and followthrough-sweeper have `schedule:` but are documented exceptions).
- SC2: `ls .github/workflows/scheduled-*.yml | wc -l` returns exactly 2 (the exceptions).
- SC3: All Inngest cron monitors show successful heartbeats in Sentry.
- SC4: Monday 09:00 UTC peak: no function waits >30 minutes in the concurrency queue.
- SC5: `cron-no-byok-lease-sweep.test.ts` passes.
- SC6: No `||true`-wrapped silencers in any new handler.

## Wave Sequencing

```
Prerequisites: #4472 (substrate extraction) + ADR-033 amendment
          │
          ▼
  Wave 0: Quick wins (2 DELETEs + 2 oneshot conversions) ─── can start now
          │
          ▼
  Wave 1: Claude-code-spawn (5 functions) ─── needs #4472
          │
          ▼
  Wave 2: Event-triggered (1 function)
          │
          ▼
  Wave 3: Pure-TS ports (15 functions, ordered by fire frequency)
          │
          ▼
  Cleanup: Promote #3948 milestone, update roadmap, close deferred issues
```

## Estimated Effort

| Wave | Items | Pattern | Estimate |
|------|-------|---------|----------|
| Prerequisites | ADR amendment + #4472 | Architecture + refactor | 1-2 days |
| Wave 0 | 4 | DELETE + oneshot conversion | 0.5 day |
| Wave 1 | 5 | Claude-eval spawn (mechanical) | 3-4 days |
| Wave 2 | 1 | Event-triggered conversion | 0.5 day |
| Wave 3 | 15 | Pure-TS Octokit ports | 5-7 days |
| **Total** | **25** | | **10-14 days** |
