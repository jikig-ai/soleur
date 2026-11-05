/**
 * #12011 PR-D: the strict wrappers over verify_legal_acceptance (no `outcome` key), ack_legal_acceptance and
 * legal_acceptance_ack_state. Synthesized fixtures only. An unrecognised payload is `bad_payload`, never a status.
 */
import { describe, expect, it } from "vitest";
import { ackAcceptance, ackState, LegalServiceError, verifyAcceptance, type LegalRpcClient } from "@/server/legal-acceptance/service";

const FOUNDER = "00000000-0000-4000-8000-0000000000aa";
const KEY = "fixture-terms";
const HASH = "a".repeat(64);
const OTHER_HASH = "b".repeat(64);
const WHEN = "2026-11-05T10:00:00.000Z";

type Res = { data?: unknown; error?: { message: string; code?: string } | null };
function client(results: Res[] | Res | (() => Res)) {
  const calls: Array<{ fn: string; args: Record<string, unknown> }> = [];
  const queue = Array.isArray(results) ? [...results] : null;
  const c: LegalRpcClient = {
    async rpc(fn, args = {}) {
      calls.push({ fn, args });
      const r: Res | undefined = queue ? queue.shift() : typeof results === "function" ? results() : (results as Res);
      if (!r) throw new Error("unexpected rpc");
      return { data: r.data ?? null, error: r.error ?? null };
    },
  };
  return { c, calls };
}
const code = async (p: Promise<unknown>): Promise<string> => {
  try {
    await p;
  } catch (e) {
    return e instanceof LegalServiceError ? (e.code ?? "no-code") : "other";
  }
  return "none";
};
const a = { founderId: FOUNDER, key: KEY, textHash: HASH };

describe("verifyAcceptance", () => {
  it("passes the founder id, key and hash to verify_legal_acceptance and returns the four fields", async () => {
    const { c, calls } = client({ data: { status: "accepted", text_hash: HASH, decided_at: WHEN, row_ok: true } });
    expect(await verifyAcceptance(c, a)).toEqual({ status: "accepted", text_hash: HASH, decided_at: WHEN, row_ok: true });
    expect(calls).toEqual([{ fn: "verify_legal_acceptance", args: { p_founder_id: FOUNDER, p_key: KEY, p_text_hash: HASH } }]);
  });

  it.each(["accepted", "declined", "changes_requested"] as const)("%s needs row_ok true and a timestamp", async (status) => {
    const ok = { status, text_hash: HASH, decided_at: WHEN, row_ok: true };
    expect((await verifyAcceptance(client({ data: ok }).c, a)).status).toBe(status);
    for (const bad of [{ row_ok: false }, { row_ok: null }, { row_ok: "true" }, { decided_at: null }, { decided_at: "not a date" }, { decided_at: 7 }]) {
      expect(await code(verifyAcceptance(client({ data: { ...ok, ...bad } }).c, a)), JSON.stringify(bad)).toBe("bad_payload");
    }
  });

  it("none needs a null decided_at and a null row_ok", async () => {
    const none = { status: "none", text_hash: HASH, decided_at: null, row_ok: null };
    expect(await verifyAcceptance(client({ data: none }).c, a)).toEqual(none);
    for (const bad of [{ decided_at: WHEN }, { row_ok: true }, { row_ok: false }]) {
      expect(await code(verifyAcceptance(client({ data: { ...none, ...bad } }).c, a)), JSON.stringify(bad)).toBe("bad_payload");
    }
  });

  it("invalid passes through as invalid with row_ok false; it is never read as none, and row_ok true is refused", async () => {
    const inv = { status: "invalid", text_hash: HASH, decided_at: WHEN, row_ok: false };
    expect(await verifyAcceptance(client({ data: inv }).c, a)).toEqual(inv);
    expect(await code(verifyAcceptance(client({ data: { ...inv, row_ok: true } }).c, a))).toBe("bad_payload");
    expect(await code(verifyAcceptance(client({ data: { ...inv, row_ok: null } }).c, a))).toBe("bad_payload");
  });

  it("an unknown status, a different echoed hash, a missing or non-object payload, and an array are bad_payload", async () => {
    const good = { status: "accepted", text_hash: HASH, decided_at: WHEN, row_ok: true };
    for (const data of [
      { ...good, status: "pending" },
      { ...good, status: "ACCEPTED" },
      { ...good, status: undefined },
      { ...good, text_hash: OTHER_HASH },
      { ...good, text_hash: undefined },
      null,
      "accepted",
      [good],
      { outcome: "accepted" },
    ]) {
      expect(await code(verifyAcceptance(client({ data }).c, a)), JSON.stringify(data)).toBe("bad_payload");
    }
  });

  it("the result carries exactly four keys: an extra column from the database (the note) is dropped, never forwarded", async () => {
    const { c } = client({ data: { status: "changes_requested", text_hash: HASH, decided_at: WHEN, row_ok: true, requested_edit: "NOTE-SENTINEL" } });
    const out = await verifyAcceptance(c, a);
    expect(Object.keys(out).sort()).toEqual(["decided_at", "row_ok", "status", "text_hash"]);
    expect(JSON.stringify(out)).not.toContain("NOTE-SENTINEL");
  });

  it("an RPC error throws LegalServiceError with the SQLSTATE and a static message; a thrown rpc is rpc_threw", async () => {
    const err = await verifyAcceptance(client({ error: { message: "row echo: NOTE-SENTINEL", code: "XX000" } }).c, a).catch((e) => e);
    expect(err).toBeInstanceOf(LegalServiceError);
    expect((err as LegalServiceError).code).toBe("XX000");
    expect((err as Error).message).not.toContain("NOTE-SENTINEL");
    const throwing: LegalRpcClient = { rpc: () => Promise.reject(new Error("boom")) };
    expect(await code(verifyAcceptance(throwing, a))).toBe("rpc_threw");
  });

  it("a serialization failure (40001) is retried once, then the second answer is used", async () => {
    const good = { status: "none", text_hash: HASH, decided_at: null, row_ok: null };
    const { c, calls } = client([{ error: { message: "x", code: "40001" } }, { data: good }]);
    expect((await verifyAcceptance(c, a)).status).toBe("none");
    expect(calls).toHaveLength(2);
    const twice = client([{ error: { message: "x", code: "40001" } }, { error: { message: "x", code: "40001" } }]);
    expect(await code(verifyAcceptance(twice.c, a))).toBe("40001");
    expect(twice.calls).toHaveLength(2);
  });
});

