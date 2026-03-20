---
status: complete
priority: p2
issue_id: 945
tags: [code-review, quality]
dependencies: []
---

# Add localhost to next.config.ts allowedOrigins for dev

## Problem Statement

`next.config.ts` hardcodes `allowedOrigins: ["app.soleur.ai"]` without including `localhost:3000` for development. While no Server Actions exist yet, this creates a footgun when they are adopted — dev would silently fail.

## Findings

- **Source:** security-sentinel, architecture-strategist, code-quality-analyst
- **Location:** `apps/web-platform/next.config.ts:9-11`

## Proposed Solutions

### Option A: Environment-aware config (Recommended)
```typescript
serverActions: {
  allowedOrigins: process.env.NODE_ENV === "development"
    ? ["app.soleur.ai", "localhost:3000"]
    : ["app.soleur.ai"],
},
```
- **Effort:** Small
- **Risk:** Low

## Recommended Action

Option A.

## Technical Details

- **Affected files:** `apps/web-platform/next.config.ts`

## Acceptance Criteria

- [ ] `allowedOrigins` includes `localhost:3000` in development
- [ ] Production config unchanged

## Work Log

| Date | Action | Notes |
|------|--------|-------|
| 2026-03-20 | Created | Flagged by 3 review agents |
