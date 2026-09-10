---
title: "Machinery findings are a separate ledger, and the filing lever moves to filing time"
status: accepted
date: 2026-09-10
issue: none
supersedes: null
---

# ADR-216: Machinery findings are a separate ledger, and the filing lever moves to filing time

## Context

Measured 2026-09-10 against `jikig-ai/soleur`:

| Quantity | Value | Command |
|---|---|---|
| Open issues | **1,455** | `gh api "search/issues?q=repo:jikig-ai/soleur+is:issue+is:open" --jq '.total_count'` |
| Opened, last 8 weeks | 1,134 | search API, `created:>=` window |
| Closed, last 8 weeks | 563 | search API, `closed:>=` window |
| Net, last 8 weeks | **+571** | derived |
| Older than 60 days | 841 (58%) | search API, `updated:<` window |
| Never commented | 330 | `comments:0` |
| `domain/engineering` : `domain/product` | **626 : 39** | 1,000-issue sample |
| PRs overriding net-issue-flow | 98 | PR-body marker scan |

The ratio is ~2 filed per 1 closed, every week, without exception.

**This is not technical debt.** Debt is the cost of shortcuts taken. This is
*audit exhaust*: the byproduct of running adversarial review agents over the
project's own verification machinery. Representative open titles are findings
about guards — "guard checks assertion SHAPE, not that a rehearsal passed",
"the live-arm ledger records reachability, not emission" — not about anything a
Soleur user receives. That is why product is 39 and engineering is 626.

It matters beyond housekeeping because **this machinery ships to customers**
(`hr-weigh-every-decision-against-target-user-impact`). A non-technical founder
running Soleur on their own repo will have work generated faster than they can
absorb it, and will read that as the tool being broken.

### Why it compounds

1. **Cost asymmetry, ~3 orders of magnitude.** Filing is one `gh issue create`.
   Closing is plan → work → review → ship.
2. **The drain is also a source.** Every closing PR runs the same review
   pipeline over itself and files new findings.
3. **The gate cannot drain.** `net-issue-flow.sh` is real and blocking (exit 1
   at `NET > 0`) but is per-PR **net-zero**. Perfectly enforced it holds 1,455
   forever. It also fails open on API error, deliberately and with telemetry,
   and has been overridden 98 times.
4. **Some filings are mandated.** `wg-block-pr-ready-on-undeferred-operator-steps`
   carries `[mandates-filing]`, so obeying one rule forces a filing.

## Decision

**1. Machinery findings are separated by a LABEL** (`meta/machinery`), excluded
from the operator digest, from `ticket-triage` domain routing, and from every
user-facing drain.

**2. The decisive check on filing moves from the merge boundary to the filing
site** — a blocking `PreToolUse` gate, `guardrails:require-filing-justification`.

### Rejected: a separate repo

It breaks the `Closes` link from the closing PR, and it breaks
`net-issue-flow.sh`'s own counting: the script's `FILED` arm matches issues in
*this* repo that reference the PR, so cross-repo filings become **invisible** to
the gate rather than merely re-scoped. That converts a visibility change into an
accountability hole.

### Rejected: a knowledge-base rolling audit log

It loses close-on-merge entirely, needs new tooling to write and to query, and
has no state model — an entry can never be "resolved", only appended to.

### Chosen: a label

One taxonomy addition, reversible by deleting the label, and it makes the ~39
product issues visible immediately without moving anything.

### Why the filing-site gate rather than a stricter merge-boundary gate

Per-PR net-zero, *perfectly enforced*, holds the backlog at its current size
forever. Only a check at the moment of filing moves the rate. The 2026-05-29
learning `net-issue-flow-gate-at-filing-site-not-just-ship` already recorded
this shape: `/ship` Phase 5.5's surfacing was bypassed precisely because filings
happen in `/work`. Enforce a discipline where the action is taken.

This ordering is binding and comes from the operator: *expiry drains the stock;
only the filing-time gate touches the rate.* At ~2:1, a 90-day sweep buys a
one-time drop and the curve then resumes its old slope.

### Three exits, one gate, and deliberately no fourth

1. `--label meta/machinery`
2. `User-Impact:` naming a surface from a shared closed taxonomy, **and**
   `Fix-Size: <N> lines / <M> files` measured — refused when inside the inline
   threshold
3. `Mandated-By: <rule-id>`

An earlier draft added a purpose-named bypass marker. **It is cut.** Exit 1 is
free and always available; name the filing that must bypass the gate, cannot be
labelled machinery, and cannot name a user impact — there isn't one. A fourth
exit on a gate that already has a universal one reproduces exactly the
reflexive-override pathology this repo has measured 98 times.

### Reconciliation with ADR-155

The third exit is `Mandated-By: <rule-id>` — the same closed, human-gated
vocabulary ADR-155 established. This is what makes the gate that *mandates* a
filing and the gate that *restricts* filing **one** gate rather than two that
disagree. The hook does not re-derive the tagged set; that is `net-issue-flow.sh`'s
job, from the merge-base corpus. The hook accepts a well-formed claim and lets
the merge boundary adjudicate it. Two gates, one vocabulary, no second pin on
the same fact.

**This ADR adds, weakens, and drops no `[mandates-filing]` marker.** Verified:
`git diff origin/main -- AGENTS.rules.md | grep -c 'mandates-filing'` is 0.

### The threshold's provenance

