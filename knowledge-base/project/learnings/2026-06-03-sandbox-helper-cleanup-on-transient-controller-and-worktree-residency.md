# Learning: a server-written sandbox helper needs a cleanup owner that always runs AND a write location the agent cannot commit

category: logic-errors
module: apps/web-platform/server (cc-dispatcher / git-auth)
date: 2026-06-03
pr: 4899
tags: [sandbox, lifecycle, cleanup, abortcontroller, git-askpass, agent-native, brand-survival]

## Problem

PR #4899 wired an in-sandbox `GIT_ASKPASS` helper for the Concierge: the server
writes a tiny shell script under the user's `workspacePath` and passes its path
to the sandboxed agent via env so raw `git push/fetch/pull` authenticates. The
first implementation had two pr-introduced defects that all passed `tsc` + the
full unit suite (88 green) and were caught only by multi-agent review:

1. **Cleanup never ran on the normal completion path.** Cleanup was registered
   as `controller.signal.addEventListener("abort", () => cleanupAskpassScript(path))`
   on the per-dispatch synthetic `AgentSession.abort` controller. But that
   controller is `.abort()`-ed ONLY from `cleanupCcBashGatesForConversation`,
   which iterates `_ccBashGates` — and a session is registered into
   `_ccBashGates` ONLY transiently, inside `canUseTool`'s Bash-review-gate
   branch (`registerCcBashGate`). A resolved gate deletes its record;
   auto-approved safe-bash registers none. So on the dominant path (conversation
   completes with no pending Bash gate — including every dispatch where git ran
   via autonomous/auto-approve) there is no record, the controller is never
   aborted, the listener never fires, and the helper file leaks every dispatch
   into the persistent per-user workspace.

2. **The helper sat in the repo working-tree root.** It was written to
   `<workspacePath>/.askpass-<uuid>.sh` — the root of the user's cloned git
   working tree. The Concierge's whole job is git work; an agent running
   `git add -A && git commit && git push` would stage+commit+push the stray
   helper into the user's own connected repo. Token-free body, so not a
   credential leak — but user-owned-resource corruption on the brand's headline
   path ("an AI team that does git work in your repo"). Brand-survival threshold
   was `single-user incident`.

## Solution

Write a **fixed-name** helper INSIDE the repo's `.git/` directory:
`writeAskpassScriptTo(join(workspacePath, ".git"), ".soleur-askpass.sh")`
(falling back to the workspace root only when `.git` is absent — degraded /
no-repo, so no commit vector either way). This resolves BOTH defects at once
and removes the cleanup machinery entirely:

- `.git/` is outside the working tree → `git add` can never stage it (kills the
  litter/commit vector). It is still under `workspacePath`, so the SAME sandbox
  realpath-containment that made the root readable makes `.git/` readable.
- A FIXED name means the helper is reused per workspace: at most one file ever
  (no accumulation), and concurrent same-workspace dispatches are safe because
  the body is byte-identical and token-free (it reads `GIT_INSTALLATION_TOKEN`
  from env at runtime). No cleanup lifecycle to get wrong — the dead
  abort-listener + catch-path cleanup were deleted.

## Key Insight

Two generalizable rules for **server-written files consumed by a sandboxed
agent**:

1. **A cleanup registered on an event that only fires conditionally is not
   cleanup.** Before binding `cleanupX()` to `controller.abort` / a close hook /
   a `finally`, trace whether that signal fires on the *normal* completion path,
   not just the exceptional one. A synthetic `AbortController` that is only
   aborted via a transient registry (here `_ccBashGates`, populated only when a
   Bash gate fires) is dead cleanup for every dispatch that doesn't hit the
   registry. Prefer a design that needs NO cleanup (fixed-name, reused,
   idempotent) over wiring cleanup onto a maybe-fires signal.

2. **Anything the agent's `git add -A` can reach, the agent can publish.** A
   helper/scratch file written into a repo working tree the agent operates on is
   committable. Put server-side scratch files OUTSIDE the working tree — `.git/`
   is the natural choice (under the workspace for sandbox-readability, but never
   part of the tracked tree). "The body is token-free" answers *is it a leak?*
   (no) but not *what does the user experience?* (a polluted repo branch).

Both bugs shipped green through `tsc` + 88 unit tests because neither the unit
mocks nor the type system model the conversation-close lifecycle or the agent's
git behavior. Multi-agent review (architecture-strategist + performance-oracle
on the cleanup path; user-impact-reviewer + architecture-strategist on the
working-tree residency) caught them; agent-native-reviewer initially
*contradicted* the cleanup finding ("lifecycle sound") by conflating "the abort
path exists" with "the abort path runs" — resolved by reading `registerCcBashGate`'s
sole call site.

## Session Errors

1. **iac-plan-write-guard blocked the plan Write on "out-of-band"** — Recovery:
   removed the operator-driven/manual-infra phrasing (plan introduces zero
   infra). Prevention: the guard scans plan prose for manual-infra framing even
   in Non-Goals; describe what's NOT done without operator-handoff verbs.
2. **SDK type-defs absent in the worktree `node_modules`** — Recovery: deferred
   the managed-domain source-read to /work (non-blocking; Outcome-A was settled
   by the empirical prod `gh auth status` 401-from-`/user` signal). Prevention:
   when a plan cites an SDK `.d.ts` line, confirm the package is installed in
   the worktree before depending on a re-read; fall back to the empirical signal.
3. **First askpass implementation leaked the helper (dead cleanup) + wrote it
   into the committable working-tree root** — Recovery: fixed-name helper inside
   `.git/`, deleted the cleanup machinery. Prevention: the two Key-Insight rules
   above; route to the review skill's defect catalogue is unnecessary (the
   existing "feature-wiring composition bug" + "plan-asserted structural guard
   must be encoded not prose" entries already name this class).
