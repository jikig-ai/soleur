// PR-H (#4077) — POST /api/dashboard/today/[id]/discard
//
// Archives a draft message owned by the caller (status: draft → archived).
// No action_sends row is written — discard is a no-op outbound.
//
// Per cq-nextjs-route-files-http-only-exports: only HTTP exports + dynamic.

import { NextResponse } from "next/server";
import { createClient } from "@/lib/supabase/server";
import { validateOrigin, rejectCsrf } from "@/lib/auth/validate-origin";
import { reportSilentFallback } from "@/server/observability";

export const dynamic = "force-dynamic";

export async function POST(
  req: Request,
  { params }: { params: Promise<{ id: string }> },
) {
  const { valid, origin } = validateOrigin(req);
  if (!valid) return rejectCsrf("api/dashboard/today/[id]/discard", origin);

  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) {
    return NextResponse.json({ error: "unauthorized" }, { status: 401 });
  }

  const { id: messageId } = await params;

  // Belt-and-suspenders alongside RLS.
  const { data, error } = await supabase
    .from("messages")
    .update({ status: "archived" })
    .eq("id", messageId)
    .eq("user_id", user.id)
    .eq("status", "draft")
    .select("id")
    .maybeSingle();

  if (error) {
    reportSilentFallback(error, {
      feature: "dashboard-discard",
      op: "messages-archive",
      message: "Failed to archive draft",
      extra: { userId: user.id, messageId },
    });
    return NextResponse.json({ error: "internal_error" }, { status: 500 });
  }
  if (!data) {
    return NextResponse.json({ error: "forbidden" }, { status: 403 });
  }

  return NextResponse.json({ id: data.id, status: "archived" });
}
