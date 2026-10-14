---
title: "Enable GitHub Security and Quality"
status: complete
date: 2026-04-10
---

# Tasks: Enable GitHub Security and Quality

## Phase 1: Enable Secret Scanning

- [x] 1.1 Enable secret scanning via repository settings API
  - Enabled `secret_scanning` and `secret_scanning_push_protection`
  - `secret_scanning_non_provider_patterns` and `secret_scanning_validity_checks` blocked: requires `admin:org` scope to attach org code security config
- [x] 1.2 Verify secret scanning status via API
  - secret_scanning: enabled, push_protection: enabled
- [x] 1.3 Triage any pre-existing secret scanning alerts
  - 1 alert found: Anthropic API Key (2026-02-10 incident). Dismissed as "revoked"

## Phase 2: Enable CodeQL Code Scanning

- [x] 2.1 Enable CodeQL default setup via code scanning API
  - Configured with `extended` query suite, `remote_and_local` threat model, languages: actions, javascript-typescript, python
- [x] 2.2 Wait for initial CodeQL analysis to complete
  - state: configured, updated_at: 2026-04-10T15:47:37Z
- [x] 2.3 Verify code scanning is active
  - Code scanning alerts endpoint returns 200 with 84 alerts
- [x] 2.4 Triage any initial code scanning alerts
  - 84 alerts (63 error, 21 warning) across 11 rules. Tracking issue #1894 created

## Phase 2b: Threat Model Tuning

- [x] 2b.1 Switch CodeQL threat model from `remote_and_local` to `remote`
  - [Updated 2026-04-16] Threat model switched to `remote` only (see #2418).
    100 false positives from `local` taint sources (env vars, file paths) were
    dismissed in PR #2416. Switching to `remote` prevents recurrence on future PRs.

## Phase 3: Verification

- [x] 3.1 Verify all features via API
  - All API verification commands pass
- [ ] 3.2 Verify GitHub Security tab shows all features active
  - Skipped: Playwright browser not logged in to GitHub (OAuth consent required)
- [x] 3.3 Create PR with plan artifacts
  - Committed plan, tasks, and session-state files
