---
title: "Concierge worktree creation wedged for six rounds — identity-authority inversion, not a lock bug"
date: 2026-07-07
incident_pr: 6183
incident_window: "~2026-06-01 to 2026-07-07 (recurring across six fix rounds)"
recovery_at: "2026-07-07 (PR #6183 merge)"
suspected_change: "ensure_worktree_identity forcing the sandbox github-actions[bot] --global over the host-seeded owner --local on the non-bare Concierge workspace"
brand_survival_threshold: single-user incident
status: resolved
triggers:
  - recurring full-workspace outage (autonomous /soleur:one-shot and /soleur:go blocked at worktree creation)
art_33_triggered: false
art_34_triggered: false
art_33_deadline: "n/a"
---

## Actor key

- `agent` — Claude Code did this autonomously.
- `agent-with-ack` — after operator menu-confirm.
- `human` — operator directly.

# Incident Overview

`worktree-manager.sh create` failed in the non-bare Concierge/agent-sandbox web environment, aborting worktree creation (RC=255) and thereby blocking **every** autonomous `/soleur:one-shot` and `/soleur:go` run for affected workspaces. Six consecutive fix rounds (#5880 → #5907 → #5932 → #5934 → #6041 → #6071/#6108) all hardened the bare-repo lock-handling machinery and all failed, because the actual failing code path (`ensure_worktree_identity`) runs on a different layout and failed for an un-instrumented reason.

## Status

resolved — PR #6183.

## Symptom

Unremovable `.git/config.lock` reporting `File exists`/EEXIST (RC=255) at worktree creation; the product's core promise (autonomous engineering runs) dead for the affected Concierge workspace.

## Incident Timeline

| Actor | Time (UTC) | Action |
|---|---|---|
| human | ~2026-06-01 | First wedge reports; rounds #5880–#6108 harden the bare-repo lock/sweep/atomic_git_config path. |
| human | 2026-07-07 | Operator reports the wedge still recurs; challenges the "workspace is bare like Concierge" assumption. |
| agent | 2026-07-07 | Better Stack telemetry (`type=chardevice rdev=1:3`) + local RC=255 repro locate the real cause: identity-authority inversion in `ensure_worktree_identity`. |
| agent | 2026-07-07 | PR #6183: bot-aware identity fix + ADR-099 topology + telemetry sentinels + all-scripts audit. |

## Detection (+ MTTD)

- **How detected:** operator report of repeated recurrence after six shipped fixes; telemetry pull confirmed the signature.
- **MTTD:** ~5 weeks across rounds (the abort was a plain-git `EEXIST`, not a `SOLEUR_GIT_LOCK_*` marker, so it was invisible to the existing telemetry — the core detection gap this PR closes).

## Triggered by

`ensure_worktree_identity` issuing a raw `git config --local` write to overwrite the host-seeded owner identity with the sandbox image's `github-actions[bot]` `--global`; that write acquires the shared config lock and EEXISTs on the deliberately-masked char-device `.git/config.lock` (ADR-081 RCE guard).

## Resolution

Made `ensure_worktree_identity` bot-aware: respect a present non-bot local identity (zero writes on the common Concierge path), override a bot-shaped local from a human `--global`, and refuse to ever write a bot-shaped `--global`. Added `SOLEUR_GIT_LOCK_IDENTITY_{WEDGED,DIAG}` telemetry so the next occurrence self-diagnoses. Canonicalized the three-git-surface topology in ADR-099.

## Recovery verification

56 test assertions (T1–T19) green; telemetry drift test + tsc + shellcheck + budget lint green; multi-agent review (one P2 fixed inline).

## Root Cause(s) — 5-Whys

1. Why did worktree creation abort? → `git config --local` EEXIST'd on a masked config.lock.
2. Why was it writing config at all? → `ensure_worktree_identity` tried to overwrite the local identity with `--global`.
3. Why overwrite the correct owner? → the function assumed the bare-dev polarity (global = human, local = bot); on non-bare Concierge it is inverted (global = bot, local = owner).
4. Why did six rounds miss it? → the abort was a plain-git EEXIST, not a `SOLEUR_GIT_LOCK_*` marker, so telemetry never saw it; and the git-surface topology was tribal knowledge, so every round hardened the guarded-out bare path.
5. Why was topology tribal? → it lived only as an inline comment + server code, never a canonical loaded fact. → ADR-099 fixes this.

## Impact details

### Services Impacted

Concierge autonomous engineering (worktree creation → all downstream one-shot/go work).

### Customer Impact (by role)

Affected-workspace operators: autonomous runs fully blocked at creation. No data loss, no data exposure.

### Revenue Impact

None quantified (internal tooling / dogfood surface).

### Team Impact

Six fix rounds of engineering effort mis-targeted at the wrong layer.

## Lessons Learned

### Where we got lucky

The wedge was accidentally *protective* — the raw write it blocked would have silently misattributed commits to the bot. The loud wedge prevented a quiet git-history-corruption bug.

### What went well

Evidence-first telemetry + local reproduction overturned two wrong hypotheses before any round-7 code shipped.

### What went wrong

Six rounds shipped against an un-instrumented, wrong-layer hypothesis because the failure signature was never captured and the topology was never canonical.

## Action Items & Follow-ups

| Issue | Item | Owner |
|---|---|---|
| #6186 | Unify `_config_lock_wedged` with the sweep's node-classification (deferred hardening) | agent |
| #6191 | Route `workspace.ts` identity seed through `atomic_git_config` + record the `prod-write-defer-gate` `--global` inversion caveat (2 latent non-bare sites) | agent |
