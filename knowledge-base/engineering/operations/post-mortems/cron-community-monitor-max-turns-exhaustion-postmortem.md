---
title: "cron-community-monitor silent digest dropout (max-turns exhaustion)"
date: 2026-06-03
incident_pr: 4870
incident_window: "2026-05-25 → 2026-06-03 (~9 days; surfaced by Sentry WEB-PLATFORM-1Z at 2026-06-03T08:06:02Z)"
suspected_change: "No single change. The 50-turn spawn budget (set when the cron migrated GHA→Inngest in #4468) became insufficient as the digest task grew (ephemeral-workspace plugin load + 7-platform collection + git→PR→issue). Turn exhaustion was a dark silent no-op until #4714 (output-aware heartbeat) + #4786 (stdout-tail capture) made it observable."
brand_survival_threshold: aggregate-pattern
status: resolved
triggers:
  []
art_33_triggered: false
art_34_triggered: false
art_33_deadline: "n/a"
---

## Actor key

- `agent` — Claude Code did this autonomously (no operator ack required).
- `agent-with-ack` — Claude Code did this AFTER operator confirmed via menu option per `hr-menu-option-ack-not-prod-write-auth`.
- `human` — Operator did this directly.

## Symptom

The daily `cron-community-monitor` Inngest function (`0 8 * * *` UTC) stopped producing its community-digest GitHub issue. The last successful digest was issue #4401 / PR #4400 on **2026-05-25**. On 2026-06-03 the output-aware heartbeat fired Sentry `WEB-PLATFORM-1Z`: `cron-community-monitor spawn exited non-zero AND created no "scheduled-community-monitor" issue in the run window (since 2026-06-03T08:00:08.046Z)`. The cron monitor had been (correctly) RED on every fire since detection machinery landed.

## Root-cause hypothesis

| Hypothesis | Supporting evidence | Disconfirming evidence | Status |
|---|---|---|---|
| Turn-budget exhaustion: the spawned `claude --print` hit its 50-turn ceiling before the final issue-create step | Sentry event `eff0bef435664f4d929d2ac3aa3e6a7e` extra: `exitCode=1`, `stdoutTail="Error: Reached max turns (50)"`, ~6 min elapsed (08:00:08→08:06:02) | none | **CONFIRMED** |
| Wall-clock timeout (`MAX_TURN_DURATION_MS` 50 min) | — | `abortedByTimeout` would be true and ~50 min would elapse; only ~6 min did, no `claude-eval-timeout` event | Refuted |
| Infra fault (git clone / auth / DNS / disk) | — | `stderrTail` empty; no `setup-ephemeral-workspace` event near the fire | Refuted |
| Sandbox/permission denial of `gh issue create` | — | empty `stderrTail`; `cron-daily-triage` produces output through the SAME `DEFAULT_CLAUDE_SETTINGS` | Refuted |
| Monitor over-firing on a legitimately-empty run | — | producer is always-create (even no-platform path files a `- FAILED` issue); zero output IS the failure | Refuted |

## Timeline

| Actor | Time (UTC) | Action |
|---|---|---|
| platform | 2026-05-25 | Last successful digest (issue #4401 / PR #4400). |
| platform | 2026-05-26..06-02 | Cron fired daily; spawn exhausted 50 turns each run; no digest issue produced. Dark until detection machinery landed. |
| platform | 2026-06-03T08:00:08Z | Cron fired; spawn exited 1 with `Reached max turns (50)`; no issue created. |
| platform | 2026-06-03T08:06:02Z | Output-aware heartbeat posted `status=error`; Sentry `WEB-PLATFORM-1Z` emitted; operator notified by email. |
| human | 2026-06-03 ~10:06 CEST | Operator forwarded the Sentry alert; triage began. |
| agent | 2026-06-03 | Root cause pulled from live Sentry `extra`; fix authored (`--max-turns` 50→80) in PR #4870. |

## Recovery verification

- **Pre-merge:** unit guard (`cron-community-monitor.test.ts`, 60/60, RED-verified at `50`); full `webplat` shard 8205 passed; `tsc --noEmit` clean.
- **Post-merge (AC8/AC9, tracked as follow-through):** after deploy, a live cron fire (natural 08:00 UTC or `cron/community-monitor.manual-trigger`) must (a) create a `[Scheduled] Community Monitor - <date>` issue labeled `scheduled-community-monitor`, and (b) post Sentry monitor `status=ok`. If still RED with `Reached max turns (N)` at 80, the prompt-efficiency lever re-opens with fresh `stdoutTail` evidence.

## Follow-ups

- [ ] Post-merge AC8/AC9 live verification (tracked via /ship follow-through issue).
- [ ] (Considered, not filed) A cohort-wide turn-budget audit — every `cron-*.ts` always-create producer should be checked against its task weight. Deferred: no evidence other crons are under-budgeted (daily-triage at 80 is healthy; this was the only RED producer).

## Who was affected (by role)

- Prospect: none.
- Authenticated app user: none — internal-ops cron, no user-facing surface.
- Legal-document signer: none.
- Admin via Access: none.
- Billing customer: none.
- OAuth installation owner: none.
- **Operator (Soleur founder):** lost ~9 days of daily community-activity visibility (Discord/GitHub/HN/Bluesky digests, new stargazers, external interactions) and received a daily correct-but-fatiguing Sentry RED page.

## Art. 33/34 assessment

No personal-data exposure. This is an availability gap in an internal-ops digest cron; the spawn-env allowlist is unchanged and the digest aggregates only public/community-platform data. `art_33_triggered: false`, `art_34_triggered: false` — n/a (no breach of personal data).
