# Refactor: rename `cleanup-scope-outs` skill → `drain-labeled-backlog` and add `drain` intent to `/soleur:go`

**Date:** 2026-04-19
**Branch:** `feat-one-shot-rename-drain-labeled-backlog`
**Worktree:** `.worktrees/feat-one-shot-rename-drain-labeled-backlog/`
**Type:** `refactor` (skill rename + router intent add)
**Semver label:** `semver:minor` (new routing intent is a user-visible capability)
**Detail level:** MORE (mechanical refactor, narrow blast radius, verification-heavy)
**Closes:** none — pure follow-up from the dogfood runs that produced PR #2486 and the drain PRs of 2026-04-18

## Enhancement Summary

**Deepened on:** 2026-04-19
**Sections enhanced:** 3 (Files to edit — description rewrite; Sharp Edges — word-budget math; Phase 2 step 3 — tokenizer-accurate word count)
**Research agents used:** local grep survey; live `bun test plugins/soleur/test/components.test.ts` tokenizer replication; read of `components.test.ts` source to identify exact budget-enforcement constraints.

### Key improvements from deepen-pass

1. **Word-budget math pinned to live numbers.** Pre-rename cumulative skill description total is **1798 / 1800** words (not the stale 1791 figure quoted in the 2026-04-17 learning). Available headroom is **+2 words**, not +9. The original draft description (~55 words, later shortened to 36 in first-draft Sharp Edges) would have blown the budget and failed CI. Replacement description is now 26 words — exactly at the ceiling. If it fails, drop "issue" to reach 25.
2. **Test tokenizer replicated locally.** The `split(/\s+/).filter(Boolean)` tokenizer in `components.test.ts` is now replicated in Sharp Edges via a shell one-liner. Runs identically to the bun test assertion, so verification happens locally before `bun test` runs.
3. **Test-file assertions explicitly enumerated.** `components.test.ts` enforces: (a) `description.startsWith("This skill")` — planned description complies, (b) `description.length <= 1024` chars — planned description is ~210 chars, well clear, (c) kebab-case filename — `drain-labeled-backlog` complies, (d) no `<example>` block — complies, (e) no backtick refs to `references/`, `assets/`, `scripts/` — complies.

### New considerations discovered

- The project's root `AGENTS.md` rule `rf-review-finding-default-fix-inline` does NOT reference the `cleanup-scope-outs` skill by name — the ARGUMENTS block warned it might, but live grep confirms zero matches. No rule edit needed.
- `plugins/soleur/AGENTS.md` similarly has zero references to the old skill name. Nothing to update there.
- None of `review/SKILL.md`, `ship/SKILL.md`, `one-shot/SKILL.md`, or `compound/SKILL.md` reference the skill by name. The rename's surface area in live code is exactly 4 files.
- `.claude/hooks/` has zero matches. The rename does not require hook updates.
- Docs site (`docs/`) has zero hardcoded matches; the skill list is data-generated and will pick up the new directory name automatically at build time.


## Overview

The `cleanup-scope-outs` skill was shipped in PR #2492 and has since accumulated dogfood evidence
(multiple drain PRs on 2026-04-18) proving it is already **label-generic**:

- `--label <name>` is a supported flag with full argv plumbing
- Default `deferred-scope-out` works; `code-review` has been exercised by existing drain plans
- Helper [`group-by-area.sh`](../../plugins/soleur/skills/cleanup-scope-outs/scripts/group-by-area.sh) validates the label against `gh label list` before querying, so any namespaced label (`type/security`, etc.) also works

The skill's **name** and **description** still frame it as scope-out-specific, which misroutes
future intents. This PR aligns name/framing with the implementation and adds a `drain` intent
to `/soleur:go` so users can trigger it with phrases like "drain the type/security backlog"
without having to remember the skill name.

No behavior change. No helper script rewrite. No new tests beyond filename-stability guards.
The type/security drain itself is **out of scope** — a separate `/soleur:one-shot` invocation
runs after this PR merges.

## Research Reconciliation — Spec vs. Codebase

