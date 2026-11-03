# Tasks: feat-one-shot-9603-public-security-claim-ledger

Plan: `knowledge-base/project/plans/2026-11-03-feat-public-security-claim-ledger-plan.md`. Work phase only; the ledger file is not written during planning. Every sub-agent prompt carries the read-only preamble from the plan's Implementation Phases.

## Phase 0: Setup

- 0.1 `git fetch origin main`; record the origin/main SHA.
- 0.2 Generate the frozen sweep file list into the scratchpad (three worker categories, one owner each).

## Phase 1: Row verification

- 1.1 CLO agent re-verifies every evidence matrix row against the pinned SHA (latest state of each source) and returns a seed-versus-verified diff table.
- 1.2 Record each status flip as a technical row in `decision-challenges.md`.
- 1.3 Read the four flag states by the read-only rule or mark them `unverified: <missing source>`.

## Phase 2: Ledger Part 1

- 2.1 Write banner, legend, Part 1A and Part 1B (flag tags, host class, ADR status quote, bullet pointers).
- 2.2 Hand the frozen Part 1 id list to the Part 2 workers.

## Phase 3: Part 2 sweep

- 3.1 Three CLO workers (docs/legal; docs site, blog, READMEs; in-app copy and registers) return rows with the trailer line.
- 3.2 Re-dispatch any slice with a missing or mismatched trailer; add Part 1 rows for unmapped statements.
- 3.3 Merge Part 2; triage each finding (type, disposition); stop and return any `escalate` item to the lead.

## Phase 4: Criterion and decisions

- 4.1 Write the Publication Criterion with pass criterion and reviewer one-liners, the premise correction, the #2004 decision and the re-evaluation trigger.
- 4.2 Write Method last (pinned SHA, commands, ADR path checks).

## Phase 5: Verification

- 5.1 Run AC1 to AC5 and AC6a with negative controls; fix and re-run.

## Phase 6: Reviews

- 6.1 Standard panel and `soleur:engineering:review:user-impact-reviewer` (report-only), apply findings.
- 6.2 Fresh CLO review last; append the CLO Review Record (prose) to `decision-challenges.md` with blob hash and SHA.
- 6.3 Re-run AC1 to AC5 and AC6a after any edit; run `technical-ruling-gate.sh --branch` and require exit 0.

## Phase 7: Handoff

- 7.1 Hand the lead the PR-body notes (`Ref #9603`, `Ref #9601`, finding counts, ledger path) and the finding list for the human principal.
