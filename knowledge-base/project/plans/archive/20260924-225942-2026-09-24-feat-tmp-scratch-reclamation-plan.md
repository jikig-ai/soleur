---
title: "feat: session temp/scratch reclamation — /tmp + /var/tmp (extends #7004)"
type: feat
date: 2026-09-24
slug: tmp-scratch-reclamation
branch: feat-tmp-scratch-reclamation
issue: 7004
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
spec: knowledge-base/project/specs/feat-tmp-scratch-reclamation/spec.md
brainstorm: knowledge-base/project/brainstorms/2026-09-24-tmp-scratch-reclamation-brainstorm.md
---

# Session temp/scratch reclamation — /tmp + /var/tmp

## Overview

Finish the stalled #7004 ownership-keyed reclamation arc, extended to `/var/tmp`,
plus a one-time operator-invoked quarantine purge of the existing ~32 GB backlog
and a git-aware orphaned-worktree sweep. Every destructive path moves to
quarantine — nothing is deleted outright; sibling-session scratch is never
reaped; unattributable dirs are left to systemd-tmpfiles.

## Problem Statement

Measured on the operator host 2026-09-24:

- `/tmp` (16G tmpfs): 5.5 GB, ~14k stale entries (`kbcov` 2115, `pirgate` 2040,
  `inngest` 2033, `tmp.*` 1984, `plan`/`gdpr`/`rung`/`deploygap` ~5.7k)
- `/var/tmp` (disk): **27 GB, ~67k top-level entries; +27k produced during the brainstorm session itself (rate far above the 7-day ~4 GB/day average)** — `tmp.*`
  16,438 of which **1,484 contain `.git` (orphaned worktrees; only 3 registered)**,
  `rung2-archive.*` 12,819, `gdboot*` 7,837, `inngest-ci`/`inngest-arm-*` ~6k,
  `pr`/`shared`/`infra` ~8.5k, `gdpr`/`kb`/`deploygap`/`kbcov`/`pirgate`/`plan` ~8k
- `TMPDIR=/var/tmp` is this repo's own documented bulk-scratch convention
  (`plugins/soleur/skills/preflight/SKILL.md`,
  `.claude/hooks/memory-backstop-mutation-battery.sh`)
- `/` has 46 GB free → ~11 days runway; systemd-tmpfiles ages `/var/tmp` at 30d —
  too slow to drain the backlog before pressure hits
- **Trigger gap:** `scripts/tmpfs-guard.sh`'s designed 5-min user cron is not
  installed on this host (no `crontab` binary; `~/.local/state/soleur/` absent).
  The only cleanup that ran is the session-start `cleanup-merged` sweep — it
  reaped 22 stale sandbox dirs at this session's start.

The #7004 plan's "legacy backlog self-drains" premise held for the tmpfs (10d
aging + reboot wipe) and fails on disk-backed `/var/tmp`. Its reclamation PRs
(1: allocator + Reaper 3; 2: producer adoption) were fully designed and never
started. Detection shipped — reclamation did not.

## Proposed Solution

Three tracks, ordered by urgency:

**Track 1 — Backlog purge (reclaims what already exists).**
`scripts/soleur-tmp-purge.sh` — operator-invoked, dry-run-by-default report of
attributable stale classes per base; `--apply` `mv`s qualifying entries to
`<base>/soleur-quarantine.<uid>/` (mode 0700). Only certain-attribution classes:
empty dirs (`rmdir`), `.git`-bearing dirs (via the Track-1b worktree classifier),
`.soleur-owned`-marked dirs past their liveness gates, and a committed allowlist
of prefixes traced to in-repo writers (`rung2-archive.*`, `gdboot*`, `mutbat.*`,
`pirgate-*`, `kbcov*`, `gdpr-gate-incidents-*`, `pmr-*`, `inngest-ci*`,
`inngest-arm-*`, `deploygap*`, `soleur-inc-*`, `legal-*`, `luks-*`, `harness-*`,
`rr-*`, `pir-*`, `cron-*`, `sbx-*`, `pmr-env-*`, `infra-suites.*`) past an age
floor. Bare `tmp.*` non-git, `plan-*`, `shared-*`, `vbcr*`,
`skill-security-scan-*`, `systemd-private-*`, `playwright`,
`node-compile-cache`, `claude-<uid>` — never candidates.

**Track 1b — Orphaned-worktree sweep (the new class the plan never covered).**
`_classify_scratch_git_dir` lives in `plugins/soleur/scripts/lib/tmp-classify.sh`
(the shipped lib surface — `scripts/lib/` doesn't exist on installed hosts;
sourcing `worktree-manager.sh` executes session-state init, so it can't host
the classifier either). Sourced by the sweep and the purge. Classification
anchors to the **owning repo** (advisor + spec-flow): read the candidate's
`.git` file → gitdir → resolve the main repo →
`git --git-dir=<main> worktree list --porcelain` and ancestor/upstream checks
against that repo's default ref *as last fetched* (no fetch side-effects).
Outcomes: registered + clean + merged + no-unpushed + past-age-floor **+ no
live process inside** (cwd/fd scan of `/proc` — `git worktree remove` doesn't
check residency, and orphaned registrations hold no leases; the fd/cwd scan
is the only protection — Kieran-4) → `git worktree remove`; **proven**
unregistered → quarantine + report; everything else → **retain + report** —
moving a *registered* worktree corrupts registry state. "Clean" means
no-modified AND no-untracked AND no-ignored files (porcelain omits ignored
paths — `.env.local` must not read clean, `worktree-manager.sh:2909`).
Registration unverifiable → retain + `retain-since` stamp → hard floor →
operator-decision list.

