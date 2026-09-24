---
title: "docs(ci): record the 2026-09-23 founder decisions in the mattpocock/skills audit record"
type: docs
date: 2026-09-24
slug: docs-mattpocock-audit-record-founder-decisions
branch: feat-one-shot-mattpocock-audit-record-founder-decisions
issue: 8648
closes: none
priority: p3
domain: product
brand_survival_threshold: none
lane: cross-domain
---

# docs(ci): record the 2026-09-23 founder decisions in the mattpocock/skills audit record

## Enhancement Summary

**Deepened on:** 2026-09-24 (proportionate pass for a docs-only plan).

- Every edit anchor was checked against `competitive-intelligence.md` with `grep -c -F`: each one
  matches exactly once. The exception is `| B5 |`, which matches twice, so the B5 instruction now
  names the reconciliation-table row explicitly.
- AC4 was rewritten. The old "rows starting `| B4 |`" form would also have matched the dated §4
  table's `| B4 |`/`| B10 |` rows, and those never gain "Bundled", so AC4 would have failed on a
  correct edit.
- Negative claims were checked:
  - `git show --stat e5a725a5e1` touches no `go.md`.
  - `archive-kb.sh` contains no `git commit`.
  - No test or script reads the reconciliation section.
  - `e5a725a5e1` is an ancestor of `origin/main`.
- Halt gates:
  - User-Brand Impact passes: threshold `none`, no sensitive path.
  - Observability, Encryption, Guard, UI-wireframe and Downtime gates skip, since this is pure docs.
  - The PAT sweep finds nothing.
  - The only rule ID cited, `cq-cite-content-anchor-not-line-number`, is active in `AGENTS.md`.

## Overview

Spec lacks valid lane: — defaulted to cross-domain (TR2 fail-closed).

