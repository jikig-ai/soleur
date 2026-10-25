// Agent auth-failure diagnostic: context derivation from the REAL option builders, the payload builder, the probe
// (latch, debounce, process-wide cap, init-derived cli_key_source, authMode normalisation), the REAL authMode resolver
// against a fake PersistenceClient, and the no-unhandled-rejection property. Plan Phase 1 items 2 and 6; Guard 2 rows
// 7, 8a-8c, 10. `@/server/observability` is a partial mock with a spy for reportSilentFallback (the real-path
// counterpart is agent-auth-failure-sentry-path.test.ts); the tap and the runner wiring have their own files.
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

const h = vi.hoisted(() => ({
  report: vi.fn(),
  warnFallback: vi.fn(),
  log: { info: vi.fn(), warn: vi.fn(), error: vi.fn(), debug: vi.fn() },
  freshTenant: vi.fn(),
}));
vi.mock("@/server/observability", () => ({
  reportSilentFallback: h.report,
  warnSilentFallback: h.warnFallback,
  mirrorWarnWithDebounce: vi.fn(),
  mirrorWithDebounce: vi.fn(),
}));
vi.mock("@/server/logger", () => ({ default: h.log, createChildLogger: vi.fn(() => h.log) }));
vi.mock("@/lib/supabase/tenant", () => ({ getFreshTenantClient: h.freshTenant }));

import { buildAgentQueryOptions } from "@/server/agent-runner-query-options";
import { resolveWorkspaceMode } from "@/server/workspace-mode";
import {
  AGENT_AUTH_DEBOUNCE_MS,
  AGENT_AUTH_GLOBAL_CAP,
  AGENT_AUTH_MODE_TIMEOUT_MS,
  __resetAgentAuthDedupeForTests,
  agentAuthSuppressedCount,
  buildAgentAuthPayload,
  createAgentAuthFailureProbe,
  deriveAgentAuthContext,
  normalizeAuthMode,
} from "@/server/agent-auth-failure";
import { makeAuthModeResolver } from "@/server/agent-auth-mode";

const APP_ROOT = join(__dirname, "..");
const SEP = "\u00B7";

// Fake secrets are split by concatenation so a push-protection scanner never sees a whole token literal.
const FAKE_KEY = "sk-ant-" + "api03-" + "FAKEFAKEFAKEFAKE";
const FAKE_OAUTH = "sk-ant-" + "oat01-" + "FAKEFAKEFAKEFAKE";

const API_CRED = { value: FAKE_KEY, scheme: "api_key" as const };
const OAUTH_CRED = { value: FAKE_OAUTH, scheme: "oauth_token" as const };
const baseArgs = {
  workspacePath: "/tmp/test-workspace",
  pluginPath: "/tmp/test-workspace/plugins/soleur",
  mode: resolveWorkspaceMode("command_center"),
  credential: API_CRED,
  serviceTokens: {} as Record<string, string>,
  systemPrompt: "x",
  canUseTool: (async () => ({ behavior: "allow" as const, updatedInput: {} })) as never,
};
const build = (over: Record<string, unknown> = {}) => buildAgentQueryOptions({ ...baseArgs, ...over } as never) as Record<string, any>;

const failure = () => ({
  type: "assistant",
  message: { model: "<synthetic>", content: [{ type: "text", text: `Not logged in ${SEP} Please run /login` }] },
  error: "authentication_failed",
  is_api_error_message: true,
});
const init = (apiKeySource: unknown) => ({ type: "system", subtype: "init", apiKeySource });
const resultOk = () => ({ type: "result", subtype: "success", is_error: false, result: "" });

const emits = () => h.report.mock.calls.filter((c) => (c[1] as { feature?: string })?.feature === "agent-auth");
const tagsOf = (i = 0) => (emits()[i][1] as { tags: Record<string, string> }).tags;

const TEN_KEYS = [
  "runner",
  "credential_scheme",
  "auth_env_present",
  "auth_mode",
  "cli_key_source",
  "seccomp_artifact",
  "has_egress",
  "sandbox",
  "outer_wrap",
  "match_kind",
].sort();