**Track 2 — Ownership-keyed machinery (#7004 PR 1, both bases).**

- `scripts/lib/scratch-root.sh`: add `soleur_scratch_session_begin` per #7004
  plan tasks 1.1–1.9 — subshell guard, sourced-file guard (`BASH_SOURCE[1]`
  caller-frame check, not the library's), `mktemp -d
  "$base/soleur-run.$$.XXXXXXXX"`, holder fd `exec {fd}< "$dir"` on the caller's
  fd table (`declare -g`), `TMPDIR` export. **Trap contract (spec-flow
  Critical 1 — pin):** `begin` does NOT install a trap by default (a later
  `trap ... EXIT` at the call site — e.g. `test-all.sh:2800` — would clobber
  it and leak the root while reading green); callers splice
  `_soleur_scratch_cleanup` into their EXISTING trap — which must END
  `return 0` / `|| true` (a failing spliced fn under `set -e` aborts the rest
  of the trap; `test-all.sh:4451`'s `trap - EXIT` is an acknowledged bypass
  the splice can't reach). Opt-in trap mode exists only for callers with no
  later EXIT trap. **TMPDIR contract (Kieran-5):** `begin`'s base = the base
  of the effective TMPDIR (an inherited explicit `TMPDIR=/var/tmp` selects
  that base — runners "respect explicit caller TMPDIR", not suppress it). A
  nested `begin` (run-registered-suites inside test-all) detects an
  already-exported `SOLEUR_SCRATCH_SESSION_ROOT` and no-ops — the parent's
  root governs. The existing `soleur_scratch_root` is unchanged.
- `scripts/tmpfs-guard.sh`: add `reap_orphan_scratch_roots()` (Reaper 3) per
  tasks 2X.1–2X.9 — iterate `TMPFS_GUARD_SCRATCH_BASES="${TMPFS_GUARD_SCRATCH_BASES:-/tmp /var/tmp}"`,
  schema-anchored `soleur-run.<pid>.XXXXXXXX` parse (reject non-schema names),
  owner-pid-dead (`/proc/<pid>` absent) AND no `/proc/*/fd` beneath the root
  AND no `/proc/*/environ` containing the root AND `ns=` namespace match —
  the scan folds into `_build_inuse_top`'s existing single-pass `/proc` walk
  per base — `mv` to per-base quarantine + TTL drain. Plus the named merge
  blockers: base-aware `_mark_inuse`/`_INUSE_TOP`
  (2X.5c), `_INUSE_TOP["__built__"]` fail-closed sentinel (2X.6),
  `TMPFS_GUARD_SCRATCH_BASES` fail-closed-when-unset arm (AC14), lockfile
  TMPDIR-independent (task 2.11), Reaper-2 protect-list `soleur-run.*|soleur-quarantine.*` (task 2.10).

**Track 3 — Adoption + triggers (prevention + reach).**

- Session-start sweep in `worktree-manager.sh` reaps schema-named +
  `.soleur-owned` orphans on both bases. **Placement:** BEFORE the
  `cleanup_merged_worktrees` fetch gate (line ~2804) — an offline session must
  still sweep (it needs no network). **Serialization:** `flock -n` on the
  SINGLE literal guard lockfile path (task-2.11-pinned, TMPDIR-independent,
  per-uid) — the repo-scoped `acquire_lock` session-state locks are
  the wrong domain, and their `_SS_LIB_MISSING` stub returns 0 (would run
  unserialized against a live guard). Skip loudly on contention or
  unresolvable path. The sweep call itself is `||`-guarded (a non-zero exit
  must not abort the fetch + downstream maintenance — wm:2777-2789 precedent)
  and carries a `SWEEP-DEFER` telemetry line for the bounded worktree batch.
- `.soleur-owned` marker convention: producers write `<dir>/.soleur-owned`
  (regular file, same-uid) containing `pid=` (the TOP-LEVEL harness pid —
  a fixture's own `$$` dies at suite exit and would reap the dir mid-run) or
  `owner_root=` (the adopting session root whose liveness covers it), plus
  `schema=` and `ns=` (pid-ns/boot-id discriminator). Marker-bearing dirs reap
  under the same conjuncts as `soleur-run.*`. A marker without `pid=`/
  `owner_root=` is invalid → ignored.
- Producer adoption: `scripts/test-all.sh` +
  `apps/web-platform/infra/run-registered-suites.sh` call
  `soleur_scratch_session_begin` at entry (splice cleanup into existing
  traps — ADR-129; the run-registered-suites EXIT trap is an inline string,
  not a function list — splice inside it, ending `|| true`). **Spec-flow
  Critical 2:** post-adoption `TMPDIR` is the session root, so every
  producer's self-reap enumeration must be pinned to the BASE, not `$TMPDIR`
  — `run-registered-suites.sh:386`'s
  `find "${TMPDIR}" -name 'infra-suites.*' -mmin +720` would otherwise scan
  the root and no-op forever silently. The census is wider than
  `find.*TMPDIR`: also `mktemp "${TMPDIR:-/tmp}/…"`, `mktemp -d /var/tmp`,
  `mktemp -d /tmp` hardcoded-base forms (`git grep -n` census at work time —
  these bypass the TMPDIR redirect entirely). Top fixture writers get
  markers + self-reap-at-startup: `rung2-archive`, `gdboot`, `pirgate`,
  `kbcov`, `gdpr-gate-incidents`, `deploygap`, `inngest-ci/arm`.
- `scripts/tmpfs-guard.timer` + `scripts/tmpfs-guard.service` (systemd `--user`)
  and a runbook note covering `loginctl enable-linger` (required for the timer
  to fire headless) — the designed trigger for hosts with no cronie (this host).

## Technical Approach

### Architecture

- **One classifier, three consumers — and it lives on the SHIPPED surface.**
  `plugins/soleur/scripts/lib/tmp-classify.sh` (new shared module, self-contained,
  no imports from session-state/worktree-manager — the purge must not break
  under `set -u` on a bare host) owns the single definition of "safe to move":
  the `.soleur-owned` marker format, the attribution ladder + purge allowlist,
  the full liveness predicate, and `_classify_scratch_git_dir`. It sits under
  `plugins/soleur/scripts/lib/` because `worktree-manager.sh` ships via
  marketplace as `./plugins/soleur` ONLY — `scripts/lib/` does not exist on
  installed hosts (the pre-#7409 torn-install class). Repo-side consumers
  (purge, tests) resolve it via `git rev-parse --show-toplevel`. A missing lib
  fails closed: sweep skips its tmp arm loudly.
- **Attribution ladder** (in priority order): `.soleur-owned` marker →
  `soleur-run.*` schema → `.git` file (worktree pointer) → empty dir →
  name-prefix+signature allowlist (purge-only). `.git` *directories* (standalone
  clones) are report-only never-candidates — there is no owning repo to verify.
  Below the ladder: unattributable — left to tmpfiles, reported only.
- **The prefix allowlist is honest about what it is.** Each row carries
  prefix + a per-class subpath/content signature (e.g. `rung2-archive.*` must
  contain the readiness-gate's marker layout) + a writer citation. Prefix-only
  is the rejected heuristic relocated behind a manual trigger — the signature
  is what makes it attributable; the spec owns that framing. The list is
  **frozen**: new producers get markers, not rows.
- **Liveness is conjunctive and external** — owner pid absent in `/proc` AND
  no `/proc/*/fd` entry beneath the root AND no `/proc/*/environ` containing
  the root path. (`/proc/<owner>/environ` is an exec-time snapshot — it can
  never see a post-exec `export TMPDIR`, so the environ conjunct works only as
  a descendant scan; PPID checks are unimplementable because dead-owner
  orphans reparent to init.) This scan folds INTO the existing single-pass
  `_build_inuse_top` walk per base — one `/proc` enumeration, not a second
  machinery (DHH-2). `/proc/<pid>`-present-but-foreign (pid reuse) is
  retentive. **Namespace discriminator:** markers/schema dirs record the
  owner's pid-namespace inode or boot-id; a container producer writing
  `soleur-run.<container-pid>` on a host bind-mount would otherwise read dead
  to a host reaper — the reaper skips any candidate whose recorded namespace
  can't be verified from its own namespace, and skips the whole arm + alarms
  when it detects it is itself containerized.
- **Holder-fd pin:** the allocator's holder var is `declare -g` (a function-
  local `{var}` fd closes when the function returns — the conjunct would die
  silently).
- **Worktree classification anchors to the owning repo** — `.git` file →
  gitdir → resolve main repo → `git --git-dir=<main> worktree list --porcelain`
  and ancestor/upstream checks vs that repo's default ref *as last fetched* (no
  fetch side-effects). Outcomes: registered + clean (no-modified AND
  no-untracked AND no-ignored — porcelain omits ignored files, the
  `worktree-manager.sh:2909` `.env.local` lesson) + merged + no-unpushed +
  past-age-floor → `git worktree remove`; **proven** unregistered → quarantine;
  everything else → **retain**. A `retain-since` stamp bounds the retentive
  arm: a tree whose owning-repo resolution has been unverifiable past a hard
  floor (e.g. 7d — gitdir target deleted/unmounted) escalates to an operator-
  decision list instead of re-reporting forever (×~1,484 backlog dirs = report
  flood otherwise). Reports print counts + top-N, never a full enumeration.
- **Quarantine is the only destructive primitive — with the drain carve-out
  stated.** `mv` to `<base>/soleur-quarantine.<uid>/<class>/` mode 0700 where
  `<class>` ∈ `worktrees|scratch|prefix` — the subdir name encodes the TTL
  class (worktrees 30d, scratch/prefix 7d default), no sidecar files to parse.
  Pre-move: refuse when the quarantine path is a symlink or mountpoint;
  compare `stat -c %d` of source vs quarantine parent — EXDEV fails loud
  (also the BSD-safe mountpoint check; `mountpoint -q` is GNU-only).
  Basename collision → uniquify suffix. The no-`rm -rf`/`find -delete` rule
  is scoped: those tools are permitted ONLY beneath the quarantine root (the
  drain is a terminal delete by definition) and for `git worktree remove` /
  `rmdir` — both are stated carve-outs recorded in the ledger. Schema-named
  roots may be deleted directly in two bounded cases (operator decision
  2026-09-24): the OWNER's own EXIT cleanup, and Reaper 3 on `/tmp` ONLY —
  `soleur-run.*` carries certain attribution at creation and a tmpfs `mv`
  frees zero RAM, so direct delete is the prompt-reclaim path; every
  `/var/tmp` candidate still quarantines.
- **Ledger** — post-move append of the FULL mapping
  `original_path → quarantine_path → class → ts` (mv is atomic; pre-write
  pending rows are near-vacuous); an append failure emits `LEDGER-DROP` on
  stdout+stderr. The ledger also records removes (`worktree remove`, `rmdir`,
  TTL drain) so the restore picture is complete. Rows for live quarantine
  entries are never rotated. `soleur-tmp-purge.sh --restore <name|all>`
  replays the ledger to `mv` entries back; `--drain` forces the TTL drain now
  (`df`-visibility is the operator's reclaim signal — without it the operator
  runs `--apply`, sees no space freed, and files a bug).
- **Serialization** — purge, sweep, and guard all `flock -n` the SAME literal
  lockfile path (single domain lock, TMPDIR-independent — not repo-scoped
  `acquire_lock`, whose `_SS_LIB_MISSING` stub returns 0 unserialized).
  The sweep arm runs at the TOP of `cleanup_merged_worktrees` (before
  `acquire_lock cleanup-merged 5` at :2754 — contention there `return 0`s and
  would silently skip the sweep; before the :2804 fetch gate — offline
  sessions must still sweep).
- **Sweep bounds** — session-start sweeps schema/marker dirs plus a BOUNDED
  worktree batch (cap ~50 dirs or ~10s timebox, remainder deferred to next
  session + `SWEEP-DEFER` telemetry; 1,484 porcelain calls at startup is
  unacceptable) and emits per-run latency.
- **Tree-freshness, not dir mtime** — a top-level dir's mtime does not advance
  on nested writes (the `_FRESH_TOP` fix precedent at `tmpfs-guard.sh:671`);
  the classifier evaluates recursive tree freshness at move time.
- **Marker schema (pinned):** regular file `<dir>/.soleur-owned`, same-uid
  (`-user $uid` scoping like Reaper 2 :606 — never follow symlinks), containing
  `pid=` (the TOP-LEVEL harness pid — a fixture's own `$$` dies at suite exit
  and would reap the dir mid-run) or `owner_root=` pointing at the adopting
  session root whose liveness covers it, plus `schema=` version + `ns=` the
  namespace discriminator. Missing `pid=`/`owner_root=` → invalid marker.
- **Fail-closed surfaces:** base list unset/empty → no reap; `__built__`
  sentinel absent → no count alarm and no reap; `/proc` degraded → skip the
  arm and alarm; marker invalid → ignore the marker; never-candidate/protected
  prefixes evaluate BEFORE all ladder rungs; enumeration itself excludes
  `soleur-quarantine.*` and `*.quarantine-meta` artifacts.
- **Reaper 2 stays single-base.** `reap_scratch_entries` uses `find -delete`
  with no quarantine — the multi-base iteration applies to Reaper 3 ONLY;
  Reaper 2's protect-list gains `soleur-run.*|soleur-quarantine.*` and its
  scope stays `/tmp` (AC6 pins this; unmediated delete must never reach
  `/var/tmp`).
- **Empty-dir rung guards:** `rmdir` only after the `%d` device/mountpoint
  check and the `[A-Za-z0-9_-]{15,}` name-shape gate — emptiness alone is no
  attribution.
- **Host portability:** enumerate external binaries; `timeout`→`gtimeout`→bare
  per `memory-backstop.sh`; no `stat -c`/`date -d`/`readlink -f`/`sed -i`
  GNU-isms without fallbacks (BSD `stat -f` form for the device compare).

### Implementation Phases

#### Phase 1 — Shared classifier + purge + worktree arm (this PR's first slice)

- `plugins/soleur/scripts/lib/tmp-classify.sh` — the single "safe to move"
  module: marker format, attribution ladder, prefix+signature allowlist,
  liveness predicate (evaluated at move time), `_classify_scratch_git_dir`
  (self-contained — no session-state/worktree-manager imports)
- `scripts/soleur-tmp-purge.sh` (dry-run report + `--apply` quarantine +
  `--restore`/`--drain` + ledger; sources `tmp-classify.sh` via `git rev-parse`)
- Worktree arm in `tmp-classify.sh` consumed by both purge and the bounded
  session-start batch — anchors to the owning repo via the candidate's `.git`
  gitdir pointer, never cwd
- `tests/scripts/test-tmp-purge.sh` (fixtures under a sentinel `TMPDIR`, synthetic dirs
  only — `cq-test-fixtures-synthesized-only`; includes a foreign-repo worktree
  fixture proving classification resolves through ITS OWN registry, never
  the cwd repo's — dirty→retain, unverifiable→retain, proven-unregistered→
  quarantine)
- Success criteria: dry-run on the real host lists per-class counts with zero
  unattributable candidates marked for action; `--apply` on synthetic fixtures
  quarantines exactly the allowlisted classes; worktree arm spares a dirty
  registered tree, removes a clean merged one, quarantines an unregistered one.
- Effort: ~1 session.

#### Phase 2 — Reaper 3 + session allocator + markers (machinery slice)

- `soleur_scratch_session_begin` in `scripts/lib/scratch-root.sh`
- `reap_orphan_scratch_roots` + `TMPFS_GUARD_SCRATCH_BASES` multi-base +
  merge-blocker set (TR1) in `scripts/tmpfs-guard.sh`
- `.soleur-owned` marker writer helper (`soleur_scratch_mark_owned`) + reaper
  marker arm
- `scripts/tmpfs-guard.test.sh` extension + `tests/scripts/test-scratch-session.sh`
- Success criteria: AC2–AC4 arms all green on both bases; DRY_RUN inert.
- Effort: ~2 sessions (Reaper 3 + allocator + markers + the full merge-blocker
  set + mutation-matrix rows — heavier than the other slices).

#### Phase 3 — Adoption + triggers + docs (reach slice)

- Entry-point migration: `test-all.sh`, `run-registered-suites.sh` (extend
  existing traps); marker emitters in the named fixture producers; session-start
  sweep extension in `worktree-manager.sh` (both bases, shared flock)
- `scripts/tmpfs-guard.{service,timer}` + runbook section
- Residue probe: run both runners, diff top-level entries before/after on both
  bases; record the measurement in
  `knowledge-base/project/specs/feat-tmp-scratch-reclamation/measurements.md`
  (durable artifact; `soleur:ship` folds it into the PR body)
- ADR-250 (provisional): extends the ownership-keyed decision to `/var/tmp`,
  records the `.soleur-owned` marker schema + the purge attribution allowlist,
  amends the never-delete-user-data compliance case to cover `/var/tmp`
- Success criteria: AC5–AC7 pre-merge; AC10 post-merge (zero new unattributed
  entries after full run); ADR lands in the same PR.
- Effort: ~1 session.

## Files to Create

- `plugins/soleur/scripts/lib/tmp-classify.sh` — shared "safe to move"
  classifier (marker format, attribution ladder, prefix+signature allowlist,
  liveness predicate, `_classify_scratch_git_dir`; self-contained) consumed by
  the purge, Reaper 3, and the session-start sweep
- `scripts/soleur-tmp-purge.sh` — `--dry-run` report + `--apply` quarantine +
  `--restore`/`--drain` + ledger
- `tests/scripts/test-tmp-purge.sh` — purge fixtures under sentinel `TMPDIR`
- `tests/scripts/test-scratch-session.sh` — allocator + marker + liveness tests
- `scripts/tmpfs-guard.service` + `scripts/tmpfs-guard.timer` — systemd `--user`
  units (conditional — see User-Challenge UC5)
- `knowledge-base/engineering/operations/runbooks/tmpfs-guard-install.md` —
  timer/cron install + session-start fallback doc (incl. `enable-linger`)
- `knowledge-base/engineering/architecture/decisions/ADR-250-*.md` — provisional ordinal

## Files to Edit

- `scripts/lib/scratch-root.sh` — add `soleur_scratch_session_begin` + `soleur_scratch_mark_owned`
- `scripts/tmpfs-guard.sh` — Reaper 3 folded into `_build_inuse_top`'s
  single-pass `/proc` walk per base; `TMPFS_GUARD_SCRATCH_BASES`; merge
  blockers (base-aware `_INUSE_TOP`/`_mark_inuse`, `__built__` sentinel,
  TMPDIR-independent lockfile, Reaper-2 protect-list + `/tmp`-only pin)
- `plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh` —
  session-start sweep arm at TOP of `cleanup_merged_worktrees` (before
  `acquire_lock` + fetch gate), `||`-guarded, `flock -n` on the literal guard
  lockfile, bounded worktree batch + `SWEEP-DEFER` telemetry
- `scripts/test-all.sh` — adopt `soleur_scratch_session_begin` (splice into
  existing EXIT trap ending `|| true`)
- `apps/web-platform/infra/run-registered-suites.sh` — adopt allocator (splice
  into the existing inline EXIT trap); pin `infra-suites.*` self-reap `find`
  to the BASE
- `tests/scripts/lib/git-data-birth-readiness-gate.sh` — `.soleur-owned`
  marker on `rung2-archive.*` (writer anchor: the `rung2-archive` emit site)
- `scripts/lib/git-data-boot-signal-poll.sh` — marker on `gdboot*` (writer
  anchor: the `gdboot` emit site)
- `plugins/soleur/test/kb-coverage.test.ts`, `ship-incident-pir-gate.test.ts`,
  `web-platform-runtime-plugin-trigger.test.ts`, `gdpr-gate.test.ts` —
  markers on fixture dirs
- `scripts/tmpfs-guard.test.sh` — extend for Reaper 3 / multi-base
- `knowledge-base/engineering/architecture/decisions/ADR-133-*.md` — amendment
  noting the two-base extension + producer-self-reap adoption

## Alternative Approaches Considered

| Approach | Why rejected |
|---|---|
| B — machinery only, manual backlog cleanup | Ships prevention while the disk fills (~11-day runway); the operator does the risky cleanup by hand instead of a vetted dry-run script |
| C — producers-only, no allocator/Reaper 3 | Bare-`mktemp` class stays unowned; 27 GB backlog still needs a purge; discards the designed abstraction the plan already paid for |
| Migrate convention to XDG_CACHE_HOME | Breaks ~236 per-file `TMPDIR=/var/tmp` exports; loses the 30d tmpfiles backstop; `scratch-root.sh` already covers the need differently |
| Rely on systemd-tmpfiles alone | 30d aging vs ~4 GB/day → disk pressure before aging engages; tmpfiles cannot distinguish live sibling scratch |
| Broad heuristic reaper (age/size/count/prefix) | #7004 measured it: ~1,500 authored files marked for deletion; `find -delete` is terminal — rejected permanently, this is the hard boundary |
| GitHub Action / remote sweeper | The dirs live on the operator's workstation, not in CI |

## Research Insights

**Carried from brainstorm (this session — repo-research, learnings, triad
findings; not re-spawned):**

- Producer census: ~856 bare `mktemp`/`mktemp -d` call sites across tracked HEAD
  (~547 shell, ~309 TS); named writers verified (anchors, not stale lines):
  `rung2-archive` → `tests/scripts/lib/git-data-birth-readiness-gate.sh`
  (the `rung2-archive` emit site);
  `gdboot` → `scripts/lib/git-data-boot-signal-poll.sh` (the `gdboot` emit
  site); `inngest-*` → `tests/scripts/cloud-init-inngest-bootstrap.test.sh`
  (the inngest fixture emit sites); `infra-suites.*` →
  `apps/web-platform/infra/run-registered-suites.sh` (self-reaps >12h at
  startup — the prevention precedent); `soleur-inc-*` →
  `.claude/hooks/lib/test-incident-sandbox.sh` (self-reaps >3h — precedent);
  `pirgate`/`kbcov`/`mutbat`/`gdpr-gate-incidents` → `.ts` test fixtures with
  zero cleanup.
- Reaper inventory: `tmpfs-guard.sh` (single `TMP_ROOT=/tmp`; reaps big stale
  `.output`-class entries; count-alarm only, no reclaim); `cleanup_stale_sandbox_tmp`
  (`/tmp` only, signature classes only); `cleanup_orphan_worktree_dirs` (`.worktrees/`
  scope only — `/var/tmp` worktrees out of reach by construction);
  `session-state.sh` (lease sweep, no dir param); `soleur_scratch_root` (exists,
  zero callers); `orphan-process-reaper.sh` (reports only, ADR-195).
- Prior-art plan task map preserved: `scripts/lib/scratch-root.sh` gains
  `soleur_scratch_session_begin` (it exists — the plan's "new file" becomes
  "amend"); `tmpfs-guard.sh` merge blockers 2X.5c/2X.6/AC14/task 2.10/2.11 all
  still unimplemented (verified by grep this session).
- Institutional learnings that bind: conjunctive liveness (environ marker +
  fd + process tree), no `du` as a Reaper-3 instrument (ADR-133 addendum),
  allocation-free enumeration (no `find` unbounded, no `mapfile` on stale
  snapshots — the subshell-stale-snapshot defect), quarantine-not-delete for
  shared dirs, `bash -c` subshells in DRY_RUN are false evidence, fd
  inheritance outlives the owner (2026-09-22), reaper must re-read state at
  action time and verify its own code freshness (2026-09-24 stale-reaper).
- Related open issues: #6760 (skill-security-scan retention — excluded),
  #8659 (trap-composition class informs Phase 3), #7210 (tmpfs-guard host
  failures — verify before relying), #8496 (same cleanup-merged block —
  coordinate), #7537 (process-level reaper, complement).

**Premise Validation (Phase 0.6):** #7004 confirmed open; PR #7019 merged;
#6760/#8659/#7210/#8496 confirmed open; all cited files exist on `origin/main`
(`scratch-root.sh` at `scripts/lib/`, `session-state.sh` moved to
`plugins/soleur/scripts/lib/` post-#7409); ADR corpus check — ADR-133 D2
(tmpfs managed/reaped, conjunctive gates), ADR-124 (liveness-gated reclaim
precedent), ADR-195 (orphan boundary report-not-reap) — no ADR rejects the
proposed mechanisms; ADR-133 addendum binds: producer self-reap is the
precedent, `du` unusable as instrument. New premise corrected vs the #7004
plan: the cron trigger does not exist on this host → session-start sweep is
primary, guard timer optional.

**Property List (0.6b):**

- P1: reclaim orphaned soleur-owned scratch on `/tmp` AND `/var/tmp` without
  heuristic inference
- P2: reclaim the existing ~32 GB backlog with zero false positives
- P3: reclaim orphaned worktrees without losing uncommitted/unpushed work
- P4: producers that cannot adopt the allocator still declare ownership
- P5: reclamation runs on hosts with no cron installed
- P6: the biggest measured leakers stop leaking at the source

**Cut List (0.6b):** none — every proposed mechanism maps to a property no
existing mechanism covers (`tmpfs-guard.sh` lacks P1's second base and P2's
attribution reach; `cleanup_orphan_worktree_dirs` lacks P3's scope; the cron
trigger lacks P5's existence). The prefix allowlist inside the purge is kept
deliberately: the backlog predates markers — there is no marker to read — and
each allowlisted prefix is cited to an in-repo writer.

**Value-Proposition Measurement (0.6c):** reclaimed space is measured, not
asserted — `/var/tmp` 27 GB + `/tmp` 5.5 GB (`du -sm`, per-prefix counts via
`find -maxdepth 1`), growth ~4 GB/day over the 7-day sample, `/` free 46 GB →
runway ~11 days. The dry-run pass time will be recorded in the PR body.

**External research decision (1.6):** skipped — internal tooling on a
well-characterized local surface; the design is already certified by the
#7004 plan and this session's triad review. (Functional-overlap agent ran in
parallel — see Domain Review / References.)

## Research Reconciliation — Spec vs. Codebase

| Spec/plan claim | Reality on origin/main | Plan response |
|---|---|---|
| #7004 plan references `AGENTS.rest.md` | File is now `AGENTS.rules.md` (ADR-151) | Cite the new name |
| #7004 plan cites `.claude/hooks/lib/session-state.sh` | Moved to `plugins/soleur/scripts/lib/session-state.sh` (#7409) | Use the shipped path — it is the version installed users actually get |
| #7004 plan cites `87 suites` in run-registered-suites | 76 suites (learnings research) | Use 76 |
| #7004 plan's "backlog self-drains" | True for tmpfs only; false for /var/tmp at 4 GB/day | Track 1 purge is prerequisite, not deferred |
| #7004 plan's "reaper runs from user cron" | No `crontab` binary on this host; guard never ran | Session-start sweep is primary trigger; systemd user timer committed as optional unit |
| spec FR3 names `scripts/lib/scratch-root.sh` as new | File exists with `soleur_scratch_root` | Amend, don't create; preserve existing semantics |

## User-Brand Impact

- **If this lands broken, the user experiences:** silent loss of authored work —
  a reaping false-positive deletes a live sibling session's scratch dir, a
  review backup, or an operator's uncommitted worktree (`find -delete`/`rm -rf`
  on shared dirs has no trash).
- **If this leaks, the user's workflow is exposed via:** a wrong-attribution
  reap touching non-Soleur dirs in the shared `/tmp`/`/var/tmp` namespaces —
  including credential-bearing trees (`env.txt`, `a*.env` observed in backlog).
- **Brand-survival threshold:** `single-user incident`

Artifacts at risk: live sibling-session scratch roots; registered-but-dirty
worktrees; unattributable operator dirs in shared temp space; quarantined
content pending TTL drain.

## Observability

```yaml
liveness_signal:
  what: "SOLEUR_TMP_REAP / SOLEUR_TMP_PURGE stdout lines per run (per-base reaped + found counts); quarantine ledger append"
  cadence: "per session-start sweep + per operator purge invocation + per guard timer tick (where installed)"
  alert_target: "operator session (stdout) + ~/.local/state/soleur/tmpfs-guard-alarms.log consumed by session-rules-loader.sh SessionStart block"
  configured_in: "scripts/tmpfs-guard.sh (alarm emit); plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh (sweep emit); scripts/soleur-tmp-purge.sh (ledger)"

error_reporting:
  destination: "~/.local/state/soleur/tmpfs-guard-alarms.log + stdout alarm lines at SessionStart"
  fail_loud: "alarm line emitted when an arm is skipped for degraded evidence (hidepid, unset bases, missing sentinel) — silence on a skip is the defect this surfaces"

failure_modes:
  - mode: "reaper runs but matches nothing (schema drift / glob broke)"
    detection: "found-count telemetry emitted per run — a run reporting found=0 while backlog counters grow is flagged"
    alert_route: "tmpfs-guard-alarms.log → SessionStart block"
  - mode: "purge mis-attributes a class"
    detection: "dry-run candidate list is operator-reviewed before --apply; quarantine mv is recoverable; forensic basename ledger records every move"
    alert_route: "operator review + ledger"
  - mode: "live sibling scratch reaped"
    detection: "liveness conjuncts (TR3) — a conjunct failure retains the dir and logs the skip reason"
    alert_route: "per-dir skip lines in run output"
  - mode: "guard skipped due to degraded /proc or missing sentinel"
    detection: "explicit skip-with-reason alarm (fail_loud)"
    alert_route: "tmpfs-guard-alarms.log → SessionStart block"

logs:
  where: "stdout per run; ~/.local/state/soleur/tmpfs-guard-alarms.log; ~/.local/state/soleur/tmp-purge-ledger.log; quarantine dirs themselves are the material ledger"
  retention: "machine-local; quarantine drains past TMPFS_GUARD_QUARANTINE_TTL_MIN; ledgers rotate via existing log-rotation lib"

discoverability_test:
  command: "bash scripts/soleur-tmp-purge.sh --dry-run"
  expected_output: "SOLEUR_TMP_PURGE"
```

## Encryption Posture

Skipped — no persistent data store, no new cross-component/network connection.
Quarantine dirs and ledgers are filesystem artifacts on the same host (mode
0700), not a store the posture schema addresses. Detection globs (`.tf`,
`.sql`, `cloud-init`, `docker-compose`) match nothing in this plan.

## Infrastructure (IaC)

Detection fired on `systemd unit`/`cron` wording — disposition recorded rather
than routed to `soleur:engineering:infra:terraform-architect`:

- The systemd `--user` timer is a **dev-workstation user-level unit file**
  committed to `scripts/` plus a runbook note; it is an optional convenience
  for hosts lacking cronie, not production/vendor infrastructure. Terraform
  has no substrate managing operator laptops — routing it through IaC is a
  category error (the same class as the existing user-cron instructions for
  tmpfs-guard, which are documented-not-provisioned).
- No servers, secrets, vendor accounts, DNS, firewall rules, or cloud resources
  are introduced. Nothing in the plan prescribes `ssh` provisioning or
  dashboard clicks.

## Guard Contract

### Guard 1 — Reaper 3 dispatch is non-vacuous

**Property.** A run of `reap_orphan_scratch_roots` over `SCRATCH_BASES`
enumerates the schema/marker population on every configured base and applies
the liveness conjuncts to each member — a run that checks zero members and
exits 0 is a defect, never a clean pass.

**Assembly.** Every top-level entry in each base matching the schema glob or
carrying `.soleur-owned`, enumerated allocation-free inside
`reap_orphan_scratch_roots` (`scripts/tmpfs-guard.sh`) — the chokepoint is the
function's per-base enumeration loop; members flow through the conjunct ladder
in one pass (no early per-base exit that skips remaining bases).

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Seed a dead-pid `soleur-run.<dead>.XXXXXXXX` on base 2 (`/var/tmp` sentinel) while base 1 is clean — run | RED unless the dir is reaped (proves multi-base iteration, not just `/tmp`) |
| 2 | Make the base-list seam unset/empty (`TMPFS_GUARD_SCRATCH_BASES=""`) — run | RED unless the arm skips loudly (fail-closed alarm), never silently reaps |
| 3 | Two schema dirs: first dead-owner, second live-owner (holder fd + environ) — run | RED unless exactly the first is quarantined and the second retained with a logged skip reason |
| 4 | (harness) Test asserts `reaped>0` but fixture setup never created the dir | RED — the suite's setup assertion must fail before the reaper runs (anti-vacuous-harness row) |
| 5 | Dir whose owner pid was reused by an unrelated process (same numeric pid, different environ, fd released) | RED unless environ/child conjuncts retain it |

### Guard 2 — Purge attribution allowlist is bounded and cited

**Property.** `soleur-tmp-purge.sh --apply` may quarantine only entries whose
class is in the committed allowlist (each row cites an in-repo writer) or is
self-declared (`.soleur-owned` marker with valid `pid=`) — anything else,
including bare `tmp.*` non-git, is report-only regardless of age or size.

**Assembly.** The allowlist table in `scripts/soleur-tmp-purge.sh` (single
case/classification chokepoint every candidate flows through) + the
marker/schema ladder evaluated before the allowlist — a candidate that matches
no ladder rung never reaches a move.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | A `tmp.<rand>` dir containing authored files, 40 days old, 500 MB — dry-run | RED unless it appears as report-only / unattributable, never as a candidate |
| 2 | Remove a prefix row from the allowlist — dry-run | RED unless that class's count drops to zero candidates (the allowlist, not a fallback heuristic, admits) |
| 3 | A `.soleur-owned` dir with `pid=` of a live process vs one with a dead pid | RED unless live is retained and dead is quarantined — the marker delegates to liveness, not to age |
| 4 | `--apply` re-run immediately after a successful `--apply` | RED unless idempotent (zero moves on second run; empty dirs rmdir'd already gone) |
| 5 | (dispatch) A run where the enumeration itself fails (base unreadable) | RED unless the run reports the arm as failed rather than "0 candidates" |

### Guard 3 — Worktree sweep never reaps unverifiable trees

**Property.** A `.git`-file-bearing scratch dir reaches `git worktree remove`
only when it is registered AND clean (incl. ignored) AND merged AND has no
unpushed commits AND no live process inside AND is past the age floor; proven-
unregistered dirs go to quarantine; everything unverifiable is retained
(`retain-since` floor → operator list); `.git` directories are report-only.

**Assembly.** `_classify_scratch_git_dir` in
`plugins/soleur/scripts/lib/tmp-classify.sh` — the single classification
chokepoint the session-start sweep's bounded batch and the purge's worktree
arm both source; registration resolves via the owning repo's
`git --git-dir=<main> worktree list --porcelain` (never cwd, never ref-name-
derived paths).

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Registered worktree, clean, merged, no unpushed, young (below age floor) | RED unless retained — all conjuncts must hold |
| 2 | Registered worktree, clean, merged, but with an unpushed commit | RED unless retained (uncommitted/unpushed is the load-bearing conjunct) |
| 3 | Proven-unregistered `.git` dir (owning-repo porcelain lists no such path) | RED unless quarantined + reported, never `rm`'d or `worktree remove`d |
| 4 | `.git` file (gitdir pointer) whose target is stale/missing | RED unless treated as unverifiable → retained + reported (quarantine is only for proven-unregistered) |
| 5 | (dispatch) `git worktree list --porcelain` itself fails/returns empty | RED unless the arm fails closed — every candidate retained with "registration unverifiable" |

## Architecture Decision (ADR/C4)

### ADR

New **ADR-250 (provisional)** via `soleur:architecture` — "ownership-keyed
scratch reclamation extends to `/var/tmp`; `.soleur-owned` marker schema;
quarantine-mediated backlog purge." Records: the two-base decision, the marker
schema (`pid=` + `schema=`), the purge's attribution allowlist, the
never-delete-user-data compliance case extended to `/var/tmp`, and the
trigger-split (session-start primary, cron/timer secondary). Amends the ADR-133
D2 posture where the new conjuncts supersede age+size for schema-owned classes.
Ordinal provisional — sibling PRs may claim 249; `soleur:ship` re-verifies.

### C4 views

No C4 impact — enumeration checked against `model.c4`/`views.c4`/`spec.c4`:
(a) external human actors: none new (founder/operator already modeled); the
reaper acts on the same host the model already bounds; (b) external
systems/vendors: none new (systemd user timers and `git worktree` are
host-internal facilities — the model treats host facilities as container
descriptions, e.g. the hooks container's systemd transient scope, not
elements); (c) containers/data-stores: `plugins/soleur` container already
models shipped bash primitives — new files are instances inside it;
`~/.local/state/soleur/` mirrors the existing compaction-ledger pattern
(machine-local, outside the git tree — already described in the model);
(d) relationships: no actor↔surface edge changes (session-start cleanup edge
already modeled; the guard adds no new consumer).

## Acceptance Criteria

### Pre-merge (PR)

- [ ] AC1: `bash scripts/soleur-tmp-purge.sh --dry-run` prints
  `SOLEUR_TMP_PURGE` + per-class candidate counts AND estimated bytes per
  class (so the PR body carries real reclaimed-GB, not the 27 GB headline)
  with zero unattributable candidates marked for action; `--apply` on
  synthetic fixtures quarantines only allowlisted/marker/schema/empty/git
  classes; re-run is idempotent; a forensic ledger
  (`original → quarantine → class → ts`, removes included) lands under
  `~/.local/state/soleur/tmp-purge-ledger.log` (redirected at the test
  chokepoint in fixtures); `--restore` replays a ledger row; `--drain`
  forces the TTL drain.
- [ ] AC2: Reaper 3 on `TMPFS_GUARD_SCRATCH_BASES="<sentinel-a> <sentinel-b>"`
  reaps a dead-owner `soleur-run.*` root on EACH base — direct delete on the
  tmpfs-class base, quarantine on the disk-class base — spares a live-owner
  root on each, drains quarantine past `TMPFS_GUARD_QUARANTINE_TTL_MIN`, and
  is fully inert under `DRY_RUN=1` (real filesystem assertions, not
  `bash -c` subshell evidence).
- [ ] AC3: Worktree arm — registered + clean (no-modified/untracked/ignored) +
  merged + no-unpushed + past floor **+ no live `/proc` cwd/fd inside the
  tree** → `git worktree remove` via the owning repo's gitdir; **proven**
  unregistered → quarantine + report; registered + dirty OR unpushed OR young
  OR live-resident OR unverifiable (incl. porcelain/gitdir failure) → retain
  and report (with `retain-since` floor → operator-decision list); `.git`
  *directories* (standalone clones) → report-only, never a candidate; a
  foreign-repo worktree resolves through ITS owning repo's registry, never
  cwd's.
- [ ] AC4: `.soleur-owned` marker dirs reap under the same conjuncts as
  `soleur-run.*`; a marker missing `pid=`/`owner_root=` or failing the
  regular-file/same-uid/`ns=` checks is ignored (dir treated by the allowlist
  ladder only).
- [ ] AC5: Session-start sweep prints per-base `SOLEUR_TMP_REAP` counts,
  runs BEFORE `acquire_lock`/the fetch gate, is `||`-guarded (never aborts
  downstream maintenance), bounds the worktree batch (cap + `SWEEP-DEFER`
  telemetry), and `flock -n`s the literal guard lockfile (a second
  concurrent sweep skips, logged).
- [ ] AC6: All merge blockers verified by test: base-aware `_INUSE_TOP`,
  `__built__` sentinel, `SCRATCH_BASES` fail-closed, lockfile
  TMPDIR-independent, Reaper-2 protect-list covers `soleur-run.*`/`soleur-quarantine.*`.
- [ ] AC7: ADR-250 (or renumbered ordinal) lands in this PR; #7004 updated with
  acceptance-status note (`Ref #7004` in the PR body — `Closes` reserved until
  the post-merge residue measurement lands).
- [ ] AC8: `bash tests/scripts/test-tmp-purge.sh`, `scripts/tmpfs-guard.test.sh`,
  `tests/scripts/test-scratch-session.sh` pass; `test-all.sh` green; a `git grep`
  census of test surfaces asserting on `tmpfs-guard`/`worktree-manager`/
  `scratch-root` is enumerated in `tasks.md` (allow-list-extension edge —
  orphan suites do not ride the touched-file set).

### Post-merge (operator)

- [ ] AC9: `bash scripts/soleur-tmp-purge.sh --dry-run` on the real host is
  reviewed; then `--apply` drains the attributable backlog to quarantine;
  measured GB + per-class counts recorded in
  `knowledge-base/project/specs/feat-tmp-scratch-reclamation/measurements.md`
  (durable artifact — `soleur:ship` folds it into the PR body; never authored
  directly into the body).
- [ ] AC10: Residue measurement — a full `test-all.sh` +
  `run-registered-suites.sh` run produces zero NEW unattributed top-level
  entries **attributable to those runs** in either base (the before/after diff
  classifies each new entry by producer; entries from unrelated concurrent
  processes are reported separately, not counted against the AC — a foreign
  session must not be able to flip this). Recorded in `measurements.md`.
- [ ] AC11: Optional `systemd --user` timer installed per
  `runbooks/tmpfs-guard-install.md` — `Automation: not feasible because the
  unit install is a per-host user preference (the operator's dotfiles layer),
  not a scriptable repo action`.

## Test Scenarios

- Given a synthetic `TMPDIR` sentinel seeded with each allowlisted prefix +
  bare `tmp.*` + `.git` fixtures, when `--dry-run` runs, then each class is
  counted and only ladder-satisfying entries are candidates.
- Given a dead-pid schema root with an orphaned holder-fd and a live-pid root
  with an open fd + environ marker, when Reaper 3 runs, then only the first is
  quarantined and the second is retained with a skip reason.
- Given a `.soleur-owned` dir whose `pid=` is reused by a foreign process
  (environ lacks the schema marker), when the reaper runs, then it is retained.
- Given `TMPFS_GUARD_SCRATCH_BASES=""`, when the guard runs, then the reap arm
  skips loudly and no candidate is touched.
- Given a registered clean merged old worktree vs a dirty one vs an
  unregistered `.git` dir, when the sweep runs, then remove / retain+report /
  quarantine+report respectively.
- Given a trap already installed by `run-registered-suites.sh`, when it adopts
  `soleur_scratch_session_begin`, then its EXIT trap still fires once and its
  `infra-suites.*` self-reap still runs at startup (ADR-129 composition).
- Given `hidepid` simulated (`/proc/<pid>` unreadable for a live owner), when
  the reaper evaluates, then it skips the arm + alarms — never reaps.
- Given the quarantine TTL passes, when the drain runs, then quarantined
  entries are removed; a ledger row remains.

Deterministic verification commands (consumed by `soleur:qa`):

- **Local verify:** `bash scripts/soleur-tmp-purge.sh --dry-run` → prints
  `SOLEUR_TMP_PURGE` + class rows.
- **Fixture verify:** `bash tests/scripts/test-tmp-purge.sh` → `ALL TESTS PASSED`.
- **Residue probe:** `find /tmp /var/tmp -maxdepth 1 -newermt '1 hour ago'
  -type d | wc -l` before/after a full runner pass — delta attributable to
  schema/marker dirs only.

## Success Metrics

- `/var/tmp` attributable backlog drained to quarantine on first `--apply`
  (measured GB in PR body); zero false-positive reports post-run.
- Post-adoption, `/var/tmp` + `/tmp` unattributed entry growth rate ≈ 0/day
  (residue probe re-run in a follow-up session).
- Session-start sweep emits per-base reap counts on every session — visible,
  non-zero-capable telemetry rather than silent no-op.

## Dependencies & Risks

- **Risk — reaping a live sibling's scratch (top risk per CTO):** mitigated by
  conjunctive liveness (pid + held fd + environ + children + commit-grace),
  quarantine-not-delete, and the fail-closed sentinel set (TR1).
- **Risk — purge mis-attribution:** bounded by the allowlist-cites-writer rule;
  dry-run reviewed before apply; quarantine is recoverable.
- **Risk — `worktree-manager.sh` is a shipped plugin surface:** session-start
  changes reach installed users; the sweep must degrade gracefully where
  `git worktree list` or `/proc` is unavailable (cloud sessions — see
  ADR-221/cloud-mode contract).
- **Risk — plan drift from the #7004 tasks:** the named merge blockers are
  carried verbatim into AC7 so a partial port cannot certify.
- **Dependency:** none external; `systemd --user` timer is optional.
- **Coordination:** #8496 touches the same `cleanup-merged` block — check its
  merge state before Phase 3 lands; #7210 should be re-verified for guard
  behavior assumptions.

## Open Code-Review Overlap

Checked 2026-09-24 against open `code-review` issues (2 matches + 1 adjacent):

- **#8496** (`worktree-manager.sh`: cleanup-merged never gh-queries `[gone]`
  branches with no worktree) — **Acknowledge.** Same function block, different
  concern (branch-side vs dir-side); this plan does not fix it but Phase 3's
  sweep edits adjacent code — check #8496's merge state before landing to
  avoid a rebase collision.
