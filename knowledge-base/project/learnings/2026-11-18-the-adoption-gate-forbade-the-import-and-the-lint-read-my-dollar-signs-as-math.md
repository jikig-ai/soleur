---
title: The adoption gate forbade the import, and the lint read my dollar signs as math
date: 2026-11-18
category: integration-issues
module: sentry-iac
tags: [sentry, terraform, uptime, markdownlint, merge-queue, test-harness, cost]
issue: 6606
pr: 12844
---

# Learning: the adoption gate forbade the import, and the lint read my dollar signs as math

## Problem

PR #12844 cut Sentry uptime spend from 5 monitors to 1. The plan was to adopt the auto-detected
`app.soleur.ai` monitor (detector 1422253, mode 3) with an `import` block and destroy the four
duplicates. Two things went wrong:

1. **The import could never pass CI.** `scripts/sentry-adoption-plan-assert.sh` runs on every
   Sentry plan, not only on the #7650 migration it was written for. It reads any `import` or
   `removed {}` row as that adoption and fails the plan when the rows do not match its reference.
2. **CI failed `quality-guards` on a ledger edit.** `markdownlint` reported MD038/MD034 on
   `knowledge-base/operations/expenses.md:50`, even though the code spans in that line looked
   well-formed.

## Solution

1. **Create, then delete through the API.** The CTO re-ruled D2: declare a new
   `sentry_uptime_monitor.app`, and DELETE 1422253 through the Sentry API right before the merge.
   The operator approved that delete as a single exact command. No import block and no
   `removed {}` block touch the Sentry root.
2. **Escape `$` outside code spans.** This repo's markdownlint parses `$…$` as inline math.
   Dollar amounts in one table cell paired up across the cell and swallowed the backticks
   between them. Writing `\$29` outside the spans fixed the line. Every changed `.md` then
   linted with rc=0.

## Key Insight

- **A gate scoped by its author's intent is not scoped by its code.** Before you plan a
  Terraform import, removal or state move, grep the plan-assert scripts the workflow runs
  without conditions. If one of them reads that row class, the import is not an option.
- **On a merge-queue repo, a pre-merge production delete opens a gap of queue time plus apply
  time, not apply time alone.** `gh pr merge --squash` only enqueues. File the tracking issue at
  the moment of the DELETE, so the gap has an owner if the queue ejects the PR.
- **An argv denylist is not a transport property.** Pin the exact argv of each call, and pin its
  token count too. `$(cat file)` strips trailing newlines, so a trailing empty argument (`''`)
  compares equal to the pinned string.
- **A parse pattern is only tested by an input that tells it apart from its weaker sibling.**
  `uptime_verdict=[^ ]+` and `[a-z-]+` agree on every stub, except one that prints `clean2`.

## Session Errors

1. **The first D2 ruling rested on a wrong provider premise.** Recovery: re-ruled after reading
   the source of provider v0.15.7. **Prevention:** a ruling on provider behaviour cites the
   provider source line it depends on.
2. **The import planned a destroy and create**, because the provider never reads `project` back.
   Recovery: `ignore_changes = [project]`, then the whole import route was dropped by item 14.
   **Prevention:** see Key Insight 1. Grep unconditional plan-asserts before choosing an import.
3. **The discoverability `expected_output` contained spaces.** Recovery: changed to the single
   token `uptime_verdict=clean`. **Prevention:** make `expected_output` one space-free token.
4. **The plan claimed `eu.sentry.io` returns 302/401.** Measured, every host returns 200.
   Recovery: corrected; the plan keeps the pinned `jikigai-eu.sentry.io`. **Prevention:** probe
   before writing a claim about a host's status code.
5. **The grep-sweep pathspec did not exclude archive folders.** Recovery: the pathspec now
   excludes them. **Prevention:** add `:!**/archive/**` to every sweep that counts live
   references.
6. **G1-9 and G1-17 went red** after `live < declared` began reading as unavailable. Their
   fixtures declared 2 blocks against 1 live row. Recovery: the fixtures now declare one block.
   **Prevention:** when you tighten a verdict, grep every fixture that sits on the boundary
   you moved.
7. **The F25 mutation sandbox measured nothing at first.** A sed keyed on line numbers missed,
   and the sandbox lacked the archive capture. Recovery: a pattern-keyed edit, and the archive
   directory is copied into the sandbox. **Prevention:** already in work-test-harness-sharp-edges
   (assert the mutant's own failure line, and carry every file the original resolves).
8. **The mutation battery misrouted W-sentry-name** after the verdict text changed. Recovery:
   the kill substring was updated. **Prevention:** change a verdict string and its battery kill
   text in the same edit.
9. **SC2034 flagged an unused `SENTRY_TF`.** Recovery: the variable was removed. One-off.
10. **The `gh issue create` hook blocked three times**: `--milestone` missing, a non-literal
    `--body-file`, and no filing exit. The legal issue was then refused as inside the inline
    threshold. Recovery: the legal gap was fixed inline (`soleur_legal_terms`), and the
    deferral was filed as #12886 with `meta/machinery`. Already hook-enforced.
11. **The scratchpad was wiped after the session restart**, which lost the verification agent's
    output path. Recovery: the agent was resumed and wrote to `.soleur-gate-logs/verify.md`.
    **Prevention:** an agent whose output must outlive the session writes into the worktree.
12. **MD038/MD034 on `expenses.md:50`** came from math parsing of `$`. Recovery: escaped `$`
    outside code spans. **Prevention:** a sharp-edge bullet was routed into
    `work-test-harness-sharp-edges.md`.
13. **The `test` aggregator went red on the draft PR.** That is by design: its log ends
    "draft: full battery owed at ready", and the skipped legs run once the PR is marked ready.
    It still cost a diagnosis round. **Prevention:** on a draft PR, read the aggregator's last
    lines before hunting for a failing leg.
14. **The verification pass found four P3s the fix round had missed:**
    - `$(…)` stripped a trailing empty argument;
    - no stub separated `[^ ]+` from `[a-z-]+`;
    - the W14 awk missed indented and bare-label HCL;
    - the remedy text cited only the `Refreshing state` id line, which the creating run never
      prints.

    Recovery: all four fixed in `bea7bfe4d1`. **Prevention:** see Key Insights 3 and 4. For a
    remedy that cites a log line, check that every run that can trigger the remedy prints
    that line.

## Tags

category: integration-issues
module: sentry-iac
