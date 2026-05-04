---
date: 2026-05-04
category: best-practices
module: planning
tags: [planning, code-reuse, lib-helpers, review-catches]
pr: "#3186"
---

# Plan-phase precedent search must include `lib/` helpers, not just sibling components

## Problem

The plan for `feat-shared-doc-cta-banner-closeable` (PR #3186) prescribed mirroring the try/catch storage shape from `apps/web-platform/components/chat/notification-prompt.tsx:20-41` verbatim — exactly the kind of structural copy that a precedent helper exists to prevent. The implementer followed the plan, producing two helpers (`getInitialDismissed`, `persistDismissed`) and inline try/catch blocks.

The codebase already had `apps/web-platform/lib/safe-session.ts` — a single-function wrapper that handles SSR-safety, QuotaExceeded, and SecurityError for sessionStorage in 27 lines. Its docstring even names the rationale: *"Introduced to replace 8 scattered try/catch sessionStorage blocks across `chat-input.tsx` and `kb/layout.tsx`."*

The plan agent did not grep `apps/web-platform/lib/` for storage helpers. The implementer didn't either. Only the post-implementation pattern-recognition-specialist and code-simplicity-reviewer agents flagged the duplication, requiring a refactor commit.

## Solution

Replace the inlined helpers with `safeSession`:

```tsx
// Before — 18 lines of helpers
function getInitialDismissed(): boolean { /* try/catch sessionStorage.getItem */ }
function persistDismissed(): void { /* try/catch sessionStorage.setItem */ }

// After — 0 helper lines, reuse existing abstraction
import { safeSession } from "@/lib/safe-session";

const [dismissed, setDismissed] = useState<boolean>(
  () => safeSession(STORAGE_KEY) === "1",
);

function handleDismiss() {
  safeSession(STORAGE_KEY, "1");
  setDismissed(true);
}
```

Net diff: −15 LOC, −1 abstraction layer, +1 reuse of an explicitly-introduced helper.

## Key Insight

AGENTS.md `cq-grep-lib-before-writing-format-helpers` covers format/date helpers but the same discipline applies to **any cross-cutting concern wrapper**: storage, fetch, logging, error reporting, retry, debounce. The rule should generalize: *before writing a new wrapper for a browser/runtime API, grep `apps/<app>/lib/` for an existing helper.*

A plan that cites a sibling component as "precedent for the try/catch shape" is a yellow flag — if the shape was load-bearing enough to mirror, it was probably load-bearing enough to extract. Look one level up.

## Prevention

- **Plan agent:** when the plan calls for "mirror the X pattern from `<file>:<lines>`", add an automatic step: `ls apps/<app>/lib/ | grep <topic>` and `rg "function safe[A-Z]" apps/<app>/lib/`. If a helper exists with overlapping intent, replace the precedent reference with the helper's contract.
- **Implementer:** before transcribing a try/catch from a precedent, grep `apps/<app>/lib/` for the API surface (`sessionStorage`, `localStorage`, `fetch`, `setTimeout` with retry, etc.). One grep beats one review-cycle refactor.
- **Plan template:** the "Research Insights" section should include a "Lib helpers checked" line listing each `apps/<app>/lib/` file inspected and the conclusion (reuse / no-match / out-of-scope). An empty list is a yellow flag.

## Session Errors

1. **Worktree-manager `--yes create` failed with "fatal: this operation must be run in a work tree"** — the script tries `git pull` for the "Updating main..." step, but the repo is `core.bare=true` and the script was invoked from the bare root. **Recovery:** bypassed with `git worktree add .worktrees/<name> -b <branch> main`. **Prevention:** the worktree-manager script should detect `IS_BARE && !IS_IN_WORKTREE` before the "Updating main" step and skip the `git pull` (already has the `require_working_tree()` guard at line 68 — extend it to `update_main()` too).

2. **`npx vitest` auto-installed vitest 4.x** which produced `Could not resolve 'vitest/config'` and `Unexpected JSX expression` parse errors against the project's vitest 3.2.4 config. **Recovery:** switched to project-local `./node_modules/.bin/vitest`. **Prevention:** when running test commands in a worktree, always use the project-local binary path (`./node_modules/.bin/<tool>`) — never `npx <tool>` for any tool the project has pinned via `devDependencies`. `npx` resolves to its own cache, ignores the project's lockfile, and silently major-version-jumps. Add to AGENTS.md or to the `work` skill's "Test Continuously" section.

3. **Draft-PR push failed with HTTP 403** ("Permission to jikig-ai/soleur denied to Elvalio") because the active GitHub auth identity didn't have repo access yet. **Recovery:** user granted access mid-session, then `git push -u origin <branch>` succeeded. **Prevention:** none warranted — this was a one-off provisioning state, not a systemic gap.

4. **Bash CWD did not persist between tool calls** when running `tsc --noEmit` and `vitest`. Initial calls without `cd` ran from the worktree root instead of `apps/web-platform/`, producing exit-0 with no output (false-clean). **Recovery:** chained `cd <abs-path> && <cmd>` in a single call. **Prevention:** AGENTS.md already has `cq-for-local-verification-of-apps-doppler` covering this. Reinforced by repeat occurrence — consider a hook that warns if a `tsc`/`vitest`/`bun test` invocation runs without a preceding `cd` to an app directory.

5. **`git add apps/web-platform/components/...` from inside `apps/web-platform/`** produced `apps/web-platform/apps/web-platform/...` path doubling. **Recovery:** used app-relative paths after `cd`. **Prevention:** when chaining `cd <subdir> && git add`, use either repo-relative paths from the bare root (no `cd`) or app-relative paths (after `cd`). Pick one and stay consistent within a single tool call.

## Cross-references

- AGENTS.md `cq-grep-lib-before-writing-format-helpers` — same class for format/date helpers
- `apps/web-platform/lib/safe-session.ts` — the helper this learning prescribes reusing
- PR #3186 — the originating PR
- Plan: `knowledge-base/project/plans/2026-05-04-feat-shared-doc-cta-banner-closeable-plan.md`
