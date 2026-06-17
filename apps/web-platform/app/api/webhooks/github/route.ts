// PR-H (#3244) Phase 3 — GitHub App webhook ingress.
//
// Order of operations mirrors the canonical Stripe webhook at
// `app/api/webhooks/stripe/route.ts:71-159`. Comments are dense because
// the ordering is load-bearing: every deviation has caused a known
// data-loss class in industry literature.
//
//   Step 1: read raw body BEFORE JSON.parse (HMAC needs raw bytes).
//   Step 2: timingSafeEqual signature verify (NEVER `===`).
//           Fail-closed 401 on mismatch / missing secret.
//   Step 3: plain .insert() into processed_github_events (NO ON CONFLICT
//           — supabase-js returns data:null not [] on no-op, which makes
//           the affected-row gate unreliable; the Stripe path catches
//           PG_UNIQUE_VIOLATION instead — same idiom here).
//   Step 4: JSON.parse + switch on req.headers.get('x-github-event').
//   Step 5: resolve founderId via github_installation_id mapping; 404
//           if no founder owns this installation.
//   Step 6: isGranted(supabase, founderId, actionClass) — fail-closed
//           on no-grant (log + 200) OR DB-error (Sentry via isGranted + 200).
//   Step 7: inngest.send({ id: github-<deliveryId>, name, v: '1', data }).
//   Step 8: ON ANY ERROR in steps 5-7 AFTER step 3 INSERT succeeded:
//           DELETE processed_github_events row (releaseDedupRow mirror)
//           so the GitHub redelivery can be processed cleanly. Without
//           this, a transient inngest.send failure leaves the dedup
//           row, GitHub redelivers, the redelivery 200s as "duplicate",
//           the event is silently dropped.

import { createHmac, timingSafeEqual } from "node:crypto";
import { NextResponse } from "next/server";
import logger from "@/server/logger";
import * as Sentry from "@sentry/nextjs";
import { createServiceClient } from "@/lib/supabase/server";
import { PG_UNIQUE_VIOLATION } from "@/lib/postgres-errors";
import { isGranted } from "@/server/scope-grants/is-granted";
import type { ActionClass } from "@/server/scope-grants/action-class-map";
import { isReconcilablePush } from "@/server/webhook-push-reconcilable";
import { resolveSoloFounderForInstallation } from "@/server/resolve-founder-for-installation";
import {
  WORKSPACE_RECONCILE_REQUESTED_EVENT,
  WORKSPACE_RECONCILE_SCHEMA_V,
} from "@/server/session-sync";
import { sendInngestWithRetry } from "@/server/inngest/send-with-retry";

// Map x-github-event header to the action_class registered in
// scope_grants. `repository_advisory` and `secret_scanning_alert` both
// route to security.cve_alert (same draft surface). `workflow_run`
// routes to engineering.ci_failed only when the conclusion is
// 'failure' — the conclusion gate lives below near step 7 because we
// need the parsed body to read it.
const HEADER_TO_ACTION_CLASS: Record<string, ActionClass> = {
  pull_request: "engineering.pr_review_pending",
  workflow_run: "engineering.ci_failed",
  issues: "triage.p0p1_issue",
  repository_advisory: "security.cve_alert",
  secret_scanning_alert: "security.cve_alert",
};

function readWebhookSecret(): string | null {
  const v = process.env.GITHUB_APP_WEBHOOK_SECRET;
  return v && v.length > 0 ? v : null;
}

// GitHub's webhook payload limit is 25 MiB per docs.github.com (Webhooks
// reference). We cap at 1 MiB — realistic PR / issue / advisory bodies fit
// comfortably under 256 KiB; the cap is a DoS guard rail, not a feature
// limit. Larger payloads return 413 BEFORE signature verification — the
// signature is HMAC over the bytes, so we cannot verify a body we refused
// to read in full. Operator-facing: if a legitimate payload trips this,
// raise the cap explicitly rather than silently truncating.
const MAX_WEBHOOK_BODY_BYTES = 1_048_576;

// Constant-time signature check. GitHub sends `X-Hub-Signature-256:
// sha256=<hex>`. Returns true ONLY when both buffers are equal length
// and equal bytes; mismatches and length-mismatches both fail closed.
function verifySignature(
  rawBody: string,
  signatureHeader: string | null,
  secret: string,
): boolean {
  if (!signatureHeader || !signatureHeader.startsWith("sha256=")) return false;
  const received = signatureHeader.slice("sha256=".length);
  const computed = createHmac("sha256", secret).update(rawBody).digest("hex");
  // Byte-length guard — timingSafeEqual throws on length mismatch.
  if (received.length !== computed.length) return false;
  try {
    return timingSafeEqual(Buffer.from(received, "utf8"), Buffer.from(computed, "utf8"));
  } catch {
    return false;
  }
}

