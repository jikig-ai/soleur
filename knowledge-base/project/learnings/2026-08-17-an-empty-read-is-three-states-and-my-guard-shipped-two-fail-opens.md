---
title: "An empty read is three states, and the guard I built to say so shipped two fail-opens"
date: 2026-08-17
issue: 7569
pr: 7573
category: integration-issues
module: observability
tags: [betterstack, observability, guards, mutation-testing, ap-021, fail-open]
---

# An empty read is three states, and the guard I built to say so shipped two fail-opens

## Problem

On **2026-08-14 19:06:58Z** Better Stack stopped accepting writes: every ingest POST returned
`HTTP 402 {"error": "Quota exceeded"}`. The **read** path kept answering `200` throughout.

That asymmetry is the whole incident. Every absence query returned `rc=0` with zero rows, and the
registry host — the fleet's sole image-pull path, with no SSH by policy — was unobservable for two
days. Three guards were green the entire time, each for a *different* reason:

1. `zot-restart-loop-alarm.sh` collapsed two states into one `||`:
   `[[ "$control_rc" -ne 0 || -z "$CONTROL" ]]` → non-alarming `TRANSIENT`.
2. The workflow reported `completed/success` every 30 minutes — because the detector *ran*.
3. `lint-diagnosis-claims.sh`, the AP-021 gate built to stop exactly (1)'s message, never counted
   it.

The alarm's message named "Better Stack unreachable / creds unset" — two causes the run had just
measured **false**, since `rc` was `0`.

## Key insight

**An empty read from a warehouse is three states, not two, and collapsing them fails toward
silence.**

| state | meaning | correct verdict |
|---|---|---|
| the query FAILED | we learned nothing | probe fault |
| the query ANSWERED, nothing there | the source is taking no writes | **alarming** |
| rows came back | healthy | clean |

"We learned nothing" and "we learned the evidence store is down" are different epistemic states
requiring opposite operator actions. Every `|| -z` in a detector is a candidate instance.

## Solution

`scripts/lib/betterstack-absence.sh` splits the three states with the rc branch and the emptiness
branch as deliberately separate `if`s. Exit 4 (`INGEST_DARK`) files a deduped
`[ci/betterstack-ingest-dark]` issue; `scripts/betterstack-ingest-probe.sh` annotates the refusal
code with **no veto** (inverting that would reintroduce the outage, where a healthy-looking 200
was available and misleading).

The probe posts an **empty batch**. Measured: `[]` gets the same 402 as a real payload and a bad
token gets 401, so the full discrimination is available without writing a row. That is
load-bearing rather than tidy — the alarm's control is an unfiltered "is there any row", so a
probe that wrote its own marker would satisfy it forever and convert a two-day outage into a
permanent blind spot.

## The part worth reading: my own guard shipped two fail-opens

A guard-shaped PR's defects live in the guard and **fail open** — they certify broken-as-fine
rather than erroring. Both of mine were green through a full suite and my own mutation battery.

### 1. A copied invariant does not travel with its precondition

I lifted `bs_absence_response_is_answer` from `betterstack-assert-absence.sh`:

```bash
grep -qiE 'exception|DB::Err|Code: [0-9]+|syntax error' <<<"$out"
```

Sound **there** — it scans a `SELECT count()` body (`{"n":"0"}`), which structurally cannot
contain application text. Wrong **here** — it scans `SELECT dt, raw … LIMIT 1`, the newest row,
payload included. Measured: a healthy row reading `TypeError: unhandled exception in handler` or
`upstream returned Code: 502` classified `TRANSPORT_FAIL`, suppressing `PRODUCER_SILENT` and NIC
`SILENT` to non-alarming and emitting a cause the run measured false — the AP-021 defect the PR
removes, reintroduced by the removal, on the ~75% of volume that logs errors.

Fixed by discriminating on **shape**: a mid-stream exception is a bare line outside the
JSONEachRow stream; every legitimate row begins `{"dt":`.

