# Learning: a proof-of-red pinned to a moving ref consumes its own fix — and pinning it widens the silent-skip window

## Problem

`infra-config-apply.test.sh` carried a mutation proof: run the *pre-fix* handler from git and
assert it FAILS the two properties #7220 added (attribution `fatal_line`, real accounting
`files_total`). It read that handler from **`origin/main`**.

The guard was added by the very PR that fixed the handler (`c2de2581e`). So it was correct for
exactly one merge: at the instant that PR landed, `origin/main` began carrying the *fixed*
handler, both assertions inverted, and the suite went permanently red —

```
=== Results: 144 passed, 2 failed ===
  FAIL: pre-fix handler carried NO fatal_line (this is #7220)
  FAIL: pre-fix handler reported the hardcoded files_total=0
```

— on every infra PR. The guard did not detect a regression. **It consumed its own fix.**

The file's own header states the intent correctly ("a regression guard that passes against the
code it was written to catch is decoration"). Only the implementation was wrong.

## Solution

Pin the read to the immutable pre-fix commit (`701e76e6b…`, full 40-char SHA) instead of a branch
name. A pinned SHA asserts *a specific historical handler failed these properties* — true forever
— instead of *a live branch is still broken*, which stops being true the moment you fix it.

## Key Insight — the fix is where the interesting failures were

Pinning is correct, and the obvious version of it ships four defects. All four passed a green
suite; all four were found by review, not by the author's own verification.

### 1. Pinning WIDENS the silent-skip window, in the direction that reads as safe

This inverted my own assessment. I checked the two-arm skip/fail structure, saw it was unchanged
from the pre-fix code, and concluded "same shape as before, no regression." That is false:

- `origin/main` is a **remote-tracking ref for the checked-out branch** — it resolves at *any*
  `fetch-depth`, so the old `git show` essentially never skipped.
- A **specific historical commit** needs a clone deep enough to reach it, and it recedes
  monotonically into history.

So the read went from "works at depth 1" to "works only at sufficient depth", and every
degradation now lands on the *quiet* arm. Two agents reproduced it independently (a `--depth 1`
clone and a non-git directory), both getting `144 passed, 0 failed`, **exit 0**.

**Ask, of any ref-pinning change: which arm does a degradation land on now, versus before?**

### 2. The backstop existed and was calibrated to the pre-fix count

The suite already had the right mechanism — an assertion-count floor whose own comment says it
exists so silently-not-running arms "make that loud." It did not fire, for an arithmetic reason
worth internalising:

| | value |
|---|---|
| floor, measured in the 144-assertion era | 142 |
| slack it carried | **2** |
| assertions the guard contributes | **exactly 2** |
| skip result | `144 >= 142` → pass, exit 0 |

A floor left behind by a growing suite silently re-opens the hole it was built to close. **A
floor is not a fire-and-forget guard; it is a number that must be ratcheted in lockstep.** Set it
to the full current count (zero headroom) and treat a floor failure on a green-looking suite as
"you added assertions, update this number."

### 3. The presence probe must test the BLOB, not the commit

`git cat-file -e <sha>^{commit}` is the intuitive predicate and is wrong here. A **blobless
clone** (`--filter=blob:none`, a routine CI speed-up) has the commit object present while the
handler's blob is unfetchable — so a commit-probe sends a *legitimate* environment to the
hard-FAIL arm, the exact inversion the guard exists to prevent.

Probe `<sha>:<path>`: absent in exactly the environments that should SKIP, present in exactly
those that should FAIL. The predicate has to match the arms it selects between.

(Related, and why `rev-parse --verify` is also wrong: on git 2.53.0 it returns **0** for any
well-formed 40-hex string whose object is absent — success on *syntax alone*. That would make the
skip arm dead code.)

### 4. A guard that fires on any abort is not testing the defect's SHAPE

The arm sabotages `sha256sum` to force a mid-delivery death. Injecting `exit 99` immediately
after the EXIT trap installs — dying *before* the write loop, never invoking `sha256sum` — left
**both assertions passing at 146/0**, because the trap emits its hardcoded zeros for any
unhandled exit.

