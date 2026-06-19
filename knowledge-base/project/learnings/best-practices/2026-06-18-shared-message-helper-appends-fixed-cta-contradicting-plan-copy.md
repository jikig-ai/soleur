---
date: 2026-06-18
category: best-practices
module: web-platform/concierge-dispatch
tags: [code-review, user-impact, copy, repo-readiness, adr-044]
related_pr: 5546
---

# Learning: A shared message-framing helper that appends a fixed CTA silently contradicts a plan that promises a different CTA

## Problem

The fix for the Concierge "no git repository" dispatch bug (membership-deny NULL
install → fail honestly instead of spawning a repo-less agent) had a central UX
claim in its plan: replace the **unactionable** "Reconnect in Settings →
Repository" CTA with a **membership-deny-aware** message ("ask the workspace
owner to confirm the connection"), because a recently-joined member cannot fix a
membership-gated credential read by reconnecting.

The implementation built that membership-deny-aware reason and then framed it
via the existing `repoErrorMsg(reason)` helper — which unconditionally appends
`". Reconnect in Settings → Repository."`. The rendered string therefore became:

> Repository setup failed: we couldn't verify your access… ask the workspace
> owner to confirm the connection. **Reconnect in Settings → Repository.**

i.e. it re-introduced the exact CTA the fix existed to remove. tsc + the unit
tests passed (they asserted only `errorCode` and zero-write counts, never the
rendered `message`), so the contradiction was invisible to every
implementation-side gate.

## Solution

Return a standalone `CONNECTION_UNRESOLVED_MESSAGE` constant directly as the
`RepoReadiness.message` — do NOT route it through `repoErrorMsg` — and add a
test asserting `r.message` contains the membership-deny copy AND does NOT contain
`"Reconnect in Settings"`. Caught by `user-impact-reviewer` (fired by the plan's
`single-user incident` brand-survival threshold); fixed inline (`d5edf4e00`).

## Key Insight

When a fix's whole point is to **replace** a specific piece of user-facing copy
(a CTA, an error suffix, a banner), do not route the replacement through a shared
formatter that re-adds the thing you're replacing. Shared message helpers
(`repoErrorMsg`, toast builders, error envelopes) frequently append a fixed
prefix/suffix; reusing one "for consistency" can silently re-stamp the very copy
the change set out to delete. Two cheap guards:

1. **Assert the rendered string, not just the structured fields.** A test that
   checks `errorCode === "repo_setup_failed"` but never reads `message` cannot
   catch a wrong CTA. Add one `expect(message).not.toContain(<old CTA>)`.
2. **When a plan promises copy-X-replaces-copy-Y, grep the helper you're about to
   reuse for Y before reusing it.** If the helper hard-codes Y, write a standalone
   message instead.

This is the copy-layer analogue of "reusing a helper drags its side effects" —
here the side effect is an appended sentence, and the blast radius is a
single-user workflow dead-end.

## Session Errors

1. **`"File has not been read yet"` Edit failures (×3) on worktree files.**
   Recovery: Read the worktree-absolute path (`<worktree>/apps/web-platform/...`)
   before editing. Prevention: the harness tracks file-read state per absolute
   path — viewing a file via `git show main:<path>`, Bash `sed`, or grep does NOT
   satisfy the read-before-edit gate; always Read the exact worktree path you
   intend to Edit. (Recurring but harness-enforced; no rule/hook change needed.)
2. **Reused `repoErrorMsg` whose fixed CTA suffix contradicted the plan's copy
   claim.** Recovery: standalone message constant + a `not.toContain` assertion.
   Prevention: see Key Insight; already covered by review's `user-impact-reviewer`
   gate on `single-user incident` plans (it enumerated the rendered string and
   flagged the contradiction).

## Tags
category: best-practices
module: web-platform/concierge-dispatch
