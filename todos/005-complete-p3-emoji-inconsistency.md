---
status: pending
priority: p3
issue_id: "005"
tags: [code-review, style, consistency]
dependencies: []
---

# Emoji Inconsistency in Output

## Problem Statement

The auto-record feature uses an emoji in its output (`println!("📝 Decision recorded...")`), while the manual `/decide` command and all other commands use plain text. This creates an inconsistent user experience.

**Why it matters:** Minor UX issue. The CLAUDE.md guidance says "Only use emojis if the user explicitly requests it."

## Findings

### Git History Analyzer / Pattern Recognition Specialist

**With emoji:** `src/cli/repl.rs`, line 174
```rust
println!("📝 Decision recorded: \"{decision_text}\"");
```

**Without emoji:** `src/cli/repl.rs`, line 231
```rust
println!("Decision recorded: {text}");
```

All other REPL outputs use plain text (e.g., "Session saved.", "Auto-record: ON", etc.).

## Proposed Solutions

### Option 1: Remove emoji (Recommended)

Match existing style by using plain text.

```rust
println!("Decision auto-recorded: \"{decision_text}\"");
```

- **Pros:** Consistent with codebase, follows CLAUDE.md
- **Cons:** Less visual distinction for auto-recorded decisions
- **Effort:** Trivial
- **Risk:** None

### Option 2: Add "Auto:" prefix for distinction

```rust
println!("[Auto] Decision recorded: \"{decision_text}\"");
```

- **Pros:** Clear distinction without emoji
- **Cons:** Slightly longer output
- **Effort:** Trivial
- **Risk:** None

### Option 3: Keep emoji, add to manual /decide too

Make both outputs use emojis for visual consistency.

- **Pros:** Consistent (with emojis)
- **Cons:** Violates CLAUDE.md guidance
- **Effort:** Trivial
- **Risk:** None

## Recommended Action

<!-- Filled during triage -->

## Technical Details

**Affected Files:**
- `src/cli/repl.rs`, line 174

**Components:** Repl::process_input()

**Database Changes:** None

## Acceptance Criteria

- [ ] Auto-recorded and manual decision outputs are visually consistent
- [ ] Follows CLAUDE.md emoji guidance

## Work Log

| Date | Action | Learnings |
|------|--------|-----------|
| 2026-01-30 | Finding discovered during code review | Small inconsistencies accumulate |

## Resources

- [PR/Branch]: Current uncommitted changes on main
