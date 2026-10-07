---
title: "fix: de-flake the real-grandchild group-kill test in cron-claude-eval-substrate-exit"
date: 2026-10-07
slug: flaky-grandchild-reaped-test
branch: feat-one-shot-9670-flaky-grandchild-reaped-test
issue: 9670
type: fix
lane: single-domain
closes: 9670
---

# fix: de-flake the real-grandchild group-kill test (#9670)

## Enhancement Summary

**Deepened on:** 2026-10-07
**Sections enhanced:** 3 (Research Insights verification, Observability, Sharp Edges)
**Agents / checks used:** plan-review panel (DHH, Kieran, code-simplicity) already folded in; deepen gates 4.6, 4.7, 4.8, 4.9, 4.10, 4.11, 4.12 run mechanically; installed-vitest API verification (no extra research fan-out: strong local context, test-only single-file change).

### Key verifications
1. `vi.waitFor` options `{ timeout, interval }` confirmed in the installed vitest 4.1.x typings (`node_modules/vitest/dist/index.d.ts`, `interface WaitForOptions`); the repo's `installViWaitForFloor` wrapper honors an explicit `timeout` (`options?.timeout ?? 10_000`), so `timeout: 15_000` wins over the 10s floor.
2. `repeats` is a supported per-test option (`@vitest/runner` `TestOptions.repeats`), so the temporary `{ repeats: 50 }` verification aid is valid; hooks (`beforeEach`/`afterEach`, including the sleeper reaper) must run per repeat - confirm at work time by checking that each iteration gets a fresh `mkdtemp` dir (if not, fall back to the 50x CLI loop).
3. Cited issues resolved live: #7122 CLOSED (origin of the P2-1 group kill), #5796 CLOSED (the 10s waitFor floor), #9670 OPEN. Gate 4.12 scope-check count = 1, gate 4.8 PAT grep = no hits, `cq-cite-content-anchor-not-line-number` exists in AGENTS.md.

### New considerations
- vitest `waitFor` runs the callback immediately and then every `interval`; a thrown `Error(lastProbe)` is how the last state reaches the rejection - the plan's `try/catch` converts that into the evidence-bearing `expect` message.
- No ADR/C4/IaC/encryption/UI/guard-contract trigger fires (single test file under `apps/web-platform/test`).


## Overview

`apps/web-platform/test/server/inngest/cron-claude-eval-substrate-exit.test.ts` has a row
that runs a REAL `claude` stand-in (a `/bin/sh` script) which backgrounds a SIGTERM-ignoring
`sleep 120` in the child's process group, prints a result line and exits 0. It then asserts
that `spawnClaudeEval`'s on-exit `process.kill(-child.pid, "SIGKILL")` (#7122 P2-1) killed the
sleeper. It failed once in a `merge_group` run (`test-webplat (2/2)`, 1 failed / 6936 passed,
run 37523884054) with `the grandchild survived the child's exit ... expected true to be false`
at the final `expect(isAlive(sleeperPid), "the grandchild survived ...").toBe(false)`. The product code is not implicated
(the queue entry was `main` plus an unrelated plugin-only change).

The fix is confined to ONE file, the test itself: replace the 3s hand-rolled wall-clock loop with
the repo's own bounded poll (`vi.waitFor`, 15s), make the inline liveness probe unable to
misreport a dead process as alive, and make the next failure self-attributing so recurrences can
be counted on #9670 with evidence. (Plan review, 3 seats: a new helper file plus 11 injected-deps
unit rows was cut as over-built for a one-caller probe; see Plan Review Revisions.)

## Research Insights

### Premise Validation (Phase 0.6)

