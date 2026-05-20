---
title: Tasks — drift-guard installation-grant diff (#4179)
issue: 4179
lane: single-domain
plan: knowledge-base/project/plans/2026-05-20-feat-drift-guard-installation-grant-diff-4179-plan.md
---

# Tasks: feat(drift-guard) installation-grant diff (#4179)

## Phase 0 — Preconditions

- [ ] 0.1 Verify worktree + branch: `pwd` returns the worktree path,
  `git branch --show-current` returns `feat-one-shot-drift-guard-install-grant-diff-4179`.
- [ ] 0.2 Re-confirm live-state baseline: `gh api /orgs/jikig-ai/installations
  --jq '.installations[] | select(.app_slug=="soleur-ai") | .permissions'`
  returns 8 keys matching `apps/web-platform/infra/github-app-manifest.json`'s
  `default_permissions`. Record the diff (should be empty).
- [ ] 0.3 Confirm contract test passes baseline: `./node_modules/.bin/vitest
  run apps/web-platform/test/github-app-manifest-drift-guard.test.ts` shows
  7 passing cases.
- [ ] 0.4 Confirm parity test passes baseline: `./node_modules/.bin/vitest
  run apps/web-platform/test/github-app-manifest-parity.test.ts` green.
- [ ] 0.5 Confirm `actionlint .github/workflows/scheduled-github-app-drift-guard.yml`
  is clean at HEAD (no pre-existing lint errors that would mask our changes).

## Phase 1 — RED: failing tests first

- [ ] 1.1 Add ONE new contract test case in
  `apps/web-platform/test/github-app-manifest-drift-guard.test.ts` for the
  per-installation synthesis pattern: given a `/app/installations` response
  with two installations (one matches manifest, one declares fewer permissions),
  `jq '{permissions, events}'` per element produces a file the diff script
  consumes correctly. Expect a `permission_drift:...` for the second install.
- [ ] 1.2 Verify the new case FAILS at this stage (because the synthesis
  pattern is not yet codified). Record the failure output.

## Phase 2 — GREEN: minimum implementation

- [ ] 2.1 Read `.github/workflows/scheduled-github-app-drift-guard.yml` end-to-
  end (already in context). Identify the insertion point: AFTER the App-level
  manifest diff block, BEFORE the `strip_log_injection` block.
- [ ] 2.2 Insert the new installation-grant diff block. Required structure:
  - Reuse `suppress_active` variable in-scope.
  - Reuse the existing `--header @<(printf 'Authorization: Bearer %s' "$JWT")`
    curl form per trap dossier P1-2.
  - `--max-time 15` per the network-call timeout convention.
  - `mktemp -p "$RUNNER_TEMP" installations.XXXXXX` for the response file.
  - `mktemp -p "$RUNNER_TEMP" install-resp.XXXXXX` for per-install files.
  - Shape validation: `jq -r '.installations | type'` must equal `"array"`;
    otherwise `record_failure installation_response_shape_unparseable …
    ci/guard-broken`.
  - HTTP code routing: 200 → continue; 401 → `installation_api_http`
    `ci/guard-broken`; non-200 non-401 → `installation_api_http` `ci/guard-broken`;
    `network_error` → `installation_api_http` `ci/guard-broken`.
  - Per-installation loop: `while IFS= read -r install_json; do … done < <(jq
    -c '.installations[]' "$INSTALL_LIST_FILE")`.
  - Inside loop: write per-install `{permissions, events}` to
    `$INSTALL_RESP_FILE`, re-invoke `bash bin/diff-github-app-manifest.sh`
    with `RESPONSE_FILE=$INSTALL_RESP_FILE`, parse `<mode>:<details>` output,
    route via the relabeled mode names (`installation_permission_drift`,
    `installation_unexpected_grant`, `installation_response_shape_unparseable`).
- [ ] 2.3 Extend the cleanup glob at YAML:553-561 to include
  `"$RUNNER_TEMP"/installations.* "$RUNNER_TEMP"/install-resp.*`.
- [ ] 2.4 Re-run the new contract test from Phase 1.1 — expect GREEN.
- [ ] 2.5 Re-run the full vitest suite (`./node_modules/.bin/vitest run
  apps/web-platform/test/`) — expect all green.

## Phase 3 — REFACTOR + co-edits

- [ ] 3.1 Update `apps/web-platform/infra/github-app.tf:24-30` comment block:
  remove "#4179 as a drift-guard extension" language; replace with "Both
  planes detected by scheduled-github-app-drift-guard.yml (App-declared vs
  manifest, installation-grant vs manifest)."
- [ ] 3.2 Update `knowledge-base/engineering/ops/runbooks/github-app-provisioning.md`
  Step 2.1 to note the auto-close-stale behavior of the new failure modes.
- [ ] 3.3 Run `actionlint .github/workflows/scheduled-github-app-drift-guard.yml`
  — expect green.
- [ ] 3.4 Run `bash -c "$(awk-extracted-snippet)" </dev/null` per AC16 to
  syntax-check the embedded shell.
- [ ] 3.5 Fold-in #3561: replace `\x7f` with `\177` in the
  `strip_log_injection` function (line 370). Add a learning-link comment.
- [ ] 3.6 Re-run all tests + actionlint. Expect green.

## Phase 4 — Plan-time grep audit (Sharp Edges enforcement)

- [ ] 4.1 Grep all four planned changes are present:
  - `grep -c '/app/installations' .github/workflows/scheduled-github-app-drift-guard.yml` ≥ 1
  - `grep -cE 'installation_(permission_drift|unexpected_grant|api_http|response_shape_unparseable)' .github/workflows/scheduled-github-app-drift-guard.yml` ≥ 4
  - `grep -c '@<(printf' .github/workflows/scheduled-github-app-drift-guard.yml` ≥ 2
  - `grep -c 'install-resp\|installations\.\*' .github/workflows/scheduled-github-app-drift-guard.yml` ≥ 2
- [ ] 4.2 Grep the `tr` fix landed:
  - `grep -E "tr -d.*\\\\177" .github/workflows/scheduled-github-app-drift-guard.yml` returns at least 1 match
- [ ] 4.3 Grep that `#4179` no longer appears in `apps/web-platform/infra/github-app.tf`.
- [ ] 4.4 Grep tasks.md doesn't accidentally cite a date filename for the
  follow-up learning (per Sharp Edge: prescribe directory + topic only).

## Phase 5 — Commit + push

- [ ] 5.1 `git add` ONLY the planned files:
  - `.github/workflows/scheduled-github-app-drift-guard.yml`
  - `apps/web-platform/test/github-app-manifest-drift-guard.test.ts`
  - `apps/web-platform/infra/github-app.tf`
  - `knowledge-base/engineering/ops/runbooks/github-app-provisioning.md`
- [ ] 5.2 Commit message body: short summary + `Closes #4179` + `Closes #3561` +
  Co-Authored-By trailer.
- [ ] 5.3 `git push` to the feature branch.

## Phase 6 — Review (multi-agent)

- [ ] 6.1 Run `/soleur:review` against the diff. Agents to invoke:
  `architecture-strategist`, `security-sentinel`, `silent-failure-hunter`,
  `user-impact-reviewer` (mandated by `single-user incident` threshold),
  `git-history-analyzer`.
- [ ] 6.2 Address all P0/P1 findings inline. Defer P2/P3 with explicit
  scope-out + tracking issue per `rf-review-finding-default-fix-inline`.

## Phase 7 — PR-ready + ship

- [ ] 7.1 PR body includes `Closes #4179` and `Closes #3561`.
- [ ] 7.2 Mark PR ready (`gh pr ready`); auto-merge label per ship convention.
- [ ] 7.3 Post-merge: trigger one manual `gh workflow run` of
  `scheduled-github-app-drift-guard.yml --ref main`; verify green.

## Phase 8 — Compound

- [ ] 8.1 Capture any session errors / learnings under
  `knowledge-base/project/learnings/` (directory + topic only; let the
  date land at write time). Topic candidates:
  - `<topic>-app-jwt-endpoint-reuse-vs-pat-endpoint-choice.md`
  - `<topic>-bash-fifo-trap-mktemp-required-for-double-read-scripts.md`
  - `<topic>-drift-guard-multi-plane-detection-pattern.md`
- [ ] 8.2 Run `/soleur:compound` to triage which (if any) of the above to
  promote into learnings.

## Phase 9 — Post-merge operator verification (deferred to ship/operator)

- [ ] 9.1 Operator confirms the first scheduled run (within 1 hour of merge)
  is green via `gh run list --workflow scheduled-github-app-drift-guard.yml
  --limit 1 --json conclusion`.
- [ ] 9.2 Optional (deferred): synthetic drift test in fork per AC19 — only
  if confidence in the new code path needs a second signal.
