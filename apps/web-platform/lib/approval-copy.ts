/**
 * Copy deck for durable approval requests (#4672). The single home of every fixed string the approval surfaces, the
 * server-built card view and the notifications use. It is a pure leaf (no imports) so client components, the server
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

/** Card, state and landing-page strings (in-app, behind sign-in). */
export const APPROVAL_COPY = {
  approve: "Approve",
  deny: "Deny",
  releasedBadge: "Released to your agent",
  releasedTitle: "Released, your agent is continuing",
  approvedLate: "Approved. Ask your agent again.",
  expiredUnanswered: "This request expired. Nothing was run.",
  approvedNeverAsked: "You approved this, but your agent never asked again",
  resolvedNothing: "Nothing was run. Saved for your agent. Asking again with the same arguments is allowed.",
  newerRequestBanner: "A newer request from your agent exists",
  newerRequestBannerDetail: "Check which one you mean to approve.",
  nonOwnerWaiting: "Waiting for the workspace Owner",
  conversationClosed: "This conversation is closed",
  detailsRemoved: "Details removed per retention policy",
  pendingSubline: (minutes: number) => `Your agent stopped waiting after ${minutes} minutes`,
  requestCount: (n: number) => `The agent asked again, request ${n}`,
  alreadyDecided: (name: string, role: string) => `Already decided by ${name} (${role})`,
} as const;

/** In-card state copy beyond the shared strings above (copy deck section C, wireframe 04). */
export const APPROVAL_STATE_COPY = {
  badge: {
    pending: "Approval needed",
    waitingForOwner: "Waiting for owner",
    released: "Released to your agent",
    approvedLate: "Approved · ask again",
    denied: "Denied",
    expired: "Expired",
    expiredAfterApproval: "Expired after approval",
    alreadyDecided: "Already decided",
    notRecorded: "Not recorded",
    detailsRemoved: "Details removed",
  },
  deniedTitle: (noun: string) => `You denied this ${noun}`,
  expiredTitle: "Nobody decided in time",
  expiredLine: (noun: string) => `This request expired. Nothing was run. Ask your agent again if you still want this ${noun}.`,
  expiredAfterApprovalLine:
    "Nothing was run. This appears in your inbox and thread only: no push, no email. Ask your agent again if you still want this.",
  approvedLateLine:
    "Saved for your agent. Asking again with the same arguments is allowed. Your agent stopped waiting after 5 minutes, so ask it again in this conversation.",
  releasedLine: "What your agent does next is up to your agent; this card does not report an outcome.",
  memberLine: "Only the workspace Owner can approve or deny this. Waiting for the workspace Owner. If nobody decides in time, this expires and nothing is run.",
  memberRoleLine: "Workspace Owner · only they can decide",
  // Neutral on purpose: the wire does not say WHO decided first (a second Owner, or this viewer's own earlier tap).
  alreadyDecidedAnonymous: "Already decided",
  alreadyDecidedLine:
    "This request was already decided before your tap. Your decision was not recorded, and nothing changes for your agent.",
  closedLine: (noun: string) =>
    `Your approval was not recorded because this conversation is closed. Ask your agent again in a new conversation if you still want this ${noun}.`,
  detailsRemovedLine: "The action details were removed 30 days after this request ended. Only who decided and when is kept.",
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
  notFoundTitle: "Page not found",
  notFoundBody: "We could not find what you were looking for.",
  notFoundCta: "Go to Soleur",
  /** Shown instead of the buttons when the stored text cannot be verified against the bound hash. */
  unverifiable: "This request cannot be shown right now. Nothing was approved. Ask your agent again.",
  from: (leader: string, conversation: string) => `From your ${leader} · ${conversation}`,
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
    pushBody: "A request expired before it was decided. Nothing was run.",
    emailSubject: "Soleur: a request expired and nothing was run",
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
      "Nothing was run. If you still want it done, ask your agent again in Soleur.",
    ];
  }
  const when = formatExpiryDateTimeTz(v.expiresAt);
  return [
    hi,
    `A request from one of your agents in ${ws} needs your decision. Open Soleur to see exactly what it would do, then approve or deny. If you do nothing, it expires${when ? ` on ${when}` : ""} and nothing is run.`,
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
