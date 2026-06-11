// feat-operator-inbox-delegation Phase 4 — email/inbound.received pipeline.
//
// Pinned step boundaries (ADR-033 I1/I5 — step.run returns are CHECKPOINTED
// in the Inngest run store, so the raw email body must NEVER be a step
// return value or event field, or parse-and-discard is defeated):
//
//   (1) step.run("claim-insert")        — stub row, 23505 finalized→short-
//       circuit / unfinalized stub→adopt+resume (mig 052 idiom; a run that
//       dies mid-pipeline must not leave a permanent blank stub that every
//       redelivery short-circuits against).
//   (2) metadata statutory check        — PURE/inline, no IO, before any
//       body fetch: a fetch outage can only degrade the row, never drop a
//       DSAR. Match → step.run("finalize-statutory") (summary stays NULL —
//       a degraded row is correct) → notify → return.
//   (3) probe check                     — pure token extract, then
//       step.run("probe-classify"): valid recent probe_tokens row →
//       mail_class 'probe', NO notify; probe SHAPE without a valid token →
//       'other' + Sentry warn (a static marker would be a forgeable
//       mail-suppression channel) + normal notify.
//   (4) ONE fused step.run("fetch-sanitize-summarize") — daily LLM ceiling,
//       body fetch, body statutory pass, thin-body escalation, LLM call —
//       returning ONLY {summary, mailClass, ...}: the body never crosses a
//       step boundary.
//   (5) step.run("finalize-row")        — one-time-set UPDATE per outcome.
//   (6) step.run("notify") LAST and separate — a notify-failure retry must
//       not re-run the LLM, a finalize retry must not double-ping.
//
// Observability: function-final errors are captured by Layer 1
// (server/inngest/middleware/sentry-correlation.ts transformOutput) — no
// per-function captureException needed for terminal errors. The ONLY
// explicit Sentry mirror here is the statutory notify failure
// (notifications.ts's catch passes errors to log.error, which the Layer 2
// pino hook does not capture as an exception for string-shaped err values).
//
// TR3: no log/Sentry call carries body, subject, or sender values —
// including Error message strings. DB column writes (sender/subject/summary)
// are the sanctioned store; the ban is logs/Sentry/Inngest checkpoints.

import * as Sentry from "@sentry/nextjs";
import { inngest } from "@/server/inngest/client";
import { createServiceClient } from "@/lib/supabase/service";
import { warnSilentFallback, reportSilentFallback } from "@/server/observability";
import { notifyOfflineUser } from "@/server/notifications";
import {
  EMAIL_INBOUND_RECEIVED_EVENT,
  type EmailInboundReceivedData,
} from "@/server/email-triage/events";
import {
  matchStatutoryMetadata,
  matchStatutoryBody,
  matchProbeToken,
  isThinBody,
  normalizeEmailHtml,
} from "@/server/email-triage/statutory-rules";
import { fetchReceivedEmail } from "@/server/email-triage/fetch-received-email";
import { summarizeEmail, type MailClass } from "@/server/email-triage/summarize";

/**
 * Daily cap on LLM-summarized rows (rows with a non-NULL summary created
 * today). Anyone on the internet can mail ops@ — without a ceiling they
 * control our Anthropic spend. On breach the row lands as mail_class
 * 'other' / summary "deferred — volume cap": degraded triage is acceptable,
 * unbounded spend is not.
 */
export const EMAIL_TRIAGE_DAILY_LLM_CEILING = 200;

/** Statutory ping coalescing window — see step (6). */
const STATUTORY_COALESCE_MS = 10 * 60 * 1000;

/** Probe tokens are only honored within 24h of minting (probe cron cadence). */
const PROBE_TOKEN_MAX_AGE_MS = 24 * 60 * 60 * 1000;

type ServiceClient = ReturnType<typeof createServiceClient>;

interface HandlerArgs {
  event: { data: EmailInboundReceivedData };
  step: { run<T>(name: string, cb: () => Promise<T>): Promise<T> };
  logger?: {
    info: (...args: unknown[]) => void;
    warn: (...args: unknown[]) => void;
    error: (...args: unknown[]) => void;
  };
}

type FusedOutcome =
  | { kind: "deferred" }
  | { kind: "bodyStatutory"; statutoryClass: string; ruleId: string }
  | { kind: "legalReview"; summary: string }
  | { kind: "summarized"; summary: string; mailClass: MailClass };

