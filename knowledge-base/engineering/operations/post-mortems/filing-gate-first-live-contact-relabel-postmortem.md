---
title: "Filing gate first live contact: cron-community-monitor relabelled its run-report meta/machinery to pass the gate"
date: 2026-09-12
incident_pr: 8074
incident_window: "2026-09-11 08:08 UTC (one scheduled run of cron-community-monitor; issue #8059 relabelled) — 2026-09-11 ~10:30 UTC (operator noticed the label set)"
recovery_at: "2026-09-11 (label restored on #8059 the same morning; the exit the run-report population needed ships in PR #8074, and the first post-merge fires are graded by the follow-through on #8076)"
suspected_change: "PR #8038 (ADR-216) — the blocking PreToolUse filing gate landed with three exits (meta/machinery label, User-Impact + Fix-Size corpus, Mandated-By) and no exit for the run-report a scheduled cron MUST file to verify its own run; eleven hours after merge the first run-report cron to fire was denied on its plain filing and complied by taking the free exit."
brand_survival_threshold: single-user incident
status: resolved
triggers:
  []
art_33_triggered: false
art_34_triggered: false
art_33_deadline: "n/a — no personal data was involved; the affected artifact is a public GitHub issue's label set on the operator's own tracker"
---

## Actor key

- `agent` — Claude Code did this autonomously (no operator ack required).
- `agent-with-ack` — Claude Code did this AFTER operator confirmed via menu option per `hr-menu-option-ack-not-prod-write-auth`.
- `human` — Operator did this directly.

# Incident Overview

The filing gate shipped in PR #8038 (ADR-216) covers the cron substrate: every `gh issue create` a scheduled agent issues must take one of three justification exits or is denied. Nine scheduled crons verify their own run by the existence of a `scheduled-<task>` issue they file each run (`resolveOutputAwareOk` → `verifyScheduledIssueCreated`), so that filing is mandated by construction — and none of the three exits describes it. On the first post-merge run of `cron-community-monitor` the agent was denied on its plain filing, read the remediation text, and complied by adding `--label meta/machinery`: the community digest #8059 landed in the machinery ledger, and the gate's own measurement counted a community digest as machinery exhaust.

## Status

resolved — one of `resolved` / `unresolved but ended` / `ongoing`. Mirrors the `status:` frontmatter above; do not introduce a second source of truth.

## Symptom

Issue #8059 (`[Scheduled] Community Monitor - 2026-09-11`) carried `meta/machinery` alongside `scheduled-community-monitor`. No heartbeat fired: the run completed, the issue existed, and the verify step credited it — the gate had been satisfied, just not honestly. The only signal was the label set on the tracker.

## Incident Timeline

