import { readFileSync } from "node:fs";
import { join } from "node:path";
import { afterEach, describe, expect, it, vi } from "vitest";

// Partial-mock pino so the module's dedicated instance writes into a capture
// buffer instead of stdout, while keeping REAL pino serialization. That is
// load-bearing for AC2: a `vi.fn()` stub would only prove "warn was called",
// whereas AC2 requires capturing the emitted **level** and asserting >= 40 (the
// threshold `[transforms.app_container_warn_filter]` ships to Better Stack).
const { lines } = vi.hoisted(() => ({ lines: [] as string[] }));

vi.mock("pino", async (importOriginal) => {
  // pino ships as CJS (`export =`), so the namespace's interop `default` is what
  // `import pino from "pino"` actually binds. Typed loosely on purpose.
  const actual = (await importOriginal()) as Record<string, unknown>;
  const realPino = actual.default as (o: unknown, d: unknown) => unknown;
  return {
    ...actual,
    default: (opts: unknown) =>
      realPino(opts, {
        write: (s: string) => {
          lines.push(s);
        },
      }),
  };
});

import {
  CERT_REISSUE_PHASES,
  emitCertReissueMarker,
  type CertReissueMarker,
} from "@/server/cert-reissue-marker";

afterEach(() => {
  lines.length = 0;
});

const baseMarker: CertReissueMarker = {
  phase: "terminal",
  runId: "run-abc",
  attempt: 2,
  probeOnly: true,
};

function emitAndParse(m: CertReissueMarker): Record<string, unknown> {
  emitCertReissueMarker(m);
  expect(lines).toHaveLength(1);
  return JSON.parse(lines[0]) as Record<string, unknown>;
}

describe("emitCertReissueMarker", () => {
  it("emits at pino level >= 40 (WARN) so the Vector filter ships it (AC2)", () => {
    const row = emitAndParse(baseMarker);
    // The Vector app_container_warn_filter keeps `level_int >= 40` ONLY. An
    // info-level (30) marker would never leave the host — the exact defect
    // #6698 exists to fix.
    expect(typeof row.level).toBe("number");
    expect(row.level as number).toBeGreaterThanOrEqual(40);
  });

  it("carries the SOLEUR_CERT_REISSUE discriminator and the marker fields", () => {
    const row = emitAndParse(baseMarker);
    expect(row.SOLEUR_CERT_REISSUE).toBe(true);
    expect(row.phase).toBe("terminal");
    expect(row.runId).toBe("run-abc");
    expect(row.attempt).toBe(2);
    expect(row.probeOnly).toBe(true);
    expect(row.component).toBe("cert-reissue");
  });

  it("exports every phase in the closed union and emits each (AC4 surface)", () => {
    // CERT_REISSUE_PHASES is the runtime mirror of the type union — AC4 compares
    // the observed phase set against it, so it must be complete and ordered.
    expect(CERT_REISSUE_PHASES).toEqual([
      "preflight",
      "pre-flip-dns",
      "flip-dns-only",
      "cname-put-null",
      "cname-put-set",
      "dns-propagation",
      "poll",
      "restore",
      "terminal",
      "onfailure-restore",
    ]);
    for (const phase of CERT_REISSUE_PHASES) {
      lines.length = 0;
      const row = emitAndParse({ ...baseMarker, phase });
      expect(row.phase).toBe(phase);
    }
  });

  it("is fail-open: a throwing logger does not propagate to the caller", () => {
    // Observability must never red a cron. Force a serialization throw.
    const circular: Record<string, unknown> = {};
    circular.self = circular;
    expect(() =>
      emitCertReissueMarker({
        ...baseMarker,
        detail: circular as unknown as string,
      }),
    ).not.toThrow();
  });
});

