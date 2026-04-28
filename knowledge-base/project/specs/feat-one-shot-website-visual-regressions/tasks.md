# Tasks — feat-one-shot-website-visual-regressions

Plan: `knowledge-base/project/plans/2026-04-27-fix-website-visual-regressions-and-add-pre-deploy-screenshot-gate-plan.md`

## Phase 1 — Reproduce locally

- [ ] 1.1 Build the site: `cd <worktree> && npx @11ty/eleventy`
- [ ] 1.2 Serve `_site/`: `npx http-server _site -p 8888 -c-1`
- [ ] 1.3 Use Playwright MCP to navigate `http://localhost:8888/pricing/`, `/blog/`, `/`. Confirm symptoms 1, 2, 3 reproduce; home is the control.
- [ ] 1.4 Capture "before" screenshots for the PR description.

## Phase 2 — Write the failing screenshot gate (RED step)

- [ ] 2.1 Create `plugins/soleur/docs/scripts/screenshot-gate-routes.yaml` with 11 canonical routes (`/`, `/pricing/`, `/blog/`, `/agents/`, `/skills/`, `/about/`, `/getting-started/`, `/community/`, `/changelog/`, `/vision/`, `/company-as-a-service/`).
- [ ] 2.2 Create `plugins/soleur/docs/scripts/screenshot-gate.mjs` using Playwright with `waitUntil: 'domcontentloaded'`.
- [ ] 2.3 Implement assertions: `no_visible_honeypot` (getBoundingClientRect width/height === 0), `h1_below_header` (top >= 56px), `h1_size_at_least_text_4xl` (computed font-size >= 40px).
- [ ] 2.4 On failure, write screenshot to `screenshot-gate-failures/<route-slug>.png` and exit 1.
- [ ] 2.5 Run gate against current (buggy) `_site/`. **Verify it fails on `/pricing/`, `/blog/`, and at least 4 other routes.** This is the RED proof.
- [ ] 2.6 Wire `tests/docs/screenshot-gate.test.sh` to assert exit-code 1 on bad fixture and 0 on good fixture.

## Phase 3 — Widen the inline critical CSS

- [ ] 3.1 Read `plugins/soleur/docs/css/style.css` lines 111-122 (`.page-hero`), 506-540 (`.landing-section`, `.section-label`, `.section-title`, `.section-desc`), 731-746 (`.landing-cta`), 1593-1598 (`.honeypot-trap`). Copy declarations VERBATIM.
- [ ] 3.2 Append to inline `<style>` block in `plugins/soleur/docs/_includes/base.njk` (between current line 188 and `</style>`).
- [ ] 3.3 Update regenerate-comment block (lines 126-132) with grep-stable selector list including new selectors.
- [ ] 3.4 Run sanity grep loop verifying every selector in the inline block exists in `style.css`.

## Phase 4 — Re-run the gate (GREEN step)

- [ ] 4.1 Rebuild: `npx @11ty/eleventy`.
- [ ] 4.2 Run `node plugins/soleur/docs/scripts/screenshot-gate.mjs` against new `_site/`. **All 11 routes must pass.**
- [ ] 4.3 Capture "after" screenshots for `/pricing/`, `/blog/`, `/`. Attach to PR.

## Phase 5 — Wire gate into deploy-docs.yml

- [ ] 5.1 Insert "Install Playwright (Chromium only)" step after `Verify build output`.
- [ ] 5.2 Insert "Screenshot gate" step that boots `http-server`, runs the gate, propagates exit code.
- [ ] 5.3 Insert "Upload screenshot-gate artifacts on failure" step using `actions/upload-artifact` (pinned to SHA, not `@v4`, per repo convention).
- [ ] 5.4 Validate workflow YAML with `actionlint` if available. Test by deliberately reverting one inlined selector on a fixture branch; confirm gate fails the workflow.

## Phase 6 — AGENTS.md rule + retroactive gate application

- [ ] 6.1 Add new rule to AGENTS.md "Code Quality" section with id `cq-eleventy-critical-css-screenshot-gate`.
- [ ] 6.2 Verify rule byte length under 600: `awk '/cq-eleventy-critical-css-screenshot-gate/ {print length}' AGENTS.md`.
- [ ] 6.3 Verify total AGENTS.md byte count under 40000: `wc -c AGENTS.md`.
- [ ] 6.4 Run gate against full template list (20 page templates that use `.page-hero`). Confirm no additional FOUC-affected pages exist outside the canonical 11 routes; if any, add to route list and inline any missing selectors.

## Phase 7 — Local Playwright verification

- [ ] 7.1 Use Playwright MCP `browser_navigate` to `http://localhost:8888/pricing/` and screenshot. Confirm honeypot invisible, headings stacked, button correctly placed.
- [ ] 7.2 Same for `/blog/` (H1 visible).
- [ ] 7.3 Same for `/` (no regression).

## Phase 8 — Throttle test

- [ ] 8.1 Use Playwright MCP `browser_evaluate` with CDP `Network.emulateNetworkConditions` (Slow 3G).
- [ ] 8.2 Navigate to `/pricing/` and `/blog/`. Capture screenshots at t=200ms, 400ms, 800ms, 2000ms post-`goto`.
- [ ] 8.3 Visually confirm: no honeypot, no heading overlap, hero visible at ALL checkpoints.

## Phase 9 — Ship

- [ ] 9.1 Compound learning: capture this debugging session via `skill: soleur:compound`. Learning topic: `screenshot-gate-prevents-critical-css-fouc`.
- [ ] 9.2 Run `/soleur:review` if scoping warrants (UI fix + new CI gate is non-trivial).
- [ ] 9.3 Push branch, open PR with `Closes` referencing whichever issue we filed for the production fire.
- [ ] 9.4 PR body: side-by-side before/after screenshots, gate-run logs, byte budget delta.
- [ ] 9.5 `gh pr merge <N> --squash --auto`. Poll until merged.
- [ ] 9.6 Post-merge: verify `deploy-docs.yml` workflow run succeeds including the new screenshot gate step.
- [ ] 9.7 Cold-load production verification: clear browser cache, throttle to Slow 3G, visit `/pricing/` and `/blog/`. Confirm no FOUC.
