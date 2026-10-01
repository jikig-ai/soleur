---
title: "The tool built to stop a misdiagnosis committed it one layer above where its author applied the principle"
date: 2026-09-17
category: runtime-errors
module: scripts/inngest-host-state.sh
tags: [observability, could-not-measure, instrument-failure, fail-safe, verdict-machinery, mutation-testing, fixture-shape, sentinel-vocabulary, review]
issue: 7228
pr: 8252
---

# Learning: harden the channel, not just the row it delivers

## Problem

`scripts/inngest-host-state.sh` was written because a 2026-09-17 incident was misdiagnosed:
a `/hooks/deploy-status` payload describing web-1 was nearly acted on as a statement about
the dedicated inngest host. Its header argues the principle at length and correctly — an
unparseable row "is not evidence of ill health any more than of good", "SILENCE IS NOT
HEALTH", "age is not decoration".

The author applied that reasoning to the **row filter** and not to the **channel that
delivers rows**. Measured directly during review, five distinct instrument faults each
printed the same sentence and exited 4:

| Injected fault | What the operator read | rc |
|---|---|---|
| query exits 1 (HTTP 503) | "the host is not shipping to Better Stack (vector down, host down, or never booted). That is a finding, not a clean read." | 4 |
| query binary absent | *identical* | 4 |
| query returns an HTML error body with exit 0 | *identical* | 4 |
| python3 raises | *identical* | 4 |
| python3 absent | *identical* | 4 |

The enabling code was one line: `probe_rows="$("$QUERY" … 2>/dev/null)" || true`. `|| true`
discarded the exit code; `2>/dev/null` discarded the reason. Every downstream branch then saw
"no rows", which the script asserts is a finding about a production host — naming three
specific host-side causes, none of which was measured.

This is the tool an operator reaches for **mid-outage**, and the wrong answer points at a
host replace, which per #7228 deterministically strands the scheduler.

## Solution

Split "the read failed" from "the read succeeded and the answer is bad" into distinct exit
codes, and reserve the host verdict for the second:

- `4` — the query **ran**, returned rc=0, and the window held no dedicated-host row. The
  original finding, preserved and separately pinned (T20b exists so over-fixing cannot
  silently destroy the signal the script carries).
- `6` — **the read failed; nothing was measured.** rc and stderr captured on both queries.
  Also reached when the query exits 0 but returns non-row bytes (`nonempty > 0 && parsed == 0`),
  which is how a proxy or CDN error page arrives.

Three siblings in the same repo already had this vocabulary and none was used:
`inngest-dedicated-host-classify.sh` grades an unreadable query `probe-unavailable` ("a
missing signal must not read as a working one"); `cutover-inngest.sh`'s G3 says "this is NOT
a statement about the host"; `inngest-host-not-serving-7674.sh` emits
`TRANSIENT: reason=query_failed`.

## Key Insight

**A file's own header is not coverage. Ask which LAYER the principle was applied at, and
check the one above it.** The reasoning here was correct, quoted, and dated — and it was
applied to the row, while the channel delivering rows kept `|| true`. The author was not
careless; they were finished thinking about the layer they were editing.

The generalisable probe: for any component that renders a verdict, enumerate every way it
can fail to *measure* — binary absent, non-zero exit, valid exit with an invalid payload,
interpreter fault, interpreter absent — and ask what each one prints. If any of them
produces the same output as a real finding, the verdict is a guess wearing a measurement's
clothes. **And check the siblings first**: a repo that has already solved this usually has
the vocabulary sitting one directory over, which makes the fix a reuse rather than a design.

### Four corollaries, each measured on this PR

**1. A counter reconciliation is not a verdict backstop.** Both suites gated on
`passes + fails == CASES_RUN` and `[[ "$fails" -eq 0 ]]`. That sum is *invariant* under the
one substitution it must catch: redirect `fail()`'s increment into `passes` and you get
`10 passed / 0 failed`, exit 0, while `FAIL:` lines print to stderr. Fixed with an
append-only ledger (`FAILED+=("$1")`) — an entry can only be added, so silencing it means
deleting evidence rather than moving a number — plus an instrument self-test driving *both*
helpers, reported by `printf` + `exit` directly rather than through the helper it backstops.

**2. A mutation arm run against a green suite proves nothing about a gate that only fires on
failure.** My own battery scored "delete the ledger gate → SURVIVED", because with zero
failures that gate is a no-op *by construction*. The valid arm is the composite: break the
SUT so a case genuinely fails, **then** delete the gate. Measured: `A)` real break, gates
intact → rc=1. `B)` real break + gate deleted → rc=0 (so the gate is load-bearing).
`C)` real break + `fail()` redirected → rc=1 (so the ledger catches the substitution).
`B` and `C` are the result; `A` is the control that makes them mean anything.

**3. Fixture shape decides what a suite can see, and no mutation of the implementation can
reach it.** Three shapes, each measured surviving at full green:
- *Doubly-disqualified negatives* — every web-1 fixture failed **both** pin conjuncts at
  once (`host=soleur-web-platform` AND `host_role=web`), so neither was ever the sole reason
  a row was excluded. Swapping the host pin to `host_name` — verbatim the wrong-machine read
  the file exists to prevent — survived 10/10.
- *Cardinality one* — no fixture set had two rows passing the pin, so `rows[-1] → rows[0]`
  ("newest" becomes "oldest") survived.
- *A token that contains its own negation* — `grep -q 'SERVING'` matches `NOT SERVING`, so
  the healthy case and the crash-loop case were both satisfied by a SUT that never reports
  healthy, and `serving = False` survived. The remedy is an unambiguous machine token
  (`SERVING=yes|no`), not a cleverer grep.

**4. When a repo has a meta-guard that classifies your guard by its OUTPUT, the output string
is part of the interface.** Both new suites' floors printed a bare `FATAL:`, which is not in
`guard-vacuity-floor.test.sh`'s sentinel vocabulary (`\[FATAL\]|\[?FAIL(ED)?\]?:|…` — `FAIL`
is not `FATA`). The floors were *correct*; only the spelling of their diagnostic was wrong,
so the meta-guard scored both mutants `CONSTRUCTION` instead of `FIRES` and the repo-wide
ratchet grew 15 → 17, turning CI red. After the fix: 15 ≤ 15, and the firing-floor
population rose 121 → 123.

