# Learning: an `--atomic` flag turned one stale ref into a permanent stall, and a clean scan had no control

## Problem

PR #11713 (refs #11704, #8211) fix round, 2026-10-31. Three things were found only by looking, after the first panel had passed:

1. **A safety flag added only downside.** The replication push used `git push --atomic --force` so that a rejected rescue ref would also hold back the `main` force. The store never prunes, so a stale store head `fix/x` plus a later local branch `fix` makes git reject `heads/fix` with a refname conflict. Under `--atomic` that rejection blocks every ref, `main` included, at every session end, for ever. Three review seats (security, data-integrity, user-impact) reproduced it independently in scratch stores. Once the rescue ref was pushed alone first (the two-step push, F19), `--atomic` on the second push protected nothing: the old tip was already referenced. CTO ruling F20 dropped it from step 2 and kept it on step 1.
2. **The fix commits carried the defect classes they existed to close.** The fix-round panel found a rescue-listing that never terminated its lifecycle (the local rescue branch was never deleted, so step 1 re-ran at every session end), instrument self-test `probe` helpers that were disarmable together with the helper they backstop, an `indexOf(a) > indexOf(b)` assertion pinning a property git does not have, and prose claims ("measured", "bounded by the existing gc", "keeps R3 INCONCLUSIVE") with no command behind them.
3. **A clean semgrep run had no control.** `semgrep --config p/javascript --config p/typescript` over the changed server files printed `0 findings`. A known-bad sample (`eval(x); cp.exec("ls " + x)`) also printed 0 under `p/javascript`, `p/nodejs` and `p/owasp-top-ten`; only `p/security-audit` fired. The first run was a statement about the rule set, not about the code.

## Solution

- Drop `--atomic` from the main push; keep it on the single-pattern rescue push. A partial rejection (main landed, one ref rejected) exits non-zero, `pushWithRetry` throws, and the existing loud `git-data replication push failed` path reports it with no success marker. Real-git rows pin all three (store `heads/fix/x` plus local `fix`).
- Delete the pushed local `soleur-store-tip-*` branches best-effort with a compare-and-delete (`update-ref -d <ref> <sha>`) after the confirmed step-1 push; bound the listing with `timeout: 5000`.
- Arm every instrument probe with a deliberately wrong expectation and report through `printf` plus `exit 1`, never through the helper it backstops.
- For semgrep, run the control against the SAME `--config` set and scan with a set that fires on it (`p/security-audit`).

## Key Insight

A guard flag is justified by the failure it prevents, so re-derive that failure after every later change to the same code path: when the rescue-first step landed, `--atomic` on the next step lost its reason and kept its cost. And a scanner's silence is evidence only after the same command has been seen to speak on a known-bad input.

## Session Errors

1. **Clean semgrep result with no control** (`p/javascript` + `p/typescript` printed 0 on the real files and on a known-bad sample). Recovery: found `p/security-audit` fires on the control, rescanned the three files with it. **Prevention:** the review skill's semgrep step runs a known-bad control against the same `--config` set before reading a zero as clean.
2. **Credential-refusal lint invoked with guessed flags** (rc=2, usage error). Recovery: read the runner's own invocation in `scripts/test-all.sh` (`python3 scripts/lint-shell-trace-credential-refusal.py`, no args) and re-ran, OK. **Prevention:** copy a ratchet's invocation from `grep run_suite scripts/test-all.sh`, never from the script name (already a work-skill rule).
3. **ADR sentence overclaimed** ("a forged row cannot move the flip because the flip's own pause read also requires fresh rows from both hosts"). A forged `=1` row can stand in for a host whose real row is missing. Caught before commit by re-reading the sentence against the rule it cited. **Prevention:** name the command or the rule clause that falsifies each new causal sentence before writing it (existing review rule).
4. **Fix brief named the wrong emitter** (`formatQuietWindowLine`; the real function is `formatLiveSessionsLine`). The fix agent corrected it. **Prevention:** grep the symbol before putting it in a brief.
5. **Cwd drift** (a `cd apps/web-platform` in one Bash call moved the primary directory for the next). **Prevention:** begin every Bash call with an absolute `cd` to the worktree.
6. **Stop hook fired twice on closing text that promised an action** (an "I will run ..." sentence at the end of a waiting message). **Prevention:** end waiting messages with a `Paused:` or `Blocked:` line and no future-tense promise.

## Tags
category: logic-errors
module: git-data-replication