So the test proved *"the old abort frame is uninformative"*, never *"the old handler could not
attribute a **delivery** failure"* — which is the actual defect. The fix is a witness: have the
mock record its invocation and assert the record is non-empty. One assertion, and the mutant dies.

Sibling, same family: `_frame_field` returns the literal `MISSING` both when the FIELD is absent
and when the FRAME is absent, so the `fatal_line` assertion alone is **satisfied by the empty
universe** — replacing the handler run with a no-op left it green. Assert a field that must
EXIST (`reason == unhandled`) to pin that a frame was published at all.

## Method notes — three ways my own verification lied

- **A control built from a fabricated object tests the wrong arm.** My first non-vacuity control
  repointed the pin at a made-up SHA. That object does not exist, so it exercised the *skip* arm
  and returned `144 passed, 0 failed` — an inconclusive result that resembles a pass. A
  discrimination control must use a **real contrasting object** (the *fixed* handler,
  `c2de2581e`), which correctly returns `144/2`.
- **The sandbox has to preserve the SUT's assumptions.** Copying the suite to a `mktemp -d`
  broke `SCRIPT_DIR`, so mutants aborted in setup rather than on the assertion under test —
  producing "no output" that is easy to misread. Mutants must live where `SCRIPT_DIR` resolves
  (dot-prefixed in the real directory, excluded from globs and `git ls-files`).
- **A timeout can kill the call between the mutation and its restore.** The final verification
  hit the 2-minute ceiling immediately after the restore `cp` and before its check — the exact
  documented trap. Restore in a *separate* call from the run, echo the backup path, and verify
  the pin afterwards rather than assuming.

## Session Errors

- **Read a telemetry query's silence as a result.** A `--since 30h` Better Stack query silently
  returned only an 11-minute window. **Prevention:** state the window the query actually covered
  before drawing any conclusion from it; recorded as an explicit limit on #7270 rather than
  presented as a correlation.
- **Concluded "no regression" on the skip arm from structural similarity.** **Prevention:** the
  question is not "is the structure the same" but "does the same input still land on the same
  arm" — see Key Insight 1.
- **Missed a P1 because I did not know the backstop existed.** The floor was ~200 lines below my
  edit. **Prevention:** when changing a suite's assertion count, grep the suite for a floor /
  count / cardinality guard before assuming nothing consumes it.
- **A fabricated-SHA control returned an inconclusive result.** **Prevention:** see Method notes.
- **A `sed` mutation silently did not land** (delimiter `|` collided with `||` in the pattern).
  **Prevention:** already caught by the landing assertion (`diff -q` against a pristine backup) —
  the guard worked; keep it mandatory.
- **A background suite reported "still running" when it had been SIGKILLed**, and a registered
  run exited **0** with `88 passed, 0 failed (of 89)` — one suite killed and swallowed.
  **Prevention:** read the runner's epilogue, not its exit code; `rc=0` answers "did everything
  it ran pass", never "did it run everything."
- **`git status --short` hid untracked agent debris** until `--untracked-files=all`.
  **Prevention:** use the explicit flag when checking for debris before a commit.
- **Two hook denials cost work:** the IaC-routing hook fired on `systemctl daemon-reload`
  appearing as a *citation of the defect* in plan prose (resolved with the documented ack), and a
  `gh issue create` denial for a missing `--milestone` took its same-command heredoc down with
  it. **Prevention:** the second is already documented — write the body with the Write tool in a
  *separate* call before any hook-gated `gh` invocation.

## Prevention

The transferable rule, for any guard that proves itself against historical code:

> Pin the proof to an immutable object, then ask three questions the pin creates:
> **(a)** which arm does a degradation land on now, and is it the loud one where reachability is
> contractual (e.g. under `CI`)?
> **(b)** does the presence predicate probe the same object the read needs (blob, not commit)?
> **(c)** does anything mechanically assert the proof still RAN — and is that floor calibrated to
> the *current* assertion count?

## Tags

category: test-failures
module: apps/web-platform/infra
