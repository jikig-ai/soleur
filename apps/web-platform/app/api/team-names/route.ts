import { NextResponse } from "next/server";
import { createClient } from "@/lib/supabase/server";
import { validateCustomName } from "@/server/team-names-validation";
import { ROUTABLE_DOMAIN_LEADERS } from "@/server/domain-leaders";
import { validateOrigin, rejectCsrf } from "@/lib/auth/validate-origin";

const VALID_LEADER_IDS = new Set<string>(ROUTABLE_DOMAIN_LEADERS.map((l) => l.id));

const ICON_PATH_PATTERN = /^settings\/team-icons\/[a-z]{2,3}\.(png|webp|svg)$/;

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
      .select("leader_id, custom_name, custom_icon_path")
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
  const iconPaths: Record<string, string> = {};
  for (const row of namesResult.data ?? []) {
    names[row.leader_id] = row.custom_name;
    if (row.custom_icon_path) {
      iconPaths[row.leader_id] = row.custom_icon_path;
    }
  }

  return NextResponse.json({ names, iconPaths, nudgesDismissed, namingPromptedAt });
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
  if (!body || typeof body.leaderId !== "string") {
    return NextResponse.json(
      { error: "Missing leaderId" },
      { status: 400 },
    );
  }

  const { leaderId } = body as { leaderId: string };
  const hasName = typeof body.name === "string";
  const hasIconPath = "iconPath" in body;

  if (!hasName && !hasIconPath) {
    return NextResponse.json(
      { error: "Missing name or iconPath" },
      { status: 400 },
    );
  }

  if (!VALID_LEADER_IDS.has(leaderId)) {
    return NextResponse.json({ error: "Invalid leader ID" }, { status: 400 });
  }

  // Icon-path-only update (set or clear)
  if (hasIconPath && !hasName) {
    const iconPath = body.iconPath as string | null;
    if (iconPath !== null && !ICON_PATH_PATTERN.test(iconPath)) {
      return NextResponse.json({ error: "Invalid icon path" }, { status: 400 });
    }
    // Try UPDATE first (won't create a row, preserves existing custom_name)
    const { data: updated, error: updateErr } = await supabase
      .from("team_names")
      .update({ custom_icon_path: iconPath, updated_at: new Date().toISOString() })
      .eq("user_id", user.id)
      .eq("leader_id", leaderId)
      .select("leader_id");

    if (updateErr) {
      return NextResponse.json({ error: "Failed to save icon path" }, { status: 500 });
    }

    // No existing row — INSERT with the leader's default role name (custom_name is NOT NULL)
    if (!updated || updated.length === 0) {
      const defaultName = ROUTABLE_DOMAIN_LEADERS.find((l) => l.id === leaderId)?.name ?? leaderId.toUpperCase();
      const { error: insertErr } = await supabase.from("team_names").insert({
        user_id: user.id,
        leader_id: leaderId,
        custom_name: defaultName,
        custom_icon_path: iconPath,
        updated_at: new Date().toISOString(),
      });
      if (insertErr) {
        return NextResponse.json({ error: "Failed to save icon path" }, { status: 500 });
      }
    }

    return NextResponse.json({ saved: true, iconPath });
  }

  // Name update (with optional icon path)
  const trimmed = (body.name as string).trim();

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

  if (hasIconPath) {
    const ip = body.iconPath as string | null;
    if (ip !== null && !ICON_PATH_PATTERN.test(ip)) {
      return NextResponse.json({ error: "Invalid icon path" }, { status: 400 });
    }
  }

  const upsertData: Record<string, string | null> = {
    user_id: user.id,
    leader_id: leaderId,
    custom_name: trimmed,
    updated_at: new Date().toISOString(),
  };
  if (hasIconPath) {
    upsertData.custom_icon_path = body.iconPath as string | null;
  }

  const { error } = await supabase.from("team_names").upsert(
    upsertData,
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
