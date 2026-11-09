// Git config-carrier guard for the agent's file tools (#9600).
//
// A repo-local `.git/config` can name helpers that the auto-approved `git status|diff|show` reads
// execute (core.fsmonitor, diff.external, textconv, filter.*.clean, gpg.program — measured with real
// git in test/safe-bash-git-config-exec.test.ts). A real `.git/config` cannot arrive through a clone,
// so the remaining writer is the agent's own `Write` / `Edit` / `NotebookEdit`. This module is the one
// place that decides "does this file-tool call write into a `.git` path", called from BOTH enforcement
// points (the PreToolUse sandbox hook and `canUseTool`) so they cannot drift.
//
// A path is a carrier when ANY component the kernel would traverse equals `.git` case-insensitively
// (any depth: nested repos, submodules, `.GIT`, a gitdir pointer FILE named `.git`). `.gitignore`,
// `.github/` and `.gitmodules` are different names and pass. The path is resolved TOP-DOWN the way
// the kernel resolves it, in ONE pass: each existing component is `lstat`ed, a symlink is expanded
// from its `readlink` text (so a DANGLING link whose target text names `.git`, and `link/../x`
// after the link is expanded, are both seen), and the not-yet-existing tail is appended as plain
// names. Anything the walk cannot decide (a loop, a non-ENOENT filesystem error, an over-long path,
// a non-string location value) fails CLOSED. One lstat per existing component and none for the
// missing tail, so a long nonexistent path costs O(existing depth), not O(missing components^2).
//
// Reads (Read / Grep / Glob / LS) are deliberately untouched: reading `.git` is not the carrier.
// Residuals the guard does not claim to cover (ADR-050 amendment 2026-11-09): hardlinks to `.git`
// files, and Bash-created `.git` members, which take the Bash review card.
import { lstatSync, readlinkSync, realpathSync } from "node:fs";
import path from "node:path";
import { warnSilentFallback } from "./observability";
import { PATH_FIELDS } from "./tool-path-checker";

export const GIT_CARRIER_WRITE_TOOLS = ["Write", "Edit", "NotebookEdit"] as const;

export type GitCarrierMatch = "lexical" | "resolved" | "malformed";

/** The plain, non-alarming message returned to the agent on a deny. It promises no approval path:
 *  autonomous workspaces show no card and support turns hard-deny non-safe Bash. */
export const GIT_CARRIER_DENY_MESSAGE =
  "File tools cannot write inside a .git directory (git configuration and hooks are protected). " +
  "Use git commands through Bash for repository changes; they may need the user's approval.";

/** Machine-facing reason carried on the hook's `permissionDecisionReason`; repeats the next step. */
export const GIT_CARRIER_DENY_REASON =
  "Access denied: git configuration and hooks are protected; file tools cannot write inside .git. " +
  "Use git commands through Bash instead.";

/** PATH_MAX; the kernel rejects longer paths anyway, so a longer one is denied rather than walked. */
const MAX_PATH_LENGTH = 4096;
/** Symlink expansions allowed in one resolution (the kernel's own ELOOP bound is 40). */
const MAX_SYMLINK_HOPS = 40;

type Origin = "lexical" | "resolved";
interface Pending {
  name: string;
  origin: Origin;
}

function isGitCarrierTool(toolName: string): boolean {
  return (GIT_CARRIER_WRITE_TOOLS as readonly string[]).includes(toolName);
}

function splitParts(p: string): string[] {
  return p.split(/[\\/]+/).filter((c) => c !== "" && c !== ".");
}

function realWorkspace(workspacePath: string): string {
  try {
    return realpathSync(workspacePath);
  } catch {
    return path.resolve(workspacePath);
  }
}

/** True when `parts` sits under the workspace's real path and strictly below its root. */
function belowWorkspace(wsParts: string[], parts: string[]): boolean {
  return parts.length > wsParts.length && wsParts.every((c, i) => parts[i] === c);
}

/**
 * Resolve one (trimmed) location the way the kernel does and report the first `.git` component.
 * `wsParts` is the real workspace path; a component is only judged when it lands strictly below the
 * workspace root, or anywhere when the path leaves the workspace (fail closed — the containment
 * checks run first at both enforcement points, so that branch is defence in depth).
 */
function resolveForCarrier(wsParts: string[], spelling: string): GitCarrierMatch | null {
  if (spelling.length > MAX_PATH_LENGTH) return "malformed";
  const absolute = spelling.startsWith("/");
  let resolved: string[] = absolute ? [] : [...wsParts];
  const queue: Pending[] = splitParts(spelling).map((name) => ({ name, origin: "lexical" as const }));
  let hops = 0;
  let missing = false; // once a component does not exist, the rest is plain names

  const judge = (name: string, origin: Origin): GitCarrierMatch | null => {
    if (name.toLowerCase() !== ".git") return null;
    const next = [...resolved, name];
    // Outside the workspace everything counts; inside it only components below the root do.
    if (belowWorkspace(wsParts, next) || !next.slice(0, wsParts.length).every((c, i) => wsParts[i] === c)) {
      return origin;
    }
    return null;
  };

  while (queue.length > 0) {
    const { name, origin } = queue.shift() as Pending;
    if (name === "." || name === "") continue;
    if (name === "..") {
      resolved = resolved.slice(0, -1);
      continue;
    }
    const hit = judge(name, origin);
    if (hit) return hit;
    if (missing) {
      resolved.push(name);
      continue;
    }
    const full = "/" + [...resolved, name].join("/");
    let st;
    try {
      st = lstatSync(full);
    } catch (err) {
      if ((err as NodeJS.ErrnoException)?.code === "ENOENT") {
        missing = true;
        resolved.push(name);
        continue;
      }
      return "malformed"; // EACCES / ENOTDIR / ELOOP / anything else: cannot decide, so deny
    }
    if (!st.isSymbolicLink()) {
      resolved.push(name);
      continue;
    }
    if (++hops > MAX_SYMLINK_HOPS) return "malformed";
    let target: string;
    try {
      target = readlinkSync(full);
    } catch {
      return "malformed";
    }
    if (target.startsWith("/")) resolved = [];
    queue.unshift(...splitParts(target).map((n) => ({ name: n, origin: "resolved" as const })));
  }
  return null;
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
  const wsParts = splitParts(realWorkspace(workspacePath));

  for (const field of PATH_FIELDS) {
    const value = input[field];
    if (value === undefined || value === null || value === "") continue;
    if (typeof value !== "string") return "malformed";
    // The CLI trims before it expands, so the trimmed spelling is the path that is written.
    const spelling = value.trim();
    if (!spelling) continue;
    const hit = resolveForCarrier(wsParts, spelling);
    if (hit) return hit;
  }
  return null;
}

/** Which of the two enforcement points denied (the event carries it). */
export type GitCarrierEnforcement = "sandbox-hook" | "canUseTool";

/**
 * Per-session reporter: one deduped Sentry/log event per (tool, enforcement point, match class) — at
 * most 3 x 2 x 3 = 18 distinct events, so the dedupe alone bounds a prompt-injected loop. Never
 * carries the path or file contents.
 */
export function createGitCarrierDenyReporter(): (
  toolName: string,
  enforcement: GitCarrierEnforcement,
  match: GitCarrierMatch,
) => void {
  const seen = new Set<string>();
  return (toolName, enforcement, match) => {
    const key = `${toolName}:${enforcement}:${match}`;
    if (seen.has(key)) return;
    seen.add(key);
    warnSilentFallback(null, {
      feature: "cc-permissions",
      op: "git-carrier-write-denied",
      extra: { toolName, enforcement, match },
    });
  };
}
