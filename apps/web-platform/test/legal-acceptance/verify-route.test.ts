/**
 * #12011 PR-D Guard 2: GET /api/internal/legal-acceptance/[key]?hash=. Behaviour tests for the check order
 * (503, 401, 400, 404, lookup), the four-field body, `invalid` pass-through, the closed status set, the founder id
 * from configuration only, and the narrow PUBLIC_PATHS entry through the middleware predicate.
 * All fixtures are synthesized. The token and the founder id below are fixtures, not credentials.
 */
import { afterAll, beforeEach, describe, expect, it, vi } from "vitest";
import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";

const FOUNDER = "00000000-0000-4000-8000-0000000000aa";
const ATTACKER = "00000000-0000-4000-8000-0000000000bb";
const TOKEN = "T".repeat(8) + "0123456789abcdef".repeat(3); // 56 chars, within the shape guard
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

import { GET } from "@/app/api/internal/legal-acceptance/[key]/route";
import { getLegalText } from "@/server/legal-acceptance/canonical";
import { VERIFY_ENDPOINT_STATUSES } from "@/server/legal-acceptance/service";
import { PUBLIC_PATHS } from "@/lib/routes";

const dir = mkdtempSync(path.join(tmpdir(), "verify-route-"));
writeFileSync(path.join(dir, "fixture-terms.md"), "---\nversion: fx-1\n---\nSynthesized fixture text.\n");
writeFileSync(path.join(dir, `${"k".repeat(63)}.md`), "---\nversion: fx-1\n---\nlimit key.\n");
mkdirSync(path.join(dir, "unreadable-key.md")); // a directory where the file should be: a read error that is not ENOENT
h.texts.dir = dir;
afterAll(() => rmSync(dir, { recursive: true, force: true }));
const HASH = getLegalText("fixture-terms").textHash;
const WHEN = "2026-11-05T10:00:00.000Z";

const verifyRow = (status: string, over: Record<string, unknown> = {}) => ({
  data: { status, text_hash: HASH, decided_at: WHEN, row_ok: status === "invalid" ? false : true, ...over },
  error: null,
});
const NONE = { data: { status: "none", text_hash: HASH, decided_at: null, row_ok: null }, error: null };
const ACKED = { data: { outcome: "row", acked: true, age_seconds: 5000 }, error: null };

/** Route the two RPCs this endpoint may call. Anything else is a test failure (the harness refuses unknown functions). */
function stubRpc(o: { verify?: unknown; ackState?: unknown } = {}) {
  h.rpc.mockImplementation(async (fn: string) => {
    if (fn === "verify_legal_acceptance") return o.verify ?? verifyRow("accepted");
    if (fn === "legal_acceptance_ack_state") return o.ackState ?? ACKED;
    throw new Error(`unexpected rpc ${fn}`);
  });
}

function call(o: { key?: string; hash?: string | null; auth?: string | null; query?: string } = {}) {
  const key = o.key ?? "fixture-terms";
  const hash = o.hash === undefined ? HASH : o.hash;
  const qs = (hash === null ? "" : `hash=${hash}`) + (o.query ? `${hash === null ? "" : "&"}${o.query}` : "");
  const headers: Record<string, string> = {};
  if (o.auth !== null) headers.authorization = o.auth ?? `Bearer ${TOKEN}`;
  const req = new Request(`https://app.soleur.ai/api/internal/legal-acceptance/${key}${qs ? `?${qs}` : ""}`, { headers });
  return GET(req, { params: Promise.resolve({ key }) });
}
const read = async (r: Response) => ({ status: r.status, body: await r.json(), cache: r.headers.get("cache-control") });
const events = (): Array<{ op: string; level: "warn" | "error"; tags?: Record<string, string>; extra?: Record<string, unknown> }> => [
  ...h.warnSink.mock.calls.map((c) => ({ ...(c[1] as object), level: "warn" as const })),
  ...h.errSink.mock.calls.map((c) => ({ ...(c[1] as object), level: "error" as const })),
] as never;
const ops = () => events().map((e) => e.op);

