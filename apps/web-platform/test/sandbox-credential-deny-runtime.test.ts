// W1 (#9601, ADR-272): the behaviour, not just the rendering. The argv test
// proves the SDK turns the config into `--unsetenv`; this proves what a command
// inside the REAL sandbox can then see. It drives the real SDK and the real
// production `buildAgentSandboxConfig` with real bubblewrap, against a scripted
// API stand-in (no model, no network, no real credential: the key is a decoy).
//
// Two arms, because a probe that has never found the decoy has not shown it can:
//   CONTROL   deny entries emptied  -> the shell sees the decoy variable AND at
//             least one readable /proc/<pid>/environ carries it. This is the
//             positive control for the scan.
//   TREATMENT production config     -> the variable is absent AND no readable
//             environ file inside the sandbox carries the decoy.
//
// What it does NOT claim: a mechanism. Why no environ carries the key is a
// property of bubblewrap's flags (PID namespace, user namespace, dumpability),
// and expert readings of the shipped argv disagreed; this test pins the OUTCOME,
// so a flag change that opens it turns this red whatever the cause. It also runs
// on a CI runner, not the production container image (ADR-272 says so).

import { afterAll, beforeAll, describe, expect, it, vi } from "vitest";
import { spawnSync } from "node:child_process";
import { mkdirSync, mkdtempSync, realpathSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

import { query } from "@anthropic-ai/claude-agent-sdk";

import { buildAgentSandboxConfig } from "@/server/agent-runner-sandbox-config";
import { startAnthropicStub, type AnthropicStub } from "./helpers/anthropic-stub";
import { pointCliAtStub, scrubAmbientCliEnv } from "./helpers/hermetic-cli-env";

const DECOY = "decoy-api-key-sentinel";

// Same convention as the C4 render suite: an unusable sandbox (bwrap that cannot
// create one, or no socat, which the SDK's own startup check needs) SKIPS locally
// and FAILS where CI sets C4_BWRAP_REQUIRED, so the guard cannot go silently absent.
const BWRAP_OK =
  process.platform === "linux" &&
  spawnSync(
    "bwrap",
    ["--unshare-user", "--unshare-pid", "--ro-bind", "/", "/", "--", "true"],
    { stdio: "ignore", timeout: 15_000 },
  ).status === 0;
const SOCAT_OK =
  process.platform === "linux" && spawnSync("sh", ["-c", "command -v socat"], { stdio: "ignore" }).status === 0;
const SANDBOX_OK = BWRAP_OK && SOCAT_OK;
if (process.platform === "linux" && !SANDBOX_OK && process.env.C4_BWRAP_REQUIRED) {
  throw new Error(
    `C4_BWRAP_REQUIRED is set but the sandbox cannot run here (bwrap usable: ${BWRAP_OK}, socat on PATH: ${SOCAT_OK}). ` +
      "apt-get install bubblewrap socat && sysctl -w kernel.apparmor_restrict_unprivileged_userns=0 (Ubuntu)",
  );
}

// Prints counts and flags only, never a value. The `[i]` keeps the scan's own
// command line from matching its own pattern.
const PROBE =
  "sh -c '" +
  'n=0; f=0; for p in /proc/[0-9]*; do ' +
  "if cat $p/environ >/dev/null 2>&1; then n=$((n+1)); " +
  "if grep -qa decoy-api-key-sent[i]nel $p/environ 2>/dev/null; then f=$((f+1)); fi; fi; done; " +
  "echo READABLE_ENVIRONS=$n; echo DECOY_IN_ENVIRON=$f; " +
  'if [ -n "$ANTHROPIC_API_KEY" ]; then echo AK=PRESENT; else echo AK=ABSENT; fi' +
  "'";

interface Observation {
  ak: "PRESENT" | "ABSENT" | undefined;
  readable: number;
  decoyInEnviron: number;
}

describe.skipIf(!SANDBOX_OK)("the credential deny, observed from inside the real sandbox (W1)", () => {
  let stub: AnthropicStub | undefined;
  let root: string;
  let own: string;
  let home: string;

  beforeAll(async () => {
    root = realpathSync(mkdtempSync(join(tmpdir(), "sbx-deny-rt-")));
    own = join(root, "00000000-0000-0000-0000-000000000001");
    mkdirSync(own);
    home = realpathSync(mkdtempSync(join(tmpdir(), "sbx-deny-rt-home-")));
    stub = await startAnthropicStub(PROBE);
    scrubAmbientCliEnv();
    pointCliAtStub(stub.port, home, DECOY);
    vi.stubEnv("WORKSPACES_ROOT", root);
    vi.stubEnv("C4_RENDER_STAGING_ROOT", `${root}-c4-staging`);
  });

  afterAll(async () => {
    vi.unstubAllEnvs();
    await stub?.close();
    if (root) {
      for (const dir of [root, `${root}-c4-staging`]) rmSync(dir, { recursive: true, force: true, maxRetries: 10, retryDelay: 300 });
    }
    if (home) rmSync(home, { recursive: true, force: true, maxRetries: 10, retryDelay: 300 });
  });

  async function observe(denyEntries: boolean): Promise<Observation> {
    const base = buildAgentSandboxConfig(own);
    const sandbox = denyEntries ? base : { ...base, credentials: { envVars: [] } };
    const seen: string[] = [];
    // Aborted in `finally`, so a hung stand-in or a failed assertion mid-iteration
    // cannot leave the CLI child running past the test.
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
      for await (const msg of q) {
        if (msg.type === "user") {
          const text = JSON.stringify((msg as { message?: { content?: unknown } }).message?.content ?? "");
          for (const m of text.matchAll(/(READABLE_ENVIRONS|DECOY_IN_ENVIRON)=(\d+)|AK=(PRESENT|ABSENT)/g)) {
            seen.push(m[0]);
          }
        }
      }
    } finally {
      controller.abort();
    }
    const num = (key: string): number => {
      const hit = seen.find((s) => s.startsWith(`${key}=`));
      return hit ? Number(hit.split("=")[1]) : Number.NaN;
    };
    const ak = seen.find((s) => s.startsWith("AK="))?.split("=")[1] as Observation["ak"];
    return { ak, readable: num("READABLE_ENVIRONS"), decoyInEnviron: num("DECOY_IN_ENVIRON") };
  }

  it("CONTROL sees the decoy (so the scan can find it); the production config does not", async () => {
    const control = await observe(false);
    // The instrument produced an answer, and the answer is a positive.
    expect(control.ak).toBe("PRESENT");
    expect(control.readable).toBeGreaterThan(0);
    expect(control.decoyInEnviron).toBeGreaterThan(0);

    const treatment = await observe(true);
    expect(treatment.ak).toBe("ABSENT");
    // The scan ran over real processes and found the decoy in none of them.
    expect(treatment.readable).toBeGreaterThan(0);
    expect(treatment.decoyInEnviron).toBe(0);
  }, 150_000);
});