| Spec claim | Reality | Plan response |
|---|---|---|
| Multiple skill/command files "likely" reference `cleanup-scope-outs` | `rg cleanup-scope-outs` returns 7 files, only **2** are live code: `plugins/soleur/skills/cleanup-scope-outs/SKILL.md` and `plugins/soleur/test/cleanup-scope-outs.test.sh`. The other 5 are historical artifacts (`knowledge-base/project/specs/`, `knowledge-base/project/plans/2026-04-17-*`, `knowledge-base/project/plans/2026-04-18-refactor-drain-review-followups-batch-plan.md`, two learnings). | **Skip edits to historical knowledge-base artifacts.** Spec-file is a snapshot of the feat that shipped the skill — retroactively rewriting it rewrites history. Learnings are dated records; update only if the body refers to the skill as if it were a live name (reference the current name inline as `(now drain-labeled-backlog)` rather than rewriting). |
| `plugins/soleur/AGENTS.md` may reference old name | Grep returns **no matches** in `plugins/soleur/AGENTS.md` or root `AGENTS.md`. | Nothing to update there. |
| Root `AGENTS.md` rule `rf-review-finding-default-fix-inline` references old skill path | Rule body does NOT mention `cleanup-scope-outs` — it points to `plugins/soleur/skills/review/SKILL.md §5` and `plugins/soleur/skills/compound/SKILL.md`. | Nothing to update in the rule body. |
| `plugins/soleur/skills/review/SKILL.md`, `ship/SKILL.md`, `one-shot/SKILL.md`, `compound/SKILL.md` may reference the old skill by name | Grep of those four files returns **no matches** for `cleanup-scope-outs`. | Nothing to update. |
| `docs/` may enumerate skill in generated component lists | `rg cleanup-scope` on `docs/` returns **no matches**. The landing page reads from `docs/_data/` generators which pick up skills by directory name automatically — the rename surfaces there at build time. | Re-run Eleventy build locally as verification step (already covered by `bun test plugins/soleur/test/components.test.ts`). |
| `.claude/hooks/` or CI workflows may hard-code the old skill name | Grep of `.claude/` returns no matches. | Nothing to update. |

**Net effect:** the surface area of the rename is **4 files**:
- `plugins/soleur/skills/cleanup-scope-outs/SKILL.md` (body + frontmatter)
- `plugins/soleur/skills/cleanup-scope-outs/scripts/group-by-area.sh` (comments only, filename unchanged)
- `plugins/soleur/test/cleanup-scope-outs.test.sh` (renamed + body)
- `plugins/soleur/commands/go.md` (add `drain` row to Step 2 table)

Plus two directory renames (`skills/cleanup-scope-outs/` → `skills/drain-labeled-backlog/`) via `git mv`.

## Open Code-Review Overlap

Query:
```bash
gh issue list --label code-review --state open --json number,title,body --limit 200 > /tmp/open-review-issues.json
jq -r --arg path "plugins/soleur/skills/cleanup-scope-outs" \
  '.[] | select(.body // "" | contains($path)) | "#\(.number): \(.title)"' /tmp/open-review-issues.json
jq -r --arg path "plugins/soleur/commands/go.md" \
  '.[] | select(.body // "" | contains($path)) | "#\(.number): \(.title)"' /tmp/open-review-issues.json
jq -r --arg path "plugins/soleur/test/cleanup-scope-outs.test.sh" \
  '.[] | select(.body // "" | contains($path)) | "#\(.number): \(.title)"' /tmp/open-review-issues.json
```

Run this at Phase 2 and record result. Expected: **None** (this is a fresh rename of recently-shipped code).

If matches are found, disposition (fold in / acknowledge / defer) recorded here before GREEN phase starts. Default disposition on a clean rename = `None`.

## Files to edit

