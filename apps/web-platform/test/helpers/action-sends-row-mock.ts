/**
 * Shared in-memory supabase `from(...)` store for the dashboard send-route tests (#10543).
 *
 * Why a stateful store and not per-test chain stubs: the route now reads `action_sends` before it writes, and the
 * contract it protects (a re-click after archive is `not_a_draft`; an archive failure leaves the draft replayable)
 * is a STATE TRANSITION, which a stub that answers every query identically cannot observe. The store therefore
 *   - honors `.eq()` filters on `select(...).maybeSingle()` (dropping a filter from the route reads a foreign row),
 *   - projects ONLY the requested columns (dropping a column from the route's select returns `undefined`), and
 *   - applies `update(patch).eq(...)` to the matching rows, so `messages.status` really flips.
 *
 * `action_sends` is read-only here: the route's own insert goes through the mocked `writeActionSend`, which tests
 * control separately (the WORM insert is out of scope for this store).
 */

export interface MessageRowShape {
  id: string;
  user_id: string;
  action_class: string;
  status: string;
  draft_preview: string | null;
  owning_domain: string | null;
  template_id: string;
  source_ref: string;
}

export interface ActionSendRowShape {
  id: string;
  message_id: string;
  user_id: string;
  per_send_body_sha256: string | null;
  tier_at_send: string;
  clicked_at: string | null;
  acknowledged_at: string | null;
  failure_reason: string | null;
  undone_at: string | null;
  cancellation_requested_at: string | null;
}

type AnyRow = Record<string, unknown>;
type Filter = [string, unknown];

export interface StoreOptions {
  message: MessageRowShape;
  /** Pre-existing `action_sends` rows (default none). */
  actionSends?: ActionSendRowShape[];
  /** Called with a short event name as the store is exercised (e.g. "messages-archive"). */
  onEvent?: (event: string) => void;
}

export interface ActionSendsStore {
  /** Pass as the `from` implementation of the mocked supabase client. */
  from: (table: string) => unknown;
  messages: MessageRowShape[];
  actionSends: ActionSendRowShape[];
  /** Filters of every `messages.update(...)` call, in order (assert `["status","draft"]` is among them). */
  archiveFilters: Filter[][];
  /** Columns requested by every `action_sends.select(...)` call. */
  actionSendsSelects: string[][];
  /** Make the next `action_sends` lookup fail with this error. */
  failLookup: (err?: { message: string; code?: string }) => void;
  /** Make the next `messages.update(...)` fail with this error (the row is NOT updated). */
  failNextArchive: (err?: { message: string; code?: string }) => void;
  /** The next `messages.update(...)` succeeds without error but matches no row (RLS-hidden shape). */
  hideNextArchive: () => void;
  messageStatus: () => string;
  archiveCount: () => number;
}

// PostgREST answers an unknown column with 42703 at runtime (the client is untyped, so tsc is
// blind to it); the store throws instead of projecting `undefined`, so a mistyped or renamed
// column in the route's select goes red here rather than reading as a "null" field.
function project(row: AnyRow, cols: string[]): AnyRow {
  const out: AnyRow = {};
  for (const c of cols) {
    if (!(c in row)) throw new Error(`unknown column: ${c}`);
    out[c] = row[c];
  }
  return out;
}

export function createActionSendsStore(opts: StoreOptions): ActionSendsStore {
  const messages: MessageRowShape[] = [{ ...opts.message }];
  const actionSends: ActionSendRowShape[] = (opts.actionSends ?? []).map((r) => ({
    ...r,
  }));
  const archiveFilters: Filter[][] = [];
  const actionSendsSelects: string[][] = [];
  let lookupError: { message: string; code?: string } | null = null;
  let archiveError: { message: string; code?: string } | null = null;
  const emit = (e: string) => opts.onEvent?.(e);

  function matching(rows: AnyRow[], filters: Filter[]): AnyRow[] {
    return rows.filter((r) => filters.every(([c, v]) => r[c] === v));
  }

  function selectBuilder(table: "messages" | "action_sends", colsArg: string) {
    const cols = colsArg.split(",").map((c) => c.trim());
    if (table === "action_sends") actionSendsSelects.push(cols);
    const filters: Filter[] = [];
    const chain = {
      eq(col: string, val: unknown) {
        filters.push([col, val]);
        return chain;
      },
      async maybeSingle() {
        if (table === "action_sends" && lookupError) {
          const error = lookupError;
          lookupError = null;
          return { data: null, error };
        }
        const rows = (table === "messages" ? messages : actionSends) as unknown as AnyRow[];
        const hit = matching(rows, filters)[0];
        return { data: hit ? project(hit, cols) : null, error: null };
      },
    };
    return chain;
  }

  let hideArchive = false;

  function updateBuilder(patch: AnyRow) {
    const filters: Filter[] = [];
    let returning = false;
    const chain = {
      eq(col: string, val: unknown) {
        filters.push([col, val]);
        return chain;
      },
      // `.select("id")` after an update makes the awaited result carry the matched rows.
      select(_cols: string) {
        returning = true;
        return chain;
      },
      // Thenable: `await supabase.from(...).update(...).eq(...)` resolves here.
      then(
        resolve: (v: {
          data?: AnyRow[];
          error: { message: string; code?: string } | null;
        }) => unknown,
        reject?: (e: unknown) => unknown,
      ) {
        try {
          archiveFilters.push([...filters]);
          if (archiveError) {
            const error = archiveError;
            archiveError = null;
            emit("messages-archive-failed");
            return Promise.resolve({ error }).then(resolve, reject);
          }
          const hit = hideArchive ? [] : matching(messages as unknown as AnyRow[], filters);
          hideArchive = false;
          for (const r of hit) {
            Object.assign(r, patch);
          }
          emit("messages-archive");
          return Promise.resolve(
            returning ? { data: hit.map((r) => ({ id: r.id })), error: null } : { error: null },
          ).then(resolve, reject);
        } catch (e) {
          return Promise.reject(e).then(resolve, reject);
        }
      },
    };
    return chain;
  }

  return {
    from(table: string) {
      if (table === "messages") {
        return {
          select: (cols: string) => selectBuilder("messages", cols),
          update: (patch: AnyRow) => updateBuilder(patch),
        };
      }
      if (table === "action_sends") {
        return { select: (cols: string) => selectBuilder("action_sends", cols) };
      }
      throw new Error(`unexpected table: ${table}`);
    },
    messages,
    actionSends,
    archiveFilters,
    actionSendsSelects,
    failLookup(err = { message: "lookup failed", code: "XX000" }) {
      lookupError = err;
    },
    /** The next `messages.update(...)` succeeds without error but matches no row (RLS-hidden shape). */
    hideNextArchive() {
      hideArchive = true;
    },
    failNextArchive(err = { message: "archive failed", code: "XX000" }) {
      archiveError = err;
    },
    messageStatus: () => messages[0].status,
    archiveCount: () => archiveFilters.length,
  };
}

/** Build a pending (unacknowledged, unfailed, not undone) `action_sends` row; override fields per test. */
export function pendingActionSendRow(
  over: Partial<ActionSendRowShape> & Pick<ActionSendRowShape, "message_id" | "user_id">,
): ActionSendRowShape {
  return {
    id: "44444444-4444-4444-aaaa-444444444444",
    per_send_body_sha256: null,
    tier_at_send: "draft_one_click",
    clicked_at: new Date().toISOString(),
    acknowledged_at: null,
    failure_reason: null,
    undone_at: null,
    cancellation_requested_at: null,
    ...over,
  };
}
