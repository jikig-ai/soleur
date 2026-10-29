"use client";

// Durable approval request card (#4672, wireframes 01-05 and 07). ONE component for the in-thread card (WebSocket) and
// the away-user landing page: only `layout` differs.
//
// Trust boundary (single-user-incident class):
//   - Every value shown comes from `view`, which the SERVER built from the canonical action that is also hashed
//     (server/approval/render.ts). The card never receives agent prose and renders every value as a plain React text
//     node (never markdown, never HTML, never a link built from a value). Invisible direction/zero-width controls are
//     made visible rather than dropped, so a right-to-left override cannot make one address look like another.
//   - Values are never truncated: a long block scrolls inside the card with a visible "N more lines" marker.
//   - Fail closed: a decide that cannot be confirmed shows a static error and unlocks the buttons. There is no
//     optimistic approved state; the card changes state only when the server reports it (props).
//   - A non-owner never gets Approve or Deny (they are absent, not disabled); the server refuses a non-owner decide too.
//   - No state claims an outcome. Approval releases the request to the agent; what the agent does next is not reported.

import { useEffect, useId, useState } from "react";
import { Button } from "@/components/ui/button";
import { usePendingAction } from "@/hooks/use-pending-action";
import {
  APPROVAL_COPY,
  APPROVAL_STATE_COPY,
  formatExpiry,
} from "@/lib/approval-copy";
import {
  AGENT_WAIT_MINUTES,
  BLOCK_VISIBLE_LINES,
  deriveApprovalCardState,
  isDecidable,
  nounFromSingleUse,
  revealInvisibleChars,
  type ApprovalCardState,
} from "@/lib/approval-card-state";
import type {
  ApprovalCardView,
  ApprovalDecideOutcomeWire,
  ApprovalDecisionWire,
  ApprovalWireStatus,
} from "@/lib/types";

/** How long the card waits for the server's reply to a decide before it stops waiting and shows the static error. */
export const APPROVAL_DECIDE_REPLY_TIMEOUT_MS = 20_000;

export interface ApprovalRequestCardProps {
  approvalId: string;
  /** Null when the stored text was removed by the retention scrub: the card then shows the details-removed state. */
  view: ApprovalCardView | null;
  status: ApprovalWireStatus;
  expiresAt: string;
  requestCount: number;
  viewerRole: "owner" | "member";
  /** True while the agent is still inside its in-session wait (server truth, never guessed client-side). */
  agentWaiting: boolean;
  /** The server's reply to THIS viewer's own decide, when there was one (conflict, expired and closed explain a refusal). */
  decideOutcome?: ApprovalDecideOutcomeWire;
  /** Expired after the Owner approved it and the agent never asked again. The wire cannot say; the landing page can. */
  expiredAfterApproval?: boolean;
  /** Render-time banner on an older pending card when a newer one exists for the same conversation and tool. */
  newerRequestExists?: boolean;
  /** Right-hand meta of a resolved card, e.g. "Today 10:42 · by you". Built by the caller from data it holds. */
  decidedLabel?: string;
  /** Name and role of whoever decided first, for the loser state. Absent = the neutral wording (the wire does not carry it). */
  alreadyDecidedBy?: { name: string; role: string } | null;
  /**
   * Sends the decision. Return false (or throw) when it could not be sent at all. A true result means "accepted, the
   * outcome will arrive as a prop change" (status / decideOutcome): the buttons stay locked until then.
   */
  onDecide: (decision: ApprovalDecisionWire) => boolean | Promise<boolean>;
  layout?: "chat" | "landing";
  /** Test seam for the countdown. */
  now?: () => number;
}

interface StateStyle {
  box: string;
  badge: string;
  icon: "none" | "lock" | "check" | "warn" | "x" | "info";
}

const BOX_BASE = "rounded-xl border-2 p-4 md:p-5";

