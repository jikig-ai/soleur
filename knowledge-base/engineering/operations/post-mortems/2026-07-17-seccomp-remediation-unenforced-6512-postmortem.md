---
title: "seccomp remediation redeploy failed image_pull_failed — profile left unenforced and invisible (#6512)"
date: 2026-07-17
incident_pr: 6622
incident_window: "2026-07-16T21:03Z (item-4 redeploy failed, host_present=false) → self-resolved by a later normal deploy (host_present=true on v0.222.1 by 2026-07-17)"
recovery_at: "2026-07-17 — live /hooks/deploy-status shows host_present=true && loaded_matches_host=true; #6622 ships the durable reload-robustness + alarm so a future occurrence survives and pages"
suspected_change: "no single change — a several-releases-old running version became GC-eligible from zot's 5-v* keep-set (#6246), and the GHCR fallback leg also failed, so the item-4 same-version seccomp reload died image_pull_failed for an image needing no new bits"
brand_survival_threshold: aggregate pattern
status: resolved
triggers:
  - one red `Apply deploy-pipeline-fix` job on a merge commit (post-merge verification of #6458)
art_33_triggered: false
art_34_triggered: false
art_33_deadline: "n/a"
---

## Actor key

- `agent` — Claude Code did this autonomously (no operator ack required).
- `human` — Operator did this directly.

# Incident Overview

On 2026-07-16 the ADR-079 item-4 step (the "applied ≠ loaded" seccomp closer) sequenced a graceful redeploy to load a committed seccomp profile onto the running web-platform container. The redeploy terminated `image_pull_failed` on tag `v0.214.7` — leaving `seccomp_profile_host_present=false`, i.e. the container seccomp layer of the tenant-agent sandbox boundary **not in force**. Crucially, prod health hid it completely (`app.soleur.ai` → HTTP 307 throughout; the release pipeline succeeded on the same commit) — the only signal was one red job among a page of green. This is the #6454 invisible-gate shape: a real control unenforced while everything anyone looks at is green.

## Status

resolved — the acute unenforcement self-resolved via a later normal deploy (live `/hooks/deploy-status` on v0.222.1 reports `host_present=true, loaded_matches_host=true`). PR #6622 ships the durable fix so the systemic gap (a same-version reload dying on a both-registries-fail + the unenforcement being invisible) cannot recur silently.

## Symptom

```
Baseline: host_present=false host_sha256='<none>' loaded_matches_host=false (committed='7654ef…', tag='latest').
STATE invariant not satisfied — a seccomp change is applied but the running container is not enforcing it. Redeploying to load it.
Redeploying running version as v0.214.7 (state-file .tag was 'latest').
Redeploy FAILED: web-platform v0.214.7 terminal reason='image_pull_failed' exit_code=1. The applied seccomp profile was NOT loaded.
```

## Incident Timeline

- **Start time (detected):** 2026-07-16T21:03Z — item-4 redeploy of the running `v0.214.7` failed `image_pull_failed`; profile left unenforced.
- **Not user-facing:** prod stayed healthy; the issue (#6512) itself noted "This is not a production outage — which is why it will get ignored."
- **Self-resolution:** subsequent normal releases (v0.215.x … v0.222.1) re-ran `docker run` with the profile, restoring enforcement without operator action.
- **Durable fix:** 2026-07-17 — #6622 (this PR).

## Root Cause

Two coupled causes, both confirmed in Phase-0 diagnosis:

1. **The seccomp reload depended on a registry pull it did not need.** The item-4 redeploy targets `v<running_version>` — the exact image the container is already running (cosign-checked at its original deploy, immutable @sha256, always in the host's local docker store). Yet `ci-deploy.sh` re-pulled it through the zot-primary → GHCR-fallback chain. zot's tightened 5-`v*` keep-set (#6246) makes a several-releases-old running version GC-eligible; when the GHCR fallback leg then also failed (transient/auth — GHCR still retains `v0.214.7`, verified HTTP 200 live), the reload died for an image needing no new bits.
2. **The unenforcement was invisible.** `host_present=false` surfaced only as one red merge-commit job — no operator-readable alert (`operator-digest` harvests action-required GitHub issues, not red CI jobs). This is the #6454/#6537 inert-gate class.

Note: issue ask #1 ("state-file `.tag='latest'` aimed the remediation at a stale image") is a **non-bug** — #5955 already resolves the redeploy target from `/health` `.version`, not `.tag`; `v0.214.7` was the correct running version at 21:03.

## Resolution

PR #6622 (ADR-079 `(#6512)` amendment):

- **Fix 1** — a `local-cache` last-resort tier in `pull_image_with_fallback`: on both-registries-fail for a **same-version** `web` reload, reuse the running container's already-verified image ID (a strict same-version RepoTag guard prevents stale-bits rollback on a new-version deploy). Removes the registry dependency for a reload.
- **Fix 2a** — `scripts/seccomp-unenforced-alert.sh` files a plain-language `ci/seccomp-unenforced` GitHub issue + a `seccomp_remediation_failed` Sentry event on any item-4 terminal failure that leaves the profile unenforced, so the next occurrence pages instead of hiding.

## Action Items & Follow-ups

| Issue | Item | Owner |
| --- | --- | --- |
| #6628 | Fix 2b — standing 6h seccomp-enforcement drift watchdog (build when a non-merge unenforcement path is observed) + the stale-but-enforcing residual page | agent |
| #6629 | Deep delivery-leg RCA — why `host_present=false` (the profile file absent from the host) before the redeploy | agent |
