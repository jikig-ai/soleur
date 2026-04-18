import { getFeatureFlags } from "@/lib/feature-flags/server";
import { NextResponse } from "next/server";

// No rate limit: returns static server feature-flag state — no DB/FS cost,
// no per-user key, no auth. Audit outcome from #2510 step 4.
export async function GET() {
  return NextResponse.json(getFeatureFlags());
}
