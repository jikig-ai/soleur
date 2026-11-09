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
