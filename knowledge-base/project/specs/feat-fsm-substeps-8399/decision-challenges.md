# Decision challenges — feat-fsm-substeps-8399 (#8399)

Recorded headless during plan review (plan: `knowledge-base/project/plans/2026-09-21-feat-fsm-substeps-compound-skip-triage-plan.md`).
The plan follows the brief's stated direction in every case below; these are the dissents.

## 1. User-Challenge — dissent 1 of #8399 should be decided, not surfaced (CTO + DHH plan review)

- **Direction as briefed:** dissent 1 (a `post >= 5` floor on the sharp-edges "kept on measured evidence" rule) is an operator call. The plan surfaces it and does not decide it.
- **Recommended instead:**
  - CTO: adopt the floor, which is the conservative choice, and close #8399. By the reviewer's reading of `hr-technical-fork-is-not-an-operator-question`, a statistical floor is not authorization, cost or scope.
  - DHH: ship with `Ref #8399` and split dissent 1 into its own issue, so this PR does not wait on it.
- **Why:** today's reading is `post=10 median_k=55`, so the rule and the floor agree and no verdict changes.
- **Cost if the dissent is right:** #8399 stays open for one sentence of ADR text.

## 2. User-Challenge — the view key-set pin is redundant (code-simplicity plan review)

- **Direction as briefed:** "pin both key sets in the parity block". The plan adds a test naming the view's `sub_steps` and `transitions` keys.
- **Recommended instead:** cut it. The existing parity deep-equal plus the exact-set `toEqual` already pin both key sets, and bun's diff already names the missing key.
- **Cost if the dissent is right:** one redundant test, plus its mentions in the ADR Verification section.

## 3. Taste (declined) — cut the Guard Contract, Observability and C4 sections (DHH plan review)

- **Recommended:** keep only Overview, B evidence, Files, tests and ACs.
- **Declined:** plan Phases 2.9, 2.10 and 2.12 and deepen-plan's halt gates require these sections. The C4 section is kept short.

## 4. Taste (declined) — per-parent substep counts or a containment window on the collapse (Step 4.5 advisor)

- **Recommended:** keep the in-ship vs after-ship compound split visible inside the classifier.
- **Declined:**
  - The Appendix triage reads raw sequences independently of the view, so the split stays measurable.
  - A compound after ship precedes no skip.
  - The log carries no parent id.
  - A new `--summary` key would break the null-line contract that case 27 pins.

## 5. Taste (declined) — generate the JSON view from the TS const (Step 4.5 advisor)

- **Declined:** ADR-229 Alternatives already weighed the `bun -e` read and kept the hand mirror plus the parity test. Reversing that is out of scope for #8399.
