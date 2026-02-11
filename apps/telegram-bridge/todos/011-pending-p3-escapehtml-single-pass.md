---
status: pending
priority: p3
issue_id: "011"
tags: [code-review, performance]
dependencies: []
---

# Collapse escapeHtml into single regex pass

## Problem Statement

`escapeHtml()` runs 3 sequential `.replace()` calls, scanning the full string each time.

## Findings

- **performance-oracle**: "~2.5x improvement in escapeHtml, ~15-20% overall markdownToHtml improvement"

## Proposed Solutions

Single regex with character class and switch callback:
```typescript
function escapeHtml(text: string): string {
  return text.replace(/[&<>]/g, (ch) => {
    switch (ch) {
      case "&": return "&amp;";
      case "<": return "&lt;";
      case ">": return "&gt;";
      default: return ch;
    }
  });
}
```
- **Effort**: Small
- **Risk**: Low

## Acceptance Criteria
- [ ] escapeHtml uses single regex pass
- [ ] markdownToHtml rule ordering fixed (headings/italic before code restoration)

## Work Log
- 2026-02-11: Identified during /soleur:review
