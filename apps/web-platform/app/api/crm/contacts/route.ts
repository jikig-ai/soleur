// GET /api/crm/contacts (feat-beta-crm-ui #6172) — the read-only pipeline
// board's contact list. Owner-scoped SELECT on the SSR cookie client
// (createClient() + getUser()) — the SAME RLS-owner boundary the agent path
// uses, NOT the agent-impersonation getFreshTenantClient. NOT registered in
// PUBLIC_PATHS: it inherits the default cookie-session gate (a cookie-less
// caller is 307'd to /login by middleware before this handler runs).
//
// PII-safe (AC5): third-party contact PII (name/company) is returned to the
// authenticated OWNER (their own data) but a query FAILURE never forwards raw
// Postgres error text (message/details) to the HTTP body or Sentry — we mirror
// a synthetic PII-free error carrying only { op, userId, code }.

import { NextResponse } from "next/server";
import * as Sentry from "@sentry/nextjs";
import { createClient } from "@/lib/supabase/server";
import { CONTACT_COLUMNS } from "@/server/crm/crm-reads";

export const dynamic = "force-dynamic";

export async function GET() {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) {
    return NextResponse.json({ error: "unauthorized" }, { status: 401 });
  }

  try {
    // RLS scopes rows to the owner; order most-recently-contacted first
    // (never-contacted rows last). Query inlined using the shared column set.
    const { data, error } = await supabase
      .from("beta_contacts")
      .select(CONTACT_COLUMNS)
      .order("last_contact", { ascending: false, nullsFirst: false })
      .order("created_at", { ascending: false });

    if (error) {
      // NEVER pass the raw PG error to Sentry (defense in depth — a read error
      // should not carry row PII, but we mirror only the SQLSTATE regardless).
      Sentry.captureException(new Error(`crm-contacts:${error.code ?? "unknown"}`), {
        tags: { surface: "crm-contacts" },
        extra: { op: "list", userId: user.id, code: error.code ?? null },
      });
      return NextResponse.json({ error: "contacts_query_error" }, { status: 502 });
    }

    const rows = (data ?? []) as unknown as Array<Record<string, unknown>>;
    // Shape to exactly the board's fields (drop user_id/source/next_action/etc.
    // — minimize what egresses to the browser; AC1).
    const contacts = rows.map((r) => ({
      id: r.id as string,
      company: r.company as string | null,
      name: r.name as string | null,
      role: r.role as string | null,
      stage: r.stage as string,
      amount: r.amount as number | null,
      currency: r.currency as string | null,
      last_contact: r.last_contact as string | null,
    }));

    return NextResponse.json({ contacts });
  } catch (e) {
    Sentry.captureException(
      new Error(`crm-contacts:${(e as { code?: string })?.code ?? "throw"}`),
      {
        tags: { surface: "crm-contacts" },
        extra: { op: "list", userId: user.id, code: (e as { code?: string })?.code ?? null },
      },
    );
    return NextResponse.json({ error: "contacts_query_error" }, { status: 502 });
  }
}
