import { NextResponse } from "next/server";
import { createClient } from "@/lib/supabase/server";
import { getStripe } from "@/lib/stripe";
import { validateOrigin, rejectCsrf } from "@/lib/auth/validate-origin";

export async function POST(request: Request) {
  const { valid, origin } = validateOrigin(request);
  if (!valid) return rejectCsrf("api/checkout", origin);

  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  // Check existing billing state to reuse Stripe customer and block double-subscribe
  const { data: userData } = await supabase
    .from("users")
    .select("stripe_customer_id, subscription_status")
    .eq("id", user.id)
    .single();

  if (userData?.subscription_status === "active") {
    return NextResponse.json(
      { error: "Already subscribed" },
      { status: 400 },
    );
  }

  const appOrigin = process.env.NEXT_PUBLIC_APP_URL ?? "https://app.soleur.ai";

  const session = await getStripe().checkout.sessions.create({
    ...(userData?.stripe_customer_id
      ? { customer: userData.stripe_customer_id }
      : { customer_email: user.email }),
    mode: "subscription",
    line_items: [{ price: process.env.STRIPE_PRICE_ID!, quantity: 1 }],
    success_url: `${appOrigin}/dashboard?checkout=success`,
    cancel_url: `${appOrigin}/dashboard?checkout=cancelled`,
    metadata: { supabase_user_id: user.id },
  });

  return NextResponse.json({ url: session.url });
}
