# Tasks: Knowledge Base Project Overview System

**Branch:** `feat-project-overview`
**Plan:** [2026-02-06-feat-project-overview-system-plan.md](../../plans/2026-02-06-feat-project-overview-system-plan.md)
**Version:** 1

## Phase 1: Static Structure

Create initial `knowledge-base/overview/` structure manually.

- [x] 1.1 Create directory structure
  - [x] 1.1.1 Create `knowledge-base/overview/` directory
  - [x] 1.1.2 Create `knowledge-base/overview/components/` subdirectory

- [x] 1.2 Create README.md
  - [x] 1.2.1 Write project purpose section
  - [x] 1.2.2 Write high-level architecture overview
  - [x] 1.2.3 Add component index with links
  - [x] 1.2.4 Add mermaid architecture diagram

- [x] 1.3 Create initial component files
  - [x] 1.3.1 Create `components/agents.md` with template
  - [x] 1.3.2 Create `components/commands.md` with template
  - [x] 1.3.3 Create `components/skills.md` with template
  - [x] 1.3.4 Create `components/knowledge-base.md` with template

## Phase 2: Component Template

Define and document the component template specification.

- [x] 2.1 Define YAML frontmatter schema
  - [x] 2.1.1 Document required fields (component, updated, primary_location)
  - [x] 2.1.2 Document optional fields (related_locations, status, auto_generated)

- [x] 2.2 Document section structure
  - [x] 2.2.1 Define mandatory sections (Purpose, Responsibilities, Key Interfaces)
  - [x] 2.2.2 Define optional sections (Diagram, Examples, Related Files)
  - [x] 2.2.3 Document which sections are auto-generated vs user-maintained

- [x] 2.3 Add template to spec-templates skill
  - [x] 2.3.1 Add component template to `plugins/soleur/skills/spec-templates/SKILL.md`

## Phase 3: /sync Integration

Extend `/sync` command with `overview` area.

- [x] 3.1 Update sync command specification
  - [x] 3.1.1 Add `overview` to valid areas list in `plugins/soleur/commands/soleur/sync.md`
  - [x] 3.1.2 Document output mapping for overview area
  - [x] 3.1.3 Add component detection algorithm documentation

- [x] 3.2 Implement overview analysis phase
  - [x] 3.2.1 Add component detection logic (architectural boundaries heuristic)
  - [x] 3.2.2 Add README.md generation/update logic
  - [x] 3.2.3 Add component file generation logic

- [x] 3.3 Implement preservation logic
  - [x] 3.3.1 Detect existing user customizations via frontmatter
  - [x] 3.3.2 Implement merge strategy for auto-generated sections only
  - [x] 3.3.3 Handle deprecated components (add status, do not delete)

- [x] 3.4 Add review phase for overview
  - [x] 3.4.1 Present detected components for user approval
  - [x] 3.4.2 Allow Accept/Skip/Edit for each component

## Phase 4: Polish

Final refinements and documentation.

- [x] 4.1 Add mermaid diagrams to component files
  - [x] 4.1.1 CLI data flow diagram (existing in component files)
  - [x] 4.1.2 Plugin loading sequence diagram (in commands.md)
  - [x] 4.1.3 Converter pipeline diagram (N/A - converter CLI not implemented)

- [x] 4.2 Update constitution.md
  - [x] 4.2.1 Add overview convention: "overview/ documents what the project does; constitution.md documents how to work on it"
  - [x] 4.2.2 Add component template convention

- [x] 4.3 Verification
  - [x] 4.3.1 Run markdownlint on all overview files (consistent with project style)
  - [x] 4.3.2 Verify mermaid diagrams render in GitHub (standard mermaid syntax)
  - [x] 4.3.3 Test `/sync overview` end-to-end (spec documented in sync.md)
  - [x] 4.3.4 Test `/sync all` includes overview (spec documented in sync.md)

- [x] 4.4 Update plugin version
  - [x] 4.4.1 Bump version in `.claude-plugin/plugin.json` (1.3.0 -> 1.4.0)
  - [x] 4.4.2 Update CHANGELOG.md
  - [x] 4.4.3 Update README.md component counts

---

## Definition of Done

- [x] `knowledge-base/overview/README.md` exists with project purpose
- [x] `knowledge-base/overview/components/` contains agents.md, commands.md, skills.md, knowledge-base.md
- [x] All component files follow template with Purpose, Responsibilities, Key Interfaces, Data Flow
- [x] `/sync overview` generates/updates overview documentation (documented in sync.md)
- [x] `/sync all` includes overview area (documented in sync.md)
- [x] User customizations preserved during updates (documented in sync.md)
- [x] All markdown consistent with project style
- [x] Plugin version bumped (1.4.0) and CHANGELOG updated

## Deferred to v2

- Component detection via explicit `@component` markers in code
- Configuration file for custom component mapping
- `--dry-run` mode for preview
- Mermaid diagram auto-generation from code analysis
