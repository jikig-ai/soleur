// #12600 (D23): the one spelling of the KB subtree root (and of its exclude pathspec), in a module with no imports so the
// self-heal (workspace-sync.ts), the publish path, the held count and the agent line share it without importing git code.
export const KB_ROOT = "knowledge-base";

/**
 * The pathspec that excludes the knowledge base, `:(exclude)knowledge-base/`: its one spelling (pattern P3-11). The held
 * count, the side-tip KB-only gates, the self-heal's held check and the listing command the agent is told to run all use
 * it, so the count and the list the user is shown cannot drift.
 */
export const KB_EXCLUDE_PATHSPEC = `:(exclude)${KB_ROOT}/`;
