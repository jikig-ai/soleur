---
name: anthropic-preflight credit-balance soft-skip (+ #3604 loop validation)
issues: [3604, 3605]
parent_pr: 3559
branch: feat-preflight-credit-balance-3605
draft_pr: 3606
brainstorm: knowledge-base/project/brainstorms/2026-05-11-preflight-credit-balance-bundle-brainstorm.md
status: ready
---

# Spec: anthropic-preflight credit-balance soft-skip

## Problem Statement

`.github/actions/anthropic-preflight/action.yml` soft-skips two operational-
failure classes (HTTP 400 spend-cap, HTTP 5xx/000 transient) but hard-fails on
HTTP 400 "credit balance is too low" — operationally identical to the
spend-cap class (API unreachable for billing reasons). Today this hard-fail
turns every Anthropic-using workflow red and fires `email-on-failure`. Repro:
manual dispatch of `scheduled-compound-promote.yml` against `b80ce90` on
2026-05-11 — run `25681412895` exit 1 on the preflight step.

Adjacent: #3604 tracks first weekly compound-promote cron tick validation,
previously blocked on credit balance; now unblocked by 2026-05-11 top-up.

## Goals

- **G1** Soft-skip on HTTP 400 with body containing `credit balance is too low`,
  same as the existing spend-cap branch.
- **G2** Validate the compound-promote end-to-end loop on real data via
  `workflow_dispatch` and close #3604 on green run.

## Non-Goals

- **NG1** No Sentry mirror retrofit on existing soft-skip branches (spend-cap,
  5xx) — `::warning::` already surfaces in workflow UI.
- **NG2** No new `SENTRY_DSN` input on the composite action.
- **NG3** No scheduled-cron trigger validation; out of scope (GitHub
  infrastructure, not our code).
- **NG4** No expansion to other HTTP 400 messages (rate-limit, model-not-found,
  invalid-request) — those are payload bugs, not upstream operational issues.

## Functional Requirements

- **FR1** When preflight receives HTTP 400 with body matching either
  `specified API usage limits` OR `credit balance is too low`, set
  `ok=false` and emit a `::warning::` indicating which billing class fired.
- **FR2** When preflight receives HTTP 400 with any other body, retain
  current hard-fail behavior (exit 1).
- **FR3** All existing branches (HTTP 200, HTTP 5xx/000) remain unchanged.

## Technical Requirements

- **TR1** Use `grep -qE "(specified API usage limits|credit balance is too low)"`
  on the response body file. Literal substrings only — no regex metachars.
- **TR2** Single-line warning text covering both billing classes. Match the
  existing comment style (cite source issue + date + literal string).
- **TR3** No new inputs, no new env vars, no change to the action's outputs
  contract. `ok` output values remain `true`|`false`; exit code on
  unexpected response remains `1`.
- **TR4** No change to `.github/workflows/*` files — all callers continue to
  treat `ok=false` as a clean skip.

## Verification

### Track A — #3604 validation

- **V-A1** Trigger `scheduled-compound-promote.yml` via
  `gh workflow run scheduled-compound-promote.yml --ref main`.
- **V-A2** Confirm preflight job is green (exit 0, `ok=true` since credits
  are topped up).
- **V-A3** Confirm one of: (a) draft PR opened with `self-healing/auto` label
  and all synthetic check-runs posted (test, dependency-review, e2e,
  skill-security-scan, cla-check), OR (b) `knowledge-base/project/promotion-log.md`
  unmodified and the no-op logged cleanly.
- **V-A4** Confirm `email-on-failure` did NOT fire.
- **V-A5** Close #3604 with run link comment.

### Track B — #3605 fix

- **V-B1** Local sanity: run a synthetic `BODY_FILE` containing each of the
  three message classes (spend-cap, credit-balance, generic 400) through the
  grep clause and verify the soft-skip vs hard-fail decision.
- **V-B2** PR review: confirm the single-line diff matches TR1; confirm the
  warning text matches TR2.
- **V-B3** Post-merge: next time credit balance triggers the message in
  production, confirm `email-on-failure` does NOT fire and `::warning::`
  surfaces in the run UI.

## Files

- `.github/actions/anthropic-preflight/action.yml` (lines 41-48 region)

## Source

- Issues: #3604, #3605
- Parent PR: #3559 (merged 2026-05-11)
- Related: #2715 (original spend-cap soft-skip)
