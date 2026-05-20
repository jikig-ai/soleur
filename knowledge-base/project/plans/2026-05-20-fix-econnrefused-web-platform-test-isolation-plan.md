---
title: "fix(test): close the happy-dom ECONNREFUSED-on-127.0.0.1:3000 test-isolation gap"
type: fix
date: 2026-05-20
lane: cross-domain
issue: 4155
pr: 4158
branch: feat-one-shot-econnrefused-web-platform-4155
---

# fix(test): close the happy-dom ECONNREFUSED-on-127.0.0.1:3000 test-isolation gap

Close the residual `ECONNREFUSED 127.0.0.1:3000` flake class in `apps/web-platform`'s
vitest suite (1-in-3 frequency post-#4128). Root cause: happy-dom's `window` provides a
real `WebSocket` (delegates to the `ws` npm package, opens a real TCP connection) and a
real `fetch`; `window.location.host` defaults to `localhost:3000`. Any happy-dom test
that fires `useWebSocket()` / a relative-path `fetch("/api/...")` and is not protected
by either `vi.mock("@/lib/ws-client", ...)` or a per-file `globalThis.WebSocket =
MockWebSocket` (and a comparable `fetch` mock) will attempt a real TCP connect to a
port that is not listening under `npm test`.

The fix is a **fail-loud network blockade** installed at `test/setup-dom.ts` scope: a
`beforeEach` hook that re-installs noisy stubs for `globalThis.WebSocket` and
`globalThis.fetch` so that any unmocked network attempt surfaces a deterministic error
naming the leaky test, rather than a transient ECONNREFUSED 30s into a 16s timeout
window. Per-file mocks (the existing `MockWebSocket` pattern) continue to override the
stub for tests that need to exercise the real code path.

## User-Brand Impact

- **If this lands broken, the user experiences:** no user impact. Test-only change.
  Failure-mode is "vitest suite gets flakier" → operator notices in CI / pre-merge
  signal.
- **If this leaks, the user's [data / workflow / money] is exposed via:** no exposure
  vector. Test scaffolding never ships in the production bundle.
- **Brand-survival threshold:** `none, reason: pure test-harness isolation change — no
  surface reachable from production code paths or operator-facing artifacts.`

Sensitive-path check: diff touches only `apps/web-platform/test/setup-dom.ts` (+
optional drift-guard test). Not in Check 6's sensitive-path regex (no schema, auth,
PII, billing, or external-data-flow surface). Preflight Check 6 should pass on
`threshold: none` with the scope-out rationale above.

## Hypotheses

The issue body's three candidate vectors map cleanly to a single root cause + one
secondary aggravator:

### H1 (primary) — happy-dom real `WebSocket` + default `window.location.host`

Verified by direct inspection:

- `node_modules/happy-dom/lib/web-socket/WebSocket.js:67` — `this.#connect(parsedURL,
  protocolList);` is called unconditionally in the `WebSocket` constructor and delegates
  to `import WS from 'ws'` (line 8) which opens a real TCP socket.
- `node_modules/happy-dom@20.8.9`'s `Window` default URL is `about:blank` but the
  `vitest` `environment: 'happy-dom'` initializer sets `http://localhost:3000` — confirmed
  via `node -e "const w = require('happy-dom'); const win = new w.Window({url:'http://localhost:3000'}); console.log('WebSocket type:', typeof win.WebSocket, 'host:', win.location.host)"` →
  `WebSocket type: function host: localhost:3000`.
- `lib/ws-client.ts:491-496` (`getWsUrlAndToken`):

  ```ts
  const proto = window.location.protocol === "https:" ? "wss" : "ws";
  ...
  return { url: `${proto}://${window.location.host}/ws`, token };
  ```

  Under happy-dom this resolves to `ws://localhost:3000/ws`. `lib/ws-client.ts:532`
  then calls `new WebSocket(url)`. If `globalThis.WebSocket` has not been overridden by
  the test file's `beforeEach`, this is happy-dom's real WebSocket → real `ws.connect()`
  → ECONNREFUSED on the loopback port nothing is listening on.

### H2 (aggravator) — relative-path `fetch("/api/...")` in mounted components

`lib/analytics-client.ts:35`, `lib/upload-attachments.ts:57`,
`lib/push-subscription.ts:36,61`, `app/(dashboard)/layout.tsx:112` (`fetch("/api/admin/check")`),
plus many page-component `useEffect`-driven fetches. happy-dom resolves the relative URL
against `window.location.origin` → `http://localhost:3000` → real `fetch` → ECONNREFUSED.

