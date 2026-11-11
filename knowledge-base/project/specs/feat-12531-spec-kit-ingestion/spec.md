---
title: "feat(engineering): Spec Kit ingestion — consume specs/<NNN>-<name>/ directories as brainstorm/plan input"
date: "2026-11-11"
lane: cross-domain
status: draft
closes: 12531
brand_survival_threshold: single-user incident
user_brand_critical: true
---

# Feature Specification: Spec Kit ingestion

**Feature Directory:** `knowledge-base/project/specs/feat-12531-spec-kit-ingestion`
**Brainstorm Reference:** `knowledge-base/project/brainstorms/2026-11-11-spec-kit-ingestion-brainstorm.md`
**Tracking Issue:** [#12531](https://github.com/jikig-ai/soleur/issues/12531)
**Epic:** [#12533](https://github.com/jikig-ai/soleur/issues/12533)
**Branch:** `feat-12531-spec-kit-ingestion`
**Draft PR:** [#12653](https://github.com/jikig-ai/soleur/pull/12653)

"Spec" is not a glossary term. **Spec Kit directory** means a folder whose name matches `specs/<prefix>-<short-name>/`. **Soleur spec** means `knowledge-base/project/specs/feat-<name>/spec.md`.

## Problem Statement

Brainstorm and plan take free text. A founder who already has a Spec Kit directory has to retype it. There is no path detector in either skill.

The input shape is the public GitHub Spec Kit layout (MIT): `spec.md`, `plan.md`, and `tasks.md` under `specs/<prefix>-<short-name>/`. The prefix is a 3-digit number or a timestamp. HephaestusNG is AGPL-3.0 and is not a source for this feature.

Demand is unconfirmed. The operator declined to say whether anyone has arrived with a folder. This spec still describes the intake, and it does not claim a tester was blocked.

## Goals

- A path-shaped argument that is a Spec Kit directory becomes intake. A sentence that merely mentions the shape stays prose.
- `spec.md` is projected into the Soleur spec template, with an unmapped appendix for headings that do not fit.
- `plan.md` and `tasks.md` are available to plan as side evidence and never become Soleur's plan or task list.
- A missing or unsafe `spec.md` stops the intake. The pipeline does not continue on the path string.
- The receipt names what moved, what was unmapped, and what was never read, before the projected Soleur spec is the build contract.

## Non-Goals

- Reading `research.md`, `data-model.md`, `contracts/`, `quickstart.md`, or a constitution file.
- Directories that are not `specs/<3-digit-or-timestamp>-<short-name>`.
- Copying Spec Kit templates, prompts, schemas, or tests.
- Opening, cloning, or quoting `hmuhlestein/HephaestusNG`.
- A new `soleur:go` routing row.
- A blog edit, a changelog hero, or the words "Spec Kit compatible."
- Writing customer spec bodies into the Soleur product tree.
- Replacing plan review or the Soleur task writer.

## User-Brand Impact

- **Artifact:** The intake that projects a Spec Kit `spec.md` into a Soleur spec.
- **Vector:** A silent map, a dropped success criterion, or a later story promoted to an equal requirement ships the wrong feature. Copied AGPL text contaminates the license.
- **Threshold:** `single-user incident`.

## Functional Requirements

### FR1: Path-shaped intake

When the argument is a directory path whose final two segments match `specs/<prefix>-<short-name>`, and the prefix is a 3-digit number or a `YYYYMMDD-HHMMSS` timestamp, brainstorm and plan treat it as intake. Prose that contains the same shape is not intake.

### FR2: Required `spec.md`

Intake reads `spec.md`. If that file is missing, unreadable, or not a regular file whose parent is the named directory, intake stops. The path string is not used as the feature description.

### FR3: Optional side files

`plan.md` and `tasks.md` are read when they are regular files in that directory. If either is missing, the receipt says `absent`. Their text is side evidence for plan. It is not copied into the Soleur spec's requirements, and kit task ids are not copied into Soleur's `tasks.md`.

### FR4: Projection

User stories and scenarios become functional-requirement candidates. Success criteria become goals. Explicit exclusions become non-goals. Every other heading is listed in an unmapped appendix. Unmapped text is not a requirement and is not built from.

### FR5: Receipt before the build contract

The receipt lists what moved, what was unmapped, and which files were never read (`research.md`, `data-model.md`, `contracts/`, `quickstart.md`, and any other name). The projected Soleur spec is the build contract only after that receipt exists. A second ingest does not overwrite a Soleur spec that a person has edited.

### FR6: No public compatibility claim

Docs and release notes for this change do not say Soleur supports, integrates, or is compatible with Spec Kit. They may say a founder can point Soleur at a directory they already wrote.

## Technical Requirements

### TR1: One read-only script

The reader is a script under `plugins/soleur/`, called by brainstorm and plan. The skill text does not open the directory. The script does not write, does not recurse, does not follow markdown links, and does not run a spec initializer.

### TR2: Containment

Resolve the directory from the invoking process cwd before any worktree `cd`, then re-read only that absolute path. Each selected file is a regular file whose resolved parent is the resolved directory. A symlink that leaves the directory fails the whole intake. A file over a fixed byte cap fails the whole intake. Do not use `soleur_approval_realpath`.

### TR3: Allow-list

The script opens only `spec.md`, `plan.md`, and `tasks.md`. Any other name, including `research.md`, `data-model.md`, `contracts/`, and `quickstart.md`, is unread and named on the receipt.

### TR4: Provenance

The implementation PR records this trailer and no AGPL or MIT notice:

`Provenance: Independent intake of the public GitHub Spec Kit directory shape (specs/<prefix>-<short-name>/{spec.md,plan.md,tasks.md}) only. No Spec Kit template, schema, or prompt text copied. No hmuhlestein/HephaestusNG source, schema, prompt, test, or comment read or copied. No AGPL notice applies.`

### TR5: Customer text and fixtures

Tests use synthesized directories. The Soleur product tree does not commit a customer's spec body. A caller's own feature branch may contain the projected Soleur spec, because that is their checkout.

### TR6: Call sites

Brainstorm runs the script before the empty-description question and before the clear-requirements shortcut. Plan runs the same script when it is the first entry and no Soleur spec exists yet. After a Soleur spec exists, plan reads that file, as it does today.

## Domain Review (carry-forward)

- **Product:** Unmapped appendix is mandatory. Later stories are not equal requirements. Demand is unconfirmed.
- **Engineering:** Script, not skill prose. `spec.md` required. Side files optional. Fail closed on escape.
- **Legal:** MIT docs only. HephaestusNG unread. Provenance trailer. No product-tree commit of customer bodies. GDPR gate not indicated.
- **Marketing:** No announcement. No compatibility wording.
