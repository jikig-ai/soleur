// PR-I (#4078) — POST /api/template-authorizations/revoke
//
// Founder-callable. Inlines the revoke_template_authorization RPC call
// (mig 053 §(f)). Sentry breadcrumb on request + completion. Returns
// rows_revoked (0 = idempotent no-op; > 0 = revoked).
//
// Mirrors apps/web-platform/app/api/scope-grants/revoke/route.ts.
// Per cq-nextjs-route-files-http-only-exports: only HTTP exports + dynamic.

import { NextResponse } from "next/server";
import * as Sentry from "@sentry/nextjs";

import { createClient } from "@/lib/supabase/server";
import { validateOrigin, rejectCsrf } from "@/lib/auth/validate-origin";
import { reportSilentFallback } from "@/server/observability";

export const dynamic = "force-dynamic";

interface RevokeBody {
  template_hash?: unknown;
  reason?: unknown;
}

// Subset of the 8-value revocation_reason enum that the founder can
// initiate from the UI. DSR-erasure / quota / expired / regulator /
// vendor / policy / quarantine paths go through other code paths (the
// predicate's auto-revoke, account-delete's cascade, the classifier
// feedback loop in PR-I+1).
const FOUNDER_REVOKE_REASONS = new Set([
  "founder_revoked",
] as const);

export async function POST(req: Request) {
  const { valid, origin } = validateOrigin(req);
  if (!valid) return rejectCsrf("api/template-authorizations/revoke", origin);

  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) {
    return NextResponse.json({ error: "unauthorized" }, { status: 401 });
  }

  let body: RevokeBody;
  try {
    body = (await req.json()) as RevokeBody;
  } catch {
    return NextResponse.json({ error: "invalid_json" }, { status: 400 });
  }

  const templateHash = body.template_hash;
  const reason = body.reason ?? "founder_revoked";

  if (
    typeof templateHash !== "string" ||
    templateHash.length < 1 ||
    templateHash.length > 128
  ) {
    return NextResponse.json(
      { error: "invalid_template_hash" },
      { status: 400 },
    );
  }
  if (
    typeof reason !== "string" ||
    !FOUNDER_REVOKE_REASONS.has(reason as "founder_revoked")
  ) {
    return NextResponse.json({ error: "invalid_reason" }, { status: 400 });
  }

  Sentry.addBreadcrumb({
    category: "template-authorizations",
    message: "template-authorization.revoke_requested",
    level: "info",
    data: { template_hash: templateHash, reason },
  });

  const { data, error } = await supabase.rpc("revoke_template_authorization", {
    p_template_hash: templateHash,
    p_reason: reason,
  });

  if (error) {
    reportSilentFallback(error, {
      feature: "template-authorizations",
      op: "revoke_template_authorization",
      message: "revoke_template_authorization RPC failed",
      extra: { userId: user.id, template_hash: templateHash, reason },
    });
    return NextResponse.json({ error: "rpc_failed" }, { status: 500 });
  }

  Sentry.addBreadcrumb({
    category: "template-authorizations",
    message: "template-authorization.revoked",
    level: "info",
    data: { template_hash: templateHash, rows_revoked: data ?? 0 },
  });

  return NextResponse.json({ rows_revoked: data ?? 0 });
}
