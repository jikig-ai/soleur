---
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
issue: "#4654"
draft_pr: "#4655"
brainstorm: "knowledge-base/project/brainstorms/2026-05-30-inngest-oneshot-scheduler-brainstorm.md"
spec: "knowledge-base/project/specs/feat-inngest-oneshot-scheduler/spec.md"
adr: "ADR-046"
---

# Plan: Inngest One-Time Scheduler — #4650 monitor-close oneshot + self-arming pattern + ADR-046

## Overview

Ship the first secret-/repo-write consumer of the Inngest one-time-scheduler pattern, and
remove the manual-arming step that all three existing `oneshot-*.ts` functions rely on.

Three deliverables (Approach A from the brainstorm — defer the n=1 generalization):

1. **`oneshot-4650-monitor-close.ts`** — a pure-TS Inngest oneshot that, on/after
   2026-05-31 09:00 UTC, reads the Inngest `/v1/functions` registry, classifies the 3 cron
   functions behind #4650's monitors, and (if all 3 are `OK` and #4650 is still OPEN) closes
   #4650 with an explanatory comment via the GitHub App installation token.
2. **Committed self-arm** — a fire-and-forget `inngest.send({ id, ts, data })` in the
   `server/index.ts` boot block (`app.prepare().then()`), idempotent via a stable event `id`.
   boot == deploy (release pipeline restarts the container on every `apps/web-platform/**`
   merge), so this is deploy-and-forget — no manual `pnpm exec inngest send` command.
3. **ADR-046** — records the three durable decisions: GHA `--once` vs Inngest-oneshot
   boundary; self-arming-in-code pattern; registered-functions-only substrate boundary (K3/K21).

**Scope guards:** registered-functions-only (no arbitrary-spec executor — K21); `inngest.send({ts,id})`
not `step.sleepUntil` (K2); ADR-033 I1–I6 (no Sentry cron monitor for the oneshot, errors via
`reportSilentFallback`, `actor:"platform"`, `cron-platform` concurrency, `retries:1`); reuse
`mintInstallationToken` + the watchdog registry read (no hand-rolled token/fetch).

## Research Reconciliation — Spec vs. Codebase

| Spec/issue claim | Codebase reality (repo-research, file:line) | Plan response |
|------------------|---------------------------------------------|---------------|
| "Reuse the Sentry-query code in `cron-inngest-cron-watchdog.ts`" | Watchdog reads the **Inngest** `/v1/functions` registry (`fetchRegistry` :274-293), NOT Sentry. Sentry is write-only (heartbeat POST) repo-wide. | Close-condition = registry read, not Sentry. (Operator-confirmed.) |
| Consumer needs net-new Sentry Crons read + `SENTRY_API_TOKEN` (spec TR1 v1) | Container has only Sentry **ingest** keys (`.env.example:73-75`); no Sentry read token. Adding one = new credential surface = the flagged USER_BRAND_CRITICAL vector. | **Dropped.** Reuse watchdog `classifyRegistry` over 3 fnIds; auth via `INNGEST_SIGNING_KEY` already in env. No new secret. |
| Self-arm via `instrumentation.ts` (brainstorm Open Q1 candidate) | `instrumentation.ts register()` is a **no-op** under the custom server (`instrumentation.ts:3-7`, `server/index.ts:1-3`). | Arm from `server/index.ts` `app.prepare().then()` block (:48) alongside existing boot side-effects. |
| `fetchRegistry` reusable as-is | `fetchRegistry` + `INNGEST_HOST_FALLBACK` are **module-private** in the watchdog (`:274`); `classifyRegistry`/`planHeal`/`EXPECTED_CRON_FUNCTIONS`/`resolveInngestHost` ARE exported. | Export `fetchRegistry` + `INNGEST_HOST_FALLBACK` from the watchdog (single source of truth); import into the oneshot. |
| 3 monitor slugs → checkable | 1:1 map to `cron-gh-pages-cert-state` / `cron-community-monitor` / `cron-inngest-cron-watchdog`, all in `EXPECTED_CRON_FUNCTIONS` (watchdog :102-119). | Classify those 3 fnIds; all-`OK` ⇒ close. |
| #4650 fires ~tomorrow; PR may not merge in time | #4650 self-recovers (Sentry auto-resolve + watchdog backstop). | Relax D3 to **on-or-after** (`today >= expected_date`) so a late merge still closes. **Explicit K5 override** (existing oneshots use strict `today === expected_date`); the load-bearing idempotency guarantee is the **already-closed check** (Phase 2 step 2), NOT stable-`id` dedup (which is bounded — see Risks). |
| Stable-`id` dedups "across many restarts between merge and fire" (brainstorm) | Inngest event-`id` dedup is a **bounded ~24h window**, not an indefinite ledger (Kieran P0-2). | Demote stable-`id` to best-effort within-window; pin idempotency on the already-closed no-op. Horizon here is ~1 day so in practice we're inside the window. |

