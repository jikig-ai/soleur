# Learning: a zero-commit work branch is reaped by concurrent cleanup-merged; and ADR-044 PR-2's "additive write relocation" was structurally the deferred #4560

## Problem

Two distinct lessons from the ADR-044 PR-2a session.

### 1. Zero-commit worktree + branch silently reaped mid-session

A fresh `worktree-manager.sh create feat-adr-044-pr2-write-relocation` was made
with the session-lease env vars (`SOLEUR_SKILL_NAME=work
SOLEUR_EXPECTED_DURATION_MIN=240`). Reconnaissance (all read-only) ran for a
while, then `cd` into the worktree failed: **the worktree directory AND the
branch ref were both gone**, and a foreign sibling worktree had appeared. A
concurrent session's `cleanup-merged` had reaped it.

Root cause: `cleanup-merged` reaps branches that `git branch --merged main`
reports as merged. **A branch with ZERO unique commits beyond `main` IS
"merged"** by that definition (it has no commits `main` lacks). So a
just-created, not-yet-committed work branch is indistinguishable from a
fully-merged one — the lease did not protect it (or the sibling's cleanup
predated/ignored the lease).

### 2. The plan's "additive write relocation" did not exist as a decoupled step

ADR-044 PR-2 was scoped as "relocate connect-time WRITES `users.* → workspaces.*`,
then DROP the legacy columns." Implementation revealed the write relocation is
structurally the **deferred #4560 / Phase-5 team-provisioning** effort, not a
quick additive step.

## Solution

### 1. Land an immediate commit right after worktree creation

After `worktree-manager.sh create`, commit a scaffolding artifact (the spec /
decision record) BEFORE any long read-only phase, so the branch has ≥1 unique
commit and never reads as "merged":

```
git add knowledge-base/project/specs/feat-<name>/spec.md
LEFTHOOK=0 git commit -q -m "docs(<scope>): spec + decision record"
git rev-list origin/main..HEAD --count   # must be ≥ 1
```

The durable fix belongs in the git-worktree subsystem (auto-create an initial
empty/scaffold commit on `create`, OR have `cleanup-merged` refuse to reap a
branch that is < N minutes old or holds an active lease) — filed as a separate
issue (different subsystem; scope discipline) — filed as **#5454**.

### 2. Trace the actual producer; route the fork to the CTO

`git grep`/Read of the real code (not the plan's line numbers) showed:
- `setup/route.ts` clones into `/workspaces/<user.id>` (solo on-disk
  provisioning); team provisioning is explicitly "Phase 5".
- the owner-gate invariant "`p_workspace_id` MUST equal the id the handler
  mutates" couples the gate change to the write relocation.
- mig 079 already did the `workspaces` repo columns + the credential protection
  (`REVOKE SELECT ON workspaces FROM authenticated` + reader RPC); PR-1 did the
  read cutover. The quick pre-drop steps were ALREADY shipped.

The architecture/sequencing fork was routed to the `cto` agent, which split PR-2
into **PR-2a** (a confused-deputy refusal guard: 422 when a team workspace is
active on `repo/setup`/`disconnect`, no-op for solo) and **PR-2b** (the
destructive drop, gated on #4560 + a real prod soak).

### 3. Soak-gate discipline

The drop's soak gate was evaluated via the Sentry issues API: **0
`repo_resolver_divergence` breadcrumbs ~28 min after PR-1 merged**. Zero events
with no soak window is *no data*, not *proven clean*. A one-way-door destructive
migration must wait for a real prod soak window with traffic.

## Key Insight

- **A not-yet-committed work branch is "merged" to `git branch --merged` — commit
  something immediately so concurrent `cleanup-merged` can't reap it.**
- **A plan's "additive step" is a hypothesis; trace the actual producer. When the
  real decoupling differs (here: the write relocation IS the deferred team-flow),
  route the sequencing fork to the CTO, don't force the plan's shape.**
- **Absence of an error signal shortly after deploy is not evidence of
  correctness; a destructive one-way door needs a real soak window.**

## Session Errors

- **Zero-commit worktree+branch reaped by concurrent cleanup-merged** — Recovery:
  recreated the worktree and landed an immediate spec commit. Prevention: commit a
  scaffold artifact right after `create` (done this session); durable fix filed
  against the git-worktree subsystem.
- **Bare-repo-root `git grep` (`fatal: must be run in a work tree`) + a CWD drift
  to the bare root** — Recovery: re-ran with `cd <worktree>` and `;` separators.
  Prevention: already covered by `hr-when-in-a-worktree-never-read-from-bare`;
  one-off operator slip.
- **`&&`-chain short-circuited on a `git grep` exit-1 (no matches), hiding a
  follow-on typecheck command** — Recovery: re-ran the steps separately.
  Prevention: separate independent shell steps with `;` (or `|| true`) when an
  intermediate grep legitimately returns non-zero. One-off.

## Tags
category: workflow-patterns
module: git-worktree, adr-044
