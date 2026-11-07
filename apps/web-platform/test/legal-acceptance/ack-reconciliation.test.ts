/**
 * #12011 PR-D Guard 3: the ack written after a flushed `accepted` event (decide path) and the per-row
 * `row_without_event` reconciliation on the verify path. Synthesized fixtures only.
 *
 * Decide side: the founder's result is returned immediately; the flush and the ack run OFF the request path and can
 * never change the response. Verify side: a row that is unacked and at least 120 s old emits `row_without_event` on every
 * verify of it; younger, acked or missing rows emit nothing.
 */
import { beforeEach, describe, expect, it, vi } from "vitest";

const FOUNDER = "00000000-0000-4000-8000-0000000000aa";
const TOKEN = "R".repeat(8) + "0123456789abcdef".repeat(3);

const h = vi.hoisted(() => ({
  warnSink: vi.fn(),
  errSink: vi.fn(),
  verifyRpc: vi.fn(),
  logWarn: vi.fn(),
  texts: { dir: "" },
}));
// The one warning line for a flush that was not confirmed goes to the server logger (not Sentry).
vi.mock("@/server/logger", async (orig) => ({
  ...(await orig<typeof import("@/server/logger")>()),
  createChildLogger: () => ({ warn: (...a: unknown[]) => h.logWarn(...a), info: () => {}, error: () => {}, debug: () => {} }),
}));
vi.mock("@/server/observability", () => ({
  warnSilentFallback: (...a: unknown[]) => h.warnSink(...a),
  reportSilentFallback: (...a: unknown[]) => h.errSink(...a),
}));
vi.mock("@/lib/supabase/service", () => ({
  serverUrl: () => "https://fixture.supabase.invalid",
  createServiceClient: () => ({ rpc: (...a: unknown[]) => h.verifyRpc(...a) }),
}));
vi.mock("@/server/legal-acceptance/canonical", async (orig) => {
  const real = await orig<typeof import("@/server/legal-acceptance/canonical")>();
  return { ...real, getLegalText: (key: string) => real.getLegalText(key, h.texts.dir) };
});

import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import { afterAll } from "vitest";
import { GET } from "@/app/api/internal/legal-acceptance/[key]/route";
import { getLegalText, parseLegalText } from "@/server/legal-acceptance/canonical";
import {
  ACK_FLUSH_TIMEOUT_MS,
  ROW_WITHOUT_EVENT_GRACE_SECONDS,
  decideLegal,
  type DecideDeps,
  type LegalRpcClient,
} from "@/server/legal-acceptance/service";

const USER = FOUNDER;
const SESSION = "11111111-1111-4111-8111-111111111111";
const ENTRY = parseLegalText("fixture-terms", "---\nversion: fx-1\n---\nSynthesized fixture text.\n");
const ENTRY_B = parseLegalText("fixture-other", "---\nversion: fx-2\n---\nA different synthesized fixture text.\n");
const WHEN = "2026-11-05T10:00:00.000Z";

const events = () => [
  ...h.warnSink.mock.calls.map((c) => ({ ...(c[1] as object), level: "warn" })),
  ...h.errSink.mock.calls.map((c) => ({ ...(c[1] as object), level: "error" })),
] as Array<{ op: string; level: string; tags?: Record<string, string>; extra?: Record<string, unknown> }>;
const ops = () => events().map((e) => e.op);
const storeFailed = () => events().filter((e) => e.op === "store_failed");

// ── decide side ──────────────────────────────────────────────────────────────────────────────────────────────────

