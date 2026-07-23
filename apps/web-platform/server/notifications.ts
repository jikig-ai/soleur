/**
 * Offline notification dispatch for review gate events.
 *
 * Notification hierarchy: WS (existing) > Push (new) > Email (new, fallback).
 * All functions are fire-and-forget — callers should not await them.
 */

import webpush from "web-push";
import { Resend } from "resend";
import * as Sentry from "@sentry/nextjs";
import { createServiceClient } from "@/lib/supabase/service";
import { createChildLogger } from "@/server/logger";
import {
  APP_URL_FALLBACK,
  reportSilentFallback,
  warnSilentFallback,
} from "@/server/observability";
import { sanitizeDisplayString } from "@/lib/sanitize-display";
import { NOT_LEGAL_ADVICE_NOTICE } from "@/lib/email-triage/statutory-rules";
import type { InboxItemSeverity } from "@/lib/inbox-severity";

const log = createChildLogger("notifications");

// Solar Forge email CTA palette — literal brand hex. Email clients do not
// resolve the soleur-* CSS custom properties (brand-guide.md:195 component
// "never raw hex" rule explicitly excepts email), so the gold tokens are
// inlined here as the single source for all transactional-email CTAs.
// Forge ink on gold is the only AA-passing pair (8.00:1→6.18:1); never white
// on gold (brand-guide.md:213). Solid background-color is the load-bearing
// base — clients that strip the gradient fall back to it.
const BRAND_EMAIL_COLORS = {
  ctaBackground: "#C9A962", // solid gold base (brand-guide.md:186,226)
  ctaGradient: "linear-gradient(135deg, #D4B36A, #B8923E)", // capable-client layer (187/188)
  ctaText: "#1A1612", // forge ink (210/213/245)
  textHeading: "#1a1a1a", // email-safe neutral heading (email clients need literal colors)
  textBody: "#4a4a4a", // email-safe neutral body
  textFootnote: "#9a9a9a", // email-safe neutral footnote
} as const;

/** Inline style for a branded gold email CTA `<a>` (sharp 0px corners). */
const EMAIL_CTA_STYLE = `display: inline-block; padding: 12px 24px; background-color: ${BRAND_EMAIL_COLORS.ctaBackground}; background-image: ${BRAND_EMAIL_COLORS.ctaGradient}; color: ${BRAND_EMAIL_COLORS.ctaText}; text-decoration: none; border-radius: 0; font-weight: 600;`;

/**
 * Single branded HTML scaffold for every transactional email this module
 * sends (heading + body + gold CTA + optional footnote). Extracted from the
 * previously-duplicated inline templates — byte-identical rendered output.
 *
 * SECURITY: `heading` and `bodyHtml` are injected RAW — callers must
 * escapeHtml any dynamic content before passing it in (they may embed
 * intentional markup like the invite's `<strong>`). `deepLink` must be built
 * exclusively from server-generated values, never email-derived content.
 */
function renderBrandedNotificationEmail(opts: {
  heading: string;
  bodyHtml: string;
  ctaLabel: string;
  deepLink: string;
  /** Raw HTML; omit to render no footnote (e.g. invite-accepted). */
  footnoteHtml?: string;
}): string {
  const footnote = opts.footnoteHtml
    ? `\n        <p style="margin: 24px 0 0; font-size: 12px; color: ${BRAND_EMAIL_COLORS.textFootnote};">${opts.footnoteHtml}</p>`
    : "";
  return `
      <div style="font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; max-width: 480px; margin: 0 auto; padding: 24px;">
        <h2 style="margin: 0 0 16px; font-size: 18px; color: ${BRAND_EMAIL_COLORS.textHeading};">${opts.heading}</h2>
        <p style="margin: 0 0 16px; color: ${BRAND_EMAIL_COLORS.textBody}; line-height: 1.5;">${opts.bodyHtml}</p>
        <div style="text-align: center; margin: 8px 0 0;">
          <a href="${opts.deepLink}" style="${EMAIL_CTA_STYLE}">${opts.ctaLabel}</a>
        </div>${footnote}
      </div>
    `;
}

// Discriminated union (feat-operator-inbox-delegation Phase 4). Consumers
// swept per cq-union-widening-grep-three-patterns + tsc --noEmit; existing
// review_gate behavior is byte-identical.
export interface ReviewGateNotificationPayload {
  type: "review_gate";
  conversationId: string;
  agentName: string;
  question: string;
}

export interface EmailTriageNotificationPayload {
  type: "email_triage";
  /** email_triage_items DB uuid ONLY — lands inside href unescaped; never
   * resend_email_id or any email-derived value. */
  emailId: string;
  /** Attacker-controlled (email subject). Sanitized + escaped at each sink. */
  title: string;
  isStatutory: boolean;
  /**
   * #6798: the statutory rule's own clock-origin prose (`StatutoryRule.catalogExcerpt`),
   * threaded from the cron so the email can render the rule-accurate caveat next
   * to the computed date. Server-authored, code-static — never third-party
   * content. Absent for non-statutory items and legacy callers.
   */
  statutoryExcerpt?: string;
}

// InboxItemSeverity is imported at the top from lib/inbox-severity (canonical).

/**
 * Operational-inbox notification (feat-severity-ranked-inbox #6007). Emitted by
 * `notifyInboxItem`, which FIRST inserts the durable inbox_item row and then
 * dispatches this push/email variant. Every field is server-generated:
 *   - `title` is built by the emit call-site from server-side identity (e.g. a
 *     domain-leader title), NEVER raw agent output / email content — a
 *     co-Owner-visible row must carry nothing the founder wouldn't want a
 *     co-Owner to see. Still sanitized at each sink (defense-in-depth).
 *   - `deepLinkPath` is a same-origin RELATIVE path built from `source_ref` ids
 *     at emit (e.g. "/dashboard/chat/{id}") — never a stored URL, never user
 *     content. Prefixed with appUrl() at the push/email sink; sw.js re-validates
 *     same-origin on click.
 */
