/**
 * Build a human-readable label for a tool_use WS event.
 *
 * Extracts meaningful details from tool input (file paths, commands, patterns)
 * and strips absolute workspace paths to prevent information leakage.
 *
 * @see #2428 — replaces the static TOOL_LABELS map with input-aware labels
 * @see #2861 — FR1 verb-based Bash labels + FR2 canonical sandbox-path scrub
 */

import { reportSilentFallback } from "./observability";
import {
  SANDBOX_PATH_PATTERNS as SHARED_SANDBOX_PATH_PATTERNS,
  SUSPECTED_LEAK_SHAPE as SHARED_SUSPECTED_LEAK_SHAPE,
} from "@/lib/sandbox-path-patterns";

/** Fallback labels when input is unavailable or unrecognized */
const FALLBACK_LABELS: Record<string, string> = {
  Read: "Reading file...",
  Bash: "Running command...",
  Edit: "Editing file...",
  Write: "Writing file...",
  WebSearch: "Searching web...",
  Grep: "Searching code...",
  Glob: "Finding files...",
};

const MAX_BASH_CMD_LENGTH = 60;

/**
 * Canonical sandbox-path patterns are defined in `@/lib/sandbox-path-patterns`
 * so the client render scrub (`lib/format-assistant-text.ts`) shares the same
 * regex table — FR2 success depends on the two ends of the pipeline scrubbing
 * the same shapes. Re-exported here for call sites that already import from
 * `server/tool-labels`.
 */
export const SANDBOX_PATH_PATTERNS: RegExp[] = SHARED_SANDBOX_PATH_PATTERNS;

const SUSPECTED_LEAK_SHAPE = SHARED_SUSPECTED_LEAK_SHAPE;

/**
 * Strip the workspace path prefix from a string, returning a relative path.
 * Also strips any leading slash and canonical sandbox prefixes. Reports
 * unmatched `/workspaces/` or `/tmp/claude-` shapes to Sentry so the pattern
 * table can be tightened from prod data.
 */
