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
  emitLine,
  CANNOT_SPEND_VIOLATED,
  CANNOT_SPEND_UNVERIFIED,
  EXPECTED_EMAIL,
  SENTINEL_KEY,
  type Config,
  type VerifiedPrincipal,
} from "../../scripts/live-verify/run";
import { redact } from "../../scripts/live-verify/redact";

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

// The key row the seed inserts, built from the harness's OWN exported constant
// (a copy here would pin the test against itself, not against run.ts).
const SENTINEL = { ...SENTINEL_KEY };

type KeyRow = { provider: string; encrypted_key: string; iv: string; auth_tag: string };
type Rows = { data: unknown; error: { name: string } | null };
type Tables = { api_keys: Rows; byok_delegations: Rows };
type Call = { table: string; select: string; filters: string[] };

const keyRow = (over: Partial<KeyRow> = {}): KeyRow => ({
  provider: "anthropic",
  ...SENTINEL,
  ...over,
});

// A compliant principal: exactly the seed's anthropic dummy row, no delegation.
const COMPLIANT: Tables = {
  api_keys: { data: [keyRow()], error: null },
  byok_delegations: { data: [], error: null },
};

// Stub for the principal's OWN RLS session: auth.getUser() plus the two reads
// the I-cannot-spend check issues. It RECORDS the query shape (table, select
// string, every filter) so a test can pin it: a stub that ignores select/eq
// lets the SUT read the wrong columns, filter by provider, or skip a table and
// still pass (and with the real UNTYPED client a wrong column is a runtime
// 42703 that reddens every release).
function stubUser(id: string, email: string | undefined, tables: Tables = COMPLIANT) {
  const calls: Call[] = [];
  const stub = {
    auth: {
      getUser: vi.fn().mockResolvedValue({
        data: { user: { id, email } },
        error: null,
      }),
    },
    from: (table: string) => {
      const call: Call = { table, select: "", filters: [] };
      calls.push(call);
      const b: Record<string, unknown> = {};
      Object.assign(b, {
        select: (cols: string) => {
          call.select = cols;
          return b;
        },
        eq: (col: string, val: unknown) => {
          call.filters.push(`eq:${col}=${String(val)}`);
          return b;
        },
        is: (col: string, val: unknown) => {
          call.filters.push(`is:${col}=${String(val)}`);
          return b;
        },
        then: (resolve: (v: unknown) => unknown) =>
          resolve(
            tables[table as keyof Tables] ?? { data: null, error: { name: "unexpected-table" } },
          ),
      });
      return b;
    },
    calls,
  };
  return stub as unknown as Parameters<typeof verifyPrincipal>[0] & { calls: Call[] };
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
  const violated = (cls: string) => new RegExp(`^${CANNOT_SPEND_VIOLATED}: ${cls}$`);
  const unverified = (cls: string) => new RegExp(`^${CANNOT_SPEND_UNVERIFIED}: ${cls}$`);

  async function verify(tables: Tables, c: Config = cfg) {
    return verifyPrincipal(stubUser(c.expectedUid, EXPECTED_EMAIL, tables), c);
  }
  const withKeys = (data: unknown, error: Rows["error"] = null): Tables => ({
    ...COMPLIANT,
    api_keys: { data, error },
  });
  const withDelegations = (data: unknown, error: Rows["error"] = null): Tables => ({
    ...COMPLIANT,
    byok_delegations: { data, error },
  });

  it("passes the seed's sentinel row, regardless of row id or created_at", async () => {
    // Must-PASS input that is NOT the canonical: extra columns a real read
    // returns (id, created_at) differ per row and must not matter.
    const row = { ...keyRow(), id: "any-id", created_at: "2030-01-01T00:00:00Z" };
    const v = await verify(withKeys([row]));
    expect(v.uid).toBe(cfg.expectedUid);
  });

  it("pins the QUERY SHAPE: exact columns, no provider filter, active delegations only", async () => {
    // The real client is untyped, so tsc cannot catch a wrong column (42703 at
    // runtime reddens every release) and a provider filter would turn "every
    // row" into "anthropic only". Both reads must happen, in the shape below.
    const supabase = stubUser(cfg.expectedUid, EXPECTED_EMAIL);
    await verifyPrincipal(supabase, cfg);
    expect(supabase.calls).toEqual([
      { table: "api_keys", select: "provider, encrypted_key, iv, auth_tag", filters: [] },
      { table: "byok_delegations", select: "id", filters: ["is:revoked_at=null"] },
    ]);
  });

  it("runs the allowlist checks FIRST and reads nothing for a wrong principal", async () => {
    const supabase = stubUser(
      "99999999-9999-9999-9999-999999999999",
      EXPECTED_EMAIL,
      withKeys([keyRow({ encrypted_key: "real" })]),
    );
    await expect(verifyPrincipal(supabase, cfg)).rejects.toThrow(/session UID/);
    expect(supabase.calls).toEqual([]);
  });

  it.each([
    ["encrypted_key", { encrypted_key: "a-real-looking-ciphertext" }],
    ["iv", { iv: "AAAAAAAAAAAAAAAA" }],
    ["auth_tag", { auth_tag: "BBBBBBBBBBBBBBBB" }],
    ["encrypted_key (prefix of the sentinel)", { encrypted_key: `${SENTINEL.encrypted_key}x` }],
    ["encrypted_key (case differs)", { encrypted_key: SENTINEL.encrypted_key.toUpperCase() }],
    ["encrypted_key (padded)", { encrypted_key: ` ${SENTINEL.encrypted_key} ` }],
    ["iv (missing)", { iv: undefined as unknown as string }],
    ["auth_tag (null)", { auth_tag: null as unknown as string }],
  ])("rejects an anthropic row whose %s is not the sentinel", async (_f, over) => {
    await expect(verify(withKeys([keyRow(over)]))).rejects.toThrow(
      violated("api_keys-non-sentinel-row"),
    );
  });

  it.each(["openai", "anthropic_oauth", "bedrock", "vertex"])(
    "rejects a non-sentinel %s row after a compliant anthropic row",
    async (provider) => {
      // A check that stops at the first (compliant) row passes this fixture.
      const bad = keyRow({ provider, encrypted_key: "real-ciphertext" });
      await expect(verify(withKeys([keyRow(), bad]))).rejects.toThrow(
        violated("api_keys-non-sentinel-row"),
      );
    },
  );

  it.each([
    ["first", (b: KeyRow) => [b, keyRow(), keyRow({ provider: "openai" })]],
    ["middle", (b: KeyRow) => [keyRow(), b, keyRow({ provider: "openai" })]],
    ["last", (b: KeyRow) => [keyRow(), keyRow({ provider: "openai" }), b]],
  ])("rejects a bad row in the %s position of three", async (_pos, build) => {
    const bad = keyRow({ provider: "bedrock", auth_tag: "real" });
    await expect(verify(withKeys(build(bad)))).rejects.toThrow(
      violated("api_keys-non-sentinel-row"),
    );
  });

  it("accepts sentinel rows of other providers (every row equals the sentinel)", async () => {
    const v = await verify(
      withKeys([keyRow(), keyRow({ provider: "openai" }), keyRow({ provider: "vertex" })]),
    );
    expect(v.uid).toBe(cfg.expectedUid);
  });

  it("rejects when an active byok_delegations row is visible to the principal", async () => {
    await expect(verify(withDelegations([{ id: "d1" }]))).rejects.toThrow(
      violated("byok_delegations-present"),
    );
  });

  it.each([
    ["zero api_keys rows", withKeys([]), unverified("api_keys-empty")],
    ["api_keys read error", withKeys(null, { name: "PostgrestError" }), unverified("api_keys-unreadable")],
    [
      "api_keys read error alongside plausible data",
      withKeys([keyRow()], { name: "PostgrestError" }),
      unverified("api_keys-unreadable"),
    ],
    ["api_keys null body", withKeys(null), unverified("api_keys-unreadable")],
    ["api_keys non-array body", withKeys({}), unverified("api_keys-unreadable")],
    [
      "byok_delegations read error",
      withDelegations(null, { name: "PostgrestError" }),
      unverified("byok_delegations-unreadable"),
    ],
    [
      "byok_delegations read error alongside empty data",
      withDelegations([], { name: "PostgrestError" }),
      unverified("byok_delegations-unreadable"),
    ],
    ["byok_delegations null body", withDelegations(null), unverified("byok_delegations-unreadable")],
    ["byok_delegations non-array body", withDelegations({}), unverified("byok_delegations-unreadable")],
  ])("fails closed (UNVERIFIED, not a breach) on %s", async (_name, tables, expected) => {
    // "Could not check" still stops the launch (the throw), but must not carry
    // the breach token: the workflow BLOCKs only the VIOLATED prefix (CTO
    // ruling, #10449).
    await expect(verify(tables)).rejects.toThrow(expected);
  });

  it("still checks under --dry-run (verifyPrincipal does not consult cfg.dryRun)", async () => {
    await expect(
      verify(withKeys([keyRow({ encrypted_key: "real" })]), baseConfig({ dryRun: true })),
    ).rejects.toThrow(violated("api_keys-non-sentinel-row"));
  });

  it("main() runs verifyPrincipal before the dry-run branch and before the browser drive", () => {
    // The unit above cannot see main(); pin the ORDER in the comment-stripped
    // source so skipping the gate under --dry-run (or reordering) reds here.
    const src = readFileSync(join(__dirname, "../../scripts/live-verify/run.ts"), "utf8")
      .replace(/\/\*[\s\S]*?\*\//g, "")
      .replace(/^\s*\/\/.*$/gm, "");
    const main = src.slice(src.indexOf("async function main()"));
    const verifyAt = main.indexOf("await verifyPrincipal(supabase, cfg)");
    expect(verifyAt).toBeGreaterThan(0);
    expect(main.indexOf("if (!cfg.dryRun)")).toBeGreaterThan(verifyAt);
    expect(main.indexOf("driveAndVerify(verified")).toBeGreaterThan(verifyAt);
    expect(main.slice(0, verifyAt)).not.toContain("dryRun");
    // I-ephemerality: the throw path signs the session out, after emitting.
    const catchAt = main.indexOf("} catch (err) {", verifyAt);
    expect(catchAt).toBeGreaterThan(verifyAt);
    expect(main.indexOf("supabase?.auth.signOut()", catchAt)).toBeGreaterThan(
      main.indexOf("emit({ kind: \"CANT-RUN\"", catchAt),
    );
  });

  it("never puts any row field in the error message", async () => {
    const canary = (f: string) => `CANARY-${f}-MUST-NOT-LEAK`;
    const row = {
      provider: canary("provider"),
      encrypted_key: canary("encrypted_key"),
      iv: canary("iv"),
      auth_tag: canary("auth_tag"),
    };
    const err = await verify(withKeys([row])).catch((e: Error) => e);
    expect(err).toBeInstanceOf(Error);
    for (const f of Object.keys(row)) expect((err as Error).message).not.toContain(canary(f));
  });

  it("the SENTINEL_KEY constant equals what seed-live-verify-user.sh inserts", () => {
    const seed = readFileSync(join(__dirname, "../../scripts/seed-live-verify-user.sh"), "utf8")
      .split("\n")
      .filter((l) => !l.trimStart().startsWith("#"))
      .join("\n");
    // Exactly one POST target, so a second (e.g. real-key) insert cannot hide
    // behind the first; and the regex runs on comment-stripped text so a
    // retained old shape in a comment cannot satisfy it.
    expect(seed.split('"$SB_URL/rest/v1/api_keys"').length - 1).toBe(1);
    const m = seed.match(
      /provider: "anthropic", encrypted_key: "([^"]+)", iv: "([^"]+)", auth_tag: "([^"]+)"/,
    );
    expect(m).not.toBeNull();
    expect({ encrypted_key: m![1], iv: m![2], auth_tag: m![3] }).toEqual(SENTINEL_KEY);
  });
});

