// pencil-adapter-roundtrip.mjs — shared driver that runs the INSTALLED adapter
// copy over real MCP stdio. The stub integration test points it at
// fixtures/pencil-stub-repl.mjs; engine-contract-probe.sh points it at the
// real `pen` binary. Same driver on both sides keeps the stub honest.
//
// Credential: `connectAdapter({ keys })` sets EXACTLY the key names given (the
// adapter accepts PEN_CLI_KEY, with PENCIL_CLI_KEY as the deprecated fallback; an
// empty string is allowed and means "set but unset-equivalent"). The default is
// `{ PEN_CLI_KEY: "stub-key" }`. A live-engine caller passes its resolved key
// explicitly; there is no stub default against a real engine.
// Crash simulation: `killAndWait(pid)` SIGKILLs and polls `kill(pid, 0)` until ESRCH
// instead of sleeping a fixed time. `stubPid(outFile, tag)` reads the stub's pid file.

import { spawnSync } from "node:child_process";
import { readFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import { sideFile, taggedStub } from "./stub-tag.mjs";

export { sideFile, taggedStub };

const HERE = dirname(fileURLToPath(import.meta.url));
export const SCRIPTS_DIR = resolve(HERE, "../../skills/pencil-setup/scripts");

/** Install the adapter copy via copy_adapter.sh (runs `npm ci`). Throws on failure. */
export function installAdapter(installDir) {
  // npm ci runs here: it must not inherit the credential, under either name
  const { PEN_CLI_KEY: _k1, PENCIL_CLI_KEY: _k2, ...inherited } = process.env;
  const r = spawnSync("bash", [join(SCRIPTS_DIR, "copy_adapter.sh")], {
    env: { ...inherited, PENCIL_ADAPTER_INSTALL_DIR: installDir },
    encoding: "utf8",
  });
  if (r.status !== 0) {
    throw new Error(
      `copy_adapter.sh failed (rc=${r.status}): ${r.stderr || r.stdout}`.slice(0, 2000)
    );
  }
  return installDir;
}

/**
 * The environment handed to the adapter process: PATH/HOME/TMPDIR, PENCIL_BINARY, exactly the
 * credential names in `keys`, then `extraEnv`. `key` is the legacy single-value form (PEN_CLI_KEY).
 */
export function buildAdapterEnv({ binary, keys, key, extraEnv = {} }) {
  const credential = keys ?? { PEN_CLI_KEY: key ?? "stub-key" };
  return {
    PATH: process.env.PATH ?? "",
    HOME: process.env.HOME ?? "",
    TMPDIR: process.env.TMPDIR ?? "",
    ...credential,
    PENCIL_BINARY: binary,
    ...extraEnv,
  };
}

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const alive = (pid) => {
  try {
    process.kill(pid, 0);
    return true;
  } catch (e) {
    return e.code !== "ESRCH";
  }
};

/** SIGKILL `pid` and wait until it is gone (polls kill(pid,0) every 20 ms, 5 s ceiling). Returns once ESRCH. */
export async function killAndWait(pid, { signal = "SIGKILL", intervalMs = 20, ceilingMs = 5000 } = {}) {
  try {
    process.kill(pid, signal);
  } catch (e) {
    if (e.code === "ESRCH") return;
    throw e;
  }
  const t0 = Date.now();
  while (alive(pid)) {
    if (Date.now() - t0 > ceilingMs) throw new Error(`process ${pid} still alive ${ceilingMs} ms after ${signal}`);
    await sleep(intervalMs);
  }
}

/** The stub's pid for `outFile` (and `tag`, when the session has one). */
export const stubPid = (outFile, tag = "") => Number(readFileSync(sideFile(outFile, "pid", tag), "utf8"));

/**
 * Connect an MCP client to the installed adapter.
 * @returns {{ call: (name: string, args?: object) => Promise<{text: string, isError: boolean}>,
 *             stderr: () => string, close: () => Promise<void> }}
 */
export async function connectAdapter({ installDir, binary, keys, key, extraEnv = {}, cwd, nodeBin }) {
  const sdk = (rel) => import(pathToFileURL(join(installDir, "node_modules/@modelcontextprotocol/sdk/dist/esm", rel)).href);
  const { Client } = await sdk("client/index.js");
  const { StdioClientTransport } = await sdk("client/stdio.js");

  const env = buildAdapterEnv({ binary, keys, key, extraEnv });
  const transport = new StdioClientTransport({
    command: nodeBin || process.env.NODE_BIN || "node",
    ...(cwd ? { cwd } : {}),
    args: [join(installDir, "pencil-mcp-adapter.mjs")],
    env,
    stderr: "pipe",
  });
  let errText = "";
  transport.stderr?.on("data", (c) => {
    errText += c.toString();
  });
  const client = new Client({ name: "pencil-roundtrip", version: "0.0.0" });
  await client.connect(transport);
  return {
    async call(name, args = {}) {
      const res = await client.callTool({ name, arguments: args });
      const text = (res.content ?? [])
        .filter((c) => c.type === "text")
        .map((c) => c.text)
        .join("\n");
      return { text, isError: Boolean(res.isError) };
    },
    async listTools() {
      return (await client.listTools()).tools;
    },
    stderr: () => errText,
    close: () => client.close(),
  };
}
