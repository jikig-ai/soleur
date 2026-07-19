---
module: web-platform / cron-gh-pages-cert-reissue
date: 2026-07-19
problem_type: logic_error
component: inngest_routine
symptoms:
  - "Multi-agent review found 7 defects in an implementation whose full test suite was green"
  - "A wall-clock break inside an Inngest gate loop terminates a healthy run as dns_propagation_failed on replay"
  - "A follow-through sweeper change would have reopened 3 legitimately-closed issues at the next sweep"
root_cause: wrong_assumption
severity: high
tags:
  - inngest
  - replay-safety
  - multi-agent-review
  - plan-premise-falsification
  - fail-open
  - mutation-testing
issue: 6698
synced_to: [review, plan]
---

# A wall-clock break in a replayed body, and a plan premise that would have overridden the operator

## Problem

#6698 made `cron-gh-pages-cert-reissue` diagnosable: step-level markers, a
DNS-propagation gate, a probe-only mode, and a follow-through-sweeper reopen
path. Implementation reached **192/192 suites green, `tsc` clean, semgrep 0
findings, shellcheck clean** — and then an 11-agent review found **seven
defects**, two of them cases where a *plan-prescribed design was itself wrong*.

The green suite was not lying. Every defect lived in a place tests structurally
could not reach: replay behavior the fake step never simulates, a third-party
payload shape no fixture modelled, a middleware projection nothing asserted, and
a bash gate no test ever drove.

## The two that mattered most

### 1. A wall-clock break inside a replayed Inngest body is a REPLAY HAZARD, not a safety bound

The gate loop carried what looked like a prudent ceiling:

```ts
// WRONG — elapsed() is Date.now() evaluated in the BODY
if (elapsed() + DNS_GATE_INTERVAL_MS >= TOTAL_DNS_ONLY_WINDOW_MS) break;
```

Inngest re-executes the function body from the top on every resume and returns
memoized results for completed steps. So on a resume **after the poll had burned
~12 minutes**:

1. `dns-gate-0` returns its memoized `retry`.
2. `elapsed()` is now ~870 s, so the wall-clock break fires.
3. The loop exits with `verdict = retry` — never reaching `dns-gate-1`, which had
   already memoized `propagated`.
4. The run terminates `dns_propagation_failed` with `attempts: 0`, **paging**,
   while 12 recorded `poll` markers sit in the marker stream contradicting it.

The entire diagnostic payload the work exists to capture — final cert state, poll
count, state trajectory — is destroyed, on precisely the slow remediation anyone
runs the routine to understand. `ADR-077` already bans `Date.now()`-derived
control flow in the replayed body; the file's own comment 226 lines above warned
that "`Date.now()` in the body would re-stamp on every resume", and the code
committed the error anyway.

**The fix is deletion, not correction.** The fixed attempt count already bounds
the loop. The window is budgeted by *constants*; a runtime measurement cannot
make it a guarantee, only a nondeterminism.

**Two agents disagreed about this line and both were partly right.**
`code-simplicity-reviewer` called it dead code (it can never fire on the original
pass). `architecture-strategist` proved it *can* fire on a replay. Dead on the
happy path and harmful on the replay path is strictly worse than either alone.

### 2. The review's own recommendation would have replicated the bug

`performance-oracle` independently found the window undercount and recommended:

> The gate loop does guard on real time [...] the poll loop runs its fixed 13
> iterations regardless. The asymmetry is the bug; the fix is one line mirroring
> what's already there: `if (elapsed() + POLL_INTERVAL_MS >= MAX_DNS_ONLY_WINDOW_MS) break;`

That is the *same construct*, moved into the poll loop, where it would corrupt
the run identically. The correct resolution was to accept performance-oracle's
**diagnosis** (the constant undercounts the real window) and reject its
**prescription** (measure at runtime) — folding a nominal IO allowance into the
budget instead and stating plainly in the ADR that it *bounds* rather than
*guarantees*.

**Agent convergence is not proof, and a plausible prescription from a correct
diagnosis is still wrong.** The tiebreaker was mechanical verification —
`node_modules/inngest/types.d.ts` and `ADR-077`'s literal text — not a vote.

### 3. A plan premise that would have overridden the operator that night

The plan mandated bypassing the follow-through sweeper's `earliest` gate for
closed issues, reasoning that "a closed follow-through is already asserting
*verified*, so its predicate should be evaluated immediately."

That misreads what exit 1 means to a soak probe:

