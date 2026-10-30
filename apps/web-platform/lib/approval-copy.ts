/**
 * Copy deck for durable approval requests (#4672). The home of the fixed strings the approval surfaces and the
 * notifications use. The per-tool consequence lines (what an approval covers) live with the card view model in
 * server/approval/render.ts (PHRASES). It is a pure leaf (no imports) so client components, the server
 * render module and `server/notifications.ts` can all read it without crossing the client/server import boundary.
 *
 * Source of truth: knowledge-base/product/design/approvals (copy deck screenshot 09, after the Phase 0.2 wireframe delta).
 *
 * Rules the string test (test/approval/copy-deck.test.ts) enforces over every constant here:
 *   - no OUTCOME word (sent, ran, executed, delivered): slice 1 records only that a request was released to the
 *     agent, never what the agent did next;
 *   - "Released to your agent" is present;
 *   - the notification copy (push and email) never names an action type, a recipient, a repository, a branch, a
 *     document, a subject line or any value from the bound payload. Only {first_name}, {workspace_name} and the
 *     expiry date-time may be interpolated, and only in the email.
 */

/** Minutes the agent waits in-session for a decision. Lockstep with `DEFAULT_WAIT_MS` in server/approval/waiters.ts (pinned by a test). */
export const AGENT_WAIT_MINUTES = 5;

/**
 * Days a finished request keeps its action text before the retention scrub removes it. Lockstep with the
 * `sweep_approvals()` interval in migration 180 (pinned by a test that reads the SQL).
 */
export const APPROVAL_RETENTION_DAYS = 30;

/** Card, state and landing-page strings (in-app, behind sign-in). */
export const APPROVAL_COPY = {
  releasedBadge: "Released to your agent",
  releasedTitle: "Released, your agent is continuing",
  /** Landing page (no live socket): what the server can honestly say about a consumed request. */
  releasedTitleNeutral: "Released. If your agent is still waiting it will continue.",
  approvedLate: "Approved. Ask your agent again.",
  /**
   * Landing page (no live socket, so the page cannot know whether the agent is still inside its wait): state-neutral, no
   * numeric claim. A push-notified Owner often opens the page within seconds, while the agent is still waiting.
   */
  approvedLateNeutral: "Approved. If your agent is still waiting it will continue; if not, ask it again in this conversation.",
  /** Approved, but the approval can no longer be applied (its decider is no longer an Owner, or the requester left): never "ask again". */
  approvedUnusable: "Approved, but this approval can no longer be used",
  /** A revoke that lost the race to the agent's repeat: the approval was already consumed. */
  revokeTooLate: "Your revoke came too late: your agent had already used this approval",
  revoke: "Revoke approval",
  revokedTitle: "Approval revoked",
  approvedNeverAsked: "You approved this, but your agent never asked again",
  resolvedNothing: "This request ran nothing. Saved for your agent. Asking again with the same arguments is allowed.",
  newerRequestBanner: "A newer request from your agent exists",
  newerRequestBannerDetail: "Check which one you mean to approve.",
  nonOwnerWaiting: "Waiting for the workspace Owner",
  conversationClosed: "This conversation is closed",
  detailsRemoved: "Details removed per retention policy",
  pendingSubline: (minutes: number) => `Your agent stopped waiting after ${minutes} minutes`,
  requestCount: (n: number) => `The agent asked again, request ${n}`,
  alreadyDecided: (name: string, role: string) => `Already decided by ${name} (${role})`,
  alreadyDecidedByAnotherOwner: "Already decided by another Owner",
} as const;

