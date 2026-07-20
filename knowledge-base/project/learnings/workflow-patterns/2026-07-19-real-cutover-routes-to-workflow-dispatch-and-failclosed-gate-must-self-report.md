---
date: 2026-07-19
problem_type: integration_issue
component: infra
module: workspaces-luks-cutover
severity: high
tags: [go-routing, operational-dispatch, observability, fail-closed-gate, rsync-verify, mutation-testing, self-pull-observability]
issue: 6604
synced_to: [soleur:go]
---

# Learning: a "real cutover" go-request routes to a workflow dispatch, not one-shot — and a fail-closed gate must self-report its evidence before it dies

## Problem

`/soleur:go "6604 let's do the real cutover now that the rehearsal works"` looks like an
implement/ship request (the routing table would send it to `soleur:one-shot`). It is not a code task:
the workspaces-luks cutover *mechanism* (PR 2, #6610) and all its follow-ups were already merged, the
fresh encrypted volume existed and was attached, and the dry-run escrow rehearsal (#6649) had passed.
"The real cutover" meant **dispatching the `workspaces-luks-cutover.yml` `workflow_dispatch` with
`dry_run=false`** — an irreversible production freeze gated by a GitHub `environment:` required-reviewer.

The dispatch ran and **safe-aborted**: freeze / luksFormat / escrow / rsync all succeeded, then the C1
byte-identity verify found `"1 difference"` and correctly refused to repoint (DP-6 auto-rolled-back to
the plaintext mount; web-1 stayed healthy). But the operator **could not tell what the 1 difference
was** — the verify was fail-closed-correct yet DISCARDED its own evidence:

1. `rsync -aHAXi … --out-format='%i %n' > "$vlog" 2>&1` folded rsync's **stderr** into the same file
   that `DIFF_N="$(grep -c . "$vlog")"` counted — a benign stderr warning inflates the count,
   indistinguishable from a real byte diff.
2. On failure it `die()`d with **only the count**, then `rm -f "$vlog"` — throwing away the offending
   path + itemize code. No SSH-free way to know which workspace path aborted the cutover.

## Solution

Make the fail-closed gate **self-report before it dies** (the self-pull-observability doctrine applied
to a host bash script, `hr-no-dashboard-eyeball-pull-data-yourself` / `hr-no-ssh-fallback-in-runbooks`):

- Capture the verify rsync's stdout (`%i %n` itemize lines) and stderr **separately**
  (`>"$vout" 2>"$verr"`); count only itemize-shaped stdout lines
  (`grep -cE '^(\*deleting|[<>ch.*][fdLDS])'`) so stderr can no longer inflate the count and **no
  itemize code is narrowed** (attribute-only `.f..t`/`.d..t` still count). Threshold unchanged (0).
- On count≠0 OR rsync rc≠0, emit the capped (≤40) offending path(s)+code(s) to the run log AND to
  Better Stack via the already-allowlisted `logger -t luks-monitor` tag (op=workspaces-luks-verify-diff)
  **BEFORE** `rm` and `die`. `_vscrub` strips CR/LF+non-printable so a crafted filename can't inject a
  spurious marker line.
- A sourced-detection guard (`if [ "${BASH_SOURCE[0]:-$0}" != "$0" ]; then return 0 …; fi`) placed
  **before** `trap cleanup EXIT` lets a behavioral test `source` the script for the functions without
  running the cutover main body or arming the trap.

## Key Insight

Three transferable lessons:

1. **An operational go-request ("do the real cutover", "run the workflow", "flip it live") routes to an
   operational runbook, not one-shot.** The deliverable is a **gated `workflow_dispatch`** whose
   `environment:` required-reviewer is the sole human authorization — dispatching it queues the work
   for the operator's approval, it does not bypass the gate. Verify readiness first (volume exists,
   dry-run rehearsal green, escrow proven), confirm the environment reviewer set is **non-empty** (a
   zero-reviewer environment auto-approves — DP-11 F8), then dispatch. The **code fix that follows an
   abort** is the one-shot task, not the cutover itself.
2. **A fail-closed gate must surface the reason it fired before it discards the evidence.** A gate that
   `die`s with only a count (and `rm`s the detail) is a silent-failure anti-pattern in disguise — it
   forces SSH to diagnose the next occurrence. Log the discriminating detail (path/code/stderr) to a
   monitored sink (run log + Better Stack marker) BEFORE the `rm`/`die`.
3. **The mutation battery only covers what you mutate.** The new `_vscrub` log-injection sanitizer had
   ZERO behavioral coverage — a no-op passthrough kept the suite 10/10 green — until test-design review
   caught it. Enumerate every NEW SUT function on the **left of a test call**; a function called zero
   times is untested whatever the mutation matrix reports.

## Session Errors

- **AC4 ordering guard matched the word `die` inside a code comment** (`cq-assert-anchor-not-bare-token`
  recurrence). Recovery: strip comment lines (`grep -vE '^[[:space:]]*#'`) before the ordering grep.
  **Prevention:** already rule-covered (`cq-assert-anchor-not-bare-token`); the mechanical habit is to
  anchor body-greps on syntax, never a bare token a comment can also carry.
- **Mutation M3's inversion was wrong** (`-ne 0`→`-ne 999` still true for rc=23, so it didn't disable
  the rc-check). Recovery: `-eq 999` (false for every real rc). **Prevention:** after writing a
  mutation, confirm it actually flips the target case — a mutation that doesn't change behavior is a
  false "guard works".
- **Case f initially asserted the wrong property** (`! grep op=FORGED` tests intra-line field-injection,
  path-last-mitigated and out of scope — not `_vscrub`'s newline/control-strip contract). Recovery:
  assert on `[[:cntrl:]]` absence. **Prevention:** name the exact property under test; `_vscrub`
  defends against injected *newlines/control bytes*, not same-line field text.
- **`_vscrub` had no behavioral coverage** (review P1). Recovery: added case f + mutation M4.
  **Prevention:** enumerate every new SUT function on the LHS of a test call before trusting a green
  suite (already in `review/SKILL.md` "mutation battery only covers what you mutate").

All session errors were self-caught by TDD / self-review / multi-agent review; every class already has
a governing rule, so no new hard rule or hook is warranted.

## Cross-references

- ADR-119 (`knowledge-base/engineering/architecture/decisions/ADR-119-luks-at-rest-for-the-live-workspaces-volume.md`) — the at-rest-LUKS decision + the 2026-07-19 self-diagnosing-verify addendum
- `knowledge-base/project/learnings/workflow-patterns/2026-07-08-self-pull-observability-in-diagnostic-loops-never-ask-operator-to-fetch.md`
- `knowledge-base/project/learnings/2026-07-11-webhook-202-but-handler-never-ran-e2big-ship-component-error-channel-first.md` (ship the component's own error channel first)
- `knowledge-base/project/learnings/2026-07-16-a-mutation-battery-only-covers-what-you-mutate.md`
