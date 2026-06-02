---
date: 2026-06-02
type: feat
feature: operator-cc-oauth
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
closes: 4825
pr: 4824
spec: knowledge-base/project/specs/feat-operator-cc-oauth/spec.md
brainstorm: knowledge-base/project/brainstorms/2026-06-02-operator-cc-subscription-auth-brainstorm.md
plan_reviewed: 2026-06-02  # spec-flow + simplicity + architecture; v2 incorporates all P0/P1
deepened: 2026-06-02  # triad resolved P0 fork → two-row consumer-class model (see § Deepen-Plan Resolution)
status: ready-for-work
---

# Plan: Operator Claude Code Subscription Auth (`oauth_token` credential)

## Overview

Add a second **credential type** to Soleur's BYOK system — a Claude Code subscription
OAuth token (`CLAUDE_CODE_OAUTH_TOKEN`, from `claude setup-token`) — so the **operator**
(Jikigai) can fund its **own** server-side dogfooding runs on its **own** Claude Max
subscription instead of paying per-token API rates. Reuses the entire BYOK
encryption/lease/RLS machinery. **Operator-internal only; never customer-facing.**

**Legal floor (CLO sign-off, brainstorm):** permitted-with-guardrails on/after **2026-06-15**
under Anthropic's Agent-SDK-credit policy (per-user, no pooling). Prohibited before — hence
the hard date gate.

**v2 note:** this plan was revised after spec-flow + architecture + simplicity review. The
load-bearing change: **all enforcement lives at the lease decrypt chokepoint**
(`byok-lease.ts fetchAndDecryptIntoSlot`), not in the resolver or per-dispatcher, because 4
of 6 credential consumers bypass both. The P0 fork is now **resolved** — see `## Deepen-Plan Resolution` below.

## Deepen-Plan Resolution (2026-06-02) — supersedes Phases 1–4 where they conflict

Triad (architecture-strategist + data-integrity-guardian + security-sentinel) resolved the P0 fork.

