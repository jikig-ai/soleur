---
module: web-platform / dashboard refactor
date: 2026-04-14
problem_type: code_quality
component: route_handler / test_design / typescript
symptoms:
  - "Source-string CSP test passed on dead code and broke on refactors"
  - "DOMAIN_LEADERS.color field had zero consumers but persisted as triple SOT"
  - "Shared mock factories silently miss new hook fields, breaking 2-of-8 call sites"
root_cause: missing_behavioral_assertion / dead_data_drift / no_compile_time_drift_detection
severity: medium
tags: [csp, behavioral-tests, refactor, dead-code, mock-factory, typescript]
synced_to: []
---

# CSP Behavioral Test + Dead-Field Removal + Typed Mock Factory

## Problem

PR #2265 closed three review-issue families in one refactor:

1. **CSP source-string test was tautological + fragile.** The initial test asserted the literal `"default-src 'none'; style-src 'unsafe-inline'"` against itself, then re-grepped the route source for the same string. It passed even when the response was never sent (dead code), and would fail on benign reformatting (whitespace, single→double quotes, extracting to a const). Four reviewers independently flagged it.

2. **`color` field on DOMAIN_LEADERS was triple source-of-truth.** Visual styling moved to `LEADER_BG_COLORS` in `leader-avatar.tsx`. The `color: "violet"`-style field on each leader entry was no longer read by any code path, but lingered as data — risk of drift if a future maintainer trusted it.

3. **`useTeamNames` mock copy-pasted across 8 test files.** Each file inlined ~15 lines of mock state; when the hook gained `iconPaths`/`updateIcon`/`refetch`/`getIconPath`, two test files shipped stale mocks. No compile-time signal — mocks are typed `as any` by Vitest's `vi.mock`.

## Solution

### Pattern A: Behavioral CSP test via directive parsing

Extract the policy into an exported constant, then parse it into a directive Map and assert per-directive guarantees:

```ts
// route.ts
export const KB_BINARY_RESPONSE_CSP =
  "default-src 'none'; style-src 'unsafe-inline'; frame-ancestors 'none'";

// kb-content-csp.test.ts
function parseCsp(policy: string): Map<string, string[]> {
  const directives = new Map<string, string[]>();
  for (const raw of policy.split(";")) {
    const trimmed = raw.trim();
    if (!trimmed) continue;
    const [name, ...sources] = trimmed.split(/\s+/);
    directives.set(name.toLowerCase(), sources);
  }
  return directives;
}

const directives = parseCsp(KB_BINARY_RESPONSE_CSP);

it("blocks framing via frame-ancestors 'none'", () => {
  // CSP frame-ancestors has no default fallback — must be explicit, or any
  // origin can iframe user-uploaded SVG/PDF.
  expect(directives.get("frame-ancestors")).toEqual(["'none'"]);
});

it("does not allow script, img, connect, or object sources", () => {
  for (const d of ["script-src", "img-src", "connect-src", "object-src"]) {
    expect(directives.has(d)).toBe(false);
  }
});
```

Why this survives: it tests the *meaning* of the policy, not its spelling. Reformatting is invisible. Critically, it asserts `frame-ancestors` explicitly because `default-src 'none'` does NOT fall back to `frame-ancestors` (that directive has no default — when absent, framing is allowed).

### Pattern B: Dead-field removal with grep + tsc gate

Before deleting `color` from DOMAIN_LEADERS, verify zero consumers:

```bash
# 1. Verify zero consumers
grep -rE '\.color\b' apps/web-platform/server/domain-leaders.ts
grep -rE 'DOMAIN_LEADERS\[[^\]]+\]\.color' apps/web-platform/
grep -rE 'leader\.color' apps/web-platform/

# 2. Delete the field (in this case via sed)
sed -i '/^    color: "/d' apps/web-platform/server/domain-leaders.ts

# 3. Compile-time gate
npx tsc --noEmit
```

The TS `noEmit` check is the safety net: if any consumer was missed by grep (e.g., destructured access, dynamic key), the structural type narrowing fails the build. The `as const` on DOMAIN_LEADERS makes this airtight — TS knows the exact shape of each tuple element after deletion.

### Pattern C: Typed mock factory with compile-time drift detection

```ts
// test/mocks/use-team-names.ts
import type { useTeamNames } from "@/hooks/use-team-names";

type UseTeamNamesReturn = ReturnType<typeof useTeamNames>;

export function createUseTeamNamesMock(
  overrides?: Partial<UseTeamNamesReturn>,
): UseTeamNamesReturn {
  return {
    names: {},
    iconPaths: {},
    nudgesDismissed: [],
    namingPromptedAt: null,
    loading: false,
    error: null,
    updateName: vi.fn(),
    updateIcon: vi.fn(),
    dismissNudge: vi.fn(),
    refetch: vi.fn(),
    getDisplayName: (id: string) => id.toUpperCase(),
    getBadgeLabel: (id: string) => id.toUpperCase(),
    getIconPath: () => null,
    ...overrides,
  };
}
```

Key trick: the explicit `: UseTeamNamesReturn` return type forces the factory to enumerate every field. When `useTeamNames` gains a field, the factory fails to compile until the new field has a default. All 8 call sites then inherit the fix.

## Key Insight

Three different problems, one shared meta-pattern: **make the test, the type system, or the grep do the work that comments and conventions cannot.**

- Behavioral CSP tests survive refactoring because they test directives, not strings.
- `as const` + `tsc --noEmit` make dead-field deletion a safe operation, not a leap of faith.
- `ReturnType<typeof hook>` on a mock factory turns hook drift into a build error instead of a runtime mock-shape mismatch.

The common failure mode is "the test/check passes on dead code." The fix is always to make the assertion structural rather than syntactic.

## Session Errors

Session errors: none detected. Plan-phase mid-draft claim ("LeaderAvatar uses useTeamNames internally") was caught and corrected via grep before implementation — proper self-correction, not a workflow violation.

## See Also

- `knowledge-base/project/learnings/2026-03-20-nonce-based-csp-nextjs-middleware.md` — middleware-level CSP (Pattern A complements it for response-level CSP)
- `knowledge-base/project/learnings/2026-03-26-hash-based-csp-static-eleventy-site.md` — Eleventy CSP
- `knowledge-base/project/learnings/2026-04-05-supabase-returntype-resolves-to-never.md` — `ReturnType<typeof>` gotcha (related but inverse case)
