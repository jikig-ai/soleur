// Pure policy for the `action-required` escalation staleness contract (#6836).
//
// The fail-safe close authority lives here, isolated from all Inngest/Octokit I/O so the
// correctness-critical decisions are exhaustively unit-testable (see
// action-required-sla-policy.test.ts). Two deepen-plan findings are FATAL if missed and are
// encoded here:
//   D1 — classify on the AGENT-owned `content-publisher` label, NEVER the human-attachable
//        `content` (an ops emergency tagged `content` must stay OPS → never closed).
//   D3 — expiry staleness is measured from the last NON-BOT activity, never the raw `updatedAt`
//        scalar (bot noise — this cron's own escalation comments + sibling crons — otherwise
//        resets `updatedAt` forever and expiry becomes dead code for the neglected backlog).
//
// ALLOWLIST, not denylist: OPS (the default) and anything unclassified are escalate-only and
// NEVER closed. Only the two structurally-dead classes are expirable.

export type SlaClass = "ops" | "dead-content" | "decision-challenge";
export type SlaAction = "escalate" | "expire" | "skip";

/** The AGENT-owned label the content pipeline itself applies to per-piece chores (D1). */
export const CONTENT_PUBLISHER_LABEL = "content-publisher";
/** A genuine standing "distribution pipeline empty" signal — kept visible, never expired. */
export const CONTENT_STARVATION_LABEL = "content-starvation";
export const DECISION_CHALLENGE_LABEL = "decision-challenge";
/** Applied by the cron when it auto-closes a structurally-dead issue. */
export const WONTFIX_STALE_LABEL = "wontfix-stale";

/**
 * Labels the digest §4 action list de-pollutes (kept in sync with operator-digest/SKILL.md §4).
 * Keyed on the AGENT-owned `content-publisher`, NOT the broad human-attachable `content` — mirroring
 * `classifyIssue`'s D1 rule. Excluding bare `content` would drop a genuine ops emergency that a human
 * tagged `content` from the operator's ONLY comprehension surface while the cron escalates it to p0.
 */
export const ACTION_LIST_EXCLUDED_LABELS = [
  DECISION_CHALLENGE_LABEL,
  CONTENT_PUBLISHER_LABEL,
] as const;

export const PRIORITY_RANK: Record<string, number> = {
  "priority/p0-critical": 4,
  "priority/p1-high": 3,
  "priority/p2-medium": 2,
  "priority/p3-low": 1,
};

/** OPS escalation ladder — highest tier first. Escalate-only; never expires. */
export const OPS_ESCALATION_TIERS: ReadonlyArray<{ minAgeDays: number; priority: string }> = [
  { minAgeDays: 60, priority: "priority/p0-critical" },
  { minAgeDays: 30, priority: "priority/p1-high" },
  { minAgeDays: 14, priority: "priority/p2-medium" },
];

/** Days of NON-BOT inactivity after which a structurally-dead class is auto-closed. */
export const EXPIRE_INACTIVE_DAYS = 30;

/**
 * Classify by AGENT-owned allowlist (D1, fail-safe). Order matters:
 *   1. content-starvation → OPS (genuine standing signal; never expired)
 *   2. content-publisher  → dead-content (the agent-only per-piece chore label)
 *   3. decision-challenge → decision-challenge
 *   4. everything else, INCLUDING an ops issue carrying broad `content` → OPS (never closed)
 */
export function classifyIssue(labels: string[]): SlaClass {
  const set = new Set(labels);
  if (set.has(CONTENT_STARVATION_LABEL)) return "ops";
  if (set.has(CONTENT_PUBLISHER_LABEL)) return "dead-content";
  if (set.has(DECISION_CHALLENGE_LABEL)) return "decision-challenge";
  return "ops";
}

/** GitHub actor is a bot if its type is Bot or its login carries the `[bot]` suffix. */
export function isBot(login: string | undefined, type: string | undefined): boolean {
  if (!login) return true; // an unattributable actor is treated as bot (conservative for the veto)
  if (type === "Bot") return true;
  return /\[bot\]$/i.test(login);
}

