// #9545 PR2 — server loader for the workspace egress audit view and the Scope Grants card hint.
//
// There is no HTTP route (CTO ruling 2026-10-26): the page and the card call the RPC directly through
// the caller's cookie (tenant) client, exactly like the rest of the settings pages.
//
// Authorization is the RPC's alone (migration 177: `is_workspace_member(p_workspace_id, auth.uid())`,
// SQLSTATE 42501 otherwise). This loader never decides who may read; it decides WHICH workspace to
// ask about and how to render each outcome, under these rules:
//
//   1. The workspace id comes ONLY from `readWorkspaceIdFromDb`, the fail-loud reader. It is never an
//      argument and never read from a request. The shared `resolveCurrentWorkspaceId` falls back to
//      the user's own id on a failed lookup, which would show a team member their personal workspace's
//      log with nothing saying so. A null pointer is `unbound`, a throw or a timeout is `unavailable`,
//      and the RPC is not called in either case.
//   2. Expected outcomes are values, never throws: forbidden / unbound / unavailable / ready. An error
//      is therefore never rendered as an empty log.
//   3. `forbidden` is ONLY the RPC's own in-body denial: SQLSTATE 42501 AND a message starting with
//      RPC_DENIAL_PREFIX (migration 177 raises exactly those). The database engine uses the same
//      SQLSTATE for a lost EXECUTE grant ("permission denied for function ..."); that is a fault, not
//      a denial, so it is mirrored and renders `unavailable`.
//   4. Faults are mirrored with the reason in `op`, `err = null` and a STATIC message, so each reason is
//      its own Sentry issue group and the tag-filtered alert rule matches (an Error object would let the
//      pino mirror capture it first and de-duplicate the tagged event away). A reply error adds only a
//      low-cardinality `pg_code` tag. No workspace id, host or other value ever reaches a mirror.
//   5. Exactly two emitters exist, and the op is a string literal at every call site (the alert
//      contract test derives the paged and unpaged op sets from this file):
//        fault(op, ...)  error level, the paged class (Terraform filter: rpc_error, rpc_timeout,
//                        workspace_read_error);
//        warn(op, ...)   warning level, debounced, UNPAGED (decorative reads: the card hint, the
//                        collection state, the web-access state). Searchable as feature:egress-audit-read.
//   6. The card hint is decorative: any failure hides it, at warning level, and never throws into the page.
//   7. Flag outage: the collection state is tri-state. When Flagsmith did not answer, the value is
//      "unknown" (never the env mirror's guess) and the view renders its unavailable state. Ingest keeps
//      the plain boolean; an outage there reads "off" so nothing is stored.

import type { SupabaseClient } from "@supabase/supabase-js";
import { readEgressAuditCollectionState } from "@/server/egress-audit-collection";
import { mirrorWarnWithDebounce, reportSilentFallback } from "@/server/observability";
import { readWorkspaceIdFromDb } from "@/server/workspace-resolver";
import {
  isEgressAuditPayload,
  PAGE_LIMIT,
  RPC_DENIAL_PREFIX,
  toRpcDecision,
  type CollectionState,
  type DecisionFilter,
  type EgressAuditResult,
  type EgressCardState,
} from "@/lib/egress-audit/summary";

const FEATURE = "egress-audit-read";
export { FEATURE as EGRESS_AUDIT_READ_FEATURE };

// Destination page. The summary RPC is the page's one essential read; the pointer read before it and the
// collection / web-access reads after it are bounded tighter so a degraded database cannot stack them.
const PAGE_TIMEOUT_MS = 8_000;
const PAGE_POINTER_TIMEOUT_MS = 2_000;
const PAGE_AUX_TIMEOUT_MS = 1_500;
// Scope Grants card: decorative, so every read is short and the whole load is capped (the hint is one
// backward primary-key probe, expected under 5 ms; these bounds are for a degraded database).
const CARD_POINTER_TIMEOUT_MS = 600;
const CARD_ORG_TIMEOUT_MS = 800;
const HINT_TIMEOUT_MS = 800;
const CARD_OVERALL_TIMEOUT_MS = 1_200;

// The result and state types live in lib/egress-audit/summary.ts (client-safe); re-exported for existing importers.
export type { CollectionState, EgressAuditResult, EgressCardState };

type RpcError = { code?: string; message?: string; name?: string } | null;
type Reply = { data: unknown; error: RpcError };

type PgTags = { pg_code: string };