## Implementation Phases

### Phase 0 — Preconditions (verify the things that can have changed / are assumed)
- Re-check #4650 is still OPEN (`gh issue view 4650 --json state`); if already CLOSED, the oneshot is a documented example only — still ship the pattern + ADR.
- Confirm `server/index.ts` fire-and-forget `.catch()` precedent still at ~:98 and `sendInngestWithRetry` signature (`send-with-retry.ts`).
- **Verify, don't assume:** confirm a past-`ts` `inngest.send` delivers on the next scheduler tick (Inngest docs via context7) — the late-merge path (reconciliation row) depends on it.
- (Already confirmed by repo-research, no re-grep needed: `classifyRegistry`/`resolveInngestHost`/`EXPECTED_CRON_FUNCTIONS`/types exported; `fetchRegistry` module-private; `mintInstallationToken` in `_cron-shared.ts`.)

### Phase 1 — Export `fetchRegistry` from the watchdog (RED→GREEN)
- Add `export` to `fetchRegistry` only in `cron-inngest-cron-watchdog.ts`. Do NOT export `INNGEST_HOST_FALLBACK` — `resolveInngestHost()` (already exported) encapsulates the fallback (Simplicity P0-1). No behavior change; existing watchdog suites (incl. orphan/scope guards) must pass via `test-all.sh`.

### Phase 2 — `oneshot-4650-monitor-close.ts` (TDD)
- Pure-TS handler. **Token/Octokit-close template = `oneshot-recheck-4217-calibration.ts`** (it uses `mintInstallationToken` + closes via App token — the correct template; gdpr inlines `generateInstallationToken`). Borrow the **no-Sentry-monitor + event-only-trigger** structure from any oneshot: `cron-platform` concurrency, `retries:1`, the `as unknown as Parameters<typeof inngest.createFunction>[2]` cast.
- `EventData`: `{ issue: number; expected_date: string; date_override?: string; actor?: "platform" }` (convention-consistent with existing oneshots; values fixed for this consumer).
- Handler steps:
  1. **D3 guard (on-or-after — explicit K5 override):** validate `date_override` regex `^\d{4}-\d{2}-\d{2}$`; compute `today`; if `today < expected_date` → `reportSilentFallback` + return `{ok:false, reason:"date-guard"}`. (Floor only — idempotency lives in step 2.)
  2. **Idempotency / issue-state (load-bearing):** `step.run("check-issue-state")` — `mintInstallationToken`, `GET issue #4650`; if `state === "closed"` → return `{ok:true, reason:"already-closed"}` (no-op). **This is the cross-boot idempotency guarantee**, not stable-`id` dedup.
  3. **Registry classify:** `step.run("classify-registry")` — `host = resolveInngestHost(process.env.INNGEST_BASE_URL)` (identical to watchdog :401); `registry = await fetchRegistry(host)`; `results = classifyRegistry(registry, ["cron-gh-pages-cert-state","cron-community-monitor","cron-inngest-cron-watchdog"])`. On fetch **throw** → `reportSilentFallback(op:"registry-fetch")` + `{ok:false, reason:"registry-fetch-failed"}` (fail-safe: do NOT close).
  4. **Decision:** if all 3 `OK` → `step.run("close-issue")` posts the close-comment + closes #4650. If any `MISSING`/`UNPLANNED` (incl. partial/empty registry mid-resync — the most likely post-deploy state) → `reportSilentFallback(op:"not-all-healthy", extra:results)` + leave open, return `{ok:false, reason:"not-all-healthy"}`. **No status comment** (Simplicity P1-3 — noise; watchdog backstops; removes an Octokit write path).
