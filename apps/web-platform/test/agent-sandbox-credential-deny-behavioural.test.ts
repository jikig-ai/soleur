// #12469 T9b: the behavioural probe behind the diagnosis of "gh has no credentials in the Soleur Cloud sandbox".
//
// Claim under test (ADR-278 D5): with Agent web access ON, `buildAgentSandboxConfig({allowWebEgress: true})` makes the real
// Agent SDK sandbox hide `GH_TOKEN` from a sandboxed command; with it OFF the very same environment lets the command see it.
// That is both the cause of the user's report (gh prints "run gh auth login") and the truthful remedy ("turn Agent web access
// off and start a new conversation"). The unit tests prove the CONFIG; this proves the BEHAVIOUR of the pinned SDK, which
// answers whether a recent SDK bump (the 2026-11-04 pin move) changed `credentials.envVars` semantics: if it had, the
// non-entitled arm would stop showing the decoy or the entitled arm would start showing it, and this file would red.
//
// Same ground as sandbox-credential-deny-runtime.test.ts (real SDK query(), real bubblewrap, a scripted API stand-in, decoy
// credential only), with the two arms differing in EXACTLY ONE input: `allowWebEgress`. Same env, same decoy, same shim, same
// command: `echo START; printenv GH_TOKEN; echo END`. Both arms must prove the shell ran (both sentinels present) before the
// value between them means anything, so an empty value cannot pass on a sandbox that never started.
//
// Skips locally without a usable bubblewrap + socat; FAILS where C4_BWRAP_REQUIRED is set, and fails if the suite is runnable
// but the probe never ran (a loud skip, never a silent one).

