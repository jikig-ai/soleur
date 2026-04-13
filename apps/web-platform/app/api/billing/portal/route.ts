import { NextResponse } from "next/server";
import { createClient } from "@/lib/supabase/server";
import { getStripe } from "@/lib/stripe";
import { validateOrigin, rejectCsrf } from "@/lib/auth/validate-origin";

export async function POST(request: Request) {
  const { valid, origin } = validateOrigin(request);
  if (!valid) return rejectCsrf("api/billing/portal", origin);

  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const { data: userData } = await supabase
    .from("users")
    .select("stripe_customer_id")
    .eq("id", user.id)
    .single();

  if (!userData?.stripe_customer_id) {
    return NextResponse.json({ error: "No subscription" }, { status: 400 });
  }

  const appOrigin = process.env.NEXT_PUBLIC_APP_URL ?? "https://app.soleur.ai";

  const portalSession = await getStripe().billingPortal.sessions.create({
    customer: userData.stripe_customer_id,
    return_url: `${appOrigin}/dashboard/settings`,
  });

  return NextResponse.json({ url: portalSession.url });
}
