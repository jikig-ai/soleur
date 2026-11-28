---
title: "fix(cloudflare): Phase 5 browser bodies wait for window.bootstrap.atok after page load"
type: fix
date: 2026-11-28
slug: fix-p5-browser-bodies-wait-for-atok
branch: feat-one-shot-p5-atok-wait
issue: 12931
closes: none
lane: single-domain
---

# fix(cloudflare): Phase 5 browser bodies wait for window.bootstrap.atok after page load

## Enhancement Summary

**Deepened on:** 2026-11-28
**Sections enhanced:** 4 (Research Insights, Scope Check, Observability, Sharp Edges)
**Research used:** the installed Playwright type definitions (local `types.d.ts`), the deepen-plan gates 4.6-4.13
run mechanically, and the earlier CTO and three-reviewer pass. No broad agent fan-out, per the pipeline brief.

### Key Improvements
1. Verified `waitForFunction(pageFunction, arg, options)` and the `polling` default (`raf`) against the installed
   docstring. Found that the default `timeout` is `0` (no timeout), so the explicit 15000 ms is what keeps a
   signed-out run bounded. A Sharp Edge that claimed a 30 s default was corrected.
2. Rebuilt `## Scope Check` into the required Ask Mapping, Plan-Item Provenance and Split Assessment form, with
   11 verbatim asks, each mapped.
3. Added `## Observability`, because the test file under `tests/scripts/` takes this plan out of the pure-docs
   skip. It uses an allowlisted, sub-15-second probe: `git grep -c waitForFunction` over the spec directory.

### New Considerations Discovered
- The wait's `timeout` must stay explicit. Removing it would not fail fast; it could hang.

## Overview

The three committed Phase 5 dashboard bodies (`p5-read.js`, `p5-mint.js`, `p5-revoke.js`) go to
`/profile/api-tokens` with `waitUntil: 'domcontentloaded'` and read `window.bootstrap.atok` on the very next
in-page call. A live signed-in measurement on 2026-11-28 showed the atok is set about 283 ms after
DOMContentLoaded. So every body reports `{atok:false}` on a page that is in fact signed in. This was reproduced
twice with `p5-read.js` policies, and a presence probe right after showed `hasAtok:true`. This plan adds a bounded
wait for the atok after the navigation in each body, re-pins every sha256 citation, and extends the browser test
so the wait is proven by behaviour and by mutation. Epic #12931 is referenced (`Ref #12931`), never closed.

Out of this PR entirely: any bootstrap write stage, mint, revoke, Doppler write, or browser session. No token value
is printed anywhere.

Lane: this branch has no spec.md, so `lane: single-domain` is set from the scope: one runbook, three bodies, one
test. It is not `cross-domain` because no product, legal or marketing surface is touched.

## Research Reconciliation — Spec vs. Codebase

| Claim in the ask | Reality | Plan response |
|---|---|---|
| Update every sha256 pin; the archived plan quotes them but must not be edited | `tests/scripts/test-cf-old-login-token-remint-browser.sh` asserts the ARCHIVED plan's `- Hold:` lines are byte-equal to the runbook's `- Hold:` lines (check text: "the plan's Operator Holds lines equal the runbook's section 6 hold lines"). Two of those lines quote `p5-mint.js (sha256=ca7847…)` and `p5-revoke.js (sha256=5a9806…)`. Re-pinning the runbook without editing the plan turns that check RED. | CTO ruling F5: normalize exactly `sha256=[0-9a-f]{64}` to a fixed token on both sides before the compare (hold lines only), and add mutant XH1 (a hold wording edit turns it RED). The `$ph == $rh` text compare already fails on a line-count difference. Hash freshness stays enforced by the per-citation check and `sha256sum -c`. One runbook sentence states that the go-time `<sha256>` comes from this runbook, not from a plan's copy (review finding K2). |
| Check whether bootstrap.sh or tests pin the shas elsewhere | `git grep` of the three shas finds only `p5-browser.sha256`, the runbook (section 5 block lines 198-200, the two holds at 426 and 433, section 12 at 568) and the archived plan (2 lines). `bootstrap.sh` has no body sha. The test computes shas and holds no literal. | Edit the manifest and the 6 runbook sites. The archived plan is not touched. |
| `p5-mint.js` second atok read (~line 207, Node-side in `cleanup()`) | `cleanup()` runs only after a POST that itself needed the atok on the same page, so there is no second navigation to race. Row M16f deletes the atok mid-run and expects `success:false` at once. | CTO ruling F2: leave `cleanup()` untouched. |
| Add a case pinning that the wait exists before the first atok read in each body | A text-position check breaks on harmless reformatting (CTO F3). | Covered by behaviour: one late-atok row per body, where the atok is absent at goto and set only during the wait. A body with no wait, a wait placed after the first read, or a wait on the wrong condition returns `{atok:false}` there or fails `resolved`, and the row goes RED. Mutants XW1-XW3 prove this for each body. |