describe("ackAcceptance", () => {
  it("returns acked or not_found and sends the three parameters", async () => {
    const { c, calls } = client({ data: { outcome: "acked" } });
    expect(await ackAcceptance(c, a)).toBe("acked");
    expect(calls).toEqual([{ fn: "ack_legal_acceptance", args: { p_founder_id: FOUNDER, p_key: KEY, p_text_hash: HASH } }]);
    expect(await ackAcceptance(client({ data: { outcome: "not_found" } }).c, a)).toBe("not_found");
  });
  it("an unknown outcome or a payload without one is bad_payload; an RPC error throws", async () => {
    expect(await code(ackAcceptance(client({ data: { outcome: "maybe" } }).c, a))).toBe("bad_payload");
    expect(await code(ackAcceptance(client({ data: { acked: true } }).c, a))).toBe("bad_payload");
    expect(await code(ackAcceptance(client({ error: { message: "x", code: "42501" } }).c, a))).toBe("42501");
  });
});

describe("ackState", () => {
  it("none, and row with acked and age_seconds; calls legal_acceptance_ack_state", async () => {
    const { c, calls } = client([{ data: { outcome: "none" } }, { data: { outcome: "row", acked: false, age_seconds: 200 } }]);
    expect(await ackState(c, a)).toEqual({ outcome: "none" });
    expect(await ackState(c, a)).toEqual({ outcome: "row", acked: false, age_seconds: 200 });
    expect(calls.every((x) => x.fn === "legal_acceptance_ack_state")).toBe(true);
  });
  it("a row payload with a non-boolean acked, or a missing, negative, fractional or non-numeric age is bad_payload", async () => {
    for (const bad of [{ acked: "false" }, { acked: undefined }, { age_seconds: undefined }, { age_seconds: -1 }, { age_seconds: 1.5 }, { age_seconds: "9" }, { age_seconds: null }]) {
      const data = { outcome: "row", acked: true, age_seconds: 5, ...bad };
      expect(await code(ackState(client({ data }).c, a)), JSON.stringify(bad)).toBe("bad_payload");
    }
    expect(await code(ackState(client({ data: { outcome: "gone" } }).c, a))).toBe("bad_payload");
  });
});
