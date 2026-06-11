# Learning: 11-agent review catches on the release-digest cron (quadratic PII regex, clock-outside-step, live-data sizing)

## Problem

PR #5122 (weekly Discord release digest) passed plan review (5 agents), TDD,
typecheck, and a 21-test suite — and the post-implementation 11-agent review
still surfaced 2 P1s and 7 P2s, all pr-introduced.

## Solution / Key Insights

1. **PII/sanitize regexes must run on PRE-BOUNDED input.** `EMAIL_RE`-class
   patterns (`[A-Za-z0-9._%+-]+@`) are O(n²); a 125k-char GitHub release body
   measured ~17s of synchronous regex — an event-loop stall for the whole
   Next.js process (Inngest crons run in-process). The truncation order
   "sanitize then slice(1500)" silently left the regex on unbounded input.
   Rule: slice raw input to a small multiple of the final budget BEFORE any
   quantified regex; performance-oracle found this only by empirically timing
   the patterns in Node.
2. **`new Date()` in an Inngest handler body is I/O, not pure computation.**
   Inngest v3 re-executes the entire handler body at every step boundary;
   anything computed outside `step.run` from the clock can diverge between
   the memoized data and later steps (Friday-15:00 window straddle). The
   "pure functions don't need steps" simplification is correct for functions
   of memoized inputs — the clock is not one. Four agents independently
   converged on this.
3. **Plan-accepted sizing residuals deserve a live-data probe at review.**
   The plan accepted `per_page=100` as "covers any realistic week (~50–100)";
   git-history-analyzer ran `gh release list` and found the repo at ~100
   releases/week — zero headroom, silent truncation. A residual accepted on
   an estimate should be re-measured once real data is one command away.
4. **Substring alternations in classifier regexes need word boundaries.**
   Bare `rce` matches "sou**rce**" — the security down-detail filter would
   have silently degraded every release mentioning "source" to title-only.
5. **Escape chains: backslash first, always.** A single `<`→`\<` escape is
   bypassable by attacker-supplied `\<@id>` (the injected backslash eats the
   escape). The in-repo precedent (`formatTailForIssue`) already encoded
   "order is load-bearing"; new escape helpers must copy it.
6. **SUT-side catch-and-fallback demands a positive happy-path test.** With
   the curate step converting any Anthropic error to the deterministic
   fallback, a permanently broken LLM integration kept all 21 tests green —
   only an assertion on the curated content + `fallback: false` +
   spy-NOT-called closes that hole (test-design-reviewer).

## Session Errors

1. **`new Response("", { status: 204 })` throws** (204 forbids a body) inside
   the test's fetch mock — surfaced as `ok:false` everywhere and cost a debug
   round. **Prevention:** use `new Response(null, { status })` for 204/205/304
   in fetch mocks.
2. **CWD drift:** one `cd apps/web-platform` failed (already inside).
   **Prevention:** existing rule — absolute paths in worktree pipelines.
3. **Pagination test asserted the wrong render path** (default Anthropic mock
   tag was outside the fixture window → fallback path, different remainder
   count). **Prevention:** when a handler test changes the window fixture set,
   re-derive which curation path the default mock hits.

## Tags

category: workflow-patterns
module: review, inngest, regex-performance, release-digest
