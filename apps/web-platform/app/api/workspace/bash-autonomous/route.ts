import { NextResponse } from "next/server";
import { createClient } from "@/lib/supabase/server";
import { validateOrigin, rejectCsrf } from "@/lib/auth/validate-origin";
import { resolveBashAutonomous } from "@/server/resolve-bash-autonomous";
import {
  setBashAutonomous,
  BashAutonomousOwnerDeniedError,
} from "@/server/set-bash-autonomous";

// Issue B part 2 — per-workspace autonomous Bash toggle (active-workspace).
// Cookie-authenticated browser route; the read/write helpers resolve the
// active workspace server-side and the SECURITY DEFINER RPCs enforce
// member-read / owner-write. NOT added to PUBLIC_PATHS (browser/session caller).

export async function GET(request: Request) {
  const { valid, origin } = validateOrigin(request);
  if (!valid) return rejectCsrf("api/workspace/bash-autonomous", origin);

  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) return NextResponse.json({ error: "unauthorized" }, { status: 401 });

  const autonomous = await resolveBashAutonomous(user.id);
  return NextResponse.json({ autonomous });
}

export async function POST(request: Request) {
  const { valid, origin } = validateOrigin(request);
  if (!valid) return rejectCsrf("api/workspace/bash-autonomous", origin);

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
    // raises (P0001) → BashAutonomousOwnerDeniedError → 403. A genuine infra
    // fault is NOT an authz denial → 500 (so it surfaces in 5xx alerting
    // rather than hiding behind a 403).
    const autonomous = await setBashAutonomous(user.id, body.value);
    return NextResponse.json({ autonomous });
  } catch (err) {
    if (err instanceof BashAutonomousOwnerDeniedError) {
      return NextResponse.json({ error: "not_authorized" }, { status: 403 });
    }
    return NextResponse.json({ error: "set_failed" }, { status: 500 });
  }
}