export interface ActivityEvent {
  actor: string | undefined;
  actorType: string | undefined;
  at: string; // ISO timestamp
}

/**
 * Epoch-ms of the most recent NON-BOT activity, or null when there is none (D3). The caller
 * falls back to the issue's createdAt when this returns null (a brand-new issue with only the
 * cron's own bot writes has "no human activity since creation").
 */
export function lastNonBotActivityMs(events: ActivityEvent[]): number | null {
  let latest: number | null = null;
  for (const e of events) {
    if (isBot(e.actor, e.actorType)) continue;
    const ms = Date.parse(e.at);
    if (Number.isFinite(ms) && (latest === null || ms > latest)) latest = ms;
  }
  return latest;
}

export interface Assignee {
  login: string;
  type: string | undefined;
}

/** Human-engagement veto (D1): a non-bot assignee OR any non-bot timeline activity. */
export function isHumanEngaged(args: { assignees: Assignee[]; events: ActivityEvent[] }): boolean {
  if (args.assignees.some((a) => !isBot(a.login, a.type))) return true;
  if (args.events.some((e) => !isBot(e.actor, e.actorType))) return true;
  return false;
}

export function priorityRank(labels: string[]): number {
  let rank = 0;
  for (const l of labels) rank = Math.max(rank, PRIORITY_RANK[l] ?? 0);
  return rank;
}

export interface IssueDecisionInput {
  cls: SlaClass;
  ageDays: number; // from createdAt (OPS ladder)
  inactiveDays: number; // from last non-bot activity (expiry clock, D3)
  humanEngaged: boolean;
  currentPriority: string | null;
  labels: string[];
  closed: boolean;
}

export interface SlaDecision {
  action: SlaAction;
  targetPriority?: string;
  reason: string;
}

export function decideAction(input: IssueDecisionInput): SlaDecision {
  if (input.cls === "ops") {
    // Escalate-only, NEVER close (allowlist fail-safe). Bump upward only (idempotent).
    const currentRank = input.currentPriority ? (PRIORITY_RANK[input.currentPriority] ?? 0) : 0;
    for (const tier of OPS_ESCALATION_TIERS) {
      if (input.ageDays >= tier.minAgeDays) {
        const tierRank = PRIORITY_RANK[tier.priority];
        if (tierRank > currentRank) {
          return { action: "escalate", targetPriority: tier.priority, reason: `age ${input.ageDays}d ≥ ${tier.minAgeDays}d` };
        }
        return { action: "skip", reason: "already at or above the age-appropriate priority" };
      }
    }
    return { action: "skip", reason: "below the first escalation tier" };
  }

  // dead-content / decision-challenge — expirable classes.
  if (input.closed || input.labels.includes(WONTFIX_STALE_LABEL)) {
    return { action: "skip", reason: "already closed or already marked stale" };
  }
  if (input.humanEngaged) {
    return { action: "skip", reason: "human-engagement veto — operator touched this issue" };
  }
  if (input.inactiveDays >= EXPIRE_INACTIVE_DAYS) {
    return { action: "expire", reason: `no non-bot activity for ${input.inactiveDays}d ≥ ${EXPIRE_INACTIVE_DAYS}d` };
  }
  return { action: "skip", reason: `non-bot-active within ${EXPIRE_INACTIVE_DAYS}d` };
}

/**
 * D2 cross-run dedup: an HTML-comment sentinel embedded IN the comment body (not a trailing
 * label). The dedup guard GETs existing comments and skips if the sentinel is present, so the
 * marker and the comment are the SAME write — atomic on GitHub, unlike a label set afterward.
 */
export function buildSentinelMarker(action: SlaAction, threshold: string): string {
  return `<!-- sla:${action}:${threshold} -->`;
}

export function hasSentinel(bodyOrBodies: string, action: SlaAction, threshold: string): boolean {
  return bodyOrBodies.includes(buildSentinelMarker(action, threshold));
}
