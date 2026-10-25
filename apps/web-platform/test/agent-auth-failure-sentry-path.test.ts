// Agent auth-failure diagnostic: the REAL path. The logger, reportSilentFallback, the probe and buildAgentQueryOptions are all
// real; only the Sentry SDK is replaced by spies (precedent: agent-sandbox-precreate-sentry-path.test.ts, whose mock spreads
// the real module so withIsolationScope stays real). Proves: one tagged message-path capture with no pino-mirror exception
// beside it (#8629 class), extra equals the payload plus err:null on the Sentry call AND on the pino line (observed through the
// logger's own breadcrumb mirror, with a positive control), the secret canary in whole and derived forms (blocking per the CPO
// condition), the real scrubSentryEvent leaves every payload key intact, no payload key collides with the sensitive or Vector
// drop sets, and the emit does not carry another tenant's breadcrumbs or user. Plan Phase 1 item 3; Guard 2 rows 1-3, 6, 7, 9, 9b.
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

// The pino line exists only if the level is enabled; the error line always is, the constant warn needs warn.
vi.hoisted(() => {
  process.env.LOG_LEVEL = "info";
});

const sentry = vi.hoisted(() => ({
  captureMessage: vi.fn(),
  captureException: vi.fn(),
  addBreadcrumb: vi.fn(),
}));
vi.mock("@sentry/nextjs", async (orig) => {
  const real = await orig<typeof import("@sentry/nextjs")>();
  // The namespace spread does not copy every export (re-exports are not enumerable); name the functions the emit and this
  // test depend on so a missing one is a loud mock error, not a silent unscoped fallback.
  return { ...real, init: real.init, getIsolationScope: real.getIsolationScope, withIsolationScope: real.withIsolationScope, ...sentry };
});

import * as Sentry from "@sentry/nextjs";

import { buildAgentQueryOptions } from "@/server/agent-runner-query-options";
import { createAgentAuthFailureProbe, __resetAgentAuthDedupeForTests } from "@/server/agent-auth-failure";
import { reportSilentFallback } from "@/server/observability";
import { scrubSentryEvent } from "@/server/sentry-scrub";
import { SENSITIVE_LOWER } from "@/server/sensitive-keys";
import { resolveWorkspaceMode } from "@/server/workspace-mode";

const APP_ROOT = join(__dirname, "..");
const SEP = "\u00B7";
const CLI_BODY = `Not logged in ${SEP} Please run /login`;

// SYNTHESIZED canaries, split by concatenation so a secret scanner never sees a whole token literal.
const CANARY_KEY = "sk-ant-" + "api03-" + "CANARYKEYCANARYKEY";
const CANARY_OAUTH = "sk-ant-" + "oat01-" + "CANARYOAUTHCANARY";
const CANARY_WORKSPACE = "/work" + "spaces/" + "canary-ws-9f2c41aa/project";
const CANARY_USER = "00000000-canary-" + "user-4000-8000-000000000042";
const CANARY_AUTHMODE = "sk-ant-" + "api03-" + "CANARYAUTHMODE";

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
];

const optionsFor = (credential: { value: string; scheme: "api_key" | "oauth_token" }) =>
  buildAgentQueryOptions({
    workspacePath: CANARY_WORKSPACE,
    pluginPath: "/tmp/test-workspace/plugins/soleur",
    mode: resolveWorkspaceMode("command_center"),
    credential,
    serviceTokens: {} as Record<string, string>,
    systemPrompt: "x",
    canUseTool: (async () => ({ behavior: "allow" as const, updatedInput: {} })) as never,
  } as never) as Record<string, any>;

/** The captured real stream shape (trimmed, synthetic ids): init, the CLI-authored assistant message, the result. */
const realStream = () => [
  { type: "system", subtype: "init", apiKeySource: "none", session_id: "fake-session", uuid: "00000000-0000-4000-8000-000000000001" },
  {
    type: "assistant",
    message: { model: "<synthetic>", role: "assistant", content: [{ type: "text", text: CLI_BODY }] },
    error: "authentication_failed",
    is_api_error_message: true,
    session_id: "fake-session",
    uuid: "00000000-0000-4000-8000-000000000002",
  },
  { type: "result", subtype: "success", is_error: true, result: CLI_BODY, session_id: "fake-session" },
];

