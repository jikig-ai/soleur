//! Decision Ledger
//!
//! Tracks key strategic decisions made during sparring sessions.

use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use std::path::PathBuf;
use uuid::Uuid;

use crate::error::{Result, SoleurError};

/// How a decision was recorded
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub enum DecisionSource {
    /// Manually recorded via /decide command
    Manual,
    /// Auto-detected from agent response
    AutoDetected,
}

impl std::fmt::Display for DecisionSource {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            DecisionSource::Manual => write!(f, "Manual"),
            DecisionSource::AutoDetected => write!(f, "Auto"),
        }
    }
}

/// A strategic decision made during a session
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Decision {
    /// The decision text
    pub content: String,

    /// When the decision was made
    pub timestamp: DateTime<Utc>,

    /// Which session this decision was made in
    pub session_id: Uuid,

    /// Optional tags for categorization
    pub tags: Vec<String>,

    /// How this decision was recorded
    #[serde(default = "default_source")]
    pub source: DecisionSource,
}

fn default_source() -> DecisionSource {
    DecisionSource::Manual
}

impl Decision {
    /// Create a new decision
    pub fn new(content: impl Into<String>, session_id: Uuid, source: DecisionSource) -> Self {
        Self {
            content: content.into(),
            timestamp: Utc::now(),
            session_id,
            tags: Vec::new(),
            source,
        }
    }

    /// Create a new decision with tags
    pub fn with_tags(
        content: impl Into<String>,
        session_id: Uuid,
        tags: Vec<String>,
        source: DecisionSource,
    ) -> Self {
        Self {
            content: content.into(),
            timestamp: Utc::now(),
            session_id,
            tags,
            source,
        }
    }

    /// Format the decision for markdown output
    pub fn to_markdown(&self) -> String {
        let timestamp = self.timestamp.format("%Y-%m-%d %H:%M");
        let source_tag = format!("[{}]", self.source);
        if self.tags.is_empty() {
            format!("- [{}] {} {}", timestamp, source_tag, self.content)
        } else {
            let tags = self.tags.join(", ");
            format!(
                "- [{}] {} [{}] {}",
                timestamp, source_tag, tags, self.content
            )
        }
    }
}

/// Manages the decision ledger for a project
pub struct DecisionLedger {
    /// Directory where decision files are stored
    decisions_dir: PathBuf,
}

/// Validate a project name to prevent path traversal attacks
fn validate_project_name(name: &str) -> Result<()> {
    if name.is_empty() {
        return Err(SoleurError::Validation(
            "Project name cannot be empty".to_string(),
        ));
    }

    if name.contains('/') || name.contains('\\') {
        return Err(SoleurError::Validation(format!(
            "Project name '{}' contains path separators",
            name
        )));
    }

    if name.contains("..") {
        return Err(SoleurError::Validation(format!(
            "Project name '{}' contains path traversal sequence",
            name
        )));
    }

    if name == "." {
        return Err(SoleurError::Validation(
            "Project name cannot be '.'".to_string(),
        ));
    }

    Ok(())
}

impl DecisionLedger {
    /// Create a new decision ledger manager
    pub fn new(decisions_dir: PathBuf) -> Self {
        Self { decisions_dir }
    }

    /// Get the path to a project's decision file
    fn ledger_path(&self, project_name: &str) -> Result<PathBuf> {
        validate_project_name(project_name)?;
        Ok(self.decisions_dir.join(format!("{project_name}.md")))
    }

    /// Append a decision to the project's ledger
    pub fn append(&self, project_name: &str, decision: &Decision) -> Result<()> {
        let path = self.ledger_path(project_name)?;

        // Create file with header if it doesn't exist
        if !path.exists() {
            let header = format!("# Decision Ledger: {project_name}\n\n");
            std::fs::write(&path, header)?;
        }

        // Append the decision
        use std::io::Write;
        let mut file = std::fs::OpenOptions::new().append(true).open(&path)?;
        writeln!(file, "{}", decision.to_markdown())?;

        Ok(())
    }

    /// Load all decisions for a project
    pub fn load(&self, project_name: &str) -> Result<Vec<String>> {
        let path = self.ledger_path(project_name)?;

        if !path.exists() {
            return Ok(Vec::new());
        }

        let content = std::fs::read_to_string(&path)?;
        let decisions: Vec<String> = content
            .lines()
            .filter(|line| line.starts_with("- ["))
            .map(String::from)
            .collect();

        Ok(decisions)
    }

    /// Get the full ledger content for display
    pub fn read_full(&self, project_name: &str) -> Result<Option<String>> {
        let path = self.ledger_path(project_name)?;

        if !path.exists() {
            return Ok(None);
        }

        Ok(Some(std::fs::read_to_string(&path)?))
    }

    /// Check if a project has any decisions
    pub fn has_decisions(&self, project_name: &str) -> Result<bool> {
        Ok(self.ledger_path(project_name)?.exists())
    }

    /// Derive project name from current directory
    pub fn project_name_from_cwd() -> String {
        std::env::current_dir()
            .ok()
            .and_then(|p| p.file_name().map(|s| s.to_string_lossy().to_string()))
            .unwrap_or_else(|| "unknown".to_string())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_decision_to_markdown() {
        let decision = Decision::new("Use PostgreSQL", Uuid::new_v4(), DecisionSource::Manual);
        let md = decision.to_markdown();
        assert!(md.starts_with("- ["));
        assert!(md.contains("Use PostgreSQL"));
        assert!(md.contains("[Manual]"));
    }

    #[test]
    fn test_decision_with_tags() {
        let decision = Decision::with_tags(
            "Use PostgreSQL",
            Uuid::new_v4(),
            vec!["database".to_string()],
            DecisionSource::AutoDetected,
        );
        let md = decision.to_markdown();
        assert!(md.contains("[database]"));
        assert!(md.contains("[Auto]"));
    }

    #[test]
    fn test_project_name_from_cwd() {
        let name = DecisionLedger::project_name_from_cwd();
        assert!(!name.is_empty());
    }

    #[test]
    fn test_validate_project_name_valid() {
        assert!(validate_project_name("my-project").is_ok());
        assert!(validate_project_name("my_project").is_ok());
        assert!(validate_project_name("project123").is_ok());
    }

    #[test]
    fn test_validate_project_name_path_traversal() {
        assert!(validate_project_name("../etc/passwd").is_err());
        assert!(validate_project_name("..").is_err());
        assert!(validate_project_name("foo/bar").is_err());
        assert!(validate_project_name("foo\\bar").is_err());
        assert!(validate_project_name(".").is_err());
        assert!(validate_project_name("").is_err());
    }
}
