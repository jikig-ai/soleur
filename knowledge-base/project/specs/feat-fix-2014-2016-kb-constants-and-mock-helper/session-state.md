# Session State

## Plan Phase
- Plan file: /home/jean/git-repositories/jikig-ai/soleur/.worktrees/feat-fix-2014-2016-kb-constants-and-mock-helper/knowledge-base/project/plans/2026-04-12-fix-kb-constants-and-mock-helper-plan.md
- Status: complete

### Errors
None

### Decisions
- **Issue #2014 scope adjusted:** The original issue referenced `ALLOWED_EXTENSIONS` in `file-tree.tsx` which no longer exists. Current duplication is between `kb-reader.ts`/`context-validation.ts` (1MB KB limit) and `presign/route.ts`/`chat-input.tsx` (20MB attachment constants). Plan addresses both groups.
- **Incremental mock migration:** Only 3-4 of the 17 test files with Supabase mocks will be migrated in this PR. Remaining files adopt incrementally when touched by future PRs.
- **mockQueryChain must be thenable:** Institutional learning (`supabase-query-builder-mock-thenable-20260407`) documents that Supabase v2 query builder is `PromiseLike`. The helper implements `.then()` on the chain itself, not just on terminal methods.
- **Helper exports building blocks, not vi.mock factories:** Due to vitest hoisting constraints (`vi.hoisted()` requirement), the helper exports `mockQueryChain` as a utility function, not pre-built mock instances. Test files still declare their own `vi.hoisted()` + `vi.mock()` blocks.
- **No cross-domain implications:** Both issues are pure engineering refactors with no product, marketing, legal, or operational impact.

### Components Invoked
- `soleur:plan` (skill)
- `soleur:deepen-plan` (skill)
- GitHub CLI (`gh issue view #2014`, `gh issue view #2016`)
- Institutional learnings search (4 relevant learnings applied)
- markdownlint-cli2 (validation)
