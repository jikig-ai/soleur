//! Model Provider Abstraction
//!
//! Defines the strategy pattern interface for AI model providers.

use async_trait::async_trait;
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use std::pin::Pin;
use tokio_stream::Stream;

use crate::error::Result;

/// Role of a message in a conversation
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum Role {
    /// System message (instructions to the model)
    System,
    /// User message
    User,
    /// Assistant (model) response
    Assistant,
}

/// A message in a conversation
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Message {
    /// Role of the message sender
    pub role: Role,
    /// Content of the message
    pub content: String,
    /// When the message was created
    pub timestamp: DateTime<Utc>,
}

impl Message {
    /// Create a new message with the current timestamp
    pub fn new(role: Role, content: impl Into<String>) -> Self {
        Self {
            role,
            content: content.into(),
            timestamp: Utc::now(),
        }
    }

    /// Create a system message
    pub fn system(content: impl Into<String>) -> Self {
        Self::new(Role::System, content)
    }

    /// Create a user message
    pub fn user(content: impl Into<String>) -> Self {
        Self::new(Role::User, content)
    }

    /// Create an assistant message
    pub fn assistant(content: impl Into<String>) -> Self {
        Self::new(Role::Assistant, content)
    }
}

/// Configuration for a completion request
#[derive(Debug, Clone)]
pub struct CompletionConfig {
    /// Model ID to use (e.g., "claude-opus-4-5-20251101")
    pub model: String,
    /// Sampling temperature (0.0 - 1.0)
    pub temperature: f32,
    /// Maximum tokens to generate
    pub max_tokens: u32,
}

impl Default for CompletionConfig {
    fn default() -> Self {
        Self {
            model: crate::config::DEFAULT_MODEL.to_string(),
            temperature: 0.7,
            max_tokens: 4096,
        }
    }
}

/// A streaming chunk from the model
#[derive(Debug, Clone)]
pub struct StreamChunk {
    /// Text content of this chunk
    pub text: String,
    /// Whether this is the final chunk
    pub done: bool,
}

/// Type alias for the streaming response
pub type StreamResponse = Pin<Box<dyn Stream<Item = Result<StreamChunk>> + Send>>;

/// Trait for AI model providers (Strategy Pattern)
///
/// Implementations of this trait provide access to different AI models
/// (Claude, GPT, Gemini, etc.) through a unified interface.
#[async_trait]
pub trait ModelProvider: Send + Sync {
    /// Get the provider name (e.g., "anthropic", "openai")
    fn name(&self) -> &str;

    /// Get the current model ID
    fn model_id(&self) -> &str;

    /// Generate a completion for the given messages
    ///
    /// Returns a stream of text chunks for real-time display.
    async fn complete(
        &self,
        messages: &[Message],
        system: Option<&str>,
        config: &CompletionConfig,
    ) -> Result<StreamResponse>;

    /// Generate a completion and collect the full response
    ///
    /// Convenience method that collects all chunks into a single string.
    async fn complete_full(
        &self,
        messages: &[Message],
        system: Option<&str>,
        config: &CompletionConfig,
    ) -> Result<String> {
        use tokio_stream::StreamExt;

        let mut stream = self.complete(messages, system, config).await?;
        let mut result = String::new();

        while let Some(chunk) = stream.next().await {
            let chunk = chunk?;
            result.push_str(&chunk.text);
        }

        Ok(result)
    }
}
