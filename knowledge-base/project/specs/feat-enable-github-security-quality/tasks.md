---
title: "Enable GitHub Security and Quality"
status: pending
date: 2026-04-10
---

# Tasks: Enable GitHub Security and Quality

## Phase 1: Enable Secret Scanning

- [ ] 1.1 Enable secret scanning via repository settings API
  - Enable `secret_scanning`, `secret_scanning_push_protection`, `secret_scanning_non_provider_patterns`, `secret_scanning_validity_checks`
- [ ] 1.2 Verify secret scanning status via API
  - Confirm all four secret scanning features show `enabled`
- [ ] 1.3 Triage any pre-existing secret scanning alerts
  - List alerts with `gh api --paginate` + `jq -s 'add // []'` (pagination safety)
  - Check validity status: active secrets must be revoked immediately
  - Dismiss false positives and revoked secrets with appropriate reason

## Phase 2: Enable CodeQL Code Scanning

- [ ] 2.1 Enable CodeQL default setup via code scanning API
  - Configure with `extended` query suite for `actions`, `javascript-typescript`, `python` with `remote_and_local` threat model
- [ ] 2.2 Wait for initial CodeQL analysis to complete
  - Poll `code-scanning/default-setup` until state is `configured` and `updated_at` is populated
- [ ] 2.3 Verify code scanning is active
  - Confirm code scanning alerts endpoint returns 200 (not 404)
- [ ] 2.4 Triage any initial code scanning alerts
  - Review alerts, dismiss false positives, file issues for real findings

## Phase 3: Verification

- [ ] 3.1 Verify all features via API
  - Run all verification commands from the plan's test scenarios
- [ ] 3.2 Verify GitHub Security tab shows all features active
  - Use Playwright to navigate to the Security tab and capture screenshot
- [ ] 3.3 Create PR with plan artifacts
  - Commit plan and tasks files