Bring the mattpocock/skills peer-plugin audit record (merged in PR #8284) in line with the founder's
2026-09-23 decisions on the review dissents T1 to T4, record declines for the inspire-only ideas, and
archive the PR #8284 planning leftovers still live on main. Docs-only. Draft PR #8648 already carries
this branch: do not open another PR. No issue is closed by it (`closes: none`).

Two files change in place, then two artifacts move:

- `knowledge-base/product/competitive-intelligence.md`, the audit record (sections named below by
  content anchor, per `cq-cite-content-anchor-not-line-number`).
- `knowledge-base/project/specs/feat-ci-mattpocock-skills-audit/decision-challenges.md`, the Model
  Dissents source: one decision line per T-entry, then it is archived with its directory.
- Archived: `knowledge-base/project/plans/2026-09-23-docs-mattpocock-skills-audit-record-reconcile-plan.md`
  and `knowledge-base/project/specs/feat-ci-mattpocock-skills-audit/`.

## Research Reconciliation — Brief vs. Codebase

| Brief claim | Reality (checked 2026-09-24) | Plan response |
|---|---|---|
| Only `#8505` is stale on the "Open issues from the bundles" line | `#8505` CLOSED 2026-09-23 (COMPLETED, via PR `#8618`, merged 2026-09-23). **`#8497` is also CLOSED** 2026-09-23, NOT_PLANNED: founder comment "close as INCONCLUSIVE. Not re-measuring, not adopting" (post-audit estimate ~+5.6 pts vs the pre-registered 10-pt bar). `#8486`, `#8499`, `#8548` are OPEN | Move both closed issues out of the open list. The B5 row's `open: #8497` cell is stale for the same reason: fix it too |
| "Tier 1 text `B4 and B10 never filed`" | The phrase lives in the **Tier 1 competitor table row** for mattpocock/skills (anchor: `B4 and B10 never filed`), not in the Tier 1 Key Takeaways | Edit that row. Two sibling sites repeat the "five bundles … B9/B12 in part" count and would go stale with it: the audit's **Scope note** and the §5 banner (anchor: `they were filed as five bundles`). Edit both |
| PR `#8647` merged 2026-09-24 as `e5a725a5e1` | Confirmed: merged 2026-09-24T13:26Z, merge commit `e5a725a5e19ac809f18cfcdb1a8c08ad34d63913`. It changed `commands/help.md` (not `go.md`), `brainstorm/SKILL.md`, `brainstorm-techniques/SKILL.md`, `compound/SKILL.md`, `plugins/soleur/NOTICE` ("Bundle 6") | Row text for B4/B10/B12b is taken from the NOTICE "Bundle 6" paragraph, including what was deliberately not imported |
| B12 second half needs a row | Today B12 sits inside the `G1, G5, B9, B12` row as "B12 in part … the `go`/`help` flow map did not" | Narrow that row to "B12 (first half)" and add a separate B12 (second half) row |
| "leading words" shipped in `plugins/soleur/skills/skill-creator/references/authoring-levers.md` | Path exists; `## Leading words` is its first section | Cite it with the section anchor |
| Docs "It's working if" needs ~99 per-skill pages that don't exist | `plugins/soleur/docs/` has one `pages/skills.njk` listing and no per-skill pages; `plugins/soleur/skills/` has 103 directories today | Write "a docs page per skill (about 100)", not a hard count |
| ADR-234 excludes "redundancy findings and refused mechanisms" | ADR-234 §"Built is not rejected" excludes redundancy findings. It does **not** exclude mechanism refusals: its `instead` field exists to distinguish a mechanism refusal from a category-level never | In the record, justify the non-entry by what holds: the register is for refused *requests* (concepts someone asked for), these ideas are audit harvest nobody requested, and several are redundancy findings. Do not assert that ADR-234 excludes refused mechanisms |
| `decision-challenges.md` lists T1 to T4 | It lists **T1 to T5**; T5 is already marked "Resolved at review 2026-09-23" | T5 untouched |

## Research Insights

**Premise Validation.** Checked every cited reference: `#8505` (closed, via PR `#8618`), `#8497`
(closed not-planned: a second stale entry), `#8486`/`#8499`/`#8548`/`#5994` (open), PR `#8284`
(merged 2026-09-23), PR `#8647` (merged 2026-09-24, `e5a725a5e1`), PR `#8648` (open, draft, this
branch), `authoring-levers.md` (exists), archive targets (both present on this branch's base). No
action-required issue tracks the PR #8284 dissents (`gh issue list --search "mattpocock in:title"`
returns only `#8548`), so nothing is closed by this PR.

**Property List.**

1. A reader of the audit record sees the current state of every B-row and every issue it cites.
2. The four dissents T1 to T4 each carry a recorded founder choice.
3. Each inspire-only idea has a recorded decline with a reason and a revisit trigger.
4. PR #8284's plan/spec no longer sit in the live `plans/` and `specs/` trees, and no live file
   points at their old paths.

**Cut List.** None. The brief proposes no mechanism: every item is a text edit or an existing
script run (`archive-kb.sh`). No `rejected/` entry (the brief forbids it; property 3 is met by the
audit record itself).

**Archive mechanics (dry-run at plan time).** The plan and spec carry different slugs, so
`archive-kb.sh` needs two runs; each dry-run warns about the missing sibling, which is expected:

- `archive-kb.sh --dry-run ci-mattpocock-skills-audit` → only `specs/feat-ci-mattpocock-skills-audit`.
- `archive-kb.sh --dry-run mattpocock-skills-audit` → only
  `plans/2026-09-23-docs-mattpocock-skills-audit-record-reconcile-plan.md`. It matches neither this
  branch's plan (`…mattpocock-audit-record-…`) nor PR #8647's (`…mattpocock-audit-b4-…`).
- The script does `git mv` with a `YYYYMMDD-HHMMSS-` prefix, the convention in both `archive/` dirs.
  It does not commit.

**Reference census (plan time).** `git grep` over both old paths, excluding `*.json` and
`**/archive/**`, returns 9 hits in 4 files, **all inside the four artifacts being archived**. No JSON
hits. So the repoint step is expected to be empty outside this branch's own planning artifacts. It
still runs, because main may gain a reference before merge.

**Lint.** `lefthook.yml` runs `bash scripts/markdown-lint.sh {staged_files}` on `*.md`. No test
parses `competitive-intelligence.md` for this section (the cron readers use frontmatter only).

**Institutional learnings applied.**

- `2026-03-13-stale-cross-references-after-kb-restructuring.md`: sweep for old paths before merge,
  not after.
- `2026-03-21-kb-migration-verification-pitfalls.md`: `grep -v` post-filters fail when the old path
  sits in the output filenames. Use git pathspec exclusions (`':!…'`), not piped negation.
- `best-practices/2026-06-03-path-rename-sweep-exclude-own-migration-artifacts.md`: this plan and its `tasks.md`
  cite the old paths on purpose. The residual-zero check excludes them.

**Plan review (2026-09-24).** DHH, Kieran and code-simplicity reviewed; no P0/P1. Applied: exact
old spans for the Tier 1 row and Scope note, the B4 second site (`brainstorm-techniques`), the
narrower ADR-234 wording (only the writing trio is a redundancy finding, so the record does not
claim it), executable ACs, and cuts of the duplicate date sentence, the inspire-only table row and
the Tier 1 lead tag. Kept §7 over one reviewer's cut: the archived dissent file is the only place
each choice sits next to the dissent it answers. No named-panel lens was relevant, so no Taste
findings were persisted.

## Implementation

All edits in `knowledge-base/product/competitive-intelligence.md` unless named otherwise. Anchors are
quoted text to search for. Wording below is the target text; minor copy fixes are allowed, but not
changes of meaning.

### 1. Frontmatter and dating

- `last_updated: 2026-09-23` → `last_updated: 2026-09-24`. Leave `last_reviewed` alone (the Scope
  note explains why).
- Reconciliation status intro, after the anchor `re-derived against origin/main on 2026-09-23.`,
  append:

  ```text
  Issue states and the rows marked "founder decision 2026-09-23" were updated on 2026-09-24.
  ```

- Table header cell `Status on 2026-09-23` → `Status (updated 2026-09-24)`.
- Keep the `#### Reconciliation status (2026-09-23)` heading as it is. Its GitHub anchor
  `#reconciliation-status-2026-09-23` is linked from `knowledge-base/marketing/content-strategy.md`
  (the `#8548` row) and from the `#8548` permalink comment, so renaming it breaks both.

### 2. T1: Key Takeaway 4 (no change)

Tier 1 Key Takeaway 4 (anchor `The most valuable thing a Tier-1 peer can hand us`) stays as it is.

### 3. T2: issue states

B5 row of the reconciliation table (the row starting `| B5 | Not applied.`; the §4 table has a second, dated `| B5 |` row that stays untouched): its last cell `` open: `#8497` `` becomes `` closed 2026-09-23, not planned: `#8497` ``, and
its status cell gains this sentence at the end:

```text
The founder closed the revisit on 2026-09-23: the estimate is below the pre-registered 10-point bar, so B5 is neither re-measured nor adopted.
```

`**Open issues from the bundles:**` paragraph: first re-run `gh issue view N --json state` for every
number on the line (states may move after 2026-09-24). Keep only the open ones with their existing
glosses (`#8486`, `#8499`, `#8548` at plan time), then append:

```markdown
**Closed since:** `#8505` (CI/eval key separated from production; shipped 2026-09-23 in PR `#8618`), `#8497` (B5 revisit; closed 2026-09-23, not planned).
```

The T2 proposal (call `#8505` the priority deferral) is moot now that `#8505` has shipped. No
PR-body priority framing is needed.

### 4. T3: B4, B10 and B12's second half, bundled

Reconciliation table. Row `| G1, G5, B9, B12 |`: first cell becomes `G1, G5, B9, B12 (first half)`.
In its status cell, the sentence starting `B12 in part: the context tree shipped` (ending
`flow map did not.`) becomes:

```markdown
B12's first half: the context tree shipped in `brainstorm-techniques/references/phase-boundaries.md`. The flow map is the B12 (second half) row.
```

Rows B4 and B10 (both today `| Not bundled — remains advisory | none |`) are replaced, and a B12
(second half) row follows them:

```markdown
| B4 | Bundled (founder decision 2026-09-23). Shipped in `brainstorm` §1.2 and its `brainstorm-techniques` exit line: the completion criterion (every decision branch walked or explicitly parked, nothing silently assumed), dependency-ordered questions, and non-blocking fact lookups. Not adopted: `grilling`'s batched multi-question frontier (Soleur keeps one question per turn). | PR `#8647` (merged 2026-09-24, `e5a725a5e1`) |
| B10 | Bundled (founder decision 2026-09-23). Shipped in `compound` Phase 1.5: the null-guardrail finding, applied per recurring failure class after reading the repo's own check commands. Not adopted: `retro`'s tool-economy and information-access categories, and a repo-level null-guardrail finding on every run. | PR `#8647` (merged 2026-09-24, `e5a725a5e1`) |
| B12 (second half) | Bundled (founder decision 2026-09-23). Shipped: a flow map of main flow, on-ramps and standalone skills in `plugins/soleur/commands/help.md`, naming only Soleur skills. `go.md` routing is unchanged. | PR `#8647` (merged 2026-09-24, `e5a725a5e1`) |
```

Sources for every added fact, to re-check at work time: the "Shipped" and "Not adopted" clauses
come from the `plugins/soleur/NOTICE` "Bundle 6" paragraph (if it and this plan disagree, NOTICE
wins); "`go.md` routing is unchanged" comes from `git show --stat e5a725a5e1`; `e5a725a5e1` is PR
#8647's `mergeCommit.oid` prefix; issue states and dates come from `gh issue view` / `gh pr view`.

Sibling count sites (they otherwise contradict the table):

- Tier 1 competitor table, mattpocock/skills row. The whole span from `(B5 measured but not applied`
  through `see the audit's §Reconciliation status.` (today: `(B5 measured but not applied; B9 and
  B12 in part; B4 and B10 never filed); see the audit's §Reconciliation status.`) becomes, so the
  "see" clause appears once:

  ```markdown
  (B5 measured but not applied; B9 in part; B12's first half only). A sixth bundle, PR `#8647` (founder decision 2026-09-23, merged 2026-09-24), shipped B4, B10 and B12's second half; see the audit's §Reconciliation status.
  ```

- Scope note: the clause `with B5 not applied and B9/B12 in part (see §Reconciliation status).`
  becomes:

  ```markdown
  with B5 not applied, B9 in part and B12's first half only; a sixth, PR `#8647` (2026-09-24), shipped B4, B10 and B12's second half (see §Reconciliation status).
  ```

- §5 banner: `they were filed as five bundles, see §Reconciliation status` becomes
  `` they were filed as five bundles plus a sixth (`#8647`); see §Reconciliation status ``.

The dated §3/§4 cells that say "See B4" / "See B10" / "See B12" sit under
"[Reconciled 2026-09-23 — cells below describe the tree on 2026-09-18 …]" banners. They stay as dated
evidence and are not edited.

### 5. T4: `setup-pre-commit` verdict

§2 "Explicitly NOT worth taking", `setup-pre-commit`/`git-guardrails-claude-code` bullet:
`**Reject — Soleur's hooks fleet already covers this in more depth.**` →
`**Reject — already covered by the hooks listed above.**`

### 6. Inspire-only ideas: declines

Add this block right after the `**Open issues from the bundles:**`
paragraph:

```markdown
**Inspire-only ideas, declined (founder decision 2026-09-23).** Recorded here rather than as
`knowledge-base/project/rejected/` entries: that register (ADR-234) holds refused requests, and
nobody requested these.

- `writing-beats` / `writing-fragments` / `writing-shape`: declined. Their one transferable idea,
  leading words, already shipped in `plugins/soleur/skills/skill-creator/references/authoring-levers.md`
  (§Leading words). Revisit if a re-audit finds the trio has gained another agent-facing mechanic.
- `teach`: declined, no user demand. Revisit if a founder asks for cross-session learning support.
- Two-axis Standards-vs-Spec review: declined, no observed failure where one axis masked the other in
  `review`. Revisit on the first such failure.
- Docs "It's working if" section: declined. It needs a docs page per skill (about 100);
  `plugins/soleur/docs/` has no per-skill pages, only the `pages/skills.njk` listing. Revisit if per-skill pages are built.
- Implementation-vs-review context pressure: declined here. If raised, it belongs in an ADR-151
  challenge, not in this record.
- `to-tickets` expand–contract sequencing: declined. Revisit if a wide-refactor plan goes wrong.
- Self-contained HTML report for `agent-native-audit`: declined as a separate item. Fold it into
  open `#5994` if wanted.
```

The dated "inspire only" verdicts in §2 and §3 stay as evidence. The block above is their current
status. Keep the neutral tone the record uses for a named third party's repo (the CLO precedent in
T5): decline reasons are about Soleur's fit, never about the upstream work's quality.

### 7. Model Dissents source: record the decisions

In `knowledge-base/project/specs/feat-ci-mattpocock-skills-audit/decision-challenges.md`, add one line
under each of T1 to T4, before archiving:

- T1: `- **Founder decision 2026-09-23:** plan default kept (past-tense KT4). No change.`
- T2: `- **Founder decision 2026-09-23:** moot. \`#8505\` shipped and closed 2026-09-23 via PR \`#8618\`.`
- T3: `- **Founder decision 2026-09-23:** both options superseded. B4, B10 and B12's second half were
  bundled and shipped in PR \`#8647\` (merged 2026-09-24, \`e5a725a5e1\`).`
- T4: `- **Founder decision 2026-09-23:** proposal adopted ("Reject — already covered by the hooks
  listed above.").`

### 8. Archive PR #8284's leftovers

From the worktree root:

```bash
bash plugins/soleur/skills/archive-kb/scripts/archive-kb.sh --dry-run ci-mattpocock-skills-audit
bash plugins/soleur/skills/archive-kb/scripts/archive-kb.sh ci-mattpocock-skills-audit
bash plugins/soleur/skills/archive-kb/scripts/archive-kb.sh --dry-run mattpocock-skills-audit
bash plugins/soleur/skills/archive-kb/scripts/archive-kb.sh mattpocock-skills-audit
```

Each dry-run must list exactly one artifact (the spec dir, then the plan file). If either lists
anything else, stop and re-derive the slug rather than archiving extra files. `archive-kb.sh` does
not commit, so step 7's edit lands in the archived copy whichever order the two run in.

Then sweep for references (pathspec exclusions, not `grep -v`):

```bash
git grep -n -e '2026-09-23-docs-mattpocock-skills-audit-record-reconcile-plan' \
  -e 'specs/feat-ci-mattpocock-skills-audit' -- ':!*.json' ':!**/archive/**' \
  ':!knowledge-base/project/plans/2026-09-24-docs-mattpocock-audit-record-founder-decisions-plan.md' \
  ':!knowledge-base/project/specs/feat-one-shot-mattpocock-audit-record-founder-decisions/**' \
  | cut -c1-200 | head -40
```

Repoint every hit to its `archive/<timestamp>-…` path. At plan time the expected result is empty.

### 9. PR #8648 body (written by `ship`)

Content for `ship` Phase 6, which authors the body: T1 to T4 with the choice made for each, the
seven inspire-only declines, and the two archive moves with their new paths. No `Closes #N`: no issue is resolved by this PR. `ship` updates the existing draft
PR #8648 and never runs `gh pr create`. Keep the body clear of the `ship-operator-step-gate.sh` deny
tokens (`Operator`, `Post-merge`, `Follow-up`): nothing here is a step for anyone to run.

## Files to Edit

- `knowledge-base/product/competitive-intelligence.md`
- `knowledge-base/project/specs/feat-ci-mattpocock-skills-audit/decision-challenges.md` (then moved)

## Files to Create

None. `archive-kb.sh` renames the two archived artifacts.

## Open Code-Review Overlap

None. `gh issue list --label code-review --state open` bodies were searched for
`knowledge-base/product/competitive-intelligence.md`, `feat-ci-mattpocock-skills-audit` and
`docs-mattpocock-skills-audit-record-reconcile-plan`: 0 matches.

## User-Brand Impact

- **If this lands broken, the user experiences:** the founder reading the audit record sees a closed
  issue listed as open, or B4/B10 as unfiled, and spends a decision on something already settled.
- **If this leaks, the user's workflow is exposed via:** nothing new. The file is a KB record
  already public in this repo, and the edits add no credentials, personal data or new third-party
  figures.
- **Brand-survival threshold:** `none`
- `threshold: none, reason: docs-only edits to a public knowledge-base record and two archive renames; no code, data or user-facing surface is touched.`

## Acceptance Criteria

Run from the worktree root. Let `CI=knowledge-base/product/competitive-intelligence.md`.

- [x] AC1 (T2): for every number on the open-issues line,
  `grep -F '**Open issues from the bundles:**' "$CI" | grep -o '#[0-9]*' | sort -u`, then
  `gh issue view N --json state` prints `OPEN`. `#8505` and `#8497` appear on the `**Closed since:**`
  line, with `#8505` next to `#8618`.
- [x] AC2 (T2): the `| B5 |` row does not contain `` open: `#8497` ``.
- [x] AC3 (T3/T4 residue): each of these prints `0`:
  `grep -c 'Not bundled — remains advisory' "$CI"`, `grep -c 'B4 and B10 never filed' "$CI"`,
  `grep -c 'already covers this in more depth' "$CI"`, `grep -c 'flow map did not' "$CI"`.
- [x] AC4 (T3): for each prefix `| B4 | Bundled (founder decision 2026-09-23)`,
  `| B10 | Bundled (founder decision 2026-09-23)` and
  `| B12 (second half: flow map) | Bundled (founder decision 2026-09-23)`, `grep -F "<prefix>" "$CI"` prints
  exactly one line, and that line contains `#8647` and `e5a725a5e1`. (Scoped by prefix because the
  dated §4 table also has `| B4 |`, `| B5 |` and `| B10 |` rows, which stay untouched.)
- [x] AC5 (T3): the Scope note line (`grep -F 'The audit itself filed nothing'`) and the §4 Recommendations banner
  line (`grep -F 'they were filed as five bundles'`) each contain `#8647`.
- [x] AC6 (T4): `grep -c 'Reject — already covered by the hooks listed above.' "$CI"` prints `1`.
- [x] AC7 (T1): `diff <(git show origin/main:"$CI" | grep -F 'The most valuable thing a Tier-1 peer') <(grep -F 'The most valuable thing a Tier-1 peer' "$CI")` prints nothing.
- [x] AC8 (declines): `awk '/^\*\*Inspire-only ideas, declined/{f=1;next} f&&/^- /{n++} f&&/^$/&&n{exit} END{print n}' "$CI"`
  prints `7`, and six of those bullets contain `Revisit` or `#5994` (the ADR-151 bullet names
  where it belongs instead).
- [x] AC9 (no register entry): `git diff --name-only origin/main -- knowledge-base/project/rejected/`
  prints nothing.
- [x] AC10 (archive): `git diff -M --name-status origin/main` shows `R` lines moving
  `plans/2026-09-23-docs-mattpocock-skills-audit-record-reconcile-plan.md` and every file of
  `specs/feat-ci-mattpocock-skills-audit/` to `archive/<YYYYMMDD-HHMMSS>-…` paths, and neither old
  path exists.
- [x] AC11 (references): the §8 `git grep` prints nothing.
- [x] AC12 (dissent record): `grep -c '^- \*\*Founder decision 2026-09-23:\*\*'` on the archived
  `decision-challenges.md` prints `4`.
- [x] AC13 (scope): `git diff --name-only origin/main` shows no path outside `$CI`, the archive
  renames, and this branch's own plan and spec directory (plus `knowledge-base/INDEX.md` if a hook
  regenerates it).
