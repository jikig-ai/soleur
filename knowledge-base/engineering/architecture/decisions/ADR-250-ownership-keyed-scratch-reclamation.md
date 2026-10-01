# ADR-250: Ownership-keyed scratch reclamation across /tmp and /var/tmp

- Status: Accepted
- Date: 2026-09-24
- Issue: #7004; PR: #8738
- Amends: ADR-133 (tmpfs managed/reaped), ADR-124 (liveness-gated reclaim)
- Supersedes nothing; composes with ADR-195 (report-not-reap for
  unattributable orphans) and ADR-129 (trap composition).

## Context

Measured on the operator host (2026-09-24): `/tmp` held ~5.5 GB and `/var/tmp`
~27 GB across **67,222 top-level entries** — including ~1,484 orphaned git
worktrees and ~4 GB/day of new leakage. `TMPDIR=/var/tmp` is this repo's own
documented bulk-scratch convention, so `/var/tmp` is the larger leak.

Two prior decisions bound the solution space:

- A dry run of a heuristic reaper over shared `/tmp` marked ~1,500 authored
  files for deletion — **heuristic reclamation over a shared base is measured
  and rejected** (#7004, ADR-133/ADR-195 lineage).
- `tmpfs-guard.sh` was built for a user cron, and this host has **no crontab
  installed** — the guard never ran. A reaper whose trigger is not installed
  is a no-op
  (`knowledge-base/project/learnings/2026-09-24-a-reaper-whose-trigger-isnt-installed-is-a-no-op.md`).

## Decision

Adopt **ownership-keyed reclamation** — producers declare an owner; reapers
reclaim only entries whose declared owner is provably dead.

### Allocator

`scripts/lib/scratch-root.sh` gains `soleur_scratch_session_begin`:
`mktemp -d <base>/soleur-run.<pid>.XXXXXXXX`, a `.soleur-owned` marker
(`pid=` top-level harness pid, `schema=1`, `ns=pid:[<inode>]`), a held
directory fd (`declare -g` — a function-local fd dies with the function), and
`export TMPDIR` at the root so descendant `mktemp` calls land inside it. It
installs **no** EXIT trap by default (ADR-129 — a later trap would clobber
it); callers splice `_soleur_scratch_cleanup` into their existing trap list.
Nested calls no-op — the parent root governs. An explicit `TMPDIR=/var/tmp`
selects `/var/tmp` as the base.

### Shared classifier

`plugins/soleur/scripts/lib/tmp-classify.sh` is the single definition of
"safe to move", consumed by the operator purge, Reaper 3, and the
session-start sweep. The attribution ladder: `.git`-file worktree resolution
FIRST (verified through the OWNING repo's registry — the strongest
attribution, outranking every name heuristic INCLUDING the prefix allowlist)
→ protected names → file allowlist → `.soleur-owned` marker (a marker that
is present but unverifiable — foreign/missing `ns=` — VETOES the schema rung
rather than falling through) → `soleur-run.*` schema → prefix+signature
allowlist (purge only; precedes standalone-clone so signature-verified
fixture classes like `pirgate-*` are reachable) → standalone-clone
(report-only) → empty dir → unattributable (retained, reported).

### Reaper 3

`reap_orphan_scratch_roots` in `tmpfs-guard.sh` iterates
`TMPFS_GUARD_SCRATCH_BASES` (default `/tmp /var/tmp`). A candidate needs a
dead owner pid, no live fd/cwd/environ/mmap/unix-socket handle (single
amortized `/proc` pass), a stale tree, and a matching pid-namespace. Disposal:
**direct delete only for schema-named (`soleur-run.<pid>.*`) roots on
tmpfs/ramfs bases** — the name is assigned at mktemp creation, creation-certain
attribution, and a same-base `mv` frees no RAM (operator decision 2026-09-24).
**Marker-only dirs quarantine on every base** (a `.soleur-owned` file is a
self-declared statement, weaker evidence), and **quarantine on disk bases**
(`<base>/soleur-quarantine.<uid>/`, TTL drain: scratch 7d, worktrees 30d).
Reaper 2 remains `/tmp`-only and protects `soleur-run.*`/`soleur-quarantine.*`
plus marker-bearing dirs.

### Separate base-list seams

`TMPFS_GUARD_SCRATCH_BASES`, `SOLEUR_SWEEP_BASES`, and `SOLEUR_PURGE_BASES`
are deliberately independent seams (all defaulting to `/tmp /var/tmp`), not a
single shared variable: each consumer's base list is its blast-radius scope,
and an operator may legitimately want the periodic guard scanning a narrower
or wider set than a manual purge targets. The cost is drift — three lists
that can diverge silently. That is accepted because the default is uniform
and each list is independently fail-closed; converging them into one
`SOLEUR_SCRATCH_BASES` is deferred until a second real divergence need
appears.

### Trigger

Session start is the primary trigger — `sweep_orphan_scratch_dirs` at the top
of `worktree-manager.sh cleanup_merged_worktrees`, before the repo lock and
the fetch gate, `flock -n` on the shared
`~/.local/state/soleur/tmp-guard.lock`, bounded to a 50-entry/10s worktree
batch with `SWEEP-DEFER`. An optional systemd user timer
(`scripts/tmpfs-guard.{service,timer}` + runbook) exists for hosts that want
the 5-minute cadence; installation is deliberately manual.

### Backlog

`scripts/soleur-tmp-purge.sh` is the operator-invoked one-shot for the
existing backlog: dry-run report → apply quarantines certain-attribution
classes → `--restore`/`--drain` for recovery, all ledger-backed at
`~/.local/state/soleur/tmp-purge-ledger.log`.

## Consequences

- Registered-but-unverifiable worktrees are **retained, never moved** —
  moving a registered tree corrupts `.git/worktrees` registry state; they
  escalate to an operator-decision list via `retain-since` stamps.
- Producers that cannot own traps (sourced libs) write `.soleur-owned`
  markers at their emit sites.
- `find -delete`/`rm -rf` remain forbidden on shared-base candidates;
  terminal deletion is permitted only beneath the quarantine root, plus the
  explicit carve-outs `git worktree remove`, `rmdir`, and owner-EXIT
  cleanup of schema roots.
- Session roots on tmpfs are deleted directly at owner exit — the only
  prompt-RAM-reclaim path.
- **Residual windows, accepted and named.** (a) The classify→act race is
  narrowed but not closed by the action-time liveness re-walk; on tmpfs,
  schema-named roots take the *only non-recoverable* disposal (direct
  delete) — accepted because a same-tmpfs quarantine `mv` frees no RAM and
  the schema name is creation-certain attribution, while marker dirs and
  disk entries get the recoverable path. (b) The liveness conjunct is not
  exhaustive — inotify/fanotify watches, transient fd holders, and
  `/proc/<pid>/root` are not in the map; the 24h age floor (well past any
  legitimate suite runtime) is the backstop, and a producer that leaves its
  tree fully stale between writes can read as dead-by-age — conservative
  attribution means those get *retained*, not deleted, whenever any conjunct
  is uncertain. (c) The marker carries `pid=`+`ns=` but no start-time/
  boot-id — a dead→reused→dead-again window is not detectable from pid
  alone; same-uid + handle checks bound it. (d) Pre-marker legacy entries
  drain only via the frozen prefix+signature allowlist — the ~19k
  unattributable residue is *intended* to persist (it is reported, not
  deleted), and the dry-run report's per-class counts are the observability
  surface for that tail.

## Amendment 1 (2026-10-01)

Context: the 2026-10-01 dev-machine disk-leak investigation found that the
reclamation half of this ADR works, but the producer half is incomplete —
direct-run test runners and agent-driven work copies still create scratch that
carries no owner declaration, so there is nothing for the reapers to key on.
The classifier, Reaper 3, the session sweep and the quarantine/drain contract
are unchanged; this amendment widens producer coverage and records the
decisions that were weighed and refused.

### A1.1 Producer coverage

Every runner chokepoint that a direct (non-`test-all.sh`) run measured as
leaking binds a per-process `soleur-run.<pid>.*` root when
`SOLEUR_SCRATCH_SESSION_ROOT` is unset: the bun test preload first, and the
vitest `globalSetup`, pytest `conftest.py` and unittest `_git_fixture_env.py`
chokepoints only where a direct run is measured to leak. A chokepoint adopts a
parent's root ONLY after validating it (exists, same uid, valid marker, owner
pid alive in the same `ns=`); otherwise it creates a fresh root. It removes
only a root it created itself, never an adopted one. Marker format is
unchanged (`pid=`, `schema=1`, `ns=`), so the classifier needs no change.

