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
  return process.env.NEXT_PUBLIC_APP_URL || "https://app.soleur.ai";
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
