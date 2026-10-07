# Tasks — fix: machinery-drain id-token + Stage A github_token + standing-issue lookup + census guard

Plan: `knowledge-base/project/plans/2026-10-05-fix-machinery-drain-id-token-plan.md`
Branch: `feat-one-shot-machinery-drain-id-token`

## Phase 1 — Drain workflow (`scheduled-machinery-drain.yml`)

- [ ] 1.1 Add `id-token: write` to the workflow-level `permissions:` block (lines 13-15) with the explanatory comment citing the missing-id-token recurrence class.
- [ ] 1.2 Rewrite the "Update the standing measurement issue" lookup: `gh api search/issues` `in:title` census → exact-title + `keep-open`+`meta/machinery` + `github-actions[bot]` jq select (use `index()`, NOT `contains()` — verified live); canonical = newest match; close older matches via `gh issue close --comment`; no match → `gh issue create` with `--label meta/machinery --label keep-open --milestone "Post-MVP / Later"` (unchanged).
- [ ] 1.3 Verify the rewritten `run:` block passes actionlint's shellcheck (no backticks; tilde fences retained).

## Phase 2 — Stage A (`fix-constraints-stage-a.yml`)

- [ ] 2.1 Add `github_token: ${{ github.token }}` to the agent step's `with:` block (~line 93). Verified bypass at pin `20f0b248`: `action.yml` maps it to `OVERRIDE_GITHUB_TOKEN`; `setupGitHubToken()` early-returns before `getOidcToken()`.
- [ ] 2.2 Extend the SECURITY header comment: why `id-token: write` is deliberately withheld (OIDC minting reachable by PR-head code; Anthropic exchange yields write-scoped app token → ADR-074 invariant broken) and why `github_token` is safe (the job's own `contents: read` token).
- [ ] 2.3 Do NOT touch either `permissions:` block — both stay `contents: read` only.

## Phase 3 — Regression guard

- [ ] 3.1 Write `plugins/soleur/test/claude-code-action-auth.test.sh` — Guard 1 census per the plan's `## Guard Contract`: `WF_DIR` env override for fixtures, flag-based awk block extraction, `^`-anchored greps, `permissions:`-sub-block scoping, job-level-replaces-workflow-level semantics, final line `token-path census: N consumer(s), M failure(s)`. Fixture rows 1-9 from the mutation matrix must drive the stated verdicts (9-row battery inside the suite via `mktemp -d` synthesized workflows).
- [ ] 3.2 Run `python3 scripts/regenerate-shard-manifest.py --incremental --write`; commit the `suite-shard-legs.tsv` row + durations floor.
- [ ] 3.3 Declare `AFFECTED_PLUGINS_SOLEUR_TEST_CLAUDE_CODE_ACTION_AUTH_TEST_SH_PATHS` in `scripts/lib/test-affected-paths.sh` (`.github/workflows/` + the suite + the lib).
- [ ] 3.4 Green: `bash plugins/soleur/test/claude-code-action-auth.test.sh`, `bash scripts/lint-orphan-test-suites.sh`, `bash plugins/soleur/test/scripts-shard-totality.test.sh`, `bash plugins/soleur/test/machinery-drain-floor.test.sh`.

## Phase 4 — ADR-074 amendment

- [ ] 4.1 Append the OIDC-posture paragraph to `knowledge-base/engineering/architecture/decisions/ADR-074-fix-constraints-two-stage-privileged-split.md` (per plan `## Architecture Decision`).

## Phase 5 — Post-merge verification (pipeline, `gh`-automatable)

- [ ] 5.1 `gh workflow run scheduled-machinery-drain.yml` → `gh run watch` to completion; confirm drain step passes OIDC + agent runs, floor verdict honest, Sentry `ok` check-in.
- [ ] 5.2 Confirm the self-heal arm closed #8068/#8482/#9132 and updated #9508 (`search/issues` `total_count == 1`).
- [ ] 5.3 Draft PR off `main` with a deliberate client→server violation → watch `fix-constraints-stage-a` run the agent step past token setup → close draft.
- [ ] 5.4 Confirm the `scheduled-machinery-drain` Sentry monitor recovered (check-in list shows `ok`; `recovery_threshold: 1`).

## Out of scope

- Pinning a different claude-code-action version.
- Changing `continue-on-error: true` on the drain step (deliberate — floor derives `closed` as a delta).
- Manual issue hygiene beyond the self-heal arm (the workflow closes the dupes itself).
