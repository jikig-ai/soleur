// PR-A (#4124) — Deterministic-acknowledgment template + source-ref parser
// for the Inngest function `agent-on-spawn-requested`.
//
// PR-B (filed before PR-A merges; ADR-039) replaces the deterministic stub
// body with the Anthropic SDK leader-prompt loop. The provisional string +
// label name in this module are scope-flagged for the copywriter follow-up
// (see `## Follow-ups` in the PR-A plan).

export const ACK_LABEL = "soleur/acknowledged";

export const ACK_PR_COMMENT_TEMPLATE = [
  "Soleur acknowledged — full agent loop landing in PR-B (#4124 substrate).",
  "",
  "This deterministic stub confirms the click reached Soleur; the autonomous",
  "leader-prompt loop will replace this body with a per-action-class response",
  "once PR-B lands.",
].join("\n");

export interface ParsedSourceRef {
  /** Whether the source ref is a PR-shaped reference (drives the artifact path). */
  isPr: boolean;
  /** GitHub owner derived from the source-ref encoding. */
  owner: string;
  /** GitHub repo derived from the source-ref encoding. */
  repo: string;
  /** Issue / PR number extracted from the source ref. */
  number: number;
}

const SOURCE_REF_PATTERN =
  /^(pr|issue|ci|cve|secret-scan|link|anchor)-([^/]+)\/([^#]+)#(\d+)$/;

/**
 * Parses a `messages.source_ref` value into the (owner, repo, number) tuple
 * needed by `octokit.rest.issues.createComment` / `addLabels`.
 *
 * Source-ref shapes (per webhook ingest envelope):
 *   - `pr-<owner>/<repo>#<n>`
 *   - `issue-<owner>/<repo>#<n>`
 *   - `ci-<owner>/<repo>#<n>`
 *   - `cve-<owner>/<repo>#<n>`
 *   - `secret-scan-<owner>/<repo>#<n>`
 *   - `link-<owner>/<repo>#<n>` (kb_drift)
 *   - `anchor-<owner>/<repo>#<n>` (kb_drift)
 *
 * Throws on malformed input — callers MUST catch and UPDATE
 * action_sends.failure_reason. The strict regex is the parsing contract;
 * the Inngest function's `retries: 3` + final-retry-writes-failure_reason
 * shape covers transient cases while malformed refs deadletter to a
 * persisted failure_reason.
 */
export function parseSourceRef(sourceRef: string): ParsedSourceRef {
  const m = sourceRef.match(SOURCE_REF_PATTERN);
  if (!m) {
    throw new Error(`agent-on-spawn: malformed source_ref ${sourceRef}`);
  }
  return {
    isPr: m[1] === "pr",
    owner: m[2],
    repo: m[3],
    number: parseInt(m[4], 10),
  };
}
