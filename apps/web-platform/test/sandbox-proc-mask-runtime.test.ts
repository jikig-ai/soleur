// #9723 — the tail-bind defect, observed through the FULL production chain:
// real Agent SDK + real production `buildAgentSandboxConfig` + a scripted API
// stand-in (no model, no network, no real credential). The vendored CLI
// PATH-resolves `bwrap`, so this test installs a wrapper ahead of the REAL
// shim that records the incoming argv and then execs the shim — pinning two
// end-to-end facts the unit rows cannot:
//
//   (a) the vendored spawn reaches OUR shim (PATH interception is the prod
//       image's deployment mechanism — Dockerfile installs the shim at
//       /usr/local/bin/bwrap ahead of /usr/bin/bwrap);
//   (b) the setup argv handed to it carries the #9723 defect shape — a tail
//       `--bind /proc /proc` after the denyRead `--tmpfs /proc`.
//
// The mask's positional rewrite and the empty-tmpfs + fd re-home outcome are pinned by
// the bwrap-shim unit rows, the real-bwrap row in that file, sandbox-isolation
// FR7b (control/treatment), and the canary proc_mask probe — all of which
// measure the setup namespace directly. An in-sandbox outcome assertion is
// deliberately absent here: the vendored `apply-seccomp` helper re-mounts
// /proc in a deeper userns on hosts where it runs (masking the defect from
// the command's view) and is denied CLONE_NEWUSER by the shim's own
// --add-seccomp-fd filter where it can't — either way the inner command is
// not a reliable defect discriminator, so asserting on it would be
// host-dependent theater. Same two-arm convention as
// sandbox-credential-deny-runtime.test.ts (W1/ADR-272).

