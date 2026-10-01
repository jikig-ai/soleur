// The single accessor seam for the Workstream board (the "same shared fn" rule):
// BOTH the HTTP route (app/api/workstream/issues) AND the agent read tool
// (server/workstream/workstream-tools) import this directly — the tool never
// self-calls the route.
//
// v2 re-backs the board on the active workspace's REAL connected GitHub repo via
// the ADR-044 resolution chain (membership-checked installation token, NEVER a
// PAT, never request input). The fabricated seed is GONE — no data may ever be
// shown that the user's own repo didn't produce.
//
// Empty-vs-throw (load-bearing — CPO / observability):
//   - `[]` is reserved STRICTLY for (a) no repo connected, and (b) a connected
//     repo whose listRepoIssues genuinely yields zero issues. Nothing else.
//   - EVERY degraded read THROWS `WorkstreamDegradedError` (route → 502, tool →
//     isError), so a degrade can never masquerade as "no issues." Previously a
//     transient resolve failure (cold token cache / connection pool → repoUrl
//     null-from-error; or a lost/blipped installation) collapsed to a 200 `[]`,
//     and SWR replaced the board's data with the empty payload → a FALSE
//     "No issues to display" flash mid-refresh. Now those paths mirror to Sentry
//     AND throw, so SWR keeps the prior issues + shows the amber "showing the
//     last loaded issues" banner instead. The GitHub LIST failure already threw.
//   - Every throw site mirrors to Sentry FIRST (mirror-precedes-throw): the HTTP
//     route skips re-capture for WorkstreamDegradedError to avoid a double event,
//     and the agent-tool caller does no capture of its own — so the source mirror
//     is the sole Sentry event on both callers.

import {
  githubIssueToWorkstreamIssue,
  WorkstreamDegradedError,
  type BoardIssueInput,
  type WorkstreamBoardMeta,
  type WorkstreamIssue,
} from "@/lib/workstream";
import { type WorkstreamFeedEvent } from "@/lib/workstream-feed";
import { getAppSlug } from "@/server/github-app";
import { readCurrentRepoUrlResult } from "@/server/current-repo-url";
import { parseConnectedRepo } from "@/server/github-repo-parse";
import { resolveInstallationId } from "@/server/resolve-installation-id";
import { resolveEffectiveInstallationId } from "@/server/cc-effective-installation";
import { fetchBoardStatusMap, listRepoIssues } from "@/server/github-read-tools";
import { reportSilentFallback } from "@/server/observability";
import { createChildLogger } from "@/server/logger";

const log = createChildLogger("workstream-issues");

/**
 * Resolve the Soleur GitHub-App bot slug for creator attribution (`<slug>[bot]`
 * detection). NEVER throws — a getAppSlug() failure is a SILENT graceful degrade
 * (the issue's author renders as a plain human) mirrored to Sentry so the degrade
 * is observable without breaking the board.
 */
async function resolveBotSlug(): Promise<string | null> {
  try {
    return await getAppSlug();
  } catch (err) {
    reportSilentFallback(err, {
      feature: "workstream",
      op: "workstream-botslug-degrade",
    });
    return null;
  }
}

/**
 * Read the canonical GitHub Project v2 board Status map (issueNumber → Status
 * name) for the connected repo, or null when unconfigured / not the board org /
 * the read fails. NEVER throws — a degraded board read falls back to label
 * derivation (mirrored to Sentry) so the tab still renders issues (Phase 2,
 * ADR-097). Configured via SOLEUR_KANBAN_ORG + SOLEUR_KANBAN_PROJECT_NUMBER.
 */
async function readBoardStatuses(
  installationId: number,
  owner: string,
  repo: string,
): Promise<Map<number, string> | null> {
  const org = process.env.SOLEUR_KANBAN_ORG?.trim();
  const projectNumber = Number(process.env.SOLEUR_KANBAN_PROJECT_NUMBER);
  if (!org || !Number.isFinite(projectNumber) || projectNumber <= 0) return null;
  // The board is org-owned — only read it for repos belonging to that org.
  if (owner.toLowerCase() !== org.toLowerCase()) return null;
  try {
    return await fetchBoardStatusMap(
      installationId,
      org,
      projectNumber,
      `${owner}/${repo}`,
    );
  } catch (err) {
    reportSilentFallback(err, {
      feature: "workstream",
      op: "board-status-read",
      extra: { owner, repo, projectNumber },
    });
    return null; // degrade to label/state derivation
  }
}

