// GET /api/crm/contacts/[id] (feat-beta-crm-ui #6172) — the contact-detail
// drawer's read. Goes through the ATOMIC crm_get_contact_detail RPC (migration
// 127): one VOLATILE SECURITY DEFINER function that inserts the Art. 5(2)
// read-audit row AND returns {contact, notes, transitions} in the same
// transaction — fail-closed (no audit row ⇒ no data). auth.uid() resolves from
// the SSR cookie session, so we call it via supabase.rpc() on createClient().
//
// Rationale (so a reviewer doesn't flag it as REST hygiene): this is a GET
// whose ONLY "write" is the accountability log — no user-facing state change,
// no CSRF surface. SWR-revalidation producing duplicate log rows is CORRECT
// (each = a real PII re-egress). Do NOT split it into a pure read + best-effort
// side-write — that reintroduces the read-succeeds/audit-fails gap the atomic
// RPC closes.
//
// Two error dispositions:
//   - missing / erased / cross-owner id (RPC raises 42501) OR a malformed uuid
//     (22P02) → byte-identical 404 { error: "not_found" } (no existence oracle,
//     no Sentry — an expected-safe cross-owner probe). AC2.
//   - any OTHER RPC error (audit table down, infra) → PII-free 5xx (NOT a 200
//     with data) + a synthetic Sentry mirror. This IS the accountability-gap
//     signal. AC3.

import { NextResponse } from "next/server";
import * as Sentry from "@sentry/nextjs";
import { createClient } from "@/lib/supabase/server";

export const dynamic = "force-dynamic";

// SQLSTATEs that map to the uniform 404 (no oracle): 42501 = the RPC's
// missing/foreign/unauthenticated guard; 22P02 = malformed uuid text.
const NOT_FOUND_CODES = new Set(["42501", "22P02"]);

export async function GET(
  _req: Request,
  { params }: { params: Promise<{ id: string }> },
) {
  const { id } = await params;

  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) {
    return NextResponse.json({ error: "unauthorized" }, { status: 401 });
  }

  const { data, error } = await supabase.rpc("crm_get_contact_detail", {
    p_contact_id: id,
  });

  if (error) {
    const code = error.code ?? "";
    if (NOT_FOUND_CODES.has(code)) {
      // Uniform, byte-identical response for never-existed / erased / foreign.
      return NextResponse.json({ error: "not_found" }, { status: 404 });
    }
    // Fail-closed accountability signal: the atomic read+audit RPC failed for a
    // non-authorization reason. Never a 200-with-data; never raw PG text.
    Sentry.captureException(new Error(`crm-contact-detail:${code || "unknown"}`), {
      tags: { surface: "crm-contact-detail" },
      extra: { op: "detail", userId: user.id, code: code || null },
    });
    return NextResponse.json({ error: "detail_query_error" }, { status: 502 });
  }

  // The RPC raises (never returns null) on missing/foreign; a null here is a
  // defensive uniform 404, not a data leak.
  if (data == null) {
    return NextResponse.json({ error: "not_found" }, { status: 404 });
  }

  // data is the RPC's jsonb: { contact, notes, transitions }.
  return NextResponse.json(data);
}
