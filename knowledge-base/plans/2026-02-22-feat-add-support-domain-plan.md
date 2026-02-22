---
title: "feat: Add Support domain with CCO and ticket-triage"
type: feat
date: 2026-02-22
---

# Add Support Domain

**Issue:** #266 | **Brainstorm:** `knowledge-base/brainstorms/2026-02-22-support-domain-brainstorm.md`

Add the 7th business domain (Support) to complete the "Company-as-a-Service" roster. Follow the established domain checklist: `knowledge-base/learnings/integration-issues/adding-new-agent-domain-checklist.md`. Template: `agents/legal/clo.md` (canonical per checklist).

## Agents

| Agent | Type | Description |
|-------|------|-------------|
| `cco.md` | Domain leader | Chief Customer Officer. 3-phase contract. Assesses support posture via `gh issue list` and `knowledge-base/support/` artifacts. Delegates to ticket-triage and community-manager. |
| `ticket-triage.md` | New specialist | Classifies GitHub issues by severity (P1/P2/P3) and domain via `gh` CLI. Routes bugs to Engineering, feature requests to Product, questions to Support. Output: structured triage report inline. |
| `community-manager.md` | Moved from Marketing | `git mv agents/marketing/community-manager.md agents/support/community-manager.md`. Unchanged functionality. |

**Dropped from brainstorm scope:** knowledge-base-curator (premature -- no knowledge base content to curate yet). Add when actual FAQ patterns emerge.

## Token Budget

Current: 2,154 words. Adding CCO (~30 words) + ticket-triage (~40 words) = ~2,224. Well under 2,500 limit. No inter-leader disambiguation needed (existing leaders don't cross-reference each other -- the CCO description is self-sufficient).

## Implementation

### Phase 1: Agent Files

1. `mkdir -p plugins/soleur/agents/support`
2. Write `agents/support/cco.md` -- 3-phase contract (Assess, Recommend/Delegate, Sharp Edges). Sharp edges: defer bug fixes to Engineering, feature prioritization to Product, retention design to Marketing, tool procurement to Operations.
3. Write `agents/support/ticket-triage.md` -- include disambiguation: "Use the triage skill for triaging internal code review findings into the CLI todo system."
4. `git mv plugins/soleur/agents/marketing/community-manager.md plugins/soleur/agents/support/community-manager.md`

### Phase 2: Cross-References

5. **CMO agent** (`agents/marketing/cmo.md`):
   - Remove `community-manager` row from delegation table
   - Remove "community" from `description:` specialist parenthetical (currently lists "brand, SEO, content, community, conversion-optimizer, paid, pricing, retention")
   - Add note in Sharp Edges: "For community engagement and health metrics, delegate to the CCO (Support domain)."
6. **Triage skill** (`skills/triage/SKILL.md`): add disambiguation in description: "Use ticket-triage agent for classifying user-reported GitHub issues by severity and domain."
7. **Brainstorm command** (`commands/soleur/brainstorm.md`): add one row to Domain Config table in Phase 0.5:
   - Assessment: "Does this feature involve customer support workflows, issue triage, help documentation, community engagement, or customer success?"
   - Leader: cco
   - Routing: "This feature has support implications. Include support assessment?"

### Phase 3: Docs Infrastructure

8. **`docs/_data/agents.js`**: add `support: "Support"` to DOMAIN_LABELS, `support: "var(--cat-support)"` to DOMAIN_CSS_VARS, `"support"` to domainOrder (after "sales")
9. **`docs/css/style.css`**: add `--cat-support: #9B59B6;` in `@layer tokens :root`
10. **`docs/_data/skills.js`**: add `"community": "Workflow"` to SKILL_CATEGORIES (currently missing), update comment count

### Phase 4: Documentation and Version

11. **Plugin AGENTS.md**: add `support/` to directory tree, add CCO row to domain leader table
12. **Root AGENTS.md**: update domain list in opening description to include "support"
13. **Plugin README.md**: add Support section to agent tables, update counts (54 -> 56)
14. **plugin.json**: update description to include "support", update agent count (54 -> 56)
15. **Hardcoded domain lists**: `grep -ri "engineering, marketing, legal, operations, product" --include="*.md" --include="*.json" --include="*.njk" plugins/soleur/` -- update all matches
16. **Version bump (MINOR)**: plugin.json + CHANGELOG.md + README.md + root README badge + bug_report.yml placeholder. Read version from `origin/main` to avoid conflicts with parallel branches.

### Phase 5: Verification

17. Token budget: `shopt -s globstar && grep -h 'description:' plugins/soleur/agents/**/*.md | wc -w` (must be under 2,500)
18. Docs build: `npx @11ty/eleventy --input=docs --output=docs/_site_test` -- verify Support renders on agents page. Clean: `rm -r docs/_site_test`
19. Agent compliance: no `<example>` blocks in descriptions

## Acceptance Criteria

- [ ] `agents/support/` with cco.md, ticket-triage.md, community-manager.md (moved)
- [ ] CCO follows 3-phase domain leader contract
- [ ] ticket-triage classifies GitHub issues via `gh` CLI, outputs inline report
- [ ] `/soleur:community` works after community-manager move
- [ ] CMO description and delegation table updated (community removed)
- [ ] Brainstorm Domain Config table has Support row
- [ ] Docs data files updated (agents.js, style.css, skills.js)
- [ ] Token budget under 2,500 words
- [ ] Version bumped (MINOR)

## Test Scenarios

- Given "add a help center for users", when running `/soleur:brainstorm`, then Phase 0.5 detects Support and offers CCO assessment
- Given ticket-triage is spawned with open GitHub issues, when it classifies, then each issue gets severity (P1/P2/P3) and domain routing
- Given ticket-triage is spawned with no open issues, when it runs, then it reports "No open issues found"
- Given `/soleur:community digest` after the move, when it spawns community-manager, then it resolves correctly and produces a digest

## Count Arithmetic

- Marketing: 12 -> 11 (community-manager moves out)
- Support: 0 -> 3 (cco + ticket-triage + community-manager)
- Net: +2 new agents (54 -> 56)
