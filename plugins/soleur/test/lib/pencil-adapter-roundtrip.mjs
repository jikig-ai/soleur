// pencil-adapter-roundtrip.mjs — shared driver that runs the INSTALLED adapter
// copy over real MCP stdio. The stub integration test points it at
// fixtures/pencil-stub-repl.mjs; engine-contract-probe.sh points it at the
// real `pencil` binary. Same driver on both sides keeps the stub honest.

import { spawnSync } from "node:child_process";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const HERE = dirname(fileURLToPath(import.meta.url));
export const SCRIPTS_DIR = resolve(HERE, "../../skills/pencil-setup/scripts");

/** Install the adapter copy via copy_adapter.sh (runs `npm ci`). Throws on failure. */
export function installAdapter(installDir) {
  // npm ci runs here: it must not inherit the credential
  const { PENCIL_CLI_KEY: _credential, ...inherited } = process.env;
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
 * Connect an MCP client to the installed adapter.
 * @returns {{ call: (name: string, args?: object) => Promise<{text: string, isError: boolean}>,
 *             stderr: () => string, close: () => Promise<void> }}
 */
export async function connectAdapter({ installDir, binary, key = "stub-key", extraEnv = {}, cwd, nodeBin }) {
  const sdk = (rel) => import(pathToFileURL(join(installDir, "node_modules/@modelcontextprotocol/sdk/dist/esm", rel)).href);
  const { Client } = await sdk("client/index.js");
  const { StdioClientTransport } = await sdk("client/stdio.js");

  const env = {
    PATH: process.env.PATH ?? "",
    HOME: process.env.HOME ?? "",
    TMPDIR: process.env.TMPDIR ?? "",
    PENCIL_CLI_KEY: key,
    PENCIL_BINARY: binary,
    ...extraEnv,
  };
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
