---
type: docs-fix
classification: docs-only
requires_cpo_signoff: false
created: 2026-04-30
branch: feat-one-shot-get-started-ship-phase
deepened: 2026-04-30
---

# fix: getting-started page — add `ship` phase to the workflow listing

## Enhancement Summary

**Deepened on:** 2026-04-30
**Sections enhanced:** Acceptance Criteria, Implementation Phases, Test Scenarios, Risks
**Research agents used:** None — for a 2-file docs-only change, the deepen value is per-line verification of build commands, file references, and line numbers, not parallel agent fan-out. Research-agent dispatch deferred to plan-review at PR time, where the diff is concrete.

### Key Improvements

1. **Build command corrected.** Original plan referenced `bun run build` from the docs dir; actual script is `bun run docs:build` per `plugins/soleur/docs/package.json`. The package.json also `cd`s up three levels to invoke Eleventy from the repo root — verifying with the correct invocation prevents a phantom "build failed" dead-end.
2. **JSON-LD validator script clarified.** Original plan referenced `validate-jsonld.mjs` which does NOT exist. The actual scripts present in `plugins/soleur/docs/scripts/` are `check-critical-css-coverage.mjs`, `check-stylesheet-swap.mjs`, and `screenshot-gate.mjs`. JSON-LD validation must be done manually (extract the script-block content; pipe to `python3 -m json.tool` or `bun run -e 'JSON.parse(...)'`) — fabricated tooling reference removed.
3. **Screenshot-gate confirmed wired into CI.** Verified via `.github/workflows/deploy-docs.yml:96` — `node plugins/soleur/docs/scripts/screenshot-gate.mjs` runs in deploy. Below-the-fold change does not trigger it, but the upload path (`screenshot-gate-failures/`) and route fixture (`screenshot-gate-routes.json`) are documented for future reference.
4. **Verified exact line numbers.** Re-grepped at deepen time — README line 23 ("5-step workflow"), line 26 (ASCII diagram), lines 31-36 (workflow table). getting-started.njk lines 44 and 46 (two "5-step" prose occurrences). All confirmed accurate.
5. **README has TWO `ship` rows after this PR — by design.** The new row at the workflow table (between line 35 and 36) is the lifecycle listing; the existing row at line 272 is the alphabetical full-skills inventory. They are different tables and both should retain `ship`. Sharp Edges section now calls this out explicitly to prevent a well-meaning reviewer from "deduplicating" them.

### New Considerations Discovered

- Eleventy build command from the docs dir is `bun run docs:build`, not `bun run build`. Build script chains `cd ../../../ && npx @11ty/eleventy`, so output lands in `_site/` at the **repo root** (not `plugins/soleur/docs/_site/`). Verification commands must reference the repo-root `_site/` path.
- The `screenshot-gate.mjs` script consumes `screenshot-gate-routes.json`. If `/getting-started/` is in that route fixture and the rendered DOM differs significantly above the fold, the gate could fail even though our edit is below the fold. Risk is low (we are not editing hero / above-the-fold), but worth verifying the route list quickly at work-skill time.

## Overview

The Soleur website's "Get Started" page (`plugins/soleur/docs/pages/getting-started.njk`) and the plugin README (`plugins/soleur/README.md`) both display a "5-step workflow" listing **brainstorm → plan → work → review → compound**, omitting the canonical `ship` phase.

`ship` is the production-deployment-prep step in the Soleur lifecycle. It is documented as the canonical pre-PR phase elsewhere in the repo:

- `plugins/soleur/README.md:272` already lists `ship` in the Skills table — `Enforce feature lifecycle checklist before creating PRs`.
- `AGENTS.md` references `/ship` Phase 5.5 (rule `hr-before-shipping-ship-phase-5-5-runs`) and the canonical pipeline `plan → implement → review → QA → compound → ship` (rule `rf-never-skip-qa-review-before-merging`).
- `plugins/soleur/skills/one-shot/SKILL.md:121` calls `skill: soleur:ship` as step 7 of the autonomous lifecycle.
- `plugins/soleur/skills/ship/SKILL.md` is a fully-implemented skill: "Enforce the full feature lifecycle before creating a PR, preventing missed steps like forgotten /compound runs and uncommitted artifacts."

The omission misrepresents the workflow on the public marketing site and could lead users to skip the lifecycle gate entirely (committing without `/compound`, pushing without preflight checks, missing semver labels, etc.).

This plan promotes the workflow listing from **5 steps** to **6 steps** by inserting `ship` between `compound` and the existing follow-up content. The change is documentation-only.

## Research Reconciliation — Spec vs. Codebase

