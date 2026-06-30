// ---------------------------------------------------------------------------
// Repo-resolver divergence breadcrumb (ADR-044 PR-1, FR4).
//
// The dual-resolver divergence this PR fixes was ZERO-Sentry / invisible. This
// emits a queryable breadcrumb when the membership self-heal RESETS a non-member
// claim to solo, or when a post-switch self-heal fails — so the NEXT occurrence
// is queryable by fingerprint (no SSH). The Sentry issue-alert ROUTING rule is a
// fast-follow (see plan §Infrastructure); making the signal queryable is PR-1's
// observability job.
// ---------------------------------------------------------------------------

import { reportSilentFallback, hashUserId } from "@/server/observability";
import { sanitizeGitStderr } from "@/server/git-auth";

// Dedupe by (op, userId, claim) fingerprint — NOT just `op`. The non-member
// reset is read-time and mutates nothing, so without claim-pair fingerprinting
// it would re-fire on EVERY dispatch for a removed member → a breadcrumb storm
// that buries the first-occurrence signal (deepen arch P1). Process-local; a
// fresh process re-emits once, which is the intended first-occurrence behavior.
const seenFingerprints = new Set<string>();

/** Test seam — clear the dedupe set between cases (vitest isolates per file,
 *  but a single file exercising multiple fingerprints needs a reset). */
export function _resetResolverDivergenceDedupeForTests(): void {
  seenFingerprints.clear();
}

export type RepoResolverDivergenceOp =
  | "non-member-claim-reset"
  | "self-heal-failed"
  // Dispatch-time divergence (this PR): a member cold-dispatch into a
  // genuinely-connected workspace (repoUrl present / repo_status indicates a
  // connection) whose credential read `resolve_workspace_installation_id`
  // returned NULL (membership-deny or a transient RPC blip). The readiness gate
  // would otherwise fast-path this into a repo-less agent spawn; instead it
  // fails honestly and emits THIS op so the previously-dark dispatch path is
  // queryable + paging. Distinct from the catch-block `self-heal-failed` op
  // (an orchestration-infra crash) — see cc-dispatcher.ts emit-site notes.
  | "connected-null-install-at-dispatch"
  // Per-dispatch reprovision-path divergence (ADR-044 PR-3): the warm+cold
  // `reprovisionWorkspaceOnDispatch` (cc-dispatcher.ts:2899) used to re-derive the
  // workspace id via three divergent resolvers — the membership-verified path
  // diverged from the raw-claim install/repo, so a non-member/stale-claim member
  // grafted the team repo into the solo `/workspaces/<userId>` (no `.git`). The fix
  // resolves ONCE via the membership-verified resolver and threads the single id;
  // this op fires when that resolve RESETS a non-member claim to solo (formerly
  // zero-Sentry on the reprovision path). Distinct from the cold-factory
  // `non-member-claim-reset` so the two sites are queryable independently.
  | "reprovision-non-member-claim-reset"
  // On-disk corruption divergence (2026-06-19): a cold dispatch into a
  // genuinely-connected workspace (install NON-null, distinct from the op above)
  // whose `<ws>/.git` EXISTS but is not a valid work tree (partial/interrupted
  // clone, failed atomic-rename). The presence-only readiness gate used to
  // fast-path this into a repo-less spawn (silent). The corrupt-worktree graft
  // now removes a positively-fingerprinted empty-corrupt `.git`, re-clones, and
  // emits THIS op. `extra.recovered` distinguishes a self-healed re-clone
  // (true) from an unrecovered honest-block (false).
  | "corrupt-worktree-at-dispatch";

/**
 * Emit a fingerprint-deduped `repo_resolver_divergence` breadcrumb. `userId` is
 * pseudonymized to `userIdHash` at the `reportSilentFallback` emit boundary
 * (ADR-029); `extra` otherwise carries ONLY the two workspace ids — no
 * `repoUrl`/`installationId`/raw-userId (security P2).
 */
