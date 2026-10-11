# Decision challenges — #7258 Step A (consumer probe covers the inngest-bootstrap repo)

Recorded headless by `soleur:plan` / `soleur:plan-review` (ADR-084). `soleur:ship` renders these
into the PR body and files the `action-required` issue.

## User-Challenge 1 — gate the heartbeat on the bootstrap repo from day one, or report-only first

- **Operator's stated direction (brief):** "classify per repo with a worst-of / all-must-pass heartbeat rule" on the existing single heartbeat.
- **What the plan does:** exactly that. Both repos gate the ping from the first run after the apply lands.
- **Challenge (named devex seat, `soleur:engineering:cto`):** ship the bootstrap repo as report-only for the first observation window (marker row emitted, excluded from the AND), then fold it into the gate. That removes the false-page risk of an unproven second-repo check on the only live web origin's heartbeat.
- **Why the plan keeps the operator's direction:** the whole point of the change is that a bootstrap-repo fault is detected; a report-only phase needs a second probe change and a second sequential apply before the heartbeat covers it, and the false page would itself be a true positive about a fresh-boot hazard. Existence evidence is gathered before merge (plan Phase 0.3).
- **Cost of the challenge:** one more PR and apply cycle, and an env or flag to mark a repo report-only.
- **Default if nobody objects:** all-must-pass from day one (as planned).
