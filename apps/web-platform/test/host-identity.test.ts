import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import {
  resolveHostId,
  assertHostIdNotUserId,
  describeHostIdentity,
  hostIdentityBootReport,
  HOST_KEY_RE,
} from "@/server/host-identity";
import verifyCases from "./fixtures/host-key-verify-cases.json";

beforeEach(() => {
  vi.stubEnv("SOLEUR_HOST_ID", "");
  vi.stubEnv("SOLEUR_HOST_KEY", "");
  vi.stubEnv("SOLEUR_HOST_PRIVATE_IP", "");
  vi.stubEnv("SOLEUR_HOST_ROSTER", "");
  vi.stubEnv("NODE_ENV", "test");
});
afterEach(() => {
  vi.unstubAllEnvs();
});

describe("resolveHostId (host-stable infra id, #5274 Phase 2)", () => {
  it("returns the injected SOLEUR_HOST_ID (the Hetzner server id)", () => {
    vi.stubEnv("SOLEUR_HOST_ID", "  12345678  "); // trims whitespace
    expect(resolveHostId()).toBe("12345678");
  });

  it("FAILS LOUD in production when SOLEUR_HOST_ID is unset (no per-container fallback)", () => {
    vi.stubEnv("NODE_ENV", "production");
    expect(() => resolveHostId()).toThrow(/SOLEUR_HOST_ID is unset in production/);
  });

  it("returns a stable non-prod sentinel when unset (dev/test), never a per-container value", () => {
    vi.stubEnv("NODE_ENV", "development");
    const id = resolveHostId();
    expect(id).toBe("dev-local");
    // Stable across calls (a per-container hostname would differ each time).
    expect(resolveHostId()).toBe(id);
  });
});

describe("assertHostIdNotUserId (the load-bearing DSAR boundary)", () => {
  const HETZNER_ID = "12345678";
  const USER_ID = "11111111-1111-4111-8111-111111111111";

  it("passes for a Hetzner integer host id vs a distinct user id", () => {
    expect(() => assertHostIdNotUserId(HETZNER_ID, USER_ID)).not.toThrow();
  });

  it("throws when host_id equals a user id", () => {
    expect(() => assertHostIdNotUserId(USER_ID, USER_ID)).toThrow(
      /host_id equals a user id/,
    );
  });

  it("throws when host_id is UUID-shaped (wrongly sourced from auth.uid())", () => {
    const otherUuid = "22222222-2222-4222-8222-222222222222";
    expect(() => assertHostIdNotUserId(otherUuid, USER_ID)).toThrow(
      /host_id is UUID-shaped/,
    );
  });

  it("passes for a 32-hex machine-id host id", () => {
    expect(() =>
      assertHostIdNotUserId("0123456789abcdef0123456789abcdef", USER_ID),
    ).not.toThrow();
  });
});