export function reportRepoResolverDivergence(args: {
  userId: string;
  op: RepoResolverDivergenceOp;
  activeClaimWorkspaceId: string;
  resolvedWorkspaceId: string;
  /**
   * Corrupt-worktree op only: true when the corrupt `.git` was removed and
   * re-cloned successfully (self-healed), false when the re-clone failed and the
   * dispatch honest-blocks. Omitted for the other ops. Non-credential, safe in
   * `extra`. Folded into the dedupe fingerprint so a recovered breadcrumb and a
   * later unrecovered page on the same workspace are not collapsed.
   */
  recovered?: boolean;
}): void {
  const recoveredKey =
    args.recovered === undefined ? "" : `:${args.recovered ? "r" : "u"}`;
  const fingerprint = `${args.op}:${args.userId}:${args.activeClaimWorkspaceId}${recoveredKey}`;
  if (seenFingerprints.has(fingerprint)) return;
  seenFingerprints.add(fingerprint);

  reportSilentFallback(new Error("repo_resolver_divergence"), {
    feature: "repo-resolver-divergence",
    op: args.op,
    extra: {
      userId: args.userId, // → userIdHash at the emit boundary (never raw)
      activeClaimWorkspaceId: args.activeClaimWorkspaceId,
      resolvedWorkspaceId: args.resolvedWorkspaceId,
      ...(args.recovered === undefined ? {} : { recovered: args.recovered }),
    },
  });
}

/**
 * Emit a fingerprint-deduped `agent_readiness_self_stop` event (#5733 Phase 1b).
 *
 * The `/soleur:go` Step 0.0 readiness self-stop is PROMPT-DRIVEN — the agent
 * reasons over prompt text and stops, emitting NO server-side Sentry event
 * (the deepest reason all three prior server-side fixes left "zero events on
 * the agent surface"). This makes the strand observable by emitting a
 * server-side signal at the dispatch readiness gate the moment the gate detects
 * a `.git` shape that WOULD strand the agent's in-bwrap `git rev-parse` (a stale
 * gitdir-pointer FILE / structurally-invalid tree), BEFORE the self-heal runs —
 * so the strand is queryable and H2 is confirmed retroactively on the same
 * dispatch.
 *
 * QUERY-ONLY BY DESIGN: the strand auto-heals in the SAME dispatch (the stale
 * pointer is unlinked + re-cloned before `query()`), so this is a *discoverability*
 * signal (the plan's `jq length` post-deploy check), not a page — it deliberately
 * gets no `sentry_issue_alert` rule. `reportSilentFallback` still `captureException`s
 * it, so it is queryable in Sentry.
 *
 * DISTINCT `Error` message → its OWN Sentry issue group (NOT the shared
 * `repo_resolver_divergence` group), so the discoverability query counts it
 * independently.
 *
 * PSEUDONYMIZATION (ADR-029, security #5733): `userId` is renamed to `userIdHash`
 * at the `reportSilentFallback` boundary. CRITICAL — for a SOLO workspace
 * `workspace_id == user_id`, so the active-workspace id IS the raw userId; it is
 * pre-hashed here to `activeWorkspaceIdHash` and the raw `workspacePath`
 * (`<root>/<id>`) is NOT emitted, so the rename-at-boundary is not defeated by a
 * sibling field. `extra` carries NO `installationId`/`repoUrl` (credential-grant
 * identifiers) and NO raw `gitdirTarget` (only the `gitKind` + escape boolean).
 */
/** Where the self-stop was observed. `host-pre-heal` is the server-side
 *  dispatch readiness gate (lstat shape OR the #5733 host `rev-parse` confirm);
 *  `in-sandbox-backstop` is the agent's OWN in-bwrap Step 0.0 `rev-parse` result
 *  (deliverable C2) — robust to shapes the host confirm is blind to (escaping
 *  pointer, object-store residual). Folded into the dedupe fingerprint so the two
 *  surfaces are counted independently for the same workspace+kind, AND promoted to
 *  a searchable Sentry `source:` tag (the `source:in-sandbox-backstop` query the
 *  plan advertises — `extra` alone is not queryable). */
