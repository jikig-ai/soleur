# Learning: Plan review catches redundant validation gates

## Problem

When designing the content-writer skill, the initial plan included a 5-phase flow: Prerequisites -> Parse Input -> Generate Draft -> Brand Voice Validation -> User Approval -> Write to Disk. Phase 3 (brand voice validation) was a separate pass that re-read the brand guide and compared each generated paragraph against the voice guidelines before showing the draft to the user.

## Solution

During plan review, both the DHH reviewer and code-simplicity reviewer independently flagged the inline brand voice check as redundant. The reasoning:

1. The generation phase already reads the brand guide's Voice section and generates content in that voice
2. The user approval gate (Accept/Edit/Reject) serves as the real quality check
3. Adding an automated validation pass between generation and user review adds complexity without meaningful safety -- the user sees the output regardless

Removed Phase 3 entirely, collapsing the skill from 5 phases to 4: Prerequisites -> Parse Input -> Generate Draft (with brand voice baked in) -> User Approval -> Write to Disk.

## Key Insight

When designing multi-phase workflows, look for "validation phases" that duplicate what adjacent phases already provide. If the generation step incorporates the constraint (brand voice), and a human review step follows, an automated validation pass between them is redundant. The pattern: **generate correctly > validate after** beats **generate > validate > review**. Trust the generation prompt to do its job; rely on human judgment as the real gate.

This also applies to the growth fix flow: instead of a separate brand voice validation step, the agent validates during generation by reading the brand guide before applying edits.

## Tags

category: workflow-patterns
module: content-writer, growth-strategist
symptoms: over-engineering, redundant validation, unnecessary phases
