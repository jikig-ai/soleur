import { describe, it, expect, vi, beforeEach, beforeAll } from "vitest";
import { createHmac } from "node:crypto";

// Pepper must be set BEFORE the SUT module loads (module-init reads
// `process.env.SENTRY_USERID_PEPPER` at top level). vi.hoisted runs above
// the top-level imports. Pepper-unset (fail-closed) coverage lives in the
// sibling `observability-pepper-unset.test.ts` file so vitest worker isolation
// keeps the env clean.
vi.hoisted(() => {
  process.env.SENTRY_USERID_PEPPER = "test-pepper";
});

const TEST_PEPPER = "test-pepper";
const expectedHashFor = (userId: string) =>
  createHmac("sha256", TEST_PEPPER).update(userId).digest("hex");

// Frozen golden vector — decouples the test's "did we hash correctly" check
// from the SUT's formula. If `hashUserId` ever silently switches primitives
// (scrypt, blake2, truncation), this constant fails before the per-call
// `expectedHashFor` helpers (which would silently track the new formula).
// Generated once via `node -e "console.log(require('crypto').createHmac('sha256','test-pepper').update('u1').digest('hex'))"`.
const GOLDEN_U1_HASH =
  "d23f7650f3a2d1b52a83870a6412528cb373d6baf3353cba3fd1b421a9c5d7ac";

const {
  mockCaptureException,
  mockCaptureMessage,
  mockLoggerError,
  mockLoggerWarn,
  mockLoggerInfo,
} = vi.hoisted(() => ({
  mockCaptureException: vi.fn(),
  mockCaptureMessage: vi.fn(),
  mockLoggerError: vi.fn(),
  mockLoggerWarn: vi.fn(),
  mockLoggerInfo: vi.fn(),
}));

vi.mock("@sentry/nextjs", () => ({
  captureException: mockCaptureException,
  captureMessage: mockCaptureMessage,
}));

vi.mock("@/server/logger", () => ({
  default: { error: mockLoggerError, warn: mockLoggerWarn, info: mockLoggerInfo, debug: vi.fn() },
}));

import {
  reportSilentFallback,
  warnSilentFallback,
  infoSilentFallback,
  mirrorP0Deduped,
  hashUserId,
  __resetMirrorP0DedupForTests,
} from "../server/observability";

beforeEach(() => {
  mockCaptureException.mockReset();
  mockCaptureMessage.mockReset();
  mockLoggerError.mockReset();
  mockLoggerWarn.mockReset();
  mockLoggerInfo.mockReset();
  __resetMirrorP0DedupForTests();
});

describe("hashUserId", () => {
  it("matches the frozen golden vector for ('u1', 'test-pepper')", () => {
    // Falsifying primitive drift (e.g., scrypt swap, truncation) — the
    // per-call expectedHashFor helpers would track such drift silently;
    // this assertion catches it.
    expect(hashUserId("u1")).toBe(GOLDEN_U1_HASH);
  });

  it("is deterministic for a fixed pepper + input", () => {
    const a = hashUserId("user-abc");
    const b = hashUserId("user-abc");
    expect(a).toBe(b);
    expect(a).toBe(expectedHashFor("user-abc"));
  });

  it("emits a 64-char hex digest (HMAC-SHA256)", () => {
    const h = hashUserId("user-abc");
    expect(h).toMatch(/^[0-9a-f]{64}$/);
  });

  it("distinct inputs produce distinct hashes", () => {
    // Birthday-bound collision prob for SHA-256 over 3 inputs is ~10^-77.
    // Replaces a prior 1000-iteration smoke that added CI runtime without
    // strengthening the contract beyond the determinism + 64-hex shape
    // tests above.
    const hashes = new Set([
      hashUserId("user-a"),
      hashUserId("user-b"),
      hashUserId("user-c"),
    ]);
    expect(hashes.size).toBe(3);
  });

  it("uses the optional pepper arg when provided (prior-pepper lookup contract)", () => {
    const priorPepper = "prior-pepper";
    const got = hashUserId("user-abc", priorPepper);
    const expected = createHmac("sha256", priorPepper)
      .update("user-abc")
      .digest("hex");
    expect(got).toBe(expected);
    // And the explicit pepper differs from the env-default hash:
    expect(got).not.toBe(hashUserId("user-abc"));
  });
});

