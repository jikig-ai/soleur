---
title: "Restore scheduled-community-monitor Sentry check-ins (Anthropic credit exhaustion)"
date: 2026-06-29
type: ops-remediation
classification: ops-only-prod-write
lane: cross-domain
brand_survival_threshold: none
status: draft
refs:
  - postmortem: knowledge-base/engineering/operations/post-mortems/anthropic-credit-exhaustion-cron-fleet-silent-failure-postmortem.md
  - runbook: knowledge-base/engineering/operations/runbooks/cloud-scheduled-tasks.md (H10)
  - "#5674 / PR #5680 (observability + credit canary)"
  - "#5692 (pre-exhaustion budget alert — open follow-up)"
---

# Restore `scheduled-community-monitor` Sentry check-ins (Anthropic credit exhaustion)

## Enhancement Summary

**Deepened on:** 2026-06-29
**Gates passed:** 4.6 User-Brand Impact (present, threshold `none`, no sensitive path) · 4.7 Observability (pure-docs Files-to-Edit → schema included for relevance) · 4.8 PAT-shaped (no match) · 4.9 UI-wireframe (no UI surface) · 4.5 Network-Outage Deep-Dive (fired on "firewall"/"timeout" → network path eliminated with artifacts).
**Review agents:** observability-coverage-reviewer, COO (ops-remediation), code-simplicity-reviewer. All three: **ship-quality, no P0/P1.**
**Live-verified citations:** #5680 MERGED (closes #5674), #5327 MERGED, #4468 CLOSED, #5199 CLOSED, #5692 OPEN; post-mortem + existing learning paths resolve.

