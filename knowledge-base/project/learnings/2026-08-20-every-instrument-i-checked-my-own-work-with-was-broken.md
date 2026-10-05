---
title: "Every instrument I checked my own work with was broken"
date: 2026-08-20
category: workflow-issues
issues: [7629, 7572, 7574, 7613]
pr: 7653
tags: [mutation-testing, vacuous-guards, measurement, fail-open, red-green]
---

# Every instrument I checked my own work with was broken

## Problem

A four-issue PR closing fail-open gates — gates that report success while doing
nothing. The implementation was sound. **Twenty-two of my own measurements were
wrong before they were right, and an 8-agent panel found more defects in the
guards I wrote than in the code they guard.**

The dominant shape, stated once because every instance is the same:

> I asserted a property of my own verification instead of measuring it.

Not the code — the *verification*. A RED that proves nothing, a control that
cannot fail, a grep satisfied by its own prose, a mutation that never lands, a
sandbox whose baseline is already red.

## The instances, by mechanism

**A RED that reproduces nothing.** The #7574 probe loses matches to a SIGPIPE
race. My fixtures were three lines, which fit inside the 64 KiB pipe buffer, so
`printf` never took SIGPIPE: 6/7 green against a defect that was fully intact.
The fixture must be able to *contain* the condition before its verdict means
anything.

**A control that fails identically in both directions.** The `R3(2)` arm compares
a seed against the first *append*; my fixture parked the relocated seed below the
*trap*. It failed in RED and in GREEN — and identical failure in both directions
is the tell that a control is not measuring the fix.

**A guard satisfied by the prose explaining it.** The S1 marker guard used
`grep -qF` over a file that includes its own comments, so renaming the emit and
leaving a comment naming it passed while every run became a green skip. This is
the exact class the PR was closing, three arms away.

**A diff of two byte-identical files reported as different.** `sed` terminates
its last line; `"\n".join()` does not. Guard 5(a) called 170 identical lines a
mismatch, and I nearly rewrote a correct expression to chase it.

**A sandbox whose control was already red.** Verifying the failure ledger, I
copied the suite to a temp dir — where `REPO_ROOT` resolves from `BASH_SOURCE`
and the workflows vanish. Control red, every row void. Re-run in place against a
green control, the conclusion **inverted**.

**Tooling that lies in the reassuring direction.** `grep -c` prints `0` *and*
exits 1, so `|| echo 0` yields the two-line string `"0\n0"`. POSIX ERE has no
`(?!…)`. `$?` after a pipe reports the last stage, so `actionlint EXIT=0` was
`head`'s status. `$((streak + 1))` reads `09` as octal, and the arithmetic error
made the enclosing function *return* rather than exit — so a probe reported
`PASS` across **0 sampled runs** with `gh` entirely broken.

**Prose asserted rather than measured.** `_SKIP_CEILING = 5` "not 7" — measured
at 7. ADR-188 claimed one remaining vacuity bound; there are four. ADR-152 said
"the suite asserts that count"; nothing does. A rule table shipped `[[:space:]]`
for an expression consumed by Python `re`, where it is inert.

## Key insight

**A guard, a fixture, a control and a sandbox are all code, and none of them is
exercised by the thing they measure.** Production code is run by its callers.
Verification code is run by nobody — so its defects are silent by construction,
and they fail in the direction that looks like success.

Three questions, each of which caught multiple instances here:

1. **Can this fixture contain the condition?** Not "is it representative" —
   *can the phenomenon physically occur inside it?* (64 KiB buffer, `$` in a
   variable name, a violation the fixture never creates.)
2. **Is my control green?** A red baseline does not weaken a measurement, it
   *deletes* it. Run the unmutated control in the same harness, first.
3. **What would falsify this sentence, and did I run it?** Applied to every
   causal or universal claim the diff *adds* — the ones in comments and ADRs,
   not just the ones in assertions.

## What worked