### A1.2 Not adopted

An operator-attested classification rung (`--attest GLOB`) was drafted as
A1.2 and is **not adopted in this amendment**; the number is kept vacant so
the draft's references stay stable. See Alternatives Considered.

### A1.3 Agent sandbox allocator

`scripts/soleur-sandbox.sh new|rm` allocates owned work copies for review and
work seats on a forced disk-backed base, named `soleur-sbx.<label>.*`, with a
`.soleur-owned` marker. The sandbox has no `.git` entry, so it never enters
the worktree registry. `rm` is added to the terminal-delete carve-out list
(alongside `git worktree remove`, `rmdir` and owner-EXIT cleanup of schema
roots), **restricted to the `soleur-sbx.*` name pattern AND a valid marker**
AND a realpath under a scratch base; any one failing refuses. This is the
only new direct-delete idiom, and it applies to a directory the allocator
itself created.

### A1.4 Residual windows restated

- SIGKILL between the directory create and the marker write leaves a
  marker-less dir. The marker write is atomic (tmp + rename) and the window
  is microseconds; such a dir is unattributable and retained, not deleted.
- A marker-only dir is quarantined (recoverable), never deleted directly.
- A pid reused after the owner died makes the owned root look live
  (immortal), which is the safe direction and is accepted.
- A quarantine on the same disk frees no bytes until drain. Immediate
  recovery is the existing TTL seam:
  `SOLEUR_PURGE_QUAR_SCRATCH_TTL_MIN=0 bash scripts/soleur-tmp-purge.sh --drain`
  (terminal delete stays scoped beneath the quarantine root).

