// W1 (#9601, ADR-272): the credential deny must survive an SDK bump. The unit
// suite (`agent-sandbox-credential-deny.test.ts`) pins the CONFIG object; this
// pins what the real SDK DOES with it. It drives the canary's own capture path
// (real SDK, real `buildAgentSandboxConfig`, a bwrap shim in place of
// bubblewrap) against a scripted API stand-in, then asserts the real bwrap
// setup argv carries `--unsetenv <NAME>` for each Anthropic auth variable.
//
// No credential, no bubblewrap run, no model: the stand-in answers one Bash tool
// call, so the property observed is the SDK's, not a model's. The SDK's own
// startup check still needs `bwrap` and `socat` on PATH (CI installs both).
// An SDK that silently stops honouring `sandbox.credentials` strips the pair
// from the argv and this reds. That is the ONLY detector: the SDK schema strips
// unknown keys, so a runtime session would start normally with the key exposed.
//
// This proves the SDK renders the config. That the production factories hand
// `query()` this config is pinned in agent-runner-query-options.test.ts.

import { afterAll, beforeAll, describe, expect, it, vi } from "vitest";
import { spawnSync } from "node:child_process";
import http from "node:http";
import type { AddressInfo } from "node:net";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

import { AGENT_AUTH_ENV_VARS } from "@/server/agent-auth-env-vars";
import { startAnthropicStub, type AnthropicStub } from "./helpers/anthropic-stub";
import { pointCliAtStub, scrubAmbientCliEnv } from "./helpers/hermetic-cli-env";
import { doCapture } from "../scripts/sandbox-canary.mjs";

describe.skipIf(process.platform !== "linux")(
  "real SDK bwrap argv carries the Anthropic credential deny (W1)",
  () => {
    let stub: AnthropicStub | undefined;
    let home: string | undefined;

    beforeAll(async () => {
      for (const tool of ["bwrap", "socat"]) {
        const found = spawnSync("sh", ["-c", `command -v ${tool}`], { stdio: "ignore" });
        if (found.status !== 0) {
          throw new Error(
            `${tool} is not on PATH: the SDK refuses to start its sandbox without it, so this guard cannot run. ` +
              "CI installs bubblewrap and socat in the test job; install them locally.",
          );
        }
      }
      stub = await startAnthropicStub("true");
      // An isolated HOME, and every ambient CLI/provider/proxy variable cleared
      // (including CLAUDE_CONFIG_DIR, which would otherwise re-point the CLI at
      // the developer's real settings), so nothing but the local stand-in is reachable.
      home = mkdtempSync(join(tmpdir(), "sbx-deny-argv-home-"));
      scrubAmbientCliEnv();
      pointCliAtStub(stub.port, home, "decoy-key-not-a-secret");
    });

    afterAll(async () => {
      vi.unstubAllEnvs();
      await stub?.close();
      // Best-effort. `doCapture` stops at the first setup argv, so the CLI it started can
      // still be writing under HOME here, and removal then races it (ENOTEMPTY in CI, even
      // with retries). The directory is scratch space under the OS temp dir, not something
      // the test asserts on, so a leftover directory must not fail a green test.
      if (home) {
        try {
          rmSync(home, { recursive: true, force: true, maxRetries: 10, retryDelay: 300 });
        } catch {
          /* a draining CLI child; the runner's temp dir is ephemeral */
        }
      }
    });

    it("emits --unsetenv for every auth variable, in the real captured setup argv", async () => {
      // One attempt with a bound well under the test timeout: a CLI that never
      // reaches the stub fails here and is aborted, instead of outliving the test.
      const result = await doCapture({ attempts: 1, attemptTimeoutMs: 60_000 });
      if (!result.ok) {
        throw new Error(`capture failed: ${JSON.stringify(result)}`);
      }
      const argv: string[] = result.rawSetupArgv;
      // The instrument saw a real argv, not an empty one.
      expect(argv.length).toBeGreaterThan(20);
      expect(stub?.requests()).toBeGreaterThan(0);

      const unset: string[] = [];
      argv.forEach((tok, i) => {
        if (tok === "--unsetenv" && typeof argv[i + 1] === "string") {
          unset.push(argv[i + 1]);
        }
      });
      for (const name of AGENT_AUTH_ENV_VARS) {
        expect(unset.filter((n) => n === name), `--unsetenv ${name}`).toHaveLength(1);
      }
      // The deny is exactly the auth set: no blanket scrub, and nothing the
      // SDK adds on its own that would hide a connected-service token.
      expect([...new Set(unset)].sort()).toEqual([...AGENT_AUTH_ENV_VARS].sort());

      // A later `--setenv <NAME>` would undo the unset; none may follow.
      const reSet = argv.flatMap((tok, i) =>
        tok === "--setenv" && (AGENT_AUTH_ENV_VARS as readonly string[]).includes(argv[i + 1])
          ? [argv[i + 1]]
          : [],
      );
      expect(reSet).toEqual([]);
    }, 90_000);

    it("honours the capture options: a CLI that never answers is aborted at the bound, not the module default", async () => {
      // The test above leans on `attempts: 1` and `attemptTimeoutMs`. If they were
      // ignored, a CLI that never reaches the API would burn 3 x 120 s and outlive
      // the test. A server that accepts and never replies is that CLI.
      const hang = http.createServer(() => {
        /* accept, never respond */
      });
      await new Promise<void>((resolve) => hang.listen(0, "127.0.0.1", () => resolve()));
      vi.stubEnv("ANTHROPIC_BASE_URL", `http://127.0.0.1:${(hang.address() as AddressInfo).port}`);
      try {
        const started = Date.now();
        const result = await doCapture({ attempts: 1, attemptTimeoutMs: 3_000 });
        expect(result.ok).toBe(false);
        // Bound + the SDK's SIGTERM grace, far under the 120 s module default.
        expect(Date.now() - started).toBeLessThan(40_000);
      } finally {
        vi.stubEnv("ANTHROPIC_BASE_URL", `http://127.0.0.1:${stub?.port}`);
        hang.closeAllConnections?.();
        await new Promise<void>((resolve) => hang.close(() => resolve()));
      }
    }, 90_000);
  },
);
