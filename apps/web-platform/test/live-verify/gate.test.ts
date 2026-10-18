// AC2 / AC2d — the allowlist code-gate and teardown predicate guard.
//
// These exercise the harness's pure gate functions WITHOUT launching a browser
// (run.ts guards main() behind import.meta.main, so importing is side-effect
// free). The gate must reject a wrong project ref BEFORE sign-in and a wrong
// UID/email BEFORE the browser launch; teardown must never issue a DELETE with
// an empty predicate.

import { spawnSync } from "node:child_process";
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

import { describe, expect, it, vi } from "vitest";
import { parse as parseYaml } from "yaml";

import {
  bindProject,
  verifyPrincipal,
  teardownConversation,
  assertUrlHostAllowed,
  EXPECTED_EMAIL,
  type Config,
  type VerifiedPrincipal,
} from "../../scripts/live-verify/run";

// Build a syntactically-valid anon JWT whose payload carries the given ref.
// Synthetic + short — never a real token (push-protection safe).
function makeAnonJwt(ref: string): string {
  const header = Buffer.from('{"alg":"HS256"}').toString("base64url");
  const payload = Buffer.from(JSON.stringify({ ref })).toString("base64url");
  return `${header}.${payload}.sig`;
}

const REF = "abcdefghijklmnopqrst"; // 20-char canonical ref

function baseConfig(over: Partial<Config> = {}): Config {
  return {
    supabaseUrl: `https://${REF}.supabase.co`,
    anonKey: makeAnonJwt(REF),
    password: "not-reached",
    expectedUid: "11111111-1111-1111-1111-111111111111",
    expectedRef: REF,
    productionUrl: "https://app.soleur.ai",
    dryRun: false,
    ...over,
  };
}

// The seed's decrypt-poisoned dummy key (seed-live-verify-user.sh). A real
// encrypted key can never equal this plaintext literal.
const SENTINEL = {
  encrypted_key: "live-verify-dummy-not-real",
  iv: "bGl2ZS12ZXJpZnktaXY=",
  auth_tag: "bGl2ZS12ZXJpZnktdGFn",
};

type KeyRow = { provider: string; encrypted_key: string; iv: string; auth_tag: string };
type Rows = { data: unknown[] | null; error: { name: string } | null };

const keyRow = (over: Partial<KeyRow> = {}): KeyRow => ({
  provider: "anthropic",
  ...SENTINEL,
  ...over,
});

// A compliant principal: exactly the seed's anthropic dummy row, no delegation.
const COMPLIANT: { api_keys: Rows; byok_delegations: Rows } = {
  api_keys: { data: [keyRow()], error: null },
  byok_delegations: { data: [], error: null },
};

// Stub for the principal's OWN RLS session: auth.getUser() plus the two reads
// the I-cannot-spend check issues. Records every table read so a test can pin
// that BOTH reads happen (a check that stops after api_keys is the bug class).
function stubUser(
  id: string,
  email: string | undefined,
  tables: { api_keys: Rows; byok_delegations: Rows } = COMPLIANT,
) {
  const reads: string[] = [];
  const stub = {
    auth: {
      getUser: vi.fn().mockResolvedValue({
        data: { user: { id, email } },
        error: null,
      }),
    },
    from: (table: string) => {
      reads.push(table);
      const b: Record<string, unknown> = {};
      Object.assign(b, {
        select: () => b,
        eq: () => b,
        then: (resolve: (v: unknown) => unknown) =>
          resolve(tables[table as keyof typeof tables] ?? { data: null, error: { name: "unexpected-table" } }),
      });
      return b;
    },
    reads,
  };
  return stub as unknown as Parameters<typeof verifyPrincipal>[0] & { reads: string[] };
}

describe("project-bind (AC2 — before sign-in)", () => {
  it("accepts the custom prod domain and the canonical shape", () => {
    expect(() => assertUrlHostAllowed("https://api.soleur.ai")).not.toThrow();
    expect(() =>
      assertUrlHostAllowed(`https://${REF}.supabase.co`),
    ).not.toThrow();
  });

  it("rejects a non-allowlisted host", () => {
    expect(() => assertUrlHostAllowed("https://evil.example.com")).toThrow();
  });

  it("throws on a wrong project ref (anon JWT ref != expected)", () => {
    const cfg = baseConfig({
      anonKey: makeAnonJwt("zzzzzzzzzzzzzzzzzzzz"),
      expectedRef: REF,
    });
    expect(() => bindProject(cfg)).toThrow(/anon-key ref/);
  });

  it("passes when the ref matches", () => {
    expect(() => bindProject(baseConfig())).not.toThrow();
  });
});

