// #11599 — the authentication-mode code pair is spelled in three places that cannot import each other: the server leaf
// (`AUTH_MODE_UNRESOLVED_CAUSES`), the client predicate (`isAuthModeErrorCode`, lib/ cannot import server code) and the wire
// schema. This pins the three together, with a negative control on each so none can pass by accepting everything.
import { describe, expect, it } from "vitest";

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

  it.each(["key_invalid", "rate_limited", "auth_mode", "", "AUTH_MODE_UNRESOLVED", null, undefined])(
    "%s is not an authentication-mode code",
    (code) => {
      expect(isAuthModeErrorCode(code as string | null | undefined)).toBe(false);
    },
  );

  it("the wire schema still rejects an unknown code (the positive rows are not satisfied by an open enum)", () => {
    expect(wsMessageSchema.safeParse(frame("auth_mode_unknown_future")).success).toBe(false);
  });
});
