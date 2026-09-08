# Mutation verdicts — #7466 check10 ANSI summary parser

Every row ran against a COPY of the committed file in `$TMPDIR`; the tracked file was
touched only by M13 (a cross-file guard) and restored from git afterwards. The harness
asserts, per row, that the edit LANDED (`diff` against the pristine copy is non-empty)
and that the mutant still parses (`bash -n`).

**The control ran first and was green** — `25 passed, 0 failed (25 checks)`, exit 0,
empty stderr. A battery whose control is red or empty is void, not passing.

**The harness was wrong once, and its own landing check caught it.** The first battery
built each mutation through a nested shell heredoc; the quoting mangled the Python and
M1 produced a `strip_ansi` that emitted nothing, scoring S1 RED — the exact half of M1
that is supposed to stay GREEN. It was rebuilt with one quoted script per row.

## Guard 1 — the parse is colour-blind

| row | mutation | verdict |
|---|---|---|
| M1 | `strip_ansi` -> `cat` | S2a, S2b, S3 **RED**; **S1 and S4 GREEN**. The green half is the differential proof: the REDs came from colour, not from a broken harness |
| M2 | `n_skip`'s second stage re-anchored (one counter reverted, four left fixed) | S1 **RED** (also S2b, S3 — every fixture carrying a `skip` line). A check stopping at `pass` could not see this |
| M3 | `n_expect`'s second stage re-anchored to `^[0-9]+` | S1 and S2a **RED** — the false-RED trap caught at author time rather than in CI |
| M4 | strip class narrowed to `[0-9;?]*[A-Za-z]` | S3 **RED** only: colon-SGR, DECSC and charset escapes all survive a narrow class |
| M5 | `n_expect`'s first-stage anchor dropped | S4 **RED** only: the decoy's mid-log `999 expect() calls` is read as the summary |
| M6 | `strip_ansi` moved inside the per-counter reads (input read five times) | S1, S2a, S2b, S3 **RED** — a process substitution is a pipe, so every field after the first drains empty |
| M7 | the five parser fixtures deleted | `[FATAL] anti-vacuity floor: only 20 check(s) dispatched, floor is 25`, exit 1 |
| M13 | blank line inserted between `MIN_CHECKS=` and its `if` (tracked file, restored after) | `scripts/guard-vacuity-floor.test.sh` **RED**, `22 passed, 1 failed`, naming `plugins/soleur/test/preflight-check10-suite-integrity.test.sh`. Restored: guard back to 23/0 |

## Guard 2 — an unmeasured count is not a zero

| row | mutation | verdict |
|---|---|---|
| M8 | predicate ignores `fail` (the #7466 fail-open) | V2 **RED**; V1, V3, V4 green |
| M9 | predicate drops `pass`, keeps `fail` | V3 **RED**; V1 and V2 green. The asymmetry NAMES which member was dropped — V1 is `- -` and stays false under either single-member edit, so it cannot distinguish them |
| M10 | `-`→0 normalisation deleted | N1 **RED** (`pass=132 fail=0 skip=- todo=- expect=539`) and stderr carries **2** `arithmetic syntax error` lines. Without both signals this mutation is invisible: the arm prints `[ok]` and a SUT floor silently stops firing |
| M11 | a `: "${n_fail:=0}"` default restored ahead of the branch | **SURVIVED — and it is EQUIVALENT, not a fixture gap.** Under M1 the measured line still reads `fail=-`: the sentinel is never the empty string, so a parameter-expansion default can no longer manufacture a zero. That is the design property, demonstrated rather than asserted |
| M11b | the same default in the form that CAN fire (`[[ "$n_fail" == "-" ]] && n_fail=0`) | measured line reads `pass=- fail=0` instead of `fail=-` -> **AC17 RED**. It also trips AC13a, so two independent assertions catch it |
| M12 | the four predicate self-checks deleted | `[FATAL] anti-vacuity floor: only 21 check(s) dispatched, floor is 25`, exit 1 |
| M14 | the pass-floor's own `if ! [[ … =~ ^[0-9]+$ ]]` arm deleted, on a copy carrying M1, under `FORCE_COLOR=1` | **still exit 1** — but through the anti-vacuity floor (`only 24 checks`), not the floor that should have caught it, and it prints **2 false `[ok]` floor rows** on the way (`[ok] test count -`). That is precisely the fail-OPEN the arm exists to remove: `[[ "-" -lt 131 ]]` errors and returns false, so control falls through to a green verdict on a count nobody read |

## Harness rows

| row | edit to the SUITE | verdict |
|---|---|---|
| H1 | S2a's expected tuple changed to the broken output | S2a **RED** against the fixed code — the expectation is load-bearing, not fitted to whatever the code emits |
| H2 | `assert_parse`'s comparator stubbed to always `pass` | N2 **RED**. Conservation alone cannot see this: a stub still records one verdict per counted check |
| H3 | must-PASS: S1's `122 3 1 2 514` is not the all-green canonical shape, S2b's is all-skip | both GREEN on the control |
| H4 | V4's expectation flipped true -> false | V4 **RED** |
| H5 | must-PASS: V4 is the true case, not the canonical false | GREEN on the control — the predicate is not stuck returning one answer |

## One plan expectation that did not reproduce, and why

The plan predicted that M8 applied end to end together with M1 would print
`[ok] bun's summary reports no failing tests` — the #7466 regression reproduced. It does
not: the run exits 1 with the arm failing closed. M8 alone cannot reproduce it because
the shipped design gates all three reporting arms behind the verdict, so a weakened
predicate is blocked a second time by the structure. Reproducing it end to end would
require reverting the arm placement and the deleted defaults too — i.e. reverting the
fix. The end-to-end evidence is therefore the **pre-fix baseline** measured in Phase 0,
where the real file printed exactly that `[ok]` line directly beneath
`[FAIL] could not parse bun's summary block`.

## Axes this battery did NOT edit

Stated plainly, because a battery's value is the number of distinct things it perturbs:
no row edits bun itself (a real summary-format change is caught by the predicate, not by
the fixtures — that is what `summary_measured` going false is for), none edits `pass()`
or `fail()` (already covered by `scripts/guard-vacuity-floor.test.sh`, run green here),
and none edits the manifest or suppression sections, which this change does not touch.
