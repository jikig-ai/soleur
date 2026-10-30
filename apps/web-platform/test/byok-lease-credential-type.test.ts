import { describe, it, expect, beforeEach, afterEach, vi } from "vitest";

// feat-operator-cc-oauth Phase 2 — two-row-by-provider credential model.
//
// Structural boundary invariants:
//   - getRestApiKey() queries ONLY provider='anthropic' and can therefore
//     NEVER return an oauth_token by construction (AC: raw-REST cannot read
//     oauth).
//   - getAgentCredential() prefers provider='anthropic_oauth' (gated), falls
//     back to provider='anthropic'. Returns { value, scheme }.
//   - The date (AC3), owner (AC4), and kill-switch (AC8) gates fire ONLY on
//     the oauth read.
//
// Provider-aware mock: the chain records the `provider` passed to `.eq()` so
// maybeSingle() can return the row for the specific provider queried — this is
// what lets the test prove getRestApiKey() never sees the oauth row.

const mocks = vi.hoisted(() => {
  let rows: Record<string, Record<string, unknown> | null> = {};
  let fetchError: Error | null = null;
  return {
    setRow: (provider: string, row: Record<string, unknown> | null) => {
      rows[provider] = row;
    },
    getRows: () => rows,
    getFetchError: () => fetchError,
    setFetchError: (e: Error | null) => {
      fetchError = e;
    },
    reset: () => {
      rows = {};
      fetchError = null;
    },
  };
});

// #11086 — capture every sink a stored credential could leak into (pino +
// Sentry) and every plaintext buffer the lease decrypts (to observe zeroize).
const sinks = vi.hoisted(() => ({
  calls: [] as unknown[],
  decrypted: [] as Buffer[],
  providersQueried: [] as string[],
  reset() {
    this.calls.length = 0;
    this.decrypted.length = 0;
    this.providersQueried.length = 0;
  },
}));

vi.mock("@/server/logger", () => {
  const rec = (...a: unknown[]) => {
    sinks.calls.push(a);
  };
  const logger: Record<string, unknown> = {
    error: rec,
    warn: rec,
    info: rec,
    debug: rec,
    trace: rec,
    fatal: rec,
  };
  logger.child = () => logger;
  return { default: logger, createChildLogger: () => logger };
});
vi.mock("@sentry/nextjs", () => ({
  captureMessage: vi.fn((...a: unknown[]) => {
    sinks.calls.push(["sentry.captureMessage", ...a]);
  }),
  captureException: vi.fn((...a: unknown[]) => {
    sinks.calls.push(["sentry.captureException", ...a]);
  }),
  addBreadcrumb: vi.fn((...a: unknown[]) => {
    sinks.calls.push(["sentry.addBreadcrumb", ...a]);
  }),
}));
vi.mock("@/server/byok", async (importOriginal) => {
  const actual = await importOriginal<typeof import("@/server/byok")>();
  return {
    ...actual,
    decryptKey: (...args: Parameters<typeof actual.decryptKey>) => {
      const buf = actual.decryptKey(...args);
      sinks.decrypted.push(buf);
      return buf;
    },
  };
});

vi.mock("@/lib/supabase/tenant", () => ({
  getFreshTenantClient: vi.fn(async (_userId: string) => ({
    from: () => {
      const ctx: { provider?: string } = {};
      // biome-ignore lint/suspicious/noExplicitAny: test mock chain
      const chain: any = {
        select: () => chain,
        eq: (col: string, val: string) => {
          if (col === "provider") {
            ctx.provider = val;
            sinks.providersQueried.push(val);
          }
          return chain;
        },
        limit: () => chain,
        maybeSingle: async () => {
          if (mocks.getFetchError()) {
            return { data: null, error: mocks.getFetchError() };
          }
          return { data: mocks.getRows()[ctx.provider ?? ""] ?? null, error: null };
        },
      };
      return chain;
    },
  })),
  RuntimeAuthError: class RuntimeAuthError extends Error {},
  _resetTenantCache: () => {},
}));

import {
  runWithByokLease,
  ByokLeaseError,
  mapByokLeaseCauseToErrorCode,
  CC_OAUTH_EFFECTIVE_DATE,
  OauthNotYetPermittedError,
  OauthDelegationForbiddenError,
  MissingByokKeyError,
} from "@/server/byok-lease";
import { encryptKey } from "@/server/byok";
import { ConversationAuthModeError, AUTH_MODE_ERROR_REASONS } from "@/server/auth-mode-error";

