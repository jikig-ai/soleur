---
title: "The pinned path I made the only path had never run: the image shipped no ssh, and the sweep meant to prove nothing was pending could not see the reports"
date: 2026-09-28
category: integration-issues
module: apps/web-platform (git-auth, git-data-replication, account-delete, Dockerfile)
tags: [git-data, host-key-pinning, art-17, sentry, observability, docker, verification]
issues: [5914, 8211, 8629, 8572, 9121]
pr: 9096
---

# Learning: the pinned path I made the only path had never run

## Problem

PR #9096 (host-key step 6 of the git-data cutover) deleted the app's unpinned SSH host-key
fallback, so the pinned transport became the only way the web app reaches git-data — including
the Art. 17 erasure call on every account deletion. Plan, deepen-plan, TDD and a green suite all
reasoned about *which* SSH options the app passes. None asked whether the app can run `ssh` at all.

It cannot. The web-platform runner stage is `node:22-slim` with
`apt-get install -y --no-install-recommends ca-certificates git …`. git only **Recommends**
`openssh-client`, and `--no-install-recommends` drops it. Measured:

```text
docker run node:22-slim@<pinned sha> sh -c 'apt-get … --no-install-recommends ca-certificates git …; command -v ssh || echo NO_SSH'
NO_SSH
```

So every app-side git-data dial in production failed `ENOENT`, and because `removeGitDataRepo`
reads `code` as a number, the string `"ENOENT"` classified as `unreachable` — the benign-sounding
outcome that sends an operator to the network. It was invisible because no deletion had reached
that path in the 90-day window.

The same session hit the observability twin of this. Host-key step 5 required proving that no
erasure was left pending. The runbook's sweep queried Sentry by the `feature`/`op` tags — but the
erasure report used `reportSilentFallback(new Error(...))`, and the pino mirror pre-captures an
Error with only `feature=pino-mirror`, after which Sentry drops the tagged capture (#8629). A tag
query therefore reads 0 **whatever happened**. The "0 events" the sweep printed was structurally
meaningless until a message-text sweep with its own positive controls was added.

## Solution

- Install `openssh-client` in the runner stage, and guard it three ways: a source test on the
  Dockerfile's apt line (with a comment-cannot-satisfy row), a `git_data_ssh_client=present|absent`
  startup line shipped to Better Stack, and a message-path Sentry event when an armed container
  boots without `ssh`. Classify a spawn `ENOENT` as `unconfigured` `ssh_client_absent:` (nothing was
  dialed) instead of `unreachable`.
- Move every Art. 17 erasure report to the message path (`reportSilentFallback(null, {...})`), put
  the `unconfigured` reason word in the message AND an `erasure_reason` tag (so one open
  `remove_key_absent` issue cannot swallow a later `pin_absent` page), and move the
  `removeGitDataRepo threw` arm too — without the thrown message, which can embed the raw id.
- In the runbook, pair the tag sweep with a message-text sweep and three positive controls
  (token/host lists any issue; tag syntax `feature:pino-mirror` returns issues; free text on a real
  title returns it), and note that Sentry Dedupe can drop consecutive identical events, so Better
  Stack's pino line is the complete per-erasure record.

## Key Insight

**When a change makes a code path the ONLY path, verify the path's runtime dependencies exist on
the surface it runs on — not just that its logic is right.** "Pinned on every dial" was true of the
code and false of production, because the binary the code shells out to was not in the image.
The generalisation is `hr-verify-repo-capability-claim-before-assert` one level down: a capability
claim about a *runtime* (a binary, a package, a mount) is falsified by one `docker run`, and no
unit test, mock or source guard can reach it.

**And a zero from an instrument is only evidence if the instrument can see the event.** A
tag-filtered query over emitters that never carry the tag is a query that cannot return non-zero.
Before accepting "0 pending", name the path the event takes to the store and run a positive
control through the *same* query shape.

## Session Errors

1. **The production image had no `ssh` client (P1, pre-existing), found only at review.** Recovery: measured with `docker run`, CTO ruling, installed `openssh-client` plus three guards. **Prevention:** plan-sharp-edges bullet (this PR) — when a plan makes a path the only path, list its runtime dependencies and verify each on the deploy image.
2. **The runbook's step-5.1 Sentry sweep was tag-only and blind to Error-path reports (#8629).** Recovery: added a message-text sweep with positive controls and recorded the gap on the #5914 record. **Prevention:** runbook step 5.1 now requires the text sweep and controls; the #8629 comment lists the other affected emitters.
3. **The semgrep seat's first run crashed with `io_uring_queue_init: Cannot allocate memory` and scanned 0 files.** Recovery: re-ran with `EIO_BACKEND=posix -j 1`. **Prevention:** semgrep-sast agent Critical Constraints note (this PR).
4. **A process-kill loop over `/proc/*/cmdline` matched its own shell (its command text carried the pattern) and exited 144; the targets survived.** Recovery: killed by explicit PID tree. **Prevention:** already covered by the pkill-self-match learnings — resolve by `/proc/<pid>/cwd` and exclude own PID; `pkill-self-match-guard.sh` does not cover hand-rolled `/proc` loops.
5. **A comment added inside a `bash -c '…'` body contained an apostrophe that would have closed the quote.** Recovery: reworded before commit; `bash -n` passed. **Prevention:** existing class (quote-hazard in shell-embedded prose) — run `bash -n` after any edit inside a quoted script body.
6. **A scripted edit of `test/repo-wide-suites.ts` matched the `[` in `string[]`, breaking the type annotation and re-sorting entries.** Recovery: restored from HEAD, inserted one line. **Prevention:** anchor scripted list edits on a unique existing member line, never on the first `[`.
7. **Two scripted multi-edits missed their anchors on line-wrapped prose (runbook, ADR).** Recovery: the `assert` aborted before any write; re-anchored. **Prevention:** existing practice — print the exact lines (`cat -A`) before writing a multi-line anchor.
8. **Test harness defects in the RED run: a `PATH` stub hid `ssh-keygen`; the sweep regex missed `execFileAsync(`.** Recovery: prepend to `PATH`; widen the callee pattern. **Prevention:** stub `PATH` by prepending; write a sweep's pattern against the real call sites first.
9. **The first RED run wrote no log because a `cd` into an already-nested directory failed.** Recovery: re-ran with absolute paths. **Prevention:** `hr-when-in-a-worktree-…` — absolute paths in every Bash call.
10. **Forwarded from planning:** two scripted plan edits aborted on anchor mismatch; interim markdownlint/guard-contract lint failures; one reviewer made read-only `gh` calls despite a no-network brief. **Prevention:** covered by existing plan-phase lints.
11. **The local affected gate printed nothing for minutes on a contended host; the operator chose to rely on CI.** Recovery: stopped the run's process tree by PID. **Prevention:** for a CI-authoritative battery, run `test-all.sh --capacity` first and skip the local gate when contended.
