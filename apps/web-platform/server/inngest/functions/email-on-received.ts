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
// per-function captureException needed for terminal errors. Statutory
// notify failures are mirrored to Sentry INSIDE notifications.ts
// (mirrorStatutoryNotifyFailure, tags feature=email-triage /
// op=statutory-notify-failed) — the single mirror lives there; this module
// adds no second catch around notifyOfflineUser (which never throws: its
// body is wrapped in notifications.ts).
//
// TR3: no log/Sentry call carries body, subject, or sender values —
// including Error message strings. DB column writes (sender/subject/summary)
// are the sanctioned store. The Inngest-checkpoint ban applies to the RAW
// BODY only: it must never be a step return value or event field
// (parse-and-discard); summary/subject/sender DO cross step boundaries by
// design and are disclosed (DPIA — Inngest run-store line).

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
} from "@/lib/email-triage/statutory-rules";
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

/**
 * Degraded-finalize sentinel (#5468). When a body fetch or the summarizer
 * throws on the FINAL Inngest attempt, the row lands degraded (mail_class
 * 'other') with THIS fixed summary instead of stranding at a permanent NULL.
 *
 * The prefix is the single source of truth: it is load-bearing in TWO places —
 * the finalize value below AND the daily-LLM-ceiling exclusion `LIKE` (a
 * degraded row cost zero Anthropic spend, so it must NOT inflate the cap). The
 * ceiling query builds its pattern from `${PREFIX}%` so the two can never drift.
 */
const EMAIL_TRIAGE_DEGRADED_SUMMARY_PREFIX = "fetch/summarize failed";
export const EMAIL_TRIAGE_DEGRADED_SUMMARY =
  `${EMAIL_TRIAGE_DEGRADED_SUMMARY_PREFIX} — verify against the Proton original`;

/** Statutory ping coalescing bucket — see sendTriageNotification. */
const STATUTORY_COALESCE_MS = 10 * 60 * 1000;

/** Probe tokens are only honored within 24h of minting (probe cron cadence). */
const PROBE_TOKEN_MAX_AGE_MS = 24 * 60 * 60 * 1000;

/** Owner-validation memo TTL — the owner env is static; re-validating with
 * 2 queries per email is pure overhead. 1h bounds staleness if the owner
 * row is ever deleted/demoted. */
const OWNER_VALIDATION_TTL_MS = 60 * 60 * 1000;

type ServiceClient = ReturnType<typeof createServiceClient>;

/** Route-emitted event data: sender is null (never "") when data.from was
 * missing/empty — local widening mirrored in resend-inbound/route.ts; fold
 * into EmailInboundReceivedData when the events module can be touched. */
type InboundEventData = EmailInboundReceivedData;

interface HandlerArgs {
  event: { data: InboundEventData };
  step: { run<T>(name: string, cb: () => Promise<T>): Promise<T> };
  logger?: {
    info: (...args: unknown[]) => void;
    warn: (...args: unknown[]) => void;
    error: (...args: unknown[]) => void;
  };
  // Inngest's zero-indexed retry attempt + (optional) max attempt count, off
  // BaseContext (the handler arg) — NOT onFunctionRun ctx, which is
  // InitialRunInfo and lacks `attempt` (learning 2026-06-16). Optional so the
  // legacy/eager test shape (neither passed) reads attempt=0/maxAttempts=1 →
  // isFinalAttempt=true, identical to the pre-degraded-tail behavior. Shape
  // copied verbatim from _cron-shared.ts:107-108.
  attempt?: number;
  maxAttempts?: number;
}

type FusedOutcome =
  | { kind: "deferred" }
  | { kind: "bodyStatutory"; statutoryClass: string; ruleId: string }
  | { kind: "legalReview"; summary: string }
  | { kind: "summarized"; summary: string; mailClass: MailClass }
  // #5468: a body-fetch or summarizer egress drop on the FINAL attempt. The row
  // degrades to mail_class 'other' + the fixed sentinel summary instead of
  // stranding at NULL. `bodyUnavailable` distinguishes the two sub-causes for
  // the notify grade: a body-FETCH failure (true) means the body never arrived
  // so matchStatutoryBody could not run — a possibly-body-only DSAR → notify
  // statutory-grade; a summarizer-only failure (false) means the body WAS
  // fetched and the deterministic statutory pass already ran clean → ordinary.
  | { kind: "fetchFailed"; bodyUnavailable: boolean };

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
    // Adopt-race loser: two concurrent runs can both adopt the same
    // unfinalized stub; the WORM freeze trigger raises P0001 for the
    // second finalize. Re-select — if the row is already finalized the
    // race winner did the work and this run short-circuits gracefully
    // instead of dying as an unhandled P0001.
    if (error.code === "P0001") {
      const { data: row, error: selErr } = await sb
        .from("email_triage_items")
        .select("mail_class, statutory_class")
        .eq("id", itemId)
        .maybeSingle();
      const existing = row as {
        mail_class: string | null;
        statutory_class: string | null;
      } | null;
      if (
        !selErr &&
        existing &&
        (existing.mail_class !== null || existing.statutory_class !== null)
      ) {
        return; // already finalized by the race winner — nothing to do
      }
    }
    // Code only — never row values (TR3).
    throw new Error(`email_triage finalize failed: ${error.code ?? "unknown"}`);
  }
}

