// PR-H (#3244) Phase 5 — KB-drift internal ingest route.
//
// Authentication: HMAC-SHA256 against KB_DRIFT_INGEST_SIGNING_KEY (Doppler
// `prd_kb_drift_walker` config; published as GH Actions secret
// `DOPPLER_TOKEN_KB_DRIFT` per Phase 2 IaC). NOT founder-facing — the
// GH Actions cron is the sole caller. Cross-tenant: NO (the walker
// findings are internal infra signal; rows are owned by the operator
// founder for routing into the `knowledge` domain).
//
// Idempotency: each finding carries a deterministic `source_ref` (e.g.,
// `link-<sha256[:16]>`) so the partial-unique index
// `messages_active_draft_dedup_idx` from migration 051 silently dedups
// re-runs. Plain `.insert()` + catch PG_UNIQUE_VIOLATION → skip silently.

import { createHmac, timingSafeEqual } from "node:crypto";
import { NextResponse } from "next/server";
import logger from "@/server/logger";
import * as Sentry from "@sentry/nextjs";
import { createServiceClient } from "@/lib/supabase/server";
import { PG_UNIQUE_VIOLATION } from "@/lib/postgres-errors";
import {
  MESSAGE_SOURCE_KB_DRIFT,
  MESSAGE_OWNING_DOMAIN_KNOWLEDGE,
  MESSAGE_STATUS_DRAFT,
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
  // so the rows route through the same RLS + audit primitives. The
  // operator-founder id lives in Doppler `prd_kb_drift_walker` so the
  // walker's blast-radius scope does not leak across configs.
  const operatorFounderId = process.env.KB_DRIFT_OPERATOR_FOUNDER_ID;
  if (!operatorFounderId) {
    logger.error({ feature: "kb-drift-ingest" }, "KB_DRIFT_OPERATOR_FOUNDER_ID unset");
    Sentry.captureMessage("KB-drift ingest operator founderId unset", {
      level: "error",
      tags: { feature: "kb-drift-ingest", op: "operator-id" },
    });
    return NextResponse.json({ error: "Server misconfigured" }, { status: 500 });
  }

  const supabase = createServiceClient();

  let inserted = 0;
  let deduped = 0;
  for (const finding of payload.findings) {
    const { error } = await supabase.from("messages").insert({
      user_id: operatorFounderId,
      tier: MESSAGE_TIER_EXTERNAL_LOW_STAKES,
      status: MESSAGE_STATUS_DRAFT,
      source: MESSAGE_SOURCE_KB_DRIFT,
      source_ref: finding.source_ref,
      owning_domain: MESSAGE_OWNING_DOMAIN_KNOWLEDGE,
      draft_preview: `${finding.kind === "broken-link" ? "Broken link" : "Broken anchor"} in ${finding.source_path} → ${finding.target}`,
      urgency: "low",
      trust_tier: "internal_infra_auto",
    });
    if (error) {
      if (error.code === PG_UNIQUE_VIOLATION) {
        deduped += 1;
        continue;
      }
      logger.error(
        { err: error, source_ref: finding.source_ref },
        "KB-drift ingest: insert failed",
      );
      Sentry.captureException(error, {
        tags: { feature: "kb-drift-ingest", op: "persist" },
        extra: { source_ref: finding.source_ref },
      });
      return NextResponse.json({ error: "Persist failed" }, { status: 500 });
    }
    inserted += 1;
  }

  return NextResponse.json({
    received: true,
    inserted,
    deduped,
    total: payload.findings.length,
  });
}