import { afterAll, beforeAll, describe, expect, it, vi } from "vitest";
import { spawnSync } from "node:child_process";
import { mkdirSync, mkdtempSync, realpathSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

import { query } from "@anthropic-ai/claude-agent-sdk";

import { buildAgentSandboxConfig } from "@/server/agent-runner-sandbox-config";
import { startAnthropicStub, type AnthropicStub } from "./helpers/anthropic-stub";
import { pointCliAtStub, scrubAmbientCliEnv } from "./helpers/hermetic-cli-env";
import {
  assertTailMatchesFixture,
  liveTailOf,
  normalizeSpawnTail,
  readFixtureTail,
} from "./helpers/vendored-bwrap-tail";

const APP_ROOT = join(dirname(fileURLToPath(import.meta.url)), "..");
const BWRAP_SHIM = join(APP_ROOT, "infra", "bwrap-shim", "bwrap");
const BWRAP_BPF = join(APP_ROOT, "infra", "bwrap-userns-clone3-deny.bpf");
const CANARY_FIXTURE = join(APP_ROOT, "infra", "sandbox-canary-argv.json");

const BWRAP_OK =
  process.platform === "linux" &&
  spawnSync(
    "bwrap",
    ["--unshare-user", "--unshare-pid", "--ro-bind", "/", "/", "--", "true"],
    { stdio: "ignore", timeout: 15_000 },
  ).status === 0;
const SOCAT_OK =
  process.platform === "linux" &&
  spawnSync("sh", ["-c", "command -v socat"], { stdio: "ignore" }).status === 0;
const SANDBOX_OK = BWRAP_OK && SOCAT_OK;
if (process.platform === "linux" && !SANDBOX_OK && process.env.C4_BWRAP_REQUIRED) {
  throw new Error(
    `C4_BWRAP_REQUIRED is set but the sandbox cannot run here (bwrap usable: ${BWRAP_OK}, socat on PATH: ${SOCAT_OK}). ` +
      "apt-get install bubblewrap socat && sysctl -w kernel.apparmor_restrict_unprivileged_userns=0 (Ubuntu)",
  );
}

// Side-effect free — the stub answers every tool turn with this.
const PROBE = "true";

describe.skipIf(!SANDBOX_OK)("the vendored sandbox spawn reaches our bwrap shim (#9723)", () => {
  let stub: AnthropicStub | undefined;
  let root: string;
  let own: string;
  let home: string;
  let shimDir: string;
  let shimLog: string;
  const savedPath = process.env.PATH;

  beforeAll(async () => {
    root = realpathSync(mkdtempSync(join(tmpdir(), "sbx-procmask-")));
    own = join(root, "00000000-0000-0000-0000-000000000001");
    mkdirSync(own);
    home = realpathSync(mkdtempSync(join(tmpdir(), "sbx-procmask-home-")));
    shimDir = realpathSync(mkdtempSync(join(tmpdir(), "sbx-procmask-shim-")));
    shimLog = join(shimDir, "calls.log");
    // The wrapper records each invocation, then execs the REAL shim — the
    // full interception chain is exercised, not a look-alike.
    writeFileSync(
      join(shimDir, "bwrap"),
      `#!/usr/bin/env bash\n` +
        `printf '%s\\0' "$@" >> ${JSON.stringify(shimLog)}\n` +
        `printf '\\0' >> ${JSON.stringify(shimLog)}\n` +
        `exec ${JSON.stringify(BWRAP_SHIM)} "$@"\n`,
    );
    spawnSync("chmod", ["+x", join(shimDir, "bwrap")], { stdio: "ignore" });
    stub = await startAnthropicStub(PROBE);
    scrubAmbientCliEnv();
    pointCliAtStub(stub.port, home, "decoy-api-key-sentinel");
    vi.stubEnv("WORKSPACES_ROOT", root);
    vi.stubEnv("C4_RENDER_STAGING_ROOT", `${root}-c4-staging`);
    vi.stubEnv("SOLEUR_BWRAP_REAL", "/usr/bin/bwrap");
    vi.stubEnv("SOLEUR_BWRAP_SECCOMP_BPF", BWRAP_BPF);
    vi.stubEnv("PATH", `${shimDir}:${savedPath ?? "/usr/bin:/bin"}`);
  });

  afterAll(async () => {
    vi.unstubAllEnvs();
    await stub?.close();
    for (const dir of [root, root && `${root}-c4-staging`, home, shimDir]) {
      if (!dir) continue;
      try {
        rmSync(dir, { recursive: true, force: true, maxRetries: 10, retryDelay: 300 });
      } catch {
        /* scratch space; the runner's temp dir is ephemeral */
      }
    }
  });

  it("the SDK's sandbox spawn PATH-resolves our shim and hands it the tail-bind shape", async () => {
    const sandbox = buildAgentSandboxConfig(own);
    const controller = new AbortController();
    const q = query({
      prompt: "probe",
      options: {
        abortController: controller,
        model: "claude-haiku-4-5-20251001",
        maxTurns: 3,
        permissionMode: "default",
        cwd: own,
        allowedTools: ["Bash"],
        settingSources: [],
        sandbox: sandbox as never,
        canUseTool: async (_name, input) => ({ behavior: "allow", updatedInput: input }),
      },
    });
    try {
      for await (const _msg of q) {
        /* drain — the assertion is on the recorded spawn, not the result */
      }
    } finally {
      controller.abort();
    }

    // The shim was consulted at least once (PATH interception through the
    // full SDK → vendored CLI → bwrap chain).
    const calls = readFileSync(shimLog, "utf8").split("\0\0").filter(Boolean);
    expect(calls.length).toBeGreaterThan(0);

    // At least one call is a SETUP spawn carrying the #9723 defect shape:
    // `--tmpfs /proc` (denyRead) followed later by `--bind /proc /proc` (the
    // enableWeakerNestedSandbox tail) ahead of the `--` command boundary.
    const sawDefectShape = calls.some((call) => {
      const toks = call.split("\0").filter(Boolean);
      const boundary = toks.indexOf("--");
      const setup = boundary >= 0 ? toks.slice(0, boundary) : toks;
      const tmpfsIdx = setup.findIndex((t, i) => t === "--tmpfs" && setup[i + 1] === "/proc");
      const bindIdx = setup.findIndex(
        (t, i) => t === "--bind" && setup[i + 1] === "/proc" && setup[i + 2] === "/proc",
      );
      return tmpfsIdx >= 0 && bindIdx > tmpfsIdx;
    });
    expect(sawDefectShape, "no setup spawn carried `--tmpfs /proc` … `--bind /proc /proc`").toBe(true);

    // #10065 live-tail row: for every recorded SETUP spawn (the ones carrying the config's
    // `--tmpfs /proc` denyRead), the tokens from the last `--dev` to the `--` boundary equal the
    // committed fixture tail (infra/sandbox-canary-argv.json), cap segment normalized: the literal
    // tokens must match, `--cap-drop ALL` is required and every `--cap-add` must be CAP_SETFCAP
    // (the fixture was captured as root; a non-root run records a shorter segment). The relative
    // order check above only sees `--tmpfs`/`--bind` positions; this one sees the whole tail.
    const fixture = readFixtureTail(CANARY_FIXTURE);
    // A setup spawn is selected by its SHAPE (`--dev` and `--unshare-pid` before the boundary), never by the
    // property under test: selecting on `--tmpfs /proc` would silently skip a spawn that lost the denyRead.
    const setupSpawns = calls
      .map((call) => call.split("\0").filter(Boolean))
      .filter((toks) => {
        const boundary = toks.indexOf("--");
        const setup = boundary >= 0 ? toks.slice(0, boundary) : toks;
        return setup.includes("--dev") && setup.includes("--unshare-pid");
      });
    for (const toks of setupSpawns) {
      const boundary = toks.indexOf("--");
      const setup = boundary >= 0 ? toks.slice(0, boundary) : toks;
      expect(
        setup.some((t, i) => t === "--tmpfs" && setup[i + 1] === "/proc"),
        "a setup spawn lacks the config's `--tmpfs /proc` denyRead",
      ).toBe(true);
    }
    const setupTails = setupSpawns.map((toks) => liveTailOf(toks));
    expect(setupTails.length, "TAIL_DRIFT: no recorded setup spawn to compare against the fixture tail").toBeGreaterThan(0);
    for (const tail of setupTails) {
      expect(tail, "TAIL_DRIFT: a setup spawn has no --dev before the -- boundary").not.toBeNull();
      assertTailMatchesFixture(tail as string[], fixture, "live spawn");
    }
  }, 180_000);
});

// Creds-free, tool-free: the comparison the live row applies, driven on synthetic spawns built from
// the committed fixture tail. A normalization that ignored the cap segment would pass the
// CAP_SYS_ADMIN row; one that compared the raw segment would fail the non-root row.
describe("live-spawn tail comparison (pure rows)", () => {
  const fixture = readFixtureTail(CANARY_FIXTURE);
  const spawn = (tail: string[]) => ["--new-session", "--ro-bind", "/", "/", "--tmpfs", "/proc", ...tail, "--", "bash", "-c", "true"];
  const live = (toks: string[]) => liveTailOf(toks) as string[];
  const drift = (tail: string[]) => {
    try {
      assertTailMatchesFixture(live(spawn(tail)), fixture, "live spawn");
    } catch (e) {
      return (e as Error).message;
    }
    return "";
  };
  const capAt = fixture.indexOf("--cap-drop");

  it("the fixture's own tail matches itself (must-PASS control)", () => {
    expect(drift(fixture)).toBe("");
  });

  it("a non-root spawn (`--cap-drop ALL` without `--cap-add CAP_SETFCAP`) matches the root-captured fixture", () => {
    const nonRoot = fixture.filter((t, i) => !(i >= capAt + 2 && i < capAt + 4));
    expect(nonRoot).not.toEqual(fixture);
    expect(drift(nonRoot)).toBe("");
  });

  it("an added `--cap-add CAP_SYS_ADMIN` is rejected as CAP_BARRIER, not normalized away", () => {
    const withAdmin = [...fixture.slice(0, capAt + 2), "--cap-add", "CAP_SYS_ADMIN", ...fixture.slice(capAt + 2)];
    expect(drift(withAdmin)).toMatch(/CAP_BARRIER/);
  });

  it("a missing `--cap-drop ALL` is rejected as CAP_BARRIER", () => {
    const noDrop = fixture.filter((t, i) => !(i >= capAt && i < capAt + 2));
    expect(drift(noDrop)).toMatch(/CAP_BARRIER/);
  });

  it("an extra `--tmpfs /proc` after the bind is TAIL_DRIFT naming the in-image regeneration command", () => {
    const msg = drift([...fixture, "--tmpfs", "/proc"]);
    expect(msg).toMatch(/TAIL_DRIFT/);
    expect(msg).toMatch(/SANDBOX_CANARY_MODE=capture/);
    expect(msg).toMatch(/never hand-edit the fixture/);
  });

  it("a spawn whose proc branch flipped to `--proc /proc` is TAIL_DRIFT", () => {
    const flipped = [...fixture.slice(0, -3), "--proc", "/proc"];
    expect(drift(flipped)).toMatch(/TAIL_DRIFT/);
  });

  it("normalizeSpawnTail is idempotent on its own output", () => {
    const once = normalizeSpawnTail(fixture);
    expect(normalizeSpawnTail(once)).toEqual(once);
  });
});
