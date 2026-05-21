---
title: "TR9 PR-3 — migrate scheduled-oauth-probe + scheduled-github-app-drift-guard to Inngest cron substrate"
date: 2026-05-21
issue: 4211
parent_umbrella: 3948
precedents: [3985, 4062]
prior_plan: knowledge-base/project/plans/2026-05-21-fix-scheduled-oauth-probe-recurrence-plan.md
prior_immediate_relief: 4207
brand_survival_threshold: single-user incident
lane: cross-domain
mode: focused-refresh
---

# TR9 PR-3 — OAuth-probe + GitHub-App drift-guard → Inngest cron

This is a focused-refresh brainstorm over a pre-existing deepened plan (`knowledge-base/project/plans/2026-05-21-fix-scheduled-oauth-probe-recurrence-plan.md`, status `superseded` by the immediate-relief PR #4207). The plan is the authoritative design; this brainstorm carries it forward unchanged in body and adds three scope deltas mandated by the elevated brand-survival threshold.

## What We're Building

Migrate both hourly GHA-scheduled probes to the self-hosted Inngest cron substrate (Hetzner VM), matching TR9 PR-1 (#3985 `cron-daily-triage`) and PR-2 (#4062 `cron-follow-through-monitor`) precedent. Closes the May 21 `scheduled-oauth-probe` recurring missed-checkin Sentry alert (`a94c4ec23f654101a7fc4491b16a560c`) at the substrate level rather than via further `checkin_margin_minutes` patches.

Concrete deliverables (from the plan, unchanged):

1. `apps/web-platform/server/inngest/functions/cron-oauth-probe.ts` — TS port of the 540-line bash probe (8 failure modes, 5 probe helpers, dig CNAME via `dns.promises.resolveCname`, in-process Octokit issue-filing, Resend HTTP for ops email, Sentry heartbeat per `cron-daily-triage.ts:329-371` shape).
2. `apps/web-platform/server/inngest/functions/cron-github-app-drift-guard.ts` — same shape, drift-guard probe surface.
3. `apps/web-platform/server/inngest/functions/oauth-probe-sentinels.ts` — shared sentinel-string module (`redirect_uri is not associated`, `Application suspended`, `authenticity_token` regex) consumed by BOTH the new function and `apps/web-platform/test/oauth-probe-contract.test.ts`.
4. Register both in `apps/web-platform/app/api/inngest/route.ts:37`.
5. Tighten both Sentry monitors back: `checkin_margin_minutes = 30`, `failure_issue_threshold = 1` (currently 360 / 2 from immediate-relief PR #4207).
6. Delete both `.github/workflows/scheduled-{oauth-probe,github-app-drift-guard}.yml` in the same commit (TR9 I-13 hygiene precedent).
7. Runbook updates (`oauth-probe-failure.md`, `github-app-drift.md`) for the new operator surfaces.

## User-Brand Impact

**Artifact:** the oauth-probe + drift-guard detection signal.
**Vector:** silent post-migration probe failure — function registered but never fires, or fires but no longer detects the canonical failure-body sentinels.
**Threshold:** **single-user incident**. The probe IS the canary that detects OAuth + GitHub-App auth regressions for founders. A botched migration could disable detection without operator visibility; the founder discovers the outage when their agent-runtime breaks, not when the canary squawks. The original plan declared threshold `none` on a "no auth flow / no PII / no schema" rationale; that misread the detection surface as out-of-scope. The probe's *output* is what gates incident response — its silent failure mode IS a brand-impact vector.

## Why This Approach

The structural fix (Inngest substrate) is the only durable answer to the GHA cron-substrate cadence ceiling — documented in the plan: 49-fire `gh run list` distribution over the 2026-05-18..21 window showed GHA hourly cron degraded to ~150-min median / 293-min max gaps under runner-pool load, with the sister drift-guard hitting 307-min max in the same window. Further `checkin_margin_minutes` bumps degrade the monitors to "useless if the probe goes truly dark for under 5 hours" while real auth breaks remain undetectable.

Inngest fires deterministically (≤2-min jitter) — verified today (2026-05-21) by both migrated siblings' Sentry checkins:
- `scheduled-daily-triage`: expected 04:00 UTC, checkin 04:00:19Z (+19s)
- `scheduled-follow-through`: expected 09:00 UTC, checkin 09:00:08Z (+8s)

Both well inside the tightened 30-min margin. Substrate is proven; PR-3 inherits the precedent verbatim.

## Key Decisions

| Decision | Rationale |
|---|---|
| **Single PR for both probes** | Same substrate change, same cutover sequence, shared `sentry-heartbeat` composite action; splitting would double review surface for zero risk reduction. Plan-author lens confirmed. |
| **Within-PR sentinel-module extraction** | Test file and Inngest function become the only two consumers in the same commit; precursor PR would orphan the module. CTO verified `oauth-probe-contract.test.ts` has no YAML import — duplicate string literals collapse to one source of truth in this PR. |
| **Same-commit GHA workflow deletion** | Dual-substrate firing would post double check-ins to the same Sentry monitor slug, and the slug-keyed dedup would let either substrate mask the other's failure. Plan AC9 rationale stands. |
| **Reuse existing `sentry-heartbeat` composite action** | The `.github/actions/sentry-heartbeat/action.yml` composite already exists with 5 inputs and a divergent status branch for drift-guard. Do NOT inline a 9th copy. (Source: 2026-05-18 composite-action-extraction-inline learning.) |
| **Brand-survival threshold elevated to `single-user incident`** | Triad-confirmed override of plan's `none` declaration. CPO + CTO both flagged the detection-surface gap; CLO confirmed no Article-30 / GDPR-gate trigger remains. Plan's `requires_cpo_signoff: false` MUST flip to `true` at /work-time. |

## Scope Additions (under elevated threshold)

Three named scope deltas added to the plan's 25 ACs:

### AC26 — Post-merge detection contract (CPO)

Post-merge, fire `inngest send cron/oauth-probe.manual-trigger` (and the drift-guard equivalent) with a `data.overrideHost` pointing at a fixture URL serving each of the 8 canonical failure-body sentinels. Assert each maps to the correct `failureMode` AND a `?status=error` heartbeat lands in Sentry's checkins API within 90s per mode. If the handler doesn't support a host-override input, the AC narrows to "one synthetic failure mode via a feature-flagged probe target." Closes the gap that AC22/AC23 prove the probe ticks but not that it still squawks.

### AC27 — Pre-deletion staging gate (CTO)

Stage the `.github/workflows/scheduled-{oauth-probe,github-app-drift-guard}.yml` deletion ONLY after `inngest send cron/oauth-probe.manual-trigger` lands successfully in staging Inngest (Phase 4 dev/staging step in plan AC4). Collapses the up-to-90-min cutover-blindness window if `apps/web-platform/app/api/inngest/route.ts:37` silently fails to discover the new function (route.ts typo, dead-code elimination, registration drift).

### AC28 — Substrate-vs-probe disambiguation (CTO)

The `[ci/auth-broken]` issue template (filed in-process by `cron-oauth-probe.ts` on probe failure) MUST include the last Better Stack heartbeat timestamp inline as a substrate-liveness pre-flight. Source: pull from `https://uptime.betterstack.com/api/v2/heartbeats` for the `inngest-heartbeat` monitor at issue-file time. Operator opening the issue sees substrate-vs-probe disambiguation without dashboard hopping. Closes the #4116 silent-substrate-fail residual risk — under elevated threshold, the inherited "if Hetzner goes dark, multiple monitors fire" reasoning is too thin (daily-triage / follow-through cadences are too coarse for a 60-min auth canary).

## Sanity Gates (from learnings, pre-merge)

1. **#4116 six-question pre-merge self-check:** PUBLIC_PATHS for `/api/inngest`, signing-key prefix, `User=` vs chown, sandbox ReadWritePaths, env source-of-truth — run before declaring the function live. (Source: `2026-05-19-inngest-substrate-five-bug-cascade.md`.)
2. **Verify infra-validation pathspec actually matched:** PRs #3985/#4002/#4003 had `validate: SKIPPED` due to `git diff -- 'apps/*/infra/'` zero-matching. Confirm the workflow ran on this PR's diff before relying on green status. (Source: `2026-05-18-infra-validation-pathspec-silent-zero-match.md`.)
3. **Unpause Better Stack heartbeat before claiming GREEN:** paused-at-apply will hide failures. (Source: `2026-05-20-inngest-heartbeat-doppler-env-injection.md`.)

## Open Questions

None. The plan is fully specified, deepened against live state, and the triad converged on three additive scope deltas. /work-time executes the plan with the additions.

## Domain Assessments

**Assessed:** Marketing, Engineering, Operations, Product, Legal, Sales, Finance, Support (triad fired: CPO, CTO, CLO per `USER_BRAND_CRITICAL=true`).

### Product (CPO)

**Summary:** Threshold elevation holds narrowly — the probe IS the signal-of-last-resort for founder-facing auth breaks; AC22/AC23 prove plumbing but not detection contract. Verdict: **named scope addition** — AC26 (post-merge synthetic-failure injection).

### Engineering (CTO)

**Summary:** Cutover risk is real but shadow-fire overlap would be worse (dual-substrate dedup masking). Sentinel-module extraction is correctly within-PR (no consumer-drift window). Under-weighted risk: substrate-down detection inheritance from sibling crons is materially weaker at 60-min cadence than at daily cadence. Verdicts: **AC27 (pre-deletion staging gate)** + **AC28 (Better Stack disambiguation in issue body)**.

### Legal (CLO)

**Summary:** GDPR-gate correctly non-triggered — substrate change is data-flow-neutral; OAuth endpoints + GitHub-App credentials are public-tier identifiers, not personal data. Article-30 register PA 13 already inventories self-hosted Inngest (PR-F #3244). No DPA addendum, no LIA, no compliance-posture row. **Carry-forward only.**

## Capability Gaps

None reported. All affected domains covered by existing skills (`soleur:work`, `soleur:ship`, `soleur:postmerge`).

---

## Post-Brainstorm Update — 2026-05-21 (plan-review applied)

Three plan-review reviewers (DHH + Kieran + Code Simplicity) spawned against the plan derived from this brainstorm produced convergent pushback. Operator chose **Full apply: split + cut AC27/28**.

**Scope revisions to the brainstorm-blessed scope:**

- **Bundled scope → single-probe scope.** Drift-guard deferred to TR9 PR-4 follow-up. Brainstorm's bundling rationale (shared substrate, shared composite, shared cron-monitors.tf cleanup) was infrastructure-symmetry; plan-review surfaced that risk-symmetry under elevated threshold favors split. Drift-guard is qualitatively heavier (724 LoC vs 540, 12+ failure modes vs 8, JWT minting, manifest-diff shell-out).
- **AC27 (pre-deletion local `inngest dev` gate) cut.** Local dev doesn't exercise the prd substrate (different runtime, different deploy path). Real cutover gate is post-merge first-fire heartbeat + 1-command rollback contract.
- **AC28 (Better Stack disambiguation in issue body) cut.** Premature optimization for an unrealized failure mode; cross-monitor correlation already disambiguates. Replaced by a runbook line in the revised plan.
- **AC4 helper choice corrected.** The existing `apps/web-platform/server/github/app-client.ts` is wrong-shaped (installation-scoped + audit-writer attached, expects `founderId`). New helper at `apps/web-platform/server/github/probe-octokit.ts` exports `createProbeOctokit()` using `@octokit/app`'s `App` constructor (no audit-writer attachment — probe stays out of `audit_github_token_use` ledger).

**The retained scope addition (AC20 in the revised plan):** post-merge synthetic-failure injection against a NON-prd surface (env-var-override in dev shell, NOT a handler input). Prd code path has zero fixture-injection plumbing — addresses Kieran's plan-review finding that brainstorm AC26's prd-vs-fixture-injection gate was incoherent.

**Source-of-truth pointer:** the revised plan at `knowledge-base/project/plans/2026-05-21-feat-tr9-pr3-oauth-probe-drift-guard-inngest-plan.md` and the derived `knowledge-base/project/specs/feat-tr9-pr3-oauth-probe-drift-guard-inngest-4211/tasks.md` supersede this brainstorm's scope decisions where they conflict. This brainstorm document is preserved as historical record of the framing-time triad assessment.
