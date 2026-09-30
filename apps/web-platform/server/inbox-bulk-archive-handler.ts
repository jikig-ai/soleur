/**
 * Handler for POST /api/inbox/bulk-archive (feat-inbox-bulk-archive, #9284).
 * Thin route file (cq-nextjs-route-files-http-only-exports) delegates here.
 *
 * Auth: caller wraps this in `withUserRateLimit` + the user-context Supabase
 * client (NEVER the service client). Rows are fetched with `.in("id", ids)`
 * on the user-context client — RLS makes foreign-workspace rows invisible, so
 * the RPC's authz and the SELECT policies are the same predicate (missing +
 * foreign collapse to `not_found`, preserving the no-existence-oracle
 * convention of the single-id handlers).
 *
 * Eligibility is classified client-independently via the shared
 * `lib/inbox-archive-eligibility` predicate — a submitted-but-ineligible id
 * (statutory email, un-acted action_required, acknowledged, already-archived)
 * returns `guarded` + reason and the RPC is NEVER invoked for it. A P0001
 * from the RPC then unambiguously means `conflict` (the row became ineligible
 * between prefetch and dispatch — or an unclassified guard fired). mig 153
 * additionally pins statutory rows at the DB level.
 *
 * Soft deadline: sequential per-id RPCs in one request risk outliving the
 * client's pending watchdog (30 s). On expiry the remaining ids flush as
 * `error` — the response always lands before the UI re-enables Archive;
 * partial application is reported honestly (archived rows stay archived on
 * retry; retries are idempotent).
 *
 * Responses:
 *   200 { results: [{id, kind, outcome, reason?}] } — always one entry per
 *       (deduped) submitted id, in request order.
 *   400  malformed body / >200 items / non-UUID / unknown kind
 *   401 / 429  wrapper
 *   500  prefetch query failure (Sentry-mirrored; ids only, no PII)
 */

import { NextResponse } from "next/server";
import type { VerifiedUser } from "@/server/request-auth";
import { createClient } from "@/lib/supabase/server";
import { reportSilentFallback } from "@/server/observability";
import {
  emailRowEligibility,
  inboxRowEligibility,
  keyOf,
  type ArchiveEligibilityReason,
  type BulkItemRef,
  type BulkItemResult,
  type BulkOutcome,
} from "@/lib/inbox-archive-eligibility";

const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

const MAX_ITEMS = 200;
/** PostgREST `in` filter rides the request line — 200 UUIDs ≈ 7.4 KB; chunked
 * to keep headroom under typical ~8 KB ingress limits. */
const PREFETCH_CHUNK = 100;
/** Soft deadline inside the dispatch loop. Must land under the client-side
 * PENDING_WATCHDOG_MS (30 s) so the response arrives before the watchdog
 * re-enables the Archive button — a retry racing a still-mutating zombie
 * would let the zombie's residual-selection write clobber the new run's.
 * ~30-60 ms/RPC covers the 200-item cap; a cold leg (20-38 s) overflows to
 * honest `error` outcomes instead. */
const SOFT_DEADLINE_MS = 25_000;

const MAX_BODY_BYTES = 65_536; // 200 {kind,id} entries ≈ 15 KB; bound req.json()

function parseItems(
  body: unknown,
): { items: BulkItemRef[] } | { error: string } {
  const raw = (body as { items?: unknown } | null)?.items;
  if (!Array.isArray(raw) || raw.length === 0 || raw.length > MAX_ITEMS) {
    return { error: "items must be an array of 1-200 entries" };
  }
  const seen = new Set<string>();
  const items: BulkItemRef[] = [];
  for (const entry of raw) {
    const { kind, id } = (entry ?? {}) as { kind?: unknown; id?: unknown };
    if (
      (kind !== "inbox" && kind !== "email") ||
      typeof id !== "string" ||
      !UUID_PATTERN.test(id)
    ) {
      return { error: "each item needs {kind: inbox|email, id: uuid}" };
    }
    // Normalize case — the regex is /i but keyOf is case-sensitive; a
    // case-variant duplicate would double-dispatch the same row.
    const ref: BulkItemRef = { kind, id: id.toLowerCase() };
    const key = keyOf(ref);
    if (seen.has(key)) continue;
    seen.add(key);
    items.push(ref);
  }
  return { items };
}

type Supabase = Awaited<ReturnType<typeof createClient>>;

async function fetchRows<T extends { id: string }>(
  supabase: Supabase,
  table: string,
  select: string,
  ids: string[],
): Promise<{ rows: Map<string, T> } | { error: unknown }> {
  const rows = new Map<string, T>();
  for (let i = 0; i < ids.length; i += PREFETCH_CHUNK) {
    const chunk = ids.slice(i, i + PREFETCH_CHUNK);
    const { data, error } = await supabase.from(table).select(select).in("id", chunk);
    if (error) return { error };
    for (const row of (data ?? []) as unknown as T[]) rows.set(row.id, row);
  }
  return { rows };
}

