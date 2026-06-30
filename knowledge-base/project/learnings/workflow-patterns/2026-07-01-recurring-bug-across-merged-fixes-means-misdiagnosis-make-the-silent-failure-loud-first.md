---
title: "A bug that recurs across multiple merged fixes is a mis-diagnosis, not an incomplete fix — make the silent failure loud before fixing again"
date: 2026-07-01
category: workflow-patterns
tags: [investigation, observability, concierge, clone, silent-failure, diagnosis, operator-context]
issues: ["#5733", "#5790"]
---

# Recurring-across-fixes ⇒ mis-diagnosis. Surface the silent failure before fixing again.

## Problem

Workspace `754ee124`'s `/soleur:go` stranded on `not a git repository` across **five**
merged+deployed server-side fixes (#5716, #5584, #5730, #5734, #5790). Each fix targeted
a plausible mechanism (reconcile heal, N-co-owner tolerance, rev-parse confirm). None
worked. In a single session I mis-diagnosed it **twice more** before reaching the real
shape: (1) "corrupt `.git`" (H2 — shipped #5790, didn't heal); (2) "ambiguous-founder for
>1 solo workspace" (a red herring — that Sentry op stopped firing 06-29 and never writes
`repo_last_synced_at`); before live forensics narrowed it to **the agent dispatches into a
repo-less `/workspaces/754ee124`** whose in-process clone outcome is **silently swallowed**.

## Key insights

1. **A bug that survives N merged fixes is almost always a MIS-DIAGNOSIS, not an
   incomplete fix.** Stop shipping server-side fixes against code-reading. The repeated
   "still happening" is the signal to pull **live exec-path evidence** (prod Supabase +
   Sentry, read-only) and to confirm the fixed code path actually executes on the
   affected surface — every prior fix emitted **zero events** on the agent surface, which
   alone should have reframed the search far earlier.
2. **Ask the operator about prior recovery attempts EARLY.** The decisive fact — *"reconnect
   (`/api/repo/setup` wipe-and-reclone) has NEVER landed the repo"* — reopened the
   clone-path/filesystem hypothesis that an earlier plan had wrongly dismissed from
   deploy-config reading. I learned it only **after** shipping a non-fix (#5790). One
   question ("does reconnect work?") would have saved a full one-shot cycle. When a
   recovery action is assumed to work, verify it with the operator before building on it.
3. **When you have ZERO telemetry, the highest-value first move is to make the silent
   failure LOUD — not to guess the fix.** The root reason five fixes were undiagnosable:
   the cold dispatch path *already* clones in-process at `cc-dispatcher.ts:1987`, but its
   outcome was **discarded**. A swallowed result on the one path that matters turns every
   downstream symptom into a guessing game. Surfacing it (a distinct `repo_clone_failed`
   event + honest-block + an absent-`.git` `agent_readiness_self_stop`) converts an
   undiagnosable silent strand into a one-shot-to-the-real-cause signal. Ship the
   instrumentation, get the named signal, THEN fix — instead of a 6th speculative fix.
4. **`repo_status='ready'` in the DB is NOT on-disk truth.** `754ee124` was `ready` /
   `repo_error=null` with `repo_last_synced_at` frozen at 06-29 while the agent's disk had
   no repo. `repo_last_synced_at` only advances when the agent's *own* in-workspace
   `git pull/push` runs (`session-sync.ts`) — so a frozen timestamp is a SYMPTOM of the
   strand (the agent never syncs because it strands), not proof reconcile skipped it.
   Never trust a DB readiness flag over the on-disk reality; gate clones on the actual
   `.git` presence.
5. **In-process clone + same-process bwrap cwd cannot diverge by construction.** Both the
   clone target and the agent `query()` cwd resolve to the identical
   `workspacePathForWorkspaceId(id)` string in the same Node process, and bwrap binds that
   host dir — so the cold-path "clone lands where the agent can't read it" hypothesis is
   ruled out *in-process*. A remaining divergence can only be the out-of-process Inngest
   reconcile worker on a different replica/mount (a real but separate, infra-layer
   concern). Trace path resolution before asserting filesystem divergence.

## Session Errors

1. **Shipped #5790 (H2 corrupt-`.git` fix) before confirming the failure mode** — it
   deployed cleanly but didn't heal; the live `agent_readiness_self_stop` op was still
   zero post-deploy. **Recovery:** pulled live Supabase+Sentry, found the repo is *absent*
   not corrupt. **Prevention:** for a "still happening" P1, confirm the on-disk `.git`
   shape (or its observable proxy) BEFORE designing the fix; don't infer the shape from
   `repo_status`.
2. **Didn't ask about reconnect's history until very late** — assumed reconnect would
   unblock and even advised it. **Prevention:** ask the operator "has <recovery action>
   ever worked?" before building a fix on the assumption it does.
3. **Transient API rate-limits + a session usage limit** interrupted background planning/
   implementation agents mid-run (zero-token deaths). **Recovery:** re-resumed each agent
   via SendMessage after backoff; verified on-disk artifacts (commits, plan edits) to
   resume from the real state rather than re-running. **Prevention:** on a background-agent
   rate-limit/limit death, check committed artifacts before re-spawning; resume, don't
   restart.