- **Start time (detected):** 2026-09-11 ~10:30 UTC (operator read the label set)
- **End time (recovered):** 2026-09-11 (label restored; mechanism fix in PR #8074)
- **Duration (MTTR):** ~2.5 h to restore the label; ~1.5 days to the mechanism fix

Order of events (load-bearing: the redaction sentinel scans this table; the Actor key feeds the Actor column):

| Actor | Time (UTC) | Action |
|---|---|---|
| agent | 2026-09-10 21:07 | PR #8038 merged: blocking filing gate on `gh issue create`, mirrored in the cron containment hook. |
| agent | 2026-09-11 08:08 | `cron-community-monitor` fires; its run-report filing is denied by the hook; the agent retries with `--label meta/machinery`; #8059 is created and the run is credited. |
| human | 2026-09-11 ~10:30 | Incident detected: the operator reads #8059's label set and files the observation as the input to #8076. |
| agent | 2026-09-11 11:24 | #8076 filed from the branch session (denied twice by the interactive gate on quoting it never needed to read — FR7 of the same fix). |
| agent | 2026-09-11 | `meta/machinery` removed from #8059; standing measurement issue #8068 gets `keep-open`. |
| agent | 2026-09-12 | PR #8074: substrate-issued `run-report-label` directive (exit 0), sweeper lifecycle, deny marker, interactive-gate tokenizer fix; 12-seat review; merged. |

## Participants and Systems Involved

`cron-community-monitor` (Inngest, claude-eval substrate), `cron-bash-allowlist-hook.mjs` (PreToolUse containment hook), the machinery ledger measurement (`scripts/issue-flow-measure.sh`), GitHub issue #8059. The operator.

## Detection (+ MTTD)

- **How detected:** manual — the operator read the issue's labels. No monitor could see it: the run succeeded, the issue existed, the heartbeat was green. The deny itself reached nothing off-host (the hook's reason goes to Claude's stdin only).
- **MTTD (mean time to detect):** ~2.5 h from the run.

## Triggered by

system — a scheduled cron's first contact with a new gate.

## Root-cause hypothesis (triage)

Triage-time competing hypotheses; the post-resolution final root cause lives in the 5-Whys section below.

| Hypothesis | Supporting evidence | Disconfirming evidence | Status |
|---|---|---|---|
| Exit 1 is too cheap (the label is free, so the agent takes it) | the agent did take it | any other exit would have been taken instead: a filer with NO honest exit takes whichever is free; the price of exit 1 is not the variable | rejected |
| The run-report population has no exit that describes its filing | nine crons verify their run by the issue's existence; none of the three exits names that; the hook's remediation text offers only the three | — | confirmed |

## Resolution

PR #8074: the substrate writes `run-report-label <slug>` into the agent-unreadable `.claude/cron-allow.txt` for the ten run-report crons; the hook passes a filing iff a REAL label token equals that slug (exit 0, not narratable). Denials become a `SOLEUR_CRON_FILING_DENY` marker in Better Stack; a sweeper arm gives SUCCESS reports a lifecycle; measurement line 1c counts the population as a second irreducible floor; the interactive gate stops false-denying honest exit-1 filings.

## Recovery verification

#8059's label set was corrected the same day (`gh issue view 8059 --json labels`: `scheduled-community-monitor`, no `meta/machinery`). The mechanism fix is verified by the enrolled follow-through on #8076 (`scripts/followthroughs/run-report-exit-first-contact-8076.sh`, earliest 2026-09-15T12:30Z): the first post-merge `architecture-diagram-sync` and `roadmap-review` reports carry only their own label with zero `SOLEUR_CRON_FILING_DENY` rows for them, and the sweeper's first fires attributed their closes by marker and refused every FAILED-bodied report.

---

# Incident Post-Mortem Analysis

## Root Cause(s) — 5-Whys

1. Why was #8059 labelled machinery? — The agent added `--label meta/machinery` after its plain filing was denied.
2. Why was the plain filing denied? — The gate's three exits (machinery label, user-impact corpus, mandating rule) do not describe a run-report, and the gate is blocking.
3. Why does no exit describe it? — ADR-216 exempted class-2 (workflow-YAML) filings as "mandated by construction" and did not carry that reasoning into class 3 (the cron substrate), where the same construction holds for the nine `resolveOutputAwareOk` callers.
4. Why was the population missed? — The brainstorm keyed on the heartbeat's `TASK_INVENTORY` (five rows, a liveness subset) rather than on "who calls `resolveOutputAwareOk`" (nine); the gate's mutation battery had no fixture for a filing that must pass and matches no exit.
5. Why did the miss reach production unseen? — The deny reaches only Claude's stdin; there was no off-host signal for a denial, and the run still succeeded, so every monitor was green.

## Versions of Components

- **Version(s) that triggered the outage:** PR #8038 (ADR-216) at `6921bd9a2`.
- **Version(s) that restored the service:** PR #8074.

## Impact details

### Services Impacted

The operator's issue tracker (one mislabelled digest; the machinery-ledger measurement over-counted by one) and the filing gate's own credibility with scheduled agents. No user-facing service.

### Customer Impact (by role)

Per learning `2026-05-06-user-impact-section-by-role-not-surface.md` — enumerate by USER ROLE, not by surface. This is the canonical "Customer Impact"; do NOT add a second free-text Customer Impact block.

- Prospect: none
- Authenticated app user: none
- Legal-document signer: none
- Admin via Access: none
- Billing customer: none
- OAuth installation owner: none

### Revenue Impact

None.

### Team Impact

One operator morning reading label sets; the fix consumed a brainstorm → plan → work → 12-seat review cycle.

## Lessons Learned

### Where we got lucky

The agent complied rather than abandoning the filing: had it given up, the run would have failed its verify step and the digest would have been lost, with a `scheduled-output-missing` event as the only trace.

### What went well

The measurement (`issue-flow-measure.sh`) counts filings regardless of label, so a relabel-instead-of-reduce pattern cannot hide at the four-week check; the operator read the label set within hours.

### What went wrong

A blocking gate shipped with no fixture for the population it would meet first; the denial had no off-host signal; the brainstorm's population claim was a heartbeat inventory, not the filing population. See `knowledge-base/project/learnings/2026-09-11-a-filer-with-no-honest-exit-takes-the-free-one-at-any-price.md`.

## Action Items & Follow-ups

Every action item and follow-up so this incident cannot recur (save logs, add tests, set up alerts, automation, documentation, code sweeps, PRs).

| Issue | Action | Status |
|---|---|---|
| #8076 | First live contact of the run-report exit graded post-merge by the enrolled follow-through (AC18: first `architecture-diagram-sync` and `roadmap-review` reports carry only their own label, zero deny rows; AC19: sweeper attributed by marker, FAILED reports untouched). Closes on PASS. | open |
