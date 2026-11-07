// Phase 0.3 record (#4672): the per-tool canonical field lists, confirmed against each tool's REAL zod
// schema (the drift test in canonical-schema-drift.test.ts introspects the schemas the tool builders pass to
// the SDK `tool()` and compares them to `FIELD_LISTS` below, so this record cannot rot).
//
// Synthesized data only (cq-test-fixtures-synthesized-only): reserved example domains, UUID-shaped ids.

export const WORKSPACE_ID = "00000000-0000-4000-8000-000000000001";
export const OTHER_WORKSPACE_ID = "00000000-0000-4000-8000-000000000002";
export const CONVERSATION_ID = "00000000-0000-4000-8000-000000000003";
export const OTHER_CONVERSATION_ID = "00000000-0000-4000-8000-000000000004";
export const MESSAGE_ID = "00000000-0000-4000-8000-000000000005";
export const APPROVAL_ID = "00000000-0000-4000-8000-000000000006";
export const USER_ID = "00000000-0000-4000-8000-000000000007";

const P = "mcp__soleur_platform__";

export const TOOLS = {
  emailSend: `${P}email_send`,
  emailReply: `${P}email_reply`,
  emailSuppress: `${P}email_suppress`,
  pushBranch: `${P}github_push_branch`,
  createPr: `${P}create_pull_request`,
  triggerWorkflow: `${P}github_trigger_workflow`,
  kbShareCreate: `${P}kb_share_create`,
  setAutonomous: `${P}workspace_set_autonomous`,
} as const;

/**
 * `input`: every zod field the tool accepts (all of them change what runs, so all are hashed).
 * `server`: fields the model cannot supply (derived by the platform at gate time) that still change what runs.
 * `defaults`: zod defaults the handler applies, which the canonical object must apply too so an omitted
 *   field and its default value are the SAME action.
 */
export const FIELD_LISTS: Record<
  string,
  { builder: string; input: string[]; server: string[]; defaults: Record<string, unknown> }
> = {
  [TOOLS.emailSend]: {
    builder: "email-triage-tools",
    input: ["to", "subject", "body", "replyTo", "jurisdiction", "postalAddress", "optOut", "ftcDisclosure", "art14"],
    server: [],
    defaults: { jurisdiction: "unknown" },
  },
  [TOOLS.emailReply]: {
    builder: "email-triage-tools",
    input: ["messageId", "subject", "body", "jurisdiction", "postalAddress", "optOut", "ftcDisclosure", "art14"],
    server: ["recipient"],
    defaults: { jurisdiction: "unknown" },
  },
  [TOOLS.emailSuppress]: {
    builder: "email-triage-tools",
    input: ["recipient", "reason"],
    server: [],
    defaults: {},
  },
  [TOOLS.pushBranch]: {
    builder: "github-tools",
    input: ["branch", "force"],
    server: ["repo", "headSha"],
    defaults: { force: false },
  },
  [TOOLS.createPr]: {
    builder: "github-tools",
    input: ["head", "base", "title", "body"],
    server: ["repo"],
    defaults: { base: "main" },
  },
  [TOOLS.triggerWorkflow]: {
    builder: "github-tools",
    input: ["workflow_id", "ref", "inputs"],
    server: ["repo"],
    defaults: {},
  },
  [TOOLS.kbShareCreate]: {
    builder: "kb-share-tools",
    input: ["documentPath"],
    server: [],
    defaults: {},
  },
  [TOOLS.setAutonomous]: {
    builder: "workspace-settings-tools",
    input: ["value"],
    server: [],
    defaults: {},
  },
};

export const SHA40 = "a91c3e2a91c3e2a91c3e2a91c3e2a91c3e2a91c3";

export interface Sample {
  input: Record<string, unknown>;
  server: Record<string, unknown>;
}

