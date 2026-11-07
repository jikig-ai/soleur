/**
 * The requester label on an Owner's approval card (#9601, ADR-309 flip item 1 limb i): who raised the request.
 *
 * CONTRACT. This module reads another member's EMAIL with the service role inside the agent-shared process. It is
 * Owner-only by construction, not by caller discipline alone: the single membership read proves the VIEWER is an Owner of
 * the ROW's workspace before any address is read, and test/approval/render-sink-scan.test.ts pins who may import it
 * (gate.ts, ws-handler.ts and the Owner landing page; the file is on the CODEOWNERS-pinned service-role allowlist).
 *
 *   - ids: every id passes `isUuid` before it reaches a filter; filters are built with `.eq()` / `.in()` only, never a
 *     filter string.
 *   - scope: ONE `workspace_members` read for (workspace_id = row's workspace) AND user_id in (viewer, requester). The
 *     viewer row must have role `owner` (else `undefined`); the requester row must exist (else the fixed fallback: the
 *     requester left, or was never a member of that workspace).
 *   - source of the address: the AUTHORITATIVE auth record (`auth.admin.getUserById`), NOT `public.users.email`, which any
 *     authenticated member can overwrite (migrations 006 and 178) and so could make the Owner's card say anything.
 *   - shape: kept only when a string of 1 to 320 characters with exactly one `@` and no whitespace or control characters
 *     (320 is the wire cap; it also guarantees a real label never collides with the in-band "you" and fallback literals).
 *   - bounded: one deadline of 2 seconds per `label()` call covers both reads (the PostgREST read carries the abort
 *     signal; `auth.admin` has no abort support, so it is raced against the same signal). A timeout trips the instance:
 *     later lookups omit at once, so a sequential reattach loop costs at most one wait.
 *   - never throws; a failure is ONE `requesterLabelFailed` report (ids and an error code, never the address or database
 *     text) and the key is omitted, because the fallback would assert a membership fact the code could not check.
 *   - memo: success AND failure, per labeler instance (one per attach / per landing render), keyed by workspace and
 *     requester (a conversation's rows can sit in different workspaces). Nothing is cached across instances.
 */

import { createServiceClient } from "@/lib/supabase/service";
import { REQUESTER_FALLBACK } from "@/lib/approval-copy";
import { isUuid } from "@/lib/is-uuid";
import type { RequesterLabelFn } from "./card-visibility";
import { reportApprovalOp } from "./ops";

/** A PostgREST-shaped result. */
export interface RequesterQueryResult<T> {
  data: T | null;
  error: unknown;
}

/** The slice of the service client the labeler reads through. */
export interface RequesterQueryClient {
  from(table: string): {
    select(columns: string): {
      eq(column: string, value: string): {
        in(
          column: string,
          values: string[],
        ): {
          abortSignal(signal: AbortSignal): PromiseLike<RequesterQueryResult<Array<{ user_id: string; role: string }>>>;
        };
      };
    };
  };
  auth: {
    admin: {
      getUserById(id: string): PromiseLike<RequesterQueryResult<{ user: { email?: string | null } | null }>>;
    };
  };
}

export interface RequesterLabelerOptions {
  /** Test seam: the deadline signal of ONE lookup (default `AbortSignal.timeout(2000)`). */
  signal?: () => AbortSignal;
}

/** One lookup, both reads. */
export const REQUESTER_LABEL_DEADLINE_MS = 2000;
const MAX_LABEL_LENGTH = 320;
const UNSAFE_CHARS = /[\s\u0000-\u001f\u007f]/;

class LabelDeadlineError extends Error {
  readonly code = "timeout";
  constructor() {
    super("requester label deadline");
    this.name = "LabelDeadlineError";
  }
}

/** Race a read against the lookup's signal; the listener is removed on settle. */
function withDeadline<T>(read: PromiseLike<T>, signal: AbortSignal): Promise<T> {
  return new Promise<T>((resolve, reject) => {
    if (signal.aborted) {
      reject(new LabelDeadlineError());
      return;
    }
    const onAbort = () => reject(new LabelDeadlineError());
    signal.addEventListener("abort", onAbort, { once: true });
    Promise.resolve(read).then(
      (v) => {
        signal.removeEventListener("abort", onAbort);
        resolve(v);
      },
      (e) => {
        signal.removeEventListener("abort", onAbort);
        reject(e);
      },
    );
  });
}

function usableAddress(v: unknown): v is string {
  if (typeof v !== "string" || v.length === 0 || v.length > MAX_LABEL_LENGTH) return false;
  if (UNSAFE_CHARS.test(v)) return false;
  return v.split("@").length === 2;
}

export function createRequesterLabeler(getClient?: () => RequesterQueryClient, opts: RequesterLabelerOptions = {}): RequesterLabelFn {
  // Resolved on the FIRST lookup that needs it, never at construction or import.
  let client: RequesterQueryClient | null = null;
  const resolveClient = (): RequesterQueryClient =>
    (client ??= (getClient ?? (() => createServiceClient() as unknown as RequesterQueryClient))());
  const newSignal = opts.signal ?? (() => AbortSignal.timeout(REQUESTER_LABEL_DEADLINE_MS));
  const memo = new Map<string, Promise<string | undefined>>();
  let tripped = false;

  const lookup = async (workspaceId: string, viewerUserId: string, requestedBy: string): Promise<string | undefined> => {
    const signal = newSignal();
    // Both failure paths (a read error and a deadline) go through this ONE report helper.
    const fail = (err: unknown, stage: "membership" | "auth"): undefined => {
      if (err instanceof LabelDeadlineError || signal.aborted) tripped = true;
      reportApprovalOp("requesterLabelFailed", err, { workspaceId, userId: viewerUserId, extra: { stage } });
      return undefined;
    };

    let stage: "membership" | "auth" = "membership";
    try {
      const c = resolveClient();
      const members = await withDeadline(
        c.from("workspace_members").select("user_id, role").eq("workspace_id", workspaceId).in("user_id", [viewerUserId, requestedBy]).abortSignal(signal),
        signal,
      );
      if (members.error) return fail(members.error, "membership");
      const rows = Array.isArray(members.data) ? members.data : [];
      // The Owner proof lives here, in the same read: only an Owner of THIS row's workspace is shown another member's address.
      if (!rows.some((r) => r.user_id === viewerUserId && r.role === "owner")) return undefined;
      if (!rows.some((r) => r.user_id === requestedBy)) return REQUESTER_FALLBACK;

      stage = "auth";
      const auth = await withDeadline(c.auth.admin.getUserById(requestedBy), signal);
      if (auth.error) return fail(auth.error, "auth");
      const email = auth.data?.user?.email;
      return usableAddress(email) ? email : REQUESTER_FALLBACK;
    } catch (err) {
      return fail(err, stage);
    }
  };

  return async (workspaceId, viewerUserId, requestedBy) => {
    try {
      if (!isUuid(workspaceId) || !isUuid(viewerUserId)) return undefined;
      // NULL (erased account), empty or malformed: nothing to look up, and nothing to verify either.
      if (typeof requestedBy !== "string" || !isUuid(requestedBy)) return REQUESTER_FALLBACK;
      const key = `${workspaceId}:${requestedBy}`;
      const hit = memo.get(key);
      if (hit) return await hit;
      if (tripped) return undefined;
      const p = lookup(workspaceId, viewerUserId, requestedBy);
      memo.set(key, p);
      return await p;
    } catch {
      return undefined;
    }
  };
}
