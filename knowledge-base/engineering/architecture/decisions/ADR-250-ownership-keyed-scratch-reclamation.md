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

**Coverage boundary, stated plainly.** Rooted today: bun test runs (the
preload, from the repo-root and `plugins/soleur` working directories), the
vitest main process, pytest under `tests/`, and unittest modules that import
`_git_fixture_env`. NOT rooted: a shell `.test.sh` run directly (only the
`soleur-inc-*` incident sandbox it creates is marked, and ADR-129 forbids the
EXIT trap a sourced lib would need to root the rest), bun runs from other
working directories, Playwright, and plain node tooling. This amendment does
not claim full producer coverage; that residue is tracked by #8659 (trap
ownership in `.test.sh` files) and #9341 (the census-driven remainder of the
shell leak sites). A green lint rule (d) does not mean no leak.

### A1.2 Not adopted

Number reserved, not used. The operator-attested classification rung
(`--attest GLOB`) that was drafted here is recorded as a rejected row in
Alternatives Considered.

### A1.3 Agent sandbox allocator

`scripts/soleur-sandbox.sh new|rm` allocates owned work copies for review and
work seats on a forced disk-backed base, named `soleur-sbx.<label>.*`, with a
`.soleur-owned` marker. The sandbox has no `.git` entry, so it never enters
the worktree registry. `rm` is added to the terminal-delete carve-out list
(alongside `git worktree remove`, `rmdir` and owner-EXIT cleanup of schema
roots), **restricted to the `soleur-sbx.*` name pattern AND a valid marker**
AND a realpath under a scratch base; any one failing refuses. It is meant for
a directory the allocator itself created; the marker check is a same-user
declaration, not proof of authorship.

