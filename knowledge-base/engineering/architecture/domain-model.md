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
> here in the same PR. **Wired today:** the `architecture` skill's `create` step
> (an ADR that records/changes a business rule must update this register).
> **Fast-follow (not yet mechanically gated):** plan-time flagging, a review
> drift-check, and a ship block — tracked alongside the `/soleur:sync
> --domain-model` auto-fill in #5754.

## Entities

| Entity | Key | Description | Canonical source |
|---|---|---|---|
| User | `auth.users.id` (uuid) | An authenticated principal. | Supabase auth |
| Organization | `organizations.id` | Owns workspaces; carries `owner_user_id`. | ADR-038, migration 053 |
| Workspace | `workspaces.id` | A project context; binds a repo + an on-disk `/workspaces/<id>` tree. | ADR-038, ADR-044 |
| Membership | `workspace_members(workspace_id, user_id)` PK | Grants a user access to a workspace, with a `role`. | ADR-038, migration 053 |
| Repo binding | `workspaces.(github_installation_id, repo_url)` | The GitHub repo a workspace is connected to. | ADR-044 |

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

## How to maintain this register

- **A PR that changes a business rule** (a new/changed migration constraint, RLS policy, ownership/access invariant, or resolver-guard semantics) updates the affected row(s) + cites the new source. Wired today via the `architecture` skill's `create` step (ADR → register); plan-flagging, a review drift-check, and a ship block are fast-follows (#5754).
- **Auto-population (#5754):** `/soleur:sync --domain-model` derives candidate rules from migrations (tables / FKs / UNIQUE+CHECK constraints / RLS) and guard functions, reconciles against this register, and flags drift (a register rule with no backing source, or a source-level invariant with no register row).
- **Rule IDs are immutable** (mirrors `cq-rule-ids-are-immutable`): retire a row by marking it superseded + linking the superseding row, never by reusing an ID.