/** In-card state copy beyond the shared strings above (copy deck section C, wireframe 04). */
export const APPROVAL_STATE_COPY = {
  badge: {
    pending: "Approval needed",
    waitingForOwner: "Waiting for owner",
    released: "Released to your agent",
    approvedLate: "Approved · ask again",
    approvedUnusable: "Approved · unusable",
    denied: "Denied",
    revoked: "Revoked",
    expired: "Expired",
    expiredAfterApproval: "Expired after approval",
    alreadyDecided: "Already decided",
    notRecorded: "Not recorded",
    detailsRemoved: "Details removed",
  },
  deniedTitle: (noun: string) => `You denied this ${noun}`,
  expiredTitle: "Nobody decided in time",
  expiredLine: (noun: string) => `This request expired and ran nothing. Ask your agent again if you still want this ${noun}.`,
  expiredAfterApprovalLine:
    "This request ran nothing. This appears in your inbox and thread only: no push, no email. Ask your agent again if you still want this.",
  approvedLateLine: (minutes: number) =>
    `Saved for your agent. Asking again with the same arguments is allowed. Your agent stopped waiting after ${minutes} minutes, so ask it again in this conversation.`,
  /** Approved row that can never be consumed: ask the Owner to revoke it or let it expire, then start a new request. */
  approvedUnusableLine:
    "Workspace membership or roles changed after it was approved, so your agent cannot use it. Ask a workspace Owner to revoke it, or wait for it to expire, then start a new request.",
  /** Landing-page variant of `approvedLateLine`: no wait duration, because the page cannot see the agent's wait. */
  approvedLateNeutralLine: "Saved for your agent. Asking again with the same arguments is allowed.",
  /** Landing-page pending sub-line: the page cannot tell whether the agent is still inside its wait. */
  pendingSublineNeutral: "If your agent has stopped waiting, ask it again in this conversation once you have decided.",
  /** Offered on an approved request the agent has not used yet; the deny decision on an approved request is a revoke. */
  revokeHint: "Changed your mind? Revoking stops your agent from using this approval.",
  revoking: "Revoking",
  revokedLine: "Revoked. Your agent cannot use this approval.",
  releasedLine: "What your agent does next is up to your agent; this card does not report an outcome.",
  memberLine: "Only the workspace Owner can approve or deny this. Waiting for the workspace Owner. If nobody decides in time, this expires and the request runs nothing.",
  memberRoleLine: "Workspace Owner · only they can decide",
  // Neutral on purpose: the wire does not say WHO decided first (a second Owner, or this viewer's own earlier tap).
  alreadyDecidedAnonymous: "Already decided",
  alreadyDecidedLine:
    "This request was already decided before your tap. Your decision was not recorded, and nothing changes for your agent.",
  /** A second Owner repeated the decision that was already recorded. */
  alreadyDecidedSameLine: "Another Owner recorded the same decision before your tap. Nothing changes for your agent.",
  closedLine: (noun: string) =>
    `Your approval was not recorded because this conversation is closed. Ask your agent again in a new conversation if you still want this ${noun}.`,
  /** Scheduled retention removal (the row is at least `days` past its end). */
  detailsRemovedLine: (days: number) =>
    `The action details were removed ${days} days after this request ended. We keep the kind of action, its status and its times, and, unless that person's account has been erased, who asked and who decided.`,
  /** Removal whose reason the UI cannot tell from the row (e.g. early, on the requester's account erasure): no day count. */
  detailsRemovedNeutralLine:
    "The action details have been removed. We keep the kind of action, its status and its times, and, unless that person's account has been erased, who asked and who decided.",
  approving: "Approving",
  denying: "Denying",
  recordingDecision: "Recording your decision…",
  /** Static: a decide failure never shows an optimistic state (the reply may have been lost, so it does not claim nothing was recorded). */
  decideFailed: "We couldn't confirm your decision. Reload to see this request's current state, then try again if it still needs you.",
  /** The expiry line for a stored request; the countdown itself is formatted by `formatExpiry`. */
  expired: "Expired",
} as const;

/** Away-user landing page strings (wireframe 07). */
export const APPROVAL_LANDING_COPY = {
  pageTitle: "Approval request",
  /** Fixed header line: the conversation title is agent-influenceable text and is never shown here. */
  fromAgent: "From your agent",
  /** Shown instead of the buttons when the stored text cannot be verified against the bound hash. */
  unverifiable: "This request cannot be shown right now. Nothing was approved. Ask your agent again.",
} as const;

/**
 * PROVISIONAL (needs CPO and CLO sign-off before `approval-queue` is ON for anyone but a Jikigai canary).
 *
 * The workspace-autonomy card changes what every future approval looks like, so its wording is a product and a legal
 * statement, not a UI string. Wireframe 03 note 3: "Copy for this row needs CPO/CLO sign-off before build." Until the
 * sign-off is recorded this constant is the only place the wording lives, `PROVISIONAL` is true, and a test fails the
 * moment the sign-off flag is flipped without the reviewer fields being filled in. Do not edit the wording without them.
 */
