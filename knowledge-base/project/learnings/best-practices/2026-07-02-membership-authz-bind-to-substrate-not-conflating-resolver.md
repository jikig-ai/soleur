# Learning: authorize on the membership *substrate*, and bind the transport target to the *authorized* id

category: best-practices
module: apps/web-platform/server (git-data cross-tenant isolation, ADR-068 §6)
date: 2026-07-02
pr: #5893 (Sub-PR 3.C, Ref #5274)

## Problem

Building the cross-tenant isolation boundary for the shared git-data store (3.C),
two subtly-wrong-but-plausible authorization designs were on the table — one
prescribed by the plan, one that passed a naïve reading of "authorize before you
transport." Both would have shipped green.

## Insight 1 — "reuse RPC X's membership shape (NULL→deny)" must be checked against what X *actually* returns NULL for

The plan said to authorize git-data access via the
`resolve_workspace_installation_id` "membership shape (NULL→deny)". But that RPC
returns NULL for **two** distinct states:
- a genuine non-member (the deny path the plan meant), AND
- a legitimate **member whose workspace has no GitHub App installation**.

git-data is replicated for *every* workspace (connected to GitHub or not), so
keying the git-data authz on that resolver would **wrongly deny a legitimate
member's own git-data** — and worst in the common **solo** case (most workspaces
have no GitHub install).

The fix was to authorize on the *substrate* the resolver itself gates on:
`is_workspace_member(p_workspace_id, p_user_id)` (mig 053) — the canonical
SECURITY DEFINER membership predicate that returns a clean boolean, which mig 079's
`resolve_workspace_installation_id` calls internally. Verified the solo case:
`handle_new_user` inserts a `workspace_members(role='owner')` row for every
signup's solo workspace (`workspace_id === userId`), so
`is_workspace_member(userId, userId)` is TRUE.

**Generalizable rule:** when a plan says "reuse X's membership/authz shape," X is a
*starting hypothesis*, not the authority. Trace X to the predicate it's built on and
enumerate every input for which X returns the deny sentinel. If X conflates the
real invariant (membership) with an orthogonal state (credential presence), reuse
the underlying substrate, not the conflating resolver. Same family as
"trace the ACTUAL producer / plan hypotheses are starting points."

## Insight 2 — a membership gate must bind the transport target to the *authorized* id, not a name resolved elsewhere

The read path `fetchFromGitData` first authorized membership on `workspaceId`,
then fetched from the git remote **named** `"git-data"` — a name resolved from the
workspace clone's *local* git config, which the function does not set. Authorizing
on an id but transporting via a name resolved from mutable local state **decouples
the authz subject from the transport target**: a clone whose local `git-data`
remote pointed at workspace B would pull tenant-B objects while authz passed for
tenant-A. (Dark today — flag-off, no callers — but a latent cross-tenant confusion
vector.) Caught by `security-sentinel` review.

Fix: fetch by the **explicit URL built from the authorized id**
(`gitDataRemoteUrl(workspaceId)`), mirroring the write path's inline
`ensureGitDataRemote(workspacePath, workspaceId)`. The id that was authorized is the
id that names the transport target — no indirection through mutable local config.

**Generalizable rule:** after an `authorize(id)` check, the very next side effect
must consume that same `id` to build the resource address. If it instead consumes a
name/handle resolved from separate mutable state, the check is decorative. Same
family as `hr-write-boundary-sentinel` "keyed on the exact id, no re-derivation."

## Session Errors

- **`git status` at bare-repo root failed** ("must be run in a work tree").
  Recovery: operate from the worktree. **Prevention:** in a `core.bare=true` repo,
  never run working-tree git at the bare root; `cd` into the worktree first
  (already covered by the CWD rule).
- **CWD drift across Bash calls** — a `sed`/`grep` ran against the bare root after
  a prior `cd`. Recovery: prefix each call with `cd <worktree-abs> &&`.
  **Prevention:** existing rule ("chain `cd <abs> && cmd` in a single Bash call");
  no new enforcement needed.
- **tsc TS2554 on a mocked class constructor** — `new RuntimeAuthError("no jwt")`
  in the test used 1 arg, but the REAL `RuntimeAuthError(cause, message)` takes 2;
  vitest was green (it uses the mock's 1-arg class) but `tsc --noEmit` checks
  against the real type. Recovery: `new RuntimeAuthError("jwt_mint", "no jwt")`.
  **Prevention:** when a test instantiates a class imported from a mocked module,
  match the REAL type's constructor arity — run standalone `tsc --noEmit`, not just
  vitest (adjacent to the "vitest green, tsc red" learning class).
- **Comment containing the literal `createServiceClient` would have tripped the
  `service-role-allowlist-gate`** (the gate greps the whole file, comments
  included). Recovery: reworded the comment to "the service-role client".
  **Prevention:** existing learning (grep-over-body false-matches own comments);
  when writing a comment that names a token a whole-file grep-gate keys on, avoid
  the literal.

## Tags
category: best-practices
module: authz, git-data, membership
related: hr-write-boundary-sentinel-sweep-all-write-sites, ADR-068, ADR-044, mig-053, mig-079
