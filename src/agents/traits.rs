//! Agent Abstraction
//!
//! Defines the interface for AI agents.

use async_trait::async_trait;

use crate::conversation::Session;
use crate::error::Result;
use crate::providers::{CompletionConfig, ModelProvider};

/// Trait for AI agents
///
/// Agents provide specialized behavior and system prompts for different
/// use cases (sparring partner, code reviewer, etc.)
#[async_trait]
pub trait Agent: Send + Sync {
    /// Get the agent's name
    fn name(&self) -> &str;

    /// Get the agent's type identifier
    fn agent_type(&self) -> &str;

    /// Get the system prompt for this agent
    ///
    /// The system prompt defines the agent's personality and behavior.
    /// It may incorporate context from the session.
    fn system_prompt(&self, session: &Session) -> String;

    /// Generate a response to the user's input
    ///
    /// Returns a stream of response chunks for real-time display.
    async fn respond(
        &self,
        session: &Session,
        user_input: &str,
        provider: &dyn ModelProvider,
        config: &CompletionConfig,
    ) -> Result<crate::providers::StreamResponse>;
}
