import { NextResponse } from "next/server";
import { createClient } from "@/lib/supabase/server";
import { validateOrigin, rejectCsrf } from "@/lib/auth/validate-origin";
import { SlidingWindowCounter } from "@/server/rate-limiter";
import { deleteAccount } from "@/server/account-delete";
import logger from "@/server/logger";

// Rate limit: 1 deletion attempt per 60 seconds per user
const deletionLimiter = new SlidingWindowCounter({
  windowMs: 60_000,
  maxRequests: 1,
});

export async function POST(request: Request) {
  // CSRF protection
  const { valid: originValid, origin } = validateOrigin(request);
  if (!originValid) return rejectCsrf("api/account/delete", origin);

  // Auth check
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  // Rate limit
  if (!deletionLimiter.isAllowed(user.id)) {
    return NextResponse.json(
      { error: "Too many requests. Please wait before trying again." },
      { status: 429 },
    );
  }

  // Parse body
  const body = await request.json().catch(() => null);
  if (!body?.confirmEmail || typeof body.confirmEmail !== "string" || body.confirmEmail.length > 320) {
    return NextResponse.json(
      { error: "Missing confirmation email" },
      { status: 400 },
    );
  }

  // Execute deletion cascade
  const result = await deleteAccount(user.id, body.confirmEmail);

  if (!result.success) {
    logger.warn(
      { userId: user.id, error: result.error },
      "Account deletion failed",
    );
    return NextResponse.json(
      { success: false, error: result.error },
      { status: 400 },
    );
  }

  // Build response and clear all Supabase cookies
  const response = NextResponse.json({ success: true });

  // Clear all sb-* cookies to fully sign out the deleted user
  const cookieHeader = request.headers.get("cookie") ?? "";
  const cookies = cookieHeader.split(";").map((c) => c.trim());
  for (const cookie of cookies) {
    const name = cookie.split("=")[0];
    if (name.startsWith("sb-")) {
      response.cookies.set(name, "", {
        maxAge: 0,
        path: "/",
        secure: process.env.NODE_ENV === "production",
        sameSite: "lax",
      });
    }
  }

  return response;
}
