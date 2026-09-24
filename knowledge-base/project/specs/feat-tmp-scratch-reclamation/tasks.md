# Tasks — feat-tmp-scratch-reclamation

Plan: `knowledge-base/project/plans/2026-09-24-feat-tmp-scratch-reclamation-plan.md`
Issue: #7004 | PR: #8738 | Lane: cross-domain | Threshold: single-user incident

## Phase 1 — Shared classifier + purge + worktree arm

- [x] 1.1 Create `plugins/soleur/scripts/lib/tmp-classify.sh` (self-contained;
  no session-state/worktree-manager imports; fails closed when missing)
  - [x] 1.1.1 `.soleur-owned` marker validation (regular file, same-uid,
    `pid=`|`owner_root=`, `schema=`, `ns=` discriminator)
  - [x] 1.1.2 Attribution ladder: marker → `soleur-run.*` schema → `.git` file
    → empty dir → prefix+signature allowlist (frozen, writer-cited);
    `.git` directories = report-only; protected prefixes evaluate first
  - [x] 1.1.3 Liveness predicate at move time: owner pid absent AND no
    `/proc/*/fd` beneath root AND no `/proc/*/environ` containing root AND
    `ns=` match; pid-reuse retentive
  - [x] 1.1.4 `_classify_scratch_git_dir`: `.git` file → gitdir → owning repo
    → `git --git-dir=<main> worktree list --porcelain`; clean includes
    ignored files; + no live `/proc` cwd/fd inside the tree; `retain-since`
    stamp + hard floor → operator-decision list
  - [x] 1.1.5 Tree-freshness (recursive), not dir mtime; EXDEV `%d` compare;
    symlink/mountpoint refusal; basename uniquify
- [x] 1.2 Create `scripts/soleur-tmp-purge.sh` — `--dry-run` (default, prints
  `SOLEUR_TMP_PURGE` + per-class count + est. bytes), `--apply`, `--restore`,
  `--drain`; `flock -n` on the literal guard lockfile; ledger at
  `~/.local/state/soleur/tmp-purge-ledger.log` with LEDGER-DROP alarm
- [x] 1.3 `tests/test-tmp-purge.sh` — sentinel TMPDIR fixtures: allowlisted
  classes, bare `tmp.*` (never candidate), `.git` file worktrees (dirty→retain,
  unverifiable→retain, proven-unregistered→quarantine, foreign-repo registry),
  `.git` dir (report-only), protected prefixes, concurrent-run skip
- [x] 1.4 RED→GREEN→REFACTOR per `cq-write-failing-tests-before`

## Phase 2 — Allocator + Reaper 3 + markers

- [x] 2.1 `scripts/lib/scratch-root.sh`: `soleur_scratch_session_begin` —
  `BASH_SOURCE[1]` caller-frame guard, `mktemp -d "$base/soleur-run.$$.XXXXXXXX"`,
  holder fd (`declare -g`), TMPDIR export, NO default trap; nested-`begin`
  no-op on `SOLEUR_SCRATCH_SESSION_ROOT`; base = effective TMPDIR's base;
  `soleur_scratch_mark_owned` writer
- [x] 2.2 `scripts/tmpfs-guard.sh`: `reap_orphan_scratch_roots` folded into
  `_build_inuse_top`'s single-pass `/proc` walk per base;
  `TMPFS_GUARD_SCRATCH_BASES` (fail-closed when unset); per-base quarantine;
  direct-delete on tmpfs-class base, quarantine on disk-class base; TTL drain
  (quarantine-internal delete carve-out)
- [x] 2.3 Merge blockers: base-aware `_INUSE_TOP`/`_mark_inuse`; `__built__`
  fail-closed sentinel; TMPDIR-independent lockfile; Reaper-2 protect-list
  `soleur-run.*|soleur-quarantine.*` AND Reaper-2 pinned `/tmp`-only
- [x] 2.4 `scripts/tmpfs-guard.test.sh` extension +
  `tests/test-scratch-session.sh` — mutation-matrix rows per Guard Contract
  (multi-base iteration, unset-seam fail-closed, dead+live split, vacuous
  harness row, pid-reuse retentive, container-ns skip)
- [x] 2.5 Run `soleur:gdpr-gate` at Phase-2 exit (advisory; expected scope-out)

## Phase 3 — Adoption + triggers + docs

- [x] 3.1 `scripts/test-all.sh`: `begin` at entry + splice
  `_soleur_scratch_cleanup` into existing EXIT trap ending `|| true`
  (note `trap - EXIT` at :4451 bypasses — splice can't reach it)
- [x] 3.2 `apps/web-platform/infra/run-registered-suites.sh`: `begin` at entry
  + splice into inline EXIT trap; pin `infra-suites.*` self-reap `find` to
  the BASE not `$TMPDIR`
- [x] 3.3 Producer markers + self-reap: `rung2-archive`
  (`tests/scripts/lib/git-data-birth-readiness-gate.sh`), `gdboot`
  (`scripts/lib/git-data-boot-signal-poll.sh`), `pirgate`, `kbcov`,
  `gdpr-gate-incidents`, `deploygap`, `inngest-*`
  (`tests/scripts/cloud-init-inngest-bootstrap.test.sh`)
- [x] 3.4 Census: `git grep -n 'find.*TMPDIR'` + `mktemp "${TMPDIR:-/tmp}/…"` +
  `mktemp -d /var/tmp` + `mktemp -d /tmp` — every self-reap enumeration pinned
  to BASE; every hardcoded-base producer listed in the PR body
- [x] 3.5 `worktree-manager.sh`: sweep arm at TOP of `cleanup_merged_worktrees`
  (before `acquire_lock` at ~2754, before fetch gate ~2804), `||`-guarded,
  `flock -n` literal guard lockfile, bounded worktree batch (~50/~10s) +
  `SWEEP-DEFER`, per-base `SOLEUR_TMP_REAP` counts + latency; first-run
  dry-pass stamp (wm:2899–2935 precedent)
- [x] 3.6 `scripts/tmpfs-guard.{service,timer}` + runbook
  `tmpfs-guard-install.md` (enable-linger) — conditional per UC5
- [x] 3.7 Residue probe + `specs/feat-tmp-scratch-reclamation/measurements.md`
- [x] 3.8 ADR-249 (provisional) via `soleur:architecture` + ADR-133 amendment
  + #7004 acceptance-status note

## Testing & Verification

- [x] 4.1 `bash tests/test-tmp-purge.sh`, `scripts/tmpfs-guard.test.sh`,
  `tests/test-scratch-session.sh` all green
- [x] 4.2 `git grep` census of test surfaces asserting on
  `tmpfs-guard`/`worktree-manager`/`scratch-root` enumerated here (orphan
  suites don't ride the touched-file set — AC8)
- [x] 4.3 `test-all.sh` green; markdownlint clean on all artifacts
- [ ] 4.4 Post-merge (operator): dry-run review → `--apply` → measurements.md →
  `--drain`/TTL drain verification