let clock = 1_000_000;
const now = () => clock;
let n = 0;
const mk = (over: Record<string, unknown> = {}) =>
  createAgentAuthFailureProbe({
    runner: "legacy",
    credentialScheme: "api_key",
    dedupeToken: `user-${++n}`,
    resolveAuthMode: async () => "managed",
    now,
    ...over,
  } as never);

beforeEach(() => {
  vi.clearAllMocks();
  __resetAgentAuthDedupeForTests();
  clock = 1_000_000;
  n = 0;
});
afterEach(() => {
  vi.useRealTimers();
  vi.unstubAllEnvs();
});

describe("deriveAgentAuthContext over the real buildAgentQueryOptions output", () => {
  it("api_key, no egress, flag off: base artifact, env present, sandbox on, no outer wrap", () => {
    expect(deriveAgentAuthContext("legacy", "api_key", build())).toEqual({
      runner: "legacy",
      credential_scheme: "api_key",
      auth_env_present: "true",
      seccomp_artifact: "base",
      has_egress: "false",
      sandbox: "on",
      outer_wrap: "false",
    });
  });

  it("oauth_token reads ONLY CLAUDE_CODE_OAUTH_TOKEN; the wrong scheme against the same options reports absent", () => {
    const opts = build({ credential: OAUTH_CRED });
    expect(deriveAgentAuthContext("cc-soleur-go", "oauth_token", opts)).toMatchObject({ runner: "cc-soleur-go", auth_env_present: "true" });
    expect(deriveAgentAuthContext("cc-soleur-go", "api_key", opts).auth_env_present).toBe("false");
    expect(deriveAgentAuthContext("legacy", "oauth_token", build()).auth_env_present).toBe("false");
  });

  it("an empty or missing variable is absent; a non-empty one is present", () => {
    expect(deriveAgentAuthContext("legacy", "api_key", { env: { ANTHROPIC_API_KEY: "" } }).auth_env_present).toBe("false");
    expect(deriveAgentAuthContext("legacy", "api_key", { env: {} }).auth_env_present).toBe("false");
    expect(deriveAgentAuthContext("legacy", "api_key", { env: { ANTHROPIC_API_KEY: "x" } }).auth_env_present).toBe("true");
    expect(deriveAgentAuthContext("legacy", "api_key", { env: { ANTHROPIC_API_KEY: 42 } }).auth_env_present).toBe("false");
    expect(deriveAgentAuthContext("legacy", "api_key", {}).auth_env_present).toBe("unknown");
  });

  it("egress: a GitHub token or a web-egress handle is has_egress=true and the base artifact whatever the flag says", () => {
    const gh = deriveAgentAuthContext("cc-soleur-go", "api_key", build({ ghToken: "ghs_fake", sandboxUnixDeny: true }));
    expect(gh).toMatchObject({ has_egress: "true", seccomp_artifact: "base" });
    const web = deriveAgentAuthContext(
      "cc-soleur-go",
      "api_key",
      build({ webEgress: { workspaceId: "w", token: "t", port: 1 }, sandboxUnixDeny: true }),
    );
    expect(web).toMatchObject({ has_egress: "true", seccomp_artifact: "base" });
  });

  it("flag on with no egress selects unixdeny; flag off stays base", () => {
    expect(deriveAgentAuthContext("legacy", "api_key", build({ sandboxUnixDeny: true })).seccomp_artifact).toBe("unixdeny");
    expect(deriveAgentAuthContext("legacy", "api_key", build({ sandboxUnixDeny: false })).seccomp_artifact).toBe("base");
  });

  it("sandbox absent or disabled is off; a spawn hook is the outer wrap", () => {
    const opts = build();
    expect(deriveAgentAuthContext("legacy", "api_key", { ...opts, sandbox: undefined }).sandbox).toBe("off");
    expect(deriveAgentAuthContext("legacy", "api_key", { ...opts, sandbox: { enabled: false } }).sandbox).toBe("off");
    expect(deriveAgentAuthContext("legacy", "api_key", { ...opts, spawnClaudeCodeProcess: () => undefined }).outer_wrap).toBe("true");
    expect(deriveAgentAuthContext("legacy", "api_key", opts).outer_wrap).toBe("false");
  });

  it("a builder that returned undefined (or anything not an object) leaves every options-derived field unknown and never throws", () => {
    for (const bad of [undefined, null, 42, "x"]) {
      expect(deriveAgentAuthContext("cc-soleur-go", "oauth_token", bad)).toEqual({
        runner: "cc-soleur-go",
        credential_scheme: "oauth_token",
        auth_env_present: "unknown",
        seccomp_artifact: "unknown",
        has_egress: "unknown",
        sandbox: "unknown",
        outer_wrap: "unknown",
      });
    }
  });

  it("a scheme outside the closed set is unknown; a hostile options object never throws", () => {
    expect(deriveAgentAuthContext("legacy", "something-else" as never, build()).credential_scheme).toBe("unknown");
    const hostile = new Proxy({}, { get: () => { throw new Error("boom"); } });
    expect(() => deriveAgentAuthContext("legacy", "api_key", hostile)).not.toThrow();
  });

  it("has_egress and seccomp_artifact come from the single predicate and the recorded posture, not a fourth spelling", () => {
    const src = readFileSync(join(APP_ROOT, "server/agent-auth-failure.ts"), "utf8");
    expect(src).toContain("usesUnixDenyArtifact(");
    expect(src).toContain("sandboxPostureOf(");
    expect(src).not.toMatch(/unixDenyFlag\s*===\s*true/);
    expect(src).not.toMatch(/hasEgress\s*===\s*false/);
  });

  it("the derived context never carries the credential value", () => {
    const ctx = deriveAgentAuthContext("legacy", "api_key", build());
    expect(JSON.stringify(ctx)).not.toContain(FAKE_KEY);
    expect(JSON.stringify(ctx)).not.toContain("FAKEFAKE");
  });
});