export async function inboxBulkArchiveHandler(req: Request, user: VerifiedUser) {
  const declaredBytes = Number(req.headers.get("content-length") ?? 0);
  if (declaredBytes > MAX_BODY_BYTES) {
    return NextResponse.json({ error: "Payload too large" }, { status: 413 });
  }
  const body = await req.json().catch(() => null);
  const parsed = parseItems(body);
  if ("error" in parsed) {
    return NextResponse.json({ error: parsed.error }, { status: 400 });
  }
  const { items } = parsed;

  const supabase = await createClient();

  const inboxIds = items.filter((i) => i.kind === "inbox").map((i) => i.id);
  const emailIds = items.filter((i) => i.kind === "email").map((i) => i.id);

  // Independent fetches — parallel, not serial (the cold-path latency is
  // inside the same 25 s soft deadline the dispatch loop budgets).
  const [inbox, emails] = await Promise.all([
    fetchRows<{
      id: string;
      severity: string;
      acted_at: string | null;
      status: string;
    }>(supabase, "inbox_item", "id, severity, acted_at, status", inboxIds),
    fetchRows<{
      id: string;
      status: string;
      statutory_class: string | null;
    }>(
      supabase,
      "email_triage_items",
      "id, status, statutory_class",
      emailIds,
    ),
  ]);
  for (const res of [inbox, emails]) {
    if ("error" in res) {
      reportSilentFallback(res.error, {
        feature: "inbox",
        op: "bulk-archive",
        message: "bulk-archive prefetch failed",
        extra: { userId: user.id },
      });
    }
  }
  if ("error" in inbox || "error" in emails) {
    return NextResponse.json({ error: "Internal error" }, { status: 500 });
  }

  const KIND = {
    inbox: {
      rows: inbox.rows,
      eligible: inboxRowEligibility as (r: unknown) => ArchiveEligibilityReason,
      rpc: (id: string) =>
        supabase.rpc("set_inbox_item_state", { p_id: id, p_action: "archived" }),
    },
    email: {
      rows: emails.rows,
      eligible: emailRowEligibility as (r: unknown) => ArchiveEligibilityReason,
      rpc: (id: string) =>
        supabase.rpc("set_email_triage_status", { p_id: id, p_status: "archived" }),
    },
  } as const;

  const results: BulkItemResult[] = [];
  const deadline = Date.now() + SOFT_DEADLINE_MS;

  for (const item of items) {
    const k = KIND[item.kind];
    const row = k.rows.get(item.id);
    if (row === undefined) {
      // RLS-invisible (foreign workspace, missing) — no oracle.
      results.push({ ...item, outcome: "not_found" });
      continue;
    }
    const reason = k.eligible(row);
    if (reason !== "ok") {
      results.push({ ...item, outcome: "guarded", reason });
      continue;
    }

    if (Date.now() >= deadline) {
      // Soft deadline tripped — the response still lands before the client's
      // pending watchdog releases the Archive button; retries are safe.
      // Mirrored once per flush so a chronically slow path pages someone.
      reportSilentFallback(new Error("bulk-archive soft deadline"), {
        feature: "inbox",
        op: "bulk-archive",
        message: "soft deadline flushed remaining items",
        extra: { userId: user.id, remaining: items.length - results.length },
      });
      results.push({ ...item, outcome: "error" });
      continue;
    }

    const { error } = await k.rpc(item.id);

    if (!error) {
      results.push({ ...item, outcome: "archived" });
    } else if (
      error.code === "42501" &&
      // Both RPCs raise 42501 for auth.uid() IS NULL ("authenticated callers
      // only") as well as missing/foreign rows ("not authorized"). A dropped
      // session mid-batch must not read as "already handled" — that's an
      // error, not not_found. (Single-id routes keep the 404 collapse; bulk
      // amplifies it into a whole-batch false report.)
      !/authenticated callers only/i.test(error.message ?? "")
    ) {
      results.push({ ...item, outcome: "not_found" });
    } else if (error.code === "P0001") {
      results.push({ ...item, outcome: "conflict" });
    } else {
      // No PII: ids only.
      reportSilentFallback(error, {
        feature: "inbox",
        op: "bulk-archive",
        message: `${item.kind} archive RPC failed`,
        extra: { userId: user.id, itemId: item.id, kind: item.kind },
      });
      results.push({ ...item, outcome: "error" });
    }
  }

  return NextResponse.json({ results });
}
