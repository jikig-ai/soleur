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

### Four exits, one gate, and deliberately no fourth *narratable* exit

0. `--label <run-report-label>` where the label equals the `run-report-label`
   directive the substrate wrote into this spawn's `cron-allow.txt` — present
   only for the run-report crons, unreadable and unwritable by the agent
   (2026-09-11 addendum below)
1. `--label meta/machinery`
2. `User-Impact:` naming a surface from a shared closed taxonomy, **and**
   `Fix-Size: <N> lines / <M> files` measured — refused when inside the inline
   threshold
3. `Mandated-By: <rule-id>`

An earlier draft added a purpose-named bypass marker. **It is cut.** Exit 1 is
free and always available; name the filing that must bypass the gate, cannot be
labelled machinery, and cannot name a user impact — there isn't one. (> **Superseded
2026-09-11 (#8076):** there is one — the run-report a cron MUST file to verify
its own run, which is neither machinery nor a user impact; #8059 relabelled it
`meta/machinery` to comply. The addendum below is that filing's exit, and it
stays non-narratable.) A fourth
narratable exit on a gate that already has a universal one reproduces exactly the
reflexive-override pathology this repo has measured 98 times. Exit 0 is not
that exit: an agent cannot take it by writing anything, because the token it
must match is issued by the substrate per spawn and the agent never sees it.
The addendum below records why it exists and why it is not the cut marker.

### Addendum 2026-09-11 — the run-report population

**The population.** Every cron whose run completion is verified by its own
scheduled issue. Mechanically: the nine `resolveOutputAwareOk` callers —
architecture-diagram-sync, campaign-calendar, community-monitor,
competitive-analysis, content-generator, growth-audit, growth-execution,
roadmap-review, seo-aeo-audit — whose handlers call
`verifyScheduledIssueCreated` (eight of them persist through the
`safeCommitAndPr` handshake, which refuses to commit the run's artifacts until
the issue is seen; roadmap-review commits through its own hook-guarded path
and verifies the same way). Plus legal-audit, by operator
decision (D1, plan review 2026-09-11): its issues are per-gap findings rather
than reports, so it sits in the directive map and never in the sweep. The list
lives in one leaf, `RUN_REPORT_CRONS` in `_cron-run-reports.ts`; the
measurement script mirrors the label set and a parity test keeps the two in
lockstep. The population key is "calls `resolveOutputAwareOk`", NOT the
heartbeat's `TASK_INVENTORY` — the brainstorm keyed on that and was wrong by
four.

**First live contact: #8059.** Eleven hours after the gate merged,
cron-community-monitor was denied on its prescribed filing and complied via
exit 1 — a community digest relabelled `meta/machinery`. The gate did what it
says; the population was mis-specified. For these crons the issue *is* the
proof of output: a run that cannot file it is a heartbeat failure and a lost
artifact, not a saved filing.

**Why this is class-2 reasoning inside class 3.** The filing-surface table
exempts workflow-YAML filings (class 2) because they are "mandated by
construction" — a machine emits them on a schedule, no discretion is
exercised, and the gate never reached them anyway. The run-report crons are
mandated by construction in exactly that sense, but they file from inside the
Inngest substrate (class 3), which the gate DOES reach. The three exits were
designed for discretionary, LLM-authored findings; a filing whose absence fails
the run is not one. So the exemption is the class-2 exemption, applied to the
subset of class 3 that shares class 2's property, and to nothing else.

**The fourth exit.** A directive line `run-report-label <label>` written by the
substrate (`_cron-claude-eval-substrate.ts`) into the per-spawn
`cron-allow.txt` — the ADR-058 grammar, the third directive shape — and
honoured by the hook iff a REAL `--label` token (any of the six spellings,
comma-anchored, dequoted) equals it. **Label only.** A `[Scheduled]`-prefixed
title-half was considered and cut: campaign-calendar's REQUIRED filings are
`[Content] Overdue: …`, so a title shape would have re-denied the one cron
whose issue titles are not the report shape. The agent can neither read nor
write `cron-allow.txt`, and the line is absent for every cron outside the map,
so the exit is not narratable: nothing an interactive filer or an off-map cron
can type reaches it. That is what makes it not the cut marker.

**The file-and-vanish path is closed for non-report titles, and counted otherwise.** A finding that borrowed
the label to pass the gate would still be a `scheduled-*` issue authored by
`app/soleur-ai`. The sweeper closes only `[Scheduled]`-titled,
`app/soleur-ai`-authored issues after `closeAfterDays`, so a label-borrowing
finding with a non-report title is never swept and stays visible; and every
filing under these labels is counted by measurement line 1c as a second
irreducible floor — inside the gate's reach, not reducible by it — so a
residue shows in the weekly numbers rather than vanishing.

