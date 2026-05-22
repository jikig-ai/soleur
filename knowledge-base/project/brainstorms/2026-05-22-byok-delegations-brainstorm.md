---
date: 2026-05-22
status: committed
decision: ship-table-resolver-cap-and-ui-in-two-prs
brand_survival_threshold: single-user incident
lane: cross-domain
supersedes: []
related:
  - knowledge-base/project/brainstorms/2026-05-21-team-workspace-multi-user-brainstorm.md
  - knowledge-base/project/brainstorms/2026-04-10-byok-cost-tracking-brainstorm.md
  - knowledge-base/project/brainstorms/2026-04-17-restore-byok-usage-dashboard-brainstorm.md
  - knowledge-base/legal/compliance-posture.md
closes_issues:
  - 4232
---

# BYOK Delegations Brainstorm — Owner-Funded BYOK with Per-Grantee Opt-In

## What We're Building

A `byok_delegations` primitive that lets a workspace owner (Jean) grant a member (Harry, intern) permission to invoke the Anthropic API using the owner's BYOK key. Each invocation tags the actual caller's `user_id` in `audit_byok_use`; cost debits the owner's ledger by default. A USD/day cap on the delegation row is enforced at write-time, and revocation is instant + auditable.

The schema split shipped in PR #4225 (`apps/web-platform/server/byok-lease.ts` accepts `keyOwnerUserId ≠ workspaceContextUserId`) was designed for exactly this feature; the lease's `MissingByokKeyError` ADR comment at `byok-lease.ts:101-112` already cites #4232 by issue number as "the future opt-in remediation. NEVER falls back to another user's key." This brainstorm flips that invariant from "never" to "only with an active, unexpired, unrevoked, under-cap delegation row."

## Why Now (Re-Evaluation Criterion Fired)

Issue #4232's deferral criteria: *"When the first request to fund a workspace member's runs lands, OR when external small-team customers ask for shared-billing."* The first criterion fired today: Harry started as intern at jikigai; Jean wants to fund Harry's agentic runs because Harry has no AI budget. No external customer ask yet.

