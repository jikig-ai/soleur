import { describe, it, expect } from "vitest";
import { readFileSync } from "node:fs";
import { join } from "node:path";

// #8211 — the reporter must be started at boot and cleared at shutdown, and
// the flag must be wired with its env mirror. A wiring regression here would
// leave the owner with no per-host read and no mirror, silently.
const root = join(__dirname, "..");
const read = (p: string) => readFileSync(join(root, p), "utf8");

describe("quiet-window wiring", () => {
  it("server/index.ts starts the reporter with both count sources and clears it on shutdown", () => {
    const src = read("server/index.ts");
    expect(src).toMatch(/startQuietWindowReporter\(\{/);
    expect(src).toMatch(/activeCcQueryCount\(\)/);
    expect(src).toMatch(/activeLegacySessionCount\(\)/);
    expect(src).toMatch(/clearInterval\(quietWindowReporterTimer\)/);
  });

  it("the flag is registered with the FLAG_NEW_SESSIONS_PAUSED mirror, default 0 in .env.example", () => {
    expect(read("lib/feature-flags/server.ts")).toMatch(
      /"new-sessions-paused":\s*"FLAG_NEW_SESSIONS_PAUSED"/,
    );
    expect(read(".env.example")).toMatch(/^FLAG_NEW_SESSIONS_PAUSED=0$/m);
  });

  it("the reporter payload and the gate are the only quiet-window emitters (no user-id field is ever passed to the reporter log)", () => {
    const src = read("server/quiet-window.ts");
    // The structured payload keys are a closed set of four.
    expect(src).toMatch(
      /agentSessionsLive:[\s\S]*ccQueries:[\s\S]*legacySessions:[\s\S]*newSessionsPaused:/,
    );
    expect(src).not.toMatch(/userId|conversationId/);
  });
});
