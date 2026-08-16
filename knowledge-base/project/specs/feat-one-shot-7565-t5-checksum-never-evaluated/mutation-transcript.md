# Mutation transcript — #7565

Every row ran against a full scratch copy of `apps/web-platform/infra`; the committed tree was
never mutated. Sequential by construction — concurrent docker rows contend for the same
machine-global `/tmp` tmpfs and corrupt each other's verdicts. Each mutation was asserted to
have **landed** (`diff -q` against the pristine source) before its row ran; a mutation that does
not land reports the baseline, which is indistinguishable from a pass.

**Control first.** A red baseline voids every row below it.

| Row | Mutation / input | rc | Terminal line | Verdict |
|---|---|---|---|---|
| **control** | none (scratch copy, CDN reachable) | 0 | `47 passed, 0 failed (47 assertions)` | **GREEN** — baseline valid |

## Guard 1 — the checksum, and only the checksum, aborted the chain

| Row | Mutation / input | rc | Terminal line | Verdict |
|---|---|---|---|---|
| G1-1 | DELETE the checksum-verdict assertion (guard's own dispatch); CDN reachable | 1 | `FAIL: ran only 46 assertions (<47)` | **RED** ✅ via the floor — a removed assertion is not indistinguishable from an arm that ran |
| G1-2 | *as the plan specified it* — drop `$` anchor; CDN blocked | 1 | `45 passed, 2 failed` | **FALSIFIED** — see below |
| G1-2a | drop `$` anchor **+ curl non-fatal** + CDN blocked | 1 | `46 passed, 1 failed` | checksum assertion **PASSED** — the false green ✅ |
| G1-2b | `$` anchor present, **identical input** to G1-2a | 1 | `45 passed, 2 failed` | checksum assertion **FAILED** ✅ — the anchor is load-bearing |
| G1-3 | both fixes intact; CDN blocked, apt healthy | 1 | `45 passed, 2 failed` | **RED** ✅ — `sha256sum never rejected the tarball`. On `origin/main` this identical input is **green with zero findings**: the false pass this PR closes |
| G1-4 | genuine checksum so the chain completes; CDN reachable | 1 | `42 passed, 5 failed` | **RED** ✅ — `CHMOD_RAN` appears, absence assertion fires |
| G1-5 | a **second** `chmod` added to the shipped block | 1 | `FAIL: CHMOD_RAN instrumentation did not land` | **RED** ✅ — `s.count(old) != 1` refuses to instrument one and ignore the other |

### G1-2 was falsified as written, and replaced rather than skipped

The plan predicted GREEN, reasoning that `FAILED open or read` would satisfy an unanchored
`: FAILED`. Executed verbatim it came back **RED**, because `grep -c 'FAILED open or read'`
over the whole run returns **0**: with `set -e` armed, a blocked CDN aborts at `curl` **before
`sha256sum` runs at all**, so there is no verdict line for an unanchored pattern to over-match.
The plan transplanted its probe cell (d) — labelled *"CDN blocked + no `set -e` (mutant)"* —
onto the errexit-armed primary arm.

Reaching the cell requires `sha256sum` to actually run against a missing tarball, so G1-2a/b
append `|| true` to the curl line. On that identical input the pair separates cleanly:

```
g1-2b (anchor present):
  FAIL: T5: sha256sum never rejected the tarball — the abort was not the checksum
        /tmp/doppler.tar.gz: FAILED open or read      <-- the over-match string IS present

g1-2a (anchor dropped):
  (no such FAIL line — the checksum assertion PASSED)
  FAIL: T5 MUTATION: ...                              <-- only the mutation arm fails
```

**Residual, stated plainly.** The `|| true` is a harness contrivance. No arm in the committed
suite relaxes errexit on the curl line, so the over-match cell is not reachable as the suite
ships today. The `$` anchor is defence-in-depth against a future edit, not a guard on a live
path — a weaker claim than the plan made, and the true one.

## Guard 2 — `CHMOD_RAN` is emitted only when chmod actually ran

| Row | Mutation / input | rc | Terminal line | Verdict |
|---|---|---|---|---|
| G2-1 | revert transform to `;` (anchored check intact) | 1 | `FAIL: CHMOD_RAN instrumentation did not land` | **RED** ✅ — the anchored check is the detector; behaviourally `;` and `&&` are indistinguishable with the CDN reachable |
| G2-2a | **bare** post-transform grep + `;` transform (`main`'s pair) | 1 | `FAIL: the mounted T5 mutation artifact lost the CHMOD_RAN instrumentation` | **RED** ✅ — the bare grep *was* defeated as predicted; the **mounted-artifact** check caught it independently |
| G2-2b | bare post-transform grep + marker not emitted at all | 1 | `FAIL: CHMOD_RAN instrumentation did not land` | **RED** ✅ |
| G2-3 | rename the marker in the transform only | 1 | `FAIL: CHMOD_RAN instrumentation did not land` | **RED** ✅ (see note) |
| G2-4 | delete the mounted-artifact check **and** strip the marker from `dl.case.sh` after `sed -i` | 1 | `46 passed, 1 failed` | **RED** ✅ — the mutation arm fails; the check pins *application*, not presence in the source copy |
| G2-5 | both fixes intact; CDN blocked (same run as G1-3) | 1 | `45 passed, 2 failed` | **RED** ✅ — `CHMOD_RAN` absent |

**G2-3 note.** The plan predicted "RED twice, independently". Only the **source-level** check
fires, because it `exit 1`s immediately and the mutation arm is never reached. The
mounted-artifact check's independence is demonstrated by **G2-2a** instead, where the
source-level check was deliberately defeated and the mounted check was the sole detector.

## Harness rows (mutations of the SUITE, not the system under test)

| Row | Mutation / input | rc | Terminal line | Verdict |
|---|---|---|---|---|
| H1 | *first attempt* — malformed edit | 2 | `syntax error: unexpected end of file` | **VOID** — see below |
| H1-redo | neuter `pass()`/`fail()` to no-ops | 1 | `FAIL: ran only 0 assertions (<47)` | **RED** ✅ — the floor is the detector |
| H2 | leave the floor at 46 with the new assertion present | 0 | `47 passed, 0 failed` | **GREEN, and that is the finding** — a floor only ever guards work that predates it |
| H3 | **must-PASS**: apt install fails once, succeeds on retry | 0 | `47 passed, 0 failed` | **GREEN** ✅ — slow but correct must pass |
| H4 | **must-PASS**: shipped block reordered, `rm` before `chmod` | 0 | `47 passed, 0 failed` | **GREEN** ✅ — the contract is that the checksum aborts before tar/chmod, not a fixed tail order |

**H1's first run was not counted.** It exited non-zero (`rc=2`), and reading "the row must go
RED" carelessly would have accepted it. But a bash syntax error is not the floor firing — the
run never reached `total=$((passes + fails))`, so it measured nothing about the dispatch layer
it targets. Redone as a clean two-line substitution.

## Addendum — 2026-08-16, review round (#7565)

An 8-agent panel found the axes this battery did not mutate. Recorded here rather than in place,
because the rows above are the evidence for what was measured at the time.

**The battery's blind spots, as measured by the panel:**

| Axis the battery did not edit | What survived it |
|---|---|
| **dispatch — `fail()` alone** | H1-redo neutered `pass()` *and* `fail()` together, so its RED is fully explained by the `pass()` half. Neutering only `fail()` — or, worse, swapping its bucket (`fail() { passes=$((passes+1)); … }`) — leaves `total` at its floor, prints accurate `FAIL:` text, and **exits 0**. Reproduced in isolation with three real regressions injected: `47 passed, 0 failed`, `EXIT=0`. One token disarms ~129 assertion sites. |
| **fixture direction, mutation arm** | The arm's wrong-digest `sed -i` had no landing assertion. A no-op sed means the genuine checksum passes, the chain completes legitimately, `CHMOD_RAN` prints, and the arm reports a cheerful pass having reproduced nothing. Fail-open. |
| **population growth** | G1-5 grew the set with a *duplicate* member, which the exact-literal `s.count(old) != 1` catches by construction. A **new** member — a second pinned binary in the same runcmd block — yields 5/5 green with its checksum never evaluated. |
| **which arm was pinned** | The mounted-artifact check went to the arm whose assertion is POSITIVE (self-failing). The PRIMARY arm's `CHMOD_RAN` assertion is NEGATIVE, so a marker lost in transit makes it pass **vacuously** — the tautology class #7565 exists to kill — and it was the unpinned one. |
| **observation-grep anchoring** | Both `CHMOD_RAN` observation greps were bare-token while the two *source* checks were anchored. bash echoes the offending source line on a syntax error, and that line contains the marker. |

**Fixes applied, and the floor consequence.** The verdict now reads an append-only `FAILURES`
ledger instead of a counter; the primary arm's mounted artifact is pinned; the mutation arm
asserts its own premise (the rejection verdict must be PRESENT) — a counted assertion, so the
floor moves **47 → 48**; both observation greps became whole-line; the tarball path is derived
from the extracted block rather than hard-coded.

**Three prose defects the panel found, all mine, all in the added comments:** the anchor
rationale asserted a prose-collision threat model that is false (the grep target is the extracted
block, and #7264 made the rendered template comment-free — measured: zero comment lines); the
`docker run --rm` correction replaced a wrong number with another wrong number via a
self-polluting recipe (it is 6 source sites / 8 runtime invocations, and the unanchored grep it
prescribed returned 9 *because the comment counted itself*); and the floor's leading itemisation
is the frozen 19-era baseline, which I updated, breaking the `= 14 new, 19 pre-existing, 33 total`
ledger 40 lines below for anyone doing what that stanza invites.

**Still open, deliberately.** The floor is a bare count with no per-arm identity, and `pass; pass`
at the dash-absent branch means `total == 48` is satisfiable with two fewer real assertions. A
per-arm ledger is the real fix and is a larger change to a file two open PRs are editing; recorded
rather than filed, since it needs the #7291 rebase to settle first.

## Axes mutated, and axes not

Mutated: **guard dispatch** (G1-1, G2-2a/b, H1-redo), **fixture direction** (G1-2a vs G1-2b —
the far side of the transform), **population growth** (G1-5 adds a member to the guarded set),
**region/anchor boundaries** (G2-1, G2-3), **application vs presence** (G2-4), **the floor
itself** (H2), and **must-PASS non-canonical inputs** (H3, H4).

**Not mutated, stated plainly:** the extraction layer (`assert len(blocks) == 1` selecting the
runcmd block) was not perturbed beyond the second-`chmod` case; the capture-server fixture and
the `docker run` mount set were left alone; and no row perturbs `run_case`, which this PR pins
unmodified by AC6.

No mutation row is left applied to the committed file — every row ran in `/var/tmp/t5-7565/mut/<row>/`.
