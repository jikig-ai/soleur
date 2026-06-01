---
issue: 4734
type: feat
app: web-platform
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

# feat(ops): on-demand cron trigger route for `*.manual-trigger` events

## Enhancement Summary

**Deepened on:** 2026-06-01
**Gates passed:** 4.6 User-Brand Impact (threshold `single-user incident`), 4.7
Observability (5 fields, no-SSH discoverability test), 4.8 PAT-shaped variable (none).

### Key corrections from deepen-plan (implementation-realism passes)

1. **`sendInngestWithRetry` arg #1 is a thunk, not a payload.** v1 prescribed
   `sendInngestWithRetry({ name, data }, ctx)` — a type error. Corrected to
   `sendInngestWithRetry(() => inngest.send({ name, data }), { feature })` with a dynamic
   `import("@/server/inngest/client")` inside the handler, mirroring
   `app/api/webhooks/github/route.ts:285-286` (`send-with-retry.ts:29`).
2. **Module-load fail-closed throw.** `cron-inngest-cron-watchdog.ts:45` statically
   imports the Inngest client (throws on missing `INNGEST_SIGNING_KEY` outside build
   phase). Importing `EXPECTED_CRON_FUNCTIONS` from it would fire that throw at route-load
   time. Resolved by extracting a client-free `cron-manifest.ts` leaf module (new Files to
   Create + watchdog re-export edit) — not deferred to /work.
3. **`-target=` count corrected** 74 → **76** (verified `grep -cE '^\s*-target='`); new
   total after adding the 4 secret targets is 80.
4. **Concurrency bound on replay abuse verified** — `cron-bug-fixer.ts:882-884` caps
   `{ scope: "account", key: "cron-platform", limit: 1 }`, bounding manual-trigger replay
   to one extra in-flight run (folded into security Open Question 3).

### Confirmed precedents
- Auth primitive shape (`timingSafeEqual` + length-guard, fail-closed `readSecret`):
  `kb-drift-ingest/route.ts:64-73` (HMAC there; Bearer here per issue prose).
- IaC: `random_id` (byte_length 32) → `doppler_secret` (`.hex`, `ignore_changes=[value]`)
  per `inngest.tf:31-93`; opaque-secret `.hex` shape matches the event-key precedent.
- Allowlist drift guard: `function-registry-count.test.ts (e)` already asserts
  `EXPECTED_CRON_FUNCTIONS` == cron-*.ts file set (33 entries).

