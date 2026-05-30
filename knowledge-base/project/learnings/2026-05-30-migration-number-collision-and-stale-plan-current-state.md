---
title: Migration-number collision survives a malformed pre-check; plan-claimed current-state must be re-verified
date: 2026-05-30
feature: feat-skip-api-key-onboarding
pr: 4640
tags: [migrations, workflow, plan-drift, review]
---

# Migration-number collision + stale plan current-state (PR #4640)

Two workflow gaps surfaced during `feat-skip-api-key-onboarding`, both caught at
multi-agent review rather than at work-start.

## 1. A migration-number "collision check" that returns empty silently is NOT a clean check

At work-start I ran a pre-apply collision check to pick the next migration
number. The grep pipeline I used returned **empty** and I read that as "no
collision → 085 is free". It was malformed (wrong field/grep shape), so it
returned empty regardless of reality. `085_revoke_workspace_invitation.sql` had
already landed on `origin/main` via #4632 — 085 was taken. The collision was
caught by `data-integrity-guardian` at review, forcing a rename 085 → 086.

**Fix / rule:** Verify the next free migration number with the *verified* form
the review agent used, and treat an empty result as suspicious until proven:

```bash
git fetch origin main -q
git ls-tree origin/main --name-only apps/web-platform/supabase/migrations/ \
  | grep -oE '0[0-9]{3}_' | sort -u | tail -3
```

Confirm the chosen number does **not** appear, and sanity-check that the command
lists the migrations you *know* exist (084, 085, …). An empty/short list means
the command is wrong, not that the directory is clear. A piped `grep` over
`git ls-tree` that returns nothing is a false-clean class — assert the
expected-present case before trusting the absent case.

## 2. Plan-claimed "current code" is a precondition to verify, not a fact

The authoritative plan's **Phase 5** instructed: "drop ONLY the
`window.location.href` line in the `key_invalid` handler of `lib/ws-client.ts`."
At work-start I read the actual file: the `key_invalid` branch **already**
rendered an in-chat CTA and called `teardown()` — there was no
`window.location.href` to remove. The plan was authored days earlier against an
older `ws-client.ts`; the loop-break had since shipped independently. Phase 5
reduced to a regression test (behavioral teardown + a source-level negative-space
gate) instead of an edit.

**Fix / rule:** When a plan says "change line X in file Y" or quotes current
behavior, re-read Y at work-start. Plans describe a moving target; sibling PRs
land between plan-write and work-start. The plan is authoritative for *intent*
(break the loop), never for the *current state* (the redirect that no longer
exists). Same class as `hr-when-a-plan-specifies-relative-paths-e-g`.

## Bonus: prompt-vs-authoritative-plan design conflict

The invoking prompt described a role-gated onboarding *wizard*
(`shouldSkipApiKeyStep`, owners/admins always shown) whose files do not exist;
the authoritative plan described an effective-key redirect-gate design matching
the real codebase. Surfaced the conflict via `AskUserQuestion` before writing
code rather than silently picking one — the two designs diverge on observable
behavior (an owner with their own key: shown vs skipped).