/** One-time-set finalize UPDATE (NULL → value once; WORM trigger enforces). */
async function applyFinalize(
  sb: ServiceClient,
  itemId: string,
  patch: Record<string, string>,
): Promise<void> {
  const { error } = await sb
    .from("email_triage_items")
    .update(patch)
    .eq("id", itemId);
  if (error) {
    // Code only — never row values (TR3).
    throw new Error(`email_triage finalize failed: ${error.code ?? "unknown"}`);
  }
}

/**
 * Step (6) body. Statutory pings coalesce: if another statutory item row was
 * created within the last 10 minutes (excluding this one), skip the ping —
 * the earlier item already pinged and rows stay pinned in the UI. When
 * pinging with N>1 unacknowledged statutory items, the title appends
 * " (+N-1 more)".
 */
async function sendTriageNotification(args: {
  ownerId: string;
  itemId: string;
  subject: string;
  statutory: boolean;
}): Promise<{ pinged: boolean }> {
  const sb = createServiceClient();
  let title = args.subject;

  if (args.statutory) {
    const windowStart = new Date(Date.now() - STATUTORY_COALESCE_MS).toISOString();
    const { data: recent, error: recentErr } = await sb
      .from("email_triage_items")
      .select("id")
      .not("statutory_class", "is", null)
      .neq("id", args.itemId)
      .gte("created_at", windowStart)
      .limit(1);
    if (!recentErr && recent && recent.length > 0) {
      return { pinged: false };
    }

    const { count } = await sb
      .from("email_triage_items")
      .select("id", { count: "exact", head: true })
      .not("statutory_class", "is", null)
      .eq("status", "new");
    const unacknowledged = count ?? 1;
    if (unacknowledged > 1) {
      title = `${title} (+${unacknowledged - 1} more)`;
    }
  }

  try {
    await notifyOfflineUser(args.ownerId, {
      type: "email_triage",
      emailId: args.itemId, // DB uuid ONLY — lands in href unescaped.
      title,
      isStatutory: args.statutory,
    });
  } catch (err) {
    if (args.statutory) {
      // Explicit mirror (cq-silent-fallback-must-mirror-to-sentry): the
      // notifications-layer catch logs without capturing, and a silently
      // missed statutory ping is an eaten Art. 12 clock.
      Sentry.captureException(
        err instanceof Error ? err : new Error("statutory notify failed"),
        { tags: { feature: "email-triage", op: "statutory-notify-failed" } },
      );
    }
    // Non-statutory: keep existing fire-and-forget behavior.
  }
  return { pinged: true };
}

