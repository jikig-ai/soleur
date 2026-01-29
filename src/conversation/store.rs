//! Session Persistence
//!
//! Handles saving and loading sessions to/from disk.

use std::path::PathBuf;
use uuid::Uuid;

use super::Session;
use crate::error::{Result, SoleurError};

/// Metadata about a saved session (for listing)
#[derive(Debug, Clone)]
pub struct SessionMetadata {
    pub id: Uuid,
    pub agent_type: String,
    pub project_name: String,
    pub message_count: usize,
    pub last_preview: Option<String>,
    pub created_at: chrono::DateTime<chrono::Utc>,
    pub updated_at: chrono::DateTime<chrono::Utc>,
}

/// Manages session persistence
pub struct SessionStore {
    /// Directory where sessions are stored
    sessions_dir: PathBuf,
}

impl SessionStore {
    /// Create a new session store
    pub fn new(sessions_dir: PathBuf) -> Self {
        Self { sessions_dir }
    }

    /// Get the path for a session file
    fn session_path(&self, id: Uuid) -> PathBuf {
        self.sessions_dir.join(format!("{id}.json"))
    }

    /// Save a session to disk
    pub fn save(&self, session: &Session) -> Result<()> {
        let path = self.session_path(session.id);
        let json = serde_json::to_string_pretty(session)?;
        std::fs::write(path, json)?;
        Ok(())
    }

    /// Load a session from disk by ID
    pub fn load(&self, id: Uuid) -> Result<Session> {
        let path = self.session_path(id);

        if !path.exists() {
            return Err(SoleurError::Session(format!("Session {id} not found")));
        }

        let content = std::fs::read_to_string(path)?;
        let session: Session = serde_json::from_str(&content)?;
        Ok(session)
    }

    /// Load a session by ID string (parses UUID)
    pub fn load_by_str(&self, id_str: &str) -> Result<Session> {
        let id = Uuid::parse_str(id_str)
            .map_err(|e| SoleurError::Session(format!("Invalid session ID: {e}")))?;
        self.load(id)
    }

    /// List all saved sessions with metadata
    pub fn list(&self) -> Result<Vec<SessionMetadata>> {
        let mut sessions = Vec::new();

        if !self.sessions_dir.exists() {
            return Ok(sessions);
        }

        for entry in std::fs::read_dir(&self.sessions_dir)? {
            let entry = entry?;
            let path = entry.path();

            if path.extension().is_some_and(|ext| ext == "json")
                && let Ok(content) = std::fs::read_to_string(&path)
                && let Ok(session) = serde_json::from_str::<Session>(&content)
            {
                let message_count = session.message_count();
                let last_preview = session.last_message_preview(50);
                sessions.push(SessionMetadata {
                    id: session.id,
                    agent_type: session.agent_type,
                    project_name: session.project_name,
                    message_count,
                    last_preview,
                    created_at: session.created_at,
                    updated_at: session.updated_at,
                });
            }
        }

        // Sort by updated_at descending (most recent first)
        sessions.sort_by(|a, b| b.updated_at.cmp(&a.updated_at));

        Ok(sessions)
    }

    /// Get the most recently updated session
    pub fn get_latest(&self) -> Result<Option<Session>> {
        let sessions = self.list()?;

        if let Some(metadata) = sessions.first() {
            Ok(Some(self.load(metadata.id)?))
        } else {
            Ok(None)
        }
    }

    /// Delete a session
    pub fn delete(&self, id: Uuid) -> Result<()> {
        let path = self.session_path(id);

        if path.exists() {
            std::fs::remove_file(path)?;
        }

        Ok(())
    }

    /// Check if any sessions exist
    pub fn has_sessions(&self) -> bool {
        self.sessions_dir.exists()
            && std::fs::read_dir(&self.sessions_dir)
                .map(|mut dir| {
                    dir.any(|e| {
                        e.is_ok_and(|e| e.path().extension().is_some_and(|ext| ext == "json"))
                    })
                })
                .unwrap_or(false)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::tempdir;

    #[test]
    fn test_save_and_load() {
        let dir = tempdir().unwrap();
        let store = SessionStore::new(dir.path().to_path_buf());

        let session = Session::new("test-agent", "test-project");
        let id = session.id;

        store.save(&session).unwrap();
        let loaded = store.load(id).unwrap();

        assert_eq!(loaded.id, id);
        assert_eq!(loaded.agent_type, "test-agent");
        assert_eq!(loaded.project_name, "test-project");
    }

    #[test]
    fn test_list_sessions() {
        let dir = tempdir().unwrap();
        let store = SessionStore::new(dir.path().to_path_buf());

        let session1 = Session::new("agent1", "project1");
        let session2 = Session::new("agent2", "project2");

        store.save(&session1).unwrap();
        store.save(&session2).unwrap();

        let list = store.list().unwrap();
        assert_eq!(list.len(), 2);
    }

    #[test]
    fn test_get_latest() {
        let dir = tempdir().unwrap();
        let store = SessionStore::new(dir.path().to_path_buf());

        // No sessions yet
        assert!(store.get_latest().unwrap().is_none());

        let session = Session::new("test", "test");
        let id = session.id;
        store.save(&session).unwrap();

        let latest = store.get_latest().unwrap();
        assert!(latest.is_some());
        assert_eq!(latest.unwrap().id, id);
    }
}