- `plugins/soleur/skills/cleanup-scope-outs/SKILL.md` (will become `plugins/soleur/skills/drain-labeled-backlog/SKILL.md` via `git mv`):
  - Line 2 frontmatter: `name: cleanup-scope-outs` → `name: drain-labeled-backlog`
  - Line 3 `description:` — rewrite to lead with the label-generic framing. Keep under 1,024 chars. Preserve third person ("This skill should be used when…"). Mention `deferred-scope-out` default + `code-review` / `type/security` examples.
  - Line 6 `# Cleanup Scope-Outs` → `# Drain Labeled Backlog`
  - Lines 10-17 "When to use" — replace the deferred-scope-out-first phrasing with label-generic bullets. Add `type/security` as a named example. Keep the `/soleur:review` cross-reference.
  - Line 56 path inside bash example: `plugins/soleur/skills/cleanup-scope-outs/scripts/group-by-area.sh` → `plugins/soleur/skills/drain-labeled-backlog/scripts/group-by-area.sh`
  - Line 121 `--name weekly-scope-out-cleanup` → `--name weekly-deferred-scope-out-drain`
  - Line 122 `--skill cleanup-scope-outs` → `--skill drain-labeled-backlog`
  - Line 151 test-file link: `[cleanup-scope-outs.test.sh](../../test/cleanup-scope-outs.test.sh)` → `[drain-labeled-backlog.test.sh](../../test/drain-labeled-backlog.test.sh)`
  - Line 154 `bash plugins/soleur/test/cleanup-scope-outs.test.sh` → `bash plugins/soleur/test/drain-labeled-backlog.test.sh`
  - Retain ALL sharp edges verbatim — they are label-agnostic and regression-valuable.

- `plugins/soleur/skills/cleanup-scope-outs/scripts/group-by-area.sh` (path becomes `plugins/soleur/skills/drain-labeled-backlog/scripts/group-by-area.sh` via directory `git mv` — filename unchanged):
  - Header comment block (lines 1-14) — already label-generic ("given label", "any other GitHub label works"). No edit required.
  - **No functional change.** Validate with `bash plugins/soleur/test/drain-labeled-backlog.test.sh` post-rename.

- `plugins/soleur/test/cleanup-scope-outs.test.sh` → `plugins/soleur/test/drain-labeled-backlog.test.sh` (via `git mv`):
  - Line 3 comment: `# Tests for cleanup-scope-outs helper script (group-by-area.sh).` → `# Tests for drain-labeled-backlog helper script (group-by-area.sh).`
  - Line 4 comment: `# Run: bash plugins/soleur/test/cleanup-scope-outs.test.sh` → `# Run: bash plugins/soleur/test/drain-labeled-backlog.test.sh`
  - Line 12 `HELPER="$REPO_ROOT/plugins/soleur/skills/cleanup-scope-outs/scripts/group-by-area.sh"` → `HELPER="$REPO_ROOT/plugins/soleur/skills/drain-labeled-backlog/scripts/group-by-area.sh"`
  - Line 13 `FIXTURE_DIR="$SCRIPT_DIR/fixtures/cleanup-scope-outs"` — **KEEP AS-IS** for now; the fixture directory is not being renamed in this PR (tracked as optional follow-up).
  - Line 15 `echo "=== cleanup-scope-outs group-by-area ==="` → `echo "=== drain-labeled-backlog group-by-area ==="`

- `plugins/soleur/commands/go.md` — Step 2 classification table (current lines 31-35):
  - Add a row between `fix` and `review` (alphabetical insertion is fine; position after `fix` groups "work" intents together):

    ```markdown
    | drain | User says "fix all issues labeled X", "drain the Y backlog", "close all label:Z", "clean up the X backlog" | `drain-labeled-backlog` |
    ```

  - Add a short prose note below the table (after current line 37 "If intent is clear…"):

    > When routing to `drain-labeled-backlog`, extract the label value from the user's message. If the user used a bare name (e.g., "security"), resolve it to the namespaced form by running `gh label list --limit 100 | grep -i <name>` before invoking (rule `cq-gh-issue-label-verify-name`). Pass the resolved label via `--label <resolved>` in the skill arguments.

## Files to create

- `knowledge-base/project/specs/feat-one-shot-rename-drain-labeled-backlog/tasks.md` (generated by plan skill at Save Tasks phase)
- `knowledge-base/project/plans/2026-04-19-refactor-rename-cleanup-scope-outs-to-drain-labeled-backlog-plan.md` (this file)

No new source files, tests, or fixtures.

## Files NOT to edit (deliberate)

Historical artifacts whose content is a snapshot and must not be retroactively rewritten:

- `knowledge-base/project/specs/feat-review-backlog-workflow-improvements/tasks.md` — task list for the PR that *shipped* the old skill name. Rewriting history loses the audit trail.
- `knowledge-base/project/plans/2026-04-17-feat-review-backlog-workflow-improvements-plan.md` — ship-time plan referencing the name that was correct at plan-time.
- `knowledge-base/project/plans/2026-04-18-refactor-drain-review-followups-batch-plan.md` — references `cleanup-scope-outs` as the skill that would "re-discover" something at a date when that was its live name.
- `knowledge-base/project/learnings/2026-04-17-cleanup-scope-outs-sub-cluster-selection.md` — dated learning, filename preserved per the ARGUMENTS instruction. Body references are historical.
- `knowledge-base/project/learnings/best-practices/2026-04-17-review-backlog-net-positive-filing.md` — historical mention in the same category.

