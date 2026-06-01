---
title: "Decouple cron claude-eval heartbeats from claude exit code (9 siblings of scheduled-bug-fixer)"
date: 2026-06-01
type: fix
status: planned
lane: single-domain
brand_survival_threshold: none
related_issues:
  - 4730
related_prs: []
related_learnings:
  - knowledge-base/project/learnings/bug-fixes/2026-05-27-sentry-cron-community-monitor-missed-checkin.md
  - knowledge-base/project/learnings/2026-05-18-test-all-tail-masking-and-monitor-exit-condition-tightness.md
reference_plan: knowledge-base/project/plans/2026-06-01-fix-scheduled-bug-fixer-cron-error-checkin-plan.md
---

# 🐛 Decouple cron claude-eval heartbeats from claude exit code (siblings of `scheduled-bug-fixer`)

## Enhancement Summary

**Deepened on:** 2026-06-01

### Key Improvements

1. **Premise corrected via re-grep:** the issue's "11 crons, all `ok: spawnResult.ok`" is stale — only **9** still match; 3 (content/competitive/roadmap) were already converted to `resolveOutputAwareOk` by PR #4714. Scope is **8 crons**.
2. **Per-cron classification resolved by precedent-diff:** read every prompt → **4 Pattern-B** always-create producers (growth-audit, growth-execution, seo-aeo, community-monitor) wire `resolveOutputAwareOk`; **4 Pattern-A** conditional/best-effort crons (agent-native, legal, campaign-calendar, ux) mirror the bug-fixer `ok:true` + `warnSilentFallback` shape.
3. **All citations live-verified** (PR #4727/#4714 MERGED; 4 rule IDs active) and all enforcement gates passed (4.6 user-brand, 4.7 observability, 4.8 PAT-sweep).

### New Considerations Discovered

- `cron-campaign-calendar` was the one ambiguous case. **Correction (multi-agent review, PR #4732):** the plan-time read missed prompt **STEP 2.5** ("Heartbeat audit issue (runs when NEW == 0): create and immediately close a heartbeat audit issue … Label: `scheduled-campaign-calendar`"). Combined with STEP 2(c)'s per-overdue issue (same label), the cron creates a `scheduled-campaign-calendar` artifact on EVERY run → it is **Pattern B** (always-create producer), not Pattern A. Final split is therefore **5 Pattern-B + 3 Pattern-A**. security-sentinel + architecture-strategist independently flagged the misclassification; reclassified inline.
- None of the 8 raw crons declare `runStartedAt`; the 4 Pattern-B crons must thread it (copied from the 3 already-wired producers). The `resolveOutputAwareOk` helper works unchanged because all 4 label their summary issue with their `SENTRY_MONITOR_SLUG`.

## Overview

The `scheduled-bug-fixer` Sentry cron monitor false-paged (incident `5127648`,
error check-ins 2026-05-31 / 2026-06-01) because its heartbeat was wired as
`ok: spawnResult.ok` — a non-zero `claude --print` exit (the *normal* "no fix
landed today" outcome for a best-effort autonomous fixer) posted
`status=error` even though no infrastructure fault occurred. The fix
(PR #4727, commit `120a946c`) decoupled the monitor heartbeat from claude's
exit code: a clean end-to-end run posts `status=ok` regardless of claude's
exit, the no-fix exit is surfaced as a *non-paging* `warnSilentFallback`
WARNING-level Sentry event (`op=claude-eval-nonzero-nofix`), and only genuine
infra faults (token mint, clone/setup-workspace, parse-event, spawn-error)
keep their strict `status=error` early-returns.

Issue #4730 calls out **the sibling claude-eval crons that share the identical
over-tight semantic**. Each carries the same latent false-page risk; they have
not paged yet only because their claude invocations have exited 0 reliably so
far.

This is **not a mechanical sweep**. Each cron has a different liveness
contract, so the fix requires a per-cron decision: is "claude exited non-zero"
an infrastructure-liveness failure (page) or a best-effort outcome (log +
non-paging breadcrumb, monitor stays green)?

## Research Reconciliation — Spec vs. Codebase

The issue body asserts **11** affected crons all posting `ok: spawnResult.ok`.
A re-grep against `origin`/worktree HEAD shows the premise is **partially
stale** — 3 of the 11 were already converted to an *output-aware* heartbeat
by PR #4714 (commit `a697660c`, "output-aware Sentry heartbeat for scheduled
producers").

| Spec claim (#4730 body) | Codebase reality (HEAD) | Plan response |
| --- | --- | --- |
| 11 crons post `ok: spawnResult.ok` | Only **9** still do (grep `ok: spawnResult\.ok` returns 9 files, 18 hits). | Scope to the 9 raw crons. |
| `cron-content-generator.ts:201` is raw `ok: spawnResult.ok` | Already uses `resolveOutputAwareOk({ spawnOk: spawnResult.ok, ... })` → `ok: heartbeatOk` (PR #4714). | **Out of scope** — already fixed; not raw. |
| `cron-competitive-analysis.ts:252` is raw | Already uses `resolveOutputAwareOk` → `ok: heartbeatOk`. | **Out of scope** — already fixed. |
| `cron-roadmap-review.ts:277` is raw | Already uses `resolveOutputAwareOk` → `ok: heartbeatOk`. | **Out of scope** — already fixed. |
| "Apply the bug-fixer decoupling pattern" | TWO established patterns exist: (a) bug-fixer best-effort = `ok:true` + `warnSilentFallback(op=…-nonzero-nofix)`; (b) `resolveOutputAwareOk` in `_cron-shared.ts:186` for always-create producers (spawn-ok + issue-absent → RED). | Per-cron decision picks (a) or (b); precedent-diff resolved it to **4 Pattern-B + 4 Pattern-A** (see classification below). |
| "Per-cron decision required (not a sweep)" | Confirmed: prompt-read shows 4 crons create a `[Scheduled] …` summary issue UNCONDITIONALLY every run (growth-audit, growth-execution, seo-aeo, community-monitor → Pattern B) and 4 create issues only conditionally on findings (agent-native, legal, campaign-calendar, ux → Pattern A). | The split is the deepen-plan deliverable; #4730's "not a sweep" thesis holds. |
| Re-grep line numbers before editing | Confirmed current sites (HEAD): see Files to Edit. | Use grep, not the issue's line numbers. |

**Premise Validation:** Reference plan
`knowledge-base/project/plans/2026-06-01-fix-scheduled-bug-fixer-cron-error-checkin-plan.md`
EXISTS (H1 root-cause confirmed). Bug-fixer fix is MERGED
(`cron-bug-fixer.ts` lines 744-788, 839-846 carry the decoupled pattern;
PR #4727 / commit `120a946c`). The `resolveOutputAwareOk` helper EXISTS at
`apps/web-platform/server/inngest/functions/_cron-shared.ts:186`. All 9 raw
crons have dedicated test files under
`apps/web-platform/test/server/inngest/cron-*.test.ts`. **None** of the 9 raw
crons currently declare a `runStartedAt` variable (grep returns 0) — any cron
classified as an always-create producer needs that variable threaded for the
output-aware path. No open `code-review` issues touch these files (74 open
code-review issues queried; 0 match `cron-*-audit`, `cron-growth-*`,
`cron-legal-audit`, `cron-ux-audit`, `_cron-shared`).

## The two established patterns (pick one per cron)

**Pattern A — best-effort eval (bug-fixer shape).** For crons where "claude
exited non-zero" is a NORMAL best-effort outcome (an audit/review that
legitimately finds nothing to file, or whose value is the side-effect run, not
a guaranteed artifact). Reference: `cron-bug-fixer.ts:744-788, 839-846`.

```ts
// after spawnResult, before the final heartbeat:
if (spawnResult.abortedByTimeout) {
  // already surfaced by the claude-eval-timeout reportSilentFallback above
} else if (!spawnResult.ok) {
  warnSilentFallback(
    new Error("claude-eval exited non-zero — best-effort run, no artifact this cycle"),
    {
      feature: "cron-<name>",
      op: "claude-eval-nonzero-noop",
      message:
        "claude-eval exited non-zero (best-effort); cron monitor stays green (liveness, not success)",
      extra: { fn: "cron-<name>", exitCode: spawnResult.exitCode, durationMs: spawnResult.durationMs },
    },
  );
}
// liveness heartbeat: pipeline ran end-to-end without an INFRA fault → ok:true
await step.run("sentry-heartbeat", async () => {
  await postSentryHeartbeat({ ok: true, sentryMonitorSlug: SENTRY_MONITOR_SLUG, cronName: "cron-<name>", logger });
});
return { ok: true };
```

**Pattern B — always-create producer (output-aware shape).** For crons that
are CONTRACTUALLY expected to produce an artifact (a `scheduled-<x>` issue)
every run. A clean exit that produced no artifact SHOULD turn the monitor RED.
Reference: `_cron-shared.ts:186` `resolveOutputAwareOk` + the 3 already-wired
producers. Requires a `runStartedAt` capture before spawn.

```ts
const heartbeatOk = await step.run("verify-output", async () =>
  resolveOutputAwareOk({ spawnOk: spawnResult.ok, label: SENTRY_MONITOR_SLUG, runStartedAt, cronName: "cron-<name>" }),
);
await step.run("sentry-heartbeat", async () => {
  await postSentryHeartbeat({ ok: heartbeatOk, sentryMonitorSlug: SENTRY_MONITOR_SLUG, cronName: "cron-<name>", logger });
});
return { ok: heartbeatOk };
```

In BOTH patterns the existing infra-fault `reportSilentFallback` early-returns
(token mint, setup-workspace, parse-event) keep posting `ok: false` /
`status=error` unchanged — the decoupling is ONLY between the *success-path*
heartbeat and claude's exit code, never between the heartbeat and an infra
fault.

## Per-cron classification (precedent-diff completed; lock at work time)

Deepen-plan read each cron's prompt to determine the artifact contract:
does it create a `scheduled-<slug>`-labelled issue **unconditionally every
run** (→ Pattern B output-aware, a missing artifact pages) or **conditionally
on findings** (→ Pattern A best-effort, a clean run with no artifact is
normal)? The split is real — confirming #4730's thesis that this is a per-cron
decision, not a uniform sweep. The prompt evidence (file:line) below is the
precedent-diff; the work phase reads the full prompt to lock each call.

| Cron (slug) | Site (re-grep) | Pattern | Prompt evidence | Notes |
| --- | --- | --- | --- | --- |
| `cron-growth-audit` (`scheduled-growth-audit`) | `:197` | **B** producer | `cron-growth-audit.ts:85` "Create issue '[Scheduled] Growth Audit - <today>'" — unconditional summary each run. | Wire `resolveOutputAwareOk` + `runStartedAt`; missing summary issue → RED. |
| `cron-growth-execution` (`scheduled-growth-execution`) | `:234` | **B** producer | `cron-growth-execution.ts:114,116` "create a GitHub issue '[Scheduled] Growth Execution'"; "If no stale pages are found, create the issue noting 'No stale pages found'". | Explicitly always-create. Pattern B. |
| `cron-seo-aeo-audit` (`scheduled-seo-aeo-audit`) | `:226` | **B** producer | `cron-seo-aeo-audit.ts:108` "create a GitHub issue '[Scheduled] SEO/AEO Audit - <today>'" each run. | Pattern B. |
| `cron-community-monitor` (`scheduled-community-monitor`) | `:292` | **B** producer | `cron-community-monitor.ts:105,118` "create a GitHub Issue summarizing the findings"; even on no-platform-enabled it "create[s] a GitHub Issue titled …" + writes a dated digest each run. | Pattern B (unconditional digest). |
| `cron-agent-native-audit` (`scheduled-agent-native-audit`) | `:246` | **A** best-effort | `cron-agent-native-audit.ts:124` "For each filed issue" — per-gap, no unconditional summary. Clean audit = zero issues is normal. | Pattern A; mirror bug-fixer + `cron-strategy-review` exclusion. |
| `cron-legal-audit` (`scheduled-legal-audit`) | `:263` | **A** best-effort | `cron-legal-audit.ts:132` "If no legal documents are found, exit cleanly **without filing**". | Pattern A; explicit zero-issue clean path. |
| `cron-campaign-calendar` (`scheduled-campaign-calendar`) | `:196` | **B** producer (corrected) | `cron-campaign-calendar.ts:81-84` STEP 2.5 "Heartbeat audit issue (runs when NEW == 0): create and immediately close … Label: scheduled-campaign-calendar" + STEP 2(c) per-overdue issue (same label) → artifact every run. | **Reclassified A→B at review** (PR #4732): plan-time read missed STEP 2.5; wire `resolveOutputAwareOk` + `runStartedAt`. |
| `cron-ux-audit` (`scheduled-ux-audit`) | `:329` | **A** best-effort | `cron-ux-audit.ts:126` "No findings.json found — skipping upload" — conditional on findings. | Pattern A. |

**Work-time confirmation (not re-litigation):** the classification above is
evidence-backed; the work phase reads each full prompt to confirm there is no
counter-evidence (e.g., a producer that ALSO has a conditional path), then
locks the heartbeat shape. The SpecFlow lens (Phase 3) is the cross-check that
each Pattern-B wiring asserts the *invariant* (issue created in the run window)
not a proxy, and each Pattern-A wiring does not silently false-green a
producer.

**Pattern-B precedent (the 3 already-wired producers):** `cron-roadmap-review`,
`cron-content-generator`, `cron-competitive-analysis` all call
`resolveOutputAwareOk({ spawnOk: spawnResult.ok, label: SENTRY_MONITOR_SLUG, runStartedAt, cronName })`
and feed `ok: heartbeatOk`. The 4 new Pattern-B crons must thread a
`runStartedAt` (captured before the spawn step, ISO string) — **none of the 8
declare it today** (grep confirmed 0). `resolveOutputAwareOk`
(`_cron-shared.ts:186`) queries `verifyScheduledIssueCreated({ label: SENTRY_MONITOR_SLUG, sinceIso: runStartedAt })`; all 4 Pattern-B crons use the
slug as the issue label, so the helper works unchanged.

## User-Brand Impact

**If this lands broken, the user experiences:** a false-paging Sentry cron
monitor (operator paged at 06:00–08:00 for a benign "claude found nothing"
run), OR — the inverse failure — a monitor that goes *false-green* on a cron
whose artifact silently stopped being produced. The first is alert-fatigue;
the second is the silent-no-op the output-aware path guards against.

**If this leaks, the user's [data / workflow / money] is exposed via:** N/A —
no user data, no new write surface, no external API contract change. The
change is confined to internal observability semantics
(`postSentryHeartbeat` `ok` argument) of self-hosted Inngest cron handlers.

**Brand-survival threshold:** none — internal-observability tuning on
operator-only cron monitors; no per-user data surface.
_threshold: none, reason: change is confined to operator-facing cron-monitor heartbeat semantics; no regulated-data, auth, schema, or API-route surface is touched._

## Acceptance Criteria

### Pre-merge (PR)

- [x] For each of the 8 in-scope crons, the heartbeat semantic (Pattern A page
  vs. non-paging breadcrumb, or Pattern B output-aware) is **explicitly decided
  and documented inline** with a comment citing the liveness contract (mirror
  the `cron-bug-fixer.ts:744-769` comment block).
- [x] `git grep -nE "ok: spawnResult\.ok" apps/web-platform/server/inngest/functions/cron-*.ts`
  returns **0** hits after the change (the exact pre-fix line that PR #4714
  forbids for producers; extend the enforcement to the 8 newly-fixed crons).
- [x] Each in-scope cron's test file is updated RED→GREEN mirroring the
  bug-fixer group-(e) rewrite (`cron-bug-fixer.test.ts:809-856`): a
  non-zero-exit clean run asserts the heartbeat URL contains `status=ok` AND
  (Pattern A) a `warnSilentFallback` breadcrumb with the documented `op`, OR
  (Pattern B) `resolveOutputAwareOk` is invoked and a missing-output run posts
  `status=error`.
- [x] `reportSilentFallback` infra-fault early-returns remain **strict**
  (still post `ok: false` / `status=error`): assert at least one infra-fault
  test per cron still pages (or confirm the existing one is unchanged).
- [x] `cron-producer-output-wiring.test.ts` adds the **4 Pattern-B** crons
  (`cron-growth-audit`, `cron-growth-execution`, `cron-seo-aeo-audit`,
  `cron-community-monitor`) to the `ALWAYS_CREATE_PRODUCERS` list it asserts
  on (each must contain `resolveOutputAwareOk(` and NOT `ok: spawnResult.ok`),
  joining the existing 3. The **4 Pattern-A** crons (`cron-agent-native-audit`,
  `cron-legal-audit`, `cron-campaign-calendar`, `cron-ux-audit`) are NOT added
  — they legitimately keep a non-output-aware heartbeat, like
  `cron-strategy-review` (excluded at `cron-producer-output-wiring.test.ts:50`).
  Add a sibling guard asserting the 4 Pattern-A crons contain neither
  `ok: spawnResult.ok` (forbidden) nor `resolveOutputAwareOk` (wrong pattern)
  but DO contain `postSentryHeartbeat({ ok: true` + a `warnSilentFallback` op.
- [x] `tsc --noEmit` clean; the in-scope cron test files pass via the package's
  configured runner (vitest — verify via `apps/web-platform/package.json`
  `scripts.test` and `vitest.config.ts` `include` globs, not a hardcoded
  runner).

### Post-merge (operator)

- [x] None. The Inngest function container is restarted automatically by
  `web-platform-release.yml` on merge to `main` touching
  `apps/web-platform/**` (path-filtered `on.push`); the PR merge IS the
  deploy. No separate operator step. (Automation: handled by existing release
  pipeline.)

## Observability

```yaml
liveness_signal:
  what: Sentry cron monitor check-in per fixed cron (status=ok on clean end-to-end run)
  cadence: per cron schedule (daily/weekly per existing SENTRY_MONITOR_SLUG)
  alert_target: Sentry cron monitor (existing per-slug monitors; operator email channel)
  configured_in: apps/web-platform/server/inngest/functions/cron-<name>.ts (postSentryHeartbeat call) + apps/web-platform/infra/sentry/*.tf (existing monitors, unchanged)
error_reporting:
  destination: Sentry — reportSilentFallback (infra faults, status=error, paging) + warnSilentFallback (best-effort non-zero exit, WARNING-level, non-paging)
  fail_loud: yes — infra-fault early-returns keep status=error; best-effort exits emit a queryable WARNING event (off-host visible, not a bare logger.warn)
failure_modes:
  - mode: claude-eval non-zero exit on a best-effort cron (no artifact)
    detection: warnSilentFallback op=claude-eval-nonzero-noop (per-cron op)
    alert_route: non-paging Sentry WARNING event (monitor stays green)
  - mode: infra fault (token mint / clone / setup-workspace / parse-event / spawn-error)
    detection: existing reportSilentFallback early-return → postSentryHeartbeat ok:false
    alert_route: Sentry cron monitor status=error (pages)
  - mode: (Pattern B only) clean exit but no scheduled-<x> issue produced
    detection: resolveOutputAwareOk → scheduled-output-missing event
    alert_route: Sentry cron monitor status=error (pages)
logs:
  where: Inngest function step logs (pino) + Sentry events (reportSilentFallback / warnSilentFallback)
  retention: Sentry default (90d events); Inngest run history per plan
discoverability_test:
  command: "git grep -nE 'ok: spawnResult\\.ok' apps/web-platform/server/inngest/functions/cron-*.ts  # expect 0 hits; then grep warnSilentFallback op per fixed cron"
  expected_output: "no matches (all heartbeats decoupled); each fixed cron file contains its documented warnSilentFallback op or resolveOutputAwareOk call"
```

## Files to Edit

Re-grep before editing (line numbers as of HEAD 2026-06-01):

- `apps/web-platform/server/inngest/functions/cron-agent-native-audit.ts` (heartbeat `:246`, return `:249`)
- `apps/web-platform/server/inngest/functions/cron-campaign-calendar.ts` (`:196`, `:199`) — ⚠ confirm A vs B
- `apps/web-platform/server/inngest/functions/cron-community-monitor.ts` (`:292`, `:295`)
- `apps/web-platform/server/inngest/functions/cron-growth-audit.ts` (`:197`, `:200`)
- `apps/web-platform/server/inngest/functions/cron-growth-execution.ts` (`:234`, `:237`)
- `apps/web-platform/server/inngest/functions/cron-legal-audit.ts` (`:263`, `:266`)
- `apps/web-platform/server/inngest/functions/cron-seo-aeo-audit.ts` (`:226`, `:229`)
- `apps/web-platform/server/inngest/functions/cron-ux-audit.ts` (`:329`, `:332`)
- Corresponding test files (RED→GREEN, mirror `cron-bug-fixer.test.ts` group-(e)):
  - `apps/web-platform/test/server/inngest/cron-agent-native-audit.test.ts`
  - `apps/web-platform/test/server/inngest/cron-campaign-calendar.test.ts`
  - `apps/web-platform/test/server/inngest/cron-community-monitor.test.ts`
  - `apps/web-platform/test/server/inngest/cron-growth-audit.test.ts`
  - `apps/web-platform/test/server/inngest/cron-growth-execution.test.ts`
  - `apps/web-platform/test/server/inngest/cron-legal-audit.test.ts`
  - `apps/web-platform/test/server/inngest/cron-seo-aeo-audit.test.ts`
  - `apps/web-platform/test/server/inngest/cron-ux-audit.test.ts`
- `apps/web-platform/test/server/inngest/cron-producer-output-wiring.test.ts` — only if any cron is classified Pattern B (add to producer list).

## Files to Create

None.

## Implementation Phases (TDD)

1. **[x] Phase 0 — precondition grep.** Re-run
   `git grep -nE "ok: spawnResult\.ok" apps/web-platform/server/inngest/functions/cron-*.ts`
   to confirm the 9 sites (8 in scope + bug-fixer already done). Re-read each
   full prompt to confirm the precedent-diff classification (4B/4A) has no
   counter-evidence (a producer with an ALSO-conditional path, or vice-versa).
   Read each target cron's existing infra-fault early-returns so they are
   preserved untouched.
2. **[x] Phase 1 — RED (per cron).** For each cron, add a failing test mirroring
   `cron-bug-fixer.test.ts:809-856`: a non-zero-exit clean run must post
   `status=ok` and — (Pattern A) emit the documented `warnSilentFallback` op
   AND the no-output run stays green; (Pattern B) invoke `resolveOutputAwareOk`
   AND a spawn-ok-but-no-issue run posts `status=error`
   (`scheduled-output-missing`). Keep an existing infra-fault test asserting
   `status=error`.
3. **[x] Phase 2 — GREEN (per cron).** Apply Pattern A (agent-native, legal,
   campaign-calendar, ux) or Pattern B (growth-audit, growth-execution,
   seo-aeo, community-monitor — thread `runStartedAt` + call
   `resolveOutputAwareOk`) to each cron's success-path heartbeat, with the
   inline liveness-contract comment. Leave infra-fault early-returns untouched.
4. **[x] Phase 3 — enforcement + suite.** Extend `cron-producer-output-wiring.test.ts`:
   add the 4 Pattern-B crons to `ALWAYS_CREATE_PRODUCERS`; add a sibling guard
   for the 4 Pattern-A crons (no `ok: spawnResult.ok`, no `resolveOutputAwareOk`,
   has `postSentryHeartbeat({ ok: true` + a `warnSilentFallback` op). Run
   `tsc --noEmit` and the package's configured test runner over the changed
   files; then the cron suite.

## Risks & Mitigations

- **Misclassifying a producer as best-effort (false-green).** If a cron is
  actually always-create and we apply Pattern A, a silently-stopped artifact
  goes undetected. Mitigation: precedent-diff (below) read each prompt and
  pinned 4B/4A on the unconditional-vs-conditional issue-create distinction;
  SpecFlow (Phase 3) cross-checks that each Pattern-B wiring asserts the
  invariant (issue in run window), not a proxy.
- **Sentry monitor slug / infra drift.** No `*.tf` change — the monitors
  already exist; only the `ok` argument changes. Mitigation: AC asserts the
  heartbeat URL slug is unchanged per cron.
- **Test-runner discovery.** Per repo Sharp Edge, do NOT hardcode `bun test`;
  `apps/web-platform` uses vitest with `test/**/*.test.ts` include globs and
  the test files already live there. Mitigation: AC verifies via
  `package.json scripts.test` + `vitest.config.ts include`.
- **`runStartedAt` absent in the 8 raw crons.** Pattern B needs it; grep
  confirmed 0 declarations. Mitigation: the 4 Pattern-B crons thread it (ISO
  string captured before the spawn step) exactly like the 3 already-converted
  producers; the 4 Pattern-A crons do not need it.

### Precedent-diff — Pattern A (bug-fixer) vs Pattern B (`resolveOutputAwareOk`)

Both patterns are established in-repo; this change is NOT novel. Side-by-side:

| Aspect | Pattern A (best-effort) | Pattern B (always-create producer) |
| --- | --- | --- |
| Precedent | `cron-bug-fixer.ts:744-788, 839-846` (PR #4727, MERGED) | `_cron-shared.ts:186` + `cron-roadmap-review.ts:287-297`, `cron-content-generator.ts:211`, `cron-competitive-analysis.ts:262` (PR #4714, MERGED) |
| Success-path heartbeat | `postSentryHeartbeat({ ok: true, … })` always | `postSentryHeartbeat({ ok: heartbeatOk, … })` where `heartbeatOk = resolveOutputAwareOk({ spawnOk, label: SENTRY_MONITOR_SLUG, runStartedAt, cronName })` |
| Non-zero claude exit | `warnSilentFallback(op=…-nonzero-noop)` (WARNING, non-paging) | folded into `resolveOutputAwareOk`: `!spawnOk` → `ok:false` (spawn error already reported upstream) |
| No-output clean run | green (normal) | RED + `scheduled-output-missing` event |
| Verify GitHub query | none | `verifyScheduledIssueCreated({ label: SENTRY_MONITOR_SLUG, sinceIso: runStartedAt })` — confirmed all 4 Pattern-B crons label their summary issue with their slug (`scheduled-growth-audit` etc.), so the helper works unchanged |
| Producer-wiring test | excluded (like `cron-strategy-review` at `:50`) | added to `ALWAYS_CREATE_PRODUCERS` |

No novel pattern is introduced; the only new code per Pattern-B cron is the
`runStartedAt` capture + the `resolveOutputAwareOk` call (copy the 3 wired
producers verbatim), and per Pattern-A cron the bug-fixer `else if (!spawnResult.ok)` `warnSilentFallback` block + `ok:true` heartbeat.

### Research Insights

- **Inngest is canonical (ADR-033).** No new scheduled job is introduced — all
  8 crons already exist as Inngest functions (33 `cron-*.ts` files on disk);
  Phase 4.4 scheduled-work check is satisfied by editing in place.
- **The `warnSilentFallback` vs `logger.warn` choice is load-bearing, not
  cosmetic.** Per `cron-bug-fixer.ts:755-769`: a bare pino `logger.warn` only
  adds a Sentry breadcrumb, flushed solely on a later `captureException` (which
  a clean `ok:true` run never produces), and lands in a Docker json-file stream
  Vector does not tail — i.e. invisible without SSH. The WARNING-level event is
  the only off-host-queryable, non-paging signal that makes a
  chronically-broken-but-live cron diff-able week over week
  (`cq-silent-fallback-must-mirror-to-sentry`, `hr-observability-layer-citation`).
- **Verify-the-negative (deepen Phase 4.45):** the plan's negative claims were
  grep-confirmed — "none of the 8 declare `runStartedAt`" (grep -c → 0);
  "`cron-strategy-review` is the excluded-producer precedent"
  (`cron-producer-output-wiring.test.ts:50` confirms with the deliberate-exclusion
  comment); "no `*.tf` change" (Sentry monitors are pre-existing per the
  `SENTRY_MONITOR_SLUG` NAME NOTE comments).
- **Live-citation verification:** PR #4727 (MERGED, "scheduled-bug-fixer
  heartbeat ok decoupled from claude exit code") and PR #4714 (MERGED,
  "output-aware Sentry heartbeat for scheduled producers") both confirmed via
  `gh pr view`; all 4 cited rule IDs are active in AGENTS sidecars.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only
  `TBD`/`TODO`/placeholder text, or omits the threshold will fail
  `deepen-plan` Phase 4.6. (Filled above; threshold = none with scope-out
  reason.)
- The issue's line numbers and "11 crons" count are STALE (PR #4714 converted
  3). Use the grep, not the issue body — see Research Reconciliation.
- Do NOT add Pattern A crons to `cron-producer-output-wiring.test.ts`'s
  producer list; that test forbids `ok: spawnResult.ok` for producers AND
  requires `resolveOutputAwareOk(`. A best-effort cron legitimately has
  neither — like `cron-strategy-review` (explicitly excluded in that test at
  `:50`).
- Mirror the bug-fixer's `warnSilentFallback` (WARNING-level Sentry event),
  NOT a bare `logger.warn` — a pino `logger.warn` only adds a Sentry
  breadcrumb (flushed solely on a later `captureException`, which a clean
  `ok:true` run never produces) and lands in a Docker json-file stream Vector
  does not tail — invisible without SSH (`cq-silent-fallback-must-mirror-to-sentry`,
  `hr-observability-layer-citation`).
