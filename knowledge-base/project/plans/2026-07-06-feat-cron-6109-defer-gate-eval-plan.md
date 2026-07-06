---
title: "feat: self-disarming recurring Inngest cron re-evaluating deferred #6109 at its ≥8-week defer gate"
date: 2026-07-06
branch: feat-one-shot-6109-defer-gate-cron
type: feature
lane: single-domain
brand_survival_threshold: none
refs: [6109]
status: draft
---

# feat: `cron-6109-defer-gate-eval` — self-disarming recurring defer-gate nudge for #6109

## Overview

Issue **#6109** ("rule-metrics: cross-worktree read-merge + first_observed obsolescence")
is an OPEN p3 engineering task (label `deferred-scope-out`, milestone *Post-MVP / Later*)
that 4 plan-reviewers deliberately deferred until "real fire data accumulates ≥8 weeks"
after its producer landed. The producer — the rule-metrics local-aggregation fix — merged
**2026-07-06** in commit `0ce2d2d75`, so the re-evaluation window opens **2026-08-31**
(2026-07-06 + 56 days = 8 weeks; verified by calendar arithmetic).

This plan builds a **recurring Inngest cron** (`cron-6109-defer-gate-eval`) that fires
monthly, no-ops before the window, then — once the window is open — posts **exactly one**
re-evaluation nudge comment on #6109 and **self-disarms** (idempotent; never double-posts,
never nags forever). It mirrors the recurring-cron reminder pattern already in the tree
(`cron-nag-4216-readiness.ts` — the closest sibling — and `cron-review-reminder.ts` for
config), and the date-guard / mint-inside-`step.run` / token-redaction idioms of
`oneshot-4650-monitor-close.ts` and `oneshot-f2-defer-gate-review.ts`.

**Mechanism decided upstream (do NOT re-litigate):** recurring cron, NOT a self-armed
oneshot. Consistent with ADR-033 (Inngest is the single cron substrate; Inngest > GH
Actions cron) and the recurring-nag precedent `cron-nag-4216-readiness`.

**PR body says `Refs #6109`, NOT `Closes` — #6109 stays OPEN; this cron only nudges it.**

## Premise Validation (Phase 0.6)

Every cited reference was checked against live repo state; all held:

- **#6109 is OPEN** (`gh issue view 6109` → `state: OPEN`, label `deferred-scope-out`,
  milestone *Post-MVP / Later*). Title confirmed: "rule-metrics: cross-worktree read-merge
  + first_observed obsolescence (completeness + prunability)". Not stale — the nudge is warranted.