describe("buildAgentAuthPayload and normalizeAuthMode", () => {
  const ctx = deriveAgentAuthContext("legacy", "api_key", build());

  it("is exactly the ten closed-enum string keys", () => {
    const payload = buildAgentAuthPayload({ context: ctx, authMode: "managed", cliKeySource: "none", matchKind: "not_logged_in" });
    expect(Object.keys(payload).sort()).toEqual(TEN_KEYS);
    for (const v of Object.values(payload)) expect(typeof v).toBe("string");
    expect(payload).toMatchObject({ auth_mode: "managed", cli_key_source: "none", match_kind: "not_logged_in" });
  });

  it("a cli_key_source outside the closed ApiKeySource list (path- or key-shaped) becomes unknown", () => {
    for (const bad of ["/workspaces/abc/.claude/key", FAKE_KEY, "", undefined, 7]) {
      const payload = buildAgentAuthPayload({ context: ctx, authMode: "managed", cliKeySource: bad as never, matchKind: "structured" });
      expect(payload.cli_key_source, String(bad)).toBe("unknown");
    }
    for (const ok of ["ANTHROPIC_API_KEY", "apiKeyHelper", "/login managed key", "none", "user", "project", "org", "temporary", "oauth"]) {
      expect(buildAgentAuthPayload({ context: ctx, authMode: "managed", cliKeySource: ok, matchKind: "structured" }).cli_key_source).toBe(ok);
    }
  });

  it("normalizeAuthMode: managed and api-key pass; null is unbound; everything else is unknown (never echoed)", () => {
    expect(normalizeAuthMode("managed")).toBe("managed");
    expect(normalizeAuthMode("api-key")).toBe("api-key");
    expect(normalizeAuthMode(null)).toBe("unbound");
    for (const bad of ["codex", "/workspaces/11111111-aaaa/secret", FAKE_KEY, "", undefined, 3, {}]) {
      expect(normalizeAuthMode(bad), String(bad)).toBe("unknown");
    }
  });
});

