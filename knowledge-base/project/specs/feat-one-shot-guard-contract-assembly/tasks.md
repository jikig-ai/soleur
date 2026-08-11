# Tasks — Guard Contract at plan time, class-scoped fixes, structural enumeration

Plan: `knowledge-base/project/plans/2026-08-11-feat-guard-contract-assembly-and-pipeline-friction-plan.md`
Branch: `feat-one-shot-guard-contract-assembly`
PR: #7438
Closes: #5095, #5097

Scope decided at plan time: **A–D + F ship here; E splits to its own issue.** Reasoning is recorded
in the plan's Scope Decision section.

## Phase 0 — Preconditions

- [x] 0.1 Export `TMPDIR=/var/tmp` for every command in the session.
- [x] 0.2 Detect sibling `test-all.sh` runs by resolving `/proc/<pid>/cwd` (never by process name —
      a bash script's process name is `bash`). Shard with `TEST_GROUP=bun|scripts` if one is active.
- [x] 0.3 Capture a green unmutated control run before any mutation work.
- [x] 0.4 Confirm the git HTTPS redirect is still in place (SSH to github.com is blocked on this
      machine, ports 22 and 443). Do not "restore" the SSH remote.

## Phase 1 — (A) Guard Contract in `/plan`

- [x] 1.1 Add `### 2.12. Guard Contract Gate` to `plugins/soleur/skills/plan/SKILL.md`, after the
      Encryption Posture Gate.
- [x] 1.2 Encode the three required fields: property (one sentence), ASSEMBLY (every contributing
      code path / array / file), mutation matrix (>= 3 edits that MUST go RED).
- [x] 1.3 State the load-bearing distinction in both homes: **members drift, assembly is
      structural**. An assembly enumerated as current members is not an assembly.
- [x] 1.4 Add the `## Guard Contract` template to
      `plugins/soleur/skills/plan/references/plan-issue-templates.md`.

## Phase 2 — (A cont.) deepen-plan verification

- [x] 2.1 Add `### 4.11. Guard Contract Halt (Conditional)` to
      `plugins/soleur/skills/deepen-plan/SKILL.md`, mirroring the 4.6 / 4.10 halt pattern.
- [x] 2.2 Validate per guard entry: non-empty ASSEMBLY, mutation matrix with >= 3 rows.
- [x] 2.3 Halt message carries a copy-pasteable remedy.

## Phase 3 — (D) `lint-guard-contract.py` — RED first

- [x] 3.1 Write `scripts/lint-guard-contract.test.sh` with fixtures for all five mutation rows.
- [x] 3.2 Confirm RED before implementing.
- [x] 3.3 Implement `scripts/lint-guard-contract.py`.
- [x] 3.4 Enumerate plans by directory walk over `knowledge-base/project/plans/*.md`
      (non-recursive — `archive/` excluded by construction).
- [x] 3.5 Quantify over EVERY `### Guard N —` subsection, not the first.
- [x] 3.6 Print a checked-count and fail when it is zero (anti-vacuity floor on its own dispatch).
- [x] 3.7 Wire `run_suite` into `scripts/test-all.sh`.
- [x] 3.8 Mutation-prove rows 1-5 on sandbox copies under `/var/tmp`; prove each landed with
      `diff -q` against a pristine backup, never against HEAD.

## Phase 4 — (D cont.) `lint-window-closure-assertion.py` — RED first

- [x] 4.1 Write `scripts/lint-window-closure-assertion.test.sh` covering all five mutation rows.
- [x] 4.2 Confirm RED before implementing.
- [x] 4.3 Implement `scripts/lint-window-closure-assertion.py`.
- [x] 4.4 Enumerate by directory walk over BOTH test roots (`apps/web-platform/`,
      `plugins/soleur/test/`) — a walk, not a glob list.
- [x] 4.5 Quantify over EVERY `*Window` / `*Region` / `*Section` helper per file, not the first.
- [x] 4.6 Encode the grandfather allowlist as an explicit enumerated list, not a pattern.
      CORRECTED at implementation time: the population is **7 helpers across 3 files**, not the 5
      files the looser plan-time probe suggested. Six are allowlisted; `sandboxWindow` — the
      originating defect — instead carries a real `// window-assembly:` declaration.
- [x] 4.7 Wire `run_suite` into `scripts/test-all.sh`.
- [x] 4.8 Mutation-prove rows 1-5 (including the relocation row, which pins the walk).

## Phase 5 — (B) `/work` class-scoped fixes

- [x] 5.1 Add to `plugins/soleur/skills/work/SKILL.md` Phase 2: when a finding says "X can be added
      at site A", enumerate all sites {A,B,C} reaching the same sink BEFORE writing the fix.
- [x] 5.2 Require recording the enumeration AND the method that produced it.
- [x] 5.3 State the measured failure: the `/home` re-bind was fixed inside the array and validated
      four ways while three further entry points existed outside it. A mutation protocol validates a
      fix; it never tells you the fix's population is right.

## Phase 6 — (C) `/review` structural-enumeration seat

- [x] 6.1 Add a conditional agent seat to `plugins/soleur/skills/review/SKILL.md` for guard-shaped
      PRs: one seat spent on STRUCTURAL ENUMERATION.
- [x] 6.2 Phrase the seat's task as "enumerate every path by which a mount, token, or write reaches
      the sink" rather than "find defects".
- [x] 6.3 Record the tell: N agents independently finding N instances of one structural gap means the
      seat allocation was wrong, not that the panel worked.
- [x] 6.4 Keep it CONDITIONAL — the always-on count stays 8, so the C4 `review` component description
      is not falsified.

## Phase 7 — (D cont.) `/review` bullet

- [x] 7.1 Add the closure-assertion bullet to the Defect Classes section.
- [x] 7.2 Cross-reference the lint by content anchor so prose and gate cite each other rather than
      restating each other.

## Phase 8 — (F) rename-guard source-allowlist exemption

- [x] 8.1 Extend the rename-guard test with all five mutation rows; confirm RED first.
- [x] 8.2 Edit `apps/web-platform/scripts/rename-guard.sh`: a rename is a violation only when the
      TARGET matches `ALLOW_RES` and the SOURCE does not.
- [x] 8.3 Test source and target against the SAME `ALLOW_RES` array — two separately-derived sets
      would be two assemblies and could drift.
- [x] 8.4 Leave both existing override paths (label, trailer) and the parser-failure / empty-allowlist
      early exits untouched.
- [x] 8.5 Mutation-prove rows 1-5, especially row 3 (deleting the source check must revert row 2 to
      exit 1) and row 4 (differing regex sets must still fail row 1).
- [x] 8.6 Add a one-line pointer in `plugins/soleur/skills/compound/SKILL.md` and
      `plugins/soleur/skills/archive-kb/SKILL.md`: archival renames are exempt by construction and
      need no label.
- [x] 8.7 Document the exemption in
      `knowledge-base/engineering/operations/secret-scanning.md`.

## Phase 9 — (E) file the split issue

- [x] 9.1 File the ADR-ordinal-allocation-at-ship issue with the full design sketch.
- [x] 9.2 Record: `ADR-NEXT` placeholder at plan time; ship assigns max+1 across ALL `origin/*` refs
      (never a presence check against `main`); ship sweeps every reference across code, plans, specs
      and ACs; the sweep needs its own Guard Contract because its failure mode is a narrow window.
- [x] 9.3 Record the issue number in the PR body.

## Phase 10 — ADR

- [x] 10.1 Author the ADR: Guard Contract as a plan-time deliverable.
- [x] 10.2 Re-derive the ordinal across every `origin/*` ref immediately before merge (max on `main`
      was 176 at plan time; the ordinal is provisional).
- [x] 10.3 If the ordinal moves, sweep this plan, this tasks file, and every AC naming it in the same
      edit.

## Phase 11 — Gates

- [x] 11.1 `bun test plugins/soleur/test/components.test.ts`
- [x] 11.2 `python3 scripts/lint-agents-rule-budget.py AGENTS.md AGENTS.rules.md` — no worse tier
      (this PR adds zero rule bodies).
- [x] 11.3 `bash scripts/check-adr-ordinals.sh`
- [x] 11.4 `bash scripts/test-all.sh` — preamble and epilogue banners read, not the exit code alone.
      `SIBLING_RUN_DETECTED` and `LOW_TMP_HEADROOM` BOTH fired and rc was 1 (291/293). This is NOT
      a clean green: the two failures were attributed to contention via the three required
      confirmations recorded below, not dismissed. Task 0.2's precondition (no siblings) could not
      be met — the box ran 3-4 concurrent suites throughout.
- [x] 11.5 `git grep -ln "secret-scan-allow-rename" -- plugins/soleur/skills/` returns >= 1 hit
      (#5097's own close criterion).
- [x] 11.6 Confirm this plan's own `## Guard Contract` passes `scripts/lint-guard-contract.py`.

## Verified gate results (2026-08-11)

- `bun test plugins/soleur/test/components.test.ts` — **1297 pass / 0 fail**.
- `python3 scripts/lint-agents-rule-budget.py AGENTS.md AGENTS.rules.md` — `B_ALWAYS=44478`,
  byte-identical to the pre-change baseline. This PR adds zero `AGENTS.*` rule bodies.
- `bash scripts/check-adr-ordinals.sh` — pass. ADR-178 chosen by re-deriving max+1 across all 64
  `origin/*` refs: `origin/main` reported 176 while a pushed branch already held 177.
- `bash scripts/lint-orphan-test-suites.sh` — `orphan test suites: none` (all three new suites wired).
- `bash scripts/test-all.sh` — **rc=1, `=== 291/293 suites passed ===`**. Both failures confirmed as
  sibling contention, NOT regressions, via the three required confirmations:
  - **Isolated re-run:** `tests/scripts/zot-inventory` → 146 passed / 0 failed, exit 0. The 8
    `apps/web-platform` files → 7 pass in a batch, `ws-abort.test.ts` passes alone (3/3, exit 0);
    it had failed as a WHOLE FILE (collection/timeout), never on an assertion.
  - **Matching CI gate:** `ci.yml` on `main` is `success`.
  - **Structural:** the diff touches zero files under `apps/web-platform/{app,components,server,lib,test}/`
    — the only `apps/web-platform` path is `scripts/rename-guard.sh`, a standalone bash script no
    vitest suite imports. Those tests cannot reach anything this PR changed.
  - Run conditions, from the runner's own preamble: `SIBLING_RUN_DETECTED` (3 other worktrees) and
    `LOW_TMP_HEADROOM` (764MB against a 1024MB floor). `zot-inventory` self-diagnosed:
    `SETUP FAIL — could not bind 127.0.0.1:5000 … Address already in use`.
  - Epilogue: `apps/web-platform/infra/ is NOT covered above (diff does not touch it)` — correct;
    the diff changes `apps/web-platform/scripts/`, not `infra/`.
- New suites, green inside that same run: `scripts/lint-guard-contract` 14/14,
  `scripts/lint-window-closure-assertion` 13/13, `scripts/rename-guard` 8/8.
- `git grep -ln "secret-scan-allow-rename" -- plugins/soleur/skills/` → 2 hits
  (`compound/SKILL.md`, `archive-kb/SKILL.md`), satisfying #5097's own event-grep close criterion.
- `python3 scripts/lint-guard-contract.py` over the real tree — 1533 plans scanned, 1 with a Guard
  Contract (this one), 3 guard entries, exit 0 (AC10).
