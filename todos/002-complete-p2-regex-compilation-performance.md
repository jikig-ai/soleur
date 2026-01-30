---
status: pending
priority: p2
issue_id: "002"
tags: [code-review, performance, rust-patterns]
dependencies: []
---

# Regex Compiled on Every Response

## Problem Statement

The decision detection regex is compiled on every call to `process_input()`. Regex compilation involves parsing the pattern, building a finite automaton, and allocating internal data structures - all of which are unnecessarily repeated on each AI response.

**Why it matters:** While the absolute overhead (microseconds) is small for interactive use, this is an anti-pattern that wastes CPU cycles and creates memory churn. It would become significant if batch processing responses.

## Findings

### Performance Oracle Agent

**Location:** `src/cli/repl.rs`, line 168

```rust
let re = Regex::new(r"\[DECISION:\s*([^\]]+)\]").unwrap();
```

**Benchmarks:**
- Regex::new() compilation: ~5,000 ns (5 microseconds)
- Compiled regex matching: ~50-500 ns per match
- Ratio: ~10-100x overhead per response

### Pattern Recognition Specialist

The `.unwrap()` is safe because the regex pattern is a compile-time constant, but using `LazyLock` with `.expect()` is more idiomatic.

## Proposed Solutions

### Option 1: Use std::sync::LazyLock (Recommended)

Use the standard library's lazy initialization (Rust 1.80+, no new dependencies).

```rust
use std::sync::LazyLock;
use regex::Regex;

static DECISION_REGEX: LazyLock<Regex> = LazyLock::new(|| {
    Regex::new(r"\[DECISION:\s*([^\]]+)\]")
        .expect("Invalid decision regex pattern")
});

// In process_input():
if self.auto_record {
    for cap in DECISION_REGEX.captures_iter(&response) {
        // ...
    }
}
```

- **Pros:** No new dependencies, idiomatic Rust 2024, thread-safe, single compilation
- **Cons:** None significant
- **Effort:** Small (3-line change)
- **Risk:** Very Low

### Option 2: Remove regex entirely, use string operations

The pattern is simple enough for basic string operations.

```rust
for part in response.split("[DECISION:").skip(1) {
    if let Some(end) = part.find(']') {
        let decision_text = part[..end].trim();
        // ...
    }
}
```

- **Pros:** Removes entire regex dependency (~200KB binary reduction)
- **Cons:** Less readable, harder to modify pattern later
- **Effort:** Small
- **Risk:** Low

### Option 3: Use regex-lite crate

Replace `regex` with `regex-lite` for smaller binary size.

- **Pros:** ~180KB binary reduction
- **Cons:** Still a dependency, no Unicode (not needed here)
- **Effort:** Small
- **Risk:** Low

## Recommended Action

<!-- Filled during triage -->

## Technical Details

**Affected Files:**
- `src/cli/repl.rs` (add LazyLock static)

**Components:** Repl::process_input()

**Database Changes:** None

## Acceptance Criteria

- [ ] Regex is compiled exactly once (on first use)
- [ ] All existing decision detection tests pass
- [ ] No performance regression

## Work Log

| Date | Action | Learnings |
|------|--------|-----------|
| 2026-01-30 | Finding discovered during code review | Always use lazy statics for constant regex patterns |

## Resources

- [PR/Branch]: Current uncommitted changes on main
- [std::sync::LazyLock docs](https://doc.rust-lang.org/std/sync/struct.LazyLock.html)