export const AUTONOMOUS_CARD_COPY_PROVISIONAL = {
  PROVISIONAL: true,
  signOff: { cpo: null as string | null, clo: null as string | null },
  settingOn: "Agent approval: Ask first → Autonomous",
  settingOff: "Agent approval: Autonomous → Ask first",
  appliesTo: "All agents, all members, all connected accounts",
  consequenceExtraOn: "Once switched on, agents here stop asking you before they act on supported actions.",
  consequenceExtraOff: "Once switched, agents here ask you before they act on supported actions.",
} as const;

/** Push and email copy (copy deck sections A and B). Fixed strings; the email may interpolate only the three named values. */
export const APPROVAL_NOTIFY_COPY = {
  requested: {
    pushTitle: "Approval needed",
    pushBody: "A request needs your decision. Open to review.",
    emailSubject: "Soleur: a request needs your decision",
    emailHeading: "A request needs your decision",
    emailCta: "Open request",
  },
  expired: {
    pushTitle: "Approval request expired",
    pushBody: "A request expired before it was decided. It ran nothing.",
    emailSubject: "Soleur: a request expired without being run",
    emailHeading: "A request expired",
    emailCta: "Open Soleur",
  },
} as const;

export type ApprovalNotifyKind = keyof typeof APPROVAL_NOTIFY_COPY;

export interface ApprovalEmailValues {
  firstName?: string | null;
  workspaceName?: string | null;
  /** ISO timestamp; formatted as an unambiguous UTC date-time. */
  expiresAt?: string | null;
}

/** "Wed 29 Oct, 10:42 UTC": the one interpolated date-time ({expiry_date_time_tz}). Empty for an unparseable value. */
export function formatExpiryDateTimeTz(iso: string | null | undefined): string {
  if (!iso) return "";
  const t = Date.parse(iso);
  if (Number.isNaN(t)) return "";
  const d = new Date(t);
  const day = new Intl.DateTimeFormat("en-GB", { weekday: "short", day: "numeric", month: "short", timeZone: "UTC" }).format(d);
  const time = new Intl.DateTimeFormat("en-GB", { hour: "2-digit", minute: "2-digit", hour12: false, timeZone: "UTC" }).format(d);
  return `${day}, ${time} UTC`;
}

/**
 * The email body as plain-text lines (the HTML sink escapes each line). The ONLY interpolations are `firstName`,
 * `workspaceName` and the expiry date-time; callers sanitize them before passing them in.
 */
export function approvalEmailLines(kind: ApprovalNotifyKind, v: ApprovalEmailValues): string[] {
  const hi = v.firstName ? `Hi ${v.firstName},` : "Hi,";
  const ws = v.workspaceName ? v.workspaceName : "your workspace";
  if (kind === "expired") {
    return [
      hi,
      `A request from one of your agents in ${ws} expired before it was decided.`,
      "This request ran nothing. If you still want it done, ask your agent again in Soleur.",
    ];
  }
  const when = formatExpiryDateTimeTz(v.expiresAt);
  return [
    hi,
    `A request from one of your agents in ${ws} needs your decision. Open Soleur to see exactly what it would do, then approve or deny. If you do nothing, it expires${when ? ` on ${when}` : ""} and the request runs nothing.`,
  ];
}

export function approvalEmailFootnote(workspaceName?: string | null): string {
  const ws = workspaceName ? workspaceName : "your workspace";
  return `You are receiving this because you are the Owner of ${ws}. Request details are left out of this email on purpose.`;
}

/**
 * Countdown chip text ("Expires in 23h 41m"). `now` is injected so the chip is testable. Past the expiry the chip reads
 * "Expired": the server decides (a late decide is refused and flips the row), the chip never hides the buttons.
 */
export function formatExpiry(expiresAtIso: string, nowMs: number): { text: string; urgent: boolean; past: boolean } {
  const t = Date.parse(expiresAtIso);
  if (Number.isNaN(t)) return { text: "", urgent: false, past: false };
  const ms = t - nowMs;
  if (ms <= 0) return { text: APPROVAL_STATE_COPY.expired, urgent: true, past: true };
  const totalMin = Math.floor(ms / 60_000);
  const h = Math.floor(totalMin / 60);
  const m = totalMin % 60;
  // Under one hour the chip turns amber (urgent) and drops the hours.
  if (h === 0) return { text: `Expires in ${Math.max(m, 1)}m`, urgent: true, past: false };
  return { text: `Expires in ${h}h ${m}m`, urgent: false, past: false };
}
