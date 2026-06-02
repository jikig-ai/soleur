---
title: "A Sentry alert's named op is not the user's actual failure; and a NOT-NULL+RLS column add must sweep every INSERT site"
date: 2026-06-02
category: bug-fixes
module: apps/web-platform (cc-dispatcher, agent-runner, messages RLS)
tags: [rls, workspace_id, write-boundary-sweep, cc-dispatcher, agent-runner, misdiagnosis, sentry, silent-fallback, migration-059]
issues: []
prs: [4816, 4831]
---

# Two compounding lessons from the "An unexpected error occurred" chat outage

## Problem

A user reported "I tried running a new conversation in the webapp but it failed" with
the generic bubble **"An unexpected error occurred. Please try again."** The Sentry
alert in hand was `kb-chat silent fallback`, op `history-fetch-404-not-owned-or-missing`
on `GET /api/conversations/{id}`.

## What went wrong first (the misdiagnosis)

PR #4816 fixed the **history-fetch 404**: a fresh deferred conversation fired an
unconditional history fetch against a not-yet-created row → 404 + error-level Sentry
noise. That was a real defect — but it was **not the user's outage**. The user's
actual failure surfaced on message **send** (an error bubble *after* typing), not on
conversation **open**. The user retried and hit the same wall.

The real bug: migration `059_workspace_keyed_rls_sweep` made `messages.workspace_id`
`NOT NULL` and changed the INSERT policy to
`WITH CHECK (is_workspace_member(workspace_id, auth.uid()))`. Every **interactive**
`messages` INSERT site omitted `workspace_id` → NULL → predicate false → RLS reject →
`cc-dispatcher.ts` threw `Failed to save user message` → `sanitizeErrorForClient`
returned the generic bubble. Service-role cron inserts bypass RLS, so background writes
kept working and masked the outage for ~3 weeks (last interactive message saved
2026-05-11).

## Solution

Populate `workspace_id` on every interactive `messages` INSERT, derived from the
**parent conversation's** `workspace_id` (NOT `resolveCurrentWorkspaceId`, the
session-selected workspace, which can mis-attribute for a multi-membership operator).
Four sites: cc-dispatcher user row + assistant row (via `buildRow`), agent-runner
`saveMessage` + `sendUserMessage`. The conversation row is already
ownership/membership-gated by its own RLS, so its `workspace_id` is guaranteed to
satisfy the messages WITH CHECK. Plus a source-grep sweep test (with a non-vacuous
negative control) over every `.from("messages").insert` so a future site that omits
`workspace_id` fails CI.

## Key insights

1. **A Sentry alert's named op is a clue, not a verdict.** The op the alert names
   (`history-fetch-404`) was a *real but secondary* signal. The user-visible symptom
   (generic bubble on message SEND) had a *different* producer (error-sanitizer
   fallback ← dispatch catch ← RLS reject on the write path). Trace the user-visible
   symptom to its actual producer and check Sentry at the **actual interaction
   timestamp** (here, 19:06:18Z = the user's 21:06 local send), rather than fixing the
   op the alert happened to surface.
2. **Noise reduction has diagnostic value.** PR #4816 downgrading the expected-404
   from `error` to `warning` is what let the *real* error
   (`Failed to save user message: new row violates row-level security policy`) surface
   above the noise floor in Sentry. Killing benign error-level events is not just
   hygiene — it unmasks the regressions that were drowning.
3. **A migration that adds a NOT NULL + RLS-gated column must sweep EVERY writer in the
   same change.** `059` backfilled existing rows and set the policy but never updated
   the application INSERT sites. The write-boundary-sweep + a grep-guard test
   (`hr-write-boundary-sentinel-sweep-all-write-sites`) is the mechanical defense; the
   service-role-bypass exemplar (`insert-draft-card.ts`) is why the gap stayed hidden.

## Session Errors

1. **Misdiagnosis: fixed the alert's named op, not the user's failure (PR #4816 →
   #4831).** Recovery: after the user re-reported, pulled Sentry issues at the real
   send timestamp, found the RLS write error, traced it to the un-swept INSERT sites.
   **Prevention:** when a fix targets a Sentry op, confirm that op IS the user-visible
   failure by tracing the symptom (which UI action produces it) to its code producer
   before shipping; a partial-noise fix that leaves the core path broken is worse than
   no fix because it consumes a full pipeline. (Relates to the work-skill
   symptom-root-cause-trace rule.)
2. **CWD-relative path drift across Bash calls.** Recovery: absolute `cd <abs> && cmd`.
   **Prevention:** already covered by the `/work` rule "chain `cd <worktree-abs-path>
   && <cmd>` in a single Bash call" — no new rule.
3. **(Forwarded) No Task subagent tool in the planning delegation** — deepen ran
   inline; substance equivalent. Not a defect.

## References

- `apps/web-platform/supabase/migrations/059_workspace_keyed_rls_sweep.sql:94,106-108`
- `apps/web-platform/server/cc-dispatcher.ts`, `apps/web-platform/server/agent-runner.ts`
- `apps/web-platform/server/error-sanitizer.ts:79` (the generic-fallback producer)
- `apps/web-platform/test/server/messages-insert-workspace-id-sweep.test.ts` (grep-guard)
- [[2026-05-05-cc-dispatcher-assistant-persistence-asymmetry]], [[2026-05-12-type-widening-cascades-and-write-boundary-sentinels]]
- Prior adjacent PR #4816 (history-fetch 404 noise — fixed the wrong layer)
