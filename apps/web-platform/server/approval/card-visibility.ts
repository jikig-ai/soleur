/**
 * PHASE 0 STUB (fail-open on purpose, replaced in Phase 2): the signatures exist so the RED tests fail on assertions,
 * not at collection.
 */

export type RequesterLabelFn = (
  workspaceId: string,
  viewerUserId: string,
  requestedBy: string | null | undefined,
) => Promise<string | undefined>;

export type RequesterKind = "self" | "lookup" | "none";

export function canSeeAction(_viewerUserId: string, _isOwner: boolean, _requestedBy: string | null | undefined): boolean {
  return true;
}

export function requesterKind(_viewerUserId: string, _isOwner: boolean, _requestedBy: string | null | undefined): RequesterKind {
  return "none";
}