const STATE_STYLE: Record<ApprovalCardState, StateStyle> = {
  pending_owner: {
    box: `${BOX_BASE} border-soleur-border-emphasized bg-soleur-accent-gold-fill/[0.07]`,
    badge: "bg-soleur-accent-gold-fill text-soleur-text-on-accent",
    icon: "none",
  },
  pending_member: {
    box: `${BOX_BASE} border-soleur-border-default bg-soleur-bg-surface-1`,
    badge: "bg-soleur-bg-surface-2 text-soleur-accent-gold-text",
    icon: "lock",
  },
  released: {
    box: `${BOX_BASE} border-green-500/60 bg-green-950/20`,
    badge: "bg-green-500/15 text-green-400",
    icon: "check",
  },
  approved_late: {
    box: `${BOX_BASE} border-amber-500/60 bg-amber-950/20`,
    badge: "bg-amber-500/15 text-amber-400",
    icon: "warn",
  },
  denied: { box: `${BOX_BASE} border-soleur-border-default bg-soleur-bg-surface-1`, badge: "bg-soleur-bg-surface-2 text-soleur-text-secondary", icon: "x" },
  expired: { box: `${BOX_BASE} border-soleur-border-default bg-soleur-bg-surface-1`, badge: "bg-soleur-bg-surface-2 text-soleur-text-secondary", icon: "x" },
  expired_after_approval: {
    box: `${BOX_BASE} border-soleur-border-default bg-soleur-bg-surface-1`,
    badge: "bg-soleur-bg-surface-2 text-soleur-text-secondary",
    icon: "x",
  },
  already_decided: {
    box: `${BOX_BASE} border-soleur-border-default bg-soleur-bg-surface-1`,
    badge: "bg-soleur-bg-surface-2 text-soleur-text-secondary",
    icon: "info",
  },
  conversation_closed: {
    box: `${BOX_BASE} border-soleur-border-default bg-soleur-bg-surface-1`,
    badge: "bg-soleur-bg-surface-2 text-soleur-text-secondary",
    icon: "lock",
  },
  details_removed: {
    box: `${BOX_BASE} border-soleur-border-default bg-soleur-bg-surface-1`,
    badge: "bg-soleur-bg-surface-2 text-soleur-text-secondary",
    icon: "x",
  },
};

const BADGE_TEXT: Record<ApprovalCardState, string> = {
  pending_owner: APPROVAL_STATE_COPY.badge.pending,
  pending_member: APPROVAL_STATE_COPY.badge.waitingForOwner,
  released: APPROVAL_STATE_COPY.badge.released,
  approved_late: APPROVAL_STATE_COPY.badge.approvedLate,
  denied: APPROVAL_STATE_COPY.badge.denied,
  expired: APPROVAL_STATE_COPY.badge.expired,
  expired_after_approval: APPROVAL_STATE_COPY.badge.expiredAfterApproval,
  already_decided: APPROVAL_STATE_COPY.badge.alreadyDecided,
  conversation_closed: APPROVAL_STATE_COPY.badge.notRecorded,
  details_removed: APPROVAL_STATE_COPY.badge.detailsRemoved,
};

function Icon({ name, className = "h-4 w-4" }: { name: StateStyle["icon"] | "timer" | "repeat"; className?: string }) {
  const common = { className: `${className} shrink-0`, viewBox: "0 0 24 24", fill: "none", stroke: "currentColor", strokeWidth: 2, strokeLinecap: "round" as const, strokeLinejoin: "round" as const, "aria-hidden": true };
  switch (name) {
    case "lock":
      return (
        <svg {...common}>
          <rect x="5" y="11" width="14" height="10" rx="2" />
          <path d="M8 11V7a4 4 0 0 1 8 0v4" />
        </svg>
      );
    case "check":
      return (
        <svg {...common}>
          <polyline points="20 6 9 17 4 12" />
        </svg>
      );
    case "warn":
      return (
        <svg {...common}>
          <path d="M10.3 3.9 1.8 18a2 2 0 0 0 1.7 3h17a2 2 0 0 0 1.7-3L13.7 3.9a2 2 0 0 0-3.4 0z" />
          <line x1="12" y1="9" x2="12" y2="13" />
          <line x1="12" y1="17" x2="12.01" y2="17" />
        </svg>
      );
    case "x":
      return (
        <svg {...common}>
          <circle cx="12" cy="12" r="10" />
          <line x1="15" y1="9" x2="9" y2="15" />
          <line x1="9" y1="9" x2="15" y2="15" />
        </svg>
      );
    case "timer":
      return (
        <svg {...common}>
          <circle cx="12" cy="13" r="8" />
          <polyline points="12 9 12 13 14 15" />
          <line x1="10" y1="2" x2="14" y2="2" />
        </svg>
      );
    case "repeat":
      return (
        <svg {...common}>
          <polyline points="17 1 21 5 17 9" />
          <path d="M3 11V9a4 4 0 0 1 4-4h14" />
          <polyline points="7 23 3 19 7 15" />
          <path d="M21 13v2a4 4 0 0 1-4 4H3" />
        </svg>
      );
    case "info":
    case "none":
    default:
      return (
        <svg {...common}>
          <circle cx="12" cy="12" r="10" />
          <line x1="12" y1="16" x2="12" y2="12" />
          <line x1="12" y1="8" x2="12.01" y2="8" />
        </svg>
      );
  }
}

