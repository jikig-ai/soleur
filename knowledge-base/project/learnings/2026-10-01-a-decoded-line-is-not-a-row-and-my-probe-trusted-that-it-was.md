---
title: "A decoded line is not one row from one emitter — my probe's gates were pinned, forgeable and un-anchored to the boot"
date: 2026-10-01
category: test-failures
tags: [followthrough-probe, betterstack, row-identity, forgery, decode, guard-vacuity, mutation-battery, python-in-bash]
issue: 7556
pr: 9353
branch: feat-one-shot-7556-zot-ceiling-probe-selector
---

# Learning: a decoded line is not one row from one emitter

## Problem

The #7556 follow-through probe returned `too-few-samples patch_rows=2` on every sweep since 2026-08-21. Cause: the sample floor counted the zot handler name `PatchBlobUpload`, which appears only on error lines and on the disk heartbeat's echo of a stale error, never on a successful upload row (real week: 44 PATCH uploads). The first fix (re-select the PATCH HTTP-API rows, pin them to the envelope, one python classifier) passed a 71-case harness and a 20-row mutation battery, and a ten-seat review then found it still certified narrower than its name:

- DELIVERY (`configuration settings`, the causal evidence that auto-closes the tracker) was the one signal read without the envelope pin. A real webhook row quoting that text already sat in the live warehouse; a newer one flipped a host still on 60 s to PASS.
- `jq -r` re-emits an embedded newline as a row break, so one webhook message carrying twelve forged envelope lines satisfied the sample floor, the coverage anchor and the drop read.
- `statusCode`/`latency` sit AFTER client-controlled `path`/`username`, so a client could forge a 5xx (false FAIL) or mask its own 30-minute cut.
- The drop guard's empty answer reads as "no drops", and it accounted for none of the rows it fetched.
- The 7-day window was never tied to the boot that carries the deadlines; the trailing edge (shipper/warehouse outage) was unobserved; a refused 401 PATCH counted as an upload.

## Solution

One python decoder emits exactly one sanitized line per row (line breaks neutralised) and counts undecodable rows; every signal is pinned to its emitter's envelope at offset 0 AND to its row shape; a row whose server fields repeat is unparseable (TRANSIENT), never counted; exact-duplicate rows count once; the floor counts PATCH 2xx; every zot start inside the window must carry the deadlines (30-day config lookback so a long-lived host does not wedge); heartbeats must exist at BOTH ends of the window; the drop read accounts for every fetched row. 135 harness cases; a 39-mutant battery, 39/39 killed (one survivor, a fixture gap on the row-shape check, closed by a User-Agent-forged config fixture).

## Key Insight

For any probe over a SHARED log source, the unit of trust is not "a decoded line". Ask three questions of every count the verdict reads: which emitter can write this exact text (envelope + shape pin at offset 0; an envelope pin does NOT imply a shape pin, because a client-influenced field inside a correctly-pinned row can quote the signal), can one message become several rows (decode to one line per row), and which fields of the row does a client control before the fields I parse (count server fields once). The author's own battery cannot find these: every row perturbs the SUT and is scored through fixtures whose population the author chose. What found them was a security seat that BUILT the forged inputs against the pristine probe, a structural-enumeration seat that mapped every path to each count, and the test-design seat that mutated the harness's own matchers (neutering `expect()`'s substring check survived the whole suite until a known-negative control was added).

## Session Errors

1. **Trusted a decoded line to be a row (and a config line to be a config row).** Recovery: single decoder, envelope + shape pins, count-once. **Prevention:** ask the three questions above before the first fixture is written; fixture one forged row per question.
2. **Embedded a python program in a bash single-quoted string with doubled backslashes** (`"\\n"` writes a literal backslash-n; `\\r\\n` in a regex class is the wrong escape level). Caught by reading before running. **Prevention:** run each embedded program once on a known input before wiring it; inside bash single quotes write the python escape exactly as python expects (`"\n"`).
3. **My 20-row mutation battery reported all-killed while ten escape shapes were live.** **Prevention:** add escape rows (feed the PRISTINE guard a corpus it must refuse) and mutate the harness helpers' own decisions (`expect`, `expect_not`) with a known-negative control; a battery's all-killed is a sentence about its rows.
4. **Three fixture mistakes in the rewritten harness** (a duplicate case expecting the wrong count, an undecodable drop row filtered out by the stub's own needle, a path-forged row that is now correctly unparseable). One-off; caught on the first run.
5. **Environment friction:** a Bash call rejected by the process-pattern self-match hook (the whole command is lost, and a commit message or learning text that merely NAMES the blocked tool trips it too), two commands moved to the background at the 120 s ceiling, `lefthook` absent on every commit. Already hook-enforced or environmental. **Prevention:** write prose that names a blocked command with the Write tool, not inside a Bash heredoc.
6. **Stop-hook "unkept promise" twice** — closing text named a next action while waiting on background work. **Prevention:** end a wait with an explicit `<stop>BLOCKED: ...</stop>` naming what it waits on.