const OPERATOR = "550e8400-e29b-41d4-a716-446655440000";
const OTHER = "660e8400-e29b-41d4-a716-446655440111";
const REST_PLAINTEXT = "sk-ant-api03-rest-key-1234567890";
const OAUTH_PLAINTEXT = "sk-ant-oat01-subscription-token-abcdef";

const BEFORE_DATE = CC_OAUTH_EFFECTIVE_DATE - 1; // 2026-06-14T23:59:59.999Z
const AFTER_DATE = CC_OAUTH_EFFECTIVE_DATE + 86_400_000; // 2026-06-16

// An oauth row with no mode resolver fails closed by design (the mode source is
// required for a subscription holder). Cases that intend the subscription path
// pass this.
const managedResolver = async () => "managed";

function seedProvider(provider: string, plaintext: string, owner: string) {
  const { encrypted, iv, tag } = encryptKey(plaintext, owner);
  mocks.setRow(provider, {
    encrypted_key: encrypted.toString("base64"),
    iv: iv.toString("base64"),
    auth_tag: tag.toString("base64"),
    key_version: 2,
  });
}

let savedEnabled: string | undefined;

beforeEach(() => {
  mocks.reset();
  sinks.reset();
  delete process.env.BYOK_ENCRYPTION_KEY;
  savedEnabled = process.env.CC_OAUTH_ENABLED;
});

afterEach(() => {
  vi.restoreAllMocks();
  if (savedEnabled === undefined) delete process.env.CC_OAUTH_ENABLED;
  else process.env.CC_OAUTH_ENABLED = savedEnabled;
});

describe("getRestApiKey — structural raw-REST boundary", () => {
  it("returns the provider='anthropic' plaintext", async () => {
    seedProvider("anthropic", REST_PLAINTEXT, OPERATOR);
    const result = await runWithByokLease(
      { workspaceContextUserId: OPERATOR, keyOwnerUserId: OPERATOR },
      (lease) => Promise.resolve(lease.getRestApiKey()),
    );
    expect(result).toBe(REST_PLAINTEXT);
  });

  it("NEVER returns the oauth token even when one exists, kill-switch on, date passed", async () => {
    process.env.CC_OAUTH_ENABLED = "1";
    vi.spyOn(Date, "now").mockReturnValue(AFTER_DATE);
    seedProvider("anthropic", REST_PLAINTEXT, OPERATOR);
    seedProvider("anthropic_oauth", OAUTH_PLAINTEXT, OPERATOR);

    const result = await runWithByokLease(
      { workspaceContextUserId: OPERATOR, keyOwnerUserId: OPERATOR },
      (lease) => Promise.resolve(lease.getRestApiKey()),
    );
    // Construction guarantee: getRestApiKey queries provider='anthropic'.
    expect(result).toBe(REST_PLAINTEXT);
    expect(result).not.toBe(OAUTH_PLAINTEXT);
  });
});

