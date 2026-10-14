---
title: "docs: salvage learnings and planning trail from orphaned feat-10117 draft PR"
type: chore
date: 2026-10-14
slug: docs-salvage-10117-artifacts
branch: feat-one-shot-salvage-10117-artifacts
issue: 10117
lane: cross-domain
domain: engineering
brand_survival_threshold: none
---

# docs: salvage learnings and planning trail from orphaned feat-10117 draft PR

## Enhancement Summary

**Deepened on:** 2026-10-14
**Sections enhanced:** 3 (Acceptance Criteria, Test Scenarios, Implementation Phases)
**Research agents used:** none — mechanical docs salvage; all verification executed inline (no Task tool in this harness). Every gate of `deepen-plan` §§4.5–4.12 was evaluated and passes (see below).

### Key Improvements

1. AC3 + its Test Scenario now diff `origin/main...HEAD` (three-dot, merge-base-scoped) so a sibling merge moving main cannot false-red the "only the appended bullet" assertion (sharp-edge #8616 class).
2. A case-sensitive anchor in the sibling-worktree probe was corrected to the paragraph's actual capitalization (`Sibling-worktree`), and the probe was executed against the live file (count = 1) — plan probes are run, not just cited (#9303 class).
3. Phase 3 gained the `mkdir -p` for the new `specs/archive/${TS}-feat-10117-edge-coverage-residuals/` directory (brainstorms/plans archive dirs already exist).

### New Considerations Discovered

- `deepen-plan` §4.7's pure-docs exemption excludes `.md` files under `plugins/*/skills/` — the two edited skill docs therefore DO require the `## Observability` block (present; all 5 fields validated: allowlisted `git` verb, no shell-active bytes, literal `expected_output`, <15 s).
- The branch's complete delta vs merge-base `943ebacc` is exactly the brief's copy list — nothing else is salvageable; the remaining diff hunks are main-side drift.

## Overview

The `feat-10117-edge-coverage-residuals` draft PR (#10190, OPEN/draft, updatedAt
2026-10-14T11:58:59Z) delivered its code through two merged PRs (#10237 and #10242,
both merged 2026-10-14) and will be closed unmerged once this salvage lands. Its
branch (`1219f7a0`, worktree `.worktrees/feat-10117-edge-coverage-residuals`) still
carries the documentation trail: five learnings absent from main, two single-bullet
additions to live skill files, and the brainstorm/plan/spec set for the finished
arc. This plan salvages that trail verbatim before the draft and its worktree are
torn down. A CTO-agent ruling on 2026-10-14 prescribed this exact hybrid-salvage
shape — it is not re-opened here (`decision-challenges.md` row 1).

Spec note: this branch has no `knowledge-base/project/specs/feat-one-shot-salvage-10117-artifacts/spec.md`,
so there is no spec-vs-codebase reconciliation to perform; `lane:` defaults
fail-closed to `cross-domain`.

## Research Insights

**Premise Validation (Phase 0.6, all verified live 2026-10-14):**

- Branch `feat-10117-edge-coverage-residuals` resolves to `1219f7a0d27a`; sibling
  worktree `.worktrees/feat-10117-edge-coverage-residuals` exists and is the copy
  source. It must stay alive until the salvage PR merges — it is both the `git
  show` source and the thing being cleaned up.
- Draft PR #10190 `OPEN`, `isDraft: true`, `updatedAt 2026-10-14T11:58:59Z`.
- Delivery PRs verified MERGED: `gh pr view 10237` → MERGED 2026-10-14T11:41:36Z
  ("fix(affected): --paths normalization + matchability census + root-corpus
  detection"); `gh pr view 10242` → MERGED 2026-10-14T11:53:47Z ("fix(kb-consumers):
  dir-ref coverage requires all tracked members matching"). Squash commits
  `b5f20098f6` / `4c35ff3340` are on `origin/main`.
- Issue 10117 CLOSED 2026-10-14T11:58:30Z ("review: edge-declaration coverage
  residuals…") — hence `Ref` prose only, never `Closes`/`Fixes`.
- All nine KB artifacts exist on the branch via `git cat-file -e`; none of the
  five learnings exists on `origin/main` (verified absent — not "anything already
  on main").
- `git diff --name-status <merge-base 943ebacc>..<branch>` confirms the branch's
  entire non-KB delta is exactly the two files the brief names:
  `plugins/soleur/skills/review/references/risk-tier-and-fix-rounds.md` and
  `plugins/soleur/skills/work/SKILL.md`. The KB `A`-set is exactly the nine files
  in the brief — the copy list is complete, nothing else is salvageable.
- Bullet positions verified by diff: the risk-tier bullet inserts between the
  `#6760` seat bullet ("A seat must never mutation-test the LIVE worktree…") and
  the PID-namespace bullet ("A brief that asks a seat… to flip a line inside a
  helper that sends signals or removes files…"), ~line 79. The work/SKILL.md
  bullet appends as the last line of the file (the sharp-edge list tail, after
  the `git commit rc` bullet). The branch's sibling-worktree paragraph variant is
  OLDER than main's (confirmed in the same diff) — excluded per the brief; the
  branch's two `work/SKILL.md` deletions (bullet `6.8`, the test-harness
  sharp-edges pointer) are also excluded — both bullets are live on main.
- `plugins/soleur/test/review-tier-parity.test.ts` exists and reads
  `skills/review/references/risk-tier-and-fix-rounds.md` — the named verification.
  `plugins/soleur/test/components.test.ts` covers SKILL.md files and is the
  likely affected-suite selector alongside it.

**Property List (Phase 0.6b):**

1. The five learnings exist on main at their canonical live paths, byte-identical
   to the branch versions (one frontmatter retarget excepted).
2. The two bullets exist in the live skill files at the named positions.
3. The four planning docs are preserved under archive paths at repo convention.
4. The orphaned draft PR gets a clean close-out trail (comment naming the salvage
   PR + the two delivery PRs), and its remote branch + sibling worktree are
   deleted only after merge lands.

**Cut List (Phase 0.6b):** none — the brief prescribes the mechanism verbatim and
no mechanism already on main covers "move content from an orphaned branch to
main". `archive-kb.sh` was considered and does not apply: it `git mv`s files
*within* a tree; the source files live on a different branch and must be
materialized via `git show <branch>:<path>` first (its `${ts}-$(basename)` naming
rule IS adopted — see decision-challenges row 2).

**Conventions applied:**

- Archive naming: `plugins/soleur/skills/archive-kb/scripts/archive-kb.sh` —
  `${ts}-$(basename "$artifact")`, timestamp `date +%Y%m%d-%H%M%S` generated ONCE
  per run (observed: `20261014-202522-2026-10-13-…-plan.md`; spec dirs become
  `archive/<ts>-<spec-dirname>/` with files keeping their names).
- PR shape: `wg-kb-artifacts-archived-in-pr` (archive lands in the same PR);
  `wg-use-closes-n-in-pr-body-not-title-to` (auto-close keywords out — here
  strengthened to `Ref`-only since issue 10117 is already closed);
  `hr-when-in-a-worktree-never-read-from-bare` (all `git show` reads go through
  the branch ref, never the bare root's working-tree files);
  `hr-never-git-stash-in-worktrees`.

**Learnings consulted:** none needed beyond the five being salvaged — the plan is
mechanical; the relevant guard-rails are the rules above plus the
bash-incremental-reads learning itself (do not edit a file a suite is executing —
applies if a battery is running during the port).

## User-Brand Impact

- **If this lands broken, the user experiences:** a missing or misplaced bullet
  inside `plugins/soleur/skills/` docs — an agent reads stale guidance on its
  next session; the blast radius is guidance quality, not a serving surface.
- **If this leaks, the user's [data / workflow / money] is exposed via:** nothing —
  the content is the repo's own internal documentation, already public to anyone
  with repo access and authored by our own sessions.
- **Brand-survival threshold:** `none`
- **Threshold decision (challengeable):** `threshold: none, reason: the diff is
  KB docs plus two skill-doc bullets; zero matches against the canonical
  SENSITIVE_PATH_RE (preflight Check 6 Step 6.1) — no credential, auth, data, or
  infra surface is touched.`

## Observability

```yaml
liveness_signal:
  what: "ported content present at the named anchors (content-anchored grep probes, Verification phase)"
  cadence: "per-run pre-merge; review-tier-parity pin runs on every PR touching the review skill"
  alert_target: "PR check failure"
  configured_in: "plugins/soleur/test/review-tier-parity.test.ts"
error_reporting:
  destination: "CI (bun test) + PR checks"
  fail_loud: "review-tier-parity.test.ts RED on seat-table drift; Verification-phase probes print empty/mismatched output when a port is missing or misplaced"
failure_modes:
  - mode: "bullet inserted at the wrong anchor or the frontmatter retarget missed"
    detection: "Verification-phase line-position + archive-path grep probes in Test Scenarios"
    alert_route: "work-phase FAIL, PR stays draft"
  - mode: "verbatim drift between branch source and landed copy"
    detection: "diff probes comparing landed files against `git show feat-10117-edge-coverage-residuals:<path>`"
    alert_route: "work-phase FAIL, PR stays draft"
logs:
  where: "salvage commit diff; PR checks log"
  retention: "PR history (indefinite)"
discoverability_test:
  command: "git grep -l 'bash reads a running script incrementally' -- plugins/soleur/skills/review/references/risk-tier-and-fix-rounds.md"
  expected_output: "risk-tier-and-fix-rounds.md"
```

## Implementation Phases

All copy operations read from the branch ref `feat-10117-edge-coverage-residuals`
via `git show <branch>:<path>` — never from the sibling worktree's checkout and
never from the bare root (which is bare and has no readable working tree).

`TS` below = one timestamp generated at execution time: `TS=$(date -u +%Y%m%d-%H%M%S)`,
shared by all four archive destinations (brief: "one shared timestamp").

### Phase 1 — Five learnings (verbatim, live paths)

`git show feat-10117-edge-coverage-residuals:<path> > <same path>` for each of:

- `knowledge-base/project/learnings/test-failures/2026-10-14-a-mutation-row-is-vacuous-until-a-fixture-distinguishes-the-mutant.md`
- `knowledge-base/project/learnings/test-failures/2026-10-14-c-quoted-names-evade-extension-anchored-list-filters.md`
- `knowledge-base/project/learnings/workflow-patterns/2026-10-13-plan-review-fold-in-hazards-test-seams-and-quoted-literals.md`
- `knowledge-base/project/learnings/workflow-patterns/2026-10-13-residual-bundle-brainstorm-rulings-and-packaging.md`
- `knowledge-base/project/learnings/workflow-patterns/2026-10-14-bash-reads-a-running-script-incrementally-mid-run-edits-corrupt-it.md`

Then the ONE non-verbatim edit the brief names: in the
plan-review-fold-in-hazards learning's frontmatter, retarget the
`related_artifacts` entry `knowledge-base/project/plans/2026-10-13-fix-edge-declaration-coverage-residuals-plan.md`
→ `knowledge-base/project/plans/archive/${TS}-2026-10-13-fix-edge-declaration-coverage-residuals-plan.md`
(the path Phase 3 lands — the basename-retention ruling in decision-challenges
row 2). `TS` must be captured BEFORE this edit so the same value is reused in
Phase 3.

### Phase 2 — Two bullet ports

- `plugins/soleur/skills/review/references/risk-tier-and-fix-rounds.md`: insert
  the branch bullet verbatim (`git show feat-10117-edge-coverage-residuals:plugins/soleur/skills/review/references/risk-tier-and-fix-rounds.md | sed -n '79p'` —
  the `+`-line from the branch diff, "**Never edit a script while a suite is
  still executing it — bash reads a running script incrementally.** …" citing the
  bash-incremental-reads learning) BETWEEN the `#6760` seat bullet ("A seat must
  never mutation-test the LIVE worktree…") and the PID-namespace bullet ("A brief
  that asks a seat… sends signals or removes files…"). Extract the line from the
  branch file by anchor, not by hardcoding — confirm with `grep -n` on main first.
- `plugins/soleur/skills/work/SKILL.md`: append the branch bullet verbatim
  ("**A mutation row is vacuous until a fixture distinguishes the mutant —
  fabricate the discriminating state when the live corpus can't produce it.** …"
  citing the mutation-vacuity learning) as the LAST bullet of the file's
  sharp-edge list (it is the file's final line on the branch).

Do NOT port: the sibling-worktree-contention paragraph variant (main's wording
is newer — verified against merge-base `943ebacc`), the branch's deletions of
the `6.8` sharp-edge bullet and the test-harness-sharp-edges pointer bullet
(both live on main), or anything else — the branch's remaining delta is
main-side drift, not salvageable content.

### Phase 3 — Planning docs into archive paths (verbatim, shared `TS`)

- `knowledge-base/project/brainstorms/2026-10-13-edge-coverage-residuals-brainstorm.md`
  → `knowledge-base/project/brainstorms/archive/${TS}-2026-10-13-edge-coverage-residuals-brainstorm.md`
- `knowledge-base/project/plans/2026-10-13-fix-edge-declaration-coverage-residuals-plan.md`
  → `knowledge-base/project/plans/archive/${TS}-2026-10-13-fix-edge-declaration-coverage-residuals-plan.md`
- `knowledge-base/project/specs/feat-10117-edge-coverage-residuals/spec.md`
  → `knowledge-base/project/specs/archive/${TS}-feat-10117-edge-coverage-residuals/spec.md`
- `knowledge-base/project/specs/feat-10117-edge-coverage-residuals/tasks.md`
  → `knowledge-base/project/specs/archive/${TS}-feat-10117-edge-coverage-residuals/tasks.md`

`mkdir -p knowledge-base/project/specs/archive/${TS}-feat-10117-edge-coverage-residuals`
before the two spec writes — the archive specs dir is a new directory
(`brainstorms/archive/` and `plans/archive/` already exist).

### Phase 4 — Verification

- `bun test plugins/soleur/test/review-tier-parity.test.ts` (parity-pins the
  risk-tier file).
- The suite the affected-diff selector picks for `plugins/soleur/skills/work/SKILL.md`
  (expected: `plugins/soleur/test/components.test.ts` — run whatever
  `scripts/test-all-affected*` selects).
- Content probes (Test Scenarios).
- Full affected battery at ship (`soleur:ship` runs it).

### Phase 5 — PR and post-merge trail (recorded for ship)

Draft PR first; body carries `## Changelog` (semver:patch, docs-only); cites the
arc with `Ref` in prose — never `Closes`/`Fixes` + a closed number (issue 10117
closed 2026-10-14). Squash merge after green. Post-merge, in order:

1. Comment on draft PR #10190 naming the salvage PR and the two delivery PRs
   (#10237, #10242), then close it unmerged.
2. Verify no live-session activity before teardown: `gh pr view 10190`
   updatedAt/author unchanged since salvage, and the sibling worktree shows no
   uncommitted changes (`git -C .worktrees/feat-10117-edge-coverage-residuals status --porcelain` empty).
3. Delete remote branch `feat-10117-edge-coverage-residuals` and remove sibling
   worktree `.worktrees/feat-10117-edge-coverage-residuals` — LAST, because the
   worktree is the copy source's checkout point and must stay alive until merge
   lands (the `git show <branch>:<path>` reads need the branch ref; the worktree
   pins nothing once the branch is fetched, but the deletion order keeps the
   audit trail: merge → comment/close → branch delete → worktree remove).

## Files to Create

- `knowledge-base/project/learnings/test-failures/2026-10-14-a-mutation-row-is-vacuous-until-a-fixture-distinguishes-the-mutant.md` (verbatim copy)
- `knowledge-base/project/learnings/test-failures/2026-10-14-c-quoted-names-evade-extension-anchored-list-filters.md` (verbatim copy)
- `knowledge-base/project/learnings/workflow-patterns/2026-10-13-plan-review-fold-in-hazards-test-seams-and-quoted-literals.md` (verbatim copy + one frontmatter `related_artifacts` retarget)
- `knowledge-base/project/learnings/workflow-patterns/2026-10-13-residual-bundle-brainstorm-rulings-and-packaging.md` (verbatim copy)
- `knowledge-base/project/learnings/workflow-patterns/2026-10-14-bash-reads-a-running-script-incrementally-mid-run-edits-corrupt-it.md` (verbatim copy)
- `knowledge-base/project/brainstorms/archive/${TS}-2026-10-13-edge-coverage-residuals-brainstorm.md` (verbatim copy)
- `knowledge-base/project/plans/archive/${TS}-2026-10-13-fix-edge-declaration-coverage-residuals-plan.md` (verbatim copy)
- `knowledge-base/project/specs/archive/${TS}-feat-10117-edge-coverage-residuals/spec.md` (verbatim copy)
- `knowledge-base/project/specs/archive/${TS}-feat-10117-edge-coverage-residuals/tasks.md` (verbatim copy)

## Files to Edit

- `plugins/soleur/skills/review/references/risk-tier-and-fix-rounds.md` (insert one bullet, ~line 79, between the `#6760` and PID-namespace bullets)
- `plugins/soleur/skills/work/SKILL.md` (append one bullet as last line of the sharp-edge list)

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "Copy VERBATIM from `git show feat-10117-edge-coverage-residuals:<path>` into this worktree: A. Five learnings, identical live paths" | Phase 1 / Files to Create rows 1–5 | mapped |
| 2 | "In the plan-review-fold-in-hazards learning's frontmatter, retarget any `related_artifacts` entry pointing at the live plan path to the archived plan path in (C)." | Phase 1 retarget step | mapped |
| 3 | "B. Two verbatim bullet ports into files that already exist on main: … insert the branch's added bullet … between the #6760-seat bullet and the PID-namespace bullet (branch position ~line 79). … append the branch's added bullet … as the last bullet in the file's sharp-edge list." | Phase 2 / Files to Edit rows 1–2 | mapped |
| 4 | "Do NOT port: the branch's stale 'sibling-worktree contention' paragraph variant (main's wording is newer), and anything already on main." | Phase 2 exclusion list | mapped |
| 5 | "C. Planning docs verbatim into archive paths (repo convention `<yyyymmddhhmmss>-<name>` — one shared timestamp)" | Phase 3 / Files to Create rows 6–9 | mapped |
| 6 | "Verification: the risk-tier file is parity-pinned by `plugins/soleur/test/review-tier-parity.test.ts` — run it (plus the suite covering SKILL.md if the diff selects one). Full affected battery at ship." | Phase 4 / Test Scenarios | mapped |
| 7 | "draft first; body with `## Changelog` (semver:patch, docs-only); cite the arc with `Ref` in prose — never `Closes`/`Fixes` + a closed number … squash merge after green; post-merge, comment-and-close the orphaned draft naming the salvage PR and the two delivery PRs, then delete its remote branch and sibling worktree `.worktrees/feat-10117-edge-coverage-residuals` — the worktree is the copy SOURCE so it must stay alive until merge lands; before deleting it verify the draft shows no live-session activity" | Phase 5 | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| Phase 1 verbatim copies (5 files) | "Copy VERBATIM from `git show feat-10117-edge-coverage-residuals:<path>` into this worktree" | asked |
| Phase 1 frontmatter retarget | "retarget any `related_artifacts` entry pointing at the live plan path to the archived plan path in (C)" | asked |
| Phase 2 bullet inserts (2 files) | "Two verbatim bullet ports into files that already exist on main" | asked |
| Phase 2 exclusion list | "Do NOT port: the branch's stale 'sibling-worktree contention' paragraph variant … and anything already on main." | asked |
| Phase 3 archive copies (4 files) | "Planning docs verbatim into archive paths (repo convention `<yyyymmddhhmmss>-<name>` — one shared timestamp)" | asked |
| Phase 4 verification probes + parity test | "the risk-tier file is parity-pinned by `plugins/soleur/test/review-tier-parity.test.ts` — run it (plus the suite covering SKILL.md if the diff selects one). Full affected battery at ship." | asked |
| Phase 5 PR/post-merge sequence | "draft first; body with `## Changelog` (semver:patch, docs-only); cite the arc with `Ref` in prose … post-merge, comment-and-close the orphaned draft … then delete its remote branch and sibling worktree" | asked |
| `TS` generation step (once, shared) | "one shared timestamp" | asked |
| Archive basename retains original `2026-10-13-` prefix | — | inferred — justification: `archive-kb.sh` uses `${ts}-$(basename)` and every existing `*/archive/` entry carries the double date; the brief's `<name>` reads as the full original basename (decision-challenges row 2) |

### Split Assessment

- Subsystems touched: 2 — `plugins/soleur`, `knowledge-base`
- Planned files: 11 | Estimated changed lines: ~1360 (1356 copied lines + 2 bullet lines + 1 frontmatter line)
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR — nominally over the lines threshold (~1360), but the content is verbatim `git show` copies rather than authored diff, the learnings and the bullets that cite them must land together to avoid dangling references, and the set is the brief's single atomic salvage unit.

## Acceptance Criteria

- [ ] AC1: All five learnings exist at their live paths and are byte-identical to `git show feat-10117-edge-coverage-residuals:<path>` — EXCEPT the fold-in-hazards file, which differs only in its `related_artifacts` frontmatter line now pointing at `knowledge-base/project/plans/archive/<TS>-2026-10-13-fix-edge-declaration-coverage-residuals-plan.md` (the same `<TS>` Phase 3 uses).
- [ ] AC2: `risk-tier-and-fix-rounds.md` contains the bash-incremental-reads bullet exactly once, positioned immediately between the `#6760` seat bullet and the PID-namespace bullet; `bun test plugins/soleur/test/review-tier-parity.test.ts` is green.
- [ ] AC3: `plugins/soleur/skills/work/SKILL.md`'s last line is the mutation-vacuity bullet citing `2026-10-14-a-mutation-row-is-vacuous-until-a-fixture-distinguishes-the-mutant.md`; the `6.8` bullet and the test-harness-sharp-edges pointer bullet are still present (not ported away); `git diff origin/main...HEAD -- plugins/soleur/skills/work/SKILL.md` (merge-base-scoped three-dot, so a sibling merge moving main cannot false-red it) shows ONLY the appended bullet — the sibling-worktree-contention paragraph untouched.
- [ ] AC4: Four archive files exist at the `${TS}-`-prefixed paths (basename-retention form), all sharing one timestamp, byte-identical to `git show feat-10117-edge-coverage-residuals:<path>`.
- [ ] AC5: PR is draft-first with `## Changelog` (semver:patch), `Ref`-only citation of the 10117 arc; no `Closes`/`Fixes` token naming a closed issue.
- [ ] AC6: Post-merge — PR #10190 carries the naming comment and is closed unmerged; remote branch `feat-10117-edge-coverage-residuals` and worktree `.worktrees/feat-10117-edge-coverage-residuals` are deleted only after merge lands and only after the no-live-activity check (updatedAt/author unchanged, `status --porcelain` empty) passes.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — docs/KB salvage. Mechanical UI-surface
override check: every Files-to-Create/Edit path is `.md` under `knowledge-base/`
or `plugins/soleur/skills/` — zero matches against the `ui-surface-terms.md` glob
superset, so the Product/UX gate does not fire.

## Open Code-Review Overlap

- The two edited files and the nine created files: no open `code-review` issue
  body contains any of their full paths — **None**.
- `knowledge-base/project/learnings/` (directory substring) matched nine open
  issues whose bodies name the subtree but no planned file. Disposition:
  **Acknowledge** — #3321 (CODEOWNERS coverage for the learnings subtree) is a
  governance concern this docs-only salvage does not fix and does not worsen;
  #10245, #8859, #8487, #3414, #3280, #2590, #2349, #2348 matched on the shared
  directory string only, none touch a planned file.

## Test Scenarios

- **Verification (integration):** `for p in <five learnings>; do diff <(git show feat-10117-edge-coverage-residuals:"$p") "$p"; done` — four files diff empty; the fold-in-hazards file diffs ONLY on its `related_artifacts` line.
- **Verification (integration):** `grep -n 'bash reads a running script incrementally' plugins/soleur/skills/review/references/risk-tier-and-fix-rounds.md` returns exactly one hit, with the `#6760` bullet immediately before and the PID-namespace bullet immediately after (`sed -n '$((N-1)),$((N+1))p'` shows the three-bullet order).
- **Verification (integration):** `tail -1 plugins/soleur/skills/work/SKILL.md` is the mutation-vacuity bullet; `grep -c 'Sibling-worktree contention produces a FALSE RED' plugins/soleur/skills/work/SKILL.md` stays `1` (main's paragraph untouched); `git diff origin/main...HEAD -- plugins/soleur/skills/work/SKILL.md` shows ONLY the appended line.
- **Verification (integration):** `ls knowledge-base/project/{plans,brainstorms}/archive/*2026-10-13* knowledge-base/project/specs/archive/*feat-10117*` resolves the four landed artifacts with one shared `<TS>` prefix; each diffs empty against `git show feat-10117-edge-coverage-residuals:<path>`.
- **Test (unit/integration):** `bun test plugins/soleur/test/review-tier-parity.test.ts` green; the affected-diff-selected suite covering `work/SKILL.md` green; full affected battery green at ship.

## Sharp Edges

- The sibling worktree `.worktrees/feat-10117-edge-coverage-residuals` is BOTH
  the copy source's checkout point and the teardown target — deletion is the
  LAST step, after merge + close + liveness check, never before.
- `git show feat-10117-edge-coverage-residuals:<path>` is the only source of
  truth for copied bytes — do not copy from the sibling worktree's files
  (uncommitted drift is possible there) and never read the bare root
  (`hr-when-in-a-worktree-never-read-from-bare`; the root is `bare` per
  `git worktree list`).
- A plan whose `## User-Brand Impact` section is empty or omits the threshold
  fails deepen-plan Phase 4.6; this plan's `## Observability` block is REQUIRED
  (not optional) because the edited `.md` files live under `plugins/*/skills/`,
  outside the pure-docs exemption of deepen-plan Phase 4.7.
- `TS` is captured ONCE before Phase 1's frontmatter retarget and reused for all
  four archive destinations — regenerating it per file would split the archive
  set across two timestamps.
- The bash-incremental-reads learning being ported applies to this very port:
  check `pgrep -f test-all` before editing `work/SKILL.md` if any battery is
  running in the worktree.

## References

- Draft PR to close: `gh pr view 10190` (OPEN, draft) — `feat-10117-edge-coverage-residuals` @ `1219f7a0`
- Delivery PRs (merged 2026-10-14): `gh pr view 10237`, `gh pr view 10242`
- Arc issue (CLOSED 2026-10-14 — `Ref` only): `gh issue view 10117`
- Archive convention: `plugins/soleur/skills/archive-kb/scripts/archive-kb.sh` (`${ts}-$(basename)`)
- Parity pin: `plugins/soleur/test/review-tier-parity.test.ts`
- Rulings: `knowledge-base/project/specs/feat-one-shot-salvage-10117-artifacts/decision-challenges.md`
