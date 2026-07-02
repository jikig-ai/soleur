---
title: "Runtime-plugin changes never reliably reach the Concierge host"
date: 2026-07-02
incident_pr: "feat-one-shot-plugin-deploy-gap (fix PR filed at ship time)"
incident_window: "2026-07-01 evening → 2026-07-02 morning"
recovery_at: "2026-07-02 morning (coincidental apps/web-platform deploy re-seeded the host); structurally fixed by the source PR"
suspected_change: "worktree-manager.sh stale-git-lock self-heal (plugins-only merge, 2026-07-01 evening) — a runtime-plugin change class that never triggered a deploy"
brand_survival_threshold: single-user incident
status: resolved
triggers: none
art_33_triggered: false
art_34_triggered: false
art_33_deadline: "n/a"
---

## Actor key

- `agent` — Claude Code did this autonomously (no operator ack required).
- `agent-with-ack` — Claude Code did this AFTER operator confirmed via menu option per `hr-menu-option-ack-not-prod-write-auth`.
- `human` — Operator did this directly.

## GDPR Art. 33/34 evaluation

**Art. 33 (supervisory-authority notification): false.** No personal data was
accessed, altered, exfiltrated, or lost. This is a deployment/availability +
process gap — a runtime fix silently not reaching the Concierge host. There is no
personal-data breach and therefore no 72-hour notification obligation.

**Art. 34 (data-subject notification): false.** No data subject is affected; the
risk is correctness/availability, not confidentiality or integrity of personal
data. Single-user (operator-only) impact surface.

# Incident Overview

Runtime-affecting changes to the Soleur plugin — skills, hooks, agents, scripts,
commands, and the `AGENTS.md`/`CLAUDE.md` instruction files the Concierge agent
executes from `/mnt/data/plugins/soleur` (a read-only bind-mount) — never reliably
reached the production Concierge host. The mount is seeded from the web-platform
image's baked plugin tree and re-seeded on every deploy, but the ONLY workflow
that rebuilds+deploys that image (`web-platform-release.yml`) triggered solely on
`apps/web-platform/**`. A plugins-only merge rebuilt no image, ran no deploy, and
never re-seeded — so a runtime-plugin fix landed on the host only by coincidence
when an unrelated `apps/web-platform/**` change happened to deploy.

## Status

resolved — both change-detection gates widened (denylist), the inner gate made
fail-loud, and a behavioral drift-guard test added, in the source PR.

## Symptom

The `worktree-manager.sh` stale-git-lock self-heal fix merged the evening of
2026-07-01, but the Concierge kept hitting the original `git EEXIST` failure the
next day: the host mount was still running the pre-fix script. The fix only
reached the host the next morning via a coincidental `apps/web-platform` deploy.

## Incident Timeline

- **Start time (detected):** 2026-07-02 morning (Concierge re-hit the pre-fix failure)
- **End time (recovered):** 2026-07-02 morning (coincidental apps deploy re-seeded)
- **Duration (MTTR):** ~overnight staleness window until the coincidental deploy

| Actor | Time (UTC) | Action |
|---|---|---|
| agent | 2026-07-01 evening | worktree-manager.sh self-heal merged (plugins-only) — no deploy fired. |
| human | 2026-07-02 morning | Concierge re-hit the pre-fix failure; staleness observed. |
| agent | 2026-07-02 morning | Coincidental apps/web-platform deploy re-seeded the mount; symptom cleared. |
| agent | 2026-07-02 | Root-caused the two-gate deploy filter; authored Option A fix + ADR-080 + this PIR. |

## Participants and Systems Involved

`web-platform-release.yml`, `reusable-release.yml` (`check_changed`),
`version-bump-and-release.yml`, `deploy-docs.yml`, the web-platform image
(`apps/web-platform/Dockerfile` plugin bake), `apps/web-platform/infra/ci-deploy.sh`
(host mount re-seed), and the Concierge host bind-mount `/mnt/data/plugins/soleur`.

## Detection (+ MTTD)

- **How detected:** external/manual — the operator observed the Concierge repeating
  a failure a merged fix was supposed to have resolved.
- **MTTD:** ~overnight (staleness only becomes visible on the next Concierge run
  exercising the fixed path).

## Triggered by

system — a CI trigger-topology gap (the deploy pipeline's change-detection filters
did not include the runtime-plugin surface).

## Root-cause hypothesis (triage)

