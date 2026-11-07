/**
 * #9601: the requester labeler (server/approval/requester-label.ts) against the strict PostgREST fake.
 *
 * Properties: Owner-only (proved inside the labeler by the membership read), scoped to the ROW's workspace, the email is
 * the AUTHORITATIVE auth email (never the member-writable public.users.email), shape-checked, bounded by one deadline,
 * memoised per instance (success and failure) keyed by viewer, workspace and requester, never throws, reports ids only.
 */
import { beforeEach, describe, expect, expectTypeOf, it, vi } from "vitest";

// The REAL ops registry runs; only the Sentry sink is mocked, so the assertions see exactly what Sentry would receive
// (op, static message, `extra.code` from the thrown value; never the thrown message).
const h = vi.hoisted(() => ({ report: vi.fn(), serviceClient: vi.fn() }));
vi.mock("@/server/observability", async (orig) => ({
  ...(await orig<typeof import("@/server/observability")>()),
  warnSilentFallback: (...a: unknown[]) => h.report(...a),
  reportSilentFallback: (...a: unknown[]) => h.report(...a),
}));
vi.mock("@/lib/supabase/service", () => ({ createServiceClient: (...a: unknown[]) => h.serviceClient(...a) }));

import { createRequesterLabeler, type RequesterQueryClient } from "@/server/approval/requester-label";
import type { createServiceClient } from "@/lib/supabase/service";
import {
  FakeContractError,
  MEMBER_ID,
  OTHER_WORKSPACE_ID,
  OWNER_ID,
  REQUESTER_EMAIL,
  REQUESTER_ID,
  WORKSPACE_ID,
  makeLabelerClient,
  type FakeLabelerWorld,
} from "./fixtures";

const FALLBACK = "a workspace member";

const baseWorld = (over: Partial<FakeLabelerWorld> = {}): FakeLabelerWorld => ({
  members: [
    { workspace_id: WORKSPACE_ID, user_id: OWNER_ID, role: "owner" },
    { workspace_id: WORKSPACE_ID, user_id: REQUESTER_ID, role: "member" },
    { workspace_id: WORKSPACE_ID, user_id: MEMBER_ID, role: "member" },
  ],
  authEmails: { [REQUESTER_ID]: REQUESTER_EMAIL },
  publicEmails: { [REQUESTER_ID]: "attacker-controlled@example.com" },
  ...over,
});

function setup(world: FakeLabelerWorld = baseWorld(), signal?: () => AbortSignal) {
  const fake = makeLabelerClient(world);
  const label = createRequesterLabeler(() => fake.client as unknown as RequesterQueryClient, signal ? { signal } : undefined);
  return { ...fake, label };
}

const reportCalls = () => h.report.mock.calls.filter((c) => (c[1] as { op?: string }).op === "approval-requester-label-failed");
const serialized = (calls: unknown[][]) => JSON.stringify(calls);

beforeEach(() => {
  h.report.mockReset();
  h.serviceClient.mockReset();
});

