---
status: pending
priority: p2
issue_id: "003"
tags: [code-review, architecture, maintainability]
dependencies: []
---

# Implicit Contract Between Prompt and Parser

## Problem Statement

The `[DECISION: ...]` marker format creates an implicit contract between the AI prompt instruction in `sparring_partner.rs` and the regex parser in `repl.rs`. This coupling is not explicitly documented or tested, making it fragile to changes.

**Why it matters:** If someone modifies the prompt or the regex independently, the system will silently fail to detect decisions. As more agents are added, this pattern may need to be duplicated or shared.

## Findings

### Architecture Strategist Agent

**Producer side:** `src/agents/sparring_partner.rs`, lines 24-26
```rust
//   [DECISION: brief description of the decision]
//   This marker helps the system automatically track key choices.
```

**Consumer side:** `src/cli/repl.rs`, lines 168-169
```rust
let re = Regex::new(r"\[DECISION:\s*([^\]]+)\]").unwrap();
```

**SOLID Analysis:**
- **Single Responsibility Violation:** REPL now has two responsibilities (user interaction AND LLM output parsing)
- **Open/Closed Violation:** Adding new structured outputs requires modifying both prompt AND parser

### Pattern Recognition Specialist

No integration test verifies that the regex matches what the prompt instructs. The unit tests in `sparring_partner.rs` do not validate decision marker generation.

## Proposed Solutions

### Option 1: Extract marker constants (Recommended - Minimal change)

Co-locate the format definition in a shared module.

```rust
// src/agents/markers.rs
pub const DECISION_MARKER_REGEX: &str = r"\[DECISION:\s*([^\]]+)\]";
pub const DECISION_MARKER_INSTRUCTION: &str =
    "Format decisions as: [DECISION: brief description]";
```

- **Pros:** Makes contract explicit, easy to test both sides match
- **Cons:** Still a string-based contract
- **Effort:** Small
- **Risk:** Very Low

### Option 2: Create a ResponseParser component

Move parsing logic to a dedicated module.

```rust
// src/agents/response_parser.rs
pub struct ParsedResponse {
    pub raw: String,
    pub decisions: Vec<String>,
}

impl ResponseParser {
    pub fn parse(response: &str) -> ParsedResponse { ... }
}
```

- **Pros:** Single Responsibility, testable, extensible for future markers
- **Cons:** More abstraction for current simple use case
- **Effort:** Medium
- **Risk:** Low

### Option 3: Add integration test (Complementary)

Create a test that validates the regex against sample LLM output.

```rust
#[test]
fn test_decision_marker_detection() {
    let sample = "Let me acknowledge that. [DECISION: Focus on enterprise customers]";
    let re = Regex::new(DECISION_MARKER_REGEX).unwrap();
    let caps = re.captures(sample).unwrap();
    assert_eq!(caps[1].trim(), "Focus on enterprise customers");
}
```

- **Pros:** Catches contract breakage in CI
- **Cons:** Doesn't prevent divergence, just detects it
- **Effort:** Small
- **Risk:** Very Low

## Recommended Action

<!-- Filled during triage -->

## Technical Details

**Affected Files:**
- `src/agents/markers.rs` (new, if Option 1 or 2)
- `src/agents/mod.rs` (export new module)
- `src/cli/repl.rs` (import constant)
- `src/agents/sparring_partner.rs` (use constant in prompt)

**Components:** Agent system, REPL

**Database Changes:** None

## Acceptance Criteria

- [ ] Marker format is defined in one place
- [ ] Change to marker format causes test failure if regex not updated
- [ ] Integration test validates end-to-end decision detection

## Work Log

| Date | Action | Learnings |
|------|--------|-----------|
| 2026-01-30 | Finding discovered during code review | Cross-module string contracts should be explicit |

## Resources

- [PR/Branch]: Current uncommitted changes on main