## Research Insights

**Premise Validation.** #12931 is OPEN (an epic, Ref only). The collision pre-check found open PR #12958, which
names #12931 (CF tunnel and Access re-home). Its file list touches none of the planned files, so there is no
overlap. The three body paths, `p5-browser.sha256`, the runbook and the test all exist on this branch's base
(`069e9371ef`). Each body has exactly one `page.goto` (read :145, mint :278, revoke :173). Each goto is followed
directly by the first in-page atok read: `get()` in read, `call('GET', …)` in mint, `page.evaluate(listInPage, …)`
in revoke. A reviewer (Kieran) re-checked all of these site claims against the files.

**Property List.**
- P1: on a signed-in page whose atok appears after DOMContentLoaded, each body proceeds as if the atok was there at
  load. There is no false `{atok:false}`.
- P2: on a page that really is signed out, each body still returns `{atok:false}` within a bounded time (finite
  timeout, error swallowed).
- P3: every sha256 citation equals the edited file's sha256. That covers the manifest, the runbook section 5 block,
  the runbook holds and runbook section 12.
- P4: return shapes, allowlists and the one-expression shape are unchanged.
- P5: the wait polls on an interval, not on animation frames (CTO F1).

**Cut List.**
- Text-position static check for the wait (would serve P1): covered by the late-atok rows plus XW1-XW3 (CTO F3).
- Wait inside mint `cleanup()` (serves no property): the POST already proved the atok on the same page (CTO F2).
- Runbook returns-table edit (serves no property): `{atok:false}` still means signed out.
- A committed mutant for the polling literal (would serve P5): the L-row `typeof polling === 'number'` assert plus
  the AC literal cover it. A one-off mutation is checked during work, not committed (DHH and simplicity reviews).
- A separate hold line-count check: the existing whole-text compare already fails on a count change (simplicity
  review).

**Mechanism detail (CTO F1, F4).** The operator's snippet, with interval polling added:

```js
// p5-read.js, p5-mint.js, p5-revoke.js — directly after the page.goto line
await page.waitForFunction(() => !!(window.bootstrap && window.bootstrap.atok), null, { timeout: 15000, polling: 100 }).catch(() => {});
```

Playwright's default `polling: 'raf'` stalls in a background or covered tab of an operator's own Chrome. That
happens when MCP attaches to it without Playwright's anti-backgrounding launch flags, and it would reproduce this
exact false negative. 15000 ms is about 50x the measured 283 ms.

**Test harness facts** (`tests/scripts/test-cf-old-login-token-remint-browser.sh`):
- The stub `page(world)` exposes only `goto`, `evaluate` and `request.delete`. Without a `waitForFunction` stub,
  every row would throw TypeError inside the body's `try` and go RED.
- The anti-vacuity floors are exact: `EXPECT_FULL=219`, `EXPECT_MUTANTS=66`, and the pristine `SCORED` count check
  is `-ne 22`.
- In `p5-read.js` an uncaught throw returns `{error:<e.name>}` (`errName`). So without `.catch`, a stub error named
  `TimeoutError` surfaces as `"error":"TimeoutError"`.
- The default worlds used by C1, C2, I1 and M16f have the atok present at load, so they are unaffected (Kieran
  review).
- The header comment block lists properties and mutants. It must name the new rows.

**Learnings applied.**
- `knowledge-base/project/learnings/test-failures/2026-10-31-a-guard-floor-constant-is-two-write-sites-not-one.md`:
  grep every occurrence of the old floor values (219, 66, 22) before bumping, then rerun the mutation battery.
