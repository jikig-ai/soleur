// Node (unit) project setup.
//
// Default WORKSPACES_ROOT to a writable temp dir. Server startup paths
// (`realSdkQueryFactory`, `startAgentSession`) now UNCONDITIONALLY mkdir the
// resolved workspace dir before sandbox construction (feat-one-shot-warm-
// reprovision-ensure-dir-presandbox) — previously the only mkdir was gated
// behind `ensureWorkspaceRepoCloned`'s not-connected / `.git`-present early
// returns, so unmocked startup tests never hit a real FS write. The production
// default "/workspaces" is a root-owned mount that is NOT writable in CI/dev,
// so an unguarded default makes that real mkdir EACCES-throw and abort startup.
//
// `||=` only fills an UNSET/empty value — any test that sets its own
// WORKSPACES_ROOT (or deletes it to assert the "/workspaces" default) is
// unaffected: its file-top assignment runs after this setup, and its
// per-test delete restores the unset state for its own scenarios.
import { tmpdir } from "node:os";
import { join } from "node:path";
import { vi } from "vitest";

process.env.WORKSPACES_ROOT ||= join(tmpdir(), "soleur-vitest-workspaces");

// #5796 — raise vitest's `vi.waitFor` default timeout floor (1000ms) to 10_000ms
// for the node/unit project. This MUST mirror the identical wrapper in
// `setup-dom.ts`: `vi.waitFor` is used in 18 node-project sites
// (cc-dispatcher.test.ts, server/templates/is-template-authorized.test.ts), and
// a setup-dom-only fix would leave those at the 1s default. vitest's `vi.waitFor`
// has no global config knob (distinct from RTL's `asyncUtilTimeout`), so the only
// way to lift the default across all call sites is to wrap the singleton at
// setup-file top-level. Explicit per-site timeouts still win (object form spreads
// over the injected default; number form replaces it). Passing waits are
// unaffected; only genuinely-failing waits get slower (10s vs 1s).
const _origNodeWaitFor = vi.waitFor.bind(vi);
vi.waitFor = ((
  callback: Parameters<typeof _origNodeWaitFor>[0],
  options?: Parameters<typeof _origNodeWaitFor>[1],
) => {
  const opts =
    typeof options === "number"
      ? { timeout: options }
      : { timeout: 10_000, ...(options ?? {}) };
  return _origNodeWaitFor(callback, opts);
}) as typeof vi.waitFor;
