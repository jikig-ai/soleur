# Tasks: ADR-276 Decision 4 adopting line

Plan: knowledge-base/project/plans/2026-10-11-docs-adr-276-decision-4-adopting-line-plan.md

## 1. Edit

- 1.1 Re-read the ADR Stage status block; confirm the last line still begins `- 2026-10-09 S3 amended (#9728;`.
- 1.2 Append the single dated line from the plan's Implementation section after it (before `## Context`). Do not edit any other line.

## 2. Verify

- 2.1 `git diff origin/main -- <ADR>` has one added line, no removed content lines.
- 2.2 Added line has no `S3 live` claim, no `exited`, no `S2`/`CI_PUSH_DEDUPE`; ADR-270 appears only as a non-evidence disclaimer.
- 2.3 Run the markdown lint used for knowledge-base files.

## 3. Ship

- 3.1 PR #10040 body: `Ref #9728`, no Closes/Fixes/Resolves; mark ready after verify.
