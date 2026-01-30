---
status: pending
priority: p3
issue_id: "006"
tags: [code-review, performance, rust-patterns]
dependencies: []
---

# Unnecessary String Clone in Decision Loop

## Problem Statement

The `project_name` is cloned inside the decision detection loop, creating a new `String` allocation for each decision found. This is likely unnecessary since the callee may only need a reference.

**Why it matters:** Minor inefficiency. In practice, there will rarely be multiple decisions per response, so the impact is negligible. However, it's worth fixing for idiomatic Rust code.

## Findings

### Pattern Recognition Specialist

**Location:** `src/cli/repl.rs`, line 171

```rust
for cap in re.captures_iter(&response) {
    let decision_text = cap[1].trim();
    let project_name = self.session.project_name.clone();  // <-- Clone inside loop
    let decision = self.session.add_decision(decision_text);
    self.decision_ledger.append(&project_name, decision)?;
    // ...
}
```

## Proposed Solutions

### Option 1: Pass reference directly (Recommended)

Check if `decision_ledger.append()` accepts `&str` or `&String`.

```rust
self.decision_ledger.append(&self.session.project_name, decision)?;
```

- **Pros:** Zero allocations, idiomatic
- **Cons:** May require signature change in append()
- **Effort:** Trivial
- **Risk:** None

### Option 2: Clone once before loop

If clone is needed, do it before the loop.

```rust
let project_name = self.session.project_name.clone();
for cap in re.captures_iter(&response) {
    // ... use &project_name
}
```

- **Pros:** Single allocation instead of N
- **Cons:** Still one unnecessary allocation
- **Effort:** Trivial
- **Risk:** None

## Recommended Action

<!-- Filled during triage -->

## Technical Details

**Affected Files:**
- `src/cli/repl.rs`, line 171
- Possibly `src/conversation/decision.rs` (if append signature needs change)

**Components:** Repl, DecisionLedger

**Database Changes:** None

## Acceptance Criteria

- [ ] No unnecessary clones in decision detection loop
- [ ] Tests pass

## Work Log

| Date | Action | Learnings |
|------|--------|-----------|
| 2026-01-30 | Finding discovered during code review | Check ownership requirements before cloning |

## Resources

- [PR/Branch]: Current uncommitted changes on main
