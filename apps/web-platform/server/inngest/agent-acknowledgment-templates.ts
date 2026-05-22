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

// PR-A (#4124) — match the format emitted by
// `server/inngest/functions/github-on-event.ts:deriveSourceRef`:
//   - `pr-<owner>:<repo>:<n>`              for pull_request
//   - `issue-<owner>:<repo>:<n>`           for issues
//   - `secret-scan-<owner>:<repo>:<n>`     for secret-scan alerts
//
// The `:` (not `/`) is used between owner/repo because `:` is invalid in
// GitHub repo names — so `org/repo-1` and `org/repo` with number 1
// cannot collide at the dedup partial-unique index.
//
// Out-of-band shapes that do NOT carry (owner, repo, number) and so are
// rejected here:
//   - `ci-<workflow_run_id>` (no repo info at all)
//   - `cve-GHSA-xxxx-xxxx-xxxx` (advisory id; not an issue-comment target)
//   - `link-<hash>` / `anchor-<hash>` (kb_drift; resolved server-side in PR-B)
//
// Callers MUST catch the malformed-throw and UPDATE
// action_sends.failure_reason. PR-B replaces the ci-/cve-/kb-drift legs
// with per-class targeting via the leader-prompt loop.
const SOURCE_REF_PATTERN =
  /^(pr|issue|secret-scan)-([^:]+):([^:]+):(\d+)$/;

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
