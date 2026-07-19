---
title: "Community monitor reported fabricated GitHub stats for ~4 months while self-reporting the failure 16 times"
date: 2026-07-19
incident_pr: 6709
incident_window: "2026-03-22 → 2026-07-19"
recovery_at: "2026-07-19"
suspected_change: "7229ebfa4 (2026-03-28) fixed the argv-size defect in cmd_fetch_interactions only; the sibling call sites were judged safe against the wrong ceiling model"
brand_survival_threshold: none
status: resolved
triggers:
  - operator-facing data pipeline emitted values no collector produced
  - defect self-reported in 16 consecutive digests without remediation
art_33_triggered: false
art_34_triggered: false
art_33_deadline: "n/a"
---

## Actor key

- `agent` — Claude Code did this autonomously (no operator ack required).
- `agent-with-ack` — Claude Code did this AFTER operator confirmed via menu option.
- `human` — Operator did this directly.

# Incident Overview

The daily community-monitor cron produced a digest whose **Repository Stats** table stated
Stars/Forks/Watchers as `10 / 1 / 10 (stale — last confirmed 2026-06-08)` and claimed to cover
a 41-day period. Neither number came from that run: three of the five GitHub collector
subcommands had been failing, and the LLM authoring the digest filled a *mandatory* table by
carrying values forward from a six-week-old digest and inventing a window to explain them.

This is filed as an incident rather than a plain bug fix for one reason: **the pipeline
detected and reported its own failure 16 times and nothing acted on it.** The engineering
defect is unremarkable; the detection-without-remediation loop is the part worth a
post-mortem.

## Status

resolved

## Symptom

- `github activity` and `github contributors` exited 126 with
  `/usr/bin/jq: Argument list too long`.
- `github repo-stats` failed with a jq `parse error` (exit 5).
- The resulting digest nonetheless presented confident Stars/Forks/Watchers numbers, labelled
  only `(stale)`, under an invented 41-day period.

## Incident Timeline

