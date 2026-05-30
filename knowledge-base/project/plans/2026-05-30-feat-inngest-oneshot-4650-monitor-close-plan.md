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

## Enhancement Summary

**Deepened on:** 2026-05-30. **Halt gates (4.6/4.7/4.8):** all PASS. **4.5 network-outage:** N/A (the only `ssh` token is "NO ssh" in the discoverability test). **4.4 precedent-diff:** done (see Research Insights).
**Substance reviewers:** architecture-strategist, observability-coverage-reviewer, silent-failure-hunter.

**Key improvements applied:**
1. **Self-arm hardened** — guarded `void (async()=>{try…catch})()` IIFE routing to `reportSilentFallback(op:"self-arm-send")`, not a bare `.catch()`. Under no-monitor (ADR-033) this catch is the ONLY signal for a permanently-lost arm. (3-reviewer convergence.)
2. **`function-registry-count.test.ts` 41→42** added to Files-to-Edit — a guaranteed-red test the plan had missed.
3. **Past-`ts` delivery** promoted to a HARD Phase 0 gate against the running self-hosted Inngest, with an immediate-send fallback if unverified.
4. **Registry-presence ≠ checking-in** — close-comment reworded to "cron triggers re-planned (H9a/H9b cleared)"; the planned-but-failing gap is accepted (watchdog monitor backstops).
5. **already-closed** path re-classifies + alerts on `already-closed-unhealthy` (foreign-close masking guard).
6. date-guard reject → warn-level; `date_override` calendar-validity check; 2 new Observability failure modes.