| Hypothesis | Supporting evidence | Disconfirming evidence | Status |
|---|---|---|---|
| The host mount runs a stale plugin tree because plugins-only merges never rebuild/redeploy the image | Only web-platform-release.yml deploys, gated on apps/web-platform/**; the fix reached the host only via a later apps deploy | — | Confirmed |

## Resolution

Option A (CTO ruling): make a runtime-plugin merge rebuild+deploy the web-platform
image, so the mount re-seeds from the fresh image and image/host stay consistent by
construction. Both change-detection gates were widened with a DENYLIST
(`plugins/soleur/**` minus `docs/` and `test/`): the outer `on.push.paths`
(Actions-glob dialect) and the inner `check_changed` `path_filter` (git-pathspec
dialect, `:(exclude)`, NO `**`, under `set -f`). The inner gate was made fail-loud
(`set -euo pipefail` + explicit git rc check) so a git error can no longer be
swallowed into a green `changed=false` no-op. Option B (host-direct re-seed) was
disqualified — the next unrelated apps deploy would re-seed from an image baking the
stale tree and silently revert the fix.

## Recovery verification

- Pre-merge: `plugins/soleur/test/web-platform-runtime-plugin-trigger.test.ts` runs
  the byte-identical `check_changed` bash against synthesized diffs — runtime paths
  (incl. `worktree-manager.sh`, `AGENTS.md`, `CLAUDE.md`, a future `mcp/` surface)
  yield `changed=true`; `docs/`-only and `test/`-only yield `changed=false`; a git
  failure fails loud. `actionlint` + `shellcheck` clean on both workflows.
- Post-merge soak: `scripts/followthroughs/runtime-plugin-deploy-soak-*.sh` — after
  the first post-fix runtime-plugin merge, `app.soleur.ai/health` `.build_sha` must
  equal that merge's SHA (secret-free gh + curl check).

---

# Incident Post-Mortem Analysis

## Root Cause(s) — 5-Whys

1. **Why did the Concierge run a stale script?** The host bind-mount still held the
   pre-fix `worktree-manager.sh`.
2. **Why was the mount stale?** The mount re-seeds only on a web-platform image
   deploy, and no deploy ran after the plugins-only merge.
3. **Why did no deploy run?** `web-platform-release.yml` triggered only on
   `apps/web-platform/**`; the plugin surface was not in the trigger set.
4. **Why was the plugin surface excluded?** The deploy pipeline modeled the plugin
   tree as build-context vendoring only (baked into the image at #3045), never as a
   deploy TRIGGER — the image-baked-plugin seed model was undocumented.
5. **Why would a naive fix (widen only the outer trigger) not have worked?** A
   second, hidden inner gate (`reusable-release.yml` `check_changed`) re-keys every
   build/deploy step on `git diff -- "$PATH_FILTER"`; leaving it narrow (or letting
   it swallow errors into `changed=false`) produces a green no-op that reproduces
   the incident.

## Versions of Components

- **Version(s) that triggered the outage:** `web-platform-release.yml` with
  `on.push.paths: ['apps/web-platform/**']` + `reusable-release.yml` `check_changed`
  keyed on `apps/web-platform/` with an error-swallowing `git diff | head -1`.
- **Version(s) that restored the service:** the source PR's denylist widening of
  both gates + fail-loud inner gate (ADR-080).

## Impact details

### Services Impacted

Concierge runtime (executes plugin skills/hooks/instructions from the stale mount).
No web-platform HTTP surface, auth, or data path affected.

### Customer Impact (by role)

- Prospect: none.
- Authenticated app user (the operator, single-user): the Concierge executed stale
  plugin components after a fix merged — a merged fix appeared not to work.
- Legal-document signer: none.
- Admin via Access: none.
- Billing customer: none.
- OAuth installation owner: none.

### Revenue Impact

None.

### Team Impact

Single operator; an overnight confusion window ("the fix merged but the bug
persists") plus the investigation that produced this remediation.

## Lessons Learned

### Where we got lucky

A coincidental `apps/web-platform` deploy the next morning masked the staleness
before it caused durable harm — the failure mode is a silent, indefinite stale
mount that only a coincidental unrelated deploy clears.

### What went well

Root-causing traced the FULL mechanism (both gates + the seed path) rather than
stopping at the obvious outer trigger — surfacing the inner `check_changed`
landmine and the error-swallowing no-op before shipping a fix that would have been
a green no-op.

### What went wrong

The deploy pipeline had two independent change-detection gates in two dialects, one
of them silently defaulting to `changed=false` on any error — a fail-direction that
turns a runtime-fix delivery into an invisible skip.

## Action Items & Follow-ups

| Issue | Action | Status |
|---|---|---|
| #5892 | Harden the runtime-plugin change-detection basis beyond `HEAD~1` (push-range compare) — closes the non-squash/multi-commit recurrence vector (spec-flow G7) | open |
| #5891 | Suppress the duplicate plugin `v*` release announcement on runtime-plugin merges (dual-release co-fire noise) | open |
