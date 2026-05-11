# Runbook: Vendor Pin Drift Resolution

When the `scheduled-content-vendor-drift.yml` workflow files a re-vendor PR (label `vendor/pin-drift`) or opens a tracking issue (label `vendor/cron-failure` / `vendor/upstream-rollback` / `vendor/upstream-archived`), use this runbook to resolve the situation.

Cross-references:
- Policy: `knowledge-base/engineering/policies/content-vendoring.md`
- Workflow: `.github/workflows/scheduled-content-vendor-drift.yml`
- Compliance posture: `knowledge-base/legal/compliance-posture.md` §Vendored Code Provenance
- gdpr-gate skill: `plugins/soleur/skills/gdpr-gate/SKILL.md`
- Helper scripts: `plugins/soleur/skills/gdpr-gate/scripts/{notice-frontmatter,vendor-pin-integrity,vendor-drift-classify}.sh`

## 1. Synthetic-Drift Test (post-merge AC validation)

Run this once after merging the PR that landed this runbook (#3517) to verify the workflow end-to-end:

```bash
# 1. Create a feature branch with a deliberately-wrong NOTICE pinned-commit.
git checkout -b synthetic-drift-test
sed -i 's|^pinned-commit: 7b58d68.*|pinned-commit: deadbeefdeadbeefdeadbeefdeadbeefdeadbeef|' \
  plugins/soleur/skills/gdpr-gate/NOTICE
git commit -am 'test: mutate NOTICE pinned-commit for drift workflow validation'
git push -u origin synthetic-drift-test

# 2. Dispatch the workflow against this branch.
gh workflow run scheduled-content-vendor-drift.yml --ref synthetic-drift-test

# 3. Poll until the run completes.
RUN_ID=$(gh run list --workflow=scheduled-content-vendor-drift.yml \
                     --branch=synthetic-drift-test --limit=1 \
                     --json databaseId --jq '.[0].databaseId')
gh run watch "$RUN_ID"

# 4. Assert the workflow opened an auto-PR (or filed a tracking issue).
gh pr list --search 'head:ci/vendor-drift-' --state all --limit 5
```

Expected outcome: a PR is opened against `synthetic-drift-test` with at least the `vendor/pin-drift` label. NOTICE `last-verified` on the auto-PR is bumped to today's date. Delete the test branch after assertion: `gh pr close <num>` and `git push origin --delete synthetic-drift-test`.

## 2. Conflict-Marker Resolution (`needs-human-review` label)

When the auto-PR is labeled `needs-human-review`, the workflow's inline 3-way merge produced conflict markers (`<<<<<<<`, `=======`, `>>>>>>>`). The classifier output and bumped NOTICE are still on the PR branch, but the lifted-file changes are unmerged.

1. Check out the PR branch locally: `gh pr checkout <num>`.
2. For each lifted file with conflict markers (`grep -l '<<<<<<<' plugins/soleur/skills/gdpr-gate/references/`):
   - Open the file. The `--diff3` markers show three labels: `<<<<<<< <our>`, `||||||| <base>` (the pinned upstream blob), `=======`, `>>>>>>> <theirs>` (the new upstream blob).
   - Decide per hunk: keep our text (Soleur extension is right), keep theirs (upstream patch supersedes our extension), or merge (combine both).
   - Remove all conflict markers.
3. After resolving, recompute the local blob SHA: `git hash-object --no-filters <path>`.
4. Update NOTICE `local-blob-sha` for the resolved file to the new SHA.
5. Commit: `git commit -am "fix(vendor-drift): resolve conflict on <path>"`.
6. Push and re-run the workflow's classifier locally to verify no further drift: `bash plugins/soleur/skills/gdpr-gate/scripts/vendor-pin-integrity.sh plugins/soleur/skills/gdpr-gate/references/<path>`.
7. Remove the `needs-human-review` label and merge.

## 3. Upstream Rollback (`vendor/upstream-rollback` label)

The classifier exits 15 when upstream HEAD is an ancestor of our pinned SHA — i.e., upstream went BACKWARD. Two underlying scenarios:

### 3a. Intentional upstream rollback

Upstream maintainers reverted a commit (security regression, unintended breaking change). We probably want to follow them — re-pin to upstream HEAD and inherit the rollback.

1. Verify the rollback is intentional by reading upstream commit history: `gh api repos/<o>/<r>/commits?per_page=10`.
2. Check the upstream issue tracker / changelog for a rollback announcement.
3. If intentional: dispatch the workflow with `--ref main` to bump to current upstream HEAD. The classifier will re-run; if exit 15 stabilizes, manually edit NOTICE `pinned-commit` to the rollback target SHA and open a non-auto PR.

### 3b. Force-push accident

Upstream maintainer accidentally force-pushed an older commit on top of newer history. We do NOT want to follow.

1. Open a tracking issue: `gh issue create --label vendor/upstream-rollback --title "[vendor-drift] Suspected upstream force-push: <o>/<r> rolled back"`.
2. Ping upstream maintainers via their preferred channel (issue, Discord, email).
3. Hold the auto-PR (do not merge). Re-run the workflow weekly until upstream re-publishes the newer history.

## 4. Upstream Renamed (`vendor/upstream-archived` + redirect)

When `gh api repos/<o>/<r>` returns a `full_name` that doesn't match our recorded `<o>/<r>`, GitHub has redirected the canonical path:

1. Update NOTICE `upstream` field to the new `github.com/<new-owner>/<new-repo>` path.
2. Verify upstream content is still accessible at that new path.
3. Re-run the workflow (`gh workflow run scheduled-content-vendor-drift.yml`).
4. Merge any drift PR the re-run produces normally.

## 5. Upstream Archived (`vendor/upstream-archived`, no redirect)

When upstream is permanently archived (read-only, will not receive patches), we have a fork-or-drop decision.

1. File an Architecture Decision Record via `/soleur:architecture create` titled "Upstream `<o>/<r>` archived — fork or drop?". The ADR should weigh: maintenance cost of a fork, criticality of the lifted content, availability of an alternative upstream.
2. Until the ADR resolves, leave the auto-PR open (do not merge). The runtime staleness banner will continue to fire on every gdpr-gate invocation, which is the correct user signal: "this rule set is no longer maintained; your output is advisory."
3. ADR outcomes:
   - **Fork**: create `Soleur/<repo>` as a hard fork, change NOTICE `upstream` to point at the fork, rotate `pinned-commit`, merge.
   - **Drop**: delete the lifted files + NOTICE entry, update `compliance-posture.md` registry to remove the row, rotate any downstream skill references.

## 6. Cron Failure (`vendor/cron-failure` issue)

The `if: failure()` step in the workflow opens an issue when the cron itself fails (gh api 5xx, rate-limit, runner OOM, etc.). The issue title and body link to the failed run.

1. Inspect the run: `gh run view <run-id> --log`.
2. Common transient causes:
   - **Rate-limit** (HTTP 403 from `gh api`): wait one hour, manually re-dispatch.
   - **Upstream 5xx**: wait, re-dispatch. If GitHub Status indicates a degraded API, hold until resolved.
   - **Runner OOM**: rare; bump the timeout-minutes or split into smaller batches if it recurs.
3. If the failure persists across two consecutive re-dispatches, escalate: read the policy doc §4.1 and consider whether the workflow logic itself needs revision (issue + PR).

## 7. POSTURE_FAIL Operator Chain (>90d stale)

When `gdpr-gate.sh` emits `POSTURE_FAIL: gdpr-gate rules >90 days stale` to STDOUT during a regulated PR's `/soleur:gdpr-gate` invocation, the gate is signaling that the cron + auto-PR pipeline has been silently broken for >90 days and the lifted detection rules are dangerously stale. The chain:

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
   - If a `ci/vendor-drift-*` PR is already open, ping it.
   - Otherwise dispatch: `gh workflow run scheduled-content-vendor-drift.yml`.
6. The current regulated PR ships per its own gate; the staleness-driven follow-up is a separate work cycle with its own review and merge. The Active Compliance Items row tracks both.

Precedent: `knowledge-base/engineering/ops/runbooks/admin-ip-drift.md` uses the same operator-acknowledged-write pattern for credential drift.