describe("probe: latch, debounce, cap", () => {
  it("emits exactly once per probe for repeated failures, and the emit carries the ten keys", async () => {
    const probe = mk();
    probe.bindOptions(build());
    await probe.observe(failure());
    await probe.observe(failure());
    expect(emits()).toHaveLength(1);
    expect(h.report.mock.calls[0][0]).toBeNull();
    expect(Object.keys(tagsOf()).filter((k) => k !== "feature" && k !== "op").sort()).toEqual(TEN_KEYS);
    expect(tagsOf()).toMatchObject({ runner: "legacy", credential_scheme: "api_key", auth_env_present: "true", auth_mode: "managed", match_kind: "not_logged_in" });
  });

  it("a non-matching stream emits nothing", async () => {
    const probe = mk();
    for (const m of [init("none"), { type: "assistant", message: { content: [{ type: "text", text: "hello" }] } }, resultOk(), null, 42]) {
      await probe.observe(m);
    }
    expect(emits()).toHaveLength(0);
  });

  it("the latch resets on every result: a warm Query re-emits after the window and not before it", async () => {
    const probe = mk();
    probe.bindOptions(build());
    await probe.observe(failure());
    await probe.observe(resultOk());
    clock += AGENT_AUTH_DEBOUNCE_MS - 1;
    await probe.observe(failure());
    expect(emits()).toHaveLength(1);
    await probe.observe(resultOk());
    clock += 2;
    await probe.observe(failure());
    expect(emits()).toHaveLength(2);
  });

  it("8a: with the latch alone (no result boundary) a second failure in the same probe never reaches the debounce", async () => {
    const probe = mk();
    await probe.observe(failure());
    clock += AGENT_AUTH_DEBOUNCE_MS * 3;
    await probe.observe(failure());
    expect(emits()).toHaveLength(1);
  });

  it("8b: a second probe with the same user and tuple inside the window emits nothing; after the window it emits; a flipped scheme or another user emits", async () => {
    const opts = build();
    const a = mk({ dedupeToken: "same-user" });
    a.bindOptions(opts);
    await a.observe(failure());
    const b = mk({ dedupeToken: "same-user" });
    b.bindOptions(opts);
    await b.observe(failure());
    expect(emits()).toHaveLength(1);

    const flipped = mk({ dedupeToken: "same-user", credentialScheme: "oauth_token" });
    flipped.bindOptions(build({ credential: OAUTH_CRED }));
    await flipped.observe(failure());
    expect(emits()).toHaveLength(2);

    const other = mk({ dedupeToken: "other-user" });
    other.bindOptions(opts);
    await other.observe(failure());
    expect(emits()).toHaveLength(3);

    clock += AGENT_AUTH_DEBOUNCE_MS + 1;
    const later = mk({ dedupeToken: "same-user" });
    later.bindOptions(opts);
    await later.observe(failure());
    expect(emits()).toHaveLength(4);
  });

  it("a different cli_key_source is a different tuple (init precedes the failure, so it is complete at claim time)", async () => {
    const a = mk({ dedupeToken: "u" });
    await a.observe(init("none"));
    await a.observe(failure());
    const b = mk({ dedupeToken: "u" });
    await b.observe(init("ANTHROPIC_API_KEY"));
    await b.observe(failure());
    expect(emits()).toHaveLength(2);
  });

  it("8c: the process-wide cap lets ten distinct users through inside the window and suppresses the eleventh with no warn", async () => {
    expect(AGENT_AUTH_GLOBAL_CAP).toBe(10);
    for (let i = 0; i < 11; i++) {
      const p = mk({ dedupeToken: `flood-${i}` });
      await p.observe(failure());
    }
    expect(emits()).toHaveLength(10);
    expect(agentAuthSuppressedCount()).toBe(1);
    expect(h.log.warn).not.toHaveBeenCalled();
    // The window passes: the cap frees up.
    clock += AGENT_AUTH_DEBOUNCE_MS + 1;
    await mk({ dedupeToken: "flood-after" }).observe(failure());
    expect(emits()).toHaveLength(11);
  });

  it("a suppressed same-user repeat does not consume a process-wide slot", async () => {
    const opts = build();
    for (let i = 0; i < 30; i++) {
      const p = mk({ dedupeToken: "one-user" });
      p.bindOptions(opts);
      await p.observe(failure());
    }
    expect(emits()).toHaveLength(1);
    for (let i = 0; i < 9; i++) await mk({ dedupeToken: `fresh-${i}` }).observe(failure());
    expect(emits()).toHaveLength(10);
  });
});

