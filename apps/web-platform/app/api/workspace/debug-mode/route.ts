import { NextResponse } from "next/server";
import { createClient } from "@/lib/supabase/server";
import { validateOrigin, rejectCsrf } from "@/lib/auth/validate-origin";
import { resolveDebugMode } from "@/server/resolve-debug-mode";
import {
  setDebugMode,
  DebugModeOwnerDeniedError,
} from "@/server/set-debug-mode";

// feat-debug-mode-stream — per-workspace debug-mode toggle (active-workspace).
// Cookie-authenticated browser route; the read/write helpers resolve the
// active workspace server-side and the SECURITY DEFINER RPCs enforce
// member-read / owner-write. NOT added to PUBLIC_PATHS (browser/session caller).

export async function GET(request: Request) {
  const { valid, origin } = validateOrigin(request);
  if (!valid) return rejectCsrf("api/workspace/debug-mode", origin);

  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) return NextResponse.json({ error: "unauthorized" }, { status: 401 });

  const debugMode = await resolveDebugMode(user.id);
  return NextResponse.json({ debugMode });
}

export async function POST(request: Request) {
  const { valid, origin } = validateOrigin(request);
  if (!valid) return rejectCsrf("api/workspace/debug-mode", origin);

  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) return NextResponse.json({ error: "unauthorized" }, { status: 401 });

  let body: { value?: unknown };
  try {
    body = await request.json();
  } catch {
    return NextResponse.json({ error: "invalid_body" }, { status: 400 });
  }
  if (typeof body.value !== "boolean") {
    return NextResponse.json({ error: "value_must_be_boolean" }, { status: 400 });
  }

  try {
    // The owner check lives in the SECURITY DEFINER RPC; a non-owner caller
    // raises (P0001) → DebugModeOwnerDeniedError → 403. A genuine infra fault
    // is NOT an authz denial → 500 (so it surfaces in 5xx alerting rather than
    // hiding behind a 403).
    const debugMode = await setDebugMode(user.id, body.value);
    return NextResponse.json({ debugMode });
  } catch (err) {
    if (err instanceof DebugModeOwnerDeniedError) {
      return NextResponse.json({ error: "not_authorized" }, { status: 403 });
    }
    return NextResponse.json({ error: "set_failed" }, { status: 500 });
  }
}
