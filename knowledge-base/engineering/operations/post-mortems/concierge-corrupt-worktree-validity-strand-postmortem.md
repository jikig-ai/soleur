---
title: "Concierge dispatch strands on a present-but-INVALID `.git` (presence-not-validity gate)"
date: 2026-06-29
incident_pr: 5584
incident_window: "recurring; last observed 2026-06-29 ~22:0x UTC (after the #5716 deploy)"
recovery_at: "2026-06-29 (PR #5584 merged) + operator reconnect as immediate unblock"
suspected_change: "dispatch readiness gated on `.git` PRESENCE (existsSync), not VALIDITY — a corrupt/empty `.git` short-circuited the self-heal"
brand_survival_threshold: single-user incident
status: resolved
triggers:
  - "<ws>/.git exists but is not a valid work tree (partial/interrupted clone, failed atomic-rename, empty dir)"
  - "Concierge dispatch (cold or warm) into that workspace"
art_33_triggered: false
art_34_triggered: false
art_33_deadline: "n/a"
---

## Actor key

- `agent` — Claude Code did this autonomously (no operator ack required).
- `agent-with-ack` — Claude Code did this AFTER operator confirmed via menu option per `hr-menu-option-ack-not-prod-write-auth`.
- `human` — Operator did this directly.

# Incident Overview

The operator's Concierge `/soleur:go` flow repeatedly stranded: `git status` → `fatal: not a git repository`, `go.md` Step 0.0 honest-stopped. The dispatch **proceeded** into a repo-less agent (the operator saw go.md's gate, NOT the `repo reclaimed` message) while `repo_status='ready'` and `repo_error=null`. That signature is decisive: the self-heal **short-circuited on `existsSync('.git')===true`** — i.e. `<ws>/.git` was **present but invalid** (a corrupt/empty `.git`). The presence-only readiness gate fast-pathed it into a corrupt-repo spawn with **zero Sentry signal**.

This is the **actual root cause of the operator's recurring failure**. Sibling PR #5716 (warm-dispatch await for an *absent* `.git`) fixed a real but DISTINCT latent bug; it could not catch this case because it is gated on `.git` ABSENT, and here `.git` was present (just invalid). See the correction note appended to `concierge-warm-dispatch-reclaim-strand-postmortem.md`.

## Status

resolved

## Symptom

`git rev-parse --is-inside-work-tree` / `git status` report "not a git repository" inside `/workspaces/<id>`, while the DB shows `repo_status='ready'`. The dispatch is not blocked (no reclaim message) — it silently spawns into the corrupt repo.

## Incident Timeline

