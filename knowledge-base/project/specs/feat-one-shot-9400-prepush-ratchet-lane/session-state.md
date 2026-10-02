# Session State

## Plan Phase
- Plan file: /data/git-repositories/jikig-ai/soleur/.worktrees/feat-one-shot-9400-prepush-ratchet-lane/knowledge-base/project/plans/2026-10-01-chore-affected-ratchets-pre-push-lane-plan.md
- Status: complete

### Errors
- No subagent/Task capability in the planning environment: plan research fan-out, plan-review panel, advisor consult, and deepen-plan Phase 2-6 agent fan-outs ran inline instead. Deepen-plan mechanical halt gates (4.6-4.11) executed for real and passed. Parent may run `soleur:plan-review` if panel review is wanted before `soleur:work`.
- `gh pr view --json merged` once errored on an invalid field name (used `state`/`closed`/`mergedAt` instead).

### Decisions
- Scratch-worktree merge, not in-place: the lane materializes branch+`origin/main` via `git worktree add --detach` + in-scratch `git merge`; mutating the operator's branch from a hook was rejected.
- Two-tier member set: seconds-scale fast tier (highwater family, plugin-root-anchor-debt, fixture-scan suites, skill-body-budget, rule-bodies) always runs; `test-affected-kb-consumers` demoted to a three-trigger conditional tier (~4-11 min selection walk, measured `--print-selection` at 4m17s) to reconcile the 1-2 min budget with the acceptance criterion. A third "branch-touched suite" tier runs diff-modified `*.test.sh` files in a disk-backed-TMPDIR scratch, reproducing the vitest-absent and tmpfs-vs-ext4 CI classes.
- New standalone script `scripts/pre-push-ratchet-lane.sh` wired into `lefthook.yml` `pre-push:` and as stage 1 of `scripts/hooks/pre-push` — deliberately not a `test-all.sh` mode flag.
- Gates discharged: User-Brand `none`, Guard Contract 11-row mutation matrix mapping the five #9339 failures to RED rows, Observability block with `--print-members` Check-10-safe probe, ADR-242 amendment in scope, C4 "no impact" via three-file enumeration, code-review overlap checked (#8659, #7942, #8800 acknowledged, no fold-ins).
- Deepen corrections: grok-pre-push-gate's existing fetch+merge-base-lint noted, `SSH_ASKPASS` added to env scrub, `GIT_LOCATION_VARS` six-site parity, `timeout`->`gtimeout` portability, shard-manifest regen task, member-parity and exit-code-verification suite requirements.

### Components Invoked
- `soleur:plan` (Phases 0 -> 0.5 -> 0.6/0.6b/0.6c -> 0.7 skeleton -> 1 research inline -> 1.7.5 code-review overlap -> 1.8 -> 2 structure -> 2.5 domain review -> 2.6 user-brand -> 2.9 observability -> 2.10 ADR -> 2.12 guard contract -> 6.5 sharp-edges -> tasks.md)
- `soleur:deepen-plan` (halt gates 4.6-4.11 executed mechanically, all pass; precedent-diff + verify-the-negative passes inline)
- No agents/commands spawnable; no commits made (pipeline lead commits).

## Work Phase — Session 2 (inline Tier C)

### Phase 0 measurements (recorded)
- Member exit semantics verified on the real tree: all fast-tier members exit 0
  green on this branch; `lint-trap-tempfile-ownership.py --check-highwater`
  prints a ratchet-maintenance note at rc=0 (highwater 71 vs population 70).
- `.highwater` consumers enumerated: `lint-trap-tempfile-ownership` (shell+tspy),
  `lint-supabase-deprecated-endpoints`, `lint-diagnosis-claims`,
  `alarm-issue-filing-guard`, `lint-workflow-step-env-refs`. Canonical argv in
  the lane member table; parity asserted by the suite.
- F5 identity: `tests/scripts/test-tmp-purge.sh` Reaper-3 keep-hash arm (fixed
  `bbaaf27468`): pre-fix whole-quarantine-root hash moves on a non-tmpfs base
  because the control root is quarantine-moved INTO it — locally invisible on
  tmpfs (deletes instead of moves).
- `git worktree add --detach` + in-scratch `git merge` round-trip: ~1-3 s on
  this host; negligible vs the member budget.

### As-built deltas vs plan
- `lanE_TMP` is the scratch's SIBLING (`$PARENT/lane-tmp`), NOT inside the
  worktree — a member mktemp root inside the scratch resolves `git rev-parse`
  to the lane's repo and breaks non-repository probes (measured:
  fixture-dir-operand-assert lost 2/71 assertions).
- Branch tier excludes `scripts/test-all.sh` and `*/lib/*` — basename
  `test-*.sh` matches the runner and the declarations lib; the dogfood caught
  test-all's rc=4 refusal reading as a member RED.
- Members and the branch tier both get the disk-backed TMPDIR pin; only the
  branch tier additionally gets `env -i` with the minimal allowlist.
- `env -i` strips `CI`, so AC-F4's pre-fix leaf (which keys on `CI`) was driven
  through the members-file seam with `env CI=1` — reproducing the CI shard's
  env shape (CI set + vitest absent + non-tmpfs TMPDIR). Branch-tier copy
  passed, member copy red — the class boundary demonstrated.

### AC drives (throwaway `ac-9400` worktree off origin/main, lane = this branch's script)
- AC-F1 revert 21c2efa184 → `member=lint-trap-tempfile-ownership tier=fast
  verdict=RED`, lane exit 1 in 84 s. PASS.
- AC-F2 revert 61c5105a25 → conditional member `test-affected-kb-consumers`
  fired (declared-input moved) and RED (10/12), lane exit 1 in 557 s. PASS.
- AC-F3 injected `CLAUDE_PLUGIN_ROOT:` token → `plugin-root-anchor-debt` RED
  (anchor-debt-files=1); bonus: `skill-body-budget` RED (+2 B over work ceiling
  — the injected line itself). Lane exit 1 in 528 s. PASS.
- AC-F4 pre-bbaaf27468 vitest leaf + `env CI=1` member → RED "FAILED: 2/129"
  (vitest absent + CI set); env -i branch-tier copy PASS (CI scrubbed). 37 s.
- AC-F5 pre-bbaaf27468 Reaper-3 whole-root hash → `test-tmp-purge` RED
  (111/112) under the lane's disk-backed TMPDIR, BOTH as a member and in the
  env -i branch tier. 26 s.
- AC worktree + branch removed after drives; no scratch residue.

### Errors during work
- Suite self-caught: `${!LEFTHOOK_@}` prefix sweep missed bare `LEFTHOOK` (the
  underscore belongs to the family suffix, not the name) — arm 12 caught it.
- Dogfood caught: unguarded operand sites (fixture-scan), one-hop kb baseline
  rows needed (+2), runner/lib misclassified as branch-tier suites, TMPDIR pin
  inside the worktree contaminating fixture repo probes. All fixed, suite green
  64/64, scanners clean.

### Timing
- Fast tier wall clock: ~1.5 min (members 78 s + fetch/scratch/merge ~6 s).
- With conditional member firing: ~9-11 min (kb-consumers ~7-11 min member).