/** One full-field sample per tool: every optional field set, so a field dropped from the canonical object is visible. */
export const SAMPLES: Record<string, Sample> = {
  [TOOLS.emailSend]: {
    input: {
      to: "maria@example.test",
      subject: "Updated pricing",
      body: "Hello Maria,\nconfirmed.",
      replyTo: "dana@example.test",
      jurisdiction: "eu_uk",
      postalAddress: "1 Example Street, Exampleville",
      optOut: "Reply STOP to opt out.",
      ftcDisclosure: "This is a commercial message.",
      art14: {
        identity: "Example Co",
        purpose: "pricing follow-up",
        legalBasis: "legitimate interest",
        dataSource: "public directory",
        retention: "12 months",
        rights: "access, erasure",
      },
    },
    server: {},
  },
  [TOOLS.emailReply]: {
    input: {
      messageId: MESSAGE_ID,
      subject: "Re: pricing",
      body: "Confirmed.",
      jurisdiction: "us",
      postalAddress: "1 Example Street, Exampleville",
      optOut: "Reply STOP to opt out.",
      ftcDisclosure: "This is a commercial message.",
      art14: { identity: "Example Co" },
    },
    server: { recipient: "sender@example.test" },
  },
  [TOOLS.emailSuppress]: {
    input: { recipient: "promo@example.test", reason: "opt_out" },
    server: {},
  },
  [TOOLS.pushBranch]: {
    input: { branch: "feat/pricing", force: false },
    server: { repo: "example-org/example-repo", headSha: SHA40 },
  },
  [TOOLS.createPr]: {
    input: { head: "feat/pricing", base: "main", title: "Pricing refresh", body: "Updates tier names." },
    server: { repo: "example-org/example-repo" },
  },
  [TOOLS.triggerWorkflow]: {
    input: { workflow_id: 4242, ref: "feat/pricing", inputs: { environment: "preview", notify: "false" } },
    server: { repo: "example-org/example-repo" },
  },
  [TOOLS.kbShareCreate]: {
    input: { documentPath: "knowledge-base/pricing/q4.md" },
    server: {},
  },
  [TOOLS.setAutonomous]: {
    input: { value: true },
    server: {},
  },
};

/** The set of input keys of a sample whose change MUST flip the hash, per tool (every field of the tool). */
export function mutateField(tool: string, field: string): Sample {
  const s = structuredClone(SAMPLES[tool]);
  const bag = field in s.input ? s.input : s.server;
  const cur = bag[field];
  // Fields with a constrained domain need a DIFFERENT VALID value, or zod rejects the mutation instead of hashing it.
  const alt: Record<string, unknown> = {
    jurisdiction: cur === "us" ? "eu_uk" : "us",
    reason: "decline",
    messageId: "00000000-0000-0000-0000-000000000000",
    headSha: `${String(cur).slice(0, -1)}b`,
  };
  if (field in alt) bag[field] = alt[field];
  else if (typeof cur === "string") bag[field] = `${cur}x`;
  else if (typeof cur === "boolean") bag[field] = !cur;
  else if (typeof cur === "number") bag[field] = cur + 1;
  else if (cur && typeof cur === "object") bag[field] = { ...(cur as object), identity: "Changed Co" };
  else throw new Error(`mutateField: unsupported field ${field}`);
  return s;
}

// The approval action hash is an HMAC keyed from SENTRY_USERID_PEPPER (canonical.ts; an unset pepper fails closed).
// Suites that hash fill a fixed, non-secret test pepper here; a suite that needs it unset deletes it itself.
process.env.SENTRY_USERID_PEPPER ||= "vitest-approval-pepper-not-a-secret";

// ---------------------------------------------------------------------------------------------------------------------
// #9601: requester label and reattach redaction. Distinct, recognisable principals (synthesized; example.com only).
// ---------------------------------------------------------------------------------------------------------------------
export const OWNER_ID = "00000000-0000-4000-8000-0000000000a1";
export const MEMBER_ID = "00000000-0000-4000-8000-0000000000a2";
export const REQUESTER_ID = "00000000-0000-4000-8000-0000000000a3";
export const OTHER_MEMBER_ID = "00000000-0000-4000-8000-0000000000a4";
export const REQUESTER_EMAIL = "jane.requester@example.com";

/** A distinct, loud value per card field. Each is >= 12 ASCII-alphanumeric characters and appears in no key name. */
export const CANARIES = {
  to: "RcptCanary91x2",
  subject: "SubjCanary47b8",
  body: "BodyCanary63k5",
  replyTo: "ReplyCanary28d7",
  postalAddress: "PostalCanary35m1",
  branch: "BranchCanary55q9",
  repo: "RepoCanary18m4",
} as const;

/** The real tool name behind an email send; the redacted frame must not carry it. */
export const EMAIL_TOOL = TOOLS.emailSend;

/** Throws when the fake client is driven outside its contract (an unknown or out-of-order method). Distinct from TypeError. */
export class FakeContractError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "FakeContractError";
  }
}

export interface FakeQueryRecord {
  table: string;
  columns: string;
  filters: Array<{ op: "eq" | "in"; col: string; val: unknown }>;
  signalPresent: boolean;
  signalAborted: boolean;
  /** How the chain ended: awaited directly (array rows) or through maybeSingle (one row). */
  terminal: "await" | "maybeSingle" | null;
}

export interface FakeResult {
  data: unknown;
  error: unknown;
}

const strictPhase = <T extends object>(phase: string, allowed: string[], impl: T): T =>
  new Proxy(impl, {
    get(target, prop, receiver) {
      if (typeof prop === "symbol") return Reflect.get(target, prop, receiver);
      if (!allowed.includes(prop)) throw new FakeContractError(`unknown or out-of-order method "${prop}" in phase ${phase}`);
      return Reflect.get(target, prop, receiver);
    },
  });

