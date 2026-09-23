# Decision Challenges — feat-8486-human-presence-guard

Headless-path record (no interactive operator gate). `soleur:ship` should render these into the PR
body and file an `action-required` issue so the operator sees them. Each is a **taste** finding from
the plan-review panel: the plan keeps its current design (the default) and the finding is surfaced,
not applied.

## T-1 — Keep or drop the segment-scoped read-only escape in the defer rule (plan Phase 4.2)

**Finding (code-simplicity-reviewer, P2):** reuse the hook's existing whole-command
`READONLY_FLAG_PATTERNS` check; a `--dry-run` hidden elsewhere in a chain is deliberate evasion (a
Non-Goal), and the script's own precheck still refuses at exit 64.

**Plan keeps the segment scope because:** `bash flip.sh f prd on --dry-run && bash flip.sh f prd on`
("preview, then apply" in one command) is an accidental pattern, not an evasion. Whole-command
matching lets the apply half through the backstop. The change is one capture group.

## T-2 — Fewer invocation shapes in Guard 3 (five → three)

**Finding (simplicity, P3):** drop the nested `bash -c '…'` and `cd x &&` shapes; the `cd` shape is
already a named residual.

**Plan keeps five:** `bash -c` is what `doppler run -- bash -c '…'` in the `oauth-probe-failure.md`
runbook produces; the `cd` row asserts the residual is what the ADR says it is (a known miss), so
the ADR cannot drift from the hook.

## T-3 — One stub profile for every arm-table row (drop `stub_profile` and the hetzner external row)

**Finding (simplicity, P3).** **Plan keeps the column** until implementation shows the fixtures are
uniform; provision-hetzner is already driven by `operator-script.test.sh`, and duplicating its
`hcloud` stub is the larger change.

## T-4 — Narrow Guard 1's detectors (line-local `yes` match; `--confirmed`/`--yes` only)

**Finding (simplicity, P2):** drop read-variable-to-comparison tracking (and rows M5, H2).

**Plan keeps the tracking:** M5 (`printf 'Type yes: '; IFS= read -r ans`) is the shape a line-local
`read -p … yes` detector misses, and it is how a new script would most likely re-introduce the class.

## T-5 — Skip the live Codex / Grok / Devin TTY measurement (plan Phase 5)

**Finding (simplicity, P3):** FR8 asks for per-harness coverage, not measurement; record UNMEASURED
and save ≤ 6 model calls.

**Plan keeps the measurement:** the brainstorm asserted "every harness refuses"; a PTY-capable exec
tool would make that false, and that is the one fact the ADR's coverage table exists to state. The
cost is disclosed (`hr-autonomous-loop-skill-api-budget-disclosure`).

## T-6 — Drop the `webapp -> flagsmith` C4 edge; fixed text for the `--confirmed` rejection

**Finding (simplicity, P3).** **Plan keeps the edge** because the C4 completeness mandate makes an
added element carry its existing relationships (an element with only the new write edge would
misdescribe Flagsmith as write-only). **Plan accepts** a fixed rejection message if rebuilding the
argv proves fiddly; AC3 checks only "own terminal".

## T-7 — Derive `approval_method` from ack state instead of a helper literal

**Finding (architecture-strategist, P2):** have `soleur_op_ack_or_die` set a non-exported
`SOLEUR_OP_ACKED=tty-ack` on success; `audit_flag_flip_rpc` reads it and returns 4 when unset. The
WORM value then means "the ack returned in this process", and an audit append placed before the ack
fails immediately.

**Plan currently:** the helper sends a `tty-ack` literal (simplicity finding 1, mechanical, applied).
The alternative edits the class-2 ack body, which `operator-script.test.sh`'s `g4_class2_body_ok`
constrains; the work phase should check that constraint before adopting it. Operator choice.

## T-8 — Parse `--help`/`-h` before the early TTY precheck

**Finding (architecture-strategist, P3):** the plan does not require help handling to precede the
precheck; add a readonly `--help` row per script to the arm table. **Plan note:** additive test rows;
the work phase adds them if any script's parser reaches the precheck on `--help`.

## T-9 — Drop the `DESTRUCTIVE_RE` widening (plan 3.1) entirely

**Finding (architecture-strategist, P3, alternative):** key Guard 9's fallback on "caller of
`soleur_op_ack_or_die` with a `write` row" and skip the widening. **Plan keeps the widening** (with
fixture row M2, without the hand-kept count): it is the only check that sees a library consumer
writing with curl and never calling the ack, which Guard 2's population cannot contain.
