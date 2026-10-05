# Tasks: fix merge queue slow ejecting failures

Plan: knowledge-base/project/plans/2026-10-05-fix-merge-queue-slow-ejecting-failures-plan.md
Ref #9482 (never Closes). Closes #8785 and #9170 in the PR body only when their ACs pass.

## Phase 1: Setup and verification of premises
- 1.1 Re-pull the two headline figures the PR body will quote (4/27 ejections, window demand 4,435 vs 3,900 job-min) with the plan's Measurement recipe.
- 1.2 Confirm PR #9511 is still open/merged and do not touch ADR-270 or merge-queue-canary-log.md.

## Phase 2: Core implementation
- 2.1 Vendor Inter (cause A, #8785)
  - 2.1.1 Download the latin variable woff2 to apps/web-platform/assets/fonts/inter-latin-wght.woff2; verify size 48,256 and sha256 from the plan.
  - 2.1.2 Write assets/fonts/README.md (source URL, v20, OFL pointer, sha256, regenerate command, frozen-asset statement).
  - 2.1.3 Write test/no-network-fonts.test.ts first (Guard 1, RED against current fonts.ts), then switch app/fonts.ts to next/font/local (weight "400 600", adjustFontFallback "Arial").
  - 2.1.4 Repoint the three vi.mock("next/font/google") sites to next/font/local (default export).
  - 2.1.5 Verify offline serving (unshare -cn/-rn, else CSS has no fonts.gstatic.com), .next/static/media after next build, .dockerignore does not exclude assets/.
- 2.2 playwright.config.ts: switch both webServer entries from port to url (/login); verify /login on :3100 does not need the mock Supabase, else use the inline globalSetup fallback; prove with a deliberately broken layout import (fails within about 2 min).
- 2.3 otp-login.e2e.ts: add the filtered noAccountBanner helper at the three sites; negative control with a route delay.
- 2.4 reap-archive-persistence.test.sh: print SOLEUR markers and git log -5 in the fixture G failure message.
- 2.5 merge-queue-dequeue.md: 2 to 3 line advisory-red note.

## Phase 3: Testing
- 3.1 Run the Guard 1 mutation rows 1 to 6 and the harness rows; record results in the PR body.
- 3.2 Run the web-platform vitest project and the full e2e once locally; confirm CI e2e has 0 failed and none of the three log signatures.
- 3.3 python3 scripts/lint-guard-contract.py and markdown lint.

## Phase 4: Tracker updates (agent-run, after the PR is open)
- 4.1 One consolidated #9482 comment (Task 1 and Task 3 tables, 4/27 ejection rate, auto-merge-stays-armed finding, #9190/#7376 notes, PR-churn finding).
- 4.2 #8785 evidence comment; #9167 mock-noise comment (read attempt-1 log of run 36449125669 before recommending closure); #9512 numbers comment.
- 4.3 Re-measure note: after the next 20 merge_group runs, repeat the recipe and post the delta.
