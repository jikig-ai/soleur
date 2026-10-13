---
title: "observability: cron-workspace-gc emits freedMb to Sentry on every run (no-SSH reclaim verification)"
type: feat
issue: 4897
refs: [4886, 4882]
branch: feat-one-shot-4897-cron-workspace-gc-freedmb-sentry
lane: cross-domain
brand_survival_threshold: aggregate pattern
created: 2026-06-03
---

## Enhancement Summary

**Deepened on:** 2026-06-03
**Sections enhanced:** 4 (Premise Validation, Phase 1 helper, Phase 3 tests, Research Insights added)
**Gates run:** Phase 4.4 precedent-diff, Phase 4.45 verify-the-negative, Phase 4.6 User-Brand Impact (PASS), Phase 4.7 Observability (PASS), Phase 4.8 PAT-shaped (PASS, no match), Phase 4.9 UI-wireframe (skip, no UI surface)

### Key Improvements

1. **Verbatim `warnSilentFallback` body pinned** as the copy-from anchor for the
   new `infoSilentFallback` helper (Phase 1 Research Insights) — eliminates
   guesswork on the `tags` / `hashExtraUserId` / shim-guard machinery to mirror.
2. **All three negative claims verified against `origin/main`** (heartbeat carries
   no event body; healthy path is `logger.info`-only; payload has no userId) —
   see Premise Validation + Research Insights.
3. **Precedent-diff confirmed**: this edits an EXISTING Inngest cron (no new
   scheduled job → ADR-033 trigger gate already satisfied); info-level
   `Sentry.captureMessage` precedent exists at `leader-document-resolver.ts:157`.

### New Considerations Discovered

- The existing healthy-reclaim test (`:102-132`) is the natural home for the
  every-run-emit regression guard (AC4) — it already mocks the above-floor case
  where `warnSilentFallback` does NOT fire, so asserting `infoSilentFallback`
  fires there directly proves the gap is closed.

# ✨ observability: cron-workspace-gc must emit freedMb to Sentry on every run

## Overview

`cron-workspace-gc` (`apps/web-platform/server/inngest/functions/cron-workspace-gc.ts`)
sweeps leaked ephemeral `soleur-*` cron-clone dirs off the shared `/workspaces`
volume every 6h (and on `cron/workspace-gc.manual-trigger`). It computes a full
reclaim payload — `{ freeMbBefore, freeMbAfter, freedMb, sweptCount, root }` —
every run, but only emits a **durable Sentry signal** on two paths:

1. The Sentry Crons **heartbeat** (liveness only — a fire-and-forget check-in URL
   that carries `status=ok`, **no structured payload**; `_cron-shared.ts:160`).
2. The low-disk **`warnSilentFallback`** path — fires ONLY when
   `freeMbAfter < floorMb` (`cron-workspace-gc.ts:211-230`).

