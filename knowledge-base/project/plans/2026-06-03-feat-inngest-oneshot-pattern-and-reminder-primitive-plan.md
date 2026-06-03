---
title: "feat: Encode the self-armed Inngest oneshot pattern + a generic reminder primitive"
date: 2026-06-03
branch: feat-one-shot-inngest-reminder-primitive
type: feat
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: false
references: ["#2714"]
opens_no_issue_to_close: true
---

# feat: Encode the self-armed Inngest oneshot pattern + a generic reminder primitive

> Note: this branch has no `spec.md`. `lane:` defaulted to `cross-domain` (TR2 fail-closed) —
> the change spans `apps/web-platform/server` (code), `app/api` (route), `knowledge-base/engineering`
> (docs), and `plugins/soleur/skills` (skill pointers).

## Enhancement Summary

**Deepened on:** 2026-06-03
**Halt gates cleared:** 4.6 User-Brand Impact (threshold `single-user incident`), 4.7 Observability
(5-field schema, no-SSH discoverability), 4.8 PAT-shaped (no match), 4.9 UI-wireframe (non-UI, skipped),
4.5 Network-outage (no diagnosis trigger, skipped).

### Key Improvements (deepen pass)
1. **CORRECTION:** `EXEMPT_ROUTES` is in `lib/auth/csrf-coverage.test.ts` (a TEST file) and keys on the
   **relative route-file path** `app/api/internal/schedule-reminder/route.ts`, NOT the URL path. Files-to-Edit
   + Phase 3 step 8 fixed.
2. Confirmed the precedent-diff vs `oneshot-4650`: novel-pattern-free except the endpoint-armed (not
   boot-armed) delivery, the discriminated-union action, and the ISO-instant date guard.
3. Verified the two load-bearing negatives (token-never-returned at oneshot-4650:143; no-send-before-secret
   at trigger-cron:63-133) and the `sendInngestWithRetry(fn, {feature,...})` signature.

### New Considerations Discovered
- The CSRF gate fires mechanically on any new `POST` route (`mutatingMethodRe`) — the relative-path
  exemption is non-optional, not just a nicety.
- The endpoint MAY pass `eventId: reminder_id` to `sendInngestWithRetry` for log correlation (optional).

## Overview

The codebase schedules one-time, future-dated, server-side verifications via **self-armed Inngest
oneshots**: a function triggered by a `oneshot/*.fire` event, armed at container boot in
`apps/web-platform/server/index.ts` via `inngest.send({ name, id, ts, data })` with a **future `ts`**;
Inngest natively schedules the delayed delivery (no `step.sleepUntil`). ADR-046 codifies the
self-arm-at-boot + registered-functions-only decision; ADR-033 codifies the cron/oneshot runtime
invariants (IO inside `step.run`, deterministic step returns, operator-token-only / no-BYOK,
`actor:"platform"` on emitted events, **NO Sentry cron monitor** for oneshots).

The pattern is **used 5×** today (`oneshot-4650-monitor-close`, `oneshot-gdpr-gate-50d-eval`,
`oneshot-f2-defer-gate-review`, `oneshot-recheck-4217-calibration`, `oneshot-heartbeat-recovery-verify`)
but is **undocumented as a reusable approach** and is **hand-copied** each time: a new function file
+ a `app/api/inngest/route.ts` registration + a `server/index.ts` boot-arm + a
`function-registry-count.test.ts` count bump. Each new author reverse-engineers it from a prior file.

This is a **tooling/capability improvement, not a bug fix**. It is **strictly additive**: the 5 existing
bespoke oneshots and every `cron-*.ts` are **untouched**. It delivers two parts:

- **Part A** — *Encode the existing pattern*: a reference doc (decision matrix + 3 integration points +
  gotchas), a copy-fill `.ts.template` scaffold mirroring `oneshot-4650`, and skill pointers wired into
  `/ship` Step 3.5.B and `/soleur:schedule`.
- **Part B** — *Generic reminder primitive*: a single new Inngest function
  (`event-scheduled-reminder.ts`, triggered by `reminder.scheduled`) with an **allowlisted discriminated-union
  action** (`issue-comment` | `named-check`), a server-side `CHECK_REGISTRY`, an internal secret-authed
  emit endpoint (`POST /api/internal/schedule-reminder`) mirroring `trigger-cron`, and TDD tests. After
  Part B, a future-dated comment or a registered check fires **without a per-reminder deploy** — only the
  one-time function deploy.

The canonical precedent every artifact mirrors is
`apps/web-platform/server/inngest/functions/oneshot-4650-monitor-close.ts`.

## Premise Validation

- `#2714` (cited "for lineage" / "context only") — `gh issue view 2714` → **CLOSED**, title
  `ops: scheduled-content-generator workflow not firing since 2026-03-24`. The ARGUMENTS use it as a
  **tracking/lineage reference only**, not a close target; `oneshot-heartbeat-recovery-verify.ts:37`
  already posts verdicts to it. A closed reference does not invalidate this plan — the plan **opens no
  issue to close** and emits no `Closes #N`. PR body uses `references #2714`, never `Closes`.
- The 5 named bespoke oneshots all exist on disk (verified `ls` of
  `apps/web-platform/server/inngest/functions/`) and are registered in `route.ts` — all remain
  **untouched** (additive constraint).
- `oneshot-heartbeat-recovery-verify.ts` exists and is **already armed** in `server/index.ts` (boot block,
  fires 2026-06-04) — the plan does **NOT** migrate it into the new registry (explicit ARGUMENTS constraint).
- ADR-033 (`...ADR-033-inngest-cron-functions-invoke-claude-code-via-child-process-spawn.md`) and ADR-046
  (`...ADR-046-inngest-oneshot-scheduler-self-arm-and-registered-only.md`) both exist on disk.
- `INNGEST_MANUAL_TRIGGER_SECRET` is the existing operator-held secret powering `trigger-cron` — reused,
  not newly minted (no IaC change, see `## Infrastructure (IaC)`).

No external premises require re-scoping.

## Research Reconciliation — Spec vs. Codebase

