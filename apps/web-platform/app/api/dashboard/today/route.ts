// PR-H (#3244) Phase 6 — server-side data loader for the dashboard
// Today section, widened to multi-source signals.
//
// Returns the caller's draft messages with inline ranking (15 LoC):
//   1. Strict-tier sort: urgency='critical' > 'high' > 'normal' > 'low' (+ legacy 'medium').
//   2. Within tier: score = recency × severity × leader_confidence (placeholder
//      until per-source scoring lands; recency-only today via created_at DESC).
//   3. Slice cap at 7 items in `items`; remainder in `extras` for client
//      "Show N more".
//
// Cache-Control: private, max-age=60 — minimizes Art. 14 surface on
// third-party-ingested content (per plan TR6 amendment) and prevents
// rapid-refresh re-redact-thrash. 60s window is bounded by the
// brand-survival threshold's acceptable freshness.
//
// Uses createClient() (cookie-scoped, RLS-enforced) so a malformed query
// CANNOT leak cross-founder rows. Belt-and-suspenders: explicit
// .eq("user_id", user.id) filter alongside table-level RLS.
//
// ACTIVE-WORKSPACE SCOPING (workspace-leak fix, 2026-06-02): the read is
// ALSO scoped to the caller's SELECTED workspace via
// .eq("workspace_id", resolveCurrentWorkspaceId(...)). `messages` RLS is
// is_workspace_member(workspace_id, auth.uid()), which an OWNER satisfies for
// EVERY workspace they own — so RLS is NOT the cross-workspace guard here. A
// solo-pinned draft card (e.g. a KB-drift digest about Soleur's company repo,
// pinned to the operator's solo workspace) would otherwise render on every
// workspace the owner switches to. The explicit workspace_id filter is the
// actual scoping; RLS is defense-in-depth. resolveCurrentWorkspaceId falls
// back to the solo workspace (= userId), never a sibling.
//
// Per cq-nextjs-route-files-http-only-exports — only HTTP method handlers
// are exported.

import { NextResponse } from "next/server";
import { createClient } from "@/lib/supabase/server";
import { resolveCurrentWorkspaceId } from "@/server/workspace-resolver";
import logger from "@/server/logger";
import { reportSilentFallback } from "@/server/observability";
import { RUNTIME_COST_DISCLOSURE } from "@/lib/legal/disclosures";
import {
  MESSAGE_TIER_EXTERNAL_BRAND_CRITICAL,
  MESSAGE_TIER_EXTERNAL_LOW_STAKES,
  MESSAGE_STATUS_DRAFT,
} from "@/lib/messages/tiers";

interface TodayRow {
  id: string;
  source: string;
  source_ref: string | null;
  owning_domain: string;
  draft_preview: string;
  urgency: string;
  created_at: string;
}

interface TodayItem {
  id: string;
  source: string;
  sourceRef: string | null;
  owningDomain: string;
  draftPreview: string;
  urgency: string;
  createdAt: string;
}

// CVE advisory bodies (`${ghsa_id} (${severity}): ${summary}`) carry
// free-text summaries whose copy can include secret-shape strings the
// redaction allowlist won't catch (proprietary cloud account IDs etc).
// The card renders ID + severity by default (AC6) and reveals the body
// only on explicit Edit-modal click. On the wire we drop the summary
// (everything after the first `:`) so devtools / Network tab cannot
// surface what the DOM intentionally hides. The Edit modal fetches the
// full body via a separate, audited endpoint (PR-H+1).
//
// Secret-scan rows (`Secret scan alert #<n>: <secret_type>`) are NOT
// stripped — `secret_type` is GitHub's public classification enum
// (`aws_access_key_id`, `slack_bot_token`, etc.), not the secret value
// itself, so it is safe to include on the wire.
function maskBodyForCveSecretScan(row: TodayRow): string {
  if (row.source !== "github" || row.source_ref === null) return row.draft_preview;
  if (!row.source_ref.startsWith("cve-")) return row.draft_preview;
  const colonIdx = row.draft_preview.indexOf(":");
  return colonIdx === -1 ? row.draft_preview : row.draft_preview.slice(0, colonIdx);
}

function toItem(row: TodayRow): TodayItem {
  return {
    id: row.id,
    source: row.source,
    sourceRef: row.source_ref,
    owningDomain: row.owning_domain,
    draftPreview: maskBodyForCveSecretScan(row),
    urgency: row.urgency,
    createdAt: row.created_at,
  };
}

const URGENCY_ORDER: Record<string, number> = {
  critical: 0,
  high: 1,
  // 'medium' is the legacy CFO value (PR-F); rank between 'high' and 'normal'
  // so existing rows keep their relative position when multi-source lands.
  medium: 2,
  normal: 3,
  low: 4,
};

// Inline ranking (plan-review P2 simplification — no separate module).
// Strict-tier sort first; within tier, recency desc (created_at DESC).
// Score multiplication wires when per-source severity + leader confidence
// land alongside the strategy table evolution.
function rank(a: TodayItem, b: TodayItem): number {
  const ua = URGENCY_ORDER[a.urgency] ?? 99;
  const ub = URGENCY_ORDER[b.urgency] ?? 99;
  if (ua !== ub) return ua - ub;
  return b.createdAt.localeCompare(a.createdAt);
}

const TODAY_ITEM_CAP = 7;

export async function GET(_req: Request) {
  const supabase = await createClient();
  const { data: auth, error: authErr } = await supabase.auth.getUser();
  if (authErr || !auth?.user) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }
  const userId = auth.user.id;

  // Resolve the caller's ACTIVE workspace (claim → solo fallback, never a
  // sibling). Drives the workspace_id filter below so cards pinned to one of
  // the owner's workspaces do not bleed onto another. Read-only; the cookie
  // tenant client reads only its own user_session_state row (RLS).
  const activeWorkspaceId = await resolveCurrentWorkspaceId(userId, supabase);

  // Select widens to BOTH external tiers — PR-F's external_brand_critical
  // (CFO drafts) and PR-H's external_low_stakes (GitHub + KB-drift). Both
  // are bound by the messages_external_tier_status_check CHECK constraint
  // (migration 046) to status='draft' / 'archived'.
  const { data, error } = await supabase
    .from("messages")
    .select("id, source, source_ref, owning_domain, draft_preview, urgency, created_at")
    .eq("user_id", userId)
    .eq("workspace_id", activeWorkspaceId)
    .in("tier", [MESSAGE_TIER_EXTERNAL_BRAND_CRITICAL, MESSAGE_TIER_EXTERNAL_LOW_STAKES])
    .eq("status", MESSAGE_STATUS_DRAFT)
    .order("created_at", { ascending: false })
    .limit(50);

  if (error) {
    reportSilentFallback(error, {
      feature: "dashboard-today",
      op: "select-drafts",
      message: "Failed to load Today drafts",
      extra: { userId },
    });
    logger.error({ err: error }, "dashboard-today: select failed");
    return NextResponse.json({ error: "Internal error" }, { status: 500 });
  }

  const all = (data ?? []).map((r) => toItem(r as TodayRow)).sort(rank);
  const items = all.slice(0, TODAY_ITEM_CAP);
  const extras = all.slice(TODAY_ITEM_CAP);

  return NextResponse.json(
    { items, extras, disclosure: RUNTIME_COST_DISCLOSURE },
    {
      headers: {
        // Per plan §Risks R4 + GDPR gate row 2: minimize Art. 14 surface
        // for third-party-ingested text. private = no shared proxy cache;
        // max-age=60 caps the freshness drift.
        "Cache-Control": "private, max-age=60",
      },
    },
  );
}
