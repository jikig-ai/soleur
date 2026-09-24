# Tasks: harness-parity census, agent-body half (#8317)

Plan: `knowledge-base/project/plans/2026-09-24-feat-harness-parity-census-agent-bodies-plan.md`

## 1. Setup: remove the phantom agent (D2)

- [ ] 1.1 Inline `agents/operations/references/service-deep-links.md` into `agents/operations/service-automator.md` as `## Service Deep Links`:
  - [ ] Demote service headings, including the fenced template's, to `###`.
  - [ ] Drop the file's preamble.
  - [ ] Reword the "this file" and "here" self-references.
  - [ ] Keep URLs and steps byte-identical.
- [ ] 1.2 Rewrite the 3 relative links as in-document references.
- [ ] 1.3 `git rm` the references file. Update the `discoverAgentPaths` comment.
- [ ] 1.4 Run `scripts/sync-readme-counts.sh`, then `--check`. Set `### Operations (5)`. Change `nfr-register.md` and `grok-onboarding.md` to 67. Leave historical 68s alone.

## 2. Tests first (RED)

- [ ] 2.1 Create the 6 agent fixtures (`agents/<case>/cpo.md`) and `skills/self-name-under-skill.md`.
- [ ] 2.2 In `harness-parity.test.ts`:
  - [ ] Extend `fixture()` to agents.
  - [ ] Add a test per fixture, with message assertions.
  - [ ] Add a table-driven grammar test using inline strings (quoted, comment, double space, CRLF, no/unterminated frontmatter).
  - [ ] Flip the plumbing assertion. Add the depth-5 positive and the anchored negative.
  - [ ] Pin `fixDoc` byte-identity.
  - [ ] Make the H5 loader recursive and files-only.
  - [ ] Make the no-orphan check a per-case literal.
- [ ] 2.3 In `harness-parity-tree.test.ts`:
  - [ ] Add `OWN_AGENTS` to the admission proof, with a count of `EXPECTED_SOLEUR_AGENT_COUNT`.
  - [ ] Add a per-doc "exactly one self-name" test with readable messages and a checked-count denominator.
- [ ] 2.4 In `c4-count-parity.test.sh`, add `derive_registry_agents` and row C8.
- [ ] 2.5 Run the suites and record the RED set per test, as listed in Phase 2.5.

## 3. Core implementation

- [ ] 3a Widen the unions (`"agent"`, `"SELF-NAME"`) and `VERDICTS`, and add the agents glob. Record the classifier-level RED: 287 non-canonical sites.
- [ ] 3b Add the `classifyDoc` self-name carve-out (the D3 first-`^name:` rule, plus the dedicated message).
  - [ ] Add the self-name count to the `formatReport` header.
  - [ ] Update the header comments.
  - [ ] Confirm the fixtures are GREEN and the tree has 220 non-canonical sites.

## 4. Remediation

- [ ] 4.0 Capture the unknown-ns baseline to scratch.
- [ ] 4.1 Commit Phases 1–3 so the tree is clean.
- [ ] 4.2 Run `harness-parity-census.ts --fix`, review every hunk, and commit (~35 sites).
- [ ] 4.3 Rewrite the 185 bare leaves with the scratch script, apply the D4 exceptions (semgrep-sast literal, `clo.md` path), review with `--word-diff`, and commit.
- [ ] 4.4 Check that `--report` shows 0 non-canonical and 67 self-name, and that the unknown-ns diff is empty.

## 5. Derived artifacts and records

- [ ] 5.1 In `sync-grok-agent-compat.ts`, map registry agent ids in stub descriptions to Grok stems. Add the test, regenerate, and run `--check`.
- [ ] 5.2 Change `model.c4` from 65 to 67 and run `scripts/regenerate-c4-model.sh`.
- [ ] 5.3 Amend ADR-226 using dated amendment blockquotes (the items listed in plan 5.3).
- [ ] 5.4 In `plugins/soleur/AGENTS.md`, update the checklist to require registry ids and add the `agents/`-only line.
- [ ] 5.5 Comment on #8622, #8063, #8409 and #8410.

## 6. Verification

- [ ] 6.1 Run the full battery:
  - [ ] `bun test plugins/soleur`.
  - [ ] Every `plugins/soleur/test/*.test.sh`.
  - [ ] `scripts/lint-agents-enforcement-tags.test.sh`.
  - [ ] The web-platform C4 vitest.
- [ ] 6.2 Diff the docs-site agent cards before and after, and record the blockquote exception.
- [ ] 6.3 Run the Grok inspect-contract and discoverability tests with grok on PATH, with no SKIP.
- [ ] 6.4 Run the AC2 live-tree mutations by hand (Guard 1 rows 1, 3, 4; Guard 2 row 10), observe RED, and revert.
- [ ] 6.5 PR body: `Closes #8317`, `Ref #8622`, the reworded sites, the scratch script source and the `NEXT_PUBLIC_AGENT_COUNT` note.