// #12910: the lease host_id is the var.web_hosts key (web-1/web-2), verified
// against this container's own private IP through the roster (CTO ruling T1).
describe("describeHostIdentity (#12910, verified var.web_hosts key)", () => {
  const ROSTER = JSON.stringify({ "web-1": "10.0.1.10", "web-2": "10.0.1.11" });
  const INSTANCE = "hetzner-176328334";
  function env(over: Record<string, string | undefined>): NodeJS.ProcessEnv {
    return {
      NODE_ENV: "production",
      SOLEUR_HOST_ID: INSTANCE,
      SOLEUR_HOST_ROSTER: ROSTER,
      ...over,
    } as NodeJS.ProcessEnv;
  }

  it("a valid, roster-verified key wins over the instance id", () => {
    expect(
      describeHostIdentity(env({ SOLEUR_HOST_KEY: "web-2", SOLEUR_HOST_PRIVATE_IP: "10.0.1.11" })),
    ).toEqual({ id: "web-2", source: "web-host-key" });
  });

  it("trims the key before verifying it", () => {
    expect(
      describeHostIdentity(env({ SOLEUR_HOST_KEY: "  web-2 ", SOLEUR_HOST_PRIVATE_IP: "10.0.1.11" })),
    ).toEqual({ id: "web-2", source: "web-host-key" });
  });

  it("a missing key falls back to the instance id (key-absent)", () => {
    expect(describeHostIdentity(env({ SOLEUR_HOST_PRIVATE_IP: "10.0.1.11" }))).toEqual({
      id: INSTANCE,
      source: "key-absent",
    });
  });

  it.each(["Web_1", "w".repeat(33), "22222222-2222-4222-8222-222222222222", "1web"])(
    "a malformed key %s falls back (key-malformed)",
    (k) => {
      expect(
        describeHostIdentity(env({ SOLEUR_HOST_KEY: k, SOLEUR_HOST_PRIVATE_IP: "10.0.1.11" })),
      ).toEqual({ id: INSTANCE, source: "key-malformed" });
    },
  );

  it("T1 collision: web-1 claimed on 10.0.1.11 does not verify (key-unverified)", () => {
    expect(
      describeHostIdentity(env({ SOLEUR_HOST_KEY: "web-1", SOLEUR_HOST_PRIVATE_IP: "10.0.1.11" })),
    ).toEqual({ id: INSTANCE, source: "key-unverified" });
  });

  it("a key absent from the roster does not verify (key-unverified)", () => {
    expect(
      describeHostIdentity(env({ SOLEUR_HOST_KEY: "web-3", SOLEUR_HOST_PRIVATE_IP: "10.0.1.12" })),
    ).toEqual({ id: INSTANCE, source: "key-unverified" });
  });

  it.each(["", "0.0.0.0", "   "])(
    "T10 canary: private IP %j cannot verify a key, so the instance id is used",
    (ip) => {
      expect(
        describeHostIdentity(env({ SOLEUR_HOST_KEY: "web-2", SOLEUR_HOST_PRIVATE_IP: ip })),
      ).toEqual({ id: INSTANCE, source: "key-unverified" });
    },
  );

  it("an unset roster cannot verify a key", () => {
    expect(
      describeHostIdentity(
        env({ SOLEUR_HOST_KEY: "web-2", SOLEUR_HOST_PRIVATE_IP: "10.0.1.11", SOLEUR_HOST_ROSTER: "" }),
      ),
    ).toEqual({ id: INSTANCE, source: "key-unverified" });
  });

  it("production with nothing set still throws the existing error", () => {
    expect(() =>
      describeHostIdentity({ NODE_ENV: "production" } as NodeJS.ProcessEnv),
    ).toThrow(/SOLEUR_HOST_ID is unset in production/);
  });

  it("an unverified key with no instance id in production throws, never returns the key", () => {
    expect(() =>
      describeHostIdentity(
        env({ SOLEUR_HOST_ID: "", SOLEUR_HOST_KEY: "web-2", SOLEUR_HOST_PRIVATE_IP: "10.0.1.12" }),
      ),
    ).toThrow(/SOLEUR_HOST_ID is unset in production/);
  });

  it("dev with nothing set gives the dev-local sentinel", () => {
    expect(describeHostIdentity({ NODE_ENV: "development" } as NodeJS.ProcessEnv)).toEqual({
      id: "dev-local",
      source: "dev-sentinel",
    });
  });

  it("resolveHostId() returns describeHostIdentity().id from process.env", () => {
    vi.stubEnv("NODE_ENV", "production");
    vi.stubEnv("SOLEUR_HOST_ID", INSTANCE);
    vi.stubEnv("SOLEUR_HOST_ROSTER", ROSTER);
    vi.stubEnv("SOLEUR_HOST_KEY", "web-2");
    vi.stubEnv("SOLEUR_HOST_PRIVATE_IP", "10.0.1.11");
    expect(resolveHostId()).toBe("web-2");
    expect(resolveHostId()).toBe(describeHostIdentity().id);
    vi.stubEnv("SOLEUR_HOST_PRIVATE_IP", "10.0.1.12");
    expect(resolveHostId()).toBe(INSTANCE);
  });

  it("a verified key needs no instance id, even in production", () => {
    expect(
      describeHostIdentity(
        env({ SOLEUR_HOST_ID: "", SOLEUR_HOST_KEY: "web-2", SOLEUR_HOST_PRIVATE_IP: "10.0.1.11" }),
      ),
    ).toEqual({ id: "web-2", source: "web-host-key" });
  });

  it("HOST_KEY_RE alone matches an instance-id key; only the roster check rejects it", () => {
    expect(HOST_KEY_RE.test("hetzner-176328334")).toBe(true);
    expect(HOST_KEY_RE.source).toBe("^[a-z][a-z0-9-]{0,30}$");
  });
});

