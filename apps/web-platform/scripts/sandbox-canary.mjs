#!/usr/bin/env node
// Faithful sandbox canary — #5875 item 1 / ADR-079.
//
// One payload, two ends of a single faithfulness pipeline (ADR-079 hybrid):
//
//   --capture  (CI only, PR3, creds-gated): put a bwrap-intercepting shim on
//              PATH, import the REAL `buildAgentSandboxConfig`, feed that exact
//              options object into the SDK `query()`, run one no-op Bash op so
//              the SDK builds+spawns its real split-unshare bwrap argv, then
//              snapshot the SETUP argv to the committed fixture. The argv is a
//              pure function of (SDK version, sandbox config) — both in-tree —
//              so re-capture on any change keeps the fixture from going stale.
//
//   --verify   (CI, PR3): re-capture and byte-diff against the committed
//              fixture; non-zero on drift (forces the dev to commit the refresh).
//
//   --replay   (DEFAULT, deploy-time, PR2): read the committed fixture and run
//              `bwrap <captured-setup-argv> -- true` INSIDE the running canary
//              container (this file is baked into the image; ci-deploy.sh calls
//              `docker exec <canary> node /app/scripts/sandbox-canary.mjs`).
//              Creds-free, network-free, deterministic — never reaches query().
//              The replayed argv IS the SDK's captured argv, so it is faithful
//              by construction (cannot repeat #5849's false-green); and because
//              the argv is never hand-authored and non-EPERM failures classify
//              as canary_infra_error, it cannot repeat #4932's false-rollback.
//
// The deploy-time verdict is written to deploy-state by ci-deploy.sh (surfaced
// on /hooks/deploy-status) and a Sentry event fires on a faithful FAIL — never
// journald-only (hr-no-ssh-fallback-in-runbooks).

import { spawnSync } from "node:child_process";
import { mkdirSync, readFileSync } from "node:fs";
import { fileURLToPath, pathToFileURL } from "node:url";

const DEFAULT_FIXTURE_URL = new URL(
  "../infra/sandbox-canary-argv.json",
  import.meta.url,
);

// ---------------------------------------------------------------------------
// Pure, LLM-free logic (the plan's "no LLM in the assertion path"). Exported
// for apps/web-platform/test/sandbox-canary.test.ts.
// ---------------------------------------------------------------------------

/**
 * Map a replayed bwrap outcome to a canary verdict.
 *
 * Exit-code classification is the false-rollback guard (#4941): ONLY a bwrap
 * "Operation not permitted" (EPERM — the #5873 seccomp/userns-denial shape) is
 * `sandbox_broken`; a missing binary, OOM, or any other non-zero exit is
 * `canary_infra_error` (non-blocking — never rolls back).
 */
export function classifyReplayVerdict({
  bwrapExitCode,
  bwrapStderr = "",
  spawnErrorCode,
} = {}) {
  if (spawnErrorCode === "ENOENT") {
    return { verdict: "canary_infra_error", reason: "bwrap_spawn_enoent" };
  }
  if (spawnErrorCode) {
    return {
      verdict: "canary_infra_error",
      reason: `bwrap_spawn_${String(spawnErrorCode).toLowerCase()}`,
    };
  }
  if (bwrapExitCode === 0) {
    return { verdict: "pass", reason: "ok" };
  }
  // bwrap merges its userns/seccomp stderr into this stream; the EPERM phrase is
  // the load-bearing signature (Phase-0 spike; matches the seccomp `unshare`
  // denial that took down the Concierge sandbox for all tenants under SDK 0.3.x).
  if (/operation not permitted/i.test(bwrapStderr)) {
    return {
      verdict: "sandbox_broken",
      reason: "bwrap_operation_not_permitted",
    };
  }
  return {
    verdict: "canary_infra_error",
    reason: `bwrap_exit_${bwrapExitCode ?? "null"}`,
  };
}

/**
 * Validate a captured-argv fixture. Returns a normalized shape or throws.
 * The `{status:"uncaptured"}` sentinel is the dark-launch default: until PR3's
 * CI capture populates the real SDK argv, the replay records an infra-error
 * verdict rather than replaying a hand-authored argv (the #4932 trap).
 */
export function validateFixture(obj) {
  if (!obj || typeof obj !== "object") {
    throw new Error("sandbox-canary: fixture is not an object");
  }
  if (obj.status === "uncaptured") {
    return { status: "uncaptured", sdkVersion: obj.sdkVersion ?? null };
  }
  const argv = obj.bwrapSetupArgv;
  if (!Array.isArray(argv)) {
    throw new Error("sandbox-canary: bwrapSetupArgv must be an array");
  }
  if (argv.length === 0) {
    // An empty argv would let `bwrap -- true` succeed trivially — a new
    // empty-green class (CTO constraint #6). Reject it.
    throw new Error("sandbox-canary: bwrapSetupArgv is empty (empty-green guard)");
  }
  if (!argv.every((t) => typeof t === "string")) {
    throw new Error("sandbox-canary: bwrapSetupArgv must be all strings");
  }
  const prepDirs = Array.isArray(obj.prepDirs)
    ? obj.prepDirs.filter((d) => typeof d === "string")
    : [];
  return {
    status: "captured",
    bwrapSetupArgv: argv,
    prepDirs,
    sdkVersion: obj.sdkVersion ?? null,
  };
}

