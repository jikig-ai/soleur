# Decision Challenges — feat-one-shot-8290-invocation-axis-budget-relief

Persisted headless by `soleur:plan` (Step 4.5 consult + Phase 2.5 domain leaders) and
`soleur:plan-review` (9-seat panel). `ship` Phase 6 renders these into the PR body and files the
`action-required` issue. Each entry names the **default applied** (the operator's stated direction unless
noted) and the alternative the operator may choose instead.

## DC-1 (User-Challenge) — What a non-EXTEND B5 verdict records, and where

- **Operator direction:** "if it shows none, close B5 as tested-and-rejected and record it in bundle 3's rejected-concepts record."
- **Challenge:** `knowledge-base/project/rejected/README.md` reserves the no-list for refused *concepts*; refused *mechanisms* belong in ADR alternatives tables. The advisor adds that a public refusal written from an underpowered null overstates the evidence.
- **Also raised by** the plan-review CPO and Kieran. `README.md:146-148,165` forbids an unconfirmed entry, and forbids recording something nobody refused. INCONCLUSIVE carries a `revisit_if`, so it reads as a deferral.
- **Default applied:** every non-EXTEND verdict closes B5. The record goes where each verdict's own contract allows:
  - **REJECT and REJECT-CEILING** → the no-list entry, framed as Soleur's own measurement and gated on the typed-concept confirmation (a merge gate). It is mirrored in ADR-236.
  - **INCONCLUSIVE** → ADR-236 and `b5-eval-results.md`, plus a `revisit_if` follow-up issue. **No no-list entry.**
- **Alternatives:** an entry on INCONCLUSIVE too (the operator's literal wording); or ADR-only for every verdict.

## DC-2 (User-Challenge) — Split B5 into its own PR

- **Raised by:** CTO (Phase 2.5), Step 4.5 advisor.
- **Default applied:** the eval and its verdict stay bundled, per #8290 and the run constraint to close B5 in this run. On EXTEND, only the `AGENTS.rules.md` rewrite and its acks go to a separate follow-up PR. That PR is not auto-merged and goes to @deruelle for review (architecture P1-3: CODEOWNERS review is not enforced on main, so an autonomous run appending its own acks would approve its own weakening).
- **Alternative:** ship the invocation axis and B6 now, and move B5 (eval plus verdict) to a follow-up PR. ADR-236 would then carry an "open" row.

## DC-3 (Taste) — Ratchet `SKILL_DESCRIPTION_WORD_BUDGET` down vs keep slack

- **Default applied:** lower the cap to the measured post-flip total (2561 − 266 = 2295 if nothing concurrent lands), which keeps the zero-headroom convention and banks the relief.
- **Alternative:** keep 2561 and leave 266 words of headroom for future skills.

## DC-4 (User-Challenge) — Flip 12, not the 16 the issue lists

- **Default applied:** 12. `flag-bootstrap` is not a skill. `trigger-cron` is named as the agent's own tool in `hr-no-dashboard-eyeball-pull-data-yourself`. `invoice` is founder-facing and reachable on the web only through the model. `flag-list` is a read-only audit the agent must be able to pull itself (plan-review agent-native P1).
- **Alternative:** the operator may override per skill.

## DC-5 — The no-list's typed-concept confirmation

The README ("Writing an entry" step 4) asks for the concept to be typed, not `y`. That cannot be taken
headless. The basis recorded instead is the operator's standing direction in #8290 plus the run
constraints. The operator confirms it at PR review by typing the concept, or declines, in which case the
entry is deleted before merge (the directory is public and git-permanent).

## DC-6 (declined with reason) — CPO C2 "run the tool-selection eval before and after"

That eval's arms are static hand-written catalogs and cannot observe the harness listing. It is replaced
by the W0-f before/after listing probe on a 200k-window model.

## DC-7 (Taste) — Reduce B5 spend by dropping the `none` arm or running `--repeat 2`

- **Raised by:** DHH (plan-review), with simplicity marking it optional.
- **Default applied:** keep all three arms and `--repeat 3`. The `none` arm is the only V1 control that shows each rule matters at all. The $60 spend cap already falls back to `--repeat 2`.
- **Alternative:** drop `none`, which saves a third of the calls, at the cost of V1.

## DC-8 (Taste) — Guard 1 size

- **Raised by:** DHH and simplicity, who want a scan of groups 1-2 only, with no exact-set pin. Architecture, test-design and COO want more coverage (hooks, lib, Inngest prompts, runbooks, per-glob floors).
- **Default applied:** the correctness side for coverage, and the simplification side for form. The bare-name durable scan is cut, reasons are down to two, and rows are trimmed.
- **Alternative:** the minimal DHH form.

## Outcome — 2026-09-21 (B5 run)

- **DC-1 resolved by measurement: INCONCLUSIVE** (+8.0 pts, [+0.2, +15.8], MWE 10). The INCONCLUSIVE
  branch applied: ADR-236's alternatives row and `b5-eval-results.md` carry the record, and the
  `revisit_if` follow-up is #8497. **No rejected-concepts entry was written.** The operator can
  still override toward an entry at review.
- **DC-5 did not fire.** No entry exists, so the typed-concept confirmation is not needed for this PR.
- **DC-7:** the run used `--repeat 3` and all three arms. It cost $48.85, inside the $60 cap. One
  deviation was made before spending: `ANTHROPIC_MAX_TOKENS` went from 300 to 3000, because thinking
  models returned empty text at 300 (evidence in `b5-eval-results.md`).
- **DC-4 revised by review:** the final flip set is 8, not 12. flag-create, flag-set-role, cron-list
  and cron-delete stay model-invocable (CTO ruling; ADR-236 reviewed list).
- **B5 disposition refined:** the verdict carries the qualifier "instrument validity limited", and the
  machinery is archived (b5-eval-results.md §Post-verdict instrument audit).
