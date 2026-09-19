---
module: cron-compound-promote outcome marker (server/compound-promote-marker.ts)
date: 2026-09-19
problem_type: test_failure
component: testing_framework
symptoms:
  - "New 3-test suite for the #8281 marker fix stayed 13/13 green with the default sink bound to `console` — the production defect verbatim"
  - "Re-adding the Inngest ctx logger as a SECOND argument at all seven call sites also stayed green"
  - "The author's console-sink mutation battery reported 2/3 kills — it mutated the sibling export the test read, not the default-parameter binding the emitter used"
  - "A second emitter (SOLEUR_RUN_REPORT_SWEEP) had the identical defect and its runbook decode had matched nothing on every live fire since it was written"
root_cause: test_isolation
resolution_type: test_fix
severity: high
tags: [test-seams, default-parameter, dependency-injection, mutation-testing, false-green, pino, inngest, ctx-logger, marker-shape, instance-vs-class]
synced_to: [review]
---

# My fix for the unpinned wire injected the seam under test

## Problem

PR #8344 fixed #8281's marker: `emitOutcomeMarker` had written the
`SOLEUR_COMPOUND_PROMOTE_OUTCOME` row through Inngest's console-backed
`ctx.logger`, which renders `warn(obj, msg)` as multi-line `util.inspect` text
that no field-isolated reader can match. The fix gave the emitter a dedicated
pino instance and a signature `emitOutcomeMarker(outcome, sink = outcomeMarkerLogger)`,
and shipped three tests:

1. inject a `Writable`, call `emitOutcomeMarker(outcome, sink)`, assert one JSON row;
2. assert the exported `outcomeMarkerLogger` is a pino instance (`bindings()`);
3. grep the handler source for `emitOutcomeMarker\s*\(\s*logger\b` and require null.

The test-design seat then re-drove the mutants on a sandbox copy. Measured:

| Mutant | Result |
|---|---|
| `sink: OutcomeMarkerSink = console as never` (the production defect) | **SURVIVED**, 13/13 green |
| default destination → `/tmp/blackhole.log` / a no-op Writable / fd 2 | SURVIVED |
| `emitOutcomeMarker({…}, logger)` at all seven call sites (ctx logger in position 2) | SURVIVED |
| `const log = logger; emitOutcomeMarker(log, …)` at the `deduped` site | SURVIVED |
| drop `sync: true`; drop `try/catch` | SURVIVED |

The three tests pinned three things — that a pino logger *exists* in the
module, that the emitter *can* write JSON when *handed* one, and that the
literal identifier `logger` is not in argument position 1 — and not the one
property the PR existed to buy: *the emitter, called the way the handler calls
it, writes single-line JSON to fd 1.* The **default-parameter binding is the
wire**, and every test routed around it: test 1 supplied its own sink, test 2
read the sibling export the binding *pointed at*, test 3 looked at the
argument position the signature swap had just vacated.

The author's own battery certified this. It replaced the exported
`outcomeMarkerLogger` with a console-backed object and saw test 2 go red — a
mutation of the thing the test reads, not of the binding the emitter uses.
"2/3 kills" was a measurement of the battery.

## Solution

- **No injectable sink in production.** `emitOutcomeMarker(outcome)` is
  single-argument and lives in `server/compound-promote-marker.ts` with a
  module-private `const log = pino({ base: { component } })`, exactly like the
  four sibling `server/*-marker.ts` modules. There is no default parameter to
  rebind.
- **Observe the default path.** The suite partial-mocks `pino` with REAL
  serialization behind a capturing `{ write }` sink (the
  `cert-reissue-marker.test.ts` seam), then calls `emitOutcomeMarker(outcome)`
  with no second argument and parses the captured line. It also captures the
  constructor call and asserts exactly one argument (`{ base: {…} }` — no
  destination, no level override).
- **Pin the shape of every call, not an identifier in one slot.** The wire
  test comment-strips the handler and, for each `emitOutcomeMarker(`, balances
  parens and asserts zero top-level commas — an optional second parameter is a
  mutation `tsc` cannot see, so the source assertion is the only thing that can.
- **Then the class.** A ~10-line guard walks every file in
  `server/inngest/functions/` and asserts no `logger.<method>({ SOLEUR_…` /
  `logger.<method>({ [X_MARKER]: true` call exists. It went RED on
  `cron-stale-deferred-scope-outs.ts` before the fix — `SOLEUR_RUN_REPORT_SWEEP`
  had the identical defect, its runbook decode had claimed "at pino WARN" since
  it was written, and the observability seat measured it dark on the
  2026-09-14 and 2026-09-15 live fires. Routed through Marker 7
  `emitRunReportSweep` in `cron-liveness-marker.ts`.

