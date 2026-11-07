/**
 * Who may see the action text of an approval card (#9601, ADR-309 flip item 1).
 *
 * Pure and synchronous on purpose. `canSeeAction` is the chokepoint for the REATTACH emit site (reattach.ts): one function
 * with a truth table (test/approval/card-visibility.test.ts), and the whole-`server/` sink scan
 * (test/approval/render-sink-scan.test.ts) pins who calls the renderer. The FIRST send (gate-flow.ts) does not go through
 * it: that frame goes to the proposing session user, who sees their own freshly canonicalised action, and it carries no
 * label other than the literal "you" (`isVerifiedRequester`). The call sites do their own single `await`.
 *
 * Fail closed: a runtime value that is not exactly what the type says (the stored row is only cast by `parseApprovalRow`)
 * never widens access. Only a literal boolean `true` makes an Owner; ids are compared with strict equality and only when both
 * are non-empty strings, so NULL, `undefined`, "" and a mismatch all mean "not the requester".
 */

/**
 * Reads the label for the card (an Owner's view of who raised the request). The workspace is the ROW's, never the attaching
 * session's. Resolves to `undefined` when no label applies or the read failed (the key is then omitted, never a guess).
 * Declared here, not in requester-label.ts, because reattach.ts and ws-handler.ts import the TYPE without importing the
 * service-role module (the importer pin in render-sink-scan.test.ts counts only real importers of that module).
 */
export type RequesterLabelFn = (
  workspaceId: string,
  viewerUserId: string,
  requestedBy: string | null | undefined,
) => Promise<string | undefined>;

const isId = (v: unknown): v is string => typeof v === "string" && v.length > 0;

/** True when `viewerUserId` is the verified `requested_by_user_id` of the row (both non-empty strings, strict equality). */
export function isVerifiedRequester(viewerUserId: unknown, requestedBy: unknown): boolean {
  return isId(viewerUserId) && isId(requestedBy) && viewerUserId === requestedBy;
}

/** The full action text is shown only to an Owner or to the row's verified requester. */
export function canSeeAction(viewerUserId: string, isOwner: boolean, requestedBy: string | null | undefined): boolean {
  return isOwner === true || isVerifiedRequester(viewerUserId, requestedBy);
}