export type AgentReadinessSelfStopSource = "host-pre-heal" | "in-sandbox-backstop";

export function reportAgentReadinessSelfStop(args: {
  userId: string;
  activeWorkspaceId: string;
  /** lstat-structural validity (`isValidGitWorkTree`) — true for the FILE-pointer
   *  trap AND for the dir-valid-that-rev-parse-rejects trap, which is exactly why
   *  the strand was previously silent. */
  gitValid: boolean;
  /** Structural `.git` shape kind (`probeGitWorktreeShape`) — distinguishes a
   *  file-pointer strand from a dir-invalid / absent strand in the one event. */
  gitKind: string;
  /** For a file-pointer: did the gitdir target escape the workspace (denyRead)? */
  gitdirEscapesWorkspace?: boolean;
  /**
   * #5733 deliverable A/C: the AUTHORITATIVE `git rev-parse --is-inside-work-tree`
   * verdict (host confirm OR the agent's in-sandbox result). Omitted on the
   * pure-lstat pre-heal emit (where no rev-parse ran). When present and `false`
   * alongside `gitValid=true`, the event itself shows the proxy-vs-invariant
   * divergence (lstat said ready; `git` itself disagrees). NEVER carries the
   * subprocess stderr/path (the raw path == raw userId for a solo workspace).
   */
  gitRevParseValid?: boolean;
  /** Observation surface (defaults to `host-pre-heal`). */
  source?: AgentReadinessSelfStopSource;
}): void {
  const source: AgentReadinessSelfStopSource = args.source ?? "host-pre-heal";
  // Dedupe by (op, userId, workspace, .git kind, source) — a recurring strand for
  // one workspace emits once per process, but a SHAPE CHANGE (e.g. pointer →
  // absent after a partial heal) OR a DIFFERENT surface (host vs in-sandbox
  // backstop) re-fires. Process-local; a fresh process re-emits once.
  const fingerprint = `agent-readiness-self-stop:${args.userId}:${args.activeWorkspaceId}:${args.gitKind}:${source}`;
  if (seenFingerprints.has(fingerprint)) return;
  seenFingerprints.add(fingerprint);

  reportSilentFallback(new Error("agent_readiness_self_stop"), {
    feature: "agent-readiness-self-stop",
    op: "agent-readiness-self-stop",
    // PROMOTED to searchable Sentry tags — `extra` is NOT queryable, and the plan
    // advertises `source:in-sandbox-backstop` + `gitKind:` discoverability queries
    // that only work as tags. All three are low-cardinality enums/booleans with NO
    // PII (never the hashed/raw ids, never the gitdirTarget/path). Kept in `extra`
    // below too (structured context) — the tags are what make them queryable.
    tags: {
      source,
      gitKind: args.gitKind,
      ...(args.gitRevParseValid === undefined
        ? {}
        : { gitRevParseValid: String(args.gitRevParseValid) }),
    },
    extra: {
      userId: args.userId, // → userIdHash at the emit boundary (never raw)
      // Pre-hashed: for a solo workspace this equals the raw userId, which the
      // boundary rename would otherwise miss (it only transforms the `userId` key).
      activeWorkspaceIdHash: hashUserId(args.activeWorkspaceId),
      gitValid: args.gitValid,
      gitKind: args.gitKind,
      source,
      ...(args.gitRevParseValid === undefined
        ? {}
        : { gitRevParseValid: args.gitRevParseValid }),
      ...(args.gitdirEscapesWorkspace === undefined
        ? {}
        : { gitdirEscapesWorkspace: args.gitdirEscapesWorkspace }),
    },
  });
}

