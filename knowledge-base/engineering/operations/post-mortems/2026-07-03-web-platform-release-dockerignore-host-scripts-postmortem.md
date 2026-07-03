---
title: "web-platform release build broke on main — baked host-scripts excluded by .dockerignore"
date: 2026-07-03
incident_pr: 5922
incident_window: "2026-07-03 07:12Z (merge) → 07:~40Z (hotfix merged)"
recovery_at: "2026-07-03 (hotfix re-includes the files)"
suspected_change: "PR #5922 added a Dockerfile COPY of 25 baked host-scripts without re-including them in .dockerignore"
brand_survival_threshold: aggregate pattern
status: resolved
triggers:
  - availability (web-platform release/deploy pipeline)
art_33_triggered: false
art_34_triggered: false
art_33_deadline: "n/a"
# Classification rationale: availability-only — a broken image build blocked the
# deploy of the SAME app code; no personal-data breach, no confidentiality/integrity
# loss. GDPR Art. 33/34 do not apply (n/a).
---

## Actor key

- `agent` — Claude Code did this autonomously (no operator ack required).
- `agent-with-ack` — Claude Code did this AFTER operator confirmed via menu option.
- `human` — Operator did this directly.

# Incident Overview

Immediately after PR #5922 merged to `main`, the **Web Platform Release** workflow's
`release / release` job failed at "Build and push Docker image":

```
#33 ERROR: failed to calculate checksum of ref ...: "/app/infra/cron-egress-resolve.sh": not found
ERROR: failed to build: failed to solve: failed to compute cache key
```

The `deploy` job was consequently **skipped** (gated on release success), so prod stayed
on the prior image. Because the build error is on `main`, **every** subsequent
web-platform release would also fail until fixed — a release-pipeline outage, not a
single-PR failure.

## Status

resolved — hotfix re-includes the 25 baked files in `.dockerignore`; a guard-test leg
was added so the class fails at `bun test` time (which CI runs) instead of at Docker-build
time (which CI does not run pre-merge).

## Symptom

Docker build aborts at the runner-stage `COPY --from=builder /app/infra/<file> ...
/opt/soleur/host-scripts/` because `/app/infra/cron-egress-resolve.sh` (and the other 24
baked files) do not exist in the builder stage.

## Incident Timeline

| Actor | Time (UTC) | Action |
|---|---|---|
| agent | 2026-07-03 07:12 | PR #5922 merged; Web Platform Release starts. |
| agent | 2026-07-03 07:16 | `release / release` fails at Build-and-push-Docker-image; deploy skipped. |
| agent | 2026-07-03 07:~30 | /ship Phase 7 verification surfaces the failure; root-caused to `.dockerignore` `infra/` exclude. |
| agent | 2026-07-03 07:~40 | Hotfix: re-include all 25 baked files + guard-test leg; verified via targeted docker build. |

## Detection (+ MTTD)

- **How detected:** /ship Phase 7 post-merge release-workflow verification (the
  `wg-after-a-pr-merges-to-main-verify-all` gate). MTTD ≈ minutes.

## Triggered by

system — a Dockerfile COPY added without the matching `.dockerignore` re-include.

## Root-cause hypothesis (triage)

| Hypothesis | Supporting evidence | Disconfirming evidence | Status |
|---|---|---|---|
| Baked files excluded from build context by `.dockerignore` `infra/` | buildkit "not found" in builder; `infra/` excluded with only 2 JSON re-includes | — | confirmed |

## Resolution

Add `!infra/<file>` for all 25 baked host-scripts in `apps/web-platform/.dockerignore`
(same pattern as the existing `sandbox-canary-argv.json` / `sandbox-canary.mjs`
re-includes). Extend `plugins/soleur/test/cloud-init-user-data-size.test.ts` with a third
parity leg asserting every Dockerfile-baked file is re-included in `.dockerignore`.

## Recovery verification

Targeted `docker build` of a throwaway image COPYing the previously-missing files from the
real `apps/web-platform` context now resolves (`DOCKERIGNORE_FIX_OK`). Guard test: 22 pass.
Post-merge, the web-platform release build goes green and `deploy` runs.

---

# Incident Post-Mortem Analysis

## Root Cause(s) — 5-Whys

1. **Why** did the release build fail? The runner `COPY --from=builder /app/infra/<file>` couldn't find the files.
2. **Why** were they missing in the builder? `.dockerignore` excludes `infra/`, so builder-stage `COPY . .` dropped them.
3. **Why** wasn't `.dockerignore` updated? #5922 added the bake COPY but not the matching re-includes.
4. **Why** didn't a test catch it? The size-guard asserted Dockerfile↔server.tf parity but not `.dockerignore` re-include coverage; CI runs `bun test`, not the Docker build.
5. **Why** is the gap latent? The `.dockerignore`-exclude-then-COPY interaction only fails at image-build time — a surface CI does not exercise pre-merge.

Root cause: **a Dockerfile COPY of context-excluded files with no source-level test of `.dockerignore` re-include coverage.**

## Versions of Components

- **Triggered:** main @ 4bfe714 (#5922).
- **Restored:** this hotfix.

## Impact details

### Services Impacted

web-platform release/deploy pipeline (all releases blocked while main was red). The app
runtime itself was unaffected — prod continued serving the prior image.

### Customer Impact (by role)

- Prospect / Authenticated app user / Legal signer / Admin / Billing / OAuth owner: **none** — no user-facing change was pending in #5922 (the bake affects fresh-host provisioning only), and prod kept running the prior image.

### Revenue Impact

None.

### Team Impact

~1 hotfix cycle; blocked deploys until merged.

## Lessons Learned

### Where we got lucky

Post-merge verification caught it within minutes; the pending change (#5922 bake) was
inert at runtime, so no user-facing regression accrued during the red window.

### What went well

The exact class already had precedent (#5875/#5890 sandbox-canary re-includes) — root cause
was immediate, and a source-level guard now covers it.

### What we can do better

This is the **recurring `.dockerignore`-copy-gap class** (now 2+ instances). A generic guard
that cross-checks EVERY `COPY --from=builder /app/<path>` against `.dockerignore`
re-includes (not just the host-scripts set) would cover the whole class; tracked by the
in-flight dockerignore-copy-gap learning work.

## Action Items & Follow-ups

_No action items — incident fully resolved in the source PR with no residual work._
