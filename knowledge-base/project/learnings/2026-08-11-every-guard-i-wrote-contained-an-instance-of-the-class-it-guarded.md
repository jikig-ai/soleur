# Every guard I wrote contained an instance of the class it guarded

**Date:** 2026-08-11
**Issue:** #7376
**Category:** best-practices

## Problem

`run-registered-suites.sh` runs 93 infra suites in parallel and discarded every suite's output
(`bash "{}" >/dev/null 2>&1`), so a CI failure carried no diagnostic at all — characterising the
flake took eight executions, and the issue the health monitor filed for it (#7374) is 21 `PASS`
lines and a count, naming no suite.

The fix was an instrument: capture per-suite stdout+stderr, print a marker-anchored excerpt on
RED. It shipped with a mutation matrix, a corpus-conformance test, an anti-vacuity floor, and
~110 lines of rationale prose. Eight review agents then found ~40 defects, and the striking thing
is not the count — it is that **almost every guard I wrote contained an instance of the class it
was written to guard.**

## The pattern

| Guard | The class it guards | The instance inside it |
|---|---|---|
| Sentinel prefix, whose comment cites AP-021 ("never name a cause the job did not measure") | CI messages naming unmeasured causes | The accounting verdict was prefixed too, so it was filtered from the issue body — and the monitor then titled the issue *"usually a timeout"*, a cause it never measured |
| PEM rule rewritten because header-only redaction is "an ANTI-mitigation" | A redaction that makes a leak less recognisable | The `sed` range I replaced it with consumes to EOF on an unterminated BEGIN, deleting the summary line, the run URL and every suite name — a strictly worse outcome, with a live trigger already in the corpus |
| Test (14a) certifying the widened redaction set | Secrets surviving redaction | Its Doppler fixture used `dp.scim.`, which matches. The real service-token shape `dp.st.<config>.` does not — the fixture dodged the exact gap it existed to find |
| 7-row mutation matrix proving the assertions discriminate | Assertions that cannot fail | Two rows scored "killed" against an **unmutated** runner, because `ok()` prints the assertion id and the scorer substring-matched the *passing* line |
| Fixture for "anchored selection, not a blind tail" | Selection by position | The marker sat on log line 1, so `head -n 5` and marker-anchored selection are indistinguishable — a head-selection mutant survived the whole suite |
| T2e, an "independent" oracle for registration drift | An oracle that agrees with the SUT by construction | Mine was anchored on `run: bash`, sharing the SUT's blind spot for the `sudo bash` registration — so it could not see the 8th underived suite while its comment promised "reds if an 8th appears" |

## Key insight

**A guard written by the same author, in the same session, against the same mental model,
inherits that model's blind spot — and it fails in the reassuring direction.**

That is why a self-run mutation battery reporting all-green is evidence about *the mutations its
author imagined*, not about the tests. Every one of the defects above was invisible to a careful
re-read of the diff, and every one was found by driving the thing rather than reading it: running
the mutant, running the fixture, running the `sed` against a realistic capture.

The corollary for review prompts: instruct the agent to **find the vacuity the battery missed —
not to re-run its mutations.** The most productive question was "name an implementation a
reasonable engineer might write next that satisfies this assertion while violating the property."

### The reliable tells

- The guard's own comment states an invariant. (Mine claimed "every line the parent emits after
  xargs is prefixed" — false by design, in three places, one of which a test asserts.)
- The fixture instantiates one member of the set the assertion quantifies over. `1-of-1` is
  indistinguishable from `all-of-1`.
- The oracle and the thing it checks are derived from the same expression.
- The assertion's bound is a hand-picked constant unrelated to the constant it is bounding
  (`<= 60` against `DUMP_CAP=40`).

## Session Errors

**Inherited three measurements from the plan into code comments without re-deriving** — "10
suites print `[FAIL]` at column 0" (11), "85/93" (unreproducible under either stated cause), "101
stderr emit sites" (~107, and predicate-dependent).
*Recovery:* re-derived; published the command beside each figure or dropped the digit.
*Prevention:* the repo already re-derives inherited NUMBERS at /work start. The gap is that a
number pasted into a **code comment** is not treated as a claim the way a number in a plan is.
Any figure written into a comment needs the command that produces it written next to it.

**Edited the runner while a measurement run held it in flight.** run03 came back 81/12 with all
12 showing `rc=?`; the log dir had been deleted mid-run. Those REDs were mine, not the flake's.
*Recovery:* discarded run03 as evidence, killed the loop.
*Prevention:* the rule exists ("confirm clean, then do not edit under it") and I broke it anyway,
because the edits felt unrelated to the running suite. They were not: the suite under measurement
is itself registered and invokes the script being edited. **If an edit cannot wait, kill the run.**

**`pkill -f 'soleur-7376'` matched its own command line** and killed the invoking shell (exit 144).
*Recovery:* re-killed by resolving `/proc/<pid>/cwd` ownership instead.
*Prevention:* documented repo-wide already; this is a one-off recurrence.

**Read `comm` output that had printed `file 1 is not in sorted order`.** Believed a wrong
underived-suite count for several turns.
*Prevention:* `comm` announces its own invalidity on stderr and still prints a plausible-looking
result. Always `LC_ALL=C sort` both operands; treat that warning as a hard stop.

**Proposed filing a duplicate issue.** #7076 was already open and tracked the same remediation
with a better analysis than mine (8 suites, not 7).
*Recovery:* the CONCUR gate rejected it; commented on #7076 instead.
*Prevention:* search for an existing tracker BEFORE invoking the CONCUR gate, not after — the
gate should be adjudicating the deferral, not discovering the duplicate.

**Ran eight review agents concurrently with a pinned measurement loop**, contaminating it.
*Prevention:* measurement runs and agent panels contend for the same machine; sequence them.

**Two one-offs:** a `shellcheck disable` directive placed where it did not apply (twice — above
prose, then above a three-command line, where it covers only the first); and `MIN_ASSERTIONS` set
from an expectation rather than from a green run.

## Prevention

- When a PR **builds a verifier**, review the verifier the way it reviews its target. Its
  vacuities fail OPEN — a bug there certifies broken-as-fine rather than erroring.
- Score a mutation on the **failure** line, never a bare assertion id — dispatchers print the id
  on success too. Add a **noop-control** row expected to SURVIVE; without it, "all rows killed"
  cannot be distinguished from "the scorer matches anything".
- Put a fixture's marker in the **middle**, not at either end, whenever the property under test
  is *how* the excerpt was selected.
- Derive one guard's literal from the other side (`grep -qF "$SENTINEL_PREFIX" "$SUT"`), so a
  producer-side rename reds the consumer's test.
- Ask of every number in a comment: *what command produced this, and is it next to it?*

## Tags

category: best-practices
module: infra/test-harness
