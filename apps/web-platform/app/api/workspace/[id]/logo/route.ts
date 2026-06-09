import { NextResponse } from "next/server";
import { createClient } from "@/lib/supabase/server";
import { createServiceClient } from "@/lib/supabase/service";
import { reportSilentFallback } from "@/server/observability";
import { toPublicStorageUrl } from "@/lib/supabase/public-storage-url";
import {
  SlidingWindowCounter,
  startPruneInterval,
  logRateLimitRejection,
} from "@/server/rate-limiter";

// GET /api/workspace/[id]/logo — stable proxy (#4916). Membership-gates then
// 302-redirects to a freshly-minted short-TTL (300s) signed URL. The browser
// caches the redirect for max-age=300 against this STABLE path (no signature in
// the URL) so window-focus re-polls of the chrome don't thrash a re-download
// (architecture P1-A/B). The signed target rotates invisibly behind the cache.
//
// 401 unauth · 403 non-member · 404 no logo · 502 mint failure · 302 success.

const BUCKET = "workspace-logos";
const SIGNED_TTL_SECONDS = 300;
const FEATURE = "workspace-logo";

// Per-user limit on the proxy: each cache-miss mints a signed URL + runs an
// RPC, so cap the amplification an authenticated member can drive (browser
// max-age=300 covers the steady state). Module-scoped — one counter for the
// route, mirroring withUserRateLimit's internals (we inline it here because the
// handler needs the [id] params the wrapper signature doesn't thread).
const proxyLimiter = new SlidingWindowCounter({ windowMs: 60_000, maxRequests: 60 });
startPruneInterval(proxyLimiter);

export async function GET(
  _request: Request,
  { params }: { params: Promise<{ id: string }> },
): Promise<Response> {
  const { id } = await params;

  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  if (!proxyLimiter.isAllowed(user.id)) {
    logRateLimitRejection("workspace-logo.proxy", user.id);
    return NextResponse.json(
      { error: "Too many requests" },
      { status: 429, headers: { "Retry-After": "60" } },
    );
  }

  // Membership gate (403). is_workspace_member is SECURITY DEFINER, GRANT
  // authenticated; distinguishes 403 (non-member) from 404 (member, no logo).
  const memberRes = await supabase.rpc("is_workspace_member", {
    p_workspace_id: id,
    p_user_id: user.id,
  });
  if (memberRes.error) {
    reportSilentFallback(memberRes.error, {
      feature: FEATURE,
      op: "member-check",
      extra: { userId: user.id, workspaceId: id },
    });
    return NextResponse.json({ error: "Internal server error" }, { status: 500 });
  }
  if (memberRes.data !== true) {
    return NextResponse.json({ error: "Forbidden" }, { status: 403 });
  }

  const service = createServiceClient();
  const wsRes = await service
    .from("workspaces")
    .select("logo_path")
    .eq("id", id)
    .maybeSingle();
  const logoPath = (wsRes.data as { logo_path: string | null } | null)?.logo_path ?? null;
  if (wsRes.error || !logoPath) {
    return NextResponse.json({ error: "Not found" }, { status: 404 });
  }

  const signed = await service.storage.from(BUCKET).createSignedUrl(logoPath, SIGNED_TTL_SECONDS);
  if (signed.error || !signed.data?.signedUrl) {
    reportSilentFallback(signed.error ?? new Error("no signedUrl"), {
      feature: FEATURE,
      op: "sign-url",
      extra: { userId: user.id, workspaceId: id },
    });
    return NextResponse.json({ error: "Bad gateway" }, { status: 502 });
  }

  // The service client signs storage URLs against SUPABASE_URL (the raw
  // <ref>.supabase.co host in prod), but CSP img-src is built from
  // NEXT_PUBLIC_SUPABASE_URL (the public custom domain) — so a 302 to the raw
  // host is CSP-blocked → <img> onError → monogram (#4996→#5012). Rewrite the
  // origin to the public host so the redirect target matches img-src.
  const location = toPublicStorageUrl(signed.data.signedUrl);

  return new NextResponse(null, {
    status: 302,
    headers: {
      Location: location,
      "Cache-Control": `private, max-age=${SIGNED_TTL_SECONDS}`,
      "X-Content-Type-Options": "nosniff",
    },
  });
}
