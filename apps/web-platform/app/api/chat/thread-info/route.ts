import { NextResponse } from "next/server";
import { createClient } from "@/lib/supabase/server";
import { lookupConversationForPath } from "@/server/lookup-conversation-for-path";

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

  const result = await lookupConversationForPath(user.id, contextPath);
  if (!result.ok) {
    // Helper already mirrored to Sentry; thread-info's public contract
    // degrades to messageCount=0 rather than exposing the error.
    return NextResponse.json({ messageCount: 0 });
  }
  return NextResponse.json({
    messageCount: result.row?.message_count ?? 0,
  });
}
