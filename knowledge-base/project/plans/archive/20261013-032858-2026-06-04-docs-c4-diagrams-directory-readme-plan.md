---
title: "docs: README for the LikeC4 C4-model diagrams directory"
type: docs
status: planned
branch: feat-one-shot-c4-diagrams-readme
created: 2026-06-04
lane: procedural
requires_cpo_signoff: false
deepened: 2026-06-04
---

# 📚 docs: README for the LikeC4 C4-model diagrams directory

## Enhancement Summary

**Deepened on:** 2026-06-04
**Sections enhanced:** Research Reconciliation, Risks, README Content Outline
**Gates run:** 4.4 precedent-diff, 4.45 verify-the-negative, 4.6 User-Brand Impact (pass), 4.7 Observability (pure-docs skip, section present), 4.8 PAT-shaped (pass)

### Key Improvements
1. Regeneration command verified verbatim against TWO sources (architecture SKILL.md:256-261 and likec4-reference.md:112-113) — exact string `npx -y likec4@latest export json -o model.likec4.json .`.
2. Verify-the-negative pass confirmed the "viewer does NOT run the likec4 toolchain at runtime" claim against `apps/web-platform/components/kb/c4-diagram.tsx` and SKILL.md:251-254 — no contradiction.
3. Precedent-diff: the existing `.md` view pages (`system-context.md` etc.) are the in-repo precedent for the README's prose style and header convention — README should match their tone (terse, ADR-cross-referencing), not introduce a new doc voice.