- Errors only via `reportSilentFallback` (ADR-033 — oneshots get no Sentry monitor).

### Phase 3 — Self-arm in `server/index.ts` boot block
- Inside `app.prepare().then()`, add a non-awaited arm wrapped in `sendInngestWithRetry` (K6 — boot IS a deploy restart; the loopback can blip and a raw `.catch()` would silently lose the arm with no monitor):
  `sendInngestWithRetry(() => inngest.send({ name: "oneshot/monitor-close-4650.fire", id: "oneshot-4650-close-2026-05-31-v1", ts: new Date("2026-05-31T09:00:00Z").getTime(), data: { issue: 4650, expected_date: "2026-05-31", actor: "platform" } }), { feature: "oneshot-4650-arm" }).catch(...)`.
- Stable `id` dedups repeated arms **within Inngest's ~24h window** (best-effort); post-close the arm is a permanent no-op on every deploy (acceptable; removable in a later cleanup).

### Phase 4 — Register + ADR-046
- `app/api/inngest/route.ts`: import + add to the `serve({functions:[...]})` array (RV6 — manual, no barrel).
- ADR-046 via `soleur:architecture` (or hand-write): `adr/title/status/date` frontmatter; Context / Considered Options / Decision (boundary + self-arming + registered-only invariants) / Consequences.

## Files to Edit
- `apps/web-platform/server/inngest/functions/cron-inngest-cron-watchdog.ts` — export `fetchRegistry`, `INNGEST_HOST_FALLBACK`.
- `apps/web-platform/server/index.ts` — boot-block self-arm send.
- `apps/web-platform/app/api/inngest/route.ts` — import + functions-array entry.

## Files to Create
- `apps/web-platform/server/inngest/functions/oneshot-4650-monitor-close.ts`
- `apps/web-platform/test/server/inngest/oneshot-4650-monitor-close.test.ts` (vitest — verify path against `vitest.config.ts` include globs; `test/**/*.test.ts`)
- `knowledge-base/engineering/architecture/decisions/ADR-046-inngest-oneshot-scheduler-self-arm-and-registered-only.md` — scoped to the TWO genuinely-durable decisions: (1) **registered-functions-only** substrate boundary (K3/K21 — the security-load-bearing one; CTO-recommended) and (2) **self-arm-in-code** pattern (the novel one). Cross-link (do NOT re-decide) the GHA `--once` vs Inngest boundary, which the brainstorm already records.

## User-Brand Impact

**If this lands broken, the user experiences:** nothing user-facing — this is platform-internal bookkeeping. Worst internal case: #4650 stays open (it self-recovers anyway) or a spurious comment is posted on #4650.

**If this leaks, the user's data is exposed via:** N/A — the oneshot reads the Inngest registry (operator infra) and closes a GitHub issue via the operator App token (ADR-033 I2: operator-owned data only, never founder BYOK). The registry-read decision means **no new credential surface** is introduced.

**Brand-survival threshold:** `single-user incident` (carry-forward from brainstorm Phase 0.1; operator selected "All of them"). `requires_cpo_signoff: true`.

