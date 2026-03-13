---
title: validate-seo.sh misses wildcard User-agent blocks
date: 2026-03-03
category: technical-debt
tags: [seo, robots-txt, validation]
severity: low
synced_to: [seo-aeo]
---

# validate-seo.sh Misses Wildcard User-agent Blocks

## Problem

`plugins/soleur/skills/seo-aeo/scripts/validate-seo.sh` only checks for named AI bot entries in `robots.txt` (e.g., `User-agent: GPTBot`). It does not detect wildcard `User-agent: *` blocks that disallow all bots, producing false negatives when a site blocks everything via wildcard.

## Evidence

A test explicitly documents this limitation:

```typescript
// plugins/soleur/test/validate-seo.test.ts:111-117
"does not flag wildcard User-agent block (known limitation)"
// Script only checks named AI bots, not wildcard rules
```

## Key Insight

The fix is straightforward (parse `User-agent: *` blocks for `Disallow: /`), but needs care to avoid false positives since many sites use `User-agent: *` with specific path restrictions that are benign.

## Tags

seo, robots-txt, validation