describe("hostIdentityBootReport (#12910 boot line + Sentry condition)", () => {
  const ROSTER = JSON.stringify({ "web-2": "10.0.1.11" });
  const PROD = {
    NODE_ENV: "production",
    SOLEUR_HOST_ID: "hetzner-176328334",
    SOLEUR_HOST_ROSTER: ROSTER,
    SOLEUR_PROXY_BIND: "0.0.0.0",
  };
  const report = (over: Record<string, string | undefined>) =>
    hostIdentityBootReport({ ...PROD, ...over } as NodeJS.ProcessEnv);

  it("a verified prod host logs web-host-key and does not report", () => {
    expect(report({ SOLEUR_HOST_KEY: "web-2", SOLEUR_HOST_PRIVATE_IP: "10.0.1.11" })).toEqual({
      source: "web-host-key",
      line: "host_identity source=web-host-key",
      reportFallback: false,
    });
  });

  it("a prod host with an EMPTY private IP (late NIC) still reports", () => {
    expect(report({ SOLEUR_HOST_KEY: "web-2", SOLEUR_HOST_PRIVATE_IP: "" })).toEqual({
      source: "key-unverified",
      line: "host_identity source=key-unverified",
      reportFallback: true,
    });
  });

  it("the canary (empty SOLEUR_PROXY_BIND, empty key and IP) never reports", () => {
    expect(
      report({ SOLEUR_PROXY_BIND: "", SOLEUR_HOST_KEY: "", SOLEUR_HOST_PRIVATE_IP: "" }).reportFallback,
    ).toBe(false);
  });

  it("the first-boot container (no proxy bind, no ids) logs unresolved with the key reason and does not report", () => {
    expect(
      report({ SOLEUR_PROXY_BIND: undefined, SOLEUR_HOST_ID: undefined, SOLEUR_HOST_PRIVATE_IP: "10.0.1.11" }),
    ).toEqual({
      source: "unresolved",
      line: "host_identity source=unresolved key=key-absent",
      reportFallback: false,
    });
  });

  it("outside production nothing reports", () => {
    expect(report({ NODE_ENV: "development", SOLEUR_HOST_KEY: "" }).reportFallback).toBe(false);
  });
});

// CTO ruling T3a: the same table drives ci-deploy.sh host_key_running_verified (ci-deploy.test.sh HKV rows).
describe("shared host-key verification table (app side of the T3a parity pin)", () => {
  it("carries cases on both sides of the verdict", () => {
    expect(verifyCases.cases.filter((c) => c.verified).length).toBeGreaterThan(0);
    expect(verifyCases.cases.filter((c) => !c.verified).length).toBeGreaterThan(0);
  });
  it.each(verifyCases.cases)("$name", ({ env, verified }) => {
    const r = describeHostIdentity({
      NODE_ENV: "production",
      SOLEUR_HOST_ID: "hetzner-1",
      ...env,
    } as NodeJS.ProcessEnv);
    expect(r.source === "web-host-key" ? r.id : "").toBe(verified);
  });
});
