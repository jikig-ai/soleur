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
import {
  chmodSync,
  mkdirSync,
  mkdtempSync,
  readFileSync,
  realpathSync,
  renameSync,
  rmSync,
  writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
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
 *
 * @param {{ bwrapExitCode?: number | null, bwrapStderr?: string, spawnErrorCode?: string }} [args]
 * @returns {{ verdict: "pass" | "sandbox_broken" | "canary_infra_error", reason: string }}
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
    // `canonical-bwrap-v1` argv carries ${CANARY_WS}/${CANARY_EMPTY}
    // placeholders that runReplay substitutes to real container paths before
    // the bwrap spawn (ADR-079 amendment / CTO Option A). Absent → a legacy
    // verbatim fixture (no placeholders), replayed as-is.
    schema: typeof obj.schema === "string" ? obj.schema : null,
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
 *
 * SECURITY BOUNDARY: the integrity of `bwrapSetupArgv` is enforced by the fixture
 * TRUST PATH — it is committed to the repo, baked into the image at build time
 * (Dockerfile COPY), and re-captured + byte-diffed (`--verify`) on every SDK/config
 * change; it is only ever populated by `--capture` driving the real SDK (which
 * emits `-`-prefixed setup options). The two checks below are cheap SANITY FILTERS,
 * NOT the security boundary: bwrap treats the first non-option token as the start of
 * the COMMAND (no `--` needed), so a hostile fixture could inject a command that
 * these structural checks cannot fully exclude (a `--bind SRC DEST` legitimately
 * carries non-dash value tokens). Do not lean on them as an authorization boundary.
 */
export function buildBwrapInvocation(fixture) {
  const argv = fixture.bwrapSetupArgv;
  if (argv.includes("--")) {
    throw new Error(
      "sandbox-canary: setup argv must not contain a '--' separator; replay appends its own no-op command",
    );
  }
  // A real bwrap SETUP argv always begins with an option (`--new-session`,
  // `--unshare-*`, …), never a bare command — cheapest filter for the obvious
  // "command in argv[0]" injection shape.
  if (!argv[0].startsWith("-")) {
    throw new Error(
      `sandbox-canary: setup argv must begin with a bwrap option, got '${argv[0]}'`,
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
// CAPTURE-side pure logic (#5913 / ADR-079 deferral B). LLM-free: the model
// turn decides only WHETHER the SDK builds+spawns bwrap; these functions decide
// what the fixture asserts, keeping the LLM out of the assertion path
// (learning 2026-04-19-llm-sdk-security-tests-need-deterministic-invocation).
// ---------------------------------------------------------------------------

// A FIXED, non-symlinked base for the hermetic capture workspace. On the pinned
// GH-hosted ubuntu-latest runner `/tmp` is a real directory (not a symlink like
// macOS `/private/var` or `$RUNNER_TEMP`), so a fixed `/tmp`-rooted path is
// realpath-stable and the captured argv is byte-reproducible for `--verify`.
// SECURITY (review #5913 L2): unlike the shim dir (`mkdtemp`, unpredictable),
// this root is GUESSABLE, and cleanup `rmSync`s it recursively. That is safe
// ONLY on a single-tenant, ephemeral runner (no second local user to pre-seed a
// `/tmp/soleur-sandbox-canary` symlink). If `--capture`/`--verify` ever runs on a
// shared or self-hosted runner, switch this to a per-run `mkdtemp` base and
// accept that the ws path is then normalized to `${CANARY_WS}` in the projection
// anyway (so byte-reproducibility survives — the fixed path is a determinism
// convenience, not a requirement of the canonical projection).
const CANARY_ROOT_BASE = "/tmp";
// A constant UUID for the own workspace so the captured argv never embeds a
// mktemp-random token (the byte-reproducibility crux). Valid v4 shape so it
// passes any UUID id-guard the SDK/config might apply.
const CANARY_WORKSPACE_UUID = "00000000-0000-4000-8000-0000000000ca";
// The single new predicate over `validateFixture` (which already checks
// array/non-empty/all-strings): a real bwrap SETUP argv carries a userns unshare.
const UNSHARE_TOKEN_RE = /^--unshare-/;
// Secret-shaped `--setenv` names — a forwarded value here would be a durable
// leak in the image-baked fixture (Dockerfile COPY). security-sentinel P1.
const SECRET_ENV_NAME_RE = /KEY|TOKEN|SECRET|PASSWORD/i;

/**
 * Split the shim's recorded argv at the FIRST `--`; the prefix is the bwrap
 * SETUP argv (options only), the suffix is the model-chosen command tail we
 * never store or replay. A later `--` inside the command tail is preserved
 * there (we split once).
 *
 * @param {string[]} rawArgv
 * @returns {string[]}
 */
export function parseShimSetupArgv(rawArgv) {
  const i = rawArgv.indexOf("--");
  return i === -1 ? [...rawArgv] : rawArgv.slice(0, i);
}

/**
 * PURE, IO-free. Compute the fixed zero-sibling hermetic path set. The FS
 * creation (mkdir) + realpath normalization live in the side-effecting Phase-2
 * runtime, not here. Given the same `base`, always returns byte-identical
 * paths — the property that makes the captured argv reproducible.
 *
 * The own workspace is the ONLY entry under `root`, so
 * `enumerateSiblingDenyPaths` returns exactly `["/proc"]` and the emitted argv
 * is deterministic by construction (no readdir-order hazard, no sort needed).
 *
 * @param {string} [base]
 * @returns {{ root: string, ownWorkspacePath: string, prepDirs: string[] }}
 */
export function computeCanaryPaths(base = CANARY_ROOT_BASE) {
  const root = join(base, "soleur-sandbox-canary");
  const ownWorkspacePath = join(root, CANARY_WORKSPACE_UUID);
  return { root, ownWorkspacePath, prepDirs: [ownWorkspacePath] };
}

/**
 * The SDK may spawn bwrap more than once per turn (e.g. a probe + the real
 * sandbox SETUP). Select the invocation carrying `--unshare-user` (the sandbox
 * SETUP spawn); return null if none did (no real sandbox was built).
 *
 * @param {string[][]} invocations - each is a parsed SETUP argv.
 * @returns {string[] | null}
 */
export function selectSandboxSetupArgv(invocations) {
  for (const argv of invocations) {
    if (Array.isArray(argv) && argv.some((t) => t === "--unshare-user")) {
      return argv;
    }
  }
  return null;
}

/**
 * LLM-free retry-loop decision: is `setupArgv` a valid captured sandbox SETUP
 * argv? Reuses `validateFixture`'s array/non-empty/all-strings checks and adds
 * the single new `--unshare-*` predicate. A completed model turn that never
 * spawned bwrap (or spawned it without a userns unshare) is NOT a capture.
 *
 * @param {{ captureFilePresent: boolean, setupArgv: unknown }} args
 * @returns {{ captured: boolean, reason: string }}
 */
export function assessCaptureOutcome({ captureFilePresent, setupArgv }) {
  if (!captureFilePresent) {
    return { captured: false, reason: "capture_no_bwrap:no_tool_call" };
  }
  if (!Array.isArray(setupArgv) || setupArgv.length === 0) {
    return { captured: false, reason: "capture_no_bwrap:empty_argv" };
  }
  if (!setupArgv.every((t) => typeof t === "string")) {
    return { captured: false, reason: "capture_no_bwrap:non_string_token" };
  }
  if (!setupArgv.some((t) => UNSHARE_TOKEN_RE.test(t))) {
    return { captured: false, reason: "capture_no_bwrap:no_unshare" };
  }
  return { captured: true, reason: "ok" };
}

// Canonical-projection placeholders (ADR-079 amendment / CTO Option A). The
// captured SDK argv embeds capture-host-specific paths; the projection replaces
// the hermetic-workspace prefix and the random empty-dir bind sources with
// these stable tokens so the committed fixture is byte-reproducible AND
// replayable off-host (runReplay substitutes real paths back at deploy-time).
export const CANARY_WS_PLACEHOLDER = "${CANARY_WS}";
export const CANARY_EMPTY_PLACEHOLDER = "${CANARY_EMPTY}";

// bwrap option arities for the projection parser. `null` = classify as a
// bind-like 2-arg (src, dest). An unrecognized `--option` throws (fail loud →
// ack-fallback in the gate) rather than mis-parse a shifted SDK argv.
const BWRAP_ZERO_ARG = new Set([
  "--new-session",
  "--die-with-parent",
  "--clearenv",
  "--disable-userns",
  "--assert-userns-disabled",
  "--as-pid-1",
]);
// 1-arg options whose single arg is a PATH we may normalize/keep.
const BWRAP_ONE_ARG_PATH = new Set([
  "--dev",
  "--proc",
  "--tmpfs",
  "--mqueue",
  "--dir",
  "--remount-ro",
  "--chdir",
]);
// 1-arg options whose arg is NOT a path (numeric / name) — kept verbatim.
const BWRAP_ONE_ARG_OPAQUE = new Set([
  "--uid",
  "--gid",
  "--hostname",
  "--argv0",
  "--size",
  "--perms",
  "--chmod",
  "--seccomp",
  "--add-seccomp-fd",
  "--userns",
  "--userns2",
  "--pidns",
  "--sync-fd",
  "--info-fd",
  "--json-status-fd",
  "--block-fd",
  "--userns-block-fd",
  "--unsetenv",
  "--cap-add",
  "--cap-drop",
]);
// 2-arg bind-like options (src, dest).
const BWRAP_TWO_ARG_BIND = new Set([
  "--bind",
  "--bind-try",
  "--dev-bind",
  "--dev-bind-try",
  "--ro-bind",
  "--ro-bind-try",
  "--symlink",
  "--file",
  "--bind-data",
  "--ro-bind-data",
]);

const RANDOM_SOCKET_RE = /\/claude-http-[0-9a-f]+\.sock$/;
const RANDOM_EMPTY_RE = /\/claude-empty-[A-Za-z0-9]+$/;

function isDeterministicConstPath(p) {
  return (
    p === "/" ||
    p === "/dev/null" ||
    p === "/proc" ||
    p === "/dev" ||
    p.startsWith("/proc/") ||
    p.startsWith("/dev/") ||
    p.startsWith("/sys")
  );
}

/**
 * Canonical projection of the raw SDK bwrap SETUP argv (CTO Option A, ADR-079
 * amendment — supersedes the "verbatim, no normalization" clause of deferral B,
 * whose "byte-reproducible by construction" premise the empirical 0.3.197 argv
 * falsified). Runs AFTER the secret-scrub gate. Keeps every seccomp-relevant
 * structural token (all `--unshare-*`, `--dev`, `--tmpfs`, deterministic-const
 * binds, ws-relative binds), normalizes the ws root → `${CANARY_WS}` and the
 * random empty-dir bind source → `${CANARY_EMPTY}`, and DROPS the axes that are
 * non-deterministic or host-specific (all `--setenv`, the random proxy socket,
 * host-specific binds). The full `--unshare-*` multiset MUST survive — it is the
 * #5849 split-unshare discriminator (enforced by the deploy-time/CI replay
 * against the pre-#5874 profile, ADR-079 §2d proof obligation).
 *
 * @param {string[]} rawArgv
 * @param {{ wsRoot: string }} opts - the realpath'd hermetic own-workspace path.
 * @returns {{ bwrapSetupArgv: string[], prepDirs: string[],
 *   dropped: { setenv: number, hostBind: number, randomSocket: number, randomEmptyDirBind: number } }}
 */
export function normalizeCapturedArgv(rawArgv, { wsRoot }) {
  const norm = (p) => {
    if (typeof p !== "string") return p;
    if (p === wsRoot) return CANARY_WS_PLACEHOLDER;
    if (p.startsWith(`${wsRoot}/`)) {
      return CANARY_WS_PLACEHOLDER + p.slice(wsRoot.length);
    }
    return p;
  };
  const isWs = (p) =>
    typeof p === "string" && (p === wsRoot || p.startsWith(`${wsRoot}/`));

  const out = [];
  const dropped = {
    setenv: 0,
    hostBind: 0,
    randomSocket: 0,
    randomEmptyDirBind: 0,
  };

  for (let i = 0; i < rawArgv.length; ) {
    const tok = rawArgv[i];
    if (BWRAP_ZERO_ARG.has(tok) || /^--unshare-/.test(tok)) {
      out.push(tok);
      i += 1;
    } else if (tok === "--setenv" || tok === "--setenv-try") {
      dropped.setenv += 1;
      i += 3; // NAME VALUE
    } else if (tok === "--args") {
      i += 2; // FD — never persisted; parseShimSetupArgv already resolved it
    } else if (BWRAP_ONE_ARG_PATH.has(tok)) {
      out.push(tok, norm(rawArgv[i + 1]));
      i += 2;
    } else if (BWRAP_ONE_ARG_OPAQUE.has(tok)) {
      out.push(tok, rawArgv[i + 1]);
      i += 2;
    } else if (BWRAP_TWO_ARG_BIND.has(tok)) {
      const src = rawArgv[i + 1];
      const dst = rawArgv[i + 2];
      if (RANDOM_SOCKET_RE.test(src) || RANDOM_SOCKET_RE.test(dst)) {
        dropped.randomSocket += 1;
      } else if (RANDOM_EMPTY_RE.test(src) && isWs(dst)) {
        // Random empty-dir source → stable placeholder; deterministic dst kept.
        out.push(tok, CANARY_EMPTY_PLACEHOLDER, norm(dst));
        dropped.randomEmptyDirBind += 1;
      } else if (
        (isWs(src) || isDeterministicConstPath(src)) &&
        (isWs(dst) || isDeterministicConstPath(dst))
      ) {
        out.push(tok, norm(src), norm(dst));
      } else {
        // Host-specific bind (e.g. /home/<user>/.npm/_logs) — not in the prod
        // canary container; dropping it is what makes the replay run off-host.
        dropped.hostBind += 1;
      }
      i += 3;
    } else if (typeof tok === "string" && tok.startsWith("-")) {
      throw new Error(
        `normalizeCapturedArgv: unrecognized bwrap option '${tok}' — SDK argv shape changed, refusing to project (fail loud → ack-fallback)`,
      );
    } else {
      // A bare (non-option) leading token would mean a command crept into the
      // setup argv — buildBwrapInvocation's argv[0] guard rejects it downstream.
      out.push(tok);
      i += 1;
    }
  }

  // prepDirs: the placeholder directories runReplay must mkdir before binding.
  // Only directory roots — bwrap auto-creates nested mount points; file-mount
  // dsts (/dev/null → …/.gitconfig) must NOT be pre-created as dirs.
  const prepDirs = [CANARY_WS_PLACEHOLDER];
  if (dropped.randomEmptyDirBind > 0 || out.includes(CANARY_EMPTY_PLACEHOLDER)) {
    prepDirs.push(CANARY_EMPTY_PLACEHOLDER);
  }

  return { bwrapSetupArgv: out, prepDirs, dropped };
}

/**
 * Replay-time substitution: replace the canonical placeholders with real paths.
 * Applied to `bwrapSetupArgv` AND `prepDirs` before the bwrap spawn.
 *
 * @param {string[]} argv
 * @param {{ ws: string, empty: string }} paths
 * @returns {string[]}
 */
export function substituteCanonicalArgv(argv, { ws, empty }) {
  return argv.map((t) =>
    typeof t === "string"
      ? t
          .split(CANARY_WS_PLACEHOLDER)
          .join(ws)
          .split(CANARY_EMPTY_PLACEHOLDER)
          .join(empty)
      : t,
  );
}

/**
 * Secret-scrub predicate. Returns a rejection reason string if the SETUP argv
 * would leak a secret into the committed, image-baked fixture, else null.
 * Two classes: (a) any token containing the literal API-key value; (b) a
 * `--setenv <NAME> <VALUE>` whose NAME matches /KEY|TOKEN|SECRET|PASSWORD/i.
 *
 * Two placements (CTO §5): (1) on the RAW argv with `checkSetenvNames:false` —
 * catches the SDK forwarding the literal key value into ANY token, WITHOUT
 * rejecting on the benign secret-shaped `--setenv` NAMEs the SDK always forwards
 * (e.g. an empty `CLOUDSDK_PROXY_PASSWORD`) which projection DROPS anyway; (2) on
 * the CANONICAL (committed) argv with names on — the fail-closed backstop for a
 * secret in a KEPT token class (a future SDK embedding a credential in a bind
 * path or a retained `--setenv`). Reject, never silently strip.
 *
 * @param {string[]} argv
 * @param {string} secretValue - the API key value (may be empty).
 * @param {{ checkSetenvNames?: boolean }} [opts]
 * @returns {string | null}
 */
export function argvSecretRejection(argv, secretValue, opts = {}) {
  const { checkSetenvNames = true } = opts;
  for (let i = 0; i < argv.length; i++) {
    const tok = argv[i];
    if (secretValue && typeof tok === "string" && tok.includes(secretValue)) {
      return "secret_scrub:literal_key_value";
    }
    if (checkSetenvNames && tok === "--setenv") {
      const name = argv[i + 1];
      if (typeof name === "string" && SECRET_ENV_NAME_RE.test(name)) {
        return `secret_scrub:setenv_${name}`;
      }
    }
  }
  return null;
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

  // Canonical fixtures (canonical-bwrap-v1) carry ${CANARY_WS}/${CANARY_EMPTY}
  // placeholders — substitute real container paths before mkdir + spawn. A
  // legacy verbatim fixture has no placeholders, so substitution is a no-op.
  let replayFixture = fixture;
  if (fixture.schema === "canonical-bwrap-v1") {
    const ws = mkdtempSync(join(tmpdir(), "canary-replay-ws-"));
    const empty = mkdtempSync(join(tmpdir(), "canary-replay-empty-"));
    replayFixture = {
      ...fixture,
      bwrapSetupArgv: substituteCanonicalArgv(fixture.bwrapSetupArgv, {
        ws,
        empty,
      }),
      prepDirs: substituteCanonicalArgv(fixture.prepDirs, { ws, empty }),
    };
  }

  // Best-effort prep of the bind-source dirs the captured argv references.
  for (const dir of replayFixture.prepDirs) {
    try {
      mkdirSync(dir, { recursive: true });
    } catch {
      // A prep-dir failure surfaces as a bwrap infra error below; do not abort.
    }
  }

  const { cmd, args } = buildBwrapInvocation(replayFixture);
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

// Reserved exit code for a capture-MECHANISM failure (model never spawned
// bwrap, query() threw, import failed, secret-scrub reject). Distinct from the
// taken codes — 0 (replay verdict-is-payload), 2 (env/usage error), 3 (legacy
// stub) — so the CI gate can tell "capture broke → ack-fallback" from
// "captured + profile EPERM'd → block" (CTO §1). NEVER writes the fixture.
const EXIT_CAPTURE_MECH_FAIL = 4;
const CAPTURE_ATTEMPTS = 3;
const ATTEMPT_TIMEOUT_MS = 120_000; // per attempt; end-to-end ceiling N×this.
// Cheapest model that reliably issues one Bash tool call. Verified against the
// claude-api reference at implementation time (#5913): claude-haiku-4-5,
// $1/$5 per MTok, 200K ctx. The turn OUTPUT is irrelevant — the shim execs
// nothing; the SDK need only build+spawn bwrap once. Disclosed per-SDK-bump-PR
// API cost: one short Haiku turn, creds-gated, never on routine deploys.
const CAPTURE_MODEL = "claude-haiku-4-5";
// A maximally-directive no-op so the model acts instead of reasoning.
const CAPTURE_PROMPT =
  "Run the Bash command `true` exactly once and then stop. Do not explain, do not run anything else.";

const SHIM_SOURCE = `#!/usr/bin/env node
// bwrap-intercepting shim (#5913). Records ONLY argv (never process.env) to the
// capture file, then exit 0 — it does NOT exec the model-chosen command tail
// (no model-provided code runs in the creds-bearing job; security-sentinel P2).
const fs = require("fs");
const argv = process.argv.slice(2);
// The SDK PROBES bwrap availability with \`bwrap --version\` (and refuses to
// build the sandbox — failIfUnavailable — if the probe looks broken). Answer it
// like the real binary so the probe passes and the SDK proceeds to the real
// SETUP spawn we want to capture. (A version-only invocation carries no setup
// argv, so nothing to record.)
if (argv.length === 1 && argv[0] === "--version") {
  process.stdout.write("bubblewrap 0.11.1\\n");
  process.exit(0);
}
const rec = { argv };
// bwrap may pass setup args via \`--args FD\` (NUL-separated on a pipe fd)
// rather than argv; capture that stream too so the setup argv is never missed.
const ai = argv.indexOf("--args");
if (ai !== -1 && argv[ai + 1] != null) {
  try { rec.argsFd = fs.readFileSync(Number(argv[ai + 1]), "utf8"); }
  catch (e) { rec.argsFdError = String((e && e.message) || e); }
}
try { fs.appendFileSync(process.env.SOLEUR_CANARY_CAPTURE_FILE, JSON.stringify(rec) + "\\n"); }
catch { /* best-effort; a missing capture file surfaces as no-bwrap downstream */ }
process.exit(0);
`;

/**
 * Read the shim's recorded invocations and return each parsed SETUP argv.
 * Prefers the `--args`-FD stream (NUL-separated) when the SDK used it.
 */
function readCapturedInvocations(captureFile) {
  let raw;
  try {
    raw = readFileSync(captureFile, "utf8");
  } catch {
    return [];
  }
  const invocations = [];
  for (const line of raw.split("\n")) {
    if (!line.trim()) continue;
    let rec;
    try {
      rec = JSON.parse(line);
    } catch {
      continue;
    }
    let argv = Array.isArray(rec.argv) ? rec.argv : [];
    if (typeof rec.argsFd === "string" && rec.argsFd.length > 0) {
      argv = rec.argsFd.split("\0").filter((t) => t.length > 0);
    }
    invocations.push(parseShimSetupArgv(argv));
  }
  return invocations;
}

/**
 * Drive the real SDK against the real sandbox config with a bwrap-intercepting
 * PATH shim, retrying under a per-attempt wall-clock timeout until a valid
 * `--unshare-user` SETUP argv is captured. Returns a discriminated result; the
 * caller decides whether to write the committed fixture (`--capture`) or
 * byte-diff it (`--verify`). All hermetic state is cleaned up in `finally`.
 *
 * Returns the RAW SETUP argv (unprojected) + the hermetic `wsRoot`; the caller
 * runs the secret-scrub then `normalizeCapturedArgv` (CTO Option A). The raw
 * argv is NOT written anywhere (it carries host paths + env forwarding).
 *
 * @returns {Promise<{ ok: true, rawSetupArgv: string[], wsRoot: string, sdkVersion: string, sdkPackage: string }
 *                  | { ok: false, reason: string }>}
 */
export async function doCapture() {
  const SDK_PACKAGE = "@anthropic-ai/claude-agent-sdk";
  // Lazy import so the config's heavy static graph never loads on the creds-free
  // replay path (unit test sandbox-canary.test.ts asserts this stays lazy).
  const { query } = await import(SDK_PACKAGE);
  const { buildAgentSandboxConfig } = await import(
    "../server/agent-runner-sandbox-config.ts"
  );
  const sdkVersion = await (async () => {
    try {
      const pkg = await import(`${SDK_PACKAGE}/package.json`, {
        with: { type: "json" },
      });
      return String(pkg.default?.version ?? pkg.version ?? "");
    } catch {
      return "";
    }
  })();

  const { root, ownWorkspacePath } = computeCanaryPaths();
  const shimDir = mkdtempSync(join(tmpdir(), "soleur-canary-shim-"));
  const captureFile = join(shimDir, "captured-argv.jsonl");
  const prevPath = process.env.PATH;
  const prevWorkspacesRoot = process.env.WORKSPACES_ROOT;

  try {
    // Hermetic zero-sibling root: own workspace is the ONLY entry under root, so
    // enumerateSiblingDenyPaths → denyRead:["/proc"] and the argv is byte-det.
    mkdirSync(ownWorkspacePath, { recursive: true });
    const resolvedRoot = realpathSync(root);
    const resolvedOwn = realpathSync(ownWorkspacePath);
    process.env.WORKSPACES_ROOT = resolvedRoot;

    // bwrap shim FIRST on PATH (mktemp -d 0700 — a predictable /tmp shim path
    // is a pre-seeding/symlink vector; security-sentinel).
    chmodSync(shimDir, 0o700);
    const shimPath = join(shimDir, "bwrap");
    writeFileSync(shimPath, SHIM_SOURCE, { mode: 0o700 });
    process.env.PATH = `${shimDir}:${prevPath ?? ""}`;
    process.env.SOLEUR_CANARY_CAPTURE_FILE = captureFile;

    const sandbox = buildAgentSandboxConfig(resolvedOwn);

    let lastReason = "capture_no_bwrap:no_tool_call";
    for (let attempt = 1; attempt <= CAPTURE_ATTEMPTS; attempt++) {
      const controller = new AbortController();
      let timedOut = false;
      const timer = setTimeout(() => {
        timedOut = true;
        controller.abort();
      }, ATTEMPT_TIMEOUT_MS);
      try {
        const q = query({
          prompt: CAPTURE_PROMPT,
          options: {
            model: CAPTURE_MODEL,
            maxTurns: 2,
            // NOT "bypassPermissions": that maps to --dangerously-skip-permissions,
            // which claude.exe REFUSES under root ("cannot be used with root/sudo
            // privileges") — and the capture runs as root in CI/in-image. The
            // `canUseTool` force-allow below + `autoAllowBashIfSandboxed` in the
            // sandbox config already auto-allow the one Bash op, so "default" is
            // sufficient and root-compatible (#5913 in-image capture fix).
            permissionMode: "default",
            cwd: resolvedOwn,
            allowedTools: ["Bash"],
            sandbox,
            abortController: controller,
            // Force-allow so the model acts; the shim exits 0 so no command runs.
            canUseTool: async (_name, input) => ({
              behavior: "allow",
              updatedInput: input,
            }),
          },
        });
        for await (const _msg of q) {
          void _msg;
          // Early-out the moment a sandbox SETUP spawn is observed.
          if (selectSandboxSetupArgv(readCapturedInvocations(captureFile))) {
            break;
          }
        }
      } catch (err) {
        lastReason = timedOut
          ? "capture_no_bwrap:timeout"
          : `capture_no_bwrap:query_threw`;
        process.stderr.write(
          `sandbox-canary: capture attempt ${attempt} error: ${err?.message ?? err}\n`,
        );
      } finally {
        clearTimeout(timer);
      }

      const setupArgv = selectSandboxSetupArgv(
        readCapturedInvocations(captureFile),
      );
      const outcome = assessCaptureOutcome({
        captureFilePresent: setupArgv != null,
        setupArgv,
      });
      if (outcome.captured) {
        return {
          ok: true,
          rawSetupArgv: setupArgv,
          wsRoot: resolvedOwn,
          sdkVersion,
          sdkPackage: SDK_PACKAGE,
        };
      }
      lastReason = outcome.reason;
    }
    return { ok: false, reason: lastReason };
  } finally {
    if (prevPath === undefined) delete process.env.PATH;
    else process.env.PATH = prevPath;
    if (prevWorkspacesRoot === undefined) delete process.env.WORKSPACES_ROOT;
    else process.env.WORKSPACES_ROOT = prevWorkspacesRoot;
    delete process.env.SOLEUR_CANARY_CAPTURE_FILE;
    // Remove the shim bin/, hermetic root, and capture file. ANTHROPIC_API_KEY
    // was env-only throughout — never a CLI arg, never a temp file.
    try {
      rmSync(shimDir, { recursive: true, force: true });
    } catch {
      /* best-effort */
    }
    try {
      rmSync(root, { recursive: true, force: true });
    } catch {
      /* best-effort */
    }
  }
}

/**
 * Shared entry for `--capture` (write committed fixture) and `--verify`
 * (re-capture to a temp fixture + byte-diff). One routine parameterized by
 * output target (simplicity review). Every failure path emits a structured
 * verdict JSON before returning a non-fixture exit — no exit-2/no-verdict path.
 */
async function runCapture(fixtureUrl, { verify = false } = {}) {
  // CI-only. Structurally unreachable at deploy-time unless explicitly opted in,
  // so the paid/nondeterministic model turn can never fire on a routine deploy.
  if (process.env.SANDBOX_CANARY_CAPTURE !== "1") {
    emitVerdict({
      verdict: "canary_infra_error",
      reason: "capture_opt_in_required",
    });
    process.stderr.write(
      "sandbox-canary: --capture/--verify requires SANDBOX_CANARY_CAPTURE=1 (CI only)\n",
    );
    return EXIT_CAPTURE_MECH_FAIL;
  }
  const apiKey = process.env.ANTHROPIC_API_KEY;
  if (!apiKey) {
    // Fork PRs receive no secrets — degrade to the human ack, never block.
    emitVerdict({ verdict: "canary_infra_error", reason: "creds_absent" });
    return EXIT_CAPTURE_MECH_FAIL;
  }

  let result;
  try {
    result = await doCapture();
  } catch (err) {
    // Top-level catch (query()/import throw, shim-write error): route through a
    // structured verdict so the in-surface probe fires on EVERY path.
    emitVerdict({
      verdict: "canary_infra_error",
      reason: `capture_error:${err?.name ?? "unknown"}`,
    });
    process.stderr.write(`sandbox-canary: ${err?.message ?? err}\n`);
    return EXIT_CAPTURE_MECH_FAIL;
  }

  if (!result.ok) {
    // capture mechanism gave up (no bwrap / timeout / query threw) — NON-fixture.
    emitVerdict({ verdict: "canary_infra_error", reason: result.reason });
    return EXIT_CAPTURE_MECH_FAIL;
  }

  // Secret-scrub, stage 1 — RAW argv, literal-value only (CTO §5, reconciled to
  // empirical reality): the SDK ALWAYS forwards a benign secret-shaped env var
  // (`CLOUDSDK_PROXY_PASSWORD`, empty) that projection DROPS, so rejecting on
  // raw `--setenv` NAMEs would block every capture. Here we catch only the SDK
  // forwarding the literal key VALUE into any token.
  const rawScrub = argvSecretRejection(result.rawSetupArgv, apiKey, {
    checkSetenvNames: false,
  });
  if (rawScrub) {
    emitVerdict({ verdict: "canary_infra_error", reason: rawScrub });
    return EXIT_CAPTURE_MECH_FAIL;
  }

  // Canonical projection (CTO Option A): drop env-forwarding + random/host paths,
  // normalize the ws root, keep the seccomp-relevant structure. This is what
  // makes the committed fixture byte-reproducible AND replayable off-host.
  let projected;
  try {
    projected = normalizeCapturedArgv(result.rawSetupArgv, {
      wsRoot: result.wsRoot,
    });
  } catch (err) {
    // Unrecognized bwrap option → SDK argv shape changed; fail loud (ack-fallback).
    emitVerdict({
      verdict: "canary_infra_error",
      reason: `projection_error:${err?.message?.includes("unrecognized") ? "unrecognized_option" : "unknown"}`,
    });
    process.stderr.write(`sandbox-canary: ${err?.message ?? err}\n`);
    return EXIT_CAPTURE_MECH_FAIL;
  }

  const captured = {
    _comment:
      "Real-captured SDK bwrap SETUP argv (canonical projection) for the faithful sandbox canary (#5875 / #5913 / ADR-079). Populated by --capture driving the real @anthropic-ai/claude-agent-sdk query() with buildAgentSandboxConfig(), then normalizeCapturedArgv() (drops env-forwarding + random/host paths, keeps the seccomp-relevant --unshare-*/mount structure; ${CANARY_WS}/${CANARY_EMPTY} placeholders substituted at replay). MUST NOT be hand-authored (#4932 trap).",
    status: "captured",
    schema: "canonical-bwrap-v1",
    sdkPackage: result.sdkPackage,
    sdkVersion: result.sdkVersion,
    bwrapSetupArgv: projected.bwrapSetupArgv,
    prepDirs: projected.prepDirs,
    // Audit-only — NOT part of the --verify byte-diff (counts can vary per run).
    droppedForDeterminism: projected.dropped,
  };

  // Secret-scrub, stage 2 — the CANONICAL (committed) argv, names+value on
  // (CTO §5 backstop). Projection drops all `--setenv`, so a benign forwarded
  // env var can't reach here; this catches a secret that survived into a KEPT
  // token class (a credential in a bind path, or a `--setenv` a future SDK
  // keeps). The committed fixture is image-baked — fail loud, never ship it.
  const canonScrub = argvSecretRejection(captured.bwrapSetupArgv, apiKey);
  if (canonScrub) {
    emitVerdict({ verdict: "canary_infra_error", reason: `canonical_${canonScrub}` });
    return EXIT_CAPTURE_MECH_FAIL;
  }

  if (verify) {
    // Re-capture done; byte-diff against the committed fixture's argv.
    let committed;
    try {
      committed = validateFixture(
        JSON.parse(readFileSync(fixtureUrl, "utf8")),
      );
    } catch (err) {
      emitVerdict({
        verdict: "canary_infra_error",
        reason: `verify_read_error:${err?.code ?? "parse"}`,
      });
      return EXIT_CAPTURE_MECH_FAIL;
    }
    // Diff the CANONICAL fields only (argv + prepDirs) — droppedForDeterminism
    // counts can vary run-to-run and are audit-only, never part of the gate.
    const a = JSON.stringify({
      bwrapSetupArgv: committed.bwrapSetupArgv ?? null,
      prepDirs: committed.prepDirs ?? null,
    });
    const b = JSON.stringify({
      bwrapSetupArgv: captured.bwrapSetupArgv,
      prepDirs: captured.prepDirs,
    });
    if (a !== b) {
      emitVerdict({
        verdict: "canary_infra_error",
        reason: "argv_drift",
        message:
          "committed sandbox-canary-argv.json is stale — re-run --capture and commit the refreshed argv",
      });
      return 1; // drift blocks (the always-on deterministic gate).
    }
    emitVerdict({ verdict: "verify_ok", reason: "ok", sdkVersion: captured.sdkVersion });
    return 0;
  }

  // --capture: write the committed fixture atomically (temp + rename).
  const fixturePath = fileURLToPath(fixtureUrl);
  const tmpPath = `${fixturePath}.tmp`;
  writeFileSync(tmpPath, `${JSON.stringify(captured, null, 2)}\n`);
  renameSync(tmpPath, fixturePath);
  emitVerdict({
    verdict: "captured",
    reason: "ok",
    sdkVersion: captured.sdkVersion,
    tokenCount: captured.bwrapSetupArgv.length,
  });
  return 0;
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
      return runCapture(fixtureUrl, { verify: false });
    case "verify":
      return runCapture(fixtureUrl, { verify: true });
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
      // Process-level backstop: emit a structured verdict so NO exit-with-no-
      // verdict path escapes the blind capture surface (e.g. an EACCES/ENOSPC on
      // the atomic fixture write, which throws AFTER runCapture's last
      // emitVerdict). The CI gate reads the verdict reason; a verdict-less exit
      // would degrade to an ack-fallback with an empty (undiscriminating)
      // reason. Observability review #5913 P2.
      emitVerdict({
        verdict: "canary_infra_error",
        reason: `capture_error:uncaught_${err?.name ?? "unknown"}`,
      });
      process.stderr.write(`sandbox-canary: ${err?.message ?? err}\n`);
      process.exit(EXIT_CAPTURE_MECH_FAIL);
    });
}

// Referenced to keep the direct-invocation guard's fileURLToPath import used in
// environments that tree-shake; harmless no-op.
export const __mjsPath = fileURLToPath(import.meta.url);
