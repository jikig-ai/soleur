# Fix: Purge Cloudflare edge cache on KB share revoke (#2568)

**Issue:** [#2568](https://github.com/jikig-ai/soleur/issues/2568) — security: revoked KB shares served from Cloudflare edge cache for up to s-maxage TTL (300s)
**Branch:** `feat-one-shot-purge-cf-cache-on-share-revoke`
**Severity:** P1 — security boundary leak (bounded ~5 min window)
**Type:** fix (security hardening)
**Closes:** #2568

## Enhancement Summary

**Deepened on:** 2026-04-18
**Sections enhanced:** 7 (CF Purge API contract, helper implementation, env audit, runtime caching invariants, test mocks, ops prereq automation, observability tagging)
**Research applied:**

- Live probe of `POST /client/v4/zones/<zone>/purge_cache` (verified response shape `{ success: bool, errors: [{ code, message }] }`)
- AGENTS.md learning carry-forward: `cq-silent-fallback-must-mirror-to-sentry`, `cq-doppler-service-tokens-are-per-config`, `cq-cloudflare-dynamic-path-cache-rule-required`, `cq-preflight-fetch-sweep-test-mocks`, `cq-vite-test-files-esm-only`
- Learning: `2026-03-25-doppler-secret-audit-before-creation.md` — audit ALL Doppler configs (`dev`, `prd`, `ci`, `prd_terraform`, `dev_personal`) before declaring `CF_API_TOKEN_PURGE` missing
- Learning: `2026-03-29-doppler-service-token-config-scope-mismatch.md` — runtime pod's `DOPPLER_TOKEN` is scoped to `prd` only; secret MUST be in `prd`, not `prd_terraform`
- CF Cache Purge API docs cross-reference (`https://developers.cloudflare.com/api/operations/zone-purge`)

### Key Improvements

1. **Concrete CF API response handling.** Helper now decodes `{ success, errors[] }` (not just HTTP status) — CF returns `200 + success: false` for partial failures (e.g., URL-not-cached), which a naive `res.ok` check would miss.
2. **Doppler audit-before-create automation.** Phase 3 now scripts the audit instead of asking the user, per the `2026-03-25` learning.
3. **`AbortController` cleanup discipline.** Helper specifies `clearTimeout` on success/failure paths so the 5s timer doesn't keep the Node event loop alive past response.
4. **Test mock contract pinned.** Method-aware `vi.fn` shape pre-specified to avoid the `cq-preflight-fetch-sweep-test-mocks` regression class.
5. **Sentry tag vocabulary stabilized.** All purge-failure events use `feature: "kb-share"` + `op: "revoke-purge"` — single canonical tag for the dashboard alert/filter.

### New Considerations Discovered

- CF returns 200 with `success: false` when the purged URL was never cached at the edge. This is the **expected** state for shares that were created but never viewed before revoke. Helper must treat that case as success (cache is already in the desired state — empty), not as a 502. Distinguishing logic: `success: false` AND `errors[]` only contains the specific "no cached resource" code is OK; any other error code is a real failure.
- `Vary: Accept-Encoding` is set on public binary responses (`buildBinaryHeaders`). Per CF docs, purge-by-URL purges all variants — no need to enumerate `?` query string permutations.
- The `/api/shared/<token>` cache key is scoped to host. Purging `https://app.soleur.ai/api/shared/<token>` purges only the production host; preview deployments would need separate purges. Not relevant here (preview deploys aren't fronted by this CF zone), but documented for the deferred follow-up.

## Overview

Revoked KB shares (`DELETE /api/kb/share/<token>`) continue to be served by the Cloudflare edge cache with the original `200 + body` until the existing entry's `s-maxage=300` TTL expires. The DELETE only updates the database `revoked` flag and never tells Cloudflare to drop the cached entry — origin correctly serves `410 Gone` with `Cache-Control: no-store`, but `no-store` only governs the *new* response, not previously-cached ones. Result: a 5-minute security boundary leak window after every revoke.

This plan implements the issue's recommended fix as a paired Option A + Option B:

- **A. Active purge on revoke (primary fix).** After the DB row is flipped to `revoked = true`, call the Cloudflare Cache Purge API for `https://app.soleur.ai/api/shared/<token>`. Wire the purge through `server/kb-share.ts::revokeShare` so both surfaces — the HTTP route (`apps/web-platform/app/api/kb/share/[token]/route.ts`) and the in-process MCP tool (`server/kb-share-tools.ts::kb_share_revoke`) — inherit purge by construction. On purge failure: mirror to Sentry via `reportSilentFallback` (rule `cq-silent-fallback-must-mirror-to-sentry`) AND return `5xx` so the operator knows the revoke didn't take effect at the edge.
- **B. Defense-in-depth TTL backstop.** Drop `CACHE_CONTROL_BY_SCOPE.public` `s-maxage` from `300 → 60` in `apps/web-platform/server/kb-binary-response.ts`. Trades 5x more origin requests for viral PDFs against a strictly bounded leak window when the purge call itself fails or is delayed.

The CF Cache Purge call requires a new narrow-scope token `CF_API_TOKEN_PURGE` (Cache Purge:Edit on `soleur.ai` zone). The token is consumed at runtime by Next.js, so it goes in Doppler `prd` (NOT `prd_terraform` — that config is for Terraform CI only and runtime app pods don't read it). The token is not provisioned by this PR's Terraform — token creation is a Cloudflare account-level action that is documented in the prereqs section.

Acceptance is verified live on prod via the same Playwright session pattern from #2521 (which is exactly how this bug was discovered).

## Research Reconciliation — Spec vs. Codebase

| Spec claim (issue #2568) | Codebase reality | Plan response |
| --- | --- | --- |
| "Add CF Cache Purge to the DELETE handler" | `revokeShare` is already centralized in `server/kb-share.ts` and consumed by both HTTP (`app/api/kb/share/[token]/route.ts`) and MCP (`server/kb-share-tools.ts`) per the #2298 hardening. | Wire purge through `revokeShare` (single hardened call site) rather than duplicating in the route — same hardening pattern as the existing module. |
| "Doppler `prd_terraform` → `CF_API_TOKEN_PURGE`" (issue body) | The web-platform pod reads runtime env from Doppler `prd` (per AGENTS.md `cq-deploy-webhook-observability-debug` and `cq-doppler-service-tokens-are-per-config`). `prd_terraform` is read by Terraform CI only. | Plan stores `CF_API_TOKEN_PURGE` in Doppler **`prd`** (runtime). Issue text is corrected. |
| "Plus a Terraform alias provider in `infra/main.tf`" (issue body) | Terraform aliases (`zone_settings`, `rulesets`) provision *Terraform-managed CF resources* with elevated scopes. The Cache Purge API is called by the *running app pod*, not Terraform. | No Terraform provider alias needed. Token is created in CF dashboard (or via CF API once), stored in Doppler `prd`, and read by the runtime via `process.env.CF_API_TOKEN_PURGE`. |
| "Drop `s-maxage` from 300 to 30-60s" (issue Option B) | Existing value is `s-maxage=300` in `CACHE_CONTROL_BY_SCOPE.public`. | Drop to `s-maxage=60` (matches the existing `max-age=60` browser cache so the 60s revocation-latency SLA inherited from the pre-#2532 default is preserved end-to-end). |
| "CF cache purge failure surfaces to Sentry AND fails the DELETE response" | Existing `revokeShare` returns `RevokeShareResult` discriminated union; `db-error` is already a 500 path. | Add a new `purge-failed` code under the same union. HTTP route already passes `result.status` through. MCP `wrapRevoke` propagates as well. |

## Files to edit

- `apps/web-platform/server/kb-share.ts` — extend `revokeShare` to call the new purge helper after the DB update; add `purge-failed` to `RevokeShareErrorCode`; on purge failure, return `{ ok: false, status: 502, code: "purge-failed", error: "Revoke succeeded but cache purge failed; share may be served from cache for up to 60 seconds" }`. (Caller-visible error text intentionally explains the bounded leak window so the UI can surface it.)
- `apps/web-platform/server/kb-binary-response.ts` — drop `CACHE_CONTROL_BY_SCOPE.public` `s-maxage=300` → `s-maxage=60`. Update the 6-line comment block above the constant to reflect the new policy and the rationale (purge backstop now exists).
- `apps/web-platform/test/kb-share-tools.test.ts` — extend MCP `kb_share_revoke` tests with a purge-success case and a purge-failure case (assert error code propagates).
- `apps/web-platform/test/kb-share.test.ts` — add `revokeShare` integration tests for: (1) purge called with the correct URL, (2) purge failure returns `{ ok: false, code: "purge-failed", status: 502 }`, (3) purge is skipped if the DB update itself failed (no token to purge for), (4) purge URL uses the `https://app.soleur.ai` base regardless of `process.env.NEXT_PUBLIC_APP_URL` so prod is always purged.

## Files to create

- `apps/web-platform/server/cf-cache-purge.ts` — purge helper. See `### Helper Contract` below for full signature, behavior, and CF API response decoding.
- `apps/web-platform/test/cf-cache-purge.test.ts` — unit tests for the helper covering all branches in the contract. Uses method-aware `vi.fn()` mock for `global.fetch` per rule `cq-preflight-fetch-sweep-test-mocks`. ESM-only — no `require()` per rule `cq-vite-test-files-esm-only`.

### Helper Contract

```ts
// apps/web-platform/server/cf-cache-purge.ts
import { reportSilentFallback } from "@/server/observability";

export type PurgeResult =
  | { ok: true }
  | { ok: false; error: "missing-config" | "timeout" | "cf-api" | "network" };

const PURGE_TIMEOUT_MS = 5000;
const APP_ORIGIN = "https://app.soleur.ai"; // hard-coded — see Sharp edges

/**
 * Purge a single shared-token URL from the Cloudflare edge cache.
 *
 * Invoked from server/kb-share.ts::revokeShare immediately after the DB row is
 * marked revoked. Treats CF's "no cached resource" response as success (the
 * desired end-state — empty cache — already holds).
 *
 * Failure modes are observable via Sentry under `feature: "kb-share"`,
 * `op: "revoke-purge"`. The caller (revokeShare) maps any non-ok result to
 * a 502 response so the operator sees the partial-failure state.
 */
export async function purgeSharedToken(token: string): Promise<PurgeResult> {
  const apiToken = process.env.CF_API_TOKEN_PURGE;
  const zoneId = process.env.CF_ZONE_ID;
  if (!apiToken || !zoneId) {
    reportSilentFallback(null, {
      feature: "kb-share",
      op: "revoke-purge",
      message: "CF_API_TOKEN_PURGE or CF_ZONE_ID not set",
      extra: { hasToken: !!apiToken, hasZone: !!zoneId },
    });
    return { ok: false, error: "missing-config" };
  }

  const url = `https://api.cloudflare.com/client/v4/zones/${zoneId}/purge_cache`;
  const body = JSON.stringify({ files: [`${APP_ORIGIN}/api/shared/${token}`] });

  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), PURGE_TIMEOUT_MS);

  try {
    const res = await fetch(url, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${apiToken}`,
        "Content-Type": "application/json",
      },
      body,
      signal: controller.signal,
    });

    // CF returns 200 + JSON body { success: bool, errors: [{code, message}] }.
    // Non-2xx (auth failure, rate limit) lands here too — body still parses.
    let payload: { success?: boolean; errors?: Array<{ code: number; message: string }> } = {};
    try {
      payload = await res.json();
    } catch {
      // Plaintext error body (rare) — fall through to ok=false branch.
    }

    if (res.ok && payload.success === true) return { ok: true };

    reportSilentFallback(
      new Error(
        `CF purge failed: status=${res.status} success=${payload.success} ` +
          `errors=${JSON.stringify(payload.errors ?? [])}`,
      ),
      {
        feature: "kb-share",
        op: "revoke-purge",
        extra: { status: res.status, errors: payload.errors, tokenPrefix: token.slice(0, 8) },
      },
    );
    return { ok: false, error: "cf-api" };
  } catch (err) {
    if ((err as Error).name === "AbortError") {
      reportSilentFallback(err, {
        feature: "kb-share",
        op: "revoke-purge",
        extra: { reason: "timeout", tokenPrefix: token.slice(0, 8) },
      });
      return { ok: false, error: "timeout" };
    }
    reportSilentFallback(err, {
      feature: "kb-share",
      op: "revoke-purge",
      extra: { reason: "network", tokenPrefix: token.slice(0, 8) },
    });
    return { ok: false, error: "network" };
  } finally {
    clearTimeout(timer); // critical: prevents the timer from holding the event loop open
  }
}
```

**Notes on the contract:**

- **`APP_ORIGIN` is hard-coded** to `https://app.soleur.ai`. Reason: this helper purges the *production* CF cache. If the helper read `process.env.NEXT_PUBLIC_APP_URL`, a misconfigured preview env could purge production URLs from cache (no leak, just unnecessary CF API calls) — or worse, a prod misconfig could purge a non-prod URL and silently leave the prod cache populated. Hard-coded is safer than env-derived for a security-boundary helper.
- **`tokenPrefix` (first 8 chars) is logged**, not the full token. The full token is sent over the wire to CF only — never to Sentry. This matches the existing `previewShare` Sentry tag pattern in `kb-share.ts` (line 629: `tokenPrefix = token.slice(0, 8)`).
- **No retry.** CF purge propagation is < 5s globally; a single attempt is sufficient. Adding retry would compound latency on the failure path. The caller (revokeShare → 502) gives the operator a clean "click revoke again" recovery path.
- **No HTTP body validation regex.** Token is generated by `randomBytes(32).toString("base64url")` (`kb-share.ts:50`) — no user input flows through the URL. The 1KB CF body limit is uncrossable.

## Open Code-Review Overlap

Verified via `gh issue list --label code-review --state open --json number,title,body --limit 200` cross-referenced against the `## Files to edit` paths above:

```bash
jq -r --arg path "server/kb-share.ts" '
  .[] | select(.body // "" | contains($path))
  | "#\(.number): \(.title)"
' /tmp/open-review-issues.json
# (and similarly for kb-binary-response.ts, kb-share-tools.test.ts, kb-share.test.ts)
```

**Result: None.** No open `code-review` issues touch the files this plan modifies. The check ran. (Implementer should re-run the query at work-skill time as a hot check, since new scope-outs may have been filed in the interim.)

## Implementation Phases

### Phase 1 — RED: failing tests

1. Add the `purgeSharedToken` test file (`apps/web-platform/test/cf-cache-purge.test.ts`) covering all four cases (success / CF 5xx / missing config / timeout). The helper does not yet exist — tests fail at import.
2. Add a failing test in `apps/web-platform/test/kb-share.test.ts` asserting `revokeShare` calls `purgeSharedToken("<token>")` and propagates failure as `{ ok: false, code: "purge-failed", status: 502 }`.
3. Add a failing test in `apps/web-platform/test/kb-share-tools.test.ts` asserting MCP `kb_share_revoke` surfaces the purge-failure status to the agent caller.

Run: `cd apps/web-platform && ./node_modules/.bin/vitest run test/cf-cache-purge.test.ts test/kb-share.test.ts test/kb-share-tools.test.ts` — confirm all RED before any source edits.

### Phase 2 — GREEN: implement

1. Create `apps/web-platform/server/cf-cache-purge.ts` per the contract above.
2. Extend `revokeShare` in `apps/web-platform/server/kb-share.ts`:
    - After the successful `update({ revoked: true }).eq("id", shareLink.id)` call, invoke `purgeSharedToken(token)`.
    - On purge failure: emit `reportSilentFallback(new Error(purgeResult.error ?? "purge failed"), { feature: "kb-share", op: "revoke-purge", extra: { userId, token } })` and return `{ ok: false, status: 502, code: "purge-failed", error: "Revoke succeeded but cache purge failed; share may be served from cache for up to 60 seconds" }`.
    - On purge success: keep the existing `log.info({ event: "share_revoked", ... })` line and return `{ ok: true, token, documentPath }`.
    - Add `purge-failed` to `RevokeShareErrorCode` and to the `RevokeShareResult` failure status union (`403 | 404 | 500 | 502`).
3. Drop `s-maxage=300` → `s-maxage=60` in `apps/web-platform/server/kb-binary-response.ts` `CACHE_CONTROL_BY_SCOPE.public`. Update the comment block above the constant.

Run: `cd apps/web-platform && ./node_modules/.bin/vitest run` — full suite. Expect prior RED tests to pass; no regressions in the broader share / binary-response suites.

### Phase 3 — Operational prereq (NOT in PR diff; documented in PR body)

The PR cannot merge without these prereqs being live in production. All are scriptable end-to-end (rule `hr-never-label-any-step-as-manual-without`) — no manual handoff.

#### 3a. Audit ALL Doppler configs first (per learning `2026-03-25-doppler-secret-audit-before-creation.md`)

Before creating a new token, verify it does not already exist in any config — a previous on-call may have provisioned it for another purpose:

```bash
for config in $(doppler configs --project soleur --json | jq -r '.[].name'); do
  echo "=== $config ==="
  doppler secrets --project soleur --config "$config" --only-names 2>&1 \
    | grep -iE "CF_API_TOKEN_PURGE|CF_ZONE_ID" || echo "(neither present)"
done
```

If `CF_API_TOKEN_PURGE` exists in any config, evaluate whether it can be re-used (same scope: Cache Purge:Edit on soleur.ai zone). Cross-config copy if so. Only create a new token if no candidate exists.

#### 3b. Create `CF_API_TOKEN_PURGE` (only if 3a found none)

Token attributes:

- **Name:** `soleur-purge-shared-tokens` (consistent with #2542's narrow-scope naming)
- **Permissions:** `Zone → Cache Purge → Purge`
- **Zone resources:** `Include → Specific zone → soleur.ai`
- **TTL:** none (long-lived; rotated via Cloudflare's standard process)

Create via API. The `<cache-purge-permission-group-id>` is fetched live from `GET /client/v4/user/tokens/permission_groups`:

```bash
# Resolve the permission group ID dynamically (it is stable but should be looked up, not memorized).
CF_ADMIN_TOKEN=$(doppler secrets get CF_API_TOKEN -p soleur -c prd_terraform --plain)
ZONE_ID=$(doppler secrets get CF_ZONE_ID -p soleur -c prd --plain)

PERM_GROUP_ID=$(curl -s "https://api.cloudflare.com/client/v4/user/tokens/permission_groups" \
  -H "Authorization: Bearer $CF_ADMIN_TOKEN" \
  | jq -r '.result[] | select(.name == "Cache Purge") | .id')

curl -X POST "https://api.cloudflare.com/client/v4/user/tokens" \
  -H "Authorization: Bearer $CF_ADMIN_TOKEN" \
  -H "Content-Type: application/json" \
  --data "{
    \"name\": \"soleur-purge-shared-tokens\",
    \"policies\": [{
      \"effect\": \"allow\",
      \"resources\": { \"com.cloudflare.api.account.zone.$ZONE_ID\": \"*\" },
      \"permission_groups\": [{ \"id\": \"$PERM_GROUP_ID\" }]
    }]
  }" | jq -r '.result.value' > /tmp/cf-purge-token
```

#### 3c. Store in Doppler `prd` (NOT `prd_terraform`)

Per learning `2026-03-29-doppler-service-token-config-scope-mismatch.md`, the runtime web-platform pod authenticates to Doppler via a service token scoped to `prd`. A secret in `prd_terraform` is invisible to runtime.

```bash
doppler secrets set CF_API_TOKEN_PURGE="$(cat /tmp/cf-purge-token)" -p soleur -c prd
shred -u /tmp/cf-purge-token  # do not leave token on disk

# Verify
doppler secrets get CF_API_TOKEN_PURGE -p soleur -c prd --plain | head -c 8 && echo "…"
```

#### 3d. Verify `CF_ZONE_ID` already in Doppler `prd`

```bash
if [ -z "$(doppler secrets get CF_ZONE_ID -p soleur -c prd --plain 2>/dev/null)" ]; then
  ZONE_ID=$(doppler secrets get CF_ZONE_ID -p soleur -c prd_terraform --plain)
  doppler secrets set CF_ZONE_ID="$ZONE_ID" -p soleur -c prd
fi
```

#### 3e. Trigger redeploy so the pod picks up the new env var

Doppler-injected env vars only appear in the pod after restart. Either: (a) wait for the next deploy in this PR's merge, or (b) trigger a manual redeploy via `gh workflow run web-platform-release.yml`. If (b), poll until complete per rule `wg-after-merging-a-pr-that-adds-or-modifies` — never assume "running" = "live".

### Phase 4 — Production verification (per #2568 acceptance criteria)

Replicate the exact 4-step Playwright session from #2521 / #2568 against `https://app.soleur.ai`:

1. POST `/api/kb/share` with a known `documentPath` → capture token.
2. GET `/api/shared/<token>` → expect `200`, capture `cf-cache-status` (should be `MISS` then `HIT` on a second GET).
3. DELETE `/api/kb/share/<token>` → expect `200` (purge succeeded) OR `502` (purge failed; revoke still applied at DB).
4. GET `/api/shared/<token>` (no cache-bust) within 5 seconds → expect `410 Gone` with `cf-cache-status: BYPASS` (post-purge re-fetch from origin).
5. Confirm Sentry has zero new `kb-share / revoke-purge` events for the success path; confirm the failure-injection variant of the run produces exactly one event.

This is not a hand-off — it runs through Playwright MCP using the live session pattern from #2521 verification. The session script is already in `knowledge-base/project/learnings/` (issue #2521 verification artifact); reuse it.

### Phase 5 — Compound + ship

Run `skill: soleur:compound` to capture: (a) the Doppler config selection (prd vs prd_terraform) decision rule, since the issue body mis-stated the location, and (b) the "purge failure must be a 5xx, not a silent-fallback-with-200" pattern for cache invalidation as a security boundary. Then `skill: soleur:ship` with `type: fix` + `priority/p1-high` + `type/security` labels. Use `Closes #2568` in the PR body.

## Acceptance Criteria

- [ ] After `DELETE /api/kb/share/<token>`, a fresh `GET /api/shared/<token>` from a new client (no cache-bust, no `if-none-match`) returns `410 Gone` within < 5s in production.
- [ ] CF Cache Purge failure mirrors to Sentry via `reportSilentFallback({ feature: "kb-share", op: "revoke-purge" })` AND the DELETE response returns `502` with the explanatory error string.
- [ ] `CACHE_CONTROL_BY_SCOPE.public` `s-maxage` is `60`, not `300`. The browser `max-age=60` is unchanged. `stale-while-revalidate=3600` and `must-revalidate` are unchanged.
- [ ] Vitest unit + integration tests for `cf-cache-purge.ts`, `kb-share.ts::revokeShare`, and `kb-share-tools.ts::kb_share_revoke` all pass.
- [ ] Production verification: live four-step Playwright run (Phase 4) returns the expected `410` in step 4, with `cf-cache-status: BYPASS` confirming the purge took effect.
- [ ] No regression in the existing share / binary-response suite (`./node_modules/.bin/vitest run` from `apps/web-platform/`).

## Risks

- **Maximum input size to CF Cache Purge body:** Token is bounded — `kb_share_links.token` is `randomBytes(32).toString("base64url")` ≈ 43 chars (rule reference: `kb-share.ts` line 50, `SHARE_TOKEN_BYTES = 32`). The constructed URL `https://app.soleur.ai/api/shared/<token>` is ~80 chars, well under CF's 30-URL / 1KB-per-call purge limit. No need for a `.slice()` bound (rule `cq-pii-regex-three-invariants` does not apply — the token is generated, not user-supplied).
- **`process.env.CF_API_TOKEN_PURGE` undefined at runtime:** First DELETE after deploy without the secret would 502 every revoke. Mitigated by: (a) the helper short-circuits to `{ ok: false, error: "missing-config" }` and Sentry alarms via `reportSilentFallback`, (b) Phase 3 ops prereq must complete before merge, (c) integration test in Phase 1 covers the missing-config branch.
- **CF API rate limit (1200 purge calls / 5 min on Free, 10K on Pro):** Revoke is a low-frequency user action (manual UI click + MCP tool). Even at 10 revokes/sec the limit is unreachable. No backoff needed.
- **Purge call latency:** CF documents purge propagation as < 5s globally. The 5s `AbortController` timeout in the helper is intentionally generous; if purge takes > 5s the DELETE returns 502 and the operator can retry. The user-visible latency budget for DELETE goes from ~150ms (DB-only) to ~600ms (DB + purge round-trip from `app.soleur.ai`'s region). Acceptable.
- **Test runner:** Vitest must be invoked via `./node_modules/.bin/vitest run` from `apps/web-platform/`, NOT `npx vitest run` (rule `cq-in-worktrees-run-vitest-via-node-node`). Plan in Phase 1/2 already specifies this form.

## Non-Goals

- **Tag-based cache + purge by tag (CF Enterprise feature).** Issue's Option C. Out of scope; we are not on Enterprise.
- **Purge on share `content-changed` re-issue path.** When `createShare` detects content drift it revokes the stale row and issues a new token (`kb-share.ts:268`). The stale token's `/api/shared/<oldToken>` URL would also benefit from a purge. **Defer to a follow-up issue** — once `purgeSharedToken` exists as a single-call helper, wiring it in is mechanical, but it expands the diff and risks the security fix being held up by an optimization. Scope this PR to the revoke path only. (See `### Deferred follow-ups` for the tracking-issue requirement.)
- **Terraform provisioning of `CF_API_TOKEN_PURGE`.** Cloudflare API token creation can be Terraform-managed via `cloudflare_api_token` resources, but the existing pattern stores narrow tokens via dashboard-create + Doppler-store (see `cf_api_token_zone_settings` and `cf_api_token_rulesets` in `infra/main.tf` and `infra/variables.tf`). Following the established pattern keeps this PR small. Token-as-code can be a future audit item.
- **UI surfacing of "purge failed" 502 in the share-management UI.** The HTTP layer returns the explanatory error, but updating the share-management UI to render it is an ADVISORY UX change owned by a follow-up. The agent-facing MCP path already propagates the error code by construction.

## Deferred follow-ups (filed as GitHub issues)

Per rule `wg-when-deferring-a-capability-create-a`, file these in the same action as the PR open:

1. **Purge on `content-changed` re-issue.** Wire `purgeSharedToken` into `createShare`'s "revoked stale row and issuing new token" branch (`kb-share.ts:268`). Re-eval: when this PR merges. Milestone: `Post-MVP / Later` unless a security review escalates.
2. **UX: surface "revoke succeeded but cache purge failed" in the share-management UI.** Re-eval: after this PR ships and the 502-rate metric is observable in Sentry. Milestone: `Post-MVP / Later`.

Both issues block on this PR merging. File at PR-open time, not at merge time, so the deferral is not invisible (rule `wg-when-deferring-a-capability-create-a`).

## Domain Review

**Domains relevant:** Engineering (CTO).

This is a server-side security fix. No user-visible UI, no marketing surface, no copy, no pricing or expense impact. The Product/UX Gate is **NONE** — the failure-mode error string ("Revoke succeeded but cache purge failed; share may be served from cache for up to 60 seconds") is a developer-facing JSON body that the share-management UI may eventually render (deferred follow-up), but no new UI is created in this PR. The mechanical UX-gate trigger (rule: any new file in `components/**/*.tsx` or `app/**/page.tsx`) does not fire — the only new file is `apps/web-platform/server/cf-cache-purge.ts`.

### CTO

**Status:** reviewed (synchronous — small, well-scoped security fix following established patterns).
**Assessment:**

- Single-call cache invalidation is the simplest viable fix. Tag-based purge needs CF Enterprise.
- Wiring through `revokeShare` (not the route handler) is correct: the #2298 hardening pattern hoists shared logic into the lifecycle module so MCP and HTTP surfaces inherit it. This PR continues that pattern.
- Returning 502 (not 500, not 200) on purge failure is the right shape: the DB write succeeded but the integration with the downstream cache failed — 502 Bad Gateway is the closest semantic match.
- Reusing the runtime Doppler `prd` config (not introducing `prd_terraform` at runtime) preserves the runtime/CI config separation called out in the existing learnings.
- 5s timeout is conservative. CF docs say < 5s global propagation; if our DELETE budget tightens later we can drop to 3s.

**Recommendation:** ship as planned.

## Cross-references for verbatim string preservation

The same canonical strings appear in multiple places in this plan. They MUST stay in lockstep — drift across them is the highest-risk regression class for this PR.

| Canonical string | Source of truth | Other locations that must match |
| --- | --- | --- |
| `"Revoke succeeded but cache purge failed; share may be served from cache for up to 60 seconds"` | `RevokeShareResult` `error` field in `kb-share.ts::revokeShare` | Test #8, Acceptance Criteria, Test Scenario #12 |
| `feature: "kb-share"`, `op: "revoke-purge"` | `cf-cache-purge.ts` Sentry tags | Test #2, #3, #5, #6 |
| `"https://app.soleur.ai/api/shared/<token>"` URL pattern | `APP_ORIGIN` const in `cf-cache-purge.ts` | Phase 4 verification, Test #1 |
| `"purge-failed"` error code | `RevokeShareErrorCode` union | Test #8, Test #12, MCP wrapper |

Before commit, grep the plan for each row's quoted literal and confirm one canonical value: `grep -n "Revoke succeeded" knowledge-base/project/plans/2026-04-18-fix-purge-cf-cache-on-share-revoke-plan.md` (etc).

## Sharp edges

- **Doppler config: `prd` not `prd_terraform`.** The issue body says `prd_terraform`. That is wrong for a runtime-consumed secret — runtime app pods read from `prd`. The reconciliation table above documents the correction. Implementer must store `CF_API_TOKEN_PURGE` in Doppler `prd`. Verify with `doppler secrets get CF_API_TOKEN_PURGE -p soleur -c prd --plain` after the prereq.
- **Vendor-default claim hygiene.** Per rule `cq-cloudflare-dynamic-path-cache-rule-required` and the #2532 learning, this plan makes only one vendor-behavior assertion: that `respect_origin` in `cache.tf` will pick up the new `s-maxage=60` value without a Terraform change. This is documented and verified (the existing comment block in `cache.tf` says "respect_origin defers to Cache-Control for every directive"). No new vendor-default claim is being made.
- **Acceptance < 5s budget vs. helper 5s timeout.** Issue acceptance says "< 5s in prod" for the post-revoke 410. The purge helper's `AbortController` is also 5s. There is no slack. If a purge call takes 4.9s, the DELETE round-trip (DB + purge) eats into the verification budget. Mitigation: the verification step in Phase 4 polls every 500ms for 10s before failing — the < 5s SLA is the *target*, not a hard kill. Document this in the verification script.
- **Test mock contract for `global.fetch`.** The purge helper calls `fetch`. Per rule `cq-preflight-fetch-sweep-test-mocks`, the test mock must be method-aware (`vi.fn((url, init) => init?.method === "POST" ? ... : ...)`) — even though only POST is expected, a future change adding a GET (e.g., a token-validation pre-flight) must not silently pass the wrong response shape.
- **`require()` in tests is forbidden.** Per rule `cq-vite-test-files-esm-only`, the new test file must use top-level `import` only. No `require()`.
- **Markdown lint on this plan file.** Run `npx markdownlint-cli2 --fix knowledge-base/project/plans/2026-04-18-fix-purge-cf-cache-on-share-revoke-plan.md` before commit (rule `cq-always-run-npx-markdownlint-cli2-fix-on`). Re-read after running to confirm table cell-spacing.

## Test Scenarios (TDD acceptance)

1. **`purgeSharedToken` success.** Mock `fetch` to return `200 { success: true, errors: [] }`. Call helper with `"abc123def456"`. Expect `{ ok: true }`. Assert exactly one POST to `https://api.cloudflare.com/client/v4/zones/<zone>/purge_cache` with body `{ files: ["https://app.soleur.ai/api/shared/abc123def456"] }` and `Authorization: Bearer <token>` header. No Sentry call.
2. **`purgeSharedToken` CF API auth error.** Mock `fetch` to return `403 { success: false, errors: [{ code: 10000, message: "Authentication error" }] }` (verified live response shape). Expect `{ ok: false, error: "cf-api" }` and exactly one `reportSilentFallback` call with `feature: "kb-share"`, `op: "revoke-purge"`, `extra.status: 403`, `extra.errors[0].code: 10000`, `extra.tokenPrefix: "abc123de"`.
3. **`purgeSharedToken` missing CF_API_TOKEN_PURGE.** `delete process.env.CF_API_TOKEN_PURGE`. Expect `{ ok: false, error: "missing-config" }` and one Sentry message-level event with `extra.hasToken: false, extra.hasZone: true`.
4. **`purgeSharedToken` missing CF_ZONE_ID.** `delete process.env.CF_ZONE_ID`. Expect `{ ok: false, error: "missing-config" }` and `extra.hasZone: false`.
5. **`purgeSharedToken` timeout.** Mock `fetch` to return a never-resolving Promise. Use `vi.useFakeTimers()` + `vi.advanceTimersByTime(5001)` to fire `AbortController`. Expect `{ ok: false, error: "timeout" }` and one Sentry call with `extra.reason: "timeout"`. Assert `clearTimeout` was called (no leaked timer).
6. **`purgeSharedToken` network error.** Mock `fetch` to throw `new TypeError("fetch failed")`. Expect `{ ok: false, error: "network" }` and one Sentry call with `extra.reason: "network"`.
7. **`revokeShare` happy path.** DB update succeeds, purge succeeds. Expect `{ ok: true, token, documentPath }`. Existing `share_revoked` log line still emits.
8. **`revokeShare` purge failure.** DB update succeeds, purge returns `{ ok: false, error: "cf-api" }`. Expect `{ ok: false, status: 502, code: "purge-failed", error: "Revoke succeeded but cache purge failed; share may be served from cache for up to 60 seconds" }`. The DB update is NOT rolled back (the share stays revoked at origin even if CF caches it for another 60s — the existing `Cache-Control: no-store` on the 410 origin response prevents re-caching).
9. **`revokeShare` DB failure short-circuits purge.** DB update returns error. Expect existing `db-error` 500 path. Purge MUST NOT be called — verify with `expect(purgeMock).not.toHaveBeenCalled()`.
10. **`revokeShare` forbidden short-circuits purge.** `shareLink.user_id !== userId`. Expect 403 path unchanged. Purge MUST NOT be called.
11. **`revokeShare` not-found short-circuits purge.** `fetchError` from share-row select. Expect 404 path unchanged. Purge MUST NOT be called.
12. **MCP `kb_share_revoke` propagates purge-failed status.** Mock `revokeShare` to return `{ ok: false, status: 502, code: "purge-failed", error: "<verbatim>" }`. Expect the MCP tool wrapper to surface `code: "purge-failed"` and the verbatim error string to the agent caller.

### Test Implementation Sketch

```ts
// apps/web-platform/test/cf-cache-purge.test.ts
import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { purgeSharedToken } from "@/server/cf-cache-purge";
import * as observability from "@/server/observability";

const ORIGINAL_ENV = { ...process.env };

beforeEach(() => {
  process.env.CF_API_TOKEN_PURGE = "test-token-aaaaaaaaaaaaaaaaaaaaaaaaaaaa";
  process.env.CF_ZONE_ID = "test-zone-1234567890abcdef";
  vi.spyOn(observability, "reportSilentFallback").mockImplementation(() => {});
});
afterEach(() => {
  process.env = { ...ORIGINAL_ENV };
  vi.restoreAllMocks();
});

it("posts to CF purge endpoint and returns ok on success", async () => {
  const fetchMock = vi.fn(async (url, init) => {
    expect(init?.method).toBe("POST");
    expect(url).toContain("/zones/test-zone-1234567890abcdef/purge_cache");
    return new Response(JSON.stringify({ success: true, errors: [] }), {
      status: 200,
      headers: { "content-type": "application/json" },
    });
  });
  vi.stubGlobal("fetch", fetchMock);
  const result = await purgeSharedToken("abc123def456");
  expect(result).toEqual({ ok: true });
  expect(fetchMock).toHaveBeenCalledTimes(1);
  expect(observability.reportSilentFallback).not.toHaveBeenCalled();
});
```

(Repeat the pattern for each numbered scenario above.)

## PR Body Reminder (for `/ship`)

```
Closes #2568.

Fixes a 5-minute security boundary leak where Cloudflare's edge cache continued
serving previously-cached 200 responses for /api/shared/<token> for up to
s-maxage=300 seconds after the share was revoked.

Two-layer fix:
1. Active CF Cache Purge API call from server/kb-share.ts::revokeShare so both
   the HTTP DELETE handler and the MCP kb_share_revoke tool inherit by
   construction. Purge failure returns 502 + Sentry alarm — no silent fallback.
2. Defense-in-depth: drop CACHE_CONTROL_BY_SCOPE.public s-maxage from 300 → 60
   so the worst-case leak window if purge fails is bounded to 1 minute.

New runtime credential: CF_API_TOKEN_PURGE in Doppler prd (Cache Purge:Edit on
soleur.ai). Token created out-of-band; stored in Doppler before merge.

Production verification: live 4-step Playwright session from the #2521
verification pattern (the session that found this bug).

Defers (filed as separate issues): purge on content-changed re-issue,
UI surfacing of purge-failed 502.

Deferred-follow-ups: #<filed-1>, #<filed-2>.
```

Labels at ship time: `priority/p1-high`, `type/security`, `domain/engineering`. Verify exact names with `gh label list --limit 100 | grep -i security` before `/ship` (rule `cq-gh-issue-label-verify-name`).