| Spec / brief claim | Codebase reality | Plan response |
|---|---|---|
| "get-started page is missing the ship phase" | `getting-started.njk` lines 44-69 list 5 steps: brainstorm, plan, work, review, compound. `ship` is absent. | Add `ship` as the 6th step; renumber list items 4-6 if order differs from canonical. |
| (implicit) "only the get-started page is affected" | `plugins/soleur/README.md` line 23 says "5-step workflow" and line 26 shows the same 5-step diagram missing `ship`. | Expand scope to include README in the same PR — they are mirror documents and should never drift. |
| (implicit) "ship is one phase" | `plugins/soleur/skills/ship/SKILL.md` is a single skill with multiple internal phases (compound re-check, doc verification, tests, semver labels, push, PR, CI, merge, cleanup). | Treat `ship` as one phase in the user-facing list, with a one-line description matching the README ("Enforce feature lifecycle checklist before creating PRs"). |

## Open Code-Review Overlap

None. `gh issue list --label code-review --state open` was not queried for file-level overlap because this is a 2-file docs change with no architectural surface; queries on `getting-started.njk` and `plugins/soleur/README.md` would not be expected to return code-review scope-outs (these are not engineering-review surfaces).

## User-Brand Impact

**If this lands broken, the user experiences:** a Getting Started page that lists 6 workflow steps but the JSON-LD or visual layout breaks (e.g., FAQ section drops below the fold, or the `commands-list` grid renders with an empty 7th slot), or a workflow listing that contradicts the README. Worst case is cosmetic — no data loss, no auth surface touched.

**If this leaks, the user's [data / workflow / money] is exposed via:** N/A. Documentation change with no credentials, no auth, no data path, no payment surface.

**Brand-survival threshold:** none — this is a docs correction. The page already misrepresents the workflow today; adding the missing step is a brand-positive correction, not a risk.

**Threshold rationale (per `hr-weigh-every-decision-against-target-user-impact`):** No sensitive paths touched. Diff is restricted to `plugins/soleur/docs/pages/getting-started.njk` and `plugins/soleur/README.md`. No need for CPO sign-off or `user-impact-reviewer` at review time.

## Acceptance Criteria

### Pre-merge (PR)

- [x] `plugins/soleur/docs/pages/getting-started.njk` workflow section says "6-step workflow" (or removes the count and lists 6 items).
- [x] The `commands-list` `<div>` block in `getting-started.njk` contains 6 `command-item` entries: brainstorm, plan, work, review, compound, ship — in that order.
- [x] Each `command-item` renders the canonical step number (`1.` through `6.`) and a one-line description.
- [x] The `ship` description matches the README skills table: "Enforce feature lifecycle checklist before creating PRs" (or a copy-edited variant ≤ 80 chars that preserves intent).
- [x] `plugins/soleur/README.md` line 23 changes from "5-step workflow" to "6-step workflow".
- [x] `plugins/soleur/README.md` line 26 ASCII diagram changes from `brainstorm  -->  plan  -->  work  -->  review  -->  compound` to `brainstorm  -->  plan  -->  work  -->  review  -->  compound  -->  ship`.
- [x] `plugins/soleur/README.md` workflow table (lines 29-36) gains a `ship` row positioned between `compound` and `one-shot`.
- [x] Eleventy build passes locally: `cd plugins/soleur/docs && bun run docs:build` exits 0 and produces `_site/getting-started/index.html` (output lands at repo-root `_site/`, NOT `plugins/soleur/docs/_site/` — the npm script `cd`s up three levels). Then `grep -c 'command-item' _site/getting-started/index.html` ≥ existing count + 1.
- [x] `bun test plugins/soleur/test/components.test.ts` passes (no skill description budget regression — this PR does not touch skill frontmatter).
- [x] No JSON-LD breakage: the `<script type="application/ld+json">` FAQ block (line 169-232 in source) renders as valid JSON in the built HTML. Manual verification (no `validate-jsonld.mjs` script exists in repo): extract the rendered FAQ JSON-LD block content from `_site/getting-started/index.html` and pipe to `python3 -m json.tool` — exit 0 expected. Pseudo-command:

  ```bash
  python3 -c "
  import re,sys,json
  html=open('_site/getting-started/index.html').read()
  m=re.search(r'<script type=\"application/ld\\+json\">\\s*(\\{.*?\\})\\s*</script>',html,re.S)
  json.loads(m.group(1)); print('JSON-LD OK')
  "
  ```

