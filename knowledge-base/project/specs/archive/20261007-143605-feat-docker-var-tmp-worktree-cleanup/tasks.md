# Tasks: worktree cleanup — Docker builder cache and /var/tmp scratch drain (#9677)

Plan: `knowledge-base/project/plans/2026-10-07-chore-worktree-cleanup-docker-cache-and-scratch-drain-plan.md`
Decisions: drain is opt-in (`SOLEUR_QUARANTINE_DRAIN=1`); single PR; Docker prune kept (opt-in, builder cache + dangling only).

## Phase 1: RED tests first

- 1.1 Create `tests/scripts/test-cleanup-merged-space.sh` with PATH shims for `docker`, `findmnt`, `df` and a fixture snapper config (env seam `SOLEUR_SNAPPER_CONFIG_DIR`); register it in `scripts/test-all.sh` beside `tests/scripts/scratch-session`.
  - 1.1.1 T4–T7 Docker scenarios (exact call log, no `-a`/volume/container/system, skip reasons, verbatim `Total:` and `Total reclaimed space:` lines).
  - 1.1.2 T8–T10 space report (btrfs+snapper vs ext4, no `snapper` call, `space-report` read-only).
  - 1.1.3 T15 lock-contended run still prints one `SOLEUR_CLEANUP_SPACE`.
- 1.2 Extend `tests/scripts/test-scratch-session.sh` (reuse its `sweep()` harness): T1/T1b/T12 (fixture script tree with a wrapper classifier that sleeps in `tc_build_inuse_map`), T2/T2b/T2c/T3 (per-class TTLs, TTL floor, restore-after-drain, opt-in), T14 (drain inside the lock window).
- 1.3 Add T13 to the gdboot suite check: zero new `/var/tmp/gdboot.*` after a passing and a forced-failing run.
- 1.4 Run the new tests and confirm each is RED for the right reason; record the mutation rows (T11) as a checklist in the test file header.

## Phase 2: Sweep fixes

- 2.1 `worktree-manager.sh` `sweep_orphan_scratch_dirs`: rebase `deadline` inside the `map_tried == 0` block; emit `map_s`.
- 2.2 `tmp-classify.sh` `tc_drain_quarantine`: optional trailing absolute-epoch deadline, entry cap; keep `TC_DRAINED` per-call semantics; confirm `tmpfs-guard.sh:944` and `soleur-tmp-purge.sh:161` unchanged.
- 2.3 Sweep: opt-in drain (`SOLEUR_QUARANTINE_DRAIN=1`) before `exec {sweep_fd}>&-`; TTL env with 1440-min floor; sum `drained`/`drained_bytes` per base (`du -sk` × 1024, `x=$((x + n))`); extend the `SOLEUR_TMP_SWEEP` line; keep the "holds entries" note when the drain did not run.
- 2.4 Guard every new call (`|| headless_or_stderr warn`, `rc=0; … || rc=$?`).

## Phase 3: Effective-space report

- 3.1 Wrap `cleanup_merged_worktrees`: `space_begin`, inner function (keeps its RETURN trap), then Docker and report after the lock is released; export the removal count from the `cleaned` array.
- 3.2 `report_cleanup_space` + `space-report` subcommand: portable `df -Pk <first scratch base>`, signed delta, `findmnt` when present, read-only snapper config check, hint line; `logical_bytes` = drained bytes only.

## Phase 4: Docker builder cache (opt-in)

- 4.1 `docker_builder_prune`: values `1` (dry-run, upper bound) and `apply`; invalid value, no timeout/gtimeout, no docker, daemon unreachable, timeout, no worktree removed → named skip; only `builder prune -f --filter until=24h` and `image prune -f --filter until=24h`; echo Docker's own totals verbatim.

## Phase 5: Producer fix

- 5.1 `tests/scripts/test-git-data-boot-signal-poll.sh`: `export TMPDIR="$SANDBOX"` right after the existing trap; run the suite twice and count `/var/tmp/gdboot.*`.

## Phase 6: Docs and architecture

- 6.1 `soleur:architecture` — amend ADR-250 (Amendment 2: opt-in session-start drain, timebox excludes map build, lock window, TTL floors, Docker regenerable-cache carve-out, qualify the three superseded statements).
- 6.2 `model.c4` plugin description: one sentence for the user-machine delete/prune surface; let `c4-model-regenerate` refresh `model.likec4.json`; run `c4-code-syntax`, `c4-render`, `c4-count-parity`.
- 6.3 Update `tmpfs-guard-install.md` (session-start drain alternative, checkout-path drop-in text) and `git-worktree/SKILL.md` (one table: `SOLEUR_QUARANTINE_DRAIN`, `SOLEUR_DOCKER_PRUNE`, markers, snapper limits).
- 6.4 Run `soleur:architecture assess` (NFR register) and record it in the PR.

## Phase 7: Verification and operator host (post-merge, agent-run)

- 7.1 Run `lint-orphan-test-suites.sh`; execute the declared `space-report` probe in the Check 10 sandbox; markdownlint plan + tasks.
- 7.2 After merge: install `tmpfs-guard.timer` on the operator host via a `systemctl --user edit` drop-in pointing at the main checkout, `daemon-reload`, `enable --now`, verify with `systemctl --user list-timers tmpfs-guard.timer`.
- 7.3 PR body: root-cause table with commands (map 12.7 s vs 10 s timebox; 68/71 age-gate; quarantine undrained; `gdboot.*` leak), the "rebase widens quarantine scope" statement, `Closes #9677`.
