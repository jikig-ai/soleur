# Learning: Verify what's actually on the deploy critical path before acting on a CD-velocity premise

## Problem

Operator asked whether re-running CI post-merge was useful and whether *removing* it
would improve "post-merge CD velocity / time to production." The framing assumed
post-merge CI sits on the path to prod and slows it down.

## Solution / What we found

The premise was **inverted**. In this repo (verified 2026-06-08):

- `ci.yml` (post-merge CI, `push:[main]`) is **not** on the web-platform deploy critical
  path. `web-platform-release.yml` triggers on the **same** `push:[main]` event and runs
  **in parallel** with CI.
- Deploy chain: `release(version+docker build+push) → migrate → verify-migrations →
  verify-doppler-secrets → deploy(webhook → status poll → /health version poll, ≤900s)`.
  There is **no `needs: CI`, no `workflow_run` on CI, no status-check wait** anywhere in it.
- Therefore removing post-merge CI saves **zero** time-to-prod, *and* it is the only
  per-push main-health signal plus the `workflow_run` trigger for `post-merge-monitor.yml`'s
  `[bot-fix]` auto-revert. Removal is strictly worse.
- The real latent risk surfaced by the investigation: **prod deploys are not gated on tests
  at all.** A PR green in isolation but broken by a semantic conflict on `main` (builds,
  boots, health 200s) ships to prod. The health poll catches *hard* failures (won't boot /
  wrong version / wrong SHA) but not *semantic* ones.

Decision: gate the **`deploy` job** (not the build) on CI → `max(build, CI)` not `sum`; and
add Docker layer caching (the build has none) as the actual velocity lever. (→ issue #5052,
PR #5051.)

## Key Insight

When someone proposes removing/changing a CI/CD stage to "go faster," **trace what is
literally on the critical path before acting.** A stage that *feels* sequential (CI →
deploy) is often parallel and gating nothing. Two cheap probes settle it:

1. **Grep the deploy workflow for `needs:`, `workflow_run`, and any wait-for-check step.**
   Absence = the stage is parallel and removing it changes no wall-clock.
2. **Pull real run durations** instead of assuming:
   `gh run list --workflow <wf> --branch main --limit 8 --json createdAt,updatedAt`
   then diff the timestamps. Here: CI ~5m median vs. release chain ~13m median (2–3×),
   which proved a CI gate on `deploy` is effectively free wall-clock.

The most valuable output of "should we remove X for speed?" is often discovering X wasn't
the bottleneck — and that the *absence* of a gate (deploys not waiting on tests) is the real
risk hiding behind the velocity question.

## Secondary finding

`apps/web-platform/Dockerfile` (built via `reusable-release.yml`) has **no layer cache** —
no `setup-buildx`, no `cache-from`/`cache-to` on `docker/build-push-action`. Every release
re-runs all pinned heavy runner-stage installs (`@anthropic-ai/claude-code`, `likec4`,
apt `git/bubblewrap/socat/qpdf/jq`, `gh`, `playwright+chromium ~1–2m`) + two `npm ci`.
`type=gha` layer caching is the dominant CD-speed lever and is independent of the gate.

## Session Errors

None detected. Clean session.

## Tags
category: workflow-patterns
module: ci-cd
related: [5052, 5051]
