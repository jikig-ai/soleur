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

process.env.WORKSPACES_ROOT ||= join(tmpdir(), "soleur-vitest-workspaces");
