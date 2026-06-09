---
title: "Postmortem: user-account 'Create Project' 403 — user-installation tokens cannot POST /user/repos (mocked 201 for ~30 days)"
date: 2026-06-05
incident_pr: 3399
incident_window: "~2026-04-07 (POST /user/repos path shipped, unit-tested with a hand-mocked 201) → ~2026-05-07 (PR #3399 deployed: routed Create Project through jikig-ai/kb-template /generate)"
recovery_at: "2026-05-07T00:00:00Z"
suspected_change: "POST /user/repos for user-account repo creation was unit-tested with a hand-rolled mockFetch returning 201, but GitHub App user-installation tokens cannot POST /user/repos — production returned 403. The drift went undetected for ~30 days because the path was never exercised end-to-end against the real API."
brand_survival_threshold: single-user incident
status: closed
closed_on: 2026-05-07
closed_via: "PR #3399 (routed Create Project through jikig-ai/kb-template /generate template-seed). This PIR is authored retroactively (2026-06-05) while building the structural prevention (#3413 health probe + #3415 synthesized fixtures) — the incident was shipped-and-fixed without a post-mortem; the standing rule (every detected incident gets a PIR, even found incidentally) is satisfied here."
triggers:
  - create project 403
  - user/repos forbidden
  - github app installation token
  - mock vs real API drift
  - test fixture 201 vs prod 403
art_33_triggered: false
art_34_triggered: false
art_33_deadline: "n/a — availability/functional outage (repo-create was BLOCKED), no personal-data exposure or breach"
---

## Actor key

- `agent` — Claude Code did this autonomously.
- `agent-with-ack` — Claude Code did this after operator confirmation.
- `human` — Operator did this directly.

# Incident Overview

For roughly 30 days, a non-technical founder clicking **"Create Project"** (the user-account repo-creation path) received an opaque failure. The server attempted `POST /user/repos` with a GitHub App **user-installation** token, which GitHub forbids (403). The path had shipped green because its unit test mocked `fetch` to return `201` — a hand-imagined shape that never matched production. PR #3399 resolved it by routing Create Project through `jikig-ai/kb-template`'s `/generate` template-seed endpoint instead.

## Status

closed — fixed by PR #3399 (~2026-05-07). This PIR is retroactive.

## Symptom

"Create Project" failed with a generic error toast; the founder could not create a project at all. Server logs showed `403` from `POST /user/repos`.

## Incident Timeline

- **Start time (detected):** ~2026-05-06 (first user-reported failure, #3183/#3401 class)
- **End time (recovered):** ~2026-05-07 (PR #3399 deployed)
- **Duration (MTTR):** ~1 day from report to fix; ~30 days latent (ship → first report)

| Actor | Time (UTC) | Action |
|---|---|---|
| human | ~2026-04-07 | `POST /user/repos` path ships; unit test mocks a `201` response. |
| — | ~2026-04-07 → ~2026-05-06 | Latent: no user exercises the path end-to-end; green CI masks the 403. |
| human | ~2026-05-06 | User reports "Create Project" broken (403). |
| agent | ~2026-05-07 | PR #3399 reroutes through `kb-template` `/generate`; incident resolved. |
| agent | 2026-06-05 | This PIR authored + structural prevention shipped (#3413 probe, #3415 synthesized fixtures). |

## Participants and Systems Involved

GitHub App installation-token auth surface (`server/github-app.ts`); the Create-Project route; `jikig-ai/kb-template` (the new template seed).

## Detection (+ MTTD)

- **How detected:** external/manual — a user reported the failure. There was NO proactive monitoring of the path.
- **MTTD:** ~30 days (ship → first user report). This is the core failure: the only detection channel was a user hitting it.

## Root Cause

Two compounding causes:
1. **Wrong API for the auth context.** GitHub App user-installation tokens cannot `POST /user/repos`. The correct path for cross-account repo creation is the template `/generate` endpoint (PR #3399's fix).
2. **Test-fixture-vs-real-API drift.** The unit test mocked `POST /user/repos → 201` from imagination. A mock can assert any shape; nothing forced the fixture to match GitHub's real `403`. The green test actively masked the bug for ~30 days.

## Prevention / Follow-ups (this PR: #3413 + #3415)

- **#3413 — hourly kb-template health probe** (`cron-kb-template-health.ts`, this PR): proactively probes `GET /repos/jikig-ai/kb-template`, asserts `is_template===true && private===false`, files a P1 ops issue on drift, auto-closes on recovery. Moves detection from "a user hits it" (~30-day MTTD) to "hourly" (≤1h MTTD) for the template-drift class that would break Create Project the same way.
- **#3415 — synthesized GitHub API fixtures** (this PR): replaces hand-imagined mock bodies with fixtures synthesized to GitHub's documented response shapes, closing the mock-vs-real-API drift class for the github-app test surface.
- **Residual (already tracked):** #3414 (Playwright E2E smoke for `/api/repo/create` against a real dev GitHub installation) is the true end-to-end guard — a unit test cannot catch an auth-context-vs-API mismatch. It remains an open `deferred-scope-out` because it needs a dedicated dev GitHub App installation account.

## Lessons

- A mocked third-party API response is only as trustworthy as its fidelity to the real shape — a path never exercised end-to-end against the real API is unverified, regardless of green unit tests.
- Detection-by-user-report is a ~30-day MTTD; proactive probes on user-onboarding-critical dependencies are worth their weight.
