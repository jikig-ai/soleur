---
title: "I wrote the evidence down and then concluded the opposite, in the same document"
date: 2026-08-25
category: workflow-issues
module: inngest-cutover
issues: [7674, 7698, 6616]
pr: 7692
tags: [evidence-integration, guard-vacuity, mutation-testing, observability, measurement]
---

# I wrote the evidence down and then concluded the opposite, in the same document

## Problem

`#7674` was opened to fix a dedicated Inngest host that boots cleanly and never serves. In the
first ten minutes I self-pulled Better Stack and measured, from web-1:

```
[Inngest] error - TypeError: fetch failed
  [cause]: Error: connect ECONNREFUSED 10.0.1.40:8288
```

I wrote that into the issue body as **"correction #2 to the handoff"** — and then, in the **same
issue body, three sections lower**, wrote a section headed **`## No outage`**. I repeated "no
outage" in the runbook and to the operator.

It was false. Measured when finally checked: **~621 ECONNREFUSED/hour (~14,900/day)**.
`INNGEST_BASE_URL=http://10.0.1.40:8288` is baked unconditionally into the web-platform container
and `server/inngest/client.ts` passes it through as `baseUrl` with **no fallback**, so every
app-originated `inngest.send()` was addressed to the stopped host. `send-with-retry.ts` retries
*transient* failures; against a host stopped by design every retry also fails and the event is
dropped.

The claim survived a plan phase, a CTO consult, my own drafting, and a self-review. It was caught
by an architecture review agent asking whether the premise held.

## Root cause

**Proximity in one artifact is not integration.** I had the datum and the conclusion in the same
file, ~40 lines apart, and never joined them. What did the joining work in my head was a *summary*
— "crons are firing" — and that summary was true. It was also only half the system.

A half-true summary is worse than a missing one, because it **terminates inquiry**. "No outage"
reads as a completed check. Nobody re-opens a closed question.

The generalizable trigger: I had partitioned the system without noticing (scheduled path vs
event-driven path), verified one partition, and reported on the whole.

## Solution

- Corrected the runbook with a measured split rather than a summary:

  | Path | State | Evidence |
  |---|---|---|
  | Scheduled crons | healthy | ~14 `inngest/scheduled.timer` rows/hour |
  | App-originated `inngest.send()` | **failing** | ~621 `ECONNREFUSED`/hour (~14,900/day) |

