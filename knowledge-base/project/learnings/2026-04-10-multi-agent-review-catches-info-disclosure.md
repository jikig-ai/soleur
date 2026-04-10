---
title: Multi-agent review catches info disclosure in error rendering
date: 2026-04-10
category: security-issues
tags: [review, security, supabase, error-handling]
module: web-platform/analytics
---

# Learning: Multi-agent review catches info disclosure in error rendering

## Problem

The admin analytics page rendered Supabase error messages directly to the browser:
```tsx
<p>Failed to load analytics data: {errorMsg}</p>
```
Supabase error messages can contain table names, column names, constraint names, and PostgreSQL error codes — leaking database schema to the admin UI.

## Solution

Log the full error server-side and render a generic message:
```tsx
console.error("[analytics] query failed:", usersResult.error ?? convsResult.error);
return <p>Failed to load analytics data. Please try again.</p>;
```

## Key Insight

Error messages from database clients (Supabase, Prisma, etc.) should never be rendered to the UI — even for admin pages. The security-sentinel agent caught this pattern alongside three other P2 issues (dead import, missing query limit, misleading RLS comment) that passed TypeScript checks and all tests. Multi-agent review with security-sentinel, architecture-strategist, and code-simplicity-reviewer running in parallel adds ~3 minutes but catches issues that static analysis and tests miss.

## Session Errors

1. **Churn threshold boundary condition** — `computeMetrics` initially used `>` instead of `>=` for the 7-day churn threshold. TDD caught this: the test expected 7 days = churning but the code computed `7 > 7 = false`. **Prevention:** When implementing boundary conditions, write the test with exact boundary values first (TDD already enforces this).

## Tags

category: security-issues
module: web-platform/analytics