/**
 * #5733 D0 — un-blind the previously SWALLOWED dispatch-time clone failure. The
 * cold path already clones in-process into the agent's own `workspacePath`
 * (`cc-dispatcher.ts:1987`), but its `"failed"` outcome was discarded, so a
 * genuine clone failure (token/network/entitlement) flowed silently into a false
 * `ready`. This emits a DISTINCT, queryable + PAGING `repo_clone_failed` event so
 * the real clone error is operator-actionable (no SSH) — wired into
 * `ensure-workspace-repo.ts`'s clone catch so EVERY caller (cold/warm/reconcile)
 * surfaces it.
 *
 * SECURITY (#5733 P1): `reason` is git stderr / an `execFile` rejection `.message`
 * that carries the `repo_url` AND the absolute `/workspaces/<uuid>` path
 * (PII-equivalent for a solo workspace, where `workspace_id == user_id`). The
 * installation token NEVER rides `err` (it is GIT_ASKPASS env, never argv/URL).
 * `sanitizeGitStderr` is applied HERE (the value reaching `captureException`),
 * stripping every absolute path and the https repo URL — so neither the token nor
 * any raw path/url survives. `extra` excludes `repoUrl`/`installationId`; `userId`
 * is renamed to `userIdHash` at the boundary and the workspace id is pre-hashed
 * (it equals the raw userId for a solo workspace, which the boundary rename would
 * otherwise miss). DISTINCT `Error` message → its OWN Sentry issue group.
 */
export function reportRepoCloneFailed(args: {
  userId: string;
  activeWorkspaceId: string;
  /** Raw git stderr / execFile rejection message — sanitized HERE before emit. */
  reason: string;
}): void {
  const fingerprint = `repo-clone-failed:${args.userId}:${args.activeWorkspaceId}`;
  if (seenFingerprints.has(fingerprint)) return;
  seenFingerprints.add(fingerprint);

  reportSilentFallback(new Error("repo_clone_failed"), {
    feature: "repo-clone-failed",
    op: "repo-clone-failed",
    extra: {
      userId: args.userId, // → userIdHash at the emit boundary (never raw)
      activeWorkspaceIdHash: hashUserId(args.activeWorkspaceId),
      // Sanitized at the write boundary — no token, no absolute path, no repo URL.
      reason: sanitizeRepoCloneReason(args.reason),
    },
  });
}

// GitHub token shapes (App installation `ghs_`, PAT `ghp_`/`github_pat_`, OAuth
// `gho_`, user-to-server `ghu_`, refresh `ghr_`). The production token NEVER rides
// `err` (it is GIT_ASKPASS env, never argv/URL/stderr), so this is defense-in-depth
// — but a belt-and-suspenders redaction guarantees AC0b even if a future git/exec
// shape ever surfaces a credential in a rejection message.
const GH_TOKEN_RE = /\b(?:gh[posru]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,})\b/g;

/** Redact token shapes THEN strip absolute paths/URLs (`sanitizeGitStderr`), so the
 *  value reaching `captureException` carries neither a credential nor a raw path. */
function sanitizeRepoCloneReason(raw: string): string {
  return sanitizeGitStderr(raw.replace(GH_TOKEN_RE, "<redacted>"));
}

/**
 * #5733 deliverable A — low-signal breadcrumb for a host `rev-parse` confirm that
 * came back INCONCLUSIVE twice (spawn-error / timeout / EACCES). The readiness
 * gate FAILS-OPEN on this (spawns rather than honest-blocking a healthy repo), so
 * this is a DISTINCT op/issue-group from `agent_readiness_self_stop` — it must NOT
 * inflate the strand discoverability count. Same pseudonymization bar: only the
 * hashed workspace id, NEVER the probe stderr/path.
 */
export function reportAgentReadinessProbeInconclusive(args: {
  userId: string;
  activeWorkspaceId: string;
}): void {
  const fingerprint = `agent-readiness-probe-inconclusive:${args.userId}:${args.activeWorkspaceId}`;
  if (seenFingerprints.has(fingerprint)) return;
  seenFingerprints.add(fingerprint);

  reportSilentFallback(new Error("agent_readiness_probe_inconclusive"), {
    feature: "agent-readiness-self-stop",
    op: "agent-readiness-probe-inconclusive",
    extra: {
      userId: args.userId, // → userIdHash at the emit boundary (never raw)
      activeWorkspaceIdHash: hashUserId(args.activeWorkspaceId),
    },
  });
}