function stripWorkspacePath(text: string, workspacePath?: string): string {
  let out = text;
  let scrubbed = false;
  if (workspacePath && out.includes(workspacePath)) {
    out = out.replaceAll(workspacePath, "");
    scrubbed = true;
  }
  for (const pattern of SANDBOX_PATH_PATTERNS) {
    // Each pattern carries the `g` flag; `replace` resets lastIndex per call.
    const next = out.replace(pattern, "");
    if (next !== out) {
      out = next;
      scrubbed = true;
    }
  }
  // Only normalize a leading slash when an actual strip happened — otherwise
  // leave input paths untouched (preserves behavior for callers that pass
  // `workspacePath=undefined`, e.g. display of raw absolute paths in tests).
  if (scrubbed) {
    out = out.replace(/^\//, "");
  }

  // Any remaining suspected-leak shape is a gap in the pattern table.
  if (SUSPECTED_LEAK_SHAPE.test(out)) {
    reportSilentFallback(null, {
      feature: "command-center",
      op: "tool-label-scrub",
      message: "Unmatched workspace/sandbox path shape after scrub",
      extra: { text: out.slice(0, 200) },
    });
  }
  return out;
}

/**
 * Extract a relative file path from tool input, stripping workspace prefix.
 */
function extractRelativePath(
  input: Record<string, unknown> | undefined,
  workspacePath?: string,
): string | undefined {
  const filePath = input?.file_path;
  if (typeof filePath !== "string") return undefined;
  return stripWorkspacePath(filePath, workspacePath);
}

// ---------------------------------------------------------------------------
// FR1: Bash verb allowlist (#2861)
// ---------------------------------------------------------------------------

/**
 * Static verb → activity-label map. Subcommand-aware verbs (`git`, `gh`) are
 * handled in `mapBashVerb` below, not in this table.
 *
 * Non-goals (fallback to "Working…" via reportSilentFallback instrumentation):
 * pipelines that swap the leading verb mid-stream, `bash -c "..."` wrappers,
 * `sudo`, `$(...)` subshells. The fallback is safe — we never leak the raw
 * command string.
 */
const BASH_VERB_LABELS: Record<string, string> = {
  ls: "Exploring project structure",
  find: "Searching code",
  rg: "Searching code",
  grep: "Searching code",
  cat: "Reading file",
  npm: "Running package command",
  bun: "Running package command",
  pnpm: "Running package command",
  yarn: "Running package command",
  doppler: "Fetching secrets",
  terraform: "Running Terraform",
  tofu: "Running Terraform",
};

/** Parse the first meaningful token from a shell command, skipping leading
 *  env-var assignments (`FOO=bar ls` → `ls`). Returns null when the command
 *  starts with a token we can't map safely (`bash -c`, `sudo`, `$(...)`). */
function parseLeadingVerb(command: string): string | null {
  const trimmed = command.trim();
  if (!trimmed) return null;

  const tokens = trimmed.split(/\s+/);
  let i = 0;
  // Skip env-var assignments: NAME=VALUE (no spaces around `=`).
  while (i < tokens.length && /^[A-Za-z_][A-Za-z0-9_]*=/.test(tokens[i])) {
    i++;
  }
  const first = tokens[i];
  if (!first) return null;

  // Reject shapes that don't expose a simple verb:
  //   - subshells / command substitution: `$(ls)`, `\`ls\``
  //   - shell wrappers: `bash -c`, `sh -c`, `zsh -c`
  //   - sudo
  if (first.startsWith("$(") || first.startsWith("`") || first.startsWith("(")) {
    return null;
  }
  if (first === "sudo") return null;
  if ((first === "bash" || first === "sh" || first === "zsh") && tokens[i + 1] === "-c") {
    return null;
  }
  return first;
}

/**
 * Map a Bash command to a human-readable activity label. Returns "Working…"
 * as the safe default for unknown verbs (fires `reportSilentFallback` so the
 * allowlist can be tightened from prod data).
 */
export function mapBashVerb(command: string): string {
  const verb = parseLeadingVerb(command);

  if (!verb) {
    reportSilentFallback(null, {
      feature: "command-center",
      op: "tool-label-fallback",
      message: "Unparseable Bash verb",
      extra: { verb: command.trim().split(/\s+/)[0] ?? "" },
    });
    return "Working…";
  }

  // Subcommand-aware verbs come first — `git log` / `gh issue view`.
  if (verb === "git") {
    const sub = command.trim().split(/\s+/)[1] ?? "";
    return sub ? `Checking git ${sub}` : "Checking git";
  }
  if (verb === "gh") {
    return "Querying GitHub";
  }

  const label = BASH_VERB_LABELS[verb];
  if (label) return label;

  reportSilentFallback(null, {
    feature: "command-center",
    op: "tool-label-fallback",
    message: "Unknown Bash verb",
    extra: { verb },
  });
  return "Working…";
}

export function buildToolLabel(
  toolName: string,
  input: Record<string, unknown> | undefined,
  workspacePath?: string,
): string {
  switch (toolName) {
    case "Read": {
      const rel = extractRelativePath(input, workspacePath);
      return rel ? `Reading ${rel}...` : FALLBACK_LABELS.Read;
    }

    case "Edit": {
      const rel = extractRelativePath(input, workspacePath);
      return rel ? `Editing ${rel}...` : FALLBACK_LABELS.Edit;
    }

    case "Write": {
      const rel = extractRelativePath(input, workspacePath);
      return rel ? `Writing ${rel}...` : FALLBACK_LABELS.Write;
    }

    case "Bash": {
      const cmd = input?.command;
      if (typeof cmd !== "string") return FALLBACK_LABELS.Bash;
      // Strip workspace/sandbox paths from the command before verb mapping so
      // SUSPECTED_LEAK_SHAPE instrumentation fires consistently, then derive
      // the verb label. The verb label itself is the safe default — we never
      // emit the raw command string to the client.
      stripWorkspacePath(cmd.replace(/\n/g, " "), workspacePath);
      return mapBashVerb(cmd);
    }

    case "Grep": {
      const pattern = input?.pattern;
      if (typeof pattern !== "string") return FALLBACK_LABELS.Grep;
      const truncatedGrep = pattern.length > MAX_BASH_CMD_LENGTH
        ? pattern.slice(0, MAX_BASH_CMD_LENGTH) + "..."
        : pattern;
      return `Searching for "${truncatedGrep}"...`;
    }

    case "Glob": {
      const pattern = input?.pattern;
      if (typeof pattern !== "string") return FALLBACK_LABELS.Glob;
      const truncatedGlob = pattern.length > MAX_BASH_CMD_LENGTH
        ? pattern.slice(0, MAX_BASH_CMD_LENGTH) + "..."
        : pattern;
      return `Finding ${truncatedGlob}...`;
    }

    case "WebSearch":
      return FALLBACK_LABELS.WebSearch;

    default:
      return FALLBACK_LABELS[toolName] ?? "Working...";
  }
}
