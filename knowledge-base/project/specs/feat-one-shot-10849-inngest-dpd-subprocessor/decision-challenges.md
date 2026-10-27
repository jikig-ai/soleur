# Decision Challenges — feat-one-shot-10849-inngest-dpd-subprocessor

## Decision Classes

| Item | Class | Ruling |
|------|-------|--------|
| §2.3(o) replacement text | legal (CLO) | Ruled by CLO agent, 2026-10-22 (recorded in `knowledge-base/legal/audits/2026-10-counsel-review-9927.md` + issue #10849): the CLO-prescribed clause replaces "no external sub-processor" verbatim — implement, do not re-litigate |
| Sibling-sentence rewrites ((aa), privacy §4.13, gdpr recipients bullet, §4.2 row) | legal (CLO) | pending — drafted in the plan's Implementation Phases from the same verified facts; routed to the counsel-review attestation pass (Phase 9) per the issue's "counsel-review attestation pass" requirement and the CLO delegation rule for new legal drafting |
| `requires_cpo_signoff: true` at single-user-incident threshold | operator (sign-off) | pending — declared in plan frontmatter; headless pipeline cannot pause; recorded for ship Phase 6 rendering per the ADR-084 channel |
| Correction-note date pinned to October 27, 2026 | technical | pending - assumed: house style dates the correction at edit date; if the pipeline crosses midnight UTC before commit, update all six notes + AC5 to the commit date |
