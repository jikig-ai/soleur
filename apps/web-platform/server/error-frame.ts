// ---------------------------------------------------------------------------
// The first app code frame of an error (#12600, CTO ruling D20, amending D8): a leaf module (no imports), so a test that mocks
// `@/server/observability` or `@/server/workspace-sync` with a factory still gets the real helper.
// ---------------------------------------------------------------------------

const APP_FRAME_DIRS = ["server", "app", "lib"] as const;
/** Build output directories kept in front of an app dir, so a bundle frame names the bundle it ran from (D23). */
const BUNDLE_DIRS = ["dist", ".next"] as const;
const APP_ROOT_ANCHOR = "apps/web-platform/";
const FRAME_RE = /^[\w./-]+:\d+(?::\d+)?$/;
const STACK_AT_RE = /^\s*at (?:.*?\()?([^()\s]+?):(\d+)(?::(\d+))?\)?\s*$/;

/** `rel` minus an optional leading bundle dir starts with an app dir. */
const isAppPath = (rel: string): boolean => {
  const inner = BUNDLE_DIRS.reduce((r, b) => (r.startsWith(`${b}/`) ? r.slice(b.length + 1) : r), rel);
  return APP_FRAME_DIRS.some((d) => inner.startsWith(`${d}/`));
};

/**
 * The first stack frame of `err` under the app's `server/`, `app/` or `lib/`, as a repo-relative `file:line:column` (the column
 * when the stack has one) matching `[\w./-]+:\d+(:\d+)?`, or undefined when none matches. Only the stack's `at` lines AFTER the
 * `<name>: <message>` header are read, so the message (git argv, stderr) never reaches the frame; `node:` internals and
 * `node_modules` are skipped. A code location carries no argv or user data. It only LOCATES the throw: `extra` is not part of
 * Sentry's grouping, so it splits no issue group. In production the server runs the esbuild bundle with no source maps and the
 * routes run in Next's minified server chunks, so the frame there is a release-bundle coordinate (`dist/server/index.cjs:L:C`,
 * `.next/server/chunks/<n>.js:1:C`), resolved against that release's build; the column is what localises a minified line.
 * Used by the `syncPush` outer catch (a non-`KbSyncError`) and `self-heal-failed`.
 */
export function firstAppFrame(err: unknown): string | undefined {
  if (!(err instanceof Error) || typeof err.stack !== "string") return undefined;
  const header = `${err.name}: ${err.message}`;
  const frames = err.stack.startsWith(header) ? err.stack.slice(header.length) : err.stack;
  for (const line of frames.split("\n")) {
    const m = STACK_AT_RE.exec(line);
    if (!m) continue;
    const file = m[1].replace(/\\/g, "/");
    if (file.startsWith("node:") || file.includes("/node_modules/")) continue;
    const anchor = file.lastIndexOf(APP_ROOT_ANCHOR);
    let rel: string;
    if (anchor >= 0) {
      rel = file.slice(anchor + APP_ROOT_ANCHOR.length);
    } else {
      const idx = Math.max(...APP_FRAME_DIRS.map((d) => file.lastIndexOf(`/${d}/`)));
      if (idx < 0) continue;
      const bundle = BUNDLE_DIRS.find((b) => file.slice(0, idx).endsWith(`/${b}`));
      rel = `${bundle ? `${bundle}/` : ""}${file.slice(idx + 1)}`;
    }
    if (!isAppPath(rel)) continue;
    const frame = `${rel}:${m[2]}${m[3] ? `:${m[3]}` : ""}`;
    if (FRAME_RE.test(frame)) return frame;
  }
  return undefined;
}