Rationale: these are git-anchored historical records. Users who `git log`-walk them should see the name as it was at that time. The skill-name is resolvable via `git log --all --diff-filter=R -M` after this PR merges.

## Implementation phases

### Phase 1 — RED (baseline test run before any edits)

1. From worktree root, run: `bash plugins/soleur/test/cleanup-scope-outs.test.sh` — all pass (sanity check on current state).
2. Run: `bun test plugins/soleur/test/components.test.ts` — verify skill discovery finds the skill and description word count is within budget.
3. Commit nothing yet. This is the "before" snapshot.

### Phase 2 — GREEN (mechanical rename)

Execute in this exact order so `git mv` records clean renames:

1. **Directory rename:**
   ```bash
   git mv plugins/soleur/skills/cleanup-scope-outs plugins/soleur/skills/drain-labeled-backlog
   ```
2. **Test file rename:**
   ```bash
   git mv plugins/soleur/test/cleanup-scope-outs.test.sh plugins/soleur/test/drain-labeled-backlog.test.sh
   ```
3. **Edit `plugins/soleur/skills/drain-labeled-backlog/SKILL.md`** per the line-level edits in "Files to edit" above. Write the new `description:` (under 1,024 chars, third person, starts with "This skill", AND **at most 26 words** — see Sharp Edges for word-budget math):

   > This skill should be used when draining a labeled issue backlog (deferred-scope-out, code-review, type/security) in one cleanup PR. Groups by code area and delegates to /soleur:one-shot.

   Word count: 26 (counted via `desc.split(/\s+/).filter(Boolean).length` — the exact tokenizer used by `plugins/soleur/test/components.test.ts`). Net delta vs. current 24-word description: **+2 words**. Cumulative post-rename total: 1798 + 2 = **1800** (at the ceiling; passes `toBeLessThanOrEqual`-style check — the test uses `>` comparison, so 1800 is fine). If verification fails, trim one word (e.g., drop "issue" → 25 words).

   Rewrite "When to use" bullets:

   > - A labeled backlog has grown and needs a scheduled drain — `deferred-scope-out` (the original use case), `code-review` (unresolved review findings), `type/security` (open security issues), or any label validated by `gh label list`.
   > - Multiple open issues carrying the target label reference the same top-level directory (e.g., `apps/web-platform`) and are safe to batch.
   > - You want one PR to close 3+ issues instead of N separate PRs.

4. **Edit `plugins/soleur/test/drain-labeled-backlog.test.sh`** per the line-level edits above (header comments, HELPER path, echo string). Leave `FIXTURE_DIR` pointing at `fixtures/cleanup-scope-outs/` — fixture dir is NOT renamed in this PR.

5. **Edit `plugins/soleur/commands/go.md`** — add the `drain` row to the Step 2 classification table and the namespaced-label-resolution note below it.

6. **Run test immediately after edits:**
   ```bash
   bash plugins/soleur/test/drain-labeled-backlog.test.sh
   ```
   All assertions pass (T6-T10 all pass — no behavior changed).

7. **Run skill-discovery + word-budget test:**
   ```bash
   bun test plugins/soleur/test/components.test.ts
   ```
   Skill count unchanged (1 skill renamed, not added). Cumulative description word count may tick up or down ~20 words; verify under 1,800.

8. **Verify zero stale refs in live code:**
   ```bash
   rg "cleanup-scope-outs" plugins/ --type md --type yaml --type sh
   ```
   Expected output: empty. Any hit here is a bug — investigate before proceeding.

   Knowledge-base refs are expected (historical, see "Files NOT to edit"); grep scoped to `plugins/` only.

