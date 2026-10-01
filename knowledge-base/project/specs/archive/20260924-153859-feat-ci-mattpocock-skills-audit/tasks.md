# Tasks: land the mattpocock/skills audit record, reconciled (PR 8284)

Plan: `knowledge-base/project/plans/2026-09-23-docs-mattpocock-skills-audit-record-reconcile-plan.md`

## Phase 1: Setup

- [x] 1.1 Run `git fetch origin main && git merge-tree --write-tree origin/main HEAD`. It must exit 0.
- [x] 1.2 Record the AC baselines: the absence-grep counts, and the content-strategy count of 2.

## Phase 2: Core Implementation

- [x] 2.1 Reconcile `knowledge-base/product/competitive-intelligence.md` (plan Phase 1 steps 1–16)
  - [x] 2.1.1 Frontmatter: set `last_updated: 2026-09-23`.
  - [x] 2.1.2 Tier 1 row: add the reconciled tag, the third-cell pointer note, the in-place
    annotations (`#8287`, "now 6 of 6"), the filed-bundles sentence, the NOTICE attribution pointer and
    the neutral star wording (drop "implausible for the category", "~265k stars in 7.5 months" and the
    newsletter clause).
  - [x] 2.1.3 Key Takeaway 4: keep the `4. **[2026-09-18]` prefix, put the evidence in the past tense,
    and cite `#8287` and `#8288`.
  - [x] 2.1.4 Header: add the `**Reconciled:**` line after the Fork note.
  - [x] 2.1.5 Add the new `#### Reconciliation status (2026-09-23)` section before §1. Write every
    ID individually, add the NOTICE pointer sentence and the open-issues line, and state that
    `#8486` is not closed by ADR-236.
  - [x] 2.1.6 §1: rewrite the stars bullet and add the defects "[Fixed … `#8484`]" note.
  - [x] 2.1.7 §2: reword the `setup-pre-commit` reject verdict. §4: reword the `openai.yaml` reject
    verdict.
  - [x] 2.1.8 §3: annotate the `diagnosing-bugs` row. §4: annotate the Recommendations lead-in.
  - [x] 2.1.9 §Attribution: replace the per-target list with the NOTICE pointer.
  - [x] 2.1.10 Rewrite the Convergence-risk star bullet (replace the "implausible … laundered" clause)
    and the scope note.
  - [x] 2.1.11 Correct both now-false "No `frontier` concept exists" sentences in place (§3 `grilling`
    row and §4 B4 row).
  - [x] 2.1.12 Add the `*[Reconciled 2026-09-23 — …]*` pointer under the §2, §3 and §4 table lead-ins.
  - [x] 2.1.13 Status-table rows for B4 and B10 read lowercase `not bundled — remains advisory`.
- [x] 2.2 `knowledge-base/marketing/content-strategy.md`: in the calendar row for the `#8548` post,
  add the Sources pointer (status anchor) and the "no star count; no competitive comparison" note.
- [x] 2.3 Commit with `LEFTHOOK_EXCLUDE=bun-test`.

## Phase 3: Testing

- [x] 3.1 Run AC1–AC8 from the plan. Every grep names its file operand.
- [x] 3.2 Mutation check: restore one retired phrase and confirm exactly one AC3 grep returns 1, then
  revert.

## Phase 4: Issue actions (do not gate the PR)

Every comment starts with `<!-- pr8284-triage -->`. Skip any issue that already carries one.

- [ ] 4.1 Run `gh issue edit 8497 --add-blocked-by 8505`, then post a one-line comment on 8497.
- [ ] 4.2 Post the scope-correction comment on 8486 (model-invocable `flag-create` and
  `flag-set-role`, cross-harness coverage, `hookify` prior art).
- [ ] 4.3 Post a comment on 8505 with the existing credit probe and regex, the closed Admin-API route,
  and the console step marked `automation-status: UNVERIFIED`.
- [ ] 4.4 Post a one-line comment on 8499: the re-probe is due on 2.1.280, and automation is deferred
  behind `#8505`.
- [ ] 4.5 Check AC10 for 8497, 8499, 8486 and 8505.

## Phase 5: Ship

- [ ] 5.1 Push with `--force-with-lease` against the remote head read from `git ls-remote`.
- [ ] 5.2 Run `soleur:ship`. It regenerates the body with the triage table, `Filed: none`, `Refs`
  (never `Tracks #8505`) and Merge Danger, and syncs with main before merge.
- [ ] 5.3 Check AC11. The body must carry `Filed: none`, the triage heading, `**Undo:**` and
  `**Blast Radius:** docs`. Use `gh pr edit` if it does not.
- [ ] 5.4 After merge, check AC9. Then post the 8548 comment with the anchor permalink (confirm the
  slug from the rendered HTML first), and check AC10 for 8548.