describe("allowlist code-gate (AC2 — before launch)", () => {
  const cfg = baseConfig();

  it("throws on a wrong UID", async () => {
    const supabase = stubUser(
      "99999999-9999-9999-9999-999999999999",
      EXPECTED_EMAIL,
    );
    await expect(verifyPrincipal(supabase, cfg)).rejects.toThrow(
      /session UID/,
    );
  });

  it("throws on a wrong email", async () => {
    const supabase = stubUser(cfg.expectedUid, "attacker@example.com");
    await expect(verifyPrincipal(supabase, cfg)).rejects.toThrow(
      /session email/,
    );
  });

  it("returns a verified principal when UID + email match", async () => {
    const supabase = stubUser(cfg.expectedUid, EXPECTED_EMAIL);
    const verified = await verifyPrincipal(supabase, cfg);
    expect(verified.uid).toBe(cfg.expectedUid);
  });
});

describe("I-cannot-spend gate (before launch, also under --dry-run)", () => {
  const cfg = baseConfig();
  const violation = /cannot-spend-violated/;

  async function verify(
    tables: { api_keys: Rows; byok_delegations: Rows },
    c: Config = cfg,
  ) {
    return verifyPrincipal(stubUser(c.expectedUid, EXPECTED_EMAIL, tables), c);
  }

  it("passes the seed's sentinel row, regardless of row id or created_at", async () => {
    // Must-PASS input that is NOT the canonical: extra columns a real read
    // returns (id, created_at) differ per row and must not matter.
    const row = { ...keyRow(), id: "any-id", created_at: "2030-01-01T00:00:00Z" };
    const v = await verify({ ...COMPLIANT, api_keys: { data: [row], error: null } });
    expect(v.uid).toBe(cfg.expectedUid);
  });

  it("reads BOTH api_keys and byok_delegations", async () => {
    const supabase = stubUser(cfg.expectedUid, EXPECTED_EMAIL);
    await verifyPrincipal(supabase, cfg);
    expect(supabase.reads).toEqual(expect.arrayContaining(["api_keys", "byok_delegations"]));
  });

  it.each([
    ["encrypted_key", { encrypted_key: "a-real-looking-ciphertext" }],
    ["iv", { iv: "AAAAAAAAAAAAAAAA" }],
    ["auth_tag", { auth_tag: "BBBBBBBBBBBBBBBB" }],
  ])("rejects an anthropic row whose %s is not the sentinel", async (_f, over) => {
    await expect(
      verify({ ...COMPLIANT, api_keys: { data: [keyRow(over)], error: null } }),
    ).rejects.toThrow(violation);
  });

  it("rejects a non-sentinel row of ANOTHER provider after a compliant anthropic row", async () => {
    // A check that stops at the first (compliant) row passes this fixture.
    await expect(
      verify({
        ...COMPLIANT,
        api_keys: {
          data: [keyRow(), keyRow({ provider: "openai", encrypted_key: "real-openai-ciphertext" })],
          error: null,
        },
      }),
    ).rejects.toThrow(violation);
  });

  it("accepts a sentinel row of another provider (every row equals the sentinel)", async () => {
    const v = await verify({
      ...COMPLIANT,
      api_keys: { data: [keyRow(), keyRow({ provider: "openai" })], error: null },
    });
    expect(v.uid).toBe(cfg.expectedUid);
  });

  it("rejects when a byok_delegations row exists for the principal", async () => {
    await expect(
      verify({ ...COMPLIANT, byok_delegations: { data: [{ id: "d1" }], error: null } }),
    ).rejects.toThrow(violation);
  });

  it("fails closed on zero api_keys rows", async () => {
    await expect(
      verify({ ...COMPLIANT, api_keys: { data: [], error: null } }),
    ).rejects.toThrow(violation);
  });

  it("fails closed when the api_keys read errors or returns null", async () => {
    await expect(
      verify({ ...COMPLIANT, api_keys: { data: null, error: { name: "PostgrestError" } } }),
    ).rejects.toThrow(violation);
    await expect(
      verify({ ...COMPLIANT, api_keys: { data: null, error: null } }),
    ).rejects.toThrow(violation);
  });

  it("fails closed when the byok_delegations read errors or returns null", async () => {
    await expect(
      verify({ ...COMPLIANT, byok_delegations: { data: null, error: { name: "PostgrestError" } } }),
    ).rejects.toThrow(violation);
    await expect(
      verify({ ...COMPLIANT, byok_delegations: { data: null, error: null } }),
    ).rejects.toThrow(violation);
  });

  it("fails closed when a read reports an error even alongside plausible data", async () => {
    // Kills a check keyed on the body alone: `error` must be consulted itself.
    await expect(
      verify({ ...COMPLIANT, api_keys: { data: [keyRow()], error: { name: "PostgrestError" } } }),
    ).rejects.toThrow(violation);
    await expect(
      verify({ ...COMPLIANT, byok_delegations: { data: [], error: { name: "PostgrestError" } } }),
    ).rejects.toThrow(violation);
  });

  it("still checks under --dry-run", async () => {
    await expect(
      verify(
        { ...COMPLIANT, api_keys: { data: [keyRow({ encrypted_key: "real" })], error: null } },
        baseConfig({ dryRun: true }),
      ),
    ).rejects.toThrow(violation);
  });

  it("never puts row contents in the error message", async () => {
    const secret = "REAL-CIPHERTEXT-MUST-NOT-LEAK";
    const err = await verify({
      ...COMPLIANT,
      api_keys: { data: [keyRow({ encrypted_key: secret })], error: null },
    }).catch((e: Error) => e);
    expect(err).toBeInstanceOf(Error);
    expect((err as Error).message).not.toContain(secret);
  });

  it("the sentinel literals equal what seed-live-verify-user.sh inserts", () => {
    const seed = readFileSync(
      join(__dirname, "../../scripts/seed-live-verify-user.sh"),
      "utf8",
    );
    // Anchored on the jq object the seed POSTs, not on the bare literals.
    const m = seed.match(
      /provider: "anthropic", encrypted_key: "([^"]+)", iv: "([^"]+)", auth_tag: "([^"]+)"/,
    );
    expect(m).not.toBeNull();
    expect({ encrypted_key: m![1], iv: m![2], auth_tag: m![3] }).toEqual(SENTINEL);
  });
});

