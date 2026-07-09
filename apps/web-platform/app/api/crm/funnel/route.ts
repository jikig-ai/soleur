// GET /api/crm/funnel (feat-beta-crm-ui #6172) — count-based conversion funnel
// + stage velocity for the read-only CRM funnel view. Owner-scoped reads on the
// SSR cookie client; NOT in PUBLIC_PATHS. Returns COUNTS/TIMINGS ONLY — no note
// bodies, no contact PII beyond stage counts (AC4). The dataset is a single
// owner's tiny beta pipeline (no hot path). The pure computation lives in the
// sibling compute.ts (route files may export only handlers —
// cq-nextjs-route-files-http-only-exports).

import { NextResponse } from "next/server";
import * as Sentry from "@sentry/nextjs";
import { createClient } from "@/lib/supabase/server";
import { computeFunnel, type ContactRow, type TransitionRow } from "./compute";

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
    // Stage counts + timings only — no name/company/body columns egress.
    const [contactsRes, transitionsRes] = await Promise.all([
      supabase.from("beta_contacts").select("id, stage, created_at"),
      supabase
        .from("beta_contact_stage_transitions")
        .select("contact_id, from_stage, to_stage, entered_at"),
    ]);

    if (contactsRes.error || transitionsRes.error) {
      const code =
        contactsRes.error?.code ?? transitionsRes.error?.code ?? "unknown";
      Sentry.captureException(new Error(`crm-funnel:${code}`), {
        tags: { surface: "crm-funnel" },
        extra: { op: "funnel", userId: user.id, code },
      });
      return NextResponse.json({ error: "funnel_query_error" }, { status: 502 });
    }

    const funnel = computeFunnel(
      (contactsRes.data ?? []) as ContactRow[],
      (transitionsRes.data ?? []) as TransitionRow[],
    );
    return NextResponse.json(funnel);
  } catch (e) {
    Sentry.captureException(
      new Error(`crm-funnel:${(e as { code?: string })?.code ?? "throw"}`),
      {
        tags: { surface: "crm-funnel" },
        extra: {
          op: "funnel",
          userId: user.id,
          code: (e as { code?: string })?.code ?? null,
        },
      },
    );
    return NextResponse.json({ error: "funnel_query_error" }, { status: 502 });
  }
}
