import { createClient } from "@/lib/supabase/server";
import { NextResponse } from "next/server";

export async function GET(request: Request) {
  const { searchParams, origin } = new URL(request.url);
  const code = searchParams.get("code");

  if (code) {
    const supabase = await createClient();
    const { error } = await supabase.auth.exchangeCodeForSession(code);

    if (!error) {
      // Check if user has an API key set up
      const {
        data: { user },
      } = await supabase.auth.getUser();

      if (user) {
        const { data: keys } = await supabase
          .from("api_keys")
          .select("id")
          .eq("user_id", user.id)
          .eq("is_valid", true)
          .limit(1);

        // Redirect to key setup if no valid key, otherwise dashboard
        if (!keys || keys.length === 0) {
          return NextResponse.redirect(`${origin}/setup-key`);
        }
        return NextResponse.redirect(`${origin}/dashboard`);
      }
    }
  }

  // Auth failed — redirect to login with error
  return NextResponse.redirect(`${origin}/login?error=auth_failed`);
}