export async function POST(request: Request) {
  // Step 0: bounded read. Content-Length is advisory (GitHub sets it but
  // an attacker would not need to) — guard the actual byte length AFTER
  // .text() resolves. Reject 413 before allocating regex state for HMAC.
  const rawBody = await request.text();
  if (rawBody.length > MAX_WEBHOOK_BODY_BYTES) {
    return NextResponse.json({ error: "Payload too large" }, { status: 413 });
  }
  // Step 1: HMAC needs the exact bytes GitHub signed; any whitespace/
  // escape normalization breaks signing — do not parse before step 2.
  const signatureHeader = request.headers.get("x-hub-signature-256");
  const githubEvent = request.headers.get("x-github-event");
  const deliveryId = request.headers.get("x-github-delivery");

  // Step 2: signature verification. Fail-closed on missing secret
  // (production misconfiguration is a security incident, not a 200).
  const secret = readWebhookSecret();
  if (!secret) {
    logger.error(
      { feature: "github-webhook" },
      "GITHUB_APP_WEBHOOK_SECRET unset — fail-closed 500",
    );
    Sentry.captureMessage("GitHub webhook secret unset", {
      level: "error",
      tags: { feature: "github-webhook", op: "secret" },
    });
    return NextResponse.json({ error: "Server misconfigured" }, { status: 500 });
  }

  if (!verifySignature(rawBody, signatureHeader, secret)) {
    logger.error(
      { feature: "github-webhook", deliveryId },
      "GitHub webhook signature verification failed",
    );
    Sentry.captureMessage("GitHub webhook signature verification failed", {
      level: "error",
      tags: { feature: "github-webhook", op: "signature" },
      extra: { deliveryId },
    });
    return NextResponse.json({ error: "Invalid signature" }, { status: 401 });
  }

  if (!deliveryId) {
    return NextResponse.json({ error: "Missing x-github-delivery" }, { status: 400 });
  }
  if (!githubEvent) {
    return NextResponse.json({ error: "Missing x-github-event" }, { status: 400 });
  }

  const supabase = createServiceClient();

  // Step 3: delivery-id dedup. Plain .insert() — NO ON CONFLICT.
  // supabase-js .insert() returns data:null (not []) on
  // ON CONFLICT DO NOTHING without .select(); the affected-row gate
  // is unreliable. We catch PG_UNIQUE_VIOLATION (23505) → 200 instead,
  // mirroring the Stripe webhook (route.ts:117-127).
  const { error: dedupErr } = await supabase
    .from("processed_github_events")
    .insert({ delivery_id: deliveryId });

  if (dedupErr) {
    if (dedupErr.code === PG_UNIQUE_VIOLATION) {
      logger.info(
        { deliveryId, githubEvent },
        "GitHub webhook replay — delivery_id already processed, skipping",
      );
      return NextResponse.json({ received: true });
    }
    logger.error(
      { err: dedupErr, deliveryId },
      "GitHub webhook dedup insert failed — returning 500",
    );
    Sentry.captureException(dedupErr, {
      tags: { feature: "github-webhook", op: "dedup-insert" },
      extra: { deliveryId, githubEvent },
    });
    return NextResponse.json({ error: "DB error" }, { status: 500 });
  }

  // releaseDedupRow mirror of Stripe's pattern at route.ts:144-159.
  // On any 5xx error in steps 5-7 below, this MUST run before return
  // so the GitHub redelivery is processed (not silently dropped as a
  // duplicate). Silently tolerates a DELETE failure — the redelivery
  // is the correction mechanism.
  async function releaseDedupRow(): Promise<void> {
    const { error } = await supabase
      .from("processed_github_events")
      .delete()
      .eq("delivery_id", deliveryId);
    if (error) {
      logger.error(
        { err: error, deliveryId },
        "GitHub webhook: failed to release dedup row on handler error — redelivery will be short-circuited",
      );
      Sentry.captureException(error, {
        tags: { feature: "github-webhook", op: "dedup-release" },
        extra: { deliveryId },
      });
    }
  }

  // Step 4: parse body (signature verified, dedup committed).
  let body: {
    installation?: { id?: number };
    action?: string;
    workflow_run?: { conclusion?: string | null };
    ref?: string;
    before?: string;
    after?: string;
    repository?: { default_branch?: string; full_name?: string };
  };
  try {
    body = JSON.parse(rawBody);
  } catch (err) {
    logger.error({ err, deliveryId }, "GitHub webhook: body is not valid JSON");
    await releaseDedupRow();
    return NextResponse.json({ error: "Malformed body" }, { status: 400 });
  }

  const installationId = body.installation?.id;
  if (typeof installationId !== "number") {
    logger.warn(
      { deliveryId, githubEvent },
      "GitHub webhook: no installation.id in payload — ignoring",
    );
    // No installation to attribute → drop and DO NOT release dedup
    // (any redelivery would also have no installation; let the row
    // age out via autovacuum).
    return NextResponse.json({ received: true });
  }

  // workflow_run gate: only `failure` conclusions are actionable.
  if (githubEvent === "workflow_run" && body.workflow_run?.conclusion !== "failure") {
    // Skip silently — neither a 4xx nor a draft. The dedup row stays
    // so a future legitimate failure replay (same delivery_id) is
    // 200-deduped; new delivery_ids for the same workflow_run land
    // here on their own merits.
    return NextResponse.json({ received: true });
  }

  // Step 5: founder attribution. Split by event type (ADR-044 Amendment
  // 2026-06-17b, CTO Option C).
  //
  // The install→founder reverse-lookup formerly read the credential column
  // off `users` (migration 011) gated by the mig-052 partial-UNIQUE. PR-2b
  // drops that column AND its UNIQUE index; the lookup now resolves through
  // `workspaces` (NON-UNIQUE, one install → N workspaces), so a single-row
  // `.maybeSingle()` is structurally invalid. Resolution branches:
  //
  //   - PUSH (Step 5.5): the reconcile fan-out re-derives workspaces from
  //     (installation_id, repo_url), so no per-event founder lookup is
  //     needed; `founderId` was vestigial in the payload and is dropped.
  //   - NON-PUSH (before Step 6): the solo-workspace self-join resolver
  //     yields exactly ONE founder, with a `>1` fail-closed branch (the
  //     defense the dropped UNIQUE used to give structurally).

  // Step 5.5 (#4224): push-event reconcile dispatch. Branches BEFORE the
  // scope-grant gate because workspace reconciliation is structurally NOT
  // an ActionClass (ADR-034) — the GitHub App install IS the consent
  // surface (Art. 6(1)(b)) per CLO carry-forward in the brainstorm. The
  // dispatched Inngest function handles concurrency coalescing per
  // installation_id via CEL. See plan
  // knowledge-base/project/plans/2026-05-21-feat-workspace-reconciliation-with-main-plan.md.
  if (githubEvent === "push") {
    const reconcilable = isReconcilablePush(body);
    if (!reconcilable.ok) {
      logger.warn(
        { deliveryId, reason: reconcilable.reason, ref: body.ref },
        "GitHub webhook push: not reconcilable — drop",
      );
      return NextResponse.json({ received: true });
    }
    try {
      const { inngest } = await import("@/server/inngest/client");
      await sendInngestWithRetry(
        () =>
          inngest.send({
            id: `github-${deliveryId}`,
            name: WORKSPACE_RECONCILE_REQUESTED_EVENT,
            v: WORKSPACE_RECONCILE_SCHEMA_V,
            data: {
              installationId,
              deliveryId,
              defaultBranch: reconcilable.defaultBranch,
              headSha: reconcilable.headSha,
              beforeSha: reconcilable.beforeSha,
              // ADR-044: bare owner/repo slug. The reconcile composes
              // https://github.com/<fullName> and matches workspaces by
              // normalized repo_url (fan-out). v=3 (SCHEMA_V) — `founderId`
              // dropped (vestigial; the consumer re-derives workspaces).
              fullName: reconcilable.fullName,
              pushReceivedAt: Date.now(),
            },
          }),
        { feature: "github-webhook", deliveryId },
      );
    } catch (err) {
      logger.error(
        { err, deliveryId },
        "GitHub webhook push: inngest.send failed — releasing dedup row",
      );
      Sentry.captureException(err, {
        tags: { feature: "github-webhook", op: "inngest-send-push" },
        extra: { deliveryId, installationId },
      });
      await releaseDedupRow();
      return NextResponse.json({ error: "Dispatch failed" }, { status: 500 });
    }
    return NextResponse.json({ received: true });
  }

  // Non-push founder resolution: solo-workspace self-join (CTO Option C).
  // Discriminated union — 0/1/>1/db-error each branch distinctly. The `>1`
  // (ambiguous) branch is the load-bearing fail-closed defense: dropping a
  // re-drivable event is strictly safer than misattributing an action /
  // installation-token to the WRONG founder (the brand-survival hazard).
  const founderResolution = await resolveSoloFounderForInstallation(
    installationId,
    supabase,
  );
  if (founderResolution.kind === "db-error") {
    logger.error(
      { installationId, deliveryId },
      "GitHub webhook: founder resolution DB error",
    );
    Sentry.captureException(new Error("founder resolution db error"), {
      tags: { feature: "github-webhook", op: "founder-resolve" },
      extra: { installationId, deliveryId },
    });
    await releaseDedupRow();
    return NextResponse.json({ error: "DB error" }, { status: 500 });
  }
  if (founderResolution.kind === "ambiguous") {
    // >1 solo workspaces share this installation — invariant drift (two
    // users + same fork, OR a connect/reconcile bug duplicating the install
    // onto a second solo row). The dropped mig-052 UNIQUE made this
    // unreachable; we now FAIL CLOSED: do NOT pick one founder, do NOT
    // dispatch, do NOT scope-check. Page on this — it is a STANDING state
    // (every event drops until the duplicate solo row is removed; GitHub
    // does not retry 4xx and releaseDedupRow does not replay).
    Sentry.captureException(
      new Error("ambiguous founder for installation (>1 solo workspaces)"),
      {
        level: "error",
        tags: { feature: "github-webhook", op: "founder-ambiguous" },
        extra: { installationId, deliveryId, count: founderResolution.count },
      },
    );
    await releaseDedupRow();
    return NextResponse.json(
      { error: "Ambiguous founder for installation" },
      { status: 404 },
    );
  }
  if (founderResolution.kind === "none") {
    logger.warn(
      { installationId, deliveryId, githubEvent },
      "GitHub webhook: no founder for installation_id — 404",
    );
    // 404 mirrors GitHub's expectation that the receiver advertises
    // "not for me"; GitHub will not retry 4xx. Release the dedup row
    // so a future install→delivery on the same delivery_id (unlikely
    // but legitimate) is not silently short-circuited (Kieran #1).
    await releaseDedupRow();
    return NextResponse.json({ error: "No founder for installation" }, { status: 404 });
  }
  // kind === "found": founderId is byte-equal to the resolver's `w.id`
  // (== owner users.id by the solo invariant) and flows unchanged into
  // isGranted (Step 6) + the dispatch payload (Step 7).
  const founderId = founderResolution.founderId;

  // Step 6: scope-grant gate. fail-closed (200 without dispatch) on
  // no-grant OR DB error. The DB-error case mirrors the silent-fallback
  // contract in cq-silent-fallback-must-mirror-to-sentry — surfaces to
  // Sentry but does NOT propagate a 5xx (GitHub would retry forever and
  // the founder's scope_grant state didn't change between retries).
  const actionClass = HEADER_TO_ACTION_CLASS[githubEvent];
  if (!actionClass) {
    logger.info(
      { githubEvent, deliveryId },
      "GitHub webhook: unsupported event — ignoring",
    );
    return NextResponse.json({ received: true });
  }

  const grant = await isGranted(supabase, founderId, actionClass);
  if (!grant) {
    logger.info(
      { founderId, actionClass, deliveryId },
      "GitHub webhook: no active scope_grant — skip inngest.send (fail-closed)",
    );
    return NextResponse.json({ received: true });
  }

  // Step 7: inngest.send. Single event-id namespace per delivery — the
  // Inngest 24h `event.id` dedup window + our DB dedup combine to give
  // exactly-once dispatch up to GitHub's redelivery limit.
  try {
    const { inngest } = await import("@/server/inngest/client");
    // Redact rawBody before forwarding — the self-hosted Inngest event store
    // retains payloads with NO automatic deletion (until operator-side store
    // maintenance; ~24h is only the event-id dedup window — see DPD §2.3(o))
    // and is a third PII surface beyond the messages row
    // and the audit ledger. redactGithubSourcedText regexes are
    // JSON-syntax-safe (they match PII shapes inside string values; quote
    // and brace characters are not in any pattern). Belt-and-suspenders
    // with the INSERT-time redaction in github-on-event.ts.
    const { redactGithubSourcedText } = await import("@/lib/safety/redaction-allowlist");
    const redactedRawBody = redactGithubSourcedText(rawBody);
    await sendInngestWithRetry(
      () =>
        inngest.send({
          id: `github-${deliveryId}`,
          name: actionClass,
          v: "1",
          data: {
            founderId,
            installationId,
            deliveryId,
            githubEvent,
            action: body.action ?? null,
            tier: grant.tier,
            rawBody: redactedRawBody,
          },
        }),
      { feature: "github-webhook", deliveryId },
    );
  } catch (err) {
    logger.error(
      { err, deliveryId, actionClass },
      "GitHub webhook: inngest.send failed — releasing dedup row",
    );
    Sentry.captureException(err, {
      tags: { feature: "github-webhook", op: "inngest-send" },
      extra: { deliveryId, actionClass, founderId },
    });
    await releaseDedupRow();
    return NextResponse.json({ error: "Dispatch failed" }, { status: 500 });
  }

  return NextResponse.json({ received: true });
}
