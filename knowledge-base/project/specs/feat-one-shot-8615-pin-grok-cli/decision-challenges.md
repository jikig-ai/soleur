# Decision challenges — feat-one-shot-8615-pin-grok-cli

Plan review raised taste-class findings. The pipeline was running headless, so they are recorded here
and the plan was left unchanged on these points.

## T1 — #8574 update: body append vs a short comment

- **Plan:** append a `## Pin-freshness criterion` section to the #8574 body. It covers all three
  vendor pins with their probes, the rule that `GROK_PIN` and `GROK_SHA256` move together, and the
  ownership-gap note that nothing executes the monthly comparison today.
- **Reviewer (code-simplicity):** post one short comment instead. The criterion already lives in
  ADR-245 and the test README.
- **Why the plan kept the body edit:** the #8574 body does not state the freshness criterion at all.
  Whoever closes #8574 on promotion reads the body, so that is where the ownership gap has to be
  stated.

## T2 — local mutation harness size

- **Plan:** a harness that loads the step and env from `ci.yml`, covering rows 1-6, a
  replace-with-`true` harness row, and a must-PASS row.
- **Reviewer (code-simplicity):** keep only must-PASS, row 1 and row 4. `harness-discovery` has no
  harness at all.
- **Why the plan kept the full harness:** Phase 2.12 (Guard Contract) needs at least three rows, one
  of which targets the guard's own dispatch, plus harness rows. The harness is local, scratch-only and
  is not committed.

## T3 — CR/LF strip on `raw` before `::error::` (deepen, security-sentinel P2 taste)

- **Plan:** no strip. `raw` is echoed only after the digest has pinned the bytes, so its content is
  the pinned binary's fixed output.
- **Reviewer:** add `raw=${raw//[$'\r\n']/ }` anyway. It costs nothing and does not depend on that
  ordering argument.
- **Disposition:** left to the operator. The plan-review simplicity pass argued the opposite, and the
  Codex/Devin arms do not strip either.