describe("reportSilentFallback — userIdHash pseudonymization", () => {
  it("hashes userId on the Error → captureException path; emits userIdHash, never raw userId", () => {
    const err = new Error("connection refused");
    reportSilentFallback(err, {
      feature: "kb-share",
      op: "create",
      extra: { userId: "u1", documentPath: "overview/doc.md" },
    });

    expect(mockCaptureException).toHaveBeenCalledTimes(1);
    const [errArg, payload] = mockCaptureException.mock.calls[0];
    expect(errArg).toBe(err);
    expect(payload.tags).toEqual({ feature: "kb-share", op: "create" });
    expect(payload.extra).toEqual({
      userIdHash: expectedHashFor("u1"),
      documentPath: "overview/doc.md",
    });
    expect(payload.extra).not.toHaveProperty("userId");
    expect(mockCaptureMessage).not.toHaveBeenCalled();

    // pino mirror also receives userIdHash, not userId.
    const [ctx] = mockLoggerError.mock.calls[0];
    expect(ctx).toMatchObject({
      feature: "kb-share",
      op: "create",
      userIdHash: expectedHashFor("u1"),
      documentPath: "overview/doc.md",
    });
    expect(ctx).not.toHaveProperty("userId");
  });

  it("promotes userIdHash to event user.id so affected-users alerts can count tenants (#5875)", () => {
    // The sandbox-startup alert uses event_unique_user_frequency, which counts
    // distinct Sentry USERS — not extra keys. Without user.id the ≥K-tenants
    // threshold is unreachable. user.id = the HASH (Recital-26 preserved).
    const err = new Error("bwrap: Operation not permitted");
    reportSilentFallback(err, {
      feature: "agent-sandbox",
      op: "sdk-startup",
      extra: { userId: "u1", conversationId: "c1" },
    });
    const [, payload] = mockCaptureException.mock.calls[0];
    expect(payload.user).toEqual({ id: expectedHashFor("u1") });
    // The hash is what Sentry counts — never the raw id.
    expect(payload.user.id).not.toBe("u1");
  });

  it("omits event.user when the emit carries no userId (no tenant attribution)", () => {
    reportSilentFallback(new Error("boot probe"), { feature: "startup" });
    const [, payload] = mockCaptureException.mock.calls[0];
    expect(payload.user).toBeUndefined();
  });

  it("hashes userId on the non-Error → captureMessage path", () => {
    const pgError = { message: "duplicate key", code: "23505" };
    reportSilentFallback(pgError, {
      feature: "kb-share",
      op: "create",
      extra: { userId: "u1" },
    });

    expect(mockCaptureException).not.toHaveBeenCalled();
    expect(mockCaptureMessage).toHaveBeenCalledTimes(1);
    const [msg, payload] = mockCaptureMessage.mock.calls[0];
    expect(msg).toBe("kb-share silent fallback");
    expect(payload.level).toBe("error");
    // SQLSTATE 23505 (unique_violation) surfaces as the `pg_code` tag (#4695).
    expect(payload.tags).toEqual({ feature: "kb-share", op: "create", pg_code: "23505" });
    expect(payload.extra).toEqual({
      err: pgError,
      userIdHash: expectedHashFor("u1"),
    });
    expect(payload.extra).not.toHaveProperty("userId");
  });

  it("uses a custom message and hashes userId (null err)", () => {
    reportSilentFallback(null, {
      feature: "accept-terms",
      op: "record",
      message: "User row not found",
      extra: { userId: "u1" },
    });

    const [msg, payload] = mockCaptureMessage.mock.calls[0];
    expect(msg).toBe("User row not found");
    expect(payload.level).toBe("error");
    expect(payload.tags).toEqual({ feature: "accept-terms", op: "record" });
    expect(payload.extra.userIdHash).toBe(expectedHashFor("u1"));
    expect(payload.extra).not.toHaveProperty("userId");
  });

  it("strips line terminators from the message before logging (js/log-injection)", () => {
    // A CR/LF (or unicode line/paragraph separator) in the message must not
    // survive into the pino `msg` field or Sentry, where it could forge a log
    // line in a downstream plaintext view.
    reportSilentFallback(null, {
      feature: "accept-terms",
      op: "record",
      message: "User row not found\r\nFAKE 2026 ERROR forged\u2028tail\u2029end\vx\fy",
      extra: { userId: "u1" },
    });

    const sanitized = "User row not found FAKE 2026 ERROR forged tail end x y";
    // pino path (logger.error second arg)
    const [, loggedMsg] = mockLoggerError.mock.calls[0];
    expect(loggedMsg).toBe(sanitized);
    expect(loggedMsg).not.toMatch(/[\r\n\u2028\u2029\v\f]/);
    // Sentry captureMessage path uses the same sanitized string
    const [sentryMsg] = mockCaptureMessage.mock.calls[0];
    expect(sentryMsg).toBe(sanitized);
  });

  it("does not emit tags.op when op is omitted", () => {
    const err = new Error("boom");
    reportSilentFallback(err, { feature: "shared-token", extra: { token: "abc" } });

    expect(mockCaptureException).toHaveBeenCalledWith(
      err,
      expect.objectContaining({ tags: { feature: "shared-token" } }),
    );
  });

  it("passes through extra unchanged when no userId key is present", () => {
    const err = new Error("boom");
    reportSilentFallback(err, { feature: "shared-token", extra: { token: "abc" } });

    expect(mockCaptureException).toHaveBeenCalledWith(
      err,
      expect.objectContaining({ extra: { token: "abc" } }),
    );
  });

  it("hashes a null userId to the 'pepper_unset_null' sentinel (avoids empty-string collision)", () => {
    const err = new Error("boom");
    reportSilentFallback(err, {
      feature: "nullable",
      extra: { userId: null, other: "value" },
    });
    const [, payload] = mockCaptureException.mock.calls[0];
    expect(payload.extra).toEqual({ userIdHash: "pepper_unset_null", other: "value" });
    expect(payload.extra).not.toHaveProperty("userId");
  });

  it("emits a pino logger.error with userIdHash instead of userId", () => {
    const err = new Error("x");
    reportSilentFallback(err, {
      feature: "services",
      op: "delete",
      extra: { userId: "u2" },
    });

    expect(mockLoggerError).toHaveBeenCalledTimes(1);
    const [ctx, msg] = mockLoggerError.mock.calls[0];
    expect(ctx).toMatchObject({
      err,
      feature: "services",
      op: "delete",
      userIdHash: expectedHashFor("u2"),
    });
    expect(ctx).not.toHaveProperty("userId");
    expect(msg).toBe("services silent fallback");
  });
});

