/**
 * Build a human-readable label for a tool_use WS event.
 *
 * Extracts meaningful details from tool input (file paths, commands, patterns)
 * and strips absolute workspace paths to prevent information leakage.
 *
 * @see #2428 — replaces the static TOOL_LABELS map with input-aware labels
 * @see #2861 — FR1 verb-based Bash labels + FR2 canonical sandbox-path scrub
 * @see #3235 — `buildToolUseWSMessage` shared by agent-runner + cc-dispatcher
 */

import type { WSMessage } from "@/lib/types";
import type { DomainLeaderId } from "./domain-leaders";
import { reportSilentFallback } from "./observability";
import {
  SANDBOX_PATH_PATTERNS as SHARED_SANDBOX_PATH_PATTERNS,
  SUSPECTED_LEAK_SHAPE as SHARED_SUSPECTED_LEAK_SHAPE,
} from "@/lib/sandbox-path-patterns";

/**
 * #5733 deliverable C2 — the agent-context observability backstop predicate.
 * Decides whether an in-sandbox Bash tool RESULT is the agent's `/soleur:go`
 * Step 0.0 `git rev-parse --is-inside-work-tree` reporting NOT-a-work-tree (the
 * strand). This is the GUARANTEED strand signal: it fires from the agent's REAL
 * in-bwrap context, so it surfaces the strand for shapes the host `rev-parse`
 * confirm is blind to (the escaping pointer — host git is not sandboxed — and
 * object-store corruption, which passes host rev-parse).
 *
 * Deliberately conservative (it must NOT false-positive a healthy probe, which
 * prints exactly `"true"`): fires ONLY when the command IS the rev-parse work-tree
 * probe AND its output carries NO standalone `true` token. This single negation
 * (#5733 D3) subsumes the prior `not a git repository` / `^fatal:` / bare-`false`
 * branches AND closes the dominant prod shape they all missed: go.md Step 0.0 runs
 * `git rev-parse … --is-inside-work-tree 2>/dev/null || true`, so a stranded
 * workspace emits EMPTY stdout (stderr suppressed, `|| true` swallows the non-zero
 * exit) — empty output carries no `true`, so it is now correctly a strand. The
 * healthy forms all print a standalone `true` (a lone `true`, the compound
 * `false\ntrue` work-tree case, or the bare-repo `true\nfalse`) → NOT a strand.
 *
 * The command guard requires the probe to be the operative STATEMENT (a command
 * head — start of line / after `;`/`&&`/`||`/`|`/newline, optionally behind a
 * `cd … &&` prelude), NOT merely a substring embedded in an unrelated command
 * (e.g. `echo "git rev-parse --is-inside-work-tree"`) — which would otherwise
 * false-positive a strand on empty output (architecture-review bound). Pure — the
 * dispatcher owns the emit + pseudonymization.
 */
export function isInSandboxRevParseStrand(
  command: string,
  output: string,
): boolean {
  const isWorkTreeProbe =
    /(?:^|[\n;|]|&&|\|\|)[ \t]*(?:cd[ \t]+\S[^\n;|]*?(?:&&|;)[ \t]*)?git[ \t]+(?:-\S+[ \t]+)*rev-parse[ \t][^\n;|]*--is-inside-work-tree\b/i.test(
      command,
    );
  if (!isWorkTreeProbe) return false;
  // Strand iff the output has NO standalone `true` token. Healthy probes always
  // print a whitespace-delimited `true`; a stranded/empty/`false`/`fatal:` output
  // does not.
  return !/(^|\s)true(\s|$)/i.test(output);
}

/** Fallback labels when input is unavailable or unrecognized */
const FALLBACK_LABELS: Record<string, string> = {
  Read: "Reading file…",
  Bash: "Running command…",
  Edit: "Editing file…",
  Write: "Writing file…",
  WebSearch: "Searching web…",
  WebFetch: "Fetching page…",
  Grep: "Searching code…",
  Glob: "Finding files…",
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

  // Report the matched shape (not surrounding prose) so Sentry names the
  // offending form. Mirrors lib/format-assistant-text.ts:88.
  const leak = out.match(SUSPECTED_LEAK_SHAPE);
  if (leak) {
    reportSilentFallback(null, {
      feature: "command-center",
      op: "tool-label-scrub",
      message: "Unmatched workspace/sandbox path shape after scrub",
      extra: { shape: leak[0].slice(0, 200) },
    });
  }
  return out;
}