// The only mirror emitters. `fault` is the paged class; `warn` is unpaged and debounced per op.
function fault(op: string, message: string, tags?: PgTags): void {
  reportSilentFallback(null, { feature: FEATURE, op, message, ...(tags ? { tags } : {}) });
}
function warn(op: string, message: string, tags?: PgTags): void {
  mirrorWarnWithDebounce(null, { feature: FEATURE, op, message, ...(tags ? { tags } : {}) }, FEATURE, op);
}

// Low-cardinality SQLSTATE / PostgREST code for a tag: the code itself when it has a known shape, else a bucket.
function pgTag(code: unknown): PgTags {
  if (typeof code !== "string" || code === "") return { pg_code: "none" };
  return { pg_code: /^[0-9A-Z]{5}$/.test(code) || /^PGRST\d{3}$/.test(code) ? code : "other" };
}

const isAbort = (e: NonNullable<RpcError>): boolean =>
  e.name === "AbortError" || e.name === "TimeoutError" || /abort|timed? ?out/i.test(e.message ?? "");

// The RPC's own denial (migration 177): SQLSTATE 42501 with a message from the function body. The engine's
// "permission denied for function ..." carries the same SQLSTATE and is NOT a denial.
const isRpcDenial = (e: NonNullable<RpcError>): boolean =>
  e.code === "42501" && typeof e.message === "string" && e.message.startsWith(RPC_DENIAL_PREFIX);

function call(supabase: SupabaseClient, fn: string, args: Record<string, unknown>, timeoutMs: number): PromiseLike<Reply> {
  return supabase.rpc(fn, args).abortSignal(AbortSignal.timeout(timeoutMs));
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

type Pointer = { kind: "id"; id: string } | { kind: "unbound" } | { kind: "threw" } | { kind: "timeout" };

/** The current-workspace pointer, fail-loud and bounded; the caller decides how (and at which level) to mirror. */
async function readPointer(supabase: SupabaseClient, userId: string, timeoutMs: number): Promise<Pointer> {
  try {
    const id = await bounded(readWorkspaceIdFromDb(userId, supabase), timeoutMs);
    if (id === "timeout") return { kind: "timeout" };
    return id ? { kind: "id", id } : { kind: "unbound" };
  } catch {
    return { kind: "threw" };
  }
}

async function readCollection(
  supabase: SupabaseClient,
  wsId: string,
  onFault: (op: string) => void,
  timeoutMs: number,
): Promise<{ collection: CollectionState; workspaceName: string | null }> {
  let orgId: string;
  let workspaceName: string | null;
  try {
    const r = await bounded(supabase.from("workspaces").select("organization_id, name").eq("id", wsId).maybeSingle(), timeoutMs);
    if (r === "timeout" || r.error || !r.data?.organization_id) {
      onFault("org_read");
      return { collection: "unknown", workspaceName: null };
    }
    orgId = r.data.organization_id;
    workspaceName = typeof r.data.name === "string" ? r.data.name : null;
  } catch {
    onFault("org_read");
    return { collection: "unknown", workspaceName: null };
  }
  // readEgressAuditCollectionState does not throw on a Flagsmith outage (it answers "unknown"); the catch and the
  // bound below are defensive, for a flag client that throws or hangs.
  try {
    const collection = await bounded(readEgressAuditCollectionState(orgId), timeoutMs);
    if (collection === "timeout") {
      onFault("flag_eval");
      return { collection: "unknown", workspaceName };
    }
    return { collection, workspaceName };
  } catch {
    onFault("flag_eval");
    return { collection: "unknown", workspaceName };
  }
}

async function readWebAccess(supabase: SupabaseClient, wsId: string): Promise<boolean | null> {
  try {
    const r = await bounded(call(supabase, "get_workspace_web_egress", { p_workspace_id: wsId }, PAGE_AUX_TIMEOUT_MS), PAGE_AUX_TIMEOUT_MS);
    if (r === "timeout") {
      warn("web_access_read", "egress audit read: web access state timed out");
      return null;
    }
    if (r.error) {
      warn("web_access_read", "egress audit read: web access state could not be read", pgTag(r.error.code));
      return null;
    }
    if (typeof r.data !== "boolean") {
      warn("web_access_read", "egress audit read: web access state was not a boolean");
      return null;
    }
    return r.data;
  } catch {
    warn("web_access_read", "egress audit read: web access state read failed");
    return null;
  }
}

/** Destination page: the 30-day summary for the caller's current workspace. Never throws. */
export async function loadEgressAudit(
  supabase: SupabaseClient,
  userId: string,
  filter: DecisionFilter,
): Promise<EgressAuditResult> {
  const pointer = await readPointer(supabase, userId, PAGE_POINTER_TIMEOUT_MS);
  if (pointer.kind === "timeout") {
    fault("workspace_read_error", "egress audit read: current workspace pointer read timed out");
    return { kind: "unavailable" };
  }
  if (pointer.kind === "threw") {
    fault("workspace_read_error", "egress audit read: current workspace pointer could not be read");
    return { kind: "unavailable" };
  }
  if (pointer.kind === "unbound") return { kind: "unbound" };
  const ws = pointer.id;

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
    const replyError = reply.error;
    const aborted = isAbort(replyError);
    if (isRpcDenial(replyError)) return { kind: "forbidden" };
    if (aborted) {
      fault("rpc_timeout", "egress audit read: summary call timed out", pgTag(replyError.code));
    } else if (replyError.code === "42501") {
      fault("rpc_error", "egress audit read: summary call was refused by the database", pgTag(replyError.code));
    } else {
      fault("rpc_error", "egress audit read: summary call failed", pgTag(replyError.code));
    }
    return { kind: "unavailable" };
  }
  if (!isEgressAuditPayload(reply.data)) {
    fault("rpc_error", "egress audit read: summary body was malformed");
    return { kind: "unavailable" };
  }

  // Started only after the RPC succeeded: a failing or slow summary call never waits behind these two reads.
  const [{ collection, workspaceName }, webAccess] = await Promise.all([
    readCollection(supabase, ws, (op) => warn(op, "egress audit read: collection state could not be determined"), PAGE_AUX_TIMEOUT_MS),
    readWebAccess(supabase, ws),
  ]);
  return { kind: "ready", data: reply.data, collection, webAccess, workspaceName };
}

