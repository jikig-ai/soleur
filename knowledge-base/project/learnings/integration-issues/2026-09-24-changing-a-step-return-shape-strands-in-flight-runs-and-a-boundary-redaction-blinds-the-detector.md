---
title: Changing an Inngest step's return shape strands in-flight runs, and a redaction added at the step boundary blinds the detector behind it
date: 2026-09-24
category: integration-issues
module: apps/web-platform/server/inngest
tags: [inngest, step-boundary, memoization, deploy, leak-tripwire, review]
issues: [8726, 8762, 8764, 8783]
---

# Learning: two defects the plan review missed and the review panel caught

## Problem

PR #8758 (#8726) moved two verdicts across the Inngest step boundary as returned values instead of
caught error classes (`instanceof` on an error thrown inside `step.run` never matches: the handler
gets the SDK's rebuilt `StepError`). A 9-seat plan review and a green TDD run shipped two new P2s,
both found only by the post-implementation panel:

1. **In-flight runs on the old shape.** The PR changed what `setup-workspace` and `drift-check`
   RETURN. Inngest has no function versioning here: a run that memoized `setup-workspace` under the
   old code and resumes on the new code after the deploy reads the OLD value. The deploy drain waits
   only for a live `claude` process, then swaps the container exactly as a heavy cron moves to its
   last steps — so the first deploy of this PR would have landed a run in that state. The new code
   read `verdict.workspace.ephemeralRoot` off a bare `{ephemeralRoot, spawnCwd}` and threw a
   TypeError outside every catch: no heartbeat, no teardown, the day's output lost.
2. **A redaction added at the boundary blinded the detector behind it.** To keep secrets out of
   Inngest run state, the fix rethrew non-leak errors from `drift-check` as `redactedError(err)`.
   But a PEM in a *thrown* error (e.g. from key loading) was previously caught downstream by the
   issue-body tripwire and filed as `[security/leak-suspected]`; redacting it first removed exactly
   the text the tripwire keyed on, so a real leak was filed as a routine `github_api_network`
   failure. Fixed by testing the error itself (`errorCarriesLeak`: message, stack, cause chain to
   Inngest's serialization depth) and taking the leak arm on a hit.

## Solution

- `unwrapSetupVerdict(stored, cronName)` accepts both `WorkspaceSetupVerdict` and the pre-#8726 bare
  `EphemeralWorkspace`; `readDriftCheck` and null-safe folds do the same for the drift guard. Tests
  seed the old memo shape through `runLikeInngest` (S8 fails 8/8 crons without the shim; S9).
- `drift-check` decides every verdict while the error is live: leak (instance OR carried text) →
  returned leak verdict; non-final attempt → rethrow for the retry; final attempt → report once with
  the live error name and return a `github_api_network` failure. The handler-level catch, which
  reported the same failure four times across re-entries, is gone.

## Key Insight

**A change to what a step RETURNS is a change to persisted state.** Memoized step output outlives
the code that wrote it, so the reader must accept every shape a live run can hold — the same
discipline as a DB migration, with no migration runner to remind you. And **a scrub added upstream
of a detector changes what the detector can see**: before redacting at a boundary, list what
downstream reads the unredacted text, and decide there instead.

## Session Errors

1. **Scratchpad `mktemp` failed (plan phase, forwarded)** — Recovery: created the dir. — Prevention: one-off.
2. **Follow-up issue blocked until `meta/machinery` label (plan phase)** — Recovery: added the label. — Prevention: already hook-enforced.
3. **`sleep`/`pgrep` waits blocked by hooks (plan phase)** — Recovery: bounded loop. — Prevention: already hook-enforced.
4. **Reviewer's 23-caller count (plan phase)** — Recovery: rejected after grep (6 local definers). — Prevention: already covered (verify counts).
5. **Relative scratchpad path failed** — Recovery: absolute path. — Prevention: use the absolute scratchpad path always.
6. **Pre-commit `bun-test` queued ~10 min behind sibling full-gate runs** — Recovery: killed only my own run (`proc.sh kill_mine`), confirmed the commit had not landed, re-committed with `LEFTHOOK_EXCLUDE=bun-test` after targeted suites passed. — Prevention: check `test-all.sh --capacity` before a `.ts` commit on a contended box; the operator prefers relying on CI's required `test` context over a queued local battery (stated 2026-09-24).
7. **Implementation-exit affected gate queued; skipped at operator direction** — Recovery: killed own run, CI is the gate. — Prevention: as 6.
8. **Tried to write Claude memory; blocked by `hr-never-write-to-claude-code-memory-claude`** — Recovery: recorded here instead. — Prevention: already hook-enforced.
9. **Drift-guard test runner dropped `attempt`/`maxAttempts`, so S5d saw no retry** — Recovery: pass the harness ctx through. — Prevention: a `runLikeInngest` lambda must forward `attempt`/`maxAttempts` whenever the handler reads them.
10. **Two PR-introduced P2s missed by the plan review (old memo shape; boundary redaction blinding the tripwire)** — Recovery: fixed inline with harness tests that fail without the fix. — Prevention: plan Sharp Edge added (see Route-to-definition below).
11. **Unmeasured prose shipped (ADR-126 mechanism, ADR-078 citation and NonRetriableError reason, census comment scope, S6b passing via another step)** — Recovery: corrected from the panel's measurements. — Prevention: already covered by the review skill's "falsify every sentence the diff adds".
12. **Three review seats wrote probe files into the shared worktree despite a report-only brief** — Recovery: each deleted its file; tree verified clean. — Prevention: already covered (`isolation`/detached worktree guidance); restate "no files, even temporary" in the brief.
13. **semgrep partial-parse errors on existing test files** — Recovery: confirmed all production files scanned. — Prevention: one-off (tool limitation).

## Route-to-definition

`plugins/soleur/skills/plan/references/plan-sharp-edges.md`: a plan that changes a durable step's
return shape or id must specify how the new reader handles the old memoized value.
