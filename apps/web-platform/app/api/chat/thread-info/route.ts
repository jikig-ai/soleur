import { NextResponse } from "next/server";
import { createClient, createServiceClient } from "@/lib/supabase/server";
import { reportSilentFallback } from "@/server/observability";

const CONTEXT_PATH_MAX_LEN = 512;
const CONTEXT_PATH_PREFIX = "knowledge-base/";

function validateContextPath(v: string | null): string | null {
  if (!v || v.length === 0 || v.length > CONTEXT_PATH_MAX_LEN) return null;
  if (!v.startsWith(CONTEXT_PATH_PREFIX)) return null;
  if (v.includes("..") || v.includes("\0")) return null;
  const filename = v.split("/").pop() ?? "";
  if (filename.lastIndexOf(".") <= 0) return null;
  return v;
}

export async function GET(req: Request) {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const url = new URL(req.url);
  const contextPath = validateContextPath(url.searchParams.get("contextPath"));
  if (!contextPath) {
    return NextResponse.json({ error: "Invalid contextPath" }, { status: 400 });
  }

  const service = createServiceClient();
  const { data: existing, error: lookupErr } = await service
    .from("conversations")
    .select("id")
    .eq("user_id", user.id)
    .eq("context_path", contextPath)
    .is("archived_at", null)
    .order("last_active", { ascending: false })
    .limit(1)
    .maybeSingle();

  if (lookupErr) {
    reportSilentFallback(lookupErr, {
      feature: "kb-chat",
      op: "thread-info-lookup",
      extra: { contextPath },
    });
    return NextResponse.json({ messageCount: 0 });
  }
  if (!existing) {
    return NextResponse.json({ messageCount: 0 });
  }

  const { count, error: countErr } = await service
    .from("messages")
    .select("id", { count: "exact", head: true })
    .eq("conversation_id", existing.id);

  if (countErr) {
    reportSilentFallback(countErr, {
      feature: "kb-chat",
      op: "thread-info-count",
      extra: { conversationId: existing.id },
    });
    return NextResponse.json({ messageCount: 0 });
  }

  return NextResponse.json({ messageCount: count ?? 0 });
}
