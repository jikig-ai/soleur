// W1 (#9601, ADR-272): the behaviour, not just the rendering. The argv test
// proves the SDK turns the config into `--unsetenv`; this proves what a command
// inside the REAL sandbox can then see. It drives the real SDK and the real
// production `buildAgentSandboxConfig` with real bubblewrap, against a scripted
// API stand-in (no model, no network, no real credential: the key is a decoy).
//
// Two arms, because a probe that has never found the decoy has not shown it can:
//   CONTROL   deny entries emptied, plain bwrap -> the shell sees the decoy variable
//             AND at least one readable /proc/<pid>/environ carries it (plain bwrap
//             leaves host procfs reachable). The positive control for the scan.
//   TREATMENT production config, through OUR bwrap shim (PATH-first, as in
//             production) -> the variable is absent AND no environ file is readable
//             inside the sandbox: the shim drops the procfs bind, so /proc is an
//             empty tmpfs (#10032). The shim is part of the boundary since #10445:
//             `allowAllUnixSockets` removes the SDK's apply-seccomp helper, whose
//             nested user namespace had incidentally hidden the launcher's environ
//             from plain bwrap. Without the shim the launcher's environ IS readable.
//
// It pins the OUTCOME. It runs on a CI runner, not the production image; the docker
// suite (infra/sandbox-masked-proc-docker.test.sh, "environ scan") repeats the
// treatment under the production run tuple.

import { afterAll, beforeAll, describe, expect, it, vi } from "vitest";
import { spawnSync } from "node:child_process";
import { mkdirSync, mkdtempSync, realpathSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

import { query } from "@anthropic-ai/claude-agent-sdk";

import { buildAgentSandboxConfig } from "@/server/agent-runner-sandbox-config";
import { startAnthropicStub, type AnthropicStub } from "./helpers/anthropic-stub";
import { pointCliAtStub, scrubAmbientCliEnv } from "./helpers/hermetic-cli-env";

const DECOY = "decoy-api-key-sentinel";
const APP_ROOT = join(dirname(fileURLToPath(import.meta.url)), "..");
const BWRAP_SHIM = join(APP_ROOT, "infra", "bwrap-shim", "bwrap");
const BWRAP_BPF = join(APP_ROOT, "infra", "bwrap-userns-clone3-deny.bpf");
const savedPath = process.env.PATH;

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
  let shimDir: string;

  beforeAll(async () => {
    root = realpathSync(mkdtempSync(join(tmpdir(), "sbx-deny-rt-")));
    own = join(root, "00000000-0000-0000-0000-000000000001");
    mkdirSync(own);
    home = realpathSync(mkdtempSync(join(tmpdir(), "sbx-deny-rt-home-")));
    shimDir = realpathSync(mkdtempSync(join(tmpdir(), "sbx-deny-rt-shim-")));
    writeFileSync(join(shimDir, "bwrap"), `#!/usr/bin/env bash\nexec ${JSON.stringify(BWRAP_SHIM)} "$@"\n`, { mode: 0o755 });
    stub = await startAnthropicStub(PROBE);
    scrubAmbientCliEnv();
    pointCliAtStub(stub.port, home, DECOY);
    vi.stubEnv("WORKSPACES_ROOT", root);
    vi.stubEnv("C4_RENDER_STAGING_ROOT", `${root}-c4-staging`);
    vi.stubEnv("SOLEUR_BWRAP_REAL", "/usr/bin/bwrap");
    vi.stubEnv("SOLEUR_BWRAP_SECCOMP_BPF", BWRAP_BPF);
  });

  afterAll(async () => {
    vi.unstubAllEnvs();
    await stub?.close();
    // Best-effort (see the argv test): a CLI child still draining must not fail a green test.
    for (const dir of [root, root && `${root}-c4-staging`, home, shimDir]) {
      if (!dir) continue;
      try {
        rmSync(dir, { recursive: true, force: true, maxRetries: 10, retryDelay: 300 });
      } catch {
        /* scratch space; the runner's temp dir is ephemeral */
      }
    }
  });

  async function observe(denyEntries: boolean, viaShim: boolean): Promise<Observation> {
    vi.stubEnv("PATH", viaShim ? `${shimDir}:${savedPath ?? "/usr/bin:/bin"}` : savedPath);
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
        // Stays on Haiku 4.5 on purpose: this drives the REAL Agent SDK query(), whose
        // bundled CLI is the pinned @anthropic-ai/claude-agent-sdk 0.3.284, and that
        // bundle does not know claude-haiku-5-5 (the first SDK release that does is
        // 0.3.293). Retires with the SDK bump; audit-models.sh carves out the two
        // scripts on the same ground and model-launch-review.test.ts expires it.
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
    const control = await observe(false, false);
    // The instrument produced an answer, and the answer is a positive.
    expect(control.ak).toBe("PRESENT");
    expect(control.readable).toBeGreaterThan(0);
    expect(control.decoyInEnviron).toBeGreaterThan(0);

    const treatment = await observe(true, true);
    expect(treatment.ak).toBe("ABSENT");
    // The shim's empty /proc: nothing readable, so nothing can carry the decoy. `toBe(0)` (not NaN)
    // is the instrument check: a sandbox that never ran prints no counters and fails here.
    expect(treatment.readable).toBe(0);
    expect(treatment.decoyInEnviron).toBe(0);
  }, 150_000);
});
