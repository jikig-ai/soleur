/**
 * #9601: the single decision functions behind the reattach redaction and the first-send requester label.
 *
 * `canSeeAction(viewer, isOwner, requestedBy)` is true for an Owner, or for the verified requester (both ids non-empty
 * strings, strict `===`). `requesterKind` says how the card learns the requester: `self` (no read), `lookup` (an Owner
 * who is not the requester) or `none`. Synchronous truth tables, including runtime garbage: `parseApprovalRow` only casts.
 */
import { describe, expect, it } from "vitest";
import { canSeeAction, requesterKind } from "@/server/approval/card-visibility";
import { MEMBER_ID, OWNER_ID, REQUESTER_ID } from "./fixtures";

const asAny = (v: unknown) => v as never;

describe("canSeeAction truth table", () => {
  it("an Owner sees the action whoever the requester is", () => {
    expect(canSeeAction(OWNER_ID, true, REQUESTER_ID)).toBe(true);
    expect(canSeeAction(OWNER_ID, true, null)).toBe(true);
    expect(canSeeAction(OWNER_ID, true, undefined)).toBe(true);
    expect(canSeeAction(OWNER_ID, true, OWNER_ID)).toBe(true);
  });

  it("a member who is the verified requester sees the action (equal non-empty ids)", () => {
    expect(canSeeAction(MEMBER_ID, false, MEMBER_ID)).toBe(true);
  });

  it("a member who is not the requester does not", () => {
    expect(canSeeAction(MEMBER_ID, false, REQUESTER_ID)).toBe(false);
  });

  it("NULL, undefined and empty requester ids never match", () => {
    expect(canSeeAction(MEMBER_ID, false, null)).toBe(false);
    expect(canSeeAction(MEMBER_ID, false, undefined)).toBe(false);
    expect(canSeeAction(MEMBER_ID, false, "")).toBe(false);
  });

  it("empty equals empty is NOT a match (an empty attaching id never counts as the requester)", () => {
    expect(canSeeAction("", false, "")).toBe(false);
    expect(canSeeAction(asAny(undefined), false, asAny(undefined))).toBe(false);
    expect(canSeeAction(asAny(null), false, asAny(null))).toBe(false);
  });

  it("ids that differ only by case do not match (strict equality, no normalisation)", () => {
    expect(canSeeAction(MEMBER_ID.toUpperCase(), false, MEMBER_ID)).toBe(false);
  });

  it("non-string ids never match, even when they are strictly equal", () => {
    expect(canSeeAction(asAny(7), false, asAny(7))).toBe(false);
    expect(canSeeAction(asAny({}), false, asAny({}))).toBe(false);
  });

  it("only a literal boolean true makes an Owner (runtime garbage in the owner slot is a non-Owner)", () => {
    expect(canSeeAction(MEMBER_ID, asAny("owner"), REQUESTER_ID)).toBe(false);
    expect(canSeeAction(MEMBER_ID, asAny(1), REQUESTER_ID)).toBe(false);
    expect(canSeeAction(MEMBER_ID, asAny(undefined), REQUESTER_ID)).toBe(false);
  });
});

describe("requesterKind truth table", () => {
  it("self: the verified requester, in any role, needs no read", () => {
    expect(requesterKind(OWNER_ID, true, OWNER_ID)).toBe("self");
    expect(requesterKind(MEMBER_ID, false, MEMBER_ID)).toBe("self");
  });

  it("lookup: an Owner who is not the requester (including a NULL or empty requester)", () => {
    expect(requesterKind(OWNER_ID, true, REQUESTER_ID)).toBe("lookup");
    expect(requesterKind(OWNER_ID, true, null)).toBe("lookup");
    expect(requesterKind(OWNER_ID, true, undefined)).toBe("lookup");
    expect(requesterKind(OWNER_ID, true, "")).toBe("lookup");
  });

  it("none: a member who is not the requester never gets a label, whatever the requester field holds", () => {
    expect(requesterKind(MEMBER_ID, false, REQUESTER_ID)).toBe("none");
    expect(requesterKind(MEMBER_ID, false, null)).toBe("none");
    expect(requesterKind(MEMBER_ID, false, undefined)).toBe("none");
    expect(requesterKind(MEMBER_ID, false, "")).toBe("none");
    expect(requesterKind("", false, "")).toBe("none");
  });

  it("an empty attaching id equal to an empty requester is not `self`", () => {
    expect(requesterKind("", true, "")).toBe("lookup");
    expect(requesterKind("", false, "")).toBe("none");
  });

  it("agrees with canSeeAction: `none` exactly when the action is hidden", () => {
    const viewers: Array<[string, boolean]> = [
      [OWNER_ID, true],
      [MEMBER_ID, false],
      ["", false],
    ];
    const requesters = [REQUESTER_ID, MEMBER_ID, OWNER_ID, null, undefined, ""];
    for (const [v, o] of viewers) {
      for (const r of requesters) {
        expect(requesterKind(v, o, r) === "none", `${v}|${o}|${String(r)}`).toBe(!canSeeAction(v, o, r));
      }
    }
  });
});