| Claim (ARGUMENTS) | Codebase reality (verified) | Plan response |
|---|---|---|
| Pattern armed in `server/index.ts` via `inngest.send` future `ts` | Confirmed: `server/index.ts:133-194` arms 2 oneshots inside `if (process.env.INNGEST_SIGNING_KEY)` guarded `void (async()=>{try…catch})()` blocks, `ts: new Date(...).getTime()` | Reminder primitive is **endpoint-armed**, not boot-armed — so NO `server/index.ts` edit for Part B. The doc/template cover the boot-arm path for *bespoke* oneshots. |
| `function-registry-count.test.ts` bump | Confirmed: `route.ts` array currently **49** entries; test `(a)` hard-asserts `toBe(49)` | Bump to **50** for `eventScheduledReminder`. |
| Mirror `trigger-cron` auth exactly | Confirmed: `trigger-cron/route.ts` uses `readSecret()` + `bearerMatches()` (length-guarded `timingSafeEqual`), `503` when secret unset, `401` on mismatch, `413`/`400` body guards, dynamic client import | `schedule-reminder/route.ts` copies this shape verbatim; differs only in event name + payload validation. |
| Add path to `PUBLIC_PATHS` | Confirmed: `lib/routes.ts` `PUBLIC_PATHS` already lists `/api/internal/kb-drift-ingest` and `/api/internal/trigger-cron` with narrow exact-match comments | Add `/api/internal/schedule-reminder` as a NARROW exact entry + `middleware.test.ts` membership assertion. |
| `reportSilentFallback(error)` on `verdict==="fail"` | Confirmed signature: `reportSilentFallback(err, { feature, op, message?, extra? })` at `server/observability.ts:183` | Pass an `Error`, route via the existing helper. |
| New POST route trips CSRF coverage gate | Per learning `2026-06-01-new-internal-api-route-needs-public-paths-registration.md` §Session Errors #3: `lib/auth/csrf-coverage.test.ts` requires every mutating route to `validateOrigin` or be in `EXEMPT_ROUTES` | Add `/api/internal/schedule-reminder` to `EXEMPT_ROUTES` (secret-auth, cookieless — same class as `trigger-cron`/`kb-drift-ingest`). **Decided at plan time** per the learning's prevention note. |

## User-Brand Impact

**If this lands broken, the user experiences:** a scheduled GitHub issue comment that never posts (a
silently-dropped reminder), or — worse — a malformed/over-permissive `action` that posts to the **wrong
issue** or runs an unintended check. Because the primitive writes to the operator's GitHub repo via the
installation token, a broken allowlist could surface operator-visible repo noise.

**If this leaks, the user's workflow is exposed via:** the `INNGEST_MANUAL_TRIGGER_SECRET`-gated endpoint.
A secret-holder gains the **same capability the operator already has** (`gh issue comment` / a registered
check) — time-delayed. The named-check dispatch is **allowlisted to code-reviewed registered functions
only**; it does NOT accept arbitrary code. Comments are non-mutating + reversible; **no issue
close/edit/label mutation in v1**.

**Brand-survival threshold:** `single-user incident` — the endpoint → installation-token → GitHub-write
boundary is the abuse surface (identical class to `trigger-cron`, which is already gated at this threshold).
The security model (allowlist completeness + secret as the trust boundary) is the load-bearing mitigation;
`security-sentinel` MUST scrutinize it at review (see `## Domain Review`). Note: `requires_cpo_signoff`
is `false` because this primitive grants **no new capability** beyond what the operator already holds via
`trigger-cron` + manual `gh` — it is a time-delay shim over an existing authorized surface, reviewed by
security-sentinel rather than CPO. (If review judges the allowlist materially widens capability, escalate.)

## Infrastructure (IaC)

**No new infrastructure.** The endpoint reuses the **existing** `INNGEST_MANUAL_TRIGGER_SECRET`
(TF-generated `random_id`, Doppler-provisioned, already consumed by `trigger-cron`). No new secret, server,
systemd unit, cron, DNS record, vendor account, or firewall rule. The reminder function runs on the
already-provisioned Inngest substrate (ADR-030/033). Part B is endpoint-armed (no boot-arm), so no
`server/index.ts` edit and no new persistent runtime process.

→ **IaC gate: skipped (pure code change against an already-provisioned surface).**

## Observability

```yaml
liveness_signal:
  what: "event-scheduled-reminder is a oneshot-class function — per ADR-033 I3 it gets NO Sentry cron monitor (a non-recurring fn false-alerts on missed check-ins). Liveness for a SPECIFIC reminder is the reminder's own action effect (the issue comment appears, or the named-check posts its body)."
  cadence: "per-reminder (event-driven, not periodic)"
  alert_target: "Sentry (reportSilentFallback) on any failure inside step.run; the endpoint's 202 confirms the arm was accepted (mirrors the trigger-cron 202 contract)."
  configured_in: "server/observability.ts reportSilentFallback (feature: event-scheduled-reminder); endpoint returns 202 on inngest.send success, 502 on dispatch failure."
error_reporting:
  destination: "Sentry via reportSilentFallback / warnSilentFallback (feature: 'event-scheduled-reminder' for the handler, 'schedule-reminder' for the endpoint)"
  fail_loud: "yes — guard rejections (invalid fire_at, non-allowlisted action, unregistered check, body cap) reportSilentFallback + return a deterministic {ok:false, reason} union; named-check verdict==='fail' routes reportSilentFallback at error level."
failure_modes:
  - { mode: "invalid fire_at (NaN / non-ISO)", detection: "Date.parse guard in handler AND endpoint", alert_route: "reportSilentFallback op:invalid-fire-at; handler returns {ok:false,reason:'invalid-fire-at'}; endpoint 400" }
  - { mode: "action.type not allowlisted", detection: "discriminated-union exhaustive switch default arm in handler AND endpoint", alert_route: "reportSilentFallback op:action-not-allowlisted; handler returns {ok:false,reason:'action-not-allowlisted'}; endpoint 400" }
  - { mode: "named-check not in CHECK_REGISTRY", detection: "registry lookup miss in handler AND endpoint", alert_route: "reportSilentFallback op:unregistered-check; handler returns {ok:false,reason:'unregistered-check'}; endpoint 400" }
  - { mode: "named-check verdict==='fail'", detection: "verdict branch after running the registered check", alert_route: "reportSilentFallback op:named-check-failed (error level) + comment still posted to report_to_issue" }
  - { mode: "issue-comment body over cap (>65000) or empty / issue not positive int", detection: "length + integer guards in handler AND endpoint", alert_route: "reportSilentFallback op:invalid-issue-comment; handler {ok:false}; endpoint 400" }
  - { mode: "endpoint secret unset / wrong", detection: "readSecret()/bearerMatches() (mirrors trigger-cron)", alert_route: "503 (unset) / 401 (wrong) — no Sentry (auth failure is expected noise)" }
  - { mode: "inngest.send dispatch failure", detection: "try/catch around sendInngestWithRetry in endpoint", alert_route: "reportSilentFallback op:dispatch; endpoint 502" }
  - { mode: "lost boot-arm (bespoke oneshots only — N/A for the primitive)", detection: "guarded IIFE catch in server/index.ts", alert_route: "reportSilentFallback feature:<oneshot>-arm — documented in the reference doc as the ONLY lost-arm signal under I3" }
logs:
  where: "pino (container stdout → Better Stack) mirrored by reportSilentFallback; Sentry issues"
  retention: "per existing Sentry/Better Stack retention (unchanged)"
discoverability_test:
  command: "cd apps/web-platform && ./node_modules/.bin/vitest run test/server/inngest/event-scheduled-reminder.test.ts test/server/internal/schedule-reminder-route.test.ts test/middleware.test.ts test/server/inngest/function-registry-count.test.ts"
  expected_output: "all suites pass; function-registry-count (a) asserts 50; middleware asserts /api/internal/schedule-reminder is public; handler tests exercise every action arm + every reject path; endpoint tests assert 401/202/400."
```

