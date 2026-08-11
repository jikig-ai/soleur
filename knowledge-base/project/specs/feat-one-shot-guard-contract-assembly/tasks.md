# Tasks — Guard Contract at plan time, class-scoped fixes, structural enumeration

Plan: `knowledge-base/project/plans/2026-08-11-feat-guard-contract-assembly-and-pipeline-friction-plan.md`
Branch: `feat-one-shot-guard-contract-assembly`
PR: #7438
Closes: #5095, #5097

Scope decided at plan time: **A–D + F ship here; E splits to its own issue.** Reasoning is recorded
in the plan's Scope Decision section.

## Phase 0 — Preconditions

- [ ] 0.1 Export `TMPDIR=/var/tmp` for every command in the session.
- [ ] 0.2 Detect sibling `test-all.sh` runs by resolving `/proc/<pid>/cwd` (never by process name —
      a bash script's process name is `bash`). Shard with `TEST_GROUP=bun|scripts` if one is active.
- [ ] 0.3 Capture a green unmutated control run before any mutation work.
- [ ] 0.4 Confirm the git HTTPS redirect is still in place (SSH to github.com is blocked on this
      machine, ports 22 and 443). Do not "restore" the SSH remote.

## Phase 1 — (A) Guard Contract in `/plan`

- [ ] 1.1 Add `### 2.12. Guard Contract Gate` to `plugins/soleur/skills/plan/SKILL.md`, after the
      Encryption Posture Gate.
- [ ] 1.2 Encode the three required fields: property (one sentence), ASSEMBLY (every contributing
      code path / array / file), mutation matrix (>= 3 edits that MUST go RED).
- [ ] 1.3 State the load-bearing distinction in both homes: **members drift, assembly is
      structural**. An assembly enumerated as current members is not an assembly.
- [ ] 1.4 Add the `## Guard Contract` template to
      `plugins/soleur/skills/plan/references/plan-issue-templates.md`.

## Phase 2 — (A cont.) deepen-plan verification

- [ ] 2.1 Add `### 4.11. Guard Contract Halt (Conditional)` to
      `plugins/soleur/skills/deepen-plan/SKILL.md`, mirroring the 4.6 / 4.10 halt pattern.
- [ ] 2.2 Validate per guard entry: non-empty ASSEMBLY, mutation matrix with >= 3 rows.
- [ ] 2.3 Halt message carries a copy-pasteable remedy.

## Phase 3 — (D) `lint-guard-contract.py` — RED first

- [ ] 3.1 Write `scripts/lint-guard-contract.test.sh` with fixtures for all five mutation rows.
- [ ] 3.2 Confirm RED before implementing.
- [ ] 3.3 Implement `scripts/lint-guard-contract.py`.
- [ ] 3.4 Enumerate plans by directory walk over `knowledge-base/project/plans/*.md`
      (non-recursive — `archive/` excluded by construction).
- [ ] 3.5 Quantify over EVERY `### Guard N —` subsection, not the first.
- [ ] 3.6 Print a checked-count and fail when it is zero (anti-vacuity floor on its own dispatch).
- [ ] 3.7 Wire `run_suite` into `scripts/test-all.sh`.
- [ ] 3.8 Mutation-prove rows 1-5 on sandbox copies under `/var/tmp`; prove each landed with
      `diff -q` against a pristine backup, never against HEAD.

## Phase 4 — (D cont.) `lint-window-closure-assertion.py` — RED first

- [ ] 4.1 Write `scripts/lint-window-closure-assertion.test.sh` covering all five mutation rows.
- [ ] 4.2 Confirm RED before implementing.
- [ ] 4.3 Implement `scripts/lint-window-closure-assertion.py`.
- [ ] 4.4 Enumerate by directory walk over BOTH test roots (`apps/web-platform/`,
      `plugins/soleur/test/`) — a walk, not a glob list.
- [ ] 4.5 Quantify over EVERY `*Window` / `*Region` / `*Section` helper per file, not the first.
- [ ] 4.6 Encode the grandfather allowlist measured at plan time (7 helpers, 5 files) as an explicit
      enumerated list, not a pattern.
- [ ] 4.7 Wire `run_suite` into `scripts/test-all.sh`.
- [ ] 4.8 Mutation-prove rows 1-5 (including the relocation row, which pins the walk).

## Phase 5 — (B) `/work` class-scoped fixes

- [ ] 5.1 Add to `plugins/soleur/skills/work/SKILL.md` Phase 2: when a finding says "X can be added
      at site A", enumerate all sites {A,B,C} reaching the same sink BEFORE writing the fix.
- [ ] 5.2 Require recording the enumeration AND the method that produced it.
- [ ] 5.3 State the measured failure: the `/home` re-bind was fixed inside the array and validated
      four ways while three further entry points existed outside it. A mutation protocol validates a
      fix; it never tells you the fix's population is right.

## Phase 6 — (C) `/review` structural-enumeration seat

- [ ] 6.1 Add a conditional agent seat to `plugins/soleur/skills/review/SKILL.md` for guard-shaped
      PRs: one seat spent on STRUCTURAL ENUMERATION.
- [ ] 6.2 Phrase the seat's task as "enumerate every path by which a mount, token, or write reaches
      the sink" rather than "find defects".
- [ ] 6.3 Record the tell: N agents independently finding N instances of one structural gap means the
      seat allocation was wrong, not that the panel worked.
- [ ] 6.4 Keep it CONDITIONAL — the always-on count stays 8, so the C4 `review` component description
      is not falsified.

## Phase 7 — (D cont.) `/review` bullet

- [ ] 7.1 Add the closure-assertion bullet to the Defect Classes section.
- [ ] 7.2 Cross-reference the lint by content anchor so prose and gate cite each other rather than
      restating each other.

## Phase 8 — (F) rename-guard source-allowlist exemption

- [ ] 8.1 Extend the rename-guard test with all five mutation rows; confirm RED first.
- [ ] 8.2 Edit `apps/web-platform/scripts/rename-guard.sh`: a rename is a violation only when the
      TARGET matches `ALLOW_RES` and the SOURCE does not.
- [ ] 8.3 Test source and target against the SAME `ALLOW_RES` array — two separately-derived sets
      would be two assemblies and could drift.
- [ ] 8.4 Leave both existing override paths (label, trailer) and the parser-failure / empty-allowlist
      early exits untouched.
- [ ] 8.5 Mutation-prove rows 1-5, especially row 3 (deleting the source check must revert row 2 to
      exit 1) and row 4 (differing regex sets must still fail row 1).
- [ ] 8.6 Add a one-line pointer in `plugins/soleur/skills/compound/SKILL.md` and
      `plugins/soleur/skills/archive-kb/SKILL.md`: archival renames are exempt by construction and
      need no label.
- [ ] 8.7 Document the exemption in
      `knowledge-base/engineering/operations/secret-scanning.md`.

## Phase 9 — (E) file the split issue

- [ ] 9.1 File the ADR-ordinal-allocation-at-ship issue with the full design sketch.
- [ ] 9.2 Record: `ADR-NEXT` placeholder at plan time; ship assigns max+1 across ALL `origin/*` refs
      (never a presence check against `main`); ship sweeps every reference across code, plans, specs
      and ACs; the sweep needs its own Guard Contract because its failure mode is a narrow window.
- [ ] 9.3 Record the issue number in the PR body.

## Phase 10 — ADR

- [ ] 10.1 Author the ADR: Guard Contract as a plan-time deliverable.
- [ ] 10.2 Re-derive the ordinal across every `origin/*` ref immediately before merge (max on `main`
      was 176 at plan time; the ordinal is provisional).
- [ ] 10.3 If the ordinal moves, sweep this plan, this tasks file, and every AC naming it in the same
      edit.

## Phase 11 — Gates

- [ ] 11.1 `bun test plugins/soleur/test/components.test.ts`
- [ ] 11.2 `python3 scripts/lint-agents-rule-budget.py AGENTS.md AGENTS.rules.md` — no worse tier
      (this PR adds zero rule bodies).
- [ ] 11.3 `bash scripts/check-adr-ordinals.sh`
- [ ] 11.4 `bash scripts/test-all.sh` — read the preamble and epilogue banners, not the exit code
      alone; confirm no `SIBLING_RUN_DETECTED`.
- [ ] 11.5 `git grep -ln "secret-scan-allow-rename" -- plugins/soleur/skills/` returns >= 1 hit
      (#5097's own close criterion).
- [ ] 11.6 Confirm this plan's own `## Guard Contract` passes `scripts/lint-guard-contract.py`.
