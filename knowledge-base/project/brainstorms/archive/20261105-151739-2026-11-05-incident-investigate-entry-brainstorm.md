---
title: incident investigate entry — pull logs into the existing incident skill
date: 2026-11-05
brand_survival_threshold: single-user incident
lane: cross-domain
status: brainstormed
pr: 12143
---

# Brainstorm: founder pull into the incident skill

"Incident" here means a production outage the founder is already responding to, the sense of `plugins/soleur/skills/incident/SKILL.md`. It does not mean the rule-telemetry counter in `.claude/hooks/lib/incidents.sh`. The glossary has no entry for the word.

## What We're Building

One change to the existing incident skill. When the founder starts it, the skill runs the three log readers that already exist, builds a hypothesis card, runs the redaction sentinel on that card, and shows the cleared card before it asks the founder to confirm facts.

The readers are `scripts/betterstack-query.sh`, `scripts/sentry-issue.sh`, and `scripts/supabase-logs-query.sh`. The card proposes only the fields a cleared log line can support. The founder still confirms severity, still types `ACK-ART33` and `ACK-ART34` when those fire, and still types `COMMIT-PIR`.

## Why This Approach

The Better Stack Claude plugin ad bundles three claims: investigate inside the agent, auto-fix errors on a schedule, and configure Better Stack without the UI. The founder asked for the first claim only, as a Soleur entry for the incident skill.

The first claim is already half-present. Phase 0 of the incident skill tells the agent to pull those three scripts, then collects 19 facts from the founder (`title` through `team_impact`). No phase executes a query. `soleur:go` sends outage speech to that skill. `soleur:reproduce-bug` pulls the same readers for a bug repro and does not write a post-mortem.

Ruled by CTO agent, 2026-11-05: extend `soleur:incident` with one operator-invoked pull-first phase. A second skill would copy the transcript gate and the post-mortem path.

Two earlier decisions stay closed:

- The 2026-02-13 SRE-agent brainstorm (`knowledge-base/project/brainstorms/archive/20260213-150351-2026-02-13-sre-agent-brainstorm.md`) scoped an agent to Terraform generation and review, and left observability out. `plugins/soleur/agents` has no `sre-agent.md`. This work does not add one.
- The 2026-05-13 incident-commander brainstorm locked skill-not-agent, operator-invoked only, no cron auto-fire, redaction before any text is shown, and the Art. 33/34 gate before the narrative. Its "no Sentry auto-fetch" line was written when these readers did not exist. The readers exist now. Auto-fire stays out.

## User-Brand Impact

**Artifact:** the hypothesis card the incident skill shows the founder, and any post-mortem field the founder then confirms from that card.

**Vector:** a fluent wrong cause, or a production log line (stack trace, pseudonymous id, raw workspace id, secret) shown in the transcript or committed in the post-mortem before the sentinel runs.

**Threshold:** `single-user incident`.

## Key Decisions

