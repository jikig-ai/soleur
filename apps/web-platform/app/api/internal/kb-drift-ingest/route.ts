// PR-H (#3244) Phase 5 — KB-drift internal ingest route.
//
// Authentication: HMAC-SHA256 against KB_DRIFT_INGEST_SIGNING_KEY (Doppler
// `prd_kb_drift_walker` config; published as GH Actions secret
// `DOPPLER_TOKEN_KB_DRIFT` per Phase 2 IaC). NOT founder-facing — the
// GH Actions cron is the sole caller. Cross-tenant: NO (the walker
// findings are internal infra signal; rows are owned by the operator
// founder for routing into the `knowledge` domain).
//
// Digest model (#4579): a walker run inserts ONE draft card summarizing N
// findings (not one row per finding), protecting the 7-item Today cap from
// low-stakes flooding. `source_ref` is a full sha256 content hash over the
// findings, so an unchanged KB produces the same ref → the partial-unique
// index `messages_active_draft_dedup_idx` (migration 052) yields an idempotent
// skip. The shared `insertDraftCard` helper does plain `.insert()` + maps
// 23505 → { status: "deduped" } (never ON CONFLICT — PostgREST cannot infer it
// against a partial index, 42P10).
//
// Cross-tenant: the helper PINS workspace_id to the operator's solo workspace
// (NOT the session-selected workspace) and writes via the RLS-enforced tenant
// client — closing the service-role bypass this route used to carry.

import { createHmac, createHash, timingSafeEqual } from "node:crypto";
import { NextResponse } from "next/server";
import logger from "@/server/logger";
import * as Sentry from "@sentry/nextjs";
import { insertDraftCard } from "@/server/messages/insert-draft-card";
import {
  MESSAGE_SOURCE_KB_DRIFT,
  MESSAGE_OWNING_DOMAIN_KNOWLEDGE,
  MESSAGE_TIER_EXTERNAL_LOW_STAKES,
} from "@/lib/messages/tiers";

interface KBFinding {
  kind: "broken-link" | "broken-anchor";
  source_path: string;
  target: string;
  source_ref: string;
}

interface KBPayload {
  findings: KBFinding[];
  counts: { broken_link: number; broken_anchor: number };
}

const SIGNATURE_HEADER = "x-soleur-kb-drift-signature";

// Walker output bounded by repo size; current KB has ~2k markdown files
// and the walker emits one JSON object per finding. Even an unrealistic
// catastrophic-drift run (every link broken) tops out around 256 KiB. Cap
// at 1 MiB so an attacker who learned the signing key still cannot use
// this route as a memory-amp DoS primitive against the Next.js worker.
const MAX_INGEST_BODY_BYTES = 1_048_576;

function readSigningKey(): string | null {
  const v = process.env.KB_DRIFT_INGEST_SIGNING_KEY;
  return v && v.length > 0 ? v : null;
}

function verifyHmac(rawBody: string, headerValue: string | null, secret: string): boolean {
  if (!headerValue) return false;
  const received = headerValue.startsWith("sha256=") ? headerValue.slice("sha256=".length) : headerValue;
  const computed = createHmac("sha256", secret).update(rawBody).digest("hex");
  if (received.length !== computed.length) return false;
  try {
    return timingSafeEqual(Buffer.from(received, "utf8"), Buffer.from(computed, "utf8"));
  } catch {
    return false;
  }
}

function validatePayload(parsed: unknown): KBPayload | null {
  if (typeof parsed !== "object" || parsed === null) return null;
  const p = parsed as Partial<KBPayload>;
  if (!Array.isArray(p.findings)) return null;
  for (const f of p.findings) {
    if (typeof f.kind !== "string" || (f.kind !== "broken-link" && f.kind !== "broken-anchor")) {
      return null;
    }
    if (typeof f.source_path !== "string" || typeof f.target !== "string") return null;
    if (typeof f.source_ref !== "string" || f.source_ref.length === 0) return null;
  }
  if (typeof p.counts !== "object" || p.counts === null) return null;
  return p as KBPayload;
}