### New Considerations Discovered
- The README is itself a `.md` file in the diagrams directory but is NOT a LikeC4 view page (no ` ```likec4-view ` block) — the taxonomy table should implicitly make clear the README is meta/index, distinct from the three view pages. (Listing the three view pages by name avoids the reader mistaking README for a fourth view.)
- The optional `spec.c4` comment edit is comment-only and therefore does NOT trigger a `model.likec4.json` regeneration (comments are not exported) — but this is a sharp edge worth stating so a future editor does not "play it safe" and regenerate (or worse, hand-edit) the JSON. Already captured in Sharp Edges + AC.

## Overview

After the Mermaid → LikeC4 migration (merged PR #4883), the
`knowledge-base/engineering/architecture/diagrams/` directory grew from three
Mermaid `.md` files to **eight** files spanning three artifact classes (DSL
sources, a compiled JSON, human-readable view pages). Operators report
confusion ("too many files") because nothing in the directory explains the
taxonomy, and `spec.c4:3` dangles a reference to a README that does not exist:

```
// Knowledge Base viewer (see ../README of the diagrams dir / the .md view pages).
```

This plan adds **one new file** — `knowledge-base/engineering/architecture/diagrams/README.md` —
a concise reference doc that names each file's role, states the authoring
workflow, and documents the verified `model.likec4.json` regeneration command.
Optionally it tightens the dangling `spec.c4` comment to point at the new README.

This is a knowledge-base documentation change only. No app code, no migration,
no new tests beyond what one-shot normally runs (markdown lint / link checks).

## Research Reconciliation — Spec vs. Codebase

All taxonomy claims in the feature description were verified against the live
directory and the architecture skill. The table records every fact the README
asserts and its source of truth.

| Claim (to appear in README) | Reality (verified) | Source |
|---|---|---|
| Directory has 8 files (3 `.c4`, 1 `.json`, 3 `.md`, `.gitkeep`) | Confirmed: `spec.c4`, `model.c4`, `views.c4`, `model.likec4.json`, `system-context.md`, `container.md`, `component-plugin.md`, `.gitkeep` | `ls knowledge-base/engineering/architecture/diagrams/` |
| `spec.c4` declares element kinds + tags once | Confirmed: `specification { element actor/system/container/database/component … tag external }` | `spec.c4:6-50` |
| `spec.c4` has a dangling `../README` reference | Confirmed: `spec.c4:3` | `spec.c4:3` |
| `model.c4` is the single source of truth, every element declared once, nesting = boundaries, migrated 1:1 from 3 Mermaid diagrams | Confirmed by header comment: "consolidated C4 model (single source of truth)… Every element is defined ONCE… Migrated 1:1 from the former Mermaid C4 diagrams" | `model.c4:1-6` |
| "40 elements, 51 relations" element/relation counts | **Authoritative count = the `elements`/`relations` key counts in `model.likec4.json`** (the render sub-command reads these). README states the count is authoritatively obtained from `model.likec4.json` rather than hard-coding a number that drifts. | architecture SKILL.md:263-264; feature description |
| `views.c4` = one view per C4 level: `context` (L1), `containers` (L2), `components` (L3), clickable drill-down, "code" level excluded | Confirmed: `view context`, `view containers of platform`, `view components of platform.plugin`; header documents drill-down | `views.c4:5-57` |
| `model.likec4.json` is COMPILED, pre-layouted, required by the web viewer at runtime; viewer does NOT run the likec4 toolchain | Confirmed: viewer reads committed `model.likec4.json`; "does NOT run the `likec4` toolchain at runtime (it would pull vite/esbuild into production deps)" | architecture SKILL.md:251-254 |
| Web viewer = `apps/web-platform/components/kb/c4-diagram.tsx`, fetches the dump, renders `@likec4/diagram` (browser-only, `next/dynamic ssr:false`) | Confirmed: component exists; `dump={data.dump}`; "Loaded via next/dynamic({ ssr: false }) — @likec4/diagram is browser-only" | `c4-diagram.tsx:7,56,60` |
| Regeneration command | **VERIFIED exact two-step form** (see below) | architecture SKILL.md:256-261; likec4-reference.md:112-113 |
| 3 `.md` pages each embed their view via a ` ```likec4-view ` fenced block + `## Notes`; role unchanged from Mermaid era (only the block changed) | Confirmed: each `.md` has a ` ```likec4-view ` block (body = view id) + `## Notes`; `Migrated to LikeC4: 2026-06-03` header | `system-context.md`, `container.md`, `component-plugin.md` |
| DSL syntax reference cross-link | Confirmed path exists | `plugins/soleur/skills/architecture/references/likec4-reference.md` |

**No divergence found.** Every paraphrased claim matched the source. The only
correction applied to the feature description: the README should NOT hard-code
"40 elements, 51 relations" as a frozen literal — it should state the counts are
read authoritatively from `model.likec4.json` (the `render` sub-command's source
of truth), with the migration-era figures cited as illustrative ("~40 elements,
~51 relations as of the 2026-06-03 migration"). This prevents the doc from
silently drifting on the next model edit.

### Verified regeneration command (paste verbatim into README)

Run from the diagrams directory (`architecture` SKILL.md:256-261):

```bash
cd knowledge-base/engineering/architecture/diagrams
npx -y likec4@latest validate .
# Rebuild the committed layouted model the web viewer reads:
npx -y likec4@latest export json -o model.likec4.json .
```

Then commit the regenerated `model.likec4.json` alongside the `.c4` edits.
Canonical regeneration path is the `soleur:architecture render` sub-command.

## User-Brand Impact

**If this lands broken, the user experiences:** a README that mis-describes the
file taxonomy or prescribes a wrong regeneration command — at worst an operator
hand-edits or deletes `model.likec4.json` and the KB C4 viewer renders blank or
stale until the JSON is regenerated. (Documentation-only blast radius; no
runtime code path changes.)

**If this leaks, the user's data / workflow / money is exposed via:** N/A — the
README documents only public architecture-model file roles and a public `npx`
command. No secrets, PII, credentials, or regulated data are touched.

**Brand-survival threshold:** none — pure internal documentation of an
already-shipped directory; no user-facing surface, no data path.

## Scope

### Files to Create

- `knowledge-base/engineering/architecture/diagrams/README.md` — the reference doc.

### Files to Edit (optional, secondary)

- `knowledge-base/engineering/architecture/diagrams/spec.c4` — tighten the
  dangling comment on line 3 from
  `(see ../README of the diagrams dir / the .md view pages)` to point at the
  now-existing `./README.md`. One-line wording change only; do NOT touch the
  `specification { … }` block (any `.c4` edit otherwise mandates a
  `model.likec4.json` regeneration — a comment-only change does not, because
  comments are not exported, but keep the edit comment-only to stay out of the
  regeneration path).

### Out of Scope (do NOT do)

- Do NOT delete, consolidate, move, or rename any existing file. All eight are
  correct and required (verified above).
- Do NOT hand-edit or regenerate `model.likec4.json` — no `.c4` semantic change
  is being made.
- No app code, no migration, no new test files.

## README Content Outline

Keep it a short reference doc (target ~70-110 lines), not an essay. Suggested
structure:

1. **Title + one-paragraph purpose** — "This directory holds the single
   consolidated LikeC4 C4 model and the pages that render it. The files below
   are NOT redundant; each has a distinct role." Explicitly name the
   Mermaid → LikeC4 migration (PR #4883) so the "too many files" reader lands
   here with context.

2. **File taxonomy table** — one row per file, three columns
   (`File` / `Kind` / `Role`):

   | File | Kind | Role |
   |---|---|---|
   | `spec.c4` | LikeC4 DSL (source) | Declares element KINDS once (actor / system / container / database / component) and tags. Authored by the `soleur:architecture diagram` skill. |
   | `model.c4` | LikeC4 DSL (source) | The consolidated C4 model — single source of truth. Every element declared exactly once (≈40 elements, ≈51 relations as of the 2026-06-03 migration; authoritative counts live in `model.likec4.json`). Migrated 1:1 from the former 3 Mermaid diagrams. Nesting creates C4 boundaries. |
   | `views.c4` | LikeC4 DSL (source) | One view per C4 level: `context` (L1), `containers` (L2), `components` (L3). Define-once-render-many: the three C4 layers live here as VIEWS, giving clickable drill-down Context → Containers → Components. The C4 "code" level is intentionally excluded per convention. |
   | `model.likec4.json` | Compiled artifact (generated) | COMPILED, pre-layouted model REQUIRED by the web viewer at runtime. `apps/web-platform/components/kb/c4-diagram.tsx` renders `@likec4/diagram` from `data.dump` (fetched via the KB C4 API); client libs are pinned WITHOUT the likec4 compiler, so the DSL is compiled at author-time and the JSON shipped to the browser. **Do NOT hand-edit or delete — regenerate from the `.c4` sources.** |
   | `system-context.md` | View page (L1) | Human-readable C4 L1 page; embeds the `context` view via a ` ```likec4-view ` fenced block + prose `## Notes`. |
   | `container.md` | View page (L2) | Human-readable C4 L2 page; embeds the `containers` view + `## Notes`. |
   | `component-plugin.md` | View page (L3) | Human-readable C4 L3 page; embeds the `components` view + `## Notes`. |

   Add a one-line note that the three `.md` pages are the same three files that
   existed in the Mermaid era — their role is unchanged; only the embedded block
   changed from ` ```mermaid ` to ` ```likec4-view `.

3. **Authoring workflow** (short, numbered):
   1. Edit the `.c4` sources (`spec.c4` / `model.c4` / `views.c4`) via the
      `soleur:architecture` skill (`architecture diagram` sub-command).
   2. Regenerate `model.likec4.json` from the `.c4` sources (the
      `soleur:architecture render` sub-command) — paste the verified two-step
      command block above.
   3. Commit the regenerated `model.likec4.json` alongside the `.c4` edits.
   4. **Never hand-edit `model.likec4.json`** — it is a build output.

4. **Cross-references:**
   - DSL syntax: `plugins/soleur/skills/architecture/references/likec4-reference.md`
   - Authoring/render commands: the `soleur:architecture` skill SKILL.md.

## Acceptance Criteria

### Pre-merge (PR)

- [x] `knowledge-base/engineering/architecture/diagrams/README.md` exists and is
      non-empty (`test -s` passes).
- [x] README contains a row/section for **each** of the seven content files
      (`spec.c4`, `model.c4`, `views.c4`, `model.likec4.json`,
      `system-context.md`, `container.md`, `component-plugin.md`).
      Verify: `for f in spec.c4 model.c4 views.c4 model.likec4.json system-context.md container.md component-plugin.md; do grep -qF "$f" knowledge-base/engineering/architecture/diagrams/README.md || echo "MISSING: $f"; done` returns no output.
- [x] README embeds the **verified** regeneration command line
      `npx -y likec4@latest export json -o model.likec4.json .`
      (substring match): `grep -qF 'npx -y likec4@latest export json -o model.likec4.json .' knowledge-base/engineering/architecture/diagrams/README.md`.
- [x] README states `model.likec4.json` must NOT be hand-edited:
      `grep -qiE 'do not (hand-edit|edit)|never hand-edit' knowledge-base/engineering/architecture/diagrams/README.md`.
- [x] README cross-references the DSL reference path
      `plugins/soleur/skills/architecture/references/likec4-reference.md`
      (substring match).
- [x] Every `knowledge-base/`-relative path the README cites resolves to a real
      file. Verify with the standard plan-time link sweep:
      `grep -oE '(knowledge-base|plugins|apps)/[A-Za-z0-9/_.-]+\.(md|c4|json|tsx)' knowledge-base/engineering/architecture/diagrams/README.md | sort -u | xargs -I{} bash -c '[[ -f "{}" ]] || echo "BROKEN: {}"'` returns no `BROKEN:` lines.
- [x] (If the optional `spec.c4` edit is applied) the comment-only change keeps
      the `specification { … }` body byte-identical, so no `model.likec4.json`
      regeneration is required. Verify the model file is unmodified:
      `git diff --quiet -- knowledge-base/engineering/architecture/diagrams/model.likec4.json`.
- [x] No existing file in the directory was deleted, renamed, or moved:
      `git status --porcelain knowledge-base/engineering/architecture/diagrams/`
      shows only `A` (README.md) and at most `M spec.c4`.

### Post-merge (operator)

- [x] None. Pure docs; no operator action.
      Automation: N/A — nothing to run.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — internal engineering documentation of an
already-shipped directory. No product surface (no new page/component), no legal /
regulated-data surface, no infrastructure, no marketing/finance/sales/support
impact.

## Infrastructure (IaC)

Not applicable — no new server, service, secret, vendor, DNS record, cron, or
persistent runtime process. Pure documentation file under `knowledge-base/`.

## Observability

Not applicable — pure-docs change with no Files-to-Edit under `apps/*/server/`,
`apps/*/src/`, `apps/*/infra/`, or `plugins/*/scripts/`, and no new
infrastructure surface. (Plan Phase 2.9 skip condition: pure-docs.)

## Open Code-Review Overlap

None — overlap check ran against the planned file paths (`README.md`, `spec.c4`)
with no open `code-review` issues touching them.

## Test Strategy

No new test files. Relies on the repository's existing markdown lint / link
checks that one-shot runs. The Acceptance Criteria `grep`/`test`/`git diff`
commands above are the verifiable post-conditions; run them at PR-review time.

## Risks & Mitigations

- **Risk: README hard-codes element/relation counts that drift.**
  Mitigation: state counts as illustrative ("≈40/≈51 as of the 2026-06-03
  migration") and direct readers to `model.likec4.json` for the authoritative
  figure — exactly what the `render` sub-command reads.
- **Risk: an over-eager edit to `spec.c4` touches the `specification` body and
  silently desyncs `model.likec4.json`.**
  Mitigation: scope the optional `spec.c4` edit to the line-3 comment only; AC
  asserts `model.likec4.json` is byte-unchanged.
- **Risk: a fabricated/wrong regeneration command rots the doc.**
  Mitigation: command was copied verbatim from `architecture` SKILL.md:256-261
  and cross-checked against `likec4-reference.md:112-113`; AC greps for the exact
  string.

## Precedent-Diff (Phase 4.4)

The in-repo precedent for the README's voice is the three existing view pages
in the same directory (`system-context.md`, `container.md`, `component-plugin.md`).
They share a consistent header convention — `Generated: <date> · Migrated to
LikeC4: 2026-06-03`, a one-line "Rendered interactively from the canonical
LikeC4 model in this directory (`spec.c4`, `model.c4`, `views.c4`)" pointer, and
a terse `## Notes` list that cross-references ADRs. The README should match that
terse, pointer-style tone rather than introducing a new documentation voice.

No SQL / lock / atomic-write / RPC pattern is in scope — the only "pattern-bound"
behavior is the regeneration command, which is taken verbatim from the canonical
`soleur:architecture render` sub-command (SKILL.md:256-261), not re-invented.

## Verify-the-Negative (Phase 4.45)

The plan's load-bearing negative claim — "the web viewer does NOT run the likec4
toolchain at runtime" — was grep-confirmed against
`apps/web-platform/components/kb/c4-diagram.tsx` (renders `@likec4/diagram` from
`data.dump`; `next/dynamic({ ssr: false })`, browser-only) and architecture
SKILL.md:251-254 ("does NOT run the `likec4` toolchain at runtime … it reads the
committed, layouted `model.likec4.json`"). Result: **confirms** — no
contradiction. The README may state this claim as fact.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only
  `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan`
  Phase 4.6. This plan's section is filled (threshold: none) — do not blank it.
- Comments in `.c4` files are NOT exported into `model.likec4.json`, so the
  optional `spec.c4` comment tweak does not require regeneration. But ANY change
  to the `specification`/`model`/`views` bodies DOES — keep the edit
  comment-only.
- Do NOT "tidy" the directory by merging the three `.md` view pages or deleting
  the JSON; they are load-bearing (the JSON is the runtime artifact, the `.md`
  pages are the operator-readable layer). The whole point of this README is to
  stop that instinct.
