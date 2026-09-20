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

## Review-round declines (2026-09-20, 11-seat panel)

Findings the panel raised that were NOT applied, with the reason. Recorded because a declined
finding with no record reads later as one nobody noticed.

### DECLINED — admit `not-local:sentinel-absent` to Step 0's proceed set

**Raised by:** user-impact (Finding 8) and, in passing, code-quality. Both correct about the
symptom: a local box with a stray `DEVIN_DIR` exported reports that verdict, so the preamble is
skipped and the operator is told `reason=cloud-session` on their own laptop. Measured, and it is
this repo's own operator profile.

**Why declined.** `cloud-detect.sh`'s header is explicit: *"not-local:<reason> — everything else;
consumers MUST fail closed on it"*, with exactly one documented carve-out (*"Callers treat
no-devin-env like `local`"*). `sentinel-absent` means "a Devin-MARKED box with no sentinel" —
the fail-closed case by construction. Admitting it would let a real Devin cloud session reach
`cleanup-merged`, which is the destructive direction, to fix a cosmetic misattribution.

**What was done instead.** The predicate is unchanged and now carries the classifier's contract
as a comment. The skip reports `reason=cloud-session verdict=<v>`, and a fifth state-keyed
sentence tells the operator which variable causes it and to unset it. The symptom is addressed
in the reason; the safety property is untouched.

### DECLINED — collapse the four state-keyed sentences to two

**Raised by:** code-simplicity (mechanism 5), on the grounds that `grok-env verified=false` and
`verified=false with any other source` resolve to the same operator action.

**Why declined.** They do not: one says "your `GROK_PLUGIN_ROOT` points somewhere else, check it"
and the other says "reinstall the plugin". AC7 mandates four, and the split exists because CPO
note B objected to a blanket "file a defect" misattributing a customer's configuration to Soleur.
The panel then ADDED a fifth (above), which is the opposite of the pressure to collapse.

### DECLINED for this PR — version-sort the Devin cache arm

**Raised by:** security (F3) and user-impact (Finding 6). Real: `find … | head -1` is readdir
order, and a plugin cache holds several versions by design.

**Why declined here.** The arm is confined to Step 0.5, whose only dispatch is a classifier, so
the worst outcome is a wrong session class and no mutation — bounded, and the seats agreed it is
not blocking. Version-sorting it correctly is coupled to the #8401 migration, which is where the
requirement is now recorded (with the measurement that makes it load-bearing). Doing it here
would put the harder half of #8401's design into a PR that deliberately does not take it.
