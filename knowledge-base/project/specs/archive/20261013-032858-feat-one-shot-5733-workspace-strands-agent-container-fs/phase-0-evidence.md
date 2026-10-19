# Phase 0 — Live exec-path verification (BLOCKING) — EVIDENCE RECORD

Date: 2026-06-30. Source: read-only prod Supabase (`DATABASE_URL_POOLER` via Doppler `soleur/prd`, `SET default_transaction_read_only=on`). Resolver code read at plan time.

> NOTE: `file:line` citations below are **pre-implementation** point-in-time records (e.g. the reconcile owner query moved from `~255-260` to `~262-271`, and the validity gate from `~310` to `~353` after the multi-owner edit). They describe the as-found state; navigate by symbol/function name, not the exact line.

## 0.0 Resolver predicate (`workspace-resolver.ts:365-418`)
`resolveActiveWorkspace(userId)`:
1. `claim = resolveCurrentWorkspaceId(userId)` (reads `user_session_state.current_workspace_id`; fail-closes to `userId`).
2. **`if (claim === userId) return solo userId`** (line 376-378) — NO membership probe, NO reset.
3. Else membership probe: `workspace_members WHERE workspace_id=claim AND user_id=userId`, `.maybeSingle()` — **role-agnostic** (no role filter). Member → claim; non-member → `userId` + `resetFromClaim`; db-error → fail-closed `db-error`.

**Consequence:** the owner *canary* (`role='owner'`) is NOT what the resolver gates on → a canary restore has **zero** effect on the resolution outcome.

