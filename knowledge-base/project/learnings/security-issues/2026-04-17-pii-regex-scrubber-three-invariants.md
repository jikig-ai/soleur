---
module: analytics-track
date: 2026-04-17
problem_type: security_issue
component: api_route
severity: high
symptoms:
  - "Allowlisted path prop leaks PII (email, UUID v1 MAC+timestamp, customer ID) to Plausible"
  - "Regex on user-controlled string has unbounded input (ReDoS surface)"
  - "/g regex + .test() pattern is latent footgun (silent PII leak on future edit)"
root_cause: pii_scrubber_design_invariants
tags: [pii-scrubbing, regex, redos, uuid, security, plausible]
related:
  - 2026-04-15-multi-agent-review-catches-bugs-tests-miss
  - 2026-04-15-negative-space-tests-must-follow-extracted-logic
synced_to: [plan]
---

# Learning: PII regex scrubbers — three invariants that must hold

## Problem

PR #2462 added a server-side PII scrubber to `/api/analytics/track` so that
the allowlisted `path` prop cannot carry emails, UUIDs, or customer IDs to
Plausible. The initial implementation (plan-deepened, TDD'd, test-green) had
three latent defects that only surfaced under multi-agent review:

1. **ReDoS via unbounded input length.** Plan's deepen phase verified regex
   correctness against 11 spec cases + a 2000-char smoke test, declaring "no
   ReDoS exposure." But `isTrackBody` caps goal length and prop key count
   without capping per-string length. A 100KB path with alternating email-ish
   tokens pegged the Node event loop because `EMAIL_RE` = `[^\s/]+@[^\s/]+\.[^\s/]+`
   has two adjacent unbounded `+` groups around the `\.` anchor.

2. **Non-v4 UUID leak.** Plan specified UUID v4 regex
   (`4[0-9a-f]{3}-[89ab]`). v1 UUIDs encode MAC address + timestamp —
   *stronger* PII than v4 — but the v4-restricted regex would pass them
   through unscrubbed. The assumption "UUIDs in paths are v4" was a
   codebase-specific convention (Supabase default) that a motivated caller
   could violate.

3. **Stateful `/g` regex + `.test()` latent footgun.** Module-level `/g`
   regexes combined with `if (RE.test(x)) x = x.replace(RE, ...)` works
   today only because `.replace()` internally resets `lastIndex` on each
   call. Any future edit calling `.test()` twice without a subsequent
   `.replace()` — e.g., to set a metric flag — would silently leak PII on
   alternating calls as `lastIndex` carries between requests.

## Solution

Three invariants, each enforcing one of the above:

### Invariant 1: Bound input length BEFORE regex, not after

```ts
const MAX_SCRUB_INPUT_LEN = MAX_PROP_STRING_LEN * 2; // 400

function scrubPath(value: string): { clean: string; scrubbed: ScrubPatternName[] } {
  const bounded =
    value.length > MAX_SCRUB_INPUT_LEN
      ? value.slice(0, MAX_SCRUB_INPUT_LEN)
      : value;
  // ... regex runs on bounded, not value
}
```

`.slice()` after `.replace()` doesn't help — the engine has already walked
the full string by then. The cap is 2× the output cap so a worst-case
boundary-straddling email still scrubs cleanly.

### Invariant 2: Match PII shape, not PII version

```ts
// WRONG — leaks v1/v3/v5/v7
const UUID_V4_RE = /[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}/gi;

// RIGHT — matches any 8-4-4-4-12 hex shape
const UUID_RE = /[0-9a-f]{8}(?:-|%2d)[0-9a-f]{4}(?:-|%2d)[0-9a-f]{4}(?:-|%2d)[0-9a-f]{4}(?:-|%2d)[0-9a-f]{12}/gi;
```

General pattern: when scrubbing PII, match the **structural shape** that
identifies the token as non-human, not the **version discriminator**
(which attackers and future callers can bypass). A UUID-shaped token in a
path is always an ID, regardless of version.

### Invariant 3: Avoid stateful `/g` + `.test()` — use `.replace()` + compare

```ts
// WRONG — fragile: relies on .replace() resetting lastIndex across calls
if (EMAIL_RE.test(out)) {
  fired.push("email");
  out = out.replace(EMAIL_RE, "[email]");
}

// RIGHT — reuse-safe: single .replace() + reference compare
const next = out.replace(EMAIL_RE, "[email]");
if (next !== out) {
  fired.push("email");
  out = next;
}
```

The `.replace() + compare` form is a single scan (faster) AND doesn't
depend on `lastIndex` reset semantics. Four review agents converged on
this finding independently — the pattern is the kind of latent bug that
unit tests cannot catch because one-call sequences always pass.

### Data-driven table consolidates all three

```ts
const SCRUB_PATTERNS: ReadonlyArray<{
  name: ScrubPatternName;
  re: RegExp;
  sentinel: string;
}> = [
  { name: "email", re: EMAIL_RE, sentinel: "[email]" },
  { name: "uuid",  re: UUID_RE,  sentinel: "[uuid]" },
  { name: "id",    re: LONG_DIGIT_RUN_RE, sentinel: "[id]" },
];

for (const { name, re, sentinel } of SCRUB_PATTERNS) {
  const next = out.replace(re, sentinel);
  if (next !== out) { scrubbed.push(name); out = next; }
}
```

Adding a 4th pattern is one table entry. The loop body inherits Invariant 3.
`ScrubPatternName` literal-union typing gives callers compile-time safety.

## Key Insight

**PII scrubbers are defense-in-depth, but only if the defense actually
holds against a motivated attacker.** Three common shortcuts that break
the defense:

- Slicing AFTER the regex scan (attacker can still pin the event loop).
- Restricting to a version/format variant the app happens to use today
  (attacker controls the input).
- Using `/g` regexes with `.test()` gates whose correctness relies on
  `.replace()` reset semantics (future edit breaks it silently).

The invariants generalize to any security-relevant regex: length-bound
first, match shape not version, prefer single-pass `.replace()` + compare
over `.test()` + `.replace()` pairs.

## Prevention

- **Plan-level:** For PII/security-regex risk sections, state the
  **maximum input size reachable by the regex engine**, not a smoke-test
  number. If upstream callers can send unbounded input, the plan must
  specify a pre-regex length bound. (Routed to `plan` skill Sharp Edges.)
- **Review-level:** multi-agent review with security-sentinel +
  performance-oracle + pattern-recognition-specialist + code-quality
  reliably catches `/g` + `.test()` footguns. All four flagged it on
  PR #2462. Keep this in the review pipeline for security PRs.
- **Test-level:** add ReDoS bound tests that assert elapsed time, not
  just correctness: `expect(Date.now() - t0).toBeLessThan(100)` on
  pathological input.

## Session Errors

1. **Case 12 boundary test used brittle arithmetic** — the exact offset
   where the email starts vs. the 200-char slice boundary was miscalculated
   on first GREEN attempt, causing the sentinel to fall outside the slice
   window.
   **Recovery:** reshaped input so `[email]` sentinel survives slice
   regardless of exact offset math.
   **Prevention:** boundary-slice tests should assert shape (`toContain`,
   `length <=`), not exact character-position arithmetic.

2. **`git add` with worktree-relative paths from app-subdirectory CWD
   failed** with "pathspec did not match" because CWD persisted from a
   prior Bash call.
   **Recovery:** `cd <worktree-root> && git add ...`.
   **Prevention:** existing rule `cq-for-local-verification-of-apps-doppler`
   already covers "shell state does not persist across Bash tool calls."
   No new enforcement needed.

3. **`git stash -u` attempt** blocked by PreToolUse hook
   `guardrails:block-stash-in-worktrees`.
   **Recovery:** hook worked as designed; used `git diff --stat main`
   instead to verify PR didn't touch the failing test files.
   **Prevention:** already hook-enforced by rule `hr-never-git-stash-in-worktrees`.

4. **Plan-deepen verified regex correctness but not ReDoS input-size
   ceiling** — plan's Risks section claimed "no ReDoS" based on a
   2000-char smoke test, but the regex engine can be fed up to Next.js's
   1MB body default.
   **Recovery:** review's security-sentinel caught it; PR added
   `MAX_SCRUB_INPUT_LEN` guard.
   **Prevention:** plan skill Sharp Edges now requires "state the max
   input size reachable by the regex engine, not a cherry-picked smoke
   test." Routed to plan skill in this compound pass.

5. **Plan specified UUID v4 regex** — plan's Implementation section
   wrote `[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}`
   based on spec FR2. Review's security-sentinel flagged that v1 UUIDs
   encode MAC+timestamp (stronger PII) and would leak through.
   **Recovery:** broadened to any 8-4-4-4-12 hex shape.
   **Prevention:** the Invariant 2 learning above (match shape, not
   version) is the durable fix. Captured in this learning.

6. **5 pre-existing parallel vitest flakes** (chat-page, kb-chat-sidebar-a11y,
   kb-chat-sidebar-banner-dismiss) failed in full-suite run but passed in
   isolation.
   **Recovery:** verified by running offending files alone (9/9 + 36/36
   pass); filed as #2505 per `wg-when-tests-fail-and-are-confirmed-pre`.
   **Prevention:** tracking issue exists; root cause (shared jsdom state
   between parallel workers) will be diagnosed separately.

## See Also

- [`2026-04-15-multi-agent-review-catches-bugs-tests-miss.md`](../2026-04-15-multi-agent-review-catches-bugs-tests-miss.md) — 4 review agents converging on the same latent bug is the signal that the pattern is real. This PR's `/g` + `.test()` finding is another instance.
- PR #2503 — implementation.
- Issue #2462 — original PII leak report.
- Issues #2507, #2508 — pre-existing-unrelated scope-outs (historical PII in Plausible + dashboard filter audit).

## Tags

category: security-issues
module: analytics-track
