---
title: Log-injection sanitization must strip Unicode line separators (U+2028/U+2029) and DEL, not just C0 controls
date: 2026-04-17
category: security-issues
tags: [log-injection, sanitization, unicode, plausible, analytics-track]
pr: 2445
issue: 2383
---

# Log-injection sanitization: C0 is necessary but not sufficient

## Problem

`/api/analytics/track` logs attacker-controlled `goal` and `err` strings to pino. Plan #2383 prescribed stripping `[\x00-\x1f]` before `log.warn` — the pattern already used in `rejectCsrf` (`lib/auth/validate-origin.ts:42`). The security-sentinel review of PR #2445 flagged this as incomplete:

- `U+2028` (line separator) and `U+2029` (paragraph separator) pass through JSON.stringify verbatim.
- `\x7f` (DEL) is outside the C0 range but renders as a line break in many terminals.
- Many log viewers (Better Stack, Sentry breadcrumbs, Grafana Loki when rendering JSON on a single line) treat U+2028/U+2029 as line terminators — re-enabling log injection through a "sanitized" `goal`.

An attacker sending `goal: "kb.opened\u2028[FAKE] fake-event"` would see the `[FAKE]` line appear as a forged log entry in the viewer even though pino emitted it as part of a single JSON payload.

## Solution

Replace `/[\x00-\x1f]/g` with `/[\x00-\x1f\x7f\u2028\u2029]/g` everywhere log-injection sanitization is applied:

```ts
export function sanitizeForLog(s: string): string {
  return s.replace(/[\x00-\x1f\x7f\u2028\u2029]/g, "");
}
```

Length-cap upstream (`String(err).slice(0, 500)`) before replace so pathological stack traces don't bloat logs.

## Key insight

**"Strip control characters" is ambiguous.** The C0 range (`\x00-\x1f`) covers `\n`, `\r`, `\t`, `\b` and friends — the common attack vectors. But the *observable* attack surface is whatever renders as a line break in a log viewer. For JSON-structured logs consumed by web UIs, that includes U+2028 and U+2029. For plaintext logs consumed by terminals, it also includes DEL.

When reviewing a log-sanitization implementation, the test is "what characters does the downstream viewer treat as a line terminator," not "what characters are in the C0 range."

## Prevention

1. Add to AGENTS.md Code Quality: log-injection sanitization regex MUST include `\x7f`, `\u2028`, `\u2029` alongside the C0 range. A C0-only strip passes CodeQL but fails security review.
2. When writing a new "sanitize before log" helper, grep the repo for existing implementations (`rejectCsrf` style) and either reuse or upgrade them — do NOT copy an incomplete pattern forward.
3. Plan skill should add a "log sanitization completeness" check item when a plan proposes stripping control characters from logged user input.

## Session Errors (compound Phase 0.5)

- **Plan T5b expected-value typo.** Plan prescribed `expect(ctx.goal).toBe("kb.opendLINE2")` (missing `e`). Input is `"kb.opened\r\nLINE2"`, correct output is `"kb.openedLINE2"`. Recovery: one-line edit to the test after the first GREEN run failed on this single assertion. **Prevention:** plan skill should regenerate expected test values by mechanically applying the described transformation to the input, not by typing them out.
- **Plan did not call out U+2028/U+2029.** See main body — caught only at review time. **Prevention:** codify in AGENTS.md.
- **Plan did not cap the `dropped` keys debug log.** Attacker can emit unbounded log volume via 10k random props. Caught by security review P3. Recovery: added `MAX_DROPPED_KEYS_LOGGED = 20` cap in `sanitize.ts`. **Prevention:** plan skill should flag any `log.debug({ collection })` pattern where the collection originates from iterated user input.
- **Performance agent over-classified P1.** Test handle accumulation from `vi.resetModules()` + module-level `setInterval` is P2 at worst (matches 4 existing throttles, `.unref()` prevents hang, full suite runs cleanly in 24 s). Recovery: re-classified as debatable P2, filed no scope-out because it's functionally equivalent to the existing convention. **Prevention:** when evaluating review P1 claims, cross-check against existing codebase conventions and measured test-run behavior before accepting severity.

## References

- Source patch: `apps/web-platform/app/api/analytics/track/sanitize.ts`
- Existing pattern source: `apps/web-platform/lib/auth/validate-origin.ts:42`
- Related: `knowledge-base/project/learnings/security-issues/websocket-rate-limiting-xff-trust-20260329.md` (companion finding from the same review author)
- PR: <https://github.com/jikig-ai/soleur/pull/2445>
- Issue: <https://github.com/jikig-ai/soleur/issues/2383>
