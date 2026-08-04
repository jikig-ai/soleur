---
title: "My A/B had the wrong baseline arm, so I shipped a 2.25x regression as a win"
date: 2026-08-03
category: best-practices
module: .claude/hooks/grep-rewrite.sh, scripts/rule-metrics-aggregate.sh
tags: [measurement, benchmarking, ab-testing, hooks, jq, argv-limit, test-vacuity, review, tdd]
severity: P1
issue: 7165
pr: 7167
---

# Learning: an A/B whose baseline arm is not the current behavior answers a different question

## Problem

PR #7167 replaces Claude Code's ugrep `grep` shim (which reached 9.5 GB RSS on a
21 kB file and froze a 31 GB desktop) with a prefixed `grep()` redefinition that
routes to GNU grep. Dropping ugrep's `--ignore-files` makes recursive greps
traverse far more files, so the design adds `--exclude-dir` for `node_modules`,
`dist` and `.next` to claw the cost back.

I measured that, carefully. Interleaved reps, stated noise floor, cold-cache rep
excluded, sign checked for physical plausibility. The result — ~3,600 ms without
the excludes vs ~590 ms with them, ~6.0x — was solid, and I even corrected the
plan's claimed 12.9x downward on the strength of it.

Then I wrote it up as evidence the change was fast.

**Both arms were the new implementation.** The comparison was
*new-without-excludes* vs *new-with-excludes*. Neither arm was the shim. So the
measurement answered "are the three excludes worth adding" (decisively yes) and
said nothing whatsoever about "is this faster than what we have today" — which is
the question the PR's performance claim was making.

`performance-oracle` ran the three-arm version:

| arm | median | range |
|---|---|---|
| **today** — ugrep `--ignore-files` | **243 ms** | [212, 321] |
| **new** — GNU grep + the three excludes | **548 ms** | [332, 611] |
| new — without the three excludes | 3,179 ms | [3001, 3541] |

Ranges disjoint. A **~2.25x regression**, and ~5.7x in a repo whose `.gitignore`
covers a heavy directory outside the three (this repo lists `target`, `_site/`,
`__pycache__`, `.venv`, `.terraform`, `coverage/`).

The stated *cause* was wrong too. At an **identical file set** GNU grep is 4.0x
slower than ugrep, ~1.9x of that being ugrep's threading. The dominant term is the
single-threaded-engine swap, not the `.gitignore` loss — so `spec.md`'s "losing
`--ignore-files` is the single accepted semantic delta, compensated by the three
excludes" was wrong in both halves.

## Root cause

Every rigor check I ran was a check on **precision**, and the defect was in
**reference**. Interleaving, noise floors, sign checks and rep counts all
interrogate *how well you measured the two things you chose*. None of them asks
*whether one of those two things is the status quo*.

The trap is structural, not careless: when you build a change in stages, the
natural A/B is stage-N vs stage-N+1, because that is the decision in front of you
("do the excludes earn their place?"). That is a legitimate question with a
legitimate answer. It just is not the question the PR body ends up claiming, and
the two get conflated because both are "the benchmark".

## Solution

Before reading any A/B, name the arms out loud and check one against reality:

> **Arm A is `<literal command>`. Arm B is `<literal command>`. Which one is what
> runs on `main` right now?**

If the answer is "neither", the measurement cannot support a claim about the
change — only about a choice *within* the change. Add the status-quo arm or
restate the claim.

Concretely, the arm that mattered had to invoke the real shim, not a
reconstruction of its flags:

```bash
# today (the actual shim), capped — never run the reproducer uncapped
( ulimit -v 2000000; timeout 30 env -i PATH=/usr/bin:/bin HOME="$HOME" bash -c \
  "cd '$D' && exec -a ugrep '$CLAUDE_BIN' -G --ignore-files --hidden $SHIM6 -rl NEEDLE ." )
```

The PR now documents the regression in ADR-162, `spec.md` and the hook header as
an accepted trade — it buys elimination of a desktop-freezing OOM, and both arms
are sub-second — rather than presenting it as a win.

## Key insight

**A benchmark has a subject and a referent. Rigor discipline protects the subject;
nothing protects the referent except naming it.** "Is the new thing configured
well?" and "is the new thing better than the old thing?" produce numbers of
identical shape, and the second is the one a PR body almost always claims.