type CaptureCall = [string, { level?: string; tags?: Record<string, string>; extra?: Record<string, unknown>; user?: unknown }];
const agentMessages = () => (sentry.captureMessage.mock.calls as CaptureCall[]).filter(([, o]) => o?.tags?.feature === "agent-auth");
const pinoMirrorCaptures = () =>
  (sentry.captureException.mock.calls as Array<[unknown, { tags?: Record<string, string> }?]>).filter(([, o]) => o?.tags?.feature === "pino-mirror");
const crumbs = () => (sentry.addBreadcrumb.mock.calls as Array<[{ category?: string; message?: string; data?: Record<string, unknown> }]>).map((c) => c[0]);
const agentCrumb = () => crumbs().find((c) => c.data?.feature === "agent-auth");
const surfaces = () => JSON.stringify([sentry.captureMessage.mock.calls, sentry.captureException.mock.calls, sentry.addBreadcrumb.mock.calls]);

async function runStream(over: { credential?: { value: string; scheme: "api_key" | "oauth_token" }; user?: string; resolver?: () => Promise<string | null>; runner?: "legacy" | "cc-soleur-go" } = {}) {
  const credential = over.credential ?? { value: CANARY_KEY, scheme: "api_key" as const };
  const probe = createAgentAuthFailureProbe({
    runner: over.runner ?? "legacy",
    credentialScheme: credential.scheme,
    dedupeToken: over.user ?? CANARY_USER,
    resolveAuthMode: over.resolver ?? (async () => "managed"),
  });
  const opts = probe.bindOptions(optionsFor(credential));
  for (const message of realStream()) await probe.observe(message);
  return opts;
}

beforeEach(() => {
  for (const f of Object.values(sentry)) f.mockReset();
  __resetAgentAuthDedupeForTests();
});
afterEach(() => {
  vi.unstubAllEnvs();
});

describe("the real path: one tagged message-path capture", () => {
  it("captures ONCE at level error with the constant message, feature/op and the ten keys, and no pino-mirror exception beside it", async () => {
    await runStream();
    const msgs = agentMessages();
    expect(msgs).toHaveLength(1);
    const [message, opts] = msgs[0];
    expect(opts.level).toBe("error");
    expect(opts.tags).toMatchObject({ feature: "agent-auth", op: "cli-auth-failure" });
    expect(message).toBe("agent-auth: the Claude CLI reported an authentication failure");
    expect(Object.keys(opts.tags!).filter((k) => k !== "feature" && k !== "op").sort()).toEqual([...TEN_KEYS].sort());
    // The #8629 defect: with an Error first argument the pino mirror would capture feature=pino-mirror and Sentry drops ours.
    expect(pinoMirrorCaptures()).toHaveLength(0);
    expect(sentry.captureException).not.toHaveBeenCalled();
  });

  it("the text arm wins over the structured code in the real stream, and the context tags are real values (a runner that skipped bindOptions would report unknown)", async () => {
    await runStream({ runner: "cc-soleur-go" });
    const tags = agentMessages()[0][1].tags!;
    expect(tags).toMatchObject({
      runner: "cc-soleur-go",
      credential_scheme: "api_key",
      auth_env_present: "true",
      auth_mode: "managed",
      cli_key_source: "none",
      seccomp_artifact: "base",
      has_egress: "false",
      sandbox: "on",
      outer_wrap: "false",
      match_kind: "not_logged_in",
    });
    for (const k of TEN_KEYS) expect(tags[k], k).not.toBe("unknown");
  });

  it("extra equals the payload plus err:null on the Sentry call, and the pino line (via the breadcrumb mirror) carries the same keys", async () => {
    await runStream();
    const [, opts] = agentMessages()[0];
    const payload = Object.fromEntries(Object.entries(opts.tags!).filter(([k]) => k !== "feature" && k !== "op"));
    expect(opts.extra).toEqual({ err: null, ...payload });

    // POSITIVE control for the observation point: the logger's mirror really handed the redacted pino object to addBreadcrumb.
    const crumb = agentCrumb();
    expect(crumb, "no breadcrumb carrying feature=agent-auth: the pino observation point saw nothing").toBeDefined();
    expect(crumb!.category).toBe("pino");
    expect(crumb!.data).toEqual({ err: null, feature: "agent-auth", op: "cli-auth-failure", ...payload });
    expect(Object.keys(payload).sort()).toEqual([...TEN_KEYS].sort());
  });

  it("the oauth scheme on the cc runner reports its own tuple", async () => {
    await runStream({ credential: { value: CANARY_OAUTH, scheme: "oauth_token" }, runner: "cc-soleur-go", user: `${CANARY_USER}-2` });
    expect(agentMessages()[0][1].tags).toMatchObject({ runner: "cc-soleur-go", credential_scheme: "oauth_token", auth_env_present: "true" });
  });
});

