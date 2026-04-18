# Fix invalid `ollama launch` command on /getting-started/

**Issue:** [#2550](https://github.com/jikig-ai/soleur/issues/2550) (P0, `domain/marketing`, `type/bug`)
**Parent audit:** [#2549](https://github.com/jikig-ai/soleur/issues/2549) — 2026-04-18 content audit, finding C1 / recommendation R5
**Milestone:** Phase 3: Make it Sticky
**Branch:** `feat-one-shot-2550-fix-ollama-command`

## Overview

The `/getting-started/` install page ships a callout whose command is fabricated:

> "Running with Ollama? Use the command `ollama launch claude --model gemma4:31b-cloud` to start Soleur with your preferred local model."

Ollama has no `launch` subcommand, no Claude model, and `gemma4:31b-cloud` is not a real tag. A first-touch user who copy-pastes the command hits an immediate failure on their install page. This is a trust-breaking P0 on the highest-intent URL in the funnel.

The same line appears in three shipped surfaces (site FAQ, the plugin README, the repo README) and in the FAQ's embedded JSON-LD `FAQPage` schema (so search engines are also indexing the wrong instruction).

**Goal:** Remove every instance of the invalid command in the same PR. Do NOT replace it with a "verified" command — per audit R5, a replacement callout ships only after the linked `/docs/local-models/` doc exists, which is out of scope for this P0. Silence beats invalid.

**Scope signal:** This is a content fix — three files, one line each (plus one FAQ paragraph and one JSON-LD mirror). No UI, no data migration, no domain implications beyond marketing (audit-originated). MINIMAL detail level.

## Research Reconciliation — Spec vs. Codebase

Single pre-existing spec in this area: `knowledge-base/project/specs/feat-docs-ollama-instructions/session-state.md`. It explicitly records that a prior plan (2026-04-10) *added* the `ollama launch claude --model gemma4:31b-cloud` command "as the specific command" on `getting-started.njk`. That prior plan is the cause of this P0 — it treated an unverified string as authoritative.

| Spec claim (2026-04-10 session-state) | Reality (verified 2026-04-18) | Plan response |
|---|---|---|
| `ollama launch claude --model gemma4:31b-cloud` is "the specific command" for running Soleur via Ollama | `ollama` has no `launch` subcommand (verified against `ollama help` documented surface); no `claude` model exists in the Ollama registry; `gemma4:31b-cloud` is not a published tag. The real surface is `ollama run <model>` + a Claude-Code-compatible OpenAI-compatible endpoint — which Soleur does not yet document. | Remove the claim from all three shipped files and the JSON-LD mirror. Do not substitute another unverified command. The out-of-scope follow-up (write `/docs/local-models/` and only then re-introduce a verified callout) is covered by audit R5 and should be filed as a separate roadmap item if not already tracked. |
| Ollama instructions are safe to ship on `getting-started.njk` without a local-models doc | No local-models doc exists; the callout is the *only* place the integration is described, so there is no reference to verify against. | Gate any future Ollama callout behind the existence of `/docs/local-models/`. This plan does NOT create that doc. |

## Files to Edit

1. `plugins/soleur/docs/pages/getting-started.njk`
   - Lines ~66–68: delete the `<div class="callout">` block that contains the `ollama launch claude --model gemma4:31b-cloud` command. Leave the preceding callout (`Existing project? / Starting fresh?`) intact.
   - Lines ~172–173: rewrite the FAQ answer for "What do I need to run Soleur?" to drop the sentence "Alternatively, you can run Soleur using Ollama via the `ollama launch` command." The remaining answer still stands on its own.
   - Lines ~206–210: mirror the FAQ edit into the `application/ld+json` `FAQPage` schema (the `text` field of the matching `Question` entry). The JSON-LD string must match the rendered FAQ answer verbatim or the structured-data validator will flag a mismatch.

2. `plugins/soleur/README.md`
   - Line 13: delete the `**Running with Ollama?** Use`ollama launch claude --model gemma4:31b-cloud`…` line and the trailing blank line that pairs with it. Leave the install block above and "The Soleur Workflow" heading below untouched.

3. `README.md` (repo root)
   - Line 31: delete the same `**Running with Ollama?**` line and the trailing blank line. The "For existing codebases: Run `/soleur:sync` first…" guidance immediately below is unrelated and must stay.

## Files to Create

None.

## Implementation Phases

### Phase 1 — Delete the callout and the FAQ sentence (one commit)

1. Open `plugins/soleur/docs/pages/getting-started.njk` and remove the three ollama references listed above.
2. Open `plugins/soleur/README.md` and delete line 13 + paired blank line.
3. Open root `README.md` and delete line 31 + paired blank line.
4. Run `npx markdownlint-cli2 --fix plugins/soleur/README.md README.md` (targeted — see `cq-markdownlint-fix-target-specific-paths`). The `.njk` file is not covered by markdownlint.
5. Verify no regression in the FAQ structured data: the rendered `<p class="faq-answer">` text for "What do I need to run Soleur?" must be string-identical to the `text` field in the `application/ld+json` block's matching question. Eyeball the diff before committing.

### Phase 2 — Verify no stale references remain

Run, from the worktree root:

```bash
grep -rn --include='*.njk' --include='*.md' --include='*.html' \
  -e 'ollama launch' -e 'gemma4:31b-cloud' \
  plugins/ README.md 2>&1 | grep -v '/knowledge-base/'
```

Expected output: empty (the knowledge-base hits are intentionally excluded — audit, content-plan, and roadmap entries describe the bug as a historical artifact and must not be rewritten).

### Phase 3 — Build & visual sanity check

1. Build the docs site: `cd plugins/soleur/docs && npm ci && npm run build` (or `bun run build` per package.json scripts, verify at time of run).
2. Serve the build output and load `/getting-started/`. Confirm:
   - The "Existing project? / Starting fresh?" callout is still present.
   - The "Running with Ollama?" callout is gone.
   - The "What do I need to run Soleur?" FAQ answer reads cleanly (no dangling "Alternatively, …" fragment).
3. Validate the JSON-LD: paste the rendered page source into Google's Rich Results Test (or run `npm run test:schema` if the docs site has a schema test — check `plugins/soleur/docs/package.json` before relying on it). The `FAQPage` entry must parse and its `text` must match the visible answer.

## Acceptance Criteria

- [ ] No file under `plugins/` or `README.md` contains the strings `ollama launch` or `gemma4:31b-cloud` (knowledge-base archival references are exempt).
- [ ] The "Running with Ollama?" callout on `/getting-started/` is removed (not replaced).
- [ ] The FAQ answer for "What do I need to run Soleur?" no longer mentions `ollama launch`, and the visible HTML answer matches the JSON-LD `text` verbatim.
- [ ] Both READMEs (plugin and repo root) no longer carry the "Running with Ollama?" line.
- [ ] Docs site builds clean; `/getting-started/` renders without missing-callout artifacts.
- [ ] Markdownlint passes on the two edited `.md` files.

## Test Scenarios

Per AGENTS.md `cq-write-failing-tests-before`: this is an **infrastructure/content-only** task (string deletion, no logic). The TDD gate is exempt. The test strategy is the grep-based regression check in Phase 2 + the visual build check in Phase 3 — both run before commit.

There is no existing test file asserting the absence of specific strings on the docs pages. Adding one is out of scope (see Non-Goals); the grep sweep is sufficient and is also the action a future reviewer would take.

## Non-Goals

- **Writing a replacement `/docs/local-models/` page.** Audit R5 explicitly defers this ("Only ship this once the linked doc exists"). File a separate roadmap item if one is not already tracked; do not conflate with this P0 fix.
- **Adding a content-audit linter that would catch future fabricated commands.** Useful, but a meta-concern not gated on this P0. A separate issue should track it.
- **Rewriting historical knowledge-base references** (`knowledge-base/marketing/audits/…`, `knowledge-base/product/roadmap.md` row 3.27, `knowledge-base/support/community/*`, `knowledge-base/project/specs/feat-docs-ollama-instructions/*`, `knowledge-base/project/plans/2026-04-06-chore-remove-telegram-bridge-plan.md`). These describe the bug or predate the fix; editing them erases the audit trail.
- **Replacing the callout with `ollama run <model>` or any other command.** R5 is explicit: removal is strictly better than shipping an unverified substitute.

## Alternative Approaches Considered

| Approach | Why rejected |
|---|---|
| Replace the callout with `ollama run gemma2:27b` (or another real Ollama tag) | Soleur does not yet document the full integration path (how Claude Code is pointed at the Ollama endpoint). A partially-correct command still fails for the same first-touch user — it just fails two steps later. R5 recommends removal until `/docs/local-models/` exists. |
| Ship R5's suggested replacement callout ("Using a local model? Soleur runs on any Claude Code-compatible backend. See [local model setup](/docs/local-models/)…") now | The linked doc doesn't exist. Shipping a link to a 404 is worse than shipping nothing — it compounds the trust break. Audit explicitly says "Only ship this once the linked doc exists." |
| Delete only the callout on the docs site; leave the READMEs | Incomplete. The README.md on GitHub is the second-most-visited surface (stars, plugin-install search). Both READMEs carry the same fabricated line and both need the fix in the same PR. |
| Add a pre-commit lint rule that catches fabricated CLI invocations | Out of scope (see Non-Goals). A useful follow-up but should not block a P0 content fix. |

## Open Code-Review Overlap

One match on `README.md` from #2262 (`review: agent-native polish — verify block, path docs, --dry-run docs (PR #2213)`). Disposition: **acknowledge** — #2262 is about agent-native `--dry-run` documentation on a different section of the README, unrelated to the Ollama callout. This plan does not change that section. The overlap is a false positive from substring matching on a common filename.

No matches on `plugins/soleur/docs/pages/getting-started.njk` or `plugins/soleur/README.md`.

## Domain Review

**Domains relevant:** Marketing (CMO — audit-originated finding)

### Marketing (CMO)

**Status:** carry-forward from 2026-04-18 content audit (R5).
**Assessment:** CMO's 2026-04-18 content audit identified this as P0 because the failure mode is on the highest-intent URL in the funnel (install page). The prescribed fix is removal until `/docs/local-models/` exists. No additional CMO review is needed for the deletion itself; a follow-up review is needed *when* a replacement callout is drafted. This plan respects the boundary.

### Product/UX Gate

**Tier:** none. This is a content deletion with no new user-facing surface. The existing page structure is untouched (one callout removed; the preceding callout and the FAQ section still render).

**Mechanical escalation check:** `Files to create` is empty — no `components/**/*.tsx`, no `app/**/page.tsx`. BLOCKING does not apply.

No other domains implicated (not CTO: no architecture; not CPO: no product framing change; not CLO: no legal surface; not CFO/CRO/COO/CCO: unrelated).

## Rollout & Risk

- **Rollout:** single PR, squash-merge via `/ship`. Auto-deploy picks it up on the next docs build.
- **Rollback:** `git revert` is safe — the deletion has no data or state implications.
- **Risk:** very low. The only non-obvious failure mode is forgetting to mirror the FAQ edit into the JSON-LD block, which would leave a schema-vs-visible mismatch that SEO validators flag. Phase 3 step 3 catches this.

## Sharp Edges

- The FAQ answer and the JSON-LD `text` field must stay string-identical after the edit. `replace_all` in a single tool call cannot safely cover both because they live in different HTML contexts (prose vs. JSON string with escaped characters) — edit each explicitly and re-read.
- The knowledge-base references to the bad command are intentionally preserved. If a future agent runs a "repo-wide grep and replace" on `ollama launch`, they will destroy the audit trail. The Phase 2 verify command explicitly excludes `/knowledge-base/` for this reason.
- Do not run `npx markdownlint-cli2 --fix` repo-wide (AGENTS.md `cq-markdownlint-fix-target-specific-paths`). Pass only the two edited `.md` files.
- A reviewer may push to "replace rather than remove." Point them at audit R5 and the rejected-alternatives table — removal is the audit's explicit recommendation.

## PR Body Reminder

Include in the PR body:

- `Closes #2550` (auto-close on merge per AGENTS.md `wg-use-closes-n-in-pr-body-not-title-to`).
- `Ref #2549` (parent audit issue — stays open).
- Screenshot of the rendered `/getting-started/` page with the Ollama callout gone (before/after pair if easy).
- `## Changelog` section: "Removed invalid `ollama launch claude` command from getting-started page, plugin README, and repo README. Fabricated command referenced a non-existent Ollama subcommand and model." semver label: `semver:patch`.
