//! Error types for Soleur

use thiserror::Error;

/// Main error type for Soleur operations
#[derive(Error, Debug)]
pub enum SoleurError {
    /// Configuration errors (missing files, invalid format, missing API keys)
    #[error("Configuration error: {0}")]
    Config(String),

    /// API errors (network failures, rate limits, auth failures)
    #[error("API error: {0}")]
    Api(String),

    /// IO errors (file read/write failures)
    #[error("IO error: {0}")]
    Io(#[from] std::io::Error),

    /// Session errors (corrupt data, missing sessions)
    #[error("Session error: {0}")]
    Session(String),

    /// JSON serialization/deserialization errors
    #[error("JSON error: {0}")]
    Json(#[from] serde_json::Error),

    /// TOML parsing errors
    #[error("TOML error: {0}")]
    Toml(#[from] toml::de::Error),

    /// HTTP request errors
    #[error("HTTP error: {0}")]
    Http(#[from] reqwest::Error),

    /// Input validation errors (invalid names, formats, etc.)
    #[error("Validation error: {0}")]
    Validation(String),
}

/// Convenience Result type for Soleur operations
pub type Result<T> = std::result::Result<T, SoleurError>;