This is dogfood-driven, not market-driven. Scope stays internal-flag-gated; pricing/marketing surfaces unchanged (consistent with #4225's flag-OFF posture).

## User-Brand Impact

`USER_BRAND_CRITICAL=true` — operator selected all three failure modes in Phase 0.1 framing.

**Artifact at risk:** Jean's Anthropic API key (plaintext at decryption boundary), Jean's billing ledger (Anthropic invoice), Harry's prompt content (now joint-controlled by Jean), and the cross-tenant boundary on `byok_delegations` itself.

**Vectors named:**

1. **Grantor billing surprise** — revoked or expired delegation still charges Jean's key for in-flight tokens; OR a runaway agent loop on Harry's account bills Jean unboundedly before he can manually revoke. **Mitigations:** USD/day cap enforced at write-time on every `record_byok_use_and_check_cap` call; 60s grace window after revoke, then in-flight tokens debit the caller (Harry) not the grantor.
2. **Credential leak via Harry's process** — Harry's runtime should never read Jean's plaintext key. **Mitigation:** ALS-scoped lease + HKDF decrypt (mig 037-061 already established) is preserved; delegation only changes *which* `api_keys` row to lease, not how the plaintext is handled. The Anthropic subprocess `ANTHROPIC_API_KEY` env exposure is bounded by the existing PR-B #3244 §1.5 defenses (kernel `prctl(PR_SET_DUMPABLE, 0)` + bubblewrap `--proc/--tmpfs`).
3. **Cross-tenant grant bug** — a member of OrgA grants themselves use of a key owned by a user in OrgB. **Mitigations:** workspace-scoped grants (not org-scoped), RLS `WITH CHECK` enforces `grantor_user_id = auth.uid() AND is_workspace_member(workspace_id, grantee_user_id)`, plus a DB-level `CHECK (grantor_user_id <> grantee_user_id)`. CLO Art. 33 note: cross-tenant grant is unauthorized disclosure of grantee's prompt content → 72h breach clock; Sentry alert on any `same_workspace` constraint violation (silent fallback would mask the breach).

**Threshold:** `single-user incident` — one cross-tenant grant row that lets a stranger lease Jean's $X/day Anthropic budget IS brand-survival territory.

## Domain Assessments

**Assessed:** Product (CPO), Engineering (CTO), Legal (CLO). Marketing/Sales/Ops/Support/Finance not spawned (no public surface, no positioning change, no per-seat vendor trigger, no marketing/sales asset created).

### Product (CPO)

**Summary:** The split in PR #4225 makes the build small; the product question is "what's the smallest grant model that survives the three named vectors without becoming a billing/credential incident." Per-workspace member-row grant surface is structurally safer than a global settings tab. USD/day cap is load-bearing v1 — it's the only failure mode a manual revoke can't catch in real time. Out-of-band reimbursement was considered and rejected: Harry doesn't have upfront capital, and the brand promise is "agentic work without budget friction for the team." Bidirectional cost visibility (Jean sees per-grantee spend, Harry sees a persistent "running on Jean's key — $Y of $CAP today" banner) is mandatory v1.

### Engineering (CTO)

**Summary:** Resolver-and-table change, not architecture change. SQL resolver (plpgsql SECURITY DEFINER, `search_path = public, pg_temp`) chosen over TS resolver — atomic read against the same MVCC snapshot as the revoke write eliminates TOCTOU between "resolver picks grantor" and "grantor's revoke commits." `byok_delegations` table follows the **scope_grants (048) WORM pattern**: structural-diff trigger allows only the `revoked_at NULL → non-NULL` UPDATE shape + Art. 17 anonymise shape; no other mutations. `audit_byok_use` gains `delegation_id uuid NULL REFERENCES byok_delegations(id)` to distinguish self-funded from delegated rows. Revocation race resolved via 60s grace then reject-at-write debiting the grantee. Five `runWithByokLease` call sites in prod must add the resolver wrapper (`cc-dispatcher.ts:890`, `agent-runner.ts:882`, `agent-runner.ts:2401`, `cfo-on-payment-failed.ts:199`, `github-on-event.ts:208`) — **sentinel sweep load-bearing**. ADR recommended (new cross-user authorization primitive).

### Legal (CLO)

**Summary:** Existing ToS 2.2.0 + AUP §5.5 + workspace-member Side Letter framework does NOT cover the specific delegation act (Harry's prompts processed under Jean's credential with cost attribution). Required scaffolding: (a) **Delegation Consent Side Letter** (new, separate from workspace-member Side Letter) — Harry attests consent + acknowledgement Jean receives itemized usage telemetry; (b) **DPD §2.3 addendum** declaring joint controllership (Art. 26) between Jean and Harry for Harry's prompt content via delegation; Anthropic remains processor under Jean's existing DPA (no new sub-processor); (c) **AUP §5.6 clause** — owners granting delegations must hold current Side Letter and may not surveil grantee's prompt *content* (cost telemetry only, no prompt-body inspection conveyed); (d) **WORM grant/revoke ledger** — Art. 5(2) accountability + Art. 30 ROPA require immutable history (the 048 scope_grants WORM trigger pattern satisfies this); (e) **member-departure auto-revoke** transactionally on `workspace_members` removal, history retained 7 years; (f) **DSAR runbook update** to extract delegation history (Art. 15). **Art. 33 risk note:** cross-tenant grant is GDPR-reportable breach (unauthorized disclosure to another controller), not just internal incident; recommend DB-level `same_workspace` constraint + Sentry alert on violation.

## Capability Gaps

None new. Existing agents cover:

- **`legal-document-generator`** — drafts Delegation Consent Side Letter, DPD §2.3 addendum, AUP §5.6 clause (parallel-tracked with code PRs).
- **`legal-compliance-auditor`** — post-merge audit that scaffolding actually shipped.
- **`spec-flow-analyzer`** — for the 6-state failure-mode flow matrix CPO enumerated.
- **`ux-design-lead`** — for the member-row grant affordance + Jean's "Funded for others" pane + Harry's "Running on Jean's key" banner.
- **`security-sentinel`** + **`data-integrity-guardian`** — RLS + WORM trigger + sentinel-sweep review at PR time.
- **`gdpr-gate`** — fires on `byok_delegations` migration (regulated data surface, joint controllership).

## Key Decisions

| # | Decision | Choice | Rationale |
|---|----------|--------|-----------|
| 1 | Trigger | First re-eval criterion fired: Harry started; Jean funding intern runs. No external small-team ask yet. | Operator confirmed. Scope stays internal-flag-gated. |
| 2 | USD/day cap | **Column + enforcement v1.** Default $20/day for Harry, configurable per delegation. Cap-hit = blocking error with "ask Jean to raise cap" CTA. | CPO load-bearing: only mitigation for runaway-loop billing surprise that revoke can't catch in real time. |
| 3 | Precedence (grantee has own key + delegation) | **Grantee's own key wins by default.** Delegation is fallback when own key missing/invalid. | CPO principle of least surprise; Harry's key means Harry chose to pay. No `prefer_delegation` flag in v1 (defer until asked). |
| 4 | Revocation race | **60s grace; tokens after grace debit grantee.** Not the grantor. Lease resolver re-checks at `record_byok_use_and_check_cap` write time. | CTO billing-safety: grantor never pays for tokens after explicit revoke; caller absorbs as the party that triggered the call. Operator accepted Harry's possible ~60s overrun bill. |
| 5 | Stream abort | **No mid-token abort.** Block NEW leases, grace in-flight, reject-at-write. AbortController on ALS is leaky (Anthropic CLI subprocess doesn't honor it). | CTO: cost-recovery is more important than killing the stream; the grace + write-time reject covers the billing risk without breaking Harry's current turn. |
| 6 | Grant surface | **Per-workspace member detail row** ("Fund this member's runs" toggle + cap input + expiry). NOT a global settings tab. | CPO: structurally prevents cross-tenant grant bug (RLS `WITH CHECK` uses `is_workspace_member`); workspace-scoped grants match audit/cost predicate granularity. |
| 7 | Scope of grant | **Workspace-scoped, not org-scoped.** Jean→Harry in workspace-Q does NOT auto-extend to workspace-R. | CTO: org-scope forces new workspaces to inherit funding — dangerous default. Workspace match audit/cost predicate; cross-tenant blast-radius = one workspace. |
| 8 | Resolver placement | **SQL plpgsql function** `resolve_byok_key_owner(p_caller_user_id, p_workspace_context_user_id)`. Not a TS module. | CTO: atomic MVCC read vs revoke write eliminates TOCTOU. TS resolver would need a serialisable txn around resolver+lease+audit-write that doesn't exist. |
| 9 | Table mutation model | **Hybrid WORM (scope_grants 048 pattern).** Single table; structural-diff trigger allows only `revoked_at NULL→non-NULL` UPDATE shape + Art. 17 anonymise shape. | Research reconciliation: 048 IS the precedent. CLO's WORM requirement and CTO's soft-delete proposal are reconciled — `revoked_at` IS the WORM-permitted mutation. |
| 10 | `audit_byok_use.delegation_id` | **Add column** `delegation_id uuid NULL REFERENCES byok_delegations(id)`. NULL=self-funded, NOT NULL=delegated. | CTO: required to distinguish self-spend from funded-for-others in Jean's dashboard. Sentinel sweep target. |
| 11 | RLS predicates | INSERT: `grantor_user_id = auth.uid() AND is_workspace_member(workspace_id, grantee_user_id)`. SELECT: `grantor_user_id = auth.uid() OR grantee_user_id = auth.uid()`. UPDATE (revoke) via SECURITY DEFINER RPC only. | CTO + CLO: cross-tenant insert structurally impossible; both parties to a grant can see it. |
| 12 | Same-workspace constraint | **DB-level CHECK** that grantor + grantee both belong to `workspace_id` + Sentry alert on constraint violation. | CLO Art. 33: a constraint violation is a 72h breach trigger; silent fallback would mask. |
| 13 | Legal sequencing | **Parallel track** — Delegation Consent Side Letter + DPD §2.3 addendum + AUP §5.6 ship in PR-B's window via legal-document-generator. Flag flips ON when both PRs + signed Side Letter land. | Operator chose parallel over legal-first; CLO non-negotiable requirement preserved via flag-gate. |
| 14 | Packaging | **Two PRs (B).** PR-A (~3-4d): migration 062 + SQL resolver + 5 call-site updates + USD cap enforcement + CLI grant/revoke for dogfood. PR-B (~2-3d): UI surfaces + legal docs. Both behind `BYOK_DELEGATIONS_ENABLED` flag, OFF in prd. | Operator: reduces review surface; lets schema land + dogfood-test before UI polish. |
| 15 | Member-departure | **Transactional auto-revoke** on `workspace_members` removal (same statement). History retained 7y. | CLO: financial/audit retention; Art. 5(1)(e) satisfied via documented purpose. |
| 16 | ADR | **Required.** Cross-user authorization primitive (resolver-in-SQL-not-TS rationale + revocation-race billing decision). Run `/soleur:architecture create` before PR-A merges. | CTO. |
| 17 | Sentinel sweep | **Pre-merge gate.** All 5 `runWithByokLease` call sites + every reader of `audit_byok_use.founder_id` in dashboards. | `hr-write-boundary-sentinel-sweep-all-write-sites` + reconciliation that research found 5 sites, not the 2 CTO initially estimated. |
| 18 | Type widening | `ByokLeaseArgs` + `ByokLease` + `ByokLeaseError.cause` enum widen with `delegation_expired` / `delegation_revoked` / `delegation_cap_exceeded`. Grep all consumers of the three. | `hr-type-widening-cross-consumer-grep` + `cq-union-widening-grep-three-patterns`. `mapByokLeaseCauseToErrorCode` exhaustive switch at `byok-lease.ts:182-196` is the canonical sweep entry. |

## Non-Goals

- **Per-action ACLs** (e.g., "Harry can use my key for research but not deploys") — defer until second grantee exists.
- **Time-window grants** (auto-expire after N days from creation) — `expires_at` column ships but UI defaults to NULL (no expiry); manual revoke + daily cap sufficient for dogfood.
- **Multi-grantor delegations** (Harry funded by Jean AND a second founder) — defer; if it ever happens, pick first-active by `created_at`.
- **Out-of-band reimbursement** ("Harry brings own key, Jean Venmos monthly") — explicitly rejected; documented as considered-and-cut.
- **Mid-token stream abort** — decision #5; defer until billing-recovery proves insufficient.
- **`prefer_delegation` flag** on the table — defer until a real user asks for delegation-wins precedence.
- **Per-workspace dashboard for grantee** ("here's all your funders across workspaces") — defer; v1 banner per workspace is enough.
- **Multi-delegation aggregation** in cap accounting (cap = per-delegation, not per-grantor across all delegations) — defer; first overrun pattern.

## Open Questions

1. **`workspace_member_attestations` consent overlap.** The Delegation Consent Side Letter is separate, but its acceptance row needs storage. Plan-skill: new `byok_delegation_acceptances` table mirroring `tc_acceptances_ledger` shape, OR extend `workspace_member_attestations` with a `delegation_consent` jsonb column? CLO leans toward new table (different consent surface, different revocation semantics, different DSAR profile).
2. **Cached lease invalidation on revoke** (per learning `2026-04-18-cf-cache-purge-on-share-revoke`). The lease itself is ALS-scoped (per-request), so no in-process LRU to invalidate. But: does any agent-runner path cache the resolver result across turns of a long conversation? Plan-skill must grep for resolution caching. If yes, revoke must invalidate.
3. **CLI grant/revoke shape.** `pnpm soleur:byok grant --to <user> --workspace <id> --cap-cents <n> [--expires-in <duration>]`? Reuses tenant client + RLS or runs as service_role? Plan-skill decision.
4. **Cap accounting granularity.** Daily = UTC midnight, or rolling 24h? UTC simpler; rolling fairer. CPO/CTO defer to plan-skill.
5. **`record_byok_use_and_check_cap` integration.** Does it call the resolver (and re-check delegation state) on every token-batch write, or only at lease setup? Re-checking per-write closes the revocation grace window faster but adds RTT to a hot path. Plan-skill: measure or pick the safer default (per-write).
6. **Default privileges audit.** Per learning `2026-05-06-supabase-default-privileges-defeat-revoke-from-public`, every new DEFINER RPC needs `pg_default_acl` post-apply audit. Plan-skill: add to migration 062's smoke test.
7. **Sentry alert routing.** Cross-tenant CHECK violation → which channel? CLO Art. 33 implies escalation; existing Sentry → email path probably suffices for solo founder, but document. Plan-skill.

## Cross-Domain Dependencies

| From | To | Dependency |
|---|---|---|
| CLO | legal-document-generator | Delegation Consent Side Letter + DPD §2.3 addendum + AUP §5.6 (PR-B window) |
| CLO | CTO | DB-level `same_workspace` CHECK + Sentry alert on violation (Art. 33 risk mitigation) |
| CLO | CTO | Member-departure transactional auto-revoke on `workspace_members` removal |
| CTO | spec-flow-analyzer | 6-state failure-mode flow matrix (no delegation / expired / revoked / cap-hit / grantee-has-own-key / cross-tenant-attempt) |
| CTO | ux-design-lead | Member-row grant affordance + Jean's funded pane + Harry's banner (PR-B) |
| CTO | data-integrity-guardian | Migration 062 review (WORM trigger, RLS, anonymise RPC) |
| CTO | security-sentinel | RLS predicate review + sentinel sweep of 5 `runWithByokLease` call sites |
| CPO | CTO | Bidirectional cost visibility surfaces (`audit_byok_use.delegation_id` column) |

## Out of Scope for This Brainstorm

- Exact migration 062 SQL — plan-skill work (CTO sketch in Decisions above is the contract).
- Exact Delegation Consent Side Letter wording — legal-document-generator at plan-time.
- Exact UI visual design for member row / panes / banner — ux-design-lead at plan-time.
- ADR text — `/soleur:architecture create` post-plan.
- Whether the `byok_delegations_active` view is a materialized view or query-time SELECT — plan-skill decision.

## Session Errors

1. **CTO undershot call-site count.** CTO initially named 2 prod call sites (`cc-dispatcher.ts:891`, `inngest/functions/github-on-event.ts:209`); repo-research-analyst found **5** (`cc-dispatcher.ts:890`, `agent-runner.ts:882`, `agent-runner.ts:2401`, `cfo-on-payment-failed.ts:199`, `github-on-event.ts:208`). Reconciled before approach selection: PR-A effort sizing assumes 5 sites. Root cause: CTO didn't run the explicit call-site grep before sizing. **Fix for next brainstorm:** when sentinel-sweep rule fires, the CTO prompt should require an explicit `git grep -n 'runWithByokLease\|<symbol>'` listing.
2. **CTO referenced `runtime_cost_state` as if it were a table.** Repo-research-analyst clarified `runtime_cost_state` is two columns on `public.users` (kill-switch state), not a cost ledger; writes land in `audit_byok_use` where `founder_id` is "whose key was charged." CTO's `delegation_id` column addition was correctly targeted at `audit_byok_use` despite the naming confusion. No downstream impact, but the brainstorm narrative is now accurate.
3. **Learnings flagged "WORM vs soft-delete is incompatible"; reconciliation showed they're not.** The 048 scope_grants pattern uses a structural-diff WORM trigger that ALLOWS exactly the `revoked_at: NULL→non-NULL` UPDATE shape. Soft-delete IS the WORM-permitted mutation in this pattern. Decision #9 captures the reconciliation; canonical precedent is mig 048, not mig 044 (GUC-bypass) or mig 058 (different mutation profile).

## Productize Candidate

None identified. `byok_delegations` is app-domain authorization primitive, not a reusable skill/agent shape.

## Lane

- Lane: cross-domain (user-brand-critical triad mandatory).
- Brand-survival threshold: single-user incident.
