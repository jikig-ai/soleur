import { vi } from "vitest";

// #5796 — raise vitest's `vi.waitFor` default timeout floor (1000ms) to 10_000ms,
// mirroring the #5113 `asyncUtilTimeout` fix for RTL. These are TWO INDEPENDENT
// mechanisms: vitest's `vi.waitFor` does NOT read RTL's
// `configure({ asyncUtilTimeout })` and has no global config knob of its own, so
// the dozens of `vi.waitFor` sites across BOTH vitest projects stayed at the 1s
// default after #5113 — node/unit (cc-dispatcher.test.ts,
// server/templates/is-template-authorized.test.ts) AND component
// (live-repo-badge.test.tsx, org-switcher-container.test.tsx, …). Under
// full-suite forked-worker CPU contention a 1s wait is exceeded before the
// condition settles — the proven CI-red flake (live-repo-badge.test.tsx
// vi.waitFor.timeout) that fail-closes await-ci and silently skips prod deploys.
//
// Wrapping the singleton lifts the default across every call site (existing AND
// future), so a new bare `vi.waitFor` cannot re-arm the flake. Explicit per-site
// timeouts still win (object form overrides the injected default; number form
// replaces it); a literal `{ timeout: undefined }` falls back to the floor rather
// than reinstating the 1s default. Passing waits are unaffected (they resolve
// when the condition is met); only genuinely-failing waits get slower (10s vs 1s)
// — the same tradeoff as the RTL ceiling and isolate:true.
//
// Lives under test/helpers/ (not test/) so it does NOT match the vitest `include`
// glob, mirroring test/helpers/engines-floor.ts. Call it from the top level of
// BOTH setup-dom.ts and setup-node.ts (vi.waitFor is exercised in both projects);
// installing it in only one would leave the other project's sites at 1s. The
// drift guard in test/setup-dom-leak-guard.test.ts asserts both call sites + this
// body so a silent removal fails fast.
export function installViWaitForFloor(): void {
  const origWaitFor = vi.waitFor.bind(vi);
  vi.waitFor = ((
    callback: Parameters<typeof origWaitFor>[0],
    options?: Parameters<typeof origWaitFor>[1],
  ) => {
    const timeout =
      typeof options === "number" ? options : (options?.timeout ?? 10_000);
    const rest =
      typeof options === "object" && options !== null ? options : {};
    return origWaitFor(callback, { ...rest, timeout });
  }) as typeof vi.waitFor;
}