> ✨ Closes #4734. An authenticated internal API route `POST /api/internal/trigger-cron`
> that dispatches a whitelisted `cron/<name>.manual-trigger` event via the app's
> already-wired Inngest client, so a cron can be fired on demand without SSH-ing to
> the Hetzner box and curling the loopback Inngest event endpoint (a forbidden manual
> prod op). Surfaced while trying to fire the went-quiet detector (#4717) on demand.

## Overview

Self-hosted Inngest (ADR-030) runs loopback-only on the Hetzner box
(`INNGEST_BASE_URL=http://host.docker.internal:8288` / `http://127.0.0.1:8288`). The
Next.js app container reaches the Inngest server (it already calls `inngest.send` from
the Stripe-webhook and weekly-analytics cascades), but there is **no operator/agent-facing
path** to fire a cron's `*.manual-trigger` event. The fix is pure app code: a single
internal route that authenticates with a fail-closed shared secret, validates the
requested event against the drift-guarded cron allowlist, and dispatches it via the
existing hardened `sendInngestWithRetry` helper.

This is agent-native (an agent or operator can POST it), reusable for every
`*.manual-trigger` cron, and carries **no deploy-pipeline / infra runtime coupling** —
the considered "hook into the HMAC+CF-Access deploy webhook" alternative was rejected
because it couples to `terraform_data.deploy_pipeline_fix` (drift gate + terraform apply).

**Brand-survival threshold = `single-user incident`.** Several allowlisted crons
mutate state or spend money (`bug-fixer` opens PRs; `content-generator`,
`competitive-analysis`, `growth-execution`, `daily-triage` spend Anthropic/API budget).
An under-authed trigger endpoint that can fire mutating/paid crons is an abuse vector,
so the auth strength + allowlist scope are the load-bearing review questions.

## Research Reconciliation — Spec vs. Codebase

| Issue claim | Reality (verified on this branch) | Plan response |
| --- | --- | --- |
| "reuse the secret-auth pattern from `app/api/internal/kb-drift-ingest/route.ts`" | kb-drift-ingest uses **HMAC-SHA256** (`x-soleur-kb-drift-signature`), NOT a Bearer/shared-secret. The issue's prose then specifies "Bearer/shared-secret, constant-time compare". | Reuse the **primitive shapes** from kb-drift-ingest (`timingSafeEqual`, fail-closed `readSigningKey()` pattern, `reportSilentFallback` mirror) but implement a **Bearer shared-secret** comparison per the issue prose — not HMAC. Document the divergence in the route header. |
| "32 crons register a `cron/<name>.manual-trigger` event" | There are **33** `cron-*.ts` files and `EXPECTED_CRON_FUNCTIONS` has **33** entries (`cron-inngest-cron-watchdog.ts:86-119`), drift-guarded by `function-registry-count.test.ts` test `(e)` (`new Set(EXPECTED_CRON_FUNCTIONS)).toEqual(new Set(cronFiles))`). A 34th distinct `*.manual-trigger` string (`cron/cf-token-expiry-check.manual-trigger`) belongs to an `event-`-prefixed function, NOT a `cron-`. | The allowlist is **`EXPECTED_CRON_FUNCTIONS.map(manualTriggerEventFor)`** — exactly the 33 cron events, already drift-guarded. Do NOT hardcode a parallel 32/33-string array (it would silently drift). The "32" in the issue is stale by one; the plan uses the live manifest, so the exact count is self-correcting. |
| "`inngest.send({ name, data })` → 202" | The hardened call path is `sendInngestWithRetry` (`server/inngest/send-with-retry.ts:29`), whose signature is **`sendInngestWithRetry(fn: () => Promise<unknown>, context: { feature; deliveryId?; eventId? })`** — the first arg is a **thunk**, NOT a `{ name, data }` payload object. The canonical route precedent is `app/api/webhooks/github/route.ts:285-286`: `const { inngest } = await import("@/server/inngest/client"); await sendInngestWithRetry(() => inngest.send({…}), { feature })`. The dynamic `import()` of the client inside the handler defers the client's load-time fail-closed `throw` to request time. | Dispatch via `await sendInngestWithRetry(() => inngest.send({ name, data: { trigger: "manual-api", at } }), { feature: "trigger-cron" })`, with `const { inngest } = await import("@/server/inngest/client")` inside the handler. On exhausted-retry failure (the call rejects) mirror with `reportSilentFallback(err, { feature: "trigger-cron", op: "dispatch", extra: { event } })` and return 502. Return **202 Accepted** on success. |
| "`INNGEST_MANUAL_TRIGGER_SECRET` provisioned in Doppler dev+prd as a generated `random` value (NOT operator-minted) + `.env.example`" | The canonical pattern in `apps/web-platform/infra/inngest.tf` is `random_id` (byte_length 32) → `doppler_secret` (prd + dev), `ignore_changes = [value]`. `.env.example` currently has **no** INNGEST entries (Inngest keys are Doppler-only). | Add `INNGEST_MANUAL_TRIGGER_SECRET` as 2 `random_id` + 2 `doppler_secret` resources in `inngest.tf`; add a documented commented entry to `.env.example` (consistent with file style). |

## User-Brand Impact

- **If this lands broken, the user experiences:** a `POST /api/internal/trigger-cron`
  that either (a) silently 404/503s when the operator/agent tries to fire a cron on
  demand (fail-closed misconfig), or (b) — the dangerous mode — accepts unauthenticated
  requests and lets an attacker fire `cron/bug-fixer.manual-trigger` (opens PRs against
  the user's repo) or `cron/content-generator.manual-trigger` /
  `cron/competitive-analysis.manual-trigger` (burns the user's Anthropic/API budget).
- **If this leaks, the user's money / workflow is exposed via:** the trigger endpoint
  itself — a leaked or weak `INNGEST_MANUAL_TRIGGER_SECRET`, or a missing/incorrect
  constant-time compare, lets a third party drive the user's paid + mutating crons at
  will (budget drain + unsolicited PRs / public-repo activity attributed to the user).
- **Brand-survival threshold:** `single-user incident` — an under-authed trigger
  endpoint that can fire mutating/paid crons is an abuse vector.

> CPO sign-off required at plan time before `/work` begins (`requires_cpo_signoff: true`).
> `user-impact-reviewer` will be invoked at review-time (handled by the review skill's
> conditional-agent block). The brainstorm phase was skipped (direct plan entry); the
> CPO domain leader is invoked in Phase 2.5 below to provide the framing-time product
> sign-off on the chosen approach.

## Files to Create

- `apps/web-platform/app/api/internal/trigger-cron/route.ts` — the route handler
  (`POST` only; `cq-nextjs-route-files-http-only-exports` compliant — no non-HTTP exports).
- `apps/web-platform/server/inngest/cron-manifest.ts` — **client-free leaf module**
  holding `EXPECTED_CRON_FUNCTIONS` + `manualTriggerEventFor` (moved out of
  `cron-inngest-cron-watchdog.ts`, which statically imports the Inngest client and would
  trip the fail-closed throw at route-load time — see Phase 1 load-order hazard). No
  `@/server/inngest/client` import. The watchdog re-exports these symbols from here so
  `function-registry-count.test.ts (e)` stays green.
- `apps/web-platform/lib/inngest/manual-trigger-allowlist.ts` — sibling module exporting
  `MANUAL_TRIGGER_EVENTS: ReadonlySet<string>` derived from `EXPECTED_CRON_FUNCTIONS` +
  `manualTriggerEventFor` (imported from `cron-manifest.ts`), plus
  `isAllowlistedManualTrigger(name): boolean`. Kept in a sibling module (NOT the route
  file) per `cq-nextjs-route-files-http-only-exports`, and so the allowlist is
  unit-testable without importing the route.
- `apps/web-platform/test/server/internal/trigger-cron-route.test.ts` — RED→GREEN route
  tests (vi.hoisted mocks, `import { POST }`, `makeRequest` helper — mirrors
  `kb-drift-ingest-route.test.ts`).
- `apps/web-platform/test/lib/inngest/manual-trigger-allowlist.test.ts` — asserts the
  allowlist equals `EXPECTED_CRON_FUNCTIONS.map(manualTriggerEventFor)` (drift guard:
  if a `cron-*.ts` is added/removed, `function-registry-count.test.ts (e)` updates
  `EXPECTED_CRON_FUNCTIONS`, and this allowlist follows automatically — no second list
  to maintain).

## Files to Edit

- `apps/web-platform/server/inngest/functions/cron-inngest-cron-watchdog.ts` — move
  `EXPECTED_CRON_FUNCTIONS` + `manualTriggerEventFor` to the new `cron-manifest.ts` leaf
  module and `export { EXPECTED_CRON_FUNCTIONS, manualTriggerEventFor } from "../cron-manifest"`
  (re-export). No behavior change; `function-registry-count.test.ts (e)` and
  `cron-inngest-cron-watchdog.test.ts` (which unit-test `manualTriggerEventFor`) keep
  importing from the watchdog path. Verify both test files still pass at /work.
- `apps/web-platform/infra/inngest.tf` — add 2 `random_id` (`inngest_manual_trigger_secret_prd`,
  `_dev`, `byte_length = 32`) + 2 `doppler_secret` (`config = "prd"` / `"dev"`,
  `name = "INNGEST_MANUAL_TRIGGER_SECRET"`, `value = random_id.<name>.hex`,
  `ignore_changes = [value]`). Update the file header comment block
  ("4 random_id … 5 doppler_secret" → "6 random_id … 7 doppler_secret").
- `apps/web-platform/infra/inngest.test.sh` — bump the count assertions
  (`random_id resources (4)` → `(6)`, `doppler_secret resources (5)` → `(7)`) and add
  per-resource grep asserts for the 4 new resources. The `byte_length = 32` floor
  (`-ge 4`) and `ignore_changes` floor (`-ge 5`) remain valid (the new resources also
  carry both), but tighten the comments to the new totals.
- `.github/workflows/apply-web-platform-infra.yml` — add **4 new `-target=` lines**
  (`random_id.inngest_manual_trigger_secret_prd`, `_dev`,
  `doppler_secret.inngest_manual_trigger_secret_prd`, `_dev`) to the `-target=`-scoped
  apply (currently 76 targets → 80; verified `grep -cE '^\s*-target=' = 76` at deepen-plan).
  Place adjacent to the existing
  `-target=…inngest_*` block (workflow lines ~302-310). **Without this, the new secret
  is never applied to Doppler** and the route fail-closes in prod forever.
- `apps/web-platform/.env.example` — add a documented commented
  `# INNGEST_MANUAL_TRIGGER_SECRET=` entry with a one-line description (generated random,
  Doppler-provisioned; used by `POST /api/internal/trigger-cron`).

## Open Code-Review Overlap

None. (Verified: no open `code-review` issue body references
`trigger-cron`, `manual-trigger-allowlist`, or `inngest.tf` for this surface.)

## Implementation Phases

> TDD: each route branch ships RED→GREEN. The allowlist module and its drift test land
> first (they are the contract the route depends on), then the route, then the IaC.

### Phase 1 — Allowlist module + drift test (contract first)

1. Create `lib/inngest/manual-trigger-allowlist.ts`:
   ```ts
   // Import from the CLIENT-FREE leaf module (see load-order hazard below),
   // NOT from cron-inngest-cron-watchdog (which imports the Inngest client).
   import {
     EXPECTED_CRON_FUNCTIONS,
     manualTriggerEventFor,
   } from "@/server/inngest/cron-manifest";

   export const MANUAL_TRIGGER_EVENTS: ReadonlySet<string> = new Set(
     EXPECTED_CRON_FUNCTIONS.map(manualTriggerEventFor),
   );

   export function isAllowlistedManualTrigger(name: unknown): name is string {
     return typeof name === "string" && MANUAL_TRIGGER_EVENTS.has(name);
   }
   ```
   > **Load-order hazard (confirmed at deepen-plan — this is NOT optional).**
   > `cron-inngest-cron-watchdog.ts:45` does `import { inngest } from "@/server/inngest/client"`
   > at module top-level. Importing `EXPECTED_CRON_FUNCTIONS` from it therefore
   > transitively loads the client, which **throws** on missing `INNGEST_SIGNING_KEY`
   > outside `NEXT_PHASE=phase-production-build` (`client.ts:30-33`). Because the
   > allowlist module imports the watchdog **statically**, that throw would fire at the
   > route module's load time (defeating the route's dynamic-import-of-client
   > mitigation) AND in the allowlist unit test.
   >
   > **Required fix: extract the manifest into a client-free leaf module.** Move
   > `EXPECTED_CRON_FUNCTIONS` + `manualTriggerEventFor` into a new leaf file (e.g.
   > `apps/web-platform/server/inngest/cron-manifest.ts`, no client import) and have
   > `cron-inngest-cron-watchdog.ts` re-export from it (keeps `function-registry-count.test.ts (e)`
   > green — it imports `EXPECTED_CRON_FUNCTIONS` from the watchdog path, which still
   > re-exports). The allowlist module + the route then import from the leaf module and
   > never touch the client. (Add `apps/web-platform/server/inngest/cron-manifest.ts` to
   > Files to Create at /work; update the watchdog import in Files to Edit.)
   >
   > Fallback if leaf extraction is undesirable: set `NEXT_PHASE` via `vi.hoisted` in the
   > allowlist test (mirrors `function-registry-count.test.ts:8`) — but this does NOT fix
   > the route-runtime load-order throw, so the leaf extraction is the load-bearing path.
2. RED→GREEN `manual-trigger-allowlist.test.ts`: assert
   `MANUAL_TRIGGER_EVENTS` equals `new Set(EXPECTED_CRON_FUNCTIONS.map(manualTriggerEventFor))`
   and that a known event (`cron/workspace-sync-health.manual-trigger`) is allowlisted
   while a non-cron string (`cron/cf-token-expiry-check.manual-trigger`, `evil`,
   `cron/bug-fixer.run`) is rejected.

### Phase 2 — Route handler (RED→GREEN per branch)

`apps/web-platform/app/api/internal/trigger-cron/route.ts`:

```ts
import { timingSafeEqual } from "node:crypto";
import { NextResponse } from "next/server";
import { reportSilentFallback } from "@/server/observability";
import { sendInngestWithRetry } from "@/server/inngest/send-with-retry";
import { isAllowlistedManualTrigger } from "@/lib/inngest/manual-trigger-allowlist";

// NOTE: the Inngest client is imported DYNAMICALLY inside POST (see below),
// mirroring app/api/webhooks/github/route.ts:285 — this defers the client's
// load-time fail-closed throw (missing INNGEST_SIGNING_KEY) to request time
// and keeps the route module importable in `next build` page-data collection.

function readSecret(): string | null {
  const v = process.env.INNGEST_MANUAL_TRIGGER_SECRET;
  return v && v.length > 0 ? v : null;
}

function bearerMatches(header: string | null, secret: string): boolean {
  if (!header) return false;
  const token = header.startsWith("Bearer ") ? header.slice("Bearer ".length) : header;
  const a = Buffer.from(token, "utf8");
  const b = Buffer.from(secret, "utf8");
  if (a.length !== b.length) return false;        // length-guard before timingSafeEqual
  return timingSafeEqual(a, b);
}

export async function POST(request: Request) {
  const secret = readSecret();
  if (!secret) {
    // fail-closed: indistinguishable-from-absent. 503 (server misconfigured), NOT 401.
    return NextResponse.json({ error: "Not available" }, { status: 503 });
  }
  if (!bearerMatches(request.headers.get("authorization"), secret)) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  let body: unknown;
  try { body = await request.json(); } catch {
    return NextResponse.json({ error: "Malformed JSON" }, { status: 400 });
  }
  const name = (body as { event?: unknown } | null)?.event;
  if (!isAllowlistedManualTrigger(name)) {
    return NextResponse.json({ error: "Event not allowlisted" }, { status: 400 });
  }

  try {
    const { inngest } = await import("@/server/inngest/client");
    await sendInngestWithRetry(
      () => inngest.send({ name, data: { trigger: "manual-api", at: new Date().toISOString() } }),
      { feature: "trigger-cron" },
    );
  } catch (err) {
    reportSilentFallback(err, { feature: "trigger-cron", op: "dispatch", extra: { event: name } });
    return NextResponse.json({ error: "Dispatch failed" }, { status: 502 });
  }
  return NextResponse.json({ dispatched: name, trigger: "manual-api" }, { status: 202 });
}
```

> `sendInngestWithRetry` arg #1 is a **thunk** `() => Promise<unknown>` (see
> `send-with-retry.ts:29`), NOT a payload object — passing `{ name, data }` directly is
> a type error. Mirror the `app/api/webhooks/github/route.ts:285-286` precedent verbatim.

RED→GREEN tests, one branch each (mirror `kb-drift-ingest-route.test.ts` mock harness —
mock `@/server/inngest/send-with-retry`, `@/server/observability`):
- secret unset → **503** (fail-closed; assert no `sendInngestWithRetry` call).
- valid secret + allowlisted event → **202**, `sendInngestWithRetry` called once; assert
  arg #2 is `{ feature: "trigger-cron" }`. The thunk (arg #1) wraps `inngest.send` — to
  assert the dispatched envelope, mock `@/server/inngest/client` (`inngest.send` as a
  `vi.fn()`) and invoke the captured thunk, OR mock `sendInngestWithRetry` to call its
  `fn` arg and assert `inngest.send` was called with
  `{ name, data: { trigger: "manual-api", at: <ISO> } }`.
- missing / wrong / wrong-length Bearer → **401** (assert no dispatch).
- allowlisted event + malformed JSON → **400**.
- valid secret + non-allowlisted event (`cron/cf-token-expiry-check.manual-trigger`,
  `evil`) → **400** (assert no dispatch).
- `sendInngestWithRetry` rejects → **502** + `reportSilentFallback` called with
  `{ feature: "trigger-cron", op: "dispatch", extra: { event } }`.

> Signature confirmed at deepen-plan: `sendInngestWithRetry(fn: () => Promise<unknown>,
> context: { feature: string; deliveryId?; eventId? })` (`send-with-retry.ts:29`). Mock
> harness mirrors `kb-drift-ingest-route.test.ts`; also `vi.mock("@/server/inngest/client")`
> so the dynamic `import()` resolves to the mocked `inngest`.

### Phase 3 — IaC (Doppler secret, dev + prd)

1. `inngest.tf`: add the 4 resources (pattern verbatim from the existing
   `inngest_signing_key_*` / `inngest_event_key_*` blocks — `random_id` byte_length 32,
   `doppler_secret` value `random_id.<name>.hex`, `lifecycle { ignore_changes = [value] }`).
   No `signkey-`/`signkey-test-` prefix is needed (this secret is opaque to the SDK; a
   bare 64-hex value is fine). Update the header comment totals.
2. `inngest.test.sh`: bump count comments to `(6)` / `(7)` and add the 4 per-resource
   grep asserts.
3. `apply-web-platform-infra.yml`: add the 4 `-target=` lines next to the existing
   inngest targets.
4. `.env.example`: add the documented commented entry.

> Apply path: merging this PR triggers `apply-web-platform-infra.yml` (path filter on
> `apps/web-platform/infra/*.tf`), which runs the `-target=`-scoped
> `terraform apply` and writes the new Doppler secrets. The merge IS the authorization
> (`hr-menu-option-ack-not-prod-write-auth`). Container restart (which re-reads Doppler
> env) is handled by `web-platform-release.yml` on merges touching
> `apps/web-platform/**` — so the route picks up the new secret without an operator step.

### Phase 4 — Post-merge exercise (AC4)

After the secret is applied and the container restarts, fire
`cron/workspace-sync-health.manual-trigger` via the new route to exercise the
went-quiet detector (#4717) in prod, and confirm a 202 + the cron's Sentry monitor
check-in. See `### Post-merge (operator)` below for the exact automatable command.

## Acceptance Criteria

### Pre-merge (PR)

- [x] `POST /api/internal/trigger-cron` dispatches an allowlisted event (202) and calls
      `sendInngestWithRetry` once with `{ name, data: { trigger: "manual-api", at } }`.
- [x] **401** on missing / wrong / wrong-length Bearer (no dispatch).
- [x] **503** (fail-closed) when `INNGEST_MANUAL_TRIGGER_SECRET` is unset (no dispatch).
- [x] **400** on non-allowlisted event AND on malformed JSON (no dispatch).
- [x] **502** + `reportSilentFallback({ feature: "trigger-cron", op: "dispatch" })`
      when `sendInngestWithRetry` throws.
- [x] Allowlist is derived from `EXPECTED_CRON_FUNCTIONS.map(manualTriggerEventFor)`
      (no hardcoded parallel list); `manual-trigger-allowlist.test.ts` asserts equality
      so adding/removing a `cron-*.ts` cannot silently drift the allowlist.
- [x] `inngest.tf` declares `random_id.inngest_manual_trigger_secret_{prd,dev}` +
      `doppler_secret.inngest_manual_trigger_secret_{prd,dev}` (byte_length 32,
      `ignore_changes = [value]`); `inngest.test.sh` asserts all 4 and the bumped counts
      (`bash apps/web-platform/infra/inngest.test.sh` exits 0).
- [x] `apply-web-platform-infra.yml` contains the 4 new `-target=` lines (grep returns 4).
- [x] `.env.example` documents `INNGEST_MANUAL_TRIGGER_SECRET`.
- [x] Route file exports only `POST` (`cq-nextjs-route-files-http-only-exports`).
- [ ] security-sentinel review of the auth + allowlist signs off (the
      mutating/paid-cron abuse surface is the key risk — see Open Questions).
- [ ] PR body uses `Closes #4734` (the route is pure app code — closure at merge is
      correct; the post-merge exercise in AC4 is verification, not the deliverable).

### Post-merge (operator)

- [ ] After the Doppler secret applies and the container restarts, fire
      `cron/workspace-sync-health.manual-trigger` to exercise went-quiet (#4717) in prod.
      **Automation: feasible** — `gh secret`/`doppler` read + a single authenticated
      curl. Bake into ship Phase post-merge verification:
      ```bash
      SECRET=$(doppler secrets get INNGEST_MANUAL_TRIGGER_SECRET -p soleur -c prd --plain)
      curl -sS -o /dev/null -w '%{http_code}\n' -X POST https://<app-host>/api/internal/trigger-cron \
        -H "Authorization: Bearer $SECRET" -H 'Content-Type: application/json' \
        -d '{"event":"cron/workspace-sync-health.manual-trigger"}'   # expect 202
      ```
      Then confirm the went-quiet detector ran (Sentry `op:went-quiet` event or the
      cron's Sentry monitor check-in) via the Sentry API — NOT dashboard eyeballing
      (`hr-no-dashboard-eyeball-pull-data-yourself`).

## Domain Review

**Domains relevant:** Engineering (CTO), Product (CPO — `single-user incident` threshold).

### Engineering (CTO)

**Status:** reviewed (inline, direct-plan entry — no Task subagent available in this harness)
**Assessment:** Pure app-code route reusing established primitives (`timingSafeEqual`
fail-closed pattern from kb-drift-ingest; `sendInngestWithRetry` + `reportSilentFallback`).
IaC follows the `random_id` → `doppler_secret` precedent in `inngest.tf` exactly. The
one cross-cutting risk is the `-target=`-allowlist + `inngest.test.sh` count coupling
(Sharp Edge: extend the hand-maintained `-target=` set) — covered explicitly in
Files to Edit. No new infrastructure runtime process, no schema change, no deploy-pipeline
coupling. Routes through `apply-web-platform-infra.yml` (the canonical IaC boundary).

### Product/UX Gate

**Tier:** none (no user-facing UI surface — internal API route only; no
`components/**`, `app/**/page.tsx`, or `app/**/layout.tsx` created).
**Decision:** CPO sign-off required at plan time (`requires_cpo_signoff: true`,
`single-user incident` threshold) — product owner ack on the *approach* (internal route
with fail-closed Bearer + drift-guarded allowlist). Invoke CPO domain leader, or confirm
CPO has reviewed, before `/work` begins. No wireframes (no UI). No copywriter (no copy).

## Infrastructure (IaC)

### Terraform changes
- Files: `apps/web-platform/infra/inngest.tf` (extend existing root).
- New resources: `random_id.inngest_manual_trigger_secret_prd`, `…_dev`;
  `doppler_secret.inngest_manual_trigger_secret_prd`, `…_dev`.
- Providers: `hashicorp/random`, `doppler` — already pinned in the root; no new provider.
- Sensitive variables: none new. Doppler provider auth via existing
  `TF_VAR_DOPPLER_TOKEN_TF` (`prd_terraform` config); the secret VALUE is TF-generated
  (`random_id`), not an operator-supplied variable.

### Apply path
- **(b) cloud-init + idempotent apply via `apply-web-platform-infra.yml`** — the existing
  `-target=`-scoped auto-apply workflow fires on merge of any PR touching
  `apps/web-platform/infra/*.tf`. Add 4 `-target=` lines. Zero downtime; blast radius =
  2 new Doppler keys in dev + prd configs. The app container re-reads Doppler env on the
  `web-platform-release.yml` restart that the same merge triggers.

### Distinctness / drift safeguards
- `dev != prd`: separate `random_id` resources per config (mirrors the
  `inngest_signing_key_{prd,dev}` distinctness invariant `inngest.test.sh` already encodes).
- `lifecycle { ignore_changes = [value] }` on both `doppler_secret` resources — rotate via
  `terraform taint random_id.inngest_manual_trigger_secret_<env> && terraform apply`.
- Secret value lands in `terraform.tfstate` (R2-backed encrypted backend — same as the
  existing Inngest keys; no new exposure class).

### Vendor-tier reality check
- N/A — no paid-tier-gated resource (Doppler secret + random_id are free; no Better Stack
  monitor added for this route).

## Observability

```yaml
liveness_signal:
  what: HTTP 202 from POST /api/internal/trigger-cron on a valid dispatch; the fired
        cron's own Sentry monitor check-in is the downstream liveness proof.
  cadence: on-demand (per trigger call) — not a scheduled signal.
  alert_target: Sentry (the dispatched cron's existing sentry_cron_monitor) +
                Sentry issue stream (op:dispatch failures via reportSilentFallback).
  configured_in: apps/web-platform/server/observability.ts (reportSilentFallback) +
                 apps/web-platform/infra/sentry/cron-monitors.tf (per-cron monitors).
error_reporting:
  destination: Sentry (reportSilentFallback to captureException/captureMessage) + pino stdout.
  fail_loud: true — dispatch failure returns 502 and mirrors to Sentry with
             tags { feature trigger-cron, op dispatch }; secret-unset returns 503.
failure_modes:
  - mode: secret unset (Doppler misconfig) so route fail-closes (503)
    detection: 503 response code; route returns "Not available"
    alert_route: caller observes 503 (operator/agent); no false-positive Sentry noise.
  - mode: Inngest loopback unreachable (server down) so sendInngestWithRetry exhausts retries
    detection: 502 response + Sentry op:dispatch event
    alert_route: Sentry issue stream (feature:trigger-cron op:dispatch).
  - mode: non-allowlisted event submitted (probe / typo)
    detection: 400 response (no dispatch); not Sentry-mirrored (expected 4xx).
    alert_route: none (expected client error per cq-silent-fallback exempt list).
logs:
  where: container stdout (pino) to Better Stack; Sentry for dispatch failures.
  retention: per existing Better Stack + Sentry retention (no new sink).
discoverability_test:
  command: |
    SECRET=$(doppler secrets get INNGEST_MANUAL_TRIGGER_SECRET -p soleur -c prd --plain)
    curl -sS -o /dev/null -w '%{http_code}\n' -X POST https://APP_HOST/api/internal/trigger-cron \
      -H "Authorization: Bearer $SECRET" -H 'Content-Type: application/json' \
      -d '{"event":"cron/workspace-sync-health.manual-trigger"}'
  expected_output: "202"
```

## Open Questions (for security-sentinel — load-bearing at `single-user incident`)

1. **Allowlist scope: all 33 crons, or narrow to read-only?** Several allowlisted crons
   mutate state / spend money: `cron/bug-fixer.manual-trigger` (opens PRs),
   `cron/content-generator`, `cron/competitive-analysis`, `cron/growth-execution`,
   `cron/daily-triage` (Anthropic/API budget). With a strong fail-closed Bearer secret,
   the **recommended default is the full manifest** (the secret is the trust boundary;
   narrowing creates a second hand-maintained list that drifts, defeating the
   `EXPECTED_CRON_FUNCTIONS`-derived design). security-sentinel must confirm the auth
   strength justifies the full allowlist, OR specify per-event scoping (e.g., a
   `mutating: false` subset for an unauthenticated-but-rate-limited tier — NOT proposed
   here). **Decision owner: security-sentinel review + CPO sign-off.**
2. **Bearer vs HMAC.** kb-drift-ingest uses HMAC (signs the body). This route carries a
   trivial body (event name only) and no replay-sensitive payload, so a constant-time
   Bearer compare is sufficient and matches the issue prose. security-sentinel: confirm
   Bearer (no nonce/replay protection) is acceptable for a fire-a-cron action, given the
   allowlist already bounds the blast radius to known events. (Replaying a manual trigger
   re-runs an idempotent-ish cron; the crons themselves carry their own concurrency keys.)
3. **Rate limiting.** No rate-limit primitive is proposed (the route is secret-gated).
   **Mitigating factor (verified at deepen-plan):** the mutating crons carry Inngest
   `concurrency` caps — e.g. `cron-bug-fixer.ts:882-884` declares
   `concurrency: [{ scope: "fn", limit: 1 }, { scope: "account", key: "cron-platform", limit: 1 }]`,
   so replaying its manual-trigger collapses to a single in-flight run (a flood does NOT
   fan out N concurrent PR-openers; `cron-platform`-scoped crons serialize). This bounds
   the worst case to "one extra run per dispatch", not unbounded parallelism. security-sentinel:
   confirm this concurrency bound is sufficient, or fold in a per-secret rate limit /
   short-window dedup if "one extra mutating run per request" is still unacceptable at
   `single-user incident`. If folding in, file a scope-out or extend Phase 2.

## Test Strategy

- Runner: `vitest` (`apps/web-platform` `package.json scripts.test = "vitest"`).
  Test paths under `test/**/*.test.ts` per `vitest.config.ts include`. Run a single file
  with `./node_modules/.bin/vitest run test/server/internal/trigger-cron-route.test.ts`.
- IaC test: `bash apps/web-platform/infra/inngest.test.sh` (pure grep/shell, exits 0).
- Mock harness: copy `kb-drift-ingest-route.test.ts`'s `vi.hoisted` + `vi.mock` setup
  (mock `@/server/inngest/send-with-retry`, `@/server/observability`, `@/server/logger`).

## Risks & Mitigations

- **Module-load fail-closed throw on importing `EXPECTED_CRON_FUNCTIONS` (resolved).**
  `cron-inngest-cron-watchdog.ts:45` statically imports the Inngest client, which throws
  on missing `INNGEST_SIGNING_KEY` outside `NEXT_PHASE=phase-production-build`
  (`client.ts:30-33`). Importing the manifest from the watchdog would fire that throw at
  route-load time. Mitigation (baked into Files to Create/Edit, not deferred): extract the
  manifest into the client-free `cron-manifest.ts` leaf and re-export from the watchdog.
  Precedent for the throw + the `NEXT_PHASE` workaround: `function-registry-count.test.ts:6-11`.
- **`-target=` allowlist drift (Sharp Edge).** Forgetting the 4 `-target=` lines means
  the secret never applies so permanent 503 in prod. Mitigation: explicit AC + the
  `inngest.test.sh` count bump forces the author to touch the IaC in the same PR.
- **Allowlist abuse surface.** Covered by Open Questions 1-3 + security-sentinel AC.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty or omits the threshold fails
  `deepen-plan` Phase 4.6. (This plan fills it; threshold `single-user incident`.)
- Do NOT hardcode a parallel allowlist array — derive from `EXPECTED_CRON_FUNCTIONS`
  (the issue's "32" is stale by one; the live manifest is 33 and drift-guarded).
- Adding resources to `inngest.tf` REQUIRES matching `-target=` lines in
  `apply-web-platform-infra.yml` AND count bumps in `inngest.test.sh` — three artifacts,
  same PR (the orphan IaC-test is the one plans usually miss).
- `cq-nextjs-route-files-http-only-exports`: the allowlist `Set` + helper MUST live in the
  sibling `lib/inngest/manual-trigger-allowlist.ts`, not the route file — `next build` is
  the only thing that catches a violation (not `tsc`/vitest).
- 503-vs-401 for fail-closed: return **503** when the secret is unset (server
  misconfigured, indistinguishable-from-absent) and **401** when the secret is set but the
  Bearer is wrong. Do not collapse them — the issue's AC distinguishes "404/503 when secret
  unset" from "401 on missing/wrong secret".