describe("who gets a label", () => {
  it("an Owner viewer gets the requester's auth email for a current member", async () => {
    const { label, queries, authCalls } = setup();
    expect(await label(WORKSPACE_ID, OWNER_ID, REQUESTER_ID)).toBe(REQUESTER_EMAIL);
    expect(authCalls).toEqual([REQUESTER_ID]);
    expect(queries).toHaveLength(1);
    expect(reportCalls()).toHaveLength(0);
  });

  it("a member viewer gets undefined with ZERO getUserById calls (the Owner proof is inside the labeler)", async () => {
    const { label, authCalls, queries } = setup();
    expect(await label(WORKSPACE_ID, MEMBER_ID, REQUESTER_ID)).toBeUndefined();
    expect(authCalls).toEqual([]);
    expect(queries).toHaveLength(1);
    expect(reportCalls()).toHaveLength(0);
  });

  it("the membership select asks for exactly user_id and role (the fake projects columns, so a select without role would deny every Owner)", async () => {
    const { label, queries } = setup();
    expect(await label(WORKSPACE_ID, OWNER_ID, REQUESTER_ID)).toBe(REQUESTER_EMAIL);
    expect(queries[0].columns).toBe("user_id, role");
  });

  it("the REQUESTER is an Owner but the VIEWER is a plain member: undefined and zero getUserById calls (the proof is about the viewer)", async () => {
    const world = baseWorld({
      members: [
        { workspace_id: WORKSPACE_ID, user_id: REQUESTER_ID, role: "owner" },
        { workspace_id: WORKSPACE_ID, user_id: MEMBER_ID, role: "member" },
      ],
    });
    const { label, authCalls } = setup(world);
    expect(await label(WORKSPACE_ID, MEMBER_ID, REQUESTER_ID)).toBeUndefined();
    expect(authCalls).toEqual([]);
  });

  it("a viewer who is not in the workspace at all gets undefined and no email read", async () => {
    const { label, authCalls } = setup();
    expect(await label(WORKSPACE_ID, "00000000-0000-4000-8000-0000000000ff", REQUESTER_ID)).toBeUndefined();
    expect(authCalls).toEqual([]);
  });

  it("an Owner of ANOTHER workspace is not an Owner of the row's workspace (the membership read is scoped to the row)", async () => {
    const world = baseWorld({
      members: [
        { workspace_id: WORKSPACE_ID, user_id: OWNER_ID, role: "member" },
        { workspace_id: OTHER_WORKSPACE_ID, user_id: OWNER_ID, role: "owner" },
        { workspace_id: WORKSPACE_ID, user_id: REQUESTER_ID, role: "member" },
      ],
    });
    const { label, authCalls } = setup(world);
    expect(await label(WORKSPACE_ID, OWNER_ID, REQUESTER_ID)).toBeUndefined();
    expect(authCalls).toEqual([]);
  });

  it("the single membership query carries the ROW's workspace and both ids, and the abort signal", async () => {
    const { label, queries } = setup();
    await label(WORKSPACE_ID, OWNER_ID, REQUESTER_ID);
    expect(queries).toHaveLength(1);
    const q = queries[0];
    expect(q.table).toBe("workspace_members");
    expect(q.filters).toContainEqual({ op: "eq", col: "workspace_id", val: WORKSPACE_ID });
    const inFilter = q.filters.find((f) => f.op === "in");
    expect(inFilter?.col).toBe("user_id");
    expect([...(inFilter?.val as string[])].sort()).toEqual([OWNER_ID, REQUESTER_ID].sort());
    expect(q.signalPresent).toBe(true);
    expect(q.terminal).toBe("await");
  });

  it("the requester is no longer a member (departed): the fixed fallback, and no email read", async () => {
    const world = baseWorld({ members: [{ workspace_id: WORKSPACE_ID, user_id: OWNER_ID, role: "owner" }] });
    const { label, authCalls } = setup(world);
    expect(await label(WORKSPACE_ID, OWNER_ID, REQUESTER_ID)).toBe(FALLBACK);
    expect(authCalls).toEqual([]);
  });

  it("the requester is a member of ANOTHER workspace only: the fallback, never their email", async () => {
    const world = baseWorld({
      members: [
        { workspace_id: WORKSPACE_ID, user_id: OWNER_ID, role: "owner" },
        { workspace_id: OTHER_WORKSPACE_ID, user_id: REQUESTER_ID, role: "member" },
      ],
    });
    const { label } = setup(world);
    expect(await label(WORKSPACE_ID, OWNER_ID, REQUESTER_ID)).toBe(FALLBACK);
  });
});

describe("authoritative source of the address", () => {
  it("the label is the auth email, and a differing public.users.email is never used or read", async () => {
    const { label, queries } = setup();
    const out = await label(WORKSPACE_ID, OWNER_ID, REQUESTER_ID);
    expect(out).toBe(REQUESTER_EMAIL);
    expect(out).not.toContain("attacker-controlled");
    expect(queries.every((q) => q.table === "workspace_members")).toBe(true);
  });
});

describe("ids that are not uuids, and absent requesters", () => {
  it("a non-uuid requester: the fallback with no query and no report", async () => {
    const { label, queries, authCalls } = setup();
    expect(await label(WORKSPACE_ID, OWNER_ID, "not-a-uuid")).toBe(FALLBACK);
    expect(queries).toHaveLength(0);
    expect(authCalls).toEqual([]);
    expect(reportCalls()).toHaveLength(0);
  });

  it("a filter-injection shaped requester id is never put into a query", async () => {
    const { label, queries } = setup();
    expect(await label(WORKSPACE_ID, OWNER_ID, `${REQUESTER_ID},role.eq.owner`)).toBe(FALLBACK);
    expect(queries).toHaveLength(0);
  });

  it("a non-uuid viewer or workspace: undefined, no query", async () => {
    const { label, queries } = setup();
    expect(await label(WORKSPACE_ID, "nope", REQUESTER_ID)).toBeUndefined();
    expect(await label("nope", OWNER_ID, REQUESTER_ID)).toBeUndefined();
    expect(queries).toHaveLength(0);
  });

  it.each([null, undefined, ""])("a %s requester: the fallback without a query (erased account)", async (r) => {
    const { label, queries } = setup();
    expect(await label(WORKSPACE_ID, OWNER_ID, r as string | null | undefined)).toBe(FALLBACK);
    expect(queries).toHaveLength(0);
  });
});

