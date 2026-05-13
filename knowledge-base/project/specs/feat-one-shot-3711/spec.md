---
name: feat-one-shot-3711
issue: 3711
related: [3698, 3701, 3710]
lane: cross-domain
brand_survival_threshold: aggregate pattern
date: 2026-05-13
status: ready-for-plan
plan: knowledge-base/project/plans/2026-05-13-feat-ops-hash-user-id-cli-pa8-retention-pin-plan.md
---

# Feature: operator hash-user-id CLI + PA8 §(f) retention pin + compliance-posture refresh (#3711)

## Problem Statement

Three loose ends from the #3698 follow-up bundle (PR-A landed as #3701, PR-B in #3710):

1. **Operator hash-user-id CLI.** Operators handling support tickets currently use an ad-hoc `node -e` incantation to compute `hashUserId(<uuid>)` and grep pino stdout. Fragile, error-prone, drift-prone vs. the contract-pinned primitive at `apps/web-platform/server/observability.ts:36`.
2. **PA8 §(f) RoPA placeholder.** `knowledge-base/legal/article-30-register.md` PA8 §(f) carries the literal string `"short rolling window (re-confirm with infra runbook)"` — a CLO-flagged placeholder blocking the next audit cycle.
3. **Compliance-posture implicit-scope hygiene.** Once §(f) is concrete, drop pino retention from the implicit RoPA counsel-review scope at `knowledge-base/legal/compliance-posture.md` (the Article 30 Register row's outstanding-items tail-text).

## Goals

- Ship a Bun-shebanged TypeScript operator CLI that reuses `hashUserId` from `observability.ts` (no parallel hash implementation).
- Concretise PA8 §(f) with a structural cap (30 MB rolling per container, sourced from `cloud-init.yml:303-310`) + a `__TBD_OBSERVED_VOLUME__` sentinel that the post-merge operator step fills with measured daily volume.
- Append a one-sentence concretisation note to compliance-posture's RoPA row.
- Add an operator runbook that documents both the canonical CLI invocation and the post-merge measurement procedure.

## Non-Goals

- Sentry-side coverage (deferred to PR-B #3710).
- Helper-migration call sites (deferred to PR-B).
- Continuous (cron-scheduled) retention measurement — re-verification governed by event triggers, not cadence.
- Running the CLI inside the prod container — operator-local invocation only.

## Plan

See `knowledge-base/project/plans/2026-05-13-feat-ops-hash-user-id-cli-pa8-retention-pin-plan.md`.

## Tasks

See `tasks.md` in this directory.