/**
 * Degraded finalize (#5468, AC7). Writes mail_class='other' + the degraded
 * sentinel ONLY while BOTH one-time-set class columns are still NULL.
 *
 * `statutory_class` and `mail_class` are INDEPENDENT one-time-set columns
 * (mig 102:189-203): a concurrent statutory finalize sets statutory_class
 * WITHOUT raising P0001 against this mail_class write, so applyFinalize's
 * P0001 re-select does NOT cover this race. The `.is(...null)` WHERE guard
 * makes a degraded write a no-op (zero rows) when a sibling already classed
 * the row FIRST — `written:false` then signals "a sibling won; suppress the
 * notify".
 *
 * The guard serializes only the statutory-finalize-FIRST ordering. In the
 * reverse ordering (degraded write commits first, then a sibling statutory
 * finalize lands its disjoint `statutory_class` write — which the WORM trigger
 * permits, NULL→value), the row ends BENIGNLY co-classed `mail_class='other'`
 * AND `statutory_class='dsar'`: the statutory signal is never lost, the row is
 * retained under the `statutory_class IS NOT NULL` carve-out, and the statutory
 * run still pings statutory-grade. A degraded `summary` sitting beside a correct
 * `statutory_class` is the only artifact — acceptable at single-user threshold.
 * Returns whether the degraded row was actually written.
 */
async function applyDegradedFinalize(
  sb: ServiceClient,
  itemId: string,
): Promise<{ written: boolean }> {
  const { data, error } = await sb
    .from("email_triage_items")
    .update({
      mail_class: "other",
      summary: EMAIL_TRIAGE_DEGRADED_SUMMARY,
    })
    .eq("id", itemId)
    .is("statutory_class", null)
    .is("mail_class", null)
    .select("id");
  if (error) {
    // Code only — never row values (TR3).
    throw new Error(
      `email_triage degraded finalize failed: ${error.code ?? "unknown"}`,
    );
  }
  const rows = (data as { id: string }[] | null) ?? [];
  return { written: rows.length > 0 };
}

/**
 * Step (6) body. Statutory pings coalesce on WALL-CLOCK 10-minute buckets:
 * the ping is suppressed only when another statutory row (excluding this
 * one) was created within the CURRENT bucket (created_at >=
 * floor(now / 10min)). Anchoring on the bucket — not on "any row in the
 * last 10 minutes" — means a sustained <10-min drip still pings once per
 * bucket (max 1 ping / 10 min, the actual contract) instead of pinging
 * once and then being chain-suppressed forever. The lookup is fail-OPEN:
 * on a query error we ping (a duplicate ping is noise; a silently missed
 * statutory ping is an eaten Art. 12 clock). When pinging with N>1
 * unacknowledged statutory items, the title appends " (+N-1 more)".
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
    const bucketStart = new Date(
      Math.floor(Date.now() / STATUTORY_COALESCE_MS) * STATUTORY_COALESCE_MS,
    ).toISOString();
    const { data: recent, error: recentErr } = await sb
      .from("email_triage_items")
      .select("id")
      .eq("user_id", args.ownerId)
      .not("statutory_class", "is", null)
      .neq("id", args.itemId)
      .gte("created_at", bucketStart)
      .limit(1);
    if (!recentErr && recent && recent.length > 0) {
      return { pinged: false };
    }

    const { count } = await sb
      .from("email_triage_items")
      .select("id", { count: "exact", head: true })
      .eq("user_id", args.ownerId)
      .not("statutory_class", "is", null)
      .eq("status", "new");
    const unacknowledged = count ?? 1;
    if (unacknowledged > 1) {
      title = `${title} (+${unacknowledged - 1} more)`;
    }
  }

  // No try/catch here: notifyOfflineUser never throws (its body is wrapped
  // in notifications.ts) and statutory failures are mirrored to Sentry
  // there (mirrorStatutoryNotifyFailure) — a second catch would be dead
  // code and a duplicate-mirror hazard.
  await notifyOfflineUser(args.ownerId, {
    type: "email_triage",
    emailId: args.itemId, // DB uuid ONLY — lands in href unescaped.
    title,
    isStatutory: args.statutory,
  });
  return { pinged: true };
}

// Module-level owner-validation memo (P9f): the owner env is static, so
// re-running the users + workspace_members checks on every email is pure
// overhead. Keyed on ownerId (an env rotation invalidates immediately) with
// a 1h TTL bound on staleness.
let ownerValidationMemo: { ownerId: string; validatedAt: number } | null = null;

/** Test-only: clear the owner-validation memo between cases. */
export function resetOwnerValidationMemo(): void {
  ownerValidationMemo = null;
}