**`keep-open` carries one meaning on three surfaces.** It is the sweeper's
kill-switch (`KILLSWITCH_LABELS`); the machinery drain excludes it from both
pool counts and applies it to the standing measurement issue it creates; and
measurement line 1d (`meta/machinery` minus `keep-open`) subtracts EVERY
`keep-open` machinery filing in the window, not only the standing issue — a
machinery finding an operator protects from the sweeper also leaves the
exit-1 count. That is the intended reading: a filing a person chose to keep
is no longer machinery exhaust the lever is measured against.

**Rejected alternatives, each with its mechanical reason.**

- *Once-per-run marker* (allow the first filing, deny the rest): `PreToolUse`
  fires on allow, not on success. A denied-then-retried or failed first
  `gh issue create` would consume the run's one allowance and the real filing
  would be denied.
- *Handler-side filing* (the TypeScript handler files the issue, the agent
  never does): the issue is the proof-of-output. Moving it out of the agent's
  run makes the verify step attest to the handler's own action, which is the
  self-reported-success shape this repo keeps removing.
- *`cronName` in argv or env*: ADR-058 keys per-cron policy on directive lines
  in the file precisely so the hook never trusts a name the spawn could carry.
- *A new closer*: the sweeper already carries the human-triage, kill-switch,
  `action-required` and FAILED-report guards; a second closer would be a second
  pin on every one of them.
- *A hook-written deny log* (`.jsonl` under `.claude/`): `permission_denials[]`
  in the result event already carries every deny — measured 2026-09-11 — so
  the substrate reads it there and emits `SOLEUR_CRON_FILING_DENY`; a second
  log would be a second copy of the same fact on a surface no runner can read.

**Where the operative text lives.** The hook header
(`cron-bash-allowlist-hook.mjs`, the EXIT 0 block) is canonical. This addendum,
ADR-058's consequence bullet, and the `wg-defer-only-after-inline-triage` body
are pointers to it, not restatements.

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
| 3 | Inngest cron agent substrate | `cron-bash-allowlist-hook.mjs` — the same three exits, plus the substrate-issued `run-report-label` directive (exit 0) for the run-report crons only (2026-09-11 addendum) |
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
adjective.

**And a DIRECTIONAL limit, which is the sharper one.** `Fix-Size:` is
self-reported and unverified, and the escape from the refusal is to claim a
LARGER fix — an agent that wants to file rather than fix writes
`Fix-Size: 300 lines / 12 files` and passes. "Not gameable by adjective" is true
and answers a different objection; it is gameable by numeral, and the gradient
points the wrong way. Compounding it, the shared taxonomy admits generic tokens
(`CLI`, `command`, `page`, `report`, `document`), so a machinery finding about
`/ship` can satisfy exit 2 with "User-Impact: the `/ship` command blocks". Neither
is fixable inside a shape check. What bounds them is that metric 1 is a PURE
filing count with no machinery exclusion — taking exit 1 does not hide a filing
from the headline — so gaming shows up as a rate that does not fall, within four
weeks, which is the backstop this ADR already names.

**The derivable-inputs predicate is a deny-list, and this ADR's own taxonomy
argues against deny-lists.** `.claude/hooks/lib/user-surface-taxonomy.txt` says a
deny-list "can only ever catch phrasings already in it; it rots against whatever
wording the current review agent happens to use." That applies verbatim to the
missing-numbers trigger, which matches a fixed set of phrasings, and its accept
arm is one-token satisfiable. It is retained because the alternative — a third
required field — is the form this design already rejected as enforcing nothing,
and because its failure mode is silence rather than a false pass. Recorded as
the one place the design contradicts its own stated principle. The weekly rate measurement is the backstop: if the rate does not
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
- **The weekly cadence measures and enforces; it does not yet close.** Stated
  plainly because a green run would otherwise imply the opposite. The drain step
  invokes `/soleur:drain-labeled-backlog`, which delegates to `/soleur:one-shot`
  and closes issues through a merged PR carrying `Closes #N`. That needs
  branch-push and pull-request authority; the workflow deliberately runs with
  `contents: read` and `issues: write`, so the closing arm cannot fire. Widening
  an unattended weekly agent to `contents: write` is a privilege and spend
  decision, not an implementation detail, and it is not taken here.
  Consequently, on merge the pool is 0 (the backfill proposes, it never applies)
  and the floor is waived every week. What this change guarantees is that the
  waiver is **legible**: the floor step emits `WAIVED-EMPTY`, `WAIVED-SUPPLY`,
  `MET` or `BREACH` into the standing measurement issue, and `WAIVED-EMPTY`
  says in words that it is not evidence of a drained backlog. The failure this
  avoids is the one the change exists to remove — an instrument whose green is
  indistinguishable from its blind spot. Closing the loop means applying the
  backfill and granting the drain the authority to open its PR, in that order.
- Two of the three levers that reduce the RATE are therefore live on merge (the
  ledger and the filing-time gate); the sweeper reduces the STOCK from
  2026-10-10; the weekly cadence reports. The success criterion is stated against
  the filing rate precisely because that is what the live levers move.

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