- #9670 is OPEN, no closing PR. Cited file exists on `origin/main`; the test is at
  the `describe("spawnClaudeEval — a real grandchild in the child's process group is reaped on exit ...")` block (the issue's `:406` is its final `expect`).
- **Stale premise in the issue body:** it says "the assertion checks once". On this branch the
  test already polls: `deadline = Date.now() + 3_000; while (isAlive(pid) && Date.now() <
  deadline) await sleep 25` (the `const deadline = Date.now() + 3_000` loop), then does ONE more `isAlive` for the assertion. The
  failure at `:406` is therefore either (a) the 3s wall-clock bound expiring, or (b) the final
  single probe misreporting. The plan targets both; a plain "add a poll" would be a no-op.
- Not an ADR-corpus mechanism question (test-only change); no mechanism proposed by the issue
  conflicts with an ADR. A vitest `retry` was considered and rejected (see Cut List).

### Property List (Phase 0.6b)

1. P1 - The test passes whenever the product's group kill ran, for any runner stall shorter than a
   generous, repo-conventional bound (10s floor per `installViWaitForFloor`, #5796).
2. P2 - The liveness probe never reports a dead process as alive (a process that vanishes between
   `kill(pid,0)` and the `/proc/<pid>/stat` read is dead; `EPERM` is alive, not dead).
3. P3 - A failure names its own evidence (last observed `/proc` state, waited ms, load average)
   so a recurrence can be classified as "stall" vs "product regression" and counted on #9670.
4. P4 - The test stays RED when the product's group kill is removed (anti-vacuity preserved).

### Cut List

- vitest `retry`/`--retry` on this row -> buys P1 only by hiding failures and defeats P3; a
  deterministic regression (P4) would also burn retries. Cut.
- Any change to `_cron-claude-eval-substrate.ts` -> the kill is synchronous in the `exit` handler
  (the `process.kill(-child.pid, "SIGKILL")` in the `child.on("exit"` handler) and never conditional; measured below, it lands within 72ms. Cut.
- Raising a global vitest `testTimeout` -> unrelated rows do not need it. Cut; only this row's
  per-test timeout moves.
- New helper file + injected-deps unit test (added then cut at plan review, R1) -> one caller; `vi.waitFor` is
  already the repo's bounded poll. Cut.
- A `minPolls` / stall-detection scheme in the wait loop -> YAGNI; a 15s bound already exceeds
  the repo's 10s contended-CI floor. Cut.

### Measurements (this session, command named)

- Probe `probe.mjs` (scratchpad, not committed): 400 iterations of the exact fixture under
  load average ~40 on 16 cores (48 `yes` busy loops): the sleeper was still "alive" on the
  FIRST post-exit probe in 391/400 iterations (SIGKILL delivery is asynchronous), max time to
  gone 72ms, 0 timeouts. Consequences: (i) a single immediate check is unreliable, so polling is
  required (it already exists); (ii) local CPU load alone does NOT reproduce the CI failure at
  baseline - the CI failure needs a longer stall (VM steal / memory pressure under 450 parallel
  files) or the probe race. So "50 runs under load" is supporting evidence only; the proof is the 15s bound, the
  probe-race fix, and the RED mutation of the product kill (see Plan Review Revisions R1/R11).
- `npx vitest run test/server/inngest/cron-claude-eval-substrate-exit.test.ts --project unit -t grandchild`
  passes locally; the row's own runtime is ~56ms (the rest is transform/import, ~11s wall per
  invocation, so a 50x CLI loop is ~9 min - run it in the background with a Monitor).

### Identified defects in the current probe (the local `isAlive` const)

1. `kill(pid,0)` succeeds then `readFileSync('/proc/<pid>/stat')` throws (ENOENT: reaped
   between the two calls) -> the `catch { return true }` around the stat read reports a DEAD process as ALIVE. A narrow race (zombie
   read, then reap between the immediate re-probe's `kill(0)` and stat read), but it is real,
   deterministic to reason about, and one line to fix. Linux can also surface the vanished pid as
   `ESRCH` (open succeeded, read failed) rather than `ENOENT`: treat both as dead when `/proc` is
   readable; any other read error (`EACCES` under `hidepid`) stays alive.
2. Any `kill(pid,0)` error is treated as "dead", including `EPERM` (exists, not ours) which
   means alive. Harmless today (same uid) but wrong.
3. The wait bound is wall-clock 3s with one post-deadline probe: a runner stall that consumes
   the window (sleeper's SIGKILL needs CPU time the stalled VM did not give) fails the row even
   though the product behaved. 3s is also below the repo's own contended-CI convention
   (`installViWaitForFloor`, 10s; see its header for the proven CI-red precedent).
4. The failure message carries no evidence.

### Relevant paths / conventions

- Test: `apps/web-platform/test/server/inngest/cron-claude-eval-substrate-exit.test.ts`
- Product (read-only here): `apps/web-platform/server/inngest/functions/_cron-claude-eval-substrate.ts`
  (`detached: true` in the spawn options; `process.kill(-child.pid, "SIGKILL")` in the `exit` handler).
- Existing bounded poll: `vi.waitFor` with the 10s default floor installed by
  `apps/web-platform/test/helpers/install-vi-waitfor-floor.ts` (#5796); explicit `{timeout}` wins.
- Learnings consulted: `2026-09-29-i-pinned-a-flake-class-with-a-weaker-fork-of-the-detector-we-already-had.md`
  (reuse the repo's own mechanism instead of a weaker fork -> here: align the bound with the
  existing 10s `vi.waitFor` floor rather than invent a different number silently);
  `2026-05-26-chromium-zombie-processes-docker-without-init.md` (zombies persist where PID 1
  does not reap; keep the 'Z' => dead rule).
- Open code-review overlap: none (queried `gh issue list --label code-review` bodies for the test
  file, the substrate file and the new helper path - zero hits).

## Open Code-Review Overlap

None.

## User-Brand Impact

- **If this lands broken, the user experiences:** nothing directly - this is a test-only change;
  the failure mode is a red required check ejecting an unrelated PR from the merge queue (~35 min
  re-queue) or, worse, a green test that no longer detects a surviving grandchild.
- **If this leaks, the user's data is exposed via:** no exposure vector in the change itself. The
  property the test guards (a grandchild must not outlive the run and read the write token minted
  into `.git/config`) is why P4 (still RED without the group kill) is a hard requirement.
- **Brand-survival threshold:** `none`
- **Threshold decision (challengeable):** the diff touches only `apps/web-platform/test/**`; the
  guarded product behavior is unchanged and its detection is explicitly preserved by AC5.

threshold: none, reason: test-only diff under `apps/web-platform/test/` that changes how a liveness wait is performed; no runtime, schema, auth or credential path is touched.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "make it poll with a bounded deadline for the grandchild to be gone (or otherwise remove the timing dependency)" | Phase 1 (`vi.waitFor` 15s bound in the test) | mapped |
| 2 | "verify by re-running the test ~50 times under CPU load" | Phase 2 | mapped |
| 3 | "if the same test fails again, count it on this issue rather than opening a new one" | Phase 1 (self-attributing failure message), Phase 3 (issue comment) | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| Edit of `cron-claude-eval-substrate-exit.test.ts` (poll via `vi.waitFor`, 15s bound) | "poll with a bounded deadline for the grandchild to be gone" | asked |
| Inline `isAlive` fix (ENOENT/ESRCH read failure => dead, EPERM => alive) | "otherwise remove the timing dependency" | asked |
| Failure message with last `/proc` state, waited ms, loadavg | "count it on this issue rather than opening a new one" | asked |
| Per-test timeout 20s -> 40s on the one row | "poll with a bounded deadline" | asked - the bound must fit inside the test timeout |
| 50x-under-load run + one mutation run (scratchpad scripts, not committed) | "~50 times under CPU load" | asked |

### Split Assessment

- Subsystems touched: 1 - `apps/web-platform/test`
- Planned files: 1 | Estimated changed lines: ~40
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## Plan Review Revisions

Panel: DHH, Kieran, code-simplicity (threshold `none` => 3-seat baseline). All findings engineering-class (mechanical); none touches operator-requested scope.

| # | Finding | Seats | Disposition |
|---|---------|-------|-------------|
| R1 | New `test/helpers/process-liveness.ts` + 11-row injected-deps unit test is over-built: one caller, `vi.waitFor` already is the repo's bounded poll, rows 8-11 re-test vitest, rows 1-7 test a 12-line probe | DHH, simplicity, Kieran (asked to justify) | Applied: both new files and all DI (`deps/now/sleep`) CUT; fix stays inline in the test file |
| R2 | Probe must also treat `ESRCH` from the stat read as dead (open ok, read fails) | Kieran | Applied (defect 1 + Phase 1) |
| R3 | "exactly where this bites" overstated; the 15s bound is the more plausible fix | Kieran | Applied (wording softened) |
| R4 | Line-number citations violate `cq-cite-content-anchor-not-line-number` | Kieran | Applied (content anchors) |
| R5 | Extend the existing `node:os` import instead of `import os` | Kieran | Applied |
| R6 | AC3 depends on machine state / load; AC6 "lint if any" vague | Kieran | Applied: AC3 re-labelled supporting evidence; AC6 names real commands |
| R7 | Mutations 2 (`detached`) and 3 (helper) not needed; keep mutation 1 only | simplicity | Applied |
| R8 | Cut `cpus` from message; keep state, waited ms, loadavg | simplicity | Applied |
| R9 | Use a 10s bound with the existing 20s timeout (one fewer number) | simplicity | Declined with reason: 15s + 2s `STDIO_CLOSE_WAIT_MS` drain leaves 3s margin on a 20s timeout, too thin on the very runners that stall; 15s/40s kept (still one row only) |
| R10 | 50 CLI runs ~9 min; use a temporary `{repeats: 50}` | simplicity | Applied: a temporary `{ repeats: 50 }` option on the row (reverted before commit) under load; CLI-loop fallback if `repeats` cannot re-create the temp dir per iteration |
| R11 | The ENOENT-race fix has no deterministic RED after cutting the unit rows | (self-noted tradeoff) | Accepted: the defect is a one-line, read-visible branch; evidence for it is reasoning + the diagnostic message on any recurrence. Recorded honestly in Sharp Edges |

## Implementation Phases

### Phase 1 - Edit the one test file

File: `apps/web-platform/test/server/inngest/cron-claude-eval-substrate-exit.test.ts`.

1. Fix the local `isAlive` (keep it local, one caller):
   - `process.kill(pid, 0)` throwing `ESRCH` => dead; any other error (`EPERM`) => alive.
   - Read `/proc/<pid>/stat`; parse the state char after the LAST `)` (comm may contain spaces/parens); `Z`/`X` => dead.
   - Stat read failure: `ENOENT` or `ESRCH` => dead when `/proc` is readable (pid vanished between the two calls); any other error, or no `/proc` (non-Linux), => alive (kill(0) is the only signal).
   - Record the last observed state string in a closure variable (`lastProbe`) for the failure message.
2. Replace the `const deadline = Date.now() + 3_000` loop and the final single probe with:
   ```ts
   const t0 = Date.now();
   let gone = true;
   try {
     await vi.waitFor(() => { if (isAlive(sleeperPid)) throw new Error(lastProbe); }, { timeout: 15_000, interval: 25 });
   } catch { gone = false; }
   expect(gone, `the grandchild survived the child's exit: the group kill did not reach it ` +
     `(pid ${sleeperPid}; last probe: ${lastProbe}; waited ${Date.now() - t0}ms; loadavg ${loadavg().map((n) => n.toFixed(1)).join("/")})`).toBe(true);
   ```
   Extend the existing `import { tmpdir } from "node:os"` to `{ loadavg, tmpdir }`. The 15s explicit bound beats the 10s global floor (explicit `{timeout}` wins per `install-vi-waitfor-floor.ts`).
3. Change the row's per-test timeout `20_000` -> `40_000` (15s wait + 2s drain + spawn margin) so the RED path fails on the assertion, not the vitest timeout. Keep the `afterEach` reaper.
4. Refresh the describe-block comment: the kill is asynchronous (measured: first post-exit probe sees the sleeper alive 391/400 times), the wait is bounded at 15s by design, and the failure message is the evidence to paste on #9670 (state `S` after the full wait = real product regression, not a flake).

### Phase 2 - Verify (evidence, not assertion)

From `apps/web-platform` in the worktree. Load: `2 x nproc` `yes >/dev/null` loops (`timeout 900`), torn down with `pkill -x yes` in a `trap`. Poll with Monitor, bounded output.

1. Row passes under load: temporary `{ repeats: 50 }` on the row (or a 50x CLI loop, ~9 min) - 0 failures; record load average, count, wall time. Remove the temporary option before commit. This is SUPPORTING evidence only: locally the baseline never failed (measured), so green-50 cannot prove the fix by itself.
2. Whole file once under load (all rows) green.
3. Mutation (anti-vacuity, P4): comment out `process.kill(-child.pid, "SIGKILL")` in the product `exit` handler, run the row: it must go RED on the assertion within the 40s timeout, with the new message showing state `S`. Revert; `git diff origin/main -- apps/web-platform/server` must be empty.
4. `cd apps/web-platform && npx tsc --noEmit` and `npx vitest run test/server/inngest/cron-claude-eval-substrate-exit.test.ts` green.

### Phase 3 - Ship notes

- PR body: `Closes #9670` (body, not title).
- Comment on #9670: corrected premise (test already polled for 3s), measured baseline (391/400 first-probe-alive, max 72ms under load ~40), defects fixed, and that a recurrence must paste the new failure message as a count on this issue.

## Files to Edit

- `apps/web-platform/test/server/inngest/cron-claude-eval-substrate-exit.test.ts` - `isAlive` fix, `vi.waitFor` 15s poll, evidence-bearing message, row timeout 20s -> 40s, comment refresh, `node:os` import extended.

## Files to Create

- None.

## Acceptance Criteria

### Pre-merge (PR)

- [x] AC1: the row calls `vi.waitFor(..., { timeout: 15_000, ... })` and no longer contains the `Date.now() + 3_000` loop; its per-test timeout is >= 40_000 (`git grep -n "3_000" apps/web-platform/test/server/inngest/cron-claude-eval-substrate-exit.test.ts` shows no deadline loop).
- [x] AC2: `isAlive` treats `ENOENT`/`ESRCH` stat-read failures as dead when `/proc/self/stat` is readable, `EPERM` from `kill(pid,0)` as alive, and parses the state after the last `)` (verified by reading the diff; there is deliberately no helper unit test, see R1/R11).
- [x] AC3 (supporting evidence): a 50-iteration run of the row under >= 2x `nproc` busy loops passes; the PR body records count, load average and wall time.
- [x] AC4: the assertion message includes pid, last probe state, waited ms and loadavg (verified from the mutation run's captured output pasted in the PR body).
- [x] AC5: with `process.kill(-child.pid, "SIGKILL")` removed from the product `exit` handler the row is RED on the assertion (not the vitest timeout); restored it is GREEN; `git diff origin/main -- apps/web-platform/server` is empty at commit time.
- [x] AC6: `cd apps/web-platform && npx tsc --noEmit` and `npx vitest run test/server/inngest/cron-claude-eval-substrate-exit.test.ts` both pass.
- [x] AC7: `git diff --stat origin/main` lists exactly the one planned test file plus plan/spec artifacts (no vitest config, setup file or other test touched).

### Post-merge (operator)

- [ ] None. Follow-up observation only: if the test fails again in `merge_group` or on a PR run, add the failure message as a count comment on #9670 (do not open a new issue).

## Test Scenarios

The edited row itself is the scenario; verification is Phase 2 (50x under load, full file, mutation of the product kill).

## Observability

Test-only change (no runtime surface); declared because the file is code-class under `apps/web-platform`. The "signal" is the CI test result and the failure message.

```yaml
liveness_signal:
  what: the vitest row "kills a SIGTERM-ignoring grandchild ..." passes in the required `test-webplat` CI check
  cadence: every PR run and every merge_group run
  alert_target: a red required check (merge queue ejection) plus the follow-up count comment on #9670
  configured_in: .github/workflows/ci.yml (test-webplat job; unchanged by this plan)
error_reporting:
  destination: the vitest assertion message in the GitHub Actions job log
  fail_loud: true - the message carries pid, last /proc state, waited ms and loadavg so a recurrence is classifiable without reproducing
failure_modes:
  - mode: runner stall longer than the 15s bound
    detection: last probe state is S (alive) with a high loadavg and waited ~15000ms
    alert_route: red check; count on #9670
  - mode: product regression (group kill removed or detached dropped)
    detection: same message, but reproducible on every run and in the local mutation run
    alert_route: red check on every PR
logs:
  where: GitHub Actions job logs for test-webplat
  retention: GitHub default (90 days)
discoverability_test:
  command: grep -c "timeout: 15_000" apps/web-platform/test/server/inngest/cron-claude-eval-substrate-exit.test.ts
  expected_output: 1
```

## Domain Review

**Domains relevant:** none

No cross-domain implications detected - test-only reliability fix (engineering/CI hygiene); no
UI, schema, infra, credential, legal or GDPR surface touched.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty or placeholder fails deepen-plan Phase 4.6;
  this one carries `threshold: none` with a reason because the diff is confined to `test/**`.
- Do not "fix" the flake by loosening the product: the group kill must stay a synchronous
  `SIGKILL` in the `exit` handler; the sleeper surviving is exactly the credential-read window
  #7122 P2-1 closes.
- Parse `/proc/<pid>/stat` state after the LAST `)`; zombie ('Z') must stay "dead" (containers
  without an init never reap a killed orphan; see the chromium-zombie learning).
- Local load does not reproduce the CI failure at baseline (measured). Do not claim "50/50 green
  proves the fix"; claim "50/50 green under load plus the 15s bound plus the probe-race fix plus a
  RED mutation of the product kill". The root cause of the single CI failure is not proven; the
  self-attributing message exists so the next occurrence can be classified.
- The probe-race fix has no deterministic RED test by design (R1/R11 trade-off after panel review);
  do not reintroduce a helper + DI unit file without new evidence.
- `{ repeats: 50 }` is a temporary verification aid: it must not be present in the committed diff.

## Addendum — 2026-10-07 (review round on #9697)

Supersedes parts of R11, AC2 and the Sharp Edge "no deterministic RED test" above (those are kept as written):

- The review panel's test-design seat measured that an always-false oracle, an `S`-is-dead oracle and a first-paren parser all passed the file with the product kill removed. Three inline control rows (`isAlive oracle controls`: a live process with comm `sleep`, one with comm `x) Z y`, and an unreaped zombie) now give those a deterministic RED. Mutants killed: always-false, S-is-dead, first-paren `indexOf`, Z-blind, `kill(0)`-only. No helper file or injected-deps unit file was added, so the R1 decision stands.
- Still unpinned, by design: the EPERM branch (needs a process of another uid; equivalent for a same-uid fixture), the `/proc` vanished-between-calls branch (race only), and `procIsOurs` (needs a foreign pid namespace).
- The real-process row bounds only that the group is eventually dead; that the kill was issued before the spawn resolves is owned by the mocked P2-1 rows.
