# Decision challenges — feat-one-shot-8308-go-gates-plugin-root

Surfaced at plan time in a headless pipeline run, so they are persisted here rather than asked.
`soleur:ship` renders these into the PR body and files an `action-required` issue.

Plan: [2026-09-19-fix-go-session-gates-plugin-root-resolution-plan.md](../../plans/2026-09-19-fix-go-session-gates-plugin-root-resolution-plan.md).
Issue #8308. Threshold `single-user incident`.

## Challenge 1 — Taste: keep or drop the success-path `RESOLVE` marker

**Reviewer position (`code-simplicity-reviewer`).** Emit `SOLEUR_PLUGIN_ROOT_RESOLVE` only on the
degraded branch. Three healthy lines print at the top of ~100% of sessions and carry no
information; the plan's own argument for not mirroring healthy lines hosted ("they carry no
information") does not stop at the hosted boundary. Failure is already reported by
`reason=plugin-root-unverified` vs `reason=absent-from-verified-root`; the only genuinely new
cell is *which arm* produced the root, which is one field on the existing skip line.

**Plan position (kept).** Three reasons, in order of weight:

1. **#8308 asks for it explicitly** — "make each gate emit a monitored `SOLEUR_*` marker with the
   resolution source so a future regression self-reports instead of degrading silently." A
   degraded-only marker cannot distinguish "the gate ran healthy" from "the gate's echo was
   deleted", which is the very substitution the issue is about.
2. **It is what makes AC12 and row H3 checkable.** The real-harness contact row asserts three
   `verified=true` lines; with a degraded-only marker there is nothing to assert on a healthy run,
   and the one row that touches the real loader would have no predicate.
3. **Cost is ~60 characters per gate**, printed next to `git worktree list` output that is orders
   of magnitude larger.

**What would change the decision.** Evidence that the three lines materially degrade the session
transcript, or a redesign of H3/AC12 that asserts health without a health marker.

## Challenge 2 — Taste: suite size (harness rows and the limitation row)

**Reviewer position (`code-simplicity-reviewer`).** Shrink Guard 1 to four rows (R8, R6, R7, H3)
and cut R2, R3, R4, R5, R6b, H1, H2 plus the `mk_workspace`/stub helpers — roughly −250 LOC of
harness. Cut mutation rows that mutate the harness rather than the artifact. R6b in particular
"documents; it cannot guard", and goes red precisely when someone *strengthens* the check.

**Plan position (kept).** The cuts would violate gates this repo already enforces:

- `plan` Phase 2.12 **requires** harness rows ("at least one edit to the SUITE that must drive it
  RED, plus at least one must-PASS input that is NOT the canonical") and **requires** a row where
  the guard's precondition holds and the property still fails. R6b is that row; H2 is that
  must-PASS input. Cutting them is not a simplification, it is a gate violation — and the learning
  the gate came from (`2026-08-13-every-guard-i-shipped-was-satisfiable-by-a-guard-that-asserts-nothing`)
  records four guards that scored green while asserting nothing for exactly this reason.
- R3 is the only row covering Step 0, the gate that runs `cleanup-merged` and the `.mcp.json`
  restore — i.e. the gate whose absence is the reported bug. R2 is the only row covering Step 0.5.
- R6b's "goes red when someone strengthens the check" is the intended signal, not a defect:
  ADR-179 A11 rejected the stronger assertion on three grounds, so strengthening it is a decision
  that must supersede A11 first, and a red row is how that decision gets made deliberately.

**What would change the decision.** A revision of Phase 2.12's contract, or evidence that the
suite's runtime is a real cost (it runs local fixtures only; expected well under 10s).

## Note on the accepted findings

Every P0 from all four review seats was applied, not surfaced — including three that falsified
claims the plan itself had made (`cleanup-merged` being "read-mostly"; a new `.test.sh` being free
of baseline churn; `ANCHOR_FIXTURES` being the home for a new positive control). Those are recorded
in the plan's Research Reconciliation table rather than here, because they were errors, not
disagreements.
