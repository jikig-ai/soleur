# Learning: column-relocation reader sweeps must cover `.eq("col", val)` lookups, not just `.select("col")`

**Date:** 2026-06-17 · **Feature:** ADR-044 PR-2 team write-cutover (#5462, PR #5466)

## Problem

Relocating connect-time repo state from `users.*` to `workspaces.*` (the write side of ADR-044). The plan asserted "the read path is already cut over." It was **false**: a `git grep` of `.select(...github_installation_id...)` / `.select(...repo_url...)` found 5+ surviving `users.*` readers, and a *sixth* — the GitHub push-webhook founder-resolver — was missed by EVERY `.select()`-shaped grep (the CTO's and mine) because it reads the relocated column as a **WHERE filter**:

```ts
.from("users").select("id").eq("github_installation_id", installationId)   // ← lookup BY the column
```

A `.select("...github_installation_id...")` grep never matches this; the column name appears only inside `.eq(...)`. Relocating the write without migrating this reader strands push auto-sync for every newly-connected user (their `users.github_installation_id` is now NULL).

## Solution / Key Insight

**When relocating a column, the consumer sweep must grep BOTH shapes:**
1. `.select(` lists that name the column (projection readers).
2. `.eq("<col>", …)` / `.in("<col>", …)` / `.match({<col>: …})` filters that *look up by* the column (lookup readers).

A column used as a lookup key is the most load-bearing kind of reader (it routes/joins on the value), yet it's invisible to the projection grep. Canonical sweep for a relocated column `C`:

```bash
git grep -nE "\.(eq|in|match|or|filter)\([\"']?$C|select\([^)]*\b$C\b" -- '<scope>'
```

**Two more durable insights from the same session:**

- **Architectural-fork → CTO worked as designed.** The plan-vs-codebase contradiction ("read path cut over" was false) + a resolution with material trade-offs (migrate-all vs defer-service-role vs dark-launch flag) is an *engineering* decision. Routing it to `soleur:engineering:cto` (not the operator) produced a clean binding ruling (Option D: migrate interactive readers in-PR, defer service-role readers — the `auth.uid()`-gated RPC is unusable from cron/webhook/inngest contexts). Re-route to the CTO when a *later* discovery (the `.eq()` reader) widens the same decision.

- **Reusing a function whose scope doesn't match the need is a silent bug.** `abortAllWorkspaceMemberSessions(workspaceId, userId)` *reads* like "abort the workspace's member sessions" but is **member-scoped** (only the passed user's own sessions — built for member-removal). Calling it for a shared-team-dir teardown left co-members mid-write → ENOENT. Before reusing a registry/util function for a new caller, read its body and confirm its *scope* matches (here: needed a workspace-wide `abortAllSessionsForWorkspace`). security-sentinel caught the overclaiming comment.

## Session Errors

1. **Both resume-state premises were stale.** The resume prompt said "all work is uncommitted" and "Sibling-set sweep CI failing" — both false (work was committed+pushed; the check passed). **Recovery:** verified actual state (`git status`, `gh pr checks`) before acting. **Prevention:** covered by the work-skill rules "plan-quoted numbers are preconditions to verify" + "on resume, prior-session artifacts are UNVERIFIED" — apply them to *session-state claims* too, not just file artifacts.
2. **Plan claimed "read path already cut over" — false (5+ readers).** **Recovery:** verify-the-negative grep + CTO ruling. **Prevention:** treat any plan "X is already done/safe" claim as a precondition to grep, never a fact.
3. **`.eq()` lookup reader missed by `.select()` grep.** **Recovery:** caught at multi-agent review (data-integrity-guardian). **Prevention:** the dual-shape sweep above (route-to-definition → work skill).
4. **`abortAllWorkspaceMemberSessions` member-scoped, used for workspace-wide need.** **Recovery:** added `abortAllSessionsForWorkspace` + tests; caught by security-sentinel. **Prevention:** read a reused function's body for scope before wiring a new caller.
5. **Hit the `vitest > log; echo "RC=$?"` tail-masking trap twice** — the trailing `echo` made the shell exit 0 while vitest failed. **Recovery:** read the summary line / `VITEST_FINAL_RC` directly. **Prevention:** ALREADY a documented learning (`2026-05-18-test-all-tail-masking`); capture vitest's rc with `vitest run; rc=$?` as the *last* statement, or grep the summary — don't trust a trailing-echo'd "exit 0".
6. **Bash CWD persistence:** used `apps/web-platform/test/...` paths while CWD was already `apps/web-platform` → file-not-found. **Prevention:** the Bash tool persists CWD across calls — anchor paths to the known CWD or use absolute paths.
7. **One-offs:** `Monitor` tool called without its schema loaded (needs ToolSearch first); an `Edit` failed "modified since read" after a `perl -i` edit to the same file (re-read before editing). No recurrence vector.

## Tags
category: integration-issues
module: apps/web-platform (ADR-044), workflow (compound/work consumer-sweep)
related: ADR-044, #5462, #5437, #5470
