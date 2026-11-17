/**
 * #9601: the single decision functions behind the reattach redaction and the first-send requester label.
 *
 * `canSeeAction(viewer, isOwner, requestedBy)` is true for an Owner, or for the verified requester (both ids non-empty
 * strings, strict `===`); `isVerifiedRequester` is that second half on its own (the first send's "you" and the reattach
 * and landing labels use it). Synchronous truth tables, including runtime garbage: `parseApprovalRow` only casts.
 */
import { describe, expect, it } from "vitest";
import { canSeeAction, isVerifiedRequester } from "@/server/approval/card-visibility";
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

describe("isVerifiedRequester truth table", () => {
  it("true only for two equal non-empty strings", () => {
    expect(isVerifiedRequester(OWNER_ID, OWNER_ID)).toBe(true);
    expect(isVerifiedRequester(MEMBER_ID, MEMBER_ID)).toBe(true);
  });

  it("false for a different id, NULL, undefined and empty (including empty equals empty)", () => {
    expect(isVerifiedRequester(MEMBER_ID, REQUESTER_ID)).toBe(false);
    expect(isVerifiedRequester(MEMBER_ID, null)).toBe(false);
    expect(isVerifiedRequester(MEMBER_ID, undefined)).toBe(false);
    expect(isVerifiedRequester(MEMBER_ID, "")).toBe(false);
    expect(isVerifiedRequester("", "")).toBe(false);
    expect(isVerifiedRequester(undefined, undefined)).toBe(false);
    expect(isVerifiedRequester(null, null)).toBe(false);
  });

  it("false for ids that differ only by case (no normalisation)", () => {
    expect(isVerifiedRequester(MEMBER_ID.toUpperCase(), MEMBER_ID)).toBe(false);
  });

  it("false for non-string ids even when strictly equal", () => {
    expect(isVerifiedRequester(7, 7)).toBe(false);
    const o = {};
    expect(isVerifiedRequester(o, o)).toBe(false);
  });

  it("canSeeAction is exactly (owner === true) || isVerifiedRequester over a grid, including a truthy non-boolean owner flag", () => {
    const viewers = [OWNER_ID, MEMBER_ID, ""];
    const requesters = [REQUESTER_ID, MEMBER_ID, OWNER_ID, null, undefined, ""];
    const flags = [true, false, "true", "owner", 1, {}, [], undefined, null];
    for (const v of viewers) {
      for (const r of requesters) {
        for (const f of flags) {
          expect(canSeeAction(v, asAny(f), r), `${v}|${String(f)}|${String(r)}`).toBe(f === true || isVerifiedRequester(v, r));
        }
      }
    }
  });
});
