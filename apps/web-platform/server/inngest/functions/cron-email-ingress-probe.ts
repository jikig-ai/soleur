// feat-operator-inbox-delegation Phase 6 — daily email-ingress liveness probe
// + retention sweep + statutory deadline-approach backstop.
//
// Step order is LOAD-BEARING (purge MUST precede the probe send): the
// Art. 5(1)(e) retention sweep must not be starved by a broken ingress chain
// — if the probe path is down for a week, old rows still get purged every
// day. The step breadcrumb (retention-purge vs send-probe/assert-probe-row)
// is what disambiguates purge-broken from ingress-broken in the Layer 1
// Sentry capture.
//
//   (1) step.run("retention-purge")  — purge_email_triage_items() RPC
//       (service-role only; GUC-bypass inside the RPC). Failure FAILS THE
//       RUN — no try/catch swallow.
//   (2) step.run("deadline-repin")   — deadline-approach ping for
//       acknowledged-but-unresolved statutory items: once at T-7d, then
//       DAILY from T-2d through overdue. Acknowledge is workflow state, not
//       legal resolution — without this mechanical backstop the UI copy's
//       distinction is just a claim. Clock derives from received_at + the
//       registry dueRule (no clock columns in the DB).
//   (3) step.run("send-probe")       — per-run unguessable token recorded in
//       probe_tokens BEFORE the Resend outbound send (an unrecorded token
//       would make our own probe classify 'other' as a forgeable shape);
//       marker email notifications@soleur.ai → ops@soleur.ai with subject
//       SOLEUR-PROBE-<uuid>.
//   (4) step.sleep("await-ingress", "15m") — the ingress SLA window.
//   (5) step.run("assert-probe-row") — same-run assertion: THIS run's token
//       must have landed as a mail_class='probe' row. Found → OK check-in;
//       absent → failed check-in + throw.
//
// `retries: 0` is pinned: under default Inngest retries a late-landing probe
// row turns the failed assertion into a retry-then-green run and the monitor
// NEVER alarms — silently degrading the 15-min SLA to 15-min-plus-retry-window.
//
// Probe identity is synthetic content from our own outbound address — no
// real-user data transits (sanctioned vs hr-dev-prd-distinct-supabase-projects;
// learning 2026-05-16 prod-synthetic-users). ZERO Anthropic involvement: the
// pipeline's probe rule short-circuits before the LLM, and this file never
// touches the summarizer.
//
// ADR-033 invariants: all outbound IO inside step.run (I1); operator-owned
// data only (I2); no subprocess (I3/I4); deterministic step returns (I5);
// emits no Inngest events (I6).

import { randomUUID } from "node:crypto";
import { Resend } from "resend";
import { inngest } from "@/server/inngest/client";
import { createServiceClient } from "@/lib/supabase/service";
import { infoSilentFallback, warnSilentFallback } from "@/server/observability";
import { notifyOfflineUser } from "@/server/notifications";
import {
  PROBE_MARKER_PREFIX,
  STATUTORY_RULES,
  computeDueDate,
  formatDueDate,
} from "@/lib/email-triage/statutory-rules";
import { postSentryHeartbeat, type HandlerArgs } from "./_cron-shared";

// =============================================================================
// Constants
// =============================================================================

export const SENTRY_MONITOR_SLUG = "cron-email-ingress-probe";

/** Ingress SLA: the probe row must land within this window of the send. */
export const PROBE_AWAIT_INGRESS_DURATION = "15m";

/** One-shot heads-up ping at exactly T-7 days (floor). */
export const DEADLINE_REPIN_HEADS_UP_DAY = 7;

/**
 * Daily ping from T-2 days through overdue (floor <= 2, including negative
 * values): the most dangerous bucket — an item at/past its statutory
 * deadline — must never be silent. An exact-day match would miss both
 * already-overdue items and any day skipped by a missed cron run.
 */
export const DEADLINE_REPIN_DANGER_THRESHOLD_DAYS = 2;

/**
 * Repin scan bound: only rows received within the last 60 days. Covers
 * every registry rule's due window (max: one calendar month ≈ 31 days)
 * plus a full month of overdue-daily-ping margin — and keeps the scan from
 * growing without bound as the table accretes acknowledged history.
 */
export const DEADLINE_REPIN_SCAN_WINDOW_DAYS = 60;

