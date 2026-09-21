---
title: "curl's retry flags turned a throttled emit into rc 0, and every P1 was a stub looser than the code it stood in for"
date: 2026-09-21
category: integration-issues
module: apps/web-platform/infra (cloud-init-inngest.yml soleur-boot-emit), scripts/followthroughs/zot-soak-6122.sh
tags: [curl, retry, sentry, test-stubs, mutation-testing, guard-vacuity-floor, soak, inngest]
issue: 6500
pr: 8488
---

# Learning: curl retry flags and stubs looser than the code

## Problem

#6500 added a host-local Sentry `soleur-boot-emit` to the dedicated inngest host so the zot soak
(the gate that authorizes the irreversible GHCR PAT revoke) can see that host's pull outcome.
The plan prescribed `curl -sf --connect-timeout 5 --max-time 8 --retry 1 --retry-max-time 15` and
claimed "about 16 s worst case". The author's own batteries reported 44 mutants killed.

A 10-seat review then found:

- **The curl flags lied in the reassuring direction.** With `--retry-max-time`, a 429 whose
  `Retry-After` exceeds the remaining budget makes curl DECLINE the retry and exit **0**, even with
  `-f` (measured, curl 8.22.0: `Retry-After: 60` gives rc=0 in 55 ms). An undelivered event reads
  as delivered and no `sentry-emit-FAILED` fires. The worst-case bound was also wrong: 8 + 1 + 8 s
  for curl plus the 8 s failure phone-home, not 16 s.
- **Three P1s, all in the tests, none in the product code.** Each stub or extractor matched MORE
  LOOSELY than the production check it stood in for:
  1. the soak's Sentry stub matched keys as URL substrings, so widening the host-pinned query
     (`… host_name:"soleur-inngest" OR stage:"inngest_zot"`) still answered and the suite stayed green;
  2. the per-arm awk extractor split on ANY `else`/`fi`, so a nested `if/else` in the served arm
     let a planted call satisfy "the missed arm emits";
  3. the curl stub exited with a configured rc regardless of flags, so dropping `-f` (an HTTP 403
     then exits 0) was invisible.

## Solution

- Emitter: no `--retry` at all (`curl -q -K - -sf --connect-timeout 5 --max-time 8`); a 429 now
  exits 22 and phones home. STAGE/LEVEL/DETAIL all reduced to a JSON-safe charset.
- Stubs: the curl stub models `-f` (`EC_HTTP` >= 400 exits 22 only when `-f` is in argv); the soak
  stub is keyed on the whole encoded clause AND an exact decoded-query assertion; unmatched keys
  are logged and fail the row; the extractor tracks nesting depth and skips heredoc bodies.
- Floors: literal adjacent to its `if`, `[FATAL] anti-vacuity floor: only N …` sentinel on stderr,
  a counter the meta-guard can zero. A suite in a deferred directory gets a floor only with a
  `PROMOTED_FILES` entry in `scripts/guard-vacuity-floor.test.sh`, never a raised ratchet.

## Key Insight

A retry flag can turn a failure into a success. When a plan prescribes transport flags for a
signal whose ABSENCE is the alarm, measure each flag's effect on the exit code against a server
that throttles, stalls and rejects, before writing the bound down. And when a mutation battery
reports all-killed, audit the stubs before the code: the question is "does this stub accept
anything the production check would refuse?". A stub that answers too generously makes every
mutant on that axis invisible, and no mutation of the SUT can reach it.

## Session Errors

1. **The brief's premise was stale** (it described an unconditional `v1.1.19` pin; #7516 had
   shipped the zot path in August). Recovery: the collision gate's `#N in:body` probe surfaced #7516;
   measured and narrowed scope with the operator. **Prevention:** already enforced by one-shot
   Step 0a.5's body-text probe. It worked as designed; keep running it on every `#N` input.
2. **Doppler failed with a locked system keyring**, so there was no live Better Stack read.
   Recovery: live verification moved to post-merge PM2. **Prevention:** one-off, local machine state.
3. **A standalone extraction of a follow-through probe died rc 127**: it sources `../lib`.
   Recovery: `git archive origin/main scripts | tar -x`. **Prevention:** extract the probe's whole
   `scripts/` tree, never the single file.
4. **The `scripts` shard queued for up to 3600 s** behind a sibling session's advisory lock.
   Recovery: relaunched detached with `TC_LOCK_TIMEOUT=5`, which proceeds under a
   `LOCK_CONTENDED_PROCEEDING` banner. **Prevention:** under known sibling contention, launch with a
   short `TC_LOCK_TIMEOUT` and triage any RED individually. Kill by `/proc/<pid>/cwd`, and expect
   that to include your own `bash -c` wrapper.
5. **An anchored replace garbled a message** (a doubled `),`) because the replacement's head
   duplicated text preceding the anchor. Recovery: read back and fixed. **Prevention:** anchor the
   replace on the whole sentence, not its tail.
6. **Hand-counted anti-vacuity floors were wrong twice** (11 vs 10, 31 vs 29). Recovery: the runs
   reported it. **Prevention:** set a floor from a green run's measured count, never from a tally.
7. **`guard-vacuity-floor` rejected the new floor.** The deferred ledger grew 47 to 48, and the
   mutant could not be constructed (snapshot variables bound far above, no sentinel). Recovery:
   reshaped to the meta-guard's contract and promoted the file. **Prevention:** before adding a floor
   to a suite under `apps/web-platform/infra/`, read the `PROMOTED_FILES` block header in
   `scripts/guard-vacuity-floor.test.sh` and run that guard.
8. **actionlint's exit code was read through `| tail`**, so the rc reported was tail's.
   Recovery: re-ran with `rc=$?` on its own line. **Prevention:** already a documented rule;
   `cmd > log; rc=$?` then read the log.
9. **Three P1s in the stubs and extractor, plus the curl flags taken unmeasured from the plan.**
   Recovery: see Solution. **Prevention:** routed to `plan-sharp-edges.md` (measure transport flags
   against a throttling server). For stubs, see Key Insight.
10. **Four harness bugs in the first test-section draft** (a counter decrement inside a subshell,
    blocking stdin, a newline DSN the reader cannot see, a sourcing fixture with an unterminated
    quote that could never execute). Recovery: caught on review before the first run.
    **Prevention:** give every `$(...)`-called helper a `</dev/null` and no counter side effects.
11. **The generated `model.likec4.json` conflicted with main.** Recovery: `merge-tree` before the
    panel, take theirs, regenerate. **Prevention:** already in review/SKILL.md §1.
12. **Forwarded from planning:** the brief named `apply_target=inngest-host` as the rollout path,
    but that target aborts on `server_touched`. Recovery: the plan corrected it to
    `inngest-host-replace`. **Prevention:** grep the workflow for the job's own refusal branch before
    prescribing a dispatch target.

## Related

- The web (`soleur-host-bootstrap.sh`) and git-data (`cloud-init-git-data.yml`) emitters use
  `--retry` WITHOUT `--retry-max-time`. They do not false-succeed (Retry-After 2 gives rc 22), but a
  long Retry-After makes curl sleep past `-m` (measured: hung to the 60 s outer timeout). Filed
  separately as #8501; it is a different subsystem.
- `knowledge-base/project/learnings/test-failures/2026-09-02-my-fake-curl-put-the-seam-above-everything-the-vendor-validates.md`

## Tags
category: integration-issues
module: apps/web-platform/infra
