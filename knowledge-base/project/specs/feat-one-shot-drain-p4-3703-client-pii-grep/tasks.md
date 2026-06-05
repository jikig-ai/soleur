---
title: "Tasks: client-pii-grep CI + lefthook gate (#3703)"
plan: knowledge-base/project/plans/2026-06-05-feat-client-pii-grep-sentry-gate-plan.md
issue: 3703
lane: cross-domain
---

# Tasks — client-pii-grep CI + lefthook gate (#3703)

Frame: signal-quality CI gate, NOT a security control. L3 `beforeSend` backstop guarantees prod posture.

## 1. Shared script (single implementation)

- [ ] 1.1 Create `.github/scripts/check-client-pii-sentry.sh` (`chmod +x`).
  - [ ] 1.1.1 Accept explicit paths (`{staged_files}`) OR default-scan `apps/web-platform/{lib,components,app}` for `*.ts`/`*.tsx` when called with no args.
  - [ ] 1.1.2 Exclude `apps/web-platform/app/api/**` and `apps/web-platform/lib/client-observability.ts`.
  - [ ] 1.1.3 **Multi-line-aware** detection: scan each `Sentry.captureException(`/`captureMessage(` call's argument span for an `extra:` object whose body matches `\b(userId|user_id|email)\b`. Prefer `awk` window state-machine (avoid `grep -P` dependency); verify the chosen form against a real multi-line fixture before committing.
  - [ ] 1.1.4 Output `path:line: <snippet>` per offender; `exit 1` if any, else `exit 0`.
  - [ ] 1.1.5 Header comment carries the signal-quality (not security) frame + L3-backstop note + boundary-vs-`userid-bypass-lint` note.

## 2. Fixture test (offline, auto-discovered)

- [ ] 2.1 Create `.github/scripts/test/test-check-client-pii-sentry.sh` modeled on `test-check-auto-commit-density.sh`.
  - [ ] 2.1.1 Build synthetic fixtures in `mktemp -d`; run the real SUT against them (tree-scanning + offline → no `gh`/network gating).
  - [ ] 2.1.2 Red fixtures (expect exit 1): same-line `userId`; **multi-line `userId`**; `email`; snake-case `user_id`.
  - [ ] 2.1.3 Green fixtures (expect exit 0): `extra: { filename }`; `tags`-only; `app/api/` path with violation (excluded); `client-observability.ts` with violation (excluded); `extra: someVar` variable form.
  - [ ] 2.1.4 PASS/FAIL tally; `exit 1` on any FAIL.
- [ ] 2.2 Confirm `bash .github/scripts/test/run-all.sh` ends with `ALL FIXTURE TESTS PASS` (existing `guard-script-fixture-tests` CI job auto-runs it — no workflow edit for the test).

## 3. lefthook wiring (consumer a)

- [ ] 3.1 Add `client-pii-grep` command under `pre-commit.commands` in `lefthook.yml` (path-array glob `apps/web-platform/{lib,components,app}/**/*.{ts,tsx}`, NOT `**/*`).
- [ ] 3.2 Add a NEW top-level `pre-push:` section (none exists today) with `commands:` containing the same `client-pii-grep` entry.
- [ ] 3.3 `run: bash .github/scripts/check-client-pii-sentry.sh {staged_files}`.

## 4. CI mirror job (consumer b)

- [ ] 4.1 Add a `client-pii-grep` job to `.github/workflows/pr-quality-guards.yml` (sibling to `pii-grep`/`userid-bypass-lint`).
- [ ] 4.2 `runs-on: ubuntu-latest`; checkout pinned to the file's existing action SHA; step runs `bash .github/scripts/check-client-pii-sentry.sh` (no args → tree-scan).
- [ ] 4.3 No opt-out label (match `pii-grep`). Job comment: cite #3703, signal-quality frame, boundary vs `userid-bypass-lint`/`pii-grep`.

## 5. Verification

- [ ] 5.1 AC2: both same-line AND multi-line red fixtures → exit 1.
- [ ] 5.2 AC3: real working tree → exit 0, zero offenders (all 9 green-sites stay green).
- [ ] 5.3 AC4: helper + `app/api/` excluded.
- [ ] 5.4 lefthook pre-commit + pre-push both block a staged synthetic violation.
- [ ] 5.5 PR body: `Closes #3703`; milestone `Phase 4: Validate + Scale`.
