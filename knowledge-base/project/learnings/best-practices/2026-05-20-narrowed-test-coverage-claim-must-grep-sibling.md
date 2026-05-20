---
title: When narrowing a test with a "covered by sibling" claim, grep the sibling first
date: 2026-05-20
category: best-practices
component: review/test-design
problem_type: documentation_defect
status: solved
related:
  - knowledge-base/project/learnings/2026-05-11-multi-agent-review-catches-cross-artifact-contract-drift.md
github_issues:
  - 4108
  - 4113
related_prs:
  - 4157
tags:
  - test-coverage
  - cross-artifact-claim
  - security-sentinel
  - narrow-assertion-fix
---

# Learning: Narrowed test coverage claim must be verified against the named sibling

## Problem

PR #4157 narrowed `action-sends-worm.test.ts` row (h) to assert only the
DB-layer contract of `anonymise_action_sends` (Art-17 erasure), dropping
the trailing `auth.admin.deleteUser` assertion. The narrowed test's header
comment claimed:

> `(h) anonymise_action_sends(uuid) → action_sends.user_id IS NULL + recipient_id_hash '__anonymised__' (Art-17 erasure; cascade integration covered by account-delete-scope-grants-cascade.test.ts)`

The claim was load-bearing — it justified dropping the cascade-position
assertion ("the other test covers it"). But `account-delete-scope-grants-cascade.test.ts`
asserted ordering for `anonymise_scope_grants`, `anonymise_tc_acceptances`,
and `auth.admin.deleteUser` only. `anonymise_action_sends` was not
named in `rpcNames` or `callOrder`, even though production
`server/account-delete.ts:211` invokes it as the FIRST FATAL step in the
cascade. Post-narrow, no test asserted that `deleteAccount` invokes
`anonymise_action_sends` in cascade position.

The claim was false; the coverage gap was real.

## Root Cause

When a test is narrowed by dropping cross-component assertions, the author
typically writes a pointer comment ("the other test covers this") to
prevent future re-coupling. The pointer is asymmetric: the file being
narrowed advertises the relationship; the named sibling has no reason to
know it's been load-bearing-cited. Pointer comments thus drift silently
when the named sibling's coverage doesn't match the citation.

Plan-time analysis can claim "cross-cascade integration is already
covered by X" without grepping X. The claim feels true when the sibling
test file's NAME matches the broad domain (cascade test → presumably
asserts cascade ordering). The verification step — does the sibling
actually call out the specific primitive being dropped from this test? —
is easy to skip.

## Solution

security-sentinel caught the gap by re-reading
`account-delete-scope-grants-cascade.test.ts` and running
`grep -n anonymise_action_sends`. Zero hits → claim invalid.

Fix (PR #4157 commit `e7288b02`): extend the cascade mock test to add
`anonymise_action_sends` to its `rpcNames`, `callOrder`, and ordering
assertions:

```ts
expect(rpcNames).toContain("anonymise_action_sends");
expect(rpcNames.filter((n) => n === "anonymise_action_sends").length).toBe(1);

const idxActionSends = callOrder.indexOf("anonymise_action_sends");
const idxScope = callOrder.indexOf("anonymise_scope_grants");
expect(idxActionSends).toBeLessThan(idxScope); // FK order: action_sends.grant_id → scope_grants(id)
```

Also updated the cascade test's header comment to reflect the 4-RPC
sequence (was 3-RPC) and added the FK rationale for the
`anonymise_action_sends → anonymise_scope_grants` ordering.

## Key Insight

A "covered by sibling" claim in a test header comment is the same defect
class as the documented "self-claimed cross-artifact contract drift"
pattern (see `2026-05-11-multi-agent-review-catches-cross-artifact-contract-drift.md`),
applied to test files. The pointer comment IS a self-claim of
cross-file fidelity.

Verification protocol when narrowing a test with a sibling-coverage claim:

1. **Identify the dropped primitive** — the RPC, route, schema field, or
   invariant the narrowed test no longer asserts.
2. **Grep the named sibling for that primitive** —
   `grep -n '<primitive>' <sibling-test-path>`. Zero hits = claim invalid.
3. **If the sibling doesn't cover it:** either extend the sibling (close
   the real gap) or revise the comment (acknowledge the residual gap and
   file a follow-up). Do not ship a false claim.

This applies at both plan time (when the plan body cites the sibling) and
implementation time (when the header comment is written). The grep is
cheap; the gap is real.

## Prevention

- **review-skill rule (already exists):** the
  `2026-05-11-multi-agent-review-catches-cross-artifact-contract-drift.md`
  pattern is documented in `plugins/soleur/skills/review/SKILL.md` under
  "Self-claimed cross-artifact contract drift". This learning is a
  concrete instance applied to test files — no new rule needed.
- **security-sentinel prompt:** when a PR narrows a test row's
  assertion path and the new comment names a sibling test as the
  coverage owner, the agent must grep the sibling for the
  dropped primitive(s) and report mismatch as a finding.
- **Plan-time check:** if a plan's "Research Reconciliation" table cites
  a sibling test file as coverage for a dropped assertion, include
  `git grep -n '<primitive>' <sibling-path>` as the verification command
  in the same row.

## Session Errors

**Bash CWD reset across calls** — After `cd apps/web-platform && tsc ...`,
the next Bash call defaulted to the bare repo root instead of the
worktree. Recovery: re-cd with the worktree-absolute path.
Prevention: already covered by existing learning
`2026-04-19-admin-ip-drift-misdiagnosed-as-fail2ban.md` (Bash CWD does
not persist). No new rule needed.

**Multi-line vitest expect with assertion-message label broke awk
per-line AC grep** — When adding `expect(value, "label").toBe(...)` with
the label formatted across multiple lines, the AC's
`grep -E 'recipient_id_hash.*__anonymised__'` (which awk feeds one line
at a time) dropped from 2 hits to 1. Recovery: collapse to single-line
expect format. Prevention: when adding vitest assertion-message labels
to a test row whose AC grep depends on per-line patterns, keep the
expect on a single line; or update the AC to use multi-line aware
matching (e.g., `grep -Pzo`).