9. **Markdownlint on touched .md files only** (rule `cq-markdownlint-fix-target-specific-paths`):
   ```bash
   npx markdownlint-cli2 --fix \
     plugins/soleur/skills/drain-labeled-backlog/SKILL.md \
     plugins/soleur/commands/go.md \
     knowledge-base/project/plans/2026-04-19-refactor-rename-cleanup-scope-outs-to-drain-labeled-backlog-plan.md \
     knowledge-base/project/specs/feat-one-shot-rename-drain-labeled-backlog/tasks.md
   ```
   Re-read each file after `--fix` to verify no unintended rewrites. Re-run the test in step 6 if SKILL.md was touched by the linter.

### Phase 3 — REVIEW + SHIP

- Standard `/ship` Phase 5.5 runs. No special gates expected — this is a rename with no new functionality.
- Verify PR body includes `## Changelog` with one line: `renamed cleanup-scope-outs skill to drain-labeled-backlog; added drain intent to /soleur:go` under the Minor section.
- Semver label: `semver:minor` (new routing intent = user-visible capability add, even though the underlying skill is pre-existing).
- No issue to close (`Closes #N` not applicable).

## Test Scenarios

All scenarios run via `bash plugins/soleur/test/drain-labeled-backlog.test.sh` — same assertions as pre-rename, just under the new filename.

| ID | Name | Expectation |
|---|---|---|
| T6 | Clustered cluster selection | `apps/web-platform` is top cluster; lists #2474, #2473, #2472 |
| T7 | Dispersed exits cleanly | No cluster → exit 0 + "No cleanup cluster available" |
| Empty | Zero-issue fixture | exit 0 + same no-cluster message |
| Contract | JSON output sorted | `.[0].area == "apps/web-platform"`, `.[0].count == 3` |
| T8 | Qualified paths outrank shorthand | bare `chat-input.tsx` does not beat qualified path |
| T9 | Deepest qualified path wins | `apps/web-platform/server/...` beats `server/...` |
| T10 | `--label` flag plumbing | Custom label still clusters; empty `--label` exits 2 |

**New assertion to add to T10 (optional, in-scope):** after the existing `--label code-review --fixture …` assertion, add one line asserting the `type/security` label is accepted through argv plumbing (fixture bypasses live validation, so this is argv-only). If T10 runs clean with just the existing `code-review` assertion, skip the addition — the argv plumbing is already proven.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] `git log --follow --diff-filter=R plugins/soleur/skills/drain-labeled-backlog/SKILL.md` shows the file as renamed from `plugins/soleur/skills/cleanup-scope-outs/SKILL.md` (not add+delete).
- [ ] `git log --follow --diff-filter=R plugins/soleur/test/drain-labeled-backlog.test.sh` shows the rename.
- [ ] `bash plugins/soleur/test/drain-labeled-backlog.test.sh` exits 0 with all T6-T10 passing.
- [ ] `bun test plugins/soleur/test/components.test.ts` passes; skill count unchanged; cumulative description word count < 1,800.
- [ ] `rg "cleanup-scope-outs" plugins/` returns zero hits.
- [ ] `rg "cleanup-scope-outs" knowledge-base/` returns only historical artifacts (4-5 files, all listed in "Files NOT to edit").
- [ ] `plugins/soleur/commands/go.md` Step 2 table has exactly 4 rows (`fix`, `drain`, `review`, `default`).
- [ ] SKILL.md frontmatter `description:` is under 1,024 chars (character check: `awk -F: '/^description:/ {print length($0)}' plugins/soleur/skills/drain-labeled-backlog/SKILL.md`).
- [ ] PR title is `refactor(skills): rename cleanup-scope-outs → drain-labeled-backlog; add drain intent to /soleur:go`.
- [ ] PR has `semver:minor` label.
- [ ] PR body has `## Changelog` section.

### Post-merge (operator)

- [ ] Running `/soleur:go drain the code-review backlog` routes to `drain-labeled-backlog` (dogfood verification, not blocking). One manual invocation suffices.
- [ ] If the docs site builds via Eleventy on merge, landing-page skill listing shows `drain-labeled-backlog` instead of `cleanup-scope-outs`. If docs CI flags anything, file an issue; the rename is still correct.

## Non-Goals / Out of Scope

