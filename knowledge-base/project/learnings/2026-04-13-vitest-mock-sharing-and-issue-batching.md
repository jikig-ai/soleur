# Learning: vitest mock sharing across test files and issue batching

## Problem

Two agent-runner test files (`agent-runner-tools.test.ts`, `agent-runner-cost.test.ts`) duplicated ~80 lines of identical Supabase mock setup. Additionally, 7 GitHub issues needed fixing — doing them individually would mean 7 separate PR/merge/deploy cycles.

## Solution

### Mock sharing

`vi.mock()` declarations must stay in each test file (vitest hoists them to file top). However, the **implementation functions** that configure mock behavior can be extracted to a shared helper (`test/helpers/agent-runner-mocks.ts`). The pattern:

- Helper exports: `createSupabaseMockImpl(mockFrom, opts)`, `createQueryMock(mockQuery, result)`, `DEFAULT_API_KEY_ROW`
- Each test file: keeps its own `vi.hoisted()` and `vi.mock()` declarations, calls shared helpers in `setupSupabaseMock()` wrappers

### Issue batching

Grouped 7 issues into 2 PRs by domain proximity:

- PR 1: agent-runner area (error constants, test mocks, team names hook) — 4 issues
- PR 2: plugin skill fixes — 2 issues
- 1 verification-only check (DNS), 1 closed as not applicable

## Key Insight

When batching issues, group by **file proximity** (which files are touched) rather than issue type. This minimizes merge conflicts and keeps each PR reviewable. Issues whose referenced code no longer exists should be verified against current code — address the underlying concern, not the literal description.

## Tags

category: testing
module: web-platform
