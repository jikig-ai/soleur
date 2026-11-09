// Git config-carrier guard for the agent's file tools (#9600).
//
// A repo-local `.git/config` can name helpers that the auto-approved `git status|diff|show` reads
// execute (core.fsmonitor, diff.external, textconv, filter.*.clean, gpg.program — measured with real
// git in test/safe-bash-git-config-exec.test.ts). A real `.git/config` cannot arrive through a clone,
// so the remaining writer is the agent's own `Write` / `Edit` / `NotebookEdit`. This module is the one
// place that decides "does this file-tool call write into a `.git` path", called from BOTH enforcement
// points (the PreToolUse sandbox hook and `canUseTool`) so they cannot drift.
//
// A path is a carrier when ANY component of its lexical OR symlink-resolved form, relative to the
// workspace, equals `.git` case-insensitively (any depth: nested repos, submodules, `.GIT`, a gitdir
// pointer FILE named `.git`). `.gitignore`, `.github/` and `.gitmodules` are different names and pass.
// The deepest existing ancestor is resolved with `realpath` and the not-yet-existing remainder is
// appended, so a symlink `g -> .git` followed by `g/config` and a write to a not-yet-created
// `.git/config` are both seen. A non-string location value fails CLOSED.
//
// Reads (Read / Grep / Glob / LS) are deliberately untouched: reading `.git` is not the carrier.
import { realpathSync } from "node:fs";
import path from "node:path";
import { warnSilentFallback } from "./observability";

export const GIT_CARRIER_WRITE_TOOLS = ["Write", "Edit", "NotebookEdit"] as const;

/** Every input field a file tool reads a location from (mirrors tool-path-checker's PATH_FIELDS). */
const LOCATION_FIELDS = ["file_path", "path", "notebook_path"] as const;

export type GitCarrierMatch = "lexical" | "resolved" | "malformed";

/** The plain, non-alarming message returned to the agent on a deny. */
export const GIT_CARRIER_DENY_MESSAGE =
  "Git configuration and hooks are protected. Run `git config` through Bash and you will be asked to approve it.";

function isGitCarrierTool(toolName: string): boolean {
  return (GIT_CARRIER_WRITE_TOOLS as readonly string[]).includes(toolName);
}

function hasGitComponent(parts: string[]): boolean {
  return parts.some((c) => c.toLowerCase() === ".git");
}

/** Components of `abs` that sit under `workspace` (or every component when `abs` is outside it: fail closed). */
function componentsUnder(workspace: string, abs: string): string[] {
  const rel = path.relative(workspace, abs);
  const base = rel.startsWith("..") || path.isAbsolute(rel) ? abs : rel;
  return base.split(/[\\/]+/).filter(Boolean);
}

/** realpath of the deepest EXISTING ancestor of `p`, with the missing remainder appended. */
function resolveDeepestExisting(p: string): string {
  let current = p;
  const tail: string[] = [];
  for (;;) {
    try {
      return path.join(realpathSync(current), ...tail.reverse());
    } catch (err) {
      const parent = path.dirname(current);
      if ((err as NodeJS.ErrnoException)?.code !== "ENOENT" || parent === current) return p;
      tail.push(path.basename(current));
      current = parent;
    }
  }
}

/**
 * Which way (if any) `toolInput` addresses a `.git` path. `null` means the call is not a carrier write.
 * Only the write-class file tools are judged; everything else returns `null`.
 */
export function gitCarrierMatch(
  toolName: string,
  toolInput: unknown,
  workspacePath: string,
): GitCarrierMatch | null {
  if (!isGitCarrierTool(toolName)) return null;
  if (toolInput === null || typeof toolInput !== "object") return "malformed";
  const input = toolInput as Record<string, unknown>;

  let workspace: string;
  try {
    workspace = realpathSync(workspacePath);
  } catch {
    workspace = path.resolve(workspacePath);
  }

  for (const field of LOCATION_FIELDS) {
    const value = input[field];
    if (value === undefined || value === null || value === "") continue;
    if (typeof value !== "string") return "malformed";
    // The CLI trims before it expands; judge the raw and the trimmed spelling.
    for (const spelling of new Set([value, value.trim()])) {
      if (!spelling) continue;
      const anchored = path.isAbsolute(spelling) ? path.normalize(spelling) : path.resolve(workspace, spelling);
      if (hasGitComponent(componentsUnder(workspace, anchored))) return "lexical";
      if (hasGitComponent(componentsUnder(workspace, resolveDeepestExisting(anchored)))) return "resolved";
    }
  }
  return null;
}

/** True when this file-tool call would write into a `.git` path. */
export function gitCarrierTouched(toolName: string, toolInput: unknown, workspacePath: string): boolean {
  return gitCarrierMatch(toolName, toolInput, workspacePath) !== null;
}

/** Which of the two enforcement points denied (the event carries it). */
export type GitCarrierEnforcement = "sandbox-hook" | "canUseTool";

const REPORT_BUDGET = 8;

/**
 * Per-session reporter: one budgeted, deduped Sentry/log event per (tool, enforcement point, match class)
 * so a prompt-injected loop cannot flood Sentry. Never carries the path or file contents.
 */
export function createGitCarrierDenyReporter(): (
  toolName: string,
  enforcement: GitCarrierEnforcement,
  match: GitCarrierMatch,
) => void {
  const seen = new Set<string>();
  return (toolName, enforcement, match) => {
    const key = `${toolName}:${enforcement}:${match}`;
    if (seen.has(key) || seen.size >= REPORT_BUDGET) return;
    seen.add(key);
    warnSilentFallback(null, {
      feature: "cc-permissions",
      op: "git-carrier-write-denied",
      extra: { toolName, enforcement, match },
    });
  };
}
