// In-process MCP tools for the operator email-triage inbox (AC11 —
// agent-native parity). Mirrors the `conversations-tools.ts` factoring:
// userId is captured in the builder closure (never tool input) and every
// query runs on the tenant-scoped client so RLS stays load-bearing.
//
// READ-ONLY surface — FR9 boundary: status transitions (acknowledge /
// archive) are operator-UI-only in v1. There is deliberately NO
// email_triage_set_status / acknowledge / archive tool here: a
// prompt-injected agent auto-acknowledging a DSAR would silently unpin a
// statutory clock. If a write tool ever ships it must be `gated`-tier,
// never auto-approve (#4671/#4672).
//
// Filter + ordering semantics mirror GET /api/inbox/emails EXACTLY (see
// `app/api/inbox/emails/route.ts` header) — keep both in lockstep.

import { tool } from "@anthropic-ai/claude-agent-sdk";
import { z } from "zod/v4";
import { getFreshTenantClient } from "@/lib/supabase/tenant";
import {
  STATUTORY_RULES,
  computeDueDate,
  formatDueDate,
} from "@/server/email-triage/statutory-rules";

interface BuildEmailTriageToolsOpts {
  /** Captured in closure — prevents cross-user reads. */
  userId: string;
}

type ToolTextResponse = {
  content: Array<{ type: "text"; text: string }>;
  isError?: true;
};

function textResponse(payload: unknown, isError = false): ToolTextResponse {
  const body: ToolTextResponse = {
    content: [{ type: "text", text: JSON.stringify(payload) }],
  };
  if (isError) body.isError = true;
  return body;
}

const LIST_COLUMNS =
  "id, user_id, message_id, sender, subject, summary, mail_class, " +
  "statutory_class, rule_id, status, status_changed_at, acknowledged_at, " +
  "received_at, created_at";

interface TriageListRow {
  statutory_class: string | null;
  status: string;
}

// Stable partition: pinned group keeps its received_at DESC order, as does
// the rest. Small deliberate duplicate of the route's helper — a shared
// module would pull this file's agent-SDK import into the HTTP route.
function statutoryPinnedFirst<T extends TriageListRow>(rows: T[]): T[] {
  const isPinned = (r: T) => r.statutory_class !== null && r.status === "new";
  return [...rows.filter(isPinned), ...rows.filter((r) => !isPinned(r))];
}

export function buildEmailTriageTools(opts: BuildEmailTriageToolsOpts) {
  const { userId } = opts;
  return [
    tool(
      "email_triage_list",
      "List the operator's email-triage inbox items (summaries of mail " +
        "received at the ops@ address — bodies are discarded at ingestion; " +
        "the original mail lives in the operator's Proton ops@ mailbox). " +
        "Mirrors GET /api/inbox/emails exactly: unfinalized stub rows are " +
        "never returned; probe rows (mail_class='probe') are excluded " +
        "unless includeProbes is true; archived items are excluded unless " +
        "status='archived'. Ordering: unacknowledged statutory items " +
        "(statutory_class set AND status='new') pinned first, then " +
        "received_at descending. Returns an array of full rows (id, " +
        "sender, subject, summary, mail_class, statutory_class, rule_id, " +
        "status, received_at, ...). Read-only — status changes are " +
        "operator-UI-only in v1.",
      {
        includeProbes: z.boolean().optional().default(false),
        status: z.literal("archived").optional(),
      },
      async (args) => {
        const tenant = await getFreshTenantClient(userId);
        // RLS on email_triage_items is owner-SELECT; the explicit user_id
        // filter is belt-and-suspenders parity with the HTTP route.
        let query = tenant
          .from("email_triage_items")
          .select(LIST_COLUMNS)
          .eq("user_id", userId)
          .or("mail_class.not.is.null,statutory_class.not.is.null");

        // NULL-safe probe exclusion: plain .neq would also drop
        // mail_class IS NULL statutory fast-path rows (SQL 3VL).
        if (!args.includeProbes) {
          query = query.or("mail_class.is.null,mail_class.neq.probe");
        }

        query =
          args.status === "archived"
            ? query.eq("status", "archived")
            : query.neq("status", "archived");

        const { data, error } = await query.order("received_at", {
          ascending: false,
        });

        if (error) {
          return textResponse({ error: "List failed", code: "list_failed" }, true);
        }
        return textResponse(
          statutoryPinnedFirst((data ?? []) as unknown as TriageListRow[]),
        );
      },
    ),
    tool(
      "email_triage_get",
      "Fetch one email-triage item by id. For statutory items (breach, " +
        "service-of-process, dsar, regulator) the response additionally " +
        "carries the server-side-derived legal clock: dueDate (ISO), " +
        "dueLabel (human string), and catalogExcerpt (the obligation from " +
        "the statutory response catalog). These derive from received_at + " +
        "the statutory registry — NEVER compute or invent statutory " +
        "periods yourself; treat the returned clock as authoritative. " +
        "The email body is not stored (parse-and-discard); only the " +
        "summary persists — the original mail is in the operator's Proton " +
        "ops@ mailbox. Read-only — acknowledge/archive are operator-UI-" +
        "only in v1.",
      { id: z.string().uuid() },
      async (args) => {
        const tenant = await getFreshTenantClient(userId);
        const { data, error } = await tenant
          .from("email_triage_items")
          .select("*")
          .eq("id", args.id)
          .eq("user_id", userId)
          .maybeSingle();

        if (error) {
          return textResponse({ error: "Get failed", code: "get_failed" }, true);
        }
        // Missing row and foreign row collapse (RLS + user_id filter) —
        // no existence oracle, matching the status RPC's 42501 posture.
        if (!data) {
          return textResponse({ error: "Not found", code: "not_found" }, true);
        }

        const row = data as Record<string, unknown> & {
          statutory_class: string | null;
          rule_id: string | null;
          received_at: string;
        };

        if (row.statutory_class !== null) {
          const rule = STATUTORY_RULES.find((r) => r.ruleId === row.rule_id);
          if (rule) {
            return textResponse({
              ...row,
              dueDate: computeDueDate(row.received_at, rule.dueRule).toISOString(),
              dueLabel: formatDueDate(row.received_at, rule.dueRule),
              catalogExcerpt: rule.catalogExcerpt,
            });
          }
          // Registry drift (rule_id not in STATUTORY_RULES): surface the
          // gap explicitly rather than letting the agent invent a period.
          return textResponse({
            ...row,
            dueDate: null,
            dueLabel: null,
            catalogExcerpt: null,
            statutoryClockNote:
              "statutory rule not found in registry — verify the deadline " +
              "against the original mail in the operator's Proton ops@ mailbox",
          });
        }

        return textResponse(row);
      },
    ),
  ];
}