describe("reportSilentFallback — pg_code SQLSTATE tagging (#4695)", () => {
  it("surfaces SQLSTATE as the pg_code tag on the non-Error → captureMessage path", () => {
    // The account-delete erasure path: anonymise_action_sends RPC returns a
    // PostgrestError ({ message, details, hint, code }), not an Error instance.
    const pgErr = {
      message: 'permission denied to set parameter "session_replication_role"',
      details: null,
      hint: null,
      code: "42501",
    };
    reportSilentFallback(pgErr, {
      feature: "account-delete",
      op: "anonymise-action-sends",
      extra: { userId: "u1" },
      message: "anonymise_action_sends failed — aborting deletion to avoid FK-block",
    });

    const [, payload] = mockCaptureMessage.mock.calls[0];
    expect(payload.tags).toEqual({
      feature: "account-delete",
      op: "anonymise-action-sends",
      pg_code: "42501",
    });
  });

  it("surfaces SQLSTATE as the pg_code tag on the Error → captureException path", () => {
    // node-postgres / thrown-PostgrestError shape: a real Error carrying `code`.
    const err = Object.assign(
      new Error("permission denied to set parameter"),
      { code: "42501", details: "secret-row-value", hint: "do not leak me" },
    );
    reportSilentFallback(err, {
      feature: "account-delete",
      op: "anonymise-action-sends",
      extra: { userId: "u1" },
    });

    const [errArg, payload] = mockCaptureException.mock.calls[0];
    expect(errArg).toBe(err);
    expect(payload.tags).toEqual({
      feature: "account-delete",
      op: "anonymise-action-sends",
      pg_code: "42501",
    });
  });

  it("never leaks details/hint (potential row values) into tags or extra", () => {
    // PII guard (#4695 acceptance #3): Postgres embeds row values in `details`
    // for constraint violations — only the SQLSTATE code is PII-free, so only
    // the code is surfaced. details/hint must appear in NEITHER tags nor extra.
    const err = Object.assign(new Error("unique violation"), {
      code: "23505",
      details: "Key (email)=(alice@example.com) already exists.",
      hint: "some hint that might carry an identifier",
    });
    reportSilentFallback(err, {
      feature: "account-delete",
      op: "anonymise-scope-grants",
      extra: { userId: "u1" },
    });

    const [, payload] = mockCaptureException.mock.calls[0];
    const tagValues = JSON.stringify(payload.tags);
    const extraValues = JSON.stringify(payload.extra);
    expect(tagValues).not.toContain("alice@example.com");
    expect(tagValues).not.toContain("Key (email)");
    expect(tagValues).not.toContain("some hint");
    expect(extraValues).not.toContain("alice@example.com");
    expect(extraValues).not.toContain("Key (email)");
    expect(extraValues).not.toContain("some hint");
    expect(payload.tags).not.toHaveProperty("pg_details");
    expect(payload.tags).not.toHaveProperty("pg_hint");
    expect(payload.extra).not.toHaveProperty("pg_details");
    expect(payload.extra).not.toHaveProperty("pg_hint");
  });

  it("does NOT add pg_code when the error is not a Postgres error (Node errno)", () => {
    // An ENOENT on an optional mount must not be mis-tagged as a DB failure.
    const err = Object.assign(new Error("no such file"), { code: "ENOENT" });
    reportSilentFallback(err, { feature: "kb-share", op: "read" });

    const [, payload] = mockCaptureException.mock.calls[0];
    expect(payload.tags).toEqual({ feature: "kb-share", op: "read" });
    expect(payload.tags).not.toHaveProperty("pg_code");
  });

  it("does NOT add pg_code when the error carries no code at all", () => {
    const err = new Error("plain error");
    reportSilentFallback(err, { feature: "kb-share" });

    const [, payload] = mockCaptureException.mock.calls[0];
    expect(payload.tags).toEqual({ feature: "kb-share" });
  });
});

