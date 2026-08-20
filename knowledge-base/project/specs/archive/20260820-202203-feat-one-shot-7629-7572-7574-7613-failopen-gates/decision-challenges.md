# Decision Challenges — feat-one-shot-7629-7572-7574-7613-failopen-gates

Recorded per ADR-084 / `decision-principles.md`. This session ran headless, so these are
persisted rather than asked. `/ship` renders them into the PR body and files an
`action-required` issue. The operator's stated direction remains the plan's default wherever it
is still executable.

---

## Challenge 1 — `#7613`: the stripper the direction centres on is a measured no-op

**Class:** user-challenge (the operator's stated direction, challenged on measured evidence).

**The direction.** #7613's fix should centre on the shared `.code.sh` comment stripper, with a
RED step and a GREEN step paid **per consumer arm** rather than once for the shared file, and
the arms enumerated explicitly by reading the file.

**What was measured.** Rendering `apps/web-platform/infra/cloud-init-git-data.yml` through the
module's own strip and extracting exactly as the suite's Python heredoc does:

| Artifact | Lines | Lines containing `#` after the render strip |
|---|---|---|
| `luks-stage.sh` (`STAGE=luks_open`) | 55 | **0** |
| `runcmd-all.sh` (all runcmd entries) | 170 | **1** — `STAGE=volume_mount # (#6982) name the stage for the top-armed on_err fatal` |

That single line is read by no R3 predicate. There are zero `${var#pat}`, `$#`, `#`-in-string
or shebang occurrences in either artifact — those live in `write_files`, which never enters
`.code.sh`. Four independent reviewers reproduced this; one rendered with terraform directly.

**Why it matters.** The stripper change alters `luks-stage.code.sh` by zero bytes and
`runcmd-all.code.sh` by one line's tail, and changes **no arm's verdict**. The property it is
meant to buy — *the R3 predicates quantify over code, not commentary* — is bought
**unconditionally** by anchoring the predicates (plan Guards 6, 7, 8), which are immune to
comments regardless of the input. The first draft of this plan also shipped three assertions
about the stripper that could not be driven RED, because they quantified over the empty set.

**What the plan does.** The per-arm RED/GREEN discipline is kept in full and applied to all
eight enumerated arms — but paid for the **anchoring**, which genuinely re-flows every one of
them. The stripper is retained per the direction, re-labelled honestly as prophylactic
hardening, scoped to two lines, with its assertions moved onto a synthesized fixture.

**The call for the operator.** Keep the prophylactic stripper (current default), or drop it and
close #7613 with the anchoring alone. Dropping it also removes the ADR-152 amendment, the
`_b2_strip` parity assertion, and one arm's worth of work.

---

## Challenge 2 — `#7572`: the issue's own suggested fix for `_SKIP_CEILING` is a tautology

**Class:** user-challenge (reverses advice written into the issue body).

**The direction.** #7572 §Suggested fix item 5: *"Consider replacing the hand-derived constant
with a grep of `arm_skip` call sites, since a prose coupling note will not enforce it."*

**Why the plan reverses it.** `SKIPPED_ASSERTIONS` is the sum of the costs *actually taken* at
`arm_skip` call sites. A ceiling equal to the sum of all *declared* costs makes
`SKIPPED_ASSERTIONS <= _SKIP_CEILING` an identity that can never fire — the AP-023 shape, and
the opposite of what the constant is for. ADR-188 already weighed and rejected exactly this:
*"Raising it is not detectable by any assertion that would not be text-matching the source,
which is the antipattern this suite rejects. The mitigation is procedural and declared."*

**What the plan does instead.** Keep the literal as a shrink-only ratchet (precedent:
`MAX_DEFERRED=47` in `scripts/guard-vacuity-floor.test.sh`), raise it to 5 with an itemised
derivation stanza, and add a separate assertion that the `arm_skip` call-site count matches the
stanza — which *can* disagree, and reddens in both directions. ADR-188 gets an amendment
recording the partial move.

---

## Challenge 3 — `#7574`: the mechanism it asks for exists, and its carrier retires it

**Class:** user-challenge (the issue's framing of the residual is wrong in both directions).

**The direction.** #7574 records the residual as needing *"an observability mechanism the suite
has no precedent for"* and scope-outs it as an architectural pivot.

**What was measured.** The mechanism exists and is enrolled:
`scripts/followthroughs/t5-skip-persistence-bound-7510.sh`, run daily by
`.github/workflows/scheduled-followthrough-sweeper.yml`. It has never reached a verdict — its
2026-08-19 run returned `TRANSIENT (exit 2)` with twenty `printf: write error: Broken pipe`
lines, because `printf '%s' "$log" | grep -qF "$MARKER" || continue` under `set -uo pipefail`
scores a successful match as a miss. And repairing it would not be enough: the follow-through
sweeper closes an issue on PASS and `closed_precheck` then refuses to re-litigate any issue
carrying its own PASS block, so a repaired probe would retire its own tracker after one run.

**What the plan does.** Repairs the EPIPE defect, replaces the marker with an enumerated
per-arm set (a bare `SKIP (loud): ` prefix would count `infra-config-apply.test.sh`'s
non-root skip from the same run log and return FAIL every day forever), adds a
consecutive-TRANSIENT escalation, and **re-homes the carrier** onto a standing daily monitor
workflow rather than the one-shot follow-through sweeper.

**The call for the operator.** The plan adds one small scheduled workflow. The alternative is to
accept a one-shot answer — "the residual did not materialise in this 20-run window" — and close
#7574 on that, which is not the persistence bound the issue asks for.