function BoundValue({ label, value, kind }: { label: string; value: string; kind: "text" | "code" | "block" }) {
  const shown = revealInvisibleChars(value);
  if (kind === "block") {
    const lines = shown.split("\n").length;
    const scrolls = lines > BLOCK_VISIBLE_LINES;
    return (
      <div className="min-w-0">
        <div
          // A long block scrolls inside the card (never ellipsised); keyboard users can focus it to scroll.
          role={scrolls ? "region" : undefined}
          aria-label={scrolls ? `${label}, ${lines} lines, scrollable` : undefined}
          tabIndex={scrolls ? 0 : undefined}
          className={`rounded-lg bg-soleur-bg-surface-2/70 px-3 py-2.5 text-sm leading-relaxed text-soleur-text-primary whitespace-pre-wrap [overflow-wrap:anywhere] ${
            scrolls ? "max-h-72 overflow-y-auto" : ""
          }`}
        >
          {shown}
        </div>
        {scrolls && (
          <p className="mt-1 text-xs text-soleur-text-muted">{lines - BLOCK_VISIBLE_LINES} more lines</p>
        )}
      </div>
    );
  }
  return (
    <p
      className={`min-w-0 text-sm whitespace-pre-wrap [overflow-wrap:anywhere] ${
        kind === "code" ? "font-mono text-soleur-text-primary" : "font-medium text-soleur-text-primary"
      }`}
    >
      {shown}
    </p>
  );
}

function BoundBlock({ view }: { view: ApprovalCardView }) {
  return (
    <dl
      data-testid="approval-bound-block"
      className="mt-3 grid grid-cols-1 gap-x-4 gap-y-2 rounded-lg border border-soleur-border-default bg-soleur-bg-base/60 p-3 sm:grid-cols-[8rem_1fr] md:p-4"
    >
      {view.fields.map((f, i) => (
        <div key={`${f.label}-${i}`} className="contents">
          <dt className="pt-0.5 text-[11px] font-medium uppercase tracking-[0.14em] text-soleur-text-muted">{f.label}</dt>
          <dd className="m-0 min-w-0">
            <BoundValue label={f.label} value={f.value} kind={f.kind} />
          </dd>
        </div>
      ))}
    </dl>
  );
}