- `knowledge-base/project/learnings/2026-08-01-my-mutation-battery-inferred-the-verdict-from-the-input-under-test.md`:
  the stub installs the atok only from inside `waitForFunction` polling, and only after the first falsy poll. It
  records whether the body's own condition resolved, so a body without the wait, or with a wrong condition, cannot
  pass by accident.
- `knowledge-base/project/learnings/workflow-patterns/2026-10-22-byte-pinned-envelope-runbook-lands-with-lint-exemption.md`:
  recompute `sha256sum` after any lint or formatting pass on the bodies, right before the final commit.

**Playwright API, verified (deepen-plan, 2026-11-28).** Source: an installed `playwright-core` 1.57.0
`types/types.d.ts` (the suite's comment names Playwright MCP 1.64; this signature and these options are unchanged
across those releases). Signature, line 5783:

```ts
waitForFunction<R, Arg>(pageFunction: PageFunction<Arg, R>, arg: Arg, options?: PageWaitForFunctionOptions): Promise<SmartHandle<R>>;
```

`PageWaitForFunctionOptions`, quoted verbatim:

> If `polling` is `'raf'`, then `pageFunction` is constantly executed in `requestAnimationFrame` callback. If
> `polling` is a number, then it is treated as an interval in milliseconds at which the function would be
> executed. Defaults to `raf`.
>
> `timeout`: Maximum time to wait for in milliseconds. Defaults to `0` - no timeout. The default value can be
> changed via `actionTimeout` option in the config, or by using the browserContext.setDefaultTimeout(timeout) or
> page.setDefaultTimeout(timeout) methods.

Two consequences for this plan:
- `null` in the `arg` slot is required, so `{ timeout, polling }` lands in `options`.
- The explicit `timeout: 15000` is load-bearing, not cosmetic. Without it the wait inherits whatever default the
  MCP session set, possibly none, and a signed-out page could hang instead of returning `{atok:false}`.

**Skipped research.** Community and functional-overlap discovery do not apply because there is no new skill, agent
or stack. Repo research ran inline, since the file set is four known files. Deepen-plan ran without the broad
agent fan-out, per the pipeline brief for this small fix: three plan reviewers and the CTO had already read the
plan and the files.

## Files to Edit

- `knowledge-base/project/specs/archive/20261127-221105-feat-one-shot-12931-phase5-token-remint/p5-read.js`: add the wait line after the goto, and one clause in the FLOW comment.
- `knowledge-base/project/specs/archive/20261127-221105-feat-one-shot-12931-phase5-token-remint/p5-mint.js`: same; `cleanup()` untouched.
- `knowledge-base/project/specs/archive/20261127-221105-feat-one-shot-12931-phase5-token-remint/p5-revoke.js`: same.
- `knowledge-base/project/specs/archive/20261127-221105-feat-one-shot-12931-phase5-token-remint/p5-browser.sha256`: three new shas; the `p5-sink.py` line is unchanged.
- `knowledge-base/engineering/operations/runbooks/cloudflare-old-login-token-remint.md`:
  - the section 5 block (3 lines);
  - the two section 6 holds that carry a sha (mint and revoke of `CF_API_TOKEN_PAGERULES_READ`);
  - the section 12 retire line;
  - one sentence after "`<sha256>` are the pair the hold or the section 5 table quotes": these are this runbook's values, and a sha quoted in an archived plan may be superseded.
  - The "same sha256" lines stay as they are.
- `tests/scripts/test-cf-old-login-token-remint-browser.sh`: the stub, the rows, hold-compare normalization, the mutants, the floors and the header.

## Files to Create

