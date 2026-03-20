# Learning: Bulk Rename Semantic and Architectural Pitfalls

## Problem

When renaming a file and updating references across 22+ files, three classes of error emerged that are invisible to simple find-and-replace tooling:

1. **Semantic corruption**: A documentation file contained a sentence contrasting the old filename with the new filename (e.g., "we renamed A to B"). A blind `replace_all` changed both A and B to the new name, producing "we renamed B to B" -- a nonsensical tautology. The sentence's purpose was to document the rename itself, so the old name was load-bearing context, not a stale reference.

2. **Architecture regression**: The plan specified replacing "Data Processing Agreement" with "Data Protection Disclosure" in the legal-document-generator agent. But the generator is a generic, cross-project tool -- it supports DPAs for any SaaS project with processor relationships, not just Soleur. Removing DPA capability from the generator to match Soleur's specific rename would have eliminated a legitimate feature. The Sharp Edges documentation already referenced DPA as a supported type, creating a dead reference.

3. **Incomplete file list**: The plan's file list missed a reference in the CLA plan file. Only a post-edit `grep` across the entire repo caught the stale reference.

## Solution

1. **Never use `replace_all` on documentation files.** Review each match in context. When a sentence deliberately contrasts old and new values (changelogs, migration notes, rename records, comparison tables), the old value is intentional and must be preserved.

2. **Distinguish "this project's instance" from "the tool's capability catalog."** When renaming a concept in your project, add the new type to generic tools rather than replacing the old one. The old type remains valid for other use cases. Ask: "Would another project using this tool still need the old type?" If yes, keep both.

3. **Always run exhaustive grep verification after bulk renames.** The plan's file list is a starting point, not the source of truth. A repo-wide grep for the old name catches files the plan missed. Treat any remaining match as a potential bug until proven intentional.

## Key Insight

Bulk renames have three blast radii that expand beyond "find old string, replace with new string":

- **Semantic radius**: Some occurrences of the old name are intentionally old (historical references, contrast statements, migration docs). Replacing these destroys meaning.
- **Architectural radius**: Renaming a concept in your project does not mean the concept ceased to exist. Generic tools that support the old concept for other contexts must retain it.
- **Discovery radius**: Plans enumerate known files, but repos contain references the plan author never considered. Grep is the only reliable enumeration.

The common failure mode is treating a rename as a mechanical text substitution when it is actually a semantic operation that requires understanding why each occurrence exists.

## Session Errors

1. **Blind find-and-replace semantic bug**: A subagent used `replace_all` on a learning file, changing both sides of a "filename A vs filename B" comparison to the same name. The sentence was meant to contrast the old and new filenames, so the old name was intentional. Fix: review each match in documentation files individually.

2. **Architecture regression in plan**: The plan specified replacing "Data Processing Agreement" with "Data Protection Disclosure" in the generic legal-document-generator. This was wrong -- the generator is a cross-project tool and DPA is a legitimate document type for SaaS projects with processor relationships. The Sharp Edges section already referenced DPA, which would have become a dead reference. Fix: added Data Protection Disclosure as an 8th document type alongside the existing Data Processing Agreement.

3. **Missed file in plan**: The CLA plan file (`knowledge-base/project/plans/2026-02-26-feat-cla-contributor-agreements-plan.md`) contained a stale reference to the old filename but was not in the plan's file list. Caught by post-edit verification grep. Fix: always grep the full repo after bulk renames, not just the planned file list.

## Tags
category: process-errors
module: documentation, legal-documents, agents
