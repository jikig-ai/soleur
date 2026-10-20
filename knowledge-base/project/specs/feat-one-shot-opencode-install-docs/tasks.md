# Tasks — feat-one-shot-opencode-install-docs

Plan: `knowledge-base/project/plans/2026-10-20-feat-opencode-install-docs-plan.md`

## Phase 1 — Repo READMEs (surface A)

- [ ] `README.md`: rename "From the marketplace (recommended)" to name Claude Code explicitly.
- [ ] `README.md`: add a Grok Build install block (command cross-checked against
      `knowledge-base/engineering/grok-onboarding.md`; pointer if no command exists).
- [ ] `README.md`: add a per-harness instruction-doc pointer for Claude Code, Grok Build, Codex,
      Devin.
- [ ] `plugins/soleur/README.md`: apply the identical harness-table / install-block edit.

## Phase 2 — getting-started page (surface B)

- [ ] `getting-started.njk`: section label "Source-available. Install in Claude Code." → neutral.
- [ ] `getting-started.njk`: self-hosted prose acknowledges the supported harness set.
- [ ] `getting-started.njk`: harness table names Claude Code, Grok Build, Codex, Devin with a
      per-harness pointer.
- [ ] `getting-started.njk`: edit FAQ prose **and** its JSON-LD twin in the same change (P6).
- [ ] `getting-started.njk`: bump `last_updated:`.
- [ ] `index.njk`: hero install note + self-hosted FAQ answers → harness-neutral.
- [ ] `index.njk`: edit FAQ prose **and** its JSON-LD twin in the same change (P6).
- [ ] `index.njk`: bump `last_updated:`.

## Phase 3 — OpenCode in-repo doc (surface C, ADR-291-bounded)

- [ ] `plugins/soleur/opencode/INSTRUCTIONS.md`: add an accurate uninstall/removal subsection;
      confirm install/`--check` flags match `install-opencode-adapter.ts`.
- [ ] `plugins/soleur/commands/sync.md`: point manual-removal prose at that subsection.

## Phase 4 — Routed decision + gates

- [ ] Record the routed public-claim decision (surface D) / confirm the CTO default at
      implementation time.
- [ ] `bash scripts/sync-readme-counts.sh --check` → exit 0.
- [ ] `bun test plugins/soleur/test/marketing-content-drift.test.ts` → pass.
- [ ] Eleventy docs build succeeds.
- [ ] `docs-cli-verification.sh` markers present on edited CLI claims.

## Acceptance (see plan)

- [ ] AC 9: no public surface gains an OpenCode/Cursor/Antigravity support sentence.
- [ ] Test Scenario 1 (RED-before grep) and 3 (README table diff) pass.