beforeEach(() => {
  vi.unstubAllEnvs();
  vi.stubEnv("LEGAL_ACCEPTANCE_VERIFY_TOKEN", TOKEN);
  vi.stubEnv("LEGAL_ACCEPTANCE_FOUNDER_ID", FOUNDER);
  h.rpc.mockReset();
  h.warnSink.mockReset();
  h.errSink.mockReset();
  h.serviceFactoryThrows.value = false;
  stubRpc();
});

describe("503: dark and fail-closed (Guard 2 row 2, scenario 1)", () => {
  it("no configuration at all is 503 with no detail in the body, and nothing is called", async () => {
    vi.stubEnv("LEGAL_ACCEPTANCE_VERIFY_TOKEN", "");
    vi.stubEnv("LEGAL_ACCEPTANCE_FOUNDER_ID", "");
    const out = await read(await call());
    expect(out.status).toBe(503);
    expect(Object.keys(out.body)).toEqual(["error"]);
    expect(h.rpc).not.toHaveBeenCalled();
  });
  it("token set but founder id unset or malformed is 503, even with the right bearer", async () => {
    for (const bad of ["", "not-a-uuid", `${FOUNDER} `, FOUNDER.slice(1), `${FOUNDER}0`]) {
      vi.stubEnv("LEGAL_ACCEPTANCE_FOUNDER_ID", bad);
      expect((await call()).status, JSON.stringify(bad)).toBe(503);
    }
    expect(h.rpc).not.toHaveBeenCalled();
  });
  it("founder id set but token unset is 503 (not 401), and an empty token is unset (row 3)", async () => {
    vi.stubEnv("LEGAL_ACCEPTANCE_VERIFY_TOKEN", "");
    expect((await call()).status).toBe(503);
    expect((await call({ auth: "" })).status).toBe(503);
    expect((await call({ auth: "Bearer " })).status).toBe(503);
    expect((await call({ auth: null })).status).toBe(503);
  });
  it("a malformed configured token (whitespace, too short) is 503, never a working credential", async () => {
    for (const bad of ["short", `${TOKEN}\n`, `${TOKEN} x`, `${TOKEN}"`]) {
      vi.stubEnv("LEGAL_ACCEPTANCE_VERIFY_TOKEN", bad);
      expect((await call({ auth: `Bearer ${bad}` })).status, JSON.stringify(bad)).toBe(503);
    }
    expect(h.rpc).not.toHaveBeenCalled();
  });
  it("the configured token is read from LEGAL_ACCEPTANCE_VERIFY_TOKEN only, never from the Inngest secret", async () => {
    vi.stubEnv("LEGAL_ACCEPTANCE_VERIFY_TOKEN", "");
    vi.stubEnv("INNGEST_MANUAL_TRIGGER_SECRET", TOKEN);
    expect((await call()).status).toBe(503);
  });
  it("a registry read failure (not a missing file) is 503, never 404 (row 7)", async () => {
    const out = await read(await call({ key: "unreadable-key" }));
    expect(out.status).toBe(503);
    expect(h.rpc).not.toHaveBeenCalled();
    expect(ops()).toEqual([]); // nothing about a database was reported: the database was not reached
  });
});