- **Producer commit `0ce2d2d75` merged 2026-07-06** (`git show -s`): "fix(telemetry):
  rule-metrics aggregator runs where its gitignored input lives … (#6042) (#6099)". Window
  open date 2026-08-31 = merge + 8 weeks, confirmed.
- **All cited files exist**: `cron-review-reminder.ts`, `oneshot-4650-monitor-close.ts`,
  `_cron-shared.ts`, `app/api/inngest/route.ts`, `cron-manifest.ts`,
  `function-registry-count.test.ts`, and the runbook
  `knowledge-base/engineering/operations/runbooks/inngest-oneshot-and-reminder-patterns.md`.
- **Mechanism vs ADR corpus**: recurring-cron-over-oneshot is consistent with ADR-033 and
  the `cron-nag-4216-readiness` precedent; no ADR rejects this shape. No new architectural
  decision is created (see Architecture Decision section).

## Research Reconciliation — Spec vs. Codebase

The task ARGUMENTS named **5 integration points**. Codebase inspection surfaced **two
material gaps** that would fail CI if implemented literally as 5 points. Both are folded in.

| Spec claim | Codebase reality | Plan response |
| --- | --- | --- |
| "5 integration points" (new file, route.ts, EXPECTED_CRON_FUNCTIONS, count test, unit test) | `function-registry-count.test.ts` has **guard (c)** ("every `SENTRY_MONITOR_SLUG` has a `cron-monitors.tf` resource OR is in `KNOWN_UNMONITORED_SLUGS`") and **guard (f)** ("every `sentry_cron_monitor` resource has a `-target` line in `apply-sentry-infra.yml`"). A recurring cron that declares `SENTRY_MONITOR_SLUG` and posts a heartbeat trips these unless wired. `cron-nag-4216-readiness` — the closest sibling — has a **real** `sentry_cron_monitor` (`cron-monitors.tf:899`) + `-target` line (`apply-sentry-infra.yml:241`). | **Add two more integration points**: (6) new `sentry_cron_monitor "cron_6109_defer_gate_eval"` in `infra/sentry/cron-monitors.tf`; (7) matching `-target=sentry_cron_monitor.cron_6109_defer_gate_eval` line in `.github/workflows/apply-sentry-infra.yml`. Monthly `crontab = "0 9 1 * *"` is already an established schedule (cron-monitors.tf:452,542) — low-risk. |
| "(e) Post a Sentry heartbeat … return `{ ok: false, reason: 'date-guard' }` before the window" | `postSentryHeartbeat({ ok })` maps `ok:false` → `?status=error` → monitor **RED**. Feeding the date-guard `{ok:false}` straight to the heartbeat would false-RED the monitor **every month until 2026-08-31** (~2 months of spurious pages). And early-returning before the heartbeat leaves NO check-in → Sentry marks it "missed" → also RED. | **Decouple liveness from the semantic verdict.** The heartbeat represents *the cron fired on schedule* (liveness), so it posts `ok:true` on ALL benign on-schedule paths — date-guard, already-handled, AND posted — and `ok:false` ONLY on a real error (token-mint / Octokit GET/POST throw). The handler still **returns** `{ ok: false, reason: "date-guard" }` per spec, but the value fed to `postSentryHeartbeat` is a separate `heartbeatOk`. Mirrors `cron-nag-4216-readiness` (benign closed-skip returns `ok:true` → green; only API error → red). |
| "self-disarm if any existing comment body contains `DEFER_GATE_MARKER`" | GitHub returns issue comments **paginated** (≤100/page). A single-page GET could miss a marker on page 2 → double-post — the exact failure mode self-disarm must prevent. `@octokit/core` has no `.paginate` (siblings use bare `.request`). | Paginate the comments read (`per_page: 100`, loop while a full page returns) inside the step; check every body for the marker. Bounded (issue #6109 is low-traffic). |

## User-Brand Impact

**If this lands broken, the user experiences:** a wrong/duplicate re-evaluation comment on
internal issue #6109, OR (the failure mode this cron prevents) #6109 silently falls off the
radar when its window opens because the nudge never fires. No end-user-facing surface.

**If this leaks, the user's data is exposed via:** nothing — the cron holds only a
short-lived, least-privilege (`contents:read`, `issues:write`) GitHub **App installation
token** (never a founder BYOK key), minted inside `step.run`, never returned into step
state, and scrubbed via `redactToken` on error. It posts one public issue comment
containing no personal data.

**Brand-survival threshold:** `none` — internal ops-tooling cron; no user-facing UI, no
regulated/personal data, operator-owned credentials only.

- `threshold: none, reason: server-side Inngest ops cron holding only a least-privilege App
  token and posting a public internal issue comment — no user data, no auth/migration/API
  surface, no regulated-data processing.`

## Implementation Phases

### Phase 1 — New cron function (Files to Create)

**Create** `apps/web-platform/server/inngest/functions/cron-6109-defer-gate-eval.ts`.

Constants (exported for tests, mirroring `cron-nag-4216-readiness`):

```ts
const FUNCTION_NAME = "cron-6109-defer-gate-eval";
const SENTRY_MONITOR_SLUG = "cron-6109-defer-gate-eval";   // slug == fn id (cidr-refresh convention)
const TOKEN_MIN_LIFETIME_MS = 15 * 60 * 1000;

export const ISSUE_NUMBER = 6109;
export const DEFER_GATE_OPEN = "2026-08-31";               // producer 0ce2d2d75 merged 2026-07-06 + 8w
export const PRODUCER_MERGE_DATE = "2026-07-06";
export const DEFER_GATE_MARKER = "<!-- cron-6109-defer-gate-eval -->";
```

Registration (mirror `cron-review-reminder.ts` / `cron-nag-4216-readiness.ts` exactly):

```ts
export const cron6109DeferGateEval = inngest.createFunction(
  {
    id: "cron-6109-defer-gate-eval",
    concurrency: [
      { scope: "fn", limit: 1 },
      { scope: "account", key: '"cron-platform"', limit: 1 },
    ],
    retries: 1,
  },
  [
    { cron: "0 9 1 * *" },                                 // monthly, 1st @ 09:00 UTC
    { event: "cron/6109-defer-gate-eval.manual-trigger" }, // manual trigger (auto-allowlisted)
  ],
  cron6109DeferGateEvalHandler as unknown as Parameters<typeof inngest.createFunction>[2],
);
```

> **Note — exported identifier `cron6109DeferGateEval`.** `function-registry-count.test.ts`
> guard (b) derives the expected identifier from the filename via camelCase
> (`cron-6109-defer-gate-eval` → `cron6109DeferGateEval`). The export MUST be named exactly
> this or guard (b) fails.

**Handler design** (imports: `inngest`; from `_cron-shared`: `REPO_OWNER`, `REPO_NAME`,
`mintInstallationToken`, `postSentryHeartbeat`, `redactToken`,
`ISSUE_CREATOR_CRON_TOKEN_PERMISSIONS`, `type HandlerArgs`; from `@/server/observability`:
`reportSilentFallback`, `warnSilentFallback`; `type Octokit` from `@octokit/core`):

```
cron6109DeferGateEvalHandler({ event, step, logger }):
  data = event?.data ?? {}

  // ── DATE GUARD (pure, OUTSIDE step.run — mirrors oneshot-4650/f2 pre-step guards) ──
  // Optional test override; validate shape like siblings.
  if (data.date_override !== undefined && !/^\d{4}-\d{2}-\d{2}$/.test(String(data.date_override))):
      reportSilentFallback(... op:"date-override-validation" ...)
      // still post a liveness heartbeat so a bad manual trigger doesn't dark the monitor
      await step.run("sentry-heartbeat", () => postSentryHeartbeat({ ok:true, SENTRY_MONITOR_SLUG, FUNCTION_NAME, logger }))
      return { ok:false, reason:"invalid-date-override" }

  today = data.date_override ?? new Date().toISOString().slice(0,10)
  if (today < DEFER_GATE_OPEN):
      // benign, EXPECTED for the first ~2 months → WARN (not error), heartbeat stays GREEN
      warnSilentFallback(new Error(`date guard: today=${today} < gate=${DEFER_GATE_OPEN} — no-op`),
        { feature:FUNCTION_NAME, op:"date-guard", message:"before ≥8-week defer gate — no-op",
          extra:{ fn:FUNCTION_NAME, today, gate:DEFER_GATE_OPEN } })
      await step.run("sentry-heartbeat", () => postSentryHeartbeat({ ok:true, ... }))   // liveness
      return { ok:false, reason:"date-guard" }

  // ── Step 1: mint least-privilege token (INSIDE step.run; NOT returned raw is fine —
  //     siblings DO return it into step state; we mirror cron-nag-4216 which returns it.
  //     Prefer the oneshot-4650 shape: mint INSIDE the work step so the live token never
  //     persists in Inngest step state. We adopt the mint-inside-work-step shape.) ──
  // ── Step 2: check-and-eval (GET issue, paginate comments, self-disarm, POST) ──
  result = await step.run("check-and-eval", async () => {
      token = await mintInstallationToken({ tokenMinLifetimeMs:TOKEN_MIN_LIFETIME_MS,
                                            permissions: ISSUE_CREATOR_CRON_TOKEN_PERMISSIONS })
      octokit = new Octokit({ auth: token })
      try:
        // (a) issue state
        issue = await octokit.request("GET /repos/{owner}/{repo}/issues/{issue_number}", {owner,repo,issue_number:6109})
        if (issue.data.state === "closed"): return { ok:true, reason:"already-handled", heartbeatOk:true }
        // (b) marker scan — paginate ALL comments (idempotency guard)
        page = 1
        loop:
          comments = await octokit.request("GET /repos/{owner}/{repo}/issues/{issue_number}/comments",
                       {owner,repo,issue_number:6109, per_page:100, page})
          if any(c.body includes DEFER_GATE_MARKER): return { ok:true, reason:"already-handled", heartbeatOk:true }
          if comments.data.length < 100: break
          page++
        // (c) window open + not closed + no marker → POST exactly one comment
        await octokit.request("POST /repos/{owner}/{repo}/issues/{issue_number}/comments",
                       {owner,repo,issue_number:6109, body: NUDGE_BODY})
        logger.info(...)
        return { ok:true, reason:"posted", heartbeatOk:true }
      catch (err):
        // redact the minted token before Sentry; preserve Error.name (cron-review-reminder shape)
        redacted = new Error(redactToken(err.message ?? "", token)); redacted.name = err.name
        reportSilentFallback(redacted, { feature:FUNCTION_NAME, op:"check-and-eval",
          message:"defer-gate eval failed (GET/list/POST)", extra:{ fn:FUNCTION_NAME } })
        return { ok:false, reason:"api-error", heartbeatOk:false }
  })

  // ── Step 3: Sentry heartbeat — liveness decoupled from semantic verdict ──
  await step.run("sentry-heartbeat", () =>
    postSentryHeartbeat({ ok: result.heartbeatOk, sentryMonitorSlug:SENTRY_MONITOR_SLUG, cronName:FUNCTION_NAME, logger }))

  return { ok: result.ok, reason: result.reason }
```

**Marker + nudge body** — the marker HTML comment MUST be embedded in the body so the next
fire's scan finds it:

```
NUDGE_BODY = [
  DEFER_GATE_MARKER,                                            // "<!-- cron-6109-defer-gate-eval -->"
  "## ≥8-week defer gate is now OPEN — re-evaluate #6109",
  "",
  `The ≥8-week defer window (opened **${DEFER_GATE_OPEN}**; producer merged`,
  `**${PRODUCER_MERGE_DATE}** in \`0ce2d2d75\`) is now open.`,
  "",
  "**Re-evaluate readiness:** check whether `rule-metrics.json` shows accumulated",
  "non-zero fire data from local worktree logs.",
  "- If YES → implement sub-tasks 1–3 first (cross-worktree read-merge, `first_observed`",
  "  stamp, prune-proxy swap), then add sub-task 4 (read-only canary) only once it goes green.",
  "- If NO → the data still has not accumulated; leave this open and ignore this nudge.",
  "",
  "Re-enter with `/soleur:go 6109`.",
  "",
  `_Posted once by Inngest function \`${FUNCTION_NAME}\`; it self-disarms after this comment`,
  `(marker: \`${DEFER_GATE_MARKER}\`). Delete the function to stop entirely._`,
].join("\n")
```

> **Design note (heartbeat token-state):** `cron-nag-4216-readiness` mints the token in a
> separate step-1 and returns it into step state; `oneshot-4650-monitor-close` mints
> *inside* the work step and never returns it (keeping the live token out of persisted step
> state). This plan adopts the **oneshot-4650 shape** (mint inside `check-and-eval`) because
> the spec explicitly requires "never return the token into step state." Keep the mint on
> the work path only — the date-guard/invalid-override paths never mint.

### Phase 2 — Register in the serve route (Files to Edit)

**Edit** `apps/web-platform/app/api/inngest/route.ts`:
- Add import (alphabetical by path — `cron-6109-*` sorts BEFORE `cron-agent-native-audit`
  because `6 < a`; insert right after the `cfoOnPaymentFailed` import at line 21):
  `import { cron6109DeferGateEval } from "@/server/inngest/functions/cron-6109-defer-gate-eval";`
- Add `cron6109DeferGateEval,` to the `serve({ functions: [...] })` array (same position —
  first cron entry, after `cfoOnPaymentFailed`).

### Phase 3 — Watchdog manifest (Files to Edit)

**Edit** `apps/web-platform/server/inngest/cron-manifest.ts`: add `"cron-6109-defer-gate-eval"`
to `EXPECTED_CRON_FUNCTIONS` (alphabetically first — before `"cron-agent-native-audit"`).
This also auto-allowlists `cron/6109-defer-gate-eval.manual-trigger` for
`/soleur:trigger-cron` (the allowlist in `lib/inngest/manual-trigger-allowlist.ts` is
**derived** from this manifest — no separate edit).

### Phase 4 — Sentry monitor Terraform (Files to Edit) — *gap surfaced by guard (c)+(f)*

**Edit** `apps/web-platform/infra/sentry/cron-monitors.tf`: add a `sentry_cron_monitor`
resource mirroring `scheduled_nag_4216_readiness` (cron-monitors.tf:899), with the monthly
crontab:

```hcl
# Monthly 1st @ 09:00 UTC — #6109 defer-gate re-eval nudge (self-disarming, pure TS).
# Inngest-fired via server/inngest/functions/cron-6109-defer-gate-eval.ts. Slug MUST match
# SENTRY_MONITOR_SLUG and the crontab MUST match the handler's { cron: "0 9 1 * *" } trigger.
resource "sentry_cron_monitor" "cron_6109_defer_gate_eval" {
  organization            = var.sentry_org
  project                 = data.sentry_project.web_platform.slug
  name                    = "cron-6109-defer-gate-eval"
  schedule                = { crontab = "0 9 1 * *" }
  checkin_margin_minutes  = 30
  max_runtime_minutes     = 5
  failure_issue_threshold = 1
  recovery_threshold      = 1
  timezone                = "UTC"
}
```

**Edit** `.github/workflows/apply-sentry-infra.yml`: add
`-target=sentry_cron_monitor.cron_6109_defer_gate_eval \` to the `-target` allowlist block
(alongside `scheduled_nag_4216_readiness` at line 241). Without this, guard (f) fails AND
the monitor is silently never created in prod (the apply reports success over a plan that
excludes it).

### Phase 5 — Registry-count guard (Files to Edit)

**Edit** `apps/web-platform/test/server/inngest/function-registry-count.test.ts`:
- Guard (a): bump the route array count `expect(routeEntries.length).toBe(60)` → `61`.
- Guards (b), (c), (e), (f) require **no manual edit** — they auto-derive from the
  filesystem/manifest/tf/workflow, and Phases 1/3/4 satisfy them. (c) passes because the tf
  resource added in Phase 4 provides the monitor for `SENTRY_MONITOR_SLUG`.
- **Do NOT add the slug to `KNOWN_UNMONITORED_SLUGS`** — we ship a real monitor (Phase 4),
  so an exemption would be a stale-but-tolerated entry. (Alternative considered below.)

### Phase 6 — Unit test (Files to Create)

**Create** `apps/web-platform/test/server/inngest/cron-6109-defer-gate-eval.test.ts`,
mirroring `cron-nag-4216-readiness.test.ts`'s mock scaffold (mock `@/server/observability`,
`@octokit/core` with the `function(){ this.request = spy }` vitest-4 constructor shape,
`@/server/github/probe-octokit`, `@/server/github-app` `generateInstallationToken`;
`makeStep()` recorder; Sentry env stubs + `vi.stubGlobal("fetch", …)` for the heartbeat
POST). Assert the three spec cases + guards:

1. **date-guard no-op before 2026-08-31** via `date_override: "2026-08-30"` → returns
   `{ ok:false, reason:"date-guard" }`, posts **no** comment, `warnSilentFallback` called
   once, `reportSilentFallback` NOT called, and the heartbeat step posted `ok:true`
   (liveness green — NOT red).
2. **self-disarm when a marker comment exists**: `date_override: "2026-09-01"`, issue open,
   comments include one whose body contains `DEFER_GATE_MARKER` → returns
   `{ ok:true, reason:"already-handled" }`, posts **no** comment.
3. **posts exactly one comment when window open + no marker**: `date_override:
   "2026-09-01"`, issue open, comments contain no marker → returns
   `{ ok:true, reason:"posted" }`, exactly **1** POST `…/comments`, body contains the
   marker + `/soleur:go 6109` + the window/producer dates.
4. self-disarm when `issue.state === "closed"` → `{ ok:true, reason:"already-handled" }`,
   no POST.
5. (source-shape anchors, mirroring nag-4216) `it.each` over `id: "cron-6109-defer-gate-eval"`,
   `cron: "0 9 1 * *"`, `event: "cron/6109-defer-gate-eval.manual-trigger"`,
   `scope: "fn"`/`scope: "account"`/`key: '"cron-platform"'`, `retries: 1`,
   `DEFER_GATE_MARKER`, `DEFER_GATE_OPEN = "2026-08-31"`, `postSentryHeartbeat`.

## Alternative Approaches Considered

| Alternative | Why not |
| --- | --- |
| One-time self-armed oneshot (`oneshot-*.ts`) instead of recurring cron | Explicitly decided upstream — recurring cron per the `cron-nag-4216-readiness` precedent. Not re-litigated. |
| Exempt via `KNOWN_UNMONITORED_SLUGS` instead of a real `sentry_cron_monitor` | Cheaper (one test-file line, no tf/workflow edit, no `apply-sentry-infra` auto-apply) but the heartbeat then posts to a non-provisioned monitor and the spec's "it gets a monitor" intent is unmet; nag-4216's *end-state* is a real monitor. **Ship the real monitor.** If a reviewer prefers to avoid the sentry-infra apply in this PR, the fallback is: drop Phase 4, add `"cron-6109-defer-gate-eval"` to `KNOWN_UNMONITORED_SLUGS`. |
| No `SENTRY_MONITOR_SLUG` const (inline the slug) to dodge guard (c) | Hack; diverges from every sibling; loses the count-test source anchor. Rejected. |

## Observability

```yaml
liveness_signal:
  what: Sentry Crons check-in ("cron-6109-defer-gate-eval") posted every monthly fire
  cadence: monthly (0 9 1 * *)
  alert_target: Sentry cron monitor cron-6109-defer-gate-eval (failure_issue_threshold 1, checkin_margin 30m) → Better Stack page on missed/error
  configured_in: apps/web-platform/infra/sentry/cron-monitors.tf (resource cron_6109_defer_gate_eval) + apply-sentry-infra.yml -target
error_reporting:
  destination: Sentry issues stream via reportSilentFallback (op:"check-and-eval" / "date-override-validation"); token redacted via redactToken
  fail_loud: true
failure_modes:
  - mode: token-mint or Octokit GET/list/POST throws
    detection: reportSilentFallback(op:"check-and-eval") + heartbeat posts ok:false → monitor RED
    alert_route: Sentry issues + cron monitor error status
  - mode: scheduler stops firing (Inngest de-plan / registration drift)
    detection: no monthly check-in within checkin_margin → Sentry "missed"; also cron-inngest-cron-watchdog classifies EXPECTED_CRON_FUNCTIONS against /v1/functions
    alert_route: Sentry cron monitor missed + watchdog
  - mode: benign no-op (date-guard before window / already-handled) misread as failure
    detection: warnSilentFallback(op:"date-guard") is WARN not error; heartbeat posts ok:true (liveness green) — false-RED explicitly avoided
    alert_route: non-paging warn only
logs:
  where: pino stdout → Better Stack (logger.info on posted/skip; logger.warn on date-guard)
  retention: Better Stack default
discoverability_test:
  command: gh api repos/jikig-ai/soleur/issues/6109/comments --jq '[.[] | select(.body｜contains("<!-- cron-6109-defer-gate-eval -->"))] | length'
  expected_output: "0 before first post / 1 after — never ≥2 (idempotency); no ssh required"
```

### Affected-surface note (Phase 2.9.2 — cron worker is a blind surface)

The cron worker cannot be directly inspected. Its `failure_modes.detection` above emits
**from the worker** (reportSilentFallback events tagged `fn:"cron-6109-defer-gate-eval"`,
op-discriminated: `date-override-validation` / `date-guard` / `check-and-eval`), plus the
in-worker heartbeat, so a host-side observer discriminates *mint-fail* vs *api-error* vs
*benign-no-op* from one event stream without SSH.

## Infrastructure (IaC)

### Terraform changes
- `apps/web-platform/infra/sentry/cron-monitors.tf` — new `sentry_cron_monitor
  "cron_6109_defer_gate_eval"` (jianyuan/sentry provider, already pinned in this root).
- No new secrets/variables (`var.sentry_org`, `data.sentry_project.web_platform` already exist).

### Apply path
- (a) auto-apply via `.github/workflows/apply-sentry-infra.yml` on merge (path-filtered on
  `infra/sentry/*.tf`), scoped by the `-target` allowlist. The new `-target` line is added
  in the same PR. No operator SSH, no manual mint.

### Distinctness / drift safeguards
- Single Sentry org/project (no dev/prd split for Sentry monitors). `function-registry-count`
  guards (c)/(f)/(f2) keep the tf resource, the `-target` line, and the handler slug in lockstep.

### Vendor-tier reality check
- `sentry_cron_monitor` is on the standard Sentry Crons tier already in use by ~30 sibling
  monitors — no free-tier gate (unlike `betteruptime_policy`). Monthly crontab `0 9 1 * *`
  already exists on other monitors (cron-monitors.tf:452,542).

## Architecture Decision (ADR / C4)

**No architectural decision.** This adds one more cron following the established ADR-033
Inngest-cron substrate and the `cron-nag-4216-readiness` recurring-nag pattern. No new
substrate, ownership/tenancy boundary, resolver/trust boundary, or ADR reversal. C4:
reviewed `model.c4` / `views.c4` / `spec.c4` conceptually — the cron is an internal
scheduled job with no new external actor, external system, or data store (it uses the
already-modeled GitHub App integration edge and the Sentry monitoring edge). No `.c4` edit.
ADR/C4 gate → **skip**.

## Domain Review

**Domains relevant:** none

No cross-domain implications — internal engineering/ops tooling change (a scheduled reminder
cron). Product/UX Gate: NONE (no `components/**`, `app/**/page.tsx`, or UI-surface file in
Files to Create/Edit).

## Acceptance Criteria (Pre-merge / PR)

- [ ] `apps/web-platform/server/inngest/functions/cron-6109-defer-gate-eval.ts` exists,
  exports `cron6109DeferGateEval` (createFunction) + `cron6109DeferGateEvalHandler` +
  constants `ISSUE_NUMBER=6109`, `DEFER_GATE_OPEN="2026-08-31"`,
  `DEFER_GATE_MARKER="<!-- cron-6109-defer-gate-eval -->"`.
- [ ] Trigger array is `[{ cron: "0 9 1 * *" }, { event: "cron/6109-defer-gate-eval.manual-trigger" }]`;
  concurrency + `retries:1` byte-match `cron-review-reminder.ts`.
- [ ] `route.ts` imports and registers `cron6109DeferGateEval`;
  `grep -c cron6109DeferGateEval apps/web-platform/app/api/inngest/route.ts` == 2 (import + array).
- [ ] `EXPECTED_CRON_FUNCTIONS` contains `"cron-6109-defer-gate-eval"`.
- [ ] `cron-monitors.tf` has `sentry_cron_monitor "cron_6109_defer_gate_eval"` with
  `name = "cron-6109-defer-gate-eval"` and `crontab = "0 9 1 * *"`; `apply-sentry-infra.yml`
  has the matching `-target=sentry_cron_monitor.cron_6109_defer_gate_eval` line.
- [ ] `function-registry-count.test.ts` guard (a) count updated to `61`; the whole file
  passes (guards b/c/e/f green).
- [ ] Unit test asserts (i) date-guard no-op (heartbeat green, no comment), (ii) marker
  self-disarm, (iii) exactly-one-comment when open + no marker, (iv) closed self-disarm.
- [ ] `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` passes.
- [ ] `cd apps/web-platform && ./node_modules/.bin/vitest run test/server/inngest/cron-6109-defer-gate-eval.test.ts test/server/inngest/function-registry-count.test.ts` passes.
- [ ] PR body says **`Refs #6109`** (NOT `Closes`).

## Test Scenarios

1. `date_override:"2026-08-30"`, issue open → `{ok:false, reason:"date-guard"}`, 0 comments,
   heartbeat `ok:true`, `warnSilentFallback` ×1, `reportSilentFallback` ×0.
2. `date_override:"2026-09-01"`, issue open, a comment body contains the marker →
   `{ok:true, reason:"already-handled"}`, 0 new comments.
3. `date_override:"2026-09-01"`, issue open, no marker → `{ok:true, reason:"posted"}`,
   exactly 1 POST, body contains marker + `/soleur:go 6109` + `2026-08-31` + `2026-07-06`.
4. `date_override:"2026-09-01"`, issue closed → `{ok:true, reason:"already-handled"}`, 0 comments.
5. GET issue throws → `{ok:false, reason:"api-error"}`, `reportSilentFallback` ×1, heartbeat `ok:false`.
6. (source anchors) registration + constant literals present.

## Open Code-Review Overlap

None. `gh issue list --label code-review --state open` cross-checked against every
Files-to-Edit path (`route.ts`, `function-registry-count`, `cron-manifest`,
`cron-monitors.tf`, `apply-sentry-infra`, `_cron-shared`) — zero matches.

## Sharp Edges

- **Feeding the date-guard `{ok:false}` straight into `postSentryHeartbeat` false-REDs the
  monitor for ~2 months.** The heartbeat is a LIVENESS signal — post `ok:true` on every
  benign on-schedule path (date-guard, already-handled, posted); `ok:false` only on a real
  error. This is the load-bearing decoupling; the unit test asserts the date-guard path
  posts a GREEN heartbeat.
- **Comment pagination.** Self-disarm scans ALL comments (paginate `per_page:100`); a
  single-page GET could miss a page-2 marker → double-post. `@octokit/core` has no
  `.paginate` — loop manually.
- **Guard (c)+(f) are the two integration points the spec omitted.** A `SENTRY_MONITOR_SLUG`
  const without a `cron-monitors.tf` resource + `-target` line fails
  `function-registry-count.test.ts` at CI. Phases 4+5 cover both.
- **Exported identifier must be `cron6109DeferGateEval`** — guard (b) derives it from the
  filename via camelCase; any other name fails the drift guard.
- **`plan` prescribes `Refs #6109`, not `Closes`** — #6109 must stay OPEN so the nudged
  human can re-evaluate. `ship` authors the PR body; ensure it uses `Refs`.
- **Route array insertion point**: `cron-6109-*` sorts before `cron-agent-native-audit`
  (`6 < a`) in the alphabetical import/array blocks.

## Skill / AGENTS.md budget

N/A — no `SKILL.md description:` edit and no new AGENTS.md rule.
