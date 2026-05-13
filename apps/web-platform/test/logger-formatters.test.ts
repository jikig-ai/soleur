import { describe, it, expect, vi, beforeEach } from "vitest";
import { Writable } from "node:stream";
import pino from "pino";
import { createHmac } from "node:crypto";

// Pepper set BEFORE the SUT module loads — required because observability.ts
// reads `process.env.SENTRY_USERID_PEPPER` at module init via vi.hoisted
// (mirrors observability.test.ts:5-11 discipline).
vi.hoisted(() => {
  process.env.SENTRY_USERID_PEPPER = "test-pepper";
});

const TEST_PEPPER = "test-pepper";
const expectedHashFor = (userId: string) =>
  createHmac("sha256", TEST_PEPPER).update(userId).digest("hex");

import { renameUserIdToHash } from "../server/userid-pseudonymize";
import { REDACT_PATHS } from "../server/sensitive-keys";

/**
 * Build a pino instance with the same wiring `logger.ts` ships:
 * - `formatters.log` wraps `renameUserIdToHash` in try/catch + one-time
 *   `console.warn`, returning `obj` unchanged on throw.
 * - `redact: REDACT_PATHS` matches the production redact list.
 *
 * Each test gets a fresh module-scope `formatterErrorReported` flag so
 * the one-time warn fires per-test.
 */
function makeLogger(opts: {
  renameImpl?: typeof renameUserIdToHash;
} = {}) {
  const rename = opts.renameImpl ?? renameUserIdToHash;
  let formatterErrorReported = false;
  const consoleWarnSpy = vi.spyOn(console, "warn").mockImplementation(() => {});

  const lines: Array<Record<string, unknown>> = [];
  const dest = new Writable({
    write(chunk, _enc, cb) {
      for (const line of String(chunk).split("\n")) {
        if (!line) continue;
        try {
          lines.push(JSON.parse(line));
        } catch {
          // ignore non-JSON output (pino-pretty preamble, etc.)
        }
      }
      cb();
    },
  });

  const logger = pino(
    {
      level: "debug",
      formatters: {
        log: (obj) => {
          try {
            return rename(obj);
          } catch (err) {
            if (!formatterErrorReported) {
              formatterErrorReported = true;
              const errStr =
                err instanceof Error ? (err.stack ?? err.message) : String(err);
              console.warn(
                "[logger] formatters.log threw; falling back to raw object",
                errStr,
              );
            }
            return obj;
          }
        },
      },
      redact: REDACT_PATHS as readonly string[] as string[],
    },
    dest,
  );

  return { logger, lines, consoleWarnSpy };
}

beforeEach(() => {
  vi.restoreAllMocks();
});

describe("pino formatters.log rename hook", () => {
  it("renames top-level `userId` to `userIdHash` for logger.error", () => {
    const { logger, lines } = makeLogger();
    logger.error({ userId: "u1", err: "boom" }, "msg");
    expect(lines).toHaveLength(1);
    expect(lines[0].userIdHash).toBe(expectedHashFor("u1"));
    expect(lines[0]).not.toHaveProperty("userId");
  });

  it("renames top-level `user_id` to `userIdHash` for logger.info", () => {
    const { logger, lines } = makeLogger();
    const uid = "11111111-1111-1111-1111-111111111111";
    logger.info({ user_id: uid }, "msg");
    expect(lines).toHaveLength(1);
    expect(lines[0].userIdHash).toBe(expectedHashFor(uid));
    expect(lines[0]).not.toHaveProperty("user_id");
  });

  it("does NOT rename nested `extra.userId` (top-level boundary)", () => {
    const { logger, lines } = makeLogger();
    logger.warn({ extra: { userId: "u1" }, op: "x" }, "msg");
    expect(lines).toHaveLength(1);
    // Nested userId remains untouched — depth boundary is by design.
    expect(lines[0].extra).toEqual({ userId: "u1" });
    expect(lines[0]).not.toHaveProperty("userIdHash");
  });

  it("renames null `userId` to `userIdHash: 'pepper_unset_null'`", () => {
    const { logger, lines } = makeLogger();
    logger.error({ userId: null, err: "boom" }, "msg");
    expect(lines).toHaveLength(1);
    expect(lines[0].userIdHash).toBe("pepper_unset_null");
  });

  it("passes through unchanged when no `userId` key is present", () => {
    const { logger, lines } = makeLogger();
    logger.info({ op: "noop" }, "msg");
    expect(lines).toHaveLength(1);
    expect(lines[0]).not.toHaveProperty("userId");
    expect(lines[0]).not.toHaveProperty("userIdHash");
    expect(lines[0].op).toBe("noop");
  });

  describe("Architecture F2 — throw safety (formatter MUST NOT drop the log line)", () => {
    it("returns `obj` unchanged when the rename helper throws", () => {
      const renameImpl = () => {
        throw new Error("synthetic helper failure");
      };
      const { logger, lines } = makeLogger({ renameImpl });
      logger.error({ userId: "u1", err: "boom" }, "msg");

      // The original error context survives — raw userId DOES land on disk
      // in this degraded mode, but the alternative (dropping the line entirely)
      // is strictly worse for incident response. Operator sees the warn.
      expect(lines).toHaveLength(1);
      expect(lines[0].userId).toBe("u1");
      expect(lines[0].err).toBe("boom");
    });

    it("emits one `console.warn` per logger lifetime on throw (re-entrancy guard)", () => {
      const renameImpl = () => {
        throw new Error("synthetic helper failure");
      };
      const { logger, consoleWarnSpy } = makeLogger({ renameImpl });

      logger.error({ userId: "u1" }, "msg1");
      logger.error({ userId: "u2" }, "msg2");
      logger.error({ userId: "u3" }, "msg3");

      // One-time guard — three throws, one warn.
      expect(consoleWarnSpy).toHaveBeenCalledTimes(1);
      expect(consoleWarnSpy).toHaveBeenCalledWith(
        "[logger] formatters.log threw; falling back to raw object",
        expect.stringContaining("synthetic helper failure"),
      );
    });
  });
});