describe("401: the token is checked before any lookup (rows 1, 2, 8)", () => {
  it("a wrong token, an absent header, a prefix, a suffix and an empty bearer are 401 and make zero RPC calls", async () => {
    for (const auth of [`Bearer ${TOKEN}x`, `Bearer ${TOKEN.slice(0, -1)}`, "Bearer wrong", "Bearer ", "", null, `Basic ${TOKEN}`, `Bearer ${TOKEN},${TOKEN}`]) {
      const out = await read(await call({ auth }));
      expect(out.status, JSON.stringify(auth)).toBe(401);
      expect(out.body).toEqual({ error: "Unauthorized" });
    }
    expect(h.rpc).not.toHaveBeenCalled();
  });
  it("a wrong token on a malformed key or hash is still 401, not 400 or 404 (auth first)", async () => {
    expect((await call({ auth: "Bearer wrong", key: "Bad_Key" })).status).toBe(401);
    expect((await call({ auth: "Bearer wrong", hash: "zz" })).status).toBe(401);
    expect((await call({ auth: "Bearer wrong", key: "no-such-key" })).status).toBe(401);
  });
  it("a right token earlier does not make a later wrong token pass (exactly one configured token)", async () => {
    expect((await call()).status).toBe(200);
    expect((await call({ auth: "Bearer wrong-token-after-a-right-one" })).status).toBe(401);
    expect((await call()).status).toBe(200);
  });
  it("the bare token without the Bearer prefix is accepted (the shared helper accepts both)", async () => {
    expect((await call({ auth: TOKEN })).status).toBe(200);
  });
});

describe("400 and 404 (rows 7, scenario 4)", () => {
  it("a malformed key or hash is 400 and nothing is looked up", async () => {
    for (const key of ["Bad_Key", "-leading", "UPPER", "a".repeat(64), "has.dot"]) {
      expect((await call({ key })).status, key).toBe(400);
    }
    for (const hash of [null, "", "A".repeat(64), "a".repeat(63), "a".repeat(65), "g".repeat(64), ` ${"a".repeat(63)}`]) {
      expect((await call({ hash })).status, JSON.stringify(hash)).toBe(400);
    }
    expect((await call({ query: `hash=${HASH}` })).status, "hash given twice").toBe(400);
    expect(h.rpc).not.toHaveBeenCalled();
  });
  it("a key that is well formed but not in the registry is 404, never a 200 none", async () => {
    const out = await read(await call({ key: "no-such-key" }));
    expect(out).toMatchObject({ status: 404 });
    expect(out.body).toEqual({ error: "Not found" });
    expect(h.rpc).not.toHaveBeenCalled();
  });
  it("a key at the 63-character limit is accepted and one at 64 is refused", async () => {
    const k63 = "k".repeat(63);
    stubRpc();
    expect((await call({ key: k63 })).status).toBe(200);
    expect((await call({ key: "k".repeat(64) })).status).toBe(400);
  });
  it("a hash that is not the registry's current hash is answered from the database, not rejected", async () => {
    const stale = "c".repeat(64);
    stubRpc({ verify: { data: { status: "none", text_hash: stale, decided_at: null, row_ok: null }, error: null } });
    const out = await read(await call({ hash: stale }));
    expect(out).toMatchObject({ status: 200, body: { status: "none", text_hash: stale } });
  });
});