describe("the shape of the stored address", () => {
  const labelFor = async (email: string | null | undefined) => {
    const { label } = setup(baseWorld({ authEmails: { [REQUESTER_ID]: email } }));
    return label(WORKSPACE_ID, OWNER_ID, REQUESTER_ID);
  };

  it("an empty, null or missing address: the fallback", async () => {
    expect(await labelFor("")).toBe(FALLBACK);
    expect(await labelFor(null)).toBe(FALLBACK);
    expect(await labelFor(undefined)).toBe(FALLBACK);
  });

  it("a 321-character address: the fallback (the wire caps the label at 320)", async () => {
    const long = `${"a".repeat(321 - "@example.com".length)}@example.com`;
    expect(long).toHaveLength(321);
    expect(await labelFor(long)).toBe(FALLBACK);
  });

  it("a 320-character address is kept", async () => {
    const edge = `${"a".repeat(320 - "@example.com".length)}@example.com`;
    expect(edge).toHaveLength(320);
    expect(await labelFor(edge)).toBe(edge);
  });

  it("an address without @, with two @, with whitespace or control characters: the fallback", async () => {
    expect(await labelFor("no-at-sign.example.com")).toBe(FALLBACK);
    expect(await labelFor("a@b@example.com")).toBe(FALLBACK);
    expect(await labelFor("a b@example.com")).toBe(FALLBACK);
    expect(await labelFor("a\tb@example.com")).toBe(FALLBACK);
    expect(await labelFor("a\u0000b@example.com")).toBe(FALLBACK);
    expect(await labelFor("a\nb@example.com")).toBe(FALLBACK);
  });

  it("C0, DEL and C1 control characters and the Unicode line separators are unsafe", async () => {
    for (const bad of ["a\u007fb@example.com", "a\u0085b@example.com", "a\u009fb@example.com", "a\u2028b@example.com", "a\u00a0b@example.com"]) {
      expect(await labelFor(bad), JSON.stringify(bad)).toBe(FALLBACK);
    }
  });

  it("a quoted-local-part address that carries a space or a second @ is the fallback", async () => {
    expect(await labelFor('"jane doe"@example.com')).toBe(FALLBACK);
    expect(await labelFor('"jane@x"@example.com')).toBe(FALLBACK);
  });

  it("a real label can never equal the in-band literals", async () => {
    expect(await labelFor("you")).toBe(FALLBACK);
    expect(await labelFor("a workspace member")).toBe(FALLBACK);
  });

  it("a homoglyph domain is kept as the stored string (no disambiguation: an accepted limitation)", async () => {
    expect(await labelFor("jane@exаmple.com")).toBe("jane@exаmple.com");
  });
});

describe("failures omit the key and report ids only", () => {
  it("a membership error: undefined, one report with the injected code and no email", async () => {
    const err = { code: "57014", message: `statement timeout for ${REQUESTER_EMAIL}` };
    const { label, queries } = setup(baseWorld({ membershipError: err }));
    expect(await label(WORKSPACE_ID, OWNER_ID, REQUESTER_ID)).toBeUndefined();
    expect(queries[0].terminal).toBe("await");
    expect(reportCalls()).toHaveLength(1);
    const ctx = reportCalls()[0][1];
    expect((ctx as { extra: { code?: string }; message: string }).extra.code).toBe("57014");
    expect((ctx as { message: string }).message).toBe("Approval card: the requester label could not be read; the card shows no requester line");
    expect(serialized(h.report.mock.calls)).not.toContain(REQUESTER_EMAIL);
    expect(serialized(h.report.mock.calls)).not.toContain("statement timeout");
  });

  it("an auth read error: undefined, one report, no email", async () => {
    const { label } = setup(baseWorld({ authError: { code: "user_not_found", message: `no ${REQUESTER_EMAIL}` } }));
    expect(await label(WORKSPACE_ID, OWNER_ID, REQUESTER_ID)).toBeUndefined();
    expect(reportCalls()).toHaveLength(1);
    expect((reportCalls()[0][1] as { extra: { code?: string } }).extra.code).toBe("user_not_found");
    expect(serialized(h.report.mock.calls)).not.toContain(REQUESTER_EMAIL);
  });

  it("never fails open: a membership error does not return the email", async () => {
    const { label, authCalls } = setup(baseWorld({ membershipError: { code: "XX000" } }));
    expect(await label(WORKSPACE_ID, OWNER_ID, REQUESTER_ID)).toBeUndefined();
    expect(authCalls).toEqual([]);
  });

  it("never throws on a malformed client (the report names the TypeError class, not its text)", async () => {
    const label = createRequesterLabeler(() => ({}) as unknown as RequesterQueryClient);
    await expect(label(WORKSPACE_ID, OWNER_ID, REQUESTER_ID)).resolves.toBeUndefined();
    expect(reportCalls()).toHaveLength(1);
  });

  it("a client driven out of contract surfaces as a FakeContractError, not as a swallowed pass (instrument control)", () => {
    const { client } = makeLabelerClient(baseWorld());
    expect(() => (client.from("workspace_members") as unknown as { insert: () => void }).insert()).toThrow(FakeContractError);
  });
});

