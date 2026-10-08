---
title: Direct validation must respect hook file selectors
date: 2026-10-08
category: workflow-patterns
tags: [workflow-patterns, ci-only, hook-selectors, draft-maintenance]
---

# Direct validation must respect hook file selectors

During PR #9051 draft maintenance, Git hooks were disabled and local suites
remained held. A direct fixture-content invocation scanned a historical session
record that its canonical `lefthook.yml` selector excludes. It reported two
public bot-address citations from earlier CLA diagnostics. That invocation was
outside the fixture/learning gate's scope; it was not a verdict about the new
maintenance entry. The infra documentation check covers session records and
passed independently.

When substituting direct checks for absent hooks, read each hook's file selector
and command before invocation. Run the checker only on matching staged paths;
record exclusions explicitly. A broad checker invocation is not equivalent to
the hook. Preserve dated historical records rather than rewriting them to
satisfy a selector they do not belong to.

Two adjacent execution errors were corrected: the sandbox made the worktree's
Git index read-only, so staging was rerun with explicit escalation; a guessed
Markdown-linter path was absent. Discover validation commands from
`lefthook.yml` or tracked paths before reading them. Run dependent stages only
after checking each command's own exit status: a later successful command must
not conceal an earlier failed validation.

The later queue-state probe rejected a copied `--repo` option with exit 2;
that flag belongs to the monitor, not `sync-pr-behind.sh`. The script's usage
names `PR_QUEUE_REPO` for repository selection and otherwise uses the current
worktree. The corrected `9051 --queue-state` probe succeeded before any merge.
Read each helper's own usage instead of transferring flags between helpers.

## Addendum — session-start maintenance in a feature worktree

The resumed routing preamble encountered read-only cleanup lock paths in the
sandbox. Its zero exit accompanied an explicit skip, so cleanup was rerun with
escalation and completed without removing worktrees. A skip is not completion.

Running that preamble in the feature worktree also refreshed its clean, tracked
`.mcp.json` from main. The resulting bytes were verified equal to main before
restoring the branch's original bytes; no unknown edit was overwritten. For
this repository, perform the required main-config refresh at the bare root,
as the session-start rule specifies, and check the feature worktree afterward.
Keep routing hygiene separate from an intentional feature-config change.

During the next main-sync inspection, the queue-state helper's sandboxed
network request failed. Its unknown result was preserved until the escalated
read established an open PR outside the queue; no unknown state was treated
as permission to push. A full read of the large pipe-guard test was truncated;
the six-line incoming diff supplied the actual merge-scope evidence. Prefer
bounded diffs for maintenance inspection and delegate broader file retrieval.

## Addendum — failed CI evidence and issue filing

For a completed failed job inside a still-running workflow, `gh run view
--log-failed` refused access until workflow completion. The jobs/logs API
worked, but the CLI refused ANSI-bearing content by default. Save it to an
ignored file with the explicit `--allow-escape-sequences` option, then strip
control sequences before displaying bounded excerpts. Match the runner's
timestamped suite verdict, not fixture self-tests that intentionally print
FAIL messages. Never replay raw terminal controls into Warp.

A superseded description-guard run accepted normal cancellation but remained
queued on repeated reads. After re-verifying the same head and inactive slot,
GitHub's force-cancel endpoint completed cancellation; the replacement guards
remained separately watched. An accepted cancel request is not completion.

The watchdog tracking issue's first filing was refused because it omitted the
milestone and filing exit; the corrected machinery-labeled, Post-MVP filing
then needed network escalation before succeeding. Apply the hook's explicit
filing metadata rather than treating a refusal or network error as a created
issue. A full canonical go-command read was truncated; use bounded sections
when retrieving a long workflow after compaction.

A PR-body JSON fetch used too small an output budget; the shell tool inserted
a truncation warning and the subsequent JSON parse failed. Retrieve structured
data with enough budget before parsing, then display only selected fields.
The corrected full fetch succeeded; no malformed description was written.

The push reported 24 default-branch Dependabot alerts. A read-only API summary
confirmed one critical, ten high, ten medium and three low existing alerts.
The maintenance diagnostic patch changes no dependency manifests; the alert
summary is neither a new dependency audit nor a promotion clearance.
