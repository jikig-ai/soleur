---
title: PR-C — Sibling-query migration (#3244 §2)
date: 2026-05-15
status: ready-for-plan
umbrella_issue: 3244
predecessor_prs: [3240, 3395]
brand_survival_threshold: single-user incident
lane: cross-domain
---

# PR-C — Sibling-query migration (#3244 §2)

## What We're Building

Extend gate-zero (PR-B #3395) outward from `agent-runner.ts` to the rest of the
server-side surface. Migrate ~30 service-role Supabase call sites in
`apps/web-platform/server/` from `createServiceClient()` to
`getFreshTenantClient(userId)` (or the SSR cookie-anon-key path for `app/api`
routes), wrap BYOK plaintext-fetching paths in `runWithByokLease`, and shrink
`.service-role-allowlist` to permanent entries only (bulk sweeps + the one
signature-verified Stripe webhook).

Concretely (per umbrella `tasks.md §2.1`):
- `server/ws-handler.ts` (10 sites): `:294, :432, :452, :754, :767, :812, :896, :1116, :1410`
- `server/conversations-tools.ts` (4 sites): `:150, :211, :248, :291`
- `server/session-sync.ts` (4 sites): `:187, :236, :254, :270`
- `server/api-messages.ts`, `api-usage.ts`, `conversation-writer.ts`, `lookup-conversation-for-path.ts`, `current-repo-url.ts`, `kb-document-resolver.ts`, `kb-route-helpers.ts` (10 total)
- `cc-dispatcher.ts:426` — `getUserApiKey` → `lease.getApiKey()` (closes
  #3392's "two parallel BYOK fetch surfaces" hazard)
- Sample-audit 5 `app/api/**/route.ts` files for SSR cookie-anon-key client (NOT service-role)

## Why This Approach

Premise verification at brainstorm time (Phase 1.1 grep + `gh pr list`):

- **PR-B #3395 merged 2026-05-06.** Gate-zero done in `agent-runner.ts`:
  9 user-scoped sites on `getFreshTenantClient(userId)`,
  `startAgentSession` body wrapped in `runWithByokLease`, CI grep gate
  enforcing `.service-role-allowlist`, CODEOWNERS pinned.
- **#1044 multi-turn CLOSED 2026-03-27.** The umbrella brainstorm's "fix
  multi-turn before background triggers" slot is already filled.
- **`tasks.md` on `main` is stale** — §1.5–§1.8 still unchecked even though
  PR-B body marks them done. Action item: PR-C should close out the §1.5
  checkboxes as part of housekeeping.
- **Inngest = zero prior art** in `knowledge-base/project/learnings/`.
  Treat the Daily Priorities + Inngest slice as research-heavy and best done
  after PR-C closes the JWT/BYOK contract that any Inngest-triggered runs will
  reuse.

PR-C is the same playbook as PR-B applied outward. No new architecture, no new
tables, no new sub-processor. Lower review-cost-per-site than the next phase
(audit-writer + dashboard + Inngest) and the only path that retires
**TRANSITIONAL** entries from the allowlist.

## Key Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Scope: PR-C only, or PR-C + PR-D bundle? | **PR-C only.** | YAGNI. PR-D wires the `audit_byok_use` writer + a new dashboard route — different review surface (security + DDD + UX), different blast radius. Bundling re-creates the YAGNI-violation that PR-B's review extracted. |
| RPC site handling | Enumerate every `.rpc(...)` call in the 30 sites. For each, check the corresponding migration for `REVOKE EXECUTE FROM authenticated`. If revoked, **keep service-role** with a `// SERVICE-ROLE: RPC revoked from authenticated — see migration NNN` comment + allowlist entry. | Direct application of `2026-05-06-tenant-jwt-rpc-grant-mismatch-vitest-blind.md`. PR-B reverted two RPCs (`migrate_api_key_to_v2`, `increment_conversation_cost`) for exactly this reason; vitest mocks the whole chain so the GRANT mismatch is invisible until prod. |
| Auth probe per migrated site | Insert `await tenant.from('users').select('id').eq('id', userId).maybeSingle()` (or the existing helper) before the first migrated query in each site, per `2026-04-12-silent-rls-failures-in-team-names`. | RLS silent-failure trap: a misconfigured policy returns zero rows, not an error. Auth probe forces a known-good baseline. |
| `cc-dispatcher.ts:426` BYOK migration | Include in PR-C. Wrap the dispatch entry point in `runWithByokLease` mirroring `startAgentSession`. | Closes #3392's "two parallel BYOK fetch surfaces" hazard. Same blast radius as the ws-handler migrations; same review window. |
| Timer pair + WorkflowEnd union (§1.5.5) | **Defer to its own PR.** | Per PR-B's deferral note: re-introduce the 8-variant union, the `_exhaustive: never` rail, the runner consumer, and the tests in the same PR. Bundling with PR-C re-creates the YAGNI mistake. |
| `/proc` env-leak test (§1.5.7) | **Defer until second hosted founder.** | Kernel-level mitigation (`PR_SET_DUMPABLE=0` + bubblewrap) is already in place. Risk currently LOW (single-host, controlled UID). Re-evaluation trigger: before 2nd hosted founder. |
| `is_jti_denied` runtime consumer | **Defer to PR-D bundle.** | The consumer is a 30-line cache-throttled check; ships cleanly with the audit-log writer in PR-D so admin revocation paths and audit-row production land together. |
| Daily Priorities surface | **Defer to its own brainstorm.** | CPO assessment: Daily Priorities is NOT the right v1 dashboard. A read-only "what changed across your domains today" digest validates trust on visibility before the priorities arbitration step. New brainstorm needed once PR-C lands. |
| Inngest adoption | **Defer to its own ADR + brainstorm.** | CLO: Inngest as sub-processor blocks first founder beta until DPA + sub-processor disclosure update + DPD + Article 30 PA-new row + DPF/SCC M2 transfer mechanism land. Material legal work; needs its own brainstorm and ADR per `/soleur:architecture create`. Zero prior art in learnings. |

## Open Questions

- **PR-C blast radius.** ~30 sites across 11 files. The PR-B `runWithByokLease`
  closure indentation chore (#3392) recommends a `git diff -w` whitespace-only
  follow-up commit. For PR-C, prefer per-file commits so the diff stays
  per-site reviewable.
- **`app/api/**/route.ts` audit scope.** Plan says "sample-audit 5 random
  routes." Question for plan phase: should the audit be deterministic
  (alphabetical first 5) or coverage-driven (the 5 routes most likely to be
  agent-callable)? The latter is higher-signal but harder to mechanize.
- **Test mock DRY (#3392).** PR-B added `vi.mock("@/lib/supabase/tenant", ...)`
  to 13 sibling test files. PR-C will add more. Worth extracting a shared
  `test/helpers/runtime-mocks.ts` module — vitest hoisting permits
  `vi.mock(specifier, () => sharedFactory(deps))` where the factory closes over
  module-level imports. Decide at plan phase: bundle the refactor with PR-C, or
  leave to a follow-up chore PR.

## User-Brand Impact

Threshold: **single-user incident.** Carry-forward from PR-B (#3395 body
matrix). PR-C extends the same protection surface outward.

Artifact + vector matrix (audited at plan phase by `user-impact-reviewer`):

| Artifact | Vector | Mitigation in PR-C |
|----------|--------|---------------------|
| `messages.content` | Cross-conversation FK-spoof read via ws-handler | RLS via FK-join to `conversations.user_id`; new integration test asserts denial. |
| `conversations.*` writes | Cross-tenant UPDATE via missing `WITH CHECK` | `USING` governs both read and write; cross-founder UPDATE + service-role re-read regression test. |
| `team_names.custom_name` | Cross-tenant route-leak via session-sync | Tenant-client read; regression test. |
| `users.workspace_path / repo_status / github_installation_id` | Cross-founder probe at session-sync start | `auth.uid() = id` policy; regression test. |
| BYOK plaintext on dispatcher path | `cc-dispatcher.ts:426` returns plaintext string into V8 heap with no lease | `runWithByokLease` wrap; zeroize-on-finally. |
| CI gate self-defeat | Attacker-modeled PR adds new TRANSITIONAL entry to allowlist | CODEOWNERS pin already in place from PR-B; PR-C only removes entries (never adds). Document removal commits as security-owner-required. |

## Domain Assessments

**Assessed:** Engineering, Product, Legal. (Marketing, Operations, Sales,
Finance, Support: not relevant — internal hardening, no user-visible surface
change, no commercial terms touched.)

### Engineering (CTO)

**Summary:** PR-B is 100% done (CTO's initial reading of `tasks.md` was based
on a stale snapshot — PR #3395 merged 2026-05-06). Next slice is PR-C: the
sibling-query migration that closes out the transitional service-role
allowlist. Same playbook as PR-B; primary risk is RPC GRANT mismatch (caught
once already in PR-B — apply the learning by enumerating every `.rpc(...)` site
upfront).

### Product (CPO)

**Summary:** Daily Priorities is NOT the right v1 surface. A read-only digest
of "what changed today" validates trust on visibility before priorities
arbitration ships. PR-C is invisible to the founder — that's a feature, not a
bug, given the brand-survival threshold. Defer Daily Priorities to its own
brainstorm post-PR-C.

### Legal (CLO)

**Summary:** PR-C is **internal hardening of existing processing.** No new DPA
prerequisite, no new sub-processor, no public Privacy Policy delta. Article 30
register update needed: extend the existing PA1/PA2 TOM row to note the
expanded tenant-JWT surface (now covers ws-handler, session-sync, etc.). The
load-bearing audit-log artifact stays paper-only until PR-D wires the
`audit_byok_use` writer — flag for next slice, not blocker for this one.

## Capability Gaps

None blocking for PR-C. Inferred from:

- **Repo grep** (`apps/web-platform/server/agent-runner.ts:188,280,421,548,883,2275`):
  `getFreshTenantClient` confirmed wired and consumed.
- **Repo grep** (`apps/web-platform/lib/supabase/tenant.ts:124,195,236`):
  `mintFounderJwt`, `createTenantClient`, `getFreshTenantClient` confirmed
  present.
- **Repo grep** (`apps/web-platform/server/byok-lease.ts:154`): `runWithByokLease`
  confirmed present.
- **Migration grep** (`supabase/migrations/037_audit_byok_use.sql`):
  `audit_byok_use` + `denied_jti` + `precheck_jwt_mint` tables and RPCs confirmed
  present.

Gaps tracked for **future** slices (NOT PR-C):

- `audit_byok_use` writer — PR-D.
- `is_jti_denied` runtime consumer — PR-D bundle.
- Timer pair + WorkflowEnd 8-variant union with runner consumer — its own PR.
- Inngest agent kit + first background trigger — needs ADR + its own brainstorm
  + CLO sub-processor work.
- Trust-tier policy engine — needs its own brainstorm.
- Daily Priorities surface — needs its own product brainstorm.

## Load-bearing Learnings to Apply

- `knowledge-base/project/learnings/2026-05-06-tenant-jwt-rpc-grant-mismatch-vitest-blind.md`
  — enumerate every `.rpc(...)` site upfront; check migration grants vs JWT
  role; flag any revoked RPC for keep-service-role with allowlist entry.
- `knowledge-base/project/learnings/2026-04-12-silent-rls-failures-in-team-names.md`
  — auth probe before first migrated query per site.
- `knowledge-base/project/learnings/2026-04-29-jwt-fixture-reminting-decode-verify.md`
  — any new test JWT fixtures must use synthesized project refs and be
  decode-verified, not source-grep'd.
- `knowledge-base/project/learnings/2026-05-13-claude-agent-sdk-canusetool-not-invoked-for-unknown-mcp-tools.md`
  — only relevant if PR-C wires any new MCP tools (it should not).
- `knowledge-base/project/learnings/2026-05-14-plan-prescribed-runtime-shapes-must-be-grepped-against-installed-version.md`
  — verify Claude Agent SDK shapes against the installed version before
  prescribing in plan.