type Rpc = { data?: unknown; error?: { message: string; code?: string } | null };
function rig(o: {
  record?: Rpc;
  issue?: Rpc;
  ack?: Rpc | (() => Promise<Rpc>);
  flush?: () => Promise<boolean>;
  noFlush?: boolean;
  schedule?: DecideDeps["runOffPath"];
} = {}) {
  const log: string[] = [];
  const tasks: Array<() => Promise<void>> = [];
  const serviceCalls: Array<{ fn: string; args: Record<string, unknown> }> = [];
  const service: LegalRpcClient = {
    async rpc(fn, args = {}) {
      log.push(`service:${fn}`);
      serviceCalls.push({ fn, args });
      if (fn === "issue_legal_reauth") return { data: o.issue?.data ?? { outcome: "issued", reused: false, event_id: "e", expires_at: "2099-01-01T00:00:00Z" }, error: null };
      if (fn === "ack_legal_acceptance") {
        const r = typeof o.ack === "function" ? await o.ack() : (o.ack ?? { data: { outcome: "acked" } });
        return { data: r.data ?? null, error: r.error ?? null };
      }
      throw new Error(`unexpected service rpc ${fn}`);
    },
  };
  const user: LegalRpcClient = {
    async rpc(fn, args = {}) {
      log.push(`user:${fn}`);
      const r = o.record ?? { data: { outcome: "recorded", choice: "accept", decided_at: WHEN, text_hash: args.p_text_hash, reauth_at: WHEN } };
      return { data: r.data ?? null, error: r.error ?? null };
    },
  };
  const flush = vi.fn(o.flush ?? (async () => true));
  const deps: DecideDeps = {
    service,
    user,
    ...(o.noFlush ? {} : { flushEvents: async () => { log.push("flush"); return flush(); } }),
    runOffPath: o.schedule ?? ((t) => { tasks.push(t); }),
  };
  const decide = (choice: "accept" | "decline" | "request_changes" = "accept", entry = ENTRY) =>
    decideLegal(deps, { userId: USER, sessionId: SESSION, entry, choice, textHash: entry.textHash, note: choice === "request_changes" ? "n" : null });
  return { decide, tasks, log, flush, serviceCalls, run: async () => { for (const t of tasks.splice(0)) await t(); } };
}
const recordedResult = { kind: "result", result: { outcome: "recorded", choice: "accept", decidedAt: WHEN, reauthAt: WHEN } };
const ackCalls = (r: ReturnType<typeof rig>) => r.serviceCalls.filter((c) => c.fn === "ack_legal_acceptance");

beforeEach(() => {
  h.warnSink.mockReset();
  h.errSink.mockReset();
  h.verifyRpc.mockReset();
  h.logWarn.mockReset();
  vi.useRealTimers();
});

