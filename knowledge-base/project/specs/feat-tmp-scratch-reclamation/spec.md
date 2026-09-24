---
title: "Session temp/scratch reclamation — extend #7004 to /var/tmp with safe backlog purge"
date: 2026-09-24
issue: 7004
status: draft
lane: cross-domain
brand_survival_threshold: single-user incident
brainstorm: knowledge-base/project/brainstorms/2026-09-24-tmp-scratch-reclamation-brainstorm.md
supersedes-plan: knowledge-base/project/plans/2026-07-27-feat-tmpfs-ownership-keyed-scratch-root-reclamation-plan.md
---

# Session temp/scratch reclamation — /tmp + /var/tmp

## Problem Statement

Soleur sessions leave tens of thousands of orphaned temp dirs and files across
`/tmp` and `/var/tmp`. Measured on the operator host (2026-09-24): `/tmp` 5.5 GB
(~14k entries), `/var/tmp` **27 GB (~45k+ entries in ~7 days, ~4 GB/day)** —
including **1,484 orphaned git worktrees** and named fixture classes produced by
our own scripts/tests (`rung2-archive` 12.8k, `gdboot` 7.8k, `inngest-ci/arm` ~6k,
`pirgate`/`kbcov`/`mutbat`/`gdpr-gate-incidents`/`pmr-*` etc.).

Detection shipped (#6998, #7019); reclamation was deferred in #7004 and its plan
was never executed (PR 1/PR 2 unstarted). The plan's "legacy backlog self-drains"
premise holds for the tmpfs but **fails on disk-backed `/var/tmp`**: 30d
tmpfiles aging vs ~4 GB/day production against 46G free ≈ 11-day runway.
Separately, the designed 5-min cron trigger **does not exist on this host**
(no `crontab` binary; the guard has never run), so session-start is the only
live reclamation surface.

## Goals

- G1: A one-time **operator-invoked backlog purge** that reclaims the existing
  /tmp + /var/tmp backlog safely — dry-run report first, `mv`-to-quarantine only,
  restricted to certain-attribution classes.
- G2: Finish #7004's ownership-keyed reclamation machinery extended to both
  bases: `soleur_scratch_session_begin` allocator + Reaper 3 on
  `TMPFS_GUARD_SCRATCH_BASES="/tmp /var/tmp"`.
- G3: A git-aware orphaned-worktree sweep for `.git`-bearing dirs outside
  `.worktrees/` — quarantine + report; drain only after clean/merged/no-unpushed
  verification.
- G4: A `.soleur-owned` marker convention (carries `pid=` + `schema=`) so
  producers that cannot adopt the allocator still declare ownership.
- G5: Producer-side adoption at the biggest measured leakers (self-reap at
  startup, `infra-suites.*` precedent; traps/markers at `.ts` fixture writers).
- G6: Zero false-positive deletions — every destructive path is
  quarantine-mediated; sibling-session scratch is never reaped.

## Non-Goals

- **Heuristic reclamation over shared namespaces.** Age/size/prefix inference
  for auto-reap remains rejected (#7004 measured: ~1,500 authored files would
  have been deleted). The purge's allowlist is *certain-attribution* only —
  classes traced to in-repo writers or self-declared markers; it is
  operator-invoked and quarantine-mediated, not an auto-reaper heuristic.
- Bare `tmp.*` non-git dirs in /var/tmp (16.4k) — unattributable; left to
  systemd-tmpfiles 30d aging. (Documented, not filed — inline-triage: no
  concrete trigger that would make a different action correct.)
- `skill-security-scan-*` retention (#6760 — deliberate durable output; its own
  retention-policy issue stays separate).
- `plan-*`, `shared-*`, `vbcr*` — no in-repo writer found; not reaped by any
  mechanism here (unverifiable attribution).
- Migrating the TMPDIR=/var/tmp convention itself to XDG_CACHE_HOME —
  evaluated and rejected in research (breaks ~236 per-file exports; loses the
  tmpfiles 30d backstop; `scratch-root.sh` covers the need differently).
- Auto-reaping `systemd-private-*`, `playwright`, `node-compile-cache`,
  `claude-<uid>` (owned by other reapers or foreign tools).

## Functional Requirements

- FR1: `scripts/soleur-tmp-purge.sh` — operator-invoked; default dry-run report
  (class → count → est. bytes); `--apply` quarantines only classes in a
  committed allowlist past an age floor; everything moves via `mv` to
  `<base>/soleur-quarantine.<uid>/`; prints a forensic list of moved basenames.
- FR2: Orphaned worktree classification inside the purge: `.git`-bearing dirs
  are checked against `git worktree list --porcelain`; registered → removed via
  `git worktree remove` **only** when clean + merged + no unpushed commits +
  past age floor; unregistered or unverifiable → quarantine + report, never
  delete.
- FR3: `soleur_scratch_session_begin [base]` in `scripts/lib/scratch-root.sh`
  per the #7004 plan tasks 1.1–1.9 (subshell guard, sourced-file guard,
  `mktemp -d "$base/soleur-run.$$.XXXXXXXX"`, holder fd, `TMPDIR` export, single
  quarantine trap).