**RED before GREEN, paid per arm.** The operator required the #7629 harness land
RED as its own commit and the #7613 budget be paid per arm rather than once for
the shared file. That structure is what surfaced most of the above: three
per-arm controls would have shipped as false green, and a single shared control
would have hidden all three.

**Report-only agents.** With eight concurrent agents, one reading another's
uncommitted edit reports it as drift — which is how a real finding gets
dismissed as noise. Panel reports, lead applies.

**Adversarial prompts that invite refutation.** The panel refuted several of my
worries (no crafted SKILL.md forces a LOW-RISK first line; a failed redirect
cannot forge a branch value). A refutation is worth as much as a finding, and
you only get them by asking for them.

## Session Errors

1. **First #7574 RED was vacuous** — 3-line fixtures fit inside the 64 KiB pipe
   buffer. **Prevention:** for any race, state the threshold and size the fixture past it.
2. **`${arr[@]@Q}` into a Python list** — adjacent string literals concatenate.
   **Prevention:** pass lists through the environment, never string interpolation.
3. **`grep -qx` against a file where the marker sits inside `echo "…"`.**
   **Prevention:** anchor on the emit form, not the bare token.
4. **`(?!…)` in POSIX ERE, plus `grep -c` printing 0 while exiting 1.**
   **Prevention:** compare two counts; never guard `grep -c` with `|| echo 0`.
5. **`diff` of byte-identical corpora reported a mismatch** (trailing newline).
   **Prevention:** normalise line termination before comparing generated text.
6. **A control that failed identically in RED and GREEN.**
   **Prevention:** treat same-verdict-both-directions as a broken control, not a finding.
7. **Fixture used `_luks_detail` where the arm derives `$_luks_detail`.**
   **Prevention:** derive the fixture's identifier from the SUT, not from memory.
8. **`actionlint EXIT=0` read from `$?` after a pipe.**
   **Prevention:** capture rc before piping; the repo's own rule says so.
9. **Counted my own error-message prose as call sites.**
   **Prevention:** anchor invocation greps on the call form.
10. **Triaged two `cd "$WT_ACTOR"` findings as "&&-guarded"; they have no `&&`**
    and are followed by a command that deletes worktrees. **Prevention:** read the
    line, do not infer the shape from the shellcheck code.
11. **Roster held `STAGE=` names where the analyzer emits window names** — the
    wiring would have rejected every run. **Prevention:** measure the producer's
    output before writing the expected set.
12. **Read `_SKIP_CALL_SITES` before assigning it** — `set -u` aborted the suite.
    **Prevention:** run the suite after every edit; syntax-checking is not running.
13. **Fabricated an `actions/checkout` SHA, then wrote an `actions/cache` SHA from
    memory** and verified after. **Prevention:** resolve pins via the API before writing.
14. **Ledger verification ran against a red control in a subtree sandbox.**
    **Prevention:** assert the control is green in the sandbox before reading any row.
15. **`_SKIP_CEILING = 5` "not 7"** — measured at 7; both arms share one allowlist.
    **Prevention:** measure a reachability claim; do not reason it.
16. **ADR-188 invented a second vacuity bound and declared it removed** — four
    remain. **Prevention:** enumerate the set before claiming its cardinality.
17. **ADR-152 claimed an assertion that does not exist.**
    **Prevention:** grep for the assertion before citing it.
18. **A rule table shipped POSIX classes for a Python regex** (inert).
    **Prevention:** state the dialect wherever an expression is meant to be ported.
19. **Attributed three destructions to a `+` prefix; only one is.**
    **Prevention:** vary one operand at a time before writing a causal claim.
20. **A comment claimed the old postmerge fallback fired on force-push shapes** —
    it fires only on root commits. **Prevention:** run the failing case.
21. **Octal fail-open in `_transient`** — `PASS` over 0 samples with `gh` broken.
    **Prevention:** `10#$n` for any counter read from a file, and validate its shape.
22. **A repo-scoped `commit.gpgsign=false` silently unsigned the first commit**
    while the global said `true`. **Prevention:** verify the raw object, not `%G?`.
