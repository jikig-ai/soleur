//! Claude/Anthropic Provider Implementation

use async_trait::async_trait;
use futures::StreamExt;
use reqwest::Client;
use serde::{Deserialize, Serialize};

use super::traits::{CompletionConfig, Message, ModelProvider, Role, StreamChunk, StreamResponse};
use crate::error::{Result, SoleurError};

const ANTHROPIC_API_URL: &str = "https://api.anthropic.com/v1/messages";
const ANTHROPIC_VERSION: &str = "2023-06-01";

/// Claude provider for Anthropic's API
pub struct ClaudeProvider {
    client: Client,
    api_key: String,
    default_model: String,
}

impl ClaudeProvider {
    /// Create a new Claude provider
    pub fn new(api_key: impl Into<String>, default_model: impl Into<String>) -> Self {
        Self {
            client: Client::new(),
            api_key: api_key.into(),
            default_model: default_model.into(),
        }
    }
}

/// Request body for the Anthropic Messages API
#[derive(Serialize)]
struct AnthropicRequest<'a> {
    model: &'a str,
    max_tokens: u32,
    #[serde(skip_serializing_if = "Option::is_none")]
    system: Option<&'a str>,
    messages: Vec<AnthropicMessage<'a>>,
    stream: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    temperature: Option<f32>,
}

#[derive(Serialize)]
struct AnthropicMessage<'a> {
    role: &'a str,
    content: &'a str,
}

/// Streaming event from Anthropic API
#[derive(Deserialize, Debug)]
#[serde(tag = "type")]
#[allow(dead_code)]
enum StreamEvent {
    #[serde(rename = "message_start")]
    MessageStart { message: MessageInfo },
    #[serde(rename = "content_block_start")]
    ContentBlockStart {
        index: u32,
        content_block: ContentBlock,
    },
    #[serde(rename = "content_block_delta")]
    ContentBlockDelta { index: u32, delta: Delta },
    #[serde(rename = "content_block_stop")]
    ContentBlockStop { index: u32 },
    #[serde(rename = "message_delta")]
    MessageDelta {
        delta: MessageDelta,
        usage: Option<Usage>,
    },
    #[serde(rename = "message_stop")]
    MessageStop,
    #[serde(rename = "ping")]
    Ping,
    #[serde(rename = "error")]
    Error { error: ApiError },
}

#[derive(Deserialize, Debug)]
#[allow(dead_code)]
struct MessageInfo {
    id: String,
    model: String,
    role: String,
}

#[derive(Deserialize, Debug)]
#[allow(dead_code)]
struct ContentBlock {
    #[serde(rename = "type")]
    block_type: String,
    text: Option<String>,
}

#[derive(Deserialize, Debug)]
#[allow(dead_code)]
struct Delta {
    #[serde(rename = "type")]
    delta_type: String,
    text: Option<String>,
}

#[derive(Deserialize, Debug)]
#[allow(dead_code)]
struct MessageDelta {
    stop_reason: Option<String>,
}

#[derive(Deserialize, Debug)]
#[allow(dead_code)]
struct Usage {
    output_tokens: u32,
}

#[derive(Deserialize, Debug)]
struct ApiError {
    message: String,
}

impl ClaudeProvider {
    /// Parse an SSE line into a StreamEvent
    fn parse_sse_line(line: &str) -> Option<Result<StreamEvent>> {
        if line.is_empty() || line.starts_with(':') {
            return None;
        }

        if let Some(data) = line.strip_prefix("data: ") {
            match serde_json::from_str::<StreamEvent>(data) {
                Ok(event) => Some(Ok(event)),
                Err(e) => Some(Err(SoleurError::Api(format!("Failed to parse SSE: {e}")))),
            }
        } else {
            None
        }
    }
}

#[async_trait]
impl ModelProvider for ClaudeProvider {
    fn name(&self) -> &str {
        "anthropic"
    }