### A1.5 Read-only attribution report

`scripts/soleur-tmp-purge.sh --report` adds a strictly read-only view (no lock,
no ledger row, no stamp): per-class count and size, top prefix families by
size with the unattributable bucket split out, and per family a
`.git`-bearing versus non-`.git` size split. It consumes the same shared
classifier and changes no classification. It exists so the unattributable
residue named in Consequences (d) is measured per family rather than guessed.

### Consequences of the amendment

- The unattributable pre-marker residue **still persists** until the operator
  reclaims it. The reclamation path is the one-off procedure in
  `knowledge-base/engineering/operations/runbooks/tmpfs-guard-install.md`
  (`git worktree remove` for registered worktrees; named non-`.git` residue
  moved into the existing quarantine root after a handle check, dry-run
  first). No automated trigger (Reaper 3, the session sweep, the timer) ever
  reaches that residue, and the shared classifier gains no rung that could.
- New producers get owners (A1.1, A1.3), so the residue stops growing from
  those sources; it does not shrink on its own.
- Reaper 3 and the session sweep are unchanged. Nothing under
  `soleur-quarantine.<uid>/` is ever a scan or reap candidate (the root is a
  protected name and the scans exclude it by name).

## Alternatives Considered

| Alternative | Rejected because |
|---|---|
| Extend the frozen prefix+signature allowlist to cover the leftover families (`vac*`, `td-*`, `perf-*`, `mut*`, `sdkprobe.*`) | The allowlist is only safe where a content signature proves authorship; agent-named directories have none, so a new row would be a name-only heuristic over a shared base. The table is FROZEN by design (new producers get markers, not rows). |
| Heuristic size/age reaper over the shared bases | Measured and rejected in this ADR's Context: a heuristic dry run over shared `/tmp` marked ~1,500 authored files for deletion. Age and size are not ownership. |
| Hardlink or worktree-based agent sandboxes instead of an owned copy | Rejected per #8800: a hardlinked or symlinked tree writes tool caches and installs through to the live checkout, and a worktree enters the registry that the reapers must not move. An owned copy has neither failure. |
| Operator-attested glob rung (`--attest GLOB`) in the classifier and purge | Rejected for this change. It is the only mechanism that could quarantine content with no machine-verifiable owner, it needs its own safety conjunction (disk-only bases, no `.git`, no live handle, age, glob guard), and the backlog it would serve is already tracked (#8786). The task needs a size-reporting view, which A1.5 provides. A documented one-off procedure in the runbook covers the operator's immediate need without adding an automation-reachable path. Revisit only if the one-off procedure proves repeatedly necessary. |
