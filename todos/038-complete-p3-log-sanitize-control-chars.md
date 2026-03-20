---
title: "Sanitize control characters in rejected origin log"
status: pending
priority: p3
tags: [security, logging, hardening]
source: "PR #937 review — security-sentinel"
file: "apps/web-platform/lib/auth/resolve-origin.ts"
---

## Description

An attacker can inject newlines or control characters into `X-Forwarded-Host` to spoof log entries. Add control character stripping:

```typescript
console.warn(`[callback] Rejected origin: ${computed.slice(0, 100).replace(/[\x00-\x1f]/g, "")}`);
```

## Work Log
