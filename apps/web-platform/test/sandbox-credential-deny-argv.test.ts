// W1 (#9601, ADR-272): the credential deny must survive an SDK bump. The unit
// suite (`agent-sandbox-credential-deny.test.ts`) pins the CONFIG object; this
// pins what the real SDK DOES with it. It drives the canary's own capture path
// (real SDK, real `buildAgentSandboxConfig`, a bwrap shim in place of
// bubblewrap) against a scripted API stand-in, then asserts the real bwrap
// setup argv carries `--unsetenv <NAME>` for each Anthropic auth variable.
//
// No credential, no network, no bubblewrap, no model: the stand-in answers one
// Bash tool call, so the property observed is the SDK's, not a model's.
// If an SDK bump stops honouring `sandbox.credentials`, the argv loses the pair
// and this reds in CI, which is the silent-exposure case the unit suite cannot see.

import { afterAll, beforeAll, describe, expect, it, vi } from "vitest";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

import { AGENT_AUTH_ENV_VARS } from "@/server/agent-auth-env-vars";
import { startAnthropicStub, type AnthropicStub } from "./helpers/anthropic-stub";
import { doCapture } from "../scripts/sandbox-canary.mjs";

describe("real SDK bwrap argv carries the Anthropic credential deny (W1)", () => {
  let stub: AnthropicStub;
  let home: string;

  beforeAll(async () => {
    stub = await startAnthropicStub("true");
    // An isolated HOME keeps the CLI from touching the developer's real ~/.claude.
    home = mkdtempSync(join(tmpdir(), "sbx-deny-argv-home-"));
    vi.stubEnv("HOME", home);
    vi.stubEnv("ANTHROPIC_BASE_URL", `http://127.0.0.1:${stub.port}`);
    vi.stubEnv("ANTHROPIC_API_KEY", "decoy-key-not-a-secret");
    vi.stubEnv("DISABLE_TELEMETRY", "1");
    vi.stubEnv("DISABLE_AUTOUPDATER", "1");
    vi.stubEnv("CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC", "1");
  });

  afterAll(async () => {
    vi.unstubAllEnvs();
    await stub.close();
    rmSync(home, { recursive: true, force: true });
  });

  it("emits --unsetenv for every auth variable, in the real captured setup argv", async () => {
    const result = await doCapture();
    if (!result.ok) {
      throw new Error(`capture failed: ${JSON.stringify(result)}`);
    }
    const argv: string[] = result.rawSetupArgv;
    // The instrument saw a real argv, not an empty one.
    expect(argv.length).toBeGreaterThan(20);
    expect(stub.requests()).toBeGreaterThan(0);

    const unset = new Set<string>();
    argv.forEach((tok, i) => {
      if (tok === "--unsetenv" && typeof argv[i + 1] === "string") unset.add(argv[i + 1]);
    });
    for (const name of AGENT_AUTH_ENV_VARS) {
      expect(unset.has(name), `--unsetenv ${name} missing from the bwrap argv`).toBe(true);
    }
    // And the deny is not a blanket scrub: a connected-service token is not unset.
    expect(unset.has("STRIPE_SECRET_KEY")).toBe(false);
    expect(unset.has("GH_TOKEN")).toBe(false);
  }, 90_000);
});
