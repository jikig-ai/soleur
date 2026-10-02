# Decision challenges (plan-review, headless)

Taste and User-Challenge findings from the plan-review panel that were NOT applied. The operator's stated
direction (and the binding CTO ruling) is the default; each entry says what was asked and what was kept.

## 1. User-Challenge: drop the four flag-skill rewordings and go.md (operator-requested scope)

- Raised by: DHH reviewer and the simplicity reviewer.
- Their case: those scripts stay on the TTY ack, so editing their skill text satisfies none of the plan's
  seven properties; limit the terminal-only sweep to generated-script surfaces.
- Kept: the operator's brief says any skill that tells the operator to use their own terminal as the only path
  must offer the agent-run path first. The CPO also requires the wording (state why, never present a terminal
  as the normal founder path, tracked follow-up with a milestone). Dropping it would drop operator-requested
  scope. Decide: keep the rewording (default), or cut it and accept the sweep reports those mentions as open.

## 2. Taste: cut the Read/Write/Edit receipt-directory deny arms (Bash-only hook)

- Raised by: DHH reviewer (Bash only) and the simplicity reviewer (cut the Read arm; records leak only a
  digest, an expiry and a session id).
- Kept: the CTO's binding ruling lists Write, Edit, Read, Bash and Monitor for the deny rule, with the Write/Edit/Read
  arms described as the reliable part (canonicalized path). The cost is a prefiltered path check.

## 3. Taste: fewer guard rows and fewer helper functions

- Raised by: DHH reviewer (13 rows total; fold `stage_decl`, `plan_op`, `stage_ok` into two functions).
- Kept: the CTO fidelity review asked for MORE rows (six missing mutation rows, a deterministic reorder row,
  more known-answer vectors). The plan already merged the duplicated rows across the three guards and dropped
  the classification file and the second capability number. Helper count is an implementation detail left to
  the work phase.

## 4. Taste: drop the apply-time `--rotate` rename and alias

- Resolved in the plan as a simplification (the existing `--rotate-token` name is kept); listed for the record.
