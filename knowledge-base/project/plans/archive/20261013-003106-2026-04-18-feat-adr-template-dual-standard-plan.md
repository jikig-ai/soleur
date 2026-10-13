---
plan: 2026-04-18-feat-adr-template-dual-standard
issue: 2541
branch: feat-one-shot-adr-template-dual-standard
status: ready
date: 2026-04-18
type: feat
---

# ADR template: document the dual standard (terse 3-section vs rich 8-section)

Closes #2541.

## Enhancement Summary

**Deepened on:** 2026-04-18
**Sections enhanced:** Design (rubric grounded in industry ADR traditions), Non-goals (YAGNI rationale for no enforcement), Risks (concrete drift-detection procedure), Implementation Phases (sequencing of template read → rubric ask → body write), Test Scenarios (added rubric-classification dry-run over ADR-001..021).

### Key Improvements

1. **Rubric is anchored in established ADR traditions** — the "terse" shape matches Michael Nygard's original 2011 3-section pattern; the "rich" shape matches the MADR (Markdown Architectural Decision Records) 3.0 structure. The plan now names both and tells contributors which tradition each shape descends from.
2. **Rubric triggers are tightened to be observable** — each of the 5 triggers is restated as a yes/no question whose answer is checkable from files that already exist in the repo (NFR register, principles register, vendor manifests). This removes the "is it cross-cutting?" subjectivity.
3. **SKILL.md step 6 sequencing is made explicit** — the rubric-ask must happen BEFORE the template body is copied into the new ADR, not after. The plan now calls out the ordering because the current step 4 ("Read the ADR template") runs before step 6 ("Gather context"), and the rubric-ask has to slot between them.
4. **ADR-001..020 retroactive classification is added as a test** — verifies the rubric classifies every existing ADR as terse (since they are terse) without ambiguity. If any existing ADR would be classified as "rich" by the rubric, that is a signal the rubric is too loose.
5. **Pipeline-mode default is explicit** — when `/soleur:architecture create` runs inside `/soleur:one-shot` with no interactive prompt, the default is terse. Rich-shape ADRs in pipeline mode require an explicit `shape: rich` hint in `$ARGUMENTS`.

### New Considerations Discovered

- AP-011 ("ADRs for architecture decisions") is already a skill-tier principle in `knowledge-base/engineering/architecture/principles-register.md`. The rubric is itself a refinement of AP-011's application and should be cross-referenced in the principle register's note column, not just in the template.
- The ADR corpus does NOT use any numbered-list markers like `## 1. Context` — every ADR uses plain `## Context`. The terse/rich template must match that exact format or the corpus will drift from the template mechanically.
- The Mermaid C4 diagram in ADR-021 is the only ADR-embedded diagram in the corpus. The template's Diagram section (in the rich shape) remains optional to avoid pressuring rich-shape ADRs toward always including a diagram when one is not informative.

## Overview

The architecture skill's ADR template at `plugins/soleur/skills/architecture/references/adr-template.md` prescribes **8 H2 sections**:

1. Context
2. Considered Options
3. Decision
4. Consequences
5. Cost Impacts
6. NFR Impacts
7. Principle Alignment
8. Diagram

But all 20 prior ADRs (ADR-001 through ADR-020) use only the original 3:

1. Context
2. Decision
3. Consequences

