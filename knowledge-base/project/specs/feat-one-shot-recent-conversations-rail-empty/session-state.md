# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-06-15-fix-conversations-rail-empty-repo-url-source-divergence-plan.md
- Status: complete

### Errors
None. CWD verified == WORKING DIRECTORY before any work. All four deepen-plan hard gates (4.6 User-Brand Impact, 4.7 Observability, 4.8 PAT, 4.9 UI-wireframe) passed. No spec.md (one-shot path) so `lane:` defaulted to `cross-domain` (fail-closed).

### Decisions
- Root cause (high confidence): `repo_url` source-of-truth divergence. Client hook `hooks/use-conversations.ts` scopes the list by deprecated `users.repo_url` (hard-returns empty when null); server stamps conversations with `workspaces.repo_url` per ADR-044. Divergence → active conversation filtered out → empty rail. RLS has no `repo_url` predicate, so it is a client app-filter, not RLS.
- Fix = adopt existing canonical client pattern: read `repoUrl` + `workspaceId` from `GET /api/workspace/active-repo` (same pattern as `hooks/use-active-repo.ts`). No new API route, no schema/migration change.
- Deepen corrections: remove dead cross-tab `users` UPDATE realtime channel; sweep now-unused `normalizeRepoUrl` import (cq-ref-removal-sweep); do NOT extract a shared coalescing helper (per-hook latch is the project pattern).
- Scoped strictly to empty-rail bug (NOT #4826 position-resume). Threshold `single-user incident`, `requires_cpo_signoff: true`; `user-impact-reviewer` runs at review.
- Test: new `.tsx` under `test/` (vitest component glob), mock `vi.stubGlobal("fetch")` + `vi.mock("@/lib/supabase/client")`.

### Components Invoked
- Skill: soleur:plan
- Skill: soleur:deepen-plan
- Agents: repo-research-analyst, learnings-researcher, general-purpose ×2 (verify-the-negative + precedent-diff)
- Deepen hard gates 4.6/4.7/4.8/4.9 (all pass)
