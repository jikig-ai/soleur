---
title: "Code Review Fixes: Security, Performance & Architecture"
category: security-issues
tags:
  - path-traversal
  - regex-performance
  - llm-safety
  - rust-patterns
  - code-review
module: conversation, cli, agents
symptoms:
  - path traversal vulnerability in file operations
  - regex compiled on every function call
  - implicit contract between prompt and parser
  - no source tracking for LLM-detected decisions
severity: p1-critical
date_discovered: 2026-01-30
date_resolved: 2026-01-30
---

# Code Review Fixes: Security, Performance & Architecture

## Problem Summary

A comprehensive code review of the Soleur project (Rust CLI for founder strategic sparring sessions) identified 6 issues that were successfully resolved:

| Priority | Issue | Category |
|----------|-------|----------|
| P1 | Path traversal vulnerability in DecisionLedger | Security |
| P2 | Regex compiled on every response | Performance |
| P2 | Implicit prompt-parser contract | Architecture |
| P2 | No decision source tracking | Data Integrity |
| P3 | Emoji inconsistency in output | Style |
| P3 | Unnecessary clone inside loop | Performance |

## Root Cause Analysis

### P1-001: Path Traversal Vulnerability

**Location:** `src/conversation/decision.rs:74-75`

The `DecisionLedger::ledger_path()` method used `project_name` directly in file path construction without sanitization:

```rust
// VULNERABLE
fn ledger_path(&self, project_name: &str) -> PathBuf {
    self.decisions_dir.join(format!("{project_name}.md"))
}
```

**Attack Vector:** `project_name = "../../../etc/passwd"` could write files outside the intended decisions directory.

### P2-002: Regex Compilation Performance

**Location:** `src/cli/repl.rs:168`

Regex was compiled on every AI response:

```rust
// INEFFICIENT - ~5 microseconds overhead per call
let re = Regex::new(r"\[DECISION:\s*([^\]]+)\]").unwrap();
```

### P2-003: Implicit Prompt-Parser Contract

The AI prompt in `sparring_partner.rs` instructed `[DECISION: ...]` format while `repl.rs` parsed it with regex - no shared constant, no tests validating they match.

### P2-004: No Decision Source Tracking

Auto-detected decisions from LLM responses were indistinguishable from manually recorded decisions - no audit trail.

## Solution

### Fix 1: Path Traversal - Validation Function

Added `validate_project_name()` in `src/conversation/decision.rs`:

```rust
fn validate_project_name(name: &str) -> Result<()> {
    if name.is_empty() {
        return Err(SoleurError::Validation(
            "Project name cannot be empty".to_string(),
        ));
    }

    if name.contains('/') || name.contains('\\') {
        return Err(SoleurError::Validation(format!(
            "Project name '{}' contains path separators", name
        )));
    }

    if name.contains("..") {
        return Err(SoleurError::Validation(format!(
            "Project name '{}' contains path traversal sequence", name
        )));
    }

    if name == "." {
        return Err(SoleurError::Validation(
            "Project name cannot be '.'".to_string(),
        ));
    }

    Ok(())
}

fn ledger_path(&self, project_name: &str) -> Result<PathBuf> {
    validate_project_name(project_name)?;  // Validate FIRST
    Ok(self.decisions_dir.join(format!("{project_name}.md")))
}
```

### Fix 2: Regex Performance - LazyLock

Used `std::sync::LazyLock` for single compilation in `src/cli/repl.rs`:

```rust
use std::sync::LazyLock;

static DECISION_REGEX: LazyLock<Regex> = LazyLock::new(|| {
    Regex::new(DECISION_MARKER_REGEX)
        .expect("Invalid decision regex pattern")
});
```

### Fix 3: Prompt-Parser Contract - Shared Constants

Created `src/agents/markers.rs`:

```rust
pub const DECISION_MARKER_REGEX: &str = r"\[DECISION:\s*([^\]]+)\]";
pub const DECISION_MARKER_INSTRUCTION: &str = "[DECISION: brief description of the decision]";
```

Both prompt and parser now reference these constants.

### Fix 4: Decision Source Tracking - Enum

Added `DecisionSource` enum in `src/conversation/decision.rs`:

```rust
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub enum DecisionSource {
    Manual,       // User typed /decide
    AutoDetected, // LLM generated marker
}

pub struct Decision {
    pub content: String,
    pub timestamp: DateTime<Utc>,
    pub session_id: Uuid,
    pub tags: Vec<String>,
    #[serde(default = "default_source")]
    pub source: DecisionSource,  // NEW FIELD
}
```

Markdown output now shows: `- [2026-01-30 14:23] [Manual] Decision text`

### Fix 5 & 6: Emoji & Clone

- Changed output from `"📝 Decision recorded:"` to `"Decision auto-recorded:"`
- Moved `project_name.clone()` outside the loop

## Files Modified

| File | Changes |
|------|---------|
| `src/error.rs` | Added `Validation(String)` variant |
| `src/conversation/decision.rs` | Path validation, `DecisionSource` enum, updated Decision struct |
| `src/conversation/session.rs` | Updated `add_decision()` signature |
| `src/conversation/mod.rs` | Export `DecisionSource` |
| `src/agents/markers.rs` | **NEW** - Shared marker constants |
| `src/agents/mod.rs` | Export markers module |
| `src/agents/sparring_partner.rs` | Use marker constant |
| `src/cli/repl.rs` | LazyLock, source tracking, output fix |

## Prevention Strategies

### Code Review Checklist

**Path Security:**
- [ ] Is user input validated before `path.join()`?
- [ ] Are path separators (`/`, `\`) blocked?
- [ ] Are traversal sequences (`..`) blocked?

**Regex Performance:**
- [ ] Is `Regex::new()` inside a hot path?
- [ ] Should use `LazyLock` or `lazy_static`?

**Format Contracts:**
- [ ] Are format definitions duplicated?
- [ ] Is there a test verifying prompt ↔ regex consistency?

**LLM Output:**
- [ ] Is LLM data marked with source tracking?
- [ ] Is parsed data validated before use?

### Rust-Specific Idioms

| Issue | Idiom |
|-------|-------|
| Regex compilation | `static RE: LazyLock<Regex>` |
| Path safety | Validation function + `Result<PathBuf>` |
| LLM output | Newtype + `DecisionSource` enum |
| Cloning | Move outside loop, use references |

## Verification

```bash
# Build
cargo build

# Lint
cargo clippy -- -D warnings

# Format
cargo fmt --all

# Tests (28 passed)
cargo test
```

### Test Coverage Added

- `test_validate_project_name_valid()` - Valid names accepted
- `test_validate_project_name_path_traversal()` - Attack vectors rejected
- `test_decision_marker_matches_instruction()` - Format consistency
- `test_prompt_contains_decision_marker_instruction()` - Prompt uses constant

## Related Documentation

- `DECISION_DETECTION_GUIDE.md` - Comprehensive prevention strategies
- `docs/plans/2026-01-29-feat-automatic-decision-detection-plan.md` - Feature plan
- `todos/001-006-complete-*.md` - Issue tracking files

## Key Learnings

1. **Path Validation is Essential:** Never use user-provided strings directly in file paths
2. **Centralize Markers/Constants:** Prompt instructions and parser regex should live in one place
3. **Source Tracking Matters:** Distinguishing manual vs. auto-detected data improves auditability
4. **LazyLock for Static Regexes:** Compile-once patterns make code efficient without complexity
5. **Backwards Compatibility:** Use `#[serde(default)]` when adding fields to serialized structs
