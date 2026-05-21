import { describe, test, expect } from "vitest";

// TR9 PR-3 (#4211, AC3a) — sentinel constants moved to a server module so
// the production handler (`server/inngest/functions/cron-oauth-probe.ts`)
// shares the source-of-truth strings with the contract test. Re-exported
// from this test file for backward compatibility with any consumer that
// imported them from here historically.
export {
  GITHUB_REDIRECT_URI_ERROR_SENTINEL,
  GITHUB_APP_SUSPENDED_SENTINEL,
  GITHUB_AUTHORIZE_PAGE_ANCHORS,
} from "@/server/inngest/functions/oauth-probe-sentinels";

import {
  GITHUB_REDIRECT_URI_ERROR_SENTINEL,
  GITHUB_APP_SUSPENDED_SENTINEL,
  GITHUB_AUTHORIZE_PAGE_ANCHORS,
} from "@/server/inngest/functions/oauth-probe-sentinels";

// The three callback URLs the GitHub App `soleur-ai` (client_id Iv23...)
// MUST have registered. Any missing entry breaks the corresponding flow.
//   - github_resolve   : Flow B, App-direct OAuth via /api/auth/github-resolve
//   - supabase_custom  : Flow A primary, Supabase advertises custom domain
//   - supabase_canonical: Flow A fallback during custom-domain CNAME re-provision
//
// Custom-domain dual-registration: per Supabase docs, both `api.soleur.ai`
// AND the canonical `<ref>.supabase.co` must be registered — Supabase
// switches between them silently during cert renewal / CNAME flap.
export const REQUIRED_GITHUB_APP_CALLBACK_URLS = [
  "https://app.soleur.ai/api/auth/github-resolve/callback",
  "https://api.soleur.ai/auth/v1/callback",
  "https://ifsccnjhymdmidffkzhl.supabase.co/auth/v1/callback",
] as const;

// User-shape end-to-end authorize path. Used by the Inngest handler's
// `probeGithubSupabaseShapeE2E` to verify the combined redirect_to +
// redirect_uri shape real users hit.
export const SUPABASE_SHAPE_AUTHORIZE_PATH =
  "/auth/v1/authorize?provider=github&redirect_to=";

// TR9 PR-3 NOTE: the workflow-grep contract suite (`scheduled-oauth-
// probe yml — GitHub redirect_uri probe contract`) was deleted alongside
// the GHA scheduled-oauth-probe workflow itself (AC9).
// The probe is now `apps/web-platform/server/inngest/functions/cron-
// oauth-probe.ts`; behavioral coverage moved to
// `apps/web-platform/test/server/inngest/cron-oauth-probe.test.ts`. The
// semantic-invariant tests below remain — they document what the probe
// expects to see in the wild and would catch a sentinel-typo regression
// at this single gate.

describe("OAuth probe sentinel — semantic invariants", () => {
  test("a fabricated GitHub error response body matches the redirect_uri sentinel", () => {
    // This test documents what the probe expects to see in the wild.
    // If GitHub rewords, this stays green (we're testing the matcher,
    // not the live GitHub HTML), but the handler's grep against live
    // HTML will start failing — exactly the drift signal we want.
    const fabricatedErrorBody =
      '<html><body><div class="error">The redirect_uri is not associated with this application.</div></body></html>';
    expect(fabricatedErrorBody).toContain(GITHUB_REDIRECT_URI_ERROR_SENTINEL);
  });

  test("a fabricated suspended-app body matches the suspended sentinel", () => {
    // Symmetry with the redirect_uri test — exists so a future GitHub
    // wording change to "suspended" is caught at the same gate.
    const fabricatedSuspendedBody =
      '<html><body><h1>Application suspended</h1></body></html>';
    expect(fabricatedSuspendedBody).toContain(GITHUB_APP_SUSPENDED_SENTINEL);
  });

  test("a healthy login form body does NOT match the error sentinels", () => {
    // Both healthy and failing GitHub authorize responses are HTTP 200.
    // The body grep is the only reliable signal — verify it is specific
    // enough to reject a healthy form.
    const fabricatedLoginBody =
      '<html><body><form action="/session" method="post"><input name="authenticity_token" value="abc" /><input name="login" /></form></body></html>';
    expect(fabricatedLoginBody).not.toContain(GITHUB_REDIRECT_URI_ERROR_SENTINEL);
    expect(fabricatedLoginBody).not.toContain(GITHUB_APP_SUSPENDED_SENTINEL);
    // And it DOES contain at least one of the positive-proof anchors.
    const matchesAnchor = GITHUB_AUTHORIZE_PAGE_ANCHORS.some((a) =>
      fabricatedLoginBody.includes(a),
    );
    expect(matchesAnchor, "login body should match at least one anchor").toBe(true);
  });
});