```bash
# scripts/followthroughs/workspaces-luks-soak-6604.sh
#   1 = FAIL       (still soaking, OR "SOAK PASSED — wipe authorized" but not yet observed complete)
echo "FAIL: still soaking — ... The internal floor (DP-5) refuses a day-0 PASS regardless of the directive earliest=."
```

Probes use exit 1 for **"not done yet"**, not **"closed prematurely"**. With the
gate bypassed, every legitimately-closed-but-still-soaking issue reads as
premature and gets reopened. Measured against live data the same day: **#6604
(`earliest=07-25`), #6416 (`07-22`) and #6462 (`07-29`)** were all closed
`COMPLETED` with a future `earliest` — all three would have been reopened at the
18:00 UTC sweep, overriding deliberate operator closures.

**And the bypass was unnecessary.** Its stated motivation was that #6657 (closed
07-18, `earliest=07-25`) would "leave the query window before its own earliest
elapsed" — true only for a recency window shorter than the ~7-day gap. The
implementation chose `CLOSED_LOOKBACK_DAYS=14`, so #6657 stays a candidate until
08-01 and is evaluated from 07-25 with the gate fully intact. **The plan's
premise was falsified by a parameter the implementation itself picked**, and
nobody re-checked the premise against the chosen value.

## The other four

