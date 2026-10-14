# Decision challenges — plan review 2026-09-11

Taste-class findings from the plan-review panel (DHH / Kieran / code-simplicity / CTO), headless
run — recorded here for `ship` Phase 6 rather than decided silently. None changes the operator's
stated direction.

1. **Phase 7 step-4 note on the merge-commit skip.** code-simplicity: delete (P7 is fully bought
   by `lefthook.yml`; the agent sees lefthook's `(skip)` line). DHH: keep. Disposition taken:
   kept as one clause on the commit line, not a sentence — it is the one place an agent decides
   whether to reach for `--no-verify`.
2. **Three authoring sites of the no-item sentence** (`pir.md`, `incident/SKILL.md`,
   `dry-run.sh`). DHH: a plan whose thesis is "stop pinning one string in three places" leaves
   three pins. Disposition taken: left as three, asserted byte-equal by the template-parity arm;
   the one-site fix (`dry-run.sh` reading the template) is named in Non-Goals.
3. **Observability block for a laptop-run bash gate.** DHH: the block is form-filling; the rule
   wants a layer-7 fast path. Disposition taken: block kept (the gate requires it); no rule change
   proposed in this PR.
