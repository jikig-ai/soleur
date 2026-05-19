// PR-G (#3947) — Server-only Inngest HTTP API proxy. INNGEST_SIGNING_KEY
// is the read-API auth credential (event key is write-only for SDK
// ingestion). Self-hosted Inngest exposes /v1/* at INNGEST_BASE_URL
// (ADR-030: bound to 127.0.0.1:8288 on the Hetzner host).
//
// This module is consumed ONLY by app/api/dashboard/runs/route.ts (server
// route). TR7 (test/lint/inngest-key-server-only.test.ts) grep-asserts
// INNGEST_SIGNING_KEY is absent from app/(dashboard)/** and components/**.

const UUID_RE =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export interface RunSummary {
  id: string;
  startedAt: string | null;
  endedAt: string | null;
  status: string;
  actionClass: string;
  tierAtTimeOfEvent: string | null;
  customerIdMasked: string;
}

interface InngestEvent {
  id: string;
  data: {
    founderId?: string;
    tier?: string;
    payload?: {
      invoiceId?: string;
      customerId?: string;
    };
  };
}

interface InngestRun {
  id: string;
  started_at: string | null;
  ended_at: string | null;
  status: string;
}

interface ListRunsParams {
  founderId: string;
  limit: number;
}

export async function listInngestRunsForFounder({
  founderId,
  limit,
}: ListRunsParams): Promise<RunSummary[]> {
  // Defense-in-depth env-guard. Doppler drift would otherwise surface as
  // a cryptic URL/fetch error.
  const baseUrl = process.env.INNGEST_BASE_URL;
  const signingKey = process.env.INNGEST_SIGNING_KEY;
  if (!baseUrl) throw new Error("INNGEST_BASE_URL not set");
  if (!signingKey) throw new Error("INNGEST_SIGNING_KEY not set");

  // UUID shape check before composing the CEL filter. founderId is sourced
  // from supabase.auth.getUser() today (UUID-shaped), but the helper is
  // exported — defend against future callers passing user-controlled data
  // into a CEL string interpolation (Kieran P1-2).
  if (!UUID_RE.test(founderId)) {
    throw new Error("invalid founderId shape");
  }

  // Step 1: list events whose data.founderId == this founder.
  // CEL filter is the canonical Inngest 2026 path per best-practices research.
  const eventsUrl = new URL("/v1/events", baseUrl);
  eventsUrl.searchParams.set("name", "finance.payment_failed");
  eventsUrl.searchParams.set("cel", `event.data.founderId=='${founderId}'`);
  eventsUrl.searchParams.set("limit", String(limit));

  const eventsRes = await fetch(eventsUrl, {
    headers: { Authorization: `Bearer ${signingKey}` },
  });
  if (!eventsRes.ok) {
    throw new Error(`inngest_api_error: ${eventsRes.status}`);
  }
  const eventsBody = (await eventsRes.json()) as { data: InngestEvent[] };
  const events = eventsBody.data ?? [];

  // Step 2: fan out to runs per event.
  const runs: RunSummary[] = [];
  for (const event of events) {
    const runsUrl = new URL(`/v1/events/${event.id}/runs`, baseUrl);
    const runsRes = await fetch(runsUrl, {
      headers: { Authorization: `Bearer ${signingKey}` },
    });
    if (!runsRes.ok) continue; // partial: one event's runs may 404
    const runsBody = (await runsRes.json()) as { data: InngestRun[] };
    for (const run of runsBody.data ?? []) {
      // Return raw (masked) customer-id; the sole renderer is
      // components/audit/redacted-event-summary.tsx (TR for composition).
      runs.push({
        id: run.id,
        startedAt: run.started_at,
        endedAt: run.ended_at,
        status: run.status,
        actionClass: "finance.payment_failed",
        tierAtTimeOfEvent: event.data.tier ?? null,
        customerIdMasked: maskCustomerId(event.data.payload?.customerId),
      });
    }
  }

  return runs;
}

function maskCustomerId(id: string | undefined): string {
  if (!id || id.length < 4) return "cus_***";
  return `${id.slice(0, 4)}***`;
}