- **Second direct-delete carve-out: durable-log GC (#9117).** `_gc_durable_logs`
  in `scripts/test-all.sh` also runs `rm -rf` (no ledger, no quarantine) on
  `<label>-<pid>-<epoch>` directories older than 14 days under
  `/var/tmp/soleur-test-all-logs/`. It is keyed on a DEDICATED namespace that
  only the test runner writes, not on an ownership marker: the namespace must
  be literally named `soleur-test-all-logs`, must not be a symlink, entries
  must match the shape, be plain same-uid directories and not symlinks, and a
  `SOLEUR_TEST_ALL_LOG_DIR` override outside that name is never reaped. It is
  acceptable because everything in the namespace is a regenerable diagnostic
  log of a failed suite, never authored work, and the delete cannot be aimed
  at a shared base. This is an exception to "age is not ownership": the
  namespace itself is the ownership.
- **The owner pid is the agent session.** The marker's `pid=` is the first
  non-shell ancestor, which is the long-lived agent process, not the seat. A
  sandbox a seat forgets or dies without removing is therefore SESSION-scoped:
  no reaper considers it until the whole session ends, then the 24h age floor
  and the 7-day quarantine apply. The lead removes it after any seat returns
  or fails.
- **Bases.** The allocator tries `/var/tmp`, then `$XDG_CACHE_HOME` or
  `$HOME/.cache`. A `$HOME/.cache` base is outside every reaper's default bases
  (`/tmp /var/tmp`); a sandbox there is reclaimed only by `soleur_sandbox_rm`,
  and allocation prints a warning saying so.

### A1.4 Residual windows restated

- SIGKILL windows, per prefix. `soleur-run.<pid>.*` (the roots the runner
  chokepoints create): there is no window of consequence, because a
  marker-less one still verifies as `kind=schema` from its name and Reaper 3
  reaches it once the owner pid is dead and the age floor passes.
  `soleur-sbx.*` and `soleur-inc-*`: between `mktemp` and the marker write (a
  `chmod` and an owner-pid chain walk of up to 32 `/proc` reads, so
  milliseconds, not microseconds) a SIGKILL leaves a marker-less directory
  with no schema name; it is unattributable, retained and reported, never
  deleted. Also `soleur_sandbox_new` killed mid-copy: the path was never
  printed, so the caller cannot `rm` it, and it stays owned by the agent
  session until the session ends.
- A marker-only dir is quarantined (recoverable until drain), never deleted
  directly.
- A pid reused after the owner died makes the owned root look live
  (immortal), which is the safe direction and is accepted.
- A quarantine on the same disk frees no bytes until drain. Immediate
  recovery is the existing TTL seam:
  `SOLEUR_PURGE_QUAR_SCRATCH_TTL_MIN=0 bash scripts/soleur-tmp-purge.sh --drain`
  (terminal delete stays scoped beneath the quarantine root). TTL=0 drains
  EVERY `scratch` and `prefix` quarantine entry, including ones moved seconds
  ago, and ends restorability for all of them; preview first with
  `SOLEUR_PURGE_DRY_RUN=1 SOLEUR_PURGE_QUAR_SCRATCH_TTL_MIN=0 bash scripts/soleur-tmp-purge.sh --drain`.

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
  *selects* that residue, and the shared classifier gains no rung that could.
  But the operator-run move feeds the existing 7-day drain, which the guard
  timer runs unattended: the operator's glob is the only evidence behind that
  automated terminal delete. The runbook procedures are therefore written to
  be at least as strict as the classifier (any-depth nested-git refusal,
  protected-name predicate sourced from the library, age floor, absolute
  `BASE`), and `SOLEUR_PURGE_QUAR_SCRATCH_TTL_MIN=0` ends recoverability for
  every quarantined scratch entry at once.
- New producers get owners (A1.1, A1.3), so the residue stops growing from
  those sources; it does not shrink on its own.
- Reaper 3 and the session sweep are unchanged. Nothing under
  `soleur-quarantine.<uid>/` is ever a scan or reap candidate (the root is a
  protected name and the scans exclude it by name).

## Amendment 2 (2026-10-07, #9677)

Measured on the operator host (2026-10-07), the session-start sweep did not reclaim marked dirs for
three separate reasons, none of which the original decision named.

### A2.1 The timebox excludes the one-time liveness map

`sweep_orphan_scratch_dirs` bounds every arm by `SOLEUR_SWEEP_TIMEBOX_S` (10 s). Its liveness map is
built lazily at the first declared-owner candidate and took 12.7 s on a 739-process host
(`tc_build_inuse_map /tmp /var/tmp`), so the clock expired during the build and every later candidate
was `deferred`, on every session start. The timebox now restarts when the map is built and bounds the
per-candidate work that remains. The map cost is reported as `map_s` in the `SOLEUR_TMP_SWEEP` line.
A host with no declared-owner candidate still pays nothing for the map, and neither does one whose only
candidates have a live owner: those are retained before the map is read, so the build is skipped for them.

The timebox is checked **between** candidates, so it is not a latency ceiling: the default path is
bounded by the map build, plus one timebox, plus the work of one candidate. Two review measurements
shaped this. A tmpfs schema-named root is deleted directly, behind an action-time liveness check; the
full per-process walk used for that check cost 138 s for one candidate on a loaded 739-process host
(inside the flock), against about 5 s for one map build. The session sweep therefore checks the map
`tc_reap_decide` has just refreshed (at most 120 s old; a truncated or unbuilt map still falls back to
the walk, so the check stays fail-closed); the unattended guard keeps the full walk, where nobody is
waiting.

### A2.2 Opt-in session-start drain

A marker-only dir on a disk base is quarantined, and only a TTL drain deletes it. The drain ran only
from the optional systemd timer, which was not installed on the measured host (no crontab, no
`tmpfs-guard.timer`), so 142 MB sat in quarantine with no trigger. The Trigger section's "installation
is deliberately manual" stays true as the default; this amendment adds an explicit alternative that
needs no install: with `SOLEUR_QUARANTINE_DRAIN=1` the sweep drains quarantine entries past their class
TTL (scratch 7 days, worktrees 30 days) before it releases the `tmp-guard.lock`, so it is serialised
against the guard and the purge. Boundaries:

- **Opt-in.** The session sweep does not drain by default. The script runs on machines Soleur does not
  own and the drain is a terminal delete, so the consent model is the user's choice (CPO and CLO
  assessments, plan review of #9677). Only the exact value `1` enables it. Where the timer is installed
  it drains every five minutes and does not need the variable.
- **Floors.** Each TTL is floored (`SOLEUR_SWEEP_QUAR_TTL_FLOOR_MIN`, default 1440 min), so an exported
  0 cannot make a session start empty the quarantine it just filled. Every numeric variable the sweep
  reads is first normalised to a decimal integer (plain digits only, base 10), because `08` is an octal
  arithmetic error that would skip the floor comparison and `5s` is an arithmetic error that would
  abort the sweep; an invalid value falls back to its default, and a max-entries value of 0 means the
  default 200, never unbounded. The sweep does not read the `SOLEUR_PURGE_QUAR_*` recovery seams.
- **Bounds.** A 5 s drain timebox (`SOLEUR_SWEEP_DRAIN_TIMEBOX_S`) and a 200-entry cap per base
  (`SOLEUR_SWEEP_DRAIN_MAX_ENTRIES`), enforced between top-level entries by an optional deadline and
  cap on `tc_drain_quarantine`. They are not a wall-clock ceiling: the mount probe, the `du -sk` size
  read and `find -delete` of one entry cannot be interrupted, so one very large entry can overrun the
  bound. Entries are pre-filtered with `find -cmin` so unexpired ones cost one `find`, not a fork each
  (measured 12 ms per entry otherwise, which let 400 fresh entries use the whole 5 s and reclaim
  nothing). A delete cut short is not retried promptly: removing an entry's children advances its own
  ctime, which restarts its TTL, so no data is lost and the error direction is retention. Restore after
  a drain reports "already gone".
- **Accepted residual: no action-time liveness re-walk in the drain.** The drain checks age and mounts
  but not open handles. An entry reaches it only after a dwell of at least the floored TTL (24 h) in a
  directory nothing names by path, having been dead-owner and stale when it was moved, and the same
  property holds for the timer's existing unattended drain. A per-entry process walk was measured at
  138 s on a loaded host and would make the bound meaningless, so it was not added. A user who `cd`s
  into a quarantined directory to recover files keeps it alive only through its top-level ctime, which
  deeper activity does not advance; recovery is `--restore`, not working in place.
- **No drain on the early returns** (`lock-contended`, `flock-missing`, `bases-empty`).
- The sweep line gains `drained`, `drained_bytes` (`du -sk` before the delete) and `map_s`.

### A2.3 Producer fix: the test, not the library

44 of 71 marked dirs on the measured host were `gdboot.*`, created by
`tests/scripts/test-git-data-boot-signal-poll.sh`. The sourced library
`scripts/lib/git-data-boot-signal-poll.sh` calls `mktemp -t gdboot.*` and cannot own a trap (ADR-129).
The suite now points `TMPDIR` at the sandbox it already removes on exit, so the library's scratch dies
with the suite. The library is unchanged, and no marker-schema change is made (worktree-stamped markers
are tracked in #9693).

### A2.4 Effective-space report and the Docker carve-out

`cleanup-merged` prints `SOLEUR_CLEANUP_SPACE` with the bytes it logically drained next to the measured
`df -Pk` delta, and names btrfs snapper pinning when `findmnt` reports btrfs and the snapper `root`
config exists (a read-only file check, never the `snapper` binary and never a snapshot). A snapshot pins
every deleted block, so the two numbers can differ by design; the operator-host measurement was 17.6 GiB
returned only after the snapshots were deleted.

An opt-in `SOLEUR_DOCKER_PRUNE=1` (dry run) or `apply` prunes old Docker build cache and dangling images
(`--filter until=24h`) once per `cleanup-merged` run, after the cleanup lock is released, and only when
the run removed a worktree. It acts on the ambient daemon, so a `tcp://` or `ssh://` `DOCKER_HOST` is
refused (`skipped reason=remote-daemon`); each Docker call is bounded by `SOLEUR_DOCKER_TIMEOUT_S` (60 s
plus a 5 s kill grace, probe 5 s), so an apply run can take about 140 s in the worst case. An age-filtered prune over a shared daemon is the heuristic this ADR rejects
for scratch, so it is admitted only as an explicit exception in the style of A1.3's durable-log GC:
regenerable cache, opt-in, dry-run first, never `-a`, never a volume or container. Label-scoped pruning
was considered and cut: no local `docker build` call site stamps a worktree label.

### Consequences of Amendment 2

- Amendment 1 says the session sweep is unchanged and that the timer is the only automated terminal
  delete. With `SOLEUR_QUARANTINE_DRAIN=1` the session sweep is a second one; without it both statements
  still hold for the drain.
- The default sweep processes more candidates per session on every machine (the A2.1 rebase) and so
  moves more marker-only dirs into quarantine (a reversible `mv`); it needs no opt-in because it only
  lets the existing, already-shipped conjuncts run. It also adds up to one timebox of default-path
  latency.
- Phase 7 of the #9677 plan installs the existing timer on the operator host; that is host
  configuration, not plugin behaviour.

## Amendment 3 (2026-10-10)

The allocator CLI gained a third verb, `run-isolated <sandbox-path> -- <cmd>` (A1.3 names `new|rm`). It deletes nothing:
it refuses (rc 2) unless the path is an allocated sandbox (the conjuncts of `soleur_sandbox_rm`, plus a refusal of any
symlink component; see `soleur_run_isolated` in `scripts/soleur-sandbox.sh`), then runs the command as PID 1 of a PID namespace through
`plugins/soleur/scripts/run-in-pid-namespace.sh`. Why a verb and not only prose: the sandbox copy bounds file removal but
not signals, and a mutant of a helper that walks `$PPID` and signals the outermost matching ancestor reached the user's
desktop session (see the learning dated 2026-10-09 under the learnings test-failures category). The terminal-delete
carve-out list is unchanged.

Decisions recorded with it (the plan and evidence of the change that made them are in its spec directory): the wrapper
fails closed with no fallback (a refusal prints `RUN_IN_PID_NAMESPACE_REFUSED reason=<...>` first on stderr and exits 125,
the command never starts); a PID namespace was chosen over a process-group or `setsid` bound because it removes the
ancestors rather than trusting a predicate; an inventory scan with a content-keyed baseline lists the sites before
anyone mutates one. Residual risk, accepted and named: the rule is prose in the seat briefs, so nothing forces a lead or
a seat to call the verb; the scan covers tracked suites and mutation-run scripts only, not helpers in libs, hooks or
non-shell code; the namespace does not bound writes, desktop IPC or the session manager; and the real-namespace test rows
run only where the runner allows user namespaces.

## Alternatives Considered

| Alternative | Rejected because |
|---|---|
| Extend the frozen prefix+signature allowlist to cover the leftover families (`vac*`, `td-*`, `perf-*`, `mut*`, `sdkprobe.*`) | The allowlist is only safe where a content signature proves authorship; agent-named directories have none, so a new row would be a name-only heuristic over a shared base. The table is FROZEN by design (new producers get markers, not rows). |
| Heuristic size/age reaper over the shared bases | Measured and rejected in this ADR's Context: a heuristic dry run over shared `/tmp` marked ~1,500 authored files for deletion. Age and size are not ownership. |
| Hardlink or worktree-based agent sandboxes instead of an owned copy | Rejected per #8800: a hardlinked or symlinked tree writes tool caches and installs through to the live checkout, and a worktree enters the registry that the reapers must not move. An owned copy has neither failure. |
| Operator-attested glob rung (`--attest GLOB`) in the classifier and purge (A1.2, number reserved) | Rejected for this change. It is the only mechanism that could quarantine content with no machine-verifiable owner, it needs its own safety conjunction (disk-only bases, no `.git`, no live handle, age, glob guard), and the backlog it would serve is already tracked (#8786). The task needs a size-reporting view, which A1.5 provides. A documented one-off procedure in the runbook covers the operator's immediate need; it is weaker than a classifier rung (it is operator-typed and single-sourced only through the sourced library predicates), so its strictness is a runbook obligation, not a code-enforced one. Revisit only if the one-off procedure proves repeatedly necessary. |
| Timer-only drain (status quo) | Not installed on the measured host; every installed machine would need the same manual step (A2.2) |
| Raise `SOLEUR_SWEEP_TIMEBOX_S` instead of rebasing the deadline | The map cost scales with process count, so a larger constant is a guess; restarting the clock after the map is structural (A2.1) |
| Detached background drain | The marker line leaves the session and the `flock` outlives it (A2.2) |
| Label-scoped Docker prune; global `docker image prune -a` on a disk threshold | No local build stamps a worktree label; `-a` on a shared daemon deletes images other sessions need (A2.4) |