**Gate:** when copying a predicate, name the property of its *original input* that made it sound,
and check the new input has it.

### 2. A blocking finding in my own plan, that my own implementation missed

F15 was written into the plan as blocking: the zot leg's `--grep SOLEUR_ZOT_DISK` is an unanchored
`raw LIKE '%…%'`, and `zot_trusted_region` only strips the free-text tail. So a row merely
*quoting* the marker made `$MAIN` non-empty and skipped the entire block holding **both**
`PRODUCER_SILENT` and the new `INGEST_DARK`. One line on a shared source suppressed the alarm
indefinitely. The NIC leg has anchored since a live 2026-07-15 incident; this leg had not.

**Gate:** at `/work` Phase 0, grep the plan for its own blocking findings and check each one off
against the diff before review. A plan's `## BLOCKING` section is a work-list, not context.

## A mutation battery only covers the axes you edit

My 5-axis battery reported all-caught. The panel then found, all at green:

- the probe suite had **no accounting control** — neutering `fail()` exited 0 with 9/11 asserting
  `[FAIL]`
- `assert_probe` captured `rc` and never asserted it, so every arm could `exit 0`
- the curl stub ignored `-w` and `-f`. Real curl without `-w` prints nothing (body already to
  `/dev/null`) so every case falls to `*)`; real curl **with** `-f` exits 22 on a 402 — reporting
  `INGEST_UNREACHABLE` for the exact state the probe exists to detect
- both NIC-leg arms were **deletable and invertible**
- `EXPECTED_MIN=45` while 57 assertions ran — twelve cases of slack

**Gate:** enumerate the AXES a battery edits (SUT branch / fixture shape / fixture direction /
harness dispatch / member cardinality / the floor). N mutations on one axis is one mutation. Ask a
reviewer to *find the vacuity the battery missed*, never to re-run its mutations.

## Four claims I asserted instead of measuring

Each falsified by one command:

1. **"ADR-184's shipper is exonerated — absent from the top-10, its 5,000/day cap held."** It is
   ~4th at **5,315 rows/day, over its cap**. The producer table grouped by
   container/`SYSLOG_IDENTIFIER`, which structurally **cannot see a direct host POST** — the
   shipper fell into an `other/unattributed` bucket and I read its missing *label* as an absent
   *producer*. Decompose the unattributed bucket by first message token before ranking.
2. **`80,320 rows/day (75%)`** was a count over a calendar day the outage truncated at 19:06:58 —
   a **19.1-hour** window. The ratio was computed inside the truncated window and paired with a
   full-day denominator. Clean 24h is 135,316 total / ~101,000 container. Every derived capacity
   figure was understated by ×1.26, including an "upgrade is avoidable on capacity" conclusion.
