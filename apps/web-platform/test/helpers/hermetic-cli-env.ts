// Tests that start the REAL Claude CLI (through the Agent SDK) must not inherit a
// developer's or a CI runner's ambient routing, provider or auth configuration:
// an exported `ANTHROPIC_AUTH_TOKEN`, a Bedrock/Vertex switch, a proxy or a
// `CLAUDE_CONFIG_DIR` would send the run to a real provider, with real settings
// and hooks, or through a proxy that sees the Authorization header.
//
// This is a PREFIX denylist rather than a list of names: it clears every variable
// under the prefixes the CLI and the providers read, so a variable the bundled
// binary starts reading next release is already covered. It does not clear
// generic Node/TLS variables (NODE_OPTIONS, SSL_CERT_FILE, ...): a hermeticity
// gap, not a credential path.

import { vi } from "vitest";

const AMBIENT_CLI_ENV = /^(ANTHROPIC|CLAUDE|AWS|GOOGLE|AZURE|OPENAI)_|^CLAUDECODE$|_proxy$/i;

/** Unset every ambient CLI/provider/proxy variable for this test file (undone by `vi.unstubAllEnvs`). */
export function scrubAmbientCliEnv(): string[] {
  const scrubbed: string[] = [];
  for (const name of Object.keys(process.env)) {
    if (AMBIENT_CLI_ENV.test(name)) {
      vi.stubEnv(name, undefined);
      scrubbed.push(name);
    }
  }
  return scrubbed;
}

/** Point the CLI at a local stand-in with a decoy credential, in an isolated HOME. */
export function pointCliAtStub(port: number, home: string, decoyKey: string): void {
  vi.stubEnv("HOME", home);
  vi.stubEnv("ANTHROPIC_BASE_URL", `http://127.0.0.1:${port}`);
  vi.stubEnv("ANTHROPIC_API_KEY", decoyKey);
  vi.stubEnv("NO_PROXY", "127.0.0.1,localhost");
  vi.stubEnv("no_proxy", "127.0.0.1,localhost");
  vi.stubEnv("DISABLE_TELEMETRY", "1");
  vi.stubEnv("DISABLE_AUTOUPDATER", "1");
  vi.stubEnv("CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC", "1");
}
