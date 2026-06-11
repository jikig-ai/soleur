# Learning: IaC-gate ack comments are byte-exact literals; parallel-agent reconciliation catches false negatives

## Problem

During the #5080 weekly-release-digest brainstorm, the spec write was blocked twice by the
`hr-all-infrastructure-provisioning-servers` PreToolUse gate. The second block was surprising:
the ack comment WAS present, but written as
`<!-- iac-routing-ack: plan-phase-2-8-reviewed — no servers… -->` — explanatory prose inserted
before the closing `-->`. The hook greps for the exact literal
`<!-- iac-routing-ack: plan-phase-2-8-reviewed -->`, so the decorated comment did not match.

Separately, two research-agent claims contradicted each other: repo-research reported "no cron
calls the Anthropic SDK/API directly" while CTO cited `cron-compound-promote.ts:423`
(`fetch("https://api.anthropic.com/v1/messages")`). And CTO's claim that
`DISCORD_RELEASES_WEBHOOK_URL` still existed as a GH Actions secret was stale — repo-research
verified it had already been deleted per `feat-slack-release-notify/tasks.md` 5.6.

## Solution

- Ack comment on its own line, byte-for-byte as printed in the hook's error message; put any
  explanation in a SEPARATE comment block. Write succeeded immediately.
- Both research contradictions resolved by orchestrator-side targeted grep / live `gh secret
  list` checks before weaving claims into the brainstorm doc; reconciliation recorded in a
  `## Research Reconciliation` section of the brainstorm.

## Key Insight

Hook ack/sentinel strings are exact-match contracts, not prose conventions — when a hook's
error message prints the opt-out string, copy it verbatim including the closing delimiter.
And when two parallel agents disagree on a repo fact, neither outranks the other: a 10-second
orchestrator grep is the tie-breaker, and the reconciliation belongs in the artifact so plan
readers don't re-inherit the losing claim.

## Session Errors

1. **Spec write blocked twice by IaC routing gate** — first write had no ack; second had the
   ack literal broken by prose inside the comment. Recovery: exact literal on its own line +
   separate explanation comment. **Prevention:** copy hook-provided ack/sentinel strings
   byte-for-byte from the hook error message; never decorate inside the delimiters.
2. **Repo-research false negative on direct Anthropic API usage** — grep summary missed
   `cron-compound-promote.ts:423`. Recovery: orchestrator targeted grep confirmed CTO's
   citation. **Prevention:** apply the existing brainstorm reconciliation rule — verify any
   load-bearing negative claim with a targeted grep before it bounds the option space.
3. **CTO stale-by-hours secret claim** (`DISCORD_RELEASES_WEBHOOK_URL` "exists as GHA secret")
   — the secret had been deleted the same day. Recovery: repo-research's live `gh secret list`
   won; recorded in Research Reconciliation. **Prevention:** for secret/config existence
   claims, prefer the agent that ran the live read; sibling-PR cleanup tasks (tasks.md
   "delete secret" entries) are a staleness signal to check.
4. **Expected probe failure** — `git show origin/main:.github/workflows/release.yml` exited 1
   (file does not exist; notification lives in `reusable-release.yml`). Recovery: grep for the
   consumer. **Prevention:** none needed (normal discovery probe).

## Tags

category: workflow-patterns
module: brainstorm, hooks, spec-writing
