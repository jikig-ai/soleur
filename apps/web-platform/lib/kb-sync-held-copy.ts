// #12714 Settings Project card notice: code files the KB-only sync holds back from the repository's main branch.
//
// Strings are the CPO's V6 copy VERBATIM (decision-challenges.md row V6; plan "V6 amendments"), one pure function per
// audience and route state, singular for n = 1. Each string stays true before the publish, after it and after the
// approval: the count persists until the merge reaches the workspace. A predicate blip ("unknown") never shows the
// no-route sentence. The UI never names the agent tool (C5) and never says "not on GitHub" (D23); the count is the only
// detail shown (C4: no paths, messages or authors).
//
// Render bound (D29(8)): only an integer in 1..10000 renders; 0, null and anything else give no notice. Callers render
// the returned string as a React text child, never as HTML.

/** `{ownerLabel}` fallback when the workspace owner's label is unknown (V5, stands under V6). */
export const HELD_OWNER_LABEL_FALLBACK = "your workspace owner";

/** Upper bound of `workspaces.kb_sync_held_files` (migration 187's range check). */
export const HELD_FILES_RENDER_MAX = 10_000;

export type HeldNoticeAudience = "owner" | "member";
/** The publish-route predicate's result (`isCcGithubPushRouteAvailable`): "unknown" is a read error or timeout. */
export type HeldRouteState = "available" | "unavailable" | "unknown";

export function isRenderableHeldCount(n: unknown): n is number {
  return typeof n === "number" && Number.isInteger(n) && n >= 1 && n <= HELD_FILES_RENDER_MAX;
}

function label(ownerLabel: string | null | undefined): string {
  const t = ownerLabel?.trim();
  return t ? t : HELD_OWNER_LABEL_FALLBACK;
}

export function heldOwnerRouteAvailable(n: number): string {
  return n === 1
    ? "1 changed code file is not on your repository's main branch yet. Nothing is lost: the change stays in your workspace. To publish it, ask your agent to push it to a new branch and approve the push, then open a pull request for that branch on GitHub and merge it. If you already did, this notice clears once the merge reaches your workspace."
    : `${n} changed code files are not on your repository's main branch yet. Nothing is lost: the changes stay in your workspace. To publish them, ask your agent to push them to a new branch and approve the push, then open a pull request for that branch on GitHub and merge it. If you already did, this notice clears once the merge reaches your workspace.`;
}

export function heldOwnerNoRoute(n: number): string {
  return n === 1
    ? "1 changed code file is not on your repository's main branch yet. Nothing is lost: the change stays in your workspace. Publishing code changes is not available for this workspace."
    : `${n} changed code files are not on your repository's main branch yet. Nothing is lost: the changes stay in your workspace. Publishing code changes is not available for this workspace.`;
}

export function heldOwnerTransient(n: number): string {
  return n === 1
    ? "1 changed code file is not on your repository's main branch yet. Nothing is lost: the change stays in your workspace. Whether your agent can publish it could not be checked right now. Reload this page to check again."
    : `${n} changed code files are not on your repository's main branch yet. Nothing is lost: the changes stay in your workspace. Whether your agent can publish them could not be checked right now. Reload this page to check again.`;
}

export function heldMemberRouteAvailable(n: number, ownerLabel: string | null | undefined): string {
  const owner = label(ownerLabel);
  return n === 1
    ? `1 changed code file is not on the repository's main branch yet. Nothing is lost: the change stays in the workspace. To publish it, ask your agent to push it to a new branch, then ask ${owner} to approve the push and merge the branch on GitHub. If this was already done, this notice clears once the merge reaches the workspace.`
    : `${n} changed code files are not on the repository's main branch yet. Nothing is lost: the changes stay in the workspace. To publish them, ask your agent to push them to a new branch, then ask ${owner} to approve the push and merge the branch on GitHub. If this was already done, this notice clears once the merge reaches the workspace.`;
}

export function heldMemberNoRoute(n: number): string {
  return n === 1
    ? "1 changed code file is not on the repository's main branch yet. Nothing is lost: the change stays in the workspace."
    : `${n} changed code files are not on the repository's main branch yet. Nothing is lost: the changes stay in the workspace.`;
}

export function heldMemberTransient(n: number): string {
  return n === 1
    ? "1 changed code file is not on the repository's main branch yet. Nothing is lost: the change stays in the workspace. Whether your agent can publish it could not be checked right now. Reload this page to check again."
    : `${n} changed code files are not on the repository's main branch yet. Nothing is lost: the changes stay in the workspace. Whether your agent can publish them could not be checked right now. Reload this page to check again.`;
}

export interface KbSyncHeldNoticeInput {
  readonly audience: HeldNoticeAudience;
  readonly route: HeldRouteState;
  readonly count: unknown;
  readonly ownerLabel?: string | null;
}

/** The V6 notice for this audience and route state, or `null` when nothing is shown (n = 0, null, out of bounds). */
export function kbSyncHeldNotice({ audience, route, count, ownerLabel }: KbSyncHeldNoticeInput): string | null {
  if (!isRenderableHeldCount(count)) return null;
  if (audience === "owner") {
    if (route === "available") return heldOwnerRouteAvailable(count);
    if (route === "unavailable") return heldOwnerNoRoute(count);
    return heldOwnerTransient(count);
  }
  if (route === "available") return heldMemberRouteAvailable(count, ownerLabel);
  if (route === "unavailable") return heldMemberNoRoute(count);
  return heldMemberTransient(count);
}