## 0.1 Supabase live state (decisive)
| Fact | Value | Plan claimed | Verdict |
|---|---|---|---|
| `754ee124` = operator user id? | **YES** — `auth.users.id` of `ops@jikigai.com` | — | 754 is the operator's **SOLO** workspace (id==user_id) |
| `754ee124` repo | `jikig-ai/soleur`, `repo_status=ready`, install `122213433`, last_synced `2026-06-29T14:46` | — | — |
| `organizations.owner_user_id` (754's org) | `754ee124` (==operator), NOT NULL | "non-solo; owner derives via org and may be corrupt" | **REFUTED** — solo, owner==operator |
| Owner canary present? | **YES** — `(754ee124, owner)`, created 2026-05-21 | "missing canary → owner-less" | **REFUTED — canary present** |
| `workspace_members(754)` owner rows | **2** (`owner_rows=2`) | 1 expected | **legitimate — multi-owner is BY DESIGN (operator-confirmed)** |
| `current_workspace_id` (operator) | `754ee124` (== userId, `points_at_solo=true`) | "H3: never 754ee124" | **REFUTED — points at 754** |

### Member topology for workspace 754 (soleur)
| user_id | principal | role | attestation | created |
|---|---|---|---|---|
| `754ee124` | ops@jikigai.com (operator A) | **owner** | NULL | 2026-05-21 18:00 |
| `41509937` | (collaborator) | member | set | 2026-06-02 07:15 |
| `52af49c2` | **jean.deruelle@jikigai.com** (operator B; also owner of `chatte`) | **owner** | set | 2026-06-02 07:47 |
| `c30e6c0a` | (collaborator) | member | set | 2026-06-03 13:54 |

**OPERATOR-CONFIRMED (authoritative): workspaces CAN have multiple owners by
design.** The second owner `52af49c2` / jean.deruelle (the founder's secondary
account) is a **legitimate co-owner**, NOT an anomaly. → There is **NO data to
remediate** (Phase 1a is MOOT) and **NO single-owner invariant/DB guard** is to
be added.

## Root cause of the "ownerless-reconcile fires 28×" headline (CODE BUG — not data)
`workspace-reconcile-on-push.ts:255-260` resolves the owner via
`workspace_members ...eq("workspace_id",ws.id).eq("role","owner").maybeSingle()`.
`.maybeSingle()` **assumes ≤1 owner** and **errors when 2+ legitimate owners
exist** → `ownerRow=null` → `ownerId=null` → `if (!ownerId)` (line 279) emits the
false **"owner-less workspace reconciled"** warn every push. **The bug is the
query, not the data.** The fix is to make owner-attribution tolerate N owners
(deterministic pick) and fire "owner-less" ONLY on ZERO owner rows.

### Systemic sweep — owner-lookup sites that assume ≤1 owner
| Site | Query | Affected? |
|---|---|---|
| `workspace-reconcile-on-push.ts:255-260` | `workspace_id + role=owner`, `.maybeSingle()` (user_id NOT pinned) | **YES — the bug** (matches all owners) |
| `email-on-received.ts:348-354` | pins `workspace_id==ownerId AND user_id==ownerId AND role=owner`, `.maybeSingle()` | NO — user_id pinned → ≤1 row |
| `resolve-founder-for-installation.ts:88-140` | self-join, filters `m.user_id==w.id` in TS, handles `>1` explicitly | NO — solo self-row, `>1` fail-closed |

## 0.2 Self-stop driver
Resolution for the operator is correct (`claim===userId` early-exit → `/workspaces/754ee124` → soleur, ready). The strand is therefore NOT a resolution-divergence; it is the readiness `git rev-parse` self-stop over `/workspaces/754ee124/.git` (prompt-driven `/soleur:go` Step 0.0). Confirmed self-stop is in the general dispatch path (not solely routine-authoring).

## 0.3 Sentry
`scripts/sentry-issue.sh` is issue-id/`--latest-event` only (no free-text search subcommand exists yet — the plan's `… search` discoverability command is a *proposed* addition). DB predicates are the decisive discriminators per the plan; Sentry corroboration deferred to the discoverability test added in Phase 1b. The "ownerless-reconcile 28×" headline is fully explained by the `.maybeSingle()`-on-2-owners code path above.

## Independence check (strand vs data anomaly)
The duplicate-owner does NOT break install-id resolution on the dispatch/clone
path: `resolve-founder-for-installation.ts:126-133` filters owner rows to the
**solo self-row** (`m.user_id === w.id`), dropping `52af49c2` (user_id ≠
workspace_id). So the strand (H2) and the duplicate-owner anomaly are
**independent**. (`kb_sync_history` is not a standalone relation under that name —
the plan's audit-unblock narrative referenced a wrong table.)

## 0.4 Branch decision
- **H1 (reset-to-solo): REFUTED.** Operator is an owner-member AND `claim===userId` early-exits before any reset.
- **H3 (current_workspace_id ≠ 754): REFUTED.** It IS 754.
- **Owner-less premise: REFUTED.** Canary present (duplicated).
- **H2 (`.git` invalid to bwrap `git rev-parse`): ONLY surviving strand hypothesis.** Decisive evidence is the prod *filesystem* state of `/workspaces/754ee124/.git`, NOT visible from DB and not reachable without SSH (forbidden). Confirmation requires the Phase 1b agent-surface observability.

**Scope consequence (material divergence from plan; multi-owner-by-design confirmed → CTO ruling for execution shape):**
1. **Phase 1b observability** — unchanged, the key committed deliverable; makes the H2 strand visible.
2. **Reconcile multi-owner attribution fix** — new, code-confirmable, kills the false "owner-less" flood. Tolerate N owners (deterministic pick); "owner-less" warn ONLY on ZERO owners.
3. **Phase 1a — DROPPED.** Multi-owner is by design; the prod data is correct; no canary insert, no demote/remove, no operator-ack write.
4. **No single-owner DB guard / CHECK** — would contradict the by-design multi-owner model.
5. **H2 git-rev-parse robustness fix** — defensible (only surviving strand hypothesis, strictly-more-correct) but unconfirmed live; CTO to rule ship-now vs defer-behind-observability.

## ARCHITECTURE DECISION OF RECORD (CTO ruling + founder decision, 2026-06-30)

**Founder decision (binding):** workspaces support **N co-owners** by design — this **supersedes #4520 single-owner-strict** (migration `075:7-12`). So `(52af49c2, owner)` is a **legitimate co-owner**; **no data remediation**.

**Ships in THIS PR (all model-independent / multi-owner-correct):**
1. **Phase 1b observability** — `agent-readiness-self-stop` Sentry event (own issue group, distinct Error message) carrying `activeWorkspaceId`, resolved `workspacePath`, `gitValid`, **and the `.git` shape** (FILE vs dir, gitdir target, `rev-parse` exit/stderr), captured BEFORE healing; read in the agent's bwrap context; no `installationId`/`repo_url`; `userId` pseudonymized.
2. **B — reconcile multi-owner attribution** (`workspace-reconcile-on-push.ts:255-260`): drop `.maybeSingle()`; select ALL owner rows; pick attribution owner deterministically (self-row `user_id==ws.id` if present, else earliest `created_at`); fire **"owner-less" warn ONLY on ZERO owners**; on ≥2 owners emit a distinct **info** "multiple-owners" breadcrumb (no page). Only broken site (sweep confirmed).
3. **D — H2 rev-parse readiness heal** (CTO: ship NOW): at the dispatch readiness gate add a real `git -C <ws> rev-parse --is-inside-work-tree` (the probe the agent runs); on failure → not-ready → re-clone a **self-contained `.git`** (clone, never rm for the FILE/denyRead case). Destructive `rm` stays gated on `isEmptyCorruptGitDir` ONLY. Sweep both call sites: dispatcher gate AND `reconcile:310`. The blind spot is `git-worktree-validity.ts:60` (a `.git` FILE returns `true`, never `rev-parse`-probed).
4. **ADR-044 amendment** — readiness = `rev-parse`-verified at the workspace root, not lstat-structural-only.

**Follow-up issues (NOT this PR):**
5. `/soleur:architecture` ADR capturing **multi-owner supersedes #4520**, + reconcile the ownership RPCs (`transfer_workspace_ownership`, `update_workspace_member_role` owner-promotion block, last-owner guard in `075`/`067`) so co-owners are reachable through the product.
6. `#5591`/`#5673` duplicate-workspace origin re-eval.

**Explicitly NOT in scope:** single-owner DB unique guard / CHECK; any data write.
