# Tasks — fix: Make RLS fuzz Supabase image pulls resilient to GHCR throttling

Plan: `knowledge-base/project/plans/2026-10-27-fix-rls-fuzz-ghcr-throttle-plan.md`
Issue: #10868 · Branch: `feat-one-shot-10868-rls-fuzz-ghcr-throttle`

## Phase 1 — Authenticated GHCR path

- [x] 1.1 Add a job-level `permissions:` block to `rls-fuzz` in `.github/workflows/rls-authz-fuzz.yml`: `contents: read` + `packages: read` (top-level block unchanged).
- [x] 1.2 Add `docker/login-action@c94ce9fb468520275223c153574b00df6fe4bcc9 # v3.7.0` step after `actions/checkout`: `registry: ghcr.io`, `username: ${{ github.actor }}`, `password: ${{ secrets.GITHUB_TOKEN }}`. Comment cites #10868 and the mechanism (Supabase CLI reads `~/.docker/config.json` via `GetRegistryAuth`). No `logout: false`.

## Phase 2 — Bounded signature-gated retry helper

- [x] 2.1 Create `.github/scripts/ghcr-pull-with-retry.sh` (`#!/usr/bin/env bash`, `set -uo pipefail`): argv command, ≤3 attempts, fresh per-attempt log via `tee`, rc via `${PIPESTATUS[0]}`, retry iff `rc != 0` AND `rc != 2` AND attempt's log matches `toomanyrequests` (ci). Sleeps `20 45`, overridable via `GHCR_PULL_RETRY_SLEEPS`. `::warning::` per retry naming the measured line; `::error::` + command's rc on exhaustion; non-signature/rc-2 failure exits attempt 1 unchanged. Do NOT include `Retrying after` / `failed to pull docker image` / `failed to display json stream` in the gate (decoy tokens — fire on non-throttle failures).
- [x] 2.2 Rewire the "Start local Supabase stack (loopback-bound)" step's `run:` to `bash "${GITHUB_WORKSPACE}/.github/scripts/ghcr-pull-with-retry.sh" ./scripts/supabase-local.sh start`; keep `working-directory: apps/web-platform` and step name.

## Phase 3 — Regression test (Guard 1)

- [x] 3.1 Create `.github/scripts/test/test-rls-fuzz-ghcr-resilience.sh` (bash-only, `set -uo pipefail`, `pass`/`fail`/`MIN_ASSERTIONS` shape):
  - wiring arm: `packages: read` on the job; `docker/login-action` ghcr step ordered before start; start step invokes the helper; no `logout: false`.
  - behavioral arm: PATH-stubbed fake commands — throttle-then-success retried+passed; non-signature failure exits attempt 1; rc=2 never retried; always-throttle exhausts with `::error::` + nonzero rc; decoy (`Retrying after` alone) not retried; stale-signature (throttle attempt 1, clean fail attempt 2) not retried; happy path single invocation rc 0.
- [x] 3.2 Local verification: `bash .github/scripts/test/test-rls-fuzz-ghcr-resilience.sh` prints `0 failed`; `bash .github/scripts/test/run-all.sh` passes; `bash scripts/lint-workflows.sh` green.

## Phase 4 — Validation

- [x] 4.1 Push branch; confirm the PR's own `RLS authz fuzz` run (self-triggering: the workflow file is in its `paths:` list) goes green — authenticated pulls exercised end-to-end.
- [x] 4.2 PR body carries `Closes #10868` and a `## Changelog` entry (patch).
