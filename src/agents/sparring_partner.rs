//! Strategic Sparring Partner Agent
//!
//! A Socratic advisor that helps founders stress-test business ideas.

use async_trait::async_trait;

use super::Agent;
use super::markers::DECISION_MARKER_INSTRUCTION;
use crate::conversation::Session;
use crate::error::Result;
use crate::providers::{CompletionConfig, Message, ModelProvider, StreamResponse};

/// Base prompt template for the Sparring Partner agent
/// Note: Decision tracking instruction uses DECISION_MARKER_INSTRUCTION constant
fn build_base_prompt() -> String {
    format!(
        r#"You are a Strategic Sparring Partner - a Socratic business advisor who helps founders stress-test their ideas through rigorous, constructive critique.

## Your Approach

1. **Socratic Method**: Ask probing questions rather than giving immediate answers. Help the founder discover insights through guided inquiry.

2. **Challenge Assumptions**: When the founder makes claims (market size, differentiation, feasibility), ask for evidence. Push back on weak assumptions constructively.

3. **Business Frameworks**: Draw on startup methodology (Lean Startup, PMF, GTM strategy, unit economics, competitive moats) to structure your analysis.

4. **Constructive Critique**: Identify weaknesses as opportunities for improvement, not failures. Frame critiques in terms of "what if" and "have you considered."

5. **Decision Tracking**: When the founder makes a strategic decision during our conversation, acknowledge it explicitly and format it as:
   {}
   This marker helps the system automatically track key choices. Decisions sound like: "Let's focus on...", "We should target...", "I've decided to...", "We'll use X instead of Y."

## Conversation Style

- Be direct and intellectually honest - don't be sycophantic
- Ask one or two focused questions at a time, not a barrage
- When you identify a critical flaw, say so clearly but constructively
- Occasionally summarize key points and decisions made
- If the founder gets defensive, acknowledge their perspective before continuing

## What NOT To Do

- Don't just agree with everything
- Don't overwhelm with too many questions at once
- Don't be harsh or demoralizing
- Don't make up statistics or market data
- Don't give generic startup advice - be specific to their idea

## Structured Outputs

When asked, provide:
- **SWOT Analysis**: Strengths, Weaknesses, Opportunities, Threats
- **Action Items**: Prioritized, concrete next steps
- **Risk Assessment**: Key risks with potential mitigations
- **Decision Summary**: All strategic decisions made in the conversation"#,
        DECISION_MARKER_INSTRUCTION
    )
}

/// The Strategic Sparring Partner agent
pub struct SparringPartner;

impl SparringPartner {
    /// Create a new Sparring Partner agent
    pub fn new() -> Self {
        Self
    }
}

impl Default for SparringPartner {
    fn default() -> Self {
        Self::new()
    }
}

#[async_trait]
impl Agent for SparringPartner {
    fn name(&self) -> &str {
        "Strategic Sparring Partner"
    }

    fn agent_type(&self) -> &str {
        "sparring-partner"
    }

    fn system_prompt(&self, session: &Session) -> String {
        let mut prompt = build_base_prompt();

        // Add project context if available
        if let Some(context) = &session.project_context {
            prompt.push_str("\n\n## Project Context\n\n");
            prompt
                .push_str("The founder has shared the following context about their project:\n\n");
            prompt.push_str("```\n");
            prompt.push_str(context);
            prompt.push_str("\n```\n");
            prompt.push_str("\nUse this context to inform your questions and analysis. Reference specific claims or sections when relevant.");
        }

        // Add previous decisions if any
        if !session.decisions.is_empty() {
            prompt.push_str("\n\n## Decisions Made So Far\n\n");
            for decision in &session.decisions {
                prompt.push_str(&format!("- {}\n", decision.content));
            }
            prompt.push_str("\nBuild on these decisions in your analysis.");
        }

        prompt
    }

    async fn respond(
        &self,
        session: &Session,
        user_input: &str,
        provider: &dyn ModelProvider,
        config: &CompletionConfig,
    ) -> Result<StreamResponse> {
        // Build message history from session
        let mut messages: Vec<Message> = session.messages.to_vec();

        // Add the new user input
        messages.push(Message::user(user_input));

        // Get the system prompt with context
        let system = self.system_prompt(session);

        // Call the provider
        provider.complete(&messages, Some(&system), config).await
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::conversation::DecisionSource;

    #[test]
    fn test_system_prompt_without_context() {
        let agent = SparringPartner::new();
        let session = Session::new("sparring-partner", "test");
        let prompt = agent.system_prompt(&session);

        assert!(prompt.contains("Strategic Sparring Partner"));
        assert!(prompt.contains("Socratic"));
        assert!(!prompt.contains("Project Context"));
    }

    #[test]
    fn test_system_prompt_with_context() {
        let agent = SparringPartner::new();
        let mut session = Session::new("sparring-partner", "test");
        session.set_context("This is my business idea: sell widgets");

        let prompt = agent.system_prompt(&session);

        assert!(prompt.contains("Project Context"));
        assert!(prompt.contains("sell widgets"));
    }

    #[test]
    fn test_system_prompt_with_decisions() {
        let agent = SparringPartner::new();
        let mut session = Session::new("sparring-partner", "test");
        session.add_decision("Target enterprise customers", DecisionSource::Manual);

        let prompt = agent.system_prompt(&session);

        assert!(prompt.contains("Decisions Made So Far"));
        assert!(prompt.contains("Target enterprise customers"));
    }

    #[test]
    fn test_prompt_contains_decision_marker_instruction() {
        let agent = SparringPartner::new();
        let session = Session::new("sparring-partner", "test");
        let prompt = agent.system_prompt(&session);

        // Verify the prompt uses the shared marker instruction
        assert!(prompt.contains(DECISION_MARKER_INSTRUCTION));
    }
}
