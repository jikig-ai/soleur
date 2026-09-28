---
title: My pager read its verdict from bytes the tenant could write
date: 2026-09-28
category: security-issues
module: web-platform/git-data observability
tags: [sentry, alerting, forgery, git, observability, legal-markers, test-design]
issues: ["#8572", "#8211", "#9152", "#9154", "#9160", "#9161"]
pr: "#9150"
---

# Learning: my pager read its verdict from bytes the tenant could write

## Problem

PR #9150 (#8572) made the web app page on git-data host-key pin faults. It added a `pin_fault` Sentry tag, a new rule `git-data-host-key-pin-fault`, and per-event re-paging on `art17-erasure-incomplete`. The implementation was mutation-tested (32 of 32 rows matched) before review. The 12-seat review then found four defects, each of a class the PR existed to prevent:

1. **The pager was forgeable by a tenant.** `classifyGitDataPinFault` returned `host_key_mismatch` for the git push on `exit 128` plus the unanchored `SSH_HOST_KEY_MISMATCH` regex matching stderr. Git exits 128 on *every* fatal error, and it echoes a malformed `.git/packed-refs` line verbatim (`fatal: unexpected line in .git/packed-refs: Host key verification failed`). The push runs with `cwd` set to the tenant's workspace, and the agent sandbox can write that file. The forged event's message was byte-identical to a genuine provision-dial mismatch, so it grouped into the same Sentry issue. Under the rule's 240-minute per-issue throttle, a forgery repeated every 4 h would also **mask** a real host re-key. That is worse than a false page.
2. **The observability helper could throw inside a catch.** `reportGitDataPinFault` runs in `replicateToGitData`'s catch block. A throw from `withIsolationScope`, `clearBreadcrumbs` or pino would replace the push error and skip both the rethrow and the Error-path report. Its `typeof` fallback also captured in the **ambient** scope, which is the scope it existed to avoid, because it carries other sessions' breadcrumbs.
3. **The single-writer census stripped comments with a hand regex.** `test/helpers/strip-comments.ts` exists because that regex opens phantom blocks on `/*` inside strings. Over the census's own walk it hid real code in 12 files. The census also missed `setTag("pin_fault", …)`, computed keys and root entry points (`sentry.server.config.ts`). The HCL stripper ignored `/* */`, so `enabled = false /* enabled = true */` stayed green. The test-design seat drove 20 new mutants and 16 survived.
4. **The prose claimed mitigations that did not exist.**
   - The plan said "the runbook's post-resolve query covers" the Art. 17 throttle window. The only query named was `pin_fault:*`, and erasure events are untagged by design, so that query can never see them.
   - The runbook's `scripts/sentry-issue.sh` has no query mode.
   - ADR-220 described an unbuilt flip check in the present tense.
   - The CLO markers said "never one email per refusal", but the throttle is per issue per 5 minutes.
   - The CLO markers said "fresh isolation scope", but `withIsolationScope` forks the scope.
   - The CLO markers said the `pin_fault` query covered erasure faults.

## Solution

- **Read host identity only where no tenant input reaches.** `host_key_mismatch` is now classified only on `via="ssh"` (the provision dial, exit 255: no cwd, `-F /dev/null`, validated argv), never off git's stderr. Nothing genuine is lost, because the provision dial runs first on the same host, pin and client. The fetch path (`git fetch` in the workspace) is documented as never read for host identity, for the same reason. Tests assert the packed-refs forgery and a git 255 both fall to the Error path.
- **Never throw, and never fall back into the hazard.** `reportGitDataPinFault` wraps the scope in try/catch. A `reported` flag prevents a double log, and the fallback is **pino only**. The `extra` type (`GitDataPinFaultExtra`, `userId?: never`) refuses a raw `userId`, so the push hashes it at the call site and the pino-only path cannot leak it.
- **Census with the scanner, on the bare token, with an exact call count.** The census now:
  - uses `stripComments` over `server`, `app`, `lib`, `components`, `hooks` and the root `*.ts`;
  - matches `/\bpin_fault\b/` in code only in the writer;
  - requires exactly 4 `reportGitDataPinFault(` calls in `git-data-replication.ts`, since a fifth on the erasure path would page one refusal through both rules.

  The HCL stripper removes `/* */`, attributes must appear exactly once, and the `in` value must equal the sorted `join(",")`. The battery is 51 of 51.
- **Every "covered by" names a runnable command.** The runbook now carries:
  - a curl pin-fault query (`has:pin_fault`, `statsPeriod=4h`);
  - Art. 17 steps for the 5-minute window: re-list events before resolving, and rerun the erasure query more than 5 minutes after;
  - resolve-never-archive in the general sweep step;
  - a Better Stack read for non-pin push failures.

  The archived-issue detector is deferred to #9160. The CLO corrected the markers (word-diff removal 0 against the merge base).