/**
 * Extract a relative file path from tool input, stripping workspace prefix.
 *
 * When `workspacePath` is undefined we cannot guarantee a literal-prefix
 * scrub — only the canonical sandbox patterns run. An absolute path that
 * is NEITHER a sandbox shape NOR matches the known workspace root would
 * flow through verbatim. Defensive guard: refuse to return an absolute
 * path in the no-workspace case so callers fall back to the safe
 * FALLBACK_LABELS (e.g., "Reading file...") instead of echoing the path
 * to clients. Relative paths remain unaffected. (#3235 review)
 */
function extractRelativePath(
  input: Record<string, unknown> | undefined,
  workspacePath?: string,
): string | undefined {
  const filePath = input?.file_path;
  if (typeof filePath !== "string") return undefined;
  if (workspacePath === undefined && filePath.startsWith("/")) return undefined;
  const rel = stripWorkspacePath(filePath, workspacePath);
  // #9515 security seat — a path that is still absolute after the workspace +
  // sandbox scrubs (`/home/user/.aws/...`) is a HOST path the label machinery
  // must never echo to clients or persist in the trail. Fall back to the
  // generic label; the unmatched shape was already reported above.
  if (rel.startsWith("/")) return undefined;
  return rel;
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
  head: "Reading file",
  tail: "Reading file",
  less: "Reading file",
  wc: "Counting output",
  sort: "Sorting output",
  uniq: "Deduplicating output",
  jq: "Processing JSON data",
  yq: "Processing structured data",
  sed: "Transforming text",
  awk: "Transforming text",
  cut: "Transforming text",
  tr: "Transforming text",
  xargs: "Processing items",
  tee: "Writing output",
  diff: "Comparing files",
  patch: "Applying a patch",
  npm: "Running package command",
  bun: "Running package command",
  pnpm: "Running package command",
  yarn: "Running package command",
  npx: "Running a package tool",
  bunx: "Running a package tool",
  node: "Running a script",
  tsx: "Running a script",
  python: "Running a script",
  python3: "Running a script",
  pip: "Managing Python packages",
  pip3: "Managing Python packages",
  uv: "Managing Python packages",
  poetry: "Managing Python packages",
  gem: "Managing packages",
  bundle: "Managing packages",
  composer: "Managing packages",
  cargo: "Building the project",
  go: "Building the project",
  make: "Building the project",
  cmake: "Building the project",
  doppler: "Fetching secrets",
  terraform: "Running Terraform",
  tofu: "Running Terraform",
  docker: "Managing containers",
  kubectl: "Managing containers",
  helm: "Managing containers",
  bash: "Running a script",
  sh: "Running a script",
  zsh: "Running a script",
  curl: "Making a web request",
  wget: "Making a web request",
  ssh: "Connecting to a remote host",
  scp: "Copying files between hosts",
  rsync: "Synchronizing files",
  sleep: "Pausing briefly",
  mkdir: "Creating directories",
  mv: "Moving files",
  cp: "Copying files",
  rm: "Removing files",
  touch: "Creating files",
  chmod: "Adjusting file permissions",
  chown: "Adjusting file ownership",
  ln: "Linking files",
  tar: "Working with archives",
  zip: "Compressing files",
  unzip: "Extracting files",
  gzip: "Compressing files",
  gunzip: "Decompressing files",
  sha256sum: "Verifying a checksum",
  md5sum: "Verifying a checksum",
  openssl: "Performing a crypto operation",
  ps: "Checking running processes",
  kill: "Stopping a process",
  pkill: "Stopping a process",
  df: "Checking disk space",
  du: "Measuring disk usage",
  free: "Checking memory",
  top: "Checking system state",
  env: "Checking the environment",
  which: "Checking the environment",
  type: "Checking the environment",
};

/**
 * #9515 — `git <subcommand>` mapped to business language. NEVER interpolate
 * the raw subcommand: `rev-parse`/`rev-list`/`reflog` are jargon to the
 * target user (CMO finding). Unknown subs degrade to the honest generic —
 * the shape test in tool-labels-shape.test.ts bans raw-token leak through.
 */