The generalization beyond benchmarks: any comparison — a diff review, a parity
test, a drift guard, a regression suite — is only as meaningful as its baseline,
and the baseline is the part nobody re-derives because it feels like context
rather than data.

## Four more measurement traps from the same PR

### 1. `jq --arg` silently caps at `MAX_ARG_STRLEN`

`jq --arg new "$PREFIX$COMMAND"` passes the whole thing as one argv entry, which
hits Linux `MAX_ARG_STRLEN` (32 × PAGE_SIZE = 131072). Bisected to the byte at a
453-byte prefix: `453 + 130,619 = 131,072`. Every command at or above 130,619
bytes silently failed to rewrite — fail-open, so nothing broke; it just stopped
working, on exactly the heredoc-shaped calls most likely to be large.

Pass **constants** through argv and concatenate inside jq, so the limit is
structurally unreachable at any input size:

```bash
jq -c --arg pre "$SGR_PREFIX" \
  '{hookSpecificOutput:{hookEventName:"PreToolUse",
    updatedInput:(.tool_input | .command = ($pre + .command))}}'
```

**The verification harness hit the same limit.** My first check built the 200 kB
payload with `jq -nc --arg c "$BIG"` and reported `Argument list too long` — which
I briefly read as the fix not working. Build large fixtures through a **file**
(`jq -Rs '…' < cmd.txt`), or the harness inherits the defect it is testing.

### 2. Trusting an exit code instead of validating output bytes

The hook took jq's `|| OUT=""` as sufficient. A jq that exits **0** while emitting
garbage had its output printed verbatim as a hook envelope. Measured: a stub that
passed through the parse call and emitted junk only on the envelope call made the
hook print `not json at all` on stdout.

Worse, the fixture written for exactly this case was **vacuous** — the PATH stub
also broke the *earlier* parse call, so the hook exited upstream and never reached
the line under test. The test named the right defect and could not reach it.

Validate the bytes: `printf '%s' "$OUT" | jq -e . >/dev/null || OUT=""`.

### 3. A test suite with no assertion floor

Neutering `ok`/`bad`/`want` to no-ops printed `=== 0 passed, 0 failed ===` and
**exited 0**. The gate was `[[ "$FAIL" -eq 0 ]]`, which is satisfied by a suite
that asserted nothing. Same shape one line up: `command -v jq || { echo SKIP;
exit 0; }` reports success on any shard without jq.