## Key Insight

**A classifier's input is trusted only as far as its least-trusted writer.** "Exit code plus stderr text" feels like a transport signal, but git's fatal channel is a *mixed* stream: git's own diagnostics plus bytes quoted from files the tenant controls. When the verdict feeds a pager, a forgery does more than add noise. It joins the genuine issue and inherits its throttle window, so the attacker's cheapest move is to *suppress* the real alarm. Before trusting any free-text channel, list every writer that can reach it: here that meant the process's cwd, the files that process quotes, and the remote's passthrough. Then read the verdict from the one channel that has none.

The second insight is about the review, not the code. A 32 of 32 battery certified the axes I thought to vary: values, triggers and codes. The survivors lived on axes I never varied: *where* a writer lives, *which comment syntax* hides a setting, and *which scope* a capture runs in. A battery says nothing about the axes its rows do not name.

## Session Errors

1. **Issue premise wrong** (forwarded from plan): the push report used the Error path, so its tags were dropped (#8629) and a rule keyed on its op would never fire. Recovery: the message-path emitter in the plan. **Prevention:** before planning an alert on a tag, confirm the emitter's report path with `reportSilentFallback(err` versus `(null`, and cite #8629.
2. **CTO claim false** (forwarded): "any-short across two tag keys never exercised". Recovery: corrected in deepen with `zot_mirror_fallback_rate`. **Prevention:** grep `issue-alerts.tf` for the construct before accepting a "never exercised" claim.
3. **`gh issue create` hook-blocked, four times across the session.** The causes were: a body file in the same command as a heredoc (the whole command is blocked, so the file never exists), a path the gate cannot read, and a missing `User-Impact:`, `Mandated-By:` or `meta/machinery` label. Recovery: write the body with the Write tool in a separate step, and add the line or label. **Prevention:** always write the body file first with Write, then run `gh issue create --body-file` alone, with `Mandated-By:` on its own line for deferrals or `--label meta/machinery` for gate findings.
4. **TDD order slip:** `git-data-pin-fault.ts` was written before its unit test. Recovery: RED verified on the existing suites. **Prevention:** `cq-write-failing-tests-before`; write the test file first even for a module extraction.
5. **Shipped a tenant-forgeable pager** (security F1). Recovery: via=ssh only, plus forgery tests. **Prevention:** a Sharp Edges bullet in the plan skill (routed below): a classifier over stderr from a process whose cwd or inputs the tenant controls is forgeable, so list every writer of the channel.
6. **The reporter could throw from inside a catch** (security F3 / user-impact F5). Recovery: try/catch, a `reported` flag and a pino-only fallback, with two never-throw tests. **Prevention:** any helper called from a catch block owes "never throws", with a test that makes its dependency throw.
7. **Census used a hand-rolled comment regex while `stripComments` existed** (third recurrence). Recovery: the import. **Prevention:** #9161 migrates the five remaining copies and adds a guard.
8. **The plan, ADR and legal markers claimed controls that did not exist or did not cover the case** (the post-resolve query, an unbuilt flip check, "never one per refusal", "fresh isolation scope"). Recovery: runnable commands, tense corrections, and a CLO rewrite. **Prevention:** for every "X covers Y" sentence, run X against a Y-shaped input, or name the event field X filters on and check that Y carries it.
9. **`vi.spyOn` attached to a logger instance from before `vi.resetModules()`**: the spy saw 0 calls. Recovery: an `onLogger` hook inside `push()`, after the reset. **Prevention:** in a helper that calls `vi.resetModules()`, attach spies through a callback that runs after the re-import.
10. **Vacuous never-throw test**: the throw was injected into `captureMessage`, which `reportSilentFallback` already swallows, so mutant B8 survived. Recovery: throw from `logger.error`, the unguarded step. **Prevention:** inject a fault at the step the code under test is the only guard for, and confirm a mutant dies.
11. **tsc implicit-any after vitest went green**: vitest does not typecheck. Recovery: typed the callback. **Prevention:** run `tsc --noEmit` before calling a test edit done.
12. **A battery row nearly mutated the wrong rule**: a whole-file `.replace` on a line shared by three rules. Caught by reading the row before running it. **Prevention:** scope every tf mutation with `in_block`, never a file-wide replace.
13. **Stop-hook wording feedback while waiting on review seats** (pre-compaction). **Prevention:** while blocked on background agents, emit `<stop>BLOCKED: …</stop>` with the concrete count and no gerund announcements.

## Tags
category: security-issues
module: web-platform/git-data observability
