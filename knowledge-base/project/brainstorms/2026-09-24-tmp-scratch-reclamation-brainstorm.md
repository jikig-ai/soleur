# Brainstorm: Session temp/scratch reclamation (/tmp + /var/tmp)

- **Date:** 2026-09-24
- **Issue:** #7004 (open — this work continues/extends it)
- **Branch:** `feat-tmp-scratch-reclamation` — draft PR #8738
- **Lane:** `cross-domain`
- **Brand-survival threshold:** `single-user incident`

## What We're Building

Finish the stalled ownership-keyed scratch-reclamation arc (#7004) and extend it to
`/var/tmp`, plus a one-time operator-invoked backlog purge and a git-aware
orphaned-worktree sweep.

**Measured on the operator host (2026-09-24):**

- `/tmp` (16G tmpfs): 5.5 GB used, ~14k stale top-level entries (`kbcov` 2115,
  `pirgate` 2040, `inngest` 2033, `tmp.*` 1984, `plan` 1880, `gdpr` 1872, `rung` 1384,
  `deploygap` 1233, `soleur-inc` 202, `playwright` 60, …)
- `/var/tmp` (disk): **27 GB, ~45k+ entries accumulated in ~7 days (~4 GB/day)**.
  `tmp.*` 16,438 (**1,484 contain `.git` — orphaned worktrees; only 3 registered**),
  `rung2-archive.*` 12,819 (writer: `tests/scripts/lib/git-data-birth-readiness-gate.sh`),
  `gdboot*` 7,837 (`scripts/lib/git-data-boot-signal-poll.sh`), `inngest-ci`/`inngest-arm-*`
  ~6k, `pr`/`shared`/`infra` ~8.5k, `gdpr`/`kb`/`deploygap`/`kbcov`/`pirgate`/`plan` ~8k.
- `TMPDIR=/var/tmp` is the repo's own documented bulk-scratch convention
  (`plugins/soleur/skills/preflight/SKILL.md`;
  `.claude/hooks/memory-backstop-mutation-battery.sh` exports it).
- systemd-tmpfiles ages `/var/tmp` at 30d; `/` has 46G free → pressure in ~11 days at
  the current production rate. `/tmp` is RAM-backed — growth there wedges sessions
  (measured 2026-09-22: `/tmp` at 13G made every Bash call exit 1).
- **Trigger gap:** `tmpfs-guard.sh`'s 5-min user cron is *not installed* on this host
  (`crontab` binary absent; `~/.local/state/soleur/` absent). The only cleanup that
  actually ran today is the session-start `cleanup-merged` sweep — it reaped 22 stale
  sandbox dirs.

## Why This Approach (A — purge + machinery)

Chosen over B (machinery-only) and C (producers-only):

- **#7004's design is certified.** Ownership-keyed reclamation
  (`soleur-run.<pid>.XXXXXXXX` roots + `/proc` liveness + quarantine) is still the
  right mechanism; the plan already anticipated multi-base reclamation
  (`TMPFS_GUARD_SCRATCH_BASES`, base-aware `_mark_inuse` are PR-1 tasks).
- **The plan's "backlog self-drains" premise breaks on /var/tmp.** It held for the
  tmpfs (10d aging, wiped on reboot); it fails for disk-backed `/var/tmp` at
  ~4 GB/day against 46G free. Backlog clearing moves from *deferred* to
  *prerequisite* — but as an operator-invoked, quarantine-mediated purge, never a
  heuristic reaper.
- **Heuristic reclamation over shared namespaces stays rejected** (the #7004 dry
  run marked ~1,500 authored files for deletion). All destructive paths are
  `mv`-to-quarantine — recoverable mistakes, per the July-27 learning corpus.
- **The orphaned-worktree class is new scope** the plan never covered; it needs
  git-aware handling, not `find -delete`.

## Key Decisions

| # | Decision | Rationale |
|---|----------|-----------|
| 1 | Ship `TMPFS_GUARD_SCRATCH_BASES="/tmp /var/tmp"` in PR 1 — do not defer /var/tmp | /var/tmp is the dominant leak; both runners already emit there (plan task 6.3) |
| 2 | One-time operator-invoked purge FIRST, before machinery | ~11-day runway; purge is the critical path (CPO). Dry-run report → `mv`-to-quarantine only |
| 3 | Purge reaps **certain-attribution classes only**: empty dirs (`rmdir`), `.git`-bearing dirs (via worktree sweep), and prefixes traceable to in-repo writers (`rung2-archive.*`, `gdboot*`, `mutbat.*`, `pirgate-*`, `kbcov*`, `gdpr-gate-incidents-*`, `pmr-*`, `inngest-ci*`, `inngest-arm-*`, `deploygap*`, `soleur-inc-*`, `legal-*`, `luks-*`, `harness-*`, `rr-*`, `pir-*`, `cron-*`, `sbx-*`, `pmr-env-*`) past an age floor | Bare `tmp.*` non-git stays for tmpfiles — unattributable means unverifiable (plan-*/shared-*/vbcr* have no in-repo writer) |
| 4 | Orphaned worktrees: **quarantine + report**, auto-drain only after clean-tree + merged + no-unpushed-commits verification, materially longer TTL than scratch roots | CLO requirement — uncommitted work stakes; registered ones need `git worktree remove`, unregistered need prune semantics; never `find -delete` |
| 5 | `.soleur-owned` marker file (carries `pid=` + `schema=`) for producers that can't adopt the allocator; bare prefix lists rejected | Self-declared ownership — reaper needs no name list; marker without pid is a permission slip (CTO) |
| 6 | Reaper home: **session-start sweep as primary** (plugin-shipped, demonstrably runs) + tmpfs-guard cron where installed + optional systemd user timer | The 5-min cron does not exist on this host — a reaper no trigger runs is a no-op |
| 7 | `skill-security-scan-*` (#6760) is deliberate durable retention — never a candidate | Its meta output is read by callers after exit |
| 8 | Producer self-reap-at-startup for named leakers (`infra-suites.*` precedent in `run-registered-suites.sh`) | Cheapest prevention for sourced-library producers that can't own traps (ADR-129) |
| 9 | Merge-blockers before enabling `/var/tmp`: base-aware `_INUSE_TOP` (2X.5c), fail-closed `__built__` sentinel (2X.6), `TMPFS_GUARD_SCRATCH_BASES` seam pinning (AC14), lockfile pin to TMPDIR-independent path (2.11) | Each is a measured fail-open-toward-delete on a second base (CLO merge-gate) |
| 10 | Zero false-positive deletions is the non-negotiable success bar | One false deletion of authored work is a trust-destroying incident (CPO/CLO) |

## User-Brand Impact

- **Artifact:** the session temp/scratch reclamation machinery — allocator
  (`soleur_scratch_session_begin`), Reaper 3 (`reap_orphan_scratch_roots`), the purge
  tool, the `.soleur-owned` marker convention, and the worktree sweep.
- **Vector:** a reaping false-positive deletes operator-authored work or a live
  sibling session's scratch directory — silent, terminal data loss on the
  dogfooding host (`find -delete`/`rm -rf` on shared dirs has no trash).
- **Threshold:** `single-user incident`.

## Open Questions

1. **Purge invocation:** operator-invoked `soleur-tmp-purge` (report + `--apply`)
   vs. auto-run at session-start. Default: report-only summary at session-start;
   the operator runs the apply step explicitly (bootstrap-script pattern,
   `hr-multi-step-post-merge-bootstrap-script`).
2. **systemd user timer for tmpfs-guard** on cron-less hosts — in scope as a small
   installer, or deferred? Default: include a `systemd --user` timer unit +
   install instructions in the spec; it is the designed trigger for hosts that
   can run it.
3. **Unattributable `tmp.*` non-git dirs** (16.4k in /var/tmp): leave to 30d
   tmpfiles aging (default) or a longer-horizon quarantine class? Default: leave —
   no ownership signal to verify against.
4. **`.ts` fixture writers** (`kb-coverage`, `ship-incident-pir-gate`,
   `web-platform-runtime-plugin-trigger`, `gdpr-gate` tests — zero cleanup):
   marker + self-reap precedent, or EXIT cleanup in-test? Default: both where
   cheap — marker the dir so ANY future reaper can attribute it.

## Domain Assessments

**Assessed:** Marketing, Engineering, Operations, Product, Legal, Sales, Finance, Support

### Engineering (CTO)

**Summary:** Plan certified with priority inversion — ship `SCRATCH_BASES` on both
dirs in PR 1. Orphaned worktrees get a git-aware sweep in `worktree-manager.sh`
(registered → `git worktree remove` only if clean/merged/no-unpushed + age floor;
unregistered → quarantine, not delete); prevention lands via TMPDIR adoption at
entry points. Marker file wins over prefix lists *only if it carries owner
identity*. Reaper home = both `tmpfs-guard.sh` and session-start, partitioned by
class. Top risk: reaping a live sibling session's scratch — every destructive
path must be quarantine-mediated.

### Legal (CLO)

**Summary:** PROCEED, conditional. `/var/tmp` is *higher* risk than `/tmp`
(semi-durable by convention). Auto-reap schema-named roots only; never age/size/
signature inference on `/var/tmp`. Orphaned worktrees = quarantine-and-report,
auto-drain only after clean `git status` + no unpushed commits, longer TTL.
Secrets-at-rest (`env.txt`, `a*.env` observed) argues FOR cleanup and for the
no-content-read invariant. `soleur:gdpr-gate` runs at plan Phase 2.7. Merge
blockers: 2X.5c base-aware `_INUSE_TOP`, 2X.2 sentinel, AC14 seam pinning before
`/var/tmp` goes live; ADR must extend the never-delete-user-data case to
`/var/tmp`; PR body must state the 27 GB backlog is out of auto-reap scope.

### Product (CPO)

**Summary:** Finishing the stalled plan is the right product call — the design
cost is already paid. The plan's deferred-backlog decision does NOT survive the
/var/tmp extension: ship prevention while the host dies of the existing 27 GB is
inverted. Sequence: one-time purge now → PR 1 machinery → adoption + worktree
class. Naming top leakers is product-valuable — it converts reclamation into
prevention.

## Capability Gaps

- **No installer for `tmpfs-guard.sh` on systemd-only hosts.** Evidence:
  `crontab` absent on the operator host (Arch/Omarchy); `~/.local/state/soleur/`
  absent (guard never ran); `git grep -ln 'crontab|systemd.*timer' scripts/` →
  comments only, no installer.
- **No reaper covers `/var/tmp`.** Evidence: `tmpfs-guard.sh` `TMP_ROOT` is
  single-root (`:82`); `cleanup_stale_sandbox_tmp` sweeps `/tmp` only
  (`worktree-manager.sh:3442`); `session-state.sh` sweep has no dir parameter.
- **No mechanism reaps orphaned worktrees outside `.worktrees/`.** Evidence:
  `cleanup_orphan_worktree_dirs` scopes to the registry-adjacent `.worktrees/`
  dir; `/var/tmp` worktrees are unregistered there by construction.
- **Several `.ts` fixture producers have no cleanup path.** Evidence:
  `plugins/soleur/test/kb-coverage.test.ts`, `ship-incident-pir-gate.test.ts`,
  `web-platform-runtime-plugin-trigger.test.ts`, `gdpr-gate.test.ts` create
  `mktemp`-class dirs with no `rmSync` — matching observed leak classes.
- **The plan's stale references need re-baselining.** Evidence: plan/tasks cite
  `AGENTS.rest.md` (now `AGENTS.rules.md`, ADR-151) and
  `.claude/hooks/lib/session-state.sh` (moved to
  `plugins/soleur/scripts/lib/session-state.sh`, #7409).

## Session Errors

None. All premise claims verified against live state before leader spawn; the
issue states cited (#7004 open, #6760/#8659/#7210/#8496 open, #7019 merged) were
verified via `gh` by the orchestrator.
