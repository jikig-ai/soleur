---
title: "A comment placed between grouped case labels fires `no-fallthrough` — annotate inside the block or the lint ratchet counts it"
date: 2026-10-05
category: test-failures
tags: [eslint, no-fallthrough, ws-client, lint-ratchet, case-labels]
pr: 9535
related:
  - knowledge-base/project/learnings/2026-08-17-i-corrected-a-fabricated-claim-by-grepping-its-phrasing-and-missed-a-site.md
---

# A comment placed between grouped case labels fires `no-fallthrough`

## Problem

While documenting why `workflow_ended` needs no in-arm unmapped-status warn
(`apps/web-platform/lib/ws-client.ts` grouped `stream_event` case arm), a
7-line comment was inserted *between* `case "workflow_started":` and
`case "workflow_ended":`. ESLint's `no-fallthrough` treats a case segment
carrying a non-`falls through`-pattern comment as occupied, so the clean-looking
comment added a third warning on top of the file's existing two — enough to
grow the `eslint-config.test.ts` per-rule ratchet baseline.

The trap is invisible locally unless you compare warning counts against the
unmodified file: `eslint` exits 0 either way (warnings, not errors), and the
findings *look* pre-existing at a glance because the file already carries two.

## Solution

Place coverage/explanatory comments **inside the case block** (after the `{`)
rather than between labels, or phrase them to match the fallsThrough pattern
(`falls? ?through`) — the former is clearer. Baseline-check by linting the
same file on `origin/main` via stdin:

```bash
git show origin/main:<path> | ./node_modules/.bin/eslint --stdin --stdin-filename <path>
```

A grown warning count on a touched file is a real signal even when `rc=0`.

## Session Errors

1. The comment-between-labels trap itself (above) — caught by diffing eslint
   output against the `origin/main` baseline, not by any gate.
   **Prevention:** annotate inside the block; baseline-compare warnings on
   touched files, don't rely on exit code.
2. Stale Playwright `__dirlock` (~/.cache/ms-playwright) blocked
   `playwright install chromium`; the pinned `chromium_headless_shell-1208`
   was already cached and headless runs resolve it — `rm` the lock and try
   the run before installing.
   **Prevention:** check `node_modules/playwright-core/browsers.json` revision
   against `ls ~/.cache/ms-playwright` before assuming an install is needed.
3. Corrected the *flagged* stale citation (`ws-client.ts:791-806` at e2e:267)
   but a fix-round verifier found the identical wrong range twice more in the
   same file (:22, :239). Same defect class as the #7539/#7826 subject-sweep
   learnings: grep the claim's SUBJECT (the `791-806` range token), not just
   the reported line.
   **Prevention:** when a finding names a wrong citation, grep the cited
   token across the whole file before committing the fix.
4. A background deepen-plan subagent pushed a stray planning commit and then
   force-with-lease'd the rewritten chain (`030f4c8c4f`); reconciled by
   verifying local ⊇ remote before pushing the implementation commit.
   **Prevention:** before pushing after a concurrent agent ran, diff
   `HEAD` vs `origin/<branch>` and confirm the remote tip is an ancestor.
5. Forwarded from the plan phase (`session-state.md`): `cloud-detect`
   `not-local` (nonfatal), one markdownlint MD004, and no Task/subagent
   spawn surface → sequential-fallback, disclosed in plan body.
   **Prevention:** covered by session-state forwarding; no new action.

## Key Insight

Comment-only diffs are not lint-neutral: in grouped `case` arms the comment
position determines whether `no-fallthrough` fires, and the one-sided ratchet
turns a warning-count regression into a merge blocker. Baseline-diff the
warning count, not just the exit code.

## Tags

eslint, no-fallthrough, comment-placement, lint-ratchet, ws-client