describe("decide path: ack only after a flush that returned true (Guard 3 rows 1 and 5)", () => {
  it("recorded: emits accepted, returns the result before any flush, then flush, then ack with the three parameters", async () => {
    const r = rig();
    expect(await r.decide()).toEqual(recordedResult);
    expect(ops()).toContain("accepted");
    expect(r.flush).not.toHaveBeenCalled(); // the response does not wait on, or even start, the flush
    expect(ackCalls(r)).toHaveLength(0);
    await r.run();
    expect(r.log.slice(-2)).toEqual(["flush", "service:ack_legal_acceptance"]);
    expect(ackCalls(r)).toEqual([{ fn: "ack_legal_acceptance", args: { p_founder_id: USER, p_key: "fixture-terms", p_text_hash: ENTRY.textHash } }]);
    expect(storeFailed()).toEqual([]);
  });
  it("two keys: each decision is acked with ITS OWN key and hash (a hard-coded key or hash fails)", async () => {
    for (const entry of [ENTRY, ENTRY_B]) {
      const r = rig();
      await r.decide("accept", entry);
      await r.run();
      expect(ackCalls(r), entry.key).toEqual([{ fn: "ack_legal_acceptance", args: { p_founder_id: USER, p_key: entry.key, p_text_hash: entry.textHash } }]);
    }
    expect(ENTRY.textHash).not.toBe(ENTRY_B.textHash);
  });
  it("the accepted event is emitted before the flush is started (the flush covers the event)", async () => {
    const r = rig({ flush: async () => { expect(ops()).toContain("accepted"); return true; } });
    await r.decide();
    await r.run();
    expect(r.flush).toHaveBeenCalledTimes(1);
  });
  it("decline and request_changes are acked too (the event is emitted for any recorded choice)", async () => {
    for (const choice of ["decline", "request_changes"] as const) {
      const r = rig({ record: { data: { outcome: "recorded", choice, decided_at: WHEN, text_hash: ENTRY.textHash, reauth_at: null } } });
      await r.decide(choice);
      await r.run();
      expect(ackCalls(r), choice).toHaveLength(1);
    }
  });
  it("flush returns false: no ack, no store_failed, and exactly one warning log line naming only the key", async () => {
    const r = rig({ flush: async () => false });
    expect(await r.decide()).toEqual(recordedResult);
    await r.run();
    expect(ackCalls(r)).toHaveLength(0);
    expect(storeFailed()).toEqual([]);
    expect(h.logWarn).toHaveBeenCalledTimes(1);
    expect(h.logWarn).toHaveBeenCalledWith({ key: "fixture-terms" }, "legal acceptance ack skipped: flush not confirmed");
    // No user id, hash or note in the line, and no Sentry event for it.
    expect(JSON.stringify(h.logWarn.mock.calls)).not.toContain(USER);
    expect(JSON.stringify(h.logWarn.mock.calls)).not.toContain(ENTRY.textHash);
    expect(ops()).toEqual(["accepted"]);
  });
  it("a flush that resolves true writes no warning; a flush that throws is store_failed and writes no warning", async () => {
    const ok = rig();
    await ok.decide();
    await ok.run();
    expect(h.logWarn).not.toHaveBeenCalled();
    const bad = rig({ flush: async () => { throw new Error("transport down"); } });
    await bad.decide();
    await bad.run();
    expect(storeFailed()).toHaveLength(1);
    expect(h.logWarn).not.toHaveBeenCalled();
  });
  it("only a flush that returned exactly true acks (a truthy non-boolean does not)", async () => {
    const r = rig({ flush: (async () => 1) as unknown as () => Promise<boolean> });
    await r.decide();
    await r.run();
    expect(ackCalls(r)).toHaveLength(0);
  });
  it("flush throws: store_failed stage ack, the founder still gets recorded, decide_rejected is never emitted, no ack", async () => {
    const r = rig({ flush: async () => { throw new Error("transport down"); } });
    expect(await r.decide()).toEqual(recordedResult);
    await expect(r.run()).resolves.toBeUndefined();
    expect(ackCalls(r)).toHaveLength(0);
    expect(storeFailed()).toHaveLength(1);
    expect(storeFailed()[0].tags?.stage).toBe("ack");
    expect(ops()).not.toContain("decide_rejected");
  });
  it("the ack RPC errors, throws or answers an unknown outcome: store_failed stage ack, nothing throws, the response is unchanged", async () => {
    const variants: Array<[string, Rpc | (() => Promise<Rpc>)]> = [
      ["rpc error", { error: { message: "x", code: "XX000" } }],
      ["rpc throws", async () => { throw new Error("socket"); }],
      ["unknown outcome", { data: { outcome: "maybe" } }],
      ["not_found", { data: { outcome: "not_found" } }],
    ];
    for (const [label, ack] of variants) {
      h.errSink.mockReset();
      h.warnSink.mockReset();
      const r = rig({ ack });
      expect(await r.decide(), label).toEqual(recordedResult);
      await expect(r.run(), label).resolves.toBeUndefined();
      expect(storeFailed(), label).toHaveLength(1);
      expect(storeFailed()[0].tags?.stage, label).toBe("ack");
      expect(ops(), label).not.toContain("decide_rejected");
    }
  });
  it("a scheduler that throws does not reach the response or decide_rejected", async () => {
    const r = rig({ schedule: () => { throw new Error("no request scope"); } });
    expect(await r.decide()).toEqual(recordedResult);
    expect(storeFailed()).toHaveLength(1);
    expect(ops()).not.toContain("decide_rejected");
  });
  it("without an injected flush nothing is scheduled and nothing is acked", async () => {
    const r = rig({ noFlush: true });
    expect(await r.decide()).toEqual(recordedResult);
    expect(r.tasks).toHaveLength(0);
  });
});

