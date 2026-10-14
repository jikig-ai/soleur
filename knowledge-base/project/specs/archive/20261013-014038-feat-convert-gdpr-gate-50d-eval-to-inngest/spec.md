---
title: "Convert gdpr-gate 50-day eval to Inngest one-shot"
date: 2026-05-25
status: draft
lane: cross-domain
brand_survival_threshold: single-user incident
parent_issue: 3948
tracking_issue: 3948
brainstorm: knowledge-base/project/brainstorms/2026-05-25-convert-gdpr-gate-50d-eval-to-inngest-brainstorm.md
tags: [tr9, inngest, gdpr-gate, one-shot, compliance]
---

# Spec: Convert gdpr-gate 50-day eval to Inngest one-shot

## Problem Statement

The last TR9 umbrella child (#3948) is a GHA cron workflow that fires once on 2026-06-29 09:00 UTC to evaluate whether gdpr-gate should be wired as preflight Check 10. The current workflow uses a heavily-engineered self-neutralization mechanism (D3 date guard, D4 self-cleanup, D5 comment-immutability pin) that is brittle, GHA-dependent, and inconsistent with the Inngest substrate all other TR9 children now use. Convert it to an Inngest event-triggered one-shot function with equivalent defense-in-depth.

## Goals

1. Delete `.github/workflows/scheduled-gdpr-gate-preflight-eval-50d.yml` and replace with an Inngest function triggered by `inngest.send({ ts: <future-epoch> })`.
2. Preserve D3 (date guard) and D5 (comment-immutability pin) defenses at handler-time; add D5 at send-time per CLO.
3. Pure-TS Octokit handler (no claude-code spawn) mirroring PR #4412 `cron-strategy-review.ts`.
4. One-shot arming script with `cron_run_ledger` UNIQUE-constraint idempotency.
5. Two Sentry monitors: arming verification + handler scheduled check-in.

## Non-Goals

- Productize the one-shot pattern as `/soleur:schedule --once --inngest` (N=1; defer).
- Agent-loop handler shape (task is 4 deterministic steps).
- Boot-time re-arming (self-rearm failure mode).
- Cloudflare Worker or any new infra substrate.

## Functional Requirements

- **FR1:** Inngest function `oneshot-gdpr-gate-50d-eval` registered on `{ event: "oneshot/gdpr-gate-50d-eval.fire" }` only (no cron trigger).
- **FR2:** Handler asserts D3 date guard (`today === "2026-06-29"`); aborts with Sentry error heartbeat if false.
- **FR3:** Handler asserts D5 comment-immutability pin (re-fetch comment #4415647777; assert author=`deruelle`, `created_at === updated_at === "2026-05-10T15:27:18Z"`); aborts on mismatch.
- **FR4:** Handler executes 4-step eval: (a) grep `incidents.log` for `cq-gdpr-gate-critical-finding` count, (b) `gh pr list --state merged --search "merged:2026-05-10..2026-06-29"` with compliance label filter, (c) apply truncated outcome matrix (0 / 1–2 / ≥3 escapes), (d) post structured comment on #3516.
- **FR5:** If 0–2 escapes, handler re-arms 90-day checkpoint for 2026-08-10 via same `inngest.send({ ts })` primitive (recursive arming with new event id).
- **FR6:** Arming script `scripts/arm-gdpr-gate-50d-eval.ts` inserts `cron_run_ledger` row, validates D5 at send-time, dispatches event with `ts: 1751187600000` and `id: "gdpr-gate-50d-eval-2026-06-29-v1"`.
- **FR7:** GHA workflow file deleted in same commit per TR9 I-13 hygiene.

## Technical Requirements

- **TR1:** Concurrency: `{ scope: "fn", limit: 1 }` + `{ scope: "account", key: '"cron-platform"', limit: 1 }` (PR-1..PR-10 precedent).
- **TR2:** `retries: 1` (same as sibling cron functions).
- **TR3:** Sentry monitor `oneshot-gdpr-gate-50d-eval` added to `apply-sentry-infra.yml` `-target=` allowlist.
- **TR4:** Sentry monitor `gdpr-gate-eval-50d-armed` for arming verification.
- **TR5:** Installation token via `generateInstallationToken` (per `hr-github-app-auth-not-pat`).
- **TR6:** Ephemeral workspace via `git clone --depth=1` for `incidents.log` grep (same pattern as `cron-strategy-review.ts`).
- **TR7:** `reportSilentFallback` on all error paths (per `cq-silent-fallback-must-mirror-to-sentry`).
- **TR8:** [CONDITIONAL] If Inngest tier does NOT support 50-day `ts` delays: keep minimal GHA workflow with cron `0 9 22 6 *` (T-7d) that calls `inngest.send({ ts: 2026-06-29T09:00Z })` with 7-day delay. Handler shape unchanged.

## Acceptance Criteria

- [ ] GHA workflow `.github/workflows/scheduled-gdpr-gate-preflight-eval-50d.yml` deleted
- [ ] `apps/web-platform/server/inngest/functions/oneshot-gdpr-gate-50d-eval.ts` registered and type-checks
- [ ] Function registered in `apps/web-platform/server/inngest/functions/` index (if one exists)
- [ ] `scripts/arm-gdpr-gate-50d-eval.ts` runs successfully against dev Inngest
- [ ] `cron_run_ledger` row inserted with UNIQUE constraint (re-run exits 1)
- [ ] D3 date guard tested (mock today ≠ 2026-06-29 → abort)
- [ ] D5 comment-immutability pin tested (mock edited comment → abort)
- [ ] Sentry monitors added to `apply-sentry-infra.yml` allowlist
- [ ] `cron-no-byok-lease-sweep.test.ts` glob picks up new file (I2 auto-assertion)
- [ ] Inngest tier TTL verified OR TR8 hybrid fallback shipped
- [ ] PR body documents event_id audit trail from arming script
