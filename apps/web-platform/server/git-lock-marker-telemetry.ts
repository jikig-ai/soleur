// Mirror the in-sandbox git-lock wedge markers to a QUERYABLE sink (#6184 follow-up).
//
// worktree-manager.sh (running INSIDE the agent sandbox) emits diagnostic markers to
// the Bash tool's stdout/stderr when worktree creation is wedged by a masked
// `.git/config.lock`:
//   - SOLEUR_GIT_LOCK_DIAG            — forensic (file type, owner, perms, mtime, rdev, mount)
//   - SOLEUR_GIT_LOCK_UNREMOVABLE     — a lock that could not be cleared (the wedge)
//   - SOLEUR_GIT_LOCK_TEMP_WEDGED     — the lockless-writer temp lock was ALSO masked (glob mask)
//   - SOLEUR_GIT_LOCK_IDENTITY_WEDGED — ensure_worktree_identity's set-from-global write could
//                                       not be applied (reason=native-eexist|common-dir-unresolved)
//   - SOLEUR_GIT_LOCK_IDENTITY_DIAG   — benign precondition: the set-from-global branch was taken
//                                       (local identity absent → drift); NOT a wedge
//   - "worktree wedge: ..."           — ensure_bare_config gave up
//
// Before this hook those lines went ONLY to blind agent-sandbox stdout — not mirrored
// to any sink an operator can query (ADR-081's stated observability gap). Diagnosing the
// #6184 wedge therefore required asking the operator to paste `findmnt` from the live
// session. This PostToolUse(Bash) hook runs SERVER-SIDE (the Node dispatch process, where
// the pino logger ships to stdout → journald → vector → Better Stack, plus a Sentry
// breadcrumb), scans Bash output for the markers, and re-emits each as a structured log —
// so the next wedge is self-diagnosable without a human round-trip.
//
// Design invariants:
//   - Observe-only + fail-open: always returns `{}`, never throws into the SDK turn.
//   - Privacy: emits ONLY the matched marker lines (device/path/mount forensic — no user
//     content), never the surrounding Bash output. A bounded scan (line count + line
//     length caps) prevents log spam / a pathological-output DoS.
//   - The marker text is diagnostic constants + filesystem metadata the platform owns; it
//     carries no repo contents, so re-logging it verbatim is safe.

import type { HookCallback, PostToolUseHookInput } from "@anthropic-ai/claude-agent-sdk";
import { createChildLogger } from "./logger";
import { reportSilentFallback } from "./observability";

const log = createChildLogger("git-lock-marker-telemetry");

// Matches the marker sentinels emitted by two in-sandbox surfaces:
//   - worktree-manager.sh — the git-lock wedge markers (SOLEUR_GIT_LOCK_*, "worktree wedge:")
//     including the ensure_worktree_identity identity-authority markers
//     (SOLEUR_GIT_LOCK_IDENTITY_WEDGED = a failed set-from-global write;
//     SOLEUR_GIT_LOCK_IDENTITY_DIAG = the benign set-from-global precondition marker, #6184).
//   - git-repo-readiness-diag.sh — the readiness-gate forensic (SOLEUR_GIT_REPO_DIAG),
//     emitted by soleur:go Step 0.0 when git rejects the workspace repo (a layer ABOVE
//     worktree creation, previously uninstrumented — #6184 round 3).
// Kept in sync with those scripts; a drift test (git-lock-marker-telemetry.test.ts) pins
// the pattern set against the live scripts so a renamed sentinel fails CI instead of going
// silently unmirrored.
const MARKER_RE =
  /^(?:SOLEUR_GIT_LOCK_(?:DIAG|UNREMOVABLE|TEMP_WEDGED)\b.*|SOLEUR_GIT_LOCK_IDENTITY_(?:WEDGED|DIAG)\b.*|SOLEUR_GIT_REPO_DIAG\b.*|worktree wedge:.*)$/;

// A wedge (vs. a benign DIAG) is any marker that indicates git operations could not
// proceed: an unremovable/masked lock, a temp-wedge, an ensure_bare_config give-up, a failed
// identity set-from-global write, OR a readiness-gate rejection (SOLEUR_GIT_REPO_DIAG is only
// emitted on the not-ready path). SOLEUR_GIT_LOCK_IDENTITY_WEDGED is a wedge;
// SOLEUR_GIT_LOCK_IDENTITY_DIAG is EXCLUDED — it is the benign precondition marker, so a
// successful drift-set must not page as wedged=true / log.error.
const WEDGE_RE =
  /^(?:SOLEUR_GIT_LOCK_(?:UNREMOVABLE|TEMP_WEDGED)\b|SOLEUR_GIT_LOCK_IDENTITY_WEDGED\b|SOLEUR_GIT_REPO_DIAG\b|worktree wedge:)/;