describe("probe: cli_key_source from the init message", () => {
  const cases: Array<[string, unknown[], string]> = [
    ["none", [init("none")], "none"],
    ["ANTHROPIC_API_KEY", [init("ANTHROPIC_API_KEY")], "ANTHROPIC_API_KEY"],
    ["oauth", [init("oauth")], "oauth"],
    ["outside the closed list (path-shaped)", [init("/workspaces/abc/key")], "unknown"],
    ["not a string", [init({ nested: true })], "unknown"],
    ["no init at all", [], "unknown"],
  ];
  it.each(cases)("%s", async (_name, pre, want) => {
    const probe = mk();
    for (const m of pre) await probe.observe(m);
    await probe.observe(failure());
    expect(tagsOf().cli_key_source).toBe(want);
  });
});

describe("probe: authMode resolution", () => {
  const rows: Array<[string, () => Promise<string | null>, string]> = [
    ["managed", async () => "managed", "managed"],
    ["api-key", async () => "api-key", "api-key"],
    ["an unlisted engine mode", async () => "codex", "unknown"],
    ["a workspace-path-shaped string", async () => "/workspaces/11111111-2222/secret", "unknown"],
    ["a canary-shaped value", async () => FAKE_KEY, "unknown"],
    ["null (no engine-run row)", async () => null, "unbound"],
    ["a rejection", async () => { throw new Error("db down"); }, "unknown"],
  ];
  it.each(rows)("%s", async (_name, resolver, want) => {
    const probe = mk({ resolveAuthMode: resolver });
    await probe.observe(failure());
    expect(tagsOf().auth_mode).toBe(want);
    expect(JSON.stringify(h.report.mock.calls)).not.toContain(FAKE_KEY);
    expect(JSON.stringify(h.report.mock.calls)).not.toContain("/workspaces/11111111");
  });

  it("no resolver supplied is unknown", async () => {
    const probe = mk({ resolveAuthMode: undefined });
    await probe.observe(failure());
    expect(tagsOf().auth_mode).toBe("unknown");
  });

  it("a never-settling resolver times out at 1.5 s to unknown and the event is still emitted", async () => {
    expect(AGENT_AUTH_MODE_TIMEOUT_MS).toBe(1500);
    vi.useFakeTimers();
    const probe = mk({ resolveAuthMode: () => new Promise<string>(() => undefined) });
    const done = probe.observe(failure());
    await vi.advanceTimersByTimeAsync(1499);
    expect(emits()).toHaveLength(0);
    await vi.advanceTimersByTimeAsync(2);
    await done;
    expect(emits()).toHaveLength(1);
    expect(tagsOf().auth_mode).toBe("unknown");
  });

  it("no resolver call happens without a claimed match (non-matching messages, a latched repeat, a debounced second probe)", async () => {
    const resolver = vi.fn(async () => "managed");
    const a = mk({ dedupeToken: "u", resolveAuthMode: resolver });
    await a.observe(init("none"));
    await a.observe(resultOk());
    await a.observe({ type: "assistant", message: { content: [{ type: "text", text: "hi" }] } });
    expect(resolver).not.toHaveBeenCalled();
    await a.observe(failure());
    await a.observe(failure());
    expect(resolver).toHaveBeenCalledTimes(1);
    const b = mk({ dedupeToken: "u", resolveAuthMode: resolver });
    await b.observe(init("none"));
    await b.observe(failure());
    // b's tuple differs from a's only through cli_key_source (equal here), so the debounce holds and no lookup runs.
    expect(resolver).toHaveBeenCalledTimes(1);
  });

  it("the claim is taken BEFORE the lookup: a concurrent second probe observing during the lookup is already debounced", async () => {
    let release: (v: string) => void = () => undefined;
    const slow = vi.fn(() => new Promise<string>((res) => { release = res; }));
    const a = mk({ dedupeToken: "u", resolveAuthMode: slow });
    const pa = a.observe(failure());
    const b = mk({ dedupeToken: "u", resolveAuthMode: slow });
    await b.observe(failure());
    expect(slow).toHaveBeenCalledTimes(1);
    release("api-key");
    await pa;
    expect(emits()).toHaveLength(1);
    expect(tagsOf().auth_mode).toBe("api-key");
  });
});

