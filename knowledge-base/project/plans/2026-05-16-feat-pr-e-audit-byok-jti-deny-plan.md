---
title: PR-E — audit_byok_use writer sweep + is_jti_denied consumer (#3887)
date: 2026-05-16
status: ready-for-work
issue: 3887
umbrella_issue: 3244
predecessor_prs: [3395, 3854, 3883]
branch: feat-pr-e-audit-byok-jti-deny
worktree: .worktrees/feat-pr-e-audit-byok-jti-deny/
pr: TBD
brainstorm: knowledge-base/project/brainstorms/2026-05-16-pr-e-audit-byok-jti-deny-brainstorm.md
spec: knowledge-base/project/specs/feat-pr-e-audit-byok-jti-deny/spec.md
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
lane: cross-domain
---

# PR-E — audit_byok_use writer sweep + is_jti_denied consumer

## Overview

Close the load-bearing Art. 5(2) accountability + Art. 32 confidentiality
gap left open by PR-B (#3395) and unaddressed by PR-C (#3854) / PR-D
(#3883). Migration `037_audit_byok_use.sql` shipped three DB-resident
primitives; PR-B wired the writer + rate-limit; PR-E wires the deny-list
**reader** as a JWT-mint-path consumer AND adds a CI-enforced
writer-sweep over every BYOK SDK call path so future regressions
cannot land silently.

No new migration. No new SECURITY DEFINER functions. No new sub-
processors. No new personal-data surface. Same review surface as PR-C
+ PR-D for the audit-writer expectation, narrower than PR-B for the
auth-domain change (single-file `tenant.ts` edit).

Closes: `Closes #3887` (in PR body per `wg-use-closes-n-in-pr-body-not-title-to`).
Umbrella: `Ref #3244`.

## Research Reconciliation — Spec vs. Codebase

| Spec / brainstorm claim | Codebase reality (re-grep 2026-05-16 at branch HEAD) | Plan response |
|--|--|--|
| `is_jti_denied` has ZERO consumer call sites in `apps/` | Verified — `grep -rn "is_jti_denied" apps/` returns only `test/supabase-migrations/037-audit-byok-use.test.ts` (5 hits, all schema-shape assertions) and migration 037 comments. No production consumer. | Plan operates on confirmed gap. PR-E adds the first consumer. |
| `RuntimeAuthError.cause = "denied_jti"` declared, no raiser | `lib/supabase/tenant.ts:65` declares the variant; no `throw new RuntimeAuthError("denied_jti", ...)` anywhere in `apps/`. | Plan's Phase 2 raises the variant from the deny-check call sites. |
| `denied_jti` table writer = service-role-only, no RPC | Migration 037 lines 122-148: zero CREATE POLICY, zero writer function. Confirmed. | Plan picks brainstorm decision (C): read-only consumer + manual SQL operator surface as documented kill-switch. No writer RPC in PR-E. |
| `write_byok_audit` call sites = single (`cost-writer.ts:115`) | Verified — `grep -rn "write_byok_audit" apps/` returns only `cost-writer.ts:116` (production) + `agent-runner.tenant-isolation.test.ts:308` (denial test) + agent-runner.ts comment + migration. | Plan's sweep CI lint targets `persistTurnCost` (the wrapper) since `cost-writer.ts` centralizes the call. |
| `persistTurnCost` callers | `agent-runner.ts:1876`, `cc-dispatcher.ts:1705` — 2 callers. | Plan's writer-sweep enumerates 5 BYOK SDK call paths; 4 are covered (parent-call rollup), 1 (pdf-chapter-router rollup) is documented out-of-scope. |
| BYOK SDK call paths | `agent-runner.ts:863, 2363` (`runWithByokLease` openings); `cc-dispatcher.ts:883` (`runWithByokLease`); `pdf-chapter-router.ts:148` (`query()` inside parent lease via ALS — verified via `import { runWithByokLease } from "./byok-lease"` chain). `agent-runner.ts:1607` is a `query()` inside the lease at `:863`. | Plan freezes the 9-row enumeration from the brainstorm. Issue body's list (cc-dispatcher, agent-runner, pdf-chapter-router, byok-lease, safe-bash, bash-sandbox, ws-handler, soleur-go-runner) is wider than the BYOK-actual set; `safe-bash`/`bash-sandbox`/`ws-handler`/`soleur-go-runner` are NOT BYOK paths (no Anthropic SDK invocation in scope) — documented in sweep table dispositions 6-9. |
| `precheck_jwt_mint` consumer | `lib/supabase/tenant.ts:131` only — via `mintFounderJwt`. Issue body's claim of "wired in lib/supabase/tenant.ts + server/ws-handler.ts + server/session-sync.ts + server/conversation-writer.ts" is misleading: those 3 server files use `getFreshTenantClient(userId)` which chains down to `mintFounderJwt`; they do NOT call `precheck_jwt_mint` directly. | No code change needed for the rate-limit path. The deny-check sits at the same boundary as the existing rate-limit invocation (`mintFounderJwt`). |
| Existing tenant-isolation suites count | 13 files at `apps/web-platform/test/server/*.tenant-isolation.test.ts`. | Plan's AC11 tally: 13 existing + 3 new (2 tenant-isolation + 1 sweep-lint, where the sweep-lint runs under standard webplat not the tenant-isolation gate) = 16 suites. |
| Migration 037 shape at HEAD | Read in full (233 lines). Matches PR-B plan §1.4 — `audit_byok_use` WORM + `write_byok_audit` SECURITY DEFINER, `denied_jti` zero-policy + `is_jti_denied` SECURITY DEFINER reader, `mint_rate_window` + `precheck_jwt_mint`. No drift. | Per `2026-05-10-handshake-schema-drift-and-stale-precondition-budgets.md`, this reconciliation step satisfies the "re-verify migration 037's current shape against any drift" precondition from #3887. |

## User-Brand Impact

**If this lands broken, the user experiences:** a closed-preview founder
sees `RuntimeAuthError(denied_jti)` falsely on a fresh JWT (false-
positive on the deny-list check) and loses access to the runtime
mid-session, OR a BYOK audit row is silently dropped on a path the
writer sweep missed and the founder's billing dashboard under-reports
a turn that actually spent against their key.

**If this leaks, the user's data / money is exposed via:** a stolen
runtime JWT remains valid for its full 10-min TTL (no in-band
kill-switch even after revocation intent is recorded), OR a BYOK
SDK call path that bypasses `persistTurnCost` charges the founder's
Anthropic key without leaving a row in the WORM ledger — Art. 5(2)
"ability to demonstrate" fails on a DSAR or audit request.

**Brand-survival threshold:** `single-user incident`. Carry-forward
from PR-B + PR-C + PR-D. `requires_cpo_signoff: true`. CPO sign-off
gathered at brainstorm (this file's CTO+CLO+CPO domain-assessment
block). `user-impact-reviewer` MUST run at review time per
`plugins/soleur/skills/review/SKILL.md` conditional-agent block #15.

| Artifact | Vector | Mitigation in PR-E |
|----------|--------|---------------------|
| Runtime JWT (jti claim) | Stolen / leaked / replayed bearer token usable for full TTL with no in-band kill-switch | `is_jti_denied(jti)` check on cache-hit + cache-miss paths inside `getFreshTenantClient` / post-mint. Operator inserts `(jti, founder_id, now(), reason)` directly into `denied_jti` to revoke. Sentry mirror on deny event. |
| BYOK SDK call path | Founder's Anthropic key spent without an `audit_byok_use` row | Writer-sweep CI lint over every `runWithByokLease(` call site — fails CI if a new BYOK path lands without `persistTurnCost` (or explicit out-of-scope comment). |
| `audit_byok_use` WORM rows | Service-role accidentally UPDATEs/DELETEs an audit row | Migration 037's `audit_byok_use_no_mutate` trigger raises P0001 — covered in PR-E by new integration test that asserts the trigger fires. |

## Domain Review

**Domains relevant:** Legal/Compliance, Engineering (CTO), Product (CPO)

### Legal/Compliance (CLO)

**Status:** reviewed (brainstorm carry-forward)
**Assessment:** Art. 5(2) accountability gap is the load-bearing legal
driver. No Article 30 register amendment expected (deny-list table
already in PA1 via "authentication" processing activity from PR-B;
`jti` is random UUID not personal data; Sentry mirror covered by PA2
from PR-D). Post-merge: close the `Art. 5(2) audit-writer gap` row
in `knowledge-base/legal/compliance-posture.md` Active Items.

### Engineering (CTO)

**Status:** reviewed (brainstorm carry-forward)
**Assessment:** Two invariants enumerated; CI lint prescribed.
`cq-pg-security-definer-search-path-pin-pg-temp` not triggered (no
new SQL). `hr-write-boundary-sentinel-sweep-all-write-sites` triggers
and is satisfied by the sweep-lint test. `hr-type-widening-cross-consumer-grep`
not triggered (no union widening). `cq-silent-fallback-must-mirror-to-sentry`
covered by AC4.

### Product/UX Gate

**Tier:** none (no new user-facing surface)
**Decision:** N/A
**Agents invoked:** none
**Skipped specialists:** none
**Pencil available:** N/A

No new UI. The deny-event presents to the founder as the existing
`RuntimeAuthError` toast ("Authentication unavailable; retry shortly")
— same UI as `jwt_mint` and `rotation` causes. No copy change, no
modal.

## Files to Edit

| Path | Change |
|------|--------|
| `apps/web-platform/lib/supabase/tenant.ts` | (a) Extend `CacheEntry` interface (line 202) with `jti: string`. (b) Inside `mintFounderJwt` (line 124), after the existing `precheck_jwt_mint` + sign block, expose `row.jti` to the returned `MintedJwt` (new field). (c) Inside `getFreshTenantClient` (line 236): cache-hit branch — after `await inflight`, call `await service.rpc("is_jti_denied", { p_jti: entry.jti })`. On `true`: evict from `cache`, call `reportSilentFallback(null, { feature: "tenant-jwt", op: "is_jti_denied.deny", extra: { userId, jti: entry.jti } })`, fall through to remint. (d) Cache-miss branch — after `minting` resolves, before returning `entry.client`, call the same deny check; on `true` throw `new RuntimeAuthError("denied_jti", "Authentication unavailable; retry shortly")` and emit the same Sentry mirror. (e) `MintedJwt` interface (line 44) gains `jti: string`. |
| `apps/web-platform/lib/supabase/service.ts` (verify, no edit expected) | `getServiceClient()` already in scope; deny-check uses the same client. |
| `apps/web-platform/test/server/tenant-jwt-deny.tenant-isolation.test.ts` | **NEW.** 4 tests covering AC1-AC5 + AC10. See §Test Detail below. |
| `apps/web-platform/test/server/audit-byok-use.tenant-isolation.test.ts` | **NEW.** 3 tests covering AC7. See §Test Detail below. |
| `apps/web-platform/test/server/byok-audit-writer-sweep.test.ts` | **NEW.** Source-grep sweep over `apps/web-platform/server/**` for `runWithByokLease(` call sites. Asserts paired `persistTurnCost(` or out-of-scope comment. Runs under standard webplat vitest, NOT the tenant-isolation gate (deterministic — no DB required). See §Test Detail. |
| `apps/web-platform/server/pdf-chapter-router.ts` | Add a single line `// byok-audit-writer-sweep: out-of-scope — cost rolls up via routingCostUsd into parent persistTurnCost (see brainstorm row 5a)` above the `query({...})` call at line 148. No behavior change. |
| `apps/web-platform/test/server/tenant-jwt-refresh.test.ts` | If existing test mocks `precheck_jwt_mint` and stubs `MintedJwt`, widen the stub to include `jti: "<uuid>"` (per AC6 widening). Read-only check at plan time; if no widening needed, no edit. |
| `knowledge-base/legal/compliance-posture.md` | Post-merge operator step: close the `Art. 5(2) audit-writer gap` Active Items row. Not in PR diff — operator runbook step AC18. |

## Files to Create

| Path | Purpose |
|------|---------|
| `apps/web-platform/test/server/tenant-jwt-deny.tenant-isolation.test.ts` | Deny-list consumer integration tests (Tests A-D). |
| `apps/web-platform/test/server/audit-byok-use.tenant-isolation.test.ts` | WORM enforcement + RLS shape tests. |
| `apps/web-platform/test/server/byok-audit-writer-sweep.test.ts` | Source-grep CI lint enforcing audit-row coverage on BYOK SDK call paths. |

## Open Code-Review Overlap

Ran the two-stage `gh issue list --label code-review --state open --json` →
`jq --arg path` sweep over each `Files to Edit` path. **None of the
edited files appear in any open code-review issue body.** No overlap;
record `None` for the gate.

## Implementation Phases

### Phase 0 — Preconditions (verified at plan-write time)

- [x] `pwd` = `/home/jean/git-repositories/jikig-ai/soleur/.worktrees/feat-pr-e-audit-byok-jti-deny`
- [x] `git branch --show-current` = `feat-pr-e-audit-byok-jti-deny`
- [x] Migration 037 read in full (233 lines); shape matches PR-B plan §1.4.
- [x] `grep -rn "is_jti_denied" apps/` confirmed zero production consumers.
- [x] `grep -rn "persistTurnCost" apps/` confirmed 2 callers (agent-runner.ts, cc-dispatcher.ts).
- [x] 13 existing `*.tenant-isolation.test.ts` files inventoried.
- [x] No new migration required — DB primitives already live from PR-B.
- [x] `gdpr-gate` advisory: brand-survival threshold `single-user incident` triggers Phase 2.7 gate; expected findings folded into AC15.

### Phase 1 — Plan Phase 1.5 (community discovery) + 1.6 (research decision)

Stack detection: TypeScript / Next.js / Supabase / pino / Sentry — all
covered by existing repo conventions. External research **skipped**:
local context is strong (PR-B plan §1.4 fully specifies the JWT path;
migration 037 in scope; `cost-writer.ts` is the existing precedent for
the audit writer). High-risk topic (auth + audit) is mitigated by the
brand-survival framing + mandatory user-impact-reviewer at review
time, not by external research.

### Phase 2 — Consumer wiring (`lib/supabase/tenant.ts`)

RED-first: write `tenant-jwt-deny.tenant-isolation.test.ts` Tests A-D
against current code (will fail Tests B + C). Land the test file
first commit.

GREEN: edit `tenant.ts` per `Files to Edit` row 1:
1. Widen `MintedJwt` (line 44) with `jti: string`. Audit consumers
   (none today — `mintFounderJwt` is exported but only called from
   `getFreshTenantClient` in the same module per `grep -rn "mintFounderJwt" apps/`).
2. Widen `CacheEntry` (line 202) with `jti: string`. Audit consumers
   (none — `CacheEntry` is module-local).
3. Extend `mintFounderJwt` to surface `row.jti` in the returned
   `MintedJwt`.
4. In the `getFreshTenantClient` cache-hit branch (line 248-252),
   between `await inflight` and the freshness check, add the deny
   probe. Place AFTER the freshness check so a stale entry remints
   rather than running an unnecessary deny RPC on a remint anyway.
   Actually — place BEFORE the freshness check: a fresh-but-denied
   entry must NOT be returned. Final order: (a) await inflight → entry,
   (b) deny-probe entry.jti, (c) on true: evict + Sentry + fall through
   to remint, (d) on false: freshness check → return cached or remint.
5. In the cache-miss installation path (line 263-267), between the
   `await minting` and `return entry.client`, add the post-mint deny
   probe. On true: throw `RuntimeAuthError("denied_jti", ...)` AFTER
   evicting from cache (the rejected Promise will be cleaned up by
   the existing catch at line 272, but the cache must be cleaned
   first to avoid the rejected-Promise-stays-in-cache race).
6. REFACTOR: extract the deny-probe into a private
   `async function denyProbe(jti: string, userId: UserId): Promise<boolean>`
   that calls the RPC and emits the Sentry mirror on `true`. Both
   call sites use it. Keep the throw at the call site (cache-miss),
   not inside the helper — the cache-hit path falls through to
   remint instead of throwing.

Asserts in tests: Tests B + C pass; Tests A + D stay green.

### Phase 3 — Audit writer sweep CI lint (`byok-audit-writer-sweep.test.ts`)

Standalone vitest in standard webplat suite (no DB). Source-grep:

```ts
import fs from "node:fs";
import { sync as globSync } from "fast-glob";
import { describe, expect, it } from "vitest";

const SERVER_DIR = "apps/web-platform/server";
const OUT_OF_SCOPE_MARKER = "byok-audit-writer-sweep: out-of-scope";

describe("BYOK audit writer sweep", () => {
  const files = globSync(`${SERVER_DIR}/**/*.ts`, { ignore: ["**/*.test.ts"] });
  for (const f of files) {
    const src = fs.readFileSync(f, "utf8");
    if (!/runWithByokLease\s*\(/.test(src)) continue;
    // byok-lease.ts itself defines runWithByokLease; not a call site.
    if (f.endsWith("byok-lease.ts")) continue;
    it(`${f}: emits persistTurnCost or carries out-of-scope marker`, () => {
      const hasWriter = /persistTurnCost\s*\(/.test(src);
      const hasMarker = src.includes(OUT_OF_SCOPE_MARKER);
      expect(hasWriter || hasMarker).toBe(true);
    });
  }
});
```

Edge cases:
- `pdf-chapter-router.ts` does NOT use `runWithByokLease` directly (it's
  inside the parent lease via ALS) but DOES call `query(...)`. The
  sweep above filters on `runWithByokLease(` so pdf-chapter-router is
  not asserted — its rollup posture is documented in the brainstorm
  table only.
- Decision: extend the sweep to ALSO grep for `query({` / `sdkQuery({`
  / `import { query } from "@anthropic-ai/claude-agent-sdk"` and
  require the same coverage. This catches the pdf-chapter-router case
  AND any future SDK-query site that lands without a `runWithByokLease`
  parent. The out-of-scope marker becomes the load-bearing exception
  for the rollup case. Final sweep grep matrix:
  - Find every `.ts` file under `server/**` that imports `query` or
    `sdkQuery` from `@anthropic-ai/claude-agent-sdk` OR contains
    `runWithByokLease(`.
  - For each: assert `persistTurnCost(` OR `OUT_OF_SCOPE_MARKER`.
- Allowlist guard: count `OUT_OF_SCOPE_MARKER` occurrences across the
  swept files; assert ≤ 2 (pdf-chapter-router + one slack reserve)
  so adding a new out-of-scope marker requires explicit allowlist
  bump.

### Phase 4 — Audit-byok-use WORM tests (`audit-byok-use.tenant-isolation.test.ts`)

Three tests under `TENANT_INTEGRATION_TEST=1`:
- A: `service.from("audit_byok_use").update({ token_count: 999 }).eq("id", existingId)` → expect P0001 from PostgREST error body.
- A': `.delete().eq("id", existingId)` → expect P0001.
- B: insert a row via `service.rpc("write_byok_audit", {...})`; founder's tenant client `.from("audit_byok_use").select()` returns the row; cross-tenant founder gets zero rows. (Already partially covered by `agent-runner.tenant-isolation.test.ts:305`; this file re-asserts at the writer boundary.)

### Phase 5 — pdf-chapter-router marker (single-line comment)

Edit row 6. No behavior change; sweep test happy.

### Phase 6 — Verification

```bash
cd apps/web-platform && \
  doppler run -p soleur -c dev -- env TENANT_INTEGRATION_TEST=1 \
    ./node_modules/.bin/vitest run test/server/*.tenant-isolation.test.ts --reporter=verbose
```

Expected: 13 existing suites + 2 new tenant-isolation suites = 15 green.

```bash
cd apps/web-platform && \
  doppler run -p soleur -c dev -- ./node_modules/.bin/vitest run test/server/byok-audit-writer-sweep.test.ts --reporter=verbose
```

Expected: 1 suite (1 sweep test) green.

```bash
bash scripts/test-all.sh
```

Expected: TEST_GROUP=webplat green (no pre-existing regression).

```bash
.github/scripts/service-role-allowlist-gate.sh   # or whatever the gate command is
```

Expected: gate passes — no new service-role imports in PR-E.

### Phase 7 — Plan-review (mandatory)

After landing the plan + tasks.md, invoke `/plan-review` for DHH +
Kieran + code-simplicity panel. Apply or document responses per the
plan review section of soleur:plan.

### Phase 8 — PR open + reviewer pipeline

Per the spec AC + Soleur conventions:
- PR title: `feat(runtime): PR-E audit_byok_use writer sweep + is_jti_denied consumer (#3887)`
- PR body must include:
  - `Closes #3887`
  - Brand-survival vector context (closes Art. 5(2) accountability gap before 2nd hosted founder or GA exposure)
  - Per-suite re-run tally (≥13 suites + PR-E suites, all green)
  - "No PA1/PA2 surface change" note
  - Writer-sweep enumeration: the 9-row table from the brainstorm verbatim
  - Operator post-merge instruction: NONE (no migration; `gh issue close 3887` + compliance-posture.md Active Items update)

Reviewer pipeline at `/soleur:review` time MUST include:
- `user-impact-reviewer` (mandatory at `single-user incident` threshold)
- `data-integrity-guardian` (audit-writer + WORM trigger surface)
- `security-sentinel` (JWT mint path change)
- `semgrep-sast` (source file changes)
- `gdpr-gate` (auth-domain code change + brand-survival = single-user-incident BOTH fire)

## Risks

- **R1 — Cache-hit deny probe adds RPC latency on every cache-hit
  fetch.** `getFreshTenantClient` is called on every tenant-data
  operation (~10× per turn). Adding one RPC per call multiplies DB
  load. **Mitigation:** the deny RPC is SECURITY DEFINER reading a
  single-row PK index — sub-millisecond. Acceptable for the closed-
  preview alpha. If beta scale shows hot-path latency: cache the deny
  result with the same TTL as the JWT (deny RPC fires once per JWT
  lifetime; refreshed on remint). Track as scope-out at deepen-plan.

- **R2 — Cache-miss deny probe race with TOCTOU.** Operator could
  insert a deny-list row between the post-mint check and the next
  user request. **Mitigation:** the next request re-enters
  `getFreshTenantClient`, finds the (just-installed) cache entry,
  runs the cache-hit deny probe, sees the deny row, evicts. The
  TOCTOU window is bounded by the deny-list insert latency, not
  unbounded. Acceptable.

- **R3 — Writer-sweep test brittleness against legitimate new
  SDK-query patterns.** A future file that imports `query` only for
  TYPE purposes (`import type { Query } from ...`) would false-
  positive. **Mitigation:** sweep grep filters
  `import\s+type\s+\{[^}]*\}\s+from\s+"@anthropic-ai/claude-agent-sdk"`
  out of the importer set. Verify against `soleur-go-runner.ts`
  which uses `type MessageParam` import — must NOT trip the sweep.

- **R4 — `MintedJwt` widening with `jti: string` breaks downstream
  consumers.** Audit at plan time: `grep -rn "MintedJwt" apps/` —
  only used inside `tenant.ts` (return type of `mintFounderJwt`).
  No external consumer. Safe.

- **R5 — `denied_jti` RLS shape.** The table has RLS-on with ZERO
  policies (migration 037:129). Tenant-client `.from("denied_jti").select()`
  would return zero rows regardless. The deny probe uses
  `getServiceClient().rpc("is_jti_denied", {...})` — service-role
  SECURITY DEFINER, bypasses RLS by design. `.service-role-allowlist`
  already covers `lib/supabase/tenant.ts`. No allowlist change.

- **R6 — Cost-writer is fire-and-forget.** `persistTurnCost` returns
  void and chains `.then()` for the audit write (`cost-writer.ts:123`).
  If the audit write fails, the user-facing turn completes successfully
  but no audit row lands. The existing code already mirrors to Sentry
  on the failure branch (`cost-writer.ts:129`). PR-E does NOT change
  this semantic — the writer-sweep CI lint enforces COVERAGE, not
  delivery. Operational reliability of the writer is out of scope
  (separate issue if needed).

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only
  `TBD`/`TODO`/placeholder text, or omits the threshold will fail
  `deepen-plan` Phase 4.6. This plan's section is filled with the
  brainstorm carry-forward + threshold `single-user incident`.

- Re-verify the migration 037 shape at plan-write time per
  `2026-05-10-handshake-schema-drift-and-stale-precondition-budgets.md`.
  Done — Phase 0 preconditions confirm no drift.

- The CI sweep test runs in the standard webplat group (no DB) — do
  NOT add it to `*.tenant-isolation.test.ts` suffix, the
  `tenant-integration.yml` workflow's path filter (line 36) would
  re-run it under the tenant-integration job needlessly.

- `is_jti_denied(p_jti uuid)` is STABLE not VOLATILE (migration 037:138).
  Postgres may cache results within a single statement — but the deny
  probe is its own statement at each call site. No staleness risk.

- Operator workflow note for revocation today (until follow-up admin
  RPC ships): direct SQL via supabase-mcp or SQL Editor:
  `INSERT INTO denied_jti (jti, founder_id, denied_at, reason) VALUES ('<uuid>', '<founder_uuid>', now(), '<reason>');`. Operator obtains
  the jti from the cached JWT (decode header.payload.signature
  base64url) or from the most-recent `audit_byok_use` row via the
  `invocation_id` ↔ session correlation in pino logs. Document this
  in the post-merge runbook.

## Tracked Deferrals (file at deepen-plan time)

1. **Deny-list TTL sweep / logout-driven revocation.** Brainstorm option
   (B). Re-evaluation trigger: deny-list table size > 1000 rows OR
   logout flow ships. File at deepen-plan with labels
   `deferred-scope-out`, `domain/engineering`, `priority/p3-low`.

2. **Per-pdf-chapter-router-turn audit row.** Brainstorm option (5b).
   Re-evaluation trigger: per-sub-call dashboard built OR Art. 5(2)
   audit requires sub-call granularity. Same labels as above.

3. **Admin `revoke_jti(...)` RPC + admin-call site.** Per #3887 OOS
   note; promote when 2nd hosted founder onboards OR a real
   compromise drill occurs. Same labels.

4. **Cache the deny RPC result with the JWT TTL (R1).** Promote at
   beta scale if Sentry shows hot-path latency.

## Verification (must run before opening PR — non-draft)

```bash
cd apps/web-platform && \
  doppler run -p soleur -c dev -- env TENANT_INTEGRATION_TEST=1 \
    ./node_modules/.bin/vitest run test/server/*.tenant-isolation.test.ts --reporter=verbose
```

Expected: 13 existing suites still pass + 2 new PR-E tenant-isolation
suites pass. Tally green: 15.

```bash
cd apps/web-platform && \
  ./node_modules/.bin/vitest run test/server/byok-audit-writer-sweep.test.ts --reporter=verbose
```

Expected: 1 suite (1 sweep test) green.

```bash
bash scripts/test-all.sh   # TEST_GROUP=webplat
```

Expected: full webplat suite green; no regressions.

`.service-role-allowlist` enforcement: must pass (no new imports).

## Test Detail

### `tenant-jwt-deny.tenant-isolation.test.ts`

```ts
// Strict outline (not literal — tasks.md will expand)
describe("tenant JWT deny-list consumer", () => {
  beforeEach(async () => {
    _resetTenantCache();
    _resetSentryEvents?.();
    await service.from("denied_jti").delete().neq("jti", "00000000-0000-0000-0000-000000000000");
  });

  it("Test A: fresh mint with empty deny-list returns a usable client", async () => {
    const client = await getFreshTenantClient(TEST_FOUNDER_ID);
    expect(client).toBeDefined();
  });

  it("Test B: cache-hit path with revoked jti throws and emits Sentry", async () => {
    const client = await getFreshTenantClient(TEST_FOUNDER_ID);
    // Extract jti from the cached MintedJwt (peek via test-only export OR
    // decode the JWT header.payload from a captured Authorization header).
    const jti = await peekCachedJti(TEST_FOUNDER_ID);
    await service.from("denied_jti").insert({ jti, founder_id: TEST_FOUNDER_ID, reason: "test" });
    await expect(getFreshTenantClient(TEST_FOUNDER_ID)).resolves.toBeDefined(); // remint
    // The denied jti's cache entry was evicted; remint produced a fresh jti.
    const sentry = _capturedSentryEvents();
    expect(sentry.some(e => e.op === "is_jti_denied.deny")).toBe(true);
  });

  it("Test C: cache-miss post-install deny check throws RuntimeAuthError", async () => {
    // Race shape: pre-insert a soon-to-be-minted jti is structurally
    // impossible (jti is gen_random_uuid()). Instead, simulate by stubbing
    // mintFounderJwt to return a known jti and pre-inserting it.
    // (Test detail expanded in tasks.md.)
  });

  it("Test D: unrelated jti insert does not affect founder's session", async () => {
    const client = await getFreshTenantClient(TEST_FOUNDER_ID);
    await service.from("denied_jti").insert({ jti: randomUUID(), founder_id: TEST_FOUNDER_ID, reason: "noise" });
    const sameClient = await getFreshTenantClient(TEST_FOUNDER_ID);
    expect(sameClient).toBe(client); // cache-hit returned same client
  });
});
```

### `audit-byok-use.tenant-isolation.test.ts`

```ts
describe("audit_byok_use WORM enforcement", () => {
  it("UPDATE raises P0001", async () => {
    const { data: row } = await service.rpc("write_byok_audit", { /* ... */ });
    const { error } = await service.from("audit_byok_use").update({ token_count: 999 }).eq("id", row.id);
    expect(error?.code).toBe("P0001");
  });
  it("DELETE raises P0001", async () => { /* analogous */ });
  it("Tenant SELECT scoped to founder_id", async () => { /* RLS shape */ });
});
```

### `byok-audit-writer-sweep.test.ts`

See Phase 3 code block above. Key invariant: every `.ts` file under
`server/**` that either calls `runWithByokLease(` OR imports the
SDK runtime `query`/`sdkQuery` (excluding type-only imports) MUST
contain `persistTurnCost(` OR the structured out-of-scope marker.
Marker-allowlist count asserted ≤ 2.

## Lifecycle gates honored

- `wg-use-closes-n-in-pr-body-not-title-to` — `Closes #3887` in PR body, not title.
- `wg-before-every-commit-run-compound-skill` — invoke at commit time.
- `wg-after-marking-a-pr-ready-run-gh-pr-merge` — auto-merge after green CI + reviews.
- `hr-write-boundary-sentinel-sweep-all-write-sites` — discharged by the writer-sweep CI lint.
- `cq-silent-fallback-must-mirror-to-sentry` — discharged by the deny-event Sentry mirror.
- `hr-gdpr-gate-on-regulated-data-surfaces` — Phase 2.7 gate runs at deepen-plan.
- `hr-dev-prd-distinct-supabase-projects` — all integration tests run against DEV Doppler; AC8/AC10 explicitly DEV-only.