describe("warnSilentFallback — userIdHash pseudonymization", () => {
  it("hashes userId on the Error → captureException(level=warning) path", () => {
    const err = new Error("timeout");
    warnSilentFallback(err, {
      feature: "stripe-webhook",
      op: "retry",
      extra: { userId: "u3" },
    });

    expect(mockCaptureException).toHaveBeenCalledTimes(1);
    const [errArg, payload] = mockCaptureException.mock.calls[0];
    expect(errArg).toBe(err);
    expect(payload.level).toBe("warning");
    expect(payload.tags).toEqual({ feature: "stripe-webhook", op: "retry" });
    expect(payload.extra).toEqual({ userIdHash: expectedHashFor("u3") });
    expect(payload.extra).not.toHaveProperty("userId");

    const [pinoCtx] = mockLoggerWarn.mock.calls[0];
    expect(pinoCtx).toMatchObject({
      feature: "stripe-webhook",
      op: "retry",
      userIdHash: expectedHashFor("u3"),
    });
    expect(pinoCtx).not.toHaveProperty("userId");
  });

  it("hashes userId on the non-Error → captureMessage(level=warning) path", () => {
    warnSilentFallback("string-error", {
      feature: "foo",
      extra: { userId: "u4" },
    });

    expect(mockCaptureMessage).toHaveBeenCalledTimes(1);
    const [msg, payload] = mockCaptureMessage.mock.calls[0];
    expect(msg).toBe("foo silent fallback");
    expect(payload.level).toBe("warning");
    expect(payload.extra.userIdHash).toBe(expectedHashFor("u4"));
    expect(payload.extra).not.toHaveProperty("userId");
  });

  it("passes through extra unchanged when no userId key is present", () => {
    const err = new Error("boom");
    warnSilentFallback(err, {
      feature: "noop",
      extra: { other: "value" },
    });
    expect(mockCaptureException).toHaveBeenCalledWith(err, {
      level: "warning",
      tags: { feature: "noop" },
      extra: { other: "value" },
    });
  });

  it("surfaces SQLSTATE as the pg_code tag (#4695)", () => {
    const err = Object.assign(new Error("lock not available"), { code: "55P03" });
    warnSilentFallback(err, { feature: "concurrency", op: "acquire-slot" });

    const [, payload] = mockCaptureException.mock.calls[0];
    expect(payload.tags).toEqual({
      feature: "concurrency",
      op: "acquire-slot",
      pg_code: "55P03",
    });
  });
});

