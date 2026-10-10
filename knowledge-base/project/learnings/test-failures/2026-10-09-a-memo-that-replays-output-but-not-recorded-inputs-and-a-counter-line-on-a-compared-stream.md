# Learning: a memo that replays output but not recorded inputs, and a counter line on a compared stream

## Problem

PR #9824 (#9812, affected-derive cross-run cache) passed its own 13-row suite and the byte-identical
acceptance bench, yet the review panel found two defects the green runs never surfaced:

1. **The `_FE_FILES` memo replayed a file's edges into later records without the probes that produced
   them.** Instrumentation recorded every existence probe during the FIRST suite's extraction of a
   shared helper; memo consumers got the replayed edges but not the negative probes — so a file
   created later at a recorded-miss path inside the helper invalidated only the extractor's record.
   ~440 consumers would have served stale narrowed edge sets: silent under-selection, the exact class
   the design exists to prevent. T3 tested probe invalidation but only on per-record paths (stem
   candidates re-derive per record), so the hole sat between two tested mechanisms.
2. **An unconditional telemetry line on stdout broke the bench's determinism arm.** The
   `AFFECTED_DERIVE_CACHE` counters went to stdout; `affected-prepass-bench --runs N>1` byte-compares
   repeat head runs' whole stdout, and cold (`misses=586`) vs warm (`hits=586`) counters legitimately
   differ → the bench fails its own head side as "non-deterministic". The recorded measurements used
   `--runs 1`, which never executes the compare loop — the defect was invisible in the evidence.

## Solution

- **Memoize the input slice, not just the output.** `_FE_PROBESETS`/`_FE_RECTRACKED` record the
  probe-window delta per extracted file and replay it into each consumer's record on a memo hit; a
  cold-populated entry poisons (`_ADC_REC_BAD`) rather than stores an under-recorded record. Test
  row: two registrations sharing a helper classified in ONE process, then create the missed path —
  the consumer's record must re-derive too.
- **Observability on a machine-compared stream belongs on stderr.** The emit moved to stderr with a
  `state=on|off` field; `--print-selection` stdout stays byte-clean for the bench's `cmp` arm, which
  now gets exercised at `--runs 2` in the acceptance evidence.
- **Truncation trailers are not integrity.** A well-formed bit-flip inside a record validates and
  replays a narrowed edge set; a `sum` cksum trailer over the body (verified before replay) catches
  mutation-class corruption, not just cut files.
- **Hash the extracted span, not the file.** A whole-file preimage flushes all ~586 records on every
  unrelated `test-all.sh` edit; the derive's own extraction anchors bound the preimage, and each leg
  must produce non-empty output or the whole file hashes — a flush, never a stale serve.

## Key Insight

Instrumentation completeness is **per-record, not per-site** — a recorder can cover every probe site
perfectly and still under-record for a consumer whose edges arrive through a replayed memo. And a
test that passes at `--runs 1` says nothing about a gate that only fires at `--runs ≥2`: acceptance
evidence must exercise the gate arm, not just the happy path.

## Tags

cache-invalidation, memoization, test-harness, telemetry-placement, review-findings
