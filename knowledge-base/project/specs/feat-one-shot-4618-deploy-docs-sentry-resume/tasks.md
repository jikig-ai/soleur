---
title: "Tasks — fix deploy-docs.yml Sentry detector resume/pause PUT payload"
issue: 4618
lane: single-domain
plan: knowledge-base/project/plans/2026-05-29-fix-deploy-docs-sentry-detector-resume-payload-plan.md
---

# Tasks — fix deploy-docs.yml Sentry detector resume/pause payload (#4618)

Single file: `.github/workflows/deploy-docs.yml`. No RED test (workflow `run:` bash is not unit-testable in the repo
runner); the "failing test" is the live-reproduced 400. Verification = actionlint + bash -n on extracted snippets +
post-merge live probe.

## Phase 1 — Resume step (lines ~282-302)

- [ ] 1.1 Remove the pre-PUT `full=$(curl ... /detectors/${MONITOR_ID}/)` GET and the `body=$(jq '.enabled = true' ...)`
      round-trip.
- [ ] 1.2 Change the resume PUT to send literal `-d '{"enabled": true}'` (verb stays `PUT`).
- [ ] 1.3 Keep: `MONITOR_ID` empty-guard, www→apex 301 probe loop, `if: always()`, fail-loud `if [[ "$http" != "200" ]]
      → ::error:: + exit 1`. Drop the now-false "enabled:null null-handling unverified" tail from the error message.

## Phase 2 — Pause step (lines ~207-222)

- [ ] 2.1 Remove the single-detector `full=$(curl ... /detectors/${id}/)` GET and `body=$(jq '.enabled = false' ...)`
      round-trip. KEEP the list GET + jq select-by-name-AND-uptime-type id resolution.
- [ ] 2.2 Change the pause PUT to send literal `-d '{"enabled": false}'` (verb stays `PUT`).
- [ ] 2.3 Keep best-effort semantics: record `monitor_id` regardless of PUT outcome; warn + `exit 0` on non-200.

## Phase 3 — Correct stale comment (lines ~205-206)

- [ ] 3.1 Replace the "Full-body GET-then-PUT: updateProjectMonitor requires the full ProjectMonitorRequest..." comment
      with the corrected note (minimal `{enabled}` PUT → 200; round-trip caused the 400 via `dataSources` shape
      mismatch; PUT not PATCH). Cite #4618.

## Phase 4 — Verify (Pre-merge ACs)

- [ ] 4.1 `actionlint .github/workflows/deploy-docs.yml` → exit 0 (AC8).
- [ ] 4.2 `bash -n` each extracted edited `run:` snippet (NOT the whole .yml).
- [ ] 4.3 AC1: minimal `{"enabled": true}` body present; `grep -c "jq .* .enabled = true"` → 0.
- [ ] 4.4 AC2: `grep -c "jq '.enabled = false'"` → 0.
- [ ] 4.5 AC3: `grep -c '\-X PUT'` → 2; `grep -c '\-X PATCH'` → 0.
- [ ] 4.6 AC5/AC6: resume fail-loud (`::error::` + exit 1) and pause best-effort (`::warning::` + exit 0) retained.
- [ ] 4.7 AC7: stale comment replaced.

## Phase 5 — Ship + post-merge verify (operator/automated)

- [ ] 5.1 Open PR with `Closes #4618` in body (pre-merge code fix, not ops-remediation).
- [ ] 5.2 AC9 (automated in /soleur:ship post-merge): next docs push → `deploy-docs.yml` green; resume step prints
      `resume PUT status: 200`. Verify via `gh run list --workflow deploy-docs.yml --limit 1 --json conclusion`.
- [ ] 5.3 AC10 (automated, read-only): after deploy, `curl .../detectors/1221117/ | jq '.enabled'` → `true` using
      `SENTRY_IAC_AUTH_TOKEN` from Doppler `prd`.