- **Start time (detected):** 2026-06-29 (recurring; explicitly re-reported by the operator after the #5716 deploy)
- **End time (recovered):** 2026-06-29 (PR #5584 merged; operator reconnect as the immediate unblock)
- **Duration (MTTR):** same-session

| Actor | Time (UTC) | Action |
|---|---|---|
| human | 2026-06-29 | Reports the strand STILL recurs after #5716 deployed. |
| agent | 2026-06-29 | Pulls live prod: `754ee124` is `ready`/no-error yet dispatch proceeds → diagnoses present-but-invalid `.git` (presence-not-validity gap). |
| human | 2026-06-29 | Reconnects the repo (Settings → Repository) — wipe-and-reclone bypasses the presence short-circuit (immediate unblock). |
| agent | 2026-06-29 | Lands the durable fix: PR #5584 (validity-not-presence + corrupt-worktree re-clone). |

## Participants and Systems Involved

Concierge dispatch readiness (`cc-dispatcher.ts`, `repo-readiness-self-heal.ts`, `ensure-workspace-repo.ts`, new `git-worktree-validity.ts`); operator workspace `754ee124` (repo `jikig-ai/soleur`); single live operator.

## Detection (+ MTTD)

- **How detected:** external/manual — operator report. The presence-only gate emitted no error and no Sentry signal, so no monitor fired (the exact gap this PR closes by emitting `corrupt-worktree-at-dispatch`).
- **MTTD:** unknown (recurred before the explicit re-report).

## Triggered by

system — an on-disk `.git` left in an invalid state (partial/interrupted clone or failed atomic-rename) by a prior reclaim/clone.

## Root-cause hypothesis (triage)

| Hypothesis | Supporting evidence | Disconfirming evidence | Status |
|---|---|---|---|
| Absent `.git` + warm-race (#5716) | strand symptom | dispatch PROCEEDED (no reclaim msg) ⇒ existsSync(.git) true ⇒ `.git` present | rejected as the operator's cause (real but separate bug) |
| Present-but-invalid `.git` + presence-only gate | dispatch proceeds; repo_status ready; no Sentry | — | confirmed |

## Resolution

Dispatch readiness now keys on on-disk worktree **VALIDITY** (`isValidGitWorkTree`: `.git` is a gitdir-pointer FILE → valid; or a directory with both `HEAD` and `objects` → valid) instead of mere presence, at all sites (cold self-heal, the warm `cc-reprovision` short-circuit, and `ensure-workspace-repo`). A corrupt `.git` routes to a corrupt-worktree graft that removes it **only on a positive empty-corrupt fingerprint** (`isEmptyCorruptGitDir`: directory + HEAD ENOENT + objects ENOENT — no objects ⇒ no commits to lose), re-clones under the workspace lock, and emits a `corrupt-worktree-at-dispatch` Sentry breadcrumb (`extra.recovered` true/false). A populated-but-broken / EACCES / gitdir-FILE `.git` is honest-blocked, never destroyed. PR #5584.

## Recovery verification

`tsc --noEmit` clean; full `vitest run` green (10996 tests). Five review agents (data-integrity, security, architecture, observability, test-design) + semgrep: no P1/P2 in code; the destructive `rm` was confirmed fenced (never destroys commits), with the EACCES guard now under test. Operator reconnect restored `754ee124` immediately; the durable fix auto-recovers future corrupt-`.git` workspaces without a manual reconnect.

---

# Incident Post-Mortem Analysis

## Root Cause(s) — 5-Whys

1. Why strand? Agent CWD had an invalid `.git`. → 2. Why invalid? A prior reclaim/clone left `<ws>/.git` present but structurally incomplete. → 3. Why not re-cloned? The readiness self-heal short-circuited on `existsSync('.git')===true`. → 4. Why presence-check? The gate was written as "repo_status-ok AND `.git` present" (the 2026-06-18 Bug-2 graft), never tightened to validity. → 5. Why undetected? The presence short-circuit set no error and emitted no Sentry signal — the failure was structurally silent until go.md Step 0.0.

## Versions of Components

- **Triggered:** web-platform with the presence-only readiness gate (through `v3.178.5`).
- **Restored:** PR #5584 (+ operator reconnect for the immediate instance).

## Impact details

### Services Impacted

Concierge `/soleur:go` dispatch for any workspace whose on-disk `.git` is present-but-invalid.

### Customer Impact (by role)

- Prospect: none.
- Authenticated app user: the single live operator could not run Concierge tasks in the affected workspace (silent strand), recurring across retries.
- Legal-document signer: none.
- Admin via Access: none.
- Billing customer: none.
- OAuth installation owner: none (connection intact; only the on-disk checkout was corrupt).

### Revenue Impact

None (pre-revenue; single dogfooding operator).

### Team Impact

Repeated failed operator sessions; engineering time to distinguish this from the sibling absent-`.git` race.

## Lessons Learned

### Where we got lucky

The "dispatch proceeded + repo_status ready + no reclaim message" signature unambiguously fingerprinted presence-not-validity, separating it from the absent-`.git` race after the first fix didn't resolve the operator's symptom.

### What went well

The destructive re-clone is safety-fenced (positive empty-corrupt fingerprint only); the corrupt path is now observable (`corrupt-worktree-at-dispatch`); operator reconnect was a correct zero-risk immediate unblock.

### What went wrong

A readiness gate checked presence where it needed validity, and the short-circuit was silent (no error, no Sentry) — so the failure was invisible to monitoring and the first fix attempt targeted the wrong (absent-`.git`) mechanism.

## Action Items & Follow-ups

_No action items — incident fully resolved in the source PR with no residual work._
