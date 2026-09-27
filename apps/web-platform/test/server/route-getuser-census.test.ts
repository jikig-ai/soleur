import { describe, it, expect } from "vitest";
import { readFileSync, readdirSync, statSync } from "node:fs";
import { resolve, join, relative } from "node:path";

// Route-level supabase.auth.getUser() census — issue #8926.
//
// Every authenticated route handler previously paid a remote GoTrue
// round-trip per request just to learn the caller's user id. Middleware now
// mints `x-soleur-auth-user-id` (verified once, propagated on the request),
// and `verifiedUserId(req)` (server/request-auth.ts) consumes it — the remote
// call survives only inside the helper's fail-closed fallback.
//
// This census walks every `app/api/** /route.ts` and asserts the exact set of
// files that still call `auth.getUser(`. Any NEW route-level call site added
// outside this allowlist fails CI — the author must either migrate to
// verifiedUserId(req) or justify the keep here.
//
// The detector is textual: a file counts when its source contains
// `auth.getUser(` (the `.auth.` receiver narrows out unrelated getUser()
// helpers such as Stripe/Supabase-admin calls, which use getUserById).

const API_ROOT = resolve(__dirname, "../../app/api");

function* walkRouteFiles(dir: string): Generator<string> {
  for (const entry of readdirSync(dir)) {
    const abs = join(dir, entry);
    if (statSync(abs).isDirectory()) {
      yield* walkRouteFiles(abs);
    } else if (entry === "route.ts") {
      yield abs;
    }
  }
}

function routeFilesContainingGetUser(): string[] {
  const hits: string[] = [];
  for (const abs of walkRouteFiles(API_ROOT)) {
    if (readFileSync(abs, "utf-8").includes("auth.getUser(")) {
      hits.push(relative(API_ROOT, abs).split("\\").join("/"));
    }
  }
  return hits.sort();
}

// KEEPERS — each entry must carry its reason. Two shapes:
//
//   (a) Rich Supabase user fields the minted header cannot supply
//       (user_metadata, identities beyond id, etc.) — getUser() stays the
//       primary verification, same as before.
//   (b) Email-only consumers migrated to verifiedUserId(req) +
//       sessionJwtEmailForVerifiedUser(supabase, userId): the remote call
//       remains ONLY as the fallback when the local session JWT cannot supply
//       an email claim for the verified id.
const GETUSER_KEEPERS = new Set<string>([
  // (b) Stripe `customer_email` prefill — resolved lazily and only when the
  // user has no stored stripe_customer_id; JWT email first, remote fallback.
  "checkout/route.ts",
  // (a) GitHub App install: consumes user.user_metadata?.full_name AND
  // user.email for the onboarding record — richer than the header carries.
  "repo/setup/route.ts",
  // (a) Invite acceptance consumes user.user_metadata?.full_name AND
  // user.email (member display name + invitee_email leg).
  "workspace/accept-invite/route.ts",
  // (b) invitee_email leg of the isInvitee check — JWT email first, remote
  // fallback (mirrors pending-invites).
  "workspace/decline-invite/route.ts",
  // (a) Consumes user.user_metadata?.full_name AND user.email for the
  // inviter display + invitee record.
  "workspace/invite-member/route.ts",
  // (b) invitee_email listing — JWT email first, remote fallback (the
  // original pattern the other (b) keepers mirror).
  "workspace/pending-invites/route.ts",
]);

describe("route-level supabase.auth.getUser() census (#8926)", () => {
  it("only allowlisted route files still call auth.getUser(", () => {
    const actual = routeFilesContainingGetUser();
    const expected = [...GETUSER_KEEPERS].sort();
    expect(
      actual,
      `Route files calling auth.getUser( diverge from the allowlist.\n` +
        `Actual:   ${JSON.stringify(actual)}\n` +
        `Expected: ${JSON.stringify(expected)}\n` +
        `New call sites must use verifiedUserId(req) (server/request-auth.ts) ` +
        `which consumes the middleware-minted x-soleur-auth-user-id header. ` +
        `Only add a keeper here when the route needs Supabase user fields the ` +
        `header cannot carry (user_metadata, identities) or an email the ` +
        `session JWT cannot supply — and document the reason above.`,
    ).toEqual(expected);
  });

  it("every keeper still exists on disk (allowlist is not stale)", () => {
    for (const rel of GETUSER_KEEPERS) {
      const abs = join(API_ROOT, rel);
      expect(
        statSync(abs, { throwIfNoEntry: false })?.isFile() ?? false,
        `Keeper ${rel} no longer exists — remove it from GETUSER_KEEPERS.`,
      ).toBe(true);
    }
  });
});
