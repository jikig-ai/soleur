// PR-H (#3244) Phase 3 — GitHub App webhook ingress.
//
// This route preserves TWO load-bearing idioms from the canonical Stripe
// webhook (`app/api/webhooks/stripe/route.ts`): the PG_UNIQUE_VIOLATION→200
// replay short-circuit, and releaseDedupRow()-on-dispatch-failure so a
// transient inngest.send failure is re-driven by GitHub's redelivery (not
// silently swallowed as a "duplicate").
//
// It INTENTIONALLY DIVERGES from Stripe's dedup-FIRST ordering (2026-06-30,
// ADR-036 amendment). Stripe writes its dedup row before its handler switch
// because every Stripe event type is actioned and volume is ~1 row/day. The
// GitHub stream is dominated by a guaranteed no-op (`workflow_run` with
// conclusion !== 'failure'); writing a dedup row for EVERY delivery made that
// single INSERT 63% of the production database's WAL
// (pg_stat_statements.wal_bytes on project ifsccnjhymdmidffkzhl) — the
// Disk-IO-budget consumer this reorder removes. So the dedup INSERT now runs
// DROP-BEFORE-DEDUP: only on a delivery that will actually dispatch, immediately
// before each inngest.send, AFTER all drop-filters. The invariant that survives
// is "INSERT strictly before side-effect dispatch" (concurrency-safe via the
// delivery_id unique constraint). Drops never write a row.
//
//   Step 1: read raw body BEFORE JSON.parse (HMAC needs raw bytes).
//   Step 2: timingSafeEqual signature verify (NEVER `===`).
//           Fail-closed 401 on mismatch / missing secret.
//   Step 4: JSON.parse + drop-filters. (There is no longer a "Step 3" dedup
//           INSERT here — it moved to Step 7-pre.) installation check,
//           workflow_run conclusion gate, push reconcilability — each drop
//           returns its existing 200/4xx WITHOUT writing a dedup row.
//   Step 5: resolve the SOLO-workspace founder for this installation via the
//           membership self-join (resolveSoloFounderForInstallation, ADR-044
//           Amendment 2026-06-17b). The reverse-lookup reads the NON-UNIQUE
//           workspaces install column, so the count is fail-closed: 0 → 404
//           (no founder owns this install), 1 → founderId, >1 → 404 + PAGE
//           (ambiguous standing-state — do NOT pick one), db-error → 500.
//           These are PRE-dedup paths now: no row written, none to release.
//   Step 6: isGranted(supabase, founderId, actionClass) — fail-closed
//           on no-grant (log + 200) OR DB-error (Sentry via isGranted + 200).
//   Step 7-pre (claimDedupRow): plain .insert() into processed_github_events
//           (NO ON CONFLICT — supabase-js returns data:null not [] on no-op,
//           so the affected-row gate is unreliable; catch PG_UNIQUE_VIOLATION
//           → 200 instead, the Stripe replay idiom). Runs immediately before
//           EACH dispatch (push + non-push), AFTER every drop-filter.
//   Step 7: inngest.send({ id: github-<deliveryId>, name, v, data }).
//   Step 8: ON ANY ERROR in Step 7 AFTER the Step 7-pre INSERT succeeded:
//           DELETE processed_github_events row (releaseDedupRow) so the GitHub
//           redelivery can be processed cleanly. Without this, a transient
//           inngest.send failure leaves the dedup row, GitHub redelivers, the
//           redelivery 200s as "duplicate", the event is silently dropped.

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
import { normalizeRepoUrl } from "@/lib/repo-url";
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

  // Step 7-pre: delivery-id dedup claim. Invoked immediately before EACH
  // dispatch (push + non-push), AFTER all drop-filters — the drop-before-dedup
  // reorder (2026-06-30, ADR-036 amendment). Plain .insert() — NO ON CONFLICT.
  // supabase-js .insert() returns data:null (not []) on ON CONFLICT DO NOTHING
  // without .select(); the affected-row gate is unreliable. We catch
  // PG_UNIQUE_VIOLATION (23505) → 200 instead, the Stripe replay idiom. Returns
  // a NextResponse to return early (200 replay / 500 db-error), or null to
  // proceed to dispatch.
  async function claimDedupRow(): Promise<NextResponse | null> {
    const { error: dedupErr } = await supabase
      .from("processed_github_events")
      .insert({ delivery_id: deliveryId });
    if (!dedupErr) return null;
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

  // releaseDedupRow mirror of Stripe's pattern. After a claimDedupRow() INSERT
  // succeeds, ANY failure on the immediately-following dispatch (push or
  // non-push) MUST run this before return so the GitHub redelivery is processed
  // (not silently dropped as a duplicate). Silently tolerates a DELETE failure —
  // the redelivery is the correction mechanism.
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

  // Step 4: parse body (signature verified; dedup is NOT yet committed — it
  // moves to Step 7-pre, immediately before dispatch).
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
    return NextResponse.json({ error: "Malformed body" }, { status: 400 });
  }

  const installationId = body.installation?.id;
  if (typeof installationId !== "number") {
    logger.warn(
      { deliveryId, githubEvent },
      "GitHub webhook: no installation.id in payload — ignoring",
    );
    // No installation to attribute → drop. This is a pre-dedup path
    // (drop-before-dedup): no row was written, so there is nothing to
    // release.
    return NextResponse.json({ received: true });
  }

  // workflow_run gate: only `failure` conclusions are actionable.
  if (githubEvent === "workflow_run" && body.workflow_run?.conclusion !== "failure") {
    // Skip silently — neither a 4xx nor a draft. This is the dominant no-op
    // case (the 63%-of-WAL driver): drop-before-dedup means NO row is written
    // here. A redelivery re-evaluates the gate on its own merits; a future
    // legitimate failure arrives under a distinct delivery_id anyway.
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
    // Step 7-pre: claim the dedup row immediately before dispatch (this push
    // WILL reconcile). A 23505 replay or db-error returns early here.
    const claimed = await claimDedupRow();
    if (claimed) return claimed;
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

  // Non-push founder resolution: solo-workspace self-join (CTO Option C),
  // REPO-SCOPED (ADR-044 Amendment 2026-06-18 — BUG 1 fix).
  // Discriminated union — 0/1/>1/db-error each branch distinctly. The `>1`
  // (ambiguous) branch is the load-bearing fail-closed defense: dropping a
  // re-drivable event is strictly safer than misattributing an action /
  // installation-token to the WRONG founder (the brand-survival hazard).
  //
  // Pre-compose guard (ADR-044 Amendment 2026-06-18): the resolver scopes by
  // (installation_id, normalizeRepoUrl(repo_url)). A non-push event with NO
  // `repository.full_name` cannot be repo-scoped, so it drops via the SAME
  // none/404 path WITHOUT issuing the resolver SELECT. This MUST be the
  // PRE-COMPOSE `!full_name` check: `normalizeRepoUrl("https://github.com/")`
  // returns "https://github.com" (NOT ""), so a post-normalize === "" check
  // would never fire and we would SELECT on a bogus host-only repo_url.
  const fullName = body.repository?.full_name;
  if (!fullName) {
    logger.warn(
      { installationId, deliveryId, githubEvent },
      "GitHub webhook: non-push event has no repository.full_name — cannot repo-scope founder, 404",
    );
    // Pre-dedup path (drop-before-dedup): no row written, none to release.
    return NextResponse.json(
      { error: "No repository for installation" },
      { status: 404 },
    );
  }
  // Compose-before-normalize, mirroring the push reconcile precedent
  // (workspace-reconcile-on-push.ts:150). The route owns this so the resolver
  // receives a PRE-NORMALIZED repo_url that matches the stored value exactly.
  const targetRepoUrl = normalizeRepoUrl(`https://github.com/${fullName}`);
  const founderResolution = await resolveSoloFounderForInstallation(
    installationId,
    targetRepoUrl,
    supabase,
  );
  if (founderResolution.kind === "db-error") {
    // The resolver ALREADY mirrored the real Postgres error to Sentry via
    // reportSilentFallback (feature=github-webhook, op=founder-resolve). Do NOT
    // re-capture a synthetic Error under the same op here — that double-reports
    // one failure. The pino line below stays for container-stdout context; the
    // durable Sentry signal is the resolver's. (One report per failure.)
    logger.error(
      { installationId, deliveryId },
      "GitHub webhook: founder resolution DB error",
    );
    // Pre-dedup path (drop-before-dedup): no row written, none to release.
    // GitHub retries 5xx, re-driving the delivery.
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
    // Pre-dedup path (drop-before-dedup): no row written, none to release.
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
    // "not for me"; GitHub will not retry 4xx. Pre-dedup path
    // (drop-before-dedup): no row was written, so there is nothing to
    // release and a future install→delivery on the same delivery_id is
    // not short-circuited.
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

  // Step 7-pre: claim the dedup row immediately before dispatch (grant
  // confirmed; this event WILL dispatch). A 23505 replay or db-error returns
  // early here.
  const claimed = await claimDedupRow();
  if (claimed) return claimed;

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
