// The best-effort `dispose()` of an isolated git directory, shared by the approved cc push (server/push-branch.ts), the
// KB sync (server/kb-sync-publish.ts, server/session-sync.ts), the self-heal (server/workspace-sync.ts) and the held-count
// refresh (server/kb-sync-held-refresh.ts). A leaf that imports neither
// push-branch.ts nor kb-sync-publish.ts, so the pull modules dispose without reaching either (#12718, ruling D25(4)).
import type { IsolatedPushDirHandle } from "./git-isolated-push-dir";
import { reportSilentFallback } from "./observability";

/**
 * Static Sentry messages, one per owner: a Sentry group is one condition. Each key is the `feature` the caller's other
 * Sentry ops already use, so a filter on that feature finds the leak next to the caller's own events.
 */
const DISPOSE_FAILED_MESSAGE = {
  "cc-push": "cc-push: the isolated push directory could not be removed",
  "session-sync": "KB sync: the isolated directory could not be removed",
  "kb-route-helpers": "KB self-heal: the isolated directory could not be removed",
  "kb-sync-held": "KB sync held count: the isolated directory could not be removed",
} as const;

/** Which caller's directory leaked (simplicity H3: a KB-sync leak no longer reads as the cc push's). */
export type DisposeFeature = keyof typeof DISPOSE_FAILED_MESSAGE;

/** A failing `dispose()` never changes the caller's result: it is reported by errno code only (no path, no message). */
export function disposeIsolated(isolated: IsolatedPushDirHandle | undefined, feature: DisposeFeature = "cc-push"): void {
  if (!isolated) return;
  try {
    isolated.dispose();
  } catch (err) {
    const code = (err as { code?: unknown } | undefined)?.code;
    const cls = typeof code === "string" && /^E[A-Z]+$/.test(code) ? code : "unknown";
    reportSilentFallback(null, {
      feature,
      op: "isolated-dir-dispose-failed",
      message: DISPOSE_FAILED_MESSAGE[feature],
      tags: { class: cls },
      extra: { class: cls },
    });
  }
}