    fn model_id(&self) -> &str {
        &self.default_model
    }

    async fn complete(
        &self,
        messages: &[Message],
        system: Option<&str>,
        config: &CompletionConfig,
    ) -> Result<StreamResponse> {
        // Convert messages to Anthropic format (skip system messages, they go in system field)
        let api_messages: Vec<AnthropicMessage> = messages
            .iter()
            .filter(|m| m.role != Role::System)
            .map(|m| AnthropicMessage {
                role: match m.role {
                    Role::User => "user",
                    Role::Assistant => "assistant",
                    Role::System => unreachable!(),
                },
                content: &m.content,
            })
            .collect();

        let request = AnthropicRequest {
            model: &config.model,
            max_tokens: config.max_tokens,
            system,
            messages: api_messages,
            stream: true,
            temperature: Some(config.temperature),
        };

        let response = self
            .client
            .post(ANTHROPIC_API_URL)
            .header("x-api-key", &self.api_key)
            .header("anthropic-version", ANTHROPIC_VERSION)
            .header("content-type", "application/json")
            .json(&request)
            .send()
            .await?;

        if !response.status().is_success() {
            let status = response.status();
            let body = response.text().await.unwrap_or_default();
            return Err(SoleurError::Api(format!(
                "Anthropic API error ({}): {}",
                status, body
            )));
        }

        // Create a stream that processes SSE events
        let byte_stream = response.bytes_stream();

        let stream = byte_stream
            .map(|result| result.map_err(|e| SoleurError::Api(format!("Stream error: {e}"))))
            .scan(String::new(), |buffer, result| {
                let bytes = match result {
                    Ok(b) => b,
                    Err(e) => return std::future::ready(Some(vec![Err(e)])),
                };

                // Append new data to buffer
                if let Ok(text) = std::str::from_utf8(&bytes) {
                    buffer.push_str(text);
                }

                // Process complete lines
                let mut chunks = Vec::new();
                while let Some(newline_pos) = buffer.find('\n') {
                    let line = buffer[..newline_pos].trim().to_string();
                    buffer.drain(..=newline_pos);

                    if let Some(result) = Self::parse_sse_line(&line) {
                        match result {
                            Ok(event) => match event {
                                StreamEvent::ContentBlockDelta { delta, .. } => {
                                    if let Some(text) = delta.text {
                                        chunks.push(Ok(StreamChunk { text, done: false }));
                                    }
                                }
                                StreamEvent::MessageStop => {
                                    chunks.push(Ok(StreamChunk {
                                        text: String::new(),
                                        done: true,
                                    }));
                                }
                                StreamEvent::Error { error } => {
                                    chunks.push(Err(SoleurError::Api(error.message)));
                                }
                                _ => {}
                            },
                            Err(e) => chunks.push(Err(e)),
                        }
                    }
                }

                std::future::ready(Some(chunks))
            })
            .flat_map(futures::stream::iter);

        Ok(Box::pin(stream))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_parse_sse_content_delta() {
        let line = r#"data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Hello"}}"#;
        let result = ClaudeProvider::parse_sse_line(line);
        assert!(result.is_some());
        let event = result.unwrap().unwrap();
        match event {
            StreamEvent::ContentBlockDelta { delta, .. } => {
                assert_eq!(delta.text, Some("Hello".to_string()));
            }
            _ => panic!("Expected ContentBlockDelta"),
        }
    }

    #[test]
    fn test_parse_sse_empty_line() {
        assert!(ClaudeProvider::parse_sse_line("").is_none());
        assert!(ClaudeProvider::parse_sse_line(": comment").is_none());
    }

    #[test]
    fn test_parse_sse_message_stop() {
        let line = r#"data: {"type":"message_stop"}"#;
        let result = ClaudeProvider::parse_sse_line(line);
        assert!(result.is_some());
        let event = result.unwrap().unwrap();
        assert!(matches!(event, StreamEvent::MessageStop));
    }
}