describe("getAgentCredential — oauth preference + gates", () => {
  it("prefers oauth_token when enabled + date passed + owner matches", async () => {
    process.env.CC_OAUTH_ENABLED = "1";
    vi.spyOn(Date, "now").mockReturnValue(AFTER_DATE);
    seedProvider("anthropic", REST_PLAINTEXT, OPERATOR);
    seedProvider("anthropic_oauth", OAUTH_PLAINTEXT, OPERATOR);

    const cred = await runWithByokLease(
      { workspaceContextUserId: OPERATOR, keyOwnerUserId: OPERATOR, resolveAuthMode: managedResolver },
      (lease) => Promise.resolve(lease.getAgentCredential()),
    );
    expect(cred).toEqual({ value: OAUTH_PLAINTEXT, scheme: "oauth_token" });
  });

  it("AC3: date gate throws OauthNotYetPermittedError before the effective date", async () => {
    process.env.CC_OAUTH_ENABLED = "1";
    vi.spyOn(Date, "now").mockReturnValue(BEFORE_DATE);
    seedProvider("anthropic", REST_PLAINTEXT, OPERATOR);
    seedProvider("anthropic_oauth", OAUTH_PLAINTEXT, OPERATOR);

    await expect(
      runWithByokLease(
        { workspaceContextUserId: OPERATOR, keyOwnerUserId: OPERATOR },
        (lease) => Promise.resolve(lease.getAgentCredential()),
      ),
    ).rejects.toBeInstanceOf(OauthNotYetPermittedError);
  });

  it("AC3 boundary: exactly at the effective instant the oauth credential is permitted (gate is `<`, not `<=`)", async () => {
    process.env.CC_OAUTH_ENABLED = "1";
    vi.spyOn(Date, "now").mockReturnValue(CC_OAUTH_EFFECTIVE_DATE);
    seedProvider("anthropic_oauth", OAUTH_PLAINTEXT, OPERATOR);

    const cred = await runWithByokLease(
      { workspaceContextUserId: OPERATOR, keyOwnerUserId: OPERATOR, resolveAuthMode: managedResolver },
      (lease) => Promise.resolve(lease.getAgentCredential()),
    );
    expect(cred).toEqual({ value: OAUTH_PLAINTEXT, scheme: "oauth_token" });
  });

  it("AC4: owner mismatch on the oauth read throws OauthDelegationForbiddenError", async () => {
    process.env.CC_OAUTH_ENABLED = "1";
    vi.spyOn(Date, "now").mockReturnValue(AFTER_DATE);
    seedProvider("anthropic_oauth", OAUTH_PLAINTEXT, OTHER);

    await expect(
      runWithByokLease(
        { workspaceContextUserId: OPERATOR, keyOwnerUserId: OTHER },
        (lease) => Promise.resolve(lease.getAgentCredential()),
      ),
    ).rejects.toBeInstanceOf(OauthDelegationForbiddenError);
  });

  it("AC4: a delegated lease on the oauth read throws OauthDelegationForbiddenError", async () => {
    process.env.CC_OAUTH_ENABLED = "1";
    vi.spyOn(Date, "now").mockReturnValue(AFTER_DATE);
    seedProvider("anthropic_oauth", OAUTH_PLAINTEXT, OPERATOR);

    await expect(
      runWithByokLease(
        {
          workspaceContextUserId: OPERATOR,
          keyOwnerUserId: OPERATOR,
          delegationId: "11111111-1111-1111-1111-111111111111",
        },
        (lease) => Promise.resolve(lease.getAgentCredential()),
      ),
    ).rejects.toBeInstanceOf(OauthDelegationForbiddenError);
  });

  it("AC8: kill-switch off ⇒ falls back to api_key (oauth row ignored, no throw)", async () => {
    delete process.env.CC_OAUTH_ENABLED;
    vi.spyOn(Date, "now").mockReturnValue(AFTER_DATE);
    seedProvider("anthropic", REST_PLAINTEXT, OPERATOR);
    seedProvider("anthropic_oauth", OAUTH_PLAINTEXT, OPERATOR);

    const cred = await runWithByokLease(
      { workspaceContextUserId: OPERATOR, keyOwnerUserId: OPERATOR },
      (lease) => Promise.resolve(lease.getAgentCredential()),
    );
    expect(cred).toEqual({ value: REST_PLAINTEXT, scheme: "api_key" });
  });

  it("falls back to api_key when no oauth row exists (enabled + date passed)", async () => {
    process.env.CC_OAUTH_ENABLED = "1";
    vi.spyOn(Date, "now").mockReturnValue(AFTER_DATE);
    seedProvider("anthropic", REST_PLAINTEXT, OPERATOR);

    const cred = await runWithByokLease(
      { workspaceContextUserId: OPERATOR, keyOwnerUserId: OPERATOR },
      (lease) => Promise.resolve(lease.getAgentCredential()),
    );
    expect(cred).toEqual({ value: REST_PLAINTEXT, scheme: "api_key" });
  });
});

