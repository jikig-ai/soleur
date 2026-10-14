---
title: "Consolidate three C4 view pages into a single interactive c4-model.md"
type: refactor
branch: feat-one-shot-c4-single-page
lane: cross-domain
brand_survival_threshold: none
---

# ♻️ Consolidate the three LikeC4 C4 view pages into a single interactive page

## Enhancement Summary

**Deepened on:** 2026-06-04

**Deepen-plan gates run (all pass / skip correctly):**

- **Phase 4.4 Precedent-Diff:** No pattern-bound behaviors (no SQL `SECURITY DEFINER`, no
  atomic-write/lock/RPC/pool/circuit-breaker shapes), no new scheduled job. **No precedent-diff
  required; pattern is a docs+test-fixture consolidation with an established in-repo precedent**
  — the three existing pages ARE the precedent for voice/header convention, and the README
  taxonomy table is the precedent for the row format. The new page matches their terse,
  ADR-cross-referencing voice.
- **Phase 4.5 Network-Outage:** No trigger — the only "ssh" token is the literal "(NO ssh)"
  discoverability-test label; no SSH/network-connectivity symptom, no `provisioner`/`connection`
  Terraform. Skipped.
- **Phase 4.6 User-Brand Impact Halt:** Section present, non-empty, threshold = `none`. Files to
  Edit do NOT match the sensitive-path regex (a `.test.ts` fixture + a `.tsx` comment-only edit),
  so no scope-out bullet is required; one is included anyway for hygiene. **Pass.**
- **Phase 4.7 Observability:** `## Observability` section present with a concrete
  `discoverability_test` (vitest run of the scope test, NO ssh). The only `apps/*` edits are a unit
  test and a comment — no runtime/infra surface introduced. **Pass.**
- **Phase 4.8 PAT-Shaped Variable Halt:** No PAT-shaped TF variable / env var / literal token
  anywhere in the plan. **Pass.**

**Why no per-section research fan-out:** This is a small, fully-locally-verified consolidation.
Premise validation already resolved every external dependency (PR #4936 confirmed; `views.c4`
drill-down edges confirmed; `c4-embed.ts` first-block-wins parser confirmed; `isC4DiagramPath`
filename-agnostic confirmed; the 12-ADR set grep-verified against the three source files; the full
reference inventory grep-verified). External best-practices/framework research adds no marginal
value over the in-repo precedent. Risk is a broken internal docs link, threshold `none`.

### Key Improvements over the raw plan

1. The intro-wording ambiguity ("drill-down button" vs the verified box-click affordance) is
   resolved in Research Reconciliation so the implementer does not invent a non-existent UI widget.
2. The `container.md` substring trap (matches the unrelated `*docker-container.md` learning) is
   called out so the cleanup grep does not touch immutable historical files.
3. The fence-shape contract (` ```likec4-view\ncontext\n``` ` exactly) is pinned to the
   `c4-embed.ts` regex so the page actually renders.

## Overview