Mutants re-driven on the FINAL tree, all killed: console sink, explicit
destination (`process.stderr`), level override, dropped `try/catch`, second
argument at a call site.

## Key Insight

When a test **injects the seam under test**, it measures the helper and leaves
the binding unpinned. A default parameter, a module-level `let`, a
`createX()` factory the production code calls with no arguments — each is a
wire, and a test that supplies the value itself cannot see what production
supplies. The battery has the same blind spot: mutating the exported thing the
test reads is not mutating the binding the code uses. Ask of every seam: *what
does the SUT bind when the test passes nothing, and which assertion observes
that?* If the honest answer is "none", the property the PR exists to buy is
unpinned, however many mutants the battery reports.

This is the third time on one thread that the #8281 defect sat inside the
#8281 fix — first the marker was unreadable, then the correction said it had
not emitted, then the tests could not see the sink. Each round's verification
inherited the framing of the round before.

## Session Errors

1. **The suite injected the seam under test** (above). **Prevention:** single-arg production signature; observe the default path through a real-serialization mock; paren-balanced call-shape assertion. Routed to `review/SKILL.md`.
2. **Instance, not class.** `SOLEUR_RUN_REPORT_SWEEP` had the same defect and a runbook reader that could never match. **Prevention:** before calling a marker fix complete, `git grep` the class (`logger.warn({ SOLEUR_` / `[X_MARKER]: true`) across every Inngest function; the class guard now does it mechanically.
3. **Correct fix, false rationale.** `sync: true` was justified by "the process may be torn down right after" — the handler runs in the long-lived Next serve process, the siblings are async with on-exit flush and decode fine, and a sync SonicBoom on a non-blocking fd 1 spins `Atomics.wait` on EAGAIN. The test comment separately credited `sync: true` for the Writable arm's synchronous capture, where it is not applied at all. Four seats converged. **Prevention:** the existing "name the command that falsifies each PROSE claim" rule; here it was `grep runtime app/api/inngest/route.ts` + reading the siblings.
4. **`error_message` under-scrubbed** — `safeDetail` strips control chars and caps at 200; `redactToken` knows only the current installation token. **Prevention:** `redactGithubSourcedText` on the one free-text field a no-`redact` logger carries, and on the Sentry `message`.
5. **Runbook consumers stale**: decode lacked the probe's `select(type == "object")` guard (pre-fix string rows jq-error rather than miss); the per-refusal `detail` recipe pointed at ctx.logger lines that render multi-line; `refusals_total`/cap undocumented. **Prevention:** when the producer's row shape changes, re-run every consumer recipe against a captured pre-fix AND post-fix row.
6. **Hooked commit queued behind a sibling worktree's 35-minute `test-all.sh` flock** (`lslocks` names the holder). Reaped my own hook tree with `proc.sh` `kill_mine`, ran every other pre-commit gate by hand on the staged set, committed `LEFTHOOK=0` with the disclosure per the operator's rely-on-CI decision. **Prevention:** documented in `2026-09-18-the-release-run-was-green-…` (PR #8343); no new rule.
7. **Wrong agent namespace**: spawned `soleur:engineering:review:git-history-analyzer`; the agent is under `research:`. One seat respawned late. **Prevention:** Sharp Edges line in `review/SKILL.md`.
8. **A mutant that crashed at import read as "no tests"** — the explicit-destination mutant used `pino.destination`, which the partial mock no longer exposed. Not scored; re-driven with `process.stderr` and killed by the named assertion. **Prevention:** existing rule — a crash is not a kill; require the named assertion to be the one that reddens.
9. **Full-command-line process grep blocked by the self-match hook**; used `list_runs`/`kill_mine`. **Prevention:** none needed — the hook is the prevention.
10. **Monitor supersede hook listed an already-expired monitor as live** (known lag, #8276 leg item 6). Noted.

## Related

- PR #8344 (this fix), PR #8276 (the marker's introduction), #8281 (tracker, stays open).
- `knowledge-base/project/learnings/workflow-issues/2026-09-18-the-release-run-was-green-and-production-was-still-serving-the-previous-build.md` — the previous round on this thread (PR #8343).
- `knowledge-base/project/learnings/2026-09-14-i-tested-both-endpoints-and-left-the-wire-between-them-unpinned.md` — the sibling shape: two pinned endpoints, unpinned wire. This learning is its default-parameter form.
- `knowledge-base/project/learnings/test-failures/2026-09-02-my-fake-curl-put-the-seam-above-everything-the-vendor-validates.md` — seam placed above what the oracle validates.
- `knowledge-base/project/learnings/2026-09-04-every-fix-reintroduced-the-class-it-was-fixing.md` — the "fix commit is the least-audited surface" rule this recurrence confirms.
