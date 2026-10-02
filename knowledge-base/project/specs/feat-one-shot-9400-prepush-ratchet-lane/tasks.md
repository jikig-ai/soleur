# Tasks — chore(ci): fast affected-ratchets pre-push lane (#9400)

Plan: `knowledge-base/project/plans/2026-10-01-chore-affected-ratchets-pre-push-lane-plan.md`
Branch: `feat-one-shot-9400-prepush-ratchet-lane`

## Phase 0 — Verify premises (cheap, before building)

- [x] 0.1 Confirm each member invocation's real exit-code semantics by running
      it once against the current tree:
      `python3 scripts/lint-trap-tempfile-ownership.py --check-highwater`,
      `bash scripts/lint-supabase-deprecated-endpoints.sh --check-highwater`,
      `bash scripts/plugin-root-anchor-debt.sh`,
      `bash plugins/soleur/test/fixture-relative-assert.test.sh` (+
      `-dir-operand-assert`, `-cd-containment`),
      `python3 scripts/lint-skill-body-budget.py --base "$(git merge-base origin/main HEAD)"`,
      `python3 scripts/lint-rule-bodies.py --check --base "$(git merge-base origin/main HEAD)"`.
- [x] 0.2 Enumerate the full `.highwater` consumer set
      (`grep -rln 'check-highwater\|\.highwater' scripts/`): trap-tempfile
      (shell + tspy), lint-supabase-deprecated-endpoints,
      lint-diagnosis-claims, alarm-issue-filing-guard,
      lint-workflow-step-env-refs — record each one's canonical argv in the
      lane member table.
- [x] 0.3 Confirm the F5 pre-fix identity: read #9339 CI logs / the fix
      commits around `bbaaf27468`, `de9fa5e643`, `917a823d62` and name the
      exact tmpfs-vs-ext4-sensitive suite + arm.
- [x] 0.4 Time a bare `git worktree add --detach` + `git merge origin/main`
      round-trip on the dev host to sanity-check the budget claim.

## Phase 1 — Lane script + its suite

- [x] 1.1 Write `scripts/pre-push-ratchet-lane.sh`:
      git-location-family `unset` first (canonical list =
      `GIT_LOCATION_VARS`, `plugins/soleur/test/lib/git-fixture-env.ts`, plus
      `SSH_ASKPASS`);
      `--print-members` pure-print arm; fetch (bounded, repo
      `timeout`→`gtimeout`→bare pattern); scratch `git worktree add --detach`;
      in-scratch `git merge --no-edit origin/main`; fast tier always;
      branch-touched tier (`git diff --name-only <base>...HEAD`, `*.test.sh`,
      cap ~12, per-member timeout, deps-free scratch env = vitest-absent,
      TMPDIR pinned disk-backed, `CI`/`GITHUB_*`/`LEFTHOOK*` scrubbed);
      conditional tier (`test-affected-kb-consumers`) on the three triggers in
      the plan; per-member receipt + `RATCHET_LANE verdict=` final line;
      `trap` cleanup + exit-site table honored; exit 0/1/2 contract.
- [x] 1.2 Write `scripts/pre-push-ratchet-lane.test.sh` implementing the Guard
      Contract mutation matrix (11 rows incl. dispatch-vacuity, second-member,
      reorder, harness must-PASS rows) over fixture repos/worktrees.
- [x] 1.3 Member-parity assertion inside the suite: lane member argv ==
      registered argv (run_suite lines / CI steps).
- [x] 1.4 Register the suite: `run_suite` in `scripts/test-all.sh` + declared
      edge set in `scripts/lib/test-affected-paths.sh`; run
      `bash scripts/lint-orphan-test-suites.sh`; regenerate
      `scripts/suite-shard-legs.tsv` via
      `python3 scripts/regenerate-shard-manifest.py --write` if assignment
      moves.

## Phase 2 — Wiring

- [x] 2.1 `lefthook.yml` `pre-push:`: add `ratchet-lane` entry
      (`run: bash scripts/pre-push-ratchet-lane.sh`, no glob, no
      `{push_files}`). Re-run `hook-git-env-coverage.test.sh` and
      `git-env-list-parity.test.sh` — both enumerate this surface.
- [x] 2.2 `scripts/hooks/pre-push`: run the lane after the existing skip
      checks and before the `exec ... --affected` line; preserve the
      existing unset block.
- [x] 2.3 Docs pointer (conditional): if
      `python3 scripts/lint-skill-body-budget.py --base "$(git merge-base origin/main HEAD)"`
      shows headroom, add a one-line pointer in `ship` or `work` SKILL.md;
      otherwise record the deferral and document in a runbook.

## Phase 3 — Acceptance verification + ADR

- [ ] 3.1 AC-F1: revert `21c2efa184` semantics on a throwaway branch → lane
      RED naming the highwater member.
- [ ] 3.2 AC-F2: revert `61c5105a25` on a branch touching a kb-reading suite →
      conditional tier fires, lane RED naming `test-affected-kb-consumers`.
- [ ] 3.3 AC-F3: inject an anchor-debt token into a `plugins/soleur/**/*.md`
      → lane RED naming `plugin-root-anchor-debt`.
- [ ] 3.4 AC-F4: un-gate the vitest leaf (pre-`bbaaf27468` semantics) on a
      branch touching `test-scratch-residue.sh` → lane RED in the deps-free
      scratch.
- [ ] 3.5 AC-F5: reproduce the tmpfs-vs-ext4 failure identified in 0.3, or
      record the evidence and amend the AC.
- [ ] 3.6 Assert non-mutation: `git rev-parse HEAD` + `git status --porcelain`
      identical before/after a lane run.
- [x] 3.7 Amend `ADR-242-…md` (`## Amendment — 2026-10-xx`): third local gate
      tier, curated members, merged-tree evaluation; ADR-183 reaffirmed.
- [ ] 3.8 Measure and record fast-tier wall time in the plan/PR (target
      ≤ ~2 min on a quiet host).
