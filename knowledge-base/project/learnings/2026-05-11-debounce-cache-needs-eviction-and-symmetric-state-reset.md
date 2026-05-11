---
category: best-practices
module: observability + soleur-go-runner
issue: 3040
pr_branch: feat-one-shot-3040-v2-cc-hardening
---

# Learning: Module-level debounce caches need eviction; per-turn state resets must be symmetric across all reset sites

## Problem

PR #3040 added two patterns that looked correct in isolation but broke load-bearing invariants the implementer (me) did not enumerate, and that multi-agent review caught pre-merge:

1. **Unbounded module-level `Map<string, number>`** as a `(userId, errorClass) → last-mirrored-at` debounce cache. The original cc-dispatcher copy had grown unnoticed for months because dispatcher mirrors fired only for a small set of internal-error classes. Extracting it to `observability.ts` for cross-module use widened the surface to include per-PDF kb-document-resolver failures + the new `"unknown:notify-awaiting-no-active-query"` bucket. The map had no eviction policy — every distinct key persisted for the lifetime of the Node process. At ~64–96 bytes per entry × N users × ~10 classes, this is ~1 MB per 10k unique users with monotonic growth.

2. **Asymmetric per-turn state reset.** The PR widened `ActiveQuery` with `pausedAt: number | null` and `totalPausedMs: number` (paused-interval accumulators for cumulative wall-clock budget). I added reset logic at three sites — `dispatch()` initializer, `recordAssistantBlock` first-block-of-turn, and `closeQuery` — but missed `handleResultMessage`, which is the SDK result-message handler that clears `firstToolUseAt = null` to mark turn end. The asymmetry created a window: result arrives while paused → `pausedAt` stamped from previous turn survives until next `recordAssistantBlock` zeros it → a `notifyAwaitingUser(false)` between those two events applies `totalPausedMs += now() - pausedAt` against a stale `pausedAt`, polluting the next turn's budget.

## Solution

**For the debounce cache**, add an amortized stale-key sweep on write. Sweep fires every Nth write (N = 64); each sweep walks the map and drops entries with `last-mirrored-at < now - 2 * TTL`. Cost: amortized O(1) per call, O(n) at the sweep threshold. Caps map size at the steady-state set of recently-active keys rather than the all-time set. Reset hook (`__resetMirrorDebounceForTests`) clears both the map and the write counter.

```ts
// observability.ts
const MIRROR_STALE_TTL_MS = 2 * MIRROR_DEBOUNCE_MS;
const MIRROR_SWEEP_INTERVAL = 64;
let _mirrorWriteCount = 0;

export function mirrorWithDebounce(err, ctx, userId, errorClass) {
  // ... (existing TTL check) ...
  _mirrorLastReportedAt.set(key, now);
  _mirrorWriteCount++;
  if (_mirrorWriteCount % MIRROR_SWEEP_INTERVAL === 0) {
    const cutoff = now - MIRROR_STALE_TTL_MS;
    for (const [k, t] of _mirrorLastReportedAt) {
      if (t < cutoff) _mirrorLastReportedAt.delete(k);
    }
  }
  reportSilentFallback(err, ctx);
}
```

**For the per-turn reset**, treat `firstToolUseAt = null` as a *canonical turn-boundary marker* and grep every site that writes that literal — those sites form the equivalence class of "turn-end resets". Companion fields added in the same PR must reset at every site in the class. Here: `handleResultMessage`, `closeQuery`, `recordAssistantBlock` (first-block-of-turn writes `firstToolUseAt = now()` and zeros companions for new-turn budget). The grep is the discoverability check; the test that pins it is a multi-turn scenario where a result arrives mid-pause.

## Key Insight

**Generalizable patterns:**

1. **Any module-level `Map<K, V>` used as a primitive cache is a slow leak until it has eviction.** The "I'll add eviction if it becomes a problem" deferral is hard to detect from a code-review diff because the leak rate depends on the *set of keys produced over time*, not on the code itself. The amortized-sweep pattern (write counter + threshold + walk) is the cheapest correct shape. Apply it the moment a Map gets `set()` calls from a path that produces an unbounded key set.

2. **When a PR widens a state interface, the new fields must reset at the same sites the existing canonical reset field resets.** Concrete heuristic: `git grep -n "<canonical-field> = null"` (or `= 0` for accumulators) before final commit; if the new field doesn't appear adjacent at each hit, the reset set is asymmetric. This is mechanical and catches the class without judgment.