| Decision | Value | Rationale |
|---|---|---|
| Shape | Extend `plugins/soleur/skills/incident/SKILL.md`. No new skill, no new agent. | CTO ruling. The skill already owns the post-mortem. |
| When it runs | While the incident is open, before the 19-field list. Phase 7's 5-whys stay founder-written after recovery. | Founder ask was a drafted cause handed to the incident report, not a rewrite of the post-recovery review. |
| What the founder must supply | Optional window. Optional Sentry issue id. An optional complaint sentence, treated as a claim. | The readers cannot invent a Sentry id. Defaults below cover the window. |
| Better Stack default | `doppler run -p soleur -c prd_terraform -- scripts/betterstack-query.sh --since 1h`, archive arm on. Name the table in the card. Default table is the Inngest vector source. | `--no-archive` returns a short hot window with exit 0. A zero on the default table is not a statement about git-data. |
| Supabase default | `--ref ifsccnjhymdmidffkzhl --since 24h` under `doppler run -p soleur -c prd`. Inngest project `pigsfuxruiopinouvjwy` only when the founder names that project. | `--ref` is required. A missing ref used to query the wrong project and return a covered zero. |
| Sentry | Run `scripts/sentry-issue.sh` only when the founder supplies an issue id. Otherwise the card says `sentry: not-queried reason=no-issue-id`. No list mode. | Issue and latest-event modes require an id. `--host-events` is a different read. |
| Partial Doppler | If `prd` is unreadable and `prd_terraform` works, draft from Better Stack and mark Sentry and Supabase unverified. If Doppler itself is missing, the card says nothing was queried. | A missing read is a gap, not a cause. Better Stack exit 3 means the query never ran. Supabase exit 3 means the data verdict is inconclusive. Branch on the script. |
| Card contents | Ranked hypotheses, what would disprove each, and per source: window, table or ref, exit or coverage verdict. A cleared error line only after the sentinel. | One confident paragraph is how a wrong mechanism gets confirmed (#4886). |
| Fields telemetry must not fill | `affected_user_count`, `data_categories_breached`, `risk_to_subjects`, `revenue_impact`, Art. 33/34 booleans, `brand_survival_threshold`, `detected_at`. | None of the three scripts returns a user count. A drafted 0 becomes "no breach" in Phase 1. A log timestamp must not start the 72-hour figure. |
| Confirm vs ack | Confirming the card fills proposed Phase 0 fields the founder accepts. It is not `ACK-ART33`, not `ACK-ART34`, and not `COMMIT-PIR`. No new ack token. | Those tokens already exist. A new token would be a second ceremony. |
| Redaction | `plugins/soleur/skills/incident/scripts/redact-sentinel.sh` runs on the card before it is shown and before it is written. Raw script stdout is not printed into the transcript. | The transcript is a write boundary. Vendor `--redact` on the Sentry script is a narrower mask. |
| Classification budget | Phase 1 still targets a fast confirm. The pull is outside that budget and does not block the Art. 33/34 prompts once the founder has confirmed the fields those prompts read. | Three remote reads are slower than the classification budget. The clock is not started from a log line. |
| Awareness note | The card prints the pull time. If a cleared line is personal data, that time is the candidate awareness moment. The skill's deadline formula stays `detected_at` plus 72 hours after the founder confirms `detected_at`. | CLO: the published policy anchors the 72 hours to awareness. This slice does not change the formula. |
| Marketing | No launch, no public copy. | Operator-facing founder command. `hr-new-skills-agents-or-user-facing` allows omitting the CMO for an internal CLI. The 2026-05-13 CMO note already forbade a standalone incident-skill launch. |
| Cost | No new vendor, no schedule, no Better Stack plugin. | COO: the three readers and both Doppler configs are already paid. |

## Non-Goals

- Scheduled auto-fix, cron or webhook auto-PIR, paging, on-call rotation.
- Installing Better Stack's Claude plugin.
- A skill or agent that configures Better Stack outside Terraform.
- Reviving the Terraform SRE agent, or extending it into observability.
- Production writes: apply, rotate, resolve, rescue, reboot, Doppler write, breach-register row.
- A Sentry list mode.
- Editing the privacy policy, the GDPR policy, or the data-protection disclosure in this change.
- Changing the Art. 33 deadline formula from `detected_at` plus 72 hours.
- Replacing Phase 7's 5-whys.

## Open Questions

1. **Tracking issue.** Not filed at brainstorm time. An unbuilt feature has no measured `Fix-Size`, and `0 lines / 0 files` is refused by the filing gate (`knowledge-base/project/learnings/workflow-issues/2026-11-02-brainstorm-new-feature-issue-gate-needs-measurable-size.md`). The tracker is draft PR #12143. File the issue at plan time, once the diff is sized.
2. **Policy text (out of scope for this change).** Privacy Policy §5.10 and §5.14 and Data Protection Disclosure §2.3(m) name the host, Better Stack, Sentry, and Supabase. They do not name the harness model provider that receives a pulled line. Issue #7529 is open: no Better Stack Article 28(3) instrument is executed. Plan Phase 2.7 runs `soleur:gdpr-gate`. Counsel owns any edit to those three documents. This slice must not claim the sections already cover the transcript copy.
3. **Art. 33 anchor (parked).** Counsel owns whether a future change should compute the deadline from awareness rather than from confirmed `detected_at`. This slice shows the pull time and leaves the formula alone.
4. **Hot-window length (parked).** Not measured live. The card always includes the Better Stack archive arm and does not encode a minute count.
5. **Sentry `count` (parked).** Not verified as users versus events. The card omits it.

## Domain Assessments

**Assessed:** Product, Legal, Engineering, Operations. Marketing omitted for an operator-facing command (`hr-new-skills-agents-or-user-facing`). Sales, Finance, and Support had no match.

### Product (CPO)

**Summary:** The user is the founder during an incident they already noticed. Extend the incident skill. Show a sentinel-cleared hypothesis card with competing hypotheses and a coverage line per source. Confirming the card does not replace the Art. 33 acknowledgement or `COMMIT-PIR`.

### Legal (CLO)

**Summary:** A founder-invoked pull is not a new Better Stack processor and is not the deferred auto-fetch. It is a new recipient: the harness model provider. Run the existing sentinel before the card is shown. Run the Art. 33/34 gate before the narrative. Invoke `soleur:gdpr-gate` at plan Phase 2.7. Do not write that an Article 28(3) instrument exists. Draft internal review, not legal advice.

### Engineering (CTO)

**Summary:** Ruling recorded in Key Decisions. The pull calls the three scripts and nothing else. Empty or exit-0 results are not health. `affected_user_count` and the breach booleans stay founder-confirmed.

### Operations (COO)

**Summary:** Zero new spend. The command calls `prd_terraform` for Better Stack and `prd` for Sentry and Supabase. It does not replace the query runbooks or add a second post-mortem writer.

## Capability Gaps

No new reader. The gap is an executed phase.

Evidence: `plugins/soleur/skills/incident/SKILL.md` names the three scripts in the Phase 0 blockquote and then lists the 19 operator fields. A search of that skill tree finds the script names in that sentence; the fenced bash is the duration math and `redact-sentinel.sh`. `plugins/soleur/commands/go.md` routes a live production incident to `soleur:incident` and has no separate "pull the logs" row. `find plugins/soleur/agents -iname '*sre*' -o -iname '*incident*'` from this worktree returns nothing.

## Lane

`cross-domain`. Phase 0.1 set user-brand-critical, which forces this lane. CPO, CLO, and CTO ran. COO ran because the change is an incident-process change on vendors the company already pays.

## Resume Prompt

```
/plan — founder pull into the incident skill.
Brainstorm: knowledge-base/project/brainstorms/archive/20261105-151739-2026-11-05-incident-investigate-entry-brainstorm.md.
Spec: knowledge-base/project/specs/archive/20261105-151739-feat-incident-investigate-entry/spec.md.
Branch: feat-incident-investigate-entry.
Worktree: .worktrees/feat-incident-investigate-entry/.
PR: #12143 (draft). No tracking issue yet.
Brand-survival threshold: single-user incident.
```