import { afterAll, beforeAll, describe, expect, it, vi } from "vitest";
import { spawnSync } from "node:child_process";
import { mkdirSync, mkdtempSync, readFileSync, realpathSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

import { query } from "@anthropic-ai/claude-agent-sdk";

import { buildAgentSandboxConfig } from "@/server/agent-runner-sandbox-config";
import { startAnthropicStub, type AnthropicStub } from "./helpers/anthropic-stub";
import { pointCliAtStub, scrubAmbientCliEnv } from "./helpers/hermetic-cli-env";

const APP_ROOT = join(dirname(fileURLToPath(import.meta.url)), "..");
const BWRAP_SHIM = join(APP_ROOT, "infra", "bwrap-shim", "bwrap");
const BWRAP_BPF = join(APP_ROOT, "infra", "bwrap-userns-clone3-deny.bpf");
const SDK_VERSION = (
  JSON.parse(readFileSync(join(APP_ROOT, "node_modules", "@anthropic-ai", "claude-agent-sdk", "package.json"), "utf8")) as { version: string }
).version;
const savedPath = process.env.PATH;

// A per-run decoy: nothing here is a real credential and nothing is keyed to a canonical value.
const RND = Math.random().toString(36).slice(2, 10);
const GH_DECOY = `decoy-gh-token-${RND}`;
const API_DECOY = `decoy-api-key-${RND}`;
const COMMAND = "echo START; printenv GH_TOKEN; echo END";

const BWRAP_OK =
  process.platform === "linux" &&
  spawnSync("bwrap", ["--unshare-user", "--unshare-pid", "--ro-bind", "/", "/", "--", "true"], { stdio: "ignore", timeout: 15_000 }).status === 0;
const SOCAT_OK = process.platform === "linux" && spawnSync("sh", ["-c", "command -v socat"], { stdio: "ignore" }).status === 0;
const SANDBOX_OK = BWRAP_OK && SOCAT_OK;
if (process.platform === "linux" && !SANDBOX_OK && process.env.C4_BWRAP_REQUIRED) {
  throw new Error(
    `C4_BWRAP_REQUIRED is set but the sandbox cannot run here (bwrap usable: ${BWRAP_OK}, socat on PATH: ${SOCAT_OK}). ` +
      "apt-get install bubblewrap socat && sysctl -w kernel.apparmor_restrict_unprivileged_userns=0 (Ubuntu)",
  );
}
if (!SANDBOX_OK) {
  // Loud, never silent: a skipped behavioural probe is a gap in the diagnosis, and CI annotations make it visible.
  console.warn(`::warning::agent-sandbox-credential-deny-behavioural SKIPPED (bwrap usable: ${BWRAP_OK}, socat on PATH: ${SOCAT_OK}); the GH_TOKEN deny was NOT observed behaviourally on this runner`);
}

interface Seen {
  /** Both sentinels were printed: the sandboxed shell actually ran the whole command. */
  ran: boolean;
  /** What `printenv GH_TOKEN` printed between the sentinels (empty when the variable is absent). */
  value: string;
}

let probeRuns = 0;

describe.skipIf(!SANDBOX_OK)("GH_TOKEN as seen from inside the real sandbox, Agent web access off vs on (#12469 T9b)", () => {
  let stub: AnthropicStub | undefined;
  let root: string;
  let own: string;
  let home: string;
  let shimDir: string;

  beforeAll(async () => {
    root = realpathSync(mkdtempSync(join(tmpdir(), "sbx-gh-deny-")));
    own = join(root, "00000000-0000-0000-0000-000000000001");
    mkdirSync(own);
    home = realpathSync(mkdtempSync(join(tmpdir(), "sbx-gh-deny-home-")));
    shimDir = realpathSync(mkdtempSync(join(tmpdir(), "sbx-gh-deny-shim-")));
    writeFileSync(join(shimDir, "bwrap"), `#!/usr/bin/env bash\nexec ${JSON.stringify(BWRAP_SHIM)} "$@"\n`, { mode: 0o755 });
    stub = await startAnthropicStub(COMMAND);
    scrubAmbientCliEnv();
    pointCliAtStub(stub.port, home, API_DECOY);
    vi.stubEnv("WORKSPACES_ROOT", root);
    vi.stubEnv("C4_RENDER_STAGING_ROOT", `${root}-c4-staging`);
    vi.stubEnv("SOLEUR_BWRAP_REAL", "/usr/bin/bwrap");
    vi.stubEnv("SOLEUR_BWRAP_SECCOMP_BPF", BWRAP_BPF);
    vi.stubEnv("PATH", `${shimDir}:${savedPath ?? "/usr/bin:/bin"}`);
    // The production shape: the minted token lives in the CLI process env, and the sandbox config decides what a sandboxed
    // command may see of it. Identical for both arms.
    vi.stubEnv("GH_TOKEN", GH_DECOY);
  });

  afterAll(async () => {
    vi.unstubAllEnvs();
    await stub?.close();
    for (const dir of [root, root && `${root}-c4-staging`, home, shimDir]) {
      if (!dir) continue;
      try {
        rmSync(dir, { recursive: true, force: true, maxRetries: 10, retryDelay: 300 });
      } catch {
        /* scratch space */
      }
    }
    // Loud skip: the suite was runnable but the probe never executed.
    if (probeRuns === 0) throw new Error("agent-sandbox-credential-deny-behavioural: the sandbox is usable but no probe ran");
    console.log(`GH_TOKEN_DENY_PROBE sdk=${SDK_VERSION} runs=${probeRuns}`);
  });

  async function observe(allowWebEgress: boolean): Promise<Seen> {
    probeRuns += 1;
    const sandbox = buildAgentSandboxConfig(own, { allowWebEgress });
    let flat = "";
    const controller = new AbortController();
    try {
      for await (const msg of query({
        prompt: "probe",
        options: {
          abortController: controller,
          model: "claude-haiku-5-5",
          maxTurns: 3,
          permissionMode: "default",
          cwd: own,
          allowedTools: ["Bash"],
          settingSources: [],
          sandbox: sandbox as never,
          canUseTool: async (_name: string, input: unknown) => ({ behavior: "allow", updatedInput: input }),
        } as never,
      })) {
        if (msg.type === "user") flat += JSON.stringify((msg as { message?: { content?: unknown } }).message?.content ?? "");
      }
    } finally {
      controller.abort();
    }
    // The tool result is JSON-encoded, so newlines arrive as the two characters `\n`.
    const m = /START\\n([\s\S]*?)END/.exec(flat);
    return { ran: m !== null, value: (m?.[1] ?? "").replace(/\\n/g, "").trim() };
  }

  it("the SAME environment shows the decoy with Agent web access OFF and nothing with it ON", async () => {
    const off = await observe(false);
    const on = await observe(true);
    // Premises first: the sandboxed shell completed in BOTH arms, so an empty value cannot be a sandbox that never started.
    expect(off.ran, "the OFF arm never completed (no START/END sentinels)").toBe(true);
    expect(on.ran, "the ON arm never completed (no START/END sentinels)").toBe(true);
    // The positive control: without the deny the scan DOES find the decoy, so an empty ON arm is a real absence.
    expect(off.value).toBe(GH_DECOY);
    // The treatment: with Agent web access on, the credential is not visible to a sandboxed command.
    expect(on.value).toBe("");
    expect(on.value).not.toContain(GH_DECOY);
    console.log(`GH_TOKEN_DENY_RESULT sdk=${SDK_VERSION} off_sees_decoy=${off.value === GH_DECOY} on_sees_decoy=${on.value === GH_DECOY}`);
  }, 180_000);
});
