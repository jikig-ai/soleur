## ADDED Requirements

### Requirement: Decision data structure

The system SHALL represent decisions with content, timestamp, session reference, and optional tags.

#### Scenario: Decision creation
- **WHEN** a decision is recorded
- **THEN** it SHALL include the decision text, ISO timestamp, and source session UUID

#### Scenario: Decision tagging
- **WHEN** a decision is recorded with tags
- **THEN** the tags SHALL be stored (e.g., "pricing", "target-market", "architecture")

### Requirement: Markdown persistence

The system SHALL persist decisions as markdown files in `~/.soleur/decisions/`.

#### Scenario: File naming
- **WHEN** decisions are saved for a project
- **THEN** they SHALL be written to `~/.soleur/decisions/{project-name}.md`

#### Scenario: Markdown format
- **WHEN** a decision is appended
- **THEN** it SHALL be formatted as: `- [YYYY-MM-DD HH:MM] {decision text}`

#### Scenario: File creation
- **WHEN** first decision is recorded for a project
- **THEN** the file SHALL be created with a header: `# Decision Ledger: {project-name}`

### Requirement: Decision recording commands

The system SHALL provide commands to record and view decisions.

#### Scenario: Manual decision recording
- **WHEN** user types `/decide <text>`
- **THEN** the decision SHALL be appended to the current project's ledger

#### Scenario: View decisions command
- **WHEN** user types `/decisions`
- **THEN** all decisions for the current project SHALL be displayed

### Requirement: Decision export

The system SHALL support exporting decisions.

#### Scenario: Export to file
- **WHEN** user requests decision export
- **THEN** the full decision ledger SHALL be copied to a specified path

#### Scenario: Inline display
- **WHEN** user views decisions in CLI
- **THEN** decisions SHALL be displayed with timestamps and session context

### Requirement: Project association

Decisions SHALL be associated with a project name derived from context.

#### Scenario: Project from directory
- **WHEN** no explicit project name is set
- **THEN** the current directory name SHALL be used as the project name

#### Scenario: Explicit project name
- **WHEN** user sets project name via `/project <name>`
- **THEN** that name SHALL be used for the decision ledger filename
