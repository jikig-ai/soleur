//! Session Management
//!
//! Handles conversation state with message history and decision tracking.

use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

use super::Decision;
use crate::providers::{Message, Role};

/// A conversation session with an agent
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Session {
    /// Unique identifier for this session
    pub id: Uuid,

    /// Type of agent this session is with
    pub agent_type: String,

    /// Optional project context (e.g., README content)
    pub project_context: Option<String>,

    /// Name of the project (for decision ledger)
    pub project_name: String,

    /// Messages in this conversation
    pub messages: Vec<Message>,

    /// Key decisions made during this session
    pub decisions: Vec<Decision>,

    /// When the session was created
    pub created_at: DateTime<Utc>,

    /// When the session was last updated
    pub updated_at: DateTime<Utc>,
}

impl Session {
    /// Create a new session
    pub fn new(agent_type: impl Into<String>, project_name: impl Into<String>) -> Self {
        let now = Utc::now();
        Self {
            id: Uuid::new_v4(),
            agent_type: agent_type.into(),
            project_context: None,
            project_name: project_name.into(),
            messages: Vec::new(),
            decisions: Vec::new(),
            created_at: now,
            updated_at: now,
        }
    }

    /// Add a message to the session
    pub fn add_message(&mut self, message: Message) {
        self.messages.push(message);
        self.updated_at = Utc::now();
    }

    /// Add a user message
    pub fn add_user_message(&mut self, content: impl Into<String>) {
        self.add_message(Message::user(content));
    }

    /// Add an assistant message
    pub fn add_assistant_message(&mut self, content: impl Into<String>) {
        self.add_message(Message::assistant(content));
    }

    /// Add a decision to the session
    pub fn add_decision(&mut self, content: impl Into<String>) -> &Decision {
        let decision = Decision::new(content, self.id);
        self.decisions.push(decision);
        self.updated_at = Utc::now();
        self.decisions.last().unwrap()
    }

    /// Add a decision with tags
    pub fn add_decision_with_tags(
        &mut self,
        content: impl Into<String>,
        tags: Vec<String>,
    ) -> &Decision {
        let mut decision = Decision::new(content, self.id);
        decision.tags = tags;
        self.decisions.push(decision);
        self.updated_at = Utc::now();
        self.decisions.last().unwrap()
    }

    /// Set the project context
    pub fn set_context(&mut self, context: impl Into<String>) {
        self.project_context = Some(context.into());
        self.updated_at = Utc::now();
    }

    /// Get all user and assistant messages (excluding system)
    pub fn conversation_messages(&self) -> Vec<&Message> {
        self.messages
            .iter()
            .filter(|m| m.role != Role::System)
            .collect()
    }

    /// Get a preview of the last message (truncated)
    pub fn last_message_preview(&self, max_len: usize) -> Option<String> {
        self.messages.last().map(|m| {
            if m.content.len() > max_len {
                format!("{}...", &m.content[..max_len])
            } else {
                m.content.clone()
            }
        })
    }

    /// Get the total number of messages
    pub fn message_count(&self) -> usize {
        self.messages.len()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_new_session() {
        let session = Session::new("sparring-partner", "test-project");
        assert!(!session.id.is_nil());
        assert_eq!(session.agent_type, "sparring-partner");
        assert_eq!(session.project_name, "test-project");
        assert!(session.messages.is_empty());
        assert!(session.decisions.is_empty());
    }

    #[test]
    fn test_add_messages() {
        let mut session = Session::new("test", "test");
        session.add_user_message("Hello");
        session.add_assistant_message("Hi there!");

        assert_eq!(session.messages.len(), 2);
        assert_eq!(session.messages[0].role, Role::User);
        assert_eq!(session.messages[1].role, Role::Assistant);
    }

    #[test]
    fn test_add_decision() {
        let mut session = Session::new("test", "test");
        let session_id = session.id;
        session.add_decision("Use PostgreSQL instead of MySQL");

        assert_eq!(session.decisions.len(), 1);
        assert_eq!(
            session.decisions[0].content,
            "Use PostgreSQL instead of MySQL"
        );
        assert_eq!(session.decisions[0].session_id, session_id);
    }

    #[test]
    fn test_last_message_preview() {
        let mut session = Session::new("test", "test");
        session.add_user_message("This is a long message that should be truncated");

        let preview = session.last_message_preview(20);
        assert_eq!(preview, Some("This is a long messa...".to_string()));
    }
}