| Vector | Worst-case | Load-bearing invariant |
|--------|-----------|------------------------|
| Credential leak / over-broad writes | A future arbitrary-spec scheduler runs with full prd env + App token | **K3** registered-functions-only (this PR ships ONE reviewed function); K21; ADR-046 |
| Silent no-op | Oneshot never fires or wrongly closes #4650 | Stable-`id` dedup + on-or-after date guard; fail-safe-open on registry-fetch error; #4650 self-recovers + watchdog backstop |
| Wrong close | #4650 closed while a cron is actually de-planned | Close ONLY when all 3 classify `OK`; partial-health leaves open + posts status |

**CPO sign-off:** carried forward from brainstorm Phase 0.5 (CPO assessed the scope and recommended the minimal surface; operator chose Approach A). `user-impact-reviewer` will run at review time per review/SKILL.md.

## Domain Review

**Domains relevant:** Engineering, Product, Legal (carry-forward from brainstorm `## Domain Assessments`).

### Engineering (CTO)
**Status:** reviewed (carry-forward). **Assessment:** registered-functions-only; `ts+id` not `sleepUntil`; reuse the shared substrate. The registry-read close-condition (chosen at plan time) further reduces blast radius to zero new credentials. One small refactor: export `fetchRegistry` from the watchdog.

