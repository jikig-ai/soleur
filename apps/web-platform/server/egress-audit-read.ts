// #9545 PR2 — server loader for the workspace egress audit view and the Scope Grants card hint.
//
// There is no HTTP route (CTO ruling 2026-10-26): the page and the card call the RPC directly through
// the caller's cookie (tenant) client, exactly like the rest of the settings pages.
//
// Authorization is the RPC's alone (migration 177: `is_workspace_member(p_workspace_id, auth.uid())`,
// SQLSTATE 42501 otherwise). This loader never decides who may read; it decides WHICH workspace to
// ask about and how to render each outcome, under four rules:
//
//   1. The workspace id comes ONLY from `readWorkspaceIdFromDb`, the fail-loud reader. It is never an
//      argument and never read from a request. The shared `resolveCurrentWorkspaceId` falls back to
//      the user's own id on a failed lookup, which would show a team member their personal workspace's
//      log with nothing saying so. A null pointer is `unbound`, a throw is `unavailable`, and the RPC
//      is not called in either case.
//   2. Expected outcomes are values, never throws: forbidden / unbound / unavailable / ready. An error
//      is therefore never rendered as an empty log.
//   3. Faults are mirrored with the reason in `op`, `err = null` and a STATIC message, so each reason is
//      its own Sentry issue group and the tag-filtered alert rule matches (an Error object would let the
//      pino mirror capture it first and de-duplicate the tagged event away). No workspace id, host or
//      other value ever reaches a mirror. The expected 42501 denial is never mirrored.
//   4. The card hint is decorative: any failure hides it, at warning level, debounced (it can repeat on
//      every page load), and never throws into the page.

import type { SupabaseClient } from "@supabase/supabase-js";
import { isEgressAuditCollectionOn } from "@/server/egress-audit-collection";
import { mirrorWarnWithDebounce, reportSilentFallback } from "@/server/observability";
import { readWorkspaceIdFromDb } from "@/server/workspace-resolver";
import {
  isEgressAuditPayload,
  toRpcDecision,
  type DecisionFilter,
  type EgressAuditPayload,
} from "@/lib/egress-audit/summary";

const FEATURE = "egress-audit-read";
export { FEATURE as EGRESS_AUDIT_READ_FEATURE };

const PAGE_LIMIT = 200;
const PAGE_TIMEOUT_MS = 8_000;
// The hint is one backward primary-key probe (expected under 5 ms); this bound is for a degraded database.
const HINT_TIMEOUT_MS = 800;

export type CollectionState = true | false | "unknown";

export type EgressAuditResult =
  | {
      kind: "ready";
      data: EgressAuditPayload;
      collection: CollectionState;
      /** null = the read failed or returned null (unknown), which the view treats as unavailable for the empties. */
      webAccess: boolean | null;
      workspaceName: string | null;
    }
  | { kind: "forbidden" }
  | { kind: "unbound" }
  | { kind: "unavailable" };

export type EgressCardState = { lastRequestAt: string | null; collection: CollectionState };

type RpcError = { code?: string; message?: string; name?: string } | null;
type Reply = { data: unknown; error: RpcError };

const isAbort = (e: NonNullable<RpcError>): boolean =>
  e.name === "AbortError" || e.name === "TimeoutError" || /abort|timed? ?out/i.test(e.message ?? "");

function call(supabase: SupabaseClient, fn: string, args: Record<string, unknown>, timeoutMs: number): PromiseLike<Reply> {
  const q = supabase.rpc(fn, args) as unknown as {
    abortSignal?: (s: AbortSignal) => PromiseLike<Reply>;
  } & PromiseLike<Reply>;
  return typeof q.abortSignal === "function" ? q.abortSignal(AbortSignal.timeout(timeoutMs)) : q;
}

// A fetch that ignores the signal must not hold the page: race the call against the same bound.
function bounded<T>(p: PromiseLike<T>, ms: number): Promise<T | "timeout"> {
  return new Promise((resolve, reject) => {
    const t = setTimeout(() => resolve("timeout"), ms);
    Promise.resolve(p).then(
      (v) => {
        clearTimeout(t);
        resolve(v);
      },
      (e) => {
        clearTimeout(t);
        reject(e);
      },
    );
  });
}

/** workspace pointer -> id | "unbound" | "unavailable"; mirrors a throw (error level on the page). */
async function workspaceId(
  supabase: SupabaseClient,
  userId: string,
  onThrow: () => void,
): Promise<string | "unbound" | "unavailable"> {
  try {
    const id = await readWorkspaceIdFromDb(userId, supabase as never);
    return id ?? "unbound";
  } catch {
    onThrow();
    return "unavailable";
  }
}