// #11086 — a stored subscription credential the bundled CLI is known to drop
// must fail loudly at the lease boundary (NOT be handed to the CLI, which
// would answer "Not logged in" without using the value as a credential), and must never fall
// back to the api_key row.
describe("getAgentCredential — unusable stored subscription credential (#11086)", () => {
  // Synthesized fakes only. One per class the classifier can return.
  const UNUSABLE: Array<[string, string]> = [
    ["api_key_shaped", "sk-ant-api03-FAKEcanaryAAAA"],
    ["api_key_shaped", "sk-ant-admin01-FAKEcanaryAAAA"],
    ["embedded_whitespace", "sk-ant-oat01-FAKEcanaryAAAA BBBB"],
    ["blank", "   "],
  ];

  beforeEach(() => {
    process.env.CC_OAUTH_ENABLED = "1";
    vi.spyOn(Date, "now").mockReturnValue(AFTER_DATE);
  });

  it.each(UNUSABLE)(
    "class %s: throws oauth_unusable, zeroizes the buffer, caches nothing, never reads the api row, emits one closed-class event",
    async (shapeClass, plaintext) => {
      seedProvider("anthropic", REST_PLAINTEXT, OPERATOR);
      seedProvider("anthropic_oauth", plaintext, OPERATOR);

      let first: unknown;
      let second: unknown;
      await runWithByokLease(
        { workspaceContextUserId: OPERATOR, keyOwnerUserId: OPERATOR, resolveAuthMode: managedResolver },
        async (lease) => {
          first = await Promise.resolve(lease.getAgentCredential()).catch((e) => e);
          // A second call in the SAME scope must refetch and throw again. If the
          // buffer had been cached into the slot before the check (reorder
          // mutation), this would return a cached credential instead.
          second = await Promise.resolve(lease.getAgentCredential()).catch((e) => e);
        },
      );

      for (const err of [first, second]) {
        expect(err).toBeInstanceOf(ByokLeaseError);
        expect((err as ByokLeaseError).cause).toBe("oauth_unusable");
        expect((err as ByokLeaseError).message).not.toContain("FAKEcanary");
      }

      // Zeroized: every buffer decrypted on this path is wiped before the throw.
      expect(sinks.decrypted.length).toBe(2);
      for (const buf of sinks.decrypted) {
        expect(buf.every((b) => b === 0)).toBe(true);
      }

      // No fallback: the api_key row is never even queried.
      expect(sinks.providersQueried).not.toContain("anthropic");

      // Exactly one event per attempt, carrying only the closed class.
      const events = sinks.calls.filter(
        (c) => Array.isArray(c) && c[0] === "sentry.captureMessage",
      ) as Array<[string, string, { tags: Record<string, string>; extra: Record<string, unknown> }]>;
      expect(events).toHaveLength(2);
      for (const [, , opts] of events) {
        expect(opts.tags).toEqual({
          feature: "byok-lease",
          op: "oauth-credential-unusable",
          shape_class: shapeClass,
        });
        const { err: _err, ...extra } = opts.extra;
        expect(extra).toEqual({ shape_class: shapeClass });
      }

      // The submitted value (or any part of it) is in no captured sink.
      const dump = JSON.stringify(sinks.calls);
      expect(dump).not.toContain("FAKEcanary");
      if (plaintext.trim() !== "") expect(dump).not.toContain(plaintext.trim());
    },
  );

  it("a valid-shaped fake subscription token still leases", async () => {
    seedProvider("anthropic_oauth", "sk-ant-oat01-FAKEvalid_0123-abc", OPERATOR);
    const cred = await runWithByokLease(
      { workspaceContextUserId: OPERATOR, keyOwnerUserId: OPERATOR, resolveAuthMode: managedResolver },
      (lease) => Promise.resolve(lease.getAgentCredential()),
    );
    expect(cred).toEqual({ value: "sk-ant-oat01-FAKEvalid_0123-abc", scheme: "oauth_token" });
    expect(
      sinks.calls.some((c) => Array.isArray(c) && c[0] === "sentry.captureMessage"),
    ).toBe(false);
  });

  it("oauth_unusable maps to key_invalid", () => {
    expect(mapByokLeaseCauseToErrorCode("oauth_unusable")).toBe("key_invalid");
  });
});

