---
status: pending
priority: p1
issue_id: "001"
tags: [code-review, security, path-traversal]
dependencies: []
---

# Path Traversal Vulnerability in DecisionLedger

## Problem Statement

The `DecisionLedger::ledger_path()` function uses `project_name` directly in file path construction without sanitization. A malicious or malformed project name containing path traversal sequences (`../`) could write files outside the intended decisions directory.

**Why it matters:** This is a security vulnerability that could allow an attacker to write arbitrary files to the filesystem if they can control the project name.

## Findings

### Security Sentinel Agent (Confidence: 95%)

**Location:** `src/conversation/decision.rs`, lines 74-75

```rust
fn ledger_path(&self, project_name: &str) -> PathBuf {
    self.decisions_dir.join(format!("{project_name}.md"))
}
```

**Attack Vector:** If `project_name` is `"../../../etc/cron.d/malicious"`, the ledger would be written to `/etc/cron.d/malicious.md` (assuming sufficient permissions).

**Evidence:** The project_name flows from user input (directory name, session creation) and is used unsanitized.

## Proposed Solutions

### Option 1: Sanitize project_name (Recommended)

Add a sanitization function to remove or reject path separators and traversal sequences.

```rust
fn sanitize_project_name(name: &str) -> String {
    name.chars()
        .filter(|c| c.is_alphanumeric() || *c == '-' || *c == '_')
        .collect()
}
```

- **Pros:** Simple, defensive, allows legitimate names
- **Cons:** May silently modify project names with special characters
- **Effort:** Small
- **Risk:** Low

### Option 2: Validate and reject invalid names

Return an error for project names containing path separators.

```rust
fn validate_project_name(name: &str) -> Result<(), SoleurError> {
    if name.contains('/') || name.contains('\\') || name.contains("..") {
        return Err(SoleurError::InvalidProjectName(name.to_string()));
    }
    Ok(())
}
```

- **Pros:** Explicit, fails fast, user is informed
- **Cons:** Requires error handling at call sites
- **Effort:** Small-Medium
- **Risk:** Low

### Option 3: Use canonicalize and verify path is within directory

```rust
fn ledger_path(&self, project_name: &str) -> Result<PathBuf, SoleurError> {
    let path = self.decisions_dir.join(format!("{project_name}.md"));
    let canonical = path.canonicalize()?;
    if !canonical.starts_with(&self.decisions_dir) {
        return Err(SoleurError::PathTraversal);
    }
    Ok(canonical)
}
```

- **Pros:** Most robust, handles all edge cases
- **Cons:** Requires path to exist, more complex
- **Effort:** Medium
- **Risk:** Low

## Recommended Action

<!-- Filled during triage -->

## Technical Details

**Affected Files:**
- `src/conversation/decision.rs` (primary fix location)
- Potentially `src/conversation/store.rs` (uses similar pattern)
- `src/cli/repl.rs` (where project_name originates)

**Components:** DecisionLedger, SessionStore

**Database Changes:** None

## Acceptance Criteria

- [ ] Project names with `..` or `/` or `\` do not write outside decisions directory
- [ ] Legitimate project names continue to work
- [ ] Error message is helpful if name is rejected
- [ ] Unit test covers path traversal attempt

## Work Log

| Date | Action | Learnings |
|------|--------|-----------|
| 2026-01-30 | Finding discovered during code review | Path traversal is a common vulnerability in file-based storage |

## Resources

- [PR/Branch]: Current uncommitted changes on main
- [OWASP Path Traversal](https://owasp.org/www-community/attacks/Path_Traversal)