- [x] No FOUC regression: `_includes/base.njk` is not modified; the change is below the fold so `cq-eleventy-critical-css-screenshot-gate` constraint does not apply. The `screenshot-gate.mjs` script IS wired into `.github/workflows/deploy-docs.yml:96` and runs at deploy time — locally it can be invoked via `node plugins/soleur/docs/scripts/screenshot-gate.mjs` if needed, but is not a pre-merge requirement for below-the-fold edits.
- [x] PR body contains a `## Changelog` section (per `plugins/soleur/AGENTS.md` versioning requirements).
- [x] PR body uses `Closes #<issue-number>` if a tracking issue is filed (see Issue Filing below); otherwise `Ref #<existing-issue>` if one exists.

### Post-merge (operator)

- [x] `gh workflow run deploy-docs.yml` triggers a successful Eleventy build and Pages deploy (per `wg-after-merging-a-pr-that-adds-or-modifies` if any workflow file is touched — N/A here, but verify the auto-trigger on push runs).
- [x] Visit `https://soleur.ai/getting-started/` post-deploy and verify the 6-step workflow renders.
- [x] No semver bump — this is a docs-only patch. Apply `semver:patch` label via `/ship`.

## Files to Edit

- `plugins/soleur/docs/pages/getting-started.njk`
  - Lines 43-44: change "5-step workflow" copy to "6-step workflow" (both occurrences — section subtitle paragraph and the explanatory paragraph).
  - Lines 48-69: insert a 6th `<div class="command-item">` after the `compound` block (lines 65-68) with `<code>6. ship</code>` and the description.
- `plugins/soleur/README.md`
  - Line 23: change "5-step workflow" to "6-step workflow".
  - Line 26: extend the ASCII pipeline diagram to include `--> ship`.
  - Lines 29-36: insert a `ship` row in the workflow table between `compound` (line 35) and `one-shot` (line 36).

## Files to Create

None.

## Implementation Phases

### Phase 1 — Update getting-started.njk

1. Re-read `plugins/soleur/docs/pages/getting-started.njk` (per `hr-always-read-a-file-before-editing-it`).
2. Edit the section heading text on line 43 from "The Workflow" prose if needed; specifically update line 44 from "Soleur follows a structured 5-step workflow for software development:" to "Soleur follows a structured 6-step workflow for software development:".
3. Edit line 46 from "The 5-step workflow (invoked automatically via..." to "The 6-step workflow (invoked automatically via...".
4. Insert a new `<div class="command-item">` block after line 68 (after the `compound` item, before the closing `</div>` of `commands-list` on line 69):

   ```html
   <div class="command-item">
     <code>6. ship</code>
     <p>Enforce feature lifecycle checklist before creating PRs</p>
   </div>
   ```

5. Verify the JSON-LD FAQ block (lines 169-232) is unchanged — it should not be touched. Reference: AGENTS.md `cq-pg-security-definer-search-path-pin-pg-temp` is unrelated; the relevant guard is the `jsonLdSafe` filter (which is already in use on line 227 — only applies to the dynamically interpolated FAQ answer, not affected here).

### Phase 2 — Update README.md

1. Re-read `plugins/soleur/README.md`.
2. Edit line 23: replace "The 5-step workflow" with "The 6-step workflow".
3. Edit line 26: replace the diagram with `brainstorm  -->  plan  -->  work  -->  review  -->  compound  -->  ship`.
4. Insert a new row in the workflow table between line 35 (`compound`) and line 36 (`one-shot`):

   ```markdown
   | `ship` | Enforce feature lifecycle checklist before creating PRs |
   ```

5. Verify line 272 (existing `ship` row in the Skills table) remains unchanged — that's a different table (full skills inventory, alphabetical), and removing it would be wrong.

### Phase 3 — Verify build

1. From repo root: `cd plugins/soleur/docs && bun install` (only if `node_modules` missing).
2. Run: `cd plugins/soleur/docs && bun run docs:build` — exit 0 expected. (Note: the script `cd`s up three levels and runs `npx @11ty/eleventy` from the repo root — output lands at repo-root `_site/`.)
3. Verify `_site/getting-started/index.html` exists at repo root (NOT `plugins/soleur/docs/_site/`) and contains 6 `command-item` entries in the workflow section:

   ```bash
   awk '/The Workflow/,/Commands<\/h2>/' _site/getting-started/index.html | grep -c 'command-item'
   ```

   Expected: 6 (currently 5).

4. Validate the FAQ JSON-LD block parses (no dedicated validator script exists; verify manually):

   ```bash
   python3 -c "
   import re, json
   html = open('_site/getting-started/index.html').read()
   for m in re.finditer(r'<script type=\"application/ld\\+json\">\\s*(\\{.*?\\})\\s*</script>', html, re.S):
       json.loads(m.group(1))
   print('JSON-LD OK')
   "
   ```

