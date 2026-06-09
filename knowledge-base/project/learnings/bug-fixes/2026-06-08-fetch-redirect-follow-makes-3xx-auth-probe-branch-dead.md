---
title: "A fetch-based auth probe that classifies on a 3xx status must set redirect:manual — the default follow makes the 3xx branch dead and any test mocking it vacuous"
date: 2026-06-08
category: bug-fixes
module: apps/web-platform/server/github-app.ts
tags: [fetch, redirect, github-api, authorization-probe, vacuous-test, code-review]
related_prs: [4946]
severity: P2
---

# Learning: `redirect: "follow"` makes a 3xx auth-probe branch unreachable

## Problem

The Concierge installation self-heal probes org membership with
`GET /orgs/{org}/members/{login}`, which GitHub answers `204` (member),
`404` (not a member), or **`302`** (requester not visible as an org member).
The new `probeOrgMembership` helper had an explicit branch:

```ts
if (response.status === 404 || response.status === 302) return "not-member";
```

…but it called `githubFetch` WITHOUT `redirect: "manual"`. Node/undici `fetch`
defaults to `redirect: "follow"`, so a real `302` is **auto-followed** to
`/orgs/{org}/public_members/{login}` and never surfaces as `status === 302`.
The `=== 302` branch is **dead code in production**, and the unit test that
"covered" it (`mockMembership(302)` returning a synthetic `{ status: 302 }`
straight from the mocked global `fetch`) is **vacuous** — it validates a code
path the real fetch engine never produces, because the mock bypasses undici's
redirect handling entirely.

Caught by `security-sentinel` at multi-agent review (no implementation-side
check — tsc and the green test both passed).

## Solution

Add `redirect: "manual"` to the probe's `githubFetch` call, matching the
pre-existing correct precedent at `verifyInstallationOwnership`
(`github-app.ts`), which already passed `redirect: "manual"` and checks
`status === 302` directly. Node/undici with `redirect: "manual"` surfaces the
**real** 3xx status (unlike browsers, which return an opaque-redirect filtered
`status 0`), so the `=== 302` branch becomes reachable and deterministic — one
authoritative deny instead of a silent second probe against `/public_members`.

## Key Insight

When a `fetch`-based probe makes an **authorization or classification
decision off a 3xx status**, the default `redirect: "follow"` silently
rewrites the outcome: the 3xx is consumed by the redirect engine and the
branch that reads it is unreachable. Two gates:

1. **Code:** any probe that switches on a 3xx (`301/302/303/307/308`) MUST set
   `redirect: "manual"`. Grep the call site, not just the branch.
2. **Test:** a mock that returns `{ status: 302 }` straight from a stubbed
   `fetch` is vacuous for redirect behavior — it bypasses undici's redirect
   engine, so it green-lights a branch production never reaches. To test
   redirect-sensitive logic for real, either set `redirect: "manual"` in the
   SUT (so the mock's status is what the SUT sees) or exercise the real
   redirect. A green "302 → not-member" test against a follow-mode fetch is
   false confidence.

Reviewer takeaway: when a diff adds a fetch probe whose branches include any
3xx status, confirm the call sets `redirect: "manual"` — otherwise the 3xx
branch is dead and its test is vacuous.

## Session Errors

1. **vitest `vi.mock` factory referenced a top-level `const`** —
   `cc-dispatcher-self-heal-observability.test.ts` referenced
   `mockReportSilentFallback` (declared with `const`) inside the hoisted
   `vi.mock` factory → `ReferenceError: Cannot access 'mockReportSilentFallback'
   before initialization`. Recovery: wrap in `vi.hoisted(() => ({ ... }))`.
   Prevention: already in `work/SKILL.md` — "use `vi.hoisted()` from the start";
   one-off here.
2. **git commit CWD drift** — `git add` failed (`pathspec did not match` /
   doubled `apps/web-platform/apps/web-platform/`) because the Bash CWD had
   persisted inside `apps/web-platform` from earlier `tsc`/`vitest` calls.
   Recovery: `cd <worktree-root> && git add …` in one call. Prevention: already
   in `work/SKILL.md` — chain `cd <worktree-abs-path> && <cmd>` per call; one-off.

## Tags
category: bug-fixes
module: apps/web-platform/server/github-app.ts
