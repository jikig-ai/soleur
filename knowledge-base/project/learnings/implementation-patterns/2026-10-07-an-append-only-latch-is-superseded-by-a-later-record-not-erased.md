---
title: An append-only latch is superseded by a LATER record, never erased — and the authorization rides a value in an exact-set config
date: 2026-10-07
category: implementation-patterns
issue: 7777
---

The #7777 repair: the `/mnt/data` flush latch could only ever mean "a FLUSHALL
already ran", and there was no authorized way to supersede it — every proposal
involved a delete (impossible on a deny-all host) or a volume recut (destroys
the evidence with the store). The fix keeps the file append-only forever and
changes what the READ means: `flushed_at=…` records a performed flush,
`cleared_at=… run=… by=… boot_id=…` records a later, separately-evidenced
authorization, and the predicate reads THE NEWEST non-empty line — a clear
supersedes the flush it follows without erasing it, a later `flushed_at`
re-latches. That is the same monotonicity one level up: a record can only be
superseded by a later record, never rewritten. Anything at the tail the build
does not recognize (malformed, truncated, a future record type) fails CLOSED —
"not a known clear" is latched, not clear.

Two supporting patterns worth reusing:

- **The evidence rides the flag VALUE, not a new secret name.** The Doppler
  config's boot-isolation self-check is an exact-set match — no new key can
  exist — so `op=reflush` writes `reflush,run=<gha-run-id>,by=<actor>` and the
  on-host arm validates and appends it. When a config is an exact set, value-
  structured keys are the only extensible channel.
- **The authorization is stamped at the host, the actor/run at the dispatch.**
  `cleared_at` + `boot_id` come from the recording host (a clear can never be
  attributed to a boot that didn't record it); `run`/`by` come from the
  reviewer-gated dispatch (the env approval IS the authorization).

## Gotchas hit during implementation

1. **`local a= b=` defeats the command-position sweep's suppressor.**
   `inngest-cutover-flip.test.sh` derives in-file-assigned names from
   `(local )?NAME=` at line start — only the FIRST name in a multi-assignment
   registers, so the rest read as UNGOVERNED externals. One `local x=` per line
   in seam-gated scripts.
2. **Capturing probe output with `$(cmd 2>&1 | grep …)` swallows the detail the
   error messages reference.** Capture stdout whole (`rc` honest), extract the
   verdict line after, and let stderr flow to the run log.
3. **`a | b || true` masks the PRODUCER's rc** — the `||` applies to the whole
   pipeline. If the rc matters, capture without the `|| true` and extract after.
4. **Assertion floors are exact in all four suites** (dark-gate `_FLOOR`,
   latch `LATCH_MIN_ASSERTIONS`, flip `MIN_ASSERTIONS`, workflow
   `_EXACT_FLOOR`). Measure the dispatched count from a green run; the stale-
   floor failure prints the exact new value.
5. **A glob-boundary match on `run=${run}` needs the trailing space arm** —
   `run=42` prefix-matches `run=420` without ` run=${run} ` and
   ` run=${run}`-at-EOL alternatives in the same case pattern.
