/**
 * Who may see the action text of an approval card, and how the card learns who raised it (#9601, ADR-309 flip item 1).
 *
 * Pure and synchronous on purpose: every emit site of an `approval_request` frame shares these two decisions, so the
 * chokepoint is one function with a truth table (test/approval/card-visibility.test.ts) and the whole-`server/` sink scan
 * (test/approval/render-sink-scan.test.ts) pins who calls the renderer. The call sites do their own single `await`.
 *
 * Fail closed: a runtime value that is not exactly what the type says (the stored row is only cast by `parseApprovalRow`)
 * never widens access. Only a literal boolean `true` makes an Owner; ids are compared with strict equality and only when both
 * are non-empty strings, so NULL, `undefined`, "" and a mismatch all mean "not the requester".
 */

/**
 * Reads the label for the card (an Owner's view of who raised the request). The workspace is the ROW's, never the attaching
 * session's. Resolves to `undefined` when no label applies or the read failed (the key is then omitted, never a guess).
 */
export type RequesterLabelFn = (
  workspaceId: string,
  viewerUserId: string,
  requestedBy: string | null | undefined,
) => Promise<string | undefined>;

export type RequesterKind =
  /** The viewer is the verified requester: the literal "you", no read. */
  | "self"
  /** An Owner viewer who is not the requester: the labeler decides. */
  | "lookup"
  /** Neither: no label. */
  | "none";

const isId = (v: unknown): v is string => typeof v === "string" && v.length > 0;

/** True when `viewerUserId` is the verified `requested_by_user_id` of the row (both non-empty strings, strict equality). */
function isVerifiedRequester(viewerUserId: unknown, requestedBy: unknown): boolean {
  return isId(viewerUserId) && isId(requestedBy) && viewerUserId === requestedBy;
}

/** The full action text is shown only to an Owner or to the row's verified requester. */
export function canSeeAction(viewerUserId: string, isOwner: boolean, requestedBy: string | null | undefined): boolean {
  return isOwner === true || isVerifiedRequester(viewerUserId, requestedBy);
}

/** How the card for this viewer learns the requester. `none` exactly when the action text is hidden from the viewer. */
export function requesterKind(viewerUserId: string, isOwner: boolean, requestedBy: string | null | undefined): RequesterKind {
  if (isVerifiedRequester(viewerUserId, requestedBy)) return "self";
  return isOwner === true ? "lookup" : "none";
}
