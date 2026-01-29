//! Decision Ledger
//!
//! Tracks key strategic decisions made during sparring sessions.

use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use std::path::PathBuf;
use uuid::Uuid;

use crate::error::Result;

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
}

impl Decision {
    /// Create a new decision
    pub fn new(content: impl Into<String>, session_id: Uuid) -> Self {
        Self {
            content: content.into(),
            timestamp: Utc::now(),
            session_id,
            tags: Vec::new(),
        }
    }

    /// Create a new decision with tags
    pub fn with_tags(content: impl Into<String>, session_id: Uuid, tags: Vec<String>) -> Self {
        Self {
            content: content.into(),
            timestamp: Utc::now(),
            session_id,
            tags,
        }
    }

    /// Format the decision for markdown output
    pub fn to_markdown(&self) -> String {
        let timestamp = self.timestamp.format("%Y-%m-%d %H:%M");
        if self.tags.is_empty() {
            format!("- [{}] {}", timestamp, self.content)
        } else {
            let tags = self.tags.join(", ");
            format!("- [{}] [{}] {}", timestamp, tags, self.content)
        }
    }
}

/// Manages the decision ledger for a project
pub struct DecisionLedger {
    /// Directory where decision files are stored
    decisions_dir: PathBuf,
}

impl DecisionLedger {
    /// Create a new decision ledger manager
    pub fn new(decisions_dir: PathBuf) -> Self {
        Self { decisions_dir }
    }

    /// Get the path to a project's decision file
    fn ledger_path(&self, project_name: &str) -> PathBuf {
        self.decisions_dir.join(format!("{project_name}.md"))
    }

    /// Append a decision to the project's ledger
    pub fn append(&self, project_name: &str, decision: &Decision) -> Result<()> {
        let path = self.ledger_path(project_name);

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
        let path = self.ledger_path(project_name);

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
        let path = self.ledger_path(project_name);

        if !path.exists() {
            return Ok(None);
        }

        Ok(Some(std::fs::read_to_string(&path)?))
    }

    /// Check if a project has any decisions
    pub fn has_decisions(&self, project_name: &str) -> bool {
        self.ledger_path(project_name).exists()
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
        let decision = Decision::new("Use PostgreSQL", Uuid::new_v4());
        let md = decision.to_markdown();
        assert!(md.starts_with("- ["));
        assert!(md.contains("Use PostgreSQL"));
    }

    #[test]
    fn test_decision_with_tags() {
        let decision = Decision::with_tags(
            "Use PostgreSQL",
            Uuid::new_v4(),
            vec!["database".to_string()],
        );
        let md = decision.to_markdown();
        assert!(md.contains("[database]"));
    }

    #[test]
    fn test_project_name_from_cwd() {
        let name = DecisionLedger::project_name_from_cwd();
        assert!(!name.is_empty());
    }
}