| Defect | Why tests could not see it |
| --- | --- |
| `onFailure` reads the **envelope**, not the wrapped event — inngest triggers it as a separate function whose payload is `{data:{function_id, run_id, error, event: <original>}}`. `probeOnly` fell back to its safe default, recording an operator's explicit `probeOnly:false` remediation as a **probe**, and `runId` pointed at the failure handler's run so markers were un-joinable to the run they describe. | Every `onFailure` test passed `event: {}` — a shape production never produces. |
| `ReissueResult` lacked `ok`/`errorSummary`, the **only** two fields `run-log.ts` projects off a handler return. A probe, an `issued` remediation and a paging `dns_propagation_failed` all wrote identical `status='completed', error_summary=null` WORM rows — while a code comment asserted the opposite. | Nothing asserted the middleware projection; the comment read as verification. |
| Gate budget (2 min) was **shorter than the TTL it waits on** (Cloudflare's proxied TTL is a fixed, non-editable 300 s), making the paging outcome the *default* result of a correct remediation. | Arithmetic was internally consistent; only an external fact falsifies it. |
| `resolve6` coalesced **every** error code to `[]`, so `ETIMEOUT` read identically to a genuine `ENODATA` — a resolver timeout green-lit exactly the AAAA state the gate exists to catch. | Fixtures only ever used `ENODATA` or `null`. |

Plus a structural one: `SWEEPER_PASS_HEADING` was **read but never written** — the
producer emitted the heading as a bare literal. Reword the producer and the guard
silently stops recognising its own output while the constant, the consumer and
the test fixture stay mutually consistent and green.

## Key Insight

**A green suite bounds the defects tests can express, not the defects present.**
Every one of these seven lived in a seam a test cannot reach by construction:

- **Replay** — a fake step that runs each callback once cannot model memoization.
- **Third-party payload shape** — a fixture invented by the same author who
  misread the contract encodes the same misreading.
- **Middleware projection** — the consumer is another module; a return value that
  is never read is indistinguishable from one that is.
- **External constants** — a budget can be arithmetically perfect and still be
  shorter than the physical thing it waits on.
- **Error-code collapse** — "could not ask" and "the answer is empty" are the
  same value unless you keep them apart deliberately.

The corollary for plans: **a plan's stated premise is a claim to re-verify
against the values the implementation actually chose.** The `earliest`-bypass
premise was true when written and false by the time `CLOSED_LOOKBACK_DAYS=14` was
picked — and no gate re-checked it, because re-checking a premise you inherited
is not a step anyone thinks to schedule.

## Prevention

- **Grep any Inngest routine body for `Date.now()`-derived control flow.** Inside
  a `step.run` callback it is fine (memoized once). In the orchestrating body it
  re-evaluates on every resume, and any `break`/`if` keyed on it produces a
  different execution path than the one whose step results are memoized.
- **When a probe's exit code drives an automated state mutation, read the
  probe's documented exit semantics first.** Exit 1 means "the assertion did not
  hold" — which is *not* the same as "the thing being asserted was closed
  prematurely."
- **When a handler's return value is consumed by middleware, assert the
  projection.** Grep the middleware for what it actually reads; a comment
  claiming a field "lands in X" is a claim, not a wiring.
- **A constant that is read but never written is a producer/consumer split.**
  `grep -c` the constant name: one declaration + one consumer and zero producers
  means the literal is duplicated somewhere.
- **Mutation-test every new guard, and mutate a *sandbox copy*.** A 4-space-indent
  `return` bypassing the post-toggle restore passed **94/94** until the AC9 anchor
  was widened from `/^ {2}return/` to `/^ {2,4}return/`. Both anchors "held"; the
  violation lived in the gap between them.
- **Run new webplat tests CI-equivalent (no Doppler) at least once.** A test
  importing anything under `server/inngest/` throws `INNGEST_SIGNING_KEY missing
  at startup` at *collection* without a hoisted `NEXT_PHASE` guard. `doppler run`
  injects the key and masks it into a CI-only red.

## Session Errors

> The session error inventory had 19 items. Eight of them — the review-caught
> defects (wall-clock replay hazard, gate budget vs TTL, `onFailure` envelope,
> `routine_runs` projection, sweeper earliest-bypass, `resolve6` fail-open,
> PASS-heading producer/consumer split, and the poll-loop prescription that would
> have replicated the first) — are the **subject of this document** and are
> written up in full above rather than repeated as bullets here. The eleven below
> are the process/tooling errors, which have no other home.

1. **Plan-phase `Write` blocked by the main-checkout guard hook.** Recovery: rewrote to the worktree path. **Prevention:** working as designed — the hook caught a real boundary violation.
2. **Plan-phase UI-wireframe gate false-positived.** Recovery: re-checked against the Files lists; the globs appeared only in the plan's *negative* statement. **Prevention:** the gate's glob match should exclude negated prose contexts, or the check should read the Files lists directly rather than the whole plan body.
3. **pino mocked as `importOriginal<typeof import("pino")>()` → TS2339.** Recovery: pino ships CJS (`export =`), so the namespace's interop `default` is what the import binds; typed it loosely. **Prevention:** when partial-mocking a CJS dependency, type the namespace as `Record<string, unknown>` and read `.default` rather than assuming an ESM shape.
4. **AC9 structural test counted `return` inside step callbacks (3, not 1).** Recovery: anchored on the function-exit indentation. **Prevention:** an indentation-anchored source assertion needs both a lower and an upper bound — see the mutation-testing note above, where the *corrected* anchor still had a blind band.
5. **`export GH_TOKEN` placed inside a `$(...)`-captured helper.** Recovery: moved the export into the subshell that sources the SUT. **Prevention:** a helper whose output is captured by command substitution runs in a subshell; its exports cannot reach the caller.
6. **Ran `scripts/sweep-followthroughs.test.sh` from `apps/web-platform`.** Recovery: re-ran from the worktree root. **Prevention:** the Bash tool does not persist CWD across calls — chain `cd <root> && <cmd>` in one call.
7. **My own gate edit silently dropped `if (verdict.status !== "retry") break;`.** Recovery: tests went red and named it. **Prevention:** when an Edit's `old_string` spans a control-flow statement plus its comment, re-read the replacement for statements the new text omits.
8. **A `probeOnly` removal regex also stripped it from inside `emitAndReturn`.** Recovery: `tsc` caught it; re-added. **Prevention:** scope a mechanical `re.sub` to the construction sites (anchor on surrounding context) rather than the bare field pattern.
9. **`DNS_GATE_MAX_ATTEMPTS = 10` gave 270 s < the 300 s TTL.** Recovery: the assertion written moments earlier caught it; bumped to 11. **Prevention:** working as designed — this is the value of asserting an external fact rather than internal consistency.
10. **`test-all.sh` exceeded the 10-minute Bash cap.** Recovery: re-ran detached and polled with `Monitor`. **Prevention:** for the full suite, start detached and monitor from the outset rather than discovering the cap.
11. **QA test failed collection with `INNGEST_SIGNING_KEY missing at startup`.** Recovery: added the hoisted `NEXT_PHASE` guard. **Prevention:** see the CI-equivalent-run note above; this is already documented in `work/SKILL.md` and was reinforced by a live hit.

## Related

- `ADR-077` — routine replay-safety contract (the rule this violated)
- `ADR-125` — the cert-reissue decision this work amends
- `knowledge-base/project/learnings/2026-07-16-a-mutation-battery-only-covers-what-you-mutate.md`
- `knowledge-base/project/learnings/2026-07-15-a-guard-that-never-ran-has-more-than-one-reason-and-indexof-block-scoping-swallows-siblings.md`
- #6698, #6657, #6703
