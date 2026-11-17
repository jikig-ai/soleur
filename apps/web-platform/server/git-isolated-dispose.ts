// The best-effort `dispose()` of an isolated git directory, shared by the approved cc push (server/push-branch.ts) and the
// KB sync (server/kb-sync-publish.ts, server/session-sync.ts, server/workspace-sync.ts). A leaf that imports neither
// push-branch.ts nor kb-sync-publish.ts, so the pull modules dispose without reaching either (#12718, ruling D25(4)).
import type { IsolatedPushDirHandle } from "./git-isolated-push-dir";
import { reportSilentFallback } from "./observability";

/** Static Sentry message: a Sentry group is one condition. The op and feature are unchanged since the cc push owned it. */
const DISPOSE_FAILED_MESSAGE = "cc-push: the isolated push directory could not be removed";

/** A failing `dispose()` never changes the caller's result: it is reported by errno code only (no path, no message). */
export function disposeIsolated(isolated: IsolatedPushDirHandle | undefined): void {
  if (!isolated) return;
  try {
    isolated.dispose();
  } catch (err) {
    const code = (err as { code?: unknown } | undefined)?.code;
    const cls = typeof code === "string" && /^E[A-Z]+$/.test(code) ? code : "unknown";
    reportSilentFallback(null, {
      feature: "cc-push",
      op: "isolated-dir-dispose-failed",
      message: DISPOSE_FAILED_MESSAGE,
      tags: { class: cls },
      extra: { class: cls },
    });
  }
}
