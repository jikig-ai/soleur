# Learning: a record PR for an arming step must sweep the claim, and pin the runtime value, not the source text

## Problem

Stage 3a of #9703 recorded that the Inngest probe heartbeat (id 504655) was armed on 2026-10-12 by dropping
`arming_pending` from its manifest row and rewording the statements the arm made false. The planned sweep and the
planned guard were both narrower than the claim they served:

- The sweep was indexed by the plan's "Files to Edit". Review found live "not yet armed" / "not wired or armed"
  statements in `ADR-282` and `inngest-luks-cutover-6894.md`, files the PR never opened.
- The parity guard was a shell grep over `heartbeat-manifest.ts` source text, inside a suite that only runs when an
  `apps/*/infra/**` path changes. A spread (`...PEND`), a computed key, a post-assignment or a one-line duplicate row
  re-added the field at runtime while the suite stayed 21/0, and an edit to the manifest alone never triggered the
  suite at all.
- The runbook and ADR-117 said the unmerged record PR "was done".

## Solution

- Pinned the property at runtime beside the reprovision-parity suite:
  `MANIFEST.filter(name === "inngest_server_probe")` has length 1 and `arming_pending` is `undefined`. The runtime
  value is what `heartbeat-live-reconcile.ts` reads. Proven red against the spread escape, which the shell guard
  missed.
- Swept the claim ("heartbeat unarmed / not wired") across the repo instead of the plan's file list, fixed the
  in-scope survivors, and left the Stage 3b files (`betterstack-logs-alerts.tf`, `cron-monitors.tf`, the 8296 script)
  for their own PR.
- Put the run-id record in one owner (the runbook section "Arming the probe heartbeat (#9703)") and made ADR-117 a
  pointer; wrote every statement about the unmerged record PR in the future tense.

## Key Insight

A guard over source text certifies the spelling, and the reconcile reads the value. For a manifest-driven monitor,
assert on the imported `MANIFEST` in a suite that runs on plugin edits. Separately, a stale-claim sweep is done when
every file naming the claim has been read, which is a repo-wide grep on its subject.

## Session Errors

1. **`Read`/`grep` at the bare repo root failed (no work tree)** — Recovery: `git show origin/main:<path>` — Prevention: read-only work from the bare root goes through `git show` or a worktree; the go skill's bare-repo guard already says so.
2. **`check-web-host-escrow-config.sh` invoked without `--static` (rc=2 usage)** — Recovery: re-ran with `--static` after comparing against `origin/main` — Prevention: read the script's usage line before quoting a plan-listed command as a suite.
3. **Source-text parity guard evaded by indirection, and unreachable on a manifest-only edit** — Recovery: runtime assertion in the reprovision-parity suite, mutation-proven — Prevention: for any guard over a TS manifest, assert the imported value and check the CI path filter covers the guarded file.
4. **File-list-indexed stale-wording sweep missed ADR-282 and the 6894 runbook** — Recovery: review seat found them; fixed inline — Prevention: index the sweep by the claim's subject (repo-wide grep), not the plan's file list.
5. **`semgrep ... | grep -E "Ran N rules"` printed nothing on an engine crash (exit -11), reading as a clean scan** — Recovery: re-ran with visible output, recorded SAST as unverified — Prevention: never filter a scanner's output before reading its exit code and rule count.
6. **A report-only seat ran `git checkout --detach` in the shared worktree** — Recovery: branch and HEAD verified unchanged afterwards — Prevention: brief seats to read with `git show <sha>:<path>`; confirm `git branch --show-current` after a panel returns (already in review Sharp Edges).
7. **The arm block (up to 75 min) exceeds Monitor's 30-minute cap** — Recovery: ran it detached under `setsid` with a log file and a tail Monitor; the rollback trap was never at risk — Prevention: when a runbook block outlives the monitor tool's cap, detach it and watch its log, never let the monitor own the process.

## Tags
category: workflow-issues
module: inngest-heartbeat-arming