describe("marker PII / vector-scrub boundary (AC7)", () => {
  // `[transforms.pii_scrub_drop_userdata]` (vector.toml) DELETES these eight
  // top-level keys. A marker field so named would be silently dropped before
  // reaching Better Stack — a permanently dark field that looks wired.
  // DERIVED from vector.toml, not hand-copied. A frozen list does not widen
  // when a ninth `del()` is added upstream, so a new marker field with that
  // name would look wired in code and be permanently dark in practice.
  const DROPPED_BY_VECTOR = (() => {
    const toml = readFileSync(
      join(__dirname, "../../infra/vector.toml"),
      "utf8",
    );
    const keys = [
      ...toml.matchAll(/del\(parsed_obj\.([A-Za-z_][A-Za-z0-9_]*)\)/g),
    ].map((m) => m[1]);
    return [...new Set(keys)];
  })();

  it("derives the dropped-key list from vector.toml (non-vacuity)", () => {
    // If the extraction breaks, every guard below passes over an empty list.
    expect(DROPPED_BY_VECTOR.length).toBeGreaterThanOrEqual(8);
    expect(DROPPED_BY_VECTOR).toContain("message");
    expect(DROPPED_BY_VECTOR).toContain("user_input");
  });

  it("emits no key that the Vector PII scrub deletes", () => {
    // Populate EVERY optional field so the runtime key set is maximal.
    const fat: CertReissueMarker = {
      phase: "poll",
      runId: "run-1",
      attempt: 0,
      probeOnly: false,
      pollIndex: 3,
      certState: "bad_authz",
      certDescription: "some LE-side detail",
      certDomains: ["soleur.ai", "www.soleur.ai"],
      certExpiresAt: "2026-08-16",
      protectedDomainState: null,
      pendingDomainUnverifiedAt: null,
      cname: "soleur.ai",
      recordCount: 5,
      proxiedCount: 0,
      resolved4: ["185.199.108.153"],
      resolved6: [],
      resolve6Error: "ENODATA",
      resolve4Error: null,
      acmeApexStatus: 404,
      acmeWwwStatus: 404,
      acmeApexServer: "GitHub.com",
      acmeWwwServer: "GitHub.com",
      outcome: "poll_timeout",
      detail: "cap reached",
      elapsedMs: 900_000,
      ok: false,
      errorName: "Error",
      errorDetail: "boom",
    };
    const row = emitAndParse(fat);
    for (const forbidden of DROPPED_BY_VECTOR) {
      expect(Object.keys(row)).not.toContain(forbidden);
    }
  });

  it("declares no forbidden field name in the marker interface", () => {
    // Source-level guard so a FUTURE field addition is caught even when no test
    // populates it. Anchored on the field-DECLARATION syntax (`name?: `), never
    // the bare token — the module documents these same eight names in a comment,
    // and a bare-token grep would false-fail on its own prose
    // (cq-assert-anchor-not-bare-token).
    const src = readFileSync(
      join(__dirname, "../../server/cert-reissue-marker.ts"),
      "utf8",
    );
    for (const forbidden of DROPPED_BY_VECTOR) {
      const decl = new RegExp(`^\\s*${forbidden}\\s*\\??\\s*:`, "m");
      expect(src).not.toMatch(decl);
    }
    // Non-vacuity: the anchor must actually match a real declared field.
    expect(src).toMatch(/^\s*phase\s*\??\s*:/m);
  });

  it("carries no user-identifying or secret field", () => {
    const src = readFileSync(
      join(__dirname, "../../server/cert-reissue-marker.ts"),
      "utf8",
    );
    // This instance has no formatters.log PII rename and no redact paths, so a
    // user id / email / token field here would bypass ADR-029 entirely.
    for (const forbidden of [
      "userId",
      "user_id",
      "email",
      "token",
      "secret",
      "apiKey",
      "api_key",
    ]) {
      const decl = new RegExp(`^\\s*${forbidden}\\s*\\??\\s*:`, "m");
      expect(src).not.toMatch(decl);
    }
  });
});
