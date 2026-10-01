---
title: "A counter named for a cause measured a gap that every outage produced"
date: 2026-09-28
category: logic-errors
module: apps/web-platform/infra (registry zot liveness feeder, web zot consumer probe)
tags: [observability, heartbeat, counters, test-stubs, curl, user-data-budget, review]
issue: 7270
---

# A counter named for a cause measured a gap that every outage produced

## Problem

Two observability fixes on the zot image-pull path (#7262, #7270):

- The web consumer probe mislabelled every private-network outage as `unexpected code 000000`.
  `curl -w '%{http_code}'` prints `000` and exits non-zero on a transport failure, so the
  `|| echo 000` fallback appended a second `000`. All 10 production SUPPRESS rows from 08-13 to
  09-28 read `000000`, so the `000)` UNREACHABLE arm had never fired.
- The registry's liveness feeder withheld a Better Stack beat when zot did not answer, and
  recorded nothing about why.

The fix for the second added per-boot counters to the feeder (tmpfs). The 5-minute
`SOLEUR_ZOT_DISK` row carries them as `liveness_*` fields. One of them, `late_ok_cum`, was meant
to isolate *timer lateness*. As first written it counted any successful beat more than 75 s after
the previous successful beat. That is an OK-to-OK gap, and **every outage produces one**. The first
good beat after a miss or a failed ping always crossed 75 s. So the runbook's decision table
("`late_ok` rose, `miss` and `ping_fail` flat → timer margin") pointed the operator at the timer
whenever the outage and the recovery fell in different 5-minute rows.

The plan asserted that semantics, the decision table asserted it, and the suite had a row for
"100 s gap counts late". Nothing ran the sequence outage → recovery. Two review seats (observability
and structural) reproduced the mismatch independently with a simulation of the feeder's own logic.

## Solution

- **Probe:** normalise exactly `000000` → `000`, and keep `|| echo 000` so an HTTP code followed
  by a curl failure (`404000` under an injected `-f`) still lands in the catch-all. The RED row
  runs the real probe against `127.0.0.1:1`.
- **Counter semantics:** the feeder clears `last_ok_ts` on any miss or failed ping. `late_ok_cum`
  then counts only a beat more than 75 s after the previous good one, with nothing failing in
  between, which is the only case the timer (or a slow probe) explains.
- **Tests:** rows for 70 s (not late), 80 s (late), a miss then an OK beat with a 500 s-old
  previous OK (not late), and a failed ping clearing `last_ok_ts`.

## Key Insight

A counter named for a CAUSE must be defined by the predicate that isolates that cause, and that
includes resetting on every competing cause. Write the decision table against a simulated
SEQUENCE, not a single event. The table row "X rose, others flat → cause C" is only true if no
other cause can move X on a later row.

Two companions from the same PR:

- **A test stub that returns an EXIT CODE where the real dependency returns an HTTP STATUS makes
  the flags that translate one into the other untestable.** The heartbeat stub returned
  `STUB_PING_RC`. Deleting `-f` from the beat (real curl then exits 0 on a 429, so a refused beat
  counts as sent) survived at full green. The suite's own header forbids exactly this ("THE FIXTURE
  MODELS HTTP STATUS CODES, NOT curl EXIT CODES"), and the new rows still did it. The fix is to
  make the stub answer a status and honour `-f`, which the existing `respond` helper already did
  for the probe target.
- **A budget at single-digit-percent slack shapes the design, not just the size.** The first
  key=value state revision measured 21,292 B stored against `REGISTRY_GZIP_BUDGET` 21,000, and
  ADR-185's amendment forbids raising the constant again. A single positional line of six fields,
  validated in one loop, came to 20,924 B (20,932 B after review fixes). Positional formats need a
  writer/reader order pin, since both parsers otherwise drift independently.

## Session Errors

1. **Epoch seconds rejected by a 9-digit field regex.** `rd()` accepted `[0-9]{1,9}`, so a
   10-digit `last_ok_ts` read as empty and `late_ok_cum` never counted. Recovery: the L5 row went
   RED; widened to `{1,10}`. **Prevention:** size every integer-shape regex from the largest value
   the writer can emit (epoch ≈ 10 digits), and fixture that value.
2. **A `sed -i` fix replaced a whole line with its placeholder `XX`.** Recovery: re-applied with
   the Edit tool. **Prevention:** use the Edit tool (or a Python `str.replace` with a count
   assertion) for edits whose pattern contains regex metacharacters; `sed` quoting of `\{`, `$`,
   and `\(` inside a double-quoted template line is error-prone.
3. **First state format blew the user_data budget (21,292 B > 21,000 B).** Recovery: repositioned
   to a one-line positional format. **Prevention:** run `registry-userdata-budget.sh --json`
   right after the first GREEN on any `cloud-init-registry.yml` change, before writing more tests
   against a format that may have to change.
4. **`sleep 60` and `pgrep -f` blocked by hooks.** Recovery: background waits, and transcript
   `end_turn` polling. **Prevention:** already hook-enforced; use Monitor or `run_in_background`.
5. **A scripted plan edit asserted on a dummy replacement pair and aborted.** Nothing was written.
   Recovery: dropped the dummy pair. **Prevention:** batch-edit scripts assert per pair (they did);
   treat an aborted batch as un-applied and re-run.
6. **The research scratchpad said "82 further incidents" after 08-05T02:33Z; the API said 99.**
   A first issue comment also said "6 boots" where the current count was 7. Recovery: re-pulled
   the Uptime API before posting, and edited the comment. **Prevention:** re-measure every number
   copied from a research brief before it goes into an issue comment.
7. **The repo-research agent claimed the probe script is not baked into the web image.** It is
   (`Dockerfile`, `host_script_files`). Recovery: grepped the Dockerfile. **Prevention:** verify
   agent claims about delivery paths with one grep before building on them.
8. **`git stash list` in a command was blocked by a hook.** Recovery: dropped it. **Prevention:**
   already hook-enforced (`hr-never-git-stash-in-worktrees`).
9. **The code-quality review seat never returned a report** (over 30 min, and no response to a
   prompt to write it). Recovery: proceeded with 6 of 8 seats and disclosed the degraded coverage
   in the review trailer. **Prevention:** already covered by review/SKILL.md's file-delivery
   mandate. The seat had it and still produced nothing, so a spawn-time deadline is the next lever.
10. **`late_ok_cum` measured an OK-to-OK gap, not timer lateness** (this learning). Recovery: reset
    on miss/failure plus sequence rows. **Prevention:** route-to-definition bullet in
    `plan-sharp-edges.md` (below).
11. **The heartbeat stub modelled an exit code, not an HTTP status.** Deleting `-f` survived.
    Recovery: the stub answers a status and honours `-f`, plus a 429 row. **Prevention:** existing
    guidance (work/SKILL.md "A PATH-shimmed fake…"); the suite header already says it. The miss was
    in new rows added below a header that forbade it, so read the suite's own header before
    adding stubs to it.
12. **`lint-shell-trace-credential-refusal --changed` flagged the touched probe.** CI runs the
    `--changed` form, which bypasses baselines for touched files. Recovery: added the xtrace
    refusal and `--disable --noproxy '*'`, then removed the probe from both baselines.
    **Prevention:** work/SKILL.md Phase 0.5 §6.5 already says to run it at Phase 0 for baselined
    files. Run it then, not at the end.
13. **A raw-template assert first wrote `\\$\\$[{]` inside an eval'd double-quoted string**,
    which bash can read as `$[ … ]` arithmetic. Recovery: moved the sed programs into
    single-quoted literals on their own line and compared counts. **Prevention:** never put sed
    programs containing `$` inside the double-quoted condition string of an eval'd `assert`.
14. **The liveness case floor lagged the case count (92 vs 103) after new rows.** Recovery:
    raised it in the same commit. **Prevention:** existing rule (raise the floor in the same edit
    that adds the row).

## Tags

category: logic-errors
module: apps/web-platform/infra
