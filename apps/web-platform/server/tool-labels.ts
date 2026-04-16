/**
 * Build a human-readable label for a tool_use WS event.
 *
 * Extracts meaningful details from tool input (file paths, commands, patterns)
 * and strips absolute workspace paths to prevent information leakage.
 *
 * @see #2428 — replaces the static TOOL_LABELS map with input-aware labels
 */

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
 * Strip the workspace path prefix from a string, returning a relative path.
 * Also strips any leading slash from the result.
 */
function stripWorkspacePath(text: string, workspacePath?: string): string {
  if (!workspacePath) return text;
  return text.replaceAll(workspacePath, "").replace(/^\//, "");
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
      let cleaned = stripWorkspacePath(cmd.replace(/\n/g, " "), workspacePath);
      if (cleaned.length > MAX_BASH_CMD_LENGTH) {
        cleaned = cleaned.slice(0, MAX_BASH_CMD_LENGTH) + "...";
      }
      return `Running: ${cleaned}`;
    }

    case "Grep": {
      const pattern = input?.pattern;
      if (typeof pattern !== "string") return FALLBACK_LABELS.Grep;
      return `Searching for "${pattern}"...`;
    }

    case "Glob": {
      const pattern = input?.pattern;
      if (typeof pattern !== "string") return FALLBACK_LABELS.Glob;
      return `Finding ${pattern}...`;
    }

    case "WebSearch":
      return FALLBACK_LABELS.WebSearch;

    default:
      return FALLBACK_LABELS[toolName] ?? "Working...";
  }
}
