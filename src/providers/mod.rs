//! AI Model Providers
//!
//! This module contains the model provider abstraction and implementations.

mod claude;
mod traits;

pub use claude::ClaudeProvider;
pub use traits::{CompletionConfig, Message, ModelProvider, Role, StreamChunk, StreamResponse};
