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

- [ ] 2.1 Define YAML frontmatter schema
  - [ ] 2.1.1 Document required fields (component, updated, primary_location)
  - [ ] 2.1.2 Document optional fields (related_locations, status, auto_generated)

- [ ] 2.2 Document section structure
  - [ ] 2.2.1 Define mandatory sections (Purpose, Responsibilities, Key Interfaces)
  - [ ] 2.2.2 Define optional sections (Diagram, Examples, Related Files)
  - [ ] 2.2.3 Document which sections are auto-generated vs user-maintained

- [ ] 2.3 Add template to spec-templates skill
  - [ ] 2.3.1 Add component template to `plugins/soleur/skills/spec-templates/SKILL.md`

## Phase 3: /sync Integration

Extend `/sync` command with `overview` area.

- [ ] 3.1 Update sync command specification
  - [ ] 3.1.1 Add `overview` to valid areas list in `plugins/soleur/commands/soleur/sync.md`
  - [ ] 3.1.2 Document output mapping for overview area
  - [ ] 3.1.3 Add component detection algorithm documentation

- [ ] 3.2 Implement overview analysis phase
  - [ ] 3.2.1 Add component detection logic (architectural boundaries heuristic)
  - [ ] 3.2.2 Add README.md generation/update logic
  - [ ] 3.2.3 Add component file generation logic

- [ ] 3.3 Implement preservation logic
  - [ ] 3.3.1 Detect existing user customizations via frontmatter
  - [ ] 3.3.2 Implement merge strategy for auto-generated sections only
  - [ ] 3.3.3 Handle deprecated components (add status, do not delete)

- [ ] 3.4 Add review phase for overview
  - [ ] 3.4.1 Present detected components for user approval
  - [ ] 3.4.2 Allow Accept/Skip/Edit for each component

## Phase 4: Polish

Final refinements and documentation.

- [ ] 4.1 Add mermaid diagrams to component files
  - [ ] 4.1.1 CLI data flow diagram
  - [ ] 4.1.2 Plugin loading sequence diagram
  - [ ] 4.1.3 Converter pipeline diagram

- [ ] 4.2 Update constitution.md
  - [ ] 4.2.1 Add overview convention: "overview/ documents what the project does; constitution.md documents how to work on it"
  - [ ] 4.2.2 Add component template convention

- [ ] 4.3 Verification
  - [ ] 4.3.1 Run markdownlint on all overview files
  - [ ] 4.3.2 Verify mermaid diagrams render in GitHub
  - [ ] 4.3.3 Test `/sync overview` end-to-end
  - [ ] 4.3.4 Test `/sync all` includes overview

- [ ] 4.4 Update plugin version
  - [ ] 4.4.1 Bump version in `.claude-plugin/plugin.json`
  - [ ] 4.4.2 Update CHANGELOG.md
  - [ ] 4.4.3 Update README.md component counts

---

## Definition of Done

- [ ] `knowledge-base/overview/README.md` exists with project purpose
- [ ] `knowledge-base/overview/components/` contains cli.md, plugins.md, converters.md, targets.md
- [ ] All component files follow template with Purpose, Responsibilities, Key Interfaces, Data Flow
- [ ] `/sync overview` generates/updates overview documentation
- [ ] `/sync all` includes overview area
- [ ] User customizations preserved during updates
- [ ] All markdown passes markdownlint
- [ ] Plugin version bumped and CHANGELOG updated

## Deferred to v2

- Component detection via explicit `@component` markers in code
- Configuration file for custom component mapping
- `--dry-run` mode for preview
- Mermaid diagram auto-generation from code analysis
