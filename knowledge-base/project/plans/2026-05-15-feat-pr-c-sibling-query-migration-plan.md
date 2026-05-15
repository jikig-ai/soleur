---
title: PR-C — Sibling-query migration (#3244 §2)
date: 2026-05-15
status: ready-for-work
umbrella_issue: 3244
predecessor_prs: [3240, 3395]
branch: feat-runtime-slice-3244
worktree: .worktrees/feat-runtime-slice-3244/
pr: 3854
brainstorm: knowledge-base/project/brainstorms/2026-05-15-pr-c-sibling-query-migration-brainstorm.md
spec: knowledge-base/project/specs/feat-runtime-slice-3244/spec.md
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
lane: cross-domain
---

# PR-C — Sibling-query migration (#3244 §2)

## Overview

Extend the gate-zero pattern PR-B (#3395) shipped in `agent-runner.ts` outward
to the rest of the server-side Supabase surface. Migrate ~34 tenant-scoped
call sites across 11 files in `apps/web-platform/server/` from
`createServiceClient()` to `getFreshTenantClient(userId)`, wrap the
`cc-dispatcher` BYOK plaintext-fetch path in `runWithByokLease`, and shrink
`.service-role-allowlist` to permanent entries only.

No new tables, no new RPCs, no new sub-processors. Same playbook as PR-B —
same review surface, lower review-cost-per-site than PR-D would be.

Closes: `Ref #3244` (umbrella), `Closes #3392` for the cc-dispatcher BYOK
item only (in PR body, not title — `wg-use-closes-n-in-pr-body-not-title-to`).

## Research Reconciliation — Spec vs. Codebase

The spec was authored against a stale `main` snapshot. Re-grepping at plan
time at `c0f1e3ab` reveals divergence on three axes: per-file site count,
line numbers, and cc-dispatcher scope. The plan operates on the fresh
enumeration below, not on the spec's numbers.

| Spec claim | Codebase reality (re-grep 2026-05-15) | Plan response |
|------------|---------------------------------------|---------------|
| `ws-handler.ts` 10 sites at `:294, :432, :452, :754, :767, :812, :896, :1116, :1410` (9 numbers given for "10 sites") | 13 `.from(...)` sites at `:265, :283, :326, :506, :541, :644, :664, :1101, :1114, :1159, :1262, :1514, :1834` (zero `.rpc(...)` sites). PLUS one PERMANENT-by-design `supabase.auth.getUser(token)` at `:1812` for the WS auth handshake — pre-tenant-JWT token validation. | Use the fresh enumeration for the 13 tenant sites. The `:1812` auth-handshake call is the load-bearing reason the file stays on the allowlist as PERMANENT after PR-C, not removable. |
| `conversations-tools.ts` 4 sites at `:150, :211, :248, :291` | 4 sites at `:156, :217, :254, :297` (drift ~6 lines) | Use fresh line numbers; semantic shape matches spec. |
| `session-sync.ts` 4 sites at `:187, :236, :254, :270` | 4 sites at `:187, :236, :254, :270` (exact match) | Adopt spec verbatim. |
| `cc-dispatcher.ts:426` (BYOK fetch only) | BYOK fetch at `:878–:879` (`getUserApiKey` + `getUserServiceTokens` in `Promise.all`) PLUS two `supabase().from("messages").insert(...)` writes at `:1367, :1464` PLUS `supabase: supabase()` service-role client passed into `persistAndDownloadAttachments({...})` at `:1395` (attachments-storage injection — out-of-scope for tenant migration; classified PERMANENT pending PR-D attachments-RLS review) | Plan extends `cc-dispatcher` scope to BYOK fetch + 2 `messages.insert` writes. The `:1395` attachments injection is the load-bearing reason cc-dispatcher.ts stays on the allowlist after PR-C — not the speculative "may have other callers." |
| `api-messages.ts` "2 sites all migrate" | 2 sites at `:55, :79` migrate to tenant. PLUS one PERMANENT-by-design `supabase.auth.getUser(token)` at `:36` for HTTP Bearer-token validation — pre-tenant-JWT. | Migrate the 2 tenant sites; file stays on allowlist as PERMANENT (auth bootstrap), allowlist comment updated from "TRANSITIONAL — PR-C" to "PERMANENT — auth.getUser bootstrap." |
| `.rpc(...)` enumeration claim "every site checks REVOKE EXECUTE FROM authenticated" | Single `.rpc(...)` in scope: `service.rpc("sum_user_mtd_cost", ...)` at `api-usage.ts:104`. Migration `027_mtd_cost_aggregate.sql:68` REVOKEs from authenticated. | This RPC stays service-role with comment + allowlist line. No other RPCs in the 11 files. |
| Total site count "~30" | 34 tenant-migration sites + 3 PERMANENT auth/attachments sites (ws-handler `:1812` + api-messages `:36` + cc-dispatcher `:1395`) | 33 of 34 tenant-migration sites move to tenant-client; 1 stays service-role (sum_user_mtd_cost RPC). The 3 PERMANENT sites do NOT count against the migration target — they were always supposed to stay service-role and were under-classified in spec. |
| Tables touched | `conversations`, `messages`, `users`, `team_names`, `user_concurrency_slots` (3 sites in ws-handler) | `user_concurrency_slots` has `slots_owner_read` RLS (`auth.uid() = user_id`) per migration 029:91 — all three sites are SELECTs, safe to migrate. Confirmed at plan time. |

## User-Brand Impact

**If this lands broken, the user experiences:** a closed-preview founder
either (a) loses their session at start time because `getFreshTenantClient`
throws against a path the runner hasn't proven (b) sees a corrupted/empty
chat history because a migrated `messages` SELECT silently returns zero rows
under tenant-JWT against a malformed RLS predicate, or (c) sees their per-turn
cost tracking silently disabled because `sum_user_mtd_cost` was not classified
as REVOKEd and the tenant-JWT call 42501s into Sentry.

**If this leaks, the user's data is exposed via:** cross-tenant FK-spoof read
of `messages.content` through ws-handler, cross-tenant `conversations` UPDATE
via missing `WITH CHECK`, cross-founder probe of
`users.{workspace_path,repo_status,github_installation_id}` at session-sync
start, OR a `cc-dispatcher` BYOK plaintext key resident in V8 heap with no
lease bound (unbounded GC residency).

**Brand-survival threshold:** `single-user incident`. Carry-forward from PR-B
(#3395 body matrix). PR-C extends the same surface outward.

Artifact + vector matrix (audited at PR-review time by `user-impact-reviewer`):

| Artifact | Vector | Mitigation in PR-C |
|----------|--------|---------------------|
| `messages.content` | Cross-conversation FK-spoof read via ws-handler/api-messages/conversation-writer | RLS via FK-join to `conversations.user_id`; integration tests assert denial per (file, op) tuple. |
| `conversations.*` writes | Cross-tenant UPDATE via missing `WITH CHECK` | `USING` governs both read and write; cross-founder UPDATE + service-role re-read regression test on conversations-tools, conversation-writer, ws-handler write sites. |
| `team_names.custom_name` | Cross-tenant route-leak via session-sync, ws-handler | Tenant-client read; regression test per file. |
| `users.{workspace_path,repo_status,github_installation_id}` | Cross-founder probe at session-sync / ws-handler / current-repo-url / kb-document-resolver / kb-route-helpers | `auth.uid() = id` policy; regression test per file. |
| `user_concurrency_slots` (3 sites) | Cross-tenant concurrency-state leak | `slots_owner_read` SELECT policy (`auth.uid() = user_id`, migration 029:91) — tenant client returns owner rows only; cross-founder denial test on one site as representative. |
| BYOK plaintext on dispatcher path | `cc-dispatcher.ts:878–879` returns plaintext string into V8 heap with no lease scope | `runWithByokLease` wrap on `realSdkQueryFactory` mirroring `startAgentSession`; zeroize-on-finally; `lease.getApiKey()` replaces direct `getUserApiKey` call. |
| `sum_user_mtd_cost` (cost rollup) | Silent 42501 if migrated naively | Stays service-role with `// SERVICE-ROLE: RPC revoked from authenticated — see migration 027` comment + allowlist entry; `reportSilentFallback` mirror on error. |
| CI gate self-defeat | Attacker-modeled PR adds new TRANSITIONAL allowlist entry | CODEOWNERS pin from PR-B in place; PR-C only REMOVES entries. Each removal commit is security-owner-required. Plan body documents the removal-only invariant. |

## Domain Review

**Domains relevant:** Engineering, Product, Legal. (Marketing, Operations,
Sales, Finance, Support: not relevant — internal hardening, no user-visible
surface, no commercial terms.) Carry-forward from brainstorm Phase 0.5.

### Engineering (CTO)

**Status:** reviewed (brainstorm carry-forward); plan-review-validated 2026-05-15
**Assessment:** PR-B is 100% done. PR-C is the sibling-query migration that
closes out the transitional service-role allowlist. Same playbook as PR-B;
primary risk is RPC GRANT mismatch (caught once in PR-B). Plan enumerates the
single `.rpc(...)` in scope upfront AND three PERMANENT auth/attachments
service-role surfaces the spec missed (ws-handler `auth.getUser`,
api-messages `auth.getUser`, cc-dispatcher attachments injection). No new
architecture.

### Product (CPO)

**Status:** reviewed (brainstorm carry-forward); sign-off granted
**Assessment:** PR-C is invisible to the founder — that's a feature given
the brand-survival threshold. Daily Priorities deferred to its own
brainstorm post-PR-C. CPO sign-off on the technical approach is granted at
plan time per `requires_cpo_signoff: true`.

### Product/UX Gate

**Tier:** none
**Decision:** N/A
**Agents invoked:** none
**Pencil available:** N/A

No new user-facing pages, no new components, no UI flows. Scan of "Files to
Create" / "Files to Edit": zero matches for `components/**/*.tsx`,
`app/**/page.tsx`, `app/**/layout.tsx`. Mechanical UX-gate escalation rule
does not fire.

### Legal (CLO)

**Status:** reviewed (brainstorm carry-forward); legal-compliance-auditor
PASS-with-advisories 2026-05-15
**Assessment:** Internal hardening of existing processing. Lawful basis:
Art. 6(1)(b) contract performance (delivering founder's own data to the
founder) + Art. 6(1)(f) legitimate interest as a security measure
(Recital 49 recognizes network/information security). No new DPA
prerequisite, no new sub-processor, no public Privacy Policy delta. Article
30 register update needed: extend the existing PA1/PA2 TOM row to note the
expanded tenant-JWT surface (now covers ws-handler, session-sync, api-*,
conversation-writer, lookup-*, current-repo-url, kb-*, cc-dispatcher) AND
name the layered controls (tenant JWT + RLS + auth-probe + service-role
allowlist gate + lease scope + CODEOWNERS pin + cross-tenant denial
integration tests) so the TOM row reflects defense-in-depth rather than
relying on RLS alone (Art. 25 advisory). Post-merge Art. 30 update SLA:
within 7 calendar days of merge. The load-bearing `audit_byok_use` artifact
stays paper-only until PR-D wires the writer — flag for next slice, NOT
blocker for PR-C **provided** PR-D's writer is sequenced before public/GA
exposure or onboarding the 2nd hosted founder (Art. 5(2) accountability).

### GDPR Gate

**Triggered by:** brand-survival threshold `single-user incident` (trigger
(b) of the expanded canonical regex). Invoke `/soleur:gdpr-gate` post-plan
authoring, pre plan-review.

**Expected output:** advisory; CLO's brainstorm assessment already covers
the substantive determination (no new processing activity, no new
sub-processor, no Privacy Policy delta, Article 30 register update only).
Gate will note the Article 30 PA1/PA2 row update as the operator-only
post-merge action.

## Implementation Phases

### Phase 0 — Preconditions (single commit)

Goal: lock the per-site classification table BEFORE any code edits, so /work
operates on a verified site inventory, not on plan paraphrase.

- **0.1** — Re-run the per-file site enumeration at the work-time HEAD:

  ```bash
  for f in server/ws-handler.ts server/conversations-tools.ts \
           server/session-sync.ts server/api-messages.ts server/api-usage.ts \
           server/conversation-writer.ts server/lookup-conversation-for-path.ts \
           server/current-repo-url.ts server/kb-document-resolver.ts \
           server/kb-route-helpers.ts server/cc-dispatcher.ts; do
    echo "=== $f ==="
    grep -nE '\.(from|rpc)\(' "apps/web-platform/$f"
  done > /tmp/pr-c-site-inventory.txt
  ```

  Compare against the Phase 0.3 table below; any divergence ≥ 5 lines or
  count mismatch halts and prompts a plan delta before proceeding.

- **0.2** — Verify infrastructure shapes at the installed version
  (`2026-05-14-plan-prescribed-runtime-shapes-must-be-grepped-against-installed-version`):

  ```bash
  grep -nE '^export (async )?function (getFreshTenantClient|mintFounderJwt)' \
    apps/web-platform/lib/supabase/tenant.ts
  grep -nE '^export (async )?function runWithByokLease|getApiKey\(\)' \
    apps/web-platform/server/byok-lease.ts
  ```

  Confirmed at plan time:
  - `getFreshTenantClient(userId)` at `tenant.ts:236` returns
    `{ client: SupabaseClient, jwt: MintedJwt }`.
  - `mintFounderJwt(userId, opts)` at `tenant.ts:124`.
  - `runWithByokLease<T>(userId, fn)` at `byok-lease.ts:213`.
  - `lease.getApiKey(): string | Promise<string>` (per F3 contract,
    `byok-lease.ts:104`).

- **0.3** — Per-site classification table (canonical inventory; supersedes
  spec line numbers):

  | File | Line | Table / RPC | Op | userId in scope? | Decision |
  |------|------|-------------|----|--------|----------|
  | `ws-handler.ts` | 265 | `conversations` | SELECT | yes | migrate (tenant) |
  | `ws-handler.ts` | 283 | `user_concurrency_slots` | SELECT | yes | migrate (tenant; `slots_owner_read` RLS, mig 029:91) |
  | `ws-handler.ts` | 326 | `user_concurrency_slots` | SELECT | yes | migrate (tenant) |
  | `ws-handler.ts` | 506 | `users` | SELECT | yes | migrate (tenant) |
  | `ws-handler.ts` | 541 | `user_concurrency_slots` | SELECT-count | yes | migrate (tenant) |
  | `ws-handler.ts` | 644 | `conversations` | INSERT | yes | migrate (tenant) |
  | `ws-handler.ts` | 664 | `conversations` | classify at /work (UPDATE vs SELECT context) | yes | migrate (tenant) |
  | `ws-handler.ts` | 1101 | `conversations` | classify at /work | yes | migrate (tenant) |
  | `ws-handler.ts` | 1114 | `messages` | classify at /work | yes | migrate (tenant) |
  | `ws-handler.ts` | 1159 | `users` | classify at /work | yes | migrate (tenant) |
  | `ws-handler.ts` | 1262 | `conversations` | classify at /work | yes | migrate (tenant) |
  | `ws-handler.ts` | 1514 | `conversations` | classify at /work | yes | migrate (tenant) |
  | `ws-handler.ts` | 1834 | `users` | classify at /work | yes | migrate (tenant) |
  | `conversations-tools.ts` | 156, 217, 254, 297 | `conversations` | mix | yes | migrate (tenant) all 4 |
  | `session-sync.ts` | 187, 236, 254, 270 | `users` | SELECT/UPDATE | yes | migrate (tenant) all 4 |
  | `api-messages.ts` | 55 | `conversations` | SELECT | yes | migrate (tenant) |
  | `api-messages.ts` | 79 | `messages` | SELECT | yes | migrate (tenant; FK-join through `conversations.user_id`) |
  | `api-usage.ts` | 96 | `conversations` | SELECT | yes | migrate (tenant) |
  | `api-usage.ts` | 104 | `sum_user_mtd_cost` RPC | EXECUTE | yes | **KEEP service-role** — `REVOKE EXECUTE FROM authenticated` per migration 027:68. Add `// SERVICE-ROLE: RPC revoked from authenticated — see migration 027` comment. File-level allowlist entry stays. |
  | `conversation-writer.ts` | 157 | `conversations` | UPDATE | yes | migrate (tenant); writer is the canonical owner of `conversations.update` per file header. |
  | `lookup-conversation-for-path.ts` | 51 | `conversations` | SELECT | yes | migrate (tenant) |
  | `current-repo-url.ts` | 26 | `users` | SELECT | yes | migrate (tenant) |
  | `kb-document-resolver.ts` | 74 | `users` | SELECT | yes | migrate (tenant) |
  | `kb-route-helpers.ts` | 69, 188 | `users` | SELECT | yes | migrate (tenant) both |
  | `cc-dispatcher.ts` | 878–879 | `getUserApiKey` + `getUserServiceTokens` (BYOK fetch) | RPC chain | yes | wrap `realSdkQueryFactory` body in `runWithByokLease`; replace `getUserApiKey(args.userId)` with `lease.getApiKey()`. `getUserServiceTokens` stays inside the lease body (service-role inside the lease is fine — lease owns the scope). |
  | `cc-dispatcher.ts` | 1367 | `messages` | INSERT | yes | migrate (tenant); `assertWriteScope` already at `:1361`. |
  | `cc-dispatcher.ts` | 1464 | `messages` | INSERT | yes | migrate (tenant); `assertWriteScope` already at `:1455`. |
  | `ws-handler.ts` | 1812 | `supabase.auth.getUser(token)` (token validation) | auth.getUser | NO (token IS what produces userId) | **KEEP service-role — PERMANENT** (auth-domain bootstrap; pre-tenant-JWT). File stays on allowlist with comment update from "TRANSITIONAL — PR-C" to "PERMANENT — WS auth.getUser handshake". |
  | `api-messages.ts` | 36 | `supabase.auth.getUser(token)` (HTTP Bearer validation) | auth.getUser | NO (token IS what produces userId) | **KEEP service-role — PERMANENT** (auth-domain bootstrap; pre-tenant-JWT). File stays on allowlist with comment update from "TRANSITIONAL — PR-C" to "PERMANENT — HTTP auth.getUser bootstrap". |
  | `cc-dispatcher.ts` | 1395 | `supabase: supabase()` passed into `persistAndDownloadAttachments({...})` | service-role injection (storage I/O) | yes (userId is in scope but attachments-storage RLS is out of PR-C scope) | **KEEP service-role — PERMANENT pending PR-D** attachments-storage RLS review. File stays on allowlist with rationale anchored on this surface (NOT on speculative ":852 lazy-init may have callers"). |

  **Total: 34 tenant-migration sites + 3 PERMANENT auth/attachments sites** —
  of the 34, 33 migrate to tenant-client and 1 stays service-role
  (`sum_user_mtd_cost` RPC; REVOKE from authenticated, migration 027:68).
  The 3 PERMANENT sites do NOT count toward the migration target — they are
  load-bearing service-role surfaces that the spec under-classified.
  Re-derive from this table at /work-start; do NOT trust paraphrased counts.

- **0.4** — Auth-probe pattern (per
  `2026-04-12-silent-rls-failures-in-team-names`): exactly one probe per
  function entry point that has user-scoped queries (NOT one per query —
  redundant). Probe form:

  ```ts
  const { client } = await getFreshTenantClient(userId);
  // Auth probe: RLS denial returns zero rows, not an error — force a
  // known-good baseline before relying on subsequent reads.
  const { error: probeErr } = await client
    .from("users")
    .select("id")
    .eq("id", userId)
    .maybeSingle();
  if (probeErr) {
    reportSilentFallback(probeErr, { feature: "<file>", op: "auth-probe", extra: { userId } });
    throw new RuntimeAuthError("auth-probe", { cause: probeErr });
  }
  ```

  **Why explicit probe, not `precheck_jwt_mint` reliance:**
  `precheck_jwt_mint` runs ONCE at JWT-mint time (rate-limit + jti-denial
  check). After the JWT is cached (TTL-based, see `tenant.ts` cache), later
  `getFreshTenantClient` calls inside the TTL window do NOT re-precheck.
  The per-handler probe verifies the JWT can still read its OWN row
  RIGHT NOW — catches mid-session jti revocation, mid-TTL policy churn,
  and silent RLS misconfiguration. Different control; not redundant.

  **Literal entry-point list (per file, exported function names):**
  - `server/ws-handler.ts`: `tryLedgerDivergenceRecovery(userId)`,
    `refreshSubscriptionStatus(userId, session)`,
    `dispatchSoleurGoForConversation(...)`,
    `setupWebSocket` inline auth handler (single probe at handshake
    completion, after `auth.getUser` resolves userId),
    `handleMessage` inline router (one probe at top, not per-message-type
    sub-handler — sub-handlers inherit).
  - `server/conversations-tools.ts`: each of the 4 tool factories returned
    by `buildConversationsTools(userId)` — probe at factory boundary, not
    at the builder.
  - `server/session-sync.ts`: `syncPull(userId)`, `syncPush(userId, ...)`.
  - `server/api-messages.ts`: the exported HTTP route handler (single probe
    after `auth.getUser` resolves userId).
  - `server/api-usage.ts`: the exported route handler.
  - `server/conversation-writer.ts`: `updateConversation(userId, ...)`.
  - `server/lookup-conversation-for-path.ts`: the single exported function.
  - `server/current-repo-url.ts`: `getCurrentRepoUrl(userId)`.
  - `server/kb-document-resolver.ts`: `fetchUserWorkspacePath(userId)`.
  - `server/kb-route-helpers.ts`: `authenticateAndResolveKbPath(...)`,
    `resolveUserKbRoot(userId)`, `syncWorkspace(userId, ...)`.
  - `server/cc-dispatcher.ts`: `realSdkQueryFactory(args)` —
    `runWithByokLease`'s body opens with `getFreshTenantClient(args.userId)`;
    add explicit probe at the top of the lease body. The 2 `messages.insert`
    write functions inherit the probe via the dispatch entry.

  /work-time verification: grep each file's exported surface
  (`grep -nE '^export (async )?function' <file>`); every name that takes
  `userId: string` as a parameter MUST have a probe on the entry path. Names
  that operate at process scope without userId (cleanup sweeps, timer
  registrations) are correctly probe-less.

### Phase 1 — Test helper extraction — REMOVED (review-driven)

Phase 1 originally extracted `apps/web-platform/test/helpers/runtime-mocks.ts`.
Plan-review (DHH + Code-Simplicity, both CONCUR) flagged this as YAGNI: the
helper was load-bearing for PR-C **plus** the deferred 19-file retrofit, but
the retrofit is the helper's natural home. Inlining `vi.mock(...)` boilerplate
into PR-C's 8 new test files costs ~120 LOC of trivially-reviewable copy-paste;
extracting a helper for PR-C only adds a test-helper-infra liability (hoisting
risk, extra commit, sanity test) on a security-critical PR.

**Resolution:** Inline `vi.mock("@/lib/supabase/tenant", ...)` in PR-C's
8 new test files using the existing PR-B pattern verbatim. Filed as
tracked deferral: extract the helper in the retrofit PR and propagate to
all 27 callers (19 existing + 8 new) in a single dedicated cleanup PR.

### Phase 2 — Per-file migration (one commit per file, smallest first)

Order: smallest files first to prove the pattern, ws-handler + cc-dispatcher
last because they carry the most sites and the most reviewer attention.
Per-file commits keep the diff per-site reviewable (carry-forward of
brainstorm decision; PR-B's whitespace-chore follow-up note explicitly
recommended per-file).

For each file:

1. Read the entry-point function(s) that hold the call site.
2. Replace module-level `createServiceClient()` with per-call
   `getFreshTenantClient(userId)`.
3. Insert auth probe per Phase 0.4 (function-level, not query-level).
4. Update test mock to use Phase 1 helper.
5. Add cross-tenant denial integration test (one per (file, table, op)
   tuple actually exercised by user-routable code).
6. Update PR-B's allowlist entry for this file: remove TRANSITIONAL line
   (Phase 4 batches all removals into one commit AFTER all files migrate).
7. Sanitize errors via `sanitizeErrorForClient` + `reportSilentFallback`
   per `cq-silent-fallback-must-mirror-to-sentry`.

Order:

- **2.1** — `session-sync.ts` (4 sites — spec line numbers exact match;
  shortest file with non-trivial site count; proves pattern). Lifts
  TRANSITIONAL allowlist entry on completion of Phase 4.
- **2.2** — `api-messages.ts` (2 sites).
- **2.3** — `api-usage.ts` (1 SELECT migrates; RPC at :104 stays service-role
  with comment).
- **2.4** — `conversation-writer.ts` (1 site; canonical `conversations.update`
  owner — must preserve the file-level lint contract noted at `:13–:19`).
- **2.5** — `lookup-conversation-for-path.ts` (1 site).
- **2.6** — `current-repo-url.ts` (1 site).
- **2.7** — `kb-document-resolver.ts` (1 site).
- **2.8** — `kb-route-helpers.ts` (2 sites).
- **2.9** — `conversations-tools.ts` (4 sites).
- **2.10** — `ws-handler.ts` (13 sites). Largest; merits its own per-site
  classification at /work-start (UPDATE-vs-SELECT for the lines marked
  "classify at /work" in Phase 0.3). Auth probe at each entry function
  (`recoverOrphanedSlot`, `refreshSubscriptionStatus`, message-receive
  handlers, conversation-create handlers, session-resume handler).
- **2.11** — `cc-dispatcher.ts` (BYOK lease wrap + 2 `messages.insert`
  sites). The lease wrap is the load-bearing part; closes #3392's "two
  parallel BYOK fetch surfaces" hazard. Mirror `startAgentSession` shape:
  `runWithByokLease(args.userId, async (lease) => { ... realSdkQueryFactory
  body ... })`.

  **BYOK reshape — canonical pattern (per `agent-runner.ts:2361`):**
  do NOT thread `lease.getApiKey()` into the existing `Promise.all`
  destructure. The type signature
  `lease.getApiKey(): string | Promise<string>` produces a union that
  TypeScript infers awkwardly inside `Promise.all`'s array element type;
  `buildAgentQueryOptions.apiKey: string` (per
  `agent-runner-query-options.ts:62`) would then surface a TS2322 at build.
  Instead, hoist the await OUT of the `Promise.all`:

  ```ts
  // Inside runWithByokLease body:
  const apiKey = await lease.getApiKey();
  const [workspacePath, serviceTokens] = await Promise.all([
    fetchUserWorkspacePath(args.userId),
    getUserServiceTokens(args.userId),
  ]);
  ```

  `getUserServiceTokens` stays inside the lease body (the lease zeroize
  contract bounds plaintext residency for the API key; service tokens are
  separate plaintext path and an explicit non-goal per #3392 — tracked
  deferral below).

  The 2 `messages.insert` sites at `:1367` and `:1464` migrate to a
  tenant-client (`getFreshTenantClient(userId)` inside `runWithByokLease`
  body); both already have `assertWriteScope` predicates at `:1361`/`:1455`
  per `hr-write-boundary-sentinel-sweep-all-write-sites`.

  Site `:1395` (`persistAndDownloadAttachments({ supabase: supabase() })`)
  stays service-role and keeps `cc-dispatcher.ts` on the allowlist with
  the new rationale anchored on this surface — NOT on the speculative
  `:852 lazy-init` hedge. Attachments-storage RLS review is PR-D scope.

### Phase 3 — app/api SSR sample audit — DEFERRED (review-driven)

Phase 3 originally bundled a 5-route `app/api/**/route.ts` audit (FR6).
Plan-review (DHH + Code-Simplicity, both CONCUR) flagged this as scope
creep on a security-critical migration PR — the audit produces a
doc-only artifact (`app-api-audit.md`) with no migration consumer.

**Resolution:** File the audit as a tracked deferral issue with the same
5-route sample selection preserved (`app/api/conversations`, `app/api/keys`,
`app/api/kb/upload`, `app/api/team-names`, `app/api/account/export`) so the
follow-up doc PR inherits the coverage-driven scope. Labels verified at
plan time: `domain/engineering` + `priority/p2-medium` both exist. FR6 is
satisfied by the deferred issue, not by an in-PR-C artifact.

### Phase 4 — Shrink `.service-role-allowlist` (single commit)

Goal: remove every TRANSITIONAL entry whose file was fully migrated. CODEOWNERS
pin means this commit requires security-owner approval — by design.

- **4.1** — Remove from allowlist (TRANSITIONAL entries that fully migrate):
  - `apps/web-platform/server/conversations-tools.ts`
  - `apps/web-platform/server/session-sync.ts`
  - `apps/web-platform/server/conversation-writer.ts`
  - `apps/web-platform/server/lookup-conversation-for-path.ts`
  - `apps/web-platform/server/current-repo-url.ts`
  - `apps/web-platform/server/kb-document-resolver.ts`
  - `apps/web-platform/server/kb-route-helpers.ts`

- **4.2** — Convert allowlist entry from TRANSITIONAL to PERMANENT
  (rationale changes; file stays):
  - `apps/web-platform/server/ws-handler.ts` — new rationale:
    `# PERMANENT — WS auth handshake (server/ws-handler.ts:1812
    supabase.auth.getUser(token)) validates the operator-supplied token
    BEFORE userId exists. Auth-domain bootstrap, structurally pre-tenant-JWT.`
  - `apps/web-platform/server/api-messages.ts` — new rationale:
    `# PERMANENT — HTTP Bearer-token validation (server/api-messages.ts:36
    supabase.auth.getUser(token)) for the /api/conversations/:id/messages
    route. Auth-domain bootstrap, pre-tenant-JWT.`
  - `apps/web-platform/server/api-usage.ts` — new rationale:
    `# PERMANENT — sum_user_mtd_cost RPC is REVOKE EXECUTE FROM authenticated
    (migration 027:68). Per-row WHERE clause + RPC call must stay service-role.`
  - `apps/web-platform/server/cc-dispatcher.ts` — new rationale:
    `# PERMANENT (pending PR-D attachments review) — server/cc-dispatcher.ts:1395
    passes service-role into persistAndDownloadAttachments({supabase: supabase()})
    for attachments-storage I/O. Tenant migration of attachments depends on
    storage RLS work scheduled for PR-D.`

- **4.3** — Allowlist content after PR-C should be only:
  - PERMANENT: `lib/supabase/service.ts`, `lib/supabase/server.ts`,
    `lib/supabase/tenant.ts`, `server/byok-lease.ts`, `server/agent-runner.ts`,
    `app/api/webhooks/stripe/route.ts`, `server/cost-writer.ts`,
    `server/dsar-export.ts`, `server/account-delete.ts`,
    `server/concurrency.ts`, `server/notifications.ts`,
    `server/ws-handler.ts` (auth bootstrap), `server/api-messages.ts`
    (auth bootstrap), `server/api-usage.ts` (RPC-only),
    `server/cc-dispatcher.ts` (attachments injection, pending PR-D).
  - TRANSITIONAL: **none.** Every entry post-PR-C has a permanent rationale.

- **4.4** — Verify gate: `bash apps/web-platform/scripts/service-role-allowlist-gate.sh`
  + `bash apps/web-platform/test/ci/service-role-allowlist-gate.test.sh`.

### Phase 5 — Update `tasks.md` (single commit)

Goal: close out PR-B's stale §1.5 checkboxes + add §2 PR-C checkboxes per
FR7.

- **5.1** — Check off `tasks.md §1.5.1 → §1.5.4`, `§1.6.2 → §1.6.5`,
  `§1.7.2` (all PR-B deliverables already merged).
- **5.2** — Add `§2.1` PR-C completion checkboxes (one per file in Phase 2
  + Phase 4 + Phase 3 audit).
- **5.3** — Cross-reference the deferrals: `§2.2 PR-D scope`,
  `§3 deferred` (audit-writer, is_jti_denied, timer pair, /proc test,
  Daily Priorities, Inngest).

### Phase 6 — Verification + multi-agent review (no commit)

- **6.1** — `bun run typecheck` clean.
- **6.2** — `bun run test` green (vitest, including new cross-tenant denial
  tests). Cross-tenant denial coverage: one test per (file, table, op)
  tuple exercised by user-routable code. Test JWT fixtures use synthesized
  project refs and are decode-verified, NOT source-grep'd (per
  `2026-04-29-jwt-fixture-reminting-decode-verify`).

  **Critical: integration tests must NOT skip silently.** PR-B's pattern
  uses `describe.skipIf(!INTEGRATION_ENABLED)` (see
  `apps/web-platform/test/server/agent-runner.tenant-isolation.test.ts:36,60`),
  gated by `TENANT_INTEGRATION_TEST=1` and `SUPABASE_JWT_SECRET`. If the
  pre-merge gate runs WITHOUT those env vars, the cross-tenant denial tests
  SKIP — reproducing the exact vitest-blind trap the 2026-05-06 learning
  describes. Pre-merge gate REQUIRES:

  ```bash
  # In CI / pre-merge gate (Doppler-injected secrets):
  TENANT_INTEGRATION_TEST=1 \
  SUPABASE_JWT_SECRET="$(doppler secrets get SUPABASE_JWT_SECRET --plain)" \
  SUPABASE_URL="$(doppler secrets get NEXT_PUBLIC_SUPABASE_URL --plain)" \
  SUPABASE_SERVICE_ROLE_KEY="$(doppler secrets get SUPABASE_SERVICE_ROLE_KEY --plain)" \
  bun run test apps/web-platform/test/server/*.tenant-isolation.test.ts
  ```

  AC verification: post-run, the test output must show the cross-tenant
  denial describe block as `passed`, NOT `skipped`. If CI cannot inject the
  vars, the integration suite runs as a pre-merge operator step against a
  dev Supabase project (synthesized founder fixtures) and the AC line below
  records the run-evidence (test output excerpt with green per-describe
  status).
- **6.3** — `bun run build` clean.
- **6.4** — `bash apps/web-platform/scripts/service-role-allowlist-gate.sh`
  shows new shrunk allowlist.
- **6.5** — `bash apps/web-platform/test/ci/service-role-allowlist-gate.test.sh`
  3/3 green/red/allowlisted.
- **6.6** — Multi-agent review (`/soleur:review` or equivalent invocation):
  `security-sentinel`, `user-impact-reviewer`, `architecture-strategist`,
  `data-integrity-guardian`, `semgrep-sast`, `code-quality-analyst`,
  `pattern-recognition-specialist`, `code-simplicity-reviewer`. All P1 + P2
  fixed inline per `rf-review-finding-default-fix-inline`.
- **6.7** — PR body documents the artifact + vector matrix (copy template
  from PR-B #3395 body). PR uses `Ref #3244, Closes #3392 (cc-dispatcher
  BYOK item only)` in body, NOT title.

## Files to Edit

- `apps/web-platform/server/ws-handler.ts` (13 tenant sites; auth.getUser at :1812 preserved; Phase 2.10)
- `apps/web-platform/server/conversations-tools.ts` (4 sites; Phase 2.9)
- `apps/web-platform/server/session-sync.ts` (4 sites; Phase 2.1)
- `apps/web-platform/server/api-messages.ts` (2 tenant sites; auth.getUser at :36 preserved; Phase 2.2)
- `apps/web-platform/server/api-usage.ts` (1 site migrates; sum_user_mtd_cost RPC at :104 stays; Phase 2.3)
- `apps/web-platform/server/conversation-writer.ts` (1 site; Phase 2.4)
- `apps/web-platform/server/lookup-conversation-for-path.ts` (1 site; Phase 2.5)
- `apps/web-platform/server/current-repo-url.ts` (1 site; Phase 2.6)
- `apps/web-platform/server/kb-document-resolver.ts` (1 site; Phase 2.7)
- `apps/web-platform/server/kb-route-helpers.ts` (2 sites; Phase 2.8)
- `apps/web-platform/server/cc-dispatcher.ts` (BYOK lease wrap + 2 messages writes; :1395 attachments injection retained; Phase 2.11)
- `apps/web-platform/.service-role-allowlist` (Phase 4 — remove 7, convert 2 to PERMANENT, retain 2 with new rationales)
- `apps/web-platform/test/server/ws-handler.tenant-isolation.test.ts` (NEW; cross-tenant denial on migrated sites only — `auth.getUser` path is unchanged)
- `apps/web-platform/test/server/conversations-tools.tenant-isolation.test.ts` (NEW)
- `apps/web-platform/test/server/session-sync.tenant-isolation.test.ts` (NEW)
- `apps/web-platform/test/server/api-messages.tenant-isolation.test.ts` (NEW; covers migrated SELECTs only — `auth.getUser` path is unchanged)
- `apps/web-platform/test/server/conversation-writer.tenant-isolation.test.ts` (NEW)
- `apps/web-platform/test/server/lookup-conversation-for-path.tenant-isolation.test.ts` (NEW)
- `apps/web-platform/test/server/kb-route-helpers.tenant-isolation.test.ts` (NEW)
- `apps/web-platform/test/server/cc-dispatcher.tenant-isolation.test.ts` (NEW; covers BYOK lease + 2 message writes; `:1395` attachments path is unchanged)
- `knowledge-base/project/specs/feat-agent-runtime-platform/tasks.md` (Phase 5)

## Files to Create

- 8 new tenant-isolation test files per above
- (Phase 1 helper REMOVED; Phase 3 audit-doc REMOVED — both filed as tracked deferrals.)

## Open Code-Review Overlap

Plan-time check: `gh issue list --label code-review --state open --json
number,title,body --limit 200 > /tmp/open-review-issues.json`; for each
file in the migration set, `jq -r --arg path "<path>" '...'` over the body.

**Decision per overlap:** none currently flagged against the 11 files in
scope. Re-run at /work Phase 0.0 (work skill's standard pre-edit step) in
case new code-review issues land between plan write-time and work-start.

If any overlap surfaces at /work-time, default disposition: **fold in**
if the scope-out concerns a tenant-isolation regression on a file in our
edit list (single-user-incident class — never defer); otherwise
**acknowledge** with 1-sentence rationale.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] `bun run typecheck` clean.
- [ ] `bun run test` green; new cross-tenant denial tests pass.
- [ ] `bun run build` clean.
- [ ] `bash apps/web-platform/scripts/service-role-allowlist-gate.sh`
  returns shrunk allowlist (every PR-C-migrated file removed, except the
  two retained-with-rationale: `api-usage.ts`, `cc-dispatcher.ts`).
- [ ] `bash apps/web-platform/test/ci/service-role-allowlist-gate.test.sh`
  3/3 green.
- [ ] Tenant migration grep (fully-migrated files — zero `createServiceClient`):

  ```bash
  grep -nE 'createServiceClient|getServiceClient' \
    apps/web-platform/server/{conversations-tools,session-sync,conversation-writer,lookup-conversation-for-path,current-repo-url,kb-document-resolver,kb-route-helpers}.ts
  ```

  Returns **zero** matches.

- [ ] Auth-bootstrap-retained grep (exactly 1 import + 1 use each):

  ```bash
  # ws-handler.ts: import line for createServiceClient + the auth.getUser
  # call site at ~:1812. Body of file has no other service-role uses.
  grep -nE 'createServiceClient|getServiceClient|supabase\.auth\.getUser' \
    apps/web-platform/server/ws-handler.ts
  ```

  Pattern: 1 import, the lazy-init proxy (`:79`), and ≥1 `auth.getUser`
  call. No `supabase.from(` matches except via tenant client (auditor reads
  diff to confirm). Same shape for `api-messages.ts`.

- [ ] Service-role retention sites (`api-usage.ts` RPC + `cc-dispatcher.ts`
  attachments):

  ```bash
  grep -nE 'createServiceClient' apps/web-platform/server/api-usage.ts
  grep -nE 'createServiceClient' apps/web-platform/server/cc-dispatcher.ts
  ```

  `api-usage.ts`: 1 match (RPC call site with `// SERVICE-ROLE: RPC revoked
  from authenticated — see migration 027` comment).
  `cc-dispatcher.ts`: 1 match (attachments injection at `:1395` with
  `// SERVICE-ROLE: attachments-storage RLS — see #PR-D` comment).

- [ ] BYOK lease wrap on cc-dispatcher:

  ```bash
  grep -nE 'runWithByokLease' apps/web-platform/server/cc-dispatcher.ts
  ```

  Returns ≥ 1 match (the `realSdkQueryFactory` wrap).

- [ ] Cross-tenant denial integration suite ran with
  `TENANT_INTEGRATION_TEST=1` set; output shows each `describe` block as
  `passed` (NOT `skipped`). Run-evidence pasted in PR body or linked from a
  CI run URL. Critical: a "skipped" status reproduces the 2026-05-06
  vitest-blind trap.

- [ ] Per-file commit history: 11 migration commits + 1 allowlist-shrink +
  1 tasks.md = 13 commits, each reviewable individually.

- [ ] PR body contains the artifact + vector matrix (copy from PR-B body).

- [ ] PR body uses `Ref #3244, Closes #3392 (cc-dispatcher BYOK item only)`
  — NOT in title.

- [ ] Multi-agent review: 8 agents, all P1 + P2 fixed inline.

- [ ] CPO sign-off acknowledged in PR body (per
  `requires_cpo_signoff: true` frontmatter); brainstorm CPO carry-forward
  is the signal.

### Post-merge (operator)

- [ ] Article 30 register update WITHIN 7 CALENDAR DAYS of merge (CLO
  advisory): extend PA1/PA2 TOM row in
  `knowledge-base/legal/article-30-register.md` (or equivalent) to note
  the expanded tenant-JWT surface (ws-handler, session-sync, api-*,
  conversation-writer, lookup-*, current-repo-url, kb-*, cc-dispatcher
  BYOK) AND name the layered controls (tenant JWT + RLS + auth-probe +
  service-role allowlist gate + lease scope + CODEOWNERS pin +
  cross-tenant denial integration tests) so the row reflects
  defense-in-depth, not RLS alone. Automation: single markdown edit; ship
  phase can prompt the operator to run a 1-line `sed`-style edit if the
  canonical file exists. Otherwise filed as deferred task with the 7-day
  SLA recorded.
- [ ] Close `tasks.md §1.5` and §2.1 checkboxes on `main` after merge
  (already done in PR; this is the merge-verification step).
- [ ] Verify post-merge that prod-deployed bundle has the tenant-JWT
  surface live: `curl -s https://app.soleur.ai/api/health | jq` (per
  `2026-04-28-anon-key-test-fixture-leaked-into-prod-build`).

## Test Strategy

- **Unit + mock-layer tests** — one per migrated file, asserting the
  `getFreshTenantClient(userId)` call shape, auth probe firing, and
  per-table query shape. Mocks routed via Phase 1's shared
  `runtime-mocks.ts` helper.
- **Cross-tenant denial integration tests** — vitest with
  `TENANT_INTEGRATION_TEST=1`. One per (file, table, op) tuple exercised
  by user-routable code. Synthesized founder fixtures (per
  `cq-test-fixtures-synthesized-only`); JWT fixtures decode-verified, NOT
  source-grep'd (per `2026-04-29-jwt-fixture-reminting-decode-verify`).
- **LLM out of assertion path** — N/A; no LLM-mediated tools in scope (per
  `2026-04-19-llm-sdk-security-tests-need-deterministic-invocation`).
- **No new test framework dependencies** — vitest already in `package.json`;
  cross-tenant denial tests reuse the
  `apps/web-platform/test/server/agent-runner.tenant-isolation.test.ts`
  fixtures + helpers from PR-B.

## Tracked Deferrals

Each filed as a `gh issue` at Phase 6 wrap-up (after labels are verified
via `gh label list`):

- **Extract `test/helpers/runtime-mocks.ts` and retrofit all 27 callers**
  — 19 existing PR-B mock-using files + 8 new PR-C mock-using files. The
  helper lands once and propagates to all callers in a single dedicated
  cleanup PR (Phase 1 was REMOVED from PR-C for YAGNI reasons; see review
  history). Label: `domain/engineering`, `priority/p3-low`. Re-evaluation:
  after PR-C lands.
- **App/api SSR sample audit (5 routes)** — coverage-driven sample:
  `app/api/conversations/route.ts`, `app/api/keys/route.ts`,
  `app/api/kb/upload/route.ts`, `app/api/team-names/route.ts`,
  `app/api/account/export/route.ts`. Verify each uses
  `createServerClient` (SSR cookie-anon-key) for user-scoped reads.
  Doc-only output: `knowledge-base/project/specs/feat-runtime-slice-3244/app-api-audit.md`.
  Label: `domain/engineering`, `priority/p2-medium`. Per-route follow-ups
  filed as additional issues if a route holds service-role usage. (Phase 3
  REMOVED from PR-C; FR6 is satisfied by this deferred issue.)
- **Service-tokens BYOK lease coverage** — `getUserServiceTokens` plaintext
  residency is bounded by `realSdkQueryFactory` scope after Phase 2.11,
  but `runWithByokLease` is API-key-only by design. If future scope wants
  service-tokens equivalent, it needs its own brainstorm. Re-evaluation:
  before 2nd hosted founder.
- **PR-D scope** — `audit_byok_use` writer, `is_jti_denied` consumer.
  Per brainstorm; not blocked by PR-C. CLO advisory: sequence PR-D's
  audit-writer BEFORE 2nd hosted founder or GA exposure (Art. 5(2)
  accountability).
- **Attachments-storage tenant RLS** — `cc-dispatcher.ts:1395` injects
  service-role into `persistAndDownloadAttachments`. Attachments tables
  need an RLS audit before this site can migrate. Re-evaluation: PR-D.
- **`api-usage.ts` allowlist line-level granularity** — already on PR-B's
  tracked deferrals list (line-level vs file-level allowlist). PR-C does
  not advance this. Cross-referenced; do NOT re-file.

## Risks

- **R1 — Stale spec line numbers mid-implementation.** Mitigation: Phase
  0.1 re-runs the enumeration at work-time HEAD and halts on count
  divergence. The Research Reconciliation table is the canonical input,
  NOT the spec.
- **R2 — Hidden `.rpc(...)` site discovered at /work.** Mitigation: Phase
  0.1 grep includes `.rpc(`. If a new RPC surfaces, classify it against
  migrations before migrating the file (apply the PR-B learning verbatim).
- **R3 — `sum_user_mtd_cost` GRANT changed in a future migration.**
  Mitigation: Phase 0.3 cites `apps/web-platform/supabase/migrations/027_mtd_cost_aggregate.sql:68`
  (`REVOKE EXECUTE … FROM authenticated`) and
  `029_plan_tier_and_concurrency_slots.sql:91-92` (`slots_owner_read` SELECT
  policy) exactly. Migration range present at plan time: 001-041. If any
  new migration (042+) lands between plan write-time and merge-time, re-run
  the `grep -rnE 'REVOKE\s+EXECUTE.*FROM\s+authenticated|slots_owner_read'
  apps/web-platform/supabase/migrations/` query and reconcile.
- **R4 — Test mock helper introduces hoisting failures.** Mitigation:
  Phase 1.3 sanity test + Phase 6.1/6.2 must pass on a clean run BEFORE
  any consumer test in Phase 2 is added.
- **R5 — Cross-tenant denial test flakiness against Supabase test DB.**
  Mitigation: use the synthesized fixture path PR-B established (NOT real
  network); RLS denial returns zero rows, so `expect(rows).toEqual([])`
  is the deterministic assertion shape.
- **R6 — Auth probe adds latency.** Per-entry-function (NOT per-query)
  amortizes the cost to one `maybeSingle()` per session-affecting handler
  call. Expected p50 < 5 ms (existing `precheck_jwt_mint` instrumentation
  in PR-B observed p50 = 2-4 ms).
- **R7 — `cc-dispatcher` lease wrap reshapes the dispatch entry point.**
  The `realSdkQueryFactory` body becomes `runWithByokLease(args.userId,
  async (lease) => { ... })`. The closure indentation chore from PR-B's
  deferrals applies here too — Phase 2.11 may surface a whitespace-only
  follow-up commit. Acceptable; do NOT bundle into PR-C.

## Sharp Edges

- **A plan whose `## User-Brand Impact` section is empty, contains only
  `TBD`/`TODO`/placeholder text, or omits the threshold will fail
  `deepen-plan` Phase 4.6.** Threshold is set above (`single-user
  incident`); section is populated.
- **`cc-dispatcher.ts:878–879` is NOT spec's `:426`.** Plan operates on the
  fresh enumeration in Phase 0.3.
- **`ws-handler.ts` site count is 13, not 10.** Same.
- **`sum_user_mtd_cost` is the only `.rpc(...)` in scope. Its GRANT status
  is the load-bearing precondition. Do NOT migrate it.** Phase 0.3 row
  documents this explicitly; comment + allowlist retention.
- **Per-file commits over single squash for /work — but the PR itself is
  one PR with one merge.** Per-file means the diff stays per-site
  reviewable; the PR squash-merge bundles them.
- **Article 30 register update is post-merge, NOT pre-merge.** Per CLO
  assessment, internal hardening does not require pre-merge legal
  artifact landing; the register update is operational documentation that
  the merged shape now covers an expanded surface.
- **Auth probe is per-entry-function, NOT per-query.** Adding a probe
  before every `client.from(...)` call would 2-3x query count per handler.
  One probe at the top of the handler suffices because the probe
  proves the JWT is valid for `auth.uid() = userId`; all subsequent reads
  inherit that proof until the handler returns.
- **`user_concurrency_slots` writes go through SECURITY DEFINER RPCs
  (migration 029:108+).** Direct INSERT/UPDATE/DELETE on this table under
  tenant JWT would fail (no policy). If a future site needs a direct
  write, route via the existing `acquire_conversation_slot` /
  `release_conversation_slot` RPCs. Phase 0.3 confirms all 3 ws-handler
  sites are SELECTs — no direct write changes needed in PR-C.
- **Foundations-PR contract caveat does NOT apply.** PR-C does not declare
  any downstream contract that PR-D consumes; both PRs touch independent
  surfaces (PR-C: tenant migration. PR-D: audit-writer + is_jti_denied).
- **Aggregate target consistency** — Phase 0.3 totals: 34 tenant-migration
  sites (33 migrate, 1 stays service-role for the REVOKED RPC) PLUS 3
  PERMANENT auth/attachments sites (ws-handler:1812, api-messages:36,
  cc-dispatcher:1395) that the spec under-classified. Allowlist post-PR-C:
  7 files REMOVED (fully migrated), 2 files CONVERTED to PERMANENT (auth
  bootstrap on ws-handler + api-messages), 2 files RETAINED with updated
  rationales (api-usage RPC, cc-dispatcher attachments). Re-derive from
  the table at /work-start; do NOT trust paraphrased counts.
- **Auth-handshake surfaces are PERMANENT, not TRANSITIONAL.** The AC
  grep MUST scope to files whose ENTIRE service-role footprint is
  expected to migrate. `ws-handler.ts` and `api-messages.ts` keep their
  `createServiceClient` import for the `auth.getUser(token)` call — that
  call validates the operator's token BEFORE userId exists, so a tenant
  JWT is structurally impossible there. The AC grep above scopes to the
  7 fully-migrated files only.
- **Test integration gating is load-bearing for the brand-survival
  threshold.** `TENANT_INTEGRATION_TEST=1` MUST be set in the pre-merge
  test runner (CI or operator-run) — otherwise `describe.skipIf` causes
  the cross-tenant denial tests to silently skip, reproducing the
  2026-05-06 vitest-blind trap the plan explicitly cites. AC verification
  requires the test output to show `passed` (not `skipped`) on each
  `tenant-isolation.test.ts` describe block.

## References

- Umbrella spec: `knowledge-base/project/specs/feat-agent-runtime-platform/spec.md`
- Umbrella tasks: `knowledge-base/project/specs/feat-agent-runtime-platform/tasks.md`
- This spec: `knowledge-base/project/specs/feat-runtime-slice-3244/spec.md`
- Brainstorm: `knowledge-base/project/brainstorms/2026-05-15-pr-c-sibling-query-migration-brainstorm.md`
- PR-A: #3240 (merged)
- PR-B: #3395 (merged) — playbook template
- Open deferrals: #3392
- Load-bearing learnings:
  - `knowledge-base/project/learnings/2026-05-06-tenant-jwt-rpc-grant-mismatch-vitest-blind.md`
  - `knowledge-base/project/learnings/2026-04-12-silent-rls-failures-in-team-names.md`
  - `knowledge-base/project/learnings/2026-04-29-jwt-fixture-reminting-decode-verify.md`
  - `knowledge-base/project/learnings/2026-05-14-plan-prescribed-runtime-shapes-must-be-grepped-against-installed-version.md`
- AGENTS.md gates: `hr-weigh-every-decision-against-target-user-impact`,
  `hr-write-boundary-sentinel-sweep-all-write-sites`,
  `wg-use-closes-n-in-pr-body-not-title-to`,
  `cq-test-fixtures-synthesized-only`,
  `cq-silent-fallback-must-mirror-to-sentry`,
  `rf-review-finding-default-fix-inline`.
