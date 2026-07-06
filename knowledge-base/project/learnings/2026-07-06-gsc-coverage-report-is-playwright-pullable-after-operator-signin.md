# Learning: GSC "not indexed" reports are Playwright-pullable — don't ask the operator to paste URLs

## Problem

An operator (non-technical) forwarded "more failures from Google Search Console on
not indexing pages." There is **no Search Console API wired into this repo** (no
credential in `.env.example`, no integration), so the instinct is to ask the operator
to open GSC, export the "Why pages aren't indexed" report, and paste the URLs. That is
an operator-action deferral (`[[feedback_never_defer_operator_actions]]` — Soleur users
are non-technical; automate everything). The coverage data lives in the operator's
Google account, which *feels* un-automatable without stored credentials.

## Solution

**The GSC dashboard is Playwright-driveable end-to-end after a single sign-in handoff.**
The only genuinely manual gate is the Google login (password + 2FA — a true operator-only
gate you must never handle). Everything else — opening the property, navigating
`Indexing → Pages`, drilling into each reason row, reading the affected URLs, paginating
— runs under Playwright MCP.

Workflow that worked:
1. `browser_navigate` to `https://search.google.com/search-console/index?resource_id=sc-domain:<domain>`.
   If it redirects to `accounts.google.com/.../signin`, there's no stored session.
2. **Hand off ONLY the login**: park the browser on the Google sign-in page, ask the
   operator to complete it in that browser, wait for "done". (This is the legitimate
   operator-only gate per the Playwright-first audit — a real WebAuthn/password/2FA wall.)
3. Re-navigate to the property index; the session now persists. Drill each reason row
   via `browser_click` on the row, `browser_snapshot` to read the URL table, paginate
   for the rest.
4. **Verify every URL live with `curl -sIL -A Googlebot`** before acting — the GSC label
   is a stale snapshot, not ground truth (see [[2026-06-15-gsc-crawled-not-indexed-remediation-is-internal-linking]]).

Result: pulled the full 70-page "not indexed" breakdown, bucketed it live (legacy `.html`
all 301 clean; www/http benign; `403` on `deploy.soleur.ai` correct; only 3 healthy blog
pages actionable), and remediated with internal-link equity — without the operator pasting
a single URL.

## Key Insight

A vendor dashboard behind an authenticated session is presumptively Playwright-automatable
(`[[2026-06-17-vendor-dashboard-mint-presumed-playwright-automatable]]`). For GSC
specifically: the "no API in the repo" fact does NOT imply "ask the operator to paste the
report." Drive the dashboard yourself; hand off only the sign-in. This turns a multi-round
operator-paste loop into a single "sign in, tell me when done" gate.

## Session Errors

- **Playwright browser context closed intermittently** ("Target page, context or browser
  has been closed") ~3× mid-navigation. — Recovery: re-issue the same `browser_navigate`;
  it succeeds on retry. — Prevention: one-off MCP flakiness; retry-once before treating as
  a real failure (`[[workflow-issues]]` retry discipline). Not a rule gap.
- **`git grep` run from the bare-repo root** failed ("must be run in a work tree") during
  the read-only diagnosis phase. — Recovery: used `git grep <pat> main --` / `find`. —
  Prevention: already covered by `hr-when-in-a-worktree-never-read-from-bare`; the
  diagnosis was pre-worktree so this was expected.
- **Playwright `browser_snapshot(filename:)` wrote files to the repo root** (`gsc-*.md`)
  as stray untracked files. — Recovery: `rm` after extracting the URLs. — Prevention:
  when using snapshot-to-file for scratch extraction, write under the scratchpad dir or
  clean up before commit (the MCP resolves the path from repo root).
- **ugrep rejected a `{{`-containing regex** in a diff-shape check. — Recovery: fixed-string
  `grep -F`. — Prevention: one-off; use `-F` when the pattern contains Nunjucks braces.

## Tags
category: integration-issues
module: docs-site / seo / gsc / playwright
