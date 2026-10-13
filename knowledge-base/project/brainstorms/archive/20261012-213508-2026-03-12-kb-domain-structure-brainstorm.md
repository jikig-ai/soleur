# Knowledge-Base Domain Structure Brainstorm

**Date:** 2026-03-12
**Status:** Complete
**Participants:** Jean, Claude

## What We're Building

Restructure `knowledge-base/` to align with Soleur's canonical 8-department taxonomy. Domain-specific content moves into domain folders; cross-cutting feature artifacts (specs, plans, brainstorms, learnings) group under a shared `features/` parent; `overview/` renames to `project/` for clarity.

## Why This Approach

- **Navigation clarity**: Currently hard to tell whether a doc is marketing, product, or project-level — `overview/` conflates strategy docs with project infrastructure.
- **Agent routing**: Domain leaders (CMO, CPO, COO, etc.) should read/write from their domain folder instead of scattered locations.
- **Canonical alignment**: The 8-department taxonomy already exists in AGENTS.md and brainstorm-domain-config.md. The knowledge-base directory structure should mirror it.

## Key Decisions

1. **Domain-specific content → domain folders**
   - `audits/` → `marketing/audits/` (SEO/content audits)
   - `design/` → `product/design/` (brand .pen files)
   - `ops/` → `operations/` (renamed to match canonical taxonomy)
   - `community/` → `support/community/`
   - Strategy docs from `overview/` distributed to their owning domain

2. **Shared feature artifacts → `features/`**
   - `specs/`, `plans/`, `brainstorms/`, `learnings/` move under `features/`
   - Organized by feature/date, NOT split by domain — preserves tooling conventions
   - Deep dependency on archiving, compound skill, feature-spec conventions

3. **`overview/` → `project/`**
   - Keeps only project-level docs: `constitution.md`, `README.md`, `components/`
   - Removes ambiguity about what belongs here

4. **Empty domain dirs created** for engineering, finance, legal
   - Ready for agents to write to without `mkdir -p` calls

5. **Canonical 8 departments used** as directory names: engineering, finance, legal, marketing, operations, product, sales, support

## Proposed Structure

```
knowledge-base/
├── project/                    # renamed from overview/
│   ├── constitution.md
│   ├── README.md
│   └── components/
│
├── features/                   # shared infra (new parent)
│   ├── specs/
│   ├── plans/
│   ├── brainstorms/
│   └── learnings/
│
├── marketing/                  # domain
│   ├── audits/          ← audits/
│   ├── distribution-content/ (existing)
│   ├── brand-guide.md   ← overview/
│   ├── content-strategy.md  ← overview/
│   └── marketing-strategy.md ← overview/
│
├── product/                    # domain
│   ├── design/          ← design/
│   ├── business-validation.md ← overview/
│   ├── competitive-intelligence.md ← overview/
│   └── pricing-strategy.md ← overview/
│
├── operations/                 # domain (rename ops/)
│   ├── expenses.md      ← ops/
│   └── domains.md       ← ops/
│
├── sales/                      # domain (existing, unchanged)
│   └── battlecards/
│
├── support/                    # domain
│   └── community/       ← community/
│
├── engineering/                # domain (empty for now)
├── finance/                    # domain (empty for now)
└── legal/                      # domain (empty for now)
```

## Migration Strategy

File moves must use `git mv` to preserve history, in a single atomic commit that can be reverted with `git revert`.

### Path Reference Update Scope (from research)

| Category | Count | Examples |
|----------|-------|---------|
| Agent files | ~20 | ops-advisor, brand-architect, competitive-intelligence, community-manager, learnings-researcher |
| GitHub Actions | 3 | content-publisher, community-monitor, competitive-analysis |
| Shell scripts | 2 | content-publisher.sh, generate-article-30-register.sh |
| Skills | ~6 | compound, ship, competitive-analysis, community, content-writer, spec-templates |
| Commands | 1 | sync.md |

### Critical Dependencies

- **Archiving system** (`compound-capture`, `worktree-manager.sh cleanup-merged`): hardcoded `knowledge-base/{brainstorms,plans}/*<slug>*` and `knowledge-base/project/specs/feat-<slug>/` — must update to `knowledge-base/features/{brainstorms,plans,specs}`
- **learnings-researcher**: hardcoded routing table with 13 subdirectory paths under `knowledge-base/project/learnings/` — must update to `knowledge-base/features/learnings/`
- **Feature-spec convention**: `feat-<name>` → `knowledge-base/project/specs/feat-<name>/` — becomes `knowledge-base/features/specs/feat-<name>/`
- **Brand-guide reads**: ~15 agents read `knowledge-base/overview/brand-guide.md` — becomes `knowledge-base/marketing/brand-guide.md`

### Execution Steps

1. `grep -r "knowledge-base/" plugins/ scripts/ .github/` to inventory all references
2. `git mv` all files per mapping above (single atomic commit)
3. Update all hardcoded paths in agents, skills, commands, scripts, workflows
4. Verify archiving tools work with new paths
5. Refresh `project/README.md` and component docs
6. Run `grep -r` for old path patterns to confirm zero stale references

## Open Questions

- Should the `features/` directory also hold archive subdirectories, or keep archive as a child of each type (e.g., `features/specs/archive/`)?
  - **Recommendation**: Keep archive as child — `features/specs/archive/` — maintains existing convention

## Risks

- **Silent archiving breakage**: Past learning shows 92 artifacts silently not archived when paths changed
- **CI workflow breakage**: 3 GH Actions workflows have hardcoded `git add` paths — breakage is silent in CI
- **Path reference count**: Prior migration found 103 references — expect similar scope
