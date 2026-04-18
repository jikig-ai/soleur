---
module: apps/web-platform + .github/actions
date: 2026-04-18
problem_type: integration_issue
component: react_hook + composite_action
symptoms:
  - "State hook returned JSX fragments (sidebarContent, docContent) causing SRP leak"
  - "Composite action used `git add $ADD_PATHS` unquoted — word-splitting, glob expansion, and flag injection risk"
  - "18-field hook return type conflated tree/collapse/chat/JSX concerns"
  - "Review agents (security-sentinel, architecture-strategist, code-quality-analyst) flagged both in seconds"
root_cause: hooks_returning_jsx + shell_unquoted_expansion
severity: high
tags: [code-review, multi-agent, hooks, composite-action, shell-injection, srp]
synced_to: []
---

# Hooks Should Return Data, Not JSX — and Multi-Agent Review Catches Action Injection Risks

## Problem

During PR #2583 (7-issue drain via one-shot), two review-driven findings surfaced
late in the pipeline that unit tests, tsc, and vitest all passed cleanly:

1. **`useKbLayoutState()` was returning `ReactNode` fragments** (`sidebarContent`,
   `docContent`) alongside its 16 state/callback fields. The 18-field return
   shape conflated concerns and broke the hook/component boundary. Unit tests
   saw only the composed output, so the violation was invisible to them.

2. **`bot-pr-with-synthetic-checks/action.yml` used `git add $ADD_PATHS`
   unquoted** (with `# shellcheck disable=SC2086`) to enable word-splitting.
   All current callers pass static literals, so it was not exploitable on
   main — but the action is a reusable primitive. Any future caller
   interpolating event data (PR title, issue body, matrix input) into
   `add-paths` becomes RCE-adjacent: glob expansion, flag injection via
   `--chmod=+x`, or silent broadening via `*`.

Unit tests and tsc --noEmit passed on all tranches; semgrep-sast reported 0
CWE matches. Review agents flagged both issues within seconds.

## Solution

### 1. Hooks return data + callbacks only

Extract JSX into dedicated shell components. For `useKbLayoutState`:

- `apps/web-platform/components/kb/kb-sidebar-shell.tsx` — header + search +
  file tree (receives `onCollapse` callback)
- `apps/web-platform/components/kb/kb-doc-shell.tsx` — optional expand button +
  scrollable content well (receives `collapsed`, `isContentView`, `onExpand`,
  `children`)
- Hook return drops from 18 fields to 16; imports of `FileTree`,
  `SearchOverlay`, `KbErrorBoundary`, `DesktopPlaceholder` move to the shells.

The hook now contains state + effects + callbacks + memoized context values
only. Future styling changes no longer require editing a `.tsx` hook file.

### 2. Composite-action hardening

Change `add-paths` input contract from space-separated to newline-separated,
parse into a bash array, terminate options with `--`:

```yaml
# Before (P1 — injection-adjacent):
# shellcheck disable=SC2086
git add $ADD_PATHS

# After:
PATHS=()
while IFS= read -r line; do
  [[ -z "$line" ]] && continue
  PATHS+=("$line")
done <<< "$ADD_PATHS"
git add -- "${PATHS[@]}"
```

Additional hardening added in the same commit:

- Validate `PR_BODY` is single-line (fail fast instead of silent `gh pr create
  --body` truncation).
- Validate `CHANGE_SUMMARY` fits GitHub's 60KB check-run summary cap.
- Pass PR body via `--body-file` (mktemp) so future multi-line support is a
  validator relaxation away.
- Add a step `name:` so workflow logs identify the step.

## Key Insight

**Multi-agent parallel review surfaces classes of bugs unit tests cannot
express.** This PR's unit tests were exhaustive for observable behavior — 2108
vitest cases, tsc clean, semgrep clean — but could not see:

- Whether a hook's return shape coheres with the hook/component boundary (that
  is a design-taste assertion, not a behavioral one).
- Whether a YAML input is safe against hypothetical future callers (the
  current callers pass static literals; the risk is structural, not
  observable).

Both findings came from the review's LLM-based architectural and security
readers in under a minute. The pattern is the same as the
`cq-silent-fallback-must-mirror-to-sentry` rule: "code that runs green today
but has a latent class-of-failure" is exactly what multi-agent review catches
that tests cannot.