describe("infoSilentFallback — every-run info-level emit (#4897)", () => {
  it("emits captureMessage(level=info) on the null-err path with tags + extra", () => {
    infoSilentFallback(null, {
      feature: "cron-workspace-gc",
      op: "workspace-gc-sweep-complete",
      message: "workspace GC sweep complete",
      extra: { fn: "cron-workspace-gc", root: "/workspaces", freedMb: 100, sweptCount: 1 },
    });

    expect(mockCaptureMessage).toHaveBeenCalledTimes(1);
    const [msg, payload] = mockCaptureMessage.mock.calls[0];
    expect(msg).toBe("workspace GC sweep complete");
    expect(payload.level).toBe("info");
    expect(payload.tags).toEqual({
      feature: "cron-workspace-gc",
      op: "workspace-gc-sweep-complete",
    });
    expect(payload.extra).toMatchObject({
      fn: "cron-workspace-gc",
      root: "/workspaces",
      freedMb: 100,
      sweptCount: 1,
    });

    // pino mirror is preserved inside the helper (no stdout signal lost).
    expect(mockLoggerInfo).toHaveBeenCalledTimes(1);
    const [pinoCtx, pinoMsg] = mockLoggerInfo.mock.calls[0];
    expect(pinoMsg).toBe("workspace GC sweep complete");
    expect(pinoCtx).toMatchObject({
      feature: "cron-workspace-gc",
      op: "workspace-gc-sweep-complete",
      freedMb: 100,
      sweptCount: 1,
    });
  });

  it("never emits at warning/error level (info channel stays separable for on-call)", () => {
    infoSilentFallback(null, {
      feature: "cron-workspace-gc",
      extra: { freedMb: 0 },
    });

    expect(mockCaptureException).not.toHaveBeenCalled();
    const [, payload] = mockCaptureMessage.mock.calls[0];
    expect(payload.level).toBe("info");
    expect(mockLoggerWarn).not.toHaveBeenCalled();
    expect(mockLoggerError).not.toHaveBeenCalled();
  });

  // #6801 (AC12/M17): sibling-parity bugfix — `info` used to silently DROP the
  // caller `tags` (unlike report/warn), so a `tags:` passed here never reached
  // Sentry. It must now merge them into captureMessage's tags.
  it("passes caller `tags` through to captureMessage (sibling parity with report/warn)", () => {
    infoSilentFallback(null, {
      feature: "email-triage",
      op: "deadline-repin-sweep-complete",
      message: "sweep",
      tags: { repin_suppressed: "no", repin_excluded: "yes" },
      extra: { pinged: 0 },
    });

    const [, payload] = mockCaptureMessage.mock.calls[0];
    expect(payload.tags).toMatchObject({
      feature: "email-triage",
      op: "deadline-repin-sweep-complete",
      repin_suppressed: "no",
      repin_excluded: "yes",
    });
  });

  it("routes userId → userIdHash through the same hashExtraUserId boundary", () => {
    infoSilentFallback(null, {
      feature: "some-feature",
      extra: { userId: "u9", count: 3 },
    });

    const [, payload] = mockCaptureMessage.mock.calls[0];
    expect(payload.extra.userIdHash).toBe(expectedHashFor("u9"));
    expect(payload.extra).not.toHaveProperty("userId");
    expect(payload.extra).toMatchObject({ count: 3 });

    const [pinoCtx] = mockLoggerInfo.mock.calls[0];
    expect(pinoCtx).not.toHaveProperty("userId");
    expect(pinoCtx.userIdHash).toBe(expectedHashFor("u9"));
  });

  it("supports the Error → captureException(level=info) symmetry path", () => {
    const err = new Error("non-fatal context");
    infoSilentFallback(err, { feature: "f", op: "o" });

    expect(mockCaptureException).toHaveBeenCalledTimes(1);
    const [errArg, payload] = mockCaptureException.mock.calls[0];
    expect(errArg).toBe(err);
    expect(payload.level).toBe("info");
    expect(payload.tags).toEqual({ feature: "f", op: "o" });
  });
});

