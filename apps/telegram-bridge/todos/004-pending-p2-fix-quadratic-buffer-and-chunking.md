---
status: pending
priority: p2
issue_id: "004"
tags: [code-review, performance]
dependencies: []
---

# Fix O(n^2) buffer concatenation and message chunking

## Problem Statement

Two quadratic algorithms: (1) stdout buffer uses `buffer += chunk` then `buffer.slice()`, creating O(n^2) allocation for large CLI outputs. (2) `chunkMessage()` slices the remaining string on each iteration, O(n^2/MAX_CHUNK_SIZE) total bytes copied.

## Findings

- **performance-oracle**: HIGH severity -- 200KB response produces ~5MB of intermediates; 1MB produces ~125MB

## Proposed Solutions

### Fix stdout buffer: Use chunk array
Accumulate chunks in an array, only join when a newline is detected.
- **Effort**: Small

### Fix chunkMessage: Track position with index
Replace `remaining.slice()` with index tracking, each character copied exactly once.
- **Effort**: Small

## Acceptance Criteria
- [ ] stdout buffer uses array accumulation, not string concatenation
- [ ] chunkMessage uses index tracking, not string slicing
- [ ] Both are O(n) total allocation

## Work Log
- 2026-02-11: Identified during /soleur:review
