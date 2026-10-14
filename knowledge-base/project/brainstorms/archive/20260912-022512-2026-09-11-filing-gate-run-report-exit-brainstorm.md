# Brainstorm: a mandated run-report has no honest exit from the filing gate

**Date:** 2026-09-11
**Inciting issue:** #8059 (`[Scheduled] Community Monitor - 2026-09-11`, filed with `meta/machinery`)
**Gate under discussion:** `guardrails:require-filing-justification` (PR #8038, ADR-216)
**Branch:** `feat-filing-gate-run-report-exit`
**Lane:** cross-domain (forced by user-brand-critical; see below)

## What We're Building

Within 11 hours of #8038 merging, the community-monitor cron was denied on its
plain filing, read the gate's remediation, and complied by taking exit 1
(`--label meta/machinery`) for a community digest that is not a machinery
finding. The gate worked end-to-end on the population it targets. The
question it raised was "is exit 1 too cheap?" — and the answer this brainstorm
reached is **no, that is the wrong question**. A filer with no honest exit
takes the free one at any price; a `Machinery: <path>` requirement would have
produced `Machinery: scripts/community-router.sh`.

What #8059 actually exposed is a **population gap**: ADR-216 §"deliberately no
fourth" says "name the filing that must bypass the gate, cannot be labelled
machinery, and cannot name a user impact — there isn't one." There are four.
`cron-cloud-task-heartbeat.ts` `TASK_INVENTORY` lists crons that MUST file a
`scheduled-<task>` issue on every run because the heartbeat detects cron
silence by that issue's existence, and the persistence handshake refuses to
commit the run's artifacts until it exists. ADR-216 exempted class 2 (workflow
YAML) as "mandated by construction"; these run in class 3 (the cron substrate)
under the same reasoning and got no exit.

We are building five coupled things, all keyed off that population:

1. **A closed, non-narratable run-report exit** in the cron containment hook.
   The substrate writes a `run-report-label scheduled-<task>` directive into
   the per-spawn `.claude/cron-allow.txt` (the same handler-produced,
   agent-unreadable, agent-unwritable file that already carries `mcp-allow` and
   `navigate-origin`). The hook passes a `gh issue create` iff a real `--label`
   token equals that directive. Four crons get the directive:
   `community-monitor`, `content-generator`, `roadmap-review`,
   `competitive-analysis`. **Not** `legal-audit`: it files up to five per-gap
   *findings* under `scheduled-legal-audit` (`cron-legal-audit.ts:148-160`),
   which is audit exhaust — 15 open, 0 ever closed — and stays on exits 1–3.