**Secondary insight:** `rf-review-finding-default-fix-inline` held up on a
large PR. All P1/P2 review findings (9 total) were fixed in a single
follow-up commit on the PR branch with zero scope-outs needed for
pr-introduced code. One pre-existing flaky test (concurrent vitest
regressions unrelated to this PR) was filed as #2594 under
`pre-existing-unrelated`. The rule's mechanical provenance triage
(pr-introduced → fix inline; pre-existing → file with re-evaluation
criteria) cleanly partitioned the work.

## Prevention

1. **Hooks MUST return data and callbacks, not JSX.** If a hook is tempted to
   return `ReactNode`, the JSX belongs in a pure-presentational component.
   Skill rule candidate for `plan/SKILL.md` "Sharp Edges" or AGENTS.md
   `cq-hooks-return-data-not-jsx`.

2. **Composite actions that accept path inputs MUST use array semantics.**
   Newline-separated + `mapfile` / `while IFS= read` + `git <cmd> -- "${ARRAY[@]}"`
   is the pattern. Never rely on shell word-splitting (`$VAR` unquoted) even
   when the current callers "happen to" pass safe values. The action is a
   primitive; safety belongs at the primitive, not at each caller.

3. **`set -euo pipefail` + input validators at the top of every composite
   action.** Cheap, loud, and catches contract drift before the gh CLI step.

## Session Errors

1. **JSX in a `.ts` file** — `apps/web-platform/hooks/use-kb-layout-state.ts`
   contained JSX; esbuild transform failed with `Expected ">" but found
   "className"` at first vitest run after the split. **Recovery:** renamed to
   `.tsx`. **Prevention:** a hook that returns or uses JSX must be `.tsx`.
   TypeScript-aware linting / plan-skill checklist item would catch this pre-
   transform.

2. **`PanelRef` not exported from `react-resizable-panels`** — initial typing
   attempt failed with `TS2305: Module has no exported member 'PanelRef'`.
   **Recovery:** used `ReturnType<typeof usePanelRef>` instead. **Prevention:**
   verify named type exports by reading the dep's `.d.ts` file before citing
   them in types.

3. **`git mv` on an untracked file** — attempted to `git mv use-kb-layout-state.ts
   .tsx` before the original `.ts` was tracked. Command failed with "not under
   version control". **Recovery:** plain `mv`. **Prevention:** add a
   `git ls-files --error-unmatch <path>` probe before invoking `git mv` in
   scripts, or prefer `mv` when the source is known-untracked.

4. **Vitest parallel-execution flakiness surfaced under load** — 1-8
   intermittent failures across chat-surface / kb-chat-sidebar tests when
   running the full suite. Pass sequentially. **Recovery:** filed #2594 under
   `pre-existing-unrelated` (the concurrency stress surfaced existing race
   conditions; this PR's hook extraction raised load but did not introduce
   the races). **Prevention:** enforce worker isolation in vitest config for
   these test paths, or audit shared module state between concurrent workers.

5. **Initial hook design returned JSX** — the pre-refactor `KbLayout` inlined
   `sidebarContent` and `docContent` in the component body; the straight-line
   extraction copied them into the hook. Review agents caught it. **Recovery:**
   extracted into `KbSidebarShell` and `KbDocShell`. **Prevention:** during
   hook extraction, if a JSX literal crosses the hook boundary, stop and
   extract a component instead.

## Workflow Feedback

- **New skill instruction for plan/SKILL.md Sharp Edges:** "When a plan
  extracts a React component's state into a hook, the hook must return
  data and callbacks only — JSX fragments belong in shell components, not
  in the hook's return type." Tier: prose rule (design taste, not
  mechanically enforceable).
- **Potential AGENTS.md rule:** `cq-composite-actions-array-paths` — "YAML
  composite actions accepting path-like inputs must use newline-separated
  contracts parsed into bash arrays with `git <cmd> -- '${ARRAY[@]}'`. Never
  rely on shell word-splitting even if current callers pass static literals."
  Tier: prose rule; not a hook target because the violation surfaces only in
  review.

## Tags

- category: integration-issues
- module: apps/web-platform + .github/actions
