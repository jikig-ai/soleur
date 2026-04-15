---
module: Knowledge Base
date: 2026-04-15
problem_type: best_practice
component: testing_framework
symptoms:
  - "Pattern-match tests in kb-security.test.ts and csrf-coverage.test.ts failed after auth logic moved into shared helper"
  - "Three review agents flagged the initial test loosening (substring match on helper name) as too weak"
  - "Substring gate accepted dead imports, comment-only mentions, and routes that ignored the helper's {ok: false} result"
root_cause: missing_validation
resolution_type: test_fix
severity: medium
tags: [testing, negative-space, security-gates, helper-extraction, kb, code-review]
---

# Negative-Space Tests Must Follow Extracted Enforcement Logic

## Problem

PR #2235 extracted the CSRF/auth/workspace-status/path-validation boilerplate
from `apps/web-platform/app/api/kb/file/[...path]/route.ts` into a new
helper `apps/web-platform/server/kb-route-helpers.ts::authenticateAndResolveKbPath`.
Two negative-space tests broke immediately:

- `test/kb-security.test.ts` — scanned KB route files for inline
  `supabase.auth.getUser` and `workspace_status` substrings.
- `lib/auth/csrf-coverage.test.ts` — scanned all state-mutating API routes
  for inline `validateOrigin` substrings.

Both failed because the strings the tests scanned for had moved into the
helper. The quick fix — accept substring presence of
`authenticateAndResolveKbPath` — passed the tests but three review agents
(architecture, test-design, security) independently flagged that the new
gate was strictly weaker than what it replaced: substring match accepts
**dead imports**, **comment-only references**, and **routes that invoke
the helper but ignore the `{ok: false}` result**. A future KB route that
imports the helper and never calls it would pass the "auth check" test.

## Root Cause

When enforcement logic is extracted from route files into a shared helper,
three things must change in lockstep:

1. The route file loses its inline enforcement (expected and intentional).
2. The helper gains the invariants (done correctly here).
3. **The negative-space tests must migrate from "does the route mention
   the pattern inline?" to "does the route *prove* it delegates to the
   helper, AND does the helper itself still carry the invariants?"**

The third step was only half-done: the tests were loosened to accept
substring presence, but substring presence is not proof of delegation.

## Solution

Two-layer fix:

### Layer 1: Prove the delegation, don't just detect the import

Replace substring match with a pair of regex matches that require both an
**invocation** and a **failure early-return**:

```ts
// apps/web-platform/test/kb-security.test.ts (and csrf-coverage.test.ts)
const invokesHelper =
  /const\s+\w+\s*=\s*await\s+authenticateAndResolveKbPath\s*\(/.test(content);
const checksHelperResult =
  /if\s*\(\s*!\s*\w+\.ok\s*\)\s*return\s+\w+\.response/.test(content);
const delegatesToHelper = invokesHelper && checksHelperResult;
```

This fails the three previously-accepted broken patterns:

```ts
// Scenario 1: dead import — invokesHelper = false → test fails (correct)
import { authenticateAndResolveKbPath } from "@/server/kb-route-helpers";
export async function POST(req: Request) { /* no auth */ }

// Scenario 2: comment-only — both regexes fail → test fails (correct)
// TODO: migrate to authenticateAndResolveKbPath
export async function PATCH(...) { /* no auth */ }

// Scenario 3: ignored result — invokesHelper = true, checksHelperResult = false → test fails (correct)
const resolved = await authenticateAndResolveKbPath(req, params);
// forgot: if (!resolved.ok) return resolved.response;
```

For the `csrf-coverage.test.ts` variant, scope the delegation check to
`app/api/kb/` paths only so non-KB routes can't accidentally satisfy the
gate by mentioning the helper name:

```ts
const isKbRoute = relativePath.startsWith("app/api/kb/");
const delegatesToKbHelper = isKbRoute && invokesHelper && checksHelperResult;
```

### Layer 2: Add direct assertions on the helper itself

The security invariants moved with the code — the tests must follow:

```ts
// apps/web-platform/test/kb-security.test.ts
it("kb-route-helpers enforces path containment, symlink rejection, and null-byte guard", () => {
  const helper = resolve(__dirname, "../server/kb-route-helpers.ts");
  const content = readFileSync(helper, "utf-8");
  expect(content).toContain("isPathInWorkspace(fullPath, kbRoot)");
  expect(content).toContain("isSymbolicLink()");
  expect(content).toContain('includes("\\0")');
});
```

