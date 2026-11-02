# Learning: the review-round fixes were the defective part, and six CI guards were invisible to every local suite

## Problem

PR #11289 (durable, action-bound approval requests, issue #4672) went through a 16-seat review, two fix rounds and two verification panels. Three patterns repeated, each already named in the review skill and each still recurring:

1. **Fixes were the least-audited and most defective surface.** The first fix round introduced an erasure alert whose two emitters passed an `Error` to `reportSilentFallback` (the pino mirror steals the capture, so the alert could never fire), a `verify/180` row that would have blocked every later release on a CLO-accepted residual, a sticky `enforcing` check that covered 3 of 8 tools, and a production gate factory (`createApprovalGateDeps`) that no test exercised un-injected. The CLO's round-2 ruling also contradicted its own round-1 ruling (canary gate vs attestation) and was caught only by an independent legal-audit seat.
2. **Delegated agents stalled mid-task.** Implementation agents ended turns on a statement of intent ("Now the registrations.") and reported `completed`. A resume with an identical brief produced the same stall; a fresh agent with a shorter, tool-first brief finished.
3. **Six CI guards were invisible to the local battery.** Local `tsc`, vitest and semgrep were green. CI failed ESLint `no-misleading-character-class` (combining characters in one regex class), CodeQL `js/insecure-temporary-file` (a `"/tmp/none"` test literal treated as the OS temp dir, flowing through `buildKbShareTools({ kbRoot })` to an `fs.open` in an untouched file), the userId-emission guard (`hashUserId(userId)` still contains the bare word `userId`), the service-role allowlist gate, the feature-map coverage lint and the sibling-set sweep (a manifest change obliges touching both parity tests).

## Solution

- Every fix round got its own verification panel that audited the NEW assertions before the new code, and each fix was mutation-checked in a sandbox.
- Stalled agents were respawned with a short brief that ends "keep calling tools until the final report is written", and file ownership was disjoint so only the lead committed.
- The CI-only guards were reproduced locally from the failing job's script (read the step that failed via the jobs API, run its command), fixed at the cause, and the CodeQL flow was found by downloading the analysis SARIF (`gh api -H "Accept: application/sarif+json" .../code-scanning/analyses/<id>`) and printing the code flow.

## Key Insight

A green local battery answers "do the suites I selected pass", never "does every repo-global guard pass". Before the first push of a PR that adds an alert, a route, a cron, a service-client importer or a regex, run the repo-global lints the diff's file classes trigger (ESLint over the changed files, `lint-feature-map-coverage.sh`, `service-role-allowlist-gate.sh`, the userId diff-grep, `check-sweep-completeness.sh` with an explicit changeset). And treat every fix commit as new code: the defect class a fix closes is the one most likely to be reintroduced inside it.

## Session Errors

1. **Delegated agents ended turns on an intent statement and reported completed (x5).** Recovery: resume once, then respawn fresh with a tool-first brief. **Prevention:** brief every delegated unit with "do not end a turn on a statement of what you will do next; keep calling tools until the final report is written", and treat a second identical interim result as a stall to respawn, not resume (review SKILL already states the resume-then-respawn rule).
2. **`beforeEach(() => mock.mockReset())` returned the mock, which vitest calls as a teardown.** It threw the test's own mocked rejection in an unrelated test. Recovery: braces, so the callback returns nothing. **Prevention:** never use an expression-bodied `beforeEach`/`afterEach` arrow whose expression returns a function.
3. **PreToolUse hook denials (git add of a moved path, `ps | awk` self-match, `rm -rf` of a tmp path while the cwd was the worktree) and a `cd ..` into the wrong directory.** Recovery: re-issue as separate, corrected calls. **Prevention:** already hook-enforced; do not chain `cd ..` in compound commands in a worktree.
4. **Six repo-global CI guards red while the local battery was green.** Recovery: reproduced each from the failing step's own script and fixed at the cause. **Prevention:** before the first push of a guard-heavy PR, run the repo-global lints listed in Key Insight; use the failing job's step name from `gh api repos/<o>/<r>/actions/jobs/<id>` rather than grepping the log.
5. **Fix commits reintroduced the defect classes they closed (alert emitter, verify row, partial enforcement, unpinned factory).** Recovery: a verification panel per fix round, mutation-checked. **Prevention:** audit new assertions before new code; ask of every fix "which input makes this pass while the property is violated".
6. **A CLO ruling contradicted its own earlier ruling.** Recovery: independent legal-audit seat found it; the CLO resolved it. **Prevention:** have an independent seat read round-N rulings against round-N-1 rulings before applying them.
7. **Local Playwright install hung on a lock and `affected-index-ratchet` was red on clean main (a stale baseline line from #11454).** Recovery: INFRA-BLOCKED per the qa skill, CI is authoritative; the ratchet failure reproduced on a clean `origin/main` worktree, so it was not bundled. **Prevention:** reproduce a red check on a clean main worktree before touching it.

## Tags
category: workflow-issues
module: approval-queue