describe("200: exactly four keys, whatever the database returns (row 4, scenario 3)", () => {
  it.each(["accepted", "declined", "changes_requested"] as const)("%s is answered with status, text_hash, decided_at, row_ok and nothing else", async (status) => {
    stubRpc({ verify: verifyRow(status) });
    const out = await read(await call());
    expect(out.status).toBe(200);
    expect(out.body).toEqual({ status, text_hash: HASH, decided_at: WHEN, row_ok: true });
    expect(out.cache).toBe("no-store");
  });
  it("none answers null decided_at and null row_ok, and makes no ack_state call (no row, no gap)", async () => {
    stubRpc({ verify: NONE });
    expect(await read(await call())).toMatchObject({ status: 200, body: { status: "none", text_hash: HASH, decided_at: null, row_ok: null } });
    expect(h.rpc.mock.calls.map((c) => c[0])).toEqual(["verify_legal_acceptance"]);
    expect(ops()).not.toContain("row_without_event");
  });
  it("the note is in no response, no RPC argument and no Sentry payload, even if the database row carried it (AC3, scenario 10)", async () => {
    stubRpc({ verify: verifyRow("changes_requested", { requested_edit: NOTE, note: NOTE }) });
    const out = await read(await call());
    expect(Object.keys(out.body).sort()).toEqual(["decided_at", "row_ok", "status", "text_hash"]);
    const everything = JSON.stringify([out, h.rpc.mock.calls, h.warnSink.mock.calls, h.errSink.mock.calls]);
    expect(everything).not.toContain(NOTE);
    expect(everything).not.toMatch(/requested_edit/);
  });
  it("the founder id comes only from configuration: a query value or a header cannot change it (row 5)", async () => {
    const req = new Request(`https://app.soleur.ai/api/internal/legal-acceptance/fixture-terms?hash=${HASH}&founder_id=${ATTACKER}&p_founder_id=${ATTACKER}`, {
      headers: { authorization: `Bearer ${TOKEN}`, "x-founder-id": ATTACKER, "x-user-id": ATTACKER },
    });
    expect((await GET(req, { params: Promise.resolve({ key: "fixture-terms" }) })).status).toBe(200);
    for (const c of h.rpc.mock.calls) expect((c[1] as Record<string, unknown>).p_founder_id).toBe(FOUNDER);
    expect(JSON.stringify(h.rpc.mock.calls)).not.toContain(ATTACKER);
  });
  it("an uppercase founder id in configuration is passed lowercase", async () => {
    vi.stubEnv("LEGAL_ACCEPTANCE_FOUNDER_ID", FOUNDER.toUpperCase());
    expect((await call()).status).toBe(200);
    expect((h.rpc.mock.calls[0][1] as Record<string, unknown>).p_founder_id).toBe(FOUNDER);
  });
});

describe("invalid is never collapsed into none (row 6, AC2)", () => {
  it("passes through as invalid with row_ok false and emits record_invalid (error)", async () => {
    stubRpc({ verify: verifyRow("invalid") });
    const out = await read(await call());
    expect(out).toMatchObject({ status: 200, body: { status: "invalid", text_hash: HASH, decided_at: WHEN, row_ok: false } });
    const ev = events().filter((e) => e.op === "record_invalid");
    expect(ev).toHaveLength(1);
    expect(ev[0].level).toBe("error");
  });
  it("an invalid row whose payload says row_ok true is not a status: 502, never a 200 or a none", async () => {
    stubRpc({ verify: verifyRow("invalid", { row_ok: true }) });
    expect((await call()).status).toBe(502);
  });
  it("a row that is not invalid never emits record_invalid", async () => {
    await call();
    expect(ops()).not.toContain("record_invalid");
  });
});

describe("store failures are never a 200 (scenario 3)", () => {
  const stage = (): string | undefined => events().find((e) => e.op === "store_failed")?.tags?.stage;
  it("an unrecognised verify payload is 502 with store_failed stage verify", async () => {
    for (const verify of [verifyRow("pending"), verifyRow("accepted", { text_hash: "d".repeat(64) }), { data: null, error: null }, { data: "ok", error: null }, { data: { outcome: "accepted" }, error: null }]) {
      h.errSink.mockReset();
      stubRpc({ verify });
      expect((await call()).status, JSON.stringify(verify)).toBe(502);
      expect(stage()).toBe("verify");
    }
  });
  it("a verify RPC error, a thrown rpc and a failing service client are 503 with store_failed stage verify", async () => {
    stubRpc({ verify: { data: null, error: { message: `row echo ${NOTE}`, code: "XX000" } } });
    expect((await call()).status).toBe(503);
    expect(stage()).toBe("verify");
    h.errSink.mockReset();
    h.rpc.mockImplementation(async () => {
      throw new Error("network");
    });
    expect((await call()).status).toBe(503);
    expect(stage()).toBe("verify");
    h.errSink.mockReset();
    h.serviceFactoryThrows.value = true;
    expect((await call()).status).toBe(503);
    expect(stage()).toBe("verify");
    expect(JSON.stringify([h.errSink.mock.calls, h.warnSink.mock.calls])).not.toContain(NOTE);
  });
  it("an ack_state RPC error is 503 and an unrecognised ack_state payload is 502, both store_failed stage ack_state", async () => {
    stubRpc({ ackState: { data: null, error: { message: "x", code: "XX000" } } });
    expect((await call()).status).toBe(503);
    expect(stage()).toBe("ack_state");
    for (const ackState of [{ data: { outcome: "row", acked: "no", age_seconds: 500 }, error: null }, { data: { outcome: "none" }, error: null }, { data: { outcome: "weird" }, error: null }]) {
      h.errSink.mockReset();
      stubRpc({ ackState });
      expect((await call()).status, JSON.stringify(ackState)).toBe(502);
      expect(stage()).toBe("ack_state");
    }
  });
});