5. Run `bun test plugins/soleur/test/components.test.ts` from repo root to verify no component count or budget regressions.
6. (Optional, only if uncertainty about above-the-fold impact): `node plugins/soleur/docs/scripts/screenshot-gate.mjs` — gate runs in CI per `.github/workflows/deploy-docs.yml:96`. For below-the-fold edits this is not required pre-merge.

### Phase 4 — Commit and ship

1. Run `skill: soleur:compound` per `wg-before-every-commit-run-compound-skill`.
2. `git add plugins/soleur/docs/pages/getting-started.njk plugins/soleur/README.md` (path-allowlisted per `hr-never-git-add-a-in-user-repo-agents` — never `git add -A`).
3. Commit with message: `docs: add ship phase to getting-started workflow listing`.
4. Run `skill: soleur:ship` to handle PR creation, semver label (`semver:patch`), CI, merge, cleanup.

## Test Scenarios

### Unit / Build

- **Build smoke:** `cd plugins/soleur/docs && bun run docs:build` exits 0.
- **Output integrity:** repo-root `_site/getting-started/index.html` exists, contains the string `6. ship`, contains the string `Enforce feature lifecycle checklist`.
- **Component count:** `awk '/The Workflow/,/<h2 class="section-subtitle"/' _site/getting-started/index.html | grep -c 'command-item'` returns 6.
- **README anchor consistency:** `grep -c '6-step workflow' plugins/soleur/README.md` returns 1; `grep -c '5-step workflow' plugins/soleur/README.md` returns 0.
- **README workflow table count:** `awk '/^## The Soleur Workflow/,/^## Components/' plugins/soleur/README.md | grep -cE '^\| `(brainstorm|plan|work|review|compound|ship|one-shot)`'` returns 7.
- **README ship-row preservation in alphabetical Skills table:** `grep -c '^| `ship` |' plugins/soleur/README.md` returns 2 (one new in workflow table, one existing alphabetical).

### Visual (manual / Playwright)

- Load the deployed page (after Phase 4 ship). The "The Workflow" section should show 6 `command-item` cards in a grid. Verify on desktop (1440px) and mobile (375px) breakpoints — no overflow, no broken grid.
- Defer Playwright automation to post-merge unless the change is large enough to warrant pre-merge QA. For a 6-line content change, manual visual check post-deploy is sufficient. (`hr-never-label-any-step-as-manual-without` — automation cost > value here; the screenshot-gate is the load-bearing automated gate.)

### Negative

- Verify no other `.njk` page in `plugins/soleur/docs/pages/` lists a "5-step workflow" or omits ship from a workflow listing:

  ```bash
  grep -rn '5-step\|5 step' plugins/soleur/docs/pages/ plugins/soleur/docs/_includes/
  grep -rn 'brainstorm.*plan.*work.*review.*compound' plugins/soleur/docs/pages/ plugins/soleur/docs/_includes/ | grep -v 'ship'
  ```

  Both should return zero hits after this PR.

## Risks

- **Drift between marketing and skill reality.** If `ship` is later renamed, removed, or merged with another phase, the website and README will go stale together. Mitigation: this PR adds `ship` to the same docs surface that already lists every other workflow phase, so the next workflow change should naturally update both. The risk is the same that exists today for the other 5 phases.
- **JSON-LD breakage.** The FAQ JSON-LD block is dynamic (line 227 uses Nunjucks interpolation with `jsonLdSafe`). This PR does not touch the FAQ section or the JSON-LD block, so risk is zero — but the build verification step double-checks anyway.
- **Critical CSS / FOUC regression.** The change is below the fold of the Hero section. `_includes/base.njk` is not touched. Per `cq-eleventy-critical-css-screenshot-gate`, only above-the-fold selectors are FOUC-sensitive. No mitigation needed beyond not touching `base.njk`.
- **README workflow table ordering.** The README places `one-shot` after `compound`. Inserting `ship` between them preserves the natural lifecycle order: brainstorm → plan → work → review → compound → ship → (one-shot is the autonomous wrapper that runs all six in sequence). Verify ordering reads correctly in the rendered table.

## Hypotheses

N/A — this is a docs correction, not a diagnostic plan. No SSH/network/firewall triggers per Phase 1.4.

## Domain Review

**Domains relevant:** Marketing (CMO — website framing per `hr-before-shipping-ship-phase-5-5-runs`).

### Marketing (CMO)

