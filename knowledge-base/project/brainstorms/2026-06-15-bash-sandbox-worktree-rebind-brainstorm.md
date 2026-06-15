---
title: Bash sandbox worktree-rebind loop — make the bwrap sandbox reach git worktrees
date: 2026-06-15
status: brainstorm-complete
issue: 5313
parent_epic: 5240
branch: feat-5240-bash-cwd-worktree-rebind
pr: 5311
lane: cross-domain
brand_survival_threshold: single-user incident
---

# Brainstorm: Bash sandbox worktree-rebind loop (deferred #5240 FR-half)

## What We're Building

Make the production Concierge's **Bash bwrap sandbox able to enter and operate inside git
worktrees**, so a worktree-creating session (e.g. `/soleur:go → one-shot → worktree-manager.sh`)
can pass its CWD-verification gate instead of hanging. Plus a **bounded fail-loud guardrail** so a
genuinely-unenterable worktree surfaces an honest error instead of looping forever.

This is the **genuine backend stuck-loop** half of #5240, distinct from:
- **#5256 (merged)** — logical workspace-id rebind + honest status on *reconnect* (FR1/FR4).
- **#5306 (draft)** — the *UI* false-positive "Agent stopped responding" banner.

The inciting failure: the "Fix Issue 4826" session created a worktree, but every Bash `pwd`
returned `/home/soleur`, Bash couldn't `ls /workspaces/<uuid>/`, while Read/Edit/Grep read the repo
fine. The agent looped `pwd && git branch --show-current && git log` 4+ times, then hung.

## Why This Approach

### Confirmed mechanism (code-verified, file:line)

Two categorically different execution contexts:
- **File tools (Read/Edit/Grep/Glob)** run **in-process** in the Claude Code CLI (Node `fs`) — full
  container FS visibility, including the `/workspaces` bind-mount. Not bwrap-sandboxed.
- **Bash** runs in a **bwrap sandbox** whose mount namespace + `cwd` are **frozen once per
  `query()`**:
  - `apps/web-platform/server/agent-runner-query-options.ts:149` — `cwd: args.workspacePath`, set
    once at session start, never re-derived mid-session.
  - `apps/web-platform/server/agent-runner-sandbox-config.ts:94` — `denyRead: ["/workspaces",
    "/proc"]`; only the specific `allowWrite: [workspacePath]` is mounted (the `/workspaces` parent
    is excluded for cross-tenant isolation).
- **`EnterWorktree` is an SDK-native tool with NO Soleur server-side handler** — it flips a
  logical/file-tool CWD notion but **cannot rebind the bwrap mount or the Bash subprocess cwd**. A
  worktree (separate working tree + a `.git` pointer into the bare repo's gitdir) created after
  session start is therefore unreachable from Bash.
- **`plugins/soleur/skills/one-shot/SKILL.md:70-76`** — the CWD gate says "abort on mismatch" but
  has **no bounded-retry escape**; the live agent looped and hung.

**Key correction vs. the original hypothesis:** the fault is **in Soleur's own code** (sandbox
config + skill gate), NOT the Claude Code harness — so the root cause is fixable in-repo.

### Chosen approach: make the sandbox support worktrees + guardrail

Operator-selected (over "skip worktrees in sandbox" and "guardrail-only"). Re-derive or extend the
bwrap `cwd` + mount set on worktree entry so worktrees are reachable from Bash, **keeping the
`/workspaces` cross-tenant `denyRead` intact**. Pairs with the bounded fail-loud guardrail. Most
robust — preserves worktree branch-isolation inside the sandbox rather than removing the capability.

**Why not the alternatives:**
- *Skip worktrees in sandbox* — simpler, no security-config risk, but removes a capability the
  operator wants to keep working in-product.
- *Guardrail-only* — stops the hang but leaves worktree-creating sessions dead.

## Key Decisions

| # | Decision | Rationale |
|---|----------|-----------|
| 1 | Root cause is Soleur sandbox config, NOT the harness — fixable in-repo | `agent-runner-sandbox-config.ts` + `agent-runner-query-options.ts` are Soleur code |
| 2 | Chosen: make the bwrap sandbox reach worktrees (re-derive/extend cwd+mount on entry) | Operator choice; preserves in-product worktree isolation |
| 3 | Keep `denyRead: ["/workspaces"]` cross-tenant isolation intact | Weakening it would let Bash list sibling tenants' workspaces — security regression |
| 4 | Ship a bounded fail-loud guardrail regardless (ceiling ~3 → `WorktreeEnterFailed{expectedPath,observedCwd}` → Sentry + honest status) | Circuit breaker, never a mask; converts hang → loud fail; independent of root-cause fix |
| 5 | Honest failure reuses #5306/#5256 honest-status vocabulary (no NEW UI surface) | Maps onto existing `reconnect-resume-states.pen` "unrecoverable" state |
| 6 | Security-sentinel + CTO sign-off MANDATORY at plan/review (sandbox-config change) | Touches the bwrap mount/denyRead security boundary |
| 7 | Capture an ADR for the bwrap-mount-namespace-for-worktrees decision | Cross-session blast radius; CTO flagged `/soleur:architecture create` |
| 8 | Ref #5240 (keep epic OPEN); Closes the new focused sub-issue | #5240 is the umbrella per the 2026-06-14 parent brainstorm |