export async function emailOnReceivedHandler({
  event,
  step,
}: HandlerArgs): Promise<Record<string, unknown>> {
  const data = event.data;

  const ownerId = process.env.EMAIL_TRIAGE_OWNER_USER_ID;
  if (!ownerId) {
    // Retriable by design — NEVER skip, NEVER NonRetriableError: a missing
    // owner env is ops misconfiguration; Inngest redelivery means no email
    // is dropped while it is fixed, and Layer 1 captures on exhaustion.
    throw new Error(
      "EMAIL_TRIAGE_OWNER_USER_ID is unset — cannot claim inbound email",
    );
  }

  // ---- (1) claim-insert ----------------------------------------------------
  const claim = await step.run("claim-insert", async () => {
    const sb = createServiceClient();

    // Owner validation: the strongest available founder/owner predicate is
    // the ADR-038 N2 solo-workspace shape — a workspace_members row with
    // workspace_id = user_id = owner AND role = 'owner' (users.role is
    // 'prd'/'dev' flag-targeting, not ownership). Invalid → retriable throw.
    const { data: userRow, error: userErr } = await sb
      .from("users")
      .select("id")
      .eq("id", ownerId)
      .maybeSingle();
    if (userErr) {
      throw new Error(`owner lookup failed: ${userErr.code ?? "unknown"}`);
    }
    if (!userRow) {
      throw new Error(
        "EMAIL_TRIAGE_OWNER_USER_ID does not match a users row",
      );
    }
    const { data: memberRow, error: memberErr } = await sb
      .from("workspace_members")
      .select("user_id")
      .eq("workspace_id", ownerId)
      .eq("user_id", ownerId)
      .eq("role", "owner")
      .maybeSingle();
    if (memberErr) {
      throw new Error(`owner role lookup failed: ${memberErr.code ?? "unknown"}`);
    }
    if (!memberRow) {
      throw new Error(
        "EMAIL_TRIAGE_OWNER_USER_ID is not the workspace owner (workspace_members role='owner')",
      );
    }

    // RFC 5322 Message-ID is optional + sender-controlled; Postgres UNIQUE
    // treats NULLs as distinct — claim_key COALESCEs to the Resend id.
    const claimKey = data.messageId ?? `resend:${data.resendEmailId}`;

    const { data: inserted, error: insertErr } = await sb
      .from("email_triage_items")
      .insert({
        user_id: ownerId,
        claim_key: claimKey,
        message_id: data.messageId,
        resend_email_id: data.resendEmailId,
        sender: data.sender,
        subject: data.subject,
        received_at: data.receivedAt,
        received_at_source: data.receivedAtSource,
        // One-time-set columns: SQL NULL, NEVER '' — an empty-string stub
        // makes the WORM freeze trigger reject the finalize.
        summary: null,
        mail_class: null,
        statutory_class: null,
        rule_id: null,
      })
      .select("id")
      .single();

    if (insertErr) {
      if (insertErr.code === "23505") {
        // supabase-js 23505-catch idiom (mig 052 quirk) — distinguish a
        // FINALIZED row (short-circuit) from an unfinalized stub (adopt +
        // resume; a run that died mid-pipeline must not rot a DSAR).
        const { data: existing, error: selErr } = await sb
          .from("email_triage_items")
          .select("id, mail_class, statutory_class")
          .eq("claim_key", claimKey)
          .single();
        if (selErr || !existing) {
          throw new Error(
            `claim conflict lookup failed: ${selErr?.code ?? "missing-row"}`,
          );
        }
        const row = existing as {
          id: string;
          mail_class: string | null;
          statutory_class: string | null;
        };
        if (row.mail_class !== null || row.statutory_class !== null) {
          return { shortCircuit: true as const, id: row.id };
        }
        return { shortCircuit: false as const, id: row.id };
      }
      throw new Error(`claim insert failed: ${insertErr.code ?? "unknown"}`);
    }
    return {
      shortCircuit: false as const,
      id: (inserted as { id: string }).id,
    };
  });

  if (claim.shortCircuit) return { shortCircuit: true };
  const itemId = claim.id;

  // ---- (2) statutory check on event METADATA — pure/inline, no IO ----------
  const metaRule = matchStatutoryMetadata({
    subject: data.subject,
    sender: data.sender,
    attachmentFilenames: (data.attachments ?? []).map((a) => a.filename),
  });
  if (metaRule) {
    await step.run("finalize-statutory", async () => {
      // summary stays NULL — a degraded row is correct; the body fetch and
      // the LLM are structurally unreachable on this path.
      await applyFinalize(createServiceClient(), itemId, {
        statutory_class: metaRule.statutoryClass,
        rule_id: metaRule.ruleId,
      });
      return { finalized: true };
    });
    await step.run("notify", () =>
      sendTriageNotification({
        ownerId,
        itemId,
        subject: data.subject,
        statutory: true,
      }),
    );
    return { statutory: metaRule.ruleId };
  }

  // ---- (3) probe check — pure token extract, then one classify step --------
  const probeToken = matchProbeToken(data.subject);
  if (probeToken !== null) {
    const probe = await step.run("probe-classify", async () => {
      const sb = createServiceClient();
      const cutoff = new Date(Date.now() - PROBE_TOKEN_MAX_AGE_MS).toISOString();
      const { data: tokenRow, error: tokenErr } = await sb
        .from("probe_tokens")
        .select("token, created_at")
        .eq("token", probeToken)
        .gte("created_at", cutoff)
        .maybeSingle();
      if (tokenErr) {
        throw new Error(`probe token lookup failed: ${tokenErr.code ?? "unknown"}`);
      }
      if (tokenRow) {
        await applyFinalize(sb, itemId, {
          mail_class: "probe",
          summary: "synthetic ingress probe",
        });
        return { valid: true as const };
      }
      // Probe SHAPE without a valid recent token: a static marker would be
      // a forgeable mail-suppression channel — classify visible + warn.
      await applyFinalize(sb, itemId, {
        mail_class: "other",
        summary:
          "probe-shaped marker without a valid token — treat as ordinary mail",
      });
      warnSilentFallback(null, {
        feature: "email-triage",
        op: "probe-token-mismatch",
        message: "probe-shaped subject without a matching probe_tokens row",
        extra: { itemId },
      });
      return { valid: false as const };
    });
    if (probe.valid) return { probe: true };
    await step.run("notify", () =>
      sendTriageNotification({
        ownerId,
        itemId,
        subject: data.subject,
        statutory: false,
      }),
    );
    return { probe: false };
  }

  // ---- (4) ONE fused fetch-sanitize-summarize step --------------------------
  const fused = await step.run("fetch-sanitize-summarize", async (): Promise<FusedOutcome> => {
    const sb = createServiceClient();

    // Daily LLM ceiling FIRST — before the body fetch spends anything.
    const startOfDay = new Date();
    startOfDay.setUTCHours(0, 0, 0, 0);
    const { count, error: countErr } = await sb
      .from("email_triage_items")
      .select("id", { count: "exact", head: true })
      .not("summary", "is", null)
      .gte("created_at", startOfDay.toISOString());
    if (countErr) {
      throw new Error(`llm ceiling count failed: ${countErr.code ?? "unknown"}`);
    }
    if ((count ?? 0) >= EMAIL_TRIAGE_DAILY_LLM_CEILING) {
      reportSilentFallback(null, {
        feature: "email-triage",
        op: "llm-ceiling-deferred",
        message: "daily LLM summarization ceiling reached — row deferred",
        extra: { itemId },
      });
      return { kind: "deferred" };
    }

    const { text, html } = await fetchReceivedEmail(data.resendEmailId);
    const bodyText = text ?? normalizeEmailHtml(html ?? "");

    // Body-text statutory pass (deterministic, before any LLM involvement).
    const bodyRule = matchStatutoryBody(bodyText);
    if (bodyRule) {
      return {
        kind: "bodyStatutory",
        statutoryClass: bodyRule.statutoryClass,
        ruleId: bodyRule.ruleId,
      };
    }

    // Thin body + attachments: a PDF-only DSAR letter must not slip through
    // as a vague summary — escalate deterministically (second net).
    const attachments = data.attachments ?? [];
    if (isThinBody(bodyText) && attachments.length > 0) {
      const filenames = attachments.map((a) => a.filename).join(", ");
      return {
        kind: "legalReview",
        summary:
          `Attachment-only message (${filenames}) — ` +
          "rules did not match — verify against the Proton original",
      };
    }

    const { summary, mailClass } = await summarizeEmail({
      subject: data.subject,
      sender: data.sender,
      bodyText,
    });
    // THE BODY MUST NEVER BE A STEP RETURN VALUE: Inngest checkpoints
    // step.run returns in its run store — returning bodyText here would
    // persist the raw third-party email body and defeat the structural
    // parse-and-discard guarantee. Only {summary, mailClass} crosses out.
    return { kind: "summarized", summary, mailClass };
  });

  // ---- (5) finalize-row ------------------------------------------------------
  await step.run("finalize-row", async () => {
    const sb = createServiceClient();
    switch (fused.kind) {
      case "bodyStatutory":
        await applyFinalize(sb, itemId, {
          statutory_class: fused.statutoryClass,
          rule_id: fused.ruleId,
        });
        break;
      case "deferred":
        await applyFinalize(sb, itemId, {
          mail_class: "other",
          summary: "deferred — volume cap",
        });
        break;
      case "legalReview":
        await applyFinalize(sb, itemId, {
          mail_class: "legal-review",
          summary: fused.summary,
        });
        break;
      case "summarized":
        await applyFinalize(sb, itemId, {
          mail_class: fused.mailClass,
          summary: fused.summary,
        });
        break;
    }
    return { finalized: fused.kind };
  });

  // ---- (6) notify — LAST and separate ----------------------------------------
  await step.run("notify", () =>
    sendTriageNotification({
      ownerId,
      itemId,
      subject: data.subject,
      statutory: fused.kind === "bodyStatutory",
    }),
  );

  return { triaged: fused.kind };
}

export const emailOnReceived = inngest.createFunction(
  {
    id: "email-on-received",
    // Transient SDK/network only; bounds the accepted re-run of the one LLM
    // call inside the fused step (cfo-on-payment-failed.ts:260 precedent).
    retries: 1,
    // ops@ is an open ingress — anyone on the internet controls event
    // volume, and each non-statutory event costs a body fetch + an
    // Anthropic call. 60/hour smooths bursts far above legitimate
    // solo-operator volume (Inngest QUEUES, not drops, beyond the limit);
    // the daily LLM ceiling above caps total spend.
    throttle: { limit: 60, period: "1h" },
  },
  { event: EMAIL_INBOUND_RECEIVED_EVENT },
  emailOnReceivedHandler as unknown as Parameters<typeof inngest.createFunction>[2],
);