Add a floor derived from a green run, as a floor (not equality, so adding an
assertion doesn't spuriously red), and make missing preconditions hard failures:

```bash
[[ "$PASS" -ge "$MIN_ASSERTIONS" ]] || { echo "FAIL: only $PASS ran — vacuous"; exit 1; }
```

### 4. A red probe that doesn't reproduce may be a broken fixture

Probing the aggregator's orphan gate, my synthetic row used `"schema_version":1`
where the consumer filters on `select(.schema == 1)`. The row was dropped before
the gate, the probe returned rc=0, and I briefly concluded the defect did not
exist. Generating the row through the **real emitter** (`emit_incident`) instead
of hand-writing the schema reproduced rc=5 immediately.

A non-reproducing RED is two hypotheses, not one: the defect is absent, **or** the
fixture never reached it. Prefer generating fixtures through the production
producer.

## Session Errors

**Benchmarked the wrong baseline arm (#16).** — Recovery: `performance-oracle`
ran the three-arm version; regression documented in ADR-162, `spec.md` and the
hook header. — **Prevention:** name both arms literally and check one against
`main` before reading any A/B; see Key insight above.

**Measured `--exclude=.env` correctly and concluded wrongly (#17).** I measured
that it also suppresses an *explicit* `grep KEY .env` (rc=1, silent) and rejected
it as harmful. A second reviewer inverted the premise: `.claude/settings.json`
**already denies** `Read(**/.env)`, so "no in-agent way to read `.env`" is the
declared posture, not a loss the flag introduces — and recursive grep was an
unguarded bypass of that deny. Adopted, with limits stated. — **Prevention:** when
a measurement rules an option out, state the *policy premise* the ruling rests on
and check it; a correct measurement can carry an inverted premise.

**Hook written before its tests (#15).** `test-design-reviewer` scored First(TDD)
5/10 on commit order. Mutation proof is strong evidence but is not the same
discipline, and it is applied *after* the shape of the code is fixed. —
**Prevention:** the `/work` TDD gate is explicit; RED first even when the unit
feels like a one-liner.

**Probes wrote 6 synthetic fault rows into the real incidents log (#18).** Running
the hook by hand without `INCIDENTS_REPO_ROOT` set wrote real
`hook-input-*` `hook_self_fault` rows, which feed
`summary.hook_input_fault_count` and an operator-facing stderr WARNING. This is
the same defect I flagged in the plan's own discoverability probe, which used an
undefined `$PAYLOAD` and manufactured a false `hook-input-unparseable` row. —
**Prevention:** any hand-probe of a telemetry-emitting component must sandbox the
sink (`INCIDENTS_REPO_ROOT=$(mktemp -d)`); otherwise the probe manufactures the
signal the operator is meant to trust.

**Prefix-extraction fixture used a marker with no `grep` substring (#3).** The
hook's gate correctly declined, `PREFIX` came back empty, and every behavioural
case reported "the shim wins" — which reads as a hook failure. — **Prevention:**
a fixture must satisfy the SUT's own entry gate; assert the extraction is
non-empty before the cases that depend on it (the committed suite now does).

**Re-derivation dropped the original's filter (#4) and split records by line
(#5).** Investigating 4 corpus exceptions, I re-ran without the `*grep*` gate
(212 false positives) and let `jq -r` unescape newlines so multi-line commands
split across records. — **Prevention:** a re-derivation must reproduce the
original's filters exactly; JSONL stays line-delimited until the last step.

**Token sweeps missed variant spellings (#9, #10).** `"18 hooks fire per Bash
call"` matched one site; the second said `"per Bash tool call"`. `s/ADR-158/…/g`
missed the bare `"to 158"` in the ordinal note. Both were caught only because the
edit scripts asserted an expected match count. — **Prevention:** assert
`s.count(old) == expected` before every scripted replacement; a sweep that
silently matches fewer sites than intended is indistinguishable from success.

**Verification harness inherited the defect under test (#8).** See trap 1.

**Aggregator RED probe used the wrong schema key (#6) and expanded `$PWD` after
`cd` (#7).** See trap 4. — **Prevention (#7):** capture `REPO=$PWD` before any
`cd` in the same compound command.

**Background full-suite runs died twice (#11) and the monitor timed out (#12).**
`nohup` inside the Bash tool did not survive; the relaunch queued behind up to 10
sibling `test-all.sh` runs with `/tmp` at 87%, tripping both `LOW_TMP_HEADROOM`
and `SIBLING_RUN_DETECTED`. — **Prevention:** use the harness-tracked
`run_in_background` rather than `nohup`, and treat both contention banners as
"this result is not evidence either way" rather than re-running into the same wall.

**`security-sentinel` died on an API session limit (#13).** On a diff with a
credential-exposure dimension this is not a neutral gap. Its unfinished probe
(prefix vs hostile command shapes) was run inline instead: 16 shapes, 15 inert,
the one difference being a bash line number on input that is a syntax error in
both arms. — **Prevention:** record degraded coverage explicitly (`10 of 11`) in
the summary and the review trailer; never let a partial panel report as full.

**Push rejected after rebase (#2), byte-comparison off by a `jq -r` newline (#14),
plan path resolved from the wrong root (#1).** One-offs. — **Prevention:** none
warranted.

## Related

- ADR-162 — PreToolUse hooks may rewrite tool input, under a single-rewriter invariant
- `knowledge-base/project/learnings/2026-08-02-ps-named-it-2-1-220-so-a-grep-that-ate-the-box-read-as-a-claude-leak.md` — the ugrep OOM and three refuted cost models
- `knowledge-base/project/learnings/2026-07-27-my-ab-could-not-resolve-the-effect-i-concluded-from-it.md` — the sibling failure: an A/B with the *right* arms and insufficient power. Together they cover both halves — that one is about resolution, this one is about reference.