- **#8659** (`test-all.sh` class: 33 suites replace test-helpers' composed
  EXIT trap and leak the incident sandbox) — **Acknowledge + informs.** Phase
  3's trap-extension rule (extend, never add/replace) is written against this
  class; closing #8659 itself is out of scope (separate trap-composition fix).
- **#7942** (two `*.mutation.sh` batteries run in no gate — mentions
  `test-all.sh`) — **Defer.** Orthogonal to scratch reclamation; no edit
  needed here.

## Domain Review

**Domains relevant:** Engineering, Legal, Product (carried forward from
brainstorm ## Domain Assessments — same session, unchanged scope)

### Engineering (CTO)

**Status:** reviewed (brainstorm carry-forward)
**Assessment:** Plan certified with priority inversion — ship
`SCRATCH_BASES="/tmp /var/tmp"` in the machinery slice, not deferred. Orphaned
worktrees get the git-aware sweep described in Track 1b. Marker file must
carry owner identity (`pid=`). Reaper home = both tmpfs-guard and
session-start, partitioned by class. Top risk: reaping a live sibling's
scratch — all destructive paths quarantine-mediated.

### Legal (CLO)

**Status:** reviewed (brainstorm carry-forward)
**Assessment:** PROCEED conditional — `/var/tmp` higher risk than `/tmp`;
schema-named roots only for auto-reap; worktrees quarantine+report with
longer TTL; no-content-read invariant; merge blockers (base-aware `_INUSE_TOP`,
fail-closed sentinel, seam pinning) gate `/var/tmp` enablement — carried into
AC7; ADR must extend the never-delete-user-data case to `/var/tmp`;
PR body must state the 27 GB backlog is out of auto-reap scope.
`soleur:gdpr-gate` invoked at this plan's Phase 2.7 — see findings below.

### Product (CPO)

**Status:** reviewed (brainstorm carry-forward) — **CPO sign-off: the CPO
assessment in the brainstorm reviewed this exact approach (purge-first
sequencing, ownership-keyed mechanism, worktree class); per the plan-time
lifecycle, that constitutes the plan-time sign-off.**
**Assessment:** Finish-the-stalled-plan is the right call; backlog purge moves
from deferred to prerequisite under `/var/tmp` growth; sequence = purge →
machinery → adoption; zero false-positive deletions is the non-negotiable bar.

**Brainstorm-recommended specialists:** none recommended by name.

## Review & Consult Provenance

- **Advisor consult (Phase 4.5):** two changes applied — (1) single shared
  classifier `scripts/lib/tmp-classify.sh` consumed by purge + Reaper 3 +
  sweep (prevents three divergent "safe to move" implementations); (2)
  worktree classification anchored to the owning repo via `.git` gitdir.
- **Spec-flow analysis (Phase 3):** verdict proceed-with-conditions — all
  conditions applied inline: trap-contract pin (no default trap in `begin`;
  splice into caller's existing trap list), base-pinned self-reap
  enumeration, registered-but-unverifiable worktrees retained (quarantine
  only for proven-unregistered), clean includes ignored files, sweep placed
  before the fetch gate, literal guard-lockfile serialization, EXDEV
  fail-loud, pre-write ledger + no-rotate-while-live, fd/environ
  descendant-scan + pid-namespace gate, empty-dir mountpoint + name-shape
  guards, protected-before-ladder ordering, per-class TTL sidecars,
  `BASH_SOURCE[1]` caller-frame check, `enable-linger` in runbook.
- **Functional discovery (Phase 1.5b):** install nothing — no community/OS
  tool expresses ownership-keyed reclamation; prior-art citations
  (dead-owner `mkdtemp` marker reclamation, `claude-owns.json`, systemd user
  timer precedent) noted in References.
- **Plan-review panel (7 seats: DHH, Kieran, code-simplicity, architecture,
  spec-flow re-check, CPO, CTO):** ~30 mechanical findings applied inline
  (shipped-surface classifier home, drain carve-out, retain-since floor,
  `.git` file-vs-dir, marker schema pins, Reaper-2 `/tmp`-only pin,
  prefix+signature allowlist, live-process conjunct, `--restore`/`--drain`,
  bounded sweep, single domain lockfile, nested-`begin` contract, citation
  corrections). **User-Challenge resolutions (operator, 2026-09-24):**
  (UC1) one PR, not split; (UC2) keep full ownership-keyed machinery —
  approach A stands; (UC3) session-start sweep ships unconditionally to
  installed hosts; (UC4) Reaper 3 MAY direct-delete schema roots on `/tmp`
  (RAM reclaim is prompt), `/var/tmp` always quarantines.

## GDPR / Compliance Gate (Phase 2.7)

**This is not legal review. Findings are heuristic. Consult `soleur:legal:clo` + `soleur:legal:legal-compliance-auditor` before merging.**

Expansion trigger (b) fired (`single-user incident` threshold) → gate run
against the plan + FR/TR surfaces. Canonical regex matches zero files in this
diff (no migrations, auth, API routes, `.sql`).

- `GDPR-Art-6` — no new schema columns → no finding.
- `GDPR-Art-5e` — no new PII table → no finding.
- `GDPR-Art-17` / `GDPR-Art-17-caller` — no FK/RPC changes → no finding.
- `GDPR-Chapter-V` — no new vendor/SDK/env var → no finding. All processing is
  same-host, same-uid; no data leaves the workstation.
- `GDPR-Art-9` — no columns at all → no finding. **No Critical findings.**

### `SUG-1` — forensic ledger retains quarantined basenames

**Severity:** Suggestion
**Article:** Art. 5(1)(c) data minimisation / Art. 5(1)(e) retention
**Location:** plan §Architecture (ledger line) + `scripts/soleur-tmp-purge.sh`
**Pattern matched:** persistent log of directory basenames
**Why this matters:** the ledger records dir *names* only (no content — the
no-content-read invariant holds), but a user could embed personal data in a
temp dir name. The design is a net Art. 32 positive — it removes stale
secret-bearing trees (`env.txt`, `a*.env` observed in backlog) and confines
quarantine to mode-0700 dirs.
**What to do:** bound ledger retention via the existing log-rotation lib
(stated in Observability); never log dir *contents*, only basenames (already
the design).

## References & Research

- Prior plan (superseded-by-reference):
  `knowledge-base/project/plans/2026-07-27-feat-tmpfs-ownership-keyed-scratch-root-reclamation-plan.md`
- Spec: `knowledge-base/project/specs/feat-tmp-scratch-reclamation/spec.md`
- Brainstorm: `knowledge-base/project/brainstorms/2026-09-24-tmp-scratch-reclamation-brainstorm.md`
- Existing module: `scripts/lib/scratch-root.sh` (`soleur_scratch_root`)
- Guard: `scripts/tmpfs-guard.sh` (Reapers 1–2, `TMP_ROOT`)
- Session-start: `plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh`
  (`cleanup-merged`, `cleanup_stale_sandbox_tmp`, `cleanup_orphan_worktree_dirs`)
- Leases: `plugins/soleur/scripts/lib/session-state.sh`
- Precedents: `scripts/run-registered-suites.sh` (infra-suites self-reap),
  `.claude/hooks/lib/test-incident-sandbox.sh` (soleur-inc self-reap)
- ADRs: ADR-133 (tmpfs managed/reaped + producer-self-reap addendum),
  ADR-124 (liveness-gated reclaim), ADR-195 (orphan boundary report-not-reap),
  ADR-129 (one trap per script), ADR-221 (cloud mode contract)
- Issues: #7004 (tracking), #7019 (merged PR 0), #7537 (closed — process-level
  reaper shipped, ADR-195), #6760/#8659/#7210/#8496/#7942 (adjacent open)