## Open Questions

1. **Exact failure trigger (needs runtime repro).** Why did even `ls /workspaces/<uuid>/` return
   nothing? Three candidates, possibly compounding: (a) the worktree's gitdir pointer escaped the
   mounted `workspacePath`; (b) `cwd` was frozen at the workspace root, not the worktree subdir, and
   bwrap fell back to `$HOME` on a failed `chdir`; (c) `workspacePath` itself drifted to the empty
   solo workspace (the #5240-core binding drift, compounding here). Trace before writing the fix.
2. **Mount mechanism for re-derivation.** Can the bwrap mount/cwd be re-derived per-tool-call or
   per-worktree-entry, or only per `query()`? If only per-query, the fix may need to mount the
   *parent worktrees root* (under `workspacePath`, not `/workspaces`) up-front so any worktree
   created later is already reachable — verify at plan time.
3. **Worktree location.** `worktree-manager.sh` creates worktrees at `$GIT_ROOT/.worktrees/<branch>`.
   Confirm `$GIT_ROOT` resolves *inside* the mounted `workspacePath` in the Concierge clone (not a
   path under the denyRead'd `/workspaces` parent or the bare-repo gitdir).
4. **Gitdir reachability.** A worktree's `.git` file points to `<bare>/.git/worktrees/<branch>`.
   Ensure that gitdir target is inside the mounted namespace so `git -C <worktree>` works, not just
   `ls`.

## User-Brand Impact

- **Artifact:** the Concierge backend agent-session worktree/Bash execution context
  (`agent-runner` bwrap sandbox + the one-shot CWD-verification gate).
- **Vector:** a worktree-creating session hangs indefinitely with no honest signal — the operator
  watches the agent loop a verify command and die ("Agent stopped responding"), the single most
  trust-destroying state a non-technical operator can see, on the brand's headline "AI org that does
  real git work in your repo" path.
- **Threshold:** single-user incident.

## Domain Assessments

**Assessed:** Engineering (CTO), Product (CPO — carry-forward from #5240 parent), Legal (CLO —
carry-forward from #5240 parent)

### Engineering (CTO)

**Summary:** Fault is the EnterWorktree→Bash rebind contract at the sandbox boundary, not app-side
resolution (`resolveActiveWorkspacePath` always returns a path, never throws — can't be the loop
source). HIGH severity / MEDIUM likelihood (every worktree-creating session crossing a
sandbox-(re)spawn boundary is exposed; one-shot/plan hard-gate on the CWD check so it's a guaranteed
hang when triggered). Mandatory guardrail: bounded retries (ceiling 3) → loud `WorktreeEnterFailed`
→ Sentry + honest status (`cq-silent-fallback-must-mirror-to-sentry`). YAGNI: do NOT redesign the
workspace/sandbox layer — it's a mount-visibility bug, not a durability bug (volume is already
persistent). Verify *where* the bwrap mount set is assembled before sizing — CONFIRMED in-repo at
`agent-runner-sandbox-config.ts`. Capture an ADR for the mount-namespace decision.

### Product (CPO)

**Summary (carry-forward from #5240):** Honesty-first — the lie/hang is the brand breach, not the
lost compute. Minimum the user must see on failure: no fake activity, an accurate "couldn't enter
the workspace" state, and one honest actionable choice. Reuse the named-continuity honest-status
family from #5256/#5306; do not invent a parallel state.

### Legal (CLO)

**Summary (carry-forward from #5240):** NOT a legal blocker. Operator-self-use (tenant-zero), single
EU-region Hetzner substrate. The cross-tenant `/workspaces` `denyRead` is a load-bearing isolation
control — **must remain intact** (Decision #3); weakening it would create a cross-tenant read surface
that WOULD trigger residency/isolation obligations once arms-length tenants exist.

## Capability Gaps

None blocking. All seams exist in-repo: bwrap config (`agent-runner-sandbox-config.ts`), per-query
cwd (`agent-runner-query-options.ts:149`), the CWD gate (`one-shot/SKILL.md:70-76`), and the
honest-status render family (`reconnect-resume-states.pen` + `chat-state-machine.ts`). Note (CTO): the
bwrap mount wiring is security-sensitive Soleur infra that no domain *leader* owns at review time —
`security-sentinel` (review agent) + CTO sign-off are the gate (Decision #6), not a new build.