/** The resolved read preamble — everything a board read needs before any issue
 *  bytes can flow. `kind:"empty"` is the honest-empty arm (no repo connected);
 *  `kind:"ok"` carries the connected repo's coordinates + the bot slug. `board`
 *  is the board-precedence meta — a PURE function of the already-parsed owner +
 *  two env vars, so it rides the same repo resolution as the issue fetch (one
 *  `getCurrentRepoUrl` read, zero meta-vs-issues TOCTOU). */
export type BoardReadContext =
  | { kind: "empty"; userId: string; board: WorkstreamBoardMeta }
  | {
      kind: "ok";
      userId: string;
      owner: string;
      repo: string;
      installationId: number;
      botSlug: string | null;
      board: WorkstreamBoardMeta;
    };

/**
 * Resolve the shared read preamble for BOTH the bulk accessor and the streamed
 * feed. Throws WorkstreamDegradedError (mirror-precedes-throw, verbatim) on
 * every degraded path — callers that stream MUST run this BEFORE opening the
 * response body so a degrade still answers a real status code, not an SSE
 * skeleton.
 */
export async function resolveBoardReadContext(
  userId: string,
): Promise<BoardReadContext> {
  const { url: repoUrl, degraded } = await readCurrentRepoUrlResult(userId);
  if (degraded) {
    // P2: the current repo couldn't be resolved due to a TRANSIENT failure
    // (cold token cache → RuntimeAuthError, or a cold connection pool →
    // workspaces query error). It is already mirrored upstream at WARN/ERROR
    // under feature:repo-scope (ADR-059), but that shared quiet signal is not
    // queryable under the board's own feature — so mirror a workstream-scoped
    // event FIRST (mirror-precedes-throw; the route skips re-capture for the
    // typed error, the agent tool does no capture), THEN throw so this surfaces
    // as a 502/isError instead of a false empty board.
    reportSilentFallback(new Error("current repo unresolved (degraded read)"), {
      feature: "workstream",
      op: "repo-unresolved",
      extra: { userId },
    });
    throw new WorkstreamDegradedError(
      "workstream read degraded: current repo unresolved",
    );
  }
  const parsed = parseConnectedRepo(repoUrl);
  // Board-precedence meta — pure function of the parsed owner + two env vars
  // (the old resolveWorkstreamBoardMeta re-read repo_url off a SECOND DB hit,
  // could throw post-headers, and went degrade-blind through getCurrentRepoUrl;
  // computing it here discharges all three + the TOCTOU).
  const kanbanOrg = process.env.SOLEUR_KANBAN_ORG?.trim().toLowerCase();
  const board: WorkstreamBoardMeta = {
    onKanbanOrg: Boolean(
      parsed && kanbanOrg && parsed.owner.toLowerCase() === kanbanOrg,
    ),
    projectWritable: process.env.SOLEUR_KANBAN_PROJECT_WRITABLE === "1",
  };

  if (!parsed) {
    // honest empty: no repo connected — meta is all-false except the env grant.
    return { kind: "empty", userId, board };
  }

  // The bot slug (a cold GitHub /app RT) is independent of installation
  // resolution — overlap them so the preamble costs max(), not sum().
  const storedP = resolveInstallationId(userId);
  const botSlugP = resolveBotSlug();
  const stored = await storedP;
  const installationId = await resolveEffectiveInstallationId({
    userId,
    installationId: stored,
    repoUrl,
  });
  if (installationId === null) {
    // P1: repoUrl present but no installation resolvable (revoked/lost grant OR
    // a transient RPC blip) — a DEGRADED read, not "no issues". Mirror to Sentry
    // FIRST (cq-silent-fallback-must-mirror-to-sentry; mirror-precedes-throw),
    // then throw so the board 502s instead of flashing a false EmptyState.
    reportSilentFallback(new Error("no installation for connected repo"), {
      feature: "workstream",
      op: "no-installation",
      extra: { userId },
    });
    throw new WorkstreamDegradedError(
      "workstream read degraded: no installation for connected repo",
    );
  }

  // Bot slug for creator attribution (Soleur-bot detection). Degrade-safe: a null
  // slug renders every author as a plain human (no throw, mirrored to Sentry).
  const botSlug = await botSlugP;

  return {
    kind: "ok",
    userId,
    owner: parsed.owner,
    repo: parsed.repo,
    installationId,
    botSlug,
    board,
  };
}

