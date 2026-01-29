## ADDED Requirements

### Requirement: Agent trait abstraction

The system SHALL define an Agent trait that abstracts agent behavior, allowing multiple agent types with different personalities and capabilities.

#### Scenario: Agent provides system prompt
- **WHEN** an agent is initialized
- **THEN** it SHALL provide a system prompt defining its personality and behavior

#### Scenario: Agent processes conversation
- **WHEN** `respond()` is called with a session
- **THEN** the agent SHALL generate a response using the configured model provider

### Requirement: Sparring Partner persona

The Strategic Sparring Partner agent SHALL embody a Socratic advisor persona that challenges business ideas constructively.

#### Scenario: Socratic questioning
- **WHEN** the user presents a business idea
- **THEN** the agent SHALL ask probing questions rather than immediately agreeing or disagreeing

#### Scenario: Challenge assumptions
- **WHEN** the user makes claims (e.g., market size, differentiation)
- **THEN** the agent SHALL ask for evidence or challenge weak assumptions

#### Scenario: Constructive not demoralizing
- **WHEN** identifying weaknesses in an idea
- **THEN** the agent SHALL frame critiques as opportunities for improvement, not failures

#### Scenario: Business domain knowledge
- **WHEN** discussing business strategy
- **THEN** the agent SHALL demonstrate familiarity with startup frameworks (Lean Startup, PMF, GTM, etc.)

### Requirement: Context awareness

The Sparring Partner SHALL incorporate project context into its analysis.

#### Scenario: README analysis
- **WHEN** session has attached README content
- **THEN** the agent SHALL reference specific claims and sections from the README in its questions

#### Scenario: Continuity across exchanges
- **WHEN** a conversation spans multiple exchanges
- **THEN** the agent SHALL maintain awareness of earlier discussion points and decisions

### Requirement: Decision identification

The Sparring Partner SHALL identify and highlight key decisions made during conversation.

#### Scenario: Explicit decision marking
- **WHEN** the user makes a strategic decision (e.g., "Let's target technical founders instead")
- **THEN** the agent SHALL acknowledge it and suggest recording it to the decision ledger

#### Scenario: Decision summary on request
- **WHEN** user asks for decision summary
- **THEN** the agent SHALL list all decisions identified in the current session

### Requirement: Structured output capability

The Sparring Partner SHALL be able to produce structured outputs when requested.

#### Scenario: SWOT analysis
- **WHEN** user requests "give me a SWOT analysis"
- **THEN** the agent SHALL produce a formatted Strengths/Weaknesses/Opportunities/Threats breakdown

#### Scenario: Action items
- **WHEN** user requests "what should I do next?"
- **THEN** the agent SHALL provide prioritized, actionable next steps
