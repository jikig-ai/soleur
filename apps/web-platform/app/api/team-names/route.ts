import { NextResponse } from "next/server";
import { createClient } from "@/lib/supabase/server";
import { validateCustomName } from "@/server/team-names-validation";
import { ROUTABLE_DOMAIN_LEADERS } from "@/server/domain-leaders";
import { validateOrigin, rejectCsrf } from "@/lib/auth/validate-origin";

const VALID_LEADER_IDS = new Set(ROUTABLE_DOMAIN_LEADERS.map((l) => l.id));

/** GET /api/team-names — returns all custom names for the authenticated user. */
export async function GET() {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const [namesResult, userResult] = await Promise.all([
    supabase
      .from("team_names")
      .select("leader_id, custom_name")
      .eq("user_id", user.id),
    supabase
      .from("users")
      .select("nudges_dismissed, naming_prompted_at")
      .eq("id", user.id)
      .single(),
  ]);

  if (namesResult.error) {
    return NextResponse.json({ error: "Failed to fetch team names" }, { status: 500 });
  }

  const nudgesDismissed: string[] = userResult.data?.nudges_dismissed ?? [];
  const namingPromptedAt: string | null = userResult.data?.naming_prompted_at ?? null;

  // Return as a map: { cto: "Alex", ... } plus metadata
  const names: Record<string, string> = {};
  for (const row of namesResult.data ?? []) {
    names[row.leader_id] = row.custom_name;
  }

  return NextResponse.json({ names, nudgesDismissed, namingPromptedAt });
}

/** PUT /api/team-names — upsert a custom name for a single leader. */
export async function PUT(request: Request) {
  const { valid: originValid, origin } = validateOrigin(request);
  if (!originValid) return rejectCsrf("api/team-names", origin);

  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const body = await request.json().catch(() => null);
  if (!body || typeof body.leaderId !== "string" || typeof body.name !== "string") {
    return NextResponse.json(
      { error: "Missing leaderId or name" },
      { status: 400 },
    );
  }

  const { leaderId, name } = body as { leaderId: string; name: string };

  if (!VALID_LEADER_IDS.has(leaderId)) {
    return NextResponse.json({ error: "Invalid leader ID" }, { status: 400 });
  }

  const trimmed = name.trim();

  // Empty name = delete the custom name (revert to default)
  if (trimmed === "") {
    await supabase
      .from("team_names")
      .delete()
      .eq("user_id", user.id)
      .eq("leader_id", leaderId);

    return NextResponse.json({ deleted: true });
  }

  const validation = validateCustomName(trimmed);
  if (!validation.valid) {
    return NextResponse.json({ error: validation.error }, { status: 400 });
  }

  const { error } = await supabase.from("team_names").upsert(
    {
      user_id: user.id,
      leader_id: leaderId,
      custom_name: trimmed,
      updated_at: new Date().toISOString(),
    },
    { onConflict: "user_id,leader_id" },
  );

  if (error) {
    return NextResponse.json({ error: "Failed to save name" }, { status: 500 });
  }

  return NextResponse.json({ saved: true, name: trimmed });
}

/** PATCH /api/team-names — dismiss the naming nudge for a leader. */
export async function PATCH(request: Request) {
  const { valid: originValid, origin } = validateOrigin(request);
  if (!originValid) return rejectCsrf("api/team-names", origin);

  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const body = await request.json().catch(() => null);
  if (!body || typeof body.leaderId !== "string") {
    return NextResponse.json({ error: "Missing leaderId" }, { status: 400 });
  }

  if (!VALID_LEADER_IDS.has(body.leaderId)) {
    return NextResponse.json({ error: "Invalid leader ID" }, { status: 400 });
  }

  // Read current dismissed list and append if not already present
  const { data: userData } = await supabase
    .from("users")
    .select("nudges_dismissed")
    .eq("id", user.id)
    .single();

  const current: string[] = userData?.nudges_dismissed ?? [];
  if (!current.includes(body.leaderId)) {
    current.push(body.leaderId);
    const { error } = await supabase
      .from("users")
      .update({ nudges_dismissed: current })
      .eq("id", user.id);

    if (error) {
      return NextResponse.json({ error: "Failed to dismiss nudge" }, { status: 500 });
    }
  }

  return NextResponse.json({ dismissed: true });
}
