---
title: "Adding a shape/format guard to a widely-DB-sourced id has a large test-fixture blast radius; syntactic SAST rules can't see throw-guards"
date: 2026-06-15
category: best-practices
module: apps/web-platform/server/workspace-resolver.ts
issue: 5344
pr: 5352
tags: [security, cwe-22, test-fixtures, semgrep, scope-estimation, uuid-validation]
---

# Learning: id-shape guard blast radius + syntactic-SAST blind spot

## Problem

Issue #5344 asked for a CWE-22 defense-in-depth UUID-shape guard on
`workspacePathForWorkspaceId` / `resolveWorkspacePathForUser` (throw before
`join(getWorkspacesRoot(), workspaceId)`). The plan estimated **"~6–10 lines, 1
source file + 1 test file."** Reality: the guard's stricter contract THREW on
the test suite's pervasive short non-UUID fixtures (`"user-1"`, `"ws-A"`,
`"ws-orphan"`, `ACTIVE_WS_ID="team-workspace-99"`, and `mkdtempSync` basenames
read back as `workspace_id` via `path.basename`). **~34 test files / ~136 tests
broke** — a 34× scope expansion the plan never sized.

Separately, the plan's acceptance criterion **"semgrep `path-join-resolve-traversal`
returns 0 findings (down from 3)"** was unachievable: that rule is a purely
*syntactic* matcher (`join($X, …)`) with no taint/dataflow, so it cannot
recognize the upstream `UUID_RE.test()` throw as a sanitizer. It still reports
the 3 `join()` lines — and the already-shipped, already-guarded precedent
`workspace.ts` trips the **same rule 13×**. The AC was a false premise.

## Solution

1. **Keep the strict UUID allowlist (do not weaken the security control to make
   tests pass).** The plan deliberately chose the allowlist over a denylist
   (CPO-signed, mirrors `workspace.ts:67` precedent). Test breakage is a signal
   that fixtures were *unrealistic* — real `workspace_id` is always a UUID (N2:
   `workspace_id === user_id`). Per `cq-test-fixtures-synthesized-only`, the fix
   is realistic fixtures, not a looser guard.
2. **Centralize the fixture pattern.** Added `test/helpers/workspace-tmpdir.ts`
   (`makeUuidWorkspaceTmpdir`) for the mkdtemp-basename cluster; swapped short id
   literals to fixed UUID literals everywhere else, keeping distinct ids distinct
   (the `divergentId` and `owner-A/B`/`ws-A/B` parity tests must NOT collapse).
3. **Report the SAST outcome honestly.** The CWE-22 vector IS closed by
   throw-before-join; the diff introduces **0 net-new** findings (custom rules +
   p/js + p/ts = 0); the `join()` lines are byte-unchanged from main, so a
   baseline/diff-aware CI scan shows 0 net-new. "0 absolute findings" is the
   wrong AC for a syntactic rule.

## Key Insight

- **A shape/format guard on an id that is read from the DB and flows through a
  shared resolver has a test-fixture blast radius proportional to how many tests
  fabricate that id with a convenient short literal.** Before estimating scope
  for such a guard, grep the fixture surface:
  `git grep -nE '"(user-1|ws-[A-Za-z0-9]|owner-[A-Z]|[a-z]+-workspace)"' apps/web-platform/test/`
  and trace which hits flow into the guarded function. Size the sweep at plan
  time — don't discover it at GREEN.
- **Syntactic SAST rules (semgrep `path-join-resolve-traversal` and most public
  `join()`/`resolve()` matchers) do not model sanitizer guards.** Adding a
  throw-before-join closes the vulnerability but does NOT clear the rule. Never
  write an AC of the form "SAST rule X returns 0 findings after adding a guard"
  for a syntactic rule — assert "vulnerability closed + 0 net-new findings"
  instead, and confirm whether CI uses a baseline/diff-aware scan.

## Session Errors

1. **Plan scope estimate off by ~34×** (1 file → 34 files). Recovery: ran the
   full web-platform vitest suite to enumerate the real blast radius, then swept
   fixtures to UUIDs + added a shared helper. **Prevention:** plan-time
   fixture-surface grep for any id-shape/format guard on a DB-sourced id (routed
   to the plan/work Sharp Edges).
2. **Plan semgrep AC unachievable** (syntactic rule can't see the guard;
   precedent trips it 13×). Recovery: corrected the AC to "vuln closed + 0
   net-new"; confirmed 0 net-new via custom+p/js+p/ts. **Prevention:** review
   Sharp Edge — don't assert absolute-zero SAST counts for syntactic rules.
3. **(one-off)** A `vitest run … ; grep -c "Invalid workspaceId format"`
   compound command exited 1 because the final `grep -c` found 0 matches (the
   success case); briefly read as a vitest failure. **Prevention:** inspect the
   vitest summary line, not the compound command's trailing-grep exit code.

## Tags
category: best-practices
module: workspace-resolver