### Key improvements applied
1. **Scope cut (code-simplicity):** fold the planned learning into the existing `integration-issues/2026-06-29-cron-health-run-log-green-masks-claude-eval-failure.md` (no third near-duplicate doc); trim the H10 addition from 4 sub-steps to the ONE net-new bullet (un-mute/re-enable), cross-linking the existing Restore Procedure instead of restating dry-run/verify/auto-close.
2. **Observability accuracy (obs-reviewer):** community-monitor is **output-aware** (`resolveOutputAwareOk` → `op=scheduled-output-missing`), NOT `classifyEvalFatal` (that is the 4 best-effort crons' path); corrected `failure_modes`. Named the no-recurring-detector residual for the muted/disabled meta-state. Named the `routine_runs` no-SSH read path (Supabase, not psql-over-SSH). Wrapped the discoverability curl in `doppler run`.
3. **Ops discipline (COO):** affirmed `Ref`-not-`Closes`, payment-gated credit top-up, and Sentry un-mute = API-attempt-first (not an a-priori operator punt). Added a `gh issue view 5692` freshness check and a *separate* (non-scope-expanding) ops-advisor follow-up to add an Anthropic prepaid-balance ledger row.

### New considerations discovered
- The operator **likely already topped up credit 2026-06-29 ~11:33Z** (post-mortem) — Phase 0 probes before prescribing any top-up so the plan doesn't direct a redundant billing action; recovery may already be one fire away.
- The only unresolved premise is the alert's "June 13" date (digest-failure onset was June 22); Phase 0 pulls the Sentry check-in timeline to reconcile, and the fix does not depend on it.

## Overview

The Sentry cron monitor `scheduled-community-monitor` (web-platform) has had no successful check-in for multiple days and Sentry warns it will auto-mute/disable. **The root cause is fleet-wide Anthropic operator-API credit exhaustion**, not anything specific to this monitor or a GitHub Actions workflow.

`scheduled-community-monitor` is fired by an **Inngest cron** (`apps/web-platform/server/inngest/functions/cron-community-monitor.ts`, `0 8 * * *` UTC), which spawns `claude --print` to build the daily community digest and file a `[Scheduled] Community Monitor - <date>` GitHub issue. It uses the **output-aware heartbeat** (`resolveOutputAwareOk` in `_cron-shared.ts`): the success contract is the digest issue, not the spawn exit code. When the spawn cannot do work, no digest issue is produced and the handler posts `?status=error` to Sentry → no successful check-in.

Live evidence (pulled this session via `gh`):

- The cron **is firing daily** (an issue appears every day June 13 → June 29).
- June 13–21 issues are **real digests** (successful runs).
- From **June 22 (#5626)** onward, every issue is the handler-level **FALLBACK** "Automated FAILED self-report" (#4960/#4988) with `stdoutTail = "Credit balance is too low"`, `exitCode 1`, `durationMs ~3.4 s` — i.e. `claude --print` is rejected by the Anthropic API on turn 1.
- Sibling claude-eval crons show the same June-22-onward failure (roadmap-review #5627/#5667, content-generator #5645) → **fleet-wide**, confirming credit exhaustion, not a per-cron defect.

This matches the 2026-06-29 post-mortem (`anthropic-credit-exhaustion-cron-fleet-silent-failure-postmortem.md`): the operator prepaid balance reached zero; **operator topped up at ~11:33Z 2026-06-29** and "the fleet self-recovers on the next scheduled fire once credit is restored (no restart)." community-monitor's 2026-06-29 fire was at 08:00:24Z — **before** the top-up — so it still failed; the next scheduled fire (2026-06-30 08:00Z) should succeed if the top-up holds.

**This is an ops-remediation, not a feature.** No new production code is required to resume check-ins — the digest cannot be produced without claude, and claude needs credit. The work is: (0) pull live state, (1) confirm/restore credit, (2) un-mute/re-enable the Sentry monitor if Sentry already disabled it, (3) verify recovery in-session via the manual trigger, (4) close stale fallback issues, (5) ship the documentation (runbook recovery sub-steps + a learning). The observability that makes the next recurrence loud already shipped in #5674/PR #5680 — **do not re-build it here**.

## Premise Validation

Checked the references the task cited by name, per Phase 0.6:

- **"GitHub Actions cron workflow / scheduled task ... pings the Sentry cron check-in URL"** — **STALE.** The GHA `scheduled-community-monitor.yml` workflow was deleted in #4468 (TR9 PR-11) when the cron migrated to the Inngest substrate. The Sentry check-in is now posted by the Inngest handler via `postSentryHeartbeat` (`_cron-shared.ts`). There is no GHA workflow to fix.
- **"failing since June 13, 2026, 8:00 a.m. UTC"** — **PARTIALLY STALE / to-verify.** GitHub issue bodies show June 13–21 produced real digests (successful claude runs); the digest-production failure begins **June 22**. The "June 13" date in the alert is not corroborated by the GitHub evidence and must be reconciled against the authoritative **Sentry check-in timeline** in Phase 0 (it may be an imprecise restatement, a margin artifact from the 30→60 min widening in #5327 on June 15, or a Sentry "incident-window-start" semantic). The fix does **not** depend on resolving this — it leads with the confirmed credit cause.
- **Mechanism vs ADR corpus** — ADR-033 governs "Inngest cron → child-process `claude --print`". This remediation operates fully within ADR-033; it makes no architectural decision and does not diverge from any ADR. No ADR is created or amended.
- **Own capability claims verified:** un-mute is NOT expressible in the `jianyuan/sentry` terraform provider (0.15.0-beta2 has no `is_muted`/`disabled` attribute); the manual-trigger `cron/community-monitor.manual-trigger` IS allowlisted (auto-derived from `EXPECTED_CRON_FUNCTIONS` via `manual-trigger-allowlist.ts`); there is **no Anthropic balance API** ("NO BALANCE ENDPOINT EXISTS", verified live 2026-06-29 in `cron-anthropic-credit-probe.ts`).

## Research Reconciliation — Premise vs. Codebase

| Premise (from alert) | Reality (codebase/live evidence) | Plan response |
| --- | --- | --- |
| GHA cron workflow pings Sentry | Inngest cron `cron-community-monitor.ts`; GHA deleted #4468 | Diagnose/fix the Inngest substrate + credit, not a workflow |
| Failing since June 13 | Real digests June 13–21; credit-fail fallbacks June 22→29; fleet-wide | Lead with credit cause; reconcile "June 13" via Sentry check-in timeline (Phase 0) |
| Monitor-specific failure | Fleet-wide (roadmap-review, content-generator siblings same window) | Credit top-up is the shared fix; un-mute is per-monitor |
| Needs a code fix to resume check-ins | Cannot produce digest without claude+credit; #5674 already shipped observability | Operator credit + monitor un-mute + verify; PR carries docs only |

## User-Brand Impact

- **If this lands broken, the user experiences:** the daily community digest (`knowledge-base/support/community/<date>-digest.md` + `[Scheduled] Community Monitor` issue) stops, and the CMO/operator loses daily visibility into GitHub/Discord/X/LinkedIn/Bluesky/HN activity. Sentry auto-mutes/disables the monitor, so a future genuine outage of this cron pages nowhere.
- **If this leaks, the user's data is exposed via:** N/A — the cron reads public/community-platform aggregate metrics and writes an internal KB digest + a repo issue. No end-user PII, money, or auth surface is touched. The digest prompt already forbids storing raw transcripts and lists only aggregate metrics.
- **Brand-survival threshold:** none — internal observability/marketing tooling; no single-user data/money/workflow exposure. (No sensitive-path code is edited; the diff is documentation + operator/ops actions, so no `threshold: none` sensitive-path scope-out bullet is required for preflight Check 6.)

## Hypotheses (ranked)

1. **H1 — Anthropic operator-API credit exhaustion (CONFIRMED, primary, current).** `stdoutTail = "Credit balance is too low"`, exit 1, ~3.4 s, in every fallback issue June 22→29; fleet-wide. Output-aware heartbeat correctly posts `?status=error` → no successful check-in. **Fix:** ensure credit restored (operator top-up; likely already done 2026-06-29 ~11:33Z per post-mortem) → fleet self-recovers on next fire.
2. **H2 — Sentry monitor already auto-muted/disabled by the multi-day failure (likely, secondary).** The alert explicitly warns of imminent auto-mute/disable. A disabled monitor ignores even a recovery check-in until re-enabled; a muted monitor suppresses alerting. **Fix:** Phase 0 reads monitor state; Phase 2 un-mutes/re-enables if needed.
3. **H3 — "no OK check-in since June 13" discrepancy (to-verify, not fix-blocking).** June 13–21 succeeded, so either the alert date is imprecise, a residue of the 30→60 min margin widening (#5327, June 15), or a Sentry incident-window semantic. **Action:** pull the Sentry check-in timeline in Phase 0 and record the reconciliation; only act if it reveals a real check-in-delivery defect (egress to `SENTRY_INGEST_DOMAIN` was confirmed NOT the cause — post-mortem L63: billing error, not connection drop).
4. **H4 — Inngest cron desync (eliminated).** The cron is firing daily (issues every day) and `cronCommunityMonitor` is registered (`route.ts:125`). The May-27 desync class (`2026-05-27-...missed-checkin.md`) does not apply here.
5. **H5 — Egress firewall blocking claude/GitHub (eliminated).** The June 11–16 egress cascade is resolved; claude reached Anthropic and got a **billing** error (post-mortem L63), and GitHub issue creation succeeded daily.

### Network-Outage Deep-Dive (deepen-plan Phase 4.5 — fired on "firewall"/"timeout")

The plan names egress/firewall and a heartbeat `timeout`, so the L3→L7 layers were checked and the network path is **eliminated** with concrete artifacts (NOT proposing a service-layer fix over an unverified firewall):

- **L3 firewall allow-list / egress:** `api.anthropic.com` and `api.github.com` are in `apps/web-platform/infra/cron-egress-allowlist.txt`; the June 11–16 egress cascade (#5244/#5281/#5413) resolved before the failure window. **Verification artifact:** claude reached Anthropic and received an application-layer **billing** error (`Credit balance is too low`), not a connection drop — post-mortem L63 — and GitHub issue creation **succeeded every day** (the daily fallback/digest issues prove `api.github.com` egress is live).
- **L3 DNS/routing + Sentry ingest:** `SENTRY_INGEST_DOMAIN` resolution in `cron-egress-resolve.sh` is unchanged across June 9–17 and is fail-safe/additive-only; the post-mortem attributes nothing to Sentry-ingest egress. **Residual to confirm in Phase 0** via the Sentry check-in timeline (the only open question is the "June 13" date, H3) — if June 13–21 OK heartbeats are absent in Sentry despite successful digests, re-open the L3 Sentry-ingest path; otherwise it is confirmed non-causal.
- **L7 TLS/proxy + application:** the application-layer cause (Anthropic 400 credit) is confirmed from the captured `stdoutTail`. No TLS/proxy fault.

No firewall/sshd/service-layer change is proposed; per `hr-ssh-diagnosis-verify-firewall` the L3 layers were verified-and-eliminated before the application cause was accepted.

## Implementation Phases

> All steps are no-SSH (`hr-no-ssh-fallback-in-runbooks`) and pull data directly (`hr-no-dashboard-eyeball-pull-data-yourself`). Sentry reads use `SENTRY_IAC_AUTH_TOKEN` (Doppler `soleur/prd_terraform`, read-only) via the runbook's documented `GET /api/0/organizations/{org}/monitors/` form.

### Phase 0 — Diagnose live state (read-only)
1. **Credit state:** read the hourly canary monitor `scheduled-anthropic-credit-probe` state (Sentry API GET) AND/OR fire a direct 1-token Anthropic probe with the operator `ANTHROPIC_API_KEY` (the canary's own method) — confirm HTTP 200 (credit restored) vs 400 `credit balance is too low`. Do NOT re-fire a heavy cron to test credit (per `knowledge-base/project/learnings/integration-issues/2026-06-29-cron-health-run-log-green-masks-claude-eval-failure.md`: probe the dependency directly).
2. **Monitor state + timeline:** `GET /api/0/organizations/$SENTRY_ORG/monitors/` filtered to `scheduled-community-monitor`; capture `status`, `isMuted`/muted state, and recent check-in statuses/timestamps. Record the actual last-OK check-in date and reconcile the "since June 13" premise (H3).
3. **Latest fire:** confirm the most recent fallback (`#5666`, 2026-06-29) `stdoutTail` (already = "Credit balance is too low") and the daily fallback cadence.
4. **Output:** a one-paragraph diagnosis note (credit restored? monitor muted/disabled? last-OK date) that branches Phases 1–2.

### Phase 1 — Ensure Anthropic credit restored
- If Phase 0 shows credit **already restored** (HTTP 200 / canary green): record "credit restored at <ts> per post-mortem; no action" and proceed.
- If still exhausted: **operator tops up the prepaid balance at `console.anthropic.com → Billing`** (post-merge operator step; payment-gated — see Automation note). Allow ~2 min billing propagation; re-probe (Phase 0.1) to confirm 200 before relying on it. The fleet self-recovers on the next scheduled fire — no restart.

### Phase 2 — Re-enable / un-mute the Sentry monitor (if needed)
- If Phase 0 shows `scheduled-community-monitor` muted or disabled by Sentry: attempt to un-mute/re-enable via the **Sentry API** (`PUT`/mute endpoint) with `SENTRY_IAC_AUTH_TOKEN` first (automation-first). If the API write is genuinely unavailable, fall back to the operator Sentry dashboard with a `playwright-attempt:` evidence line.
- Note the sibling claude-eval monitors (roadmap-review, content-generator, etc.) may be in the same state; record whether they auto-recovered on their first post-top-up fire (a single recovery check-in clears `recovery_threshold = 1`). Keep this PR scoped to community-monitor; if siblings need manual un-mute, note them for the operator (do not silently leave dark).
- The `jianyuan/sentry` provider exposes no mute attribute, so this is NOT a terraform change.

### Phase 3 — Verify recovery in-session (don't wait for the 08:00 fire)
- Once Phase 0/1 confirm credit is restored, fire `cron/community-monitor.manual-trigger` via `/soleur:trigger-cron` (already allowlisted — auto-derived from `EXPECTED_CRON_FUNCTIONS`). This avoids waiting for the 2026-06-30 08:00Z natural fire.
- Verify ALL of: (a) a **real digest** `[Scheduled] Community Monitor - <date>` issue body (NOT the "FAILED self-report" fallback shape); (b) the Sentry monitor receives a `?status=ok` check-in (re-GET the monitor); (c) the `routine_runs` row is `succeeded` (not just `completed`) — read via Supabase (per `cloud-scheduled-tasks.md` H10, line 531), NOT `psql`-over-SSH.
- Honor the prompt's 24h DEDUP RULE: a same-day manual trigger comments on the existing issue rather than creating a duplicate — verify the success signal accordingly (digest content in the comment/issue + green check-in).

### Phase 4 — Close stale fallback issues
- Close the OPEN fallback `[Scheduled] Community Monitor` issues from the failure window via `gh issue close` (automatable): currently #5586, #5587, #5592, #5593, #5596, #5597, #5626, #5643, #5650, #5655, #5657, #5662, #5664, #5666 (re-enumerate at /work time — the set grows by one per day until recovery). Add a one-line comment referencing this remediation. Confirm whether the `cron-cloud-task-heartbeat` watchdog already auto-closes them on recovery; if so, only close the residue it does not.

### Phase 5 — Documentation deliverables (the mergeable PR content)

> **Scope-minimal (code-simplicity review):** the existing `integration-issues/2026-06-29-cron-health-run-log-green-masks-claude-eval-failure.md` learning + the credit-exhaustion post-mortem already document this incident's root cause, the liveness-vs-success masking, "RED is correct," the direct-probe technique, and that #5674/PR #5680 shipped the fix. Do NOT create a third near-duplicate learning, and do NOT restate in H10 the steps the runbook's "Restore Procedure" (`cloud-scheduled-tasks.md:553`) already covers (manual dry-run, verify success signals, watchdog auto-close). Only the genuinely net-new fact ships.

- **Runbook H10 — ONE net-new bullet** (`cloud-scheduled-tasks.md`, in/after the H10 section at line 507): after a **prolonged** (multi-day) credit outage, Sentry may have **auto-muted/disabled** the monitor; **credit-restore alone does not re-enable it** — un-mute/re-enable via the Sentry REST API (`PUT` monitor status/mute) with `SENTRY_IAC_AUTH_TOKEN`, dashboard fallback only on a confirmed API-write failure. Cross-link the existing "Restore Procedure" (`:553`) for the dry-run/verify/auto-close steps rather than restating them.
- **Learning — fold, don't fork:** append a 3–4 line addendum to the existing `knowledge-base/project/learnings/integration-issues/2026-06-29-cron-health-run-log-green-masks-claude-eval-failure.md` capturing the two net-new nuggets: (a) the **alert date ≠ onset** reconciliation (the Sentry alert said "June 13" but digest-failure onset was June 22; June 13–21 produced real digests), and (b) **Sentry can leave the monitor muted/disabled after credit returns** — per-monitor un-mute is a distinct recovery step. No new file.
- **Tracking/issue linkage:** PR body uses `Ref #<tracking-issue>` and `Ref` the post-mortem — **NOT `Closes`** (ops-remediation: the real recovery is the post-merge operator/verify step; `Closes` would auto-close before remediation completes). File/identify the tracking issue at /work time if none exists. Before citing **#5692** (pre-exhaustion budget alert) as the durable follow-up, `gh issue view 5692` to confirm it is still OPEN (verified OPEN this session).
- **Out of scope (separate follow-up, do NOT expand this PR):** `expenses.md` has no dedicated row for the operator **Anthropic prepaid PAYG balance** that feeds the cron fleet (it tracks the Max seats + the metered CI key). Adding/annotating that ledger row with the monthly cron-fleet burn + #5692's alert as the control is a low-priority ops-advisor task — `wg-record-recurring-vendor-expense-before-ready` does NOT fire here (docs-only diff, no new vendor; a top-up is replenishment of an existing balance). Flag it; don't build it here.

## Files to Edit
- `knowledge-base/engineering/operations/runbooks/cloud-scheduled-tasks.md` — ONE net-new H10 bullet (un-mute/re-enable after a prolonged outage; cross-link Restore Procedure `:553`).
- `knowledge-base/project/learnings/integration-issues/2026-06-29-cron-health-run-log-green-masks-claude-eval-failure.md` — fold a 3–4 line addendum (alert-date≠onset; per-monitor un-mute after credit returns). **No new learning file** (code-simplicity review: a third per-incident doc would be ~80% duplicative of this file + the post-mortem).

## Files to Create
- None.

> No production code (`apps/web-platform/**`) is edited. The observability layer (credit canary + classify-fatal heartbeat) already shipped in #5674/PR #5680; re-implementing it here is out of scope and would duplicate merged work.

## Open Code-Review Overlap

None. `gh issue list --label code-review --state open` returned no open scope-out referencing `cloud-scheduled-tasks.md`, `cron-community-monitor.ts`, `cron-monitors.tf`, or `trigger-cron` (checked this session).

## Acceptance Criteria

### Pre-merge (PR)
- [ ] **AC1** — Premise corrected in the PR/learning: monitor is Inngest-fired (not GHA), failure onset June 22 (not June 13), cause = fleet-wide Anthropic credit exhaustion. Cites the fallback-issue `stdoutTail` evidence.
- [ ] **AC2** — Phase 0 diagnosis note recorded: credit state (probe result), monitor muted/disabled state, and the Sentry-confirmed last-OK check-in date with the "June 13" reconciliation.
- [ ] **AC3** — Runbook `cloud-scheduled-tasks.md` H10 gains the ONE net-new un-mute/re-enable bullet (cross-linking Restore Procedure `:553`, not restating it); `grep -c "un-mute\|re-enable" cloud-scheduled-tasks.md ≥ 1` in the H10 region.
- [ ] **AC4** — Addendum appended to the existing `integration-issues/2026-06-29-cron-health-run-log-green-masks-claude-eval-failure.md` (no new learning file); every `knowledge-base/` path the plan AND the addendum cite resolves (`grep -oE 'knowledge-base/[A-Za-z0-9/_.-]+\.md' <files> | xargs -I{} test -f {}`).
- [ ] **AC5** — PR body uses `Ref #<n>` (NOT `Closes`) for the tracking issue and references the post-mortem.

### Post-merge (operator / verification)
- [ ] **AC6** — Anthropic operator credit confirmed restored (1-token probe → HTTP 200, or canary `scheduled-anthropic-credit-probe` green).
- [ ] **AC7** — `scheduled-community-monitor` un-muted/re-enabled in Sentry if it was auto-muted/disabled (API write attempted first; dashboard fallback only with `playwright-attempt:` evidence).
- [ ] **AC8** — Manual trigger (or the next natural 08:00Z fire) produces a **real digest** (not the FAILED fallback) AND a `?status=ok` Sentry check-in; the monitor shows OK and is no longer flagged for auto-disable.
- [ ] **AC9** — Stale OPEN fallback `[Scheduled] Community Monitor` issues from the outage window are closed (or confirmed auto-closed by the watchdog).
- [ ] **AC10** — Tracking issue closed (`gh issue close`) only AFTER AC6–AC8 verify green.

## Domain Review

**Domains relevant:** Operations (primary — ops-remediation), Marketing (advisory — community-manager/CMO owns this cron per `routine-metadata.ts`: domain Marketing, ownerRole CMO), Engineering (advisory — observability/Inngest substrate, CTO).

### Operations
**Status:** reviewed (assessment) — Core remediation is operator credit + Sentry monitor state. Both are operator/ops prod-write actions; sequenced post-merge with `Ref` not `Closes`. Automation-feasibility gated (credit = payment-gated operator action; un-mute = Sentry API attempt → dashboard fallback).

### Marketing
**Status:** reviewed (assessment) — Impact is the daily community digest going dark; recovery restores it. No brand voice/content change. No copywriter needed (no user-facing copy).

### Engineering
**Status:** reviewed (assessment) — The output-aware heartbeat behaved correctly (RED was right). #5674 already shipped the credit canary + classify-fatal. No production-code change; do not duplicate #5674/#5692.

### Product/UX Gate
NONE — no UI surface. No file under `components/**/*.tsx`, `app/**/page.tsx`, or `app/**/layout.tsx`; the mechanical UI-surface override does not fire. Skip.

## Infrastructure (IaC)

No new infrastructure (no server, secret, vendor account, DNS, or persistent process). The two prod-write actions are **state operations on existing resources**: the Anthropic prepaid balance (vendor billing, no API) and the Sentry monitor mute/disable state (`jianyuan/sentry` 0.15.0-beta2 exposes no `is_muted` attribute → not a terraform change). No `*.tf` edit; `apply-web-platform-infra.yml` / `apply-sentry-infra.yml` are NOT triggered by this PR.

**Automation feasibility:**
- **Credit top-up** — `Automation: not feasible because` the Anthropic console Billing top-up is a payment-card / authenticated-billing action with no balance/top-up API (verified live 2026-06-29: "NO BALANCE ENDPOINT EXISTS"). `automation-status: payment-gated operator action`; if a Playwright attempt is run it will reach the Anthropic billing/payment gate. Likely already completed 2026-06-29 ~11:33Z (post-mortem) — Phase 0 verifies before prescribing.
- **Sentry un-mute** — `automation-status: UNVERIFIED — /work MUST attempt the Sentry API PUT/mute endpoint with SENTRY_IAC_AUTH_TOKEN before any operator/dashboard handoff.` Only on a confirmed API-write failure does it become an operator dashboard step (with `playwright-attempt:` evidence).
- **Stale-issue close, manual-trigger verify, monitor/canary reads** — fully automatable (`gh issue close`, `/soleur:trigger-cron`, Sentry API GET); baked into Phases 3–4, not punted.

## Observability

This change adds no new code paths; the relevant signals already exist (#5674/PR #5680). Recording them for completeness:

```yaml
liveness_signal:    scheduled-community-monitor Sentry cron monitor / daily 0 8 * * * UTC / Sentry cron alerts → operator email / apps/web-platform/infra/sentry/cron-monitors.tf
error_reporting:    resolveOutputAwareOk → postSentryHeartbeat(?status=error) + reportSilentFallback(op=scheduled-output-missing) to Sentry / fail_loud: yes (output-aware: no digest issue ⇒ RED)
failure_modes:
  - {mode: "Anthropic credit exhausted", detection: "(a) scheduled-anthropic-credit-probe canary (hourly) op=anthropic-credit-exhausted; (b) THIS monitor is output-aware — resolveOutputAwareOk finds no digest issue → op=scheduled-output-missing → heartbeat RED (NOT classifyEvalFatal, which is the 4 best-effort crons' path)", alert_route: "canary RED + this monitor RED"}
  - {mode: "operator key invalid/revoked", detection: "canary op=anthropic-key-invalid (cron-anthropic-credit-probe.ts)", alert_route: "Sentry monitor RED"}
  - {mode: "cron stops firing (desync)", detection: "scheduled-inngest-cron-watchdog missed check-in + function-registry-count.test.ts parity", alert_route: "Sentry missed-checkin"}
  - {mode: "monitor muted/disabled by Sentry after prolonged outage", detection: "GET /api/0/organizations/{org}/monitors/ status field (one-time Phase 0 read)", alert_route: "ACCEPTED RESIDUAL — no recurring detector for the meta-state of THIS monitor being disabled; a future auto-disable pages nowhere until an operator looks. Backstop: scheduled-inngest-cron-watchdog still proves the scheduler is alive. Pre-exhaustion prevention tracked in #5692."}
logs:               claude-eval stdout/stderr tail (bounded, redacted) → Sentry extra (formatTailForSentry, _cron-shared.ts:739) + pino→Better Stack via Vector / retention per Better Stack plan
discoverability_test:
  command: 'doppler run -p soleur -c prd_terraform -- bash -c '"'"'curl -s -H "Authorization: Bearer $SENTRY_IAC_AUTH_TOKEN" "https://sentry.io/api/0/organizations/$SENTRY_ORG/monitors/?per_page=100" | jq ".[] | select(.slug==\"scheduled-community-monitor\")"'"'"''
  expected_output: "monitor JSON with a recent ok check-in after recovery; status not muted/disabled (requires SENTRY_ORG + SENTRY_IAC_AUTH_TOKEN, supplied by the doppler run wrapper)"
```

## Architecture Decision (ADR/C4)

None. This remediation operates entirely within ADR-033 (Inngest cron → `claude --print` child process) and makes no architectural decision. C4: checked the cron→claude→`api.anthropic.com` external-system edge and the GitHub-issue write edge — both already modeled by the existing cron substrate views; the Anthropic billing relationship is operator-side and introduces no new external actor/system/data-store. No `.c4` edit.

## Test Scenarios

- Manual-trigger fire after credit restore → real digest issue + `?status=ok` check-in + `routine_runs.succeeded` (Phase 3 / AC8).
- Sentry monitor GET shows un-muted/enabled + recovery OK (AC7/AC8).
- Runbook + learning path-resolution greps pass (AC3/AC4).
- (Regression already covered) `function-registry-count.test.ts` + `sentry-monitor-iac-parity.test.ts` keep slug↔function↔monitor parity for `scheduled-community-monitor` — no change expected, run to confirm no drift.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. (Section is filled above; threshold = none.)
- **Do not re-build #5674.** The credit canary, classify-fatal heartbeat, and scrubbed-reason capture already merged (PR #5680, 2026-06-29). This plan ships only docs + ops actions.
- **Verify credit before prescribing a top-up.** The operator likely topped up 2026-06-29 ~11:33Z; Phase 0 probes before any top-up step so the plan doesn't direct a redundant billing action.
- **`Ref`, not `Closes`.** Ops-remediation: the recovery is the post-merge operator/verify step; `Closes #N` would auto-close at merge before the cron is verified green.
- **Don't widen the egress allowlist.** Egress to `api.anthropic.com` was never the cause (post-mortem L63 — billing error, not connection drop). Adding egress entries here would be cargo-culting.
- **Same-day manual-trigger dedup:** the prompt's 24h DEDUP RULE makes a same-day re-fire comment on the existing issue instead of creating one — verify recovery by the green check-in + digest content, not by a brand-new issue number.

## Risks & Mitigations

- **Risk:** credit re-exhausts before pre-exhaustion alerting (#5692) lands → silent fleet outage recurs. **Mitigation:** out of scope here; #5674 canary now pages AT exhaustion within one hour; note #5692 as the durable follow-up.
- **Risk:** Sentry already auto-disabled the monitor and the API can't re-enable it programmatically → operator dashboard step. **Mitigation:** Phase 2 attempts the API first; dashboard fallback is a bounded, evidenced operator step.
- **Risk:** "June 13" hides a second, real check-in-delivery defect. **Mitigation:** Phase 0 pulls the authoritative Sentry timeline; if a real defect surfaces (e.g., margin/egress to Sentry ingest), scope it as a follow-up rather than expanding this remediation.
