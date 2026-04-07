---
title: "UX agent placeholder secrets trigger GitHub push protection"
date: 2026-04-07
category: integration-issues
tags: [github, push-protection, ux-design, pencil, secrets]
module: knowledge-base/product/design
---

# Learning: UX agent placeholder secrets trigger GitHub push protection

## Problem

The ux-design-lead agent generated wireframes in a .pen (Pencil) file that contained a realistic Stripe API key placeholder (`sk_live_[REDACTED]`) in a form input mockup. GitHub push protection correctly blocked the push, requiring history rewriting to fix.

## Solution

1. Replaced the placeholder with a safe value (`sk_test_example_placeholder_key`)
2. Soft-reset to the last pushed commit to remove the secret from all commit history
3. Recommitted the cleaned files and pushed successfully

## Key Insight

UX agents generating form mockups will naturally include realistic-looking API key placeholders. These trigger GitHub push protection because the pattern matches real Stripe keys. When wireframing token/credential input forms, use obviously fake placeholders (e.g., `your-api-token-here` or `sk_test_example_placeholder_key`) instead of realistic-looking values.

## Session Errors

1. **GitHub push protection blocked push due to Stripe key in .pen file** — Recovery: soft reset + recommit without secret — Prevention: UX agents should use obviously-fake credential placeholders in form mockups. Consider adding a pre-push grep for common API key patterns in design files.
   **Prevention:** Add a note to ux-design-lead agent instructions about using safe placeholder values in form mockups.

2. **`SlidingWindowCounter.allow()` does not exist, should be `isAllowed()`** — Recovery: TypeScript compiler caught it immediately — Prevention: Always check the actual method name by reading the source before calling.
   **Prevention:** Already caught by TypeScript at compile time. No workflow change needed.

3. **CWD confusion running `tsc --noEmit` from wrong directory** — Recovery: Used absolute path to run from correct directory — Prevention: Always use absolute paths or verify CWD before running project-specific commands.
   **Prevention:** The Bash tool CWD persists between commands. Be explicit about which directory commands should run from.

## Tags

category: integration-issues
module: knowledge-base/product/design
