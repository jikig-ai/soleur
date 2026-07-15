---
title: "A dry-run that validates a parser against a FABRICATED fixture confirms your assumption, not the format"
date: 2026-07-12
category: best-practices
tags: [dry-run, external-format, parser, verification, review, observability, workflow]
issue: 6369
component: cutover-inngest-workflow
---

# Learning: dry-run fixtures for an external-format parser must be derived from the PRODUCER's source, not fabricated

## Problem

Building `op=arm` (#6369), the G6 step confirms the on-host flip FSM reached `done` by querying
Better Stack for a `logger -t inngest-cutover-flip` JSON line and grepping it. I wrote the grep
from the plan's `## Observability` **prose** (`reason:done exit_code:0`) → `grep '"reason":"done"'`.

At Phase 5 (dry-run validation) I "validated" the parse — but I constructed the test fixture MYSELF
from the same wrong assumption:

```bash
SYNTH_DONE='{"dt":"...","raw":"...{\"reason\":\"done\",\"exit_code\":0,...}"}'   # FABRICATED
# my parse grepped "reason":"done"  → matched  → "DONE -> CONFIRM-done"  ✓ (falsely reassuring)
```

The dry-run passed because the fixture and the parser shared the same fabricated shape. It proved
the parser matches my invented format — **not** that it matches what the host actually emits.

The real emitter (`apps/web-platform/infra/inngest-cutover-flip.sh`, `emit_state exit_code dbsize
reason flag`) puts the **terminal state in the `flag` field** and a *cause* in `reason`:
`{"exit_code":0,"reason":"flip-complete","flag":"done",...}`. `"reason":"done"` is emitted by NO
code path. So the shipped G6 would have `grep '"reason":"done"'` → **never match → op=arm times out
after 600s and reports EVERY successful cutover as FAILED** (a single-user incident: the operator
then halts crons for all users, or rolls back a good flip). Two independent review agents
(data-integrity-guardian, pattern-recognition-specialist) caught it by reading the actual emitter.

## Solution

- Rewrote the confirm to key on the emitter's real field: `"flag":"done"` + `"exit_code":0`
  (and `"flag":"aborted"|"flag":"rolled-back"` for the fail-loud path), extracted into a shared
  `confirm_flip_state()` used by both op=arm and op=rollback.
- **Re-validated against a fixture reconstructed from the emitter's `emit_state` call sites**
  (`flag:done reason:flip-complete`, `flag:aborted reason:dbsize-nonzero`, `flag:flipping` non-terminal):
  DONE→done, ABORT→aborted, RB→rolled-back, FLIPPING→keep-polling. This is the fixture that would
  have caught the bug at dry-run time.
- Added a drift-guard **parity assertion** that the workflow greps `"flag":"done"` (NOT
  `"reason":"done"`) AND the emitter actually stamps `flag_set "done"` — so the two files can't
  silently drift again.

## Key Insight

**A dry-run that exercises a parser against a fixture you authored from the same mental model as the
parser is circular — it validates the assumption, not the wire format.** For any parser of an
EXTERNAL producer's output (another script's `logger` line, a vendor API JSON, a CLI's stdout, a
webhook payload), the fixture MUST be derived from the producer's source of truth:

1. Read the producer's emit site(s) and copy the literal field names/shape, OR
2. Capture one real sample from the producer and assert against those bytes.

Litmus: *"If my parser's field assumption is wrong, does this fixture still pass?"* If yes, the
fixture is fabricated-from-the-same-assumption and proves nothing. This is the dry-run cousin of the
review-catalogue entry "external-API-shape AC must land a captured fixture, not a probed claim"
([[2026-06-16-external-api-shape-ac-must-land-captured-fixture-not-probed-claim]]) — and of the
plan-precondition rule that plan PROSE about a format is a claim to verify against source, never a fact.

## Companion insights (same session, #6369)

- **Folding a conditional into a previously-UNCONDITIONAL path silently narrows it.** `op=rollback`
  had an unconditional Half B (web re-enable = the documented P0-3 aborted-state recovery). Folding a
  new `flip-state` guard (Half A) in front of it gated the WHOLE job, so `aborted`/`unset` hit
  `exit 1` and Half B never ran → crons stay stalled. When wrapping a new conditional around an
  existing verb, verify the pre-existing behavior still runs for EVERY state; scope the new guard to
  ONLY the new action. (Same class as "short-circuit guard must sit after the recovery it gates.")
- **A fail-CLOSED guard fed by a fail-OPEN read is fail-open.** `CUR_FLIP=$(doppler get ... || true)`
  collapses a read/API error to empty, which the `${x:-unset}` default routes to the SAFE branch —
  so the guard evaporates exactly when the read fails. Distinguish "genuinely absent" from "read
  failed": probe a known-present key first (here `DOPPLER_PROJECT`) and fail closed if THAT read
  fails. Same shape defeated G3's `PG != PG_DARK` when `PG_DARK` read empty.
- **A CLI flag's accepted input format is a claim to verify against the tool's parser.** Passed an
  ISO `T…Z` timestamp to `betterstack-query.sh --since`, whose regex only accepts `Nh/Nm/Nd` or a
  literal `YYYY-MM-DD HH:MM:SS` (ClickHouse cast) — the ISO form falls through and can error the
  query → 600s timeout. Read the tool's `--since` parser (`^([0-9]+)([hmd])$`) before choosing the
  format. (Same class as `hr-when-a-plan-specifies-relative-paths` / plan-quoted-tool-flag-value.)

## Session Errors

1. **G6 keyed on `reason` not `flag`; dry-run validated a fabricated fixture.** Recovery: rewrote to
   `flag`, re-validated against an emitter-derived fixture + added a parity assertion. **Prevention:**
   derive external-format dry-run fixtures from the producer's source; add a producer↔consumer parity
   test. (This learning + a routed Sharp Edge to the work skill Phase 5.)
2. **op=rollback G1' gated the whole job → broke P0-3 recovery.** Recovery: Half B unconditional; new
   guard scoped to the reverse-write only. **Prevention:** when folding a conditional into an existing
   verb, assert the pre-existing unconditional path still runs for all states.
3. **G1 + G3 fail-OPEN on read error (`|| true`).** Recovery: config-readability probe + empty-check
   fail-closed. **Prevention:** never let a fail-closed guard consume a swallowed read as a safe value.
4. **ISO `--since` format rejected by the query tool.** Recovery: space-form timestamp. **Prevention:**
   verify a CLI's accepted input format against its parser before use.
5. **Drift-guard assertion matched its own comment prose** (`jq .`). Recovery: reworded the comment.
   **Prevention:** anchor body-greps on syntactic constructs, not bare tokens the file also documents
   (known class: grep-over-body-false-match). One-off (self-caught at test time).
6. **Bash CWD persisted across calls** — an early `cd` into a sibling worktree confused the bare-repo
   probe. Recovery: explicit `cd <abs>` per command. **Prevention:** the Bash tool keeps CWD; always
   chain `cd <abs-path> && <cmd>`. One-off (self-caught).

## Prevention

- Dry-run/verification fixtures for any external producer's format: reconstruct from the emit site or
  a captured real sample; add a producer↔consumer parity assertion so the two can't drift.
- New conditional in front of an existing unconditional step: prove the old behavior survives for
  every input state.
- Fail-closed guard: guard the READ, not just the decision.
