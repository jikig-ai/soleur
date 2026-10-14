---
title: A presence check after `source` is satisfied by the environment, and a log row's identity is its emitter
date: 2026-09-27
category: security-issues
module: inngest-health / Better Stack probe readers
tags: [betterstack, emitter, syslog-identifier, shared-lib, fail-open, census, inngest]
issue: 8846
pr: 8873
---

# Learning: a presence check after `source` is satisfied by the environment

## Problem

The dedicated-host inngest watchdog (#7674 arm of `scheduled-inngest-health.yml`) chose the
newest `SOLEUR_INNGEST_SERVER_PROBE` row by **substring**. The inngest server's own event log
ships from the same host under `SYSLOG_IDENTIFIER=doppler` and quotes the marker whenever a
GitHub issue about the probe is webhooked in. A quoted row won `tail -1`, a healthy host graded
`probe-unavailable`, and the alarm fed itself: every filed/closed issue produced another quoting
row. Live 6h read (2026-09-25): 6 real probe rows, 50 `doppler` rows quoting the marker. It filed
a false P1 pair hourly (#8823/#8824, #8829/#8830, #8833/#8834, #8850/#8851, #8862/#8863).

Seven readers had seven predicates; three were substring, two of those failed OPEN (7674 PASS,
which clears G18 on the apply workflow; the FSM liveness counters behind `op=resume` G3).

## Solution

1. One definition, sourced: `scripts/lib/inngest-probe-row.sh` builds a jq
   `def inngest_probe_row:` from two variables — emitter `inngest-server-probe` AND message
   `startswith("SOLEUR_INNGEST_SERVER_PROBE ")` — plus a `--selftest`.
2. Every consumer sources it and selects on the DECODED row; the liveness counters take a
   required literal emitter tag; `confirm_*_state` / `_flip_transition_dt` read only the FSM's own
   emitter on the host pair (`_fsm_own_rows`).
3. A census suite fails CI on any tracked file that reads the marker (or `$INNGEST_PROBE_MARKER`,
   or sources the lib) without the call shape `select(... inngest_probe_row)` and the load
   contract; a must-find list pins the readers that matter; parity ties the literals to the
   emitter's own `LOG_TAG`.

## Key Insight

**A post-`source` presence check (`[[ -n "$INNGEST_PROBE_ROW_JQ" ]]`) cannot tell "the lib set
this" from "the caller's environment set this".** The first implementation guarded every
consumer that way; review reproduced a fail-open in the destroy-authorizing dark gate with
`INNGEST_PROBE_ROW_LIB=/dev/null INNGEST_PROBE_ROW_JQ='def inngest_probe_row: true;'`, and the
channel is real — `.github/actions/infra-credentials` exports every Doppler key into
`$GITHUB_ENV`. The load contract that closes it: `unset` the names BEFORE `source`, keep the
source's stderr, then prove the loaded def with its own selftest (which grades the event-log
shapes), so presence is never the evidence.

Second insight: **a log row's identity is its emitter, never its message content.** Host
isolation (`host` + `host_name`) cannot exclude a different program writing on the same host.
Better Stack parses JSON-shaped messages into objects for the FSMs (`inngest-cutover-flip`,
`inngest-luks-cutover`: `.message` is an object) but not for the event log (`.message` is a
string) — measured live, and the difference is an accident of ingestion, not a control.

## Session Errors

1. **The first implementation shipped the presence-check fail-open** across all seven consumers
   (seven parallel implementers, one contract). — Recovery: load contract + selftest, with an
   inherited-permissive-def row per suite, each mutation-proven against the FAITHFUL old check.
   — Prevention: route bullet added to `plan/references/plan-sharp-edges.md` (`work/SKILL.md` is at its body-byte ceiling).
2. **A weekly API limit killed four fan-out fix agents mid-edit**, leaving an unverified partial
   tree. — Recovery: re-derived each agent's landing from `git diff` + running every suite before
   committing; finished the rest sequentially. — Prevention: fan-out briefs already say write-only;
   the lead must treat a dead agent's tree as unverified and re-run its suites (did).
3. **The new census suite reddened two repo ratchets** (`lint-orphan-test-suites`: no affected
   classification; `fixture-relative-assert`: unguarded mktemp writes). — Recovery: classified
   ALWAYS_ON, added canonical `assert_fixture_dir`. — Prevention: `work/SKILL.md` §6.6 already
   says run the fixture ratchets before a new `*.test.sh`'s first commit; it was run late, not skipped.
4. **The census matched its own classification comment** (`test-affected-paths.sh` comment named
   the marker literal and became UNCLASSIFIED). — Recovery: reworded. — Prevention: one-off.
5. **`grep -vE … | grep -qE` under `pipefail`** in the census helper read a real match as false
   (SIGPIPE class). — Recovery: herestring. — Prevention: already covered by
   `grep-q-pipe-guard` for hooks; it recurred in a suite — one-off here.
6. **A mutation sandbox built from a partial copy had a red control** (missing sibling files), and
   a later "faithful" mutant tested a different old predicate than the file had and SURVIVED. —
   Recovery: detached `git worktree` sandbox; re-derived the exact pre-change predicate per file.
   — Prevention: covered by review/SKILL.md (green control first; reconstruct the attack exactly).
7. **`test-all.sh --print-affected-set` exceeded the 120s tool timeout.** — Recovery: backgrounded.
   — Prevention: one-off (contended machine).
8. **`pgrep -f` blocked by the self-match hook.** — Recovery: inspected files instead. — Prevention: hook-enforced.
9. **Structural review seat built two P1 candidates on an unmeasured premise** ("Better Stack
   parses JSON messages into objects" for the event log). — Recovery: one live read: event-log
   messages are strings, FSM messages objects; fixed the reads anyway (pin to emitter) since the
   property should not depend on an ingestion accident. — Prevention: review/SKILL.md "a converged
   finding on an unmeasured premise" already covers it.
10. **`cutover-inngest-workflow.test.sh` #8054/#8079 render rows flaked under load** (a different
    row each run, green in isolation). — Pre-existing; one-off for this PR.
11. **Two merge conflicts with main** (`suite-shard-legs.tsv` regeneration; a sibling's
    `head -1` → `sed -n '1p'` sweep in the classify test). — Recovery: took main's manifest and
    re-added the row; kept this PR's hunk with the sibling's idiom. — Prevention: one-off.
12. Planning subagent: one `gh issue create` HTTP 502 (retried, no duplicate); a waiter loop
    failed because `bc` is absent. — One-off.

## Tags
category: security-issues
module: scripts/lib/inngest-probe-row.sh, tests/scripts/lib/inngest-host-dark-gate.sh, scripts/cutover-inngest.sh
