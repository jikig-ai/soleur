---
title: "v0.116.1 deploy timeout — buildx driver switch forced a one-time full-layer re-pull"
date: 2026-06-08
incident_pr: 5051
incident_window: "2026-06-08 20:06Z – 22:24Z (deploy job failed 20:21Z; prod flipped to v0.116.1 at 22:24Z; prod healthy on 0.116.0 throughout — no user-facing outage)"
recovery_at: "2026-06-08 22:24Z — prod on v0.116.1 (build_sha 6e7cac76), deploy exit_code=0; no user impact (v0.116.1 has zero app-code delta vs live 0.116.0)"
suspected_change: "PR #5051 WS2 — added docker/setup-buildx-action (docker-container driver) for type=gha cache"
brand_survival_threshold: single-user incident
status: resolved
triggers:
  - deploy-pipeline reliability (web-platform release)
art_33_triggered: false
art_34_triggered: false
art_33_deadline: "n/a — availability/deploy-pipeline incident, no personal-data exposure"
---

## Actor key

- `agent` — Claude Code did this autonomously (no operator ack required).
- `agent-with-ack` — Claude Code did this AFTER operator confirmed via menu option.
- `human` — Operator did this directly.

# Incident Overview

PR #5051 added a deploy-gate (`await-ci`, WS1) plus Docker `type=gha` layer caching (WS2). WS2
required `docker/setup-buildx-action`, which switches `docker/build-push-action` from the default
**`docker` driver** to the **`docker-container` driver**. That driver produces images with
different layer digests/structure than the previous releases. On the first release after the
merge (v0.116.1), the prod server's `docker pull` therefore had to **re-pull every layer** (a
multi-GB full re-pull: claude-code, likec4, playwright-chromium, apt, node). The re-pull exceeded
the `deploy` job's 900s `Verify deploy script completion` poll ceiling, so the deploy job **failed**
at 20:21Z. The server-side `ci-deploy.sh` kept pulling; each attempt was killed at the wrapper's
900s cap before the full multi-GB re-pull finished, but `docker pull` resumes from cached layers,
so repeated attempts converged. **Resolution (22:24Z):** merging the durable ceiling fix #5066
(closes #5061) fired the deploy-pipeline-fix apply, which runs `systemctl restart webhook`
(`server.tf:457`) — killing the handler and the FD-200-holding `docker pull` child, **freeing the
flock unconditionally**. The next deploy then completed on the now-fully-cached layers
(`exit_code=0`) and prod flipped to v0.116.1 (build_sha 6e7cac76). **No user impact** throughout.

## Status

resolved — prod on v0.116.1 (deploy `exit_code=0`) as of 22:24Z; healthy on 0.116.0 throughout the
window (zero app-code delta, no user-facing outage). The durable fix #5066 (#5061) raised the
deploy-completion ceiling 900s→1800s and is live on main; its v0.116.2 release is the first deploy
to exercise the raised ceiling. The autonomous lock-clear was the `webhook` restart on the DPF
apply — no SSH, no operator action.

## Symptom

`deploy` job: `##[error]ci-deploy.sh did not report completion for v0.116.1 within 900s` after 180
poll attempts. Prod `/health` stayed on the prior version (0.116.0) while the deploy ground on.

## User-Brand Impact

**None.** v0.116.1 had **zero app-code delta** vs the live 0.116.0 (which was #5042's debug-mode
release, already serving users). v0.116.1's only contents were CI workflow files (#5051 — not part
of the running app) and a `flag-set-role` *skill* change (#5057 — not app code). The web bundle in
v0.116.1 was byte-identical to 0.116.0, so prod running 0.116.0 throughout the incident was
**invisible to users**. Brand-survival threshold inherited `single-user incident` from #5051's
framing, but the realized impact was nil.

## What worked (the gate itself)

WS1's `await-ci` gate ran correctly in production on its first real exercise (AC7): it polled CI's
`test` check-run for the merge SHA, the test passed, and the gate authorized the `deploy` job.
`release` (build + cache write), `migrate`, `verify-migrations`, `verify-doppler-secrets` all
succeeded. The **only** failure was the pre-existing 900s deploy-completion ceiling being too tight
for the one-time full re-pull WS2 induced.

## Incident Timeline

- **Start (detected):** 2026-06-08 20:21Z (deploy job failed)
- **End (recovered):** 2026-06-08 22:24Z (prod flipped to v0.116.1, deploy exit_code=0)
- **Duration (MTTR):** ~2h3m to version catch-up — but **no user-facing outage at any point** (byte-identical bundle); the "recovery" is a benign version flip, not a restoration of service.

| Actor | Time (UTC) | Action |
|---|---|---|
| agent | 20:06Z | PR #5051 merged; web-platform release v0.116.1 triggered. `await-ci` gated and passed (AC7). |
| agent | ~20:09Z | Docker build (cache-cold) + push succeeded; `migrate`/verify succeeded; `deploy` cutover began. |
| agent | 20:21Z | `deploy` job failed — `ci-deploy.sh` did not report completion within 900s (full-layer re-pull still in progress). |
| agent | 20:25–20:39Z | Confirmed prod healthy on 0.116.0; deploy-status `exit_code=-1 reason=running`; re-trigger attempts returned `lock_contention` (original deploy still holding the flock past the 920s wrapper kill). |
| agent | ~20:42Z | Established **zero user impact** (v0.116.1 has no app-code delta vs live 0.116.0). |
| agent | ~20:50Z | Lock released; fresh deploy POST returned HTTP 202 (warm layers); deploy converging. |
| agent | ~20:55Z–22:18Z | Shipped durable ceiling fix #5066 (#5061): raise 900s→1800s across the coupled windows + wrapper; v0.116.1 converging via warm re-pulls meanwhile; prod healthy on 0.116.0. |
| agent | 22:18Z | #5066 merged → deploy-pipeline-fix apply ran `systemctl restart webhook` → killed the FD-200-holding `docker pull` child → freed the flock. |
| agent | 22:24Z | Next deploy completed on fully-cached layers (`exit_code=0`); **prod flipped to v0.116.1** (build_sha 6e7cac76). Resolved autonomously — no SSH. |

## Detection (+ MTTD)

- **How detected:** the `/ship` Phase 7 post-merge release-workflow verification (`wg-after-a-pr-merges-to-main-verify-all`) caught the failed `deploy` job immediately — not a user report.
- **MTTD:** ~0 (caught at the deploy job's terminal failure during active post-merge monitoring).

## Triggered by

PR #5051 WS2: `docker/setup-buildx-action` (docker-container driver, required for `type=gha` cache)
changed every pushed-image layer digest → one-time full re-pull on the prod server → exceeded the
900s deploy-completion ceiling.

## Root Cause

The 900s deploy-completion poll ceiling (coupled across `web-platform-release.yml`'s
STATUS/HEALTH/IN_FLIGHT constants and `ci-deploy-wrapper.sh`'s `timeout 900s`) assumes the server
re-pulls only *changed* layers (small). Any event that changes *all* layer digests — the buildx
driver switch here, or a future base-layer bump (claude-code/playwright/node) — forces a full
re-pull that can exceed 900s. The fragility pre-existed #5051; #5051 surfaced it.

Secondary anomaly: the deploy `flock` appeared held ~40 min, well past `ci-deploy-wrapper.sh`'s
900s SIGTERM / 920s SIGKILL — i.e. the long pull's lock outlived the wrapper's hard-kill, blocking
re-triggers. A stuck lock is a single-point deploy blocker (tracked separately).

## Lessons

1. Switching a Docker build driver (for a cache backend) is not transparent to the deploy path —
   it changes layer digests and forces a one-time full re-pull on every consumer. Weigh the build
   cache's value against the deploy-pipeline disruption it induces.
2. A deploy-completion ceiling sized for incremental pulls is fragile to any full-layer re-pull.
3. Post-merge release-workflow verification (`/ship` Phase 7) is load-bearing — it caught this in
   ~0 MTTD; without it the failed deploy would have been silent.

## Action Items & Follow-ups

| Issue | Owner | Item |
|---|---|---|
| #5061 | agent | Raise/soften the 900s deploy-completion ceiling (coupled workflow constants + `ci-deploy-wrapper.sh` timeout) to tolerate one-time large-layer re-pulls. |
| #5062 | agent | Investigate why the deploy `flock` outlived the 900s/920s wrapper hard-kill (stuck-lock blocks future deploys). |
| #5055 | agent | (pre-existing) Reorder prod-deps `npm ci --omit=dev` above `BUILD_*` ARGs — recovers the layer cache-busted every commit. |

## Open decision for the operator

Whether to **keep WS2 (the `type=gha` build cache + buildx driver)** or **revert it (keep only the
WS1 gate)**. Keep: the one-time transition re-pull is now paid (server has buildx layers); future
deploys are normal; pair with #5061 for resilience. Revert: restores the `docker`-driver deploy
behavior, but the revert deploy itself incurs another one-time re-pull (back to docker-driver
digests). Recommendation: **keep WS2 + ship #5061** — reverting adds a second transition for no net
gain, and WS1 (the brand-survival-critical gate) is independent and verified working.