const GIT_SUBCOMMAND_LABELS: Record<string, string> = {
  status: "Checking repository status",
  log: "Reviewing commit history",
  diff: "Comparing changes",
  show: "Inspecting changes",
  fetch: "Fetching latest changes",
  pull: "Fetching latest changes",
  checkout: "Switching branches",
  switch: "Switching branches",
  add: "Preparing a commit",
  commit: "Preparing a commit",
  push: "Pushing changes",
  branch: "Working with branches",
  stash: "Stashing changes",
  rebase: "Rebasing changes",
  merge: "Merging changes",
  tag: "Working with tags",
  remote: "Checking remotes",
  blame: "Checking line history",
  "rev-parse": "Inspecting the repository",
  "rev-list": "Inspecting the repository",
  reflog: "Inspecting the repository",
  worktree: "Managing worktrees",
  clean: "Cleaning the working tree",
  restore: "Restoring files",
  reset: "Resetting changes",
  "cherry-pick": "Applying a commit",
  revert: "Reverting a commit",
};

/** #9515 — `gh <noun> <verb>` business labels for the highest-frequency
 *  GitHub CLI paths (the Concierge's dominant compound-command tool). */
const GH_NOUNS = new Set([
  "pr", "issue", "run", "workflow", "release", "repo", "api", "search",
  "label", "gist", "auth", "secret", "variable", "codespace", "project",
]);

const GH_SUBCOMMAND_LABELS: Record<string, string> = {
  "pr list": "Listing pull requests",
  "pr view": "Reviewing a pull request",
  "pr checks": "Checking CI on a pull request",
  "pr status": "Checking pull request status",
  "pr merge": "Merging a pull request",
  "pr close": "Closing a pull request",
  "pr create": "Opening a pull request",
  "pr diff": "Comparing pull request changes",
  "pr review": "Reviewing a pull request",
  "pr comment": "Commenting on a pull request",
  "issue list": "Listing issues",
  "issue view": "Reviewing an issue",
  "issue create": "Filing an issue",
  "issue close": "Closing an issue",
  "issue comment": "Commenting on an issue",
  "run list": "Checking CI runs",
  "run view": "Reviewing a CI run",
  "run watch": "Watching a CI run",
  "workflow list": "Listing workflows",
  "workflow run": "Triggering a workflow",
  "release list": "Listing releases",
  "release view": "Reviewing a release",
  "repo view": "Reviewing the repository",
  api: "Calling the GitHub API",
  search: "Searching GitHub",
  label: "Managing labels",
};

/**
 * #9515 — verbs that are setup noise in a compound command, NOT the work:
 * `cd /workspaces/x; gh pr list` is "Listing pull requests", not "Working…".
 * The segment walk skips these and maps the first meaningful verb.
 */
const SETUP_NOISE_VERBS = new Set([
  "cd", "pushd", "popd", "export", "set", "unset", "echo", "printf", "true",
  "false", "eval", "source", ".", "read", "local", "declare", "typeset",
  "trap", "ulimit", "umask", "alias", "unalias", "dirs", "jobs", "bg", "fg",
  "disown", "builtin", "wait",
  "done", "fi", "esac", "{", "}", "in", "test", "[",
]);

/** Wrapper verbs — the REAL verb follows the wrapper (`nohup npm test` →
 *  `npm`). Stripped like a `do`/`then` body prefix rather than skipped, so a
 *  wrapper-prefixed command doesn't degrade to the "Working…" fallback and
 *  re-pollute the fallback class this fix measured (agent-native seat). */
const WRAPPER_VERBS = new Set([
  "nohup", "time", "nice", "chronic", "env", "xargs", "exec", "command",
  "stdbuf", "timeout", "watch", "unbuffer", "setsid", "flock",
]);

/** Shell control-flow keywords — a segment starting with a loop/conditional
 *  HEADER keyword (`for n in …`, `while`, `until`, `if`, `elif`, `case`) is
 *  control structure, not the work — the whole segment is skipped so the
 *  loop body's real verb surfaces (`for n in …; do gh pr view; done` → `gh`).
 *  Body keywords (`do`, `then`, `else`) are stripped instead — the remainder
 *  IS the command. */
