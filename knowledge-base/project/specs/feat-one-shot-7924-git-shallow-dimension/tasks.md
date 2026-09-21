# Tasks: fix-repo-write-boundary-shallow-dimension

Plan: `knowledge-base/project/plans/2026-09-21-fix-repo-write-boundary-shallow-dimension-plan.md`
Issue: #7924

## Phase 1: Setup (red-first suite arms)

- [x] 1.1 In `scripts/lib/repo-write-boundary.test.sh`, update the manifest assertion
  (`config head refs worktree wt` → include `shallow`), the rendered-inspection
  anchor list, and the next-action loops + `_want` variable for the new dimension.
- [x] 1.2 Add the ~8 new arms: absent-stable (PASS), absent→present (FATAL),
  present→absent (FATAL), digest-change presence-same (FATAL), common-dir /
  linked-worktree isolation arm, `not-measured` → UNMEASURABLE arm, foreign-repo
  shallow write must-PASS row, and a rendered-prose arm.
- [x] 1.3 Raise `MIN_ASSERTIONS` (`:1208`) by the added arm count; keep
  `passes+fails == asserted` conservation green.
- [x] 1.4 Confirm the suite is red for the right reason (missing `shallow`
  dimension), not for a fixture regression.

## Phase 2: Core Implementation

- [x] 2.1 In `scripts/lib/repo-write-boundary.sh`, add private helper
  `_repo_boundary_dim_shallow`: resolve `git rev-parse --path-format=absolute
  --git-common-dir`; emit `not-measured` on resolution failure; `absent` when no
  `shallow` file; `present:<digest>` via `_repo_boundary_digest` over raw bytes
  when present.
- [x] 2.2 Append the `shallow` dimension line to `_repo_state`'s manifest body.
- [x] 2.3 Add the `shallow` arm to `repo_boundary_classify`: any delta → FATAL
  (no shared-store softening), `not-measured` → UNMEASURABLE, equal → pass.
- [x] 2.4 Update `_repo_boundary_dim_prose` and the not-inspected heredoc (keep
  the `objects/info/grafts` carve-out line); fix the two literal dimension-count
  comments (`:128`, `:692`) with phrasing that does not recount.
- [x] 2.5 `bash scripts/lib/repo-write-boundary.test.sh` exits 0 at the raised floor.

## Phase 3: Testing (offender fixes — the issue's gate)

- [x] 3.1 `apps/cla-evidence/scripts/ccla-add.sh`: scratch-clone ledger fallback
  (`git clone --depth=1 --no-tags --single-branch --branch cla-signatures
  <origin-url> <mktemp-dir>` → read `signatures/cla.json`), with a `TMP_DIRS`
  sibling cleanup registered on the existing trap contract.
- [x] 3.2 `apps/cla-evidence/test/ccla-add.test.sh`: same scratch-clone shape to
  populate `$WORK/ledger.json` (fed via `CCLA_ADD_LEDGER`).
- [x] 3.3 `apps/web-platform/test/cla-evidence/roster-entry-gate.test.ts`:
  `readRealLedger` fallback becomes an `execFileSync` scratch clone under
  `os.tmpdir()` + `readFileSync`, removed in `finally`; `cleanGitEnv()` kept.
- [x] 3.4 `scripts/plugin-delivery-canary.sh`: `materialize_reference` missing-sha
  fallback fetches + `git archive`s inside a repo under `$SCRATCH`; `cat-file -e`
  fast path stays pointed at the live `$root`.
- [x] 3.5 `scripts/plugin-delivery-canary.test.sh`: add an arm pinning the
  scratch-repo fetch/archive operand shape.
- [x] 3.6 Amend `knowledge-base/engineering/architecture/decisions/
  ADR-207-repo-write-boundary-harm-partition.md`: `shallow` joins the sampled
  set; a new "not softened" row records the unconditional-FATAL rationale.
- [x] 3.7 Re-run the **untruncated** shallow-write census and adjudicate every
  hit per AC14; run `python3 scripts/lint-guard-contract.py` and
  `bash plugins/soleur/test/c4-count-parity.test.sh`.
- [ ] 3.8 `TEST_GROUP=scripts bash scripts/test-all.sh` exits 0 with no `[FATAL]`
  boundary block (AC11).
