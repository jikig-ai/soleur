import { randomBytes } from "node:crypto";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

// #12289 — PROXY_HELLO_HMAC_KEY is a credential that must never reach a log line, a Sentry event, an
// agent subprocess env or a service-token name. Reads the LIVE module exports, so a weakening needs a
// source edit this test sees; there is no stored hash.

import { REDACT_PATHS, SENSITIVE_KEY_NAMES, SENSITIVE_LOWER } from "@/server/sensitive-keys";
import { ALLOWED_SERVICE_ENV_VARS, buildAgentEnv } from "@/server/agent-env";
import { scrubSentryEvent } from "@/server/sentry-scrub";
import { __resetProxyHelloKeyForTests, loadProxyHelloKeys } from "@/server/proxy-tls";

vi.mock("@/server/observability", () => ({
  reportSilentFallback: vi.fn(),
  warnSilentFallback: vi.fn(),
  infoSilentFallback: vi.fn(),
}));

const NAME = "PROXY_HELLO_HMAC_KEY";
const SERVER_DIR = join(__dirname, "..", "server");
const KEY_VALUE = randomBytes(32).toString("hex");

beforeEach(() => {
  vi.stubEnv(NAME, KEY_VALUE);
});
afterEach(() => vi.unstubAllEnvs());

describe("PROXY_HELLO_HMAC_KEY is a sensitive key", () => {
  it("is listed for pino and Sentry redaction (exact name, lowercase set, redact paths)", () => {
    expect(SENSITIVE_KEY_NAMES).toContain(NAME);
    expect(SENSITIVE_LOWER.has(NAME.toLowerCase())).toBe(true);
    expect(REDACT_PATHS).toContain(NAME);
    expect(REDACT_PATHS).toContain(`*.${NAME}`);
  });

  it("the Sentry scrubber redacts it inside an extra object", () => {
    const scrubbed = scrubSentryEvent({ extra: { [NAME]: KEY_VALUE, keep: "visible" } }) as { extra: Record<string, unknown> };
    expect(JSON.stringify(scrubbed)).not.toContain(KEY_VALUE);
    expect(scrubbed.extra.keep).toBe("visible");
  });

  it("the public certificate stays unredacted (positive control for the scrubber)", () => {
    expect(SENSITIVE_LOWER.has("proxy_tls_cert")).toBe(false);
    expect(SENSITIVE_LOWER.has("proxy_tls_key")).toBe(true);
  });
});

describe("PROXY_HELLO_HMAC_KEY stays out of the agent surface", () => {
  it("precondition: the variable really is set in process.env for this test", () => {
    expect(process.env[NAME]).toBe(KEY_VALUE);
  });

  it("is not an allowed service env var", () => {
    expect(ALLOWED_SERVICE_ENV_VARS.has(NAME)).toBe(false);
  });

  it("buildAgentEnv never forwards it, whatever process.env holds", () => {
    const env = buildAgentEnv({ value: "sk-ant-test-credential", scheme: "api_key" });
    expect(Object.keys(env)).not.toContain(NAME);
    expect(JSON.stringify(env)).not.toContain(KEY_VALUE);
  });

  it("buildAgentEnv drops it even when offered as a service token name", () => {
    const env = buildAgentEnv({ value: "sk-ant-test-credential", scheme: "api_key" }, { [NAME]: KEY_VALUE });
    expect(Object.keys(env)).not.toContain(NAME);
    expect(JSON.stringify(env)).not.toContain(KEY_VALUE);
  });

  it.each(["agent-env.ts", "providers.ts"])("%s names the key on no source line", (file) => {
    const src = readFileSync(join(SERVER_DIR, file), "utf8");
    expect(src.split("\n").filter((l) => l.includes(NAME))).toEqual([]);
  });
});

// #8211 (ADR-323 Decision 9) — Guard 3: the verify-only slot PROXY_HELLO_HMAC_KEY_ACCEPT_ALSO is under the same rules,
// so these rows run over BOTH names (the single-name rows above stay as they were).
const NAMES = ["PROXY_HELLO_HMAC_KEY", "PROXY_HELLO_HMAC_KEY_ACCEPT_ALSO"] as const;
const VALUES: Record<(typeof NAMES)[number], string> = {
  PROXY_HELLO_HMAC_KEY: KEY_VALUE,
  PROXY_HELLO_HMAC_KEY_ACCEPT_ALSO: randomBytes(32).toString("hex"),
};
const ROWS = NAMES.map((n) => [n, VALUES[n]] as const);

describe("both hello-key names (Guard 3)", () => {
  beforeEach(() => {
    for (const n of NAMES) vi.stubEnv(n, VALUES[n]);
  });

  it("own dispatch: the name list is exactly the two hello-key names, with distinct synthesized values", () => {
    expect([...NAMES]).toEqual(["PROXY_HELLO_HMAC_KEY", "PROXY_HELLO_HMAC_KEY_ACCEPT_ALSO"]);
    expect(ROWS).toHaveLength(2);
    expect(VALUES.PROXY_HELLO_HMAC_KEY).not.toBe(VALUES.PROXY_HELLO_HMAC_KEY_ACCEPT_ALSO);
  });

  describe.each(ROWS)("%s", (name, value) => {
    it("is listed for pino and Sentry redaction (exact name, lowercase set, redact paths)", () => {
      expect(SENSITIVE_KEY_NAMES).toContain(name);
      expect(SENSITIVE_LOWER.has(name.toLowerCase())).toBe(true);
      expect(REDACT_PATHS).toContain(name);
      expect(REDACT_PATHS).toContain(`*.${name}`);
    });

    it("the Sentry scrubber redacts it inside an extra object", () => {
      const scrubbed = scrubSentryEvent({ extra: { [name]: value, keep: "visible" } }) as { extra: Record<string, unknown> };
      expect(JSON.stringify(scrubbed)).not.toContain(value);
      expect(scrubbed.extra.keep).toBe("visible");
    });

    it("is not an allowed service env var", () => {
      expect(ALLOWED_SERVICE_ENV_VARS.has(name)).toBe(false);
    });

    it("buildAgentEnv never forwards it from process.env, nor as an offered service token name", () => {
      expect(process.env[name]).toBe(value); // precondition: really set
      const fromEnv = buildAgentEnv({ value: "sk-ant-test-credential", scheme: "api_key" });
      const offered = buildAgentEnv({ value: "sk-ant-test-credential", scheme: "api_key" }, { [name]: value });
      for (const env of [fromEnv, offered]) {
        expect(Object.keys(env)).not.toContain(name);
        expect(JSON.stringify(env)).not.toContain(value);
      }
    });

    it.each(["agent-env.ts", "providers.ts"])("%s names the key on no source line (exact name, not a substring of a longer one)", (file) => {
      const src = readFileSync(join(SERVER_DIR, file), "utf8");
      // Bounded on both sides, so the ACCEPT_ALSO row cannot pass by the base name's row and vice versa.
      const exact = new RegExp(`(?<![A-Za-z0-9_])${name}(?![A-Za-z0-9_])`);
      expect(src.split("\n").filter((l) => exact.test(l))).toEqual([]);
      // Self-test of the matcher: it hits the exact name and misses the other name.
      expect(exact.test(`x ${name} y`)).toBe(true);
      const other = NAMES.find((n) => n !== name) as string;
      expect(exact.test(`x ${other} y`)).toBe(false);
    });

    it("is absent from process.env after the boot loader runs", () => {
      __resetProxyHelloKeyForTests();
      expect(name in process.env).toBe(true);
      loadProxyHelloKeys();
      expect(name in process.env).toBe(false);
    });
  });
});
