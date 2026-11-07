# Tasks: CTO owns read-only and preparatory technical work (Class R)

Plan: `knowledge-base/project/plans/2026-11-03-feat-cto-class-r-read-only-ownership-plan.md`
Branch: `feat-one-shot-cto-class-r-read-only-ownership` | Draft PR #12005 (unarmed) | Ref #10205 (never a closing keyword)

Pipeline constraints: do not arm, merge or ready the PR; run test suites one at a time; never print or paste a secret value.

## Phase 0: pin test (RED first)

- 0.1 Add the `Class R read-only ownership wiring (Ref #10205)` describe block to `plugins/soleur/test/components.test.ts`: newline-preserving slice-then-flatten helper, the frozen anchor table (superset semantics, floor = table length, cto.md scoped per `##` section), two member windows in section 9 (exclusions, hard limits), the `and similar` absence assertion, and the helper self-test. No set-equality.
- 0.2 Run `bun test plugins/soleur/test/components.test.ts`; confirm RED on the new block only.

## Phase 1: standing-delegation.md

- 1.1 Intro line: add the `(a read-only or preparatory act needs no step: section 9)` clause.
- 1.2 Append `## 9. Class R: acts needing no delegation` verbatim from the plan (six acts, boundary, credentials, exclusions sentence, hard-limits sentence, Operator-reserved carve-out, Records / `## Class R Checks`, evidence-not-precondition). Each pinned phrase on one physical line.
- 1.3 Confirm `git diff` shows additions only (plus the intro clause) and sections 1-8 are byte-identical.

## Phase 2: cto.md (additive only)

- 2.1 Add the "Class R first" paragraph inside `## Own the epic interface`, before the numbered list.
- 2.2 Add two bullets inside `## Rule interface`: "A live read-only check is technical" and the hold-classification bullet (`technical: checked ...` / `technical: unverified - ...`).
- 2.3 Confirm `git diff` has no removed body line; run `bash plugins/soleur/test/cto-interface-selector.test.sh`.

## Phase 3: go.md and the ruling reference

- 3.1 Add the new "waiting on you" Sharp Edge bullet immediately after the first Sharp Edge in `plugins/soleur/commands/go.md` (Step 1.5 and the first bullet byte-identical).
- 3.2 In `technical-ruling-delegation.md`: change 8.1 "every decision" to "every decision or task"; add the `8.1b (founder-facing close)` paragraph right after 8.1b (What I checked block, always-shown Waiting on you, categories).

## Phase 4: operator-holds.md

- 4.1 Add the two-sentence paragraph (Gate when a kind fits; otherwise `Checked:` / `Unverified:` in `## Class R Checks`; a read never satisfies a Gate) after "The grammar has two kinds..." in section 1.

## Phase 5: AGENTS.rules.md

- 5.1 Replace line 62 with the CTO-ruled 582-byte text (id unchanged). `AGENTS.md` untouched.
- 5.2 `python3 scripts/lint-agents-rule-budget.py AGENTS.md AGENTS.rules.md 2>&1`, `python3 scripts/lint-rule-ids.py`, `python3 scripts/lint-agents-enforcement-tags.py`.

## Phase 6: ADR-289 addendum

- 6.1 Append `## Addendum 2026-11-03 (Ref #10205)` via the architecture skill; `status: adopting` unchanged.
- 6.2 Check the ADR's `## Diagram` section and `factory-map.md` for any "every agent act needs a delegation" claim.

## Phase 7: verify (sequential)

- 7.1 Run, one at a time: `delegation-verify.test.sh`, `cto-interface-selector.test.sh`, `go-hold-routing.test.sh`, `hold-gate-eval.test.sh`, `technical-ruling-gate.test.sh`, `components.test.ts`, `ship-undeferred-operator-step-gate.test.ts`, `go-session-gates.test.sh`, `go-routing-table-parity.test.sh`, `pr-overlap-preflight.test.sh`, `harness-parity.test.ts`, `harness-parity-tree.test.ts`, `c4-count-parity.test.sh`.
- 7.2 Drive each of the four mutation rows and three harness rows of Guard 1 once, then revert.
- 7.3 Run `soleur:gdpr-gate` advisory on the diff (CPO condition 6).
- 7.4 Run each Class R CLI shape once, read-only; confirm no unknown `--json` field.
- 7.5 `gh pr view 12005 --json closingIssuesReferences` prints `[]`; PR body says `Ref #10205`; PR remains an unarmed draft.
