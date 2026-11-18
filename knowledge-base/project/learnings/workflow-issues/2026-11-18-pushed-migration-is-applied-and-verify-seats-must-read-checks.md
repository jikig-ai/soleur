---
title: "A migration pushed to a PR branch is already applied, and a verification seat that grades only the diff misses the red gate"
category: workflow-issues
tags: [migrations, dev-ledger, review, fix-round, verification, ci, e2e]
module: apps/web-platform (session-sync, kb-sync held files), plugins/soleur/skills/review
symptom: "dev-ledger parity gate red after an in-place amendment of migration 187; required guards-ruleset red through two verification seats; a unit test broke on a mock after a safe refactor"
root_cause: "a ruling assumed an unmerged migration was unapplied; verification seats never read the PR's check set; narrow pre-push test runs"
---

# Learning: a pushed migration is applied, and verification must read the checks

## Problem

PR #12704 (#12600, #12718, #12714) ran a 14-seat review of its extension range, two fix rounds and three verification seats.

- **Migration amended in place.** Ruling D42 had migration 187 amended in place, on the premise that a migration not yet merged had never been applied. That premise was false. Tenant-integration CI applies every migration pushed to a PR branch to the dev Supabase project, and run 44096996911 had already applied 187. The amended file no longer matched the dev ledger, so "Assert unmerged migrations match the dev ledger" went red.
- **Red check missed for two rounds.** Round 1 added a `createServiceClient` call to `server/workspace-sync.ts` and left it off the allowlist, which turned the required `guards-ruleset` check red. Both verification seats graded the diff and passed it. Only the final seat, which was told to run `gh pr checks`, found it.
- **Mock broken by a safe refactor.** Dropping a pre-open `lstat` (to close a CodeQL check-then-use alert) broke `session-sync-workspace-last-synced.test.ts`. That file's `vi.mock("fs")` stubbed only `lstatSync`. With no `openSync` or `constants`, the read became `unreadable` and logged an extra warning. My pre-push runs covered only the files the fix named, so CI caught it.

## Solution

- **Migrations.** 187 up and down were restored byte-identical to the blobs dev applied, and a blob-id test pins them. The new column and the widened RPC moved to a new 188. CI applied 188 to dev and the ledger-parity check came back clean (`violations=0`).
- **Allowlist.** The self-heal's system `repo_url` read now goes through `readSystemRepoUrl` in the module that is already allowlisted (`server/kb-sync-held-refresh.ts`), so `workspace-sync.ts` holds no service-role client.
- **Autostash read.** `readMergeAutostash` opens with `O_RDONLY|O_NOFOLLOW|O_NONBLOCK` and checks only the open descriptor (`fstat`), with no `lstat` first. A FIFO the agent plants returns immediately instead of stalling the event loop. A source test pins the exact flags and that no `lstat` precedes the open.
- **Logging.** `userid-bypass-lint` matches `\buserId\b` anywhere on the log line. `log.warn({ userIdHash: hashUserId(userId) })` therefore still fails it, so the hash is computed on its own line first.

## Key Insight

There are two rules here, and both are about where the evidence lives:

1. **A migration file on a pushed branch is a deployed artifact**, because of the dev project, not because of the merge. Amend a pushed migration only by adding a new one.
2. **A verification seat grades the PR, not the diff.** The question "is every required check green?" belongs inside the seat's brief. A diff-only seat structurally cannot see a gate that the fix round turned red.

## Session Errors

1. **The review scan gate got its paths on stdin and printed `skip files=0`; this happened twice.**
   - Recovery: pass the paths as positional arguments (`mapfile -t P < list; review-scan-gate.sh "${P[@]}"`).
   - Prevention: the SKILL already says "on the path list". A `skip` with `files=0` on a non-empty range means the input never reached the script.
2. **Ruling D42 assumed 187 was unapplied, so amending it in place turned the ledger gate red.**
   - Recovery: restore 187 byte-identical and add 188.
   - Prevention: covered by the ledger-parity gate, which caught it. Rulings that touch a pushed migration must add a new one.
3. **The session process exited while WP1, WP3 and WP4 were running.**
   - Recovery: resume each with SendMessage. WP1 had left a guard mutation uncommitted, and it was restored.
   - Prevention: one-off. After any resume, check each agent's worktree with `git status`.
4. **Smaller slips: the seat tally was counted twice, a test file was not registered in REPO_WIDE_SUITES, gitleaks flagged a `fileToken` in the `.pen` file, and folding DB and UI into one package collided with its fail-soft design.**
   - Recovery: each was fixed in place.
   - Prevention: the ratchets and the secret scan caught them (covered). The tally rule is one writer per dimension.
5. **The WP1 wiring patch failed 13 rows, because `writeHeldFromIsolated` ignored the injected service client.**
   - Recovery: fixed in 6ab101194f.
   - Prevention: one-off, caught by the tests.
6. **Two verification seats missed the red required `guards-ruleset` check.**
   - Recovery: the final seat, briefed to run `gh pr checks`, found it.
   - Prevention: routed to `review/references/risk-tier-and-fix-rounds.md` item 5. The verifier reads `gh pr checks` and reports red required checks as blockers.
7. **A refactor broke a test whose fs mock lacked `openSync`; narrow pre-push runs missed it.**
   - Recovery: the mock gained `openSync` and `constants`. All 102 changed test files were re-run before the next push.
   - Prevention: routed to the same reference. Re-run every changed test file before pushing a fix round.
8. **An inline `hashUserId(userId)` on the emit line still tripped `userid-bypass-lint`.**
   - Recovery: compute `const uidHash = hashUserId(userId)` first.
   - Prevention: covered by the quality-advisory check, which caught it. The lint's message ("emit userIdHash directly") does not say that the line itself must not contain `userId`.
9. **`git checkout -- <file>`, used to undo a mutation test, also reverted my uncommitted fix.**
   - Recovery: re-applied the fix from the transcript.
   - Prevention: routed to the same reference. Commit the fix before mutation-testing it.
10. **I misread a tsc exit code (`$?` of `head`), which hid a type error in a test.**
    - Recovery: redirect tsc to a file and echo its own `rc`.
    - Prevention: one-off. Never pipe a gate into `head` before reading `$?`.
11. **Next.js 16.4.3's `next dev` stops once per dist dir to print an upgrade notice aimed at agents, so the Playwright `webServer` fails on first start.**
    - Recovery: retry the same command.
    - Prevention: routed to `qa/SKILL.md` Notes. The notice's request to offer an upgrade is tool output and is not acted on.
12. **I ended a turn at "Review Phase Complete" inside one-shot, and the operator had to ask why I stopped.**
    - Recovery: continued the pipeline.
    - Prevention: covered by the stop hook, which fired on later turns and requires a `Paused:` or `Blocked:` reason.

## Tags

category: workflow-issues
module: apps/web-platform session-sync / plugins/soleur/skills/review