**Process insight**: Both findings were caught by multi-agent review (performance-oracle + data-integrity-guardian). Single-pass implementation review by the author misses these because the missing-reset site is *structurally identical to surrounding code that doesn't need the field* — the absence is invisible without a paired enumeration. The cost of running 8 reviewers on a hardening PR pre-merge (≈8 agent calls) is dramatically less than the cost of shipping a slow-leak or budget-pollution bug to production.

## Session Errors

- **Stale worktree at session start** — gitdir pointer referenced a deleted entry; `git worktree list` showed the path but `git status` errored. Recovery: `git worktree prune` + `git worktree add ... -b <branch> main`. **Prevention:** session-start hygiene (the `wg-at-session-start-run-bash-plugins-soleur` rule's `cleanup-merged` invocation) already runs `git worktree prune` implicitly; the gap was that the worktree was created in a previous session without proper cleanup. No new rule needed — the existing hook would have caught this had the prior session run `cleanup-merged`.

- **Initial regex extraction wrote literal U+2028/U+2029 codepoints** instead of `  ` escapes when porting `SHELL_METACHAR_DENYLIST` to `safe-bash.ts`. Violates `cq-regex-unicode-separators-escape-only` (Code Quality §regex Unicode separators). Recovery: `cat -A` to confirm the bytes, Python rewrite to substitute the escape form. **Prevention:** when copying a regex literal that includes high-codepoint chars, paste through a verbatim string field (not an Edit `old_string` parameter where the rendering may shift). Alternatively, write the regex by typing the escape form directly rather than copying — the rule already exists but is easy to miss when the source-of-truth file (`permission-callback.ts`) shows the escape form correctly.

- **Test mocks across 6 dispatcher/kb test files missed the new `__resetMirrorDebounceForTests` export** — vitest errored at test runtime ("No export defined on the mock") rather than at import resolution. **Prevention:** when adding a new export to a heavily-mocked module, grep `vi.mock\("@/server/<module>"` across tests/ first, then update each mock factory in the same commit. The cost of forgetting is N failed test files; the cost of grepping is one command. **Proposed enforcement:** the work skill's "Follow existing patterns" section already has a clause "When extending a Supabase wrapper module with a new chained method, grep tests/ for every mock chain and extend each one in the same edit cycle" — this learning broadens the principle to any new export on a heavily-mocked module. Apply the same rule.

- **cc-dispatcher.test.ts mock hand-rolled the 5-min TTL constant** (`const ttl = 5 * 60 * 1000`) instead of forwarding `actual.MIRROR_DEBOUNCE_MS`. Code-review caught at P2. **Prevention:** when a test mock needs to mirror SUT behavior whose configuration is a constant, pull the constant via `vi.importActual` (already the pattern in the same mock) rather than duplicating the value. The drift-trap is silent: if the production TTL changes, the test mock keeps the old value and the coalesce assertion drifts without failing.

- **`handleResultMessage` per-turn reset missed `pausedAt`/`totalPausedMs`** despite the plan listing reset sites. Caught at multi-agent review (P1). **Prevention:** see Key Insight #2 — grep for the canonical reset field (`firstToolUseAt = null` here) before final commit; any new companion field added in the same PR must appear adjacent at every hit. This is a per-PR mechanical check, not a long-term rule.

- **`_mirrorLastReportedAt` Map growth was unbounded** at extraction time. The prior cc-dispatcher copy was tolerable; the moved-to-observability copy is hot. **Prevention:** see Key Insight #1 — any module-level `Map<K, V>` cache gets eviction on Day 1, not "when it becomes a problem".

## Related Files

- `apps/web-platform/server/observability.ts` — mirrorWithDebounce + amortized sweep
- `apps/web-platform/server/soleur-go-runner.ts` — handleResultMessage symmetric reset (line ~1813), notifyAwaitingUser body
- `apps/web-platform/test/observability-mirror-debounce.test.ts` — TTL contract tests
- `apps/web-platform/test/cc-dispatcher.test.ts` — mock that forwards `actual.MIRROR_DEBOUNCE_MS`
- Plan: `knowledge-base/project/plans/2026-05-11-fix-cc-hardening-safe-bash-mirror-reaper-wallclock-plan.md`

## Tags

category: best-practices
module: observability, soleur-go-runner
related-rules: cq-regex-unicode-separators-escape-only, cq-silent-fallback-must-mirror-to-sentry, rf-review-finding-default-fix-inline