// Bounds: scan at most this many lines, keep at most this many matched markers, and
// truncate any single marker line to this many chars. A wedged run emits a handful of
// markers; these caps only fire on pathological/hostile output.
const MAX_SCAN_LINES = 4000;
const MAX_MARKERS = 12;
const MAX_MARKER_LEN = 600;

/**
 * Coerce a PostToolUse `tool_response` (typed `unknown`) into scannable text. The Bash
 * tool's response is commonly a string, or an object with `stdout`/`stderr`, or an array
 * of `{ type: "text", text }` content blocks. Unknown shapes yield "" (no markers).
 */
export function toolResponseToText(resp: unknown): string {
  if (typeof resp === "string") return resp;
  if (Array.isArray(resp)) {
    return resp
      .map((b) =>
        b && typeof b === "object" && typeof (b as { text?: unknown }).text === "string"
          ? (b as { text: string }).text
          : "",
      )
      .join("\n");
  }
  if (resp && typeof resp === "object") {
    const o = resp as { stdout?: unknown; stderr?: unknown; content?: unknown };
    if (typeof o.content === "string") return o.content;
    if (Array.isArray(o.content)) return toolResponseToText(o.content);
    const parts: string[] = [];
    if (typeof o.stdout === "string") parts.push(o.stdout);
    if (typeof o.stderr === "string") parts.push(o.stderr);
    if (parts.length > 0) return parts.join("\n");
  }
  return "";
}

export interface GitLockMarker {
  /** The marker line, trimmed + length-bounded. */
  line: string;
  /** true when the marker indicates worktree creation is wedged (not a benign DIAG). */
  wedged: boolean;
}

/**
 * Extract the git-lock marker lines from arbitrary Bash output. Pure + bounded so it is
 * unit-testable and cannot be turned into a log-amplification vector by hostile output.
 */
export function extractGitLockMarkers(text: string): GitLockMarker[] {
  if (!text) return [];
  const out: GitLockMarker[] = [];
  let scanned = 0;
  for (const raw of text.split("\n")) {
    if (scanned++ >= MAX_SCAN_LINES || out.length >= MAX_MARKERS) break;
    const line = raw.trim();
    if (!MARKER_RE.test(line)) continue;
    out.push({
      line: line.length > MAX_MARKER_LEN ? `${line.slice(0, MAX_MARKER_LEN)}…` : line,
      wedged: WEDGE_RE.test(line),
    });
  }
  return out;
}

/**
 * Build the PostToolUse(Bash) hook that mirrors in-sandbox git-lock markers to the
 * server-side logger. Factory is side-effect-free so a builder-time call inside the
 * `options.hooks` literal can never throw into `query()` startup.
 *
 * @param workspacePath included in each structured log so a wedge is attributable to a
 *   workspace without correlating separate lines.
 */
export function createGitLockMarkerHook(workspacePath: string): HookCallback {
  return async (input) => {
    try {
      const i = input as PostToolUseHookInput;
      if (i.tool_name !== "Bash") return {};
      const markers = extractGitLockMarkers(toolResponseToText(i.tool_response));
      if (markers.length === 0) return {};
      const anyWedged = markers.some((m) => m.wedged);
      const payload = {
        // `sec: true` — this is a platform-integrity signal, not per-user noise.
        sec: true,
        workspacePath,
        wedged: anyWedged,
        markerCount: markers.length,
        markers: markers.map((m) => m.line),
      };
      // A wedge is an error (a blocked session — a git-lock wedge OR a readiness-gate
      // rejection); a benign DIAG is a warning. Both reach Better Stack (pino → stdout →
      // journald → vector) and a Sentry breadcrumb.
      if (anyWedged) {
        log.error(payload, "in-sandbox git wedge/rejection detected (worktree or readiness-gate blocked)");
      } else {
        log.warn(payload, "in-sandbox git diagnostic emitted (no wedge)");
      }
      return {};
    } catch (err) {
      // Fail-open: never throw into the SDK turn. The scanned text is model-adjacent, so
      // keep the error message STATIC and route the detail through the silent-fallback
      // mirror rather than interpolating tool output into the log line.
      log.warn({ err, workspacePath }, "git-lock marker hook failed (fail-open: no mirror)");
      reportSilentFallback(err, { feature: "git-lock-marker-telemetry", op: "scan" });
      return {};
    }
  };
}
