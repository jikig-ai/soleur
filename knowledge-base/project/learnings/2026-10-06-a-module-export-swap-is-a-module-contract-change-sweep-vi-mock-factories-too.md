---
title: "A module-export swap is a module-contract change — sweep `vi.mock` factories like call sites, and every comment fix is a claim a reviewer will falsify"
date: 2026-10-06
category: workflow-issues
tags: [vitest, vi-mock, module-contract, blast-radius, review-round, comment-accuracy, cc-dispatcher, readCurrentRepoUrlResult]
issue: 9556
pr: 9630
branch: feat-one-shot-9556-9557-handoff-prefill
---

# Learning: swap the export, sweep the mock factories — and treat a comment fix as a falsifiable claim

## Problem

A review suggestion swapped `cc-dispatcher.ts`'s Promise.all slot from
`getCurrentRepoUrl` to the degrade-aware `readCurrentRepoUrlResult` (so a
transient repo_url read failure could emit `undefined` — the honest legacy
caveat arm — instead of a false `repoConnected: false`). The code edit was
small and correct. The sweep was not: I updated the ONE test file I had
touched (`cc-dispatcher-real-factory.test.ts`) and missed the other two
suites that both `vi.mock("@/server/current-repo-url")` AND invoke
`realSdkQueryFactory` — `cc-dispatcher-warm-presandbox-mkdir.test.ts` and
`cc-dispatcher-prefill-guard.test.ts`. Both went red: `No
"readCurrentRepoUrlResult" export is defined on the
"@/server/current-repo-url" mock` — 4/4 and 12/12 failures, caught by two
fix-round seats running `realSdkQueryFactory` call-site sweeps.

## Symptoms

- `[vitest] No "readCurrentRepoUrlResult" export is defined on the
  "@/server/current-repo-url" mock` inside the unconditional `Promise.all`
  at `cc-dispatcher.ts:1845` — every factory-reaching test rejects.
- The blast-radius sweep enumerated test files that import the SUT, not
  mock factories that replace the module the SUT now calls differently.

## Solution

1. When a change swaps **which export** a SUT calls from a module, the
   consumer sweep must cover both shapes:
   - `git grep -l "<newExport>\|<module-path>"` — call sites, AND
   - `git grep -l 'vi.mock.*<module-name>' -- test/` — mock factories,
     each then checked for whether its SUT reaches the call (factory
     mocks that never reach the new export are safe).
2. Mock the new export by **delegating to the existing spy**, so per-test
   `mockResolvedValue` fixtures keep working:
   `readCurrentRepoUrlResult: async (u, w) => ({ url: await
   mockGetCurrentRepoUrl(u, w), degraded: false })` — or, where no hoisted
   spy exists, one factory-local impl shared by both exports so the two
   views of one read cannot diverge.
3. Pin the new arm in the suite that owns the emission point (T15b reads
   `ctx.deps.repoConnected` through the real `createCanUseTool` call).

## Key Insight

- **A mock factory IS a consumer.** `git grep -l <SUT>` finds files that
  import the SUT; it misses files that import *the module the SUT
  changed against*. The consumer-grep must be run for BOTH the new symbol
  and the module path, and mock factories triaged by reachability, not
  file list.
- **Every comment edit is a claim.** Three round-2 findings were comments
  *my fix commits* introduced: "in production every support deny carries a
  concrete boolean" (falsified by the same commit's degraded arm), an
  "earlier-ordered effect" rationale that ignored the consumer's
  `status`-gate, and a verbatim quote that drifted one word off its
  source. The falsifier is the same for code and prose: name the command
  that would disprove the sentence and run it before shipping the comment.
- **React-effect latch tests need a dep change to discriminate.** Under
  `[prefill]` deps, clearing the composer and rerendering the *same*
  prefill value cannot re-fire the effect — the latch's load lives only on
  a `prev !== next` prop change into an empty composer. A same-string
  rerender is green on the unlatched mutant; a distinct third value reds
  it.

## Session Errors

**`test-all.sh --affected` reaped mid-queue**

- **Recovery:** Re-ran under `setsid` with a persistent `.rc` capture; the
  second attempt queued correctly (`LOCK_WAIT_HEARTBEAT`) and completed
  `161/578` green.
- **Prevention:** Launch gate runs detached (`setsid` + rc file) when the
  parent shell may not outlive the queue; treat no-marker/no-rc as
  "harness reap", never as pass or fail.

**Two review seats rate-limited on first spawn**

- **Recovery:** Re-spawned after the documented reset; both returned.
- **Prevention:** Gate 2b's prescribed fallback covers this — partial
  substantive output proceeds; a gap-closing re-spawn is cheap after the
  reset passes. No rule change.

**Export-swap missed two consumer mock factories (the P1)**

- **Recovery:** Added delegating/shared `readCurrentRepoUrlResult` exports
  to both suites; 16/16 green.
- **Prevention:** Add the mock-factory arm to the blast-radius sweep — see
  Key Insight 1.

**Latch test strengthened with a non-discriminating step**

- **Recovery:** Post-clear rerender uses a distinct third prefill value.
- **Prevention:** Mutation-check the step before claiming discrimination:
  which mutant does it red? (test-design seat's own question.)

**Fix comments introduced new false claims (three sites)**

- **Recovery:** Re-worded to enumerate the degraded arm, dropped the
  unsound ordering rationale, matched the quoted source's case.
- **Prevention:** Falsify every causal/universal sentence the diff adds —
  see Key Insight 2.

**`cd ..` then `git add <wrong path>`; `perl` rename ran before the
"flag"→"record" fix**

- **Recovery:** Re-staged from the worktree root; fixed the compound
  identifier in the same edit.
- **Prevention:** One-off shell slips; compose multi-step renames in a
  single edit tool call rather than sequential regexes.

**`fix-round-seats.sh --finding-seats` rejected two seat names**

- **Recovery:** Re-ran with the accepted leaf names; the resolved set was
  identical via path-mapping anyway.
- **Prevention:** One-off usage error — the script's `--help` documents the
  accepted leaves; read it before guessing names.

**Affected-gate queue contention (positions 7→5)**

- **Recovery:** Waited under `setsid`; first run was reaped, second queued
  to completion; post-fix re-run left queued — targeted suites carry the
  fix-delta evidence.
- **Prevention:** Documented class (#9505 learnings) — read `--capacity`
  first; when queued, rely on touched-suite runs rather than racing a fix
  commit. No new rule.

## Forwarded errors (from session-state.md)

- Write-scope deviation (disclosed, gate-required): committed the `.pen`
  wireframe under `knowledge-base/product/design/`.
- Planning fan-outs ran as inline sequential-fallback (no spawn surface);
  `Reviewed-Coverage: sequential-fallback` recorded in the plan.
- Deepen corrections applied in-file: retired rule-ID citations, path fix,
  AC3 count fix.
