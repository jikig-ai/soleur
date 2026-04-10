import { NextResponse } from "next/server";
import { createClient } from "@/lib/supabase/server";

export async function GET() {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) {
    return NextResponse.json({ isAdmin: false });
  }

  const isAdmin =
    process.env.ADMIN_USER_IDS?.split(",").includes(user.id) ?? false;

  return NextResponse.json({ isAdmin });
}
