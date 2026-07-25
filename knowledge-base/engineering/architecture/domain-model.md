# Domain Model & Business Rules Register

> Queryable catalogue of Soleur's core domain entities, their invariants, and the
> business rules that govern them. Companion to
> [`principles-register.md`](./principles-register.md) (architectural principles)
> and [`nfr-register.md`](./nfr-register.md) (non-functional requirements). Each
> rule cites its canonical source (ADR / migration / guard function).
>
> **Maintenance contract.** When a PR introduces or changes a business rule (an
> entity invariant, ownership/access model, or relationship encoded in a migration
> constraint / RLS policy / resolver-guard), it MUST update the affected row(s)
> here in the same PR. **Wired:** (1) the `architecture` skill's `create` step
> (an ADR that records/changes a business rule must update this register); (2) the
> preflight **stale-citation ship block** (`Check 11`, diff-scoped — blocks a PR that
> makes a cited migration/symbol unresolvable); (3) an **advisory review note**
> surfacing drift counts + `/soleur:sync domain-model` (#5871, ADR-076). Plan-time
> flagging was intentionally not built — no diff exists at plan time.
>
> **Auto-fill + drift-check (live, #5754).** `/soleur:sync domain-model` runs a
> deterministic analyzer (`scripts/domain-model-drift.sh`) that drift-checks this
> register against the repo's migrations/RLS/guards and, with per-row operator
> approval, proposes rows into `## Auto-inferred (unreviewed)` below. See
> [`ADR-076`](./decisions/ADR-076-domain-model-drift-extraction.md).
>
> **Completeness disclaimer.** This register + any drift report are **best-effort
> structural extraction; NOT a security audit or access-control attestation.**
> Absence from the register does not imply an invariant is unenforced, and presence
> does not imply it is correctly enforced. Dynamic RLS (`EXECUTE format`/`DO $$`),
> function-body logic, and un-merged `ALTER POLICY` are disclosed as blind spots,
> not analyzed.

## Entities

| Entity | Key | Description | Canonical source |
|---|---|---|---|
| User | `auth.users.id` (uuid) | An authenticated principal. | Supabase auth |
| Organization | `organizations.id` | Owns workspaces; carries `owner_user_id`. | ADR-038, migration 053 |
| Workspace | `workspaces.id` | A project context; binds a repo + an on-disk `/workspaces/<id>` tree. | ADR-038, ADR-044 |
| Membership | `workspace_members(workspace_id, user_id)` PK | Grants a user access to a workspace, with a `role`. | ADR-038, migration 053 |
| Repo binding | `workspaces.(github_installation_id, repo_url)` | The GitHub repo a workspace is connected to. | ADR-044 |
| Conversation | `conversations.id` | A Command Center chat thread owned by a user (`conversations.user_id`), with owner-private / opt-in workspace-shared visibility. | migration 075_conversation_visibility.sql; #4521 |

## Business Rules

| ID | Rule | Statement | Source |
|---|---|---|---|
| BR-WS-1 | Solo workspace identity | Every user has a guaranteed personal (solo) workspace where `workspace_id == user_id`. | ADR-044; principles-register `AP-015` |
| BR-WS-2 | Workspace access | A user accesses a workspace via a `workspace_members` row; absence = no access. The dispatch membership probe is **role-agnostic** (`workspace-resolver.ts` `resolveActiveWorkspace`). | ADR-038 |
| BR-WS-3 | **Workspace ownership = N co-owners (by design)** | A workspace has **≥1 owner** (`workspace_members.role='owner'`). Multiple co-owners are legitimate — **supersedes the single-owner-strict model** of migration 075 / #4520. Owner-attribution code MUST tolerate N owners (prefer the self-row `user_id==ws.id`, else earliest-created). | #5733; **ADR-073** (decision-of-record); ADR-044 (2026-06-30 amendment); RPC reconcile #5756 |
| BR-WS-4 | Owner canary | Ownership is recorded ONLY as a `workspace_members(role='owner')` row — there is no `workspaces.owner_user_id` column. For a solo workspace the canonical owner is the self-row (`user_id == workspace_id`). | ADR-038 (N2); ADR-044 |
| BR-ORG-1 | Org owner | `organizations.owner_user_id` is the org-level owner; a workspace's org is `workspaces.organization_id`. | ADR-038, migration 053 |
| BR-REPO-1 | Repo belongs to a workspace | A GitHub repo is bound to a workspace via `(installation_id, repo_url)`; reconcile-on-push heals `/workspaces/<id>` keyed on that pair. | ADR-044 |
| BR-REPO-2 | Active-workspace path resolution | The agent resolves its cwd from the user's ACTIVE workspace (`user_session_state.current_workspace_id` → membership-verified → fail-closed to solo). This keying can diverge from reconcile's `(install, repo)` keying — the **keying-divergence trust boundary**. | ADR-044 (2026-06-30 amendment) |
| BR-REPO-3 | Readiness is rev-parse-aware | A workspace is "ready" when its `.git` is a self-contained valid dir OR a non-escaping in-workspace pointer. An **escaping** `.git` FILE pointer strands the agent's in-bwrap `git rev-parse` and is re-cloned self-contained. | ADR-044 (2026-06-30 amendment); #5733 |
| BR-CONV-1 | Conversation ownership & visibility | A conversation (`conversations.id`) is owned by its creating user (`conversations.user_id`). Visibility is owner-private by default with opt-in workspace-shared **READ** (`visibility='workspace'` AND workspace membership); **INSERT/UPDATE/DELETE are conversation-row-owner-only** (`user_id = auth.uid()`), and `UPDATE(visibility)` is REVOKE'd from the `authenticated` role (flips only via a SECURITY DEFINER RPC). "Owner-only write" is scoped to **conversation-row** ownership (`conversations.user_id`) and is distinct from *workspace* ownership — see the workspace co-owner rule BR-WS-3. Cost / cache-token counters are CHECK-constrained non-negative. | migration 075_conversation_visibility.sql; constraints 017_conversation_cost_tracking.sql, 041_conversation_cache_tokens.sql; see BR-WS-3 |
| BR-STORAGE-1 | Storage-object tenancy | Access to `storage.objects` is bucket-scoped and tenant-keyed: chat-attachment objects are readable by the conversation owner + workspace co-members and writable owner-only; workspace-logo objects are member-read / owner-write; DSAR-export objects are folder-prefix self-scoped (first path segment = the owner user id); ux-audit-artifact objects are bot-scoped. Client writes are RLS-scoped to own-folder/owner (anon denied by absent policy); the chat-attachments upload path uses service-role presigned URLs. | migrations 019_chat_attachments.sql, 042_dsar_exports_storage_bucket.sql, 068_attachments_workspace_shared.sql, 071_ux_audit_artifacts_bucket.sql, 098_workspace_logos.sql |
| BR-BYOK-1 | BYOK delegation consent (Art. 7) | A BYOK key delegation (grantor→grantee) may process the grantee's prompts under the grantor's key **only while a current-version, un-withdrawn in-app consent exists**. `resolve_byok_key_owner` gates in SQL on `EXISTS(current-version acceptance) AND NOT EXISTS(withdrawal newer than that acceptance)`; a mid-run withdrawal stops in-flight billing within one turn (debiting the grantee). Consent is withdrawable as easily as given (**GDPR Art. 7(3)**); withdrawal rows are append-only WORM with a NULLABLE user id for Art. 17 anonymise. | migrations 083_byok_delegation_consent_gate.sql, 084_byok_delegation_withdrawals.sql; GDPR Art. 7 / Art. 26 |
| BR-DSAR-1 | DSAR export scoping & erasure (Art. 15/17) | DSAR export jobs (`dsar_export_jobs`) are owner-scoped (a user reads only their own job rows); PII audit rows (`dsar_export_audit_pii`) are admin-only WORM, kept separate from the user-visible job state. **Art. 17 erasure anonymises** audit rows (`requester_ip` / `user_agent` set to NULL) rather than deleting, and the owner user id de-links via `ON DELETE SET NULL` when the auth row is deleted; the delete cascade is deadlock-repaired so account deletion succeeds against the solo-canary workspace. | migrations 041_dsar_export_jobs.sql, 065_art17_cascade_deadlock_repair.sql; ADR-028; GDPR Art. 15 / Art. 17 |
| BR-NOTIFY-1 | Statutory-reminder dispatch is once-per-tick | A statutory-deadline reminder dispatches at most once per (item, logical tick). A send-marker row keyed `(item_id, tick_key)` is inserted **immediately before** dispatch — after every pre-existing skip guard, so a skipped row never records a phantom send — and a `23505` means the tick was already sent. The tick identity is **branch-derived**, not a single value: the constant `headsup` for the one-shot T-7 heads-up (whose floor-day window spans 24h, so a calendar date would let jitter send it twice) and `daily:YYYY-MM-DD` for the T-2-through-overdue band (which a constant would silence after day one). The guard **fails open**: only a clean `23505` suppresses, because silence on a running legal clock is strictly worse than a duplicate. The key is **item-grain**, which equals recipient-grain ONLY while the send path targets a single recipient — a fan-out to multiple workspace Owners must re-key the table first or the first Owner's marker suppresses every other Owner. | migration 135_statutory_repin_send.sql; ADR-037; GDPR Art. 32(1)(b); see BR-DSAR-1 |

## Auto-inferred (unreviewed)

> Rows proposed by `/soleur:sync domain-model` (operator-approved, not yet curated).
> This section is **machine-appended** and is NEVER a source of truth. Promote a row
> to a curated `## Business Rules` rule by a deliberate human edit: assign a `BR-*`
> id, refine the statement, and keep the source anchor (the anchor is the dedup key,
> so a promoted row is never re-proposed). Do not hand-edit the table shape.

| Anchor | Candidate statement |
|---|---|

## How to maintain this register

- **A PR that changes a business rule** (a new/changed migration constraint, RLS policy, ownership/access invariant, or resolver-guard semantics) updates the affected row(s) + cites the new source. Wired via the `architecture` skill's `create` step (ADR → register), the preflight stale-citation ship block (`Check 11`), and an advisory review note (#5871, ADR-076). Plan-time flagging was intentionally not built (no diff at plan time).
- **Auto-population (#5754):** `/soleur:sync domain-model` derives candidate rules from migrations (tables / FKs / UNIQUE+CHECK constraints / RLS) and guard functions, reconciles against this register, and flags drift (a register rule with no backing source, or a source-level invariant with no register row).
- **Rule IDs are immutable** (mirrors `cq-rule-ids-are-immutable`): retire a row by marking it superseded + linking the superseding row, never by reusing an ID.
- **Curating a drift finding into a `BR-*` row (learned #5882):** cite migration files as *unbackticked* prose (`migration 075_conversation_visibility.sql`), never backticked — the drift analyzer's stale-citation check cross-products every backticked `.sql`/`.ts` file × every backticked bare identifier on the SAME table row and greps the file for the symbol, so a backticked filename beside an unrelated identifier fabricates a false stale citation. Grep-validate each factual claim (column name, RLS/REVOKE semantics, `ON DELETE` behavior, GDPR article) against the migration body before promoting. A dup-`BR-ID` check must anchor to definition rows (`^\| BR-…`) so legitimate cross-references don't false-flag. See [`learnings/best-practices/2026-07-01-domain-model-register-curation-citation-parser-and-grep-validation.md`](../../project/learnings/best-practices/2026-07-01-domain-model-register-curation-citation-parser-and-grep-validation.md).