describe("mirrorP0Deduped — userIdHash pseudonymization", () => {
  it("emits userIdHash in Sentry tags + extra; never raw userId; pino receives userIdHash", () => {
    const err = new Error("write-boundary violation");
    mirrorP0Deduped(err, {
      op: "cc.write-boundary",
      userId: "user-7",
      conversationId: "conv-9",
    });

    expect(mockCaptureException).toHaveBeenCalledTimes(1);
    const [errArg, payload] = mockCaptureException.mock.calls[0];
    expect(errArg).toBe(err);
    expect(payload.level).toBe("fatal");
    expect(payload.tags).toEqual({
      op: "cc.write-boundary",
      scope: "p0_deduped",
      userIdHash: expectedHashFor("user-7"),
    });
    expect(payload.tags).not.toHaveProperty("userId");
    expect(payload.extra).toMatchObject({
      op: "cc.write-boundary",
      userIdHash: expectedHashFor("user-7"),
      conversationId: "conv-9",
      severity: "breach_attempt",
    });
    expect(payload.extra).not.toHaveProperty("userId");
    expect(typeof payload.extra.first_seen_at).toBe("string");

    // pino mirror
    const [pinoCtx, pinoMsg] = mockLoggerError.mock.calls[0];
    expect(pinoCtx).toMatchObject({
      err,
      op: "cc.write-boundary",
      userIdHash: expectedHashFor("user-7"),
      conversationId: "conv-9",
    });
    expect(pinoCtx).not.toHaveProperty("userId");
    expect(pinoMsg).toBe("p0 deduped mirror: cc.write-boundary");
  });

  it("dedupes the second call within TTL for same (userId, op, conversationId)", () => {
    const err = new Error("x");
    mirrorP0Deduped(err, { op: "o", userId: "u", conversationId: "c" });
    mirrorP0Deduped(err, { op: "o", userId: "u", conversationId: "c" });
    expect(mockCaptureException).toHaveBeenCalledTimes(1);
    expect(mockLoggerError).toHaveBeenCalledTimes(1);
  });

  it("does NOT dedupe when conversationId differs (cross-conversation breach)", () => {
    const err = new Error("x");
    mirrorP0Deduped(err, { op: "o", userId: "u", conversationId: "c1" });
    mirrorP0Deduped(err, { op: "o", userId: "u", conversationId: "c2" });
    expect(mockCaptureException).toHaveBeenCalledTimes(2);
  });

  // #4656 items 1+2+3 — the BYOK Art.33 breach routes through this primitive.
  // The `byok_art_33_breach` Sentry rule (issue-alerts.tf) is filter_match="all"
  // on BOTH `feature=byok-delegations` AND `art_33_breach=true`, so the event
  // MUST carry both tags or the rule never fires. `delegationId` is the
  // cross-tenant-leak clock-anchor identifier.
  it("sets feature + art_33_breach tags and delegationId extra when the Art.33 options are passed", () => {
    const err = new Error("cross-tenant BYOK key leak");
    mirrorP0Deduped(err, {
      op: "cross-tenant-violation",
      userId: "grantor-1",
      conversationId: "conv-x",
      feature: "byok-delegations",
      art33Breach: true,
      delegationId: "deadbeef",
    });

    expect(mockCaptureException).toHaveBeenCalledTimes(1);
    const [, payload] = mockCaptureException.mock.calls[0];
    expect(payload.level).toBe("fatal");
    expect(payload.tags).toMatchObject({
      op: "cross-tenant-violation",
      scope: "p0_deduped",
      feature: "byok-delegations",
      art_33_breach: "true",
    });
    expect(payload.extra).toMatchObject({
      delegationId: "deadbeef",
      severity: "breach_attempt",
    });
    expect(typeof payload.extra.first_seen_at).toBe("string");
  });

  it("omits feature/art_33_breach tags and delegationId extra when the options are absent", () => {
    const err = new Error("plain write-boundary violation");
    mirrorP0Deduped(err, {
      op: "cc.write-boundary",
      userId: "u",
      conversationId: "c",
    });

    const [, payload] = mockCaptureException.mock.calls[0];
    expect(payload.tags).not.toHaveProperty("feature");
    expect(payload.tags).not.toHaveProperty("art_33_breach");
    expect(payload.extra).not.toHaveProperty("delegationId");
  });

  // #4656 item 2 — capture-swallow resilience: the guaranteed pino mirror fires
  // BEFORE the try/catch-guarded Sentry capture, so a swallowed/rate-limited
  // Sentry call still leaves a durable stdout breach record. This is the
  // load-bearing property for the BYOK Art.33 path when Sentry is down.
  it("still emits the pino mirror when the Sentry capture throws (swallowed)", () => {
    mockCaptureException.mockImplementationOnce(() => {
      throw new Error("Sentry uninitialized / rate-limited");
    });
    const err = new Error("cross-tenant BYOK key leak");

    // Must not propagate the swallowed Sentry error to the caller.
    expect(() =>
      mirrorP0Deduped(err, {
        op: "cross-tenant-violation",
        userId: "grantor-1",
        conversationId: "conv-x",
        feature: "byok-delegations",
        art33Breach: true,
        delegationId: "deadbeef",
      }),
    ).not.toThrow();

    expect(mockCaptureException).toHaveBeenCalledTimes(1);
    expect(mockLoggerError).toHaveBeenCalledTimes(1);
    const [pinoCtx, pinoMsg] = mockLoggerError.mock.calls[0];
    expect(pinoCtx).toMatchObject({ op: "cross-tenant-violation" });
    expect(pinoMsg).toBe("p0 deduped mirror: cross-tenant-violation");
  });
});