## Deepen-Plan Verifications (2026-06-03)

Live-grep verifications run during the deepen pass (precedent-diff Phase 4.4 + verify-the-negative pass):

- **Precedent diff vs `oneshot-4650-monitor-close.ts`** (pattern-bound: self-armed oneshot shape) —
  the reminder function mirrors it exactly except: (a) **endpoint-armed, not boot-armed** (no
  `server/index.ts` edit; the future-`ts` arm happens in the endpoint's `inngest.send`); (b) the **action
  is a discriminated union** vs oneshot-4650's fixed close logic; (c) the date guard validates an **ISO
  instant** (`Date.parse`) vs oneshot-4650's `YYYY-MM-DD` (`isValidYmd`). All other invariants
  (guards-first, token-minted-in-step-never-returned, deterministic `{ok,reason}`, `cron-platform`
  concurrency, `retries:1`, NO Sentry monitor) are copied verbatim. **No novel pattern.**
- **verify-the-negative: "token minted inside step.run and never returned"** — confirmed at
  `oneshot-4650-monitor-close.ts:143` (`// Token is minted+used inside the step and NOT returned`); the
  token never appears in any `return` of a `step.run` callback. The reminder function adopts the same shape.
- **verify-the-negative: "no path reaches inngest.send without the secret"** (AC-S1) — `trigger-cron`
  returns at `503`/`401` BEFORE any `inngest.send`; the dynamic client import is INSIDE the post-auth
  `try` block. The reminder endpoint copies this ordering. Confirmed `trigger-cron/route.ts:63-133`.
- **`EXEMPT_ROUTES` shape (CORRECTION)** — lives in **`lib/auth/csrf-coverage.test.ts:14`** (a TEST file,
  not a source module) and keys on the **relative route-file path** (`filePath.split("/apps/web-platform/")[1]`),
  e.g. `"app/api/internal/trigger-cron/route.ts"` — NOT the URL path. Plan Files-to-Edit + Phase 3 step 8
  corrected accordingly. The gate `mutatingMethodRe = /export\s+(async\s+)?function\s+(POST|...)/` fires on
  the new `POST` route → the relative-path exemption is mandatory or the suite reddens.
- **`sendInngestWithRetry(fn, context)` signature** — confirmed `send-with-retry.ts:29`: second arg is
  `{ feature: string; deliveryId?: string | null; eventId?: string }`. Plan's `{ feature: "schedule-reminder" }`
  is valid; `eventId: reminder_id` MAY be added for log correlation (optional).
- **Test dirs exist** — `test/server/internal/` (endpoint test), `test/server/inngest/` (handler test),
  `test/middleware.test.ts`, `test/server/inngest/function-registry-count.test.ts` all present. The
  discoverability_test command paths are real.
- **route.ts count = 49** confirmed (`grep -cE '^\s+\w+,$'`) → bump to **50**.

## Research Insights

- **Canonical precedent** `apps/web-platform/server/inngest/functions/oneshot-4650-monitor-close.ts`:
  guards-first (date validity → identity → date guard), then `step.run` blocks each minting their **own**
  token (`mintInstallationToken({ tokenMinLifetimeMs })` from `_cron-shared.ts`) and **never returning**
  it into step state; deterministic `{ ok, reason }` union returns; `inngest.createFunction({ id,
  concurrency:[{scope:"fn",limit:1},{scope:"account",key:'"cron-platform"',limit:1}], retries:1 }, {
  event: "oneshot/*.fire" }, handler as unknown as Parameters<...>[2])`.
- **Token mint helper** `_cron-shared.ts:99 mintInstallationToken({ tokenMinLifetimeMs })` →
  installation token via `createProbeOctokit` + `generateInstallationToken`. `REPO_OWNER="jikig-ai"`,
  `REPO_NAME="soleur"`, `type HandlerArgs` (event?/step/logger) all exported there.
- **Octokit usage** inside `step.run`: `const { Octokit } = await import("@octokit/core"); const octokit =
  new Octokit({ auth: token });` then `octokit.request("POST /repos/{owner}/{repo}/issues/{issue_number}/comments", {...})`.
- **Endpoint precedent** `app/api/internal/trigger-cron/route.ts`: `readSecret()` (env or null),
  `bearerMatches(header, secret)` (strips optional `Bearer `, length-guard before `timingSafeEqual`),
  `503` if secret unset, `401` if mismatch, `MAX_BODY_BYTES = 64*1024` → `413`, `JSON.parse` → `400`,
  **dynamic** `await import("@/server/inngest/client")`, `sendInngestWithRetry(() => inngest.send(...), {
  feature })`, `202` on success / `502` on dispatch error. Route-controlled keys spread LAST.
- **PUBLIC_PATHS** `lib/routes.ts:5` — narrow exact entries with rationale comments; `trigger-cron` +
  `kb-drift-ingest` precedents. `middleware.test.ts:6 isPublicPath` = `pathname===p || startsWith(p+"/")`.
- **function-registry-count.test.ts** — `(a)` asserts `routeEntries.length === 49` via
  `routeSrc.matchAll(/^\s+(\w+),$/gm)`. The new `eventScheduledReminder` import + array entry brings it to
  **50**. Guards `(b)`/`(e)` are **cron-only** (`startsWith("cron-")`) so they do NOT trip on a new
  `event-*.ts` file. The new function is NOT a cron — no Sentry monitor, no `KNOWN_UNMONITORED_SLUGS`
  entry, no `cron-monitors.tf` resource.
- **Naming precedent**: `event-cf-token-expiry-check.ts` → `eventCfTokenExpiryCheck`,
  `event-ship-merge.ts` → `eventShipMerge`. So `event-scheduled-reminder.ts` → `eventScheduledReminder`,
  registered between `eventShipMerge` and `githubOnEvent` (alpha-ish ordering preserved).
- **Test pattern** `oneshot-4650-monitor-close.test.ts`: `vi.hoisted` spies for
  `reportSilentFallback`/`warnSilentFallback`/`mintInstallationToken`; `vi.mock("@octokit/core", …)` uses
  the **`function`-keyword constructor mock** (vitest 4 `new`-construct requirement — arrow throws "is not
  a constructor"); a hand-rolled `makeStep()` that records `step.run` names and awaits the callback.
- **Endpoint test pattern** `trigger-cron-route.test.ts`: capture+restore `ORIG_SECRET` in
  `beforeEach`/`afterEach` (security-relevant env — never leak a stub to a sibling file), `vi.mock`
  `send-with-retry` + `observability` + `inngest/client`, `makeRequest(body, {authorization})` helper.
- **CSRF gate**: per learning `2026-06-01-new-internal-api-route-needs-public-paths-registration.md`, a new
  mutating POST route trips `lib/auth/csrf-coverage.test.ts` → add to `EXEMPT_ROUTES` (secret-auth class).
- **`cq-nextjs-route-files-http-only-exports`**: route files export only HTTP verbs. The shared
  action-validator + `CHECK_REGISTRY` live in a **non-route module** so both the route and the handler can
  import them (defense-in-depth: validate the action shape at BOTH the endpoint and the handler).
- **Test runner**: vitest, NOT bun. `cd apps/web-platform && ./node_modules/.bin/vitest run <paths>` +
  `./node_modules/.bin/tsc --noEmit`. Test files MUST live under `test/**/*.test.ts` (vitest `include`
  glob) — co-located component tests are silently skipped.
- **Known flake**: `test/server/inngest/signature-verify*.test.ts` has a pre-existing cross-file
  `NEXT_PHASE` env-leak that is green on retry/isolation — do NOT chase as a regression; verify new tests
  pass in isolation (run the specific new test paths, not the whole `test/server/inngest/` dir unsharded).

## Architecture (shapes the work, not load-bearing prose)

```
                              POST /api/internal/schedule-reminder
                              (Bearer INNGEST_MANUAL_TRIGGER_SECRET)
 operator / agent ──curl──▶   [validateScheduleReminderBody]  ──202──▶ inngest.send({
                              (defense-in-depth: same allowlist)         name:"reminder.scheduled",
                                                                          id: reminder_id,
                                                                          ts: Date.parse(fire_at),
                                                                          data })
                                                                                │ (future ts → delayed delivery)
                                                                                ▼
                              event-scheduled-reminder.ts  ◀────── reminder.scheduled
                              guards FIRST (fire_at real date, action allowlist, numeric issue)
                                  │
                                  ├─ action.type "issue-comment" ─▶ step.run: mint token, POST comment
                                  └─ action.type "named-check"    ─▶ step.run: mint token,
                                                                       CHECK_REGISTRY[check](octokit, params)
                                                                       → post body to report_to_issue
                                                                       → verdict==="fail" ⇒ reportSilentFallback
```

Shared, route-importable module (`lib/inngest/scheduled-reminder-action.ts` — kept in `lib/` per the
route-files-http-only rule, mirroring `lib/inngest/manual-trigger-allowlist.ts`):

```ts
// Discriminated union, allowlisted. Any other `type` is rejected.
export type ReminderAction =
  | { type: "issue-comment"; issue: number; body: string }
  | { type: "named-check"; check: string; params?: Record<string, unknown>; report_to_issue: number };

export const MAX_COMMENT_BODY = 65000;

// Returns { ok: true; action } | { ok: false; reason }. Used by BOTH the endpoint
// (pre-send 400) and the handler (post-receive guard) — defense-in-depth.
export function validateReminderAction(raw: unknown): ValidateResult;

export interface ReminderEventData {
  reminder_id: string;
  fire_at: string;          // ISO; validated real date
  actor: "platform";
  action: ReminderAction;
}
```

```ts
// CHECK_REGISTRY — server-side, code-reviewed only. Seeded with ONE demonstrator
// so the registry mechanism is exercised by a test. Lives in the function module
// (server-only; uses octokit). NOT imported by the route (route validates `check`
// is a non-empty string only; the handler does the registry lookup).
type CheckFn = (
  octokit: OctokitClient,
  params: Record<string, unknown> | undefined,
) => Promise<{ verdict: "pass" | "fail" | "info"; body: string }>;

export const CHECK_REGISTRY: Record<string, CheckFn> = {
  // Trivial, safe demonstrator: how many cloud-task-silence issues are open.
  // Read-only; no mutation. Exercises the registry lookup + verdict path in a test.
  "open-silence-issue-count": async (octokit) => { /* GET issues?labels=cloud-task-silence&state=open */ },
};
```

> **Registry scope (v1, explicit):** `report_to_issue` is the only issue the named-check writes to. The
> demonstrator does NOT migrate `oneshot-heartbeat-recovery-verify` (already armed — ARGUMENTS constraint).

## Implementation Phases

### Phase 0 — Preconditions (verify, no code)

- Confirm `route.ts` array length is **49** (`grep -cE '^\s+\w+,$' app/api/inngest/route.ts`).
- Confirm `INNGEST_MANUAL_TRIGGER_SECRET` is the secret `trigger-cron` reads (`grep -n
  INNGEST_MANUAL_TRIGGER_SECRET app/api/internal/trigger-cron/route.ts`).
- Confirm `EXEMPT_ROUTES` location: `grep -rn "EXEMPT_ROUTES" apps/web-platform/lib/auth/`.
- Re-read `oneshot-4650-monitor-close.ts` + `.test.ts` as the structural template.

### Phase 1 — Part B: shared action module + RED tests (TDD)

1. **Create** `apps/web-platform/lib/inngest/scheduled-reminder-action.ts` — the `ReminderAction` union,
   `MAX_COMMENT_BODY = 65000`, `validateReminderAction(raw)` (exhaustive switch; default arm rejects),
   `ReminderEventData` type. Validation rules:
   - `issue-comment`: `issue` positive integer, `body` non-empty string, `body.length <= 65000`.
   - `named-check`: `check` non-empty string, `report_to_issue` positive integer, `params` (if present)
     a plain object.
   - any other `type` → `{ ok: false, reason: "action-not-allowlisted" }`.
2. **Create RED** `apps/web-platform/test/server/inngest/event-scheduled-reminder.test.ts` and
   `apps/web-platform/test/server/internal/schedule-reminder-route.test.ts` and the
   `middleware.test.ts` + `function-registry-count.test.ts` additions (see `## Test Scenarios`). These
   fail because the SUT does not exist yet.

### Phase 2 — Part B: the Inngest function (GREEN)

3. **Create** `apps/web-platform/server/inngest/functions/event-scheduled-reminder.ts`:
   - File header comment mirroring `oneshot-4650`: ADR-046 self-arm context (NOTE: endpoint-armed, not
     boot-armed), ADR-033 invariants I1/I2/I5/I6, NO Sentry monitor, token-minted-inside-step.
   - `FUNCTION_NAME = "event-scheduled-reminder"`.
   - `isValidIsoInstant(s)`: `!Number.isNaN(Date.parse(s))` AND round-trips (reject `"not-a-date"`).
   - `CHECK_REGISTRY` seeded with `open-silence-issue-count` (read-only demonstrator).
   - Handler `eventScheduledReminderHandler({ event, step })`:
     a. **Guards FIRST** (mirror oneshot-4650 ordering): validate `fire_at` real date → run
        `validateReminderAction(event.data.action)` → on any reject, `reportSilentFallback` + return
        deterministic `{ ok:false, reason }`. (Numeric-issue / body-cap live inside `validateReminderAction`.)
     b. `issue-comment` → `step.run("post-comment", …)`: mint token, `new Octokit`, POST comment to
        `action.issue`. Token NOT returned.
     c. `named-check` → `step.run("run-check", …)`: mint token, `new Octokit`, look up
        `CHECK_REGISTRY[action.check]` → if missing, `reportSilentFallback` + return `{ ok:false,
        reason:"unregistered-check" }`; else run it, POST `result.body` to `action.report_to_issue`, and if
        `result.verdict === "fail"` → `reportSilentFallback(new Error(...))` at error level. Return
        `{ ok:true, reason:"named-check-<verdict>" }`.
   - Export `eventScheduledReminder = inngest.createFunction({ id:"event-scheduled-reminder",
     concurrency:[{scope:"fn",limit:1},{scope:"account",key:'"cron-platform"',limit:1}], retries:1 }, {
     event: "reminder.scheduled" }, handler as unknown as Parameters<typeof inngest.createFunction>[2])`.
   - Export `CHECK_REGISTRY` and the handler for tests.

   > **Registry membership — single source of truth.** The route validates `check` is a non-empty string
   > only (it must not import the server-only `CHECK_REGISTRY`, which pulls octokit). The **handler** owns
   > the registry-membership reject. This is acceptable defense-in-depth asymmetry: an unregistered check
   > armed via the endpoint is accepted at the door (202) but rejected at fire time (`reportSilentFallback`
   > + no-op). Document this in the function header so the asymmetry is intentional, not a gap.

4. **Register** in `app/api/inngest/route.ts`: add `import { eventScheduledReminder } from
   "@/server/inngest/functions/event-scheduled-reminder";` and add `eventScheduledReminder,` to the
   `functions: [...]` array (place near the other `event*` entries).
5. **Bump** `function-registry-count.test.ts` `(a)` from `49` → `50`.

### Phase 3 — Part B: the internal emit endpoint (GREEN)

6. **Create** `apps/web-platform/app/api/internal/schedule-reminder/route.ts` — mirror `trigger-cron`
   exactly:
   - `readSecret()` (env `INNGEST_MANUAL_TRIGGER_SECRET` or null), `bearerMatches()` (length-guarded
     `timingSafeEqual`), `503` unset / `401` mismatch, `MAX_BODY_BYTES = 64*1024` → `413`, `JSON.parse`
     → `400`, dynamic `await import("@/server/inngest/client")`.
   - Validate the body: `reminder_id` non-empty string, `fire_at` a real ISO date (`Date.parse` not NaN),
     `actor === "platform"`, and `validateReminderAction(body.action).ok === true` (defense-in-depth — same
     allowlist as the handler) → else `400`. The route does NOT check `CHECK_REGISTRY` membership (server-
     only module); it validates `check` is a non-empty string via `validateReminderAction`.
   - `sendInngestWithRetry(() => inngest.send({ name: "reminder.scheduled", id: reminder_id, ts:
     Date.parse(fire_at), data: { reminder_id, fire_at, actor: "platform", action } }), { feature:
     "schedule-reminder" })` → `202 { scheduled: reminder_id, fire_at }` on success / `502` on dispatch
     error (`reportSilentFallback op:dispatch`).
   - **HTTP-verb-only export** (`cq-nextjs-route-files-http-only-exports`): only `POST`. The validator
     lives in `lib/inngest/scheduled-reminder-action.ts`.
7. **Add** `/api/internal/schedule-reminder` to `PUBLIC_PATHS` in `lib/routes.ts` as a NARROW exact entry
   with a rationale comment (cookieless secret-authed; same class as `trigger-cron` — cite
   `2026-06-01-new-internal-api-route-needs-public-paths-registration.md`). Do NOT broaden to
   `/api/internal`.
8. **Add** the **relative route-file path** `app/api/internal/schedule-reminder/route.ts` to the
   `EXEMPT_ROUTES` set in `apps/web-platform/lib/auth/csrf-coverage.test.ts` (NOT the URL path — the gate
   keys on `filePath.split("/apps/web-platform/")[1]`, e.g. the existing entry is
   `"app/api/internal/trigger-cron/route.ts"`), with a justification comment (secret-auth, cookieless —
   same class as `trigger-cron`/`kb-drift-ingest`). This is a **test file**, not a source module — the
   exemption list is maintained inline in the test (`csrf-coverage.test.ts:14`). [verified 2026-06-03:
   `EXEMPT_ROUTES` at `lib/auth/csrf-coverage.test.ts:14`; relativePath split at :48.]
9. **Add** `middleware.test.ts` membership assertion `expect(isPublicPath("/api/internal/schedule-reminder")).toBe(true)`
   + a prefix-collision assertion that the bare `/api/internal` parent stays private.

### Phase 4 — Part A: docs + scaffold template + skill pointers

10. **Create reference doc** `knowledge-base/engineering/ops/runbooks/inngest-oneshot-and-reminder-patterns.md`
    (alongside the other ops runbooks; cross-linked from ADR-046's "Consequences"). Contents:
    - **(a) Decision matrix** "I need a future-dated action": columns = mechanism / autonomous? / needs
      deploy? / fire-time secrets? / repo-write? / dies-with-session? / when-to-use. Rows:
      1. **session cron** — fragile, dies with the session; never for durable tasks.
      2. **GitHub-Actions follow-through sweeper** (`scripts/sweep-followthroughs.sh`) — needs a script +
         `earliest`; operator/CI-driven; no fire-time Doppler secret. (Cross-link `/ship` Step 3.5.)
      3. **self-armed Inngest oneshot** — autonomous, server-side, full prd env + App token; needs a
         **deploy per oneshot** (new reviewed file). (ADR-046.)
      4. **generic reminder primitive** (Part B) — autonomous, server-side; **no deploy per reminder**
         (only the one-time function deploy); arm via `POST /api/internal/schedule-reminder`. Use for
         one-off issue comments + registered checks; use a bespoke oneshot when the logic is non-trivial /
         not expressible as a registered check.
    - **(b) The 3 integration points for a bespoke oneshot**: (1) new `oneshot-*.ts` function file; (2)
      register in `app/api/inngest/route.ts` `functions:` array; (3) self-arm in `server/index.ts` boot
      block — PLUS the `function-registry-count.test.ts` `(a)` count bump (the "4th, easy-to-forget" step).
    - **(c) Gotchas**: stable event `id` for dedup (bounded ~24h window — NOT the idempotency guarantee;
      ADR-046 I2); future-`ts` delivery + the **"late re-deploy past `ts` re-fires (degrades gracefully)"**
      edge (the handler's load-bearing state check is the cross-boot idempotency); **NO Sentry monitor**
      (ADR-033 I3 / ADR-046 I3 — the self-arm catch in the guarded boot IIFE is the **only lost-arm
      signal**); token **minted inside `step.run` and never returned** into persisted step state.
    - Link the scaffold template (below) and ADR-033 + ADR-046.
11. **Create scaffold template**
    `apps/web-platform/server/inngest/functions/oneshot-TEMPLATE.ts.template` — a commented copy-fill
    mirroring `oneshot-4650-monitor-close.ts`: header block with ADR citations, `FUNCTION_NAME`,
    `isValidYmd` guard, `EventData`, guards-first handler skeleton with `// FILL:` markers, `step.run`
    token-mint-inside pattern, deterministic `{ ok, reason }` returns, `inngest.createFunction` export with
    the `oneshot/<name>.fire` event + `cron-platform` concurrency. A `// === ALSO DO (the 3 integration
    points) ===` trailer enumerating the route.ts registration, the server/index.ts boot-arm snippet, and
    the function-registry-count bump.
    - **Extension `.ts.template`** (not `.ts`) so it is NOT picked up by `tsc`/vitest/route-registry
      globs. Verify: `function-registry-count.test.ts` `listCronFiles()` filters `cron-` prefix +
      `.ts` suffix — a `.ts.template` file is excluded; confirm at GREEN that the count test still passes.
12. **Wire `/ship` Step 3.5.B** (`plugins/soleur/skills/ship/SKILL.md` ~line 1624): add two **autonomous
    (no-operator, no-GH-Actions)** verification-pattern bullets after the existing list:
    - *Self-armed Inngest oneshot* — for fire-time-secret / repo-write one-off verifications; ship a
      reviewed `oneshot-*.ts` + boot-arm (ADR-046). Link the new runbook.
    - *Generic reminder primitive* — for a one-off issue comment or a registered check with **no deploy**;
      arm via `POST /api/internal/schedule-reminder`. Link the runbook.
    - Keep the addition tight (these are routing pointers, not instructions) — no SKILL.md `description:`
      edit, so no budget impact (see `## Skill Description Budget`).
13. **Wire `/soleur:schedule`** (`plugins/soleur/skills/schedule/SKILL.md`): in the "When to use this skill
    vs harness `schedule`" section, add a note that this skill does **GH-Actions cron only**; for a
    **one-time autonomous server-side action** (fire-time secrets, repo writes) point to the self-armed
    Inngest oneshot (ADR-046) / the generic reminder primitive + link the runbook. No `description:` edit.

### Phase 5 — Verify

14. `cd apps/web-platform && ./node_modules/.bin/vitest run` the 4 new/changed test paths **in isolation**
    (NOT the whole `test/server/inngest/` dir — avoid the `signature-verify` env-leak flake).
15. `./node_modules/.bin/tsc --noEmit`.
16. Confirm the 5 existing oneshots + all `cron-*.ts` are byte-identical (`git diff --stat` shows only the
    intended additions/edits).

## Acceptance Criteria

### Pre-merge (PR)

- [ ] **AC1** `apps/web-platform/server/inngest/functions/event-scheduled-reminder.ts` exists; handler
      validates guards FIRST (real `fire_at` → action allowlist), does all IO inside `step.run`, mints the
      token inside the step and never returns it, returns a deterministic `{ ok, reason }` union, has NO
      Sentry monitor and no `cron-monitors.tf` resource.
- [ ] **AC2** `action` is a discriminated union allowlisted to `issue-comment` | `named-check`; any other
      `type` is rejected with `reportSilentFallback` + `{ ok:false, reason:"action-not-allowlisted" }`
      (handler test) and `400` (endpoint test).
- [ ] **AC3** `issue-comment` posts a comment via installation token; rejects non-positive `issue`, empty
      `body`, and `body.length > 65000`.
- [ ] **AC4** `named-check` looks up `CHECK_REGISTRY`; unregistered `check` → reject (`reportSilentFallback`
      + `{ ok:false, reason:"unregistered-check" }`); registered → posts `body` to `report_to_issue`;
      `verdict==="fail"` routes `reportSilentFallback` at error level. Registry is seeded with exactly one
      demonstrator (`open-silence-issue-count`) exercised by a test.
- [ ] **AC5** `app/api/inngest/route.ts` registers `eventScheduledReminder`; `function-registry-count.test.ts`
      `(a)` asserts **50** and the suite passes (guards b/c/d/e/f untouched — `event-*` is not a cron).
- [ ] **AC6** `app/api/internal/schedule-reminder/route.ts` exists, exports **only** `POST`, mirrors
      `trigger-cron` auth (`503` unset / `401` mismatch / `413` / `400`), validates the body against the
      same action allowlist (defense-in-depth), and on success `inngest.send({ name:"reminder.scheduled",
      id:reminder_id, ts:Date.parse(fire_at), data })` → `202`.
- [ ] **AC7** `/api/internal/schedule-reminder` is in `PUBLIC_PATHS` (narrow exact) AND `EXEMPT_ROUTES`
      (csrf); `middleware.test.ts` asserts `isPublicPath(...)===true` + bare `/api/internal` stays private.
- [ ] **AC8** Reference doc `knowledge-base/engineering/ops/runbooks/inngest-oneshot-and-reminder-patterns.md`
      contains the decision matrix (4 rows), the 3 integration points (+ count-bump), and the 4 gotchas
      (stable `id` dedup, future-`ts` + late-redeploy edge, NO Sentry monitor / self-arm-catch-only signal,
      token-minted-in-step-never-returned).
- [ ] **AC9** Scaffold `oneshot-TEMPLATE.ts.template` exists, mirrors oneshot-4650, has the 3-integration-
      point trailer, and (`.ts.template` extension) does NOT change the route-registry count or trip
      `tsc`/vitest globs.
- [ ] **AC10** `/ship` Step 3.5.B lists the Inngest self-armed oneshot + the generic reminder primitive as
      autonomous options; `/soleur:schedule` notes it is GH-Actions-cron-only and points to the Inngest
      oneshot/reminder. No SKILL.md `description:` edits (budget unaffected).
- [ ] **AC11** The 5 existing oneshots and every `cron-*.ts` are unmodified (`git diff` touches none).
- [ ] **AC12** `tsc --noEmit` clean; the 4 new/changed test paths pass in isolation.

### Security (security-sentinel — review phase, BLOCKING)

- [ ] **AC-S1** The endpoint → installation-token → GitHub-write boundary is gated solely by
      `INNGEST_MANUAL_TRIGGER_SECRET` (length-guarded `timingSafeEqual`); confirm no path reaches
      `inngest.send` without passing the secret check.
- [ ] **AC-S2** The action allowlist is **complete**: no `action.type` other than the two reaches a
      GitHub write; the endpoint AND the handler both reject non-allowlisted actions (defense-in-depth);
      `named-check` dispatches ONLY to `CHECK_REGISTRY` entries (no dynamic/arbitrary code path).
- [ ] **AC-S3** v1 performs no issue close/edit/label mutation — only `POST .../comments` (issue-comment)
      and the registered check's own writes (the demonstrator is read-only).

## Test Scenarios

**Handler** (`test/server/inngest/event-scheduled-reminder.test.ts`, mirror oneshot-4650 mocks):
- happy path `issue-comment` → posts comment, deterministic `{ ok:true }`, token minted inside step.
- happy path `named-check` (registered demonstrator) → runs check, posts body to `report_to_issue`.
- `action.type` not allowlisted → `reportSilentFallback` op:action-not-allowlisted + `{ ok:false }`.
- invalid `fire_at` (`"not-a-date"`) → `reportSilentFallback` + `{ ok:false, reason:"invalid-fire-at" }`.
- unregistered `named-check` → `reportSilentFallback` op:unregistered-check + `{ ok:false }`.
- `named-check` `verdict==="fail"` → `reportSilentFallback` at error level (assert spy called) + comment
  still posted.
- `issue-comment` `body.length > 65000` → rejected; non-positive `issue` → rejected; empty `body` → rejected.

**Endpoint** (`test/server/internal/schedule-reminder-route.test.ts`, mirror trigger-cron-route):
- missing / wrong secret → `401`; secret unset → `503`.
- valid request → emits the event (assert `inngest.send` called with `name:"reminder.scheduled"`,
  `id:reminder_id`, `ts:Date.parse(fire_at)`) → `202`.
- bad action (`type:"label"`) → `400`; invalid `fire_at` → `400`; `actor !== "platform"` → `400`.
- oversize body → `413`; malformed JSON → `400`.

**Middleware** (`test/middleware.test.ts`): `isPublicPath("/api/internal/schedule-reminder")===true`; bare
`/api/internal` stays private.

**Registry count** (`test/server/inngest/function-registry-count.test.ts`): `(a)` asserts `50`.

## Skill Description Budget

No `description:` field is edited (only SKILL.md body pointers in `/ship` and `/soleur:schedule`). Budget
gate (`plugins/soleur/test/components.test.ts`, 1800-word cap) is **not in scope** — skipped.

## Domain Review

**Domains relevant:** Engineering (CTO), Legal/compliance (gated below), Product (NONE — no UI surface).

### Engineering (CTO)

**Status:** reviewed
**Assessment:** Additive server-side primitive on an already-provisioned substrate. The load-bearing
concerns are (1) the new POST route's three cross-cutting gates (PUBLIC_PATHS, csrf EXEMPT_ROUTES, the
registry count bump) — all enumerated in Files to Edit with cited precedent; (2) the route↔handler
defense-in-depth asymmetry on `CHECK_REGISTRY` membership (route can't import the server-only registry) —
documented as intentional; (3) ADR-033/046 invariant fidelity (token-in-step, deterministic returns,
actor:platform, no monitor). Precedent-diff vs `oneshot-4650` runs at deepen-plan Phase 4.4. No new
architecture; mirrors two existing patterns verbatim.

### Product/UX Gate

**Tier:** none
**Decision:** N/A — no UI surface. No file under `components/**`, `app/**/page.tsx`, `app/**/layout.tsx`.
The mechanical UI-surface override did not fire. Pure server/route/docs/skill change.

### Legal / Compliance (gdpr-gate)

**Status:** reviewed (advisory)
**Assessment:** The endpoint adds a new internal API route that emits a `reminder.scheduled` event whose
`action` may POST a `body` to a GitHub issue via the installation token. The body is **operator-supplied**
(no automatic processing of user/session-derived personal data) and writes only to the operator's own repo.
The named-check demonstrator is read-only issue-count metadata. No new regulated-data surface (no schema,
migration, auth flow, or PII processing) — canonical gdpr regex not matched. The single-user-incident
threshold is driven by the **GitHub-write abuse surface** (security, not data-protection). No Article 30
processing-activity change. → gdpr-gate is **advisory, no critical findings**; security-sentinel (not
gdpr-gate) owns the load-bearing review.

## Open Code-Review Overlap

None — verified `gh issue list --label code-review --state open` against the planned file set (the
`event-scheduled-reminder.ts`, `schedule-reminder/route.ts`, `scheduled-reminder-action.ts`,
`lib/routes.ts`, the runbook, the template, and the two SKILL.md files); no open scope-out names them.

## Files to Create

- `apps/web-platform/lib/inngest/scheduled-reminder-action.ts` — `ReminderAction` union,
  `validateReminderAction`, `MAX_COMMENT_BODY`, `ReminderEventData` (route-importable, no octokit).
- `apps/web-platform/server/inngest/functions/event-scheduled-reminder.ts` — the function + `CHECK_REGISTRY`
  + demonstrator.
- `apps/web-platform/app/api/internal/schedule-reminder/route.ts` — secret-authed emit endpoint (POST only).
- `apps/web-platform/server/inngest/functions/oneshot-TEMPLATE.ts.template` — copy-fill scaffold.
- `knowledge-base/engineering/ops/runbooks/inngest-oneshot-and-reminder-patterns.md` — reference doc.
- `apps/web-platform/test/server/inngest/event-scheduled-reminder.test.ts` — handler tests.
- `apps/web-platform/test/server/internal/schedule-reminder-route.test.ts` — endpoint tests.

## Files to Edit

- `apps/web-platform/app/api/inngest/route.ts` — import + register `eventScheduledReminder`.
- `apps/web-platform/test/server/inngest/function-registry-count.test.ts` — `(a)` `49` → `50`.
- `apps/web-platform/lib/routes.ts` — add `/api/internal/schedule-reminder` to `PUBLIC_PATHS` (narrow exact + comment).
- `apps/web-platform/lib/auth/csrf-coverage.test.ts` — add the RELATIVE ROUTE-FILE PATH
  `"app/api/internal/schedule-reminder/route.ts"` to the `EXEMPT_ROUTES` set (keyed on
  `filePath.split("/apps/web-platform/")[1]`, NOT the URL path). Test file, inline list — `csrf-coverage.test.ts:14`.
- `apps/web-platform/test/middleware.test.ts` — PUBLIC_PATHS membership + prefix-collision assertions.
- `plugins/soleur/skills/ship/SKILL.md` — Step 3.5.B autonomous-pattern pointers (body only).
- `plugins/soleur/skills/schedule/SKILL.md` — GH-Actions-cron-only note + Inngest/reminder pointer (body only).

## Non-Goals / Out of Scope

- Migrating any of the 5 existing oneshots (incl. the just-armed `oneshot-heartbeat-recovery-verify`) into
  the new primitive — explicitly forbidden.
- Issue close/edit/label mutation actions (v1 = comment + registered-check only). A future `issue-mutate`
  action would re-trigger the security review and is deferred. → **Deferral tracking:** file a follow-up
  issue only if a concrete consumer appears (YAGNI; no consumer today, so no tracking issue created now per
  `wg-defer-only-after-inline-triage` — the Non-Goal is the record).
- A generalized oneshot scaffolding *skill* / declarative registry (ADR-046 defers to #3990 until consumer
  critical mass) — out of scope; the `.ts.template` is the lightweight substitute.
- A Sentry cron monitor for the reminder function (ADR-033 I3 forbids it for non-recurring functions).

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or
  omits the threshold will fail `deepen-plan` Phase 4.6. (Filled above.)
- The `.ts.template` extension is load-bearing: a plain `.ts` scaffold would be collected by `tsc`,
  vitest, and the `route.ts` registry-count regex (it would fail to compile / register). Confirm at GREEN
  that `listCronFiles()` (`cron-` prefix + `.ts` suffix) excludes it and `(a)` still reads 50.
- The route↔handler `CHECK_REGISTRY` asymmetry (route validates `check` is a string; handler validates
  membership) is intentional defense-in-depth — an unregistered check is accepted at the door (202) but
  rejected at fire time. Document it in the function header so a reviewer does not read it as a gap.
- Do NOT run the full `test/server/inngest/` dir unsharded — the `signature-verify*.test.ts` env-leak
  flake (`NEXT_PHASE`) will appear and is NOT a regression. Run the specific new paths in isolation.
- `function-registry-count.test.ts` guards `(b)`/`(e)` are cron-only; the new `event-*` function must NOT
  be added to `EXPECTED_CRON_FUNCTIONS`, `KNOWN_UNMONITORED_SLUGS`, or `cron-monitors.tf` — doing so would
  trip the parity guards. Only `(a)` changes.

## PR Body (draft)

> **feat: encode the self-armed Inngest oneshot pattern + a generic reminder primitive (additive)**
>
> **The gap.** The codebase schedules one-time future-dated server-side verifications via self-armed
> Inngest oneshots (a `oneshot/*.fire` function armed at container boot with a future `ts`). The pattern is
> used 5× but is undocumented and hand-copied — each new author reverse-engineers it (new function +
> route.ts registration + server/index.ts arm + count-test bump).
>
> **Part A — encode the pattern.** A reference runbook (decision matrix for "I need a future-dated action":
> session cron vs GH-Actions sweeper vs self-armed oneshot vs the new reminder primitive; the 3 integration
> points; the gotchas — stable `id` dedup, future-`ts` + late-redeploy edge, NO Sentry monitor, token
> minted-in-step-never-returned), a copy-fill `oneshot-TEMPLATE.ts.template`, and pointers wired into
> `/ship` Step 3.5.B and `/soleur:schedule`.
>
> **Part B — generic reminder primitive.** A new `event-scheduled-reminder.ts` (triggered by
> `reminder.scheduled`) with an allowlisted discriminated-union `action` (`issue-comment` | `named-check`),
> a server-side `CHECK_REGISTRY` seeded with one read-only demonstrator, and a secret-authed emit endpoint
> `POST /api/internal/schedule-reminder` mirroring `trigger-cron`. A future-dated comment or a registered
> check now fires with **no per-reminder deploy**.
>
> **Security model.** The endpoint is gated by `INNGEST_MANUAL_TRIGGER_SECRET` (operator-held in Doppler),
> so it grants the **same capability the operator already has** via `gh issue comment` / a registered check
> — time-delayed. It does NOT accept arbitrary code; `named-check` dispatches only to code-reviewed
> registered functions. Comments are non-mutating + reversible. No issue close/edit/label mutation in v1.
> `security-sentinel` reviewed the endpoint → installation-token GitHub-write boundary and the action
> allowlist completeness.
>
> **Additive.** The 5 existing bespoke oneshots and every `cron-*.ts` are untouched. References #2714 for
> lineage; opens no issue to close.