export async function POST(request: Request) {
  const rawBody = await request.text();
  if (rawBody.length > MAX_INGEST_BODY_BYTES) {
    return NextResponse.json({ error: "Payload too large" }, { status: 413 });
  }
  const secret = readSigningKey();
  if (!secret) {
    logger.error({ feature: "kb-drift-ingest" }, "KB_DRIFT_INGEST_SIGNING_KEY unset");
    Sentry.captureMessage("KB-drift ingest secret unset", {
      level: "error",
      tags: { feature: "kb-drift-ingest", op: "secret" },
    });
    return NextResponse.json({ error: "Server misconfigured" }, { status: 500 });
  }

  const signatureHeader = request.headers.get(SIGNATURE_HEADER);
  if (!verifyHmac(rawBody, signatureHeader, secret)) {
    logger.error({ feature: "kb-drift-ingest" }, "HMAC verification failed");
    Sentry.captureMessage("KB-drift ingest HMAC verification failed", {
      level: "error",
      tags: { feature: "kb-drift-ingest", op: "signature" },
    });
    return NextResponse.json({ error: "Invalid signature" }, { status: 401 });
  }

  let parsed: unknown;
  try {
    parsed = JSON.parse(rawBody);
  } catch {
    return NextResponse.json({ error: "Malformed JSON" }, { status: 400 });
  }
  const payload = validatePayload(parsed);
  if (!payload) {
    return NextResponse.json({ error: "Invalid payload shape" }, { status: 400 });
  }

  // Resolve the operator founder. The walker output is internal infra
  // signal; we attribute every row to the configured operator founder
  // so the rows route through the same RLS + audit primitives. This route
  // runs in the app runtime, so the id is read from Doppler `prd` (the
  // app-runtime config), provisioned by apps/web-platform/infra/kb-drift.tf.
  const operatorFounderId = process.env.KB_DRIFT_OPERATOR_FOUNDER_ID;
  if (!operatorFounderId) {
    logger.error({ feature: "kb-drift-ingest" }, "KB_DRIFT_OPERATOR_FOUNDER_ID unset");
    Sentry.captureMessage("KB-drift ingest operator founderId unset", {
      level: "error",
      tags: { feature: "kb-drift-ingest", op: "operator-id" },
    });
    return NextResponse.json({ error: "Server misconfigured" }, { status: 500 });
  }

  // Empty run: nothing drifted. Do not insert an empty digest card.
  if (payload.findings.length === 0) {
    return NextResponse.json({ received: true, inserted: 0, deduped: 0, total: 0 });
  }

  // Build one digest. Content-hash source_ref over the per-finding refs so an
  // unchanged KB → same ref → idempotent 23505 skip on re-run. Full sha256
  // (no truncation) avoids a birthday collision masking a distinct night's
  // findings as a false dedup.
  const sourceRef =
    "digest-" +
    createHash("sha256")
      .update(payload.findings.map((f) => f.source_ref).sort().join("\n"))
      .digest("hex");

  // Strip the URL query string from each finding target before composing the
  // preview: a broken doc link never needs its query string for triage, and
  // redactGithubSourcedText does NOT scrub signed-URL params (?X-Amz-Signature=,
  // ?token=, ?sig=). The helper redacts the composed preview as the second layer.
  const stripUrlQuery = (s: string): string =>
    s.replace(/(\bhttps?:\/\/[^\s?#]+)[?#][^\s]*/gi, "$1");

  const lines = payload.findings.map((f) => {
    const label = f.kind === "broken-link" ? "Broken link" : "Broken anchor";
    return `• ${label} in ${f.source_path} → ${stripUrlQuery(f.target)}`;
  });
  const draftPreview = `${payload.findings.length} KB-drift findings — review\n${lines.join("\n")}`;

  let result;
  try {
    result = await insertDraftCard({
      founderId: operatorFounderId,
      source: MESSAGE_SOURCE_KB_DRIFT,
      source_ref: sourceRef,
      owning_domain: MESSAGE_OWNING_DOMAIN_KNOWLEDGE,
      draft_preview: draftPreview,
      tier: MESSAGE_TIER_EXTERNAL_LOW_STAKES,
      urgency: "low",
      trust_tier: "internal_infra_auto",
      // Valid action class (knowledge.kb_drift); the digest card renders a
      // Dismiss affordance, not a send button, so the send/template-auth path is
      // not reachable — this keeps the row valid if the UI ever regresses.
      action_class: "knowledge.kb_drift",
    });
  } catch {
    // The helper already mirrored the error to Sentry/Better Stack
    // (reportSilentFallback). Return 500 so the walker cron records a non-2xx
    // (the authoritative "blind night" signal per the Observability section).
    return NextResponse.json({ error: "Persist failed" }, { status: 500 });
  }

  const deduped = result.status === "deduped" ? 1 : 0;
  const inserted = result.status === "inserted" ? 1 : 0;

  if (deduped) {
    // Mirror the idempotent skip (was silent) — cq-silent-fallback-must-mirror.
    Sentry.captureMessage("KB-drift digest deduped", {
      level: "info",
      tags: { feature: "kb-drift-ingest", op: "dedup-skip" },
      extra: { source_ref: sourceRef, finding_count: payload.findings.length },
    });
  }

  logger.info(
    {
      feature: "kb-drift-ingest",
      workspace_id: operatorFounderId,
      finding_count: payload.findings.length,
      deduped: deduped === 1,
    },
    "KB-drift ingest: digest persisted",
  );

  return NextResponse.json({
    received: true,
    inserted,
    deduped,
    total: payload.findings.length,
  });
}
