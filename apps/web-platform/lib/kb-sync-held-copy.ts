// #12714 Settings Project card notice and Disconnect dialog warning: code files the KB-only sync holds back from the
// repository's main branch.
//
// Strings are the CPO's copy VERBATIM: V6 (decision-challenges.md; plan "V6 amendments") as amended by V7 (no "Nothing is
// lost": Disconnect deletes the workspace), V8 (the Disconnect dialog), V9 (how `{n}` is printed), V10 (role unknown) and
// V11 (the clearance hedge), review-ext-rulings.md. One pure function per audience and route state, singular for n = 1.
// Each string stays true before the publish, after it and after the approval. A predicate blip ("unknown") never shows the
// no-route sentence. The UI never names the agent tool (C5) and never says "not on GitHub" (D23); the count is the only
// detail shown (C4: no paths, messages or authors).
//
// Render bound (D29(8)): only an integer in 1..10000 renders; 0, null and anything else give no notice. This module is the
// ONE home of the bound and its predicate (arch F10, simplicity F1): the server's clamp and the agent line import both.
// Callers render the returned strings as React text children, never as HTML.

/** `{ownerLabel}` fallback when the workspace owner's label is unknown (V5, stands under V6). */
export const HELD_OWNER_LABEL_FALLBACK = "your workspace owner";

/** Upper bound of `workspaces.kb_sync_held_files` (migration 187's range check). A stored value equal to it means "at least". */
export const HELD_FILES_RENDER_MAX = 10_000;

/** Who reads the notice. `unknown`: the role lookup failed or timed out (V10), so neither the Owner nor the member steps are shown. */
export type HeldNoticeAudience = "owner" | "member" | "unknown";
/** The publish-route predicate's result (`resolveCcGithubPushRoute`): "unknown" is a read error, a timeout or a flag fallback. */
export type HeldRouteState = "available" | "unavailable" | "unknown";

export function isRenderableHeldCount(n: unknown): n is number {
  return typeof n === "number" && Number.isInteger(n) && n >= 1 && n <= HELD_FILES_RENDER_MAX;
}

/**
 * V9: how `{n}` is printed on every surface (Settings notice, Disconnect warning, agent line). The cap is a clamp, so it
 * reads "10,000 or more"; from 1,000 a fixed comma separator whatever the locale; below 1,000 a plain integer.
 */
export function formatHeldCount(n: number): string {
  if (n >= HELD_FILES_RENDER_MAX) return "10,000 or more";
  return String(n).replace(/\B(?=(\d{3})+(?!\d))/g, ",");
}

function label(ownerLabel: string | null | undefined): string {
  const t = ownerLabel?.trim();
  return t ? t : HELD_OWNER_LABEL_FALLBACK;
}

/** "1 changed code file is" / "{n} changed code files are". */
function files(n: number): string {
  return n === 1 ? "1 changed code file is" : `${formatHeldCount(n)} changed code files are`;
}

export function heldOwnerRouteAvailable(n: number): string {
  return n === 1
    ? `${files(n)} not on your repository's main branch yet. The change is kept in your workspace. To publish it, ask your agent to push it to a new branch and approve the push, then open a pull request for that branch on GitHub and merge it. If you already did, this notice should clear the next time your workspace is updated from GitHub. If it does not, ask your agent which files are still counted.`
    : `${files(n)} not on your repository's main branch yet. The changes are kept in your workspace. To publish them, ask your agent to push them to a new branch and approve the push, then open a pull request for that branch on GitHub and merge it. If you already did, this notice should clear the next time your workspace is updated from GitHub. If it does not, ask your agent which files are still counted.`;
}

export function heldOwnerNoRoute(n: number): string {
  return n === 1
    ? `${files(n)} not on your repository's main branch yet. The change is kept in your workspace. Publishing code changes is not available for this workspace.`
    : `${files(n)} not on your repository's main branch yet. The changes are kept in your workspace. Publishing code changes is not available for this workspace.`;
}

export function heldOwnerTransient(n: number): string {
  return n === 1
    ? `${files(n)} not on your repository's main branch yet. The change is kept in your workspace. Whether your agent can publish it could not be checked right now. Reload this page to check again.`
    : `${files(n)} not on your repository's main branch yet. The changes are kept in your workspace. Whether your agent can publish them could not be checked right now. Reload this page to check again.`;
}