`<=100 lines AND <=4 files` is **not invented here**. ADR-131 records it moving
from `<=30 lines/<=2 files` to `<=100/<=4` "with instrumentation", and
`.claude/hooks/ship-net-issue-flow-gate.sh` quotes the same pair as "the
cost-of-filing auto-flip" in its remediation text. The citation is part of the
refusal message: a gate that names a threshold nobody can trace is how the
override reflex gets trained.

### Relationship to ADR-131 — stated, because it is uncomfortable

ADR-131 ("Gate moratorium and a meta-work filing budget", 2026-07-20) diagnosed
this same root cause and is `status: proposed` — deliberately, because both its
proposals are the operator's call. **Its Proposal 1 is a moratorium on new
gates, linters, probes and scheduled checks.**

This ADR adds one gate. If Proposal 1 is adopted, this is exactly the kind of
addition it would have required an explicit exception for. Recorded here rather
than left for a reader to notice, with three points:

- The moratorium is not in force, so no exception is required today.
- ADR-131's own framing supports this change's *direction*: it says the two
  shipped mitigations "act on the rate", and names acting on the rate as the
  right axis.
- If the operator adopts Proposal 1, this gate should be counted against the
  budget retroactively rather than grandfathered.

### The filing surface, and which classes the gate actually covers

A gate is only worth the population it reaches. The filing surface has five
classes; this is what covers each, stated so the claim cannot be read wider than
the mechanism supports.

| # | Filing path | Covered by |
|---|---|---|
| 1 | Interactive / `/work` / `/review` Bash `gh issue create` | `guardrails:require-filing-justification` |
| 2 | `.github/workflows/*.yml` | **Not covered, deliberately.** Machine-authored infra alerts (drift, health, advisor scans) never traverse a `PreToolUse` hook and are mandated by construction. |
| 3 | Inngest cron agent substrate | `cron-bash-allowlist-hook.mjs` — the same three exits |
| 4 | `gh api …/issues -X POST` | `guardrails:require-filing-justification` (trigger widened) |
| 5 | Octokit / MCP `create_issue` | **Not covered.** `github-tools.ts` and `mutate-workstream-issue.ts` call Octokit directly, and the hook's matcher is `Bash`. |

**Class 3 is the one that mattered and it is why this is not a single-hook
change.** `buildCronEvalSettings` returns a per-spawn settings overlay whose only
`PreToolUse` entry is `cron-bash-allowlist-hook.mjs`; the eight-deep chain in
`.claude/settings.json`, `guardrails.sh` included, is never loaded. Ten
scheduled agents carry `gh issue create` through
`ISSUE_CREATOR_BASH_ALLOWLIST` and file discretionary, LLM-authored findings —
precisely the audit-exhaust population behind the 626:39 skew. A gate covering
class 1 alone would have gone green while missing the majority of what it names.

The class-3 check runs AFTER the allowlist match, so it can only ever NARROW:
a cron whose allowlist omits the verb is already denied and never reaches it.
That property is contract-tested, not asserted.

**Two constraints specific to the cron surface, recorded because they are not
obvious.** The hook denies multiline commands as a pre-existing containment
rule, so exit 2 there is reachable only via `--body-file` — which is the shape
this repo prescribes anyway. And the shared taxonomy is resolved from the
module's own location rather than the CWD: a CWD-relative read silently returns
empty wherever the process did not start at the repo root, which degrades exit 2
out of existence while looking like a clean run.

### This is a SHAPE check, not a semantic one

The gate asserts that a filing *named* a surface and *measured* a size. It
cannot assert the named consequence is true. The design bet is that exit 1 makes
honest compliance cheaper than gaming, and that `Fix-Size:` is not gameable by
adjective. The weekly rate measurement is the backstop: if the rate does not
fall, the gate is being gamed, and that is visible within four weeks.

## Consequences

- `--milestone` alone no longer allows a `gh issue create`. It is necessary but
  not sufficient. The fixtures asserting the old contract were migrated in the
  same change.
- `net-issue-flow.sh` is deliberately **unchanged**. The machinery ledger stays
  inside the gate's count: the label separates visibility, never accountability.
  Excluding it would let the machinery ledger grow with no rate gate at all.
- The user-surface taxonomy is a single shared file read by both the gate and
  the backfill classifier, so the two cannot drift into disagreeing.
- The backfill is title-scoped, high-precision and low-recall, on measured
  grounds recorded in `machinery-backfill-proposal.md`. Recall is recovered by
  the gate labelling new findings at source, not by widening the classifier.

## Measured corrections to the originating brief

Recorded so the next reader does not inherit them.

1. **The evidence rule as specified does not work.** The brief and plan
   specified "title or body" for both classifier conditions. Body scope is
   vacuous as a negative — 191 of 200 bodies (96%) name a surface token
   incidentally — admitting 3%. The hybrid admits 103/200 but proposes live
   incidents (a dead `SUPABASE_PAT`, a docker login failing every deploy) as
   machinery. Only title scope discriminates. The underlying reason: Soleur's
   real infrastructure *is* guards, gates and probes, so an outage and a
   finding-about-a-guard share a vocabulary.
2. **A `-label:` exclusion in `gh issue list` is a silent no-op.** Measured:
   `gh issue list` discards `--search` when `--label` is present, so the
   self-exclusion control returned the full 200 instead of 0. The REST search
   endpoint honours the negation; `gh issue list` does not. Every user-facing
   drain exclusion is therefore a `jq` post-filter over labels the query already
   returns.