describe("the deadline", () => {
  it("an aborted deadline on a hung read: undefined, one report, no email", async () => {
    const ctl = new AbortController();
    const fake = makeLabelerClient(baseWorld());
    // A read that never settles on its own.
    const hung = {
      from: () => ({ select: () => ({ eq: () => ({ in: () => ({ abortSignal: () => new Promise(() => {}) }) }) }) }),
      auth: fake.client.auth,
    };
    const label = createRequesterLabeler(() => hung as unknown as RequesterQueryClient, { signal: () => ctl.signal });
    const p = label(WORKSPACE_ID, OWNER_ID, REQUESTER_ID);
    ctl.abort();
    expect(await p).toBeUndefined();
    expect(reportCalls()).toHaveLength(1);
    expect(serialized(h.report.mock.calls)).not.toContain(REQUESTER_EMAIL);
  });

  it("a timeout trips the instance: a later lookup in the same instance omits at once with no query", async () => {
    const ctl = new AbortController();
    const fake = makeLabelerClient(baseWorld());
    const hung = {
      from: () => ({ select: () => ({ eq: () => ({ in: () => ({ abortSignal: () => new Promise(() => {}) }) }) }) }),
      auth: fake.client.auth,
    };
    const calls: number[] = [];
    const label = createRequesterLabeler(
      () => {
        calls.push(1);
        return hung as unknown as RequesterQueryClient;
      },
      { signal: () => ctl.signal },
    );
    const first = label(WORKSPACE_ID, OWNER_ID, REQUESTER_ID);
    ctl.abort();
    await first;
    const callsAfterFirst = calls.length;
    expect(await label(WORKSPACE_ID, OWNER_ID, OTHER_WORKSPACE_ID)).toBeUndefined();
    expect(calls.length).toBe(callsAfterFirst);
    expect(reportCalls()).toHaveLength(1);
  });

  it("an auth read that never settles is bounded by the same deadline", async () => {
    const ctl = new AbortController();
    const fake = makeLabelerClient(baseWorld());
    let authReads = 0;
    const client = {
      from: fake.client.from,
      auth: {
        admin: {
          getUserById: () => {
            authReads += 1;
            return new Promise(() => {});
          },
        },
      },
    };
    const label = createRequesterLabeler(() => client as unknown as RequesterQueryClient, { signal: () => ctl.signal });
    const p = label(WORKSPACE_ID, OWNER_ID, REQUESTER_ID);
    await vi.waitFor(() => expect(authReads).toBe(1));
    ctl.abort();
    expect(await p).toBeUndefined();
    expect(reportCalls()).toHaveLength(1);
  });

  it("the default deadline is AbortSignal.timeout(2000), taken once per lookup that queries", async () => {
    const spy = vi.spyOn(AbortSignal, "timeout");
    try {
      const { label } = setup();
      await label(WORKSPACE_ID, OWNER_ID, REQUESTER_ID);
      const withTwoThousand = spy.mock.calls.filter((c) => c[0] === 2000);
      expect(withTwoThousand).toHaveLength(1);
      // A lookup that needs no query takes no deadline.
      spy.mockClear();
      await label(WORKSPACE_ID, OWNER_ID, null);
      expect(spy).not.toHaveBeenCalled();
    } finally {
      spy.mockRestore();
    }
  });
});

