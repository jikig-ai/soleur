---
title: "Gate localhost:3000 behind NODE_ENV in ALLOWED_ORIGINS"
status: pending
priority: p3
tags: [security, auth, hardening]
source: "PR #937 review — security-sentinel, architecture-strategist"
file: "apps/web-platform/lib/auth/resolve-origin.ts"
---

## Description

`http://localhost:3000` is unconditionally in `ALLOWED_ORIGINS`. In production this is not exploitable (Cloudflare won't forward it), but it violates least privilege. Gate it behind `NODE_ENV`:

```typescript
const ALLOWED_ORIGINS = new Set([
  "https://app.soleur.ai",
  ...(process.env.NODE_ENV === "development" ? ["http://localhost:3000"] : []),
]);
```

## Work Log
