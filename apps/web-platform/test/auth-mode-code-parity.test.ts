// #11599 — the authentication-mode code pair is spelled in three places that cannot import each other: the server leaf
// (`AUTH_MODE_UNRESOLVED_CAUSES`), the client predicate (`isAuthModeErrorCode`, lib/ cannot import server code) and the wire
// schema. This pins the three together, with a negative control on each so none can pass by accepting everything.
import { describe, expect, it } from "vitest";
import { z } from "zod";

import { AUTH_MODE_UNRESOLVED_CAUSES } from "@/server/auth-mode-error";
import { isAuthModeErrorCode } from "@/lib/types";
import { wsMessageSchema } from "@/lib/ws-zod-schemas";

const frame = (errorCode: string) => ({ type: "error", message: "m", errorCode });

describe("authentication-mode code parity", () => {
  it("the leaf lists exactly the two causes", () => {
    expect([...AUTH_MODE_UNRESOLVED_CAUSES]).toEqual(["auth_mode_unresolved", "auth_mode_unavailable"]);
  });

  it.each([...AUTH_MODE_UNRESOLVED_CAUSES])("%s is accepted by the client predicate and the wire schema", (code) => {
    expect(isAuthModeErrorCode(code)).toBe(true);
    expect(wsMessageSchema.safeParse(frame(code)).success).toBe(true);
  });

  it.each(["key_invalid", "rate_limited", "auth_mode", "auth_mode_unknown_future", "", "AUTH_MODE_UNRESOLVED", null, undefined])(
    "%s is not an authentication-mode code",
    (code) => {
      expect(isAuthModeErrorCode(code as string | null | undefined)).toBe(false);
    },
  );

  it("the wire schema still rejects an unknown code (the positive rows are not satisfied by an open enum)", () => {
    expect(wsMessageSchema.safeParse(frame("auth_mode_unknown_future")).success).toBe(false);
  });

  // A third auth_mode_* value added to the wire enum without the leaf list (or the client predicate) must fail here, not pass
  // because the probe string above happens not to be it: read the schema's own members.
  it("the wire enum holds exactly the leaf causes among its auth_mode_* members", () => {
    const enums: string[][] = [];
    const walk = (node: unknown): void => {
      if (Array.isArray(node)) return node.forEach(walk);
      if (node === null || typeof node !== "object") return;
      const rec = node as Record<string, unknown>;
      if (Array.isArray(rec.enum) && rec.enum.includes("auth_mode_unresolved")) enums.push(rec.enum as string[]);
      Object.values(rec).forEach(walk);
    };
    walk(z.toJSONSchema(wsMessageSchema, { unrepresentable: "any" }));
    // Non-vacuity: the error code enum was found exactly once, and it also holds the unrelated codes.
    expect(enums).toHaveLength(1);
    expect(enums[0]).toContain("key_invalid");
    const members = enums[0].filter((c) => c.startsWith("auth_mode_"));
    expect([...members].sort()).toEqual([...AUTH_MODE_UNRESOLVED_CAUSES].sort());
  });
});
