---
name: kb-share-mcp-parity — lstat TOCTOU regression + shared-import mock cascade
description: Two durable lessons from extracting kb-share lifecycle into a shared module and adding in-process MCP tools — (a) pre-open lstat reintroduces a CodeQL TOCTOU window even though it seems to add "more checks", (b) adding a new import to a widely-imported server module like agent-runner requires cascading mock updates in every test that loads that module.
category: runtime-errors
tags:
  - kb-share
  - mcp
  - agent-runner
  - toctou
  - vitest-mocks
  - refactor-cascade
pr: 2497
issue: 2309
---

# KB Share MCP Parity — lstat TOCTOU regression + shared-import mock cascade

## Problem

PR #2497 extracted the KB share lifecycle (validation + DB writes) from two HTTP route handlers into a new shared module (`server/kb-share.ts`) so three in-process MCP tools (`kb_share_create/list/revoke`) could reuse the same hardening. Two non-obvious failures surfaced during the review + test phases:

1. A pre-open `lstat` check I added to distinguish `symlink-rejected` from generic `invalid-path` silently **reintroduced the CodeQL `js/file-system-race` TOCTOU window** the pre-PR route had deliberately eliminated by relying solely on `O_NOFOLLOW` + `fstat`. It also changed observable HTTP status on EACCES/ENOTDIR from 404 to 400.
2. Adding `createChildLogger` and `reportSilentFallback` imports to `agent-runner.ts` and `kb-share.ts` broke **31 tests across 12 files** that loaded these modules. Every test that loads `agent-runner.ts` (directly or transitively) had to mock `@/server/observability` and `@/server/logger`'s `createChildLogger` export — the existing tests only mocked the logger's `default` export.

## Solution

### TOCTOU: remove the pre-open `lstat`; use realpath + O_NOFOLLOW only

```ts
// BAD — reintroduces js/file-system-race TOCTOU
const lstat = await fs.promises.lstat(fullPath);
if (lstat.isSymbolicLink()) return { code: "symlink-rejected" };
if (!isPathInWorkspace(fullPath, kbRoot)) return { code: "invalid-path" };
const handle = await fs.promises.open(fullPath, O_RDONLY | O_NOFOLLOW);

// GOOD — no window between check and open
if (!isPathInWorkspace(fullPath, kbRoot)) return { code: "invalid-path" };
try {
  const handle = await fs.promises.open(fullPath, O_RDONLY | O_NOFOLLOW);
} catch (err) {
  if (err.code === "ELOOP" || err.code === "EMLINK") return { code: "symlink-rejected" };
  return { code: "not-found" };
}
```

**Key insight:** The `symlink-rejected` code still gets emitted — just from the `ELOOP`/`EMLINK` error branch of the `O_NOFOLLOW` open instead of from the pre-flight `lstat`. The discrimination between "path escapes kbRoot" (realpath follows symlinks) and "terminal component is a symlink to something inside kbRoot" (ELOOP on O_NOFOLLOW) is preserved, without the TOCTOU. Tests must be written with symlinks whose targets are **inside** kbRoot to exercise the ELOOP path.

### Shared-import mock cascade: grep-before-import

When you add a new import to `server/agent-runner.ts` (or any widely-loaded server module), immediately grep for the set of tests that mock the existing dependencies of the same module and mirror-add the new mock:

```bash
# Find tests that load agent-runner
grep -l "startAgentSession\|from.*agent-runner" apps/web-platform/test/*.test.ts

# For each, check if it mocks the new dependency
for f in <matches>; do
  grep -q "server/observability" "$f" || echo "MISSING: $f"
done
```

Add the missing mocks as a **single batch**, not one-by-one when CI fails. The cost of a cascading import pattern (one new import → 10 mock updates) is a real signal that the agent-runner is becoming a god-module — worth noting for a future extraction.

## Key Insight

Two generalizable lessons:

1. **"Add another validation check" can make code less secure.** A pre-flight `lstat` looks like belt-and-suspenders but opens a TOCTOU window that the terminal `O_NOFOLLOW` open had already closed. For security-critical filesystem code, prefer fewer, terminal-authoritative checks over multiple early-return checks. Let the fd-based operation be the single source of truth.
2. **Shared mutation amplification: one new import, N test files broken.** The cost of adding an import to `agent-runner.ts` is proportional to how many test files load it — currently ~15. Before adding a new import to a hot server module, grep the test surface to estimate the cost. If the cascade is large, consider whether the import can live in a smaller module that fewer tests load.

## Session Errors

- **Premature plan checklist marking.** Used sed to mark the Ship Gate checkboxes done before QA, manual QA, PR body, and compound actually ran. **Recovery:** Reverted those with a follow-up sed. **Prevention:** The plan's Ship Gate checklist includes items that span multiple phases (QA, review, PR body, compound). Only mark items when actually completed in the current phase — `skill: soleur:work` should only mark items whose completion condition is "tests pass + typecheck clean" (e.g., "all X new tests pass", "vitest is green repo-wide"), not items like "PR body contains Closes #N" which belong to `skill: soleur:ship`.
- **Symlink test initially didn't exercise ELOOP path.** Test used a symlink pointing outside kbRoot, which triggers `isPathInWorkspace` (realpath) rejection as `invalid-path`, not the `symlink-rejected` ELOOP path. **Recovery:** Added a second test with symlink whose target is inside kbRoot. **Prevention:** When asserting a discriminating error code, trace which code path actually produces that code and construct the test fixture accordingly. A unit test that claims to exercise "symlink rejection" but actually exercises realpath-follow rejection is a test that will pass even if the ELOOP branch is deleted.
- **`Record<string, unknown>[]` → `RowShape[]` cast failed tsc.** TS2352 because the types don't sufficiently overlap. **Recovery:** Used `as unknown as RowShape[]` double-cast. **Prevention:** When the source type is `Record<string, unknown>[]` (loose) and target is a concrete interface, tsc requires intermediate `unknown` cast — it's the standard pattern for "I know what's in here but tsc doesn't."
- **TOCTOU reintroduction via pre-open lstat.** See Problem section above. **Recovery:** Removed lstat; rely on realpath + O_NOFOLLOW. **Prevention:** When moving a hardened filesystem check from one file to another (route → module), diff the behavior carefully. Extra checks are not always safer — they can open windows the existing terminal check had closed.
- **Cascading import breaks 31 tests across 12 files.** See Solution section above. **Recovery:** Added `vi.mock("../server/observability", ...)` to every affected test file. **Prevention:** Grep the test surface before adding imports to widely-loaded server modules. Consider extracting to a less-loaded module if the cascade is large.

## Related

- `cq-silent-fallback-must-mirror-to-sentry` — the rule that motivated the observability import.
- `cq-progressive-rendering-for-large-assets` — related kb-share binary-files work in PR #2451.
- Learning `2026-04-15-kb-share-binary-files-lifecycle.md` — the precedent extraction this PR follows.
- Learning `2026-04-15-negative-space-tests-must-follow-extracted-logic.md` — applied in the kb-security.test.ts update (accept tagged-union helper delegation as proof of delegation).
- Learning `2026-04-10-service-tool-registration-scope-guard.md` — applied in Test Scenario 32 (kb-share tools register independently of GitHub installation).