describe("the status set is closed and declared once", () => {
  it("every status the route produced across all cases is in VERIFY_ENDPOINT_STATUSES, and the set is exactly 200, 400, 401, 404, 502, 503", async () => {
    expect([...VERIFY_ENDPOINT_STATUSES].sort()).toEqual([200, 400, 401, 404, 502, 503]);
    const seen = new Set<number>();
    const run = async (p: Promise<Response>) => seen.add((await p).status);
    await run(call());
    await run(call({ auth: "Bearer x" }));
    await run(call({ key: "Bad_Key" }));
    await run(call({ key: "no-such-key" }));
    await run(call({ key: "unreadable-key" }));
    stubRpc({ verify: verifyRow("bogus") });
    await run(call());
    stubRpc({ verify: { data: null, error: { message: "x" } } });
    await run(call());
    vi.stubEnv("LEGAL_ACCEPTANCE_VERIFY_TOKEN", "");
    await run(call());
    expect([...seen].sort()).toEqual([200, 400, 401, 404, 502, 503]);
    for (const s of seen) expect(VERIFY_ENDPOINT_STATUSES as readonly number[]).toContain(s);
  });
  it("every response, success or refusal, is no-store", async () => {
    for (const r of [await call(), await call({ auth: "Bearer x" }), await call({ key: "Bad_Key" }), await call({ key: "no-such-key" })]) {
      expect(r.headers.get("cache-control")).toBe("no-store");
    }
  });
});

describe("PUBLIC_PATHS through the middleware predicate (row 9, AC5)", () => {
  // The same predicate as middleware.ts: `pathname === p || pathname.startsWith(p + "/")`. A route-level test alone
  // misses the 307 to /login (learning 2026-06-01-new-internal-api-route-needs-public-paths-registration).
  const isPublic = (pathname: string): boolean => PUBLIC_PATHS.some((p) => pathname === p || pathname.startsWith(p + "/"));
  it("the entry is exact and narrow", () => {
    expect(PUBLIC_PATHS).toContain("/api/internal/legal-acceptance");
    expect(PUBLIC_PATHS).not.toContain("/api/internal");
    expect(PUBLIC_PATHS).not.toContain("/api/internal/");
    expect(PUBLIC_PATHS.filter((p) => p.startsWith("/api/internal/legal-acceptance"))).toEqual(["/api/internal/legal-acceptance"]);
  });
  it("the dynamic route is reachable without a session and no sibling is", () => {
    expect(isPublic("/api/internal/legal-acceptance/fixture-terms")).toBe(true);
    expect(isPublic("/api/internal/legal-acceptance/probe")).toBe(true);
    expect(isPublic("/api/internal/legal-acceptance-foo")).toBe(false);
    expect(isPublic("/api/internal/legal-acceptanc")).toBe(false);
    expect(isPublic("/api/internal/other")).toBe(false);
    expect(isPublic("/api/internal")).toBe(false);
    expect(isPublic("/api/legal-acceptance/fixture-terms/decide")).toBe(false);
  });
});