describe("decide path: a flush that never resolves cannot delay or change the response", () => {
  it("the result is returned with the flush still pending; the bounded wait then ends with no ack", async () => {
    vi.useFakeTimers();
    const r = rig({ flush: () => new Promise<boolean>(() => {}) });
    const out = await r.decide(); // resolves without advancing any timer
    expect(out).toEqual(recordedResult);
    const done = r.run();
    await vi.advanceTimersByTimeAsync(ACK_FLUSH_TIMEOUT_MS - 1);
    expect(ackCalls(r)).toHaveLength(0);
    await vi.advanceTimersByTimeAsync(2);
    await done;
    expect(ackCalls(r)).toHaveLength(0);
    expect(ACK_FLUSH_TIMEOUT_MS).toBe(2000);
    // The slow flush counts as not confirmed: one warning line, no Sentry event.
    expect(h.logWarn).toHaveBeenCalledTimes(1);
    expect(storeFailed()).toEqual([]);
  });
  it("a flush that answers true after the bound is too late: still no ack", async () => {
    vi.useFakeTimers();
    let resolve: (v: boolean) => void = () => {};
    const r = rig({ flush: () => new Promise<boolean>((res) => { resolve = res; }) });
    await r.decide();
    const done = r.run();
    await vi.advanceTimersByTimeAsync(ACK_FLUSH_TIMEOUT_MS + 1);
    await done;
    resolve(true);
    await vi.advanceTimersByTimeAsync(10);
    expect(ackCalls(r)).toHaveLength(0);
  });
  it("the default scheduler is a caught fire-and-forget: the response returns first and a failing task is swallowed", async () => {
    const log: string[] = [];
    const out = await decideLegal(
      {
        service: { rpc: async () => ({ data: { outcome: "acked" }, error: null }) },
        user: { rpc: async () => ({ data: { outcome: "recorded", choice: "accept", decided_at: WHEN, text_hash: ENTRY.textHash, reauth_at: WHEN }, error: null }) },
        flushEvents: async () => {
          log.push("flush-start");
          throw new Error("x");
        },
      },
      { userId: USER, sessionId: SESSION, entry: ENTRY, choice: "accept", textHash: ENTRY.textHash, note: null },
    );
    expect(out).toEqual(recordedResult);
    await vi.waitFor(() => expect(log).toEqual(["flush-start"]));
    await vi.waitFor(() => expect(storeFailed()).toHaveLength(1));
  });
});

describe("already_recorded never acks (Guard 3 row 2)", () => {
  it("from record_legal_acceptance", async () => {
    const r = rig({ record: { data: { outcome: "already_recorded", choice: "accept" } } });
    expect(await r.decide()).toEqual({ kind: "result", result: { outcome: "already_recorded", choice: "accept" } });
    await r.run();
    expect(r.tasks).toHaveLength(0);
    expect(r.flush).not.toHaveBeenCalled();
    expect(ackCalls(r)).toHaveLength(0);
    expect(ops()).not.toContain("accepted");
  });
  it("from the intent step of a decline", async () => {
    const r = rig({ issue: { data: { outcome: "already_recorded", choice: "decline" } } });
    expect((await r.decide("decline")).kind).toBe("result");
    await r.run();
    expect(r.flush).not.toHaveBeenCalled();
    expect(ackCalls(r)).toHaveLength(0);
  });
  it("replaced, expired and code_expired do not flush or ack either", async () => {
    for (const outcome of ["replaced", "expired", "code_expired"]) {
      const r = rig({ record: { data: { outcome } } });
      await r.decide();
      await r.run();
      expect(r.flush, outcome).not.toHaveBeenCalled();
      expect(ackCalls(r), outcome).toHaveLength(0);
    }
  });
});

// ── verify side ──────────────────────────────────────────────────────────────────────────────────────────────────

// Two registry keys with different texts, so a route that hard-codes (or drops) the key it was asked about is caught.
const dir = mkdtempSync(path.join(tmpdir(), "ack-recon-"));
writeFileSync(path.join(dir, "fixture-terms.md"), "---\nversion: fx-1\n---\nSynthesized fixture text.\n");
writeFileSync(path.join(dir, "fixture-other.md"), "---\nversion: fx-2\n---\nA different synthesized fixture text.\n");
h.texts.dir = dir;
afterAll(() => rmSync(dir, { recursive: true, force: true }));
const KEY_A = "fixture-terms";
const KEY_B = "fixture-other";
const HASH = getLegalText(KEY_A).textHash;
const HASH_B = getLegalText(KEY_B).textHash;
const HASH_2 = "e".repeat(64);

type RowState = { status?: string; acked: boolean; age: number };
/**
 * Rows are keyed by `key|hash`. The stub looks the row up by the `p_key` it RECEIVES, so a route that passes the wrong key
 * (a constant, or the key of another row) reads `none` / `outcome: none` and the test goes red.
 */