export function heldMemberRouteAvailable(n: number, ownerLabel: string | null | undefined): string {
  const owner = label(ownerLabel);
  return n === 1
    ? `${files(n)} not on the repository's main branch yet. The change is kept in the workspace. To publish it, ask your agent to push it to a new branch, then ask ${owner} to approve the push and merge the branch on GitHub. If this was already done, this notice should clear the next time the workspace is updated from GitHub. If it does not, ask your agent which files are still counted.`
    : `${files(n)} not on the repository's main branch yet. The changes are kept in the workspace. To publish them, ask your agent to push them to a new branch, then ask ${owner} to approve the push and merge the branch on GitHub. If this was already done, this notice should clear the next time the workspace is updated from GitHub. If it does not, ask your agent which files are still counted.`;
}

export function heldMemberNoRoute(n: number): string {
  return n === 1
    ? `${files(n)} not on the repository's main branch yet. The change is kept in the workspace.`
    : `${files(n)} not on the repository's main branch yet. The changes are kept in the workspace.`;
}

export function heldMemberTransient(n: number): string {
  return n === 1
    ? `${files(n)} not on the repository's main branch yet. The change is kept in the workspace. Whether your agent can publish it could not be checked right now. Reload this page to check again.`
    : `${files(n)} not on the repository's main branch yet. The changes are kept in the workspace. Whether your agent can publish them could not be checked right now. Reload this page to check again.`;
}

/** V10: the role lookup failed, so the only string true for both an Owner and a member. The route state is ignored. */
export function heldRoleUnknown(n: number): string {
  return n === 1
    ? `${files(n)} not on the repository's main branch yet. The change is kept in the workspace. Your role in this workspace could not be checked right now, so the steps to publish it are not shown. Reload this page to check again.`
    : `${files(n)} not on the repository's main branch yet. The changes are kept in the workspace. Your role in this workspace could not be checked right now, so the steps to publish them are not shown. Reload this page to check again.`;
}

export interface KbSyncHeldNoticeInput {
  readonly audience: HeldNoticeAudience;
  readonly route: HeldRouteState;
  readonly count: unknown;
  readonly ownerLabel?: string | null;
}

function assertNever(x: never): never {
  throw new Error(`kb-sync-held-copy: unhandled value ${String(x)}`);
}

/** The notice for this audience and route state, or `null` when nothing is shown (n = 0, null, out of bounds). */
export function kbSyncHeldNotice({ audience, route, count, ownerLabel }: KbSyncHeldNoticeInput): string | null {
  if (!isRenderableHeldCount(count)) return null;
  switch (audience) {
    case "unknown":
      return heldRoleUnknown(count);
    case "owner":
      switch (route) {
        case "available":
          return heldOwnerRouteAvailable(count);
        case "unavailable":
          return heldOwnerNoRoute(count);
        case "unknown":
          return heldOwnerTransient(count);
        default:
          return assertNever(route);
      }
    case "member":
      switch (route) {
        case "available":
          return heldMemberRouteAvailable(count, ownerLabel);
        case "unavailable":
          return heldMemberNoRoute(count);
        case "unknown":
          return heldMemberTransient(count);
        default:
          return assertNever(route);
      }
    default:
      return assertNever(audience);
  }
}

/**
 * V8: the warning paragraph ABOVE the Disconnect dialog's own paragraph, or null when the count does not render. The
 * publish step is given only when the route is available: on a blip (or an unknown role, which the caller passes as
 * "unknown") the dialog gives no instruction rather than a wrong one. A caution, not an error: nothing failed.
 */
export function disconnectHeldWarning(count: unknown, route: HeldRouteState): string | null {
  if (!isRenderableHeldCount(count)) return null;
  const one = count === 1;
  const base = `${files(count)} not on your repository's main branch yet, and disconnecting deletes ${one ? "it" : "them"} with your workspace files.`;
  if (route !== "available") return base;
  return one
    ? `${base} If it is not on a branch on GitHub yet, cancel and ask your agent to push it to a new branch, then approve the push.`
    : `${base} If they are not on a branch on GitHub yet, cancel and ask your agent to push them to a new branch, then approve the push.`;
}

/**
 * V8: the dialog's own paragraph around the repository name (rendered as `{before}<repo name>{after}`). With a renderable
 * count it is unchanged (the warning above carries the count); without one (null, 0, out of range, or the separate
 * select failed) it gains a clause that is true in every state, including uncommitted edits, which are never counted.
 */
export function disconnectHeldBody(count: unknown): { before: string; after: string } {
  return {
    before: "This will unlink ",
    after: isRenderableHeldCount(count)
      ? " from your account. Your workspace files will be removed. You can reconnect a repository at any time."
      : " from your account. Your workspace files will be removed, including any code changes your agent made that are not on your repository's main branch yet. You can reconnect a repository at any time.",
  };
}
