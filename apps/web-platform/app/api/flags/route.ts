import { getFeatureFlags } from "@/lib/feature-flags/server";
import { NextResponse } from "next/server";

export async function GET() {
  return NextResponse.json(getFeatureFlags());
}