describe("release workflow emit step: BLOCK classification (executed, not grepped)", () => {
  // Runs the REAL `emit` step body under the runner's shell
  // (`bash --noprofile --norc -eo pipefail`), cut at the Sentry POST so no
  // network is touched. A grep over the YAML would pin spelling, not decisions.
  const wf = parseYaml(
    readFileSync(join(__dirname, "../../../../.github/workflows/web-platform-release.yml"), "utf8"),
  ) as { jobs: Record<string, { steps: Array<{ id?: string; name?: string; run?: string }> }> };
  const steps = wf.jobs["live-verify"].steps;
  const emit = steps.find((st) => st.id === "emit");
  const cut = (emit?.run ?? "").split("# Parse the public client DSN")[0];

  function classify(resultLine: string) {
    const d = mkdtempSync(join(tmpdir(), "emit-classify-"));
    const out = join(d, "out");
    const sum = join(d, "sum");
    writeFileSync(out, "");
    writeFileSync(sum, "");
    const r = spawnSync("bash", ["--noprofile", "--norc", "-eo", "pipefail", "-c", cut], {
      env: {
        PATH: process.env.PATH ?? "",
        TRIGGERED: "1",
        GATE_FAILED: "0",
        RESULT_LINE: resultLine,
        HARNESS_OUTCOME: "failure",
        RC: "1",
        GITHUB_OUTPUT: out,
        GITHUB_STEP_SUMMARY: sum,
      } as unknown as NodeJS.ProcessEnv, // hermetic: NODE_ENV (augmented as required) is deliberately absent
      encoding: "utf8",
    });
    const kv = Object.fromEntries(
      readFileSync(out, "utf8").split("\n").filter(Boolean).map((l) => l.split("=", 2) as [string, string]),
    );
    rmSync(d, { recursive: true, force: true });
    return { status: r.status, ...kv };
  }

  it("extracted the emit body (instrument self-check)", () => {
    expect(emit).toBeDefined();
    expect(cut).toContain("BLOCK=0");
    expect(cut.length).toBeGreaterThan(200);
  });

  it("no step is named report-only", () => {
    expect(steps.filter((st) => /report-only/i.test(st.name ?? ""))).toEqual([]);
  });

  it("cannot-spend-violated is BLOCK=1 (a safety breach must not fail open)", () => {
    const r = classify("RESULT: CANT-RUN:cannot-spend-violated: api_keys-non-sentinel-row");
    expect(r).toMatchObject({ status: 0, result: "CANT-RUN", level: "error", block: "1" });
  });

  it.each([
    ["RESULT: CANT-RUN:session-rejected — rate_limited", "CANT-RUN", "0"],
    ["RESULT: CANT-RUN:browser-launch:Error", "CANT-RUN", "0"],
    ["RESULT: PASS — fresh conversation persisted", "PASS", "0"],
    ["RESULT: FAIL — rail did not show the conversation", "FAIL", "1"],
  ])("%s keeps its existing classification", (line, result, block) => {
    expect(classify(line)).toMatchObject({ status: 0, result, block });
  });
});

