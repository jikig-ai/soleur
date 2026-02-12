# Tasks: Project-Aware Agent Filtering in Review Command

**Plan:** `knowledge-base/plans/2026-02-12-feat-runtime-agent-discovery-plan.md`
**Branch:** `feat-runtime-agent-discovery`

## 1. Move Rails agents to conditional section

Modify `plugins/soleur/commands/soleur/review.md`:

- [ ] Remove `kieran-rails-reviewer` and `dhh-rails-reviewer` from `<parallel_tasks>` block
- [ ] Add both agents to `<conditional_agents>` section, gated on `Gemfile + config/routes.rb`
- [ ] Add "When to run" criteria matching the existing pattern for migration/test agents
- [ ] Add "What these agents check" descriptions
- [ ] Renumber remaining parallel agents (8 agents, not 10)

## 2. Test

- [ ] Verify the conditional section reads correctly and follows the established pattern
- [ ] Review the full command flow to ensure no references to the moved agents are broken

## 3. Version bump and documentation

- [ ] Bump version in `plugin.json` (PATCH)
- [ ] Update `CHANGELOG.md`
- [ ] Update `README.md` if counts or tables changed