3. **The AP-021 blindness.** I blamed the `CLAIM` phrase list. Measured, three filters reject the
   line and `OPERATOR_LINE` rejects **first** — the message is a bare shell assignment, not an
   emission — while `MEASURED` would exempt it anyway. **When a gate misses something, identify
   which filter rejected FIRST, not the one you expected to fire.** The issue I filed (#7578)
   tested the wrong hypothesis and had to be re-scoped.
4. **"F14 is fixed."** The forgeable predicate is still live and untouched in a script this PR
   never opened. I had shipped a producer-anchored `marker` mode for it — zero callers, and the
   *default*, so any new caller inherited the mode both live sites override. Review also defeated
   the anchor (it pinned the marker's offset in a message value, not producer identity), and it
   does not fit its intended consumer, which uses a `SELECT count()` and therefore needs a
   WHERE-clause change. Cut before merge.

## What only the restoration window could buy

Ingest was restored mid-PR. Both directions are now measured against real production, same day,
no code change between:

| | dark | restored |
|---|---|---|
| probe | `INGEST_REFUSED_QUOTA http=402`, exit 4 | `INGEST_ACCEPTING http=202`, exit 0 |
| alarm (zot) | `INGEST_DARK`, exit 4 | `GREEN`, exit 0 |
| alarm (NIC) | `INGEST_DARK` | `GREEN` |

A guard proven only against fixtures is proven against the shapes its author imagined. When a
transient production state is about to clear, capturing the other direction is time-critical and
unrepeatable.

## Session Errors

1. **The planning subagent's Session Summary named blocking items `F2`/`F4`/`F7` that do not
   exist in the plan on disk** (it has F14/F15/F16/F18). — Recovery: worked from the artifact,
   not the summary. — **Prevention:** a subagent's summary is a claim about a file; grep the
   artifact for every identifier the summary cites before treating it as a work-list.
2. **Copied a predicate onto an input that violates its precondition** (fail-open, PR-introduced).
   — Recovery: reproduced, then discriminated on shape. — **Prevention:** see gate above.
3. **F15 was blocking in my own plan and the implementation missed it.** — Recovery: review
   rediscovered it independently. — **Prevention:** check the plan's own blocking list off against
   the diff at `/work` Phase 0.
4. **ADR ordinal collided mid-session** — 187 merged into main while the branch was in flight;
   188–191 claimed on unmerged branches. — Recovery: renumbered to 192, swept references. —
   **Prevention:** already covered by the existing re-derive-against-fresh-origin sharp edge; this
   is its third recorded instance.
5. **The ADR reference sweep rewrote an archived dated plan** whose `ADR-187` was an unrelated
   historical proposal. — Recovery: reverted that file. — **Prevention:** exclude
   `plans/archive/` from identifier sweeps by rule; a dated record is append-only.
6. **Four claims asserted rather than measured** (see above). — **Prevention:** for every causal,
   universal or quantitative claim the diff ADDS, name the falsifying command and run it before
   writing the sentence.
7. **Five test-vacuity gaps shipped** (accounting control, rc assertion, stub argv fidelity, NIC
   arms, slack floor). — Recovery: all fixed and mutation-proven. — **Prevention:** the axis
   enumeration above.
8. **#5134 misattributed to 5-Why #5** — it is a deferred increment of #5103. — **Prevention:**
   read the cited document's Action Items table rather than inferring provenance from topic.
9. **Two mutations did not land** (heredoc escaping) and reported the baseline. — Recovery: the
   landing assertion caught both; re-ran with `sed`. — **Prevention:** already practised — assert
   the mutation landed against a pristine backup, and treat baseline-identical as UN-RUN.
10. **Declared 10 cases in a cardinality guard while writing 9.** — Recovery: the guard caught it
    on first run. — **Prevention:** derive the count from the as-written file.
11. **A `grep` in the bare-repo root returned nothing** because the synced mirror is stale. —
    Recovery: re-ran from the worktree. — **Prevention:** existing hard rule
    `hr-when-in-a-worktree-never-read-from-bare`.
12. **A `gh issue create` hook denial took its same-command heredoc down with it**, so the retry
    failed on a missing body file. — **Prevention:** existing documented trap — write the body with
    the Write tool first, in a separate call.
13. **Four planning-phase self-corrections** forwarded from `session-state.md` (a false
    `set -uo pipefail` premise, a mis-scoped `parse_err` claim, a wrong IaC apply-path claim, and
    `filter`/`throttle` named for a fan-out problem). Each was caught by measurement during
    planning. — **Prevention:** already working as intended.

## Related

- ADR-192 — the invariants (I-1 three states, I-2 marker predicates)
- `betterstack-quota-near-miss-postmortem.md` — predicted this on 2026-06-10; its 5-Why #5 action
  item (#5103, with #5134 as a deferred increment) was never built
- #7577 — volume reduction; the account is accepting writes again at the rate that exhausted it
- #7578 — the AP-021 detector gap, re-scoped to `OPERATOR_LINE`