describe("secret canary (blocking): nothing sensitive reaches any sink, in whole or derived form", () => {
  it("the canaries are really present in the INPUTS (a canary over an empty capture proves nothing)", async () => {
    const opts = await runStream({ resolver: async () => CANARY_AUTHMODE });
    expect(JSON.stringify(opts.env)).toContain(CANARY_KEY);
    expect(String(opts.cwd)).toContain(CANARY_WORKSPACE);
    expect(JSON.stringify(realStream())).toContain("Please run /login");
    expect(agentMessages()).toHaveLength(1); // the capture is non-empty
  });

  it("the key, token, workspace path, user id, CLI body and a canary-shaped authMode appear in none of the serialised calls", async () => {
    await runStream({ resolver: async () => CANARY_AUTHMODE });
    await runStream({ credential: { value: CANARY_OAUTH, scheme: "oauth_token" }, runner: "cc-soleur-go", user: `${CANARY_USER}-2`, resolver: async () => CANARY_AUTHMODE });
    expect(agentMessages()).toHaveLength(2);
    const all = surfaces();
    const whole = [
      CANARY_KEY,
      CANARY_OAUTH,
      CANARY_WORKSPACE,
      CANARY_USER,
      CANARY_AUTHMODE,
      CLI_BODY,
      "Please run /login",
      "Not logged in",
      "canary-ws",
      "CANARY",
    ];
    for (const c of whole) expect(all, c).not.toContain(c);
    // Derived forms: a prefix of the key, its length, a slice of the user id.
    const derived = [CANARY_KEY.slice(0, 10), CANARY_OAUTH.slice(0, 10), CANARY_USER.slice(0, 12)];
    for (const c of derived) expect(all, c).not.toContain(c);
    for (const len of [CANARY_KEY.length, CANARY_OAUTH.length]) expect(all).not.toMatch(new RegExp(`(^|[^0-9])${len}([^0-9]|$)`));
    expect(all).not.toMatch(/user(Id|_id)/i);
  });

  it("CONTROL: the detector sees a leak on a non-sensitive key name (the logger's redaction cannot mask it)", () => {
    reportSilentFallback(null, { feature: "canary-control", op: "leak", extra: { note: CANARY_KEY, observed: CANARY_WORKSPACE } });
    const all = surfaces();
    expect(all).toContain(CANARY_KEY);
    expect(all).toContain(CANARY_WORKSPACE);
    expect(agentMessages()).toHaveLength(0);
  });
});