**Decision: Option B — the operator holds BOTH credentials; selection is deterministic by consumer class.** A (force-all-SDK) is disproportionate (`classifyMessage` is a 1-shot REST call; `agent-on-spawn-requested` is a durable Inngest tool-loop — multi-week rewrite). C (degrade) is partial (leader turns can't degrade).

**Data model — TWO ROWS BY PROVIDER (no `credential_type` column).** The single-row `credential_type` discriminator (Phase 1 as written) cannot hold both an api_key and an oauth token on the UNIQUE `(user_id,'anthropic')` row — and P0 proves both are needed.
- `provider='anthropic'` row = the **api_key** (feeds raw-REST consumers).
- NEW `provider='anthropic_oauth'` row = the **oauth_token** (feeds the Agent SDK subprocess).
- `(user_id, provider)` UNIQUE enforces at-most-one-of-each for free. The **provider value IS the discriminator** — drop the `credential_type` column.
- Rejected: parallel oauth-column trio on one row (partial-NULL states, doubled secret surface — the "integrity trap").

**Security boundary is STRUCTURAL, not a runtime check (resolves security P0-1/P0-2 by construction):**
- Raw-REST consumers call `lease.getRestApiKey()` → queries ONLY `provider='anthropic'` → **physically cannot return an oauth token** (it lives in a row the REST query never reads). The oauth→`x-api-key` leak is impossible by construction.
- Agent SDK path calls `lease.getAgentCredential()` → prefer `provider='anthropic_oauth'` (date + owner + kill-switch gates fire HERE, only when oauth is actually selected) → fall back to `provider='anthropic'`. Returns `{ value, scheme: 'api_key'|'oauth_token' }`; `buildAgentEnv` branches on `scheme`.
- Mandatory cross-consumer sweep (`hr-type-widening-cross-consumer-grep`): grep ALL `getApiKey()` sites (≥3); route every raw-REST caller (`domain-router.ts` classify, `agent-on-spawn-requested.ts:452`) to `getRestApiKey()`. Default-missing consumer kind ⇒ raw-REST (deny oauth).

**Gates fire only on the oauth read** (`getAgentCredential` prefer-oauth branch): the owner guard MUST run on the `anthropic_oauth` query path.

**Write path:** the new oauth-secret write goes through a predicate-locked SECURITY DEFINER RPC mirroring `033_migrate_api_key_to_v2_rpc.sql` (`SET search_path = public, pg_temp`, REVOKE authenticated/anon + GRANT service_role, operator-identity predicate baked in so the DB refuses a non-operator oauth write even if the route gate regresses). Existing api_key path unchanged.

**Migration 096 (revised):** provider-CHECK expansion mirroring `014_expand_provider_check.sql` to add `'anthropic_oauth'`. **No new column.** Back-compat: metadata-only re-validate, existing rows unaffected. Down-migration MUST first delete/guard any surviving `anthropic_oauth` rows before restoring the prior CHECK (else the down `ADD CONSTRAINT` fails).

**P1 — validation probe (FR6):** v1 is a NO-OP — "write succeeds; first run validates" (operator is the only user; a bad token fails the first run loudly). Add a test asserting no module outside `agent-env.ts` references `CLAUDE_CODE_OAUTH_TOKEN` (`grep -L`), so the probe can never become a 2nd CWE-526 injection site.

**Telemetry (security P1-2):** assert the 3 `DISABLE_*` overrides cannot be clobbered by the post-allowlist service-token loop (`agent-env.ts:54+`).

**ADR:** capture "BYOK credential-selection by consumer class + structural REST/SDK boundary" via `/soleur:architecture create` (advisory).

## Research Reconciliation — Spec vs. Codebase

| Claim | Codebase reality (verified) | Plan response |
|---|---|---|
| TR1: `credential_type` column on `api_keys` | `(user_id, provider)` UNIQUE (`002:11`); lease filters `.eq("provider","anthropic")` (`byok-lease.ts:294`) | Confirmed: one row/user, `credential_type` discriminates auth method — no two-row precedence. Nothing else keys on `provider` as "auth method" (architecture-verified). |
| ~~SDK `apiKey:` option also maps to `ANTHROPIC_API_KEY`~~ | **FALSE.** No top-level SDK `apiKey:` option exists. `apiKey` at `cc-dispatcher.ts:1088`/`agent-runner.ts:1728` is a field of the `buildAgentQueryOptions({...})` arg, consumed ONLY by `buildAgentEnv` (`agent-runner-query-options.ts:136`) | **The both-keys trap is a SINGLE site** (`buildAgentEnv`). Removed all "omit SDK apiKey option" instructions. |
| Guards live in resolver + dispatcher | **6 credential consumers; only 2 reach `buildAgentEnv`.** Bypass sites: `agent-on-spawn-requested.ts:446` (direct lease → `new Anthropic({apiKey})`), `domain-router.ts:127` (`x-api-key` fetch, live), `cfo-on-payment-failed.ts:203` + `github-on-event.ts:210` (stubs) | **Move guards into `byok-lease.ts fetchAndDecryptIntoSlot` (:288-342)** — the single chokepoint all 6 pass through, and the only place `credential_type` is known. |
| Write via `033` RPC | Actual: raw `service.from("api_keys").upsert(...,{onConflict:'user_id,provider'})` at `app/api/keys/route.ts:44-58` (service-role, no RPC). Both onboarding + settings POST this one route | Server-side gate goes IN this route; drop the RPC reference. |
| `getApiKey()` returns string | Returns `string \| Promise<string>` (`:263-284`); single resolution in `fetchAndDecryptIntoSlot` | Change to atomic `{ value, type }`; thread a single `credential` object end-to-end (NO sibling getter, NO two scalar args). |
| Next migration | Highest `095` | New = **096**; mirror `014_expand_provider_check.sql`. |

## User-Brand Impact

**If this lands broken:** agent runs fail to start, or silently bill the API account while
the operator believes they're on the subscription (both-keys trap).
**If this leaks:** the stored `CLAUDE_CODE_OAUTH_TOKEN` (tied to a personal Claude account,
un-scopable) — same encryption surface as BYOK keys (HKDF + AES-256-GCM, zeroized).
**On down-migration:** `096…down.sql` DELETEs the operator's `anthropic_oauth`
row (load-bearing — required before the CHECK can be restored). This destroys
the stored subscription token, but it is **operator-only and recoverable** by
re-running `claude setup-token` + re-paste; scoped-out as an acknowledged
rollback cost, not a silent data-loss.
**Brand-survival threshold:** single-user incident. CPO sign-off carried from brainstorm;
`user-impact-reviewer` runs at PR review.

## Implementation Phases

### Phase 1 — Schema (migration 096)
- `096_api_keys_credential_type.sql`: `ALTER TABLE api_keys ADD COLUMN credential_type text NOT NULL DEFAULT 'api_key' CHECK (credential_type IN ('api_key','oauth_token'));` (mirror `014`). Existing rows default `api_key`.
- `.down.sql`: drop column. Read+write+tests ship in THIS PR (`2026-05-16-migration-mandates-must-have-wired-call-sites`).

### Phase 2 — Lease: surface type + enforce BOTH guards at the chokepoint (load-bearing)
In `byok-lease.ts fetchAndDecryptIntoSlot` (`:288-342`) — the single point every one of the 6 consumers reaches:
- Add `credential_type` to the select (`:290-297`).
- After the row is read, BEFORE returning plaintext:
  - **Date gate (CLO G1):** `if (type==='oauth_token' && Date.now() < CC_OAUTH_EFFECTIVE_DATE) throw OauthNotYetPermittedError`. Export `CC_OAUTH_EFFECTIVE_DATE = Date.parse('2026-06-15T00:00:00Z')` as the single source.
  - **Owner-only routing (CLO G2):** `if (type==='oauth_token' && (slot.delegationId != null || slot.keyOwnerUserId !== slot.workspaceContextUserId)) throw OauthDelegationForbiddenError`. (`slot.delegationId`/`keyOwnerUserId`/`workspaceContextUserId` are all in scope here; the resolver is NOT — it never reads `credential_type`.)
- Change `getApiKey()` (`:263-284`) to return atomic `{ value, type }`. Extend the cause union + `mapByokLeaseCauseToErrorCode` (`:192-206`) with `subscription_limit`; keep the `: never` rail.

### Phase 3 — Mutually-exclusive env injection (`agent-env.ts`) — single site
- Widen `buildAgentEnv` (`:42-44`) to take `credential: { value, type }` (NOT two scalars — a forgotten `type` defaults to `api_key` = silent wrong-var).
- Branch the auth literal (`:46-49`): `oauth_token` → set ONLY `CLAUDE_CODE_OAUTH_TOKEN`; `api_key` → set ONLY `ANTHROPIC_API_KEY`. Exhaustive `: never` default.
- **Keep `...AGENT_ENV_OVERRIDES` (`:30-34`: `DISABLE_TELEMETRY`/`DISABLE_AUTOUPDATER`/`CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC`) spread at the TOP of `env`, OUTSIDE the auth branch** — a subscription token must not phone home to the operator's personal account.
- Inject the OAuth var INSIDE `buildAgentEnv` only (CWE-526 deny-by-default; do NOT add to `AGENT_ENV_ALLOWLIST` — that copies ambient `process.env`).
- Thread the single `credential` object: lease → `buildAgentQueryOptions` args (replace `AgentQueryOptionsArgs.apiKey: string` at `:62`) → `buildAgentEnv` (`:136`). No phantom SDK-option edit.

### Phase 4 — Write path + server-side operator gate (`app/api/keys/route.ts`)
- Raw upsert at `:44-58` (NOT an RPC). Accept `credential_type` (default `'api_key'` when absent).
- **Server-side reject (403)** when `credential_type==='oauth_token'` AND the caller is not the operator/internal account. This is the authorization gate — enforced in the route, NOT via UI hiding. Both onboarding (`setup-key:68`) + settings (`key-rotation-form:26`) POST this single route, so one check covers both.

### Phase 5 — Error mapping + observability (slim)
- Thread the `subscription_limit` code through `resolveSessionErrorCode` (`agent-runner.ts:101`) + WS send (`cc-dispatcher.ts:1894-1899`) + `ws-client.ts:697-704`. Render via the EXISTING non-retryable error branch in `chat-surface.tsx` (distinct from `key_invalid` to avoid the re-paste wrong-action) — defer bespoke copy to first real hit.
- Mirror the resolution/validation decision to Sentry: one-shot `reportSilentFallback`; `mirrorWithDebounce(..., 'cc-oauth:subscription_limit')` if surfaced in the per-turn iterator (`cq-silent-fallback-must-mirror-to-sentry`).

### Phase 6 — UI toggle + kill-switch
- Extend `components/settings/key-rotation-form.tsx` with a credential-type toggle + paste field + "run `claude setup-token`" copy, visible only when the server marks the caller an operator/internal account (reuse the Phase 4 gate's server-surfaced boolean via `settings/page.tsx:20-27`). No new page/component files → Product/UX = ADVISORY.
- Kill-switch: a single env constant `CC_OAUTH_ENABLED` (default off) checked alongside the date gate — instant disable without a Flagsmith round-trip. (Replaces the Flagsmith flag; see Alternatives.)

### Phase 7 — Tests (no standalone CI sentinel)
- `test/agent-env-credential-type.test.ts`: property test over BOTH branches — env contains **exactly one** of the two auth vars, AND both branches carry the 3 telemetry-suppression overrides. (Folds the only useful CI-sentinel assertion into the suite.)
- `test/byok-lease-credential-type.test.ts`: date gate throws before 2026-06-15 (mocked clock — asserts the THROW); owner-mismatch + delegation throw fail-closed.
- `test/api-keys-oauth-gate.test.ts`: POST `/api/keys` `{credential_type:'oauth_token'}` as non-operator → 403 (hits the route, not the form).
- Migration up/down apply (DEV only).

## Files to Edit
- `apps/web-platform/server/byok-lease.ts` — select `credential_type` (`:294`), atomic `{value,type}` return (`:263-284`), **date+owner guards in `fetchAndDecryptIntoSlot` (`:288-342`)**, `subscription_limit` cause (`:192-206`).
- `apps/web-platform/server/agent-env.ts` — `credential`-object branch (`:42-49`), overrides outside branch (`:30-34`).
- `apps/web-platform/server/agent-runner-query-options.ts` — `credential` arg (`:62`, `:136`).
- `apps/web-platform/server/cc-dispatcher.ts` — `subscription_limit` WS mapping (`:1894-1899`). *(No apiKey-omit edit — phantom.)*
- `apps/web-platform/server/agent-runner.ts` — `resolveSessionErrorCode` (`:101`). *(No apiKey-omit edit.)*
- `apps/web-platform/app/api/keys/route.ts` — accept `credential_type` + server-side operator gate (`:44-58`).
- `apps/web-platform/components/settings/key-rotation-form.tsx` + `app/(dashboard)/dashboard/settings/page.tsx` — toggle + operator-account surfacing.
- `apps/web-platform/lib/ws-client.ts` (`:697-704`) — `subscription_limit` reception.

## Open Design Questions — RESOLVED 2026-06-02 (see § Deepen-Plan Resolution; kept for record)
- **P0 — direct-API consumers cannot use an OAuth token.** `domain-router.ts:127` (`x-api-key` classification fetch, live) and `agent-on-spawn-requested.ts:453` (`new Anthropic({apiKey})`) send the credential to Anthropic's REST API, which an OAuth token CANNOT authenticate. If the operator's single `anthropic` row is `oauth_token`, these paths break. Candidate resolutions: (a) **force-all-through-SDK** — route classification/spawn through the Agent SDK path; (b) **api_key fallback** — these direct paths fall back to a separate operator api_key (reopens two-credential model → reconsider `provider`-value); (c) **reject + degrade** — lease gate rejects `oauth_token` for direct-API callers and they degrade (classification → default route). Interacts with the credential_type-vs-provider decision. **Must resolve before /work.**
- **P1 — token validation probe (FR6).** `setup-token` tokens can't be validated by the `/v1/models` GET. Net-new, no prior pattern. The probe MUST source the token through the lease/`buildAgentEnv`, never a direct `process.env` write (else a 2nd uncovered auth-injection site). Fallback for v1: "write succeeds; first run validates" (operator is the only user).

## Domain Review
**Domains relevant:** Product, Engineering, Legal (carry-forward from brainstorm).
- **Engineering (CTO):** reviewed — feasible ~M; both-keys trap is the load-bearing correctness risk (single site, corrected); reuse BYOK machinery; no new infra.
- **Legal (CLO):** reviewed — permitted-with-guardrails on/after 2026-06-15; per-user/no-pool satisfied by owner-only routing; no new sub-processor / no Art-30 / no external disclosure.
- **Product/UX Gate:** Tier ADVISORY (extends existing settings UI; no new page/component files; operator-internal). Decision: auto-accepted (internal toggle, CPO carry-forward). Skipped: ux-design-lead (internal-only). Pencil: N/A.

## Observability
```yaml
liveness_signal: { what: oauth_token run start/finish (reuse agent-run telemetry), cadence: per run, alert_target: Sentry, configured_in: cc-dispatcher.ts/agent-runner.ts }
error_reporting: { destination: Sentry, fail_loud: true }
failure_modes:
  - { mode: both-keys-set silent API billing, detection: property unit test asserts buildAgentEnv emits exactly one auth var, alert_route: CI fail }
  - { mode: oauth run before 2026-06-15, detection: OauthNotYetPermittedError thrown at lease + Sentry, alert_route: Sentry }
  - { mode: oauth token routed to non-owner / delegated run, detection: OauthDelegationForbiddenError fail-closed at lease + Sentry, alert_route: Sentry }
  - { mode: subscription credit/rate-limit exhausted, detection: subscription_limit code (distinct from key_invalid/429), alert_route: Sentry + user copy }
  - { mode: token expired/revoked mid-run, detection: 401 → key_invalid path, alert_route: Sentry }
logs: { where: existing pino + Sentry, retention: existing }
discoverability_test: { command: "grep -rl CC_OAUTH_EFFECTIVE_DATE apps/web-platform/server/byok-lease.ts", expected_output: "apps/web-platform/server/byok-lease.ts" }
```

## Infrastructure (IaC)
None. Pure code + one DB migration + one env kill-switch constant. No new server/systemd/cron/DNS/vendor/Doppler secret; token stored encrypted in `api_keys`.

## GDPR / Compliance Gate
Skipped-with-rationale: CLO brainstorm sign-off is the authoritative compliance artifact — operator-internal, no customer PII, `credential_type` carries no personal data, no new sub-processor/Art-30 trigger. Single-user-incident trigger (b) acknowledged; CLO already assessed the lens.

## Acceptance Criteria
### Pre-merge (PR)
- AC1. `tsc --noEmit` clean; every `: never` rail (incl. `*.test-d.ts`) updated (compiler-enumerated).
- AC2. `buildAgentEnv({type:'oauth_token'})` → env has `CLAUDE_CODE_OAUTH_TOKEN`, NO `ANTHROPIC_API_KEY`; inverse for `api_key`; property test asserts exactly-one auth var across both branches.
- AC2b. BOTH branches' env contain `DISABLE_TELEMETRY`, `DISABLE_AUTOUPDATER`, `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC` (overrides outside the branch).
- AC3. Date gate at the lease throws `OauthNotYetPermittedError` before 2026-06-15 (mocked clock; asserts the throw).
- AC4. Owner/delegation mismatch on `oauth_token` → `OauthDelegationForbiddenError` fail-closed at the lease.
- AC5. POST `/api/keys` `{credential_type:'oauth_token'}` as non-operator → 403 (route-level, not form).
- AC6. `subscription_limit` renders non-retryable copy distinct from `key_invalid` + Sentry event.
- AC7. Migration 096 applies; existing rows default `api_key`; `.down.sql` reverses (DEV only).
- AC8. `CC_OAUTH_ENABLED` off OR caller-not-operator ⇒ feature inert (no toggle, write path 403s `oauth_token`).
### Post-merge (operator)
- None. (Flag removed → no `flag-create` step; the gate is server-side + an env constant set at deploy.)

## Open Code-Review Overlap
None known at plan time; re-run `gh issue list --label code-review --state open` vs. Files-to-Edit at /work.

## Alternative Approaches Considered
| Approach | Why rejected |
|---|---|
| New `provider='claude_code_oauth'` (separate row) | `(user_id,provider)` UNIQUE → two coexisting rows → "which funds the run?" precedence ambiguity. *(But see Open Design Q P0 — if direct-API paths need an api_key fallback, two-credential may return; deepen-plan decides.)* |
| Flagsmith flag (spec FR7) | YAGNI for a one-user internal feature: no rollout, no targeting population. Replaced by a server-side operator-account gate (the real authz fence) + an env kill-switch. Removes the deferred operator `flag-create` step. (Plan corrects spec's implementation means; operator-only goal preserved.) |
| Standalone CI sentinel script | Redundant with behavioral unit tests (AC2/AC3/AC4); folded the one useful assertion (exactly-one-auth-var) into the test suite. |
| Offer to customers (original ask) | Killed: Consumer-Terms violation + illusory non-technical-ICP onboarding (brainstorm). |
| Dogfood via local CLI (no web-app change) | Doesn't cut web-app API spend; valid zero-code interim, not the build. |

## Sharp Edges
- Empty/`TBD` User-Brand Impact fails deepen-plan 4.6 — filled.
- The both-keys trap is a **single** site (`buildAgentEnv`); the "second SDK option" is a phantom — do not re-add it.
- Enforcement MUST be at the lease chokepoint, not the resolver (resolver can't see `credential_type`) nor per-dispatcher (4 of 6 consumers bypass dispatchers).
- Direct-API consumers (`domain-router`, `agent-on-spawn-requested`) cannot use an OAuth token — unresolved fork in Open Design Questions; resolve before /work.
- Telemetry-suppression overrides must stay outside the auth branch (subscription-token phone-home risk).
