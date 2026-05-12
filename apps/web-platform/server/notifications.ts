/**
 * Offline notification dispatch for review gate events.
 *
 * Notification hierarchy: WS (existing) > Push (new) > Email (new, fallback).
 * All functions are fire-and-forget — callers should not await them.
 */

import webpush from "web-push";
import { Resend } from "resend";
import { createServiceClient } from "@/lib/supabase/service";
import { createChildLogger } from "@/server/logger";
import { APP_URL_FALLBACK, reportSilentFallback } from "@/server/observability";

const log = createChildLogger("notifications");

export interface NotificationPayload {
  type: "review_gate";
  conversationId: string;
  agentName: string;
  question: string;
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

function getResend(): Resend {
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

/**
 * Orchestrator: query push subscriptions for userId, push or email.
 * Designed to be called fire-and-forget (no await needed by caller).
 */
export async function notifyOfflineUser(
  userId: string,
  payload: NotificationPayload,
): Promise<void> {
  try {
    const supabase = createServiceClient();
    const { data: subscriptions, error } = await supabase
      .from("push_subscriptions")
      .select("id, endpoint, p256dh, auth")
      .eq("user_id", userId);

    if (error) {
      log.error({ userId, err: error.message }, "Failed to query push subscriptions");
      return;
    }

    if (subscriptions && subscriptions.length > 0) {
      await sendPushNotifications(subscriptions, payload);
    } else {
      // Fallback: send email
      const { data: userData, error: userError } = await supabase.auth.admin.getUserById(userId);
      if (userError || !userData?.user?.email) {
        log.error({ userId, err: userError?.message }, "Failed to look up user email for notification");
        return;
      }
      await sendEmailNotification(userData.user.email, payload);
    }
  } catch (err) {
    log.error({ userId, err }, "notifyOfflineUser failed");
  }
}

/**
 * Send Web Push notifications to all registered devices.
 * On HTTP 410 Gone, deletes the dead subscription immediately.
 */
export async function sendPushNotifications(
  subscriptions: PushSubscriptionRow[],
  payload: NotificationPayload,
): Promise<void> {
  ensureVapid();

  const body = JSON.stringify({
    title: `${payload.agentName} needs your input`,
    body: payload.question,
    data: {
      conversationId: payload.conversationId,
      url: `${appUrl()}/dashboard/chat/${payload.conversationId}`,
    },
    icon: "/icons/icon-192x192.png",
  });

  const results = await Promise.allSettled(
    subscriptions.map((sub) =>
      webpush.sendNotification(
        {
          endpoint: sub.endpoint,
          keys: { p256dh: sub.p256dh, auth: sub.auth },
        },
        body,
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
        log.warn(
          { subscriptionId: subscriptions[i].id, err: result.reason },
          "Push notification delivery failed",
        );
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
}

/**
 * Send email notification via Resend as fallback.
 * Inline HTML — no separate template file.
 */
export async function sendEmailNotification(
  email: string,
  payload: NotificationPayload,
): Promise<void> {
  const resend = getResend();
  const deepLink = `${appUrl()}/dashboard/chat/${payload.conversationId}`;

  const { error } = await resend.emails.send({
    from: "Soleur <notifications@soleur.ai>",
    to: [email],
    subject: `${escapeHtml(payload.agentName)} needs your input — Soleur`,
    html: `
      <div style="font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; max-width: 480px; margin: 0 auto; padding: 24px;">
        <h2 style="margin: 0 0 16px; font-size: 18px; color: #1a1a1a;">${escapeHtml(payload.agentName)} needs your input</h2>
        <p style="margin: 0 0 16px; color: #4a4a4a; line-height: 1.5;">${escapeHtml(payload.question)}</p>
        <a href="${deepLink}" style="display: inline-block; padding: 12px 24px; background: #2563eb; color: #fff; text-decoration: none; border-radius: 6px; font-weight: 500;">Open conversation</a>
        <p style="margin: 24px 0 0; font-size: 12px; color: #9a9a9a;">You received this because an agent is waiting for your decision on Soleur.</p>
      </div>
    `,
  });

  if (error) {
    log.error({ email, err: error }, "Failed to send email notification");
  } else {
    log.info({ email, conversationId: payload.conversationId }, "Email notification sent");
  }
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
    html: `
      <div style="font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; max-width: 480px; margin: 0 auto; padding: 24px;">
        <h2 style="margin: 0 0 16px; font-size: 18px; color: #1a1a1a;">Your Soleur data export is ready</h2>
        <p style="margin: 0 0 16px; color: #4a4a4a; line-height: 1.5;">Your data export is ready to download. The link expires in 7 days (${escapeHtml(expiresAtUtc)}). The download link is single-use and bound to the device that requested it.</p>
        <a href="${downloadUrl}" style="display: inline-block; padding: 12px 24px; background: #2563eb; color: #fff; text-decoration: none; border-radius: 6px; font-weight: 500;">Download my data</a>
        <p style="margin: 24px 0 0; font-size: 12px; color: #9a9a9a;">You requested this export from /settings/privacy on Soleur. If you did not request it, contact legal@jikigai.com.</p>
      </div>
    `,
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
    html: `
      <div style="font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; max-width: 480px; margin: 0 auto; padding: 24px;">
        <h2 style="margin: 0 0 16px; font-size: 18px; color: #1a1a1a;">Your Soleur data export could not be completed</h2>
        <p style="margin: 0 0 16px; color: #4a4a4a; line-height: 1.5;">${escapeHtml(userCopy)}</p>
        <a href="${settingsUrl}" style="display: inline-block; padding: 12px 24px; background: #2563eb; color: #fff; text-decoration: none; border-radius: 6px; font-weight: 500;">Go to /settings/privacy</a>
        <p style="margin: 24px 0 0; font-size: 12px; color: #9a9a9a;">You requested this export from /settings/privacy on Soleur. If the problem persists, contact legal@jikigai.com.</p>
      </div>
    `,
  });

  if (error) {
    log.error({ userId, jobId, reason, err: error }, "Failed to send DSAR failed email");
    return false;
  }
  log.info({ userId, jobId, reason }, "DSAR failed email sent");
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
