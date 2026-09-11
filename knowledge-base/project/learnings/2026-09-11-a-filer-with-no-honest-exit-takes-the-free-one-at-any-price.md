---
title: A filer with no honest exit takes the free one at any price
date: 2026-09-11
category: workflow-patterns
tags:
  - filing-gate
  - net-issue-flow
  - scheduled-crons
  - measurement
  - guardrails
issue: 8076
related:
  - knowledge-base/engineering/architecture/decisions/ADR-216-machinery-ledger-and-filing-time-lever.md
  - knowledge-base/project/learnings/2026-09-10-every-escape-my-mutations-could-not-reach.md
  - knowledge-base/project/brainstorms/2026-09-11-filing-gate-run-report-exit-brainstorm.md
---

# Learning: a filer with no honest exit takes the free one at any price

## Problem

PR #8038 shipped a blocking filing gate with three exits and an ADR that said,
in words, that no filing exists which "must bypass the gate, cannot be labelled
machinery, and cannot name a user impact." Eleven hours later the first
scheduled agent to reach it — the daily community digest — was denied, read the
remediation, and filed with `--label meta/machinery`. The gate had worked
exactly as designed on the population it was designed for, and the operator's
question was whether the free exit is too cheap.

## Solution

The question was wrong, and answering it would have shipped the wrong fix.

A `Machinery: <path>` requirement on exit 1 would have produced
`Machinery: scripts/community-router.sh`. The digest cron had **no honest
exit**: its prompt says "creating the issue is REQUIRED: the platform only
persists your changes after it verifies the issue exists," and
`cron-cloud-task-heartbeat.ts` `TASK_INVENTORY` reads that issue's existence as
liveness. That is "mandated by construction" — the exact reasoning ADR-216 used
to exempt workflow-YAML filings — but these run in the cron substrate the gate
covers. Four crons are in that position (community-monitor, content-generator,
roadmap-review, competitive-analysis). The fifth inventory entry, legal-audit,
is *not*: its `scheduled-legal-audit` label covers up to five per-gap findings
per run, which is the audit exhaust the gate exists to gate.

So the fix is a **population** fix (a substrate-written, agent-unreadable
`run-report-label` directive the hook honours), plus **measurement** (report the
class-3 run-report floor and the exit-1 share beside the headline, so the
four-week check can tell relabel from reduce), plus **observability** (the cron
hook's deny never reached Better Stack; the whole denied-then-complied story was
inferred from the label set). Pricing exit 1 waits until the exit-1 share line
can say whether it needs pricing.

## Key Insight

**When a gate's first live contact produces a mislabel, ask "did this filer
have an honest exit?" before asking "is the free exit too cheap?"** A filer with
no honest exit takes whatever exit is available at whatever price; raising the
price only changes which dishonest artefact it produces. The tell is a filing
that is mandated by something the gate cannot see — a persistence handshake, a
liveness contract, a prompt that says REQUIRED.

Corollaries:

- **"There isn't one" is a claim to grep.** ADR-216's assertion was refutable in
  one command against `TASK_INVENTORY`. A closed-exit-set design should
  enumerate the mandated-by-construction filers *per covered class*, not just
  per uncovered class.
- **A flat headline cannot be diagnosed without an exit distribution.** The
  measurement counted filings regardless of label (so relabeling cannot hide),
  but reported no per-exit share (so relabeling cannot be *seen*). "Cannot hide"
  and "can be diagnosed" are different properties.
- **The wrong label accidentally gave the right lifecycle.** Run-reports had no
  lifecycle at all (43 open daily digests, last mass-closed by the operator);
  `meta/machinery` would have expired them at 90 days. When a mislabel produces
  a beneficial side effect, the side effect is a missing feature, not a reason
  to keep the mislabel — the drain would otherwise have tried to one-shot a
  community digest.

## Session Errors

1. **Counted `TASK_INVENTORY`'s five crons as five run-reporters.** Recovery:
   read each cron's prompt; legal-audit's label covers findings.
   **Prevention:** an inventory keyed on a *label* is not an inventory of
   *report-shaped filings* — read what each producer files under the label
   before deriving an exemption set from it.
2. **Asserted "mass-closed by hand" from `state_reason=completed` alone.**
   Recovery: `gh api .../issues/N/timeline` showed `closed_by: deruelle`, three
   closes in one second. **Prevention:** `state_reason` says what, never who;
   read the timeline before naming an actor.
3. **Two false denies from `guardrails:require-filing-justification` on honest
   exit-1 filings.** (a) A heredoc-then-`gh` one-liner containing "Soleur's"
   made `xargs -n1` abort on an unmatched single quote (`guardrails.sh:451`,
   stderr suppressed), so the `--label` token was never seen and the refusal
   said to add the flag already passed. (b) Re-run with `--body-file` alone,
   the unreadable-body deny (`guardrails.sh:616-628`) fired before `_fj_pass`
   was honoured — an exit-1 filing refused for a body it does not need.
   Recovery: write the body file in its own Bash call, then file.
   **Prevention:** tracked as FR7 of #8076 (quote-tolerant tokenizer fallback;
   honour exit 1 before the body-file check). Until then: never put prose with
   apostrophes in the same Bash call as `gh issue create`; write the body file
   first.
4. **Scratchpad directory absent on first heredoc write.** One-off; `mkdir -p`.
   **Prevention:** none needed beyond the mkdir.
5. **`cd /tmp` inside a tokenizer probe reset the shell CWD out of the
   worktree.** One-off. **Prevention:** run probes with absolute paths, no `cd`.
6. **Ended a turn on a first-person "I'll put the approaches to you" while an
   agent was still running.** Stop-hook caught it; the approaches went out in
   the same turn. **Prevention:** when waiting on a background agent, either
   act on what is already known or declare the wait explicitly.
7. **Discovered, not caused: the machinery-drain pool counts its own standing
   measurement issue** (`scheduled-machinery-drain.yml:62`, #8068 carries
   `meta/machinery`). Off by one on every run; the closing arm would drain its
   own ledger. **Prevention:** tracked as FR3 of #8076.

## Tags

category: workflow-patterns
module: guardrails / issue-flow / cron-substrate