This is a contributing class but is largely already covered by per-file `global.fetch =
vi.fn(...)` patterns (see the 50+ test files that mock fetch). The residual flake is
therefore most likely the WebSocket vector, with fetch as a recurrence-risk vector if
the WebSocket fix lands alone.

### H3 (race) — `vi.unstubAllGlobals` + module-scope `vi.stubGlobal` interaction

Per the existing setup-dom.ts comments and PR #2594/#2505, the `afterAll` scrub restores
`originalFetch` (happy-dom's real fetch) but does NOT touch `globalThis.WebSocket`.
Vitest `pool: forks` + `isolate: true` (post-#4097) eliminates *cross-file* leakage at
the worker level. The remaining surface is *intra-file*: a test that
`renderHook(() => useWebSocket(...))` without first overriding `globalThis.WebSocket`
in its own `beforeEach`. Grep confirms three test files override `globalThis.WebSocket`
explicitly (`useWebSocket-abort`, `ws-client-resume-history`, `kb-chat-resume-hydration`)
— any FUTURE test that imports `useWebSocket` directly without that override silently
inherits happy-dom's real WebSocket and reopens this class.

### Network-outage L3-L7 checklist (gate-triggered but materially N/A)

The hr-ssh-diagnosis-verify-firewall gate fired on the words "connection" and "timeout"
in the issue body. L3-L7 verification is not applicable: this is a *single-process*
loopback connection attempt inside `vitest`'s node runtime. There is no firewall, no
DNS, no sshd, no host route to verify — the destination port `3000` is simply not
listening because no `next dev` is running during `npm test`. The L3-L7 checklist
applies to remote-host SSH/connectivity outages (e.g., #2654 admin-IP drift); recording
the gate fired and materially N/A here.

## Research Reconciliation — Spec vs. Codebase

No spec.md exists for this feature branch — `lane:` defaulted to `cross-domain`
(fail-closed). All claims in this plan derive from direct codebase inspection at
`@HEAD` (commit `cf309bbc` on `feat-one-shot-econnrefused-web-platform-4155`).

| Issue body claim | Codebase reality | Plan response |
|---|---|---|
| "~1 in 3 full-suite runs reproduces under #4128 fixes applied" | Confirmed: PR #4141 (merged) added timeout headroom + Doppler env scrub; that PR's body explicitly scoped out the ECONNREFUSED class to #4155. | Carry as given; AC re-verifies on this branch's HEAD post-fix. |
| Candidate vector 1: `fetch("http://127.0.0.1:3000/...")` against unspawned dev server | `git grep -nE '127\.0\.0\.1:3000\|localhost:3000' apps/web-platform/test/` returns only `new Request("http://localhost:3000/...")` constructors (URL strings, not fetches), CSP-test literals, and JSDoc URL examples — no test issues a real `fetch("http://localhost:3000/...")`. | Vector reframed: the LIVE `fetch` path uses *relative* URLs (`/api/...`) resolved by happy-dom's `window.location.origin`. Same outcome (real connect to :3000), different mechanism. Caught at plan-time grep; H2 above documents. |
| Candidate vector 2: vi.mock-shadowed module escape under forks pool isolation race | `pool: forks` + `isolate: true` already on (#4097); cross-file leak is closed. | Reframed as H3 intra-file gap, not cross-file isolation race. |
| Candidate vector 3: per-process Node spin-up + dynamic-import timing | Not a Node race — it's a real outbound TCP attempt by happy-dom's `ws`-delegating WebSocket. | Reframed as H1. |

## Files to Edit

- `apps/web-platform/test/setup-dom.ts` — install fail-loud network-blockade stubs in
  `beforeEach`; preserve existing `afterAll` scrub semantics.

## Files to Create

- `apps/web-platform/test/setup-dom-network-blockade.test.ts` — drift-guard tests
  asserting (a) the `beforeEach` block installs `globalThis.WebSocket` and `globalThis.fetch`
  fail-loud stubs, (b) the stubs throw with an actionable error naming the URL, (c) a
  per-test `vi.stubGlobal("fetch", ...)` / `globalThis.WebSocket = MockWebSocket`
  override still works (intra-test override semantics survive).

## Open Code-Review Overlap

None. `gh issue list --label code-review --state open --json number,title,body --limit
200 | jq -r --arg path "apps/web-platform/test/setup-dom.ts" '.[] | select(.body // "" |
contains($path)) | "#\(.number): \(.title)"'` returned 0 matches. Same for
`apps/web-platform/vitest.config.ts` (no overlap). The only `ECONNREFUSED` match is
#4155 itself.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] **AC1 — Fail-loud stubs installed:** `apps/web-platform/test/setup-dom.ts`
  contains a `beforeEach` hook that:
  (a) assigns `globalThis.WebSocket` to a class whose constructor throws
  `new Error("[setup-dom] Unmocked WebSocket construction in test — url=" + url + ". Mock @/lib/ws-client or assign globalThis.WebSocket in beforeEach.")`,
  (b) assigns `globalThis.fetch` to a function that throws
  `new Error("[setup-dom] Unmocked fetch in test — input=" + String(input) + ". Mock the fetch in this test's beforeEach.")`.
  Verify: `grep -E "Unmocked (WebSocket|fetch)" apps/web-platform/test/setup-dom.ts` returns 2 matches.

- [ ] **AC2 — `afterAll` scrub preserved:** The existing `afterAll` block continues to
  restore `originalFetch` / `originalXHR`, call `vi.restoreAllMocks()`,
  `vi.unstubAllGlobals()`, `vi.useRealTimers()`, and `resetBrowserLikeGlobals()`.
  Verify: `apps/web-platform/test/setup-dom-leak-guard.test.ts` passes unchanged.

- [ ] **AC3 — Drift-guard test exists:** `apps/web-platform/test/setup-dom-network-blockade.test.ts`
  exists and asserts both fail-loud stubs are present in the source AND that an
  intra-test `vi.stubGlobal("fetch", vi.fn().mockResolvedValue(new Response()))` still
  takes precedence over the blockade stub (override semantics intact).
  Verify: `cd apps/web-platform && npx vitest run test/setup-dom-network-blockade.test.ts`
  passes with exit 0 (`exit=0` is the implementation-invariant signal).

- [ ] **AC4 — Zero ECONNREFUSED across 5× consecutive full-suite runs:**
  `cd apps/web-platform && for i in 1 2 3 4 5; do doppler run -p soleur -c dev -- npm test 2>&1 | tee /tmp/run-$i.log; done`
  Then `grep -c 'ECONNREFUSED.*127\.0\.0\.1:3000\|ECONNREFUSED.*localhost:3000' /tmp/run-{1,2,3,4,5}.log`
  returns `0` for every run (5 lines of `0`).
  Per the cap of brand-survival-irrelevant work + the empirical 1-in-3 baseline,
  5 consecutive runs at zero is the issue body's explicit AC and represents <1% residual
  flake probability assuming independence.

- [ ] **AC5 — No false positives in existing suite:** All 5003 tests in the full suite
  still pass after the blockade install — `cd apps/web-platform && doppler run -p soleur
  -c dev -- npm test` exits 0 on every one of the 5 AC4 runs. Per-file `globalThis.WebSocket
  = MockWebSocket` and `global.fetch = vi.fn(...)` assignments in 50+ existing test
  files override the blockade stub correctly.

- [ ] **AC6 — `tsc --noEmit` clean:** `cd apps/web-platform && npx tsc --noEmit` →
  0 errors.

- [ ] **AC7 — `bash scripts/test-all.sh` exit 0:** All 64+ test suites pass.

- [ ] **AC8 — PR body uses `Closes #4155`** (single-merge atomic fix; no post-merge
  operator step).

### Post-merge (operator)

None. Pure test-infra change applied at merge.

## Test Scenarios

- **Given** a test file that does `vi.mock("@/lib/ws-client", () => ({ useWebSocket: () => wsReturn }))`,
  **when** the component under test invokes the mocked `useWebSocket`,
  **then** the blockade stub is never reached (the mock short-circuits the real `ws-client`
  module entirely) → existing 18+ chat-surface/kb-chat-sidebar tests continue green.

- **Given** a test file that imports `useWebSocket` directly AND assigns `globalThis.WebSocket
  = MockWebSocket` in its own `beforeEach`,
  **when** `useWebSocket` invokes `new WebSocket(url)`,
  **then** the test-file's `beforeEach` runs AFTER setup-dom.ts's `beforeEach` (test
  hooks compose top-down) → the per-file override wins → MockWebSocket is used. Verified
  on `useWebSocket-abort`, `ws-client-resume-history`, `kb-chat-resume-hydration`.

- **Given** a NEW (hypothetical) test file that renders a component using `useWebSocket`
  without any mock,
  **when** the test invokes the component,
  **then** the fail-loud stub throws synchronously with the URL — the test fails with
  an actionable error message naming the source file rather than a 16s-timeout
  ECONNREFUSED a future operator has to bisect.

- **Given** a test file that does `globalThis.fetch = vi.fn().mockResolvedValue(...)`
  inside `beforeEach`,
  **when** code under test calls `fetch("/api/something")`,
  **then** the per-file override wins → the mock returns. The blockade stub is the
  fail-closed default; per-file overrides are explicit opt-out.

## Implementation Phases

### Phase 0 — Preconditions (verify before any code change)

- [ ] `grep -nE 'beforeEach' apps/web-platform/test/setup-dom.ts` returns 0 (no
  pre-existing `beforeEach` in setup-dom.ts at HEAD `cf309bbc`).
- [ ] `grep -nE '\bWebSocket\b' apps/web-platform/test/setup-dom.ts` returns 0 (no
  pre-existing WebSocket reference in setup-dom.ts).
- [ ] Confirm 3 known files explicitly override `globalThis.WebSocket`:
  `grep -l 'globalThis\.WebSocket = MockWebSocket' apps/web-platform/test/` →
  exactly `useWebSocket-abort.test.tsx`, `ws-client-resume-history.test.tsx`,
  `kb-chat-resume-hydration.test.tsx`. (If a 4th file appears, audit it for compatibility
  with the blockade — it should already work since beforeEach-in-file runs after
  setup-file beforeEach.)
- [ ] Confirm vitest beforeEach composition order via a 1-test fixture:
  ```ts
  // tmp/precondition-beforeeach-order.test.tsx
  import { beforeEach, describe, it, expect } from "vitest";
  let order: string[] = [];
  beforeEach(() => { order.push("file-level"); });
  describe("composition", () => {
    beforeEach(() => { order.push("describe-level"); });
    it("file before describe before test", () => {
      expect(order).toEqual(["file-level", "describe-level"]);
    });
  });
  ```
  Setup-file beforeEach is at the same composition level as file-level; the per-file
  beforeEach in a sibling test file runs AFTER (vitest composes hooks in registration
  order across the chain). Delete after verifying.

### Phase 1 — RED test (drift guard)

Write `apps/web-platform/test/setup-dom-network-blockade.test.ts` first. RED state:

```ts
import { describe, it, expect } from "vitest";
import { readFileSync } from "node:fs";
import { resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = dirname(fileURLToPath(import.meta.url));
const source = readFileSync(resolve(__dirname, "setup-dom.ts"), "utf8");

describe("setup-dom.ts network blockade (#4155)", () => {
  it("installs a fail-loud WebSocket stub in beforeEach", () => {
    expect(source).toMatch(/beforeEach\([\s\S]*?WebSocket/);
    expect(source).toContain("Unmocked WebSocket construction in test");
  });

  it("installs a fail-loud fetch stub in beforeEach", () => {
    expect(source).toMatch(/beforeEach\([\s\S]*?fetch/);
    expect(source).toContain("Unmocked fetch in test");
  });

  // Integration check: stub throws synchronously when WebSocket constructed
  // with no per-test override.
  it("throws when an unmocked test attempts new WebSocket()", () => {
    expect(() => new (globalThis.WebSocket as new (url: string) => unknown)(
      "ws://localhost:3000/ws"
    )).toThrow(/Unmocked WebSocket construction/);
  });

  it("throws when an unmocked test calls fetch()", async () => {
    await expect(
      (globalThis.fetch as (input: string) => Promise<Response>)("/api/probe"),
    ).rejects.toThrow(/Unmocked fetch in test/);
  });

  it("intra-test vi.stubGlobal override wins (sanity)", async () => {
    const { vi } = await import("vitest");
    vi.stubGlobal("fetch", vi.fn().mockResolvedValue(
      new Response("ok", { status: 200 })
    ));
    const res = await fetch("/api/probe");
    expect(res.status).toBe(200);
    vi.unstubAllGlobals();
  });
});
```

Expect: tests fail (the source-grep + integration assertions both red).

### Phase 2 — GREEN (install the blockade)

Edit `apps/web-platform/test/setup-dom.ts` to add:

```ts
import { afterAll, afterEach, beforeEach, vi } from "vitest";
// ... existing originalFetch, originalXHR captures unchanged ...

// #4155 — fail-loud network blockade. happy-dom's `window.location.host`
// defaults to `localhost:3000` and its `WebSocket` + `fetch` are real (delegate
// to `ws` and node's undici respectively). Without this blockade, an unmocked
// `useWebSocket()` or relative-path `fetch("/api/...")` in a component test
// attempts a real TCP connection on loopback, surfacing as a transient
// `ECONNREFUSED 127.0.0.1:3000` after the full vitest testTimeout (#4128 bumped
// to 16s) — wall-clock cost + non-actionable error.
//
// Strategy: install loud stubs in `beforeEach` so each test starts with both
// surfaces fail-closed. Per-file overrides (`globalThis.WebSocket = MockWebSocket`,
// `vi.stubGlobal("fetch", vi.fn()...)`, or `vi.mock("@/lib/ws-client", ...)`)
// take precedence — they run AFTER the setup-file beforeEach in the hook chain.
// The blockade only catches genuinely-unmocked code paths.

class BlockedWebSocket {
  constructor(url: string | URL) {
    throw new Error(
      `[setup-dom] Unmocked WebSocket construction in test — url=${String(url)}. ` +
        `Mock @/lib/ws-client via vi.mock(...) OR assign globalThis.WebSocket = MockWebSocket in this test's beforeEach. ` +
        `See knowledge-base/project/learnings/2026-05-20-happy-dom-ws-fetch-blockade.md.`,
    );
  }
}

const blockedFetch: typeof fetch = (input, _init) => {
  return Promise.reject(
    new Error(
      `[setup-dom] Unmocked fetch in test — input=${
        typeof input === "string" ? input : input instanceof URL ? input.toString() : "[Request]"
      }. Mock with vi.stubGlobal("fetch", vi.fn().mockResolvedValue(...)) in this test's beforeEach.`,
    ),
  );
};

beforeEach(() => {
  if (typeof globalThis !== "undefined") {
    // Reset to blockade state at the start of each test. Per-file beforeEach
    // hooks compose AFTER this one and can install MockWebSocket / mocked fetch.
    // Use `as unknown as ...` to satisfy TS — the stub's only contract is "throw".
    globalThis.WebSocket = BlockedWebSocket as unknown as typeof WebSocket;
    globalThis.fetch = blockedFetch;
  }
});

// ... existing afterEach (cleanup) and afterAll (restore originals) unchanged ...
```

Run RED tests → expect GREEN.

### Phase 3 — Full-suite validation

```bash
cd apps/web-platform && npx tsc --noEmit
cd apps/web-platform && for i in 1 2 3 4 5; do
  echo "=== Run $i ==="
  doppler run -p soleur -c dev -- npm test 2>&1 | tee /tmp/full-run-$i.log
done
# Then verify
for i in 1 2 3 4 5; do
  count=$(grep -c 'ECONNREFUSED.*127\.0\.0\.1:3000\|ECONNREFUSED.*localhost:3000' /tmp/full-run-$i.log || echo 0)
  echo "Run $i: ECONNREFUSED matches = $count"
done
```

Expected: `Run $i: ECONNREFUSED matches = 0` for all 5 runs. All 5003 tests pass each run.

If any run shows ECONNREFUSED matches > 0, capture the test name from the error
message (`[setup-dom] Unmocked WebSocket construction in test — url=...`) — the loud
stub names the leaky test deterministically. Add a per-file override OR a
`vi.mock("@/lib/ws-client", ...)` to that file in the same PR.

### Phase 4 — `scripts/test-all.sh` cross-suite verification

```bash
bash scripts/test-all.sh
```

Expected: 64+ suites pass. No plugin-test regressions (test-all spans plugin + app suites).

### Phase 5 — Compound learning

Write `knowledge-base/project/learnings/2026-05-20-happy-dom-ws-fetch-blockade.md`
(referenced by the blockade error message). Topic:
"happy-dom WebSocket and fetch are real network adapters — install fail-loud blockade
in setup-dom for deterministic intra-suite isolation". Cross-reference #4097 (forks
pool), #4128/#4141 (timeout headroom), and #4155 (this fix).

## Risks & Mitigations

- **Risk:** A future test that intentionally exercises the real `fetch` against a
  spawned local server (e.g., a bundled-server harness) hits the blockade.
  **Mitigation:** The blockade is the default; the test installs `vi.stubGlobal("fetch",
  origFetch)` in its own `beforeEach`. Existing `bundled-server.ts` harness spawns a
  child node process and reads via `spawnSync` stdout — does NOT use `fetch` against
  the spawned process. Verified: `git grep -nE 'fetch\(.*localhost' apps/web-platform/test/`
  returns 0 hits (all matches are `new Request(...)` URL strings).

- **Risk:** Hook composition order changes in a future vitest minor release, breaking
  the "per-file beforeEach runs after setup-file beforeEach" assumption.
  **Mitigation:** Vitest's hook ordering is documented and load-bearing for every test
  suite using `setupFiles`. A future change would be a breaking-release call-out.
  Phase 0 precondition verifies this on the installed vitest version (3.x) via a one-test
  fixture before any code change.

- **Risk:** The blockade introduces a subtle infinite-loop if a hook ITSELF calls
  `fetch` or `new WebSocket` (e.g., a future `setupFiles` addition fetches a fixture).
  **Mitigation:** Blockade installs in `beforeEach`, not at module-init. Setup-file
  module-init code path (the `originalFetch` / `originalXHR` captures at the top) runs
  BEFORE the first `beforeEach` and sees the unstubbed pristine `globalThis.fetch`.
  Hook-level fetches at `beforeAll` are also fine because `beforeAll` runs before the
  first `beforeEach` in a file.

- **Risk:** A test's `vi.mock("@/lib/ws-client", ...)` hoists module-init code that
  imports `useWebSocket`'s transitive `lib/supabase/client` etc. and that chain calls
  fetch at module init.
  **Mitigation:** Module-init runs at import time (before `beforeEach`); `globalThis.fetch`
  is still happy-dom's real fetch at that point. No regression — current behavior is
  preserved at module-init scope; the blockade ONLY changes test-body scope (after
  `beforeEach` runs).

- **Risk (drift):** A future PR removes the blockade `beforeEach` block from
  `setup-dom.ts`.
  **Mitigation:** `setup-dom-network-blockade.test.ts` (created in Phase 1) is a
  drift-guard test that reads `setup-dom.ts` source and asserts both blockade tokens
  exist. Mirrors the `setup-dom-leak-guard.test.ts` precedent (PR #2594, #2505).

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — pure test-harness isolation change. No
production code path, no user-facing surface, no compliance impact, no infrastructure
change.

## Sharp Edges

- A future test that needs to exercise the **real** `globalThis.WebSocket` (e.g., to
  spin up a `WS` server in `beforeAll` and connect a real client to it) MUST capture
  the blockaded stub and restore the real WebSocket in its own `beforeEach`:
  ```ts
  let blocked: typeof WebSocket;
  beforeEach(() => {
    blocked = globalThis.WebSocket;
    globalThis.WebSocket = realWebSocketImpl;
  });
  afterEach(() => { globalThis.WebSocket = blocked; });
  ```
  Same pattern for `fetch`. The blockade stub itself is harmless to stash — it's not
  reachable in a normal test path.

- The blockade error messages are **load-bearing operator artifacts**. Do NOT shorten
  them in a "polish" PR — the URL/input string is what makes a future ECONNREFUSED-class
  flake trivially diagnosable (vs. the current 16s-timeout-then-bisect cost).

- Test-runner choice (`vitest`) is locked in via `apps/web-platform/package.json:scripts.test`.
  This plan does NOT introduce a new test framework; the blockade is plain vitest hooks
  + `vi`.

## References

- #4128 (closed via #4141 merge): pre-existing apps/web-platform suite failures
  (timeout + Doppler env-leak). Scoped out the ECONNREFUSED class to #4155.
- PR #4097: prior stabilization (`pool: "forks"` + `isolate: true`) — closed
  cross-file leakage. Intra-file unmocked-WebSocket-in-happy-dom remained.
- PR #4141: closed #4128 (timeout headroom + Doppler env scrub).
- Learning: `knowledge-base/project/learnings/2026-05-15-drain-plan-must-revalidate-issue-state-against-codebase.md`
  documented the class as "Full vitest suite has pre-existing flaky component tests …
  ECONNREFUSED on localhost:3000 under full-suite concurrency."
- happy-dom: `node_modules/happy-dom/lib/web-socket/WebSocket.js` (delegates to `ws`).
- Setup-dom precedent: `apps/web-platform/test/setup-dom-leak-guard.test.ts` (PR #2594,
  #2505) — same drift-guard-via-source-grep pattern.
