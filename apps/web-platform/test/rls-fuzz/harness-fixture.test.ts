import { describe, expect, test, vi } from "vitest";
import type postgres from "postgres";
import { rolledBackRaw, withTransientRetry } from "./harness-fixture";

type Sql = postgres.Sql<{}>;
type Txn = postgres.TransactionSql<{}>;

/** A Postgres-shaped error: Error carrying a 5-char SQLSTATE in `.code`. */
const pgErr = (code: string) => Object.assign(new Error(`pg ${code}`), { code });

/** Injectable instant sleep — the cadence contract lives in the spy tests below. */
const NO_SLEEP = { sleep: (_ms: number) => Promise.resolve() };

describe("withTransientRetry", () => {
  test("AC1: a transient 40P01 on attempt 1 retries and resolves fn's value", async () => {
    const fn = vi.fn().mockRejectedValueOnce(pgErr("40P01")).mockResolvedValueOnce("ok");
    await expect(withTransientRetry(fn, NO_SLEEP)).resolves.toBe("ok");
    expect(fn).toHaveBeenCalledTimes(2);
  });

  test("AC1: 55P03 (lock_not_available) is transient identically to 40P01", async () => {
    const fn = vi.fn().mockRejectedValueOnce(pgErr("55P03")).mockResolvedValueOnce("ok");
    await expect(withTransientRetry(fn, NO_SLEEP)).resolves.toBe("ok");
    expect(fn).toHaveBeenCalledTimes(2);
  });

  test("AC2: non-transient errors propagate on the first attempt — no retry", async () => {
    for (const err of [pgErr("42501"), pgErr("25P02"), new Error("assertion failure")]) {
      const fn = vi.fn().mockRejectedValue(err);
      await expect(withTransientRetry(fn, NO_SLEEP)).rejects.toBe(err);
      expect(fn).toHaveBeenCalledTimes(1);
    }
  });

  test("AC2: a SQLSTATE-shaped non-transient code also propagates unretried", async () => {
    const fn = vi.fn().mockRejectedValue(pgErr("23505"));
    await expect(withTransientRetry(fn, NO_SLEEP)).rejects.toMatchObject({ code: "23505" });
    expect(fn).toHaveBeenCalledTimes(1);
  });

  test("AC3: a persistent 40P01 propagates after exactly 3 attempts and sleeps only between attempts", async () => {
    const sleep = vi.fn((_ms: number) => Promise.resolve());
    const fn = vi.fn().mockRejectedValue(pgErr("40P01"));
    await expect(withTransientRetry(fn, { sleep })).rejects.toMatchObject({ code: "40P01" });
    expect(fn).toHaveBeenCalledTimes(3);
    expect(sleep).toHaveBeenCalledTimes(2); // no sleep after the final attempt
  });

  test("AC5: the injected sleep observes jittered delays in [80, 120) ms", async () => {
    const delays: number[] = [];
    const sleep = vi.fn((ms: number) => {
      delays.push(ms);
      return Promise.resolve();
    });
    const fn = vi
      .fn()
      .mockRejectedValueOnce(pgErr("40P01"))
      .mockRejectedValueOnce(pgErr("55P03"))
      .mockResolvedValueOnce("ok");
    await expect(withTransientRetry(fn, { sleep })).resolves.toBe("ok");
    expect(delays).toHaveLength(2);
    for (const d of delays) {
      expect(d).toBeGreaterThanOrEqual(80);
      expect(d).toBeLessThan(120);
    }
  });
});

describe("rolledBackRaw", () => {
  // The fake txn is never invoked — every fn under test returns without
  // issuing SQL — so a bare async fn stands in for TransactionSql.
  const fakeTxn = (async () => {}) as unknown as Txn;
  const sqlFrom = (begin: ReturnType<typeof vi.fn>) => ({ begin }) as unknown as Sql;

  test("AC1/AC4: a 40P01 from the first begin retries the WHOLE transaction", async () => {
    const begin = vi
      .fn()
      .mockRejectedValueOnce(pgErr("40P01"))
      .mockImplementationOnce(async (cb: (t: Txn) => Promise<unknown>) => cb(fakeTxn));
    const fn = vi.fn(async () => "seeded");
    await expect(rolledBackRaw(sqlFrom(begin), fn)).resolves.toBe("seeded");
    expect(begin).toHaveBeenCalledTimes(2);
    expect(fn).toHaveBeenCalledTimes(1); // replayed txn body ran once, on the retry
  });

  test("AC4: normal completion returns fn's value — and the callback REJECTS with a Symbol (rollback requested, never committed)", async () => {
    const begin = vi.fn(async (cb: (t: Txn) => Promise<unknown>) => {
      const p = cb(fakeTxn);
      // A mutant that commits (`return out` instead of `Promise.reject(ROLLBACK)`)
      // resolves this promise with "ok" — this assertion reds on that mutant.
      await expect(p).rejects.toSatisfy((e) => typeof e === "symbol");
      return p; // propagate the sentinel rejection so rolledBackRaw can swallow it
    });
    await expect(rolledBackRaw(sqlFrom(begin), async () => "ok")).resolves.toBe("ok");
    expect(begin).toHaveBeenCalledTimes(1);
  });

  test("AC1: a 40P01 raised mid-callback (inside fn) replays the WHOLE unit — fn runs twice", async () => {
    // The observed #9779 shape: the deadlock victim is a statement inside the
    // txn, not the begin call — the retry must replay the complete unit.
    const begin = vi.fn(async (cb: (t: Txn) => Promise<unknown>) => cb(fakeTxn));
    let calls = 0;
    const fn = vi.fn(async () => {
      calls++;
      if (calls === 1) throw pgErr("40P01");
      return "seeded";
    });
    await expect(rolledBackRaw(sqlFrom(begin), fn)).resolves.toBe("seeded");
    expect(begin).toHaveBeenCalledTimes(2);
    expect(fn).toHaveBeenCalledTimes(2);
  });

  test("AC2: a fn error inside the transaction propagates without retry", async () => {
    const err = new Error("in-txn failure");
    const begin = vi.fn(async (cb: (t: Txn) => Promise<unknown>) => cb(fakeTxn));
    await expect(
      rolledBackRaw(sqlFrom(begin), async () => {
        throw err;
      }),
    ).rejects.toBe(err);
    expect(begin).toHaveBeenCalledTimes(1);
  });
});