| Actor | Time (UTC) | Action |
|---|---|---|
| agent | 2026-03-22 | First digest reporting a GitHub collection gap. |
| human | 2026-03-28 | Argv-size defect fixed in `cmd_fetch_interactions` (commit `7229ebfa4`); learning file records the ceiling as `ARG_MAX` (~2 MB). |
| agent | 2026-03-25 → 2026-06-08 | 15 further digests report the same gap. No remediation. |
| agent | 2026-07-19 | Digest reports the gap AND presents stale stats as current under a fabricated period. |
| human | 2026-07-19 | Operator asks for the GitHub data gaps to be fixed (#6695). |
| agent | 2026-07-19 | Root cause bisected to `MAX_ARG_STRLEN`, not `ARG_MAX`. Fix + regression suite + deterministic status sidecar shipped in PR #6709. |

- **Start time (detected):** 2026-03-22
- **End time (recovered):** 2026-07-19
- **Duration (MTTR):** ~119 days from first self-report to fix.

## Participants and Systems Involved

`cron-community-monitor` (Inngest, daily 08:00 UTC) → spawned `claude` →
`plugins/soleur/skills/community/scripts/github-community.sh` → GitHub REST API.
Output surface: `knowledge-base/support/community/<date>-digest.md` + a
`scheduled-community-monitor` GitHub issue.

## Detection (+ MTTD)

- **How detected:** self-reported in the digest body ("GitHub data gaps: … failed again with the
  pre-existing jq argument-list-too-long error"). Not by a monitor — the Sentry cron monitor was
  GREEN throughout, because it verifies that a labelled issue was *updated*, not that the digest
  is *correct*.
- **MTTD:** ~0 for the failure itself (the collector reported it the same day). Effectively
  **infinite for the fabrication** — no mechanism existed to notice that a number in the digest
  had no collector behind it.

## Triggered by

system — a latent argv-size defect crossed its threshold as per-object payload size grew.

## Root-cause hypothesis (triage)

| Hypothesis | Supporting evidence | Disconfirming evidence | Status |
|---|---|---|---|
| Payload exceeded `ARG_MAX` (~2 MB) | Error text is "Argument list too long" | Payloads were 142 KB–448 KB, far under 2 MB | **Rejected** |
| Payload exceeded `MAX_ARG_STRLEN` (131,072 B **per argument**) | Bisected: 131,071 B passes, 131,072 B fails | — | **Confirmed** |
| Item-count truncation (needed pagination) | v1 measured a "-87% undercount" | That figure was measured at `days=41`; production runs `days=1`, where no truncation occurs | **Rejected** |

## Resolution

PR #6709. Payloads spool to files and reach jq through a file descriptor; the stargazer fetch
captures stdout and stderr separately; shape/empty-body guards convert an exit-0 error body into
a named cause. A collector-status JSONL sidecar, read by the handler directly from `spawnCwd`,
makes a collector failure reach Sentry with no LLM in the path.

## Recovery verification

All five subcommands run live against `jikig-ai/soleur` at `days=1`, exit 0 with real data and
clean stderr (`activity` 50 issues / 14 PRs, `contributors` 12 commits, `repo-stats` 11 stars,
`fetch-interactions`, `discussions`). Regression suite: 54 assertions, 8/8 script mutations RED.
Full `TEST_GROUP=scripts` suite 186/186.

---

# Incident Post-Mortem Analysis

## Root Cause(s) — 5-Whys

1. **Why did the digest report wrong stars?** The LLM filled a mandatory Repository Stats table
   from a prior digest because `repo-stats` had failed.
2. **Why did it fill rather than report the failure?** The prompt's GitHub section had no failure
   clause, while a standing instruction said *"If any command in a batch fails, log the error and
   continue."* The vaguer instruction won.
3. **Why did `repo-stats` fail?** The stargazer fetch piped `2>&1` into `jq -s`, so any stderr
   byte poisoned the JSON parse. `activity`/`contributors` failed separately on argv size.
4. **Why did the argv defect survive a fix to the same file four months earlier?** The
   2026-03-28 learning attributed the limit to `ARG_MAX` (~2 MB) and concluded the sibling
   `--argjson` sites were safe *"because stargazers are small."* Against a 2 MB ceiling that is a
   reasonable inference; against the real 131,072 B **per-argument** ceiling, two of them were
   already over it.
5. **Why did 16 self-reports produce no action?** The report's only channel was prose inside a
   human-read digest. Nothing converted "a collector failed" into a signal a monitor could see —
   the Sentry cron monitor verified issue *presence*, which both the honest and the fabricated
   path satisfy identically.

**Final root cause:** a wrong threshold model in an institutional learning caused an incomplete
fix; a detection channel that terminated in prose caused the incomplete fix to persist for four
months despite being reported every time it fired.

## Versions of Components

- **Version(s) that triggered the outage:** `github-community.sh` as of `7229ebfa4` (2026-03-28) onward.
- **Version(s) that restored the service:** PR #6709.

## Impact details

### Services Impacted

Community-monitor digest (internal operator reporting). No customer-facing surface.

### Customer Impact (by role)

- Prospect: none.
- Authenticated app user: none.
- Legal-document signer: none.
- Admin via Access: none.
- Billing customer: none.
- OAuth installation owner: none.
- **Operator (the affected role):** made positioning and prioritization calls against a growth
  table whose Stars/Forks/Watchers values had no run behind them, over a period the digest
  invented.

### Revenue Impact

None directly. Indirect and unquantifiable: traction data used for prioritization was wrong for
~4 months.

### Team Impact

Solo operator. Cost is the ~4 months of decisions taken against fabricated traction numbers, plus
the session required to diagnose and fix.

## Lessons Learned

### Where we got lucky

The fabricated values were *stale-but-plausible* rather than wildly wrong (10 vs the real 11
stars), so no visibly absurd decision was made. Had the repo been growing quickly, a frozen star
count would have understated traction badly and for months.

### What went well

- The collector failed **loudly** at the shell layer every time — `set -o pipefail` caught the
  poisoned parse (exit 5) and E2BIG surfaced as exit 126. The script never silently degraded.
- The digest *did* name the failure in prose on all 16 occasions. The information existed; only
  the routing was missing.

### What went wrong

- **A learning file encoded a wrong threshold model, and that model propagated.** The 2026-03-28
  file said `ARG_MAX`; every subsequent judgment about sibling call sites inherited it. Correcting
  the learning was in scope for the fix precisely because the wrong model *is* the recurrence
  vector.
- **The monitor verified the wrong property.** `resolveOutputAwareOk` checks that a labelled issue
  was updated in the run window — true for a fabricated digest and an honest one alike. A GREEN
  monitor was compatible with four months of wrong data.
- **The self-report had no consumer.** Sixteen digests said "this failed." All sixteen said it in
  prose, in a document that only a human reads, with no mechanical path to an alert.
- **Scope verification was asserted rather than done.** This PR's own plan ran the correct sibling
  grep, transcribed 6 of its hits, silently dropped 2, and wrote *"the scope claim is now
  verified"* — one paragraph after citing the learning whose thesis is *"X is unaffected" is a
  hypothesis, not a fact.* One dropped site (`scripts/compound-promote.sh`) was already broken at
  8.2× the ceiling.

## Action Items & Follow-ups

| Issue | Action | Status |
|---|---|---|
| #6714 | Investigate why the cron committed no digest for 41 days (2026-06-08 → 2026-07-19) — an availability question distinct from collector correctness, and the reason the fabricated window was 41 days. | open |
| #6720 | Fix `scripts/domain-model-drift.sh` argv accumulation (~55% of the per-argument ceiling) — the second site the plan's sweep dropped. | open |
| #6713 | Fix the `/tmp` leak in `workspaces-luks-freeze.test.sh` that filled the tmpfs during this session and produced a misattributed failure in an unrelated suite. | open |