describe("release workflow: BLOCK classification (executed, not grepped)", () => {
  // Runs the REAL `emit` and `Enforce` step bodies from the workflow file. The
  // runner's default shell for a `run:` with no `shell:` key is `bash -e {0}`;
  // `-o pipefail` is what the body's own `set -uo pipefail` adds, so running
  // under `-eo pipefail` here is the same or stricter. A grep over the YAML
  // would pin spelling, not decisions.
  type Step = { id?: string; name?: string; run?: string; env?: Record<string, string> };
  const wf = parseYaml(
    readFileSync(join(__dirname, "../../../../.github/workflows/web-platform-release.yml"), "utf8"),
  ) as { jobs: Record<string, { steps: Step[] }> };
  const steps = wf.jobs["live-verify"].steps;
  const emit = steps.find((st) => st.id === "emit");
  const enforce = steps.find((st) => st.name?.startsWith("Enforce live-verify gate"));
  const MARKER = "# Parse the public client DSN";
  // Cut at the Sentry POST so no network is touched.
  const cut = (emit?.run ?? "").split(MARKER)[0];

  function run(body: string, env: Record<string, string | undefined>) {
    const d = mkdtempSync(join(tmpdir(), "wf-step-"));
    try {
      const out = join(d, "out");
      const sum = join(d, "sum");
      writeFileSync(out, "");
      writeFileSync(sum, "");
      const clean = Object.fromEntries(
        Object.entries({ PATH: process.env.PATH, GITHUB_OUTPUT: out, GITHUB_STEP_SUMMARY: sum, ...env }).filter(
          ([, v]) => v !== undefined,
        ),
      );
      const r = spawnSync("bash", ["--noprofile", "--norc", "-eo", "pipefail", "-c", body], {
        // hermetic: NODE_ENV (augmented as required in this repo) is deliberately absent
        env: clean as unknown as NodeJS.ProcessEnv,
        encoding: "utf8",
        timeout: 20_000,
      });
      const kv = Object.fromEntries(
        readFileSync(out, "utf8").split("\n").filter(Boolean).map((l) => l.split("=", 2) as [string, string]),
      );
      return { status: r.status, stdout: r.stdout ?? "", ...kv };
    } finally {
      rmSync(d, { recursive: true, force: true });
    }
  }
  const classify = (resultLine: string | undefined, env: Record<string, string | undefined> = {}) =>
    run(cut, {
      TRIGGERED: "1",
      GATE_FAILED: "0",
      RESULT_LINE: resultLine,
      HARNESS_OUTCOME: "failure",
      RC: "1",
      ...env,
    });

  it("extracted the real step bodies (instrument self-check)", () => {
    expect(emit).toBeDefined();
    expect(enforce).toBeDefined();
    expect(emit!.run).toContain(MARKER);
    expect(cut).toContain("BLOCK=0");
    expect(cut.length).toBeGreaterThan(200);
    // If the cut anchor moves, `split` returns the whole body, which reaches the
    // Sentry curl: refuse that rather than rely on the env omitting the DSN.
    expect(cut).not.toContain("curl");
  });

  it("no step is named report-only, and the watcher's substring match still resolves", () => {
    expect(steps.filter((st) => /report-only/i.test(st.name ?? ""))).toEqual([]);
    expect(steps.filter((st) => (st.name ?? "").includes("Run live-verify harness"))).toHaveLength(1);
  });

  it("a REAL thrown breach reaches BLOCK=1 through emitLine (composition, not a typed literal)", async () => {
    const err = await verifyPrincipal(
      stubUser(baseConfig().expectedUid, EXPECTED_EMAIL, {
        ...COMPLIANT,
        api_keys: { data: [keyRow({ encrypted_key: "real" })], error: null },
      }),
      baseConfig(),
    ).catch((e: Error) => e);
    const line = emitLine({ kind: "CANT-RUN", reason: redact((err as Error).message) });
    expect(line).toMatch(/^RESULT: CANT-RUN:cannot-spend-violated: api_keys-non-sentinel-row$/);
    const r = classify(line);
    expect(r).toMatchObject({ status: 0, result: "CANT-RUN", level: "error", block: "1" });
    expect(r.stdout).toContain("::error title=live-verify cannot-spend check did not pass::");
  });

  it("a REAL could-not-check reaches BLOCK=0 with an ::error annotation (not a breach, not invisible)", async () => {
    const err = await verifyPrincipal(
      stubUser(baseConfig().expectedUid, EXPECTED_EMAIL, {
        ...COMPLIANT,
        api_keys: { data: [], error: null },
      }),
      baseConfig(),
    ).catch((e: Error) => e);
    const line = emitLine({ kind: "CANT-RUN", reason: redact((err as Error).message) });
    expect(line).toMatch(/^RESULT: CANT-RUN:cannot-spend-unverified: api_keys-empty$/);
    const r = classify(line);
    expect(r).toMatchObject({ status: 0, result: "CANT-RUN", level: "error", block: "0" });
    expect(r.stdout).toContain("::error title=live-verify cannot-spend check did not pass::");
  });

  it.each([
    "RESULT: CANT-RUN:cannot-spend",
    "RESULT: CANT-RUN:cannot-spendXviolated: x",
    " RESULT: CANT-RUN:cannot-spend-violated: x",
    "RESULT: CANT-RUN:CONFIG:cannot-spend-violated",
    "RESULT: PASS — cannot-spend-violated",
  ])("near-miss %j does not BLOCK", (line) => {
    expect(classify(line)).toMatchObject({ status: 0, block: "0" });
  });

  it.each([
    ["RESULT: PASS — fresh conversation persisted", { result: "PASS", block: "0" }],
    ["RESULT: FAIL — rail did not show the conversation", { result: "FAIL", block: "1" }],
    ["RESULT: CANT-RUN:session-rejected — rate_limited", { result: "CANT-RUN", block: "0" }],
    ["RESULT: CANT-RUN:browser-launch:Error", { result: "CANT-RUN", block: "0" }],
    ["", { result: "CANT-RUN:no-result-line", block: "1" }],
  ])("%j keeps its existing classification", (line, expected) => {
    expect(classify(line)).toMatchObject({ status: 0, ...expected });
  });

  it("pre-harness states keep their classification (SKIPPED, gate-diff-failed, setup-failed)", () => {
    expect(classify("x", { TRIGGERED: "0" })).toMatchObject({ result: "SKIPPED", block: "0" });
    expect(classify("x", { GATE_FAILED: "1" })).toMatchObject({ result: "CANT-RUN:gate-diff-failed", block: "0" });
    expect(classify("x", { TRIGGERED: undefined, GATE_FAILED: undefined })).toMatchObject({
      result: "CANT-RUN:setup-failed",
      block: "0",
    });
  });

  it("the Enforce step reads the emit step's block output, and exits 1 only on BLOCK=1", () => {
    // Wiring: renaming the output key silently fails the gate OPEN through
    // `${BLOCK:-0}`, so pin the mapping and execute the body both ways.
    expect(enforce!.env?.BLOCK).toBe("${{ steps.emit.outputs.block }}");
    expect(enforce!.env?.RESULT).toBe("${{ steps.emit.outputs.result }}");
    const red = run(enforce!.run!, { BLOCK: "1", RESULT: "CANT-RUN" });
    expect(red.status).toBe(1);
    expect(red.stdout).toContain("::error::");
    expect(run(enforce!.run!, { BLOCK: "0", RESULT: "PASS" }).status).toBe(0);
    expect(run(enforce!.run!, { RESULT: "PASS" }).status).toBe(0);
    expect(enforce!.run).toContain("ADR-064");
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
