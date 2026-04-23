/**
 * Canonical sandbox/host workspace path patterns shared between the server
 * label pipeline (`server/tool-labels.ts`) and the client render scrub
 * (`lib/format-assistant-text.ts`). FR2 + FR3 (#2861) both depend on the
 * two ends of the pipeline scrubbing the SAME shapes — a drift between them
 * reintroduces the original bug class.
 *
 * The `reportSilentFallback` call on `SUSPECTED_LEAK_SHAPE` is the tightening
 * loop: any unmatched shape surfaces in Sentry, the pattern is added here,
 * and both ends pick up the fix automatically.
 *
 * Keep this module pure (no side effects, no imports from `server/`) so it
 * can be consumed on either side of the bundle boundary without pulling in
 * pino/Sentry on the client.
 */

export const SANDBOX_PATH_PATTERNS: RegExp[] = [
  // Sandbox-remapped form: /tmp/claude-<uid>/-workspaces-<uuid>[-<suffix>]/...
  /\/tmp\/claude-\d+\/-workspaces-[0-9a-fA-F]{6,}(?:-[0-9a-fA-F]+)*\//g,
  // Host form without explicit workspacePath context: /workspaces/<uuid>/
  /\/workspaces\/[0-9a-fA-F]{6,}(?:-[0-9a-fA-F]+)*\//g,
];

/** Detects any path-shape that LOOKS like a sandbox or host workspace path
 *  but did not match a canonical pattern. Used for fallthrough instrumentation. */
export const SUSPECTED_LEAK_SHAPE: RegExp = /(\/workspaces\/|\/tmp\/claude-)[A-Za-z0-9._/-]+/;
