import { NextResponse } from "next/server";
import { createClient } from "@/lib/supabase/server";
import { getStripe } from "@/lib/stripe";
import {
  invoiceEndpointThrottle,
  logRateLimitRejection,
} from "@/server/rate-limiter";
import { verifiedUserId } from "@/server/request-auth";

export async function GET(request: Request) {
  const supabase = await createClient();
  const userId = await verifiedUserId(request);

  if (!userId) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  // Per-user rate limit — defense-in-depth behind Cloudflare. Keyed by user.id
  // so throttle applies consistently across IPs (corporate NAT, dev, etc.) and
  // unauthenticated requests (handled above) cannot pollute the bucket.
  if (!invoiceEndpointThrottle.isAllowed(userId)) {
    logRateLimitRejection("invoice-endpoint", userId);
    return NextResponse.json(
      { error: "Too many requests" },
      { status: 429, headers: { "Retry-After": "60" } },
    );
  }

  const { data: userData } = await supabase
    .from("users")
    .select("stripe_customer_id")
    .eq("id", userId)
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

  const res = NextResponse.json({ invoices });
  res.headers.set("Cache-Control", "private, max-age=300");
  return res;
}