async function readCollection(
  supabase: SupabaseClient,
  wsId: string,
  onFault: (op: string) => void,
): Promise<{ collection: CollectionState; workspaceName: string | null }> {
  let orgId: string | null = null;
  let workspaceName: string | null = null;
  try {
    const { data, error } = (await supabase
      .from("workspaces")
      .select("organization_id, name")
      .eq("id", wsId)
      .maybeSingle()) as { data: { organization_id?: string; name?: string } | null; error: unknown };
    if (error || !data?.organization_id) {
      onFault("org_read");
      return { collection: "unknown", workspaceName: null };
    }
    orgId = data.organization_id;
    workspaceName = typeof data.name === "string" ? data.name : null;
  } catch {
    onFault("org_read");
    return { collection: "unknown", workspaceName: null };
  }
  try {
    return { collection: await isEgressAuditCollectionOn(orgId), workspaceName };
  } catch {
    onFault("flag_eval");
    return { collection: "unknown", workspaceName };
  }
}

async function readWebAccess(supabase: SupabaseClient, wsId: string): Promise<boolean | null> {
  try {
    const r = (await call(supabase, "get_workspace_web_egress", { p_workspace_id: wsId }, PAGE_TIMEOUT_MS)) as Reply;
    if (r.error) return null;
    return typeof r.data === "boolean" ? r.data : null;
  } catch {
    return null;
  }
}

/** Destination page: the 30-day summary for the caller's current workspace. Never throws. */
export async function loadEgressAudit(
  supabase: SupabaseClient,
  userId: string,
  filter: DecisionFilter,
): Promise<EgressAuditResult> {
  const fault = (op: string, message: string) => reportSilentFallback(null, { feature: FEATURE, op, message });

  const ws = await workspaceId(supabase, userId, () =>
    fault("workspace_read_error", "egress audit read: current workspace pointer could not be read"),
  );
  if (ws === "unbound") return { kind: "unbound" };
  if (ws === "unavailable") return { kind: "unavailable" };

  let reply: Reply | "timeout";
  try {
    reply = await bounded(
      call(supabase, "get_egress_audit_summary", { p_workspace_id: ws, p_limit: PAGE_LIMIT, p_decision: toRpcDecision(filter) }, PAGE_TIMEOUT_MS),
      PAGE_TIMEOUT_MS,
    );
  } catch {
    fault("rpc_error", "egress audit read: summary call failed");
    return { kind: "unavailable" };
  }
  if (reply === "timeout") {
    fault("rpc_timeout", "egress audit read: summary call timed out");
    return { kind: "unavailable" };
  }
  if (reply.error) {
    if (reply.error.code === "42501") return { kind: "forbidden" };
    fault(isAbort(reply.error) ? "rpc_timeout" : "rpc_error", isAbort(reply.error) ? "egress audit read: summary call timed out" : "egress audit read: summary call failed");
    return { kind: "unavailable" };
  }
  if (!isEgressAuditPayload(reply.data)) {
    fault("rpc_error", "egress audit read: summary body was malformed");
    return { kind: "unavailable" };
  }

  const [{ collection, workspaceName }, webAccess] = await Promise.all([
    readCollection(supabase, ws, (op) =>
      mirrorWarnWithDebounce(null, { feature: FEATURE, op, message: "egress audit read: collection state could not be determined" }, FEATURE, op),
    ),
    readWebAccess(supabase, ws),
  ]);
  return { kind: "ready", data: reply.data, collection, webAccess, workspaceName };
}

/** Scope Grants card: the last recorded request and the collection state. Never throws; any failure hides the hint. */
export async function loadEgressCardState(supabase: SupabaseClient, userId: string): Promise<EgressCardState> {
  const hide: EgressCardState = { lastRequestAt: null, collection: "unknown" };
  const warn = (op: string, message: string) =>
    mirrorWarnWithDebounce(null, { feature: FEATURE, op, message }, FEATURE, op);

  const ws = await workspaceId(supabase, userId, () =>
    warn("workspace_read_error", "egress audit read: current workspace pointer could not be read"),
  );
  if (ws === "unbound" || ws === "unavailable") return hide;

  // The hint probe and the collection lookup are independent: start both, await both.
  const hint = (async (): Promise<string | null> => {
    try {
      const r = await bounded(call(supabase, "get_egress_audit_summary", { p_workspace_id: ws, p_limit: 0, p_decision: null }, HINT_TIMEOUT_MS), HINT_TIMEOUT_MS);
      if (r === "timeout") {
        warn("hint_timeout", "egress audit read: last-request probe timed out");
        return null;
      }
      if (r.error) {
        if (r.error.code !== "42501") {
          const timedOut = isAbort(r.error);
          warn(timedOut ? "hint_timeout" : "hint_rpc_error", "egress audit read: last-request probe failed");
        }
        return null;
      }
      return isEgressAuditPayload(r.data) ? r.data.summary.last_request_at : null;
    } catch {
      warn("hint_rpc_error", "egress audit read: last-request probe failed");
      return null;
    }
  })();
  const [lastRequestAt, { collection }] = await Promise.all([
    hint,
    readCollection(supabase, ws, (op) => warn(op, "egress audit read: collection state could not be determined")),
  ]);
  return { lastRequestAt, collection };
}
