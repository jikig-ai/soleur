---
title: Tenant-integration required-check shim
status: draft
owner: engineering
lane: cross-domain
brand_survival_threshold: single-user incident
issue: 5585
brainstorm: knowledge-base/project/brainstorms/2026-06-29-tenant-integration-required-shim-brainstorm.md
branch: feat-tenant-integration-required-shim
pr: 5688
created: 2026-06-29
---

# Spec: Tenant-integration required-check shim

## Problem Statement

`.github/workflows/tenant-integration.yml` (the dev-Supabase tenant-isolation
suite) is the only authoritative live verification that one founder's JWT cannot
read another's `users` / repo / session-sync / email-triage rows. It is
path-filtered (`on.<event>.paths`) and **not** a required check, so a red run
does not block merges — the gap that let #5582 sit red on `main`.

Flipping it to "required" as-is fails: GitHub never reports a status context for
a workflow filtered out by `on.paths`, so the check sits "Expected — Waiting"
forever and blocks every PR outside the filter. The path filter is load-bearing
— it avoids burning dev-Supabase rate budget on the ~95% of PRs that don't touch
the tested surface.

## Goals

- **G1.** Tenant-isolation suite gates merges (fail-closed) for PRs touching the
  tenant-isolation surface (tenant-isolation tests, `apps/web-platform/server/**`,
  `apps/web-platform/supabase/migrations/**`).
- **G2.** PRs outside that surface report the required check **green** without
  running the suite — zero dev-Supabase rate-budget cost.
- **G3.** The required context is registered in ruleset **"CI Required"
  (id 14145388)** so it actually blocks merges.
- **G4.** A green-on-`main` signal is preserved (push-to-`main` always runs the
  suite).

## Non-Goals

- **NG1.** No change to the tenant-isolation tests themselves or their Doppler /
  dev-Supabase wiring.
- **NG2.** No classic branch-protection introduced — rulesets remain the gate.
- **NG3.** No third-party path-filter action adopted (use the repo's idiom).
- **NG4.** No prd-write or prod-migration behavior changes.

## Functional Requirements

- **FR1.** Remove the workflow-level `on.pull_request.paths` (and `on.push.paths`)
  filter so the workflow always triggers; a status context is always produced.
- **FR2.** Add a `detect-changes` job: checkout `fetch-depth: 0` + `git diff
  --name-only origin/$BASE_REF...HEAD` + grep against the tenant-isolation path
  anchors → boolean output `tenant`. On non-PR events (push/`workflow_dispatch`)
  short-circuit to `tenant=true`. No Doppler/Supabase access. Mirrors `ci.yml`'s
  `detect-changes`.
- **FR3.** Gate the existing heavy `tenant-integration` job with
  `if: needs.detect-changes.outputs.tenant == 'true'` (and `needs: detect-changes`).
- **FR4.** Add an always-run `tenant-integration-required` job
  (`if: always()`, `needs: [detect-changes, tenant-integration]`) that asserts
  **inside a `run:` step** (never the job `if:`): pass iff
  `needs.tenant-integration.result` is `success` OR `skipped`; fail on `failure`,
  `cancelled`, or empty. This job is the required context.
- **FR5.** Register `tenant-integration-required` in ruleset 14145388 via an
  **idempotent** `gh api` call (read `required_status_checks`, append only if
  absent), executed **post-merge** in the ship/postmerge step — never as a manual
  operator UI action.

## Technical Requirements

- **TR1.** Result-inspection logic reads `needs.*.result` via `env:` + quoted
  `"$VAR"` per the workflow-injection guidance already followed in `ci.yml`/the
  current `tenant-integration.yml`.
- **TR2.** Per-event diff-base guard: `$BASE_REF` is empty on push/dispatch —
  short-circuit before referencing it (see `ci.yml` `detect-changes`).
- **TR3.** `tenant-integration-required` must NOT use a job-level `if:` skip
  (an `if:`-skipped job reports no context → reopens the path-filter gap).
- **TR4.** `detect-changes` path anchors stay byte-identical to the workflow's
  former `on.paths` list; document the lock-step requirement.
- **TR5.** Registration confirms GitHub stores the required context as the
  job-level check name (`tenant-integration-required`), not the workflow `name:`.
- **TR6.** Decide `concurrency.cancel-in-progress` (currently `false`) at
  implementation: if flipped to `true`, ensure a cancelled superseded run fails
  the gate (red on stale commit) and the latest run re-greens it.

## Acceptance Criteria

- **AC1.** On a PR that does NOT touch tenant-isolation paths: `detect-changes`
  emits `tenant=false`, the heavy job is `skipped`, `tenant-integration-required`
  reports **success**, no Doppler/Supabase call is made.
- **AC2.** On a PR that DOES touch tenant-isolation paths and the suite passes:
  `tenant-integration-required` reports **success**.
- **AC3.** On a PR that touches the paths and the suite **fails**:
  `tenant-integration-required` reports **failure** and (post-registration) blocks
  merge.
- **AC4.** After post-merge registration, ruleset 14145388's
  `required_status_checks` contains `tenant-integration-required`; re-running the
  registration is a no-op.
- **AC5.** push-to-`main` runs the full suite (green-on-main signal preserved).
