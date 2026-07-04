# Tasks — fix(ci): Version Bump and Release startup_failure (#6018)

lane: procedural
Plan: `knowledge-base/project/plans/2026-07-04-fix-version-bump-release-startup-failure-plan.md`

Root cause: the plugin release caller `version-bump-and-release.yml` does not grant
`id-token: write`, a permission the reusable `release` job began requiring in #5977 (cosign
signing). #5981 fixed the sibling `web-platform-release.yml` caller but missed this one →
`startup_failure` on every plugin-path merge since 2026-07-04T12:20 UTC.

## Phase 1 — Core fix

- [ ] 1.1 Edit `.github/workflows/version-bump-and-release.yml`: add a job-level
      `permissions:` block to the `release:` job with `contents: write`, `packages: write`,
      `id-token: write`, mirroring the #5981 block in `web-platform-release.yml` (lines
      42–52). Include the explanatory comment (why job-level replaces inherited perms; why
      id-token is required even though the plugin caller passes no `docker_image`). Keep the
      existing `with:` inputs and `secrets: inherit` unchanged.
- [ ] 1.2 `actionlint .github/workflows/version-bump-and-release.yml` exits 0.
- [ ] 1.3 Verify: `grep -A8 '^  release:' .github/workflows/version-bump-and-release.yml | grep -c 'id-token: write'` returns `1`.

## Phase 2 — Drift-guard test (prevents recurrence for the NEXT caller)

- [ ] 2.1 Create `plugins/soleur/test/reusable-release-caller-permissions.test.sh`
      (auto-discovered by `scripts/test-all.sh:188` glob; no runner registration needed).
      Follow the header/assertion convention of `reusable-release-idempotency.test.sh`.
      Assertions:
      - (a) `reusable-release.yml` `release` job declares `id-token: write` (guard premise).
      - (b) enumerate every `uses: ./.github/workflows/reusable-release.yml` caller via grep
        (not a hardcoded list).
      - (c) each caller grants `id-token: write` at workflow level OR its calling job's
        job level; FAIL naming any caller that does not.
      - (d) sanity: enumeration found ≥ 2 callers (fail loud on a zero-match grep regression).
- [ ] 2.2 Run `bash plugins/soleur/test/reusable-release-caller-permissions.test.sh` — exits 0.
- [ ] 2.3 Negative check (author sanity): temporarily delete the `id-token: write` line from
      the plugin caller → test FAILs naming `version-bump-and-release.yml`; then revert.
- [ ] 2.4 `bash scripts/test-all.sh scripts` discovers and runs the new test green.

## Phase 3 — Ship

- [ ] 3.1 PR body: `Closes #6018`.
- [ ] 3.2 Post-merge (self-triggering, no operator step): the new `plugins/soleur/test/*.sh`
      file matches the caller's `plugins/soleur/**` path filter, so the merge itself
      triggers Version Bump and Release. Confirm via
      `gh run list --workflow "Version Bump and Release" --branch main --limit 1 --json conclusion,status,databaseId`
      that the run does NOT conclude `startup_failure` and starts with a populated `release`
      job. If it fails a *later* (non-permission) step, that is out of scope for #6018 — file
      a follow-up.

## Notes / Sharp Edges

- `actionlint` does NOT validate the caller→reusable permission ceiling (GitHub-runtime
  check) — the Phase 2 drift-guard test is the real invariant enforcer.
- Job-level `permissions:` REPLACES (not merges with) inherited workflow perms — re-declare
  `contents`/`packages` alongside `id-token`, or the release job loses tag-push/GHCR access.
- The reusable `release` job declares `id-token: write` unconditionally; the cosign steps
  that use it are `if:`-gated on `docker_image != ''` (never runs for the plugin caller).
  GitHub validates the permission ceiling at dispatch, before any `if:` — hence the grant is
  still required even though nothing is signed.
