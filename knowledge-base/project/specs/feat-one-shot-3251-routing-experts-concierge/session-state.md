# Session State

## Plan Phase
- Plan file: /home/jean/git-repositories/jikig-ai/soleur/.worktrees/feat-one-shot-3251-routing-experts-concierge/knowledge-base/project/plans/2026-05-05-fix-cc-routing-panel-hides-concierge-plan.md
- Status: complete

### Errors
None. Side-notes:
- Brainstorm/spec referenced in prompt live on `feat-cc-session-bugs-batch` branch; carry-forward read via `git show origin/feat-cc-session-bugs-batch:...`.
- AGENTS.md re-loaded mid-skill via system-reminder; acknowledged, no action.

### Decisions
- Located routing UX as TWO surfaces in `apps/web-platform/components/chat/chat-surface.tsx`: `isClassifying` chip (line 606-615, no Concierge avatar) and routed-leaders strip (line 419-429, uses `respondingLeaders` and `getDisplayName` — returns bare "Concierge" for `cc_router`).
- Fix: extract `RoutedLeadersStrip` component + Concierge slot; widen chip text to "Soleur Concierge is routing to the right experts..."; read `CONCIERGE_TITLE` from `DOMAIN_LEADERS` at module scope (avoids #3225 bare-Concierge regression).
- Acceptance reframed from pixel-diff to DOM-state RTL assertions (5 tests covering chip+strip states + bare-Concierge drift guard).
- Code-review overlap with #2223: location stale; disposition is comment on #2223, do NOT fold (orthogonal P3 perf work).
- Brand-survival threshold `single-user incident`: plan has `requires_cpo_signoff: true`; user-impact-reviewer fires at review time per `hr-weigh-every-decision-against-target-user-impact`.

### Components Invoked
- skill: soleur:plan
- skill: soleur:deepen-plan
- gh issue view 3251, 2223; gh issue list --label code-review
- git show origin/feat-cc-session-bugs-batch:knowledge-base/... (cross-branch brainstorm read)
- grep / Read on chat-surface.tsx, leader-avatar.tsx, ws-client.ts, domain-leaders.ts, use-team-names.tsx
- Phase 4.5 Network-Outage Deep-Dive: skipped (no SSH/network triggers)
- Phase 4.6 User-Brand Impact Halt: PASSED