describe("probe: failure isolation", () => {
  it("a failing emit releases the claim so a burned window cannot swallow the next event", async () => {
    h.report.mockImplementationOnce(() => {
      throw new Error("sink down");
    });
    await mk({ dedupeToken: "u" }).observe(failure());
    expect(emits()).toHaveLength(1); // the failed attempt
    await mk({ dedupeToken: "u" }).observe(failure());
    expect(emits()).toHaveLength(2); // retried: the claim was released
  });

  it("an internal throw is swallowed, observe resolves, and ONE constant warn per probe is logged with no payload", async () => {
    const probe = mk({
      dedupeToken: "ID-CANARY-user-0001",
      now: () => {
        throw new Error("clock exploded");
      },
    });
    await expect(probe.observe(failure())).resolves.toBeUndefined();
    await expect(probe.observe(failure())).resolves.toBeUndefined();
    expect(h.log.warn).toHaveBeenCalledTimes(1);
    const args = h.log.warn.mock.calls[0];
    expect(args).toHaveLength(1);
    expect(typeof args[0]).toBe("string");
    expect(emits()).toHaveLength(0);
  });

  it("no logger call (any level) ever carries the dedupe token, the key or the matched text", async () => {
    const probe = mk({ dedupeToken: "ID-CANARY-user-0002", now: () => { throw new Error(FAKE_KEY); } });
    probe.bindOptions(build());
    await probe.observe(failure());
    const all = JSON.stringify([h.log.info.mock.calls, h.log.warn.mock.calls, h.log.error.mock.calls, h.log.debug.mock.calls]);
    expect(all).not.toContain("ID-CANARY");
    expect(all).not.toContain("FAKEFAKE");
    expect(all).not.toContain("Please run /login");
  });

  it("bindOptions is the identity, derives eagerly, and retains no reference to the options or its env", async () => {
    const probe = mk();
    const opts = build();
    expect(probe.bindOptions(opts)).toBe(opts);
    // Eager: a later mutation of the live options does not change what the event reports.
    opts.env.ANTHROPIC_API_KEY = "";
    await probe.observe(failure());
    expect(tagsOf().auth_env_present).toBe("true");

    // Structural: nothing reachable through own properties of the probe is the options object or its env.
    const seen = new Set<unknown>();
    const stack: unknown[] = [probe];
    while (stack.length) {
      const cur = stack.pop();
      if (cur === null || typeof cur !== "object" || seen.has(cur)) continue;
      seen.add(cur);
      for (const v of Object.values(cur as Record<string, unknown>)) stack.push(v);
    }
    expect(seen.has(opts)).toBe(false);
    expect(seen.has(opts.env)).toBe(false);
  });

  it("a hostile options argument does not throw out of bindOptions", () => {
    const probe = mk();
    const hostile = new Proxy({}, { get: () => { throw new Error("boom"); } });
    expect(() => probe.bindOptions(hostile)).not.toThrow();
    expect(probe.bindOptions(undefined as never)).toBeUndefined();
  });
});