- FR4: `reap_orphan_scratch_roots()` (Reaper 3) in `scripts/tmpfs-guard.sh`
  covering `TMPFS_GUARD_SCRATCH_BASES` — schema-anchored parse, `/proc/<pid>`
  absence, held-fd + environ liveness, allocation-free enumeration, quarantine
  + TTL drain.
- FR5: `.soleur-owned` marker — producers write `<dir>/.soleur-owned` with
  `pid=` + `schema=`; Reaper 3 and the purge treat marker-bearing dirs as
  declared-owned (same liveness gates as `soleur-run.*`); a marker without
  `pid=` is invalid and ignored.
- FR6: Session-start sweep (`worktree-manager.sh cleanup-merged`) reaps
  schema-named + marker-bearing orphans on **both** bases, sharing the
  tmpfs-guard flock protocol; it never touches non-attributed classes.
- FR7: Producer adoption — `test-all.sh` / `run-registered-suites.sh` migrate
  to session roots (extend existing traps, never a second trap — ADR-129);
  top fixture writers (`rung2-archive`, `gdboot`, `pirgate`, `kbcov`,
  `gdpr-gate-incidents`, `deploygap`, `inngest-ci/arm`) gain self-reap-at-
  startup or `.soleur-owned` markers.
- FR8: Optional `systemd --user` timer unit + install doc for `tmpfs-guard.sh`
  on cron-less hosts (this host has no `crontab`).

## Technical Requirements

- TR1: **Merge-blockers before enabling `/var/tmp`** (CLO gate): base-aware
  `_INUSE_TOP`/`_mark_inuse` (plan 2X.5c), `_INUSE_TOP["__built__"]` fail-closed
  sentinel (2X.6), `TMPFS_GUARD_SCRATCH_BASES` seam fail-closed when unset
  (AC14), lockfile pinned to a TMPDIR-independent path (task 2.11), Reaper-2
  protect-list extended with `soleur-run.*|soleur-quarantine.*` (task 2.10).
- TR2: No `rm -rf`/`find -delete` on any shared-base path anywhere in the new
  machinery — quarantine `mv` only (same-filesystem rename; 0700 quarantine
  dirs).
- TR3: Liveness must survive `execve`/fork — held fd + `/proc/<pid>/environ`
  conjunctive checks; enumerate inheriting children (fd inheritance outlives
  the owner — 2026-09-22 learning).
- TR4: `/proc` degradation (`hidepid`) → skip the arm entirely, never reap on
  degraded evidence (plan risk table).
- TR5: Dry-run the purge + Reaper 3 against the **real** /tmp and /var/tmp
  before merge; record the measured pass time and candidate counts in the PR
  body (plan AC2 as amended; learning: dry-run destructive changes on the real
  target).
- TR6: Re-read state immediately before each destructive action — a listing
  snapshot is not action-time truth (2026-09-24 stale-reaper learning); the
  reaper must also verify its own code freshness (same learning).
- TR7: `soleur:gdpr-gate` at plan Phase 2.7 and work Phase 2 exit (CLO:
  expansion trigger fires via `single-user incident`); expected outcome is
  scope-out.
- TR8: Alarm/reporting channel: `~/.local/state/soleur/tmpfs-guard-alarms.log`
  consumed by `session-rules-loader.sh` (existing channel — reuse, do not
  invent a new one).
