import { describe, test, expect } from "vitest";
import { readFileSync } from "node:fs";
import path from "node:path";

// Load-bearing GitHub error sentinel. This exact substring is what the
// scheduled-oauth-probe workflow greps for when validating that each
// registered callback URL is still associated with our GitHub App.
//
// If GitHub rewords the error string ("redirect_uri" → "redirectUri", etc.),
// the probe goes silent-pass and the next custom-domain CNAME flap or
// operator-paste typo will break user sign-up unobserved.
//
// Quarterly skill-freshness audit must re-run a deliberately-broken
// redirect_uri probe against GitHub's authorize endpoint and confirm the
// rendered HTML still contains this sentinel.
//
// See: knowledge-base/project/learnings/integration-issues/2026-05-04-github-app-callback-url-three-entries.md
export const GITHUB_REDIRECT_URI_ERROR_SENTINEL =
  "redirect_uri is not associated";

// Adjacent sentinels the probe also greps for.
export const GITHUB_APP_SUSPENDED_SENTINEL = "Application suspended";

// The three callback URLs the GitHub App `soleur-ai` (client_id Iv23...)
// MUST have registered. Any missing entry breaks the corresponding flow.
//   - github_resolve   : /api/auth/github-resolve (Flow B, App-direct OAuth)
//   - supabase_custom  : Supabase custom-domain CNAME advertising
//   - supabase_canonical: Supabase canonical fallback during CNAME re-provision
export const REQUIRED_GITHUB_APP_CALLBACK_PATHS = [
  "/api/auth/github-resolve/callback",
  "/auth/v1/callback",
] as const;

const repoRoot = path.resolve(__dirname, "../../..");
const workflowPath = path.join(
  repoRoot,
  ".github/workflows/scheduled-oauth-probe.yml",
);

describe("scheduled-oauth-probe.yml — GitHub redirect_uri probe contract", () => {
  test("workflow file exists and is readable", () => {
    expect(() => readFileSync(workflowPath, "utf-8")).not.toThrow();
  });

  test("workflow greps for the GitHub redirect_uri error sentinel", () => {
    // Negative-space gate: if this fails, the probe cannot detect the
    // user-reported failure mode. Grep target must match the sentinel above.
    const yaml = readFileSync(workflowPath, "utf-8");
    expect(yaml).toContain(GITHUB_REDIRECT_URI_ERROR_SENTINEL);
  });

  test("workflow greps for the Application suspended sentinel", () => {
    // GitHub App suspension renders different HTML than redirect_uri error.
    // Without this grep, suspension surfaces as a silent pass.
    const yaml = readFileSync(workflowPath, "utf-8");
    expect(yaml).toContain(GITHUB_APP_SUSPENDED_SENTINEL);
  });

  test("workflow probes all required GitHub App callback URL paths", () => {
    // Both the github-resolve callback (Flow B) AND the Supabase
    // /auth/v1/callback (Flow A — both custom-domain and canonical
    // fallback) must be exercised. Custom-domain dual-registration is
    // documented in Supabase docs; losing either entry breaks Flow A
    // for the duration of a CNAME flap.
    const yaml = readFileSync(workflowPath, "utf-8");
    for (const callbackPath of REQUIRED_GITHUB_APP_CALLBACK_PATHS) {
      expect(yaml).toContain(callbackPath);
    }
  });

  test("workflow probes the canonical supabase.co host (custom-domain fallback)", () => {
    // When Supabase re-provisions the custom domain, it briefly advertises
    // the canonical <ref>.supabase.co URL. If only api.soleur.ai is
    // registered with GitHub, Flow A breaks for that window.
    const yaml = readFileSync(workflowPath, "utf-8");
    expect(yaml).toMatch(/supabase\.co/);
  });

  test("redirect_uri probe pins curl --max-time", () => {
    // Network calls inside CI steps must pin a timeout to prevent hung jobs.
    // Verifies the GitHub redirect_uri probe block contains --max-time
    // alongside a github.com/login/oauth/authorize URL within the same
    // probe_github_redirect_uri function body.
    const yaml = readFileSync(workflowPath, "utf-8");
    const probeFnMatch = yaml.match(
      /probe_github_redirect_uri\(\)\s*\{[\s\S]*?\n\s*\}/,
    );
    expect(probeFnMatch, "probe_github_redirect_uri function not found").toBeTruthy();
    const fnBody = probeFnMatch![0];
    expect(fnBody).toMatch(/--max-time\s+\d+/);
    expect(fnBody).toMatch(/github\.com\/login\/oauth\/authorize/);
  });
});

describe("OAuth probe sentinel — semantic invariants", () => {
  test("a fabricated GitHub error response body matches the sentinel", () => {
    // This test documents what the probe expects to see in the wild.
    // If GitHub rewords, this stays green (we're testing the matcher,
    // not the live GitHub HTML), but the workflow's grep against live
    // HTML will start failing — exactly the drift signal we want.
    const fabricatedErrorBody = `
      <html>
        <body>
          <div class="error">
            The redirect_uri is not associated with this application.
          </div>
        </body>
      </html>`;
    expect(fabricatedErrorBody).toContain(GITHUB_REDIRECT_URI_ERROR_SENTINEL);
  });

  test("a healthy login form body does NOT match the sentinel", () => {
    // Both healthy and failing GitHub authorize responses are HTTP 200.
    // The body grep is the only reliable signal — verify it is specific.
    const fabricatedLoginBody = `
      <html>
        <body>
          <form action="/session" method="post">
            <input name="login" />
          </form>
        </body>
      </html>`;
    expect(fabricatedLoginBody).not.toContain(
      GITHUB_REDIRECT_URI_ERROR_SENTINEL,
    );
  });
});
