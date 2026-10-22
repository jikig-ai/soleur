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
import { installViWaitForFloor } from "./helpers/install-vi-waitfor-floor";

process.env.WORKSPACES_ROOT ||= join(tmpdir(), "soleur-vitest-workspaces");

// #10734 — the quiet-window kill-switch's env mirror is ON in the dev Doppler config while the
// git-data rehearsal is armed, and the push-time `tenant-integration` job runs this project under
// `doppler run -c dev`. An ambient FLAG_NEW_SESSIONS_PAUSED=1 made `newAgentSessionsRefused()` true
// in every suite that drives the real `startAgentSession` / `triggerHeadlessSync`, so those suites
// took the refusal branch (and, with a partial `@/server/observability` mock, threw) on every push
// to main while passing on a clean env. Clear it here; a test that needs the switch on sets it
// itself, and that assignment runs after this setup.
delete process.env.FLAG_NEW_SESSIONS_PAUSED;
// The env mirror was only HALF of it (PR 10784 cleared it and the push run still failed 3/3): the dev
// Doppler config ALSO carries FLAGSMITH_ENVIRONMENT_KEY, so `client()` in lib/feature-flags/server.ts
// is live and `isNewAgentSessionsPaused()` reads the dev Flagsmith environment, where the flag is ON
// during the rehearsal. A unit suite must never reach a vendor: with no key `client()` returns null and
// the (now cleared) env mirror answers "allowed". A test that exercises the Flagsmith path mocks the
// client or sets the key itself, after this setup.
delete process.env.FLAGSMITH_ENVIRONMENT_KEY;

// #5796 — raise vitest's `vi.waitFor` default timeout floor (1s → 10s) for the
// node/unit project. Must mirror the identical install in setup-dom.ts: a
// setup-dom-only fix would leave the node-project sites (cc-dispatcher.test.ts,
// server/templates/is-template-authorized.test.ts, …) at the 1s default. See
// ./helpers/install-vi-waitfor-floor.ts for the full rationale.
installViWaitForFloor();
