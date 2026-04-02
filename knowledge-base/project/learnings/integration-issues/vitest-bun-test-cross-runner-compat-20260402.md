---
module: System
date: 2026-04-02
problem_type: integration_issue
component: testing_framework
symptoms:
  - "vi.stubGlobal is not a function in bun test"
  - "vi.importActual is not a function in bun test"
  - "Cannot find module bun:test in vitest/tsc"
  - "Attempted to assign to readonly property when monkey-patching crypto"
  - "TypeScript overload error for generateKeyPairSync without publicKeyEncoding"
root_cause: test_isolation
resolution_type: code_fix
severity: medium
tags: [vitest, bun-test, cross-runner, mocking, crypto, rsa]
---

# Learning: Cross-Runner Test Compatibility (vitest + bun test)

## Problem

The web-platform app runs tests via two runners with different capabilities:

- **vitest** (pre-commit via lefthook `npx vitest run`, and CI)
- **bun test** (pre-push hook on individual affected files)

Test mocking APIs that work in one runner fail in the other:

- `vi.stubGlobal()` -- vitest-only, not in bun's vitest compat layer
- `vi.importActual()` -- vitest-only, not in bun's vitest compat layer
- `vi.mock("crypto", async () => {...})` -- works in vitest, fails in bun
- `bun:test` imports -- work in bun, fail in vitest/tsc (module not found)
- `mock.module()` -- bun-only API
- Monkey-patching module exports -- bun freezes module exports as read-only

## Solution

Avoid mocking entirely when possible. For crypto operations that need a valid RSA key, generate a real test key at module scope:

```typescript
import { generateKeyPairSync } from "crypto";

const { privateKey } = generateKeyPairSync("rsa", {
  modulusLength: 2048,
  publicKeyEncoding: { type: "pkcs1", format: "pem" },
  privateKeyEncoding: { type: "pkcs1", format: "pem" },
});

process.env.GITHUB_APP_PRIVATE_KEY = privateKey;
```

For fetch mocking, use direct `globalThis.fetch` assignment (works in both runners):

```typescript
const mockFetch = vi.fn();
const originalFetch = globalThis.fetch;
globalThis.fetch = mockFetch as unknown as typeof fetch;

afterAll(() => { globalThis.fetch = originalFetch; });
```

Key rules:

1. Always use `vitest` imports (bun has vitest compat, but vitest doesn't have bun compat)
2. Never use `vi.stubGlobal`, `vi.importActual`, or `vi.mock` with async factory -- bun doesn't support them
3. Never use `bun:test` imports -- tsc can't resolve them
4. For TypeScript: `generateKeyPairSync("rsa", ...)` requires both `publicKeyEncoding` and `privateKeyEncoding` to satisfy the overload

## Key Insight

When a test file runs under multiple test runners, use the lowest common denominator for mocking. Real objects (generated keys, direct globalThis assignment) are universally compatible. Runner-specific mock APIs (`vi.mock`, `mock.module`) are not.

## Session Errors

1. **Worktree core.bare=true inheritance** -- Worktrees created from a bare repo inherit `core.bare=true`, causing all git working-tree commands to fail. Recovery: `git config --worktree core.bare false`. **Prevention:** The worktree-manager script should set this automatically after creating a worktree from a bare repo.

2. **vi.stubGlobal not a function in bun** -- Used vitest-specific API. Recovery: Switched to `globalThis.fetch` direct assignment. **Prevention:** Always test with `bun test <file>` before committing test files in web-platform.

3. **vi.importActual not a function in bun** -- Used vitest-specific API. Recovery: Replaced crypto mock with real RSA key generation. **Prevention:** Same as above -- verify both runners.

4. **bun:test module not found in tsc** -- Used bun-specific import. Recovery: Switched back to vitest imports. **Prevention:** Never use `bun:test` imports in web-platform; vitest imports have bun compat but not vice versa.

5. **crypto module read-only in bun** -- Attempted monkey-patch on frozen module exports. Recovery: Used `generateKeyPairSync` instead. **Prevention:** Never monkey-patch node built-in module exports; bun freezes them.

6. **generateKeyPairSync TypeScript overload** -- Missing `publicKeyEncoding` parameter. Recovery: Added both encoding parameters. **Prevention:** Always provide both `publicKeyEncoding` and `privateKeyEncoding` for RSA key pair generation.

7. **Security: identity lookup order** -- Plan specified `user_metadata` first, but review found it's user-mutable via `auth.updateUser()`. Recovery: Reversed to check immutable `identities` first. **Prevention:** Never use `user_metadata` as the primary source for security decisions when `identities` provides an immutable alternative.

## Tags

category: integration-issues
module: System