// #11591 — the conversation binding's auth mode selects the credential. The
// mode can only NARROW what the lease hands out: the kill-switch, date and
// owner gates fire first and unchanged, and an unreadable mode fails closed.
describe("getAgentCredential — binding auth mode (#11591)", () => {
  const VALID_OAUTH = "sk-ant-oat01-FAKEvalid_0123-abc";
  const SELF = { workspaceContextUserId: OPERATOR, keyOwnerUserId: OPERATOR };

  const unresolved = () =>
    sinks.calls.filter(
      (c) =>
        Array.isArray(c) &&
        c[0] === "sentry.captureMessage" &&
        (c[2] as { tags?: { op?: string } } | undefined)?.tags?.op === "auth-mode-unresolved",
    ) as Array<[string, string, { tags: Record<string, string>; extra: Record<string, unknown> }]>;

  const breadcrumbs = () =>
    sinks.calls.filter(
      (c) =>
        Array.isArray(c) &&
        c[0] === "sentry.addBreadcrumb" &&
        (c[1] as { message?: string } | undefined)?.message === "agent-credential-selected",
    ) as Array<[string, { data: Record<string, unknown> }]>;

  beforeEach(() => {
    process.env.CC_OAUTH_ENABLED = "1";
    vi.spyOn(Date, "now").mockReturnValue(AFTER_DATE);
  });

  function lease<T>(
    args: Partial<Parameters<typeof runWithByokLease>[0]>,
    fn: (l: Parameters<Parameters<typeof runWithByokLease<T>>[1]>[0]) => Promise<T>,
  ) {
    return runWithByokLease<T>({ ...SELF, ...args }, fn);
  }
  const cred = (args: Partial<Parameters<typeof runWithByokLease>[0]>) =>
    lease(args, (l) => Promise.resolve(l.getAgentCredential()));

  it("AC1 api-key: leases the api key although a valid subscription row exists; the subscription is never decrypted", async () => {
    seedProvider("anthropic", REST_PLAINTEXT, OPERATOR);
    seedProvider("anthropic_oauth", VALID_OAUTH, OPERATOR);
    const r = await cred({ resolveAuthMode: async () => "api-key" });
    expect(r).toEqual({ value: REST_PLAINTEXT, scheme: "api_key" });
    // Exactly one buffer was decrypted (the api key; zeroized at scope end), so the subscription was not.
    expect(sinks.decrypted).toHaveLength(1);
  });

  it("AC2 managed: leases the subscription token and never queries the api row", async () => {
    seedProvider("anthropic", REST_PLAINTEXT, OPERATOR);
    seedProvider("anthropic_oauth", VALID_OAUTH, OPERATOR);
    const r = await cred({ resolveAuthMode: managedResolver });
    expect(r).toEqual({ value: VALID_OAUTH, scheme: "oauth_token" });
    expect(sinks.providersQueried).not.toContain("anthropic");
  });

  it.each([
    ["api_key_shaped", "sk-ant-api03-FAKEcanaryAAAA"],
    ["embedded_whitespace", "sk-ant-oat01-FAKEcanaryAAAA BBBB"],
    ["blank", "   "],
  ])("AC3 class %s: api-key recovers from an unusable stored token; managed still fails closed", async (_c, bad) => {
    seedProvider("anthropic", REST_PLAINTEXT, OPERATOR);
    seedProvider("anthropic_oauth", bad, OPERATOR);

    const r = await cred({ resolveAuthMode: async () => "api-key" });
    expect(r.value).toBe(REST_PLAINTEXT);
    expect(r.scheme).toBe("api_key");
    expect(sinks.decrypted).toHaveLength(1);
    expect(sinks.calls.some((c) => Array.isArray(c) && c[0] === "sentry.captureMessage")).toBe(false);

    sinks.reset();
    const err = await cred({ resolveAuthMode: managedResolver }).catch((e) => e);
    expect(err).toBeInstanceOf(ByokLeaseError);
    expect((err as ByokLeaseError).cause).toBe("oauth_unusable");
  });

  it.each([
    ["delegated", { delegationId: "11111111-1111-1111-1111-111111111111" }, OauthDelegationForbiddenError, AFTER_DATE],
    ["owner mismatch", { keyOwnerUserId: OTHER }, OauthDelegationForbiddenError, AFTER_DATE],
    ["pre-date", {}, OauthNotYetPermittedError, BEFORE_DATE],
  ])("AC4 gate order (%s): the gate error wins and the mode is never read, in both modes", async (_n, extra, Err, now) => {
    seedProvider("anthropic", REST_PLAINTEXT, OPERATOR);
    seedProvider("anthropic_oauth", VALID_OAUTH, OPERATOR);
    for (const mode of ["api-key", "managed"]) {
      vi.spyOn(Date, "now").mockReturnValue(now);
      const spy = vi.fn(async () => mode);
      const p = cred({ ...extra, resolveAuthMode: spy });
      await expect(p).rejects.toBeInstanceOf(Err);
      expect(spy).not.toHaveBeenCalled();
    }
  });

  it("AC4 kill-switch off + api-key: api key, resolver never called, oauth never queried", async () => {
    delete process.env.CC_OAUTH_ENABLED;
    seedProvider("anthropic", REST_PLAINTEXT, OPERATOR);
    seedProvider("anthropic_oauth", VALID_OAUTH, OPERATOR);
    const spy = vi.fn(async () => "api-key");
    const r = await cred({ resolveAuthMode: spy });
    expect(r).toEqual({ value: REST_PLAINTEXT, scheme: "api_key" });
    expect(spy).not.toHaveBeenCalled();
    expect(sinks.providersQueried).not.toContain("anthropic_oauth");
  });

  it.each(["managed", "api-key"])("AC5 %s: no oauth row means the resolver is never called", async (mode) => {
    seedProvider("anthropic", REST_PLAINTEXT, OPERATOR);
    const spy = vi.fn(async () => mode);
    const r = await cred({ resolveAuthMode: spy });
    expect(r.scheme).toBe("api_key");
    expect(spy).not.toHaveBeenCalled();
  });

  it.each(["managed", "api-key"])("AC5 %s: with an oauth row, two calls in one scope call the resolver exactly once", async (mode) => {
    seedProvider("anthropic", REST_PLAINTEXT, OPERATOR);
    seedProvider("anthropic_oauth", VALID_OAUTH, OPERATOR);
    const spy = vi.fn(async () => mode);
    await lease({ resolveAuthMode: spy }, async (l) => {
      const a = await l.getAgentCredential();
      const b = await l.getAgentCredential();
      expect(b).toEqual(a);
    });
    expect(spy).toHaveBeenCalledTimes(1);
  });

  const JUNK: Array<[string, unknown]> = [
    ["empty", ""],
    ["underscore", "api_key"],
    ["upper", "MANAGED"],
    ["trailing space", "managed "],
    ["null", null],
    ["undefined", undefined],
    ["object", {}],
  ];
  it.each(JUNK)("AC6 invalid_value (%s): fails closed, reads nothing, caches nothing, one closed event", async (_n, junk) => {
    seedProvider("anthropic", REST_PLAINTEXT, OPERATOR);
    seedProvider("anthropic_oauth", VALID_OAUTH, OPERATOR);
    const spy = vi.fn(async () => junk as string);
    let second: unknown;
    const first = await lease({ resolveAuthMode: spy }, async (l) => {
      const f = await Promise.resolve(l.getAgentCredential()).catch((e) => e);
      second = await Promise.resolve(l.getAgentCredential()).catch((e) => e);
      return f;
    });
    for (const err of [first, second]) {
      expect(err).toBeInstanceOf(ByokLeaseError);
      expect((err as ByokLeaseError).cause).toBe("fetch_failed");
    }
    // Nothing cached: the resolver is asked again on the second call.
    expect(spy).toHaveBeenCalledTimes(2);
    expect(sinks.decrypted).toHaveLength(0);
    expect(sinks.providersQueried).not.toContain("anthropic");
    const ev = unresolved();
    expect(ev).toHaveLength(2);
    for (const [, , o] of ev) {
      expect(o.tags.reason).toBe("invalid_value");
      expect(o.extra.reason).toBe("invalid_value");
    }
    const dump = JSON.stringify(sinks.calls);
    expect(dump).not.toContain(VALID_OAUTH);
    expect(dump).not.toContain(REST_PLAINTEXT);
  });

  it("AC6 no resolver with an oauth row: fetch_failed, reason no_resolver, carried on the error", async () => {
    seedProvider("anthropic", REST_PLAINTEXT, OPERATOR);
    seedProvider("anthropic_oauth", VALID_OAUTH, OPERATOR);
    const err = await cred({}).catch((e) => e);
    expect(err).toBeInstanceOf(ByokLeaseError);
    expect((err as ByokLeaseError).cause).toBe("fetch_failed");
    // auto-sync keys its retry decision on this closed reason (deterministic reasons are not retried).
    expect((err as ByokLeaseError).reason).toBe("no_resolver");
    expect(unresolved().map((e) => e[2].tags.reason)).toEqual(["no_resolver"]);
    expect(sinks.decrypted).toHaveLength(0);
  });

  it("AC6 reasons: a real ConversationAuthModeError reaches its own tag; a spoofed plain Error is resolver_failed", async () => {
    seedProvider("anthropic", REST_PLAINTEXT, OPERATOR);
    seedProvider("anthropic_oauth", VALID_OAUTH, OPERATOR);
    for (const reason of AUTH_MODE_ERROR_REASONS) {
      sinks.reset();
      await cred({
        resolveAuthMode: async () => {
          throw new ConversationAuthModeError(reason);
        },
      }).catch(() => undefined);
      expect(unresolved().map((e) => e[2].tags.reason)).toEqual([reason]);
    }
    sinks.reset();
    const spoof = Object.assign(new Error("x"), { name: "ConversationAuthModeError", reason: "unbound" });
    const err = await cred({ resolveAuthMode: async () => { throw spoof; } }).catch((e) => e);
    expect((err as ByokLeaseError).cause).toBe("fetch_failed");
    expect(unresolved().map((e) => e[2].tags.reason)).toEqual(["resolver_failed"]);
    const plain = await cred({ resolveAuthMode: async () => { throw new Error("db down SECRETROW"); } }).catch((e) => e);
    expect((plain as ByokLeaseError).cause).toBe("fetch_failed");
    expect(JSON.stringify(sinks.calls)).not.toContain("SECRETROW");
  });

  it("AC8 api-key with no api row: MissingByokKeyError, never the subscription token", async () => {
    seedProvider("anthropic_oauth", VALID_OAUTH, OPERATOR);
    const err = await cred({ resolveAuthMode: async () => "api-key" }).catch((e) => e);
    expect(err).toBeInstanceOf(MissingByokKeyError);
    expect(sinks.decrypted).toHaveLength(0);
  });

  it.each(["managed", "api-key"])("scenario 9 (%s): a scope that ends while the mode is being read reads and decrypts nothing", async (mode) => {
    seedProvider("anthropic", REST_PLAINTEXT, OPERATOR);
    seedProvider("anthropic_oauth", VALID_OAUTH, OPERATOR);
    let release!: (v: string) => void;
    const gate = new Promise<string>((r) => { release = r; });
    let entered!: () => void;
    const resolverEntered = new Promise<void>((r) => { entered = r; });
    let pending!: Promise<unknown>;
    await lease({ resolveAuthMode: () => { entered(); return gate; } }, async (l) => {
      pending = Promise.resolve(l.getAgentCredential()).catch((e) => e);
      // Proves the call is parked ON the resolver: the oauth row read and the gates have run.
      await resolverEntered;
    });
    const queried = sinks.providersQueried.length;
    release(mode);
    const err = await pending;
    expect(err).toBeInstanceOf(ByokLeaseError);
    expect((err as ByokLeaseError).cause).toBe("escape");
    expect(sinks.providersQueried.length).toBe(queried);
    expect(sinks.decrypted).toHaveLength(0);
  });

  it("AC17: one agent-credential-selected breadcrumb per successful lease, carrying only the scheme", async () => {
    seedProvider("anthropic", REST_PLAINTEXT, OPERATOR);
    seedProvider("anthropic_oauth", VALID_OAUTH, OPERATOR);
    await cred({ resolveAuthMode: managedResolver });
    await cred({ resolveAuthMode: async () => "api-key" });
    const b = breadcrumbs();
    expect(b.map((x) => x[1].data)).toEqual([{ scheme: "oauth_token" }, { scheme: "api_key" }]);
    expect(JSON.stringify(b)).not.toContain(VALID_OAUTH);
  });

  it("AC17 negative: no breadcrumb claims a credential was selected on a fail-closed or refused lease", async () => {
    seedProvider("anthropic", REST_PLAINTEXT, OPERATOR);
    seedProvider("anthropic_oauth", VALID_OAUTH, OPERATOR);
    await cred({ resolveAuthMode: async () => "bogus" }).catch(() => undefined);
    await cred({}).catch(() => undefined);
    seedProvider("anthropic_oauth", "sk-ant-api03-FAKEcanaryAAAA", OPERATOR);
    await cred({ resolveAuthMode: managedResolver }).catch(() => undefined);
    expect(breadcrumbs()).toHaveLength(0);
  });
});
