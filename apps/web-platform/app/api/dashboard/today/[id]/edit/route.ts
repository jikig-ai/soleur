// PR-H (#4077) — POST /api/dashboard/today/[id]/edit
//
// Updates messages.draft_preview for a row owned by the caller. Only
// status='draft' rows are editable.
//
// Per cq-nextjs-route-files-http-only-exports: only HTTP exports + dynamic.

import { NextResponse } from "next/server";
import { createClient } from "@/lib/supabase/server";
import { validateOrigin, rejectCsrf } from "@/lib/auth/validate-origin";
import { reportSilentFallback } from "@/server/observability";

export const dynamic = "force-dynamic";

interface EditBody {
  draft_preview?: unknown;
}

export async function POST(
  req: Request,
  { params }: { params: Promise<{ id: string }> },
) {
  const { valid, origin } = validateOrigin(req);
  if (!valid) return rejectCsrf("api/dashboard/today/[id]/edit", origin);

  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) {
    return NextResponse.json({ error: "unauthorized" }, { status: 401 });
  }

  const { id: messageId } = await params;
  let body: EditBody;
  try {
    body = (await req.json()) as EditBody;
  } catch {
    return NextResponse.json({ error: "invalid_json" }, { status: 400 });
  }

  const draftPreview =
    typeof body.draft_preview === "string" ? body.draft_preview : null;
  if (draftPreview === null) {
    return NextResponse.json(
      { error: "invalid_draft_preview" },
      { status: 400 },
    );
  }

  // Belt-and-suspenders alongside RLS — restrict to caller's drafts only.
  const { data, error } = await supabase
    .from("messages")
    .update({ draft_preview: draftPreview })
    .eq("id", messageId)
    .eq("user_id", user.id)
    .eq("status", "draft")
    .select("id, draft_preview")
    .maybeSingle();

  if (error) {
    reportSilentFallback(error, {
      feature: "dashboard-edit",
      op: "messages-update",
      message: "Failed to update draft_preview",
      extra: { userId: user.id, messageId },
    });
    return NextResponse.json({ error: "internal_error" }, { status: 500 });
  }
  if (!data) {
    return NextResponse.json({ error: "forbidden" }, { status: 403 });
  }

  return NextResponse.json({
    id: data.id,
    draft_preview: data.draft_preview,
  });
}