const HEADER_KEYWORDS = new Set([
  "for", "while", "until", "if", "elif", "case", "select",
]);
const BODY_KEYWORDS = new Set(["do", "then", "else"]);

/** Parse the first meaningful token from a shell segment, skipping leading
 *  env-var assignments (`FOO=bar ls` → `ls`). Returns null when the segment
 *  starts with a token we can't map safely (`bash -c`, `sudo`, `$(...)`). */
function parseLeadingVerb(
  segment: string,
): { verb: string; tokens: string[] } | null {
  const trimmed = segment.trim();
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
  // `tokens.slice(i)` — env-assignments stripped so subcommand lookups index
  // from the real verb (code-quality seat: `FOO=1 git status`).
  return { verb: first, tokens: tokens.slice(i) };
}

/**
 * #9515 — walk a compound command's segments (`;`, `&&`, `||`, `|`,
 * newlines) and return the first MEANINGFUL verb with its segment. Setup
 * noise (`cd`, env assignments, `export`) and control-flow keywords (`for`,
 * `do`, `if`, `then`) are skipped — measured against prod Sentry fallback
 * distribution (issue 124542794: `cd`/`for`/`if`/`sleep` dominated 490
 * events — every one a compound command where the real verb sits behind a
 * setup segment or inside a loop body).
 */
// Known understatement: the FIRST meaningful verb wins — `ls; rm -rf dir`
// labels "Exploring project structure" while the rm runs. A compound mixing
// read + mutate is a label-fidelity limit, not a leak (labels are always
// table values); revisit if the fallback data shows the pattern matters.
function findMeaningfulVerb(
  command: string,
): { verb: string; tokens: string[]; segment: string } | null {
  const segments = command.split(/;|&&|\|\||\||\n/);
  let sleepCandidate: { verb: string; tokens: string[]; segment: string } | null = null;
  for (const rawSegment of segments) {
    let segment = rawSegment.trim();
    if (!segment) continue;
    // Body keywords (`do`, `then`, `else`) prefix the actual command.
    for (let guard = 0; guard < 4; guard++) {
      const tokens = segment.trim().split(/\s+/);
      if (tokens.length > 1 && BODY_KEYWORDS.has(tokens[0])) {
        segment = tokens.slice(1).join(" ");
        continue;
      }
      break;
    }
    // Wrapper verbs (`nohup`, `time`, `nice`) — strip the head and re-parse
    // the same segment rather than skipping the whole thing.
    for (let guard = 0; guard < 3; guard++) {
      const tokens = segment.trim().split(/\s+/);
      if (tokens.length > 1 && WRAPPER_VERBS.has(tokens[0])) {
        segment = tokens.slice(1).join(" ");
        continue;
      }
      break;
    }
    const parsed = parseLeadingVerb(segment);
    if (!parsed) continue;
    const { verb, tokens } = parsed;
    // Loop/conditional headers — checked on the POST-env-skip verb too, so
    // `FOO=1 for n in …` doesn't surface `for` as the verb.
    if (HEADER_KEYWORDS.has(verb)) continue;
    if (SETUP_NOISE_VERBS.has(verb)) continue;
    // `sleep` masks the real work in `sleep 30 && gh pr checks` — prefer a
    // later meaningful segment; keep it when nothing better exists.
    if (verb === "sleep") {
      sleepCandidate ??= { verb, tokens, segment: segment.trim() };
      continue;
    }
    return { verb, tokens, segment: segment.trim() };
  }
  return sleepCandidate;
}

/**
 * Map a Bash command to a human-readable activity label. Returns "Working…"
 * as the safe default for unknown verbs (fires `reportSilentFallback` so the
 * allowlist can be tightened from prod data).
 */
/** #9515 security seat — only allowlist-shaped tokens reach Sentry; a raw
 *  first-token like `OPENAI_API_KEY=sk-…` or a credential URL must never
 *  leave the box in the `verb` extra. */
function sanitizeVerbForTelemetry(tok: string): string {
  return /^[a-z][a-z0-9_.-]{0,39}$/.test(tok) ? tok : "<unparseable>";
}