describe("no unhandled rejection from any fire-and-forget branch", () => {
  let seen: unknown[];
  const listener = (reason: unknown) => {
    seen.push(reason);
  };
  beforeEach(() => {
    seen = [];
    process.on("unhandledRejection", listener);
  });
  afterEach(() => {
    process.off("unhandledRejection", listener);
  });
  const settle = () => new Promise<void>((r) => setTimeout(r, 120));

  it("a resolver that rejects AFTER the timeout, a resolver that throws synchronously, and an emit that throws", async () => {
    const lateReject = mk({ timeoutMs: 20, resolveAuthMode: () => new Promise<string>((_r, rej) => setTimeout(() => rej(new Error("late")), 60)) });
    await lateReject.observe(failure());
    expect(tagsOf().auth_mode).toBe("unknown");

    const syncThrow = mk({
      resolveAuthMode: () => {
        throw new Error("sync");
      },
    });
    await syncThrow.observe(failure());

    h.report.mockImplementationOnce(() => {
      throw new Error("emit");
    });
    await mk().observe(failure());

    // The fire-and-forget form the runners use: `void probe.observe(...)`.
    void mk().observe(failure());
    await settle();
    expect(seen).toEqual([]);
  });
});

describe("makeAuthModeResolver against a fake PersistenceClient", () => {
  const row = (authMode: string) => ({
    id: "run-1",
    workspace_id: "ws-1",
    execution_kind: "conversation",
    conversation_id: "conv-1",
    engine_id: "claude",
    auth_mode: authMode,
    adapter_version: "1",
    created_at: "2026-10-25T00:00:00Z",
  });
  const clientReturning = (result: { data: unknown; error: { message: string } | null }) => {
    const eq = vi.fn();
    const chain = { eq, maybeSingle: vi.fn(async () => result) };
    eq.mockReturnValue(chain);
    const select = vi.fn(() => chain);
    const from = vi.fn(() => ({ select }));
    return { client: { from, rpc: vi.fn() }, from, eq };
  };

  it("row present: the persisted auth mode; the lookup is keyed by the conversation id on the user's tenant client", async () => {
    for (const mode of ["managed", "api-key"]) {
      const { client, from, eq } = clientReturning({ data: row(mode), error: null });
      h.freshTenant.mockResolvedValueOnce(client);
      await expect(makeAuthModeResolver("user-1", "conv-1")()).resolves.toBe(mode);
      expect(h.freshTenant).toHaveBeenLastCalledWith("user-1");
      expect(from).toHaveBeenCalledWith("agent_engine_runs");
      expect(eq).toHaveBeenCalledWith("conversation_id", "conv-1");
    }
  });

  it("no engine-run row resolves null, which the probe reports as unbound", async () => {
    const { client } = clientReturning({ data: null, error: null });
    h.freshTenant.mockResolvedValueOnce(client);
    const resolver = makeAuthModeResolver("user-1", "conv-old");
    await expect(resolver()).resolves.toBeNull();
    h.freshTenant.mockResolvedValueOnce(clientReturning({ data: null, error: null }).client);
    const probe = mk({ resolveAuthMode: makeAuthModeResolver("user-1", "conv-old") });
    await probe.observe(failure());
    expect(tagsOf().auth_mode).toBe("unbound");
  });

  it("a client or query error rejects, which the probe reports as unknown without skipping the emit", async () => {
    h.freshTenant.mockRejectedValueOnce(new Error("mint failed"));
    await expect(makeAuthModeResolver("user-1", "conv-1")()).rejects.toThrow();
    h.freshTenant.mockResolvedValueOnce(clientReturning({ data: null, error: { message: "rls" } }).client);
    const probe = mk({ resolveAuthMode: makeAuthModeResolver("user-1", "conv-1") });
    await probe.observe(failure());
    expect(emits()).toHaveLength(1);
    expect(tagsOf().auth_mode).toBe("unknown");
  });

  it("a row whose mode is outside the closed set is normalised to unknown by the probe, never echoed", async () => {
    h.freshTenant.mockResolvedValueOnce(clientReturning({ data: row("/workspaces/x/secret"), error: null }).client);
    const probe = mk({ resolveAuthMode: makeAuthModeResolver("user-1", "conv-1") });
    await probe.observe(failure());
    expect(tagsOf().auth_mode).toBe("unknown");
    expect(JSON.stringify(h.report.mock.calls)).not.toContain("/workspaces/x");
  });
});