### Product (CPO)
**Status:** reviewed (carry-forward). **Assessment:** minimal surface for n=1; defer the scaffolding skill (coordinate w/ #3990). Self-arm closes the manual-arming hazard cheaply. **Product/UX Gate:** tier **NONE** — no user-facing surface (no `components/**/*.tsx`, `app/**/page.tsx`, `app/**/layout.tsx` in Files to Create).

### Legal (CLO)
**Status:** reviewed (carry-forward). **Assessment:** no Article 30 register change, no new sub-processor; operator-owned data only (issue close + registry read). No gdpr-gate finding for this consumer.

## GDPR / Compliance Gate (Phase 2.7)
**Disposition:** considered, no findings. No regulated-data surface (no schema/migration/auth/API-route/`.sql`). Trigger (b) (single-user-incident threshold) fired the consideration; CLO carry-forward confirms operator-only data, no PII, no Art. 30 impact. Skip with documented rationale.

## Infrastructure (IaC) Gate (Phase 2.8)
**Disposition:** skip — no new infrastructure. The registry-read choice eliminated the only candidate new secret (`SENTRY_API_TOKEN`). Self-arm is code in an existing process; no new server/service/cron/vendor/secret. (Had the Sentry-read path been chosen, this gate would have fired for the Doppler secret + Sentry token mint.)

## Observability

```yaml
liveness_signal:
  what: "oneshot fires once at ts=2026-05-31T09:00Z; no recurring cadence"
  cadence: "one-shot (event-triggered, future-ts)"
  alert_target: "none — ADR-033: oneshots get NO Sentry cron monitor (would false-alert on a non-recurring fn)"
  configured_in: "server/index.ts boot-arm + app/api/inngest/route.ts registration"
error_reporting:
  destination: "Sentry via reportSilentFallback (date-guard reject, registry-fetch fail, close-issue fail, partial-health)"
  fail_loud: "yes — every non-OK path calls reportSilentFallback with op + extra"
failure_modes:
  - mode: "registry fetch fails (Inngest unreachable)"
    detection: "catch in classify-registry step.run"
    alert_route: "reportSilentFallback op=registry-fetch; fail-safe (do NOT close)"
  - mode: "partial/empty registry (1-2 of 3 OK, or mid-resync partial)"
    detection: "classifyRegistry results"
    alert_route: "reportSilentFallback op=not-all-healthy (extra:results); leave #4650 open; NO comment"
  - mode: "GitHub close API fails"
    detection: "catch in close-issue step.run"
    alert_route: "reportSilentFallback op=close-issue"
  - mode: "fires on wrong day (desync/replay)"
    detection: "D3 on-or-after date guard"
    alert_route: "reportSilentFallback op=date-guard; no-op"
logs:
  where: "pino structured logs (Better Stack) via reportSilentFallback payloads + logger.info"
  retention: "per existing Better Stack config"
discoverability_test:
  command: "gh issue view 4650 --json state,comments  # plus: curl -s -H \"Authorization: Bearer $INNGEST_SIGNING_KEY\" \"${INNGEST_BASE_URL:-http://host.docker.internal:8288}/v1/functions\" | jq '.[].id' | grep oneshot-4650-monitor-close"
  expected_output: "issue state reflects close (or remains open if not-all-healthy); oneshot function id present in registry post-deploy. NO ssh. (Host = INNGEST_BASE_URL-or-fallback, identical to watchdog — not hardcoded localhost.)"
```

## Acceptance Criteria

### Pre-merge (PR)
- AC1: `oneshot-4650-monitor-close.ts` registered in `route.ts`; `tsc --noEmit` clean.
- AC2: `fetchRegistry` exported from the watchdog (NOT `INNGEST_HOST_FALLBACK`); existing watchdog test suites (incl. orphan/scope guards) pass via `test-all.sh`.
- AC3: Handler unit tests (drive the handler directly, no LLM in path) cover: date-guard before/on/after via `date_override`; already-closed no-op; all-3-OK closes; **partial/empty registry (≥1 fnId MISSING/UNPLANNED) → leaves open, NO comment** (distinct from); **registry-fetch throws → fails-safe, no close**. (Partial-registry and fetch-throw are distinct branches — Kieran P1-2.)
- AC4: No Sentry cron monitor added for the oneshot (no `sentry_cron_monitor` resource); errors route via `reportSilentFallback`.
- AC5: No new secret / Doppler key / Sentry token referenced (`grep -r SENTRY_API_TOKEN` returns nothing in the diff).
- AC6: BYOK inverse-assertion holds (oneshot does not import `runWithByokLease`; `actor:"platform"` on the event).
- AC7: ADR-046 present with `adr/title/status/date` frontmatter + Context/Decision/Consequences.
- AC8: Self-arm uses stable `id` and a future `ts`; fire-and-forget `.catch()` does not block `server.listen`.

### Post-merge (operator — automated where feasible)
- AC9: On deploy, `curl -s -H "Authorization: Bearer $INNGEST_SIGNING_KEY" <inngest-host>/v1/functions | jq '.[].id'` includes `oneshot-4650-monitor-close` (registry discoverability). Automatable via the deploy-status webhook / container — not an operator dashboard step.
- AC10: After 2026-05-31 09:00 UTC, `gh issue view 4650 --json state` is `closed` if all 3 crons healthy, else OPEN with a status comment. `Ref #4650` in PR body (NOT `Closes` — the close happens at fire time, not merge).

## Open Code-Review Overlap
2 open code-review issues mention `server/index.ts`: #3740 (sentry-post-merge-smoke workflow) and #2349 (qa port-probe / ESM loader cache). **Acknowledge (non-overlapping):** both reference the file for unrelated concerns; neither touches the `app.prepare().then()` boot-arm addition. No fold-in. `route.ts` and the new oneshot: no overlap.

## Risks & Mitigations
- **Late merge (after 2026-05-31 09:00):** on-or-after date guard + immediate delivery of a past-`ts` event means the close still fires on first post-merge boot. #4650 self-recovers regardless.
- **Exporting `fetchRegistry` widens the watchdog's surface:** minimal — `export` only, no behavior change; covered by existing watchdog tests.
- **Long-horizon SQLite durability (ADR-030):** N/A here — `ts` is ~1 day out (or already past at merge); single-host SQLite durability is not stressed.

## Sharp Edges
- A plan whose `## User-Brand Impact` section is empty/`TBD` fails deepen-plan Phase 4.6 — this plan's section is filled.
- The self-arm send is **fire-and-forget** in a non-async `.then()` — must use the `.catch()` pattern (`server/index.ts:98`), never `await` (would block `server.listen`).
