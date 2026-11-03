# Tasks: feat-one-shot-9851-art32-tom-art33-5-assessment

Plan: `knowledge-base/project/plans/2026-11-03-docs-art32-tom-residual-and-art33-5-assessment-9851-plan.md`. Ref #9851, Ref #9601.

## Phase 0: Re-verify at the pinned commit

- [x] 0.1 Run the plan's Verification Commands; record each output line in `session-state.md`.
- [x] 0.2 Read ADR-075 to its end for addenda newer than 2026-10-31; cite the latest state of every source.
- [x] 0.3 Confirm `proc_mask` is in the faithful canary verdict before saying it was read in production.
- [x] 0.4 Run the grep of AC9(f) over the canonical legal documents and mirrors; record the output.

## Phase 1: Art. 32 TOM bullet and Superseded marker

- [x] 1.1 Draft the bullet per plan Phase 1 specification (named-gap order, status `open residual`).
- [x] 1.2 Insert it after the arm-F bullet and its 2026-10-31 pointer comment, before Audit logging.
- [x] 1.3 Add the Superseded blockquote directly under the arm-F bullet (six statements); no existing character edited.
- [x] 1.4 Fill the claim-to-source table in spec.md with the resolved anchors.

## Phase 2: Art. 33(5) row

- [x] 2.1 Draft the nine cells per plan Phase 2 (no pipe, one defect sentence, window wording of D5).
- [x] 2.2 Append the row after the 2026-10-31 row; add the ADR-075 path to `related:`.

## Phase 3: Checks

- [x] 3.1 AC1 to AC4, AC6, AC9, AC10, AC11 commands; fix and re-run.
- [x] 3.2 Run the technical-ruling gate on decision-challenges.md.

## Phase 4: Review panel (first)

- [ ] 4.1 `soleur:review` with `soleur:engineering:review:user-impact-reviewer` and the standard panel; apply findings.

## Phase 5: CLO review (last)

- [ ] 5.1 Spawn a fresh `soleur:legal:clo` on the final diff with the wording lists; it writes nothing under `knowledge-base/legal/audits/`.
- [ ] 5.2 Append `## CLO Review Record` (reviewer, patch id and blob hashes, verdict, conditions, stale pointer, routed finding).
- [ ] 5.3 Any later register edit: repeat 5.1 and 5.2.

## Phase 6: QA, compound, ship

- [ ] 6.1 QA; compound (learnings file optional).
- [ ] 6.2 Ship per the plan's Ship Notes (Ref lines, displaced-path sentence, Check 4 skipped, ledger re-pin note); AC2, AC7, AC8 at the final head; merge via the queue.