Without this second layer, a future refactor that removed one of the
invariants from the helper would pass every existing test.

## Key Insight

**Negative-space tests scan for textual patterns that correspond to
enforcement. When enforcement moves, the patterns must move with it — and
proof-of-usage must be tighter than proof-of-mention.**

Three questions to ask when extracting enforcement logic into a helper:

1. Do the tests that guarded the inline enforcement now have an equivalent
   assertion against the helper file? (If no, invariants can silently
   disappear from the helper.)
2. Does the route-level test prove the helper is **invoked** and its
   **failure result is respected** — not just that the identifier appears
   somewhere in the file? (If no, dead imports and ignored results pass.)
3. Is the delegation check **scoped** to the routes that should legitimately
   use the helper? (If no, non-KB routes could accidentally bypass CSRF by
   mentioning the helper name in a comment.)

Answering "yes" to all three requires the two-layer fix: structural regex
at the route level + direct assertions on the helper file.

## Why Not These Alternatives

| Alternative | Why not |
|-------------|---------|
| Delete the pattern-match tests entirely, trust types | Types don't enforce "auth happens before the mutation". A handler can import the helper's `{ok, ctx}` type and never call it. |
| Use AST-based parsing (`@typescript-eslint/parser`) | Correct long-term, but heavyweight for a negative-space gate. Regex is cheap, obvious, and catches the three failure modes above. Worth revisiting if the pattern becomes a source of false positives. |
| Brand the helper's return type (`type KbAuthGuard`) and require handlers to destructure it | Stronger but requires churning every handler's signature. Pragmatic regex gets 90% of the value for 5% of the cost. |
| Keep the inline `validateOrigin` / `supabase.auth.getUser` duplicated across routes | Defeats the entire purpose of #2180's helper extraction. |

## Cross-References

- Related (typed error migration without forking conventions):
  [`2026-04-14-atomic-webhook-idempotency-via-in-filter.md`](../integration-issues/2026-04-14-atomic-webhook-idempotency-via-in-filter.md)
  — same "don't introduce a second class when one already exists" pattern.
- Related (pure reducer extraction requires companion-state migration):
  [`2026-04-14-pure-reducer-extraction-requires-companion-state-migration.md`](2026-04-14-pure-reducer-extraction-requires-companion-state-migration.md)
  — extraction refactors have the same "migrate everything or migrate
  nothing" shape.
- PR: #2235
- Closes: #2149, #2150, #2180, #2245
- Follow-up tracking: #2244 (upload route adopt `syncWorkspace`), #2246
  (15 low-severity polish items grouped), plus #2244's agent-tool registration
  for KB rename.

## Session Errors

**`git stash` used in a worktree by the #2149 implementation subagent** —
AGENTS.md Hard Rule explicitly forbids `git stash` in worktrees, and a
PreToolUse hook (`guardrails.sh guardrails:block-stash-in-worktrees`)
exists to block it. The subagent used `git stash && ...; git stash pop` to
verify baseline test status, then self-reported the violation in its
handoff. State was restored correctly (nothing was lost), but the rule was
violated.
**Recovery:** the agent's own `git stash pop` restored all changes.
**Prevention:** verify whether the `guardrails.sh` hook fires in subagent
Bash-tool contexts. If the hook is main-agent-only, promote it (or extend
coverage). This is a real workflow-enforcement gap — hook claims to be
defense-in-depth but didn't fire.

**Three pattern-match tests broke after helper extraction and were
initially fixed with too-weak substring loosening** — the failures were
caught by the full test suite (not the extraction subagent), and the
loosening was caught by the review round. Three layers of catch. The
lesson was compounded across them: detection patterns must follow the
code, AND must prove usage, not presence.
**Recovery:** (1) loosened tests to unblock the suite, then (2) review
flagged the weakness, then (3) tightened to structural regex + added
direct helper assertions.
**Prevention:** add to the work skill's Phase 3 quality checklist: "When
extracting enforcement logic from a route file into a helper, update
corresponding negative-space tests in the same commit. Route-level
detection must prove helper invocation + failure early-return, not just
import presence. Add direct assertions on the helper file for every
invariant that moved into it."

## Tags

category: best-practices
module: kb
