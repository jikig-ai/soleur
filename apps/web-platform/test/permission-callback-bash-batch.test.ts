// Contract tests for the per-(userId, conversationId) Bash command-prefix
// batched-approval cache (#2921).
//
// T1 — prefix grant + allow exact match
// T2 — prefix allow with extra args (prefix-match)
// T3 — different prefix denied
// T4 — revoke clears the cache
// T5 — cross-conversation isolation (R8 composite key)
// T6 — cross-user isolation
// T7 — TTL expiry (60 min)

import { describe, it, expect, beforeEach, vi } from "vitest";

import {
  getBashApprovalCache,
  deriveBashCommandPrefix,
  _resetBashApprovalCacheForTests,
  BASH_APPROVAL_CACHE_TTL_MS,
} from "@/server/permission-callback-bash-batch";

beforeEach(() => {
  _resetBashApprovalCacheForTests();
  vi.useRealTimers();
});

describe("getBashApprovalCache (#2921)", () => {
  // T1
  it("T1: grant + allow on exact match", () => {
    const cache = getBashApprovalCache("u1", "c1");
    cache.grant("git status");
    expect(cache.allow("git status")).toBe(true);
  });

  // T2
  it("T2: prefix-match allows commands with extra args", () => {
    const cache = getBashApprovalCache("u1", "c1");
    cache.grant("git status");
    expect(cache.allow("git status -s")).toBe(true);
    expect(cache.allow("git status --short")).toBe(true);
  });

  // T3
  it("T3: different prefix is NOT allowed", () => {
    const cache = getBashApprovalCache("u1", "c1");
    cache.grant("git status");
    expect(cache.allow("git push")).toBe(false);
    // Subsumed-different prefix (git status vs git statuses) blocked too —
    // word-boundary match on the prefix tokens.
    expect(cache.allow("git statuses")).toBe(false);
  });

  // T4
  it("T4: revoke() clears the cache", () => {
    const cache = getBashApprovalCache("u1", "c1");
    cache.grant("git status");
    expect(cache.allow("git status")).toBe(true);
    cache.revoke();
    expect(cache.allow("git status")).toBe(false);
  });

  // T5
  it("T5: cross-conversation isolation", () => {
    const ca = getBashApprovalCache("u1", "c1");
    const cb = getBashApprovalCache("u1", "c2");
    ca.grant("git status");
    expect(ca.allow("git status")).toBe(true);
    expect(cb.allow("git status")).toBe(false);
  });

  // T6
  it("T6: cross-user isolation", () => {
    const ca = getBashApprovalCache("u1", "c1");
    const cb = getBashApprovalCache("u2", "c1");
    ca.grant("git status");
    expect(ca.allow("git status")).toBe(true);
    expect(cb.allow("git status")).toBe(false);
  });

  // T7
  it("T7: TTL expiry (default 60min) — stale grant returns false", () => {
    vi.useFakeTimers();
    vi.setSystemTime(new Date("2026-04-27T00:00:00Z"));
    const cache = getBashApprovalCache("u1", "c1");
    cache.grant("git status");
    expect(cache.allow("git status")).toBe(true);

    // Advance just under TTL — still valid
    vi.setSystemTime(Date.now() + BASH_APPROVAL_CACHE_TTL_MS - 1);
    expect(cache.allow("git status")).toBe(true);

    // Advance past TTL — expired
    vi.setSystemTime(Date.now() + 2);
    expect(cache.allow("git status")).toBe(false);
    vi.useRealTimers();
  });
});

describe("deriveBashCommandPrefix", () => {
  it("git verbs widen to two tokens (`git status`, `git diff`, `git log`)", () => {
    expect(deriveBashCommandPrefix("git status")).toBe("git status");
    expect(deriveBashCommandPrefix("git status -s")).toBe("git status");
    expect(deriveBashCommandPrefix("git diff HEAD~1")).toBe("git diff");
    expect(deriveBashCommandPrefix("git log --oneline")).toBe("git log");
    expect(deriveBashCommandPrefix("git push origin main")).toBe("git push");
  });

  it("npm/bun/npx widen sensibly", () => {
    expect(deriveBashCommandPrefix("npm run lint")).toBe("npm run lint");
    expect(deriveBashCommandPrefix("npm run test")).toBe("npm run test");
    expect(deriveBashCommandPrefix("bun test")).toBe("bun test");
    expect(deriveBashCommandPrefix("npx tsc --noEmit")).toBe("npx tsc");
    expect(deriveBashCommandPrefix("npx vitest run")).toBe("npx vitest");
  });

  it("plain commands return their first token", () => {
    expect(deriveBashCommandPrefix("ls -la")).toBe("ls");
    expect(deriveBashCommandPrefix("pwd")).toBe("pwd");
    expect(deriveBashCommandPrefix("cat README.md")).toBe("cat");
  });

  it("empty / whitespace returns empty string", () => {
    expect(deriveBashCommandPrefix("")).toBe("");
    expect(deriveBashCommandPrefix("   ")).toBe("");
  });
});
