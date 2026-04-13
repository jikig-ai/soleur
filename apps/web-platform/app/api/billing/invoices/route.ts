import { NextResponse } from "next/server";
import { createClient } from "@/lib/supabase/server";
import { getStripe } from "@/lib/stripe";

export async function GET() {
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
    return NextResponse.json({ invoices: [] });
  }

  const stripeInvoices = await getStripe().invoices.list({
    customer: userData.stripe_customer_id,
    limit: 24,
    status: "paid",
  });

  const invoices = stripeInvoices.data.map((inv) => ({
    id: inv.id,
    date: inv.created,
    amount: inv.amount_paid,
    currency: inv.currency,
    status: inv.status,
    hostedUrl: inv.hosted_invoice_url,
    pdfUrl: inv.invoice_pdf,
  }));

  return NextResponse.json({ invoices });
}