export async function emailOnReceivedHandler({
  event,
  step,
  attempt,
  maxAttempts,
}: HandlerArgs): Promise<Record<string, unknown>> {
  const data = event.data;

  // Final-attempt gate for the degraded-finalize tail (#5468). With retries: 1
  // (below) maxAttempts is statically 2, so attempts 0 and 1 → final is index 1.
  // Predicate copied verbatim from cron-stale-deferred-scope-outs.ts:358. The
  // `?? 1` fail-safe collapses to always-final if a fire ever omits maxAttempts
  // — that degrades to "degrade on first failure" (over-eager), never to
  // masking a recoverable transient by writing a degraded row AND swallowing
  // the retry (the genuinely dangerous direction).
  const isFinalAttempt = (attempt ?? 0) >= ((maxAttempts ?? 1) - 1);

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
    // Memoized per ownerId with a 1h TTL (P9f) — the env is static and two
    // queries per email is pure overhead.
    const memoFresh =
      ownerValidationMemo !== null &&
      ownerValidationMemo.ownerId === ownerId &&
      Date.now() - ownerValidationMemo.validatedAt < OWNER_VALIDATION_TTL_MS;
    if (!memoFresh) {
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
      ownerValidationMemo = { ownerId, validatedAt: Date.now() };
    }

    // claim_key dedups redeliveries of the SAME inbound mail. RFC 5322
    // Message-ID is optional AND sender-controlled — an attacker who knows
    // (or guesses) a Message-ID could otherwise pre-claim it and suppress a
    // victim's mail. Scoping the key by sender confines that suppression to
    // the attacker's own sender identity; no sender or no Message-ID →
    // fall back to the Resend delivery id (unique per delivery; Postgres
    // UNIQUE treats NULLs as distinct, hence a non-NULL COALESCE).
    const claimKey =
      data.messageId && data.sender
        ? `${data.sender}|${data.messageId}`
        : `resend:${data.resendEmailId}`;

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
    sender: data.sender ?? "",
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
    // Owner-scoped, and only rows that actually represent LLM spend count:
    // probe rows and "deferred — volume cap" sentinel rows carry a non-NULL
    // summary with zero Anthropic involvement. (`.neq("mail_class","probe")`
    // is 3VL-safe here: a non-NULL summary implies a non-NULL mail_class on
    // every non-statutory finalize path.) Thin-body legal-review rows DO
    // still count — a conservative overcount, which is the safe direction
    // for spend.
    const startOfDay = new Date();
    startOfDay.setUTCHours(0, 0, 0, 0);
    const { count, error: countErr } = await sb
      .from("email_triage_items")
      .select("id", { count: "exact", head: true })
      .eq("user_id", ownerId)
      .not("summary", "is", null)
      .neq("mail_class", "probe")
      .not("summary", "like", "deferred — volume cap%")
      // #5468: degraded-finalize sentinel rows carry a non-NULL summary but
      // cost zero Anthropic spend — exclude them or they falsely inflate the
      // cap and defer real mail. Pattern derived from the sentinel prefix so
      // the exclusion can never drift from the finalize value (AC8).
      .not("summary", "like", `${EMAIL_TRIAGE_DEGRADED_SUMMARY_PREFIX}%`)
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

    // Body fetch — INDEPENDENT catch (not the whole step) so the deterministic
    // statutory body pass below always wins on a summarizer-only failure (AC5).
    // A body-FETCH failure means the body never arrived: matchStatutoryBody
    // could not run, so a possibly-body-only DSAR was never scanned →
    // bodyUnavailable:true drives a statutory-grade notify downstream.
    let text: string | null;
    let html: string | null;
    try {
      ({ text, html } = await fetchReceivedEmail(data.resendEmailId));
    } catch (err) {
      // Non-final attempt: re-throw the WHOLE step so Inngest retries — never
      // run-and-no-op a degraded write (Inngest memoizes step results across
      // retries; an emptied step would replay on the next attempt and mask
      // recovery — learning 2026-06-12).
      if (!isFinalAttempt) throw err;
      reportSilentFallback(err, {
        feature: "email-triage",
        op: "fetch-summarize-degraded",
        message:
          "inbound body fetch failed on final attempt — degraded finalize",
        extra: { itemId },
      });
      return { kind: "fetchFailed", bodyUnavailable: true };
    }
    // Use the text part only when it carries actual content — an
    // empty/whitespace-only text part must not bypass HTML normalization
    // (an HTML-only DSAR with text:"" would otherwise skip the body pass).
    const bodyText =
      text && text.trim().length > 0 ? text : normalizeEmailHtml(html ?? "");

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

    // Summarizer (LLM) — INDEPENDENT catch. The body WAS fetched and the
    // deterministic statutory pass already ran clean (no bodyRule above), so a
    // summarizer-only degrade notifies ORDINARY (bodyUnavailable:false).
    let summary: string;
    let mailClass: MailClass;
    try {
      ({ summary, mailClass } = await summarizeEmail({
        subject: data.subject,
        sender: data.sender ?? "",
        bodyText,
      }));
    } catch (err) {
      if (!isFinalAttempt) throw err;
      reportSilentFallback(err, {
        feature: "email-triage",
        op: "fetch-summarize-degraded",
        message: "summarizer failed on final attempt — degraded finalize",
        extra: { itemId },
      });
      return { kind: "fetchFailed", bodyUnavailable: false };
    }
    // THE BODY MUST NEVER BE A STEP RETURN VALUE: Inngest checkpoints
    // step.run returns in its run store — returning bodyText here would
    // persist the raw third-party email body and defeat the structural
    // parse-and-discard guarantee. Only {summary, mailClass} crosses out.
    return { kind: "summarized", summary, mailClass };
  });

  // ---- (5) finalize-row ------------------------------------------------------
  const finalize = await step.run(
    "finalize-row",
    async (): Promise<{ finalized: FusedOutcome["kind"]; degradedWritten: boolean }> => {
      const sb = createServiceClient();
      switch (fused.kind) {
        case "bodyStatutory":
          await applyFinalize(sb, itemId, {
            statutory_class: fused.statutoryClass,
            rule_id: fused.ruleId,
          });
          return { finalized: fused.kind, degradedWritten: false };
        case "deferred":
          await applyFinalize(sb, itemId, {
            mail_class: "other",
            summary: "deferred — volume cap",
          });
          return { finalized: fused.kind, degradedWritten: false };
        case "legalReview":
          await applyFinalize(sb, itemId, {
            mail_class: "legal-review",
            summary: fused.summary,
          });
          return { finalized: fused.kind, degradedWritten: false };
        case "summarized":
          await applyFinalize(sb, itemId, {
            mail_class: fused.mailClass,
            summary: fused.summary,
          });
          return { finalized: fused.kind, degradedWritten: false };
        case "fetchFailed": {
          // Race-guarded degraded write (AC7): a no-op (zero rows) means a
          // sibling statutory finalize already classed the row — the winner
          // pinged statutory-grade, so the notify below must be suppressed.
          const { written } = await applyDegradedFinalize(sb, itemId);
          return { finalized: fused.kind, degradedWritten: written };
        }
      }
    },
  );

  // ---- (6) notify — LAST and separate ----------------------------------------
  // Degraded race-loss: a sibling statutory finalize won the disjoint-column
  // race (degraded write hit zero rows). The winner already notified
  // statutory-grade — suppress the duplicate degraded ping entirely (AC7).
  if (fused.kind === "fetchFailed" && !finalize.degradedWritten) {
    return { triaged: fused.kind, degradedRaceLost: true };
  }
  await step.run("notify", () =>
    sendTriageNotification({
      ownerId,
      itemId,
      subject: data.subject,
      // A body-fetch failure could not rule out a body-only DSAR
      // (matchStatutoryBody never ran) → statutory-grade ping (Phase 3 P1).
      statutory:
        fused.kind === "bodyStatutory" ||
        (fused.kind === "fetchFailed" && fused.bodyUnavailable),
    }),
  );

  return { triaged: fused.kind };
}

export const emailOnReceived = inngest.createFunction(
  {
    id: "email-on-received",
    // Transient SDK/network only; bounds the accepted re-run of the one LLM
    // call inside the fused step (cfo-on-payment-failed.ts:260 precedent).
    // retries: 1 ⇒ maxAttempts = 2 (attempts 0 and 1; final is index 1). The
    // #5468 degraded-finalize tail keys off this: a fetch/summarizer throw
    // re-throws on attempt 0 (Inngest retries) and degrades only on attempt 1.
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
