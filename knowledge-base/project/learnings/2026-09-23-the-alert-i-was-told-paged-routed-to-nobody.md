---
title: The alert I was told paged routed to nobody, and the key it guarded was shared with CI
date: 2026-09-23
category: integration-issues
tags: [anthropic, console, workspace, spend-limit, sentry, reportSilentFallback, terraform, doppler, agent-browser, ci-secrets]
pr: 8618
issues: ["#8505", "#8614", "#8629", "#8630"]
---

# Learning: the alert I was told paged routed to nobody, and the key it guarded was shared with CI

## Problem

One Anthropic key (fingerprint `c95e2853ab74`) was the value of Doppler `ci`, every `prd*`
config and the `ANTHROPIC_API_KEY` repo secret. An eval run or a CI leak could drain the
org-wide prepaid balance and take the production crons and the email-triage summarizer down.
That had already happened (2026-09-19, 2026-09-21..23). The issue also said the existing
`cron-anthropic-credit-probe` "pages" on exhaustion.

It did not page. Three things were wrong:

1. The credit branch reported through `reportSilentFallback(err, …)` with an `Error`. The pino
   mirror captures that Error first, and then `checkOrSetAlreadyCaught` drops the second capture
   that carries the `feature`/`op` tags, so no tag-filtered rule could ever match it (#8629).
2. The cron monitor routes to no workflow. All 59 cron monitors do (#8630).
3. Exhaustion hit through `postAnthropicMessage` (every other cron) or the SDK summarizer
   reported nothing named at all.

## Solution

- **One named marker at two chokepoints.** `server/anthropic-credit.ts` exports the regex, the
  `feature`/`op` literals and `reportAnthropicCreditExhausted({source,status})`. That function
  calls `reportSilentFallback(null, …)`, the message path, which keeps the tags. The HTTP
  transport (`_cron-shared.ts` non-ok branch, classified from the FULL body) and the SDK
  summarizer (`APIError` catch, then rethrow) both call it. The probe no longer reports on its
  own, so one exhaustion produces one event. `sentry_alert.anthropic_credit_exhausted`
  (`logic_type all`, email `issue_owners` → `ActiveMembers`) routes it. A contract test imports
  the literals from the emitter, so the test and the rule cannot agree with each other while
  disagreeing with the code.
- **A spend-capped key for CI.** The key comes from the Console workspace `soleur-ci-eval`
  ($100/month cap) and a service account. It was minted by agent-browser; the only human step
  was the email code. It is stored in `prd_terraform/ANTHROPIC_API_KEY_CI`, and
  `anthropic-ci-key.tf` distributes it to Doppler `ci` and to the repo secret. Terraform checks
  only the `sk-ant-` shape. `anthropic-key-distinctness.sh` proves live that no `ci*` value
  equals any `prd*` value (exit 0 distinct / 1 equal or absent / 2 could not measure). See
  ADR-244 and runbook `anthropic-console-workspace-key.md`.

## Key Insight

**A claim that an alert "pages" is a claim about three hops: the emit path keeps the fields the
rule filters on, the rule exists, and the rule routes to a person.** Each hop can be checked by
one read. In this case the first hop was broken by a dedup, and the third hop did not exist for
any cron. Check every hop before building on the claim.

Second: **proving two secrets differ does not require Terraform to see both.** Declaring the
production key as a variable, so that a precondition could compare the two, would have written
the production key into every plan file. It would also have tied every apply to `prd_terraform`
inheritance. Validate the shape in Terraform and prove distinctness live, by fingerprint, with
a script whose "could not measure" exit is distinct from its "equal" exit.

## Session Errors

1. **Planning subagent hit HTTP 429 (session limit).** Recovery: the plan was complete on disk;
   deepen ran inline with a reduced 4-agent panel. **Prevention:** before re-spawning after a
   subagent dies, check the artifacts it was writing; a complete plan on disk needs only deepen.
2. **The plugin Playwright MCP could not launch** (no Chrome at `/opt/google/chrome`).
   Recovery: used the `agent-browser` CLI. **Prevention:** on a Chrome-missing launch error,
   switch to `agent-browser` at once; do not retry the MCP.
3. **Mutated the wrong Anthropic org.** The `ops@` login is a separate, unfunded org, and an
   empty workspace was created there before the mismatch was caught. Recovery: switched to the
   founder login and left the empty workspace (it bills nothing). **Prevention:** runbook step 1
   now reads `anthropic-organization-id` from a production-key response header and compares it
   with the Console before any mutation.
4. **Console dialogs closed on pointer clicks** (Scope combobox, Add button), which silently
   discarded the form. Recovery: keyboard focus plus `ArrowDown`/`Enter`, re-reading refs after
   each re-render. **Prevention:** recorded as a driving note in the runbook, mint step 5.
5. **The key panel renders the key as text**, so `get value` returned nothing. Recovery: `eval`
   straight into a `umask 077` file, which holds a JSON string, then `json.load`, then validate,
   store and shred, all in one Bash call. **Prevention:** agent-browser SKILL.md credential-safety
   paragraph (this PR).
6. **Lefthook's bun-test battery queued 35+ minutes behind five sibling gates.** Recovery:
   killed it and committed with `LEFTHOOK_EXCLUDE=bun-test`, relying on targeted suites plus CI.
   **Prevention:** when `proc.sh` shows sibling gates, exclude the battery at commit time and
   run the touched suites directly.
7. **The full shard gate refused (rc=4, siblings running), then queued** after
   `SOLEUR_ALLOW_FULL_GATE=1`. Recovery: stopped it; CI's required `test` context is the gate.
   **Prevention:** same as 6. Under contention, do not force the full gate.
8. **A kill loop killed its own shell (exit 144).** Its `pgrep -f` pattern matched the loop's
   own command line. Recovery: excluded `$$`. **Prevention:** use `proc.sh kill_mine`, or always
   exclude `$$` and `$PPID` from any `pgrep -f` result before `kill`.
9. **A multi-file Python edit aborted midway on an assert**, leaving `variables.tf` written and
   the tftest not (fmt had realigned the anchor). Recovery: edited the second file separately.
   **Prevention:** run all asserts before the first write, or `git diff --stat` every target file
   after the script and do not trust the exit code alone.
10. **The `credentials_required` corpus baseline went red** (18 vs 19; main was already at 19).
    Recovery: merged main and raised the baseline to 20. **Prevention:** already a work SKILL.md
    rule ("a file-selected suite set cannot see a repo-global ratchet").
11. **Merge conflict in the regenerated C4 JSON.** Recovery: regenerated it from the merged
    `.c4`. **Prevention:** resolve generated artifacts by regeneration, never by hunk choice.
12. **The PR sat `DIRTY` (conflict in `expenses.md`), so no `pull_request` workflow ran.** I
    waited on checks that could not start. Recovery: merged main and resolved. **Prevention:** an
    ad-hoc CI monitor must also read `mergeStateStatus`, and exit and surface `DIRTY` with zero
    checks, as ship's Phase 7 loop already does.
13. **The ADR ordinal collided twice (242, then 243)** with a sibling branch that claims both.
    Recovery: renumbered to 244, sweeping only this branch's files. **Prevention:** already in
    architecture SKILL.md (derive across all `origin/*` refs and re-derive just before merge).
    It recurred because I derived at plan time and again after a fetch, but not across all refs
    the first time.
14. **Inherited framing: "the credit probe pages."** I copied it from the issue into the plan
    before a review seat measured it (Error-path tag loss; monitor routes to no workflow).
    Recovery: filed #8629 and #8630 and corrected the runbook H10 section. **Prevention:** for
    each "X alerts/pages" claim, read the emit path, the rule, and its action target before
    writing the claim anywhere (Key Insight).
15. **A process-substitution `jq` inside `mapfile` lost jq's exit status**, so a parse failure
    produced a truncated population that read as DISTINCT. Recovery: ran `jq -er` separately,
    checked its rc, and mapped a parse failure to exit 2. **Prevention:** never feed a command
    whose failure matters to `mapfile < <(…)`; capture it to a variable or file and check `$?`.
16. **The first Terraform design declared the production key as a variable** so that a
    precondition could compare them. That writes the production key into the plan file.
    Recovery: CTO ruling B, validate the shape only and prove distinctness live. **Prevention:**
    Key Insight, second paragraph.

## Tags

category: integration-issues
module: apps/web-platform/server, apps/web-platform/infra, knowledge-base/engineering/operations
