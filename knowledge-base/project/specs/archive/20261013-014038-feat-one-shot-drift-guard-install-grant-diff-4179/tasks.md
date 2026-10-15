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
- [ ] 2.2 Insert the new installation-grant diff block per the corrected
  pseudocode in the plan's Proposed Solution. Required structure:
  - Reuse `suppress_active` variable in-scope.
  - Reuse the existing `--header @<(printf 'Authorization: Bearer %s' "$JWT")`
    curl form per trap dossier P1-2.
  - `--max-time 15` per the network-call timeout convention.
  - **Endpoint:** `https://api.github.com/app/installations?per_page=100`
    (FLAT array, App-JWT). NOT `/orgs/{org}/installations` (object-wrapped,
    PAT/OAuth admin:read scope).
  - **Headers dump:** add `-D "$INSTALL_HEADERS_FILE"` to curl for Link-header
    pagination check.
  - `mktemp -p "$RUNNER_TEMP" installations.XXXXXX` for the response body.
  - `mktemp -p "$RUNNER_TEMP" installations-hdr.XXXXXX` for headers.
  - `mktemp -p "$RUNNER_TEMP" install-resp.XXXXXX` for per-install files.
  - HTTP routing FIRST: non-200 / network_error → `installation_api_http`
    → `ci/guard-broken`.
  - Pagination check SECOND: `grep -qiE '^link:.*rel="next"'` against the
    headers file → `installation_list_truncated` → `ci/guard-broken`.
  - Shape validation THIRD: `jq -r '. | type'` must equal `"array"` (FLAT,
    not object-wrapped); otherwise `installation_response_shape_unparseable`
    → `ci/guard-broken`.
  - Per-installation loop: `while IFS= read -r install_json; do … done < <(jq
    -c '.[]' "$INSTALL_LIST_FILE")` (FLAT array iteration; **NOT**
    `'.installations[]'`).
  - Inside loop: extract `install_id=$(printf '%s' "$install_json" | jq -r
    '.id // "unknown"')`, write per-install `{permissions, events}` to
    `$INSTALL_RESP_FILE`, re-invoke `bash bin/diff-github-app-manifest.sh`
    with `RESPONSE_FILE=$INSTALL_RESP_FILE`, parse `<mode>:<details>` output,
    relabel mode names with `installation_` prefix, include `installation_id`
    in the detail body.
- [ ] 2.2b **MUST-FIX before push: #3561 fold-in is load-bearing.** Replace
  `\x7f` with `\177` in the `strip_log_injection` function (around YAML:370).
  Every new failure mode name contains the letter `f` (`drift`,
  `installation_*`); the existing `tr -d '\x7f'` silently strips `f` from the
  sanitized stdout that lands in `$GITHUB_OUTPUT.failure_mode`. Without this
  fix, operator-facing issue bodies show garbled mode names (e.g.,
  `installation_permission_drit`).
- [ ] 2.3 Extend the cleanup glob at YAML:553-561 to include
  `"$RUNNER_TEMP"/installations.* "$RUNNER_TEMP"/installations-hdr.*
  "$RUNNER_TEMP"/install-resp.*`.
- [ ] 2.4 Re-run the new contract test from Phase 1.1 — expect GREEN.
- [ ] 2.5 Re-run the full vitest suite (`./node_modules/.bin/vitest run
  apps/web-platform/test/`) — expect all green.

## Phase 3 — REFACTOR + co-edits

- [ ] 3.1 Update `apps/web-platform/infra/github-app.tf:24-30` comment block:
  remove "#4179 as a drift-guard extension" language; replace with "Both
  planes detected by scheduled-github-app-drift-guard.yml (App-declared vs
  manifest, installation-grant vs manifest)."
- [ ] 3.2 Update `knowledge-base/engineering/operations/runbooks/github-app-provisioning.md`
  Step 2.1 to note the auto-close-stale behavior of the new failure modes.
- [ ] 3.3 Run `actionlint .github/workflows/scheduled-github-app-drift-guard.yml`
  — expect green.
- [ ] 3.4 Run `bash -c "$(awk-extracted-snippet)" </dev/null` per AC16 to
  syntax-check the embedded shell.
- [ ] 3.5 (moved up to 2.2b — fold-in is load-bearing, not optional cleanup).
- [ ] 3.6 If merge will happen before 2026-05-21T16:00:00Z, also `rm
  apps/web-platform/infra/MANIFEST_DRIFT_SUPPRESS_UNTIL` in this PR so the
  first post-merge run is NOT suppressed. The post-#4173 reconciliation that
  necessitated the suppress window is complete (PR #4174 merged 2026-05-20T14:27Z).
- [ ] 3.7 Re-run all tests + actionlint. Expect green.

## Phase 4 — Plan-time grep audit (Sharp Edges enforcement)

- [ ] 4.1 Grep all planned changes are present:
  - `grep -c '/app/installations?per_page=100' .github/workflows/scheduled-github-app-drift-guard.yml` ≥ 1
  - `grep -cE 'installation_(permission_drift|unexpected_grant|api_http|response_shape_unparseable|list_truncated|diff_unknown_mode)' .github/workflows/scheduled-github-app-drift-guard.yml` ≥ 6
  - `grep -cE "jq -c '\.\[\]'" .github/workflows/scheduled-github-app-drift-guard.yml` ≥ 1
  - `grep -cE "jq -c '\.installations\[\]'" .github/workflows/scheduled-github-app-drift-guard.yml` == 0 (anti-grep: wrong shape would silently iterate zero)
  - `grep -c '@<(printf' .github/workflows/scheduled-github-app-drift-guard.yml` ≥ 2
  - `grep -cE 'install-resp|installations\.\*|installations-hdr' .github/workflows/scheduled-github-app-drift-guard.yml` ≥ 3
  - `grep -cE 'rel="next"' .github/workflows/scheduled-github-app-drift-guard.yml` ≥ 1
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
  - `knowledge-base/engineering/operations/runbooks/github-app-provisioning.md`
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