### Research Insights — Precedent-Diff (4.4)
- **createFunction shape:** `oneshot-recheck-4217-calibration.ts:234-247` — `concurrency:[{scope:"fn",limit:1},{scope:"account",key:'"cron-platform"',limit:1}]`, `retries:1`, event-only trigger, `as unknown as Parameters<typeof inngest.createFunction>[2]` cast. Adopt verbatim.
- **Token+close:** `oneshot-recheck-4217-calibration.ts` uses `mintInstallationToken` (the correct template) — NOT gdpr's inline `generateInstallationToken`.
- **No-monitor posture:** ADR-033 §table; `oneshot-gdpr-gate-50d-eval.ts` is the known deviation (declares a monitor) — do not follow it.
- **No new credential confirmed:** `fetchRegistry` reads only `INNGEST_SIGNING_KEY` (`route.ts:62` throws at load if absent → guaranteed present); `resolveInngestHost` falls back to `host.docker.internal:8288` (no new env var).

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
- Confirm `server/index.ts` fire-and-forget `.catch()` precedent still at ~:98 and `sendInngestWithRetry` signature (`send-with-retry.ts` — note it **re-throws after exhausting retries**, so the boot `.catch` is reachable).
- **HARD GATE (verify, don't assume — arch P0-2):** confirm a past-`ts` `inngest.send` delivers on the next scheduler tick against the **running self-hosted Inngest version** (ADR-030), not just SDK docs (docs only describe future `ts`). If unconfirmed at /work time, **fallback:** drop `ts` and send immediately, gated solely by the on-or-after date guard (the date guard is then the only floor). Do not rely on past-`ts` semantics that aren't verified on the deployed server.
- Note `function-registry-count.test.ts:94` asserts `routeEntries.length === 41`; registering this oneshot makes it 42 (see Files to Edit).
- (Already confirmed by repo-research, no re-grep needed: `classifyRegistry`/`resolveInngestHost`/`EXPECTED_CRON_FUNCTIONS`/types exported; `fetchRegistry` module-private; `mintInstallationToken` in `_cron-shared.ts`. Confirm `reportSilentFallback` + its warn-level variant in `server/observability.ts`.)

### Phase 1 — Export `fetchRegistry` from the watchdog (RED→GREEN)
- Add `export` to `fetchRegistry` only in `cron-inngest-cron-watchdog.ts`. Do NOT export `INNGEST_HOST_FALLBACK` — `resolveInngestHost()` (already exported) encapsulates the fallback (Simplicity P0-1). No behavior change; existing watchdog suites (incl. orphan/scope guards) must pass via `test-all.sh`.

### Phase 2 — `oneshot-4650-monitor-close.ts` (TDD)
- Pure-TS handler. **Token/Octokit-close template = `oneshot-recheck-4217-calibration.ts`** (it uses `mintInstallationToken` + closes via App token — the correct template; gdpr inlines `generateInstallationToken`). Borrow the **no-Sentry-monitor + event-only-trigger** structure from any oneshot: `cron-platform` concurrency, `retries:1`, the `as unknown as Parameters<typeof inngest.createFunction>[2]` cast.
- `EventData`: `{ issue: number; expected_date: string; date_override?: string; actor?: "platform" }` (convention-consistent with existing oneshots; values fixed for this consumer).
- Handler steps:
  1. **D3 guard (on-or-after — explicit K5 override):** validate `date_override` shape `^\d{4}-\d{2}-\d{2}$` AND validity (`!Number.isNaN(Date.parse(v))` + round-trip — `"2026-13-45"` passes shape but is not a real date, sf P2-2); compute `today`; if `today < expected_date` → **warn-level** `warnSilentFallback` (NOT error — an early replay is expected/benign, sf P2-1) + return `{ok:false, reason:"date-guard"}`. (Floor only — idempotency lives in step 2.)
  2. **Idempotency / issue-state (load-bearing):** `step.run("check-issue-state")` — `mintInstallationToken`, `GET issue #4650`; if `state === "closed"` → **still classify the registry (step 3) and if any cron is NOT OK, `reportSilentFallback(op:"already-closed-unhealthy", extra:results)`** (a foreign-close over a real de-plan must not be masked as success — sf P1-2), then return `{ok:true, reason:"already-closed"}`. **This (not stable-`id` dedup) is the cross-boot idempotency guarantee.**
  3. **Registry classify:** `step.run("classify-registry")` — `host = resolveInngestHost(process.env.INNGEST_BASE_URL)` (identical to watchdog :401); `registry = await fetchRegistry(host)`; `results = classifyRegistry(registry, ["cron-gh-pages-cert-state","cron-community-monitor","cron-inngest-cron-watchdog"])`. On fetch **throw** → `reportSilentFallback(op:"registry-fetch")` + `{ok:false, reason:"registry-fetch-failed"}` (fail-safe: do NOT close).
  4. **Decision:** if all 3 `OK` → `step.run("close-issue")` posts the close-comment + closes #4650. **Close-comment wording (arch P1-2):** "all 3 cron triggers re-planned (H9a/H9b cleared)" — NOT "monitors healthy." `classifyRegistry OK` proves the cron is *planned*, not that it is *checking in*; a planned-but-failing-every-run cron still classifies OK. Accepted gap: the watchdog's own `scheduled-inngest-cron-watchdog` monitor pages on real check-in failure, so a premature close (worst case) is bounded to a self-recovering internal issue. If any `MISSING`/`UNPLANNED` (incl. partial/empty registry mid-resync — the most likely post-deploy state) → `reportSilentFallback(op:"not-all-healthy", extra:results)` + leave open, return `{ok:false, reason:"not-all-healthy"}`. No status comment (Simplicity P1-3 — watchdog backstops).
- Errors only via `reportSilentFallback` (ADR-033 — oneshots get no Sentry monitor).

### Phase 3 — Self-arm in `server/index.ts` boot block
- Inside `app.prepare().then()`, add a non-awaited, **fully-guarded** arm. The boot block is non-async (can't `await`), and `sendInngestWithRetry` re-throws after exhausting retries with **no Sentry monitor** to notice (ADR-033) — so the catch is the ONLY signal for a permanently-lost arm. Wrap the whole thing in a `void (async () => { try … catch })()` IIFE so even a synchronous throw (client import/construct) routes to Sentry instead of escaping as an unhandledRejection (sf P0-1/P0-2, obs P1-1, arch P1-3):
  ```ts
  void (async () => {
    try {
      await sendInngestWithRetry(
        () => inngest.send({ name: "oneshot/monitor-close-4650.fire",
          id: "oneshot-4650-close-2026-05-31-v1",
          ts: new Date("2026-05-31T09:00:00Z").getTime(),  // see Phase 0 past-ts gate / fallback
          data: { issue: 4650, expected_date: "2026-05-31", actor: "platform" } }),
        { feature: "oneshot-4650-arm" });
    } catch (err) {
      reportSilentFallback(err, { feature: "oneshot-4650-arm", op: "self-arm-send" });
    }
  })();
  ```
- Stable `id` dedups repeated arms **within Inngest's ~24h window** (best-effort); post-close the arm is a permanent no-op on every deploy (acceptable; removable in a later cleanup). A permanent arm failure self-heals on the next deploy (boot==deploy) AND is now Sentry-visible.

### Phase 4 — Register + ADR-046
- `app/api/inngest/route.ts`: import + add to the `serve({functions:[...]})` array (RV6 — manual, no barrel).
- ADR-046 via `soleur:architecture` (or hand-write): `adr/title/status/date` frontmatter; Context / Considered Options / Decision (boundary + self-arming + registered-only invariants) / Consequences.

## Files to Edit
- `apps/web-platform/server/inngest/functions/cron-inngest-cron-watchdog.ts` — export `fetchRegistry` (only).
- `apps/web-platform/server/index.ts` — boot-block self-arm (guarded IIFE + `reportSilentFallback`).
- `apps/web-platform/app/api/inngest/route.ts` — import + functions-array entry.
- `apps/web-platform/test/server/inngest/function-registry-count.test.ts` — bump `routeEntries.length` assertion **41 → 42** (line ~94; the comment at ~:92 says "UPDATE this number"). Guaranteed-red otherwise (arch P0-1).

## Files to Create
- `apps/web-platform/server/inngest/functions/oneshot-4650-monitor-close.ts`
- `apps/web-platform/test/server/inngest/oneshot-4650-monitor-close.test.ts` (vitest — verify path against `vitest.config.ts` include globs; `test/**/*.test.ts`)
- `knowledge-base/engineering/architecture/decisions/ADR-046-inngest-oneshot-scheduler-self-arm-and-registered-only.md` — scoped to the TWO genuinely-durable decisions: (1) **registered-functions-only** substrate boundary (K3/K21 — the security-load-bearing one; CTO-recommended) and (2) **self-arm-in-code** pattern (the novel one). Cross-link (do NOT re-decide) the GHA `--once` vs Inngest boundary, which the brainstorm already records. **Frame the no-monitor posture precisely (arch P1-1):** ADR-033's §table prescribes no `sentry_cron_monitor` for oneshots; `oneshot-gdpr-gate-50d-eval.ts` is a *known deviation* (it declares a monitor) we are NOT following — do not cite it as the no-monitor example. Note AP-014 (platform/per-founder boundary) alignment in Consequences.

## User-Brand Impact

**If this lands broken, the user experiences:** nothing user-facing — this is platform-internal bookkeeping. Worst internal case: #4650 stays open (it self-recovers anyway) or a spurious comment is posted on #4650.

**If this leaks, the user's data is exposed via:** N/A — the oneshot reads the Inngest registry (operator infra) and closes a GitHub issue via the operator App token (ADR-033 I2: operator-owned data only, never founder BYOK). The registry-read decision means **no new credential surface** is introduced.

**Brand-survival threshold:** `single-user incident` (carry-forward from brainstorm Phase 0.1; operator selected "All of them"). `requires_cpo_signoff: true`.

| Vector | Worst-case | Load-bearing invariant |
|--------|-----------|------------------------|
| Credential leak / over-broad writes | A future arbitrary-spec scheduler runs with full prd env + App token | **K3** registered-functions-only (this PR ships ONE reviewed function); K21; ADR-046 |
| Silent no-op | Oneshot never fires or wrongly closes #4650 | Stable-`id` dedup + on-or-after date guard; fail-safe-open on registry-fetch error; #4650 self-recovers + watchdog backstop |
| Wrong close (health axis) | #4650 closed while a cron is actually de-planned | Close ONLY when all 3 classify `OK`; partial-health leaves open + alerts |
| Wrong close (identity axis) | A replayed/forged `oneshot/monitor-close-4650.fire` event with a different `issue` closes an arbitrary repo issue | **Mitigated in code (review P1):** handler pins `data.issue === TARGET_ISSUE` (4650), else `reportSilentFallback(op:"wrong-issue")` + no-op |
| Credential persistence | Live App installation token written to Inngest's durable step state | **Mitigated in code (review):** token minted+used inside each `step.run`, never returned across the step boundary (security-sentinel rated the prior threading P3/acceptable — loopback SQLite, never in Sentry/pino; this is defense-in-depth) |

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
  alert_target: "none — ADR-033: oneshots get NO Sentry cron monitor (would false-alert on a non-recurring fn). Liveness is NOT monitored; the compensating control is the cron-inngest-cron-watchdog backstop + Sentry auto-resolve on #4650, which close the issue independently of this oneshot (obs P2-1)."
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
    alert_route: "warnSilentFallback op=date-guard (warn-level — benign early-fire); no-op"
  - mode: "self-arm send permanently fails (loopback down through retries)"
    detection: "sendInngestWithRetry rejection in the boot IIFE catch"
    alert_route: "reportSilentFallback op=self-arm-send (Sentry capture); next deploy re-arms; watchdog backstop closes #4650 independently"
  - mode: "#4650 closed by something else while a cron is de-planned"
    detection: "already-closed branch re-classifies registry"
    alert_route: "reportSilentFallback op=already-closed-unhealthy (extra:results)"
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
- AC2: `fetchRegistry` exported from the watchdog (NOT `INNGEST_HOST_FALLBACK`); `function-registry-count.test.ts` count bumped 41→42; all existing suites (incl. orphan/scope guards) pass via `test-all.sh`.
- AC3: Handler unit tests (drive the handler directly, no LLM in path) cover: date-guard before/on/after via `date_override`; already-closed no-op; all-3-OK closes; **partial/empty registry (≥1 fnId MISSING/UNPLANNED) → leaves open, NO comment** (distinct from); **registry-fetch throws → fails-safe, no close**. (Partial-registry and fetch-throw are distinct branches — Kieran P1-2.)
- AC4: No Sentry cron monitor added for the oneshot (no `sentry_cron_monitor` resource); errors route via `reportSilentFallback`.
- AC5: No new secret / Doppler key / Sentry token referenced (`grep -r SENTRY_API_TOKEN` returns nothing in the diff).
- AC6: BYOK inverse-assertion holds (oneshot does not import `runWithByokLease`; `actor:"platform"` on the event).
- AC7: ADR-046 present with `adr/title/status/date` frontmatter + Context/Decision/Consequences.
- AC8: Self-arm is a guarded IIFE (`void (async () => { try … catch })()`) whose catch calls `reportSilentFallback(op:"self-arm-send")` — NOT a bare `.catch()`/`log.error`; does not block `server.listen`; uses stable `id` + future `ts` (or the Phase 0 immediate-send fallback if past-`ts` delivery is unverified).

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