/**
 * Build the replay invocation: the captured SETUP argv followed by the `-- true`
 * no-op command. The seccomp-gated syscalls (the split unshare + mounts) all run
 * in bwrap SETUP before it execs the command, so `true` exercises the profile
 * identically to the SDK's real command — same discipline as the legacy probe.
 * We store/replay SETUP argv only and NEVER a captured command token.
 */
export function buildBwrapInvocation(fixture) {
  const argv = fixture.bwrapSetupArgv;
  if (argv.includes("--")) {
    throw new Error(
      "sandbox-canary: setup argv must not contain a '--' separator; replay appends its own no-op command",
    );
  }
  return { cmd: "bwrap", args: [...argv, "--", "true"] };
}

/**
 * Deterministic sort for capture normalization. `enumerateSiblingDenyPaths`
 * returns readdir order, which is not stable across runners; sorting makes the
 * captured argv byte-reproducible so `--verify`'s diff does not false-fail.
 */
export function sortDenyPaths(paths) {
  return [...paths].sort();
}

// ---------------------------------------------------------------------------
// Runtime orchestration (side-effecting; not covered by the pure unit tests).
// ---------------------------------------------------------------------------

function emitVerdict(v) {
  // Single-line JSON on stdout — ci-deploy.sh captures + jq-parses it.
  process.stdout.write(`${JSON.stringify(v)}\n`);
}

function runReplay(fixtureUrl) {
  let fixture;
  try {
    fixture = validateFixture(JSON.parse(readFileSync(fixtureUrl, "utf8")));
  } catch (err) {
    // Missing/malformed fixture is an infra error — non-blocking, never a
    // rollback. Distinct reason so the soak follow-through can tell "not yet
    // captured" from a real pass.
    const code = err && err.code === "ENOENT" ? "fixture_missing" : "fixture_invalid";
    emitVerdict({ verdict: "canary_infra_error", reason: code });
    return 0;
  }

  if (fixture.status === "uncaptured") {
    emitVerdict({
      verdict: "canary_infra_error",
      reason: "fixture_uncaptured",
      sdkVersion: fixture.sdkVersion,
    });
    return 0;
  }

  // Best-effort prep of the bind-source dirs the captured argv references.
  for (const dir of fixture.prepDirs) {
    try {
      mkdirSync(dir, { recursive: true });
    } catch {
      // A prep-dir failure surfaces as a bwrap infra error below; do not abort.
    }
  }

  const { cmd, args } = buildBwrapInvocation(fixture);
  const res = spawnSync(cmd, args, { encoding: "utf8" });
  const verdict = classifyReplayVerdict({
    bwrapExitCode: res.status,
    bwrapStderr: `${res.stderr ?? ""}`,
    spawnErrorCode: res.error?.code,
  });
  emitVerdict({ ...verdict, sdkVersion: fixture.sdkVersion });
  // Always exit 0: the verdict is the payload (read from stdout). A non-zero
  // exit here is reserved for the host to read as `canary_infra_error` when the
  // `docker exec` itself fails (125/126/127) — see ci-deploy.sh.
  return 0;
}

async function runCapture(fixtureUrl) {
  // CI-only (PR3). Structurally unreachable at deploy-time: hard-refuse unless
  // explicitly opted in, so the paid/nondeterministic model turn can never fire
  // on a routine host deploy.
  if (process.env.SANDBOX_CANARY_CAPTURE !== "1") {
    process.stderr.write(
      "sandbox-canary: --capture requires SANDBOX_CANARY_CAPTURE=1 (CI only)\n",
    );
    return 2;
  }
  // Lazy dynamic import so the config's heavy static graph never loads on the
  // creds-free replay path (kept out of the replay import graph deliberately).
  const { buildAgentSandboxConfig } = await import(
    "../server/agent-runner-sandbox-config.ts"
  );
  // NOTE: the actual PATH-shim capture + SDK query() drive is wired and verified
  // in PR3 (ci.yml SDK-bump gate). The import above satisfies the faithfulness
  // contract: the captured argv derives from the SDK fed the REAL config, never
  // a re-specified options object.
  void buildAgentSandboxConfig;
  void fixtureUrl;
  process.stderr.write(
    "sandbox-canary: --capture is wired by PR3 (ci.yml SDK-bump gate)\n",
  );
  return 3;
}

async function main(argv) {
  const mode = argv.find((a) => a.startsWith("--"))?.slice(2) ?? "replay";
  const fixtureArg = argv.find((a) => !a.startsWith("--"));
  const fixtureUrl = fixtureArg
    ? pathToFileURL(fixtureArg)
    : (process.env.SANDBOX_CANARY_FIXTURE
        ? pathToFileURL(process.env.SANDBOX_CANARY_FIXTURE)
        : DEFAULT_FIXTURE_URL);

  switch (mode) {
    case "replay":
      return runReplay(fixtureUrl);
    case "capture":
    case "verify":
      return runCapture(fixtureUrl);
    default:
      process.stderr.write(`sandbox-canary: unknown mode --${mode}\n`);
      return 2;
  }
}

// Only run when invoked directly (not when imported by the test suite).
const invokedPath = process.argv[1] ? pathToFileURL(process.argv[1]).href : "";
if (invokedPath === import.meta.url) {
  main(process.argv.slice(2))
    .then((code) => process.exit(code))
    .catch((err) => {
      process.stderr.write(`sandbox-canary: ${err?.message ?? err}\n`);
      process.exit(2);
    });
}

// Referenced to keep the direct-invocation guard's fileURLToPath import used in
// environments that tree-shake; harmless no-op.
export const __mjsPath = fileURLToPath(import.meta.url);