export function ApprovalRequestCard(props: ApprovalRequestCardProps) {
  const {
    approvalId,
    view,
    status,
    expiresAt,
    requestCount,
    viewerRole,
    agentWaiting,
    decideOutcome,
    expiredAfterApproval,
    newerRequestExists,
    decidedLabel,
    alreadyDecidedBy,
    onDecide,
    layout = "chat",
    now = Date.now,
  } = props;

  const titleId = useId();
  const state = deriveApprovalCardState({
    status,
    viewerRole,
    agentWaiting,
    decideOutcome,
    detailsRemoved: view === null,
    expiredAfterApproval,
  });
  const style = STATE_STYLE[state];
  const noun = view ? nounFromSingleUse(view.singleUse) : "request";
  const decidable = isDecidable(state, viewerRole) && view !== null;
  const pendingState = state === "pending_owner" || state === "pending_member";

  // The countdown re-renders every 30 s. SSR and the first client render can disagree by a tick: the chip opts out of
  // the hydration warning (it is a clock, not content).
  const [, setTick] = useState(0);
  useEffect(() => {
    if (!pendingState) return;
    const t = setInterval(() => setTick((n) => n + 1), 30_000);
    return () => clearInterval(t);
  }, [pendingState]);
  const expiry = formatExpiry(expiresAt, now());

  // --- decide. Two phases, both fail closed:
  //   1. SEND (usePendingAction: double-submit guard, 30 s watchdog, focus restore): onDecide returns false or throws =>
  //      static error, buttons unlock, card unchanged.
  //   2. AWAIT THE SERVER'S WORD: the buttons stay locked while this card's status / decideOutcome still equal what they
  //      were when the decision was sent. The lock is DERIVED from props (no effect to clear), so a reply that lands at
  //      any moment unlocks it, and a reply that never arrives ends in the static error after the reply timeout. The wait
  //      is deliberately NOT inside the transition: React holds state updates made inside a transition's async action
  //      until the action finishes, so waiting there for a prop change would deadlock.
  const [choice, setChoice] = useState<ApprovalDecisionWire | null>(null);
  const [sentAt, setSentAt] = useState<{ status: ApprovalWireStatus; decideOutcome?: ApprovalDecideOutcomeWire } | null>(null);
  const [timedOut, setTimedOut] = useState(false);
  const awaitingReply = sentAt !== null && sentAt.status === status && sentAt.decideOutcome === decideOutcome;

  useEffect(() => {
    if (!awaitingReply) return;
    const t = setTimeout(() => {
      setSentAt(null);
      setTimedOut(true);
    }, APPROVAL_DECIDE_REPLY_TIMEOUT_MS);
    return () => clearTimeout(t);
  }, [awaitingReply]);

  const { run, pending, error } = usePendingAction(async (decision: ApprovalDecisionWire) => {
    const sent = await onDecide(decision);
    if (!sent) throw new Error("approval decide was not sent");
    setSentAt({ status, decideOutcome });
  });
  const locked = pending || awaitingReply;
  const decide = (decision: ApprovalDecisionWire) => {
    setChoice(decision);
    setTimedOut(false);
    run(decision);
  };

  // --- copy per state
  let title: string;
  let infoLine: string | null = null;
  let infoIcon: StateStyle["icon"] = "info";
  switch (state) {
    case "pending_owner":
      title = view?.title ?? "";
      infoLine = view?.consequence ?? null;
      break;
    case "pending_member":
      title = APPROVAL_COPY.nonOwnerWaiting;
      infoLine = APPROVAL_STATE_COPY.memberLine;
      break;
    case "released":
      title = APPROVAL_COPY.releasedTitle;
      infoLine = `${APPROVAL_COPY.releasedBadge}. ${APPROVAL_STATE_COPY.releasedLine}`;
      infoIcon = "check";
      break;
    case "approved_late":
      title = APPROVAL_COPY.approvedLate;
      infoLine = APPROVAL_STATE_COPY.approvedLateLine;
      infoIcon = "warn";
      break;
    case "denied":
      title = APPROVAL_STATE_COPY.deniedTitle(noun);
      infoLine = APPROVAL_COPY.resolvedNothing;
      infoIcon = "x";
      break;
    case "expired":
      title = APPROVAL_STATE_COPY.expiredTitle;
      infoLine = APPROVAL_STATE_COPY.expiredLine(noun);
      infoIcon = "x";
      break;
    case "expired_after_approval":
      title = APPROVAL_COPY.approvedNeverAsked;
      infoLine = APPROVAL_STATE_COPY.expiredAfterApprovalLine;
      infoIcon = "x";
      break;
    case "already_decided":
      title = alreadyDecidedBy ? APPROVAL_COPY.alreadyDecided(alreadyDecidedBy.name, alreadyDecidedBy.role) : APPROVAL_STATE_COPY.alreadyDecidedAnonymous;
      infoLine = APPROVAL_STATE_COPY.alreadyDecidedLine;
      break;
    case "conversation_closed":
      title = APPROVAL_COPY.conversationClosed;
      infoLine = APPROVAL_STATE_COPY.closedLine(noun);
      infoIcon = "x";
      break;
    case "details_removed":
      title = APPROVAL_COPY.detailsRemoved;
      infoLine = APPROVAL_STATE_COPY.detailsRemovedLine;
      infoIcon = "x";
      break;
  }

  const danger = view?.danger === true && state === "pending_owner";
  const boxClass = danger ? `${BOX_BASE} border-red-500/70 bg-red-950/20` : style.box;
  const badgeClass = danger ? "bg-red-500 text-soleur-text-on-accent" : style.badge;
  const showSubline = state === "pending_owner" && !agentWaiting;
  const landing = layout === "landing";

  return (
    <section
      role="group"
      aria-labelledby={titleId}
      aria-busy={locked}
      data-testid="approval-request-card"
      data-approval-id={approvalId}
      data-approval-state={state}
      className={boxClass}
    >
      {requestCount >= 2 && (
        <p data-testid="approval-request-count" className="mb-2 flex items-center gap-1.5 text-xs text-soleur-text-secondary">
          <Icon name="repeat" className="h-3.5 w-3.5" />
          {APPROVAL_COPY.requestCount(requestCount)}
        </p>
      )}

      <div className="flex flex-wrap items-center justify-between gap-2">
        <span
          data-testid="approval-badge"
          className={`inline-flex items-center gap-1.5 rounded-md px-2.5 py-1 text-[11px] font-semibold uppercase tracking-[0.16em] ${badgeClass}`}
        >
          {style.icon !== "none" && <Icon name={style.icon} className="h-3.5 w-3.5" />}
          {BADGE_TEXT[state]}
        </span>
        {pendingState && expiry.text ? (
          <span
            data-testid="approval-expiry"
            suppressHydrationWarning
            className={`inline-flex items-center gap-1.5 text-xs font-medium ${expiry.urgent ? "text-amber-400" : "text-soleur-accent-gold-text"}`}
          >
            <Icon name="timer" className="h-3.5 w-3.5" />
            {expiry.text}
          </span>
        ) : decidedLabel ? (
          <span data-testid="approval-decided-label" className="text-xs text-soleur-text-secondary">
            {decidedLabel}
          </span>
        ) : null}
      </div>

      {newerRequestExists && state === "pending_owner" && (
        <p
          role="note"
          data-testid="approval-newer-banner"
          className="mt-3 flex items-start gap-2 rounded-lg border border-amber-500/50 bg-amber-500/10 px-3 py-2 text-sm text-amber-300"
        >
          <Icon name="warn" className="mt-0.5 h-4 w-4" />
          <span>
            {APPROVAL_COPY.newerRequestBanner}. {APPROVAL_COPY.newerRequestBannerDetail}
          </span>
        </p>
      )}

      <div aria-live="polite">
        <h3 id={titleId} className="mt-3 text-lg font-medium text-soleur-text-primary">
          {title}
        </h3>
        {showSubline && (
          <p data-testid="approval-subline" className="mt-1 text-sm text-soleur-text-secondary">
            {APPROVAL_COPY.pendingSubline(AGENT_WAIT_MINUTES)}
          </p>
        )}
      </div>

      {view && <BoundBlock view={view} />}

      {infoLine && (
        <p data-testid="approval-info" className="mt-3 flex items-start gap-2 text-sm text-soleur-text-primary">
          <span
            className={
              infoIcon === "check" ? "text-green-400" : infoIcon === "warn" ? "text-amber-400" : danger ? "text-red-400" : "text-soleur-accent-gold-text"
            }
          >
            <Icon name={infoIcon} className="mt-0.5 h-4 w-4" />
          </span>
          <span className="min-w-0 [overflow-wrap:anywhere]">{infoLine}</span>
        </p>
      )}

      {state === "pending_member" && (
        <p data-testid="approval-member-role" className="mt-3 flex items-center gap-2 rounded-lg bg-soleur-bg-surface-2/60 px-3 py-2 text-sm text-soleur-text-secondary">
          <Icon name="lock" className="h-4 w-4" />
          {APPROVAL_STATE_COPY.memberRoleLine}
        </p>
      )}

      {decidable && view && (
        <div
          className={`mt-4 flex gap-3 ${landing ? "flex-col" : "flex-wrap items-center"}`}
          data-testid="approval-actions"
        >
          <div className={`flex gap-3 ${landing ? "flex-col" : "flex-row"} ${landing ? "w-full" : ""}`}>
            {/* Landing stacks Approve above Deny at full width (wireframe 07b); the thread card puts Deny first (04A). */}
            <Button
              variant="outlined"
              type="button"
              disabled={locked}
              loading={locked && choice === "deny"}
              loadingLabel={APPROVAL_STATE_COPY.denying}
              onClick={() => decide("deny")}
              className={`${landing ? "order-2 min-h-12 w-full" : "min-h-10 px-5 py-2"}`}
            >
              {view.denyLabel}
            </Button>
            <Button
              variant="gold"
              type="button"
              disabled={locked}
              loading={locked && choice === "approve"}
              loadingLabel={APPROVAL_STATE_COPY.approving}
              onClick={() => decide("approve")}
              className={`${landing ? "order-1 min-h-12 w-full" : "min-h-10 px-5 py-2"}`}
            >
              {view.approveLabel}
            </Button>
          </div>
          <p className={`text-xs text-soleur-text-muted ${landing ? "text-center" : "ml-auto"}`}>
            {locked ? APPROVAL_STATE_COPY.recordingDecision : view.singleUse}
          </p>
        </div>
      )}

      {(error || timedOut) && (
        <p role="alert" data-testid="approval-decide-error" className="mt-3 text-sm text-red-400">
          {APPROVAL_STATE_COPY.decideFailed}
        </p>
      )}
    </section>
  );
}
