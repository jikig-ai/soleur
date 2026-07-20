---
title: "cron-community-monitor posted GREEN for 41 days while committing no digest"
date: 2026-07-20
incident_pr: 6726
incident_window: "2026-06-09 → 2026-07-19 (41 days; the final 6 days GREEN-with-no-artifact)"
recovery_at: "2026-07-20 (fix merged; first corrected fire expected 2026-07-21 08:00 UTC)"
suspected_change: "No single change. A latent design gap: the check-in asserted a labelled GitHub ISSUE, never the committed digest."
brand_survival_threshold: aggregate pattern
status: resolved
triggers:
  - "operator noticed the community digest directory had stopped growing"
art_33_triggered: false
art_34_triggered: false
art_33_deadline: "n/a"
---

## Actor key

- `agent` — Claude Code did this autonomously (no operator ack required).
- `agent-with-ack` — Claude Code did this AFTER operator confirmed via menu option per `hr-menu-option-ack-not-prod-write-auth`.
- `human` — Operator did this directly.

# Incident Overview

`cron-community-monitor` produced **no committed community digest for 41 consecutive days**
(2026-06-09 → 2026-07-19). For the final six of those days it posted a **GREEN Sentry check-in
every morning** while committing nothing at all. The monitor was not broken — it faithfully
reported the thing it was asked to report, and it was asked to report the wrong thing.

This was discovered **incidentally**, while working the #6713/#6720 tooling fixes, not by any
alert. That is the core finding: no monitoring surface could have caught it, because the
monitoring surface itself was the defect.

## Status

resolved — the fix merged in PR #6726. Residual work is tracked in Action Items below.

## Symptom

The newest committed digest was `2026-06-08-digest.md`. Every subsequent day filed a
`[Scheduled] Community Monitor - <date>` GitHub issue at ~08:0x UTC, and the Sentry cron
monitor `scheduled-community-monitor` reported healthy on 07-14 → 07-19 — with zero
`docs: daily community digest` PRs and zero `ci/community-digest-*` branches in that window.

## Incident Timeline

- **Start time (detected):** 2026-07-19 (operator noticed the digest directory had stopped growing)
- **Actual start:** 2026-06-09 (first day with no committed digest)
- **2026-06-09 → 06-12:** `cron-community-monitor` sat in `TIER2_DEFERRED_CRONS` — the defer path
  posts a GREEN check-in and skips the spawn entirely. 4 days, no issues filed at all.
- **2026-06-13 → 07-13:** cron fired and filed issues; Sentry recorded `scheduled-output-missing` ×17
  and `Cron failure` ×48. Genuinely RED runs, correctly reported.
- **2026-07-14 → 07-19:** issues filed, **no Sentry cron failure at all**, no digest committed.
  This is the GREEN-with-no-artifact window.