- `knowledge-base/project/specs/feat-one-shot-p5-atok-wait/decision-challenges.md` (the decision table; required by the pipeline's technical-ruling rule).
- `knowledge-base/project/specs/feat-one-shot-p5-atok-wait/tasks.md`.

Not edited: `knowledge-base/project/plans/archive/20261127-221105-2026-11-27-chore-cf-phase5-old-login-token-remint-plan.md`.

## Implementation Phases

1. **RED first** (`cq-write-failing-tests-before`). In the test's node harness:
   - `page(world)` gains `async waitForFunction(fn, arg, opts)`. It:
     - serializes `fn` by `toString()` into the page vm context, as `evaluate` does;
     - polls `fn` up to 3 times;
     - after the first falsy poll, sets `win.bootstrap.atok = world.atok` when `world.lateAtok` is true, so a
       condition that is true too early (for example `!!window.bootstrap`) resolves before the atok exists;
     - pushes `{ timeout: opts && opts.timeout, polling: opts && opts.polling, resolved }` to `world.waits`;
     - resolves when a poll is truthy, otherwise rejects with an `Error` whose `name` is `'TimeoutError'`.
   - `makeWorld` gains `lateAtok: false, waits: []`. With `lateAtok: true`, `win.bootstrap` starts as `{}`.
   - New rows (each name starts with a unique id so `P5_ONLY` prefix matching works):
     - `L1 read groups, atok set only after DOMContentLoaded -> the normal groups answer, not {atok:false}`
     - `L2 mint, atok set only after DOMContentLoaded -> minted, value to the sink once`
     - `L3 revoke, atok set only after DOMContentLoaded -> the one match deleted`
   - Each row checks the result FIRST, with the same `want(...)` as its signed-in sibling, so a missing wait fails
     with text naming `"atok":false`. Only then does it assert:
     - `w.waits.length === 1`;
     - `w.waits[0].resolved === true`;
     - `Number.isFinite(timeout) && timeout > 0 && timeout <= 30000`;
     - `typeof polling === 'number'`.
   - Run the rows: L1-L3 are RED on the current bodies, because `waitForFunction` is never called and the body
     returns `{atok:false}`.
2. **Bodies.** Insert the wait line directly after the `page.goto` in each body. Add one clause to each FLOW
   comment: "then waits up to 15 s for window.bootstrap.atok, which the dashboard sets after DOMContentLoaded".
   Change nothing else. After this:
   - L1-L3 are GREEN.
   - M3, R6 and D7 (signed out) are GREEN through the stub's rejection, which proves the `.catch` swallows it.
3. **Hold compare (CTO F5).**
   - Add `holds_norm() { grep -a '^- Hold:' "$1" | sed -E 's/sha256=[0-9a-f]{64}/sha256=<pinned>/g'; }`.
   - Build `ph` and `rh` with it. The rest of the check is unchanged.
   - Update the `PLAN_FILE=` comment: the compare covers hold wording, and sha values are checked against the files
     by the citation check.
4. **Pins.**
   - `sha256sum` the three bodies and write `p5-browser.sha256`.
   - Update the 6 runbook sites and add the one runbook sentence.
   - Confirm that `git grep -l` of each old sha lists only the archived plan.
5. **Mutants** (in the mutation section):
   - XW1, XW2 and XW3 delete the wait line in read, mint and revoke. Each turns L1, L2 or L3 RED naming `"atok":false`.
   - XW4 drops `.catch(() => {})` in `p5-read.js`. It turns D7 RED naming `"error":"TimeoutError"`.
   - XH1 mutates the wording of one runbook `- Hold:` line in a copy (for example `in the same sitting` changed to
     `in a sitting`). `holds_norm` of the copy must then differ from the archived plan's.
   - Add L1, L2, L3 and D7 to `SCORED`. The pristine-count check moves from 22 to 26.
6. **Floors.**
   - Grep every write site of 219, 66 and 22.
   - Set `EXPECT_FULL` and `EXPECT_MUTANTS` from the counts of a real run (CTO F3).
   - Update the header PROPERTIES and MUTATIONS comment.
7. **Verify.**
   - `bash tests/scripts/test-cf-old-login-token-remint-browser.sh` exits 0.
   - The same command with `--mutants` exits 0.
   - The `scripts/test-all.sh` suite `tests/scripts/cf-old-login-token-remint-browser` is green.
   - One-off checks, not committed: dropping `, polling: 100` in a scratch copy of a body turns its L row RED;
     changing the wait condition to `!!window.bootstrap` in a scratch copy turns its L row RED on `resolved`.

## Scope Check

Ask source: the freeform one-shot ARGUMENTS for this branch (Ref #12931).

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "after the goto in each body, wait a bounded time for atok" | Phase 2 | mapped |
| 2 | "so a really signed-out page still returns {atok:false} after the timeout" | Phase 2 `.catch`; rows M3, R6, D7; XW4 | mapped |
| 3 | "Keep the one-expression shape and return allowlists unchanged; no other behaviour change" | Phase 2 (one line + comment clause); P4 | mapped |
| 4 | "Update every sha256 pin: p5-browser.sha256" | Phase 4 | mapped |
| 5 | "the runbook ... (section 5 code block and every section 6 / section 12 hold line quoting a sha)" | Phase 4 | mapped |
| 6 | "tests/scripts/test-cf-old-login-token-remint-browser.sh (add a case pinning that the wait exists before the first atok read in each body)" | Phase 1 rows L1-L3; Phase 5 XW1-XW3 | mapped |
| 7 | "Do not edit the archived plan" | Files to Edit exclusion; AC archived plan byte-unchanged | mapped |
| 8 | "Do not run any bootstrap write stage, mint, revoke, Doppler write, or use the browser. Never print token values." | Overview out-of-scope line; P-leak AC | mapped |
| 9 | "PR body uses \"Ref #12931\" (never Closes)" | AC last row | mapped |
| 10 | "p5-mint.js also has a second atok read around line 208 ... check whether it needs the same wait" | Reconciliation row; CTO F2: untouched | mapped |
| 11 | "Check whether the bootstrap.sh or tests pin the body sha256 values anywhere else (grep the three current shas" | Reconciliation row; Phase 4 grep AC | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| Wait line after each goto | "wait a bounded time for atok" | asked |
| `polling: 100` in the wait | "e.g." (the snippet is an example) | inferred — justification: CTO F1; default `raf` polling stalls in a background tab and reproduces the same false `{atok:false}` |
| `waitForFunction` stub, `lateAtok`, rows L1-L3 | "add a case pinning that the wait exists before the first atok read in each body" | asked |
| Hold-compare `holds_norm`, XH1 | "Do not edit the archived plan" | inferred — justification: the existing test byte-compares the archived plan's holds with the runbook's; the asked re-pin turns it RED unless shas are normalized (CTO F5) |
| One runbook sentence on the go-time sha source | "every section 6 / section 12 hold line quoting a sha" | inferred — justification: after the re-pin the archived plan quotes superseded shas; the sentence keeps a go-time reader on the runbook's values (Kieran review) |
| XW4, D7 in `SCORED` | "a really signed-out page still returns {atok:false}" | inferred — justification: without a RED edit on the `.catch`, P2 has no mutation proof |
| Floor and header updates | "add a case" | inferred — justification: the suite's exact anti-vacuity floors fail on any added row |
| `decision-challenges.md`, `tasks.md` | "Persist every decision as a row" | asked |

### Split Assessment

- Subsystems touched: 3 — `knowledge-base/project/specs/archive/` (bodies, manifest), `knowledge-base/engineering/operations/runbooks/`, `tests/scripts/`
- Planned files: 8 (6 edited, 2 created) | Estimated changed lines: about 150
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## User-Brand Impact

- **If this lands broken, the user experiences:** the Phase 5 token re-mint sitting stalls again. Either every body
  reports `{atok:false}` on a signed-in dashboard, or, worse, a body changes its return shape and the runbook's
  return table misreads it.
- **If this leaks, the user's data is exposed via:** a body or test log printing the atok or a token value. The
  change adds no new return key, and the P-leak check still scans every captured output.
- **Brand-survival threshold:** `none`
- **Threshold decision (challengeable):** this is internal operator tooling with no end-user surface. The bodies run
  only on an explicit per-command go, and no path in the diff matches the preflight sensitive-path regex.

## Observability

These bodies run in an operator-attached Playwright MCP session and return a JSON object to the agent. They have no
server process, so the signals are the return line, the go-time body check, and the CI suite.

```yaml
liveness_signal:
  what: "the SOLEUR_P5_BODY verdict line printed by the runbook section 5 check before any body runs, and the body's JSON return"
  cadence: "per go (each body run)"
  alert_target: "the agent session running the go; a verdict=stop or an unexpected return halts that step"
  configured_in: "knowledge-base/engineering/operations/runbooks/cloudflare-old-login-token-remint.md section 5"
error_reporting:
  destination: "the body's return object (keys error / refused / atok / status) read by the agent against the runbook browser returns table; CI suite tests/scripts/cf-old-login-token-remint-browser in scripts/test-all.sh"
  fail_loud: "SOLEUR_P5_BODY verdict=stop, or a return of {atok:false} / {error:<name>} / {refused:<reason>}"
failure_modes:
  - mode: "a signed-in page still reports {atok:false} (wait missing, wrong condition, or raf polling stalled)"
    detection: "rows L1-L3 and mutants XW1-XW3 in the CI suite; at go time the {atok:false} row of the runbook returns table"
    alert_route: "CI failure on the PR; at go time the agent stops the step"
  - mode: "a body edited without re-pinning its sha"
    detection: "suite P-pin checks (sha256sum -c and runbook citations); go-time SOLEUR_P5_BODY verdict=stop"
    alert_route: "CI failure on the PR; at go time the step does not start"
  - mode: "the wait throws through (missing .catch) on a signed-out page"
    detection: "row D7 and mutant XW4 ({error:TimeoutError})"
    alert_route: "CI failure on the PR"
logs:
  where: "the agent session transcript (body return lines) and the CI job log of scripts/test-all.sh"
  retention: "session transcript for the session; CI logs per GitHub Actions retention (90 days)"
discoverability_test:
  command: "git grep -c waitForFunction -- knowledge-base/project/specs/archive/20261127-221105-feat-one-shot-12931-phase5-token-remint/"
  expected_output: "p5-read.js:1, p5-mint.js:1, p5-revoke.js:1"
```

## Guard Contract

### Guard 1 — late-atok wait in every body

**Property.** Every body that reads `window.bootstrap.atok` after a navigation first waits for it on the exact atok
condition, with a bounded, interval-polled wait. A late atok then yields the normal answer, and an absent one yields
`{atok:false}`.

**Assembly.** The chokepoint is the single `page.goto` in each of the three bodies and the first in-page call after
it: `get()` in read, `call()` in mint, `page.evaluate(listInPage)` in revoke. The suite finds the three bodies with
its `find_one` glob. Mint `cleanup()` is the one other atok read. It is excluded by CTO F2: it runs on the same page,
after a POST that needed the atok.

**Mutation matrix.**

| Mutation | Must turn RED |
|---|---|
| XW1: delete the wait in `p5-read.js` | L1 (`"atok":false`) |
| XW2: delete the wait in `p5-mint.js` (a second member after a compliant first) | L2 |
| XW3: delete the wait in `p5-revoke.js` | L3 |
| XW4: drop the `.catch` in `p5-read.js` | D7 (`"error":"TimeoutError"`) |
| A wait condition that is true too early (`!!window.bootstrap`), checked once during work | that body's L row (`resolved`) |
| Own dispatch: drop L1-L3/D7 from `SCORED`, or a harness that runs 0 rows | the pristine count check (`-ne 26`, exit 2) and the exact `EXPECT_*` floors |

**Harness rows.**
- RED on a suite edit: a stub that installs the atok at `goto` instead of during the wait leaves XW1-XW3 GREEN, and
  the mutant check reports that as a FAIL. A stub that never installs it turns L1-L3 RED.
- Must-PASS, non-canonical: a body using `{ timeout: 20000, polling: 250 }` passes L1-L3, because any finite timeout
  up to 30000 with numeric polling is permitted.

**Anchor.** The body shas are also quoted in the runbook's section 5 table and its holds. The go-time check
(`SOLEUR_P5_BODY`) compares each body against the committed blob and that quoted value. A weakened body therefore
also needs a runbook edit that a reviewer reads at go time.

### Guard 2 — hold wording parity, modulo sha

**Property.** The runbook's `- Hold:` lines equal the archived plan's `- Hold:` lines, except for an exact
`sha256=<64 lowercase hex>` value.

**Assembly.** Every line starting `- Hold:` in both files, through `holds_norm`, compared as one text block (which
covers the line count).

**Mutation matrix.**

| Mutation | Must turn RED |
|---|---|
| XH1: change one word of a runbook hold (committed) | the hold compare |
| Delete one runbook hold line (checked once during work) | the hold compare |
| Shorten one runbook hold sha to 63 hex (checked once during work) | the hold compare (not normalized) |

## Acceptance Criteria

- [x] Each of the three bodies contains exactly one `page.waitForFunction(` call, directly after its `page.goto`,
      with `timeout: 15000`, `polling: 100` and `.catch(() => {})`. `git diff` of each body shows only that line and
      its FLOW comment clause.
- [x] `p5-mint.js` `cleanup()` is byte-unchanged.
- [x] `(cd <spec dir> && sha256sum -c p5-browser.sha256)` passes, and the `p5-sink.py` line is unchanged.
- [x] `git grep -l` of each of the three old shas lists only the archived plan file.
- [x] Runbook: the section 5 block lines and the sha-bearing hold and section 12 lines carry the new shas. The
      suite's citation check passes with at least 5 citations.
- [x] Rows L1-L3 exist. They were RED before Phase 2 and are GREEN after, and each asserts `resolved === true`.
      M3, R6 and D7 are GREEN.
- [x] Mutants XW1-XW4 and XH1 each land and turn their row RED with the named text.
- [x] `bash tests/scripts/test-cf-old-login-token-remint-browser.sh` exits 0, and the same command with `--mutants`
      exits 0, with the updated exact floors and the pristine count of 26.
- [x] The archived plan is byte-unchanged:
      `git diff --quiet origin/main -- knowledge-base/project/plans/archive/`.
- [x] No captured output carries the atok or any token value (the P-leak check is green).
- [ ] The PR body says `Ref #12931`, never `Closes`.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — infrastructure/tooling change (operator browser bodies and their test).

## Test Scenarios

- Late atok in each body: the normal answer, with the wait resolved (L1-L3).
- Signed out in each body: `{atok:false}` after the stub's rejection (M3, R6, D7).
- Atok removed mid-mint: cleanup returns `success:false` at once (M16f, unchanged).
- Hold parity with the new shas: GREEN. Wording drift: RED (XH1).

## Open Code-Review Overlap

None. The open `code-review` issues were checked against all six planned paths on 2026-11-28.

## Plan Review

Panel: DHH, Kieran and code-simplicity reviewers (2026-11-28). The CTO's design rulings F1-F5 are recorded in
`decision-challenges.md`. All findings below are Mechanical.

- **Applied:**
  - The wait condition is checked through `resolved`, with the atok installed after the first poll (Kieran P1).
  - The runbook sentence on where the go-time sha comes from (Kieran P1).
  - The L rows check the result before the wait asserts (Kieran P2).
  - XW4 expects `"error":"TimeoutError"` (Kieran P2).
  - D7 added to `SCORED`, so the count is 26 (Kieran P2).
  - The hold compare is normalized in place through `holds_norm`, with no separate line-count check
    (DHH P1, simplicity).
  - The XW5 committed mutant is cut, and P5 is added (DHH P1, simplicity).
  - The Guard 2 rows that are not committed are marked as checked once during work (simplicity).
  - `lateAtok` is a boolean (simplicity).
- **Not applied:**
  - Cutting `decision-challenges.md` and `tasks.md` (DHH P2): both are required by the pipeline.
  - Cutting the Guard Contract (DHH P2): plan Phase 2.12 and `lint-guard-contract.py` require it, because the
    deliverable contains a guard.
  - The single-poll stub (DHH P2): it conflicts with Kieran P1, which needs a poll after the first falsy one.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only placeholder text, or omits the threshold will
  fail `deepen-plan` Phase 4.6.
- Recompute the three shas after the LAST edit to any body, including comment tweaks from review. A stale pin fails
  the runbook's own section 5 check at go time.
- The stub must install the late atok only inside `waitForFunction`, after a falsy poll, and never in `goto` or
  `evaluate`. Otherwise a body without the wait passes L1-L3.
- The floors are exact. Set them from a real run, then grep for any second write site of the old values.
- `perl -0pi` mutants replace the first match only. Confirm each `from` literal appears exactly once in its body.
- The stub models Playwright's signature `waitForFunction(pageFunction, arg, options)`. It must read the options
  from the THIRD parameter only. A body that writes `waitForFunction(fn, { timeout: 15000 })` would, in real
  Playwright, pass the options as `arg` and fall back to the page default timeout (`0`, no timeout, unless a
  default was set) with `raf` polling: a possible hang in a background tab. The stub then records an undefined
  timeout and the L row goes RED, as it should. Do not make the stub tolerant of the two-argument form.
- Before cutting any assertion as redundant in review, name the mutation it kills and show that a surviving
  assertion still kills it. The one-off checks in Phase 7 do this for the cut XW5 mutant and the dropped hold
  line-count check.
