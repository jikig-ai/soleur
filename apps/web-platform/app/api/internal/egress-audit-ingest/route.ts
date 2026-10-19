// #9545 PR1 — Vector -> app ingest for the egress audit rollup. HTTP-method exports
// only (cq-nextjs-route-files-http-only-exports); all logic lives in
// server/egress-audit-ingest.ts. Bearer-gated, loopback-only, dark by default.
import { handleEgressAuditIngest } from "@/server/egress-audit-ingest";

export async function POST(request: Request) {
  return handleEgressAuditIngest(request);
}
