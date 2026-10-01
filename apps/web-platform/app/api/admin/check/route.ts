import { NextResponse } from "next/server";
import { verifiedUserId } from "@/server/request-auth";

export async function GET(req: Request) {
  // verifiedUserId reads the middleware-minted identity header (no auth RTT);
  // absent header falls back to getUser() — fail-closed. The route stays a
  // public surface: e2e suites exercise it directly.
  const userId = await verifiedUserId(req);

  if (!userId) {
    return NextResponse.json({ isAdmin: false });
  }

  const isAdmin =
    process.env.ADMIN_USER_IDS?.split(",").includes(userId) ?? false;

  return NextResponse.json({ isAdmin });
}