The LikeC4 C4 visualizer (PR #4883) supports **in-place drill-down**: the embedded
diagram wires `onNavigateTo → setCurrentView` (`apps/web-platform/components/kb/c4-shared.tsx`,
state held in `apps/web-platform/components/kb/c4-workspace.tsx:47`), so a single page
embedding the top-level `context` view lets a reader navigate
Context (L1) → Containers (L2) → Components (L3) without ever leaving the page.

The directory currently carries **three** human-readable view pages
(`system-context.md`, `container.md`, `component-plugin.md`) — a 1:1 carryover from the
pre-migration **Mermaid** era, when each level was a separate static image with no
drill-down. With LikeC4 drill-down that 3-file split is redundant: the three files embed
`context` / `containers` / `components` respectively, but `containers` and `components` are
already reachable as drill-down targets *from* `context` (verified in `views.c4`:
`view containers of platform`, `view components of platform.plugin`; `context` includes the
`platform` box, `containers` includes the `plugin` box).

This is a **follow-up to merged PR #4936** (which added the diagrams `README.md`). The change
replaces the three pages with one new page `c4-model.md` that embeds `context`, preserves
**every** `## Notes` bullet (and ADR cross-reference) from all three source pages as prose
subsections, and updates every in-repo reference. It is **CODE-class** because it edits a
security-boundary unit test (`c4-diagram-path-scope.test.ts`).

**Scope discipline — do NOT touch the model layer:** `spec.c4`, `model.c4`, `views.c4`, and
`model.likec4.json` are out of scope. The view ids `context` / `containers` / `components`
must all continue to exist (they are the drill-down targets). `model.likec4.json` must remain
**byte-identical** (it is a compiled artifact; `views.c4` is unchanged so no regeneration occurs).

## Premise Validation

Checked before planning (the premise is sound):

- **PR #4936** (the README-adding PR this follows up): confirmed via its merged plan artifact
  `knowledge-base/project/plans/2026-06-04-docs-c4-diagrams-directory-readme-plan.md` and the
  present `diagrams/README.md`. Premise holds.
- **Drill-down mechanism**: `apps/web-platform/lib/c4-embed.ts:parseLikeC4Embed` takes the
  FIRST `likec4-view` block's first non-empty line as the initial `viewId`; `views.c4` confirms
  `context → platform → containers` and `containers → plugin → components` drill-down edges.
  Embedding `context` alone reaches all three levels. Premise holds.
- **Filename-agnostic path guard**: `apps/web-platform/lib/c4-constants.ts:isC4DiagramPath`
  gates on dir-prefix (`engineering/architecture/diagrams/`) + `.md`/`.c4` extension + sane
  charset — it is filename-agnostic, so `c4-model.md` passes. Premise holds.
- **Reference inventory** (`git grep -nE 'system-context\.md|container\.md|component-plugin\.md'`):
  all editable references located (README, nfr-register, nfr-reference, test, c4-workspace
  comment, INDEX.md). Remaining matches are immutable historical artifacts (see Files NOT to Edit).
  Premise holds.

No stale premises.

## Research Reconciliation — Spec vs. Codebase

No `spec.md` exists for this branch; the ARGUMENTS block is the spec. One clarification
surfaced during research, recorded here so the implementer does not drift:

| Claim (ARGUMENTS) | Reality (codebase) | Plan response |
|---|---|---|
| "click the drill-down button on the Soleur Platform box" | The three existing source pages describe the mechanism as **"Click the Soleur Platform box to drill down"** (box-click), the LikeC4 native affordance wired via `onNavigateTo`. There is no separate "drill-down button" widget visible in `c4-shared.tsx`. | Intro prose describes drilling down by **clicking the box** (matching the existing pages' verified voice). Keep the wording faithful to the rendered affordance; do not invent a "button" UI element. |
| "embed the context view" | `views.c4` view id is literally `context`. | Fenced block body is exactly `context`. ✓ |

## User-Brand Impact

**If this lands broken, the user experiences:** a 404 or empty/blank C4 diagram page in the KB
viewer if `c4-model.md` is malformed (wrong fence shape) or a reference points at a deleted file
— the architecture model becomes unreachable from the docs nav. Worst realistic case is a broken
internal docs link; no user data, money, or workflow is at stake.

**If this leaks, the user's [data / workflow / money] is exposed via:** N/A — this is a
public-architecture documentation consolidation. No PII, secrets, or regulated-data surface is
touched. The only "security-adjacent" file is the `isC4DiagramPath` *test*, and the guard's
behavior is unchanged (filename-agnostic); the test edit only swaps deleted fixture filenames.

**Brand-survival threshold:** none.

_Reason for `none` while touching a security-test path:_ `c4-diagram-path-scope.test.ts` is a
test fixture file, not a production write surface, and `isC4DiagramPath` logic is **not modified**
— only the example filenames in assertions change. No sensitive runtime path is altered.

## The New File — `knowledge-base/engineering/architecture/diagrams/c4-model.md`

A *properly authored single page*, NOT a concatenation of the three old files. Structure:

1. **Title:** `# Soleur Platform — C4 Model`
2. **Generated/migrated header line** matching the existing pages' convention
   (`Generated: 2026-03-27 · Migrated to LikeC4: 2026-06-03`), preserving provenance.
3. **Intro paragraph** (terse, pointer-style, matching existing voice): states it is the
   interactive C4 model rendered from the canonical LikeC4 sources in this directory
   (`spec.c4`, `model.c4`, `views.c4`); the diagram opens at **System Context (L1)**; click the
   **Soleur Platform** box to descend to **Containers (L2)**, then the **Soleur Plugin** box to
   descend to **Components (L3)** — all in place, without leaving the page.
4. **Exactly ONE** fenced block:

   ````markdown
   ```likec4-view
   context
   ```
   ````

   The body is `context` (the FIRST — and only — `likec4-view` block; the embed parser uses the
   first block's view id as the initial view). Do **not** add a second `likec4-view` block.
5. **Three prose subsections**, each preserving **verbatim** every `## Notes` bullet from the
   corresponding source page (with ADR cross-references intact):

   - `## System Context (C4 L1)` — the 8 bullets from `system-context.md` (ADR-003, ADR-004,
     ADR-006, ADR-019, ADR-007, ADR-008).
   - `## Containers (C4 L2)` — **one lead line** telling the reader to drill into the *Soleur
     Platform* box above to reach this view, then the 7 bullets from `container.md` (ADR-016,
     ADR-011, ADR-009, ADR-017).
   - `## Components (C4 L3)` — **one lead line** telling the reader to drill into the *Soleur
     Plugin* box (inside the container view) to reach this view, then the 6 bullets from
     `component-plugin.md` (ADR-016, ADR-015, ADR-013).

**Verbatim source bullets to carry forward (read the live files at /work time; do not transcribe
from this plan — these are reproduced for the implementer's audit checklist only):**

- System Context bullets (from `system-context.md` lines 15-22): Web App thin view/control layer
  (ADR-003); CLI engine preserves 100% orchestration; BYOK AES-256-GCM/HKDF (ADR-004); Terraform +
  R2 backend (ADR-006, ADR-019); Doppler runtime injection (ADR-007); Cloudflare Tunnel zero-trust
  (ADR-008); Stripe test mode; Plausible privacy analytics.
- Containers bullets (from `container.md` lines 15-21): flat skill / recursive agent discovery
  (ADR-016); three enforcement tiers (ADR-011); KB compounds across sessions; worktree isolation
  (ADR-009); version from git tags (ADR-017); Stripe checkout/webhooks; Plausible JS snippet.
- Components bullets (from `component-plugin.md` lines 15-20): three commands only (ADR-016);
  one-shot pipeline plan→work→review→compound→ship (ADR-015); domain leaders CTO/CMO/CPO (ADR-013);
  CTO detects architectural decisions; architecture-strategist advisory; 8 review agents in parallel.

**Fence-shape hazard (Sharp Edge):** `LIKEC4_VIEW_BLOCK` in `c4-embed.ts` is the regex
` ```likec4-view[ \t]*\n([\s\S]*?)\n``` `. The block MUST be ` ```likec4-view ` on its own line,
then `context` on its own line, then a closing ` ``` ` on its own line. A title line or extra
content between the fence and `context` would change the parsed view id. Keep it minimal.

## Files to Create

| File | Content |
|---|---|
| `knowledge-base/engineering/architecture/diagrams/c4-model.md` | New consolidated page per "The New File" section above. |

## Files to Edit

| File | Edit |
|---|---|
| `knowledge-base/engineering/architecture/diagrams/README.md` | (a) Collapse the **three** `system-context.md` / `container.md` / `component-plugin.md` table rows (lines 24-26) into **one** `c4-model.md` row: Kind `View page (interactive)`; Role "single page embedding the `context` view with in-place drill-down L1→L2→L3 + per-level `## Notes`". (b) Rewrite the prose at lines 11-14 ("three human-readable view pages" / "three .md view pages") and lines 31-33 ("three `.md` view pages … same three files … Mermaid era") to describe a **single consolidated page**. (c) Update line 7-9 "Resist the urge to … merging the view pages" — the merge has now happened deliberately; reword so it no longer forbids what this PR does (e.g., "the single view page + the JSON are load-bearing; do not delete the JSON or re-split the page without cause"). **Preserve unchanged:** the regeneration-command block (lines 44-49) and the `.c4`/`.json` file-taxonomy rows + counts (lines 20-23, 56-58). |
| `knowledge-base/engineering/architecture/nfr-register.md` | Line 20: repoint `diagrams/container.md` → `diagrams/c4-model.md` as the container "source of truth". **Keep the counts** (`12 containers, 6 external systems, 19 relationships`). |
| `plugins/soleur/skills/architecture/references/nfr-reference.md` | Line 115: repoint `diagrams/container.md` → `diagrams/c4-model.md` ("When a new container is added to the C4 container diagram …"). |
| `apps/web-platform/test/c4-diagram-path-scope.test.ts` | Replace the deleted-file fixtures: line 16 `system-context.md` → `c4-model.md`; lines 48-49 (`component-plugin.md`, `container.md`) → at minimum one `c4-model.md` assertion. Keep ≥1 negative/edge fixture intact (the "rejects" + "empty-stem dotfiles" blocks at lines 19-45, 52-64 stay). The `it("accepts hyphenated view-embed page names")` block can be re-purposed to assert `c4-model.md` (hyphenated stem) still passes, OR collapsed into the `.md` accept block — implementer's choice; the invariant is: `isC4DiagramPath("engineering/architecture/diagrams/c4-model.md") === true` is asserted and no assertion references a deleted filename. |
| `apps/web-platform/components/kb/c4-workspace.tsx` | Line 40 comment example: `"knowledge-base/.../container.md"` → `"knowledge-base/.../c4-model.md"` (comment-only; no logic change). |

## Files to Delete (`git rm`)

- `knowledge-base/engineering/architecture/diagrams/system-context.md`
- `knowledge-base/engineering/architecture/diagrams/container.md`
- `knowledge-base/engineering/architecture/diagrams/component-plugin.md`

## Files NOT to Edit (immutable historical record — leave references as-is)

These match the grep but are historical plans/specs/learnings that must NOT be rewritten:

- `knowledge-base/project/plans/2026-03-27-feat-architecture-as-code-plan.md`
- `knowledge-base/project/plans/2026-04-06-chore-remove-telegram-bridge-plan.md`
- `knowledge-base/project/plans/2026-06-04-docs-c4-diagrams-directory-readme-plan.md` (the PR #4936 plan)
- `knowledge-base/project/plans/archive/**` (archived plans/specs)
- `knowledge-base/project/specs/feat-remove-telegram-bridge/tasks.md`
- `knowledge-base/project/learnings/workflow-patterns/2026-06-04-reported-file-bloat-after-tooling-migration-verify-idiomatic-layout-before-fixing.md`
- The `*-supabase-server-side-connectivity-docker-container.md` learning + its referers — these
  match `container.md` only as a substring of an unrelated filename, NOT the diagram page.

## Regenerate (do NOT hand-edit) — `knowledge-base/INDEX.md`

`INDEX.md` is auto-generated and carries the banner "Do not edit manually". After the file
create + 3 deletes, regenerate it:

```bash
bash scripts/generate-kb-index.sh
```

The script walks `knowledge-base/**/*.md`, takes each file's title from its first `# heading`
(these pages have no YAML frontmatter), and emits a sorted-by-domain flat list. Post-run, the
`engineering` section will contain `[Soleur Platform — C4 Model](engineering/architecture/diagrams/c4-model.md)`
and will NO LONGER contain the three deleted-page entries (currently INDEX.md:49-51). Commit the
regenerated `INDEX.md` (it also regenerates `kb-tags.txt` / `kb-categories.txt` deterministically;
those should be unchanged since no learnings frontmatter changed — verify they show no diff).

## Implementation Phases

1. **Create `c4-model.md`** — read the three source files live, author the single page (title +
   provenance header + intro + one `context` fenced block + three prose subsections with verbatim
   bullets). Verify the fence shape against the `c4-embed.ts` regex.
2. **`git rm` the three old pages.**
3. **Edit the prose/doc references** — README (3 rows → 1 + prose rewrite), nfr-register.md:20,
   nfr-reference.md:115, c4-workspace.tsx:40 comment.
4. **Edit the test** — `c4-diagram-path-scope.test.ts` fixtures swap to `c4-model.md`, keep
   negative fixtures.
5. **Regenerate INDEX.md** — `bash scripts/generate-kb-index.sh`; confirm c4-model.md present,
   3 pages absent.
6. **Verify** — run the AC checklist (below): grep ADR ids in c4-model.md; `git status` shows 3
   deletions + 1 addition; `git diff` shows `model.likec4.json` unchanged; no tracked file outside
   this change references the deleted filenames (excluding immutable historical); web-platform
   typecheck + the scope test pass.

## Observability

Pure docs + one test fixture edit; no runtime code path, no new infra surface. The single
code-class file (`c4-diagram-path-scope.test.ts`) is exercised by the vitest suite (the
"discoverability test" below). Per the Phase 2.9 skip rule (no Files-to-Edit under
`apps/*/server/`, `apps/*/src/`, `apps/*/infra/` introduces a runtime surface — the only
`apps/*` edits are a unit test and a comment), a full 5-field observability schema is **not
required**. Failure mode for the page itself: broken KB render, caught by the build/typecheck +
the manual KB-viewer smoke at QA time.

## Acceptance Criteria

### Pre-merge (PR)

- [x] `knowledge-base/engineering/architecture/diagrams/c4-model.md` exists, title is exactly
      `# Soleur Platform — C4 Model`.
- [x] It contains **exactly one** `likec4-view` fenced block whose body is `context`:
      `grep -c '^```likec4-view$' c4-model.md` returns `1`, and the line after it is `context`.
- [x] All ADR ids previously across the three pages appear in `c4-model.md`:
      `for a in ADR-003 ADR-004 ADR-006 ADR-007 ADR-008 ADR-009 ADR-011 ADR-013 ADR-015 ADR-016 ADR-017 ADR-019; do grep -q "$a" c4-model.md || echo "MISSING $a"; done` returns no output.
- [x] The three old pages no longer exist: `git status --short` shows `D` for `system-context.md`,
      `container.md`, `component-plugin.md`.
- [x] No tracked file **outside this change** still references the deleted filenames (excluding
      immutable historical plans/specs/learnings): re-run
      `git grep -nE 'system-context\.md|container\.md|component-plugin\.md'` and confirm every
      remaining hit is in the Files-NOT-to-Edit set (or is the unrelated
      `*docker-container.md` learning filename).
- [x] `git diff -- knowledge-base/engineering/architecture/diagrams/model.likec4.json` is **empty**
      (byte-identical).
- [x] `git diff -- knowledge-base/engineering/architecture/diagrams/spec.c4 model.c4 views.c4` is
      **empty** (model layer untouched).
- [x] README's regeneration-command block and the `.c4`/`.json` taxonomy rows + counts are
      preserved; the three view-page rows are collapsed to one `c4-model.md` row.
- [x] `isC4DiagramPath("engineering/architecture/diagrams/c4-model.md") === true` is asserted by
      the updated test, and no test assertion references a deleted filename.
- [x] **Discoverability test (NO ssh):** the scope test passes —
      `cd apps/web-platform && ./node_modules/.bin/vitest run test/c4-diagram-path-scope.test.ts`
      exits 0. (Confirm the runner: `apps/web-platform` uses vitest; do NOT hardcode `bun test` —
      `bunfig.toml`/vitest config govern discovery.)
- [x] web-platform typecheck passes: `cd apps/web-platform && npx tsc --noEmit` (or the package's
      `typecheck` script) exits 0.
- [x] `INDEX.md` regenerated: contains `c4-model.md`, omits the three deleted pages
      (`grep -c 'c4-model.md' knowledge-base/INDEX.md` == 1; `grep -cE 'diagrams/(system-context|container|component-plugin)\.md' knowledge-base/INDEX.md` == 0).
- [x] `kb-tags.txt` / `kb-categories.txt` show no diff after regeneration (no learnings frontmatter changed).

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — documentation-consolidation + a unit-test fixture edit.
No user-facing UI surface is created or modified (the C4 viewer component is unchanged; only the
markdown content it renders is consolidated). No new component file, route, or layout is added, so
the Product/UX mechanical-escalation does not fire. No regulated-data surface, no infrastructure,
no new dependency.

## Open Code-Review Overlap

None. Queried `gh issue list --label code-review --state open` (71 open) and matched each planned
file path against issue bodies via standalone `jq --arg`; zero matches against `c4-model.md`,
`README.md`, `nfr-register.md`, `nfr-reference.md`, `c4-diagram-path-scope.test.ts`, or
`c4-workspace.tsx`.

## Sharp Edges

- **Fence shape is load-bearing.** The embed parser (`c4-embed.ts`) regex requires
  ` ```likec4-view\ncontext\n``` ` exactly. Putting a title or comment between the fence and
  `context`, or indenting the fence, changes the parsed initial view (or yields `null` → no embed,
  blank diagram). Keep the block minimal and left-aligned.
- **`model.likec4.json` must stay byte-identical.** `views.c4` is unchanged, so no `likec4 export
  json` regeneration runs. If `git diff` shows the JSON changed, something edited the model layer —
  revert it. The view ids `context`/`containers`/`components` must all survive (drill-down targets).
- **`container.md` substring trap.** `git grep 'container\.md'` also matches the unrelated
  `2026-04-06-supabase-server-side-connectivity-docker-container.md` learning and its referers.
  Do NOT touch those — they are not the diagram page.
- **Test runner is vitest, not bun.** `apps/web-platform/bunfig.toml` historically blocks
  `bun test` discovery; the package uses vitest. Verify the scope test with
  `./node_modules/.bin/vitest run <path>`, not `bun test`.
- **INDEX.md title source.** These pages have no YAML frontmatter, so the index title comes from
  the first `# heading`. The new `# Soleur Platform — C4 Model` is what will appear in INDEX.md —
  keep the title exactly as specified so the regenerated entry is predictable.
- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder
  text, or omits the threshold will fail `deepen-plan` Phase 4.6. (This plan's section is filled;
  threshold = `none` with a documented reason for touching a security-test path.)