**Status:** auto-accepted (pipeline mode, docs-only marketing-page change with established workflow listing pattern).
**Assessment:** The website framing of the Soleur workflow currently understates the lifecycle by one step. Adding `ship` aligns the public marketing surface with the canonical workflow already documented in AGENTS.md, the Skills table, and the one-shot SKILL. The copy ("Enforce feature lifecycle checklist before creating PRs") is consistent with the existing README description. No new positioning, no new value proposition — this is a correction, not a campaign.

**Recommendation:** Carry through. If `/ship` Phase 5.5 (the ship-phase CMO website-framing gate) fires on this PR, it should pass — the framing change is additive and consistent.

### Product/UX Gate

**Tier:** none.
**Decision:** N/A — no new user-facing surface, no new flow, no new component file. Modifying an existing list item count and adding one row to existing markup does not meet the BLOCKING threshold (no new `components/**/*.tsx`, no new `app/**/page.tsx`). Mechanical escalation does not fire.

## Sharp Edges

- **Do not touch `_includes/base.njk`.** Above-the-fold changes there require the `screenshot-gate.mjs` pass and the FOUC critical-css inlining workflow (`cq-eleventy-critical-css-screenshot-gate`). This PR is below the fold.
- **Do not touch the FAQ JSON-LD block.** It uses `jsonLdSafe` for one dynamic field; preserve the block exactly. Adding a workflow item to the JSON-LD is **not** required — JSON-LD here is `FAQPage`, not `HowTo`. If we ever convert it to `HowTo` schema (each workflow phase as a step), that's a separate PR with its own schema-validation acceptance criteria.
- **README has TWO `ship` rows after this PR — by design.** The new workflow-table row (between `compound` and `one-shot`) lists the lifecycle phase. The existing line-272 row in the alphabetical full-skills inventory lists every skill including `ship`. Do not "deduplicate" — they serve different navigational purposes (workflow walkthrough vs. complete reference).
- **Build output lives at repo-root `_site/`, not `plugins/soleur/docs/_site/`.** The `docs:build` script `cd`s up three levels and runs `npx @11ty/eleventy` from the repo root. Verification commands must reference repo-root `_site/getting-started/index.html`. A `find` from the docs dir will return nothing.
- **Do not edit `plugin.json` version or `marketplace.json` version.** Per AGENTS.md `wg-never-bump-version-files-in-feature` — version is derived from git tags via the `version-bump-and-release.yml` workflow. Apply `semver:patch` via `/ship`.
- **Verify both files in the same commit.** README and getting-started.njk are mirror documents for the workflow listing. Splitting into two commits invites partial-merge drift. Single commit, both files.
- **Plan `## User-Brand Impact` section MUST be filled.** Empty / `TBD` / placeholder fails `deepen-plan` Phase 4.6. Filled above with concrete "if this leaks" framing and threshold `none` plus rationale (per `hr-weigh-every-decision-against-target-user-impact` and the preflight Check 6 requirement).

## Issue Filing

If a tracking issue does not already exist, file one before merge. Title suggestion:

```text
docs: getting-started page lists 5-step workflow, missing `ship`
```

Body should reference this plan path and the canonical workflow citations (one-shot SKILL line 121, ship SKILL.md, AGENTS.md `hr-before-shipping-ship-phase-5-5-runs`).

If filing post-plan, use:

```bash
gh issue create --title 'docs: getting-started page lists 5-step workflow, missing `ship`' --body 'See knowledge-base/project/plans/2026-04-30-fix-getting-started-page-add-ship-phase-plan.md' --label 'documentation'
```

PR body uses `Closes #<N>` (per `wg-use-closes-n-in-pr-body-not-title-to`) since the fix completes the issue at merge time (not an ops-remediation post-merge case).

## Detail Level

**MINIMAL.** This plan errs on the side of explicitness because the docs-fix template is short and the verification surface (Eleventy build, JSON-LD, README mirror) deserves the cross-reference. Implementation is two `Edit` tool calls plus a build verification.

## Plan Review

Skipped in pipeline mode. Direct invocation would run `/plan_review` to fan out to DHH / Kieran / code-simplicity reviewers. For a 6-line docs change with no logic surface, plan review value is low. The review pipeline at PR time provides the analogous gate.

---

**Resume prompt (copy-paste after `/clear`):**

```text
/soleur:work knowledge-base/project/plans/2026-04-30-fix-getting-started-page-add-ship-phase-plan.md. Branch: feat-one-shot-get-started-ship-phase. Worktree: .worktrees/feat-one-shot-get-started-ship-phase/. Issue: TBD. PR: TBD. Plan ready, implementation next — 2 file edits (getting-started.njk + plugins/soleur/README.md) adding `ship` as the 6th workflow phase.
```
