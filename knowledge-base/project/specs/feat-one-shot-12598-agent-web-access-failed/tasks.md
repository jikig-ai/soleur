# Tasks: tell the agent when its session's web access failed to start (#12598)

Plan: `knowledge-base/project/plans/2026-11-19-feat-tell-agent-web-access-failed-to-start-plan.md`.
Rulings: `decision-challenges.md` in this directory (T1 to T4, T1-r, T3-r1, T3-r2, AC8-r, L1 to L4).

## Phase 1: Setup

- [x] 1.1 Read `apps/web-platform/server/cc-dispatcher.ts`: `WEB_EGRESS_PROMPT_ADDENDUM`, the forwarder spawn block
      (`feat-open-web-egress (#9534) — spawn the per-session loopback forwarder`), the `#12469` prompt-suffix block, and the
      `systemPrompt:` expression.
- [x] 1.2 Read `apps/web-platform/test/cc-dispatcher-real-factory.test.ts`: the `web egress entitlement (#9534)` describe
      and the #12469 suite's `entitled + DEGRADED forwarder` case.

## Phase 2: Tests first (RED)

- [x] 2.1 Extend `entitled + spawn failure`: the line appears exactly once; `## Web access enabled for this session` is absent;
      the prompt contains `failed to start` and `` `WebFetch` is unavailable ``; it does not match
      `` /WebFetch`? (is|are) (still )?available/ `` (Test Scenario 1, AC4, AC7).
- [x] 2.2 Extend `entitled + spawn OK`, `unentitled (default)` and `entitled but support persona`: the line is absent
      (Test Scenarios 2 to 4, AC5).
- [x] 2.3 Extend the #12469-suite `entitled + DEGRADED forwarder` case: the line appears exactly once and every existing
      assertion is kept (Test Scenario 5, AC6).
- [x] 2.4 Run the suite and confirm rows 1 and 5 fail for the right reason (rows 2 to 4 are absence checks; they pass
      now and are proven in 4.1).

## Phase 3: Core Implementation (GREEN)

- [x] 3.1 Add `WEB_EGRESS_START_FAILED_PROMPT_LINE` (non-exported, with its `#12598` comment) after `WEB_EGRESS_PROMPT_ADDENDUM`,
      with the exact text in the plan's Proposed Solution step 1.
- [x] 3.2 Add `let webEgressStartFailed = false;` beside `let webEgress`; set it to `true` only inside the spawn `catch (err)`,
      after `reportSilentFallback`.
- [x] 3.3 Append ``(webEgressStartFailed ? `\n\n${WEB_EGRESS_START_FAILED_PROMPT_LINE}` : "")`` after `githubReadPromptSuffix`
      in `systemPrompt:`; insert nothing between the web-egress ternary and `githubReadPromptSuffix`.
- [x] 3.4 Update the two comments that list the degraded state's behaviour (above the spawn and above `systemPrompt:`).

## Phase 4: Verification

- [x] 4.1 After the GREEN change is committed, apply EVERY mutation in the plan's mutation table one at a time (six rows,
      including `!readRegistration?.registered`), confirm the named rows red, and restore with
      `git restore apps/web-platform/server/cc-dispatcher.ts` (or run them in a `scripts/soleur-sandbox.sh` copy).
- [x] 4.2 Run the AC1 and AC2 commands.
- [x] 4.3 AC8: from `apps/web-platform`, run
      `npx vitest run $(grep -rln --include='*.test.ts' spawnEgressForwarder test/) test/cc-github-read-prompt.test.ts test/web-egress-prompt-addendum.test.ts test/egress-audit-agent-surface-absence.test.ts`
      and `npx tsc --noEmit`.
- [x] 4.4 AC9: `git diff --name-only origin/main...HEAD` shows only the two code files and this feature's plan and spec
      files. The PR body says `Closes #12598` and puts #12572 in no closing keyword.