/**
 * One strict PostgREST fake: a phase-typed builder `from(table).select(cols).eq()|in()...abortSignal(sig)` that ends by being
 * awaited (rows) or by `.maybeSingle()` (one row). An unknown or out-of-order method, or ending the chain before
 * `.abortSignal(...)`, throws a `FakeContractError`. Every query is recorded. `respond` produces the result and may return a
 * promise that never settles (a hung read) or settles late.
 */
export function createStrictPostgrest(respond: (q: FakeQueryRecord) => FakeResult | Promise<FakeResult>) {
  const queries: FakeQueryRecord[] = [];
  const run = (rec: FakeQueryRecord, terminal: "await" | "maybeSingle"): Promise<FakeResult> => {
    rec.terminal = terminal;
    return Promise.resolve(respond(rec));
  };
  const from = (table: string) => {
    const rec: FakeQueryRecord = { table, columns: "", filters: [], signalPresent: false, signalAborted: false, terminal: null };
    queries.push(rec);
    return strictPhase("from", ["select"], {
      select: (columns: string) => {
        rec.columns = columns;
        const filterPhase = strictPhase("filter", ["eq", "in", "abortSignal"], {
          eq: (col: string, val: unknown) => {
            rec.filters.push({ op: "eq", col, val });
            return filterPhase;
          },
          in: (col: string, val: unknown) => {
            rec.filters.push({ op: "in", col, val });
            return filterPhase;
          },
          abortSignal: (signal: AbortSignal) => {
            rec.signalPresent = true;
            rec.signalAborted = signal.aborted;
            return strictPhase("terminal", ["then", "maybeSingle"], {
              then: (ok: (v: FakeResult) => unknown, bad?: (e: unknown) => unknown) => run(rec, "await").then(ok, bad),
              maybeSingle: () => run(rec, "maybeSingle"),
            });
          },
        });
        return filterPhase;
      },
    });
  };
  return { client: { from }, queries };
}

export interface FakeLabelerWorld {
  /** workspace_members rows of the fake database. */
  members: Array<{ workspace_id: string; user_id: string; role: string }>;
  /** The authoritative auth email by user id (auth.admin.getUserById). */
  authEmails: Record<string, string | null | undefined>;
  /** public.users.email by id: member-writable, so the labeler must never read it. */
  publicEmails?: Record<string, string>;
  /** Make the membership read return this error. */
  membershipError?: unknown;
  /** Make the auth read return this error. */
  authError?: unknown;
}

/**
 * A labeler client over {@link createStrictPostgrest}: `workspace_members` is served from `members` (filters applied), `users`
 * from `publicEmails`, and `auth.admin.getUserById` from `authEmails`. `getUserById` calls are recorded in `authCalls`.
 */
export function makeLabelerClient(world: FakeLabelerWorld) {
  const authCalls: string[] = [];
  const pg = createStrictPostgrest((q) => {
    if (q.table === "workspace_members") {
      if (world.membershipError) return { data: null, error: world.membershipError };
      let rows = world.members;
      for (const f of q.filters) {
        rows = rows.filter((r) => {
          const v = (r as Record<string, unknown>)[f.col];
          return f.op === "eq" ? v === f.val : (f.val as unknown[]).includes(v);
        });
      }
      return { data: rows.map((r) => ({ user_id: r.user_id, role: r.role })), error: null };
    }
    if (q.table === "users") {
      const id = q.filters.find((f) => f.col === "id")?.val as string | undefined;
      return { data: id && world.publicEmails?.[id] ? [{ id, email: world.publicEmails[id] }] : [], error: null };
    }
    throw new FakeContractError(`unexpected table ${q.table}`);
  });
  const client = {
    from: pg.client.from,
    auth: {
      admin: {
        getUserById: async (id: string) => {
          authCalls.push(id);
          if (world.authError) return { data: null, error: world.authError };
          return { data: { user: { id, email: world.authEmails[id] } }, error: null };
        },
      },
    },
  };
  return { client, queries: pg.queries, authCalls };
}

/** Throws unless every canary is absent from the serialized frame (and the serialized frame is non-trivial). Used as a detector. */
export function expectNoLeak(frame: unknown, canaries: readonly string[]): void {
  if (canaries.length === 0) throw new Error("expectNoLeak: no canaries given (a vacuous check)");
  const text = JSON.stringify(frame);
  if (!text || text.length < 20) throw new Error("expectNoLeak: the frame is empty or trivial (a vacuous check)");
  for (const c of canaries) {
    if (text.includes(c)) throw new Error(`leak: canary ${c} present in the serialized frame`);
  }
}