describe("teardown predicate guard (AC2d)", () => {
  const cfg = baseConfig();
  const verified: VerifiedPrincipal = {
    __brand: "verified-live-verify-principal",
    uid: cfg.expectedUid,
  } as VerifiedPrincipal;

  it("is a no-op (no DELETE issued) when the conversation id is empty", async () => {
    const from = vi.fn();
    const supabase = { from } as unknown as Parameters<
      typeof teardownConversation
    >[0];

    const result = await teardownConversation(supabase, cfg, verified, "");

    expect(result.kind).toBe("CANT-RUN");
    if (result.kind === "CANT-RUN") {
      expect(result.reason).toContain("CANT-TEARDOWN-empty-predicate");
    }
    // The critical assertion: zero DB calls — no DELETE with a null filter.
    expect(from).not.toHaveBeenCalled();
  });

  it("is a no-op when the allowlisted UID is empty", async () => {
    const from = vi.fn();
    const supabase = { from } as unknown as Parameters<
      typeof teardownConversation
    >[0];
    const empty: VerifiedPrincipal = {
      __brand: "verified-live-verify-principal",
      uid: "",
    } as VerifiedPrincipal;

    const result = await teardownConversation(
      supabase,
      cfg,
      empty,
      "33333333-3333-3333-3333-333333333333",
    );

    expect(result.kind).toBe("CANT-RUN");
    expect(from).not.toHaveBeenCalled();
  });
});

describe("teardown action-send-free + ordering (data-integrity)", () => {
  const cfg = baseConfig();
  const verified: VerifiedPrincipal = {
    __brand: "verified-live-verify-principal",
    uid: cfg.expectedUid,
  } as VerifiedPrincipal;
  const CONV = "44444444-4444-4444-4444-444444444444";

  // Chainable supabase stub: records the (op:table) sequence and resolves the
  // action_sends count query to `actionSendsCount`. Every chain link is
  // awaitable so `await sb.from(...).select(...).eq(...)` works.
  function makeStub(actionSendsCount: number, order: string[]) {
    const builder = (table: string) => {
      const b: Record<string, unknown> = {};
      Object.assign(b, {
        select: () => b,
        update: () => {
          order.push(`update:${table}`);
          return b;
        },
        delete: () => {
          order.push(`delete:${table}`);
          return b;
        },
        eq: () => b,
        like: () => b,
        then: (resolve: (v: unknown) => unknown) =>
          resolve(
            table === "action_sends"
              ? { count: actionSendsCount, error: null }
              : { data: null, error: null },
          ),
      });
      return b;
    };
    return { from: (t: string) => builder(t) } as unknown as Parameters<
      typeof teardownConversation
    >[0];
  }

  it("escalates to CANT-RUN (and never deletes) when the principal has action_sends", async () => {
    const order: string[] = [];
    const supabase = makeStub(1, order);

    const result = await teardownConversation(supabase, cfg, verified, CONV);

    expect(result.kind).toBe("CANT-RUN");
    if (result.kind === "CANT-RUN") {
      expect(result.reason).toContain("CANT-TEARDOWN-has-action-sends");
      expect(result.reason).toContain("#5463");
    }
    // The WORM guard: no conversation delete/update was issued.
    expect(order).not.toContain("delete:conversations");
    expect(order).not.toContain("update:conversations");
  });

  it("archives BEFORE deleting (slot-release ordering) on a clean teardown", async () => {
    const order: string[] = [];
    const supabase = makeStub(0, order);

    const result = await teardownConversation(supabase, cfg, verified, CONV);

    expect(result.kind).toBe("PASS");
    const archiveIdx = order.indexOf("update:conversations");
    const deleteIdx = order.indexOf("delete:conversations");
    expect(archiveIdx).toBeGreaterThanOrEqual(0);
    expect(deleteIdx).toBeGreaterThan(archiveIdx);
  });
});