const DAY_MS = 24 * 60 * 60 * 1000;

// =============================================================================
// Types
// =============================================================================

// _cron-shared's HandlerArgs.step has only `run`; this cron is the first to
// sleep inside a run (the 15-min ingress window is INSIDE the run on purpose
// — same-run assertion, no previous-run bookkeeping, manual-trigger works
// standalone).
interface ProbeHandlerArgs {
  step: HandlerArgs["step"] & {
    sleep(name: string, duration: string): Promise<void>;
  };
  logger: HandlerArgs["logger"];
  /**
   * Present only on the manual-trigger event. Carries the operator RELEASE
   * verb (see `release_item_id` below); absent on the scheduled cron.
   */
  event?: { data?: Record<string, unknown> | null } | null;
}

interface AcknowledgedStatutoryRow {
  id: string;
  user_id: string | null;
  received_at: string;
  rule_id: string | null;
  statutory_class: string;
}

interface HandlerResult {
  ok: boolean;
  purged: unknown;
  repinged: number;
  /**
   * Dispatches skipped because a send-marker for this (item, tick) already
   * existed — i.e. a double-fire that did NOT reach the user (#6781). A
   * non-zero value here is the signal that a second scheduler is live.
   */
  repinSuppressed: number;
  /**
   * Set only when the manual-trigger carried `release_item_id`. `cleared` is
   * the number of markers deleted — 0 means there was nothing to release,
   * which is itself the answer to "why did nothing re-send?".
   */
  released: { itemId: string; cleared: number } | null;
  probeFound: boolean;
}

// =============================================================================
// Handler
// =============================================================================

