## ADDED Requirements

### Requirement: Interactive REPL

The system SHALL provide an interactive read-eval-print loop for conversation with agents.

#### Scenario: REPL startup
- **WHEN** user runs `soleur spar`
- **THEN** the system SHALL enter interactive mode with a prompt (e.g., `> `)

#### Scenario: User input processing
- **WHEN** user enters text and presses Enter
- **THEN** the text SHALL be sent to the active agent for processing

#### Scenario: Agent response display
- **WHEN** agent generates a response
- **THEN** tokens SHALL be printed as they arrive (streaming)

#### Scenario: Input history
- **WHEN** user presses up/down arrow keys
- **THEN** previous inputs SHALL be recalled (readline behavior)

### Requirement: Slash commands

The system SHALL support slash commands for REPL control.

#### Scenario: /quit command
- **WHEN** user types `/quit` or `/q`
- **THEN** the session SHALL be saved and the REPL SHALL exit

#### Scenario: /save command
- **WHEN** user types `/save`
- **THEN** the current session SHALL be saved immediately with confirmation

#### Scenario: /load command
- **WHEN** user types `/load <session-id>`
- **THEN** the specified session SHALL be loaded, replacing current context

#### Scenario: /decisions command
- **WHEN** user types `/decisions`
- **THEN** all decisions for the current project SHALL be displayed

#### Scenario: /decide command
- **WHEN** user types `/decide <text>`
- **THEN** the text SHALL be recorded as a decision

#### Scenario: /context command
- **WHEN** user types `/context <filepath>`
- **THEN** the file contents SHALL be attached to the session

#### Scenario: /help command
- **WHEN** user types `/help`
- **THEN** available commands SHALL be listed with descriptions

#### Scenario: Unknown command
- **WHEN** user types an unrecognized slash command
- **THEN** an error message SHALL indicate the command is unknown and suggest `/help`

### Requirement: CLI subcommands

The system SHALL provide subcommands for non-interactive operations.

#### Scenario: spar subcommand
- **WHEN** user runs `soleur spar`
- **THEN** the Strategic Sparring Partner REPL SHALL start

#### Scenario: sessions subcommand
- **WHEN** user runs `soleur sessions`
- **THEN** all saved sessions SHALL be listed

#### Scenario: decisions subcommand
- **WHEN** user runs `soleur decisions`
- **THEN** the decision ledger for the current project SHALL be displayed

### Requirement: Graceful error handling

The system SHALL handle errors without crashing the REPL.

#### Scenario: API error during conversation
- **WHEN** an API error occurs during agent response
- **THEN** the error SHALL be displayed and the REPL SHALL continue accepting input

#### Scenario: Invalid command syntax
- **WHEN** a command is malformed (e.g., `/load` without ID)
- **THEN** usage help SHALL be displayed for that command

#### Scenario: Ctrl+C handling
- **WHEN** user presses Ctrl+C during agent response
- **THEN** the response SHALL be cancelled and REPL SHALL continue

#### Scenario: Ctrl+D handling
- **WHEN** user presses Ctrl+D on empty line
- **THEN** the REPL SHALL exit gracefully (same as /quit)

### Requirement: Visual feedback

The system SHALL provide clear visual feedback during operations.

#### Scenario: Thinking indicator
- **WHEN** agent is processing (before first token)
- **THEN** a spinner or "Thinking..." indicator SHALL be shown

#### Scenario: Session status
- **WHEN** REPL starts
- **THEN** current session ID and project name SHALL be displayed

#### Scenario: Command confirmation
- **WHEN** a command succeeds (e.g., /save)
- **THEN** a confirmation message SHALL be displayed
