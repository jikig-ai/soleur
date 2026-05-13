import { describe, test, expect, vi } from "vitest";
import { createHmac } from "node:crypto";

// sentry-scrub rename special-case — #3710 PR-B deliverable 3.
//
// The scrubber walks Sentry event payloads at the `beforeSend` /
// `beforeBreadcrumb` boundary. The rename special-case rewrites
// `userId` / `user_id` keys (case-insensitive, at any nesting depth) to
// `userIdHash`, computing the hash via the shared `hashUserIdValue`
// primitive (ADR-029 I4). The rename WINS over the redact branch
// (`SENSITIVE_LOWER.has`) so a future addition of `userId` to
// `SENSITIVE_KEY_NAMES` does not bury the pseudonymous identifier under
// `[Redacted]`.

vi.hoisted(() => {
  process.env.SENTRY_USERID_PEPPER = "test-pepper";
});

const TEST_PEPPER = "test-pepper";
const expectedHashFor = (userId: string) =>
  createHmac("sha256", TEST_PEPPER).update(userId).digest("hex");

import { scrubSentryEvent, scrubSentryBreadcrumb } from "../server/sentry-scrub";

describe("scrubSentryEvent — userId / user_id rename to userIdHash", () => {
  test("top-level `userId` in extras → renamed to `userIdHash` with hashed value", () => {
    const event = { extra: { userId: "abc" } };
    const result = scrubSentryEvent(event) as {
      extra: Record<string, unknown>;
    };
    expect(result.extra).toEqual({ userIdHash: expectedHashFor("abc") });
    expect(result.extra).not.toHaveProperty("userId");
  });

  test("snake_case `user_id` in tags → renamed to `userIdHash`", () => {
    const event = { tags: { user_id: "abc" } };
    const result = scrubSentryEvent(event) as {
      tags: Record<string, unknown>;
    };
    expect(result.tags).toEqual({ userIdHash: expectedHashFor("abc") });
    expect(result.tags).not.toHaveProperty("user_id");
  });

  test("mixed: rename + redact both apply in same extra object", () => {
    const event = { extra: { userId: "abc", apiKey: "secret" } };
    const result = scrubSentryEvent(event) as {
      extra: Record<string, unknown>;
    };
    expect(result.extra).toEqual({
      userIdHash: expectedHashFor("abc"),
      apiKey: "[Redacted]",
    });
  });

  test("case-insensitive: `UserId` / `USER_ID` / `User_Id` all renamed", () => {
    const event = {
      extra: { UserId: "a" },
      tags: { USER_ID: "b" },
      contexts: { x: { User_Id: "c" } },
    };
    const result = scrubSentryEvent(event) as {
      extra: Record<string, unknown>;
      tags: Record<string, unknown>;
      contexts: { x: Record<string, unknown> };
    };
    expect(result.extra).toEqual({ userIdHash: expectedHashFor("a") });
    expect(result.tags).toEqual({ userIdHash: expectedHashFor("b") });
    expect(result.contexts.x).toEqual({ userIdHash: expectedHashFor("c") });
  });

  test("nested: contexts.request.extra.userId is renamed (recursive walk)", () => {
    const event = {
      contexts: { request: { extra: { userId: "deep" } } },
    };
    const result = scrubSentryEvent(event) as {
      contexts: { request: { extra: Record<string, unknown> } };
    };
    expect(result.contexts.request.extra).toEqual({
      userIdHash: expectedHashFor("deep"),
    });
  });

  test("cycle / shared-DAG: object referenced from two sub-trees is renamed consistently via memo", () => {
    const shared = { userId: "shared" } as Record<string, unknown>;
    const event = { extra: { a: shared, b: shared } };
    const result = scrubSentryEvent(event) as {
      extra: { a: Record<string, unknown>; b: Record<string, unknown> };
    };
    expect(result.extra.a).toEqual({ userIdHash: expectedHashFor("shared") });
    expect(result.extra.b).toEqual({ userIdHash: expectedHashFor("shared") });
    // Memo guarantees identity preservation across the shared reference.
    expect(result.extra.a).toBe(result.extra.b);
  });

  test("both `userId` and `userIdHash` present → preserve preset `userIdHash`, drop raw `userId`", () => {
    // Defensive precedence: when a caller has already emitted a pseudonymous
    // `userIdHash`, the scrubber MUST NOT overwrite it with a fresh hash of
    // the raw `userId` (which would be a double-hash if the raw value were
    // actually already a hash, and would otherwise discard the caller's
    // explicit hash choice). Drop the raw `userId` key and preserve the
    // existing `userIdHash`.
    const event = { extra: { userId: "raw", userIdHash: "preset" } };
    const result = scrubSentryEvent(event) as {
      extra: Record<string, unknown>;
    };
    expect(result.extra).toEqual({ userIdHash: "preset" });
    expect(result.extra).not.toHaveProperty("userId");
  });

  test("null/undefined userId values resolve to the `pepper_unset_null` sentinel", () => {
    const event = { extra: { userId: null } };
    const result = scrubSentryEvent(event) as {
      extra: Record<string, unknown>;
    };
    expect(result.extra).toEqual({ userIdHash: "pepper_unset_null" });
  });

  test("scrubSentryBreadcrumb applies the rename to breadcrumb.data", () => {
    const breadcrumb = { data: { userId: "bc" } };
    const result = scrubSentryBreadcrumb(breadcrumb) as {
      data: Record<string, unknown>;
    };
    expect(result.data).toEqual({ userIdHash: expectedHashFor("bc") });
  });
});
