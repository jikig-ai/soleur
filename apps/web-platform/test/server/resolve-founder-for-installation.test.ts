import { describe, test, expect, vi, beforeEach } from "vitest";

// ADR-044 Amendment 2026-06-17b — direct unit coverage for the
// security-critical solo-founder resolver. The webhook-route tests mock this
// resolver wholesale, so the solo self-join (`m.user_id === row.id`), the
// team-row exclusion (real Scenario 4), and the >1-ambiguous fail-closed
// branch (Scenario 3/11) have ZERO coverage there. This file exercises the
// resolver's OWN output against a faithfully-shaped supabase embed result.

const mockReportSilentFallback = vi.fn();

vi.mock("@/server/observability", () => ({
  reportSilentFallback: (...args: unknown[]) =>
    mockReportSilentFallback(...args),
}));

import { resolveSoloFounderForInstallation } from "@/server/resolve-founder-for-installation";

const INSTALLATION_ID = 4242;
// Pre-normalized repo URL (the route owns the compose-before-normalize, mirroring
// the push reconcile). ADR-044 Decision.1 + the 2026-06-18 amendment: non-push
// founder resolution is scoped by (installation_id, normalizeRepoUrl(repo_url)).
const REPO_URL = "https://github.com/octo/repo";

// A workspaces row as the `!inner` embed returns it: the workspace `id` plus
// the embedded `workspace_members` array. The solo invariant is `m.user_id ===
// row.id`; a team row's id is a fresh uuid distinct from its owner's user_id.
type MemberRow = { user_id: string; role: string };
type WorkspaceRow = { id: string; workspace_members: MemberRow[] };

// Captures the chain calls so we can assert the resolver issues the expected
// scoped query, and returns the supplied `{data,error}` from the FINAL `.eq`
// (the resolver awaits the chain via its `.then`).
function makeService(opts: {
  data?: WorkspaceRow[] | null;
  error?: unknown;
  eqCalls?: Array<[string, string | number]>;
}) {
  return {
    from: (table: string) => {
      if (table !== "workspaces") {
        throw new Error(`unexpected table: ${table}`);
      }
      const chain = {
        select: (_cols: string) => chain,
        eq: (col: string, val: string | number) => {
          opts.eqCalls?.push([col, val]);
          return chain;
        },
        then: (onfulfilled: (value: unknown) => unknown) =>
          Promise.resolve({
            data: opts.error ? null : (opts.data ?? []),
            error: opts.error ?? null,
          }).then(onfulfilled),
      };
      return chain;
    },
  } as never;
}