export async function cronEmailIngressProbeHandler({
  step,
  logger,
  event,
}: ProbeHandlerArgs): Promise<HandlerResult> {
  // ---- (0) operator RELEASE verb (#6781) ------------------------------------
  // Reachable without SSH and without hand-written prod SQL, per
  // hr-no-ssh-fallback-in-runbooks / hr-never-label-any-step-as-manual-without:
  //
  //   soleur:trigger-cron  →  POST /api/internal/trigger-cron
  //   { "name": "cron/email-ingress-probe.manual-trigger",
  //     "data": { "release_item_id": "<uuid>" } }
  //
  // Clears that item's send markers so a later tick can re-send, for the case
  // where a dispatch was marked but demonstrably never delivered (the
  // `statutory-notify-zero-delivery` alarm is what surfaces that case).
  //
  // IMPORTANT — releasing only RE-ARMS; it does not force a send. The repin
  // predicate fires at exactly T-7, then daily from T-2 through overdue, so
  // days 6..3 fire nothing and a release inside that dead zone waits until
  // T-2. `released.rearmsNextTick` reports which case the operator is in.
  //
  // Validation mirrors cron-bug-fixer's event.data handling: the route is a
  // dumb pass-through, so the shape is enforced HERE.
  const rawRelease = event?.data?.release_item_id;
  const releaseItemId =
    typeof rawRelease === "string" &&
    /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(rawRelease)
      ? rawRelease
      : null;
  if (rawRelease !== undefined && rawRelease !== null && releaseItemId === null) {
    warnSilentFallback(null, {
      feature: "email-triage",
      op: "statutory-repin-release-invalid-id",
      message: "release_item_id present but not a uuid; ignoring",
    });
  }
  const released = releaseItemId
    ? await step.run("statutory-repin-release", async () => {
        const sb = createServiceClient();
        const { data, error } = await sb.rpc("purge_statutory_repin_send", {
          p_item_id: releaseItemId,
        });
        if (error) {
          // Fatal for THIS step only. An operator invoked a recovery action on
          // a statutory item; silently reporting success would be worse than
          // failing the run, because they would believe the item is re-armed.
          throw new Error(
            `purge_statutory_repin_send(release) failed: ${error.message ?? "unknown"}`,
          );
        }
        const cleared = typeof data === "number" ? data : 0;
        // WORM-adjacent: the parent ledger is evidence, so deleting send
        // evidence gets an audit line rather than vanishing.
        warnSilentFallback(null, {
          feature: "email-triage",
          op: "statutory-repin-released",
          message: "operator cleared statutory repin send-markers",
          extra: { itemId: releaseItemId, cleared },
        });
        return { itemId: releaseItemId, cleared };
      })
    : null;

  // ---- (1) retention purge FIRST (Art. 5(1)(e)) -----------------------------
  // MIXED failure contract — read this before adding a third RPC here.
  //   * purge_email_triage_items: FATAL. No try/catch; a failure must fail the
  //     whole run loudly. Layer 1 (sentry-correlation middleware) captures the
  //     terminal error with the retention-purge step breadcrumb, disambiguating
  //     purge-broken from ingress-broken without extra plumbing.
  //   * purge_statutory_repin_send (#6781): NON-FATAL. A stale marker suppresses
  //     nothing (the tick_key has already advanced), so failing the run here
  //     would starve the ingress liveness probe for a retention nicety.
  // Consequence: a successful step return does NOT mean both sweeps ran. The
  // marker sweep's outcome is carried in `statutory_repin_markers_purged`
  // (null = it failed) rather than in the step's success.
  const purged = await step.run("retention-purge", async () => {
    const sb = createServiceClient();
    const { data, error } = await sb.rpc("purge_email_triage_items");
    if (error) {
      throw new Error(
        `purge_email_triage_items RPC failed: ${error.message ?? "unknown"}`,
      );
    }
    // Send-marker sweep (#6781). Separate RPC, not folded into the one above:
    // replacing that function would drop its security attributes, and both
    // AP-018 guard tiers are blind to the drop. Retention here MUST be
    // explicit — statutory parent rows are evidence and are never purged, so
    // the marker's ON DELETE CASCADE effectively never fires.
    const { data: purgedMarkers, error: markerPurgeError } = await sb.rpc(
      "purge_statutory_repin_send",
    );
    if (markerPurgeError) {
      // Deliberately NOT fatal: a stale marker delays nothing and suppresses
      // nothing (the tick_key has already moved on). Failing the run here
      // would take the ingress liveness probe down for a retention nicety.
      warnSilentFallback(markerPurgeError, {
        feature: "email-triage",
        op: "statutory-repin-marker-purge-failed",
        message: "statutory repin send-marker retention sweep failed",
      });
    }
    return {
      ...(data as Record<string, number>),
      // The RPC returns its delete count; carrying it is the ONLY detection for
      // "the marker table grows without bound" (the sweep is non-fatal, so a
      // permanently-failing sweep is otherwise silent). Null when the sweep
      // errored — distinguishable from a real zero.
      statutory_repin_markers_purged:
        typeof purgedMarkers === "number" ? purgedMarkers : null,
    } as Record<string, number | null>;
  });

  // ---- (2) deadline-approach re-pin (T-7d / T-2d) ---------------------------
  const repin = await step.run("deadline-repin", async () => {
    const sb = createServiceClient();
    const scanFloor = new Date(
      Date.now() - DEADLINE_REPIN_SCAN_WINDOW_DAYS * DAY_MS,
    ).toISOString();
    const { data, error } = await sb
      .from("email_triage_items")
      .select("id, user_id, received_at, rule_id, statutory_class")
      .eq("status", "acknowledged")
      .not("statutory_class", "is", null)
      // Bounded scan — see DEADLINE_REPIN_SCAN_WINDOW_DAYS for why 60.
      .gte("received_at", scanFloor);
    if (error) {
      throw new Error(
        `deadline-repin select failed: ${error.code ?? "unknown"}`,
      );
    }

    // Computed ONCE, before the loop, and returned from the step so it is
    // checkpointed (mirrors send-probe's `sentAt`): one run is one logical
    // tick, so it gets one tick identity.
    //
    // Be honest about the midnight case rather than claiming it is a win. If a
    // run straddled UTC midnight, computing once keys the tail as D while the
    // next 06:00 tick keys D+1, so the tail could receive two sends a few hours
    // apart; a per-iteration date would key the tail D+1 and suppress it. The
    // reason to hoist is NOT that it handles the straddle better — it is that a
    // single run should not fragment into two tick identities, and a daily
    // 06:00 cron cannot straddle midnight in the first place. T9 pins the
    // one-identity property.
    //
    // Note the daily key's real protection window is the remainder of the UTC
    // day after the cron hour (~18h at 06:00), NOT 24h. That margin is a
    // property of the SCHEDULE, not of the guard — moving the cron to late
    // evening would shrink it toward zero.
    const runDateUtc = new Date().toISOString().slice(0, 10);

    let pinged = 0;
    let suppressed = 0;
    // Fail-open accounting, emitted ONCE after the loop (see M2 note above).
    let failOpenCount = 0;
    let failOpenFirstCode: string | undefined;
    // RECIPIENT-GRAIN CONSTRAINT (ADR-035; migration 135 header note 4).
    // statutory_repin_send is keyed (item_id, tick_key) — ITEM grain. That
    // equals RECIPIENT grain only because this loop pings `row.user_id` and
    // nobody else. Migration 111 already makes an item visible to every
    // workspace Owner, so this is a property of THIS SEND PATH, not a
    // structural guarantee. Before fanning out to multiple recipients, re-key
    // the marker table to recipient grain — otherwise the first Owner's marker
    // suppresses every other Owner and N-1 people get silence on a statutory
    // deadline while this step reports success. Test T12 is the tripwire.
    for (const row of (data ?? []) as AcknowledgedStatutoryRow[]) {
      // Anonymised rows (Art. 17) have user_id NULL — nobody to ping.
      if (!row.user_id) continue;
      const rule = STATUTORY_RULES.find((r) => r.ruleId === row.rule_id);
      if (!rule) {
        // rule_id is registry-pinned at finalize time; a miss means the
        // registry shrank under a live row — visible, not silently skipped.
        warnSilentFallback(null, {
          feature: "email-triage",
          op: "deadline-repin-unknown-rule",
          message: "acknowledged statutory row carries an unknown rule_id",
          extra: { itemId: row.id, ruleId: row.rule_id },
        });
        continue;
      }
      const due = computeDueDate(row.received_at, rule.dueRule);
      const daysUntilDue = Math.floor((due.getTime() - Date.now()) / DAY_MS);
      // Fire at exactly T-7 (heads-up), then DAILY from T-2 through overdue
      // — never silent in the most dangerous bucket (see constants above).
      if (
        daysUntilDue !== DEADLINE_REPIN_HEADS_UP_DAY &&
        daysUntilDue > DEADLINE_REPIN_DANGER_THRESHOLD_DAYS
      ) {
        continue;
      }

      // ---- idempotency guard (#6781) ------------------------------------
      // The tick identity is BRANCH-DERIVED because the repin has two
      // cadences. `daysUntilDue === 7` is a one-shot heads-up that spans a 24h
      // window (so a calendar date would let jitter produce two T-7 emails),
      // while the T-2-through-overdue band is genuinely daily (so a constant
      // would silence it after day 1). See migration 135 header note 3.
      const tickKey =
        daysUntilDue === DEADLINE_REPIN_HEADS_UP_DAY
          ? "headsup"
          : `daily:${runDateUtc}`;

      // Marker BEFORE dispatch: the insert is the durable record that this
      // send is claimed. Sending first would mean a crash in between re-sends
      // forever — the exact failure this guard exists to prevent.
      //
      // FAIL OPEN on everything except a clean 23505. Over-suppression is
      // strictly worse than duplication here: a duplicate statutory-deadline
      // email is annoying, but a suppressed one is SILENCE on a legal clock.
      // The T-7 arm makes this asymmetry sharper still — it is a structural
      // one-shot, so suppressing it does not delay the heads-up, it deletes
      // it (the next tick no longer satisfies the equality). And the likeliest
      // fail-open trigger, a 42P01 during the deploy window, is correlated
      // across every item in the band at once.
      try {
        // PLAIN insert, no `.select()` — the claimDedupRow idiom
        // (app/api/webhooks/github/route.ts). Deliberately NOT the
        // notifyInboxItem shape (`.select("id").single()`): that table has an
        // `id uuid PRIMARY KEY` to return, this one's PK is the composite
        // (item_id, tick_key) and it has NO `id` column at all. Asking
        // PostgREST for a RETURNING clause naming a column that does not exist
        // fails the whole statement with 42703 — which this guard would read
        // as a non-23505 error, fail open, and dispatch, forever, while never
        // writing a single marker. The guard would be inert in production and
        // green in every test that fakes the response.
        const { error: markerError } = await sb
          .from("statutory_repin_send")
          .insert({ item_id: row.id, tick_key: tickKey });
        if (markerError) {
          if (markerError.code === "23505") {
            // Already sent for this logical tick — a double-fire.
            suppressed += 1;
            continue;
          }
          // Aggregated, not emitted per item — see the sweep-complete emit
          // below. The likeliest trigger (a 42P01 during the deploy window) is
          // CORRELATED across every item in the band at once, so a per-item
          // warn produces one event per statutory row per day. That is the
          // shape that gets an alert rule muted, and a muted rule here would
          // hide exactly the class of defect this guard exists to surface.
          failOpenCount += 1;
          failOpenFirstCode ??= markerError.code ?? "unknown";
        }
      } catch (err) {
        // A THROWN rejection must not escape the iteration: under `retries: 0`
        // an escape would kill the whole run, taking the ingress liveness
        // probe (steps 3-5) down with it.
        failOpenCount += 1;
        failOpenFirstCode ??= "threw";
      }

      // Title carries only the registry-derived due string — never the
      // third-party subject (TR3 hygiene is moot for this synthetic title,
      // but keeping email content out of the ping keeps the surface uniform).
      //
      // #6798 (M2): the verb must be state-accurate. "approaching" on an item
      // that is already past due is exactly the over-claim #6798 is about, and
      // the date is COMPUTED from received_at (a best-effort backstop), so the
      // framing says so. The full not-legal-advice + clock-origin caveat rides
      // in the email body via `statutoryExcerpt` (D1/M1); the push stays a short
      // imperative pointer (its copy is CLO-adjudicated at ship, #6798 AC3).
      const dueStr = formatDueDate(row.received_at, rule.dueRule);
      const title =
        daysUntilDue >= 0
          ? `Statutory deadline (computed) approaching — ${dueStr}`
          : `Statutory deadline (computed) OVERDUE — ${dueStr}`;
      await notifyOfflineUser(row.user_id, {
        type: "email_triage",
        emailId: row.id,
        title,
        isStatutory: true,
        statutoryExcerpt: rule.catalogExcerpt,
      });
      pinged += 1;
    }

    // ONE warn for the whole run's fail-open population, at WARN level so it
    // clears the Vector >= 40 filter and reaches Better Stack as well as
    // Sentry. `pg_code` is promoted to a searchable tag by the observability
    // layer, so a 42P01 deploy race stays distinguishable from a real bug.
    if (failOpenCount > 0) {
      warnSilentFallback(
        { code: failOpenFirstCode },
        {
          feature: "email-triage",
          op: "deadline-repin-marker-insert-failed",
          message:
            "statutory repin send-marker insert failed; dispatched anyway (fail open)",
          extra: {
            failOpenCount,
            firstCode: failOpenFirstCode ?? null,
            scanned: (data ?? []).length,
            runDateUtc,
          },
        },
      );
    }

    // Per-run record via the observability layer, not a bare pino call. Be
    // precise about where this lands: Vector's allowlist keeps only
    // level_int >= 40 (see infra/vector.toml [transforms.app_container_warn_filter]),
    // and infoSilentFallback still logs at info — so this counter reaches
    // SENTRY only. Better Stack does not carry it. The WARN-level ops in this
    // file (marker-insert-failed, marker-purge-failed) clear the filter and do
    // reach both.
    infoSilentFallback(null, {
      feature: "email-triage",
      op: "deadline-repin-sweep-complete",
      message: "statutory deadline repin sweep finished",
      // Sentry indexes TAGS, not `extra` — a counter buried in `extra` cannot be
      // searched or alerted on, and every run groups under one constant message.
      // `suppressed > 0` is the only signal that a second scheduler is live and
      // double-firing (the #6781 condition), so it has to be queryable. Boolean,
      // not the count: tags must stay low-cardinality.
      tags: { repin_suppressed: suppressed > 0 ? "yes" : "no" },
      extra: {
        pinged,
        suppressed,
        scanned: (data ?? []).length,
        runDateUtc,
      },
    });

    return { pinged, suppressed, scanned: (data ?? []).length, runDateUtc };
  });

  // ---- (3) send probe -------------------------------------------------------
  const probe = await step.run("send-probe", async () => {
    const token = randomUUID();
    const sb = createServiceClient();

    // Record the token BEFORE sending: the pipeline finalizes
    // mail_class='probe' only on a token-match against a recent probe_tokens
    // row — an unrecorded token would classify our own probe as a forgeable
    // probe-shaped 'other' and warn.
    const { error: insertErr } = await sb
      .from("probe_tokens")
      .insert({ token });
    if (insertErr) {
      throw new Error(
        `probe_tokens insert failed: ${insertErr.code ?? "unknown"}`,
      );
    }

    const apiKey = process.env.RESEND_API_KEY;
    if (!apiKey) throw new Error("RESEND_API_KEY must be set");
    const resend = new Resend(apiKey);
    const subject = `${PROBE_MARKER_PREFIX}${token}`;
    const { error: sendErr } = await resend.emails.send({
      // House outbound conventions (server/notifications.ts).
      from: "Soleur <notifications@soleur.ai>",
      to: ["ops@soleur.ai"],
      subject,
      text: "synthetic ingress probe",
    });
    if (sendErr) {
      throw new Error(
        `probe send failed: ${(sendErr as { message?: string }).message ?? "unknown"}`,
      );
    }
    logger.info(
      { fn: "cron-email-ingress-probe" },
      "probe email dispatched",
    );
    // sentAt is checkpointed with the step return (deterministic on replay)
    // so the assert query below can be time-bounded to THIS run's send —
    // a top-of-handler timestamp would re-evaluate after the sleep on
    // Inngest's re-invocation model and miss the row.
    return { token, sentAt: new Date().toISOString() };
  });

  // ---- (4) ingress SLA window -----------------------------------------------
  await step.sleep("await-ingress", PROBE_AWAIT_INGRESS_DURATION);

  // ---- (5) same-run assertion -----------------------------------------------
  const found = await step.run("assert-probe-row", async () => {
    const sb = createServiceClient();
    // Index-friendly shape: equality on mail_class + a created_at lower
    // bound (this run's send time, minus 60s of app/DB clock-skew slack),
    // then token-exact match in JS over the tiny result set. A
    // leading-wildcard LIKE on subject can never use an index.
    const createdFloor = new Date(
      Date.parse(probe.sentAt) - 60_000,
    ).toISOString();
    const { data, error } = await sb
      .from("email_triage_items")
      .select("id, subject")
      .eq("mail_class", "probe")
      .gte("created_at", createdFloor);
    if (error) {
      throw new Error(
        `assert-probe-row select failed: ${error.code ?? "unknown"}`,
      );
    }
    const marker = `${PROBE_MARKER_PREFIX}${probe.token}`;
    const ok = ((data ?? []) as { id: string; subject: string | null }[]).some(
      (row) => row.subject?.includes(marker) ?? false,
    );
    await postSentryHeartbeat({
      ok,
      sentryMonitorSlug: SENTRY_MONITOR_SLUG,
      cronName: "cron-email-ingress-probe",
      logger,
    });
    if (!ok) {
      // Terminal under `retries: 0` BY DESIGN: with default retries Inngest
      // would re-run this step minutes later, the late-landing row would
      // satisfy the re-run, and the run would finish green — the monitor
      // would never alarm and the 15-min SLA would silently become
      // 15-min-plus-retry-window.
      throw new Error(
        "ingress probe row absent after 15m — email ingress chain is broken",
      );
    }
    return { found: true };
  });

  return {
    ok: true,
    purged,
    repinged: repin.pinged,
    repinSuppressed: repin.suppressed,
    released,
    probeFound: found.found,
  };
}

// =============================================================================
// Registration
// =============================================================================

export const cronEmailIngressProbe = inngest.createFunction(
  {
    id: "cron-email-ingress-probe",
    concurrency: [
      { scope: "fn", limit: 1 },
      // House cron-platform key kept: Inngest does NOT hold concurrency
      // slots while a run is step.sleep-ing, so the in-run 15-min window
      // cannot starve sibling crons.
      { scope: "account", key: '"cron-platform"', limit: 1 },
    ],
    // PINNED 0 — never raise: default retries silently convert a late probe
    // into a retry-then-green run (see assert-probe-row comment).
    retries: 0,
  },
  [
    { cron: "0 6 * * *" },
    { event: "cron/email-ingress-probe.manual-trigger" },
  ],
  cronEmailIngressProbeHandler as unknown as Parameters<
    typeof inngest.createFunction
  >[2],
);