2. **Two new measurement lines** in `scripts/issue-flow-measure.sh`: the
   class-3 run-report floor (`author:app/soleur-ai` carrying a `scheduled-*`
   label — 54 of the 330 headline filings this window, sitting *inside* the
   gate's supposed reach though the gate can never move them) and the exit-1
   share (filings carrying `meta/machinery`), so the 2026-10-08 check can tell
   relabel from reduce. Plus: the machinery-drain pool query counts the standing
   measurement issue #8068 itself (it carries `meta/machinery`); exclude it.
3. **A minimal run-report lifecycle.** SUCCESS run-reports auto-close at 3× the
   cron's heartbeat `maxGapDays` (community ≈9 d, weekly producers ≈27–30 d).
   Never auto-close a title matching `- FAILED` or `[cloud-task-silence]`.
   Exclude `scheduled-*` from daily triage, which labelled 21 of 43 digests
   `priority/p1-high, type/bug` and hid the one real signal (#8027: "Credit
   balance is too low" — a handler-filed FAILED report nobody read).
4. **Observable denials.** The hook writes its deny to Claude Code's stdin
   channel only (`cron-bash-allowlist-hook.mjs:692`); nothing reaches Better
   Stack, and the denial→retry story behind #8059 is inferred from the label
   set. The hook appends a deny record to `.claude/filing-denials.jsonl`
   (try/catch, exit-0 contract preserved — the hook's first filesystem write);
   the substrate reads it post-exit beside `stdoutTail` and emits a
   `SOLEUR_CRON_FILING_DENY` WARN marker (the `SOLEUR_CLAUDE_COST` pattern).
5. **Relabel #8059** — drop `meta/machinery`. It and #8068 are the entire
   machinery-drain pool today: 2 of 2 are reports, 0 are findings. When the
   drain's closing arm is granted push authority it would one-shot a community
   digest.

## Why This Approach

Three shapes were weighed for the population fix:

| Shape | Verdict |
|---|---|
| **Substrate directive (chosen)** | Encodes "mandated by construction" (the class-2 reasoning) in the same file-driven grammar ADR-058 established. Handler-derived from `TASK_INVENTORY`, absent for the other issue-creator crons, unreadable by the agent. Not the exit ADR-216 cut — that was a *purpose-named marker any agent narrates*. Small-medium. |
| Handler files the run-report | No new exit, no ADR amendment. But the issue is the proof-of-output (`verifyScheduledIssueCreated`, `_cron-shared.ts:820`); four prompts and the liveness contract would need a new completion artifact. Medium-large. Revisit only if the lifecycle becomes handler-owned anyway. |
| Raise exit 1's price (`Machinery: <path>`) | Answers a different question and would not have changed #8059. Deferred until the new exit-1-share line can say whether it is needed. |

**Once-per-run enforcement was considered and rejected** (CTO). The hook is
PreToolUse-only: a marker on *allow* is not a marker on *success*, so a
transient `gh` failure plus retry would deny the REQUIRED filing and the run's
persistence would be refused. The loophole — a directive cron filing a
discretionary finding under its own label — is accepted and *measured* by the
run-report floor line; roadmap-review's feature issues carry no
`scheduled-roadmap-review` label (`cron-roadmap-review.ts:166` scopes it to the
summary) so the practical exposure is small.

**Why lifecycle now and not later:** run-reports have no lifecycle at all. The
43 open community digests were last mass-closed by the operator on 2026-07-27
(three in one second — a loop, by hand). The mislabel in #8059 accidentally
gave a run-report the right lifecycle (90-day expiry) via the wrong ledger;
this gives it the right lifecycle via the right mechanism.

## Key Decisions

| # | Decision | Rationale |
|---|---|---|
| 1 | The run-report exit is a **substrate directive**, not a fourth agent-narratable exit | Agent cannot read or write `cron-allow.txt`; the label is already the heartbeat's output contract. ADR-216's cut applied to narratable markers. |
| 2 | Directive covers **four** crons, not `TASK_INVENTORY`'s five | legal-audit's `scheduled-legal-audit` issues are per-gap findings (up to 5/run), the exact population the gate exists to gate. |
| 3 | **No once-per-run marker** | Allow ≠ success; would break the REQUIRED filing on any retry. Loophole measured instead. |
| 4 | ADR-216 gets an **amendment** and `wg-defer-only-after-inline-triage` gets a **rule-body edit + ack line** | `AGENTS.rules.md:89` states the closed three-exit set in words; leaving it false is worse than an honest ack. Same shape as the #7425 "narrowing recorded honestly" line. |
| 5 | Measurement adds lines, never subtracts from the headline | ADR-216's own rule: the floor is reported beside the headline, not netted out. |
| 6 | Lifecycle closes SUCCESS only; FAILED / `[cloud-task-silence]` never | Those are the only run-reports carrying operator-relevant information. |
| 7 | `scheduled-*` excluded from daily triage | Priority labels on run-reports are noise that also shields them from the sweeper's product-facing guard. |
| 8 | Denial observability ships **in this feature** | A new gate branch with no telemetry repeats the empty-telemetry-is-not-absence class (`hr-observability-as-plan-quality-gate`). |
| 9 | #8068 stays `meta/machinery` but is excluded from the drain pool query | It is class 2 (never traverses the gate); the label is bookkeeping. The pool off-by-one is the bug. |
| 10 | **Productize Candidate:** run-report-as-issue is the wrong shape (CPO) | Liveness → Sentry monitor (already exists); SUCCESS reports stop being issues; FAILED reports become `action-required` so the operator digest surfaces them. Follow-up issue, not in scope. |

## User-Brand Impact

- **Artifact:** the cron containment hook's filing predicate
  (`cron-bash-allowlist-hook.mjs`) and the four scheduled run-report crons
  whose persistence depends on it.
- **Vector:** a run-report cron that cannot file its REQUIRED issue loses the
  run's artifacts (the digest file is never committed) and the heartbeat reads
  it as silence; conversely a directive that is too wide waves audit exhaust
  past the gate and re-inflates the backlog the gate exists to shrink. Neither
  touches a user's data; the exposure is operator trust in the instrument.
- **Threshold:** single-user incident.

## Open Questions

1. **legal-audit's honest exit.** With no directive, its per-gap findings will
   be denied on first contact (quarterly; next fire 2026-10-01). A legal gap
   names a user-received document, so exit 2 (`User-Impact: <document>` +
   `Fix-Size:`) is honest — the prompt should be told to emit it. Plan-time.
2. **Lifecycle substrate.** Extend `cron-stale-deferred-scope-outs.ts` (it
   already sweeps by label with per-arm caps and kill switches) with a
   per-label age table, or a separate small closer keyed on `TASK_INVENTORY`?
   Plan-time; the former reuses four fail-toward-skipping guards.
3. **Duplicate run-reports** (#6756/#6758, #6871/#6872, #6402/#6404 — two per
   fire). Not caused by the gate; the lifecycle drains them, the root cause is
   a separate finding.
4. **Deny-record path.** `.claude/filing-denials.jsonl` is agent-denied for
   reads and writes, which is what makes it trustworthy; confirm the hook's
   process has write permission there under the spawn's uid.

## Domain Assessments

**Assessed:** Marketing, Engineering, Operations, Product, Legal, Sales, Finance, Support

### Engineering

**Summary:** Directive exit is sound and is not the exit ADR-216 cut; requires
an ADR amendment. Once-per-run marker is feasible but must not be built (allow ≠
success; legal-audit's five-per-run findings break it by design). Denials can
reach Better Stack via a hook-appended jsonl read post-exit by the substrate and
emitted as a pino WARN marker. Handler-side filing rejected: the issue is the
proof-of-output.

### Product

**Summary:** No product consumer reads `scheduled-*` issues — operator-digest
reads `action-required` only, ticket-triage never mentions them, the heartbeat
queries `state: all`. The issue is a liveness token; closing it costs nothing.
Daily triage mislabelled 21 digests p1-high and hid #8027's "Credit balance is
too low". Lifecycle: close SUCCESS at 3× cadence, never FAILED. Productize
candidate: liveness off issues entirely, FAILED → `action-required`.

### Legal

**Summary:** Nothing legal turns on lifecycle or labels — Article 30 PA-32 §(f)
already records the community-observation output as indefinite/permanent and
GitHub as host. Editing the hook files carries no ack obligation; editing
`AGENTS.rules.md:89` does. Pre-existing register gap: PA-32 §(a)(i) names only
the committed digest file, not the `[Scheduled]` issue surface (which names a
Discord handle in #8059) — follow-up for the legal-compliance-auditor.

## Capability Gaps

None. Every mechanism proposed has an in-repo precedent: directive grammar
(`parseAllowlist`, `cron-bash-allowlist-hook.mjs:484-502`; ADR-058), label
sweeper with caps and kill switches (`cron-stale-deferred-scope-outs.ts:53-105`),
post-exit WARN marker (`SOLEUR_CLAUDE_COST`, `claude-cost-marker.ts`),
handler-side issue filing (`#4960` FAILED fallback).

## Recorded deferrals (documented in place, per `wg-defer-only-after-inline-triage`)

None of these has a concrete trigger inside six months that this feature would
own, so they are recorded here rather than filed:

- **Productize Candidate — run-report-as-issue is the wrong shape** (CPO). The
  issue conflates a liveness token (heartbeat), an audit trail nobody reads, and
  a failure alert that never reaches the operator. Target shape: liveness on the
  existing Sentry cron monitor; SUCCESS reports stop being issues; FAILED reports
  become `action-required` so the operator digest surfaces them. Trigger: the
  next FAILED run-report that the operator learns about late.
- **PA-32 §(a)(i) register gap** (CLO). The Article 30 row names only the
  committed digest file as the community-observation publication surface; the
  `[Scheduled]` issue surface (which named a Discord handle in #8059) is
  unrecorded. One-cell amendment owned by the legal-compliance-auditor; the
  quarterly legal-audit fires 2026-10-01.
- **Duplicate run-reports per fire** (#6756/#6758, #6871/#6872, #6402/#6404).
  Not gate-caused; the lifecycle drains the stock. Trigger: a duplicate filed
  after the lifecycle ships.

## Session Errors

1. Initial framing counted `TASK_INVENTORY`'s five crons as five run-reporters.
   Reading the prompts showed legal-audit's label covers findings, not a
   report; the directive scope was cut to four before the approaches were put
   to the operator.
2. The 2026-07-27 mass-close was described as "by hand" from `state_reason`
   alone; verified afterwards via the timeline (`closed_by: deruelle`, three
   closes in one second).
3. **Filing the tracking issue for this brainstorm was denied twice by the
   interactive gate**, both honest exit-1 filings. (a) The heredoc-then-`gh`
   one-liner contained apostrophes ("Soleur's") in the body; `xargs -n1`
   aborts on an unmatched single quote, the truncated token list never reaches
   `--label meta/machinery`, and the refusal says to add the flag that was
   passed — the `cq-assert-anchor-not-bare-token` remediation-loop class
   again, one layer down. (b) Re-run as `--body-file` alone, the
   unreadable-body deny (`guardrails.sh:616-628`) fires before `_fj_pass` is
   honoured, so an exit-1 filing is refused for a body it does not need. Both
   are folded into the spec (FR7) since the fix lives in the same predicate.
