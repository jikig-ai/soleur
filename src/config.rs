//! Configuration management for Soleur

use crate::error::{Result, SoleurError};
use serde::{Deserialize, Serialize};
use std::path::PathBuf;

/// Default model to use when none is specified
pub const DEFAULT_MODEL: &str = "claude-sonnet-4-20250514";

/// Configuration for Soleur
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Config {
    /// Anthropic API key
    #[serde(default)]
    pub api_key: Option<String>,

    /// Default model to use for completions
    #[serde(default = "default_model")]
    pub default_model: String,

    /// Data directory for sessions and decisions
    #[serde(default = "default_data_dir")]
    pub data_dir: PathBuf,
}

fn default_model() -> String {
    DEFAULT_MODEL.to_string()
}

fn default_data_dir() -> PathBuf {
    dirs::home_dir()
        .map(|h| h.join(".soleur"))
        .unwrap_or_else(|| PathBuf::from(".soleur"))
}

impl Default for Config {
    fn default() -> Self {
        Self {
            api_key: None,
            default_model: default_model(),
            data_dir: default_data_dir(),
        }
    }
}

impl Config {
    /// Load configuration from file and environment variables
    ///
    /// Priority:
    /// 1. Environment variables (ANTHROPIC_API_KEY)
    /// 2. Config file (~/.soleur/config.toml)
    /// 3. Defaults
    pub fn load() -> Result<Self> {
        let mut config = Self::load_from_file().unwrap_or_default();

        // Environment variable override for API key
        if let Ok(api_key) = std::env::var("ANTHROPIC_API_KEY") {
            config.api_key = Some(api_key);
        }

        Ok(config)
    }

    /// Load configuration from the default config file
    fn load_from_file() -> Result<Self> {
        let config_path = default_data_dir().join("config.toml");

        if !config_path.exists() {
            return Ok(Self::default());
        }

        let content = std::fs::read_to_string(&config_path)?;
        let config: Config = toml::from_str(&content)?;
        Ok(config)
    }

    /// Get the API key, returning an error if not configured
    pub fn api_key(&self) -> Result<&str> {
        self.api_key.as_deref().ok_or_else(|| {
            SoleurError::Config(
                "ANTHROPIC_API_KEY not set. Set the environment variable or add api_key to ~/.soleur/config.toml".to_string()
            )
        })
    }

    /// Get the sessions directory path
    pub fn sessions_dir(&self) -> PathBuf {
        self.data_dir.join("sessions")
    }

    /// Get the decisions directory path
    pub fn decisions_dir(&self) -> PathBuf {
        self.data_dir.join("decisions")
    }

    /// Ensure all required directories exist
    pub fn ensure_dirs(&self) -> Result<()> {
        std::fs::create_dir_all(&self.data_dir)?;
        std::fs::create_dir_all(self.sessions_dir())?;
        std::fs::create_dir_all(self.decisions_dir())?;
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_default_config() {
        let config = Config::default();
        assert_eq!(config.default_model, DEFAULT_MODEL);
        assert!(config.api_key.is_none());
    }

    #[test]
    fn test_env_override() {
        // SAFETY: This test runs single-threaded and we restore the var after
        unsafe {
            std::env::set_var("ANTHROPIC_API_KEY", "test-key");
        }
        let config = Config::load().unwrap();
        assert_eq!(config.api_key, Some("test-key".to_string()));
        unsafe {
            std::env::remove_var("ANTHROPIC_API_KEY");
        }
    }
}