function verifyRpcFor(rows: Record<string, RowState>) {
  h.verifyRpc.mockImplementation(async (fn: string, args: Record<string, string>) => {
    expect([KEY_A, KEY_B]).toContain(args.p_key);
    const row = rows[`${args.p_key}|${args.p_text_hash}`];
    if (fn === "verify_legal_acceptance") {
      if (!row) return { data: { status: "none", text_hash: args.p_text_hash, decided_at: null, row_ok: null }, error: null };
      const status = row.status ?? "accepted";
      return { data: { status, text_hash: args.p_text_hash, decided_at: WHEN, row_ok: status !== "invalid" }, error: null };
    }
    if (fn === "legal_acceptance_ack_state") {
      return { data: row ? { outcome: "row", acked: row.acked, age_seconds: row.age } : { outcome: "none" }, error: null };
    }
    throw new Error(`unexpected rpc ${fn}`);
  });
}
const verify = (key = KEY_A, hash = key === KEY_B ? HASH_B : HASH) =>
  GET(new Request(`https://app.soleur.ai/api/internal/legal-acceptance/${key}?hash=${hash}`, { headers: { authorization: `Bearer ${TOKEN}` } }), {
    params: Promise.resolve({ key }),
  });
const rowEvents = () => events().filter((e) => e.op === "row_without_event");

