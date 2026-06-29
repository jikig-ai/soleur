# Learning: "Still failing despite all fixes" — root-cause the DATA, and re-verify a stale issue's premise before any destructive de-dup

## Problem

The operator reported the Concierge `/soleur:go #4826` flow "still failing despite all fix attempts" — the agent kept landing in a `/workspaces/<id>` with no git checkout (`fatal: not a git repository`), and `go.md` Step 0.0 honest-stopped. Multiple prior PRs (#5409, #5435, #5546, #5580 — all ADR-044 self-heal/resolver hardening) had targeted this exact symptom and it persisted.

Two distinct traps surfaced:

1. **All prior fixes patched CODE; the operator's failure was residual DATA.** The self-heal/resolver code was correct per-workspace. The active workspace `754ee124` was DB-`ready` and recently synced, but its on-disk clone got reclaimed and the WARM dispatch path re-cloned fire-and-forget (`cc-dispatcher.ts:2899`), racing the sandbox `chdir`. The cold path awaits the clone; the warm path did not. A code timing-gap — invisible to every "is the resolver correct?" fix.

2. **A 10-day-old tracking issue's premise was stale and would have caused a destructive mistake.** Issue #5591 documented the operator owning "TWO 'My Workspace' rows … both connected to the same repo `jikig-ai/soleur`" and suggested de-duplication. Acting on that snapshot, the chosen remediation was "de-dup the duplicate row." Pulling LIVE prod data first showed the two workspaces now point at **different** repos (solo→`chatte`, active→`soleur`) in different orgs — de-duplicating would have **destroyed a real workspace**.

## Solution

- Matched the concrete failing id from the debug stream (`/workspaces/754ee124-…`) against open issues → found #5591 naming that exact id. The id is the highest-signal join key between a symptom and its tracking issue.
- **Pulled live prod data myself** (`hr-no-dashboard-eyeball-pull-data-yourself`) via Doppler `prd` + Supabase REST (psql absent; service-role key in-env, never argv) instead of trusting #5591's snapshot → premise was stale → **stopped the de-dup**, corrected #5591, and re-scoped to the real code bug.
- Filed the real bug (#5715: warm-dispatch fire-and-forget re-clone race) and fixed it: gate the warm dispatch on the re-clone the way the cold path already does, with the `.git` short-circuit hoisted into `reprovisionWorkspaceOnDispatch` so one membership-verified resolve feeds both the stat and the clone (LEADER precedent `agent-runner.ts:1148`).

## Key Insight

When a symptom "keeps failing despite fixes," the fixes and the failure may be in **different layers**: if every prior fix touched code in subsystem A and the failure persists, suspect residual DATA / a sibling layer (here: a warm-vs-cold timing path the cold-path fixes never covered). And when a tracking issue proposes a **destructive** remediation (de-dup/delete) from a captured snapshot, that snapshot is a hypothesis — re-verify it against live state before acting, because "what you find contradicts how it was described → surface that, don't proceed." The concrete failing id is the cheapest join key from symptom → issue.

## Session Errors

- **`subagent_type:"fork"` no-op'd a delegated implementation** — returned in ~9s with 0 tool uses and a confabulated "implementation is running in a background fork" echo, doing no actual work. **Recovery:** verified the worktree was untouched (`git log`/`status`), re-launched as `general-purpose` (68 tool uses, real commits). **Prevention:** for multi-step implementation, prefer `general-purpose` over `fork`; always verify a delegated agent produced the expected commits/files before trusting its summary (a clean-looking final message is not proof of work).
- **`psql` not installed** when querying prod Supabase. **Recovery:** Supabase REST API via curl with the service-role key kept in the Doppler-injected env. **Prevention:** in this repo, reach prod Postgres via Supabase REST (service-role) or `pg` under `doppler run`, not bare psql.
- **Guessed `owner_id` column on `workspaces`** (doesn't exist). **Recovery:** queried by `id` and `select=*` to discover the real schema. **Prevention:** `select=*` one row first to learn the shape before filtered queries.
- (Forwarded) plan-file linter reformat race during deepen — handled by re-reading before continuing.

## Tags
category: bug-fixes
module: web-platform/concierge-dispatch
related: "[[2026-06-14-short-circuit-guard-must-sit-after-the-recovery-it-gates]]"
issues: "#5715 #5591 #4826"