/** Map one board input to a card, applying the Project Status when a map has
 *  landed (ADR-097 precedence); falls back to label/state derivation. */
function mapBoardIssue(
  input: BoardIssueInput,
  boardMap: Map<number, string> | null | undefined,
  botSlug: string | null,
): WorkstreamIssue {
  return githubIssueToWorkstreamIssue(
    boardMap ? { ...input, boardStatus: boardMap.get(input.number) } : input,
    botSlug,
  );
}

/**
 * Collect every upstream issue for a pre-resolved context, mapped to the board
 * model. Shared by the bulk accessor and the route's JSON arm (which needs the
 * ctx it already resolved for `board` + status codes — this keeps the read a
 * single repo resolution, not a second `getCurrentRepoUrl` hit).
 */
export async function collectWorkstreamIssues(
  ctx: BoardReadContext,
): Promise<WorkstreamIssue[]> {
  if (ctx.kind === "empty") return [];

  // Throws on any GitHub API failure (404/403/5xx) — caller surfaces 502/isError.
  const raw = await listRepoIssues(ctx.installationId, ctx.owner, ctx.repo);

  // Phase 2 (ADR-097): prefer the canonical Project v2 board Status. Degrade-safe
  // — a null map (unconfigured / not the board org / read failed) leaves each
  // issue to label/state derivation, so the tab never breaks on a board hiccup.
  const boardStatuses = await readBoardStatuses(
    ctx.installationId,
    ctx.owner,
    ctx.repo,
  );

  const issues = raw.map((input) =>
    mapBoardIssue(input, boardStatuses, ctx.botSlug),
  );

  // Liveness signal (NET-NEW — this function had no success-path log). Cosmetic
  // attribution coverage per board read; no alert target.
  log.info(
    {
      creatorAttributionCoverage: {
        total: issues.length,
        withCreator: issues.filter((i) => i.creator).length,
        withInitiator: issues.filter((i) => i.creator?.initiatorLogin).length,
      },
    },
    "workstream board read",
  );

  return issues;
}

/**
 * Read the active workspace's connected-repo issues, mapped to the board model.
 * owner/repo + installation derive ONLY from the server-resolved active
 * workspace (ADR-044) — never request input — so there is no cross-tenant read.
 */
export async function getWorkstreamIssues(
  userId: string,
): Promise<WorkstreamIssue[]> {
  return collectWorkstreamIssues(await resolveBoardReadContext(userId));
}

/** Thrown inside the feed loop when the consumer went away (client disconnect
 *  or the cap fired) — stops the upstream page walk WITHOUT emitting an error
 *  frame or a Sentry event: an abandoned feed is not a failure. */
export class StreamAbortedError extends Error {
  constructor() {
    super("workstream feed aborted");
    this.name = "StreamAbortedError";
  }
}

/**
 * Progressive variant of the board read for the SSE arm: emits one `issues`
 * frame per upstream REST page as it resolves (delta with upsert-by-id on the
 * client — never a cumulative snapshot), so the first cards paint after ~1
 * upstream page instead of the whole 23+10-call chain.
 *
 * The Project v2 Status read runs in PARALLEL — gating the feed behind its up
 * to-10 sequential GraphQL pages would reproduce the stall for exactly the org
 * where board precedence applies. When the map lands mid-feed, ONE `issues`
 * frame carries the full re-mapped cards for already-emitted issues whose
 * column/`live` changed (client upsert is whole-object — the same wire
 * semantics with zero extra frame types, and future boardStatus-dependent
 * fields reconcile for free); pages emitted after it lands carry the board
 * status inline. A null map (unconfigured / read degraded) reconciles nothing.
 *
 * Failure semantics: `ctx` is PRE-resolved by the caller so resolution degrades
 * still answer real status codes; a throw inside the page loop emits `error`
 * then rethrows for the route's Sentry capture; `isAborted` (client disconnect
 * or cap) throws StreamAbortedError — the loop stops silently (no error frame,
 * no capture, a bounded log) instead of burning the remaining ~30 upstream
 * calls on a dead socket.
 */