- Filed the dispatch failure as its own issue (#7698) — a discovered defect in a different
  subsystem must not be buried in an unrelated feature branch.
- Corrected `#7674`'s body so it no longer contradicts itself.

## Key insight

**When you write down a fact that surprises you, immediately ask what else it falsifies — before
you write the next section.** A correction recorded in one paragraph does not propagate to the
conclusion three paragraphs down unless you make it propagate.

And: **before writing any "no X" / "nothing is broken" summary, name the partitions of the system
and say which one you measured.** If the sentence quantifies over the whole system and the
measurement covered one partition, the sentence is wrong even when the measurement is right.

## The second pattern: on a guard-shaped PR, the defects are in the guards

A test-design pass drove **13 mutations** at suites I had written and **11 survived**. Every one
was a case of asserting *text* where *behaviour* was available:

| Mutation | Result | Why it survived |
|---|---|---|
| `VERDICT="healthy"` (sever classifier from its only caller) | green | the assertion grepped for the `source` line, which the mutation leaves intact |
| `if: false` on the whole arm | green | eleven structural assertions are dead-code-blind |
| `RS_LIVE_N="20"` (sever the gate from its signal) | green | I asserted the **assignment** exists; a literal satisfies it |
| `FLIP_LIVENESS_SINCE` `15m` → `365d` (the fail-open direction) | green | the harness **exported** `15m`, so the argv assertion measured the test's own value |
| delete the only `host_name` isolation line | green | `grep -qF 'host_name'` matched **four comment occurrences** vs one code occurrence |

Plus two assertions that could never fail at all: one grepping `DEDICATED_VERDICT` (zero
occurrences in the file — the variable is `VERDICT`), and an empty-`INNGEST_HOST_NAME` guard that
`${VAR:-default}` makes unreachable because `:-` substitutes on empty as well as unset.

**The comments were the collision surface.** This PR's rationale comments are its best feature —
and the moment a task requires both "assert X" and "document why X", the documentation becomes
matchable text for the assertion. `host_name` appeared once in code and four times in prose I had
just written to explain the code.

**Fix:** extract the workflow step's `run:` body and **execute** it against stubbed rows with a
fake `GITHUB_WORKSPACE` holding a stub reader and the real classifier. One change killed four
mutations at once. Anchor every remaining grep on a call shape a comment cannot produce.

## The third pattern: floor slack is attack budget

Both anti-deletion floors carried slack (476 vs 477; 28 vs 30). Deleting one assertion stayed
green — and the assertion the slack permitted deleting was **exactly the one a mutation had just
proven load-bearing**. Floors are now the exact dispatched count.

## The fourth pattern: citing a learning is not applying it

All three new readers filtered on `host_name`, and I cited
`2026-07-18-betterstack-followthrough-probe-must-field-isolate-syslog-identifier.md` while doing
it. But **#6616 is OPEN and titled "host_name telemetry is lying"** — a web host has been observed
self-labelling with the dedicated node's sed-rendered literal. The authoritative field is `host`
(Vector's OS hostname = the Hetzner server name), which this repo's own
`hostname-mislabel-web1-6616.sh` pins.

Every site failed **open**: the gate would count a web host's rows as liveness; the watchdog's
`tail -1` could land on a web-1 row and auto-close the alarm; the follow-through probe would PASS
and **close #7674 while the host was dark** — recreating the silent no-op it was written to retire,
one field over.

The citation made the requirement *feel* discharged. Applying a learning means naming the specific
field/route/site it governs **here**, not naming the learning.

## Instruments that lied to me

Four, all mine, all in the direction of a confident wrong reading:

- `doppler run -- probe | head -1` then `echo rc=$?` reported **0**. That was `head`'s exit. Real
  rc was 2. Measure exit codes **without a pipe**.
- A crude grep classified `logger -t ... SOLEUR_INNGEST_SERVER_PROBE` as a "READER", nearly making
  me accept a false agent finding that my zero-consumers claim was overstated. **An emitter is not
  a consumer.**
- `python .replace()` without an `assert` silently no-op'd **twice**; only a red suite surfaced it.
  Every programmatic edit needs `assert old in s`.
- A python heredoc wrote literal `\"` into a bash file, producing a syntax error I then chased.

## A good outcome worth keeping

A code-quality agent argued my figure correction (2,450 → 2,040 rows/day) had gone the **wrong
way**, reasoning that a `--limit`-bound count under-reports a saturating channel — a specific,
plausible, well-argued challenge. I re-measured with per-minute bucketing and at limit 1000 vs
5000: **not saturating** (84 rows at both) and bucketed agreed with the bare count (1.45 vs
1.40/min). The correction stood.

**A challenge to a measurement is settled by re-measuring, not by re-arguing.** The verdict was
that I had been right; the value was in the method, and it cost about ninety seconds.

Symmetrically: three of four "falsifications" from a history agent were category errors (emitter
vs consumer; a 2026-07-23 code comment cited against the live API; attacking a claim I never made).
**Agent findings are hypotheses.** The same agent surfaced two real ones in passing.

## A design rule worth keeping (CTO ruling)

**Do not share a decider across two verbs when the signal's polarity inverts between them.**
`L >= 1` REFUSES at `op=arm` (a flush already happened) and SATISFIES the precondition at
`op=resume` (a completed flip wrote `done`). Reusing one function would force the caller to invert
two of four arms and leave the token `latched` meaning opposite things at its two call sites.

## Session Errors

1. **`session-state.md` was never written** after parsing the planning Session Summary, though
   one-shot Steps 1–2 mandate it. — *Recovery:* recovered the plan-phase errors from the summary
   text. — **Prevention:** the one-shot step should verify the file exists before continuing.
2. **Asserted "no outage" three times while holding contrary evidence.** — *Recovery:* re-measured,
   corrected runbook + issue, filed #7698. — **Prevention:** before any "nothing is broken"
   summary, name the partitions and say which was measured.
3. **11 of 13 mutations survived my own battery.** — *Recovery:* executed-arm fixture + anchored
   greps. — **Prevention:** on a guard-shaped PR, mutate the SUT before claiming the suite pins it.
4. **Asserted an assignment (`RS_LIVE_N=`) instead of the call.** — *Recovery:* pinned the call. —
   **Prevention:** a literal satisfies an assignment grep; pin what produces the value.
5. **Circular pin** — the harness exported the value its assertion checked. — *Recovery:* source
   the real assignment from the SUT. — **Prevention:** never `export` a value you then assert.
6. **Comment-satisfiable greps** (`host_name`: 1 code, 4 comments). — *Recovery:* anchored on call
   shapes. — **Prevention:** after writing a rationale comment, re-check every assertion that greps
   the same file.
7. **Floor slack absorbed the load-bearing assertion.** — *Recovery:* floors set to exact counts. —
   **Prevention:** anti-deletion floors have zero slack by definition.
8. **`DEDICATED_VERDICT` assertion could never fail** (zero occurrences). — *Recovery:* replaced
   with a real assertion. — **Prevention:** grep the token you assert on and confirm it is non-zero.
9. **An empty-host guard that could never fire** (`${VAR:-}` substitutes on empty). — *Recovery:*
   deleted it. — **Prevention:** `:-` vs `-` is the difference between reachable and dead.
10. **Backticks in a test label executed `host(1)`.** — *Recovery:* single-quoted. — **Prevention:**
    no backticks in double-quoted bash strings, including labels.
11. **Filtered on `host_name` while citing the field-isolation learning.** — *Recovery:* dual-field
    conjunction, mutation-proven. — **Prevention:** name the field the learning governs *here*.
12. **False `ignore_changes=[user_data]` attribution** — wrong host. — *Recovery:* corrected. —
    **Prevention:** when a comment names a Terraform lifecycle, read that resource.
13. **"No volume-recut apply_target exists"** — unscoped; two live recut targets exist. —
    *Recovery:* scoped to this volume. — **Prevention:** scope existence claims to their subject.
14. **ADR carried ~2,450/day beside its own ~1.4/min.** — *Recovery:* corrected to the measured
    figure with its window. — **Prevention:** never carry a figure you did not measure.
15. **The `silent` message named fields its marker does not carry** and half the conjunction the
    code evaluates. — *Recovery:* rewritten. — **Prevention:** an operator message must name a
    cause the branch measured.
16. **`FLIP_LIVENESS_SINCE` shipped as a dead knob** whose only effect was fail-open. — *Recovery:*
    literal + a "not plumbed" assertion. — **Prevention:** check whether an override is reachable.
17. **Reported `live rc=0`** — that was `head`'s exit. — *Recovery:* re-measured without a pipe. —
    **Prevention:** never read `$?` through a pipe.
18. **A grep classified an emitter as a consumer.** — *Recovery:* read the line. — **Prevention:**
    emitter ≠ consumer.
19. **`python .replace()` silently no-op'd twice.** — *Recovery:* red suite surfaced it. —
    **Prevention:** `assert old in s` on every programmatic edit.
20. **Literal `\"` written into bash via a python heredoc.** — *Recovery:* rewrote with raw
    strings. — **Prevention:** `bash -n` immediately after any generated edit.
21. **Plan-phase jq concatenated a string with an OBJECT `.message`**, rendering as zero rows under
    `2>/dev/null`. — *Recovery:* count-only re-query. — **Prevention:** never suppress stderr on a
    query whose emptiness will bound a decision.
22. **A plan research finding was wrong** (`deploy-inngest-image.yml` reaching the dedicated host).
    — *Recovery:* CTO agent corrected it; verified independently. — **Prevention:** verify delivery
    paths by reading the POST target.
23. **First `gh issue create` blocked for a missing `--milestone`**, taking its inline heredoc down
    with it. — *Recovery:* wrote the body file separately. — **Prevention:** never heredoc a body
    into the same command as a hook-gated `gh` call. *(one-off; already a documented rule)*
24. **Push rejected non-fast-forward** after rebasing my own branch. — *Recovery:*
    `--force-with-lease`. — **Prevention:** expected after a rebase. *(one-off)*

## Related

- #7698 — the dispatch outage this session discovered and mis-summarised
- #6616 — `host_name` telemetry is lying (the field I filtered on)
- #7695, #7696 — the deferred recut build and the emit rate-limit
- `2026-07-18-betterstack-followthrough-probe-must-field-isolate-syslog-identifier.md` — the
  learning I cited and misapplied
- `2026-08-10-a-guard-that-cannot-be-driven-red-is-vacuous-four-rounds-four-instances.md`
