---
date: 2026-11-11
topic: spec-kit-ingestion
issue: 12531
lane: cross-domain
user_brand_critical: true
---

# Brainstorm: Spec Kit ingestion (#12531)

**Date:** 2026-11-11
**Issue:** [#12531](https://github.com/jikig-ai/soleur/issues/12531) (OPEN)
**Epic:** [#12533](https://github.com/jikig-ai/soleur/issues/12533) (OPEN)
**Branch:** `feat-12531-spec-kit-ingestion`
**PR:** [#12653](https://github.com/jikig-ai/soleur/pull/12653)

"Spec" is not in the glossary. This document uses **Spec Kit directory** for a GitHub Spec Kit folder, and **Soleur spec** for `knowledge-base/project/specs/feat-<name>/spec.md`.

## User-Brand Impact

- **Artifact:** Brainstorm and plan intake that turns a Spec Kit directory into a Soleur spec.
- **Vector:** A silent or lossy map ships a different feature than the folder the founder pointed at, or copies AGPL text into the BSL tree.
- **Threshold:** `single-user incident`.

## Lane

`cross-domain`. Phase 0.1 sets user-brand-critical on every brainstorm, so the lane is fixed.

## What We're Building

A founder can pass a Spec Kit directory as the argument to brainstorm or plan. A read-only script reads that directory and projects `spec.md` into the Soleur spec template. `plan.md` and `tasks.md`, when present, stay side evidence. Soleur still writes its own plan and its own task list.

The directory shape comes from public GitHub Spec Kit docs (MIT): `specs/<prefix>-<short-name>/` with `spec.md`, `plan.md`, and `tasks.md`. The prefix is a 3-digit number or a timestamp. HephaestusNG was not opened. Epic #12533 requires a clean re-implementation of the idea, never the text.

## Why This Approach

Three approaches were on the table. The operator declined the demand question, so the recommended approach is the one recorded here.

### Approach A: Read-only script, Soleur spec from `spec.md` only (chosen)

A tested script allow-lists the three filenames. `spec.md` is required. `plan.md` and `tasks.md` are optional and marked absent when missing. Stories become requirement candidates. Success criteria become goals. Explicit exclusions become non-goals. Headings that do not fit stay in an unmapped appendix. Nothing in that appendix is built from until the projected Soleur spec is the accepted contract. The script resolves the path from the invoking working directory before any worktree `cd`.

**Pros:** The requirements contract stays the Soleur spec. Symlinks and extra files cannot sneak in through skill prose. Plan still owns tasks.

**Cons:** A folder whose real decisions live only in `plan.md` will look thin. The receipt has to say so.

**Best when:** The folder is a Spec Kit directory and the founder wants Soleur's pipeline, not a second copy of Spec Kit's implement phase.

### Approach B: Fold all three files into one Soleur spec

Rejected. Ruled by CTO agent, 2026-11-11: a Spec Kit `plan.md` is a how-document, and its `tasks.md` uses a different checklist than the indexed Soleur `tasks.md`. Merging them mixes how-to-build into what-to-build.

### Approach C: Tell the skill to read the files

Rejected. Ruled by CTO agent, 2026-11-11: an instruction is not a guard. Symlinks, `..`, and a second read of `research.md` or `contracts/` all get through.

## Key Decisions

- **Chosen approach:** A. One read-only script under `plugins/soleur/`, called by brainstorm and plan. Parser logic is not skill prose.
- **Required file:** `spec.md` only. A path-shaped intake with a missing, unreadable, or non-regular `spec.md` stops. There is no prose fallback.
- **Optional files:** `plan.md` and `tasks.md` are side evidence for `soleur:plan`. A missing file is `absent` on the receipt. Soleur's own `tasks.md` is still written by plan. Kit task ids and checkbox state are not copied.
- **Out of scope (not deferred):** `research.md`, `data-model.md`, `contracts/`, `quickstart.md`, constitution files, and any directory whose name is not `specs/<3-digit-or-timestamp>-<short-name>`.
- **Projection:** Stories and scenarios become FR candidates. Success criteria become goals. Explicit exclusions become non-goals. Everything else is labeled unmapped. Unmapped text is not built from.
- **Acceptance:** The projected Soleur spec is the build contract only after the receipt lists what moved, what was unmapped, and what was never read.
- **Path:** Resolve from the invoking cwd before the worktree `cd`. An external directory is allowed. A symlink that leaves the named directory fails the whole intake. Do not use `soleur_approval_realpath`.
- **License:** Reading public Spec Kit docs is permitted (MIT, SPDX checked 2026-11-11). No AGPL duty if `hmuhlestein/HephaestusNG` is never read. Provenance trailer on the implementation PR, not an AGPL or MIT notice. Do not copy Spec Kit templates, prompts, or schemas.
- **Customer text:** The caller's own checkout may hold the projected Soleur spec, at their instruction. The Soleur product tree does not commit customer spec bodies. Tests use synthesized fixtures. Committed product notes may record a path and a content hash.
- **Announcement:** None. The plateau post stays as it is. Do not say "Spec Kit compatible."
- **Routing:** No new `soleur:go` row. A path with no implement verb stays the brainstorm route.
- **Demand:** Unconfirmed. The operator declined to say whether anyone has arrived with a folder. This does not promote the issue off Post-MVP.

## Open Questions

- Has a founder or alpha tester actually brought a Spec Kit directory and stopped? Parked. The operator declined the question on 2026-11-11. Do not write the issue up as observed demand.
- (out of scope) Ingesting `research.md`, `data-model.md`, `contracts/`, and `quickstart.md`.
- (out of scope) A public compatibility claim or a blog edit.

## Domain Assessments

**Assessed:** Marketing, Engineering, Operations, Product, Legal, Sales, Finance, Support

### Product

**Summary:** The five Soleur headings cannot hold a Spec Kit spec without an unmapped appendix. Later stories must not become equal requirements. Kit tasks are not Soleur's task list. No recorded tester is blocked on this. The wall is a hypothesis until someone says otherwise.

### Engineering

**Summary:** Put the guard in a script. Require `spec.md`. Keep `plan.md` and `tasks.md` as side evidence. Fail closed on symlink escape, a non-regular file, and a missing `spec.md`. Resolve the path before the worktree `cd`.

### Legal

**Summary:** MIT docs may be read. No AGPL duty attaches if HephaestusNG stays unread. Provenance trailer required. Do not commit customer spec prose into the Soleur product tree. `soleur:gdpr-gate` does not apply to this path as specified.

### Marketing

**Summary:** No public claim change and no announcement. "Supports Spec Kit" would flatten the compound-knowledge thesis. Intake must not imply that plan review is optional.

Operations, Sales, Finance, and Support had no matching assessment question beyond the mandatory set. They were not spawned.

## Prior art

- `git grep` on `origin/main` for a path detector in brainstorm and plan: none. Intake is free-text `#$ARGUMENTS`.
- Archived brainstorm `knowledge-base/project/brainstorms/archive/20260210-122909-2026-02-05-unified-spec-workflow-brainstorm.md` borrowed Spec Kit's worktree idea. It did not ingest a Spec Kit directory.
- Sibling [#12529](https://github.com/jikig-ai/soleur/issues/12529) (closed) is the clean-room precedent for this epic. Its ADR-110 derivation sentence does not apply here. This reader is not derived from `lib/harness.ts`.

## Next Steps

Plan the script, the receipt, and the two skill call sites. Implementation follows the plan.