export interface InboxItemNotificationPayload {
  type: "inbox_item";
  /** inbox_item row uuid — drives the sw.js per-item tag; safe in the deep link. */
  inboxItemId: string;
  title: string;
  /** action_required mirrors a missed dispatch to Sentry op=notify-inbox-action-required. */
  severity: InboxItemSeverity;
  deepLinkPath: string;
}

/**
 * The failure reasons that warrant an operator cost-breaker notification —
 * the SINGLE SOURCE OF TRUTH the handler's fire-guard, the payload union, and
 * the copy switch all derive from (no forced `as` cast, no triplicated list).
 *
 * `run_paused` is deliberately EXCLUDED: the cap-breach `byok_cap_exceeded`
 * notification already tells the founder they entered pause, and the Today
 * card renders the paused halt + Resume on every subsequent blocked spawn —
 * re-paging each blocked spawn would be a notification storm from the guard
 * itself (feat-l5-runaway-guard #5767 set-only-flag learning). NEVER
 * cancelled_by_operator (operator-initiated stops are not surprises).
 */
export const COST_BREAKER_NOTIFY_REASONS = [
  "cost_ceiling_exceeded",
  "byok_cap_exceeded",
  "leader_max_turns_exceeded",
  "cap_check_unavailable",
] as const;

export type CostBreakerReason = (typeof COST_BREAKER_NOTIFY_REASONS)[number];

/** Runtime narrowing from the broad FailureReason string to the notify subset. */
export function isCostBreakerReason(reason: string): reason is CostBreakerReason {
  return (COST_BREAKER_NOTIFY_REASONS as readonly string[]).includes(reason);
}

/**
 * Cost-breaker halt notification (feat-l5-runaway-guard PR-A). Sent when a run
 * is stopped by a spending/turn guard. TR5: payload is minimized to cost
 * aggregates + the terminal reason — no prompt/response content, no PII beyond
 * the founder's own account id (the recipient). All fields are server-generated
 * (enum + numbers), so nothing here is attacker-controlled.
 */
export interface CostBreakerNotificationPayload {
  type: "cost_breaker_tripped";
  /** The terminal failure reason that tripped the halt (notify subset). */
  reason: CostBreakerReason;
  /**
   * Which enforcement window tripped (P2-G): the per-spawn cost ceiling /
   * turn cap ("spawn") or the rolling 1-hour BYOK cap ("cap-1h"). Drives
   * the window label in the copy.
   */
  which_window: "spawn" | "cap-1h";
  /**
   * Dollar context for honest amount-vs-ceiling copy. Both nullable — a
   * turn-count halt, a pause re-block, or a failed cap-check carries no
   * trustworthy dollar figure, and fabricating one would be dishonest
   * (AC4).
   */
  context: {
    cumulativeCents: number | null;
    ceilingCents: number | null;
  };
}

export type NotificationPayload =
  | ReviewGateNotificationPayload
  | EmailTriageNotificationPayload
  | CostBreakerNotificationPayload
  | InboxItemNotificationPayload;

/**
 * Notifications that must not fail silently: the catches in notifyOfflineUser
 * log without capturing (Layer 2's pino hook only captures Error-instance
 * `err` fields), so a missed send would reach no one. Explicit Sentry mirror —
 * necessary, not redundant (cq-silent-fallback-must-mirror-to-sentry):
 *   - statutory email-triage: a missed ping runs an Art. 12 clock unattended.
 *   - cost_breaker_tripped: a missed halt notification IS the exact "a halt
 *     with no notice" failure this feature exists to prevent (#5767); the plan
 *     Observability block pages on `op=notify-cost-breaker`.
 * No-op for review_gate and non-statutory email_triage (existing behavior).
 */
/**
 * The three notification classes for which a missed send is a real harm and the
 * email fallback must fire even on a partial/zero push delivery (#6802/D4a):
 *   - statutory email_triage: a missed ping runs an Art. 12/33 clock unattended.
 *   - cost_breaker_tripped: a missed halt notice IS the failure the feature
 *     exists to prevent (#5767).
 *   - action_required inbox_item: a decision that needs the founder, silently.
 * Single source of truth — `mirrorNotifyFailure` and `notifyOfflineUser` both
 * consume it, so the class set can never drift between the two.
 */
export function mustNotFailSilently(payload: NotificationPayload): boolean {
  return (
    payload.type === "cost_breaker_tripped" ||
    (payload.type === "email_triage" && payload.isStatutory) ||
    (payload.type === "inbox_item" && payload.severity === "action_required")
  );
}

function mirrorNotifyFailure(payload: NotificationPayload, err: unknown): void {
  const isCostBreaker = payload.type === "cost_breaker_tripped";
  const isStatutoryTriage =
    payload.type === "email_triage" && payload.isStatutory;
  // A missed action_required inbox dispatch is the exact "a decision that needs
  // the founder, with no notice" failure this feature exists to prevent — never
  // silent (plan Observability: op=notify-inbox-action-required).
  const isActionRequiredInbox =
    payload.type === "inbox_item" && payload.severity === "action_required";
  if (!mustNotFailSilently(payload)) return;
  const tags = isCostBreaker
    ? { feature: "cost-breaker", op: "notify-cost-breaker" }
    : isStatutoryTriage
      ? { feature: "email-triage", op: "statutory-notify-failed" }
      : { feature: "inbox", op: "notify-inbox-action-required" };
  try {
    Sentry.captureException(
      err instanceof Error ? err : new Error(String(err)),
      { tags },
    );
  } catch {
    // Observability must never become a second failure.
  }
}

interface PushSubscriptionRow {
  id: string;
  endpoint: string;
  p256dh: string;
  auth: string;
}

