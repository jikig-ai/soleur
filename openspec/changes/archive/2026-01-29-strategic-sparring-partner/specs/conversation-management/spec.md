## ADDED Requirements

### Requirement: Session data structure

The system SHALL maintain conversation state in a Session structure containing unique ID, messages, decisions, timestamps, and optional project context.

#### Scenario: New session creation
- **WHEN** a new session is created
- **THEN** it SHALL have a unique UUID, empty message list, creation timestamp, and no project context

#### Scenario: Session contains message history
- **WHEN** messages are exchanged during a session
- **THEN** each message SHALL be stored with role (user/assistant/system), content, and timestamp

### Requirement: Session persistence

The system SHALL persist sessions to disk as JSON files in `~/.soleur/sessions/`.

#### Scenario: Auto-save after agent response
- **WHEN** the agent completes a response
- **THEN** the session SHALL be automatically saved to `~/.soleur/sessions/{uuid}.json`

#### Scenario: Session file format
- **WHEN** a session is saved
- **THEN** the JSON file SHALL be human-readable (pretty-printed) and contain all session data

#### Scenario: Load existing session
- **WHEN** a session UUID is provided to the load command
- **THEN** the system SHALL restore the full session state from disk

### Requirement: Session listing

The system SHALL provide a way to list all saved sessions.

#### Scenario: List sessions command
- **WHEN** the user requests session list
- **THEN** the system SHALL display session ID, creation date, and last message preview for each session

#### Scenario: Empty session list
- **WHEN** no sessions exist
- **THEN** the system SHALL indicate "No saved sessions found"

### Requirement: Session resume

The system SHALL support resuming the most recent session automatically.

#### Scenario: Resume last session prompt
- **WHEN** a session exists and user starts a new sparring session
- **THEN** the system SHALL ask "Resume last session? [Y/n]"

#### Scenario: Fresh start option
- **WHEN** user declines to resume
- **THEN** a new session SHALL be created

### Requirement: Project context attachment

The system SHALL allow attaching project context (e.g., README content) to a session.

#### Scenario: Context from file
- **WHEN** user provides a file path via `/context` command
- **THEN** the file contents SHALL be attached to the session and included in agent prompts

#### Scenario: Auto-detect README
- **WHEN** a new session starts and README.md exists in current directory
- **THEN** the system SHALL offer to load it as context