- **Type/security drain itself.** Runs as a separate `/soleur:one-shot` invocation after this PR merges. Not blocking this PR.
- **Fixture directory rename** (`plugins/soleur/test/fixtures/cleanup-scope-outs/` → `.../drain-labeled-backlog/`). Deferred. The test file points at the old path via `FIXTURE_DIR`; the path is an implementation detail. If renamed later, the test script edit is a one-liner. **Tracking:** file a low-priority issue after merge if desired; not required.
- **Retroactive rewrites of knowledge-base historical artifacts.** See "Files NOT to edit."
- **Changes to helper script functionality.** The script is already label-generic.
- **New sharp edges or sharp-edge rewrites in SKILL.md.** All existing sharp edges are label-agnostic and carry forward verbatim.
- **`/soleur:schedule` workflow file updates.** None exist currently (schedule produces on-demand workflow YAML; the rename is a simple skill-name reference change at schedule-time).

## Alternative Approaches Considered

| Approach | Decision | Rationale |
|---|---|---|
| Add the new `drain` intent without renaming the skill | **Rejected** | Leaves name-framing-vs-implementation drift. Next time someone reads `cleanup-scope-outs` they have to re-derive that it's label-generic. One rename, all future readers see correct framing. |
| Rename + also rename fixture directory in same PR | **Deferred** | Larger blast radius for no user-visible benefit. Fixture path is an internal impl detail. Can be folded into a future PR cheaply. |
| Rename + rewrite historical knowledge-base artifacts | **Rejected** | Rewrites history. Historical records should show the name-at-time. Resolvable via `git log --follow`. |
| Add `drain` routing to `/soleur:go` via AskUserQuestion on ambiguity only | **Rejected** | Step 2 already does direct-route when intent is clear; `drain` phrasing ("drain the X backlog") is unambiguous. Keep the direct-route path. |
| Fold this rename into the upcoming type/security drain PR | **Rejected** | Mixing a refactor with a functional drain makes the drain PR's diff noisy and hard to review. Separate PRs, separate concerns. |

## Research Insights

- **Local code research:** `rg cleanup-scope-outs` returned 7 files; only 4 require edits, the other 3 are historical knowledge-base artifacts (spec snapshot, ship-time plan, drain-followups plan, two learnings). See "Files NOT to edit" for the complete list.
- **Skill-compliance checks** (from `plugins/soleur/AGENTS.md`):
  - Description uses third person ✅
  - Description under 1,024 chars ✅ (planned rewrite is ~55 words ≈ ~380 chars)
  - Cumulative description word count monitored via `bun test plugins/soleur/test/components.test.ts`
- **CLI verification** (rule `cq-docs-cli-verification`): all CLI invocations in SKILL.md (`gh issue list`, `gh label list`, `/soleur:schedule create`) are unchanged from the pre-rename file — no new CLI tokens introduced. `gh label list --limit 200` and `gh api repos/:owner/:repo/milestones` are existing, verified patterns referenced by rule `cq-gh-issue-label-verify-name` and `cq-gh-issue-create-milestone-takes-title`.
- **Git rename tracking:** `git mv` preserves history. Verify after Phase 2 step 1 with `git status` (should show `renamed: old -> new`, not `deleted: old` + `new file: new`). If history breaks, run `git reset` and redo with `git mv`.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — tooling/developer-ergonomics change. CPO/CMO/CTO review not required: no user-facing UI surface, no product strategy shift, no architectural implication. The rename is scoped to internal skill identifiers.

Product/UX Gate: **NONE** (no new component files, no new page routes, no new UI surfaces). Mechanical escalation check: plan's "Files to create" list contains ZERO entries matching `components/**/*.tsx`, `app/**/page.tsx`, or `app/**/layout.tsx`. Confirms NONE tier.

## Sharp Edges

