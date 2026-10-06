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
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

import { AGENT_AUTH_ENV_VARS } from "@/server/agent-auth-env-vars";
import { startAnthropicStub, type AnthropicStub } from "./helpers/anthropic-stub";
import { doCapture } from "../scripts/sandbox-canary.mjs";

// Variables that would route the CLI somewhere other than the local stand-in,
// or authenticate it with something other than the decoy. A developer's shell
// can export any of them.
const AMBIENT_ROUTING_VARS = [
  "ANTHROPIC_AUTH_TOKEN",
  "CLAUDE_CODE_OAUTH_TOKEN",
  "CLAUDE_CODE_USE_BEDROCK",
  "CLAUDE_CODE_USE_VERTEX",
  "CLAUDE_CODE_USE_FOUNDRY",
  "HTTP_PROXY",
  "HTTPS_PROXY",
  "ALL_PROXY",
  "http_proxy",
  "https_proxy",
  "all_proxy",
];

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
      // An isolated HOME keeps the CLI from touching the developer's real ~/.claude.
      home = mkdtempSync(join(tmpdir(), "sbx-deny-argv-home-"));
      vi.stubEnv("HOME", home);
      vi.stubEnv("ANTHROPIC_BASE_URL", `http://127.0.0.1:${stub.port}`);
      vi.stubEnv("ANTHROPIC_API_KEY", "decoy-key-not-a-secret");
      for (const name of AMBIENT_ROUTING_VARS) vi.stubEnv(name, undefined);
      vi.stubEnv("NO_PROXY", "127.0.0.1,localhost");
      vi.stubEnv("no_proxy", "127.0.0.1,localhost");
      vi.stubEnv("DISABLE_TELEMETRY", "1");
      vi.stubEnv("DISABLE_AUTOUPDATER", "1");
      vi.stubEnv("CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC", "1");
    });

    afterAll(async () => {
      vi.unstubAllEnvs();
      await stub?.close();
      if (home) rmSync(home, { recursive: true, force: true });
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

      const unsetAt: number[] = [];
      const unset: string[] = [];
      argv.forEach((tok, i) => {
        if (tok === "--unsetenv" && typeof argv[i + 1] === "string") {
          unset.push(argv[i + 1]);
          unsetAt.push(i);
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
  },
);
