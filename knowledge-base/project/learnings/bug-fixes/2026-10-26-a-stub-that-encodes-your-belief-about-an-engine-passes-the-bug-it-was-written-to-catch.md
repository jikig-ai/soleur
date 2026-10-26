---
title: 'a stub that encodes your belief about an engine passes the bug it was written to catch (#11143)'
date: 2026-10-26
category: bug-fixes
tags: [pencil, mcp, adapter, stub, contract-probe, lifecycle, sentinel, review-fix-round]
type: bug-fix
---

# A stub that encodes your belief about an engine passes the bug it was written to catch

## Problem

The headless Pencil MCP adapter sent `batch_design({ operations })`; `@pencil.dev/cli` 0.2.9 takes `{ input }`.
The engine drops an unknown key and answers OK, so every design call was a silent no-op, and
`open_document({filePath})` spawned `--out <file>` with no `--in`, so the next save replaced a tracked
`.pen` with a 96-byte empty document. The earlier unit tests encoded the same wrong belief about the REPL.

## Solution

- One table (`REPL_SURFACE`) and one formatter (`formatReplCommand`) own every command the adapter sends,
  and `operations` is mapped to `input` there. `guardedSave` is the only emitter of `save`.
- `open_document` passes the existing file as `--in`; the pre-switch save is deleted.
- A save sentinel refuses an empty document over a non-empty or unrecognizable file (it reads the
  UNtruncated `batch_get()` reply, and an unparseable disk file counts as something to protect).
- A stub REPL drives the INSTALLED adapter over real MCP stdio, and a key-gated
  `engine-contract-probe.sh` runs the same driver against the real engine. The stub exits 64 on an unknown
  key, so the original bug fails the round trip instead of being accepted.

## Key Insight

1. **A stub is your belief, not the engine.** It can only fail on what you already know. The one test that
   touches the real engine (signature diff of `--help` against the table, a round trip, a >64 KiB design,
   the sentinel refusing) is the one that would have caught #11143; pin the CLI version and re-run it on
   every bump.
2. **The fixes of a review round are the least-audited code, and they reproduce the class they close.**
   The panel's lifecycle fixes (spawn inside the queue, handlers bound to their own child, edit+save as one
   job) were followed by a fix-round review that still found a defect in the new respawn path (a respawn
   before the first save dropped the template) and a redaction fix that covered some sinks and not others.
   Fix the class at its chokepoint (redact once where replies leave `sendCommand`), not per sink.
3. **A guard that refuses must say what to do next.** Three different refusal sites carried three different
   texts; one lacked the recovery step. One shared constant removed the drift.

## Session Errors

- **The filing-justification hook blocked follow-up issues three times** (twice in the plan phase, once for
  #11168): once because the body file was written in the same Bash call as `gh issue create`, once
  because the filing named no user-visible consequence. Recovery: write the body with the Write tool as a
  separate step; label tooling findings `meta/machinery`. **Prevention:** write the body first, add
  `meta/machinery` for adapter/gate/probe findings, and never invent a `Fix-Size:` measurement to satisfy
  the hook.
- **The Bash/Write tools unescape `\uXXXX` in input**, which landed raw U+2028/U+2029/U+0085 bytes in a test
  and a module. Recovery: build such regexes from ASCII pieces with Python `chr(92)` and confirm with
  `grep -nP '[\x{2028}\x{2029}\x{0085}]'`. **Prevention:** after any edit that mentions a Unicode
  separator, run that grep before committing.
- **`technical-ruling-gate.sh` rejected rows R6-R12 as `bad-ruling-shape`.** Recovery: one batched CTO
  spawn rewrote the Ruling cells. **Prevention:** write each ruling as a decision sentence with its
  reason, not as a heading or a question.
- **`lint-shell-trace-credential-refusal --changed` flagged `check_deps.sh` and `engine-contract-probe.sh`.**
  Recovery: the canonical xtrace refusal block. **Prevention:** any new shell script that reads
  `PENCIL_CLI_KEY` starts with that block.
- **The stub integration `afterAll` hit bun's 5 s hook timeout** while closing sessions and removing the
  tree. Recovery: 60 s timeout and parallel session close. **Prevention:** give every `afterAll` that
  closes subprocesses an explicit timeout.
- **The affected-tests gate sat queued behind sibling runs and my stale queued processes would have raced
  later edits.** Recovery: killed my own queued runs. **Prevention:** run the gate detached, read its rc
  file, and do not edit while it runs.
- **I said 13 review seats were spawned when 12 were.** Recovery: counted the returned reports before
  recording the tally. **Prevention:** record the tally from the number of reports received.
- **A hook blocked `pgrep -f`** (self-matching). Recovery: `pgrep <name>` without `-f`.
  **Prevention:** use the name form or `scripts/lib/proc.sh`.

## Tags
category: bug-fixes
module: pencil-setup