describe("the boundaries after the emit: scrubber and Better Stack drop list", () => {
  it("the REAL scrubSentryEvent leaves every payload key and value intact (control: a key named `tag` is redacted)", async () => {
    await runStream();
    const [message, opts] = agentMessages()[0];
    const event = { message, tags: opts.tags, extra: opts.extra };
    expect(scrubSentryEvent(JSON.parse(JSON.stringify(event)))).toEqual(JSON.parse(JSON.stringify(event)));
    const control = scrubSentryEvent({ tags: { tag: "x", match_kind: "not_logged_in" } });
    expect(control.tags.tag).toBe("[Redacted]");
    expect(control.tags.match_kind).toBe("not_logged_in");
  });

  it("no payload key is in the sensitive-key set", () => {
    expect(SENSITIVE_LOWER.size).toBeGreaterThan(10);
    for (const k of TEN_KEYS) expect(SENSITIVE_LOWER.has(k.toLowerCase()), k).toBe(false);
    for (const k of ["feature", "op"]) expect(SENSITIVE_LOWER.has(k)).toBe(false);
  });

  it("no payload key is on the Vector user-content drop list (parsed from infra/vector.toml)", () => {
    const toml = readFileSync(join(APP_ROOT, "infra/vector.toml"), "utf8");
    const start = toml.indexOf("[transforms.pii_scrub_drop_userdata]");
    expect(start).toBeGreaterThan(0);
    const block = toml.slice(start, toml.indexOf("\n[", start + 10));
    const dropped = [...block.matchAll(/del\(parsed_obj\.(\w+)\)/g)].map((m) => m[1]);
    // Non-vacuity: the parser really found the drop list.
    expect(dropped).toEqual(expect.arrayContaining(["body", "message", "prompt"]));
    for (const k of [...TEN_KEYS, "feature", "op", "err"]) expect(dropped, k).not.toContain(k);
  });
});

describe("isolation: the emit carries no other tenant's breadcrumbs or user", () => {
  const seed = () => {
    const outer = Sentry.getIsolationScope();
    outer.setUser({ id: "OUTER-TENANT-USER" });
    outer.addBreadcrumb({ category: "pino", message: "OUTER-TENANT-CRUMB" });
    return outer;
  };
  const outerUntouched = () => {
    expect(Sentry.getIsolationScope().getUser()?.id).toBe("OUTER-TENANT-USER");
    expect(JSON.stringify(Sentry.getIsolationScope().getScopeData().breadcrumbs)).toContain("OUTER-TENANT-CRUMB");
  };
  const observeScopeAtCapture = () => {
    const seen: { user: unknown; crumbs: unknown }[] = [];
    sentry.captureMessage.mockImplementation(() => {
      const scope = Sentry.getIsolationScope();
      seen.push({ user: scope.getUser(), crumbs: scope.getScopeData().breadcrumbs });
    });
    return seen;
  };

  it("without an isolating async-context strategy (the SDK default) the emit never wipes the process-wide scope", async () => {
    // Runs BEFORE Sentry.init below: under the default stack strategy withIsolationScope hands back the SAME scope, and
    // clearing it would destroy every tenant's breadcrumbs globally. The emit must detect that and leave it alone.
    const outer = seed();
    try {
      await runStream();
      expect(agentMessages()).toHaveLength(1);
      outerUntouched();
    } finally {
      outer.setUser(null);
      outer.clearBreadcrumbs();
    }
  });

  it("with the production strategy installed (Sentry.init, as server/index.ts does) a pre-seeded outer user and breadcrumb are absent from the captured event, and the outer scope is unchanged", async () => {
    // Same init call the server makes (sentry.server.config.ts), minus the DSN: it installs the AsyncLocalStorage strategy
    // that clones the isolation scope. No DSN means nothing is sent.
    Sentry.init({ dsn: undefined, defaultIntegrations: false, integrations: [], tracesSampleRate: 0 });
    const outer = seed();
    const seen = observeScopeAtCapture();
    try {
      await runStream();
      expect(agentMessages()).toHaveLength(1);
      expect(seen, "captureMessage was not observed").toHaveLength(1);
      expect(JSON.stringify(seen[0].user ?? {})).not.toContain("OUTER-TENANT");
      expect(JSON.stringify(seen[0].crumbs)).not.toContain("OUTER-TENANT");
      // The user passed to captureMessage is not an identity either.
      expect(JSON.stringify(agentMessages()[0][1].user ?? null)).not.toContain("OUTER-TENANT");
      outerUntouched();
    } finally {
      outer.setUser(null);
      outer.clearBreadcrumbs();
    }
  });
});