// ---------------------------------------------------------------------------
// VAPID setup (lazy — only when first push is sent)
// ---------------------------------------------------------------------------
let vapidConfigured = false;

function ensureVapid(): void {
  if (vapidConfigured) return;
  const publicKey = process.env.VAPID_PUBLIC_KEY;
  const privateKey = process.env.VAPID_PRIVATE_KEY;
  if (!publicKey || !privateKey) {
    throw new Error("VAPID_PUBLIC_KEY and VAPID_PRIVATE_KEY must be set");
  }
  webpush.setVapidDetails("mailto:notifications@soleur.ai", publicKey, privateKey);
  vapidConfigured = true;
}

// ---------------------------------------------------------------------------
// Resend client (lazy)
// ---------------------------------------------------------------------------
let resendClient: Resend | null = null;

// Exported so the cold-outbound chokepoint (server/email-triage/outbound.ts)
// reuses the single shared Resend client. Per the outbound sentinel, outbound.ts
// is the ONLY other module allowed to call resend.emails.send (#5325).
export function getResend(): Resend {
  if (!resendClient) {
    const key = process.env.RESEND_API_KEY;
    if (!key) throw new Error("RESEND_API_KEY must be set");
    resendClient = new Resend(key);
  }
  return resendClient;
}

// ---------------------------------------------------------------------------
// App URL for deep links
// ---------------------------------------------------------------------------
function appUrl(): string {
  const url = process.env.NEXT_PUBLIC_APP_URL;
  if (!url) {
    reportSilentFallback(null, {
      feature: "notifications",
      op: "app-url",
      message: `NEXT_PUBLIC_APP_URL unset; notification deep links fallback to ${APP_URL_FALLBACK}`,
    });
  }
  return url ?? APP_URL_FALLBACK;
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

/** Look up the user's email and send the fallback. Returns whether it landed. */
async function emailFallback(
  supabase: ReturnType<typeof createServiceClient>,
  userId: string,
  payload: NotificationPayload,
): Promise<boolean> {
  const { data: userData, error: userError } =
    await supabase.auth.admin.getUserById(userId);
  if (userError || !userData?.user?.email) {
    log.error(
      { userId, err: userError?.message },
      "Failed to look up user email for notification",
    );
    mirrorNotifyFailure(payload, userError?.message ?? "user email missing");
    return false;
  }
  return sendEmailNotification(userData.user.email, payload);
}

/**
 * Orchestrator: query push subscriptions for userId, push or email.
 * Designed to be called fire-and-forget (no await needed by caller).
 *
 * #6802 (D4/M3): returns whether the notification was DELIVERED on at least one
 * channel — the marker in the statutory cron is rolled back on `false` so the
 * next tick retries, instead of certifying a non-send as sent. "Delivered" is
 * transport acceptance (a push service 201 / a Resend 200), not receipt; the
 * ADR names the crash and bounce residuals. Never throws (the outer catch
 * returns false), preserving the documented contract two call sites rely on.
 */
export async function notifyOfflineUser(
  userId: string,
  payload: NotificationPayload,
): Promise<boolean> {
  try {
    const supabase = createServiceClient();
    const { data: subscriptions, error } = await supabase
      .from("push_subscriptions")
      .select("id, endpoint, p256dh, auth")
      .eq("user_id", userId);

    if (error) {
      log.error({ userId, err: error.message }, "Failed to query push subscriptions");
      mirrorNotifyFailure(payload, error.message);
      return false;
    }

    if (subscriptions && subscriptions.length > 0) {
      const tally = await sendPushNotifications(subscriptions, payload);

      // Full delivery on every registered device → done, no email (no
      // double-notify).
      if (tally.delivered > 0 && tally.delivered >= tally.attempted) {
        return true;
      }

      // #6802 (D4a/M18): partial OR zero delivery on a must-not-fail-silently
      // class falls through to email. `delivered < attempted` (not `=== 0`) is
      // load-bearing: a stale device that still 201s must not mask a dead one
      // and leave the founder on the road with nothing on a legal clock.
      if (mustNotFailSilently(payload)) {
        const emailed = await emailFallback(supabase, userId, payload);
        // The #6802 incident signal fires on TRUE zero push delivery (the
        // egress-DROP case): total push silence with a marker already written.
        // Op slug unchanged so any keyed Sentry/Better Stack rule keeps firing.
        if (
          tally.delivered === 0 &&
          payload.type === "email_triage" &&
          payload.isStatutory
        ) {
          warnSilentFallback(null, {
            feature: "notifications",
            op: "statutory-notify-zero-delivery",
            message:
              "statutory push reached zero devices; fell back to email (no push retry — send-marker already written)",
            extra: {
              userId,
              attempted: tally.attempted,
              delivered: tally.delivered,
              channel: emailed ? "email" : "none",
              fallbackDelivered: emailed,
              emailId: payload.emailId,
            },
          });
        }
        return tally.delivered > 0 || emailed;
      }

      // Non-must-not-fail class (review_gate, non-statutory email_triage): the
      // push tally is the outcome, as before.
      return tally.delivered > 0;
    }

    // No subscriptions → email is the only channel.
    return emailFallback(supabase, userId, payload);
  } catch (err) {
    log.error({ userId, err }, "notifyOfflineUser failed");
    mirrorNotifyFailure(payload, err);
    return false;
  }
}

// ---------------------------------------------------------------------------
// Cost-breaker halt copy (feat-l5-runaway-guard PR-A)
// ---------------------------------------------------------------------------

/** Cents → "$X.XX", or null when there is no trustworthy figure. */
function formatDollars(cents: number | null): string | null {
  if (cents == null || !Number.isFinite(cents)) return null;
  return `$${(cents / 100).toFixed(2)}`;
}

interface CostBreakerCopy {
  heading: string;
  /** Plain-text body (push) — also escaped into the email HTML sink. */
  body: string;
  subject: string;
}

/**
 * Single source of truth for cost-breaker copy across push + email. Honest
 * by construction (AC4): never implies the run completed, denominates in
 * dollars (the founder's own Anthropic credits), and only quotes an amount
 * when we actually have one. The `cap_check_unavailable` copy deliberately
 * avoids any "you overspent" framing — a transient DB error is not a budget
 * breach (P2-H).
 */
function costBreakerCopy(payload: CostBreakerNotificationPayload): CostBreakerCopy {
  const spent = formatDollars(payload.context.cumulativeCents);
  const ceiling = formatDollars(payload.context.ceilingCents);
  const windowLabel =
    payload.which_window === "cap-1h"
      ? "rolling 1-hour spending limit"
      : "per-run spending limit";
  // Amount clause — only when we have a real figure. "your own Anthropic
  // credits" is load-bearing: BYOK spend is the founder's money.
  const amountClause =
    spent && ceiling
      ? ` You spent ${spent} of your ${ceiling} ${windowLabel} — your own Anthropic credits.`
      : spent
        ? ` You spent ${spent} of your own Anthropic credits.`
        : "";

  switch (payload.reason) {
    case "cap_check_unavailable":
      return {
        // NOT "paused" — cap_check_unavailable writes no runtime_paused_at and
        // renders no Resume affordance; "stopped" matches the sibling
        // failure-reason-copy + Today-card surfaces (avoids sending the
        // founder hunting for a Resume button that isn't there).
        heading: "Run stopped — we couldn't verify your budget",
        body:
          "We couldn't check your spending against your cap because of a " +
          "temporary system issue, so the run was stopped as a precaution. " +
          "No pull request was opened. Try again shortly.",
        subject: "Your Soleur run was paused — budget check unavailable",
      };
    case "leader_max_turns_exceeded":
      return {
        heading: "Run stopped — it hit the work limit",
        body:
          "The agent used up its allotted steps before finishing and was " +
          `stopped. Whatever it managed is preserved, but no pull request ` +
          `was opened.${amountClause}`,
        subject: "Your Soleur run stopped — work limit reached",
      };
    case "cost_ceiling_exceeded":
    case "byok_cap_exceeded":
    default:
      return {
        heading: "Run stopped — you hit your spending cap",
        body:
          `Your run reached your ${windowLabel} and was stopped partway ` +
          `through — no pull request was opened.${amountClause}`,
        subject: "Your Soleur run stopped — spending cap reached",
      };
  }
}

/** How many of the attempted pushes actually landed. */
export interface PushDeliveryTally {
  delivered: number;
  attempted: number;
}

/**
 * Send Web Push notifications to all registered devices.
 * On HTTP 410 Gone, deletes the dead subscription immediately.
 *
 * Returns a delivery tally so callers can distinguish "we had subscriptions
 * and they all failed" from "we delivered". That distinction became
 * load-bearing with the statutory repin send-marker (#6781): before the guard,
 * a failed push left the row un-pruned and the next tick retried, an accidental
 * two-run self-heal. With a marker written the retry no longer happens, so a
 * silent all-fail would be PERMANENT silence on a statutory deadline.
 */
export async function sendPushNotifications(
  subscriptions: PushSubscriptionRow[],
  payload: NotificationPayload,
): Promise<PushDeliveryTally> {
  ensureVapid();

  let body: string;
  if (payload.type === "email_triage") {
    // Deep link built EXCLUSIVELY from the server-generated DB uuid.
    // Title is attacker-controlled (email subject): bidi/control strip +
    // length cap at this sink (sw.js renders it verbatim).
    body = JSON.stringify({
      title: sanitizeDisplayString(payload.title),
      body: payload.isStatutory
        ? "Statutory item — a response clock is running."
        : "New email triaged in your Soleur inbox.",
      data: {
        emailId: payload.emailId,
        url: `${appUrl()}/dashboard/inbox/email/${payload.emailId}`,
      },
      icon: "/icons/icon-192x192.png",
    });
  } else if (payload.type === "cost_breaker_tripped") {
    // All fields server-generated (enum + numbers) — no sanitization
    // needed. Deep link routes to the Today feed where the halt banner
    // + Resume CTA live.
    const copy = costBreakerCopy(payload);
    body = JSON.stringify({
      title: copy.heading,
      body: copy.body,
      data: {
        url: `${appUrl()}/dashboard`,
      },
      icon: "/icons/icon-192x192.png",
    });
  } else if (payload.type === "inbox_item") {
    // Title is server-generated but sanitized at the sink (defense-in-depth,
    // matching email_triage). Deep link is a server-generated relative path;
    // sw.js re-validates same-origin on click. `inboxItemId` drives the
    // per-item sw.js tag so inbox pushes never collapse into one another.
    body = JSON.stringify({
      title: sanitizeDisplayString(payload.title),
      body:
        payload.severity === "action_required"
          ? "Something needs your decision."
          : "New update in your Soleur inbox.",
      data: {
        inboxItemId: payload.inboxItemId,
        url: `${appUrl()}${payload.deepLinkPath}`,
      },
      icon: "/icons/icon-192x192.png",
    });
  } else {
    body = JSON.stringify({
      title: `${payload.agentName} needs your input`,
      body: payload.question,
      data: {
        conversationId: payload.conversationId,
        url: `${appUrl()}/dashboard/chat/${payload.conversationId}`,
      },
      icon: "/icons/icon-192x192.png",
    });
  }

  const results = await Promise.allSettled(
    subscriptions.map((sub) =>
      webpush.sendNotification(
        {
          endpoint: sub.endpoint,
          keys: { p256dh: sub.p256dh, auth: sub.auth },
        },
        body,
        // Bounded: the egress firewall (#5046 PR-2) DROPs (not rejects)
        // non-allowlisted push endpoints (Edge/WNS is a deliberate
        // exclusion), so an unbounded send would hang on SYN retransmit
        // (~2 min) inside this awaited allSettled.
        { timeout: 10_000 },
      ),
    ),
  );

  const supabase = createServiceClient();
  const deliveredIds: string[] = [];
  for (let i = 0; i < results.length; i++) {
    const result = results[i];
    if (result.status === "fulfilled") {
      deliveredIds.push(subscriptions[i].id);
    } else {
      const err = result.reason as { statusCode?: number };
      if (err.statusCode === 410) {
        log.info({ subscriptionId: subscriptions[i].id }, "Push subscription expired (410 Gone), deleting");
        await supabase
          .from("push_subscriptions")
          .delete()
          .eq("id", subscriptions[i].id);
      } else {
        // Mirror to Sentry (cq-silent-fallback-must-mirror-to-sentry): a
        // bare log.warn left non-410 push failures — incl. the firewall's
        // deliberate WNS drop — invisible off-host while the user never
        // learns their agent is blocked waiting on input.
        reportSilentFallback(result.reason, {
          feature: "notifications",
          op: "webpush-send-failed",
          message: "Push notification delivery failed (non-410)",
          extra: {
            subscriptionId: subscriptions[i].id,
            statusCode: err.statusCode ?? null,
          },
        });
      }
    }
  }

  // Update last_used_at for successfully delivered subscriptions
  if (deliveredIds.length > 0) {
    await supabase
      .from("push_subscriptions")
      .update({ last_used_at: new Date().toISOString() })
      .in("id", deliveredIds);
  }

  return { delivered: deliveredIds.length, attempted: subscriptions.length };
}

/**
 * Send email notification via Resend as fallback.
 * Inline HTML — no separate template file.
 */
export async function sendEmailNotification(
  email: string,
  payload: NotificationPayload,
): Promise<boolean> {
  if (payload.type === "email_triage") {
    return sendEmailTriageEmailNotification(email, payload);
  }
  if (payload.type === "cost_breaker_tripped") {
    return sendCostBreakerEmailNotification(email, payload);
  }
  if (payload.type === "inbox_item") {
    return sendInboxItemEmailNotification(email, payload);
  }
  const resend = getResend();
  const deepLink = `${appUrl()}/dashboard/chat/${payload.conversationId}`;

  const { error } = await resend.emails.send({
    from: "Soleur <notifications@soleur.ai>",
    to: [email],
    subject: `${escapeHtml(payload.agentName)} needs your input — Soleur`,
    html: renderBrandedNotificationEmail({
      heading: `${escapeHtml(payload.agentName)} needs your input`,
      bodyHtml: escapeHtml(payload.question),
      ctaLabel: "Open conversation",
      deepLink,
      footnoteHtml:
        "You received this because an agent is waiting for your decision on Soleur.",
    }),
  });

  if (error) {
    log.error({ email, err: error }, "Failed to send email notification");
    return false;
  }
  log.info({ email, conversationId: payload.conversationId }, "Email notification sent");
  return true;
}

/**
 * Email fallback for the email_triage variant. The title (= third-party
 * email subject, attacker-controlled) passes sanitizeDisplayString (bidi +
 * CR/LF + control strip — header-injection hygiene near the subject field)
 * and escapeHtml at the HTML sink. Our own subject header is static —
 * third-party content never reaches it. TR3: logs carry emailId only,
 * never the title.
 */
async function sendEmailTriageEmailNotification(
  email: string,
  payload: EmailTriageNotificationPayload,
): Promise<boolean> {
  const resend = getResend();
  // DB uuid only — never an email-derived value (lands inside href).
  const deepLink = `${appUrl()}/dashboard/inbox/email/${payload.emailId}`;
  const safeTitle = sanitizeDisplayString(payload.title);
  const heading = payload.isStatutory
    ? "Statutory item needs your attention"
    : "New item in your Soleur inbox";

  // #6798 (M1): render the not-legal-advice framing + the rule's own
  // clock-origin excerpt in the email body (the surface with room to read it),
  // so a computed backstop date is not presented as THE deadline. Both strings
  // are server-authored + code-static; escapeHtml at the sink is defense-in-depth.
  const statutoryCaveatHtml = payload.isStatutory
    ? `<p style="font-size:13px;color:#6b7280;margin-top:16px">` +
      (payload.statutoryExcerpt
        ? `${escapeHtml(payload.statutoryExcerpt)}<br/><br/>`
        : "") +
      `${escapeHtml(NOT_LEGAL_ADVICE_NOTICE)}</p>`
    : "";

  const { error } = await resend.emails.send({
    from: "Soleur <notifications@soleur.ai>",
    to: [email],
    // Static subject — no third-party content in the header.
    subject: payload.isStatutory
      ? "Statutory item in your Soleur inbox — action required"
      : "New item in your Soleur inbox — Soleur",
    html: renderBrandedNotificationEmail({
      heading,
      bodyHtml: escapeHtml(safeTitle) + statutoryCaveatHtml,
      ctaLabel: "Open inbox item",
      deepLink,
      footnoteHtml:
        "You received this because email triage is enabled for your Soleur inbox.",
    }),
  });

  if (error) {
    log.error({ email, emailId: payload.emailId, err: error }, "Failed to send triage email notification");
    mirrorNotifyFailure(payload, error);
    return false;
  }
  log.info({ email, emailId: payload.emailId }, "Triage email notification sent");
  return true;
}

/**
 * Email fallback for the cost_breaker_tripped variant (feat-l5-runaway-guard
 * PR-A). Body is fully server-generated; escapeHtml is applied at the sink
 * for defense-in-depth even though the copy carries no third-party content.
 * The CTA lands on the Today feed where the halt banner + Resume live.
 */
async function sendCostBreakerEmailNotification(
  email: string,
  payload: CostBreakerNotificationPayload,
): Promise<boolean> {
  const resend = getResend();
  const copy = costBreakerCopy(payload);
  const deepLink = `${appUrl()}/dashboard`;

  const { error } = await resend.emails.send({
    from: "Soleur <notifications@soleur.ai>",
    to: [email],
    subject: `${copy.subject} — Soleur`,
    html: renderBrandedNotificationEmail({
      heading: escapeHtml(copy.heading),
      bodyHtml: escapeHtml(copy.body),
      // CTA reflects the actual recovery path: only byok_cap_exceeded leaves
      // the account paused (Resume renders); a failed cap-check is transient
      // (try again); the per-spawn/turn-cap halts just land on the dashboard.
      ctaLabel:
        payload.reason === "byok_cap_exceeded"
          ? "Clear pause & resume"
          : payload.reason === "cap_check_unavailable"
            ? "Try again"
            : "Review run",
      deepLink,
      footnoteHtml:
        "You received this because a spending safeguard stopped one of your Soleur runs.",
    }),
  });

  if (error) {
    log.error({ email, reason: payload.reason, err: error }, "Failed to send cost-breaker email notification");
    // A missed halt notification is the exact failure this feature prevents —
    // mirror to Sentry (op=notify-cost-breaker) so it never fails silently.
    mirrorNotifyFailure(payload, error);
    return false;
  }
  log.info({ email, reason: payload.reason }, "Cost-breaker email notification sent");
  return true;
}

/**
 * Email fallback for the inbox_item variant (feat-severity-ranked-inbox). Title
 * is server-generated but escaped at the sink (defense-in-depth). The CTA lands
 * on the item's deep link (a server-generated same-origin path).
 */
async function sendInboxItemEmailNotification(
  email: string,
  payload: InboxItemNotificationPayload,
): Promise<boolean> {
  const resend = getResend();
  const deepLink = `${appUrl()}${payload.deepLinkPath}`;
  const safeTitle = sanitizeDisplayString(payload.title);
  const isActionRequired = payload.severity === "action_required";
  const heading = isActionRequired
    ? "Something needs your decision"
    : "New update in your Soleur inbox";

  const { error } = await resend.emails.send({
    from: "Soleur <notifications@soleur.ai>",
    to: [email],
    subject: isActionRequired
      ? "Something needs your decision — Soleur"
      : "New update in your Soleur inbox — Soleur",
    html: renderBrandedNotificationEmail({
      heading,
      bodyHtml: escapeHtml(safeTitle),
      ctaLabel: "Open in Soleur",
      deepLink,
      footnoteHtml:
        "You received this because it needs your attention in your Soleur inbox.",
    }),
  });

  if (error) {
    log.error(
      { email, inboxItemId: payload.inboxItemId, err: error },
      "Failed to send inbox-item email notification",
    );
    mirrorNotifyFailure(payload, error);
    return false;
  }
  log.info({ email, inboxItemId: payload.inboxItemId }, "Inbox-item email notification sent");
  return true;
}

// ---------------------------------------------------------------------------
// Operational inbox emit (feat-severity-ranked-inbox #6007)
// ---------------------------------------------------------------------------

/**
 * Insert an inbox_item row, then dispatch the push/email nudge. Fire-and-forget
 * (never throws) — callers must not await it.
 *
 * Idempotent (ADR-037): plain-insert + catch 23505 rather than
 * `ON CONFLICT DO NOTHING` (unreliable under supabase-js — returns data:null).
 * A push is dispatched ONLY when a row was actually inserted, so an emit retry
 * (same dedup_key) never re-pushes. Targeted rows (user_id set) dispatch to that
 * one recipient; broadcast rows (user_id null) dispatch to every workspace Owner.
 *
 * Content-minimization (ADR-085): `title` must be server-generated — never raw
 * agent output / email content. `sourceRef` carries ids ONLY; the deep link is
 * built from those ids by the caller (never stored).
 */
export async function notifyInboxItem(opts: {
  workspaceId: string;
  /** null = broadcast to every workspace Owner; set = targeted to one recipient. */
  userId: string | null;
  severity: InboxItemSeverity;
  source: "task_completed" | "system";
  /** Server-generated + sanitized. NEVER raw agent output / email content. */
  title: string;
  /** ids only (e.g. { conversationId }). The deep link is built from these. */
  sourceRef?: Record<string, string> | null;
  /**
   * Idempotency key (ADR-037). Omit for naturally-once emits. NOTE the dedup
   * index is `(workspace_id, dedup_key)` — workspace-scoped, NOT per-recipient.
   * A future TARGETED emitter that fans one event out to multiple recipients
   * with a SHARED dedup_key would suppress all but the first recipient's row
   * (23505 → silent skip). Such an emitter must namespace the key per user_id.
   */
  dedupKey?: string | null;
  /** Same-origin relative deep-link path built from sourceRef ids. */
  deepLinkPath: string;
}): Promise<void> {
  // Reject a non-relative / protocol-relative deep link at the emit boundary —
  // the email CTA (sendInboxItemEmailNotification) prefixes appUrl() without an
  // origin re-check (unlike sw.js on click), so a `//evil.host` or absolute URL
  // must never reach a co-Owner-visible email/push. Server-generated ids can't
  // produce these today; this fails a future bad caller closed.
  if (!opts.deepLinkPath.startsWith("/") || opts.deepLinkPath.startsWith("//")) {
    reportSilentFallback(null, {
      feature: "inbox",
      op: "inbox-item-bad-deeplink",
      message: "notifyInboxItem rejected a non-relative deepLinkPath",
      extra: { workspaceId: opts.workspaceId, source: opts.source },
    });
    return;
  }
  // action_required failures (insert OR dispatch) key the Sentry alert on this op.
  const failOp =
    opts.severity === "action_required"
      ? "notify-inbox-action-required"
      : "inbox-item-insert";
  try {
    const supabase = createServiceClient();

    const { data: inserted, error: insertErr } = await supabase
      .from("inbox_item")
      .insert({
        workspace_id: opts.workspaceId,
        user_id: opts.userId,
        severity: opts.severity,
        source: opts.source,
        title: opts.title,
        source_ref: opts.sourceRef ?? null,
        dedup_key: opts.dedupKey ?? null,
      })
      .select("id")
      .single();

    if (insertErr) {
      // 23505 = deduped (idempotent no-op) — expected, not a failure, no push.
      if ((insertErr as { code?: string }).code === "23505") return;
      reportSilentFallback(insertErr, {
        feature: "inbox",
        op: failOp,
        message: "inbox_item insert failed",
        extra: { workspaceId: opts.workspaceId, source: opts.source },
      });
      return;
    }
    if (!inserted) return;

    const payload: InboxItemNotificationPayload = {
      type: "inbox_item",
      inboxItemId: (inserted as { id: string }).id,
      title: opts.title,
      severity: opts.severity,
      deepLinkPath: opts.deepLinkPath,
    };

    if (opts.userId) {
      // notifyOfflineUser mirrors its own dispatch failures via
      // mirrorNotifyFailure (op=notify-inbox-action-required for action_required).
      await notifyOfflineUser(opts.userId, payload);
      return;
    }

    // Broadcast: dispatch to every Owner of the workspace.
    const { data: owners, error: ownersErr } = await supabase
      .from("workspace_members")
      .select("user_id")
      .eq("workspace_id", opts.workspaceId)
      .eq("role", "owner");
    if (ownersErr) {
      reportSilentFallback(ownersErr, {
        feature: "inbox",
        op: failOp,
        message: "inbox_item broadcast owner lookup failed",
        extra: { workspaceId: opts.workspaceId },
      });
      return;
    }
    await Promise.allSettled(
      (owners ?? []).map((o) =>
        notifyOfflineUser((o as { user_id: string }).user_id, payload),
      ),
    );
  } catch (err) {
    reportSilentFallback(err, {
      feature: "inbox",
      op: failOp,
      message: "notifyInboxItem failed",
      extra: { workspaceId: opts.workspaceId },
    });
  }
}

/**
 * Shared `task_completed` inbox emit (feat-severity-ranked-inbox #6007). The
 * SINGLE seam both turn-boundary terminals call so the two agent-run lineages
 * (legacy `startAgentSession` + cc-soleur-go `cc-dispatcher`) cannot drift — a
 * new emit wired into only one path is the exact "must cover both turn
 * boundaries" defect class. Fire-and-forget (notifyInboxItem never throws).
 *
 * `title` is server-generated (a static leader title or a fixed concierge
 * string) — NEVER agent output. No dedupKey: each completed turn is a distinct
 * event, and one durable row per completion is the intended semantic (the 90d
 * retention sweep bounds accumulation).
 */
export async function notifyTaskCompleted(opts: {
  userId: string;
  conversationId: string;
  workspaceId: string;
  title: string;
}): Promise<void> {
  await notifyInboxItem({
    workspaceId: opts.workspaceId,
    userId: opts.userId,
    severity: "info",
    source: "task_completed",
    title: opts.title,
    sourceRef: { conversationId: opts.conversationId },
    deepLinkPath: `/dashboard/chat/${opts.conversationId}`,
  });
}

// ---------------------------------------------------------------------------
// DSAR export notifications (Phase 4 of feat-dsar-art15-export-endpoint
// #3637, plan rev-2 C2 fold of dsar-email.ts).
//
// TR6 contract:
//   - Subject + first 280 chars of body are PII-free (no jobId, userId,
//     email) so mobile-client preview-text rendering cannot leak.
//   - Plain `<a>` link, NOT auto-tracked: no Resend `tags` / per-link
//     tracking, since trackable URLs forwarded to a coworker would let
//     the email host's tracker correlate the recipient.
//   - Returns `false` on user-lookup or email-absent failure (silent
//     non-throw — caller is the worker, which already mirrored the
//     fact that the export completed/failed; an email failure is not
//     a hard failure of the DSAR job).
// ---------------------------------------------------------------------------

// Internal code -> user-facing copy. Codes themselves never reach the
// body (they would leak internal taxonomy and rot under refactor).
const DSAR_FAILURE_COPY: Record<string, string> = {
  job_timeout:
    "We weren't able to package your data within the time limit. Please request the export again — if it keeps failing, contact legal@jikigai.com.",
  // 'account_deleted_during_export' is referenced for completeness but
  // unreachable as an email path: the account-delete cascade flips the
  // job row BEFORE deleting the auth account, and we don't email a
  // tombstoned mailbox. Kept here so the map covers every value the
  // failure_reason column can hold (Art. 5(2) traceability).
  account_deleted_during_export:
    "Your account was deleted while the export was being prepared. The export was cancelled.",
  bundle_too_large:
    "Your account contains more data than the self-serve export currently supports. Please email legal@jikigai.com and we will package your bundle manually within 7 business days.",
  archive_error:
    "We hit an unexpected error while packaging your data. Please request the export again.",
};

function dsarFailureCopy(reason: string): string {
  return (
    DSAR_FAILURE_COPY[reason] ??
    "We weren't able to complete your data export. Please request it again or contact legal@jikigai.com."
  );
}

async function lookupUserEmail(userId: string): Promise<string | null> {
  const supabase = createServiceClient();
  const { data, error } = await supabase.auth.admin.getUserById(userId);
  if (error || !data?.user?.email) {
    log.error(
      { userId, err: error?.message },
      "Failed to look up user email for DSAR notification",
    );
    return null;
  }
  return data.user.email;
}

/**
 * Notify the user that their DSAR export bundle is ready.
 *
 * @returns `true` on Resend success, `false` on user-lookup failure or
 *          missing email. Never throws.
 */
export async function sendDsarExportReadyEmail(
  userId: string,
  jobId: string,
  expiresAt: Date,
): Promise<boolean> {
  const email = await lookupUserEmail(userId);
  if (!email) return false;

  const downloadUrl = `${appUrl()}/api/account/export/${jobId}/download`;
  // Format expiry as a human-friendly UTC date — "the link expires in
  // 7 days" + the absolute timestamp so users in any TZ can plan.
  const expiresAtUtc = expiresAt.toISOString().replace("T", " ").slice(0, 16) + " UTC";

  const resend = getResend();
  const { error } = await resend.emails.send({
    from: "Soleur <notifications@soleur.ai>",
    to: [email],
    // PII-free subject — no jobId, no userId, no email.
    subject: "Your Soleur data export is ready",
    html: renderBrandedNotificationEmail({
      heading: "Your Soleur data export is ready",
      bodyHtml: `Your data export is ready to download. The link expires in 7 days (${escapeHtml(expiresAtUtc)}). The download link is single-use and bound to the device that requested it.`,
      ctaLabel: "Download my data",
      deepLink: downloadUrl,
      footnoteHtml:
        "You requested this export from /settings/privacy on Soleur. If you did not request it, contact legal@jikigai.com.",
    }),
  });

  if (error) {
    log.error({ userId, jobId, err: error }, "Failed to send DSAR ready email");
    return false;
  }
  log.info({ userId, jobId }, "DSAR ready email sent");
  return true;
}

/**
 * Notify the user that their DSAR export job failed. Translates the
 * internal `failure_reason` code to user-facing copy — the code itself
 * never reaches the body.
 */
export async function sendDsarExportFailedEmail(
  userId: string,
  jobId: string,
  reason: string,
): Promise<boolean> {
  const email = await lookupUserEmail(userId);
  if (!email) return false;

  const settingsUrl = `${appUrl()}/dashboard/settings/privacy`;
  const userCopy = dsarFailureCopy(reason);

  const resend = getResend();
  const { error } = await resend.emails.send({
    from: "Soleur <notifications@soleur.ai>",
    to: [email],
    subject: "Your Soleur data export could not be completed",
    html: renderBrandedNotificationEmail({
      heading: "Your Soleur data export could not be completed",
      bodyHtml: escapeHtml(userCopy),
      ctaLabel: "Go to /settings/privacy",
      deepLink: settingsUrl,
      footnoteHtml:
        "You requested this export from /settings/privacy on Soleur. If the problem persists, contact legal@jikigai.com.",
    }),
  });

  if (error) {
    log.error({ userId, jobId, reason, err: error }, "Failed to send DSAR failed email");
    return false;
  }
  log.info({ userId, jobId, reason }, "DSAR failed email sent");
  return true;
}

// ---------------------------------------------------------------------------
// Workspace invite notifications
// ---------------------------------------------------------------------------

export async function sendInviteEmail(
  inviteeEmail: string,
  inviterName: string,
  workspaceName: string,
  token: string,
): Promise<boolean> {
  const resend = getResend();
  const inviteUrl = `${appUrl()}/invite/${token}`;

  const { error } = await resend.emails.send({
    from: "Soleur <notifications@soleur.ai>",
    to: [inviteeEmail],
    subject: `You've been invited to join ${escapeHtml(workspaceName)} on Soleur`,
    html: renderBrandedNotificationEmail({
      heading: `You've been invited to join ${escapeHtml(workspaceName)}`,
      bodyHtml: `${escapeHtml(inviterName)} has invited you to join the <strong>${escapeHtml(workspaceName)}</strong> workspace on Soleur.`,
      ctaLabel: "Accept invitation",
      deepLink: inviteUrl,
      footnoteHtml:
        "This invitation expires in 7 days. If you weren't expecting this, you can ignore this email.",
    }),
  });

  if (error) {
    log.error({ inviteeEmail, err: error }, "Failed to send invite email");
    reportSilentFallback(null, {
      feature: "workspace-invitations",
      op: "send-invite-email",
      message: `Failed to send invite email to ${inviteeEmail}: ${error.message}`,
    });
    return false;
  }
  log.info({ inviteeEmail, workspaceName }, "Invite email sent");
  return true;
}

export async function sendInviteAcceptedEmail(
  inviterUserId: string,
  accepterName: string,
  workspaceName: string,
): Promise<boolean> {
  const email = await lookupUserEmail(inviterUserId);
  if (!email) return false;

  const resend = getResend();
  const teamUrl = `${appUrl()}/dashboard/settings/team`;

  const { error } = await resend.emails.send({
    from: "Soleur <notifications@soleur.ai>",
    to: [email],
    subject: `${escapeHtml(accepterName)} has joined ${escapeHtml(workspaceName)}`,
    html: renderBrandedNotificationEmail({
      heading: `${escapeHtml(accepterName)} has joined ${escapeHtml(workspaceName)}`,
      bodyHtml: `Your invitation was accepted. ${escapeHtml(accepterName)} is now a member of <strong>${escapeHtml(workspaceName)}</strong>.`,
      ctaLabel: "View team",
      deepLink: teamUrl,
    }),
  });

  if (error) {
    log.error({ inviterUserId, err: error }, "Failed to send invite accepted email");
    reportSilentFallback(null, {
      feature: "workspace-invitations",
      op: "send-accepted-email",
      message: `Failed to send acceptance confirmation: ${error.message}`,
    });
    return false;
  }
  log.info({ inviterUserId, accepterName, workspaceName }, "Invite accepted email sent");
  return true;
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function escapeHtml(str: string): string {
  return str
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;");
}
