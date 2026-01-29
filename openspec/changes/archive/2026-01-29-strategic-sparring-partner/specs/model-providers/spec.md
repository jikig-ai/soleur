## ADDED Requirements

### Requirement: ModelProvider trait abstraction

The system SHALL define a `ModelProvider` trait that abstracts AI model interactions, enabling pluggable backends via the strategy pattern.

#### Scenario: Provider implements required interface
- **WHEN** a new model provider is added
- **THEN** it MUST implement `complete()`, `name()`, and `model_id()` methods

#### Scenario: Provider is runtime-selectable
- **WHEN** the application initializes
- **THEN** the provider SHALL be selected based on configuration without recompilation

### Requirement: Claude provider implementation

The system SHALL include a Claude/Anthropic provider implementation supporting the Messages API.

#### Scenario: Successful API call
- **WHEN** `complete()` is called with valid messages and API key
- **THEN** the provider SHALL return the model's response text

#### Scenario: Streaming response support
- **WHEN** `complete()` is called
- **THEN** the provider SHALL support streaming mode where tokens are yielded as they arrive

#### Scenario: Missing API key
- **WHEN** `complete()` is called without a configured API key
- **THEN** the provider SHALL return an error indicating the missing key

#### Scenario: API error handling
- **WHEN** the Anthropic API returns an error (rate limit, invalid request, etc.)
- **THEN** the provider SHALL return a descriptive error with the API error message

### Requirement: Model configuration

The system SHALL allow configuration of model parameters per request.

#### Scenario: Custom model selection
- **WHEN** a completion request specifies a model ID
- **THEN** that model SHALL be used (e.g., `claude-opus-4-5-20251101`)

#### Scenario: Default model fallback
- **WHEN** no model ID is specified
- **THEN** the system SHALL use `claude-sonnet-4-20250514` as the default

#### Scenario: Temperature configuration
- **WHEN** a completion request specifies temperature
- **THEN** that temperature SHALL be passed to the API

### Requirement: API key configuration

The system SHALL load API keys from environment variables with config file fallback.

#### Scenario: Environment variable takes precedence
- **WHEN** `ANTHROPIC_API_KEY` is set in environment AND in config file
- **THEN** the environment variable value SHALL be used

#### Scenario: Config file fallback
- **WHEN** `ANTHROPIC_API_KEY` is not set in environment
- **THEN** the system SHALL read from `~/.soleur/config.toml`

#### Scenario: No API key available
- **WHEN** no API key is found in environment or config
- **THEN** the system SHALL display a helpful error message explaining how to configure the key