On a **successful reclaim** (the common, desired case where free space stays
above the floor), the reclaim numbers go to `logger.info` (pino stdout) ONLY
(`cron-workspace-gc.ts:201-204`). Vector does **not** ship app stdout to Better
Stack/Sentry by design (confirmed in the file's own comment at `:198-200`). So
there is **no no-SSH, queryable signal of how much disk a healthy GC run freed**.

During the 2026-06-02 ENOSPC incident this made it impossible to confirm a manual
GC fire reclaimed the leaked clones without SSH — only the (success-silent)
heartbeat was visible. This violates the spirit of
`hr-no-dashboard-eyeball-pull-data-yourself` and `hr-observability-as-plan-quality-gate`:
the load-bearing outcome (disk reclaimed) must be verifiable from a durable,
pulled signal.

**The fix:** emit the same `{ freeMbBefore, freeMbAfter, freedMb, sweptCount, root }`
payload to Sentry as a structured **info-level** event on **every run** (not just
the low-disk path), so a no-SSH operator can confirm a reclaim via the Sentry
events API after firing `cron/workspace-gc.manual-trigger`.

**Scope:** small (~15-25 LoC across the handler + a new centralized info-level
observability helper + tests). Single-domain code change against an already-
provisioned cron; no new infrastructure, no migration, no UI, no regulated data.

## Premise Validation

- **Issue #4897** (`gh issue view 4897`): OPEN, labeled `deferred-scope-out`. The
  cited problem holds against current `origin/main` state — verified by reading
  `cron-workspace-gc.ts`: the success path at `:201-204` is `logger.info` only;
  the only durable Sentry emit on a healthy run is the payload-less heartbeat at
  `:238-245` → `postSentryHeartbeat` (`_cron-shared.ts:123-175`, which POSTs a
  bare check-in URL with no event body). The `warnSilentFallback` at `:211-230`
  is gated on `freeMbAfter < floorMb` — does NOT fire on a healthy reclaim.
  **Premise is current, not stale.**
- **Ref #4886** (`.cron` subdir isolation) — already reverted per the file header
  comment `:15-20`; not a dependency of this change.
- **Ref #4882** (the freeze incident) — historical context only.
- **Capability claim checked:** "fold into the heartbeat payload" (one of the
  issue's proposed options) is **NOT viable** — `postSentryHeartbeat` POSTs a
  fixed Sentry Crons check-in URL (`.../cron/<slug>/<key>/?status=ok`) that
  accepts no event body (`_cron-shared.ts:160-165`). Verified by reading the
  helper. The durable queryable signal MUST be a Sentry **event**
  (`captureMessage`), which is what `report/warnSilentFallback` already produce.

## Research Reconciliation — Spec vs. Codebase

| Claim (issue body) | Codebase reality | Plan response |
| --- | --- | --- |
| "Emit ... e.g. a structured info-level event / breadcrumb, **or fold into the heartbeat payload**" | Heartbeat is a payload-less Crons check-in URL (`_cron-shared.ts:160`). Breadcrumbs are NOT independently queryable (they only attach to a *subsequently captured event*). | Use a standalone **info-level `Sentry.captureMessage` event** via a new centralized `infoSilentFallback` helper. Drop the heartbeat-fold and bare-breadcrumb options. |
| "~10-20 lines in `cron-workspace-gc.ts` + a test" | Adding a raw inline `Sentry.captureMessage` would bypass the centralized tag/extra pseudonymization + Sentry-shim guard that `report/warnSilentFallback` provide. | Add a sibling `infoSilentFallback` to `observability.ts` (mirrors the warn/report pair) so the every-run emit keeps the same tag vocabulary + `hashExtraUserId` boundary + shim-safe try/catch. Net ~15-25 LoC. |

## User-Brand Impact

**If this lands broken, the user experiences:** no direct user-facing artifact —
this is an operator-observability signal. A broken emit (wrong payload, thrown
exception) could at worst (a) bury a real Sentry signal under noise, or (b) if it
threw, abort the GC step. Mitigated: the helper wraps the Sentry call in the same
shim-safe `try/catch` the existing `warnSilentFallback` uses (Sentry failures
never propagate), and the info emit lands AFTER the sweep + statfs-after, so a
throw cannot prevent a reclaim.

**If this leaks, the user's data is exposed via:** the emitted `extra` payload is
purely disk-capacity arithmetic (`freeMbBefore/After`, `freedMb`, `sweptCount`,
`root`) + the `soleur-` cron-clone dir basename — **no user data, no userId, no
path beyond the cron root**. The centralized helper still routes through
`hashExtraUserId` (a no-op here since no `userId` field is passed), so the
pseudonymization boundary is preserved by construction.

**Brand-survival threshold:** `aggregate pattern` — a single failed emit is an
observability gap, not a user-facing incident. (The *absence* of this signal is
what the issue is filed against; restoring it is the brand-positive direction.)

## Implementation Phases

### Phase 1 — Add `infoSilentFallback` to the centralized observability module

**File to edit:** `apps/web-platform/server/observability.ts`

Add an **info-level** sibling of `warnSilentFallback`/`reportSilentFallback` so
every-run structured emits share the same tag vocabulary, `hashExtraUserId`
pseudonymization boundary, `sanitizeLogMessage`, and the shim-safe Sentry
try/catch. Rationale: a raw inline `Sentry.captureMessage` in the cron would
duplicate (and risk drifting from) that machinery — the existing pair already
encodes the "mirror a structured branch to Sentry alongside pino" contract.

Shape (mirror `warnSilentFallback` exactly, swapping the level):

```ts
// apps/web-platform/server/observability.ts
/**
 * Info-level variant. Same contract as warn/reportSilentFallback, but emits at
 * `level: "info"` — use for an EVERY-RUN structured record that must be
 * queryable in Sentry without SSH (e.g. a cron's reclaim/throughput payload on
 * the healthy path), NOT just on the error/degraded branch. Because every call
 * emits, prefer this only for low-cardinality periodic signals (a 6h cron), not
 * per-request hot paths — pair with mirrorWithDebounce if a burst is possible.
 */
export function infoSilentFallback(
  err: unknown,
  options: SilentFallbackOptions,
): void {
  // ... identical body to warnSilentFallback, with:
  //   logger.info({ feature, op, ...transformedExtra }, safeMessage);
  //   Sentry.captureMessage(safeMessage, { level: "info", tags,
  //                                        extra: { ...transformedExtra } });
  // (info events normally carry no Error object; accept `null` as the first arg.)
}
```

Notes:
- `SilentFallbackOptions` is reused unchanged (`feature`, `op`, `message`, `extra`).
- The `info` path normally passes `err = null`, so the `err instanceof Error`
  branch is effectively unused here, but keep the same signature for symmetry and
  so a future caller can attach a non-fatal Error if needed.
- Do NOT add `art_33_breach` semantics — info-level is never a breach signal.

#### Research Insights

**Precedent-diff (Phase 4.4).** The new helper is a verbatim mirror of
`warnSilentFallback` (`observability.ts:241-282`, read at deepen time) with the
level swapped `"warning"` → `"info"` and `logger.warn` → `logger.info`. The body
to copy:

```ts
// observability.ts:241-282 — copy this, swapping the two level/log sites.
export function warnSilentFallback(err, options): void {
  const { feature, op, extra, message, art33Breach } = options;
  const tags: Record<string, string> = { feature };
  if (op) tags.op = op;
  if (art33Breach) tags.art_33_breach = "true";   // ← DROP for info (never a breach)
  const pgCode = sqlStateFromError(err);
  if (pgCode) tags.pg_code = pgCode;              // keep — harmless no-op when err=null
  const transformedExtra = hashExtraUserId(extra); // keep — pseudonymization boundary
  const safeMessage = sanitizeLogMessage(message ?? `${feature} silent fallback`);
  logger.warn(...);                                // ← logger.info for the info variant
  try {
    if (err instanceof Error) { Sentry.captureException(err, { level: "warning", ... }); }
    else if (typeof Sentry.captureMessage === "function") {
      Sentry.captureMessage(safeMessage, { level: "warning", tags, extra: { err, ...transformedExtra } });
    }                                              // ← both "warning" → "info"
  } catch { /* shim-guard — Sentry failures never propagate */ }
}
```

**Info-level `captureMessage` precedent exists** at
`leader-document-resolver.ts:157` (and `:195`, `:211`) — a standalone
`level:"info"` Sentry event is an established, queryable pattern in this codebase
(distinct from `addBreadcrumb`, which is NOT independently queryable).

**Verify-the-negative (Phase 4.45) — all three load-bearing negatives confirmed
against `origin/main`:**
- Heartbeat carries no event body: `postSentryHeartbeat` POSTs
  `.../cron/<slug>/<key>/?status=ok` with `method:"POST"` and NO `body:`
  (`_cron-shared.ts:160-165`). ✓ "fold into heartbeat" correctly rejected.
- Healthy path is Sentry-silent: the only emit on the above-floor path is
  `logger.info` (`cron-workspace-gc.ts:201`); `warnSilentFallback` is gated on
  `freeMbAfter < floorMb` (`:211`). ✓ premise current.
- No userId in payload: the `extra` is `{ fn, root, freeMbBefore, freeMbAfter,
  freedMb, sweptCount }` (`:202`) — disk arithmetic + a `soleur-` basename only.
  ✓ `hashExtraUserId` is a no-op here but preserved for symmetry.

**Scheduled-work check (Phase 4.4):** this plan adds NO new scheduled job — it
edits an existing Inngest cron (`cron-workspace-gc.ts`, one of 39 under
`apps/web-platform/server/inngest/functions/cron-*.ts`). ADR-033's "prefer
Inngest over GH Actions cron" trigger gate is already satisfied; no trigger-shape
decision is in scope.

### Phase 2 — Emit the every-run reclaim event from the cron

**File to edit:** `apps/web-platform/server/inngest/functions/cron-workspace-gc.ts`

1. Add `infoSilentFallback` to the existing `@/server/observability` import
   (line 42-45 already imports `reportSilentFallback`, `warnSilentFallback`).
2. **Replace** the success-path `logger.info(...)` at `:201-204` with an
   `infoSilentFallback` call carrying the full payload (the pino `logger.info`
   mirror is preserved *inside* the helper, so no stdout signal is lost):

```ts
// cron-workspace-gc.ts — replaces the logger.info at :201-204
infoSilentFallback(null, {
  feature: CRON_NAME,                 // "cron-workspace-gc" — queryable tag
  op: "workspace-gc-sweep-complete",
  message: "workspace GC sweep complete",
  extra: { fn: CRON_NAME, root, freeMbBefore, freeMbAfter, freedMb, sweptCount },
});
```

3. Keep the existing low-disk `warnSilentFallback` at `:211-230` **unchanged** —
   it remains the *actionable* (paging-worthy) signal at `level: "warning"`;
   the new info emit is the *every-run* (informational, non-paging) signal. They
   are deliberately distinct Sentry levels so on-call can filter
   `level:warning feature:cron-workspace-gc` for actionable vs `level:info` for
   throughput history.
4. The ENOENT short-circuit paths (`:122`, `:138-143`) emit no info event — an
   absent volume has nothing to report; leave them as-is (they already return
   cleanly without paging).

**Phase order rationale:** Phase 1 (helper, the contract producer) MUST land
before Phase 2 (the consumer) within the single atomic commit — `infoSilentFallback`
must exist before the cron imports it, or `tsc` fails in the consumer.

### Phase 3 — Tests (RED before GREEN)

**Files to edit:**
- `apps/web-platform/test/server/inngest/cron-workspace-gc.test.ts`
- `apps/web-platform/test/observability.test.ts` *(has a `warnSilentFallback`
  describe block at `:344` to mirror — confirmed present)*

In `cron-workspace-gc.test.ts`:
1. Extend the `@/server/observability` mock (currently `:37-40`) to add
   `infoSilentFallback: vi.fn()`.
2. Import `infoSilentFallback` from the mocked module alongside
   `reportSilentFallback`, `warnSilentFallback` (`:44-47`).
3. **New assertion on the existing healthy-reclaim test** (`:102-132`, "removes
   only aged soleur-* dirs..."): assert `infoSilentFallback` was called **once**
   with `extra` matching `{ freeMbBefore: 500, freeMbAfter: 600, freedMb: 100,
   sweptCount: 1, root: "/workspaces" }` and `feature: "cron-workspace-gc"` —
   this is the every-run-emit regression guard the issue exists for, and it
   asserts on the **healthy** path where `warnSilentFallback` is NOT called.
4. **Assertion on the low-disk test** (`:134-154`): `infoSilentFallback` is
   **also** called once on this run (info fires every run, independent of the
   warn). Both info AND warn fire when under floor.
5. **Assertion on the ENOENT test** (`:199-211`): `infoSilentFallback` is NOT
   called (the short-circuit returns before the emit) — proves the absent-volume
   path stays quiet.

In `apps/web-platform/test/observability.test.ts`: add an `infoSilentFallback`
describe block mirroring the existing `warnSilentFallback` block (`:344`),
asserting it emits `Sentry.captureMessage` with `level: "info"`, `tags: { feature }`,
the passed `extra`, AND routes `userId` → `userIdHash` through the same
`hashExtraUserId` boundary (the pseudonymization parity test the warn/report
blocks already carry). The file's existing Sentry mock + `import { ... } from
"@/server/observability"` (`:47-48`) are extended to cover the new export.

## Acceptance Criteria

### Pre-merge (PR)

- [x] **AC1 — helper exists, info-level:** `infoSilentFallback` is exported from
  `apps/web-platform/server/observability.ts` and calls `Sentry.captureMessage`
  with `level: "info"`. Verify:
  `grep -n 'export function infoSilentFallback' apps/web-platform/server/observability.ts`
  returns 1 line, and a `grep -n 'level: "info"' apps/web-platform/server/observability.ts`
  shows the new emit.
- [x] **AC2 — cron emits on every run:** the success-path `logger.info` at
  `cron-workspace-gc.ts:201-204` is replaced by an `infoSilentFallback` call.
  Verify: `grep -n 'infoSilentFallback' apps/web-platform/server/inngest/functions/cron-workspace-gc.ts`
  returns ≥1 line, and the bare `"workspace GC sweep complete"` `logger.info`
  call is gone (the message string now lives in the helper invocation).
- [x] **AC3 — payload shape:** the emitted `extra` contains exactly
  `{ fn, root, freeMbBefore, freeMbAfter, freedMb, sweptCount }`. Asserted by the
  test in Phase 3 step 3 (`toMatchObject`).
- [x] **AC4 — healthy-path regression guard:** the existing "removes only aged
  soleur-* dirs" test asserts `infoSilentFallback` fired once with the reclaim
  payload AND `warnSilentFallback` did NOT fire — proving the every-run signal
  exists on the path that was previously Sentry-silent.
- [x] **AC5 — low-disk path still both-fires:** the under-floor test asserts BOTH
  `infoSilentFallback` AND `warnSilentFallback` fired (distinct levels, distinct
  purposes).
- [x] **AC6 — absent-volume stays quiet:** the ENOENT test asserts
  `infoSilentFallback` was NOT called.
- [x] **AC7 — suite green:** the package's actual test runner (per
  `apps/web-platform/package.json scripts.test` / `vitest.config.ts`) passes for
  the two touched test files. Use the discovered runner, not a hardcoded
  `bun test` (see Sharp Edges). `tsc --noEmit` clean.

### Post-merge (operator)

- [ ] **AC8 — no-SSH reclaim verification path documented:** confirm an operator
  can pull the every-run reclaim event after firing the manual trigger via the
  Sentry events REST API (org-subdomain host per ADR-031). `freedMb` rides in the
  event `extra` payload (NOT a promoted column/tag), so a Discover `&field=freedMb`
  projection returns null — instead list events with
  `GET https://<org-slug>.sentry.io/api/0/organizations/<slug>/events/?query=feature:cron-workspace-gc+level:info`
  then read `extra.freedMb` from the latest event-detail (`GET .../events/<event-id>/`).
  **Automation:** this is a read-only `gh`/`curl` Sentry-API probe, NOT
  operator dashboard-watching — if a Sentry MCP/CLI is available at work-time,
  prescribe the exact query + a deterministic "freedMb present in last event"
  verdict rather than punting to a human. Folded into the post-merge step, not
  left as a manual eyeball.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — observability/tooling change against an
already-provisioned in-process cron. No product/UI surface (no path under
`components/**`, `app/**/page.tsx`, or any UI-surface term), no legal/regulated
data (the payload is disk-capacity arithmetic + a `soleur-` dir basename, no
userId/PII), no new infrastructure (Phase 2.8 IaC gate: skipped — no server,
service, secret, vendor, or persistent process introduced; the cron and its
Sentry monitor already exist in `apps/web-platform/infra/sentry/cron-monitors.tf:522`).

## Observability

This change **is** the observability feature, so the schema below describes the
signal being added, not a side-effect.

```yaml
liveness_signal:
  what: "scheduled-workspace-gc Sentry Crons heartbeat (unchanged — proves the sweep RAN)"
  cadence: "every 6h + on cron/workspace-gc.manual-trigger"
  alert_target: "Sentry Crons monitor scheduled-workspace-gc (apps/web-platform/infra/sentry/cron-monitors.tf:522)"
  configured_in: "cron-workspace-gc.ts:238-245 postSentryHeartbeat; monitor in cron-monitors.tf"
error_reporting:
  destination: "Sentry (captureMessage). NEW: level:info every-run reclaim event via infoSilentFallback; EXISTING: level:warning low-disk event via warnSilentFallback; per-dir rm failures via reportSilentFallback (error)"
  fail_loud: "true — Sentry emit is shim-guarded (never throws into the GC step); pino mirror is the durable in-container fallback"
failure_modes:
  - mode: "GC freed disk on a healthy run (the previously-silent case)"
    detection: "Sentry events: query=feature:cron-workspace-gc level:info — extra.freedMb / freeMbAfter present on every run"
    alert_route: "informational (no page); pulled on demand after a manual trigger"
  - mode: "volume still under floor after sweeping everything"
    detection: "Sentry events: query=feature:cron-workspace-gc level:warning op:workspace-gc-low-after-sweep"
    alert_route: "warning-level Sentry event (existing, unchanged)"
  - mode: "sweep never ran (scheduler dead / fn dropped)"
    detection: "missed Sentry Crons check-in on scheduled-workspace-gc"
    alert_route: "Sentry Crons monitor turns red (existing)"
logs:
  where: "pino stdout (container) via the helper's logger.info mirror; Sentry events (durable, queryable)"
  retention: "Sentry event retention (org default); pino stdout is ephemeral"
discoverability_test:
  command: "fire cron/workspace-gc.manual-trigger via /soleur:trigger-cron, then GET https://<org-slug>.sentry.io/api/0/organizations/<slug>/events/?query=feature:cron-workspace-gc+level:info"
  expected_output: "an info event whose extra carries freedMb, freeMbBefore, freeMbAfter, sweptCount, root — confirmable with zero SSH"
```

## Files to Edit

- `apps/web-platform/server/observability.ts` — add `infoSilentFallback` helper.
- `apps/web-platform/server/inngest/functions/cron-workspace-gc.ts` — import +
  replace the success-path `logger.info` with `infoSilentFallback`.
- `apps/web-platform/test/server/inngest/cron-workspace-gc.test.ts` — mock +
  import `infoSilentFallback`; add AC4/AC5/AC6 assertions.
- `apps/web-platform/test/observability.test.ts` — add an `infoSilentFallback`
  describe block mirroring the existing `warnSilentFallback` block at `:344`
  (Sentry `level:"info"` + tags + extra + `hashExtraUserId` pseudonymization
  parity).

## Files to Create

None.

## Open Code-Review Overlap

None — no open `code-review` issue touches `observability.ts`,
`cron-workspace-gc.ts`, or their tests at plan time (this issue itself is the
only open item against `cron-workspace-gc`).

## Alternative Approaches Considered

| Approach | Verdict |
| --- | --- |
| Fold reclaim numbers into the heartbeat payload | **Rejected** — `postSentryHeartbeat` POSTs a payload-less Sentry Crons check-in URL; no event body is accepted (`_cron-shared.ts:160`). |
| Raw inline `Sentry.captureMessage(level:"info")` in the cron | **Rejected** — duplicates the tag/extra pseudonymization + shim-guard machinery the `report/warnSilentFallback` pair already centralizes; drift risk. Precedent for inline info-`captureMessage` exists (`leader-document-resolver.ts`) but the cron should match the silent-fallback family it already imports from. |
| `Sentry.addBreadcrumb(level:"info")` | **Rejected** — breadcrumbs are NOT independently queryable; they only surface attached to a *subsequently captured event*. The operator needs a standalone pulled event. |
| Reuse `warnSilentFallback` for the every-run emit | **Rejected** — would emit a `level:warning` event on every healthy run, polluting the actionable-warning channel and defeating on-call's ability to filter actionable low-disk events. Info-level keeps the two signals separable. |

## Test Scenarios

1. **Healthy reclaim (above floor):** info event fires with full payload; warn
   does NOT fire. (AC4)
2. **Low disk (below floor after sweep):** info AND warn both fire. (AC5)
3. **Absent volume (ENOENT root):** neither info nor warn fires; heartbeat ok.
   (AC6)
4. **statfs-after fails (EIO):** `freedMb` degrades to 0; info event still fires
   with `freedMb: 0` (no NaN). *(extend the existing "freedMb falls back to 0"
   test at `:179-197` to also assert the info emit carries `freedMb: 0`.)*

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only
  `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan`
  Phase 4.6. (This plan fills it — threshold `aggregate pattern`.)
- **Test runner is vitest here, not bun.** `apps/web-platform/bunfig.toml`
  ignores all test discovery and the package runs **vitest**
  (`apps/web-platform/vitest.config.ts`). At work-time, verify the test command
  via `apps/web-platform/package.json scripts.test` and run via
  `./node_modules/.bin/vitest run <path>` — do NOT prescribe `bun test`. Also
  confirm the two touched test files match vitest's `include:` globs
  (`test/**/*.test.ts`) — both already live under `test/server/...` so they do.
- **Replace, don't duplicate, the pino log.** The success-path `logger.info` at
  `:201-204` must be *replaced* by `infoSilentFallback` (whose body re-emits the
  same pino `logger.info` mirror internally), not left alongside it — otherwise
  the same line double-logs to stdout.
- **Keep info and warn as distinct Sentry levels.** Do not collapse the every-run
  info emit and the low-disk warn into one call; on-call filters
  `level:warning feature:cron-workspace-gc` for actionable signals.
- **No userId in the payload** — the `extra` is disk arithmetic + a `soleur-` dir
  basename only; the helper's `hashExtraUserId` boundary is a no-op here but
  preserved for symmetry. Do not add any path beyond `root` or any user-derived
  field to the `extra`.
</content>
</invoke>
