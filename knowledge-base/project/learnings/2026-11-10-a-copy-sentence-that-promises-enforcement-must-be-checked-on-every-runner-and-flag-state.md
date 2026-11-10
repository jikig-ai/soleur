---
title: A copy sentence that promises enforcement must be checked on every runner and every flag state
date: 2026-11-10
category: workflow-issues
tags: [copy-accuracy, approval-queue, legal-records, closed-set-tests, review]
issue: '#12197'
pr: '#12567'
---

# Learning: a copy sentence that promises enforcement must be checked on every runner and every flag state

## Problem

PR #12567 replaced three false "agents can't push to git remotes" sentences with `PUSH_DISCLOSURE`, whose last clause
says "nothing is pushed that way unless the workspace owner approves that push". The work phase checked that clause
against the durable approval gate only. Two review seats found that on the older ("legacy") leader runner, when the
approval flow gives no verdict (the `approval-queue` flag off or unreadable for that workspace, or no dependency wired),
`permission-callback.ts` fell through to the in-memory `review_gate` card sent to the session's own user. A member
could approve their own push. The sentence was true at merge (flag ON everywhere) and would turn false at the operator's
planned narrowing of the flag.

The same PR re-anchored ADR-319's PR-C "Enabling conditions" from "before the flag goes on" to "before a founder id is
configured in production" and called that "the reading the 2026-11-09 addendum already applies". It did not: the founder
id was already set, so every condition became due at once, and two (counsel's retention decision, the Supabase single-session
check) had no recorded status.

## Solution

- D1 (CTO ruling): `github_push_branch` on the legacy fallback now requires the workspace Owner. The role is read with a
  5 s deadline and abort handling; a member, a failed or timed-out read, or a missing dependency gets the static deny with
  no card, no status write and no notification, each with a `sec: true` log; the failed read and the missing dependency
  also emit a Sentry op (`viewerRoleFailed`, `gateFailed` stage `wiring-absent`). Other approval-required tools keep the
  in-memory card (narrow scope, pinned by a test). Mutation: neutralizing the `role !== "owner"` deny reds 5 tests.
- D2 (CTO/CLO ruling): the amendment states each enabling condition with its measured status ((1) to (4)) instead of
  claiming it already applies. The CTO agent measured `sessions_single_per_user: false` read-only (the separate
  `mailer_otp_exp: 600` reading belongs to decision row R9).
- Copy tests: the ON block, the dialog and the Scope Grants callout are asserted as the exact array of their text nodes
  (closed sets), not as `<p>` elements or keywords.

## Key Insight

A sentence that says "X cannot happen unless Y" is an enforcement claim. Before it ships, list every code path that can do X
(each runner, each flag state including "flag read failed", each missing-dependency state) and name the line that enforces Y
on each. A claim checked only on the path the PR is about is a claim about that path, not about the product.

When a gate moves (flag to founder id), every condition anchored on the old gate is due at the moment the new gate is
already open. Write each condition with a status, never "already applies".

## Session Errors

1. **Issue-filing hook rejected `gh issue create` three times** (needed `--milestone`, User-Impact/Fix-Size/Mandated-By
   lines, a literal absolute `--body-file`). Recovery: added them. **Prevention:** already hook-enforced; draft the body
   file from the hook's template first.
2. **`sleep` wait and `pgrep -f` blocked by hooks.** Recovery: used Monitor / avoided pgrep. **Prevention:** already hook-enforced.
3. **Technical-ruling gate rejected the first decision-record draft.** Recovery: reshaped rows (34 PASS). **Prevention:** none needed (gate worked).
4. **markdownlint failures on new records.** Recovery: fixed. **Prevention:** run markdownlint on touched `.md` before commit.
5. **New test fixtures lacked `grants`** ("Cannot read properties of undefined (reading 'enforcing')"). Recovery: `new ExecutionGrants()`.
   **Prevention:** copy fixture deps from `test/approval/fixtures` rather than hand-building them.
6. **An LIA quote was written as a literal `\"`.** Recovery: plain quotes. **Prevention:** grep the diff for `\\"` in `.md` before commit.
7. **A copy-test anchor (`border-soleur-accent-gold-fg`) was stripped by the test's own string normaliser.** Recovery:
   re-anchored on `{PUSH_DISCLOSURE}`. **Prevention:** before anchoring, ask what the normaliser removes.
8. **A mutant edit was syntactically invalid, so the run reported "no tests" and read like a kill.** Recovery: rewrote it as
   valid code. **Prevention:** a mutant counts as killed only when the suite ran and an assertion failed; read the test count.
9. **The audit record's hash-range check first matched a prose mention of "## Ruling 3", not the heading line.** Recovery:
   re-verified from the heading line (unchanged). **Prevention:** anchor range checks with `^## Ruling 3$`.
10. **Playwright install hung on a stale `__dirlock`.** Recovery: used the cached chromium-1208. **Prevention:** check the
    browser cache before installing (qa browser-preflight).
11. **`PUSH_DISCLOSURE`'s owner-approval clause was checked against one runner only (D1).** Recovery: owner gate on the
    legacy fallback in the same PR. **Prevention:** plan sharp edge (routed): enumerate every runner and flag state for an
    enforcement claim in copy.
12. **The ADR-319 amendment claimed the re-anchoring "already applies" (D2).** Recovery: per-condition statuses.
    **Prevention:** a re-anchored condition list states each condition's status.
13. **Phone-width QA of the Scope Grants disclosures was not measurable** (mock Supabase has no `workspace_members` handler).
    Recovery: filed #12605. **Prevention:** tracked in #12605.
14. **A long local affected-test run duplicated CI; the operator stopped it.** Recovery: relied on PR CI. **Prevention:** once
    the targeted suites pass locally, let PR CI run the affected set.

## Tags

category: workflow-issues
module: apps/web-platform/server/permission-callback.ts, apps/web-platform/lib/web-egress-disclosure.ts, ADR-319
