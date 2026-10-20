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

// Source-level pins for the wiring review found missing. Comment-stripped so the prose that explains a
// gate cannot satisfy the assertion that guards it; anchored on call forms, ordered by index.
const code = (p: string) =>
  read(p)
    .replace(/\/\*[\s\S]*?\*\//g, "")
    .replace(/^\s*\/\/.*$/gm, "")
    .replace(/(^|[^:"'`])\/\/.*$/gm, "$1");
const idx = (s: string, needle: string, from = 0) => s.indexOf(needle, from);

describe("quiet-window gate ordering and coverage (review P2)", () => {
  it("sendUserMessage refuses BEFORE its own conversation read, message INSERT and status flip", () => {
    const src = code("server/agent-runner.ts");
    const start = idx(src, "async function sendUserMessageInner(");
    expect(start).toBeGreaterThan(0);
    const gate = idx(src, "await newAgentSessionsRefused()", start);
    const convRead = idx(src, 'getFreshTenantClient(userId)', start);
    const insert = idx(src, '.from("messages")', start);
    expect(gate).toBeGreaterThan(start);
    expect(gate).toBeLessThan(convRead);
    expect(gate).toBeLessThan(insert);
  });

  it("the three agent entry points are in-flight tracked with a finally release", () => {
    for (const [file, name] of [
      ["server/agent-runner.ts", "startAgentSessionInner"],
      ["server/agent-runner.ts", "sendUserMessageInner"],
      ["server/cc-dispatcher.ts", "dispatchSoleurGoInner"],
    ] as const) {
      const src = code(file);
      const call = idx(src, `await ${name}(`);
      expect(call, `${file} must call ${name}`).toBeGreaterThan(0);
      const before = src.slice(Math.max(0, call - 200), call);
      const after = src.slice(call, call + 200);
      expect(before).toMatch(/trackSessionStart\(\)/);
      expect(after).toMatch(/finally\s*\{\s*releaseStart\(\)/);
    }
  });

  it("ws-handler never supersede-aborts a running session while paused: the bare abort is called only inside the helper", () => {
    const src = code("server/ws-handler.ts");
    const bare = src.match(/abortActiveSession\(userId, session\)/g) ?? [];
    const guarded = src.match(/await abortActiveSessionUnlessPaused\(userId, session\)/g) ?? [];
    expect(bare).toHaveLength(1); // inside abortActiveSessionUnlessPaused itself
    expect(guarded).toHaveLength(2); // start_session and resume_session
  });

  it("a first message is refused BEFORE createConversation (no empty active row, no held slot)", () => {
    const src = code("server/ws-handler.ts");
    const gate = idx(src, 'op: "refuse-first-message"');
    const create = idx(src, "await createConversation(");
    expect(gate).toBeGreaterThan(0);
    expect(gate).toBeLessThan(create);
  });

  it("repo/setup and repo/create refuse after auth and BEFORE any resolution, body read or clone", () => {
    const setup = code("app/api/repo/setup/route.ts");
    expect(idx(setup, "await quietWindowRefusal(")).toBeGreaterThan(0);
    expect(idx(setup, "await quietWindowRefusal(")).toBeLessThan(idx(setup, "resolveActiveWorkspace("));
    const create = code("app/api/repo/create/route.ts");
    expect(idx(create, "await quietWindowRefusal(")).toBeGreaterThan(0);
    expect(idx(create, "await quietWindowRefusal(")).toBeLessThan(idx(create, "request.json()"));
  });

  it("the connect-repo copy map carries the quiet-window code and the reconnect hook does not report it", () => {
    expect(read("components/connect-repo/failed-state.tsx")).toMatch(/\[QUIET_WINDOW_CODE\]:/);
    expect(code("components/repo/use-reconnect.ts")).toMatch(/refusal\?\.code === QUIET_WINDOW_CODE/);
  });

  it("the reporter is wired to the right count sources (property pairing) and cleared inside the SIGTERM handler", () => {
    const src = code("server/index.ts");
    // A swap of the two sources still matches an unpaired regex; pair each property with its source.
    expect(src).toMatch(/ccQueries:\s*activeCcQueryCount\(\)/);
    expect(src).toMatch(/legacySessions:\s*activeLegacySessionCount\(\)/);
    const sigterm = idx(src, 'process.on("SIGTERM"');
    expect(sigterm).toBeGreaterThan(0);
    expect(idx(src, "clearInterval(quietWindowReporterTimer)")).toBeGreaterThan(sigterm);
  });

  it("every quiet-window breadcrumb carries a hashed user id only: no raw user id, no conversation id", () => {
    const files = [
      "server/agent-runner.ts",
      "server/cc-dispatcher.ts",
      "server/auto-sync-trigger.ts",
      "server/quiet-window-http.ts",
      "server/ws-handler.ts",
    ];
    let seen = 0;
    for (const f of files) {
      const src = code(f);
      for (const m of src.matchAll(/feature:\s*"quiet-window"[\s\S]{0,260}?\}/g)) {
        seen += 1;
        const payload = m[0].replace(/hashUserId(?:Value)?\([^)]*\)/g, "");
        expect(payload, `${f}: ${payload}`).not.toMatch(/\buserId\b(?!Hash)/);
        expect(payload, `${f}: ${payload}`).not.toMatch(/\bconversationId\b/);
      }
    }
    expect(seen).toBeGreaterThanOrEqual(7); // runner x2, cc, auto-sync, http helper, ws x2 (floor, never equality)
  });
});

