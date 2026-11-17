# Learning: a denylist that bounds standing approvals does not bound per-command go-aheads — and a runnable act presented as an operator errand is a classification defect

## Problem

During the epic #10390 deploy-Access rotation chain (#12380 session record), the Needs-you list
presented to the operator held five items, and zero of them required the operator's hands
(#12443 diagnosis). Each session was locally correct: the acts genuinely sat outside the recorded
standing-delegation Scope and genuinely hit the delegation's closed denylist. The defect was the
bucket they landed in. The denylist bounds what a **standing approval** may cover — the acts a
`Delegation:` line authorizes the agent to run unattended. It was being read as a bound on
**per-command authorization** — the typed in-session go naming the exact command that
`hr-menu-option-ack-not-prod-write-auth` and standing-delegation §9's hard limits already sanction
as a separate authority lane. With no classification slot for "operator authorizes, agent
executes", every non-grammar, non-Class-R act collapsed into `Operator-reserved:` — the
closed physical founder-only list — and a non-technical founder received console errands where a
go-line would have done.

## Solution

Added the fourth hold class, `Operator-authorizes:` — a second hold-word prefix beside
`Operator-reserved:` sharing its semantics (always stands, gates never probed, cleared only by the
operator) and differing only in who runs the act after clearance: for `Operator-reserved:` the
operator does it; for `Operator-authorizes:` the agent restates the exact command in-session, the
founder types a go naming it, the agent runs it, and the line is removed or rewritten. The split
rule is stated identically at every site that classifies or writes a reserved-family line:
`hold-gate-eval.sh` (recognizer + `Say go and I run it:` verdict), go.md Step 1.5 (set-aside,
classification route, delegation conversion), cto.md steps 2/3/9, technical-ruling-delegation.md
§1/§8.1c, standing-delegation.md §6/§9. Companion fix: the standing-delegation Scope is drafted
from the epic's full remaining grammar-compatible chain rather than the next few acts, and a Scope
gap fails closed to the authorizes path instead of an errand. Non-goals held byte-identical: the
four-command grammar, the denylist, and the verifier-pinned Excluded sentence (widening tracked as
#12479).

## Key Insight

Ask of every denylist which mechanism it bounds. A closed list scoped to standing approvals says
nothing about per-command authorization — reading it as the union of the two silently erases a
lane the authority model already provides, and the failure presents as mislabeled work, not an
error: the operator sees "your hands needed" for acts a typed go would have unblocked. The Class R
precedent's three pin lessons applied verbatim: the printed verdict (`Say go and I run it:`) was
checked against `OWNER_HEAD_RE` and the `PARKED_*` vocabulary before choosing it (a label is also
a match target for the triggers that scan the shared vocabulary); the boundary sentence was
written identically at all six sites; and the change states plainly what it does not do — the
grammar and denylist are unchanged by design.

## Session Errors

1. **Review ran and its findings were fixed, but the evidence step was skipped — the trailer and
   Review-Evidence comment were never emitted.** Recovery: emitted the trailer
   (`emit-review-trailer.sh`, `sequential-fallback 4/4`) at the ship tail before creating the PR.
   **Prevention:** ship's Phase 1.5/5.5 re-read is the backstop, not the mechanism — the pipeline
   tail should emit the trailer the same turn the fix commit lands (#7774 shape; review SKILL.md
   Step 3 is "ALWAYS — not conditional").
2. **go.md Step 1.5's plan-source trigger missed the new class** — an `Operator-authorizes:` hold
   typically carries no `Gate:` line, so a plan whose only hold was authorizes-class silently
   failed to trigger routing. Found by the review's silent-failure seat; fixed in the review-fix
   commit. **Prevention:** when a token family widens, grep the literal token across the file being
   edited too — the trigger clause lived in the same file and the cross-consumer sweep still
   missed it.
3. **A copied technique copied its hole:** `authorizes_hold` was written as a mirror of
   `reserved_hold`, inheriting its missing HTML-comment strip while go.md's normalization does
   strip — a `<!-- x -->` prefix desynchronized the two classifiers on the fail-closed boundary.
   **Prevention:** when a second recognizer mirrors a first, diff the normalization steps across
   every classifier that consumes the same lines, not only the two recognizers being compared.
4. **`tasks.md` spec drift:** item 1.1 wrote "first-16 alnum compare" for a 17-char token
   (`operatorauthorize`). Cosmetic — the code was right. **Prevention:** spec numbers that repeat
   an implementation constant rot the moment the constant is chosen; write them once, in the
   contract the tests pin.