/** The last recorded request for the card; null hides the hint. */
async function readHint(supabase: SupabaseClient, ws: string): Promise<string | null> {
  try {
    const r = await bounded(call(supabase, "get_egress_audit_summary", { p_workspace_id: ws, p_limit: 0, p_decision: null }, HINT_TIMEOUT_MS), HINT_TIMEOUT_MS);
    if (r === "timeout") {
      warn("hint_timeout", "egress audit read: last-request probe timed out");
      return null;
    }
    if (r.error) {
      const replyError = r.error;
      const aborted = isAbort(replyError);
      if (isRpcDenial(replyError)) return null; // the expected denial (a removed member): nothing to report
      if (aborted) {
        warn("hint_timeout", "egress audit read: last-request probe timed out", pgTag(replyError.code));
      } else {
        warn("hint_rpc_error", "egress audit read: last-request probe failed", pgTag(replyError.code));
      }
      return null;
    }
    return isEgressAuditPayload(r.data) ? r.data.summary.last_request_at : null;
  } catch {
    warn("hint_rpc_error", "egress audit read: last-request probe failed");
    return null;
  }
}

async function loadEgressCardStateInner(supabase: SupabaseClient, userId: string): Promise<EgressCardState> {
  const hide: EgressCardState = { lastRequestAt: null, collection: "unknown", workspaceId: null };

  const pointer = await readPointer(supabase, userId, CARD_POINTER_TIMEOUT_MS);
  if (pointer.kind === "timeout") {
    warn("hint_workspace_read", "egress audit read: current workspace pointer read timed out");
    return hide;
  }
  if (pointer.kind === "threw") {
    warn("hint_workspace_read", "egress audit read: current workspace pointer could not be read");
    return hide;
  }
  if (pointer.kind === "unbound") return hide;
  const ws = pointer.id;

  // The hint probe and the collection lookup are independent: start both, await both.
  const [lastRequestAt, { collection }] = await Promise.all([
    readHint(supabase, ws),
    readCollection(supabase, ws, (op) => warn(op, "egress audit read: collection state could not be determined"), CARD_ORG_TIMEOUT_MS),
  ]);
  return { lastRequestAt, collection, workspaceId: ws };
}

/**
 * Scope Grants card: the last recorded request, the collection state and the workspace they were read for.
 * Never throws; any failure (or the overall bound) hides the hint.
 */
export async function loadEgressCardState(supabase: SupabaseClient, userId: string): Promise<EgressCardState> {
  try {
    const out = await bounded(loadEgressCardStateInner(supabase, userId), CARD_OVERALL_TIMEOUT_MS);
    if (out !== "timeout") return out;
    warn("hint_timeout", "egress audit read: card state load timed out");
  } catch {
    warn("hint_rpc_error", "egress audit read: card state load failed");
  }
  return { lastRequestAt: null, collection: "unknown", workspaceId: null };
}