describe("memoisation", () => {
  it("a repeated workspace and requester pair is one read", async () => {
    const { label, queries, authCalls } = setup();
    expect(await label(WORKSPACE_ID, OWNER_ID, REQUESTER_ID)).toBe(REQUESTER_EMAIL);
    expect(await label(WORKSPACE_ID, OWNER_ID, REQUESTER_ID)).toBe(REQUESTER_EMAIL);
    expect(queries).toHaveLength(1);
    expect(authCalls).toHaveLength(1);
  });

  it("a failure is memoised too: one read, one report for the repeated pair", async () => {
    const { label, queries } = setup(baseWorld({ authError: { code: "boom" } }));
    expect(await label(WORKSPACE_ID, OWNER_ID, REQUESTER_ID)).toBeUndefined();
    expect(await label(WORKSPACE_ID, OWNER_ID, REQUESTER_ID)).toBeUndefined();
    expect(queries).toHaveLength(1);
    expect(reportCalls()).toHaveLength(1);
  });

  it("the key includes the workspace: the same requester in two workspaces (a member of one) is the email for one and the fallback for the other", async () => {
    const world = baseWorld({
      members: [
        { workspace_id: WORKSPACE_ID, user_id: OWNER_ID, role: "owner" },
        { workspace_id: WORKSPACE_ID, user_id: REQUESTER_ID, role: "member" },
        { workspace_id: OTHER_WORKSPACE_ID, user_id: OWNER_ID, role: "owner" },
      ],
    });
    const { label, queries } = setup(world);
    expect(await label(WORKSPACE_ID, OWNER_ID, REQUESTER_ID)).toBe(REQUESTER_EMAIL);
    expect(await label(OTHER_WORKSPACE_ID, OWNER_ID, REQUESTER_ID)).toBe(FALLBACK);
    expect(queries).toHaveLength(2);
    expect(queries[1].filters).toContainEqual({ op: "eq", col: "workspace_id", val: OTHER_WORKSPACE_ID });
  });

  it("the key includes the viewer: an Owner's cached answer is never served to a member viewer of the same instance", async () => {
    const { label, queries, authCalls } = setup();
    expect(await label(WORKSPACE_ID, OWNER_ID, REQUESTER_ID)).toBe(REQUESTER_EMAIL);
    expect(await label(WORKSPACE_ID, MEMBER_ID, REQUESTER_ID)).toBeUndefined();
    // The other viewer ran its own proof (a second membership read), and the member order does not matter.
    expect(queries).toHaveLength(2);
    expect(authCalls).toEqual([REQUESTER_ID]);
    const fresh = setup();
    expect(await fresh.label(WORKSPACE_ID, MEMBER_ID, REQUESTER_ID)).toBeUndefined();
    expect(await fresh.label(WORKSPACE_ID, OWNER_ID, REQUESTER_ID)).toBe(REQUESTER_EMAIL);
  });

  it("nothing is cached across instances: a second labeler re-reads", async () => {
    const world = baseWorld();
    const a = setup(world);
    const b = setup(world);
    await a.label(WORKSPACE_ID, OWNER_ID, REQUESTER_ID);
    await b.label(WORKSPACE_ID, OWNER_ID, REQUESTER_ID);
    expect(a.queries).toHaveLength(1);
    expect(b.queries).toHaveLength(1);
  });
});

describe("construction", () => {
  it("the default service client is not created until the first lookup that needs it", async () => {
    const fake = makeLabelerClient(baseWorld());
    h.serviceClient.mockReturnValue(fake.client);
    const label = createRequesterLabeler();
    expect(h.serviceClient).not.toHaveBeenCalled();
    await label(WORKSPACE_ID, OWNER_ID, null);
    expect(h.serviceClient).not.toHaveBeenCalled();
    expect(await label(WORKSPACE_ID, OWNER_ID, REQUESTER_ID)).toBe(REQUESTER_EMAIL);
    expect(h.serviceClient).toHaveBeenCalledTimes(1);
  });

  it("the real service client keeps the shapes the labeler's query interface relies on (bridges the casts at the call sites)", () => {
    // A whole-client `toExtend` instantiates the generated PostgREST types without bound (TS2589), so the bridge pins the
    // two slices the labeler uses: the auth admin read, and `from(table: string)` with a `select` after it.
    type Svc = ReturnType<typeof createServiceClient>;
    expectTypeOf<Svc["auth"]["admin"]["getUserById"]>().parameter(0).toBeString();
    expectTypeOf<Svc["from"]>().parameter(0).toExtend<string>();
    expectTypeOf<ReturnType<Svc["from"]>>().toHaveProperty("select");
    expectTypeOf<RequesterQueryClient["auth"]["admin"]["getUserById"]>().parameter(0).toBeString();
  });
});