- `git mv` records the rename only if performed **before** any content edit. If content is edited first, git sees add+delete and history is lost. Strict ordering: (1) `git mv` directory, (2) `git mv` test file, (3) content edits.
- `FIXTURE_DIR` in the renamed test file **deliberately** points at `fixtures/cleanup-scope-outs/` — don't "fix" it in this PR. Fixture dir rename is explicitly out-of-scope.
- The `description:` rewrite must stay third person. `plugins/soleur/test/components.test.ts` asserts this; a rewrite drifting into "Use this skill when…" fails the skill-compliance check.
- Sharp edges in the current SKILL.md (lines 138-147) are all label-agnostic. Resist the temptation to rewrite them "for clarity" — they are regression-encoded learnings with explicit rationale in the comments. Untouched.
- `/soleur:go` Step 2 table is **semantic-routed** — adding a row does not break existing classifications as long as the trigger phrasing is distinct. "drain the X backlog" and "fix broken Y" do not overlap. The AskUserQuestion fallback still catches true ambiguity.
- **Cumulative description word budget** — verified live during deepen-pass using the exact tokenizer from `plugins/soleur/test/components.test.ts` (`desc.split(/\s+/).filter(Boolean).length`). **Current pre-rename total: 1798 words. Budget ceiling: 1800. Available headroom: +2 words.** Current `cleanup-scope-outs` description: 24 words. Therefore the replacement description must be **≤ 26 words** to stay within budget without requiring trims elsewhere.

    The planned 26-word description (in Phase 2 step 3) lands the post-rename total at exactly 1800 — at the ceiling but compliant. If `bun test plugins/soleur/test/components.test.ts` fails on the budget assertion, drop one word (e.g., remove "issue" — "draining a labeled issue backlog" → "draining a labeled backlog") to land at 25 words / 1799 total.

    **Test tokenizer replication command** (used to verify before committing):

    ```bash
    # Cumulative check — expected output: TOTAL: 1800
    find plugins/soleur/skills -name SKILL.md | while read p; do
      awk '/^description:/ {sub(/^description: */, ""); gsub(/^"|"$/, ""); print}' "$p"
    done | tr '\n' ' ' | awk '{n=split($0, a, /[ \t\n]+/); c=0; for (i=1; i<=n; i++) if (a[i] != "") c++; print "TOTAL:", c}'
    ```

    If this drifts from the bun-native tokenizer, the bun test is authoritative.

- When the test runs clean but `rg cleanup-scope-outs plugins/` still returns hits: the directory rename may have been done before a content edit, and a file content still has the old name. Re-grep and edit.
- If `/soleur:schedule` generates a workflow file at some future date using this skill, the name `drain-labeled-backlog` flows through automatically — `/soleur:schedule create --skill <name>` takes skill name as argv.

## Deferral tracking

One optional follow-up, filed as a low-priority issue only if the rename itself succeeds cleanly:

- **Fixture directory rename.** Rename `plugins/soleur/test/fixtures/cleanup-scope-outs/` → `plugins/soleur/test/fixtures/drain-labeled-backlog/` and update `FIXTURE_DIR` in the test file. Milestone: `Post-MVP / Later`. Label: `type/refactor`. Re-evaluation criteria: cosmetic — defer indefinitely if no one notices.

No other deferrals. The type/security drain referenced in "Out of Scope" runs as a separate planned invocation (not a deferral).

## Verification checklist (Phase 2 → Phase 3)

Run all from worktree root in this order:

```bash
# 1. Unit test (main verification)
bash plugins/soleur/test/drain-labeled-backlog.test.sh

# 2. Skill-discovery + word-budget
bun test plugins/soleur/test/components.test.ts

# 3. Stale-ref scan (must be empty)
rg "cleanup-scope-outs" plugins/

# 4. Historical-ref scan (must ONLY show knowledge-base/ hits)
rg "cleanup-scope-outs" --type md

# 5. Description length (must be under 1024)
awk -F: '/^description:/ {sub(/^[^:]*: ?/, ""); print length($0)}' \
  plugins/soleur/skills/drain-labeled-backlog/SKILL.md

# 6. Markdownlint (touched files only)
npx markdownlint-cli2 --fix \
  plugins/soleur/skills/drain-labeled-backlog/SKILL.md \
  plugins/soleur/commands/go.md

# 7. Git rename tracking
git status --short | grep '^R'
# Expected: two "R" entries (directory rename shows as multiple R lines)
```

If all 7 checks pass → proceed to `/ship`.

## PR metadata

- **Title:** `refactor(skills): rename cleanup-scope-outs → drain-labeled-backlog; add drain intent to /soleur:go`
- **Semver label:** `semver:minor`
- **Body includes:** `## Changelog` section with:
  - `### Minor`
    - Renamed `cleanup-scope-outs` skill to `drain-labeled-backlog` (framing now matches its label-generic implementation; no behavior change)
    - Added `drain` intent to `/soleur:go` routing — users can now say "drain the X backlog" to trigger the skill
- **Closes:** none
- **Ref:** PR #2486 (pattern example), feat-review-backlog-workflow-improvements (origin PR that shipped the old name)
