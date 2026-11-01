// POST /api/internal/home-census — counts-only census of the shared HOME (Ref #10455).
//
// Secret-gated (INNGEST_MANUAL_TRIGGER_SECRET, Bearer header only: no cookie, no query string), passive
// (nothing arms it), synchronous, and sunset by a constant in server/home-census.ts. All behaviour lives in
// handleHomeCensus; a route file may export only HTTP methods (cq-nextjs-route-files-http-only-exports).
// Same CSRF-exempt class as trigger-cron / schedule-reminder (cookieless, not browser-reachable).
// Removal is tracked in #11714.

import { handleHomeCensus } from "@/server/home-census";

export async function POST(request: Request): Promise<Response> {
  return handleHomeCensus(request);
}
