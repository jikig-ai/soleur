// TR9 PR-3 (#4211) — sentinel-module promotion (AC3a).
//
// Load-bearing GitHub error-body substrings that the OAuth probe handler
// (`cron-oauth-probe.ts`) and the probe contract test
// (`apps/web-platform/test/oauth-probe-contract.test.ts`) share. Promoted
// out of the test file so the production handler does not import from
// `test/` (a Next.js bundle barrier in some configurations) while still
// keeping a single source of truth for the strings GitHub renders.
//
// The test file re-exports these for backward compatibility — any external
// consumer that imported the constants from `test/oauth-probe-contract.test.ts`
// keeps working.
//
// Sentinel-refresh procedure: when GitHub rewords its error page, update
// the matching constant here; the contract test's `toContain` assertions
// against the (now-deleted) workflow file are replaced by handler-level
// vitest coverage in `test/server/inngest/cron-oauth-probe.test.ts`.
//
// See: knowledge-base/project/learnings/integration-issues/2026-05-04-github-app-callback-url-three-entries.md

// Sentinel for "redirect_uri is not associated with this application" —
// surfaces when GitHub's App callback list and the URL the probe presents
// have drifted. Both healthy and failing responses are HTTP 200; this
// substring is the only reliable signal.
export const GITHUB_REDIRECT_URI_ERROR_SENTINEL =
  "redirect_uri is not associated";

// Sentinel for the "Application suspended" HTML returned when GitHub has
// administratively suspended the App. Renders different HTML than the
// redirect_uri error; without this grep, suspension would surface as a
// silent pass.
export const GITHUB_APP_SUSPENDED_SENTINEL = "Application suspended";

// Positive-proof anchors for a healthy GitHub authorize page. The probe
// requires at least one of these in the response body — both-missing is
// treated as HTML drift (probably a GitHub rewording) rather than silent
// pass. GitHub-specific to avoid false-positives on rate-limit / abuse-
// detection pages which also render generic <form/Authorize substrings.
export const GITHUB_AUTHORIZE_PAGE_ANCHORS = [
  'name="authenticity_token"',
  "Sign in to GitHub",
  // The consent page renders "Authorize <App name>"; matched as the verb
  // followed by a capitalised App name word.
  "Authorize",
] as const;
