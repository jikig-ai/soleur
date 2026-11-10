/**
 * #12429 (ADR-319 amendment 2026-11-08): GET /api/internal/legal-acceptance/[key]/counts. Behaviour tests for the check
 * order (503 token unset or malformed, 401, 400, 404, RPC), the closed response key set, `ok_to_flag`, the strict payload
 * parser (`hashCounts` in service.ts) and the store_failed reports (stage counts). The PUBLIC_PATHS entry and the
 * bearer-first rule for every handler under the prefix are in verify-route-census.test.ts, which walks this file too.
 * All fixtures are synthesized. The token below is a fixture, not a credential.
 */
import { afterAll, beforeEach, describe, expect, it, vi } from "vitest";
import { mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";

const TOKEN = "T".repeat(8) + "0123456789abcdef".repeat(3); // 56 chars, within the shape guard
const FOUNDER = "00000000-0000-4000-8000-0000000000aa";
const NOTE = "NOTE-SENTINEL-do-not-leak";

const h = vi.hoisted(() => ({
  rpc: vi.fn(),
  warnSink: vi.fn(),
  errSink: vi.fn(),
  texts: { dir: "" },
  serviceFactoryThrows: { value: false },
}));

vi.mock("@/server/observability", () => ({
  warnSilentFallback: (...a: unknown[]) => h.warnSink(...a),
  reportSilentFallback: (...a: unknown[]) => h.errSink(...a),
}));
vi.mock("@/lib/supabase/service", () => ({
  serverUrl: () => "https://fixture.supabase.invalid",
  createServiceClient: () => {
    if (h.serviceFactoryThrows.value) throw new Error("no service key");
    return { rpc: (...a: unknown[]) => h.rpc(...a) };
  },
}));
vi.mock("@/server/legal-acceptance/canonical", async (orig) => {
  const real = await orig<typeof import("@/server/legal-acceptance/canonical")>();
  return { ...real, getLegalText: (key: string) => real.getLegalText(key, h.texts.dir) };
});

import { GET } from "@/app/api/internal/legal-acceptance/[key]/counts/route";
import { getLegalText } from "@/server/legal-acceptance/canonical";
import { HASH_COUNTS_MAX_ROWS, hashCounts, LegalServiceError } from "@/server/legal-acceptance/service";

const dir = mkdtempSync(path.join(tmpdir(), "counts-route-"));
writeFileSync(path.join(dir, "fixture-terms.md"), "---\nversion: fx-1\n---\nSynthesized fixture text.\n");
mkdirSync(path.join(dir, "unreadable-key.md")); // a directory where the file should be: a read error that is not ENOENT
h.texts.dir = dir;
afterAll(() => rmSync(dir, { recursive: true, force: true }));
const HASH = getLegalText("fixture-terms").textHash;
const OTHER = "c".repeat(64);
const OTHER2 = "d".repeat(64);

const counts = (by: Array<[string, number]>, total?: number) => ({
  data: { total: total ?? by.reduce((n, [, c]) => n + c, 0), by_hash: by.map(([text_hash, count]) => ({ text_hash, count })) },
  error: null,
});
const EMPTY = { data: { total: 0, by_hash: [] }, error: null };

function call(o: { key?: string; auth?: string | null; method?: string } = {}) {
  const key = o.key ?? "fixture-terms";
  const headers: Record<string, string> = {};
  if (o.auth !== null) headers.authorization = o.auth ?? `Bearer ${TOKEN}`;
  const req = new Request(`https://app.soleur.ai/api/internal/legal-acceptance/${key}/counts`, { headers });
  return GET(req, { params: Promise.resolve({ key }) });
}
const read = async (r: Response) => ({ status: r.status, body: await r.json(), cache: r.headers.get("cache-control") });
const events = (): Array<{ op: string; level: "warn" | "error"; tags?: Record<string, string>; extra?: Record<string, unknown> }> =>
  [
    ...h.warnSink.mock.calls.map((c) => ({ ...(c[1] as object), level: "warn" as const })),
    ...h.errSink.mock.calls.map((c) => ({ ...(c[1] as object), level: "error" as const })),
  ] as never;
const ops = () => events().map((e) => e.op);

beforeEach(() => {
  vi.unstubAllEnvs();
  vi.stubEnv("LEGAL_ACCEPTANCE_VERIFY_TOKEN", TOKEN);
  vi.stubEnv("LEGAL_ACCEPTANCE_FOUNDER_ID", ""); // the counts route needs no founder id: it must work (and stay silent) without one
  h.rpc.mockReset();
  h.warnSink.mockReset();
  h.errSink.mockReset();
  h.serviceFactoryThrows.value = false;
  h.rpc.mockImplementation(async (fn: string) => {
    if (fn === "legal_acceptance_hash_counts") return EMPTY;
    throw new Error(`unexpected rpc ${fn}`);
  });
});

describe("503: dark and fail-closed", () => {
  it("token unset or empty is 503 with no detail, silent, and nothing is called", async () => {
    for (const t of ["", undefined]) {
      vi.stubEnv("LEGAL_ACCEPTANCE_VERIFY_TOKEN", t as string);
      const out = await read(await call());
      expect(out.status).toBe(503);
      expect(out.body).toEqual({ error: "Not available" });
    }
    expect(h.rpc).not.toHaveBeenCalled();
    expect(ops()).toEqual([]);
  });
  it("a malformed configured token (short, long, whitespace, quote) is 503 even with the matching bearer, and nothing is called", async () => {
    for (const bad of ["short", "y".repeat(47), "y".repeat(257), `${TOKEN}\n`, `${TOKEN} x`, `${TOKEN}"`]) {
      vi.stubEnv("LEGAL_ACCEPTANCE_VERIFY_TOKEN", bad);
      expect((await call({ auth: `Bearer ${bad}` })).status, JSON.stringify(bad)).toBe(503);
    }
    expect(h.rpc).not.toHaveBeenCalled();
  });
  it("a malformed token is reported once per route module (store_failed stage config, variable name only)", async () => {
    vi.resetModules();
    const { GET: fresh } = await import("@/app/api/internal/legal-acceptance/[key]/counts/route");
    vi.stubEnv("LEGAL_ACCEPTANCE_VERIFY_TOKEN", "x".repeat(47));
    for (let i = 0; i < 3; i++) {
      const r = await fresh(new Request("https://app.soleur.ai/api/internal/legal-acceptance/fixture-terms/counts"), { params: Promise.resolve({ key: "fixture-terms" }) });
      expect(r.status).toBe(503);
    }
    const cfg = events().filter((e) => e.op === "store_failed" && e.tags?.stage === "config");
    expect(cfg).toHaveLength(1);
    expect(cfg[0].extra).toMatchObject({ step: "config", variables: ["LEGAL_ACCEPTANCE_VERIFY_TOKEN"] });
    expect(JSON.stringify(cfg[0])).not.toContain("x".repeat(10));
  });
  it("the token is read from LEGAL_ACCEPTANCE_VERIFY_TOKEN only, never from the Inngest secret", async () => {
    vi.stubEnv("LEGAL_ACCEPTANCE_VERIFY_TOKEN", "");
    vi.stubEnv("INNGEST_MANUAL_TRIGGER_SECRET", TOKEN);
    expect((await call()).status).toBe(503);
  });
  it("a founder id in configuration is irrelevant: the route works without one and a malformed one is not read", async () => {
    vi.stubEnv("LEGAL_ACCEPTANCE_FOUNDER_ID", "not-a-uuid");
    h.rpc.mockResolvedValue(EMPTY);
    expect((await call()).status).toBe(200);
    expect(ops()).toEqual([]);
  });
});

describe("401, 400, 404 order", () => {
  it("a wrong token, absent header, prefix, suffix and empty bearer are 401 and make zero RPC calls", async () => {
    for (const auth of [`Bearer ${TOKEN}x`, `Bearer ${TOKEN.slice(0, -1)}`, "Bearer wrong", "Bearer ", "", null, `Basic ${TOKEN}`, `Bearer ${TOKEN},${TOKEN}`]) {
      const out = await read(await call({ auth }));
      expect(out.status, JSON.stringify(auth)).toBe(401);
      expect(out.body).toEqual({ error: "Unauthorized" });
    }
    expect(h.rpc).not.toHaveBeenCalled();
  });
  it("a wrong token on a malformed or unknown key is still 401 (auth first, an unauthenticated caller learns nothing)", async () => {
    expect((await call({ auth: "Bearer wrong", key: "Bad_Key" })).status).toBe(401);
    expect((await call({ auth: "Bearer wrong", key: "no-such-key" })).status).toBe(401);
    expect((await call({ auth: "Bearer wrong", key: "unreadable-key" })).status).toBe(401);
    expect(ops()).toEqual([]);
  });
  it("a malformed key is 400 and nothing is looked up", async () => {
    for (const key of ["Bad_Key", "-leading", "UPPER", "a".repeat(64), "has.dot"]) {
      expect((await call({ key })).status, key).toBe(400);
    }
    expect(h.rpc).not.toHaveBeenCalled();
  });
  it("a key that is well formed but not in the registry is 404 and the database is not reached", async () => {
    const out = await read(await call({ key: "no-such-key" }));
    expect(out).toMatchObject({ status: 404, body: { error: "Not found" } });
    expect(h.rpc).not.toHaveBeenCalled();
  });
  it("a registry read failure (not a missing file) is 503 and reported as store_failed stage registry, never 404", async () => {
    const out = await read(await call({ key: "unreadable-key" }));
    expect(out.status).toBe(503);
    expect(h.rpc).not.toHaveBeenCalled();
    expect(events().map((e) => [e.op, e.tags])).toEqual([["store_failed", { stage: "registry" }]]);
  });
});

describe("200: the closed payload and ok_to_flag", () => {
  const KEYS = ["by_hash", "key", "ok_to_flag", "registry_hash", "total"];
  it("zero rows: total 0, empty by_hash, ok_to_flag true (vacuous: the helper labels this production-table-only)", async () => {
    h.rpc.mockResolvedValue(EMPTY);
    const out = await read(await call());
    expect(out.status).toBe(200);
    expect(out.body).toEqual({ key: "fixture-terms", registry_hash: HASH, total: 0, by_hash: [], ok_to_flag: true });
    expect(out.cache).toBe("no-store");
  });
  it("one row under the registry hash: ok_to_flag true", async () => {
    h.rpc.mockResolvedValue(counts([[HASH, 1]]));
    expect((await read(await call())).body).toEqual({ key: "fixture-terms", registry_hash: HASH, total: 1, by_hash: [{ text_hash: HASH, count: 1 }], ok_to_flag: true });
  });
  it("one row under another hash: ok_to_flag false", async () => {
    h.rpc.mockResolvedValue(counts([[OTHER, 1]]));
    expect((await read(await call())).body).toMatchObject({ total: 1, ok_to_flag: false });
  });
  it("the registry hash plus any other hash: ok_to_flag false", async () => {
    h.rpc.mockResolvedValue(counts([[OTHER, 2], [HASH, 1]].sort((a, b) => (a[0] < b[0] ? -1 : 1)) as Array<[string, number]>));
    expect((await read(await call())).body).toMatchObject({ total: 3, ok_to_flag: false });
  });
  it("ok_to_flag is judged over EVERY entry: a foreign hash that sorts before, after, or between registry rows is still false", async () => {
    const BEFORE = "0".repeat(64);
    const AFTER = "f".repeat(64);
    expect([BEFORE < HASH, HASH < AFTER]).toEqual([true, true]); // the fixture really orders the foreign hashes around the registry hash
    for (const by of [[[BEFORE, 1], [HASH, 1]], [[HASH, 1], [AFTER, 1]], [[BEFORE, 1], [HASH, 1], [AFTER, 1]], [[BEFORE, 1]], [[AFTER, 1]]] as Array<Array<[string, number]>>) {
      h.rpc.mockResolvedValue(counts(by));
      expect((await read(await call())).body.ok_to_flag, by.map(([x]) => x.slice(0, 2)).join(",")).toBe(false);
    }
    h.rpc.mockResolvedValue(counts([[HASH, 5]]));
    expect((await read(await call())).body.ok_to_flag).toBe(true);
  });
  it("the response has exactly the five documented keys, whatever the database returns", async () => {
    h.rpc.mockResolvedValue(counts([[HASH, 1]]));
    expect(Object.keys((await read(await call())).body).sort()).toEqual(KEYS);
  });
  it("the RPC is called with the key asked about and nothing else, and no founder id", async () => {
    h.rpc.mockResolvedValue(EMPTY);
    await call();
    expect(h.rpc.mock.calls).toEqual([["legal_acceptance_hash_counts", { p_key: "fixture-terms" }]]);
  });
  it("a response never carries a founder id, a choice, a timestamp or the note, even if the database row did", async () => {
    h.rpc.mockResolvedValue({ data: { total: 1, by_hash: [{ text_hash: HASH, count: 1, founder_id: FOUNDER, requested_edit: NOTE }], founder_id: FOUNDER }, error: null });
    const out = await read(await call());
    // A payload that is not the documented shape is a bad gateway, never a partial 200.
    expect(out.status).toBe(502);
    const everything = JSON.stringify([out, h.rpc.mock.calls, h.warnSink.mock.calls, h.errSink.mock.calls]);
    expect(everything).not.toContain(NOTE);
    expect(everything).not.toContain(FOUNDER);
    expect(everything).not.toMatch(/requested_edit|founder_id|choice|created_at/);
  });
});

describe("failures are never a partial 200 (store_failed stage counts)", () => {
  const countsEvents = () => events().filter((e) => e.op === "store_failed" && e.tags?.stage === "counts");
  it("an RPC error is 503, one store_failed stage counts, and the body is generic", async () => {
    h.rpc.mockResolvedValue({ data: null, error: { message: "boom p_key=fixture-terms", code: "42883" } });
    const out = await read(await call());
    expect(out).toMatchObject({ status: 503, body: { error: "Not available" } });
    expect(countsEvents()).toHaveLength(1);
    expect(countsEvents()[0].level).toBe("error");
    expect(countsEvents()[0].extra).toMatchObject({ key: "fixture-terms", step: "counts" });
    expect(JSON.stringify(out.body)).not.toContain("boom");
  });
  it("the 54000 'too many distinct hashes' refusal is the same 503 body, but its report carries the static reason too_many_hashes (and nothing else distinguishes it)", async () => {
    h.rpc.mockResolvedValue({ data: null, error: { message: "legal acceptance: too many distinct hashes p_key=fixture-terms", code: "54000" } });
    const out = await read(await call());
    expect(out).toMatchObject({ status: 503, body: { error: "Not available" } });
    expect(countsEvents()).toHaveLength(1);
    expect(countsEvents()[0].extra).toMatchObject({ key: "fixture-terms", step: "counts", code: "54000", reason: "too_many_hashes" });
    expect(JSON.stringify(events())).not.toMatch(/p_key|too many distinct/);
    // every other failure keeps no reason: migration-not-applied (42883), a thrown call, a bad payload
    for (const res of [{ data: null, error: { message: "x", code: "42883" } }, { data: { total: -1, by_hash: [] }, error: null }]) {
      h.errSink.mockReset();
      h.rpc.mockResolvedValue(res);
      await call();
      expect(countsEvents()).toHaveLength(1);
      expect(countsEvents()[0].extra).not.toHaveProperty("reason");
    }
    h.errSink.mockReset();
    h.rpc.mockRejectedValue(new Error("network"));
    await call();
    expect(countsEvents()[0].extra).not.toHaveProperty("reason");
  });
  it("an RPC that throws, and a service client that cannot be built, are 503 with one report", async () => {
    h.rpc.mockRejectedValue(new Error("network"));
    expect((await call()).status).toBe(503);
    expect(countsEvents()).toHaveLength(1);
    h.errSink.mockReset();
    h.serviceFactoryThrows.value = true;
    expect((await call()).status).toBe(503);
    expect(countsEvents()).toHaveLength(1);
  });
  it("a missing function (migration 186 not applied) is 503, never 500", async () => {
    h.rpc.mockResolvedValue({ data: null, error: { message: "function public.legal_acceptance_hash_counts(text) does not exist", code: "42883" } });
    expect((await call()).status).toBe(503);
  });
  it.each([
    ["not an object", null],
    ["an array", []],
    ["total missing", { by_hash: [] }],
    ["an extra key", { total: 0, by_hash: [], extra: 1 }],
    ["total negative", { total: -1, by_hash: [] }],
    ["total a float", { total: 0.5, by_hash: [] }],
    ["total a string", { total: "1", by_hash: [] }],
    ["by_hash not an array", { total: 0, by_hash: {} }],
    ["counts that do not sum to total", { total: 3, by_hash: [{ text_hash: HASH, count: 1 }] }],
    ["a zero count", { total: 0, by_hash: [{ text_hash: HASH, count: 0 }] }],
    ["a float count", { total: 1, by_hash: [{ text_hash: HASH, count: 1.5 }] }],
    ["a malformed hash", { total: 1, by_hash: [{ text_hash: "zz", count: 1 }] }],
    ["an uppercase hash", { total: 1, by_hash: [{ text_hash: "A".repeat(64), count: 1 }] }],
    ["an extra key on a row", { total: 1, by_hash: [{ text_hash: HASH, count: 1, choice: "accept" }] }],
    ["a missing key on a row", { total: 1, by_hash: [{ text_hash: HASH }] }],
    ["a duplicate hash", { total: 2, by_hash: [{ text_hash: HASH, count: 1 }, { text_hash: HASH, count: 1 }] }],
    ["unsorted hashes", { total: 2, by_hash: [{ text_hash: OTHER2, count: 1 }, { text_hash: OTHER, count: 1 }] }],
    ["rows beyond the cap", { total: HASH_COUNTS_MAX_ROWS + 1, by_hash: Array.from({ length: HASH_COUNTS_MAX_ROWS + 1 }, (_, i) => ({ text_hash: i.toString(16).padStart(64, "0"), count: 1 })) }],
  ])("a malformed payload (%s) is 502 and one report", async (_label, data) => {
    h.rpc.mockResolvedValue({ data, error: null });
    const out = await read(await call());
    expect(out).toMatchObject({ status: 502, body: { error: "Bad gateway" } });
    expect(countsEvents()).toHaveLength(1);
  });
});

describe("hashCounts parser (service.ts)", () => {
  const client = (data: unknown, error: { message: string; code?: string } | null = null) => ({ rpc: vi.fn(async () => ({ data, error })) });
  it("accepts the documented shape and rebuilds it from the closed fields", async () => {
    expect(await hashCounts(client({ total: 3, by_hash: [{ text_hash: OTHER, count: 1 }, { text_hash: OTHER2, count: 2 }] }), { key: "k" })).toEqual({
      total: 3,
      by_hash: [{ text_hash: OTHER, count: 1 }, { text_hash: OTHER2, count: 2 }],
    });
    expect(await hashCounts(client({ total: 0, by_hash: [] }), { key: "k" })).toEqual({ total: 0, by_hash: [] });
  });
  it("accepts exactly the cap and refuses one more", async () => {
    const rows = (n: number) => Array.from({ length: n }, (_, i) => ({ text_hash: i.toString(16).padStart(64, "0"), count: 1 }));
    await expect(hashCounts(client({ total: HASH_COUNTS_MAX_ROWS, by_hash: rows(HASH_COUNTS_MAX_ROWS) }), { key: "k" })).resolves.toMatchObject({ total: HASH_COUNTS_MAX_ROWS });
    await expect(hashCounts(client({ total: HASH_COUNTS_MAX_ROWS + 1, by_hash: rows(HASH_COUNTS_MAX_ROWS + 1) }), { key: "k" })).rejects.toMatchObject({ code: "bad_payload" });
  });
  it("refuses numbers that are integers only by arithmetic accident: a fractional count pair summing to total, and a total above 2^53 formed from safe counts", async () => {
    // 1.5 + 1.5 === 3: the sum check alone would pass; the per-count integer guard must refuse.
    await expect(hashCounts(client({ total: 3, by_hash: [{ text_hash: OTHER, count: 1.5 }, { text_hash: OTHER2, count: 1.5 }] }), { key: "k" })).rejects.toMatchObject({ code: "bad_payload" });
    // (2^53 - 1) + 1 === 2^53: every count is a safe integer and the sum matches, so only the total's own guard refuses.
    await expect(hashCounts(client({ total: 2 ** 53, by_hash: [{ text_hash: OTHER, count: 2 ** 53 - 1 }, { text_hash: OTHER2, count: 1 }] }), { key: "k" })).rejects.toMatchObject({ code: "bad_payload" });
    await expect(hashCounts(client({ total: 2 ** 53 - 1, by_hash: [{ text_hash: OTHER, count: 2 ** 53 - 2 }, { text_hash: OTHER2, count: 1 }] }), { key: "k" })).resolves.toMatchObject({ total: 2 ** 53 - 1 });
  });
  it("a negative total over an empty list is refused (the sum check already covers it, so no separate sign clause exists)", async () => {
    await expect(hashCounts(client({ total: -1, by_hash: [] }), { key: "k" })).rejects.toMatchObject({ code: "bad_payload" });
  });
  it("an RPC error carries the SQLSTATE and a static message (never database text)", async () => {
    const err = await hashCounts(client(null, { message: "secret row text founder_id=abc", code: "42501" }), { key: "k" }).catch((e) => e);
    expect(err).toBeInstanceOf(LegalServiceError);
    expect(err.code).toBe("42501");
    expect(err.message).toBe("legal acceptance rpc failed: legal_acceptance_hash_counts");
  });
});

describe("source pins", () => {
  const WEB = path.join(__dirname, "../..");
  const countsSrc = readFileSync(path.join(WEB, "app/api/internal/legal-acceptance/[key]/counts/route.ts"), "utf8");
  const verifySrc = readFileSync(path.join(WEB, "app/api/internal/legal-acceptance/[key]/route.ts"), "utf8");
  const tokenLine = (s: string) => /^const TOKEN_RE = .*;$/m.exec(s)?.[0];
  it("the counts route's TOKEN_RE line is byte-identical to the verify route's (the two must never drift: one token, one shape)", () => {
    expect(tokenLine(verifySrc)).toBeDefined();
    expect(tokenLine(countsSrc)).toBe(tokenLine(verifySrc));
  });
  it("the route exports exactly GET and dynamic (HTTP-only exports; a write path would re-open the privacy review)", () => {
    const exports = [...countsSrc.matchAll(/^export (?:async )?(?:function|const) (\w+)/gm)].map((m) => m[1]).sort();
    expect(exports).toEqual(["GET", "dynamic"]);
  });
  it("the route reads the token through the named reader and never the Inngest secret", () => {
    expect(countsSrc).toContain('readNamedBearerSecret("LEGAL_ACCEPTANCE_VERIFY_TOKEN")');
    expect(countsSrc).not.toMatch(/INNGEST_MANUAL_TRIGGER_SECRET/);
  });
  it("the route emits storeFailed with a literal tags: { stage: \"counts\" } (the op-contract census reads this call site)", () => {
    expect(countsSrc).toMatch(/tags:\s*\{\s*stage:\s*"counts"\s*\}/);
  });
});