- [x] AC14 (lint): `bash scripts/markdown-lint.sh "$CI"` exits 0.
- [x] AC15 (one PR): `gh pr list --head feat-one-shot-mattpocock-audit-record-founder-decisions --state all --json number --jq length`
  prints `1`.

## Non-Goals

- `knowledge-base/marketing/content-strategy.md` still describes the `#8548` retrospective as
  covering "all five" bundles. That is the CMO's content plan, not the audit record. It is left
  unchanged.
- PR #8647's own plan and spec (`…mattpocock-audit-b4-b10-b12b…`) are not archived here. That
  cleanup belongs to its own pipeline.
- T5 in `decision-challenges.md` is already resolved. The §3/§4 dated cells stay as evidence.

## Domain Review

**Domains relevant:** none

No cross-domain implications. The founder made every decision on 2026-09-23, and this PR writes them
into an internal record. Product owns the file, but there is nothing new to assess and no UI surface
(Product/UX tier: NONE, no UI-surface path in the file lists). No observability, IaC, encryption,
guard, GDPR or ADR/C4 gate fires: no code, infra, store, guard or architectural decision. The ADR-151
decline explicitly defers any architectural question.

## Sharp Edges

- Issue states drift. Re-run `gh issue view` at work time (AC1), not only at plan time.
- The B12 edit touches two rows. Missing the `G1, G5, B9, B12` row leaves "the flow map did not"
  contradicting the new row (AC3 catches it).
- `archive-kb.sh` matches on slug substrings. Always dry-run first (§8). The two slugs were chosen so
  neither matches this branch's plan or PR #8647's.
- Table rows must keep exactly three cells. Backticks inside a cell are fine; a bare `|` is not.