export function mapBashVerb(command: string): string {
  const found = findMeaningfulVerb(command);

  if (!found) {
    reportSilentFallback(null, {
      feature: "command-center",
      op: "tool-label-fallback",
      message: "Unparseable Bash verb",
      extra: { verb: sanitizeVerbForTelemetry(command.trim().split(/\s+/)[0] ?? "") },
    });
    return "Working…";
  }

  const { verb, tokens } = found;

  // Subcommand-aware verbs come first — safe business maps, never raw
  // subcommand interpolation (#9515: `git rev-parse` is jargon, not copy).
  if (verb === "git") {
    const first = tokens[1] ?? "";
    return GIT_SUBCOMMAND_LABELS[first] ?? "Working with the repository";
  }
  if (verb === "gh") {
    // Flag-first invocations (`gh -R owner/repo pr view 5`) are idiomatic —
    // scan for the first known NOUN rather than fixed positions (agent-native
    // seat), then its verb. The fallback is neutral, not read-flavored:
    // `gh api -X DELETE` must not render as "Querying".
    let noun: string | undefined;
    let nounIdx = -1;
    for (let i = 1; i < tokens.length; i++) {
      const t = tokens[i];
      if (t?.startsWith("-")) continue;
      if (t && GH_NOUNS.has(t)) {
        noun = t;
        nounIdx = i;
        break;
      }
    }
    if (noun !== undefined) {
      const next = tokens[nounIdx + 1] ?? "";
      return (
        GH_SUBCOMMAND_LABELS[`${noun} ${next}`] ??
        GH_SUBCOMMAND_LABELS[noun] ??
        "Working with GitHub"
      );
    }
    return "Working with GitHub";
  }

  const label = BASH_VERB_LABELS[verb];
  if (label) return label;

  reportSilentFallback(null, {
    feature: "command-center",
    op: "tool-label-fallback",
    message: "Unknown Bash verb",
    extra: { verb: sanitizeVerbForTelemetry(verb) },
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
      // Strip workspace/sandbox paths for the LEAK-SHAPE instrumentation only
      // (the return is intentionally discarded — `mapBashVerb` maps the raw
      // command through its own env/wrapper/segment walk, and the label is
      // always a table value, never derived text).
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
      return FALLBACK_LABELS[toolName] ?? "Working…";
  }
}

/**
 * Build the canonical `tool_use` WS message for both the legacy agent-runner
 * emitter and the cc-dispatcher emitter (#3235). Centralizing the shape here
 * means a future schema field flows through one edit instead of two parallel
 * ones — and pins the #2138 invariant: the raw SDK tool name is intentionally
 * NOT placed on the wire (information-disclosure mitigation, see PR #2115).
 */
export function buildToolUseWSMessage(args: {
  name: string;
  input: Record<string, unknown> | undefined;
  workspacePath: string | undefined;
  leaderId: DomainLeaderId;
}): WSMessage {
  return {
    type: "tool_use",
    leaderId: args.leaderId,
    label: buildToolLabel(args.name, args.input, args.workspacePath),
  };
}

/**
 * #5214 — build the canonical `tool_progress` heartbeat WS message for the
 * cc-dispatcher's `onToolProgress` forward. Shared in `tool-labels.ts` for the
 * same reason as {@link buildToolUseWSMessage} (#3235): a future schema change
 * to the `tool_progress` wire shape flows through one edit. Pins the #2138
 * invariant — the raw SDK `toolName` is routed through `buildToolLabel` (human
 * label only) and is intentionally NOT placed on the wire (information-
 * disclosure mitigation, see PR #2115). `SDKToolProgressMessage` carries no
 * `tool_input`, so `buildToolLabel(toolName, undefined, …)` falls to
 * `FALLBACK_LABELS` — a fine heartbeat label (mirrors `agent-runner.ts:1944`).
 */
export function buildToolProgressWSMessage(args: {
  toolName: string;
  elapsedSeconds: number;
  toolUseId: string;
  workspacePath: string | undefined;
  leaderId: DomainLeaderId;
}): WSMessage {
  return {
    type: "tool_progress",
    leaderId: args.leaderId,
    toolUseId: args.toolUseId,
    toolName: buildToolLabel(args.toolName, undefined, args.workspacePath),
    elapsedSeconds: args.elapsedSeconds,
  };
}