- **2026-07-19:** investigation opened as #6714.
- **2026-07-20:** fix merged (PR #6726).

## Participants and Systems Involved

`agent` — investigation, fix, and this PIR. Systems: Inngest (cron substrate), GitHub
(issues + commits), Sentry (cron monitor), Better Stack (log sink).

## Detection (+ MTTD)

**MTTD ≈ 41 days**, and detection was incidental — a human noticing an absent artifact.
No automated surface could have detected it: the Sentry monitor was the surface, and it was
reporting GREEN by design.

## Triggered by

No triggering change. A latent design gap present since the cron was migrated: the check-in
colour was derived from `resolveOutputAwareOk` ("did a labelled issue land"), which is a correct
**persistence gate** but was being used as a **liveness signal**.

## Root-cause hypothesis (triage)

Twelve hypotheses (H1–H12) were enumerated and each decided against evidence. H1/H3/H5/H6/H7/H8
CONFIRMED; H2/H4/H10/H11/H12 REFUTED. **H9 — which internal branch swallowed persistence on the
GREEN days — is recorded UNKNOWN, not resolved.** The deciding datum lives only in Inngest
step-level run history, which ADR-030 binds to `127.0.0.1:8288` and is therefore unreachable
without SSH. The fix does not depend on H9; H6 establishes the defect from source.

## Resolution

PR #6726. The check-in is now gated on the **committed artifact** rather than issue presence
(`livenessOk`, fail-closed), the persistence result is consumed rather than discarded, the
date-dedup requires the digest committed on the default branch, and six structured WARN-level
markers make every GREEN-with-no-artifact path enumerable in Better Stack without SSH.
Design recorded in ADR-126.

## Recovery verification

The next scheduled fire (2026-07-21 08:00 UTC) either commits a digest and posts GREEN, or
posts RED with a `SOLEUR_CRON_DIGEST_LIVENESS` marker naming the failing arm. Both outcomes are
now observable — which was not true before this fix. Query:
`doppler run -p soleur -c prd_terraform -- bash scripts/betterstack-query.sh --grep SOLEUR_CRON_DIGEST_LIVENESS --since 48h`

# Incident Post-Mortem Analysis

## Root Cause(s) — 5-Whys

1. **Why did the operator lose the digest?** No digest was committed for 41 days.
2. **Why did nobody notice?** The Sentry cron monitor reported GREEN.
3. **Why was it GREEN?** Its check-in asserted a labelled GitHub *issue* existed, not that the
   digest was *committed*.
4. **Why did asserting the issue seem sufficient?** The issue and the digest were assumed to be
   produced together by the same agent run — an assumption never encoded or tested.
5. **Why was the assumption never caught?** `safeCommitAndPr`'s return value was **discarded** at
   the call site, so `"failed"` and `"no-changes"` were structurally invisible; and no
   `SOLEUR_*` marker existed on the persistence path, so no operator-reachable surface recorded
   which branch was taken.

**Root cause:** a monitor that asserted a *proxy* for the deliverable rather than the deliverable,
combined with a discarded return value that made the proxy's divergence unobservable.

## Versions of Components

`cron-community-monitor.ts` / `_cron-safe-commit.ts` / `_cron-shared.ts` at `origin/main` prior to
PR #6726; Inngest durable-trigger substrate per ADR-030; Sentry cron monitor
`scheduled-community-monitor` (`cron-monitors.tf`, unchanged by the fix).

## Impact details

**Operator-facing only.** The lost artifact is an internal community digest consumed by the
operator. No user data, credentials, or customer-facing surface was involved, and nothing was
exposed — the failure was an *absence* of output, not a leak. `art_33_triggered` and
`art_34_triggered` are both `false`: there was no personal-data breach, so neither the 72-hour
supervisory-authority notification nor the data-subject communication duty is engaged.

Cost: 41 days of missing community intelligence, plus the investigation itself.

## Lessons Learned

**What went well.** Once investigated, the evidence table decided 11 of 12 hypotheses from
source and git history alone. H9 was left honestly UNKNOWN rather than given a manufactured
verdict — and the fix was designed to convert it into a measured datum on the next fire.

**What went badly.** The first fix *did not close the bug class*: `livenessOk` was initialised
`true` and falsified only on an observed negative, so a throw anywhere between `verify-output`
and the persistence gate still produced a terminal GREEN with nothing committed, on the first
attempt. It was caught in multi-agent review, not by the author. The defending comment cited a
retry hazard that **already existed on `main`** — a check that would have taken one grep.

**Where we got lucky.** The operator happened to notice an absent file. There was no other
detection path, and the same class is still live across the cron cohort (see #6737).

## Action Items & Follow-ups

| Issue | Action | Status |
|---|---|---|
| #6737 | Audit every cron whose deliverable is a committed file — `resolveOutputAwareOk` is shared, so the same blind spot exists cohort-wide (per ADR-126) | open |
| #6739 | Close the residual predicate asymmetry: `livenessOk` asserts "in a commit on a PR branch" while the dedup gate asserts "on `main`"; and a same-day re-trigger against an unmerged PR re-spawns | open |
| #6738 | Raw claude-eval child stderr ships to Better Stack at ERROR scrubbed only by exact-match `redactToken` — discovered while auditing this incident's log surface | open |