export async function streamWorkstreamIssues(
  ctx: BoardReadContext,
  emit: (event: WorkstreamFeedEvent) => void,
  isAborted?: () => boolean,
): Promise<void> {
  const startedAt = Date.now();
  let frames = 0;
  let issueCount = 0;
  const send = (event: WorkstreamFeedEvent) => {
    frames += 1;
    emit(event);
  };
  // Stream-summary liveness signal — perception-path metric riding the same
  // pino → Better Stack channel as the bulk "workstream board read" log.
  const logSummary = (openTruncated: boolean) =>
    log.info(
      { frames, issueCount, durationMs: Date.now() - startedAt, openTruncated },
      "workstream feed streamed",
    );

  send({ type: "meta", board: ctx.board });
  if (ctx.kind === "empty") {
    send({ type: "done", openTruncated: false });
    logSummary(false);
    return;
  }

  let openTruncated = false;
  let failed = false; // set by error/abort arms — suppresses a late reconcile
  // Inputs emitted while the board map was still pending, paired with their
  // emitted card — the reconcile diff base (recompute only `next`, not `prev`).
  const emittedPreMap: { input: BoardIssueInput; issue: WorkstreamIssue }[] = [];
  let boardMap: Map<number, string> | null | undefined;
  try {
    const boardPromise = readBoardStatuses(
      ctx.installationId,
      ctx.owner,
      ctx.repo,
    ).then((m) => {
      boardMap = m;
      // `error` is terminal — a reconcile resolving after a mid-loop throw
      // must NOT emit a frame past it.
      if (failed || !m) return;
      const changed: WorkstreamIssue[] = [];
      for (const { input, issue } of emittedPreMap) {
        const next = mapBoardIssue(input, m, ctx.botSlug);
        if (
          next.status !== issue.status ||
          Boolean(next.live) !== Boolean(issue.live)
        ) {
          changed.push(next);
        }
      }
      if (changed.length > 0) send({ type: "issues", issues: changed });
    });
    // If the page loop fails or aborts before `await boardPromise`, a late
    // reconcile rejection must not surface as an unhandled rejection.
    boardPromise.catch(() => {});

    await listRepoIssues(ctx.installationId, ctx.owner, ctx.repo, {
      onBatch: (items) => {
        if (isAborted?.()) throw new StreamAbortedError();
        const mapLanded = boardMap !== undefined;
        const issues = items.map((input) =>
          mapBoardIssue(input, mapLanded ? boardMap : null, ctx.botSlug),
        );
        if (issues.length === 0) return; // all-PR page — nothing to emit
        send({ type: "issues", issues });
        issueCount += issues.length;
        if (!mapLanded) {
          for (let k = 0; k < items.length; k++) {
            emittedPreMap.push({ input: items[k], issue: issues[k] });
          }
        }
      },
      onOpenTruncated: () => {
        openTruncated = true;
      },
    });

    // Flushes the reconcile when the map lands after the last page (every
    // emitted input was pre-map) — the reconcile frame precedes done by
    // construction.
    await boardPromise;
    send({ type: "done", openTruncated });
  } catch (err) {
    if (err instanceof StreamAbortedError) {
      failed = true; // suppress a reconcile frame arriving after the abort
      // Not a failure: the consumer went away. Bounded log, no error frame,
      // no rethrow — the route just closes the (already-dead) stream.
      log.info(
        { frames, issueCount, durationMs: Date.now() - startedAt },
        "workstream feed aborted",
      );
      return;
    }
    failed = true;
    send({ type: "error", code: "workstream_query_error" });
    throw err;
  }

  logSummary(openTruncated);
}
