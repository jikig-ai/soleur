# Tasks — feat-one-shot-opencode-install-docs

Plan: `knowledge-base/project/plans/2026-10-20-feat-opencode-install-docs-plan.md`

## Phase 1 — Repo READMEs (surface A)

- [x] `README.md`: rename "From the marketplace (recommended)" to name Claude Code explicitly.
- [x] `README.md`: add a Grok Build install block (pointer + first-run steps; no invented install
      command — `grok-onboarding.md` documents none).
- [x] `README.md`: add a per-harness instruction-doc pointer for Claude Code, Grok Build, Codex,
      Devin.
- [x] `plugins/soleur/README.md`: apply the identical harness-table / install-block edit.

## Phase 2 — getting-started page (surface B)

- [x] `getting-started.njk`: section label "Source-available. Install in Claude Code." → neutral.
- [x] `getting-started.njk`: self-hosted prose acknowledges the supported harness set.
- [x] `getting-started.njk`: harness table names Claude Code, Grok Build, Codex, Devin with a
      per-harness pointer.
- [x] `getting-started.njk`: edit FAQ prose **and** its JSON-LD twin in the same change (P6).
- [x] `getting-started.njk`: bump `last_updated:`.
- [x] `index.njk`: hero install note + self-hosted FAQ answers → harness-neutral.
- [x] `index.njk`: edit FAQ prose **and** its JSON-LD twin in the same change (P6).
- [x] `index.njk`: bump `last_updated:`.

### Phase 2 extension — same-class surfaces found during implementation

- [x] `pricing.njk`: two Claude-Code-only FAQ answers (lines ~299/303) **and** their JSON-LD twins
      (~347/355) de-monopolized; `last_updated:` bumped. Same drift class as AC 4; no new claim.
- [x] `llms.txt.njk`: the Getting Started description no longer says "runs inside your own Claude
      Code".

## Phase 3 — OpenCode in-repo doc (surface C, ADR-291-bounded)

- [x] `plugins/soleur/opencode/INSTRUCTIONS.md`: added an accurate **Uninstall / removal**
      subsection. NOTE: this file is **generated** by `scripts/sync-opencode-adapter.ts`, so the
      section was added to that generator's `instructions()` array and the committed file
      regenerated — editing the committed file by hand would red the `--check` drift guard.
- [x] `plugins/soleur/commands/sync.md`: manual-removal prose now points at that subsection as the
      single authority.

## Phase 4 — Routed decision + gates

- [x] Recorded the routed public-claim decision (surface D) — see below.
- [x] `bash scripts/sync-readme-counts.sh --check` → exit 0.
- [x] `bun test plugins/soleur/test/marketing-content-drift.test.ts` → 8 pass / 0 fail.
- [x] Eleventy docs build succeeds (67 files written).
- [x] `docs-cli-verification.sh` markers present on edited CLI claims (only pre-existing warning is
      the untouched `npm install` line in `plugins/soleur/README.md`).
- [x] `bun plugins/soleur/scripts/sync-opencode-adapter.ts --check` → ok.

## Routed decision (surface D) — public OpenCode/Cursor/Antigravity claim

**Not taken.** `Ruled by: withhold — ADR-291 (accepted) §Status/§Consequences and ADR-274
(adopting) §Consequences withhold a public support claim for OpenCode/Cursor until the live
support-bar evidence lands (#10591 item 1). This PR adds no such sentence (AC 9 / Test Scenario 1
verified green).` The literal ask ("add OpenCode install docs publicly") is deferred to the
evidence gate; this PR fixes the install surfaces for the harnesses already named publicly.

## Acceptance (see plan)

- [x] AC 9: no public surface gains an OpenCode/Cursor/Antigravity support sentence.
- [x] Test Scenario 1 (RED-before grep) and 3 (README table diff) pass; 2, 4, 6 also verified.
