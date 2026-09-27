import { describe, it, expect } from "vitest";
import { readFileSync, readdirSync, statSync } from "node:fs";
import { resolve, join, relative } from "node:path";

// Route-level supabase.auth.getUser() census — issue #8926.
//
// Every authenticated route handler previously paid a remote GoTrue
// round-trip per request just to learn the caller's user id. Middleware now
// mints `x-soleur-auth-user-id` (verified once, propagated on the request),
// and `verifiedUserId(req)` (server/request-auth.ts) consumes it — the remote
// call survives only inside the helper's bounded fail-closed fallback.
//
// This census walks every `app/** /route.ts` (API handlers AND page-route
// surfaces — a handler anywhere under app/ is the same remote-call shape)
// and asserts the exact set of files still matching
// /auth\s*\.\s*getUser\s*\(/. Any NEW route-level call site added outside
// this allowlist fails CI — the author must either migrate to
// verifiedUserId(req) or justify the keep here.
//
// Detector scope, stated honestly: the regex covers whitespace variants of
// the direct `auth.getUser(` spelling only. Aliased receivers
// (`const { getUser } = supabase.auth`), computed access
// (`auth["getUser"]`), and indirection through a non-route.ts helper are
// NOT caught — widening to those would need the type checker, and the
// ratchet's job is to make new direct call sites loud, not to be a proof.
// Non-route surfaces (page.tsx/layout.tsx/server-action modules) carry
// their own getUser sites by design — they do not accept a Request, so
// verifiedUserId(req) is not a drop-in there and they are out of scope.

const APP_ROOT = resolve(__dirname, "../../app");
const GETUSER_RE = /auth\s*\.\s*getUser\s*\(/;

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
  for (const abs of walkRouteFiles(APP_ROOT)) {
    if (GETUSER_RE.test(readFileSync(abs, "utf-8"))) {
      hits.push(relative(APP_ROOT, abs).split("\\").join("/"));
    }
  }
  return hits.sort();
}

// KEEPERS — each entry must carry its reason. Three shapes:
//
//   (a) Rich Supabase user fields the minted header cannot supply
//       (user_metadata, identities beyond id, etc.) — getUser() stays the
//       primary verification, same as before.
//   (b) Email-only consumers migrated to verifiedUserId(req) +
//       sessionJwtEmailForVerifiedUser(supabase, userId): the remote call
//       remains ONLY as the fallback when the local session JWT cannot supply
//       an email claim for the verified id.
//   (c) A verification that must be FRESH for semantic reasons — the
//       middleware-minted id verifies the INCOMING session, and these
//       keepers verify a NEW one (post-exchange) or re-authenticate the
//       caller as part of a credential challenge.
const GETUSER_KEEPERS = new Set<string>([
  // (c) OAuth/magic-link exchange: getUser() verifies the session the code
  // exchange just MINTED — not the incoming request, which carried no valid
  // session for middleware to verify. A minted header cannot exist yet.
  "(auth)/callback/route.ts",
  // (c) Password re-auth: the endpoint's whole purpose is a fresh credential
  // challenge (signInWithPassword with the getUser-supplied email); the
  // minted id identifies the session but the email must come from the
  // current remote record.
  "(dashboard)/dashboard/settings/privacy/reauth/route.ts",
  // (a) GitHub App install: consumes user.user_metadata?.full_name AND
  // user.email for the onboarding record — richer than the header carries.
  "api/repo/setup/route.ts",
  // (a) Invite acceptance consumes user.user_metadata?.full_name AND
  // user.email (member display name + invitee_email leg).
  "api/workspace/accept-invite/route.ts",
  // (a) Consumes user.user_metadata?.full_name AND user.email for the
  // inviter display + invitee record.
  "api/workspace/invite-member/route.ts",
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
        `header cannot carry (user_metadata, identities), an email the ` +
        `session JWT cannot supply, or a deliberately FRESH verification ` +
        `(auth exchange, credential challenge) — and document the reason.`,
    ).toEqual(expected);
  });

  it("every keeper still exists on disk (allowlist is not stale)", () => {
    for (const rel of GETUSER_KEEPERS) {
      const abs = join(APP_ROOT, rel);
      expect(
        statSync(abs, { throwIfNoEntry: false })?.isFile() ?? false,
        `Keeper ${rel} no longer exists — remove it from GETUSER_KEEPERS.`,
      ).toBe(true);
    }
  });
});