describe("verify path: row_without_event (Guard 3 rows 3, 4, 6)", () => {
  beforeEach(() => {
    vi.unstubAllEnvs();
    vi.stubEnv("LEGAL_ACCEPTANCE_VERIFY_TOKEN", TOKEN);
    vi.stubEnv("LEGAL_ACCEPTANCE_FOUNDER_ID", FOUNDER);
  });

  it("the grace is 120 seconds and the boundary is inclusive: 119 emits nothing, 120 emits", async () => {
    expect(ROW_WITHOUT_EVENT_GRACE_SECONDS).toBe(120);
    verifyRpcFor({ [`${KEY_A}|${HASH}`]: { acked: false, age: 119 } });
    expect((await verify()).status).toBe(200);
    expect(rowEvents()).toHaveLength(0);
    verifyRpcFor({ [`${KEY_A}|${HASH}`]: { acked: false, age: 120 } });
    expect((await verify()).status).toBe(200);
    expect(rowEvents()).toHaveLength(1);
  });
  it("a row 200 s old with no ack emits on every verify (no dedupe in process); the response is unchanged", async () => {
    verifyRpcFor({ [`${KEY_A}|${HASH}`]: { acked: false, age: 200 } });
    const a = await (await verify()).json();
    const b = await (await verify()).json();
    expect(rowEvents()).toHaveLength(2);
    expect(a).toEqual(b);
    expect(a).toEqual({ status: "accepted", text_hash: HASH, decided_at: WHEN, row_ok: true });
    const ev = rowEvents()[0];
    expect(ev.level).toBe("error");
    expect(JSON.stringify(ev)).not.toContain(FOUNDER);
    // The public hash and the key identify the row for triage; the founder id and the note never do.
    expect(ev.extra).toMatchObject({ key: KEY_A, textHash: HASH, ageSeconds: 200, status: "accepted" });
  });
  it.each(["accepted", "declined", "changes_requested"] as const)(
    "a %s row (the decide path acks every recorded choice) that is unacked and >= 120 s old emits row_without_event; acked or young emits nothing",
    async (status) => {
      verifyRpcFor({ [`${KEY_A}|${HASH}`]: { status, acked: false, age: 120 } });
      const out = await (await verify()).json();
      expect(out).toEqual({ status, text_hash: HASH, decided_at: WHEN, row_ok: true });
      expect(rowEvents(), status).toHaveLength(1);
      expect(rowEvents()[0].extra).toMatchObject({ key: KEY_A, textHash: HASH, status });
      h.warnSink.mockReset();
      h.errSink.mockReset();
      verifyRpcFor({ [`${KEY_A}|${HASH}`]: { status, acked: true, age: 5000 } });
      await verify();
      verifyRpcFor({ [`${KEY_A}|${HASH}`]: { status, acked: false, age: 119 } });
      await verify();
      expect(rowEvents(), `${status} acked or young`).toHaveLength(0);
    },
  );
  it("a row acked 1 s after the write, or acked at any age, emits nothing", async () => {
    verifyRpcFor({ [`${KEY_A}|${HASH}`]: { acked: true, age: 1 } });
    await verify();
    verifyRpcFor({ [`${KEY_A}|${HASH}`]: { acked: true, age: 100000 } });
    await verify();
    expect(rowEvents()).toHaveLength(0);
  });
  it("a young unacked row (30 s) emits nothing: a write in progress is not a gap", async () => {
    verifyRpcFor({ [`${KEY_A}|${HASH}`]: { acked: false, age: 30 } });
    await verify();
    expect(rowEvents()).toHaveLength(0);
  });
  it("status none makes no ack_state call and emits nothing: no row, no gap", async () => {
    verifyRpcFor({});
    expect((await verify()).status).toBe(200);
    expect(h.verifyRpc.mock.calls.map((c) => c[0])).toEqual(["verify_legal_acceptance"]);
    expect(rowEvents()).toHaveLength(0);
  });
  it("an invalid row that is unacked and old emits BOTH record_invalid and row_without_event (it is not skipped), each with the public hash", async () => {
    verifyRpcFor({ [`${KEY_A}|${HASH}`]: { status: "invalid", acked: false, age: 500 } });
    const out = await (await verify()).json();
    expect(out.status).toBe("invalid");
    expect(ops().sort()).toEqual(["record_invalid", "row_without_event"]);
    for (const e of events()) expect(e.extra).toMatchObject({ key: KEY_A, textHash: HASH });
  });
  it("two hashes of one key where only the second lacks an ack: verifying both emits exactly one event", async () => {
    verifyRpcFor({ [`${KEY_A}|${HASH}`]: { acked: true, age: 9000 }, [`${KEY_A}|${HASH_2}`]: { acked: false, age: 9000 } });
    await verify(KEY_A, HASH);
    expect(rowEvents()).toHaveLength(0);
    await verify(KEY_A, HASH_2);
    expect(rowEvents()).toHaveLength(1);
    expect(rowEvents()[0].extra).toMatchObject({ key: KEY_A, textHash: HASH_2 });
  });
  it("the lookup key is the one asked about: both RPCs receive it, the configured founder id and the asked hash", async () => {
    verifyRpcFor({ [`${KEY_A}|${HASH}`]: { acked: true, age: 5 }, [`${KEY_B}|${HASH_B}`]: { acked: true, age: 5 } });
    await verify(KEY_A);
    await verify(KEY_B);
    const calls = h.verifyRpc.mock.calls.map((c) => ({ fn: c[0], args: c[1] }));
    expect(calls).toEqual([
      { fn: "verify_legal_acceptance", args: { p_founder_id: FOUNDER, p_key: KEY_A, p_text_hash: HASH } },
      { fn: "legal_acceptance_ack_state", args: { p_founder_id: FOUNDER, p_key: KEY_A, p_text_hash: HASH } },
      { fn: "verify_legal_acceptance", args: { p_founder_id: FOUNDER, p_key: KEY_B, p_text_hash: HASH_B } },
      { fn: "legal_acceptance_ack_state", args: { p_founder_id: FOUNDER, p_key: KEY_B, p_text_hash: HASH_B } },
    ]);
  });
  it("two keys with the SAME hash: an unacked row under one key is not reported for the other key, and is reported for its own", async () => {
    verifyRpcFor({ [`${KEY_A}|${HASH_2}`]: { acked: true, age: 9000 }, [`${KEY_B}|${HASH_2}`]: { acked: false, age: 9000 } });
    await verify(KEY_A, HASH_2);
    expect(rowEvents()).toHaveLength(0);
    await verify(KEY_B, HASH_2);
    expect(rowEvents()).toHaveLength(1);
    expect(rowEvents()[0].extra).toMatchObject({ key: KEY_B });
  });
  it("a row that exists only under the other key is none for this key (verify) and never reconciled", async () => {
    verifyRpcFor({ [`${KEY_B}|${HASH}`]: { acked: false, age: 9000 } });
    const out = await (await verify(KEY_A, HASH)).json();
    expect(out.status).toBe("none");
    expect(rowEvents()).toHaveLength(0);
  });
});
