import { describe, test, expect } from "vitest";
import { readFileSync, existsSync } from "node:fs";
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

// Positive-proof anchors. The probe requires at least one of these in the
// authorize-page response body — both-missing is treated as drift rather
// than silent-pass. These are GitHub-specific (not generic <form/Authorize)
// to avoid false-positives on rate-limit / abuse-detection pages.
export const GITHUB_AUTHORIZE_PAGE_ANCHORS = [
  'name="authenticity_token"',
  "Sign in to GitHub",
  // The consent page renders "Authorize <App name>" — match the verb +
  // capitalised follow-on as a regex in the workflow.
  "Authorize",
] as const;

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

const repoRoot = path.resolve(__dirname, "../../..");
const workflowPath = path.join(
  repoRoot,
  ".github/workflows/scheduled-oauth-probe.yml",
);

// Extract just the probe_github_redirect_uri function body so contract
// assertions don't pass on stale matches in comments or unrelated steps.
// The function opens with `<10-space-indent>probe_github_redirect_uri() {`
// and closes with `<10-space-indent>}` (intermediate `}` from `|| {` blocks
// are deeper-indented at 12 spaces, so we anchor on exactly 10).
function extractProbeFnBody(yaml: string): string {
  const match = yaml.match(
    /probe_github_redirect_uri\(\)\s*\{[\s\S]*?\n {10}\}/,
  );
  if (!match) {
    throw new Error(
      "probe_github_redirect_uri function not found in workflow — has it been renamed or removed?",
    );
  }
  return match[0];
}

describe("scheduled-oauth-probe.yml — GitHub redirect_uri probe contract", () => {
  test("workflow file exists at the expected path", () => {
    expect(
      existsSync(workflowPath),
      `Workflow not found at ${workflowPath} — was it moved or renamed? Update workflowPath in oauth-probe-contract.test.ts.`,
    ).toBe(true);
  });

  test("probe function greps for the GitHub redirect_uri error sentinel", () => {
    // Negative-space gate: if this fails, the probe cannot detect the
    // user-reported failure mode. Grep target must be inside the probe
    // function body (not in a comment or unrelated step).
    const yaml = readFileSync(workflowPath, "utf-8");
    const fnBody = extractProbeFnBody(yaml);
    expect(fnBody).toContain(GITHUB_REDIRECT_URI_ERROR_SENTINEL);
  });

  test("probe function greps for the Application suspended sentinel", () => {
    // GitHub App suspension renders different HTML than redirect_uri error.
    // Without this grep, suspension surfaces as a silent pass.
    const yaml = readFileSync(workflowPath, "utf-8");
    const fnBody = extractProbeFnBody(yaml);
    expect(fnBody).toContain(GITHUB_APP_SUSPENDED_SENTINEL);
  });

  test("probe function uses GitHub-specific positive-proof anchors", () => {
    // Generic <form/Authorize substrings appear on rate-limit and abuse
    // pages too — false-positives mean a degraded GitHub state passes as
    // healthy. Tighten to GitHub-specific anchors.
    const yaml = readFileSync(workflowPath, "utf-8");
    const fnBody = extractProbeFnBody(yaml);
    for (const anchor of GITHUB_AUTHORIZE_PAGE_ANCHORS) {
      expect(
        fnBody,
        `probe positive-proof grep is missing GitHub-specific anchor: ${anchor}`,
      ).toContain(anchor);
    }
  });

  test("workflow probes all three required GitHub App callback URLs", () => {
    // Each of the three required URLs must appear verbatim in the workflow
    // (as a literal in the host-substituted probe call). Drift between
    // this list and the workflow OR the audit runbook breaks Flow A or B.
    // Source-of-truth: knowledge-base/engineering/ops/runbooks/github-app-callback-audit.md
    const yaml = readFileSync(workflowPath, "utf-8");
    for (const url of REQUIRED_GITHUB_APP_CALLBACK_URLS) {
      // The yml uses ${APP_HOST}/${API_HOST}/${SUPABASE_PROJECT_REF}.
      // Verify each URL's distinctive path or host appears.
      // For host-substituted URLs we check the path component which is
      // literal in the yml.
      const pathOnly = url.replace(/^https:\/\/[^/]+/, "");
      expect(
        yaml,
        `workflow does not reference path ${pathOnly} from required URL ${url}`,
      ).toContain(pathOnly);
    }
    // Also verify the host substitutions are wired correctly.
    expect(yaml).toContain("${APP_HOST}/api/auth/github-resolve/callback");
    expect(yaml).toContain("${API_HOST}/auth/v1/callback");
    expect(yaml).toContain("${SUPABASE_PROJECT_REF}.supabase.co/auth/v1/callback");
  });

  test("probe pins curl --max-time and targets GitHub authorize endpoint", () => {
    // Network calls inside CI steps must pin a timeout to prevent hung jobs.
    const yaml = readFileSync(workflowPath, "utf-8");
    const fnBody = extractProbeFnBody(yaml);
    expect(fnBody).toMatch(/--max-time\s+\d+/);
    expect(fnBody).toMatch(/github\.com\/login\/oauth\/authorize/);
  });

  test("probe asserts SUPABASE_PROJECT_REF agrees with live CNAME deref", () => {
    // Catches silent Supabase project re-provisioning where the static
    // workflow secret would otherwise probe a phantom URL.
    const yaml = readFileSync(workflowPath, "utf-8");
    expect(yaml).toMatch(/dig[^\n]*CNAME[^\n]*api\.soleur\.ai|cname_ref/);
    expect(yaml).toContain("supabase_project_ref_drift");
  });

  test("misconfigured-secret failure modes are split per missing secret", () => {
    // Collapsing both into a single mode hid which `gh secret set` to run.
    const yaml = readFileSync(workflowPath, "utf-8");
    expect(yaml).toContain("github_client_id_probe_unset");
    expect(yaml).toContain("supabase_project_ref_unset");
    // Old combined mode should be gone.
    expect(yaml).not.toContain("github_redirect_probe_misconfigured");
  });
});

describe("OAuth probe sentinel — semantic invariants", () => {
  test("a fabricated GitHub error response body matches the redirect_uri sentinel", () => {
    // This test documents what the probe expects to see in the wild.
    // If GitHub rewords, this stays green (we're testing the matcher,
    // not the live GitHub HTML), but the workflow's grep against live
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