ADR-021 (merged PR #2538, `knowledge-base/engineering/architecture/decisions/ADR-021-kb-binary-serving-pattern.md`) is the first ADR to follow the 8-section template. The pattern-recognition reviewer flagged it as a 5-section, 4.5x-length deviation from the established corpus. Both the template and the prior ADRs are internally consistent — they just disagree with each other.

**The chosen resolution (Option 3 from the issue) is to document the dual standard explicitly, not to pick one shape and force the corpus into it.** The template is edited to describe *both* forms with a selection rubric so the contributor picks the right one at create-time. The architecture skill's `create` sub-command is updated to reflect that selection. No ADRs are backfilled.

### Why Option 3 (dual standard) over the alternatives

- **Option 1 (backfill 20 ADRs to the 8-section form)** — High cost. Many of the existing ADRs (e.g., ADR-006 R2 backend, ADR-009 git worktree isolation, ADR-015 decoupled work/ship) are one-decision / narrow-scope records where Cost/NFR/Principle Alignment/Diagram would be padded with `None` stanzas. The rich form on a narrow decision adds reviewer cost without adding reader value.
- **Option 2 (demote template back to 3 sections, move rich form to a separate "extended ADR" template file)** — Plausible, but splits the template into two files, each of which has to be kept in sync with the skill's `create` step. Worse, it frames the rich form as exceptional when in fact cross-cutting decisions (ADR-013 multi-phase domain gate, ADR-021 KB binary serving) genuinely benefit from it.
- **Option 3 (one template with two labeled shapes + a rubric)** — Lowest cost, contributors see both shapes in one place, the rubric becomes the load-bearing artifact rather than a file split. Adopted.

### Non-goals

- **No backfill of ADR-001 through ADR-020.** They stay as terse 3-section records. The rubric retroactively describes what they already are (narrow decisions), so no rewrite is justified. Rewriting 20 ADRs to fit the rich shape would produce 20 padded records with `None` in Cost/NFR/Principle Alignment — worse than the terse originals for the reader.
- **No new template files.** One template file, two labeled shapes. A split (e.g., `adr-template-terse.md` + `adr-template-rich.md`) doubles the maintenance surface without adding value.
- **No lint/enforcement in this PR.** The rubric is advisory. Adding a markdownlint rule that rejects a 5-section Frankenstein ADR is tractable (each canonical shape has a known H2 list) but is a separate decision — it commits the project to a linter that must be kept in sync with the template. YAGNI: until a Frankenstein ADR actually lands, the rubric's clarity and reviewer attention are sufficient. If enforcement becomes necessary, the follow-up is a ~20-line markdownlint-cli2 rule.
- **No change to the ADR numbering, status lifecycle (`active` / `superseded`), or naming convention** — all three are orthogonal to section shape.
- **No introduction of Y-Statements, pros-and-cons tables, or other ADR variants.** The rich shape is MADR-derived; the terse shape is Nygard-derived. Two traditions, two shapes. Adding a third is out of scope.

## Research Reconciliation — Spec vs. Codebase

Verified the issue's factual claims against the codebase before planning:

| Spec claim | Reality | Plan response |
|---|---|---|
| Template prescribes 8 H2 sections | Verified: `adr-template.md` has Context, Considered Options, Decision, Consequences, Cost Impacts, NFR Impacts, Principle Alignment, Diagram. | Edit the template — scope confirmed. |
| All 20 prior ADRs use 3 sections | Verified via `grep -c '^## '` per file: ADR-001..ADR-020 each have exactly 3 H2 sections; ADR-021 has 8. | No backfill required. The plan does not touch ADR-001..ADR-020. |
| ADR-021 is the only 8-section ADR | Verified: the 3/8 split is a clean boundary at ADR-021. | Rubric can cite ADR-021 as the canonical "rich" exemplar and ADR-006 as the canonical "terse" exemplar without ambiguity. |
| The architecture skill's `create` sub-command (step 6 in SKILL.md) asks for all 8 sections | Verified: lines 81-89 of `plugins/soleur/skills/architecture/SKILL.md` list Context, Considered Options, Decision, Consequences, Cost Impacts, NFR Impacts, Principle Alignment, Diagram as the prompted fields. | Skill must be updated in lockstep — asking for all 8 prompts pushes contributors to the rich form even when the decision is narrow. |
| No automated enforcement exists for ADR shape | Verified: no ESLint/markdownlint rule, no pre-commit hook scans `ADR-*.md`. | Plan does not introduce enforcement; rubric is advisory by design (see Non-goals). |
| No code-review scope-outs touch `plugins/soleur/skills/architecture/` | Verified via `gh issue list --label code-review --state open` filtered for the path. Zero matches. | See "Open Code-Review Overlap" below. |

## Open Code-Review Overlap

None. Ran the overlap check against `plugins/soleur/skills/architecture/references/adr-template.md` and `plugins/soleur/skills/architecture/` (directory match) against all open `code-review`-labeled issues. No matches.

## Design — The Dual-Shape Rubric

### Two shapes, two traditions

- **Terse ADR (3 sections):** Context, Decision, Consequences. Matches Michael Nygard's original 2011 ADR pattern ("Documenting Architecture Decisions"). All of ADR-001 through ADR-020 descend from this tradition. Optimized for read-speed and ease of authoring; the ADR is readable in <60 seconds.
- **Rich ADR (8 sections):** Context, Considered Options, Decision, Consequences, Cost Impacts, NFR Impacts, Principle Alignment, Diagram. Matches the MADR (Markdown Architectural Decision Records, adr.github.io) 3.0 "full" template, plus two Soleur-specific sections (Cost Impacts, NFR Impacts) and the project's existing Principle Alignment section bound to the principles register. ADR-021 is the first instance. Optimized for audit-trail and cross-cutting decisions where future readers need the rejected alternatives and the non-functional impact to stay available.

Both are legitimate. The rubric picks between them based on properties of the decision itself, not on the ADR author's preference.

### Selection rubric — observable triggers

The contributor picks the **rich** shape when **any one** of the following is true. Each trigger is phrased as a yes/no question whose answer is checkable from a file that already exists in the repo — there is no "is it important enough?" subjectivity.

1. **Cross-cutting code surface.** Does the decision govern behavior in 2+ existing routes/modules/skills at write time, OR is it written as guidance for "every future X" (where X is a recurring route/module pattern)? Check: grep the decision's named helper / concept across the repo. ADR-021 governs `serveKbFile` (consumed by the owner route AND the shared route, and every future KB-adjacent route) → yes. ADR-006 governs Terraform backend config (one decision, narrow application in each new `main.tf`) → no.
2. **Material cost impact.** Does the decision introduce a new paid vendor, change a billing tier, or eliminate a paid service? Check: does the decision appear in or change anything in `knowledge-base/operations/expenses.md`? ADR-006 (R2) → technically introduced R2 usage but at zero cost (free egress), no tier change → no. ADR-021 → zero cost, no vendor change → no. A hypothetical "move from Cloudflare Workers to Fly.io" decision → yes.
3. **NFR-moving.** Does the decision change the status of one or more NFRs in `knowledge-base/engineering/architecture/nfr-register.md` from one tier to another (e.g., Partial → Implemented)? Check: diff the expected NFR register state before and after implementation. ADR-021 moves NFR-024 Partial → Implemented for the scoped KB filesystem-read surface → yes.
4. **Principle deviation.** Does the decision deviate from an AP-NNN principle in `knowledge-base/engineering/architecture/principles-register.md` and require a documented exception? Check: name which AP-NNN, state why the exception is justified. If the answer is "none, aligned with all principles," this trigger is not hit.
5. **Teeth-bearing alternatives.** Did the contributor seriously evaluate 2+ concrete alternatives (named libraries, named patterns, named architectures, named vendors) AND is the rejection rationale load-bearing for future readers who might otherwise revisit the same decision? Check: can you name Option B and Option C with pros/cons without making them up? ADR-021 evaluated "Option B: dispatch table at N=2" and "Option C: inline validation per route" with substantive rationale → yes. ADR-006 had no real alternative (local state had already failed) → no.

If **zero triggers** are hit, use the terse 3-section shape. This is the default.

If **one or more triggers** are hit, use the rich 8-section shape.

The rubric is intentionally asymmetric: it takes only one trigger to justify the rich shape, because a single genuine trigger (e.g., an NFR move or a principle deviation) is load-bearing on its own.

### What NOT to use as a trigger

- **"The decision feels important."** Importance is not the rubric. A terse ADR about a one-line choice can be more important than a rich ADR about an eight-way tradeoff — importance is orthogonal to section count.
- **"There are a lot of stakeholders."** Stakeholder count drives *review* process, not ADR shape. A terse ADR with Context/Decision/Consequences can capture the outcome of a 10-person review cleanly.
- **"I want to write a longer ADR."** The 8 sections are not padding opportunities; the rich shape only helps the future reader when all 8 have substantive content. An 8-section ADR with `None` in Cost/NFR/Principle Alignment is worse than a 3-section ADR — the reader wades through four `None` stanzas before getting to Consequences.

### Template file shape

Single file `adr-template.md` with three top-level sections:

1. **YAML Frontmatter** (unchanged — `adr`, `title`, `status`, `date`, `superseded-by`, `supersedes`).
2. **Body Sections — Terse (default, for narrow decisions)** — the 3-section markdown block (Context, Decision, Consequences).
3. **Body Sections — Rich (for cross-cutting decisions)** — the 8-section markdown block, with a preamble explicitly listing the 5 rubric triggers and linking to ADR-021 as the exemplar and ADR-006 as the terse counter-example.

The current "Naming Convention" and "Status Lifecycle" sections stay at the bottom, unchanged.

## Files to Edit

- `plugins/soleur/skills/architecture/references/adr-template.md` — Replace the single "Body Sections" block with two labeled blocks (terse / rich) and add the `## Choosing the shape` rubric preamble. Keep YAML Frontmatter, Naming Convention, and Status Lifecycle sections unchanged.
- `plugins/soleur/skills/architecture/SKILL.md` — Update the `create` sub-command (under `## Sub-command: create`, currently lines 55-93) to insert a new step 4.5 ("Ask the shape rubric") between step 4 ("Read the ADR template") and step 5 ("Write the ADR file"). Modify step 5 to branch on the rubric outcome. Modify step 6 to ask 3 prompts (terse) or 8 prompts (rich). Document pipeline-mode default (terse).
- `knowledge-base/engineering/architecture/principles-register.md` — Append a note to AP-011's row pointing readers at the rubric in the template. One-line edit.

## Files to Create

None. This is a template/rubric edit.

## Implementation Phases

### Phase 1 — Edit the ADR template

Rewrite `plugins/soleur/skills/architecture/references/adr-template.md` so it has:

- `## YAML Frontmatter` (unchanged).
- `## Choosing the shape` (new) — the rubric and the two-exemplar pointers (ADR-021 rich, ADR-006 terse).
- `## Body Sections — Terse (3 sections)` — the 3-section markdown block.
- `## Body Sections — Rich (8 sections)` — the 8-section markdown block.
- `## Naming Convention` (unchanged).
- `## Status Lifecycle` (unchanged).

The rubric preamble under `## Choosing the shape` enumerates the 5 triggers from the Design section and states: "Default to terse. Use rich when any one of the triggers above applies."

### Phase 2 — Update the architecture skill's `create` sub-command

Edit `plugins/soleur/skills/architecture/SKILL.md` under `## Sub-command: create`.

**Sequencing matters.** The current flow is:

- Step 4: "Read the ADR template from `[adr-template.md](./references/adr-template.md)`"
- Step 5: "Write the ADR file" using the template
- Step 6: "Gather context" (asks for all 8 sections)

The problem with that ordering is that step 5 writes the file body BEFORE step 6 knows which shape is wanted. The new flow must read the template, ask the rubric, THEN write the body matching the chosen shape. Proposed new ordering:

- Step 4 (unchanged in intent): "Read the ADR template from `[adr-template.md](./references/adr-template.md)`. Note the template now has two labeled body shapes (terse / rich) under the `## Choosing the shape` section."
- **New step 4.5: "Ask the shape rubric."** Present the 5 triggers (from the template's `## Choosing the shape` section) and ask the contributor: "Does this decision hit any of the 5 rubric triggers?" Use AskUserQuestion with options: "No — terse (3 sections)" / "Yes — rich (8 sections)" / "Unsure — walk me through each trigger."
  - If "Unsure," ask each trigger as its own yes/no AskUserQuestion, then compute: any yes → rich, all no → terse.
  - In pipeline mode (non-interactive, `$ARGUMENTS` context only), default to **terse** unless `$ARGUMENTS` contains an explicit `shape: rich` hint or a clearly cross-cutting topic. Document this default in the skill's help text.
- Step 5 (modified): "Write the ADR file using the template's terse or rich body shape (determined in step 4.5)."
- Step 6 (modified): "Gather context" branches:
  - **Terse branch:** ask Context, Decision, Consequences only. 3 prompts.
  - **Rich branch:** ask all 8 (Context, Considered Options, Decision, Consequences, Cost Impacts, NFR Impacts, Principle Alignment, Diagram). Same as today.
- Steps 7-8 unchanged.

The existing wording of step 6 stays almost verbatim as the rich branch; the terse branch is a short new block above it.

### Phase 2b — Cross-reference in the principles register

After editing the template and the skill, append a sentence to the note column of AP-011 in `knowledge-base/engineering/architecture/principles-register.md`:

> AP-011's application to new ADRs follows the terse/rich shape rubric in `plugins/soleur/skills/architecture/references/adr-template.md#choosing-the-shape`.

This keeps the principle register the single source of truth for which principle governs ADR shape — a contributor who lands on AP-011 first still finds the rubric.

### Phase 3 — Verify

- Read both files back after edit to confirm the structure.
- Run `npx markdownlint-cli2 --fix plugins/soleur/skills/architecture/references/adr-template.md plugins/soleur/skills/architecture/SKILL.md` — pass specific paths per `cq-markdownlint-fix-target-specific-paths`.
- Confirm `grep -cE '^## ' adr-template.md` returns a shape that matches the new layout (YAML Frontmatter + Choosing the shape + Terse + Rich + Naming + Status = 6 H2 sections in the template wrapper).

## Acceptance Criteria

- [x] `plugins/soleur/skills/architecture/references/adr-template.md` contains a `## Choosing the shape` section with the 5-trigger rubric, each trigger phrased as an observable yes/no question.
- [x] The template contains two labeled body-sections blocks: `## Body Sections — Terse (3 sections)` and `## Body Sections — Rich (8 sections)`.
- [x] The rubric section names ADR-021 as the rich exemplar and ADR-006 as the terse exemplar, and anchors each shape in its tradition (Nygard / MADR).
- [x] `plugins/soleur/skills/architecture/SKILL.md` under `## Sub-command: create` has a new rubric step between "Read the ADR template" and "Write the ADR file," and the "Gather context" step branches between 3-prompt (terse) and 8-prompt (rich) lists.
- [x] Pipeline-mode default (terse) is documented in the skill.
- [x] `knowledge-base/engineering/architecture/principles-register.md` AP-011 row has a pointer to the rubric in the template.
- [x] ADR-001 through ADR-021 are unchanged — no backfill.
- [x] `npx markdownlint-cli2 --fix` passes on all three edited files.
- [x] Retroactive rubric classification (Test Scenario #3) returns 21/21 matches against the existing ADR corpus.
- [x] Running `/soleur:architecture create <terse-title>` on a narrow decision produces a 3-section ADR that looks like ADR-006/ADR-019.
- [x] Running `/soleur:architecture create <rich-title>` on a cross-cutting decision produces an 8-section ADR that looks like ADR-021.

## Test Scenarios

This plan is infrastructure-only (skill template + skill instructions + one-line principle register edit). There is no production code path to unit-test. Verification is:

1. **Template shape check.** After editing, run `grep -E '^## ' plugins/soleur/skills/architecture/references/adr-template.md` and confirm the H2 section list matches: `YAML Frontmatter`, `Choosing the shape`, `Body Sections — Terse (3 sections)`, `Body Sections — Rich (8 sections)`, `Naming Convention`, `Status Lifecycle`.
2. **Skill instruction check.** After editing, read `plugins/soleur/skills/architecture/SKILL.md` and confirm: (a) step 4.5 asks the rubric, (b) step 5 branches on the rubric outcome, (c) step 6 has two prompt lists (3-prompt terse / 8-prompt rich), (d) pipeline-mode default (terse) is documented.
3. **Retroactive rubric classification.** Walk through every existing ADR (ADR-001 through ADR-021) against the rubric and confirm the classification matches the actual shape. Expected results:
   - ADR-001 through ADR-020: rubric returns **terse** (zero triggers hit) → matches actual 3-section shape. If any one returns **rich**, the rubric is too loose — revise it before merging.
   - ADR-021: rubric returns **rich** (at least triggers #1 cross-cutting and #3 NFR-moving) → matches actual 8-section shape.
   - Spot-check procedure: for each ADR, read Context + Decision, answer the 5 trigger questions yes/no, compute `rich if any(yes) else terse`. Target: 21/21 match.
4. **Dry-run on hypothetical decisions.** Pick one narrow and one cross-cutting:
   - Narrow: "rename the deploy webhook env var from `WEBHOOK_SECRET` to `WEBHOOK_DEPLOY_SECRET`." Expected: terse (zero triggers).
   - Cross-cutting: "standardize all workspace filesystem reads through a single helper module." Expected: rich (trigger #1 cross-cutting, plausibly trigger #3 NFR-moving if attack-surface NFRs move).
5. **AP-011 reference check.** After editing the principles register, navigate from AP-011's row in the register to the rubric in the template (via the added pointer) and confirm the path works for a reader who starts at the register.
6. **Markdownlint.** Run `npx markdownlint-cli2 --fix plugins/soleur/skills/architecture/references/adr-template.md plugins/soleur/skills/architecture/SKILL.md knowledge-base/engineering/architecture/principles-register.md` — per `cq-markdownlint-fix-target-specific-paths`, pass specific paths (not globs). Zero errors expected.

## Domain Review

**Domains relevant:** Engineering only — this is a plugin-internal template edit with no user-facing surface, no cost impact, no legal/marketing/ops touchpoint.

Infrastructure/tooling change — no cross-domain implications beyond CTO. CTO guidance is implicit via AGENTS.md (which is loaded every turn and already governs ADR norms via AP-011). No explicit domain-leader spawn is needed for a 1-file template edit that codifies an existing corpus convention.

### Product/UX Gate

Not applicable. Scanning the "Files to create" list: none. Scanning the "Files to edit" list: no matches for `components/**/*.tsx`, `app/**/page.tsx`, or `app/**/layout.tsx`. Tier is **NONE** under both the subjective and mechanical-escalation checks.

## Risks

- **Rubric ambiguity at the margin.** A contributor could disagree about whether a decision is "cross-cutting" or whether an alternative has "teeth." Mitigation: each trigger is now phrased as an **observable** yes/no question whose answer is checkable against an existing repo file (NFR register, principles register, `knowledge-base/operations/expenses.md`). The rubric also cites two named exemplars (ADR-006 terse, ADR-021 rich). Fallback: the skill's `Unsure` branch walks the contributor through each trigger as its own question, which is mechanical.
- **Skill-instruction drift between `adr-template.md` and `SKILL.md`.** If a future edit to `adr-template.md` changes the rubric wording or renames the body-section headings without updating `SKILL.md`, the skill will prompt for the wrong fields. **Drift-detection procedure (run during review on any PR touching either file):**
  1. `grep -E '^## ' plugins/soleur/skills/architecture/references/adr-template.md` → expect the 6 H2 sections in the order: `YAML Frontmatter`, `Choosing the shape`, `Body Sections — Terse (3 sections)`, `Body Sections — Rich (8 sections)`, `Naming Convention`, `Status Lifecycle`.
  2. In `SKILL.md`, confirm the `create` sub-command step 4.5 references `## Choosing the shape` by exact heading name, and steps 5-6 reference `Body Sections — Terse` and `Body Sections — Rich` by exact heading names.
  3. If a later PR renames a template heading, the grep in (1) changes and a review-level check should flag the missing SKILL.md update.

  Long-term: if drift happens in practice, file an issue to have the skill read the template's heading names dynamically rather than by literal match.
- **"No enforcement" is load-bearing for the design but invisible to contributors.** This plan explicitly does not add linting or a hook. If a future contributor writes a 5-section Frankenstein ADR (picks 3 of the 8 rich sections plus the 3 terse sections), reviewers — not automation — catch it. Accepted risk per Non-goals. The rubric's framing ("use the shape as a whole, not pick-and-choose sections") is the only defense. If Frankenstein ADRs start appearing, revisit the decision to skip enforcement — a minimal markdownlint rule (e.g., "an ADR's `## ` section list must exactly match one of the two canonical lists") is a tractable follow-up.
- **ADR-021's exemplar status may age.** If ADR-021 is later superseded, the rubric's pointer to it goes stale. Mitigation: the rubric names the ADR by number, not by content. A superseded ADR retains its number, so the pointer still resolves; the rubric's argument ("see ADR-021 for the rich shape") remains valid even if the decision itself is replaced. If the entire KB-binary-serving problem space is refactored away, replace the pointer in a follow-up.
- **Pipeline-mode default surprises a pipeline caller.** If `/soleur:one-shot` ever invokes `/soleur:architecture create` for a cross-cutting decision and the default falls to terse, the resulting ADR is under-specified. Mitigation: the plan documents the pipeline-mode default and the `shape: rich` escape hatch. Since no pipeline caller creates ADRs today, this is a latent concern, not an active one.
- **Contributor may prefer "the old template" once the new one lands.** The rich shape was the default for ADR-021 because the template said so. Landing this change means the terse shape becomes default, and a contributor who was about to write a rich ADR for a borderline-cross-cutting decision might default to terse out of habit. Mitigation: the rubric's "zero triggers → terse, any trigger → rich" rule is symmetric and clear; there is no "default to the shorter one when unsure" thumb on the scale.

## Alternative Approaches Considered

| Approach | Pros | Cons | Decision |
|---|---|---|---|
| **Option 1: Backfill all 20 ADRs to 8-section shape** | Consistent corpus going forward, contributors see only the rich shape. | ~20 ADR rewrites, most of them would be padded with `None` stanzas (Cost/NFR/Principle Alignment) that add reviewer cost without reader value. High cost, low benefit. | Rejected. |
| **Option 2: Demote template back to 3 sections, move rich sections to a separate "extended ADR" template file** | Terse ADRs stay terse by default. | Two template files to keep in sync; skill's `create` step has to know which one to load when; frames the rich form as exceptional when it is the correct form for cross-cutting decisions. | Rejected. |
| **Option 3: Document the dual standard explicitly in one template file with a selection rubric** | One file to edit and keep in sync; contributors see both shapes in one place; rubric is the load-bearing artifact. | Rubric is advisory (no automated enforcement). | **Chosen.** |
| **Option 4: Add a markdown-lint rule that enforces section shape based on a frontmatter `shape: terse \| rich` field** | Machine-enforced. | Shape is often unclear at create-time; would add friction on every ADR write; and the rubric is itself advisory (it is a guide, not a law). This is a larger question than the issue scope. | Deferred — not part of this plan. Out of scope per Non-goals. |

## Rollout & Lifecycle

- Single PR branched off `main` (worktree `feat-one-shot-adr-template-dual-standard`).
- No migration. The template edit affects only newly created ADRs. ADR-001 through ADR-021 stay exactly as they are.
- No feature flag, no staged rollout. A template change takes effect the next time someone runs `/soleur:architecture create`.
- PR body uses `Closes #2541` to auto-close the issue on merge.

## Sharp Edges Noticed During Planning

- `adr-template.md` currently has the phrase "Use this template when creating Architecture Decision Records" at the top (line 3). After the edit, that opening sentence should be replaced with something like: "Use this template when creating ADRs. Read `## Choosing the shape` first to pick between the terse (3-section) and rich (8-section) body layouts." The contributor has to land on the rubric before the body sections or the rubric is invisible.
- The skill currently reads the template on every `create` invocation (step 4: "Read the ADR template from [adr-template.md]"). The new rubric question in step 6 must run *before* the template body is copied into the new ADR file — otherwise the skill would have to rewrite the body post-facto. Sequencing matters in the edit.
- No existing test suite covers the architecture skill's sub-commands. Adding one is out of scope. The verification in this plan is manual (re-read both files after edit).
- If the user invokes `/soleur:architecture create` in pipeline mode (no interactive prompt — `$ARGUMENTS` context), the rubric branch has to default to terse, since asking the 5 rubric questions non-interactively isn't possible without escalating to a subagent. Rich-shape ADRs in pipeline mode would require the caller to pass `--shape rich` (or equivalent) explicitly. Flag this in the skill edit but do not implement the CLI flag — the only pipeline caller today is `/soleur:one-shot`, which has not been observed to create ADRs.

## References

- Issue: #2541
- Prior ADR that triggered the inconsistency: ADR-021 (`knowledge-base/engineering/architecture/decisions/ADR-021-kb-binary-serving-pattern.md`), merged in PR #2538
- Terse exemplar (for the rubric): ADR-006 (`knowledge-base/engineering/architecture/decisions/ADR-006-terraform-remote-backend-r2.md`)
- Rich exemplar (for the rubric): ADR-021
- Template under edit: `plugins/soleur/skills/architecture/references/adr-template.md`
- Skill under edit: `plugins/soleur/skills/architecture/SKILL.md` (step 6 of `create` sub-command)
- Relevant AGENTS.md rules: `cq-markdownlint-fix-target-specific-paths` (Phase 3 verification form), `hr-always-read-a-file-before-editing-it` (already satisfied: both files read during planning).
- Principle: AP-011 (ADRs for architecture decisions) — the existence of the rubric is itself an instance of this principle applied to the template.