describe("resolveSoloFounderForInstallation", () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  // (a) one solo row → found with its own id.
  test("single solo row → { kind: 'found', founderId }", async () => {
    const founderId = "11111111-1111-1111-1111-111111111111";
    const result = await resolveSoloFounderForInstallation(
      INSTALLATION_ID,
      REPO_URL,
      makeService({
        data: [
          {
            id: founderId,
            workspace_members: [{ role: "owner", user_id: founderId }],
          },
        ],
      }),
    );
    expect(result).toEqual({ kind: "found", founderId });
  });

  // (b) one solo row + one TEAM row both returned → found with the SOLO id
  // only. The team row's owner user_id is distinct from the team workspace id,
  // so the `m.user_id === row.id` filter drops it (real Scenario 4). If the
  // filter were stubbed always-found this assertion fails (non-vacuous).
  test("solo + team row sharing install → drops team, returns solo id", async () => {
    const soloId = "22222222-2222-2222-2222-222222222222";
    const teamId = "33333333-3333-3333-3333-333333333333";
    const teamOwnerUserId = "44444444-4444-4444-4444-444444444444";
    const result = await resolveSoloFounderForInstallation(
      INSTALLATION_ID,
      REPO_URL,
      makeService({
        data: [
          {
            id: soloId,
            workspace_members: [{ role: "owner", user_id: soloId }],
          },
          {
            // Team workspace: id is a fresh uuid, never == owner's user_id.
            id: teamId,
            workspace_members: [{ role: "owner", user_id: teamOwnerUserId }],
          },
        ],
      }),
    );
    expect(result).toEqual({ kind: "found", founderId: soloId });
  });

  // (c) two distinct solo rows sharing the SAME (install, repo) → ambiguous
  // (real Scenario 3/11: two users + same fork on the same repo + same install).
  // Fail-closed: the resolver MUST NOT pick one. This is the genuine residual
  // that survives repo-scoping (the multi-repo-org false ambiguity no longer
  // fires — see the cross-repo case below). Non-vacuous: an always-found stub
  // returns `found`, failing this.
  test("two distinct solo rows same (install, repo) → { kind: 'ambiguous', count: 2 }", async () => {
    const soloA = "55555555-5555-5555-5555-555555555555";
    const soloB = "66666666-6666-6666-6666-666666666666";
    const result = await resolveSoloFounderForInstallation(
      INSTALLATION_ID,
      REPO_URL,
      makeService({
        data: [
          { id: soloA, workspace_members: [{ role: "owner", user_id: soloA }] },
          { id: soloB, workspace_members: [{ role: "owner", user_id: soloB }] },
        ],
      }),
    );
    expect(result).toEqual({ kind: "ambiguous", count: 2 });
  });

  // (d) zero rows → none (no workspace connected for this repo under the install).
  test("zero rows → { kind: 'none' }", async () => {
    const result = await resolveSoloFounderForInstallation(
      INSTALLATION_ID,
      REPO_URL,
      makeService({ data: [] }),
    );
    expect(result).toEqual({ kind: "none" });
  });

  // (e) DB error → db-error AND the silent-fallback mirror fires.
  test("chain error → { kind: 'db-error' } and mirrors to Sentry", async () => {
    const dbError = { message: "connection reset", code: "57P01" };
    const result = await resolveSoloFounderForInstallation(
      INSTALLATION_ID,
      REPO_URL,
      makeService({ error: dbError }),
    );
    expect(result).toEqual({ kind: "db-error" });
    expect(mockReportSilentFallback).toHaveBeenCalledTimes(1);
    expect(mockReportSilentFallback).toHaveBeenCalledWith(
      dbError,
      expect.objectContaining({ feature: "github-webhook", op: "founder-resolve" }),
    );
  });

  // Scoping: the resolver filters on the SERVER-DERIVED installationId, the
  // normalized repo_url (the 2026-06-18 amendment), AND the owner role (the
  // query that backs the self-join). Asserts the query shape is keyed on
  // (installation_id, repo_url), never request-supplied data.
  test("queries are scoped to installationId + repo_url + owner role", async () => {
    const eqCalls: Array<[string, string | number]> = [];
    await resolveSoloFounderForInstallation(
      INSTALLATION_ID,
      REPO_URL,
      makeService({ data: [], eqCalls }),
    );
    expect(eqCalls).toContainEqual(["github_installation_id", INSTALLATION_ID]);
    expect(eqCalls).toContainEqual(["repo_url", REPO_URL]);
    expect(eqCalls).toContainEqual(["workspace_members.role", "owner"]);
  });

  // (f) Multi-repo org install — the headline BUG 1 case. The install spans
  // MANY repos, each with its own solo workspace. BEFORE repo-scoping, an
  // install-only self-join returned ALL of them → `>1`/ambiguous → 404-drop.
  // AFTER repo-scoping, the `.eq("repo_url", REPO_URL)` filter is applied at the
  // DB level, so the resolver only ever sees the ONE solo row for the targeted
  // repo and returns `kind:found`. We simulate the DB-level filter by passing
  // only the matching repo's row in `data` (the mock chain records the
  // `.eq("repo_url", …)` call that the real DB would use to discriminate).
  test("multi-repo org install → repo_url filter yields the single matching founder, NOT ambiguous", async () => {
    const founderForThisRepo = "77777777-7777-7777-7777-777777777777";
    const eqCalls: Array<[string, string | number]> = [];
    const result = await resolveSoloFounderForInstallation(
      INSTALLATION_ID,
      REPO_URL,
      makeService({
        // The DB-level repo_url filter returns ONLY this repo's solo workspace,
        // even though the install also owns solo workspaces for OTHER repos.
        data: [
          {
            id: founderForThisRepo,
            workspace_members: [
              { role: "owner", user_id: founderForThisRepo },
            ],
          },
        ],
        eqCalls,
      }),
    );
    expect(result).toEqual({ kind: "found", founderId: founderForThisRepo });
    // The repo_url scope is what makes this NON-ambiguous (the load-bearing fix).
    expect(eqCalls).toContainEqual(["repo_url", REPO_URL]);
  });
});
