# Runbook: Vendor Pin Drift Resolution

When the content-vendor-drift cron opens a tracking issue (label `vendor/pin-drift` / `vendor/license-changed` / `vendor/upstream-rollback` / `vendor/upstream-archived`), or its Sentry monitor (`scheduled-content-vendor-drift`) reports a red check-in, use this runbook to resolve the situation.

**Multi-bundle model (#8122).** The cron discovers every schema-conforming bundle — `plugins/soleur/skills/*/NOTICE` with parseable frontmatter declaring `upstream` + `pinned-commit` — and runs an independent detect/attest arm per bundle. Artifacts are slugged: re-vendor branches `ci/content-vendor-drift-<slug>-<ts>`, attestation branches `ci/vendor-attest-<slug>-`, per-bundle cron name `cron-content-vendor-drift-<slug>`. Legacy un-suffixed branches/issues classify as `gdpr-gate`'s. A failure in one bundle does NOT mask a sibling — each arm returns a typed outcome and the run-level heartbeat is the AND of all bundle outcomes. Substitute `<slug>` and its NOTICE path wherever this runbook names `gdpr-gate`.

Cross-references:

- Policy: `knowledge-base/engineering/policies/content-vendoring.md`
- Cron: `apps/web-platform/server/inngest/functions/cron-content-vendor-drift.ts` (an Inngest
  function since the TR9 Phase-2 migration; it was
  `.github/workflows/scheduled-content-vendor-drift.yml`, and that file no longer exists. The
  Sentry monitor slug keeps the old name, so a `scheduled-content-vendor-drift` hit in
  `cron-monitors.tf` is correct and is not a stale reference.)
- Manual trigger: `/soleur:trigger-cron` with `cron/content-vendor-drift.manual-trigger`
  (allowlisted via the drift-guarded manifest in `server/inngest/cron-manifest.ts`).
  **`gh workflow run` cannot dispatch this job** — there is no workflow to dispatch.
- Compliance posture: `knowledge-base/legal/compliance-posture.md` §Vendored Code Provenance
- Enrolled bundles: `plugins/soleur/skills/gdpr-gate/NOTICE`, `plugins/soleur/skills/legal-generate/NOTICE` (schema-conforming set is authoritative — see `vendor-bundle-coverage.test.sh`)
- Helper scripts: `plugins/soleur/skills/gdpr-gate/scripts/{notice-frontmatter,vendor-pin-integrity,vendor-drift-classify}.sh`

## 1. Synthetic-Drift Test — Cron-Failure-Path Validation

Run this once after merging the PR that landed this runbook (#3517) — or after any change to the cron, classifier, or NOTICE schema — to verify NOTICE tampering produces a visible alert. The earlier form of this test mutated `pinned-commit` only, but the drift-detection logic compares per-file `upstream-blob-sha` values, so mutating `pinned-commit` alone produced "no drift detected" and silently skipped validation (issue #3540).

**Scope:** this test validates the **cron-failure path** — a per-bundle arm failure (e.g. an upstream blob lookup 404) produces a typed failed outcome, a red Sentry check-in, and a `comparison-could-not-measure` Sentry event. NOTE: no `vendor/cron-failure` ISSUE is filed — arm failures surface via Sentry + the heartbeat only. It does NOT validate the happy-path auto-PR creation — that route is currently unimplemented (the detect step performs no re-vendor write, so `route: "pr"` produces no artifact and reports unhealthy by design; tracked follow-up).

```bash
# 1. Create a feature branch with one upstream-blob-sha mutated to a
#    non-existent SHA. The 0000... SHA is guaranteed to 404 against the
#    upstream `git/blobs/` endpoint, which trips the workflow's cron-failure
#    arm.
git checkout -b synthetic-drift-test
sed -i '0,/^    upstream-blob-sha:.*/{s/^\(    upstream-blob-sha:\).*/\1 0000000000000000000000000000000000000000/}' \
  plugins/soleur/skills/gdpr-gate/NOTICE
git commit -am 'test: mutate one upstream-blob-sha to non-existent for cron-failure-path validation'
git push -u origin synthetic-drift-test

# 2. Dispatch the workflow against this branch.
# NOTE: `gh workflow run` does NOT work here — the job is an Inngest cron, not a
# workflow. Trigger it with /soleur:trigger-cron (event
# `cron/content-vendor-drift.manual-trigger`). An Inngest function has no branch
# scoping, so the `--ref synthetic-drift-test` half of this rehearsal no longer has
# an equivalent: the trigger runs against deployed code. Rehearse the classifier
# directly instead -- `vendor-drift-classify.sh` is a standalone script.

# 3. Poll until the run completes (expect failure status — the
#    typed-failure arm is what fires).
# Observe the run in Inngest / Sentry (monitor slug `scheduled-content-vendor-drift`)
# rather than via `gh run`.

# 4. Assert the failure surfaced: a red check-in on the
#    `scheduled-content-vendor-drift` Sentry monitor AND a Sentry event with
#    op=comparison-could-not-measure (or bundle-arm) naming the bundle slug.
#    There is NO auto-filed issue on this path — the alert IS the Sentry
#    event + red heartbeat.
```

Expected outcome: within ~10 minutes of dispatch, the Sentry monitor shows a red check-in and a `reportSilentFallback` event naming the failing bundle. The most-important invariant — NOTICE tampering produces a visible alert — is validated. Clean up after assertion:

```bash
git push origin --delete synthetic-drift-test
```

## 2. Manual Re-vendor (drift issue landed)

There is no automated re-vendor write today: the `route: "pr"` arm of the cron calls `safeCommitAndPr` on a worktree nothing has written to, so it always returns `no-changes` and reports `pr-route-no-artifact` (deliberately red — the gap is tracked in a follow-up issue). When a drift issue lands, perform the re-vendor by hand:

1. Fetch the new upstream blobs: `gh api repos/<o>/<r>/git/blobs/<new-sha>` per drifted `upstream-path` (the issue names them), or `gh api repos/<o>/<r>/contents/<upstream-path>?ref=<default-branch>` and decode `content`.
2. Write the upstream bytes into the lifted path, re-adding the line-1 attribution header (`<!-- Adapted from <upstream> (<license>) — see NOTICE -->`).
3. Recompute pins: `git hash-object --no-filters <path>` → NOTICE `local-blob-sha`; the fetched blob's `sha` field → `upstream-blob-sha`; set `pinned-commit` to the upstream commit you fetched against and bump `last-verified`.
4. Verify locally: `bash plugins/soleur/skills/gdpr-gate/scripts/vendor-pin-integrity.sh <lifted-paths>` (pass `SKILL_PREFIX`/`NOTICE_FILE` env for non-default bundles) and `NOTICE_FILE=<bundle>/NOTICE … --verify-upstream`.
5. Commit on a normal branch: `fix(vendor-drift): re-vendor <o>/<r> @<sha>`; the lefthook stanza re-checks the pins on commit.
6. Close the drift issue on merge.

## 3. Upstream Rollback (`vendor/upstream-rollback` label)

The classifier exits 15 when upstream HEAD is an ancestor of our pinned SHA — i.e., upstream went BACKWARD. Two underlying scenarios:

### 3a. Intentional upstream rollback

Upstream maintainers reverted a commit (security regression, unintended breaking change). We probably want to follow them — re-pin to upstream HEAD and inherit the rollback.

1. Verify the rollback is intentional by reading upstream commit history: `gh api repos/<o>/<r>/commits?per_page=10`.
2. Check the upstream issue tracker / changelog for a rollback announcement.
3. If intentional: trigger the cron via `/soleur:trigger-cron` (`cron/content-vendor-drift.manual-trigger`) to bump to current upstream HEAD. The classifier will re-run; if exit 15 stabilizes, manually edit the affected bundle's NOTICE `pinned-commit` to the rollback target SHA and open a non-auto PR.

### 3b. Force-push accident

Upstream maintainer accidentally force-pushed an older commit on top of newer history. We do NOT want to follow.

1. Open a tracking issue: `gh issue create --label vendor/upstream-rollback --title "[vendor-drift] Suspected upstream force-push: <o>/<r> rolled back"`.
2. Ping upstream maintainers via their preferred channel (issue, Discord, email).
3. Hold the auto-PR (do not merge). Re-run the workflow weekly until upstream re-publishes the newer history.

## 4. Upstream Renamed (`vendor/upstream-archived` + redirect)

When `gh api repos/<o>/<r>` returns a `full_name` that doesn't match our recorded `<o>/<r>`, GitHub has redirected the canonical path:

1. Update NOTICE `upstream` field to the new `github.com/<new-owner>/<new-repo>` path.
2. Verify upstream content is still accessible at that new path.
3. Re-run the cron via `/soleur:trigger-cron` (`cron/content-vendor-drift.manual-trigger`).
4. Merge any drift PR the re-run produces normally.

## 5. Upstream Archived (`vendor/upstream-archived`, no redirect)

When upstream is permanently archived (read-only, will not receive patches), we have a fork-or-drop decision.

1. File an Architecture Decision Record via `/soleur:architecture create` titled "Upstream `<o>/<r>` archived — fork or drop?". The ADR should weigh: maintenance cost of a fork, criticality of the lifted content, availability of an alternative upstream.
2. Until the ADR resolves, leave the auto-PR open (do not merge). The runtime staleness banner will continue to fire on every gdpr-gate invocation, which is the correct user signal: "this rule set is no longer maintained; your output is advisory."
3. ADR outcomes:
   - **Fork**: create `Soleur/<repo>` as a hard fork, change NOTICE `upstream` to point at the fork, rotate `pinned-commit`, merge.
   - **Drop**: delete the lifted files + NOTICE entry, update `compliance-posture.md` registry to remove the row, rotate any downstream skill references.

## 6. Cron Failure (red check-in + Sentry event — no issue is filed)

A per-bundle arm failure surfaces as a typed `failed` outcome: a red Sentry check-in on `scheduled-content-vendor-drift` plus a `reportSilentFallback` event (`op=bundle-arm` or `comparison-could-not-measure`) whose message names the bundle slug. **No `vendor/cron-failure` issue is filed** — the `if: failure()` filing step was dropped in the Inngest port; Sentry is the alert surface.

1. Inspect the run: it is an Inngest function, so `gh run view` finds nothing — observe via Inngest / Sentry; the event message names the failing bundle slug.
2. Common transient causes:
   - **Rate-limit** (HTTP 403 from `gh api`): wait one hour, manually re-trigger via `/soleur:trigger-cron`.
   - **Upstream 5xx**: wait, re-trigger. If GitHub Status indicates a degraded API, hold until resolved.
   - **Per-bundle arm failure**: a typed failure in one bundle leaves siblings green — check the handler result's per-bundle `outcomes` to see which arm threw.
3. If the failure persists across two consecutive re-triggers, escalate: read the policy doc §4.1 and consider whether the cron logic itself needs revision (issue + PR).

## 7. POSTURE_FAIL Operator Chain (>90d stale)

When a bundle's staleness surface emits `POSTURE_FAIL:` — `gdpr-gate.sh` during a regulated PR's `/soleur:gdpr-gate` invocation, or `legal-generate`'s Phase 1.5 staleness check — it is signaling that the cron + auto-PR pipeline has been silently broken for >90 days and that bundle's lifted content is dangerously stale. The chain (shown for `gdpr-gate`; substitute the affected bundle's slug and NOTICE path):

1. **Do not pause the current regulated PR.** The gate is advisory and exits 0; the staleness signal is a separate cycle.
2. Open a tracking issue:

   ```bash
   gh issue create \
     --label compliance/critical \
     --title "[gdpr-gate] >90d stale rules — N days since last-verified" \
     --body "POSTURE_FAIL emitted on PR #<N>. Detection rules pinned at $(bash plugins/soleur/skills/gdpr-gate/scripts/notice-frontmatter.sh field last-verified) — staleness exceeds Art. 5(2) accountability obligation."
   ```

3. Append a row to `compliance-posture.md` §Active Compliance Items using the canonical row schema. The gate never writes there directly; this is operator-acknowledged write only.
4. Commit:

   ```bash
   git commit -m "compliance: register vendor-pin-staleness for #<issue>"
   ```

5. Drive re-vendor:
   - If a `ci/content-vendor-drift-*` PR is already open, ping it (none has ever existed — the auto-PR route is unimplemented; see §2).
   - Otherwise dispatch via `/soleur:trigger-cron` (`cron/content-vendor-drift.manual-trigger`).
6. The current regulated PR ships per its own gate; the staleness-driven follow-up is a separate work cycle with its own review and merge. The Active Compliance Items row tracks both.

Precedent: `knowledge-base/engineering/operations/runbooks/admin-ip-drift.md` uses the same operator-acknowledged-write pattern for credential drift.