### Widening a matcher requires proving the original defect still fails

The `registry-d10` W8 gate flagged the new preflight as not supplying a token. It *does* —
via an inline `DOPPLER_TOKEN=` assignment, which is **safer** than the `--token` argv form
the gate recognised, because argv is world-readable through `/proc`. So the correct fix was
widening the gate rather than making the step less safe.

That is also exactly the shape the corpus warns about ("modify the guard so my PR passes"),
so the widening was discharged explicitly: state the property ("every doppler-calling step
supplies a token"), then show the widened predicate still rejects everything the narrow one
did. Verified both — the original defect shape (`DOPPLER_TOKEN_PRD` in env, body references
it nowhere, bare `doppler secrets get`) and a comment-only mention are each still flagged.

## Session Errors

**Three apostrophes introduced into a `python3 -c '...'` block** ("this PR's own", "this
suite's own", "the tool's own") — each terminates the single-quoted shell string; the script
died `rc=2 syntax error`. — *Recovery:* reworded all three. — *Prevention:* none proposed.
The failure is **loud and immediate**, and the corpus reserves mechanical gates for silent
failures. A repo-wide scan for the pattern was attempted and its 3 hits were all detector
false positives (the regex spanned block boundaries; all three files parse fine), which is
itself the lesson — see the next item.

**My apostrophe detector over-matched and I nearly acted on it.** It reported 194
apostrophes in one file. — *Recovery:* `bash -n` on all three "offenders" showed clean
syntax. — *Prevention:* already covered by the instrument-verification discipline; this is
the third instance in one session (below), which is the signal worth recording.

**My first off-PATH test for `--state` was invalid.** The constructed `PATH` did not actually
remove doppler — it still resolved via `/home/jean/.local/share/../bin/doppler` — so the case
would have "passed" for the wrong reason. — *Recovery:* built a minimal `PATH` from explicit
symlinks and added a **positive control** asserting doppler was genuinely absent before
running the case. — *Prevention:* any suite that stubs or removes a binary needs a control
proving the removal took effect; the control is the test, the case is the consequence.

**A mutation arm reported SURVIVED against a green suite** where the gate under test is a
no-op by construction. — *Recovery:* re-ran as a composite (real SUT break + gate deleted).
— *Prevention:* routed to `review/SKILL.md` — before crediting a mutation row, ask whether
the fixture would otherwise *fail*; a gate that only fires on failure cannot be tested by a
green run.

**`scan_rc` captured but never asserted (SC2034).** The unused-verdict class — caught by
shellcheck, not by me, on code I had written minutes earlier. — *Recovery:* wired the rc to
a real assertion. — *Prevention:* confirms the existing guidance to run the cheap
deterministic lints *after each guard-shaped commit*, not once at session start.

**A comment beginning `# shellcheck's …` was parsed as a directive** (SC1073/SC1072). —
*Recovery:* reworded. — *Prevention:* one-off.

**`grep -q 'not on PATH'` vs. the SUT's `NOT on PATH`** — my assertion, not the code. —
*Recovery:* `grep -qi`. — *Prevention:* one-off; the suite caught it on the first run.

**`rm -rf "$SB"` blocked by the protected-location guard** — the guard cannot expand a
variable, so it refused conservatively. — *Recovery:* used a literal path. — *Prevention:*
one-off; the guard behaved correctly.

**`git stash list` blocked** by `hr-never-git-stash-in-worktrees`, reached for reflexively as
a read-only probe. — *Recovery:* used `git show origin/main:<path>`. — *Prevention:*
one-off; the rule is right and the blanket block is the point.

**Assertion-floor churn** — the inngest floor was set to 13, then 21, then 23 as cases
accreted; each intermediate value was briefly wrong. — *Recovery:* set it last, from the
measured count. — *Prevention:* one-off; derive the floor after the cases are final.

**CI triage took three wasted round-trips.** `gh run view --log-failed` returned the whole
job and my greps did not isolate the failing suite. — *Recovery:* queried step conclusions
directly (`gh api …/actions/jobs/<id> --jq '.steps[] | select(.conclusion=="failure")'`),
which named it immediately. — *Prevention:* routed to `review/SKILL.md` — on a red check,
go to the failing **step** first; `--log-failed` is a haystack, and `[FAIL]`-style markers
may not exist when the failure is a ratchet or a lint rather than an assertion.

## Tags

category: runtime-errors
module: scripts/inngest-host-state.sh