- TR9: ADR (ordinal at ship): extends the ownership-keyed reclamation decision
  to `/var/tmp`, records the never-delete-user-data compliance case for the
  second base, and registers the `.soleur-owned` marker schema + the purge's
  attribution allowlist.

## Constraints

- `hr-bulk-delete-per-item-live-infra-role-check` — classify each purged item's
  live-infra role before bulk mutation; the allowlist is per-class, and each
  class entry cites its writer file:line.
- `hr-menu-option-ack-not-prod-write-auth` — the purge `--apply` is a
  destructive-ish action (quarantine-mediated, recoverable) run per explicit
  operator invocation, never auto.
- Sibling sessions are the norm — a reaper must never reap a live sibling's
  scratch (liveness conjuncts + held-fd + environ + recent-commit grace).
- Do NOT `git add -A` / `git add .` — scoped adds only.
- Test fixtures synthesized only (`cq-test-fixtures-synthesized-only`).

## Acceptance Criteria

- AC1: `soleur-tmp-purge.sh --dry-run` on a host carrying the real backlog
  reports per-class counts and zero unattributable candidates; `--apply` moves
  only allowlisted classes to quarantine; re-running is idempotent.
- AC2: Reaper 3 reaps a `soleur-run.*` root whose owner pid is dead on **both**
  bases; spares live-owner roots; quarantine drains past TTL; `DRY_RUN` inert.
- AC3: Orphaned-worktree arm: unregistered `.git` dir → quarantine + report;
  registered + clean + merged + no-unpushed + old → `git worktree remove`;
  registered + dirty/unpushed → untouched and reported.
- AC4: `.soleur-owned` marker dirs reap under the same gates as `soleur-run.*`;
  marker without `pid=` never reaps.
- AC5: Session-start sweep output names per-base reaped counts
  (`SOLEUR_TMP_REAP` lines) and shares the guard's flock (no racing reapers).
- AC6: After adoption, a full `test-all.sh` + `run-registered-suites.sh` run
  leaves **zero** new unattributed top-level entries in either base (residue
  probe measurement recorded in PR body).
- AC7: gdpr-gate report attached; zero Critical findings.
- AC8: An ADR lands covering TR9; the #7004 issue is updated with the
  artifacts + acceptance-status note.

## Observability

- **Primary signal:** `SOLEUR_TMP_REAP`/`SOLEUR_TMP_PURGE` stdout lines at
  session-start + purge runs; found-count telemetry (guards against silent
  no-op if the schema glob drifts).
- **Alarm channel:** `~/.local/state/soleur/tmpfs-guard-alarms.log` →
  `session-rules-loader.sh` SessionStart block (existing reader; reaper
  silent-failure surfaces there).
- **Quarantine ledger:** `<base>/soleur-quarantine.<uid>/` contents + forensic
  basename list printed per run — the audit trail for every destructive action.
- **discoverability_test.command:** `bash scripts/soleur-tmp-purge.sh --dry-run`
  — runs without SSH, prints the attributable-class report.
- **Failure-mode → layer map:** false-positive deletion → quarantine +
  forensic list (recoverable); silent no-op reaper → found-count telemetry +
  adoption floor; live-sibling reap → liveness conjuncts (TR3); degraded
  `/proc` → skip-arm + alarm.

## Cross-references

- Issue #7004 (tracking; its remaining tasks are superseded-by-reference: this
  spec's FR/TR set replaces plan tasks 1.x–6.x, preserving the named merge
  blockers and safety conjuncts).
- Prior plan: `knowledge-base/project/plans/2026-07-27-feat-tmpfs-ownership-keyed-scratch-root-reclamation-plan.md`
- Prior spec/tasks: `knowledge-base/project/specs/feat-one-shot-7004-tmpfs-reclaim-scratch-roots/`
- Brainstorm: `knowledge-base/project/brainstorms/2026-09-24-tmp-scratch-reclamation-brainstorm.md`
- Adjacent open issues: #6760 (out of scope), #8659 (trap-composition class —
  informs FR7), #7210 (tmpfs-guard host failures — verify before relying on
  guard behaviors), #8496 (same `cleanup-merged` block — coordinate).
