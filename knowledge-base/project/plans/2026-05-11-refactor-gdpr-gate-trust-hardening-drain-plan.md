---
title: "refactor(gdpr-gate): trust-binding + self-test gate + runbook synthetic-drift fix (drain #3535 + #3536 + #3540)"
type: refactor
classification: drain-labeled-backlog
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
created: 2026-05-11
branch: feat-gdpr-gate-trust-hardening-drain
worktree: /home/jean/git-repositories/jikig-ai/soleur/.worktrees/feat-gdpr-gate-trust-hardening-drain
pr: 3541
closes: [3535, 3536, 3540]
refs: [3521, 3517, 2486]
---

# refactor(gdpr-gate): trust-binding + self-test gate + runbook synthetic-drift fix

**Drain pattern reference:** PR #2486 (one PR, three closures). Net backlog impact: **−3 closures** (#3535, #3536, #3540) with **no new scope-outs** introduced unless review surfaces a follow-up.

**References:** PR #3521 (origin review — feat-gosprinto-pin-policy), issue #3517 (vendor pipeline parent), PR #2486 (drain pattern precedent verified via `gh pr view`).

## Overview

PR #3521 shipped the gdpr-gate vendor pipeline (NOTICE frontmatter, parser, drift workflow, runtime staleness banner). Three review-origin scope-outs against that PR converged on the same weakness class: **operator-controlled fields and ungated scripts are silent-failure-prone for an advisory gate whose `single-user incident` threshold means "broken silently" is the worst outcome**. This PR drains all three:

1. **#3535 (p1-high, compliance/critical)** — bind NOTICE `last-verified` to scheduled-content-vendor-drift workflow run. Today the field is operator-controlled; a malicious or careless PR can rewrite it to today's date and suppress the 30d/90d runtime staleness banner. Fix: `cmd_days_stale` falls back to `gh run list --workflow=scheduled-content-vendor-drift.yml --status=success --limit=1 --json updatedAt` and uses `MIN(NOTICE last-verified, last successful cron run)`. Add CODEOWNERS row for NOTICE. Document offline-mode (no `GH_TOKEN`) fallback banner.

2. **#3536 (p2-medium, compliance/critical)** — persistent self-test gate for gdpr-gate scripts. The `gdpr-gate-advisory` lefthook glob does not match `plugins/soleur/skills/gdpr-gate/scripts/**`, so a future PR can break both the script and its sibling test together while the gate stays green. Fix: new `.github/workflows/gdpr-gate-self-test.yml` runs `gdpr-gate.sh` against a deliberately-stale fixture NOTICE on PRs touching the scripts path; asserts banner-on-stdout. Cross-link from lefthook comment.

3. **#3540 (deferred-scope-out)** — runbook §1 synthetic-drift test mutates `pinned-commit`, but the workflow ignores that field (it compares per-file `upstream-blob-sha`). Documented test exits "no drift detected" — AC13 validation effectively skipped. Fix: reframe §1 as Option 3 from the issue body (validate the cron-failure path: mutate one `upstream-blob-sha` to a non-existent SHA, dispatch, assert `vendor/cron-failure` issue auto-filed).

All three defend the same gdpr-gate / vendor-drift pipeline. The two compliance/critical issues (#3535 + #3536) are complementary: the new fixture from #3536 should also exercise the MIN-of-(last-verified, cron-run-timestamp) logic from #3535, so a future regression to either layer fires the same self-test.

## User-Brand Impact

**If this lands broken, the user experiences:**

- A `/soleur:gdpr-gate` invocation on a regulated PR returns "no findings" against rule sets that are silently stale (last-verified backdated by a malicious or rebased PR; or cron silently disabled while a comply-friendly NOTICE last-verified is preserved). The user reads "advisory: clean" and ships a PR that touches Art. 9 special-category data under detection rules that have not been refreshed for weeks/months. The brand commitment "this gate caught it" becomes "this gate said clean and the rule that would have caught it was 60 days stale".

**If this leaks, the user's [data / workflow / money] is exposed via:**

- A regulated-data PR (PII fields, auth flows, schemas, API routes) that should have triggered an Art. 9 Critical finding ships under a false-clean advisory result. The downstream blast radius is the same as #2887 — single-user incident threshold — because the per-PR gate is the load-bearing pre-emission catch in the EU `single-user incident` band. Once one user's data is mis-classified, the compliance posture row will say "we had a gate" while the gate was demonstrably bypassed.

**Brand-survival threshold:** `single-user incident`

**Sign-off required:**

- CPO sign-off at plan time (this section's threshold).
- `user-impact-reviewer` at review time (handled by `plugins/soleur/skills/review/SKILL.md` conditional-agent block when `requires_cpo_signoff: true` in frontmatter).

## Research Reconciliation — Spec vs. Codebase

| Spec / Issue claim | Codebase reality (verified 2026-05-11) | Plan response |
| --- | --- | --- |
| #3535 — `cmd_days_stale` is the parser fn to extend | Confirmed: `plugins/soleur/skills/gdpr-gate/scripts/notice-frontmatter.sh` lines 68-88. Returns 999 on parse failure (always-exit-0 contract). | Extend with `cron-run-stale` subcommand + optional gh-cron MIN in `cmd_days_stale`. Preserve always-exit-0. |
| #3535 — `gdpr-gate.sh` subshell-execs the parser, passes nothing through | Confirmed: lines 47-50 use `bash "$NOTICE_PARSER" days-stale 2>/dev/null \|\| echo 999`. No env propagation. | Propagate `GH_TOKEN` (or `GITHUB_TOKEN`) explicitly via `env GH_TOKEN="$GH_TOKEN" bash "$NOTICE_PARSER" ...`. Emit distinct banner when neither token is present. |
| #3535 — workflow name is `scheduled-content-vendor-drift.yml` | Confirmed: `.github/workflows/scheduled-content-vendor-drift.yml`. Name: `"Scheduled: Content Vendor Drift"`. | Use the **filename** for `gh run list --workflow=` — name string contains spaces and is brittle. |
| #3535 — CODEOWNERS exists | Confirmed: `.github/CODEOWNERS` present, owner `@jeanderuelle`, pattern-based. No NOTICE row yet. | Append `/plugins/soleur/skills/gdpr-gate/NOTICE @jeanderuelle` row in the secret-scanning-floor block. |
| #3536 — `gdpr-gate-advisory` glob does not cover scripts/ | Confirmed: `lefthook.yml` lines 101-119 — glob is regulated-data paths only (migrations, auth, api). Scripts are unprotected. | NEW workflow `gdpr-gate-self-test.yml` is the load-bearing self-test (runs in CI on `pull_request` paths). Update lefthook comment to cross-link, not to add a fixture-based pre-commit stanza (slow + flaky). |
| #3536 — fixture path `plugins/soleur/test/fixtures/gdpr-gate-stale/NOTICE` | Confirmed `plugins/soleur/test/fixtures/` exists with sibling fixture dirs (`vendor-drift/`, `cleanup-scope-outs/`, `auto-close-scanner/`, etc.). Adding `gdpr-gate-stale/` follows precedent. | Create the fixture dir + NOTICE. Reuse existing 5-file `lifted-files:` shape from live NOTICE (so parser exercises both code paths) but with `last-verified: 2025-11-01` (200d+ stale) and a placeholder `pinned-commit`. |
| #3540 — runbook §1 mutates `pinned-commit` only | Confirmed: `knowledge-base/engineering/ops/runbooks/vendor-pin-drift-resolution.md` §1 lines 16-37. | Rewrite §1 to mutate one `upstream-blob-sha` to `0000...0000`, dispatch, assert `vendor/cron-failure` issue (Option 3 from #3540 body). |
| #3540 — workflow uses `upstream-blob-sha` not `pinned-commit` for drift | Confirmed: `.github/workflows/scheduled-content-vendor-drift.yml` line 308+ — Python regex operates on `upstream-blob-sha`. `pinned-commit` is updated only AFTER drift is detected (informational rollback anchor). | Runbook test must mutate `upstream-blob-sha`. Use a non-existent SHA so the `gh api .../git/blobs/<sha>` lookup 404s → cron-failure issue. |
| All three — `Closes #N` policy | `wg-use-closes-n-in-pr-body-not-title-to`: `Closes #N` must be on its own body line. | PR body will contain three lines: `Closes #3535\nCloses #3536\nCloses #3540`, plus `Ref #3521` + `Ref #3517` + `Ref #2486`. PR title MUST NOT include any `Closes` token. |

**Verification of `gh run list` form** (per `cq-... CLI-verification gate`):

```bash
gh run list --workflow=scheduled-content-vendor-drift.yml \
            --status=success --limit=1 \
            --json updatedAt --jq '.[0].updatedAt'
# Expected: an RFC 3339 timestamp string, e.g. "2026-05-09T11:24:53Z"
# Verified against: https://cli.github.com/manual/gh_run_list (--json fields include updatedAt)
```

## Open Code-Review Overlap

The plan's `## Files to Edit` and `## Files to Create` sections (below) were checked against `gh issue list --label code-review --state open --json number,title,body --limit 200`. Results:

- #3535 — **fold in** (this PR closes it).
- #3536 — **fold in** (this PR closes it).
- #3540 — **fold in** (this PR closes it).
- No other open `code-review` issues touch `plugins/soleur/skills/gdpr-gate/scripts/**`, `.github/workflows/gdpr-gate-self-test.yml`, `.github/CODEOWNERS`, `lefthook.yml` lines 94-119, or `knowledge-base/engineering/ops/runbooks/vendor-pin-drift-resolution.md` §1.

## Files to Edit

| Path | Issue | Change |
| --- | --- | --- |
| `plugins/soleur/skills/gdpr-gate/scripts/notice-frontmatter.sh` | #3535 | Add `cron-run-stale` subcommand. Extend `cmd_days_stale` to optionally MIN with workflow-run timestamp when `GH_TOKEN`/`GITHUB_TOKEN` is available. Preserve always-exit-0. |
| `plugins/soleur/skills/gdpr-gate/scripts/gdpr-gate.sh` | #3535 | Pass `GH_TOKEN` (or `GITHUB_TOKEN` fallback) through to parser invocation. Emit a distinct banner string when neither is present (`OPERATOR_ATTESTED_MODE` — advisory: cron-run timestamp unavailable, falling back to operator-controlled last-verified). |
| `plugins/soleur/skills/gdpr-gate/SKILL.md` | #3535 | Document `GH_TOKEN` auth contract (where it comes from in CI vs local; absent in subagent contexts). Document the operator-attested-mode banner and the three-way precedence: (cron-timestamp present + min beats last-verified) > (cron-timestamp absent → operator-attested banner) > (parse failure → 999). |
| `.github/CODEOWNERS` | #3535 | Append `/plugins/soleur/skills/gdpr-gate/NOTICE @jeanderuelle` under the secret-scanning-floor section with a comment: "Trust-binding gate — protects last-verified from drive-by edits (issue #3535)." |
| `lefthook.yml` | #3536 | Update the `gdpr-gate-advisory` comment block (lines 94-100) to cross-link the new CI workflow as the load-bearing self-test. **Do not** add a new pre-commit stanza — fixture runs are slow + flaky for `pre-commit:`. |
| `knowledge-base/engineering/ops/runbooks/vendor-pin-drift-resolution.md` | #3540 | Rewrite §1 (lines 12-37) as the cron-failure-path test (Option 3 from #3540 issue body). Mutate one `upstream-blob-sha` to `0000000000000000000000000000000000000000`, dispatch, poll, assert `vendor/cron-failure` issue auto-filed. Old §1 prose moved into a `<details>` block for historical reference OR deleted (decide at work time based on which keeps the runbook scannable). |

## Files to Create

| Path | Issue | Purpose |
| --- | --- | --- |
| `.github/workflows/gdpr-gate-self-test.yml` | #3536 | CI workflow triggered on `pull_request` for `plugins/soleur/skills/gdpr-gate/scripts/**` and `plugins/soleur/test/fixtures/gdpr-gate-stale/**` paths. Runs `gdpr-gate.sh` against the deliberately-stale fixture NOTICE (via `NOTICE_FILE` env var) and asserts (a) stdout contains the 30d staleness banner, (b) stdout contains the `POSTURE_FAIL:` >90d line, (c) when `GH_TOKEN` is **unset**, stdout also contains the operator-attested-mode banner from #3535. |
| `plugins/soleur/test/fixtures/gdpr-gate-stale/NOTICE` | #3536 | Fixture NOTICE with `last-verified: 2025-11-01` (~190 days stale at 2026-05-11). Mirrors live NOTICE shape (5 `lifted-files:` entries) so the parser exercises both `days-stale` and `lifted-files`/`upstream-files` code paths. Fixture uses synthetic SHAs (`aaa...`/`bbb...`) per `cq-test-fixtures-synthesized-only`. |
| `plugins/soleur/test/gdpr-gate-self-test.test.sh` | #3536 | Local mirror of the CI workflow assertions so an operator running `bash plugins/soleur/test/*.test.sh` exercises the same gate. Uses `NOTICE_FILE=$FIXTURES_DIR/gdpr-gate-stale/NOTICE`. Three test cases: (a) stale banner fires, (b) POSTURE_FAIL line fires, (c) operator-attested-mode banner fires when `GH_TOKEN` is explicitly unset. |

## Implementation Phases

Phases are sequenced **contract-first** per `cq-...load-bearing-when-contract-changes`:

### Phase 1 — Parser contract extension (#3535, foundations)

1.1. Add `cron-run-stale` subcommand to `notice-frontmatter.sh`. Reads `GH_TOKEN` (or `GITHUB_TOKEN`) from env; if absent, prints `999` and exits 0 (preserves advisory contract). When present, invokes `gh run list --workflow=scheduled-content-vendor-drift.yml --status=success --limit=1 --json updatedAt --jq '.[0].updatedAt'`, parses the RFC 3339 timestamp, computes days-since with `date -u -d`. Strict ISO regex guard mirrors the existing `cmd_days_stale` guard. Any parse failure → 999.

1.2. Extend `cmd_days_stale` to compute `MIN(last-verified-days, cron-run-days)` when both are non-999. If `cron-run-days` is 999 (token absent or gh failure) AND `last-verified-days` is non-999, set an env-exported sentinel `GDPR_GATE_CRON_TIMESTAMP_UNAVAILABLE=1` that the caller (`gdpr-gate.sh`) reads. (Bash subshell-exec drops env exports back to the parent — use stdout dual-line or a stderr breadcrumb pattern; decide at work time. Recommended: stdout single integer kept, banner-decision pushed into `gdpr-gate.sh` via a separate `cron-run-stale` subshell-exec.)

1.3. Add test cases to `plugins/soleur/test/notice-frontmatter.test.sh`:
   - TS-cron-1: `cron-run-stale` with `GH_TOKEN=""` → emits `999`, exits 0.
   - TS-cron-2: `cron-run-stale` with `GH_TOKEN=<valid>` against a stubbed gh wrapper that emits a fixture timestamp → emits expected integer.
   - TS-cron-3: `days-stale` MIN behavior — fixture NOTICE with `last-verified: 2026-05-11` (0d stale) + stubbed cron-run at `2026-02-01` (~100d stale) → emits `100` (cron wins).
   - TS-cron-4: `days-stale` with absent token but valid last-verified → emits last-verified value (operator-attested fallback).

### Phase 2 — Gate caller wiring (#3535, consumer of Phase 1 contract)

2.1. Modify `gdpr-gate.sh` to call both `days-stale` and `cron-run-stale` (two subshell-execs). Pick `MIN(both)` if both are non-999. If `cron-run-stale` returns 999 AND `days-stale` is non-999, prepend a third banner line: `ℹ gdpr-gate running in operator-attested mode (no GH_TOKEN available — cron-run timestamp unverified)`. Banner is advisory; does not change gate exit code.

2.2. Propagate `GH_TOKEN` (or `GITHUB_TOKEN` fallback) explicitly into the parser invocation via `env GH_TOKEN="${GH_TOKEN:-${GITHUB_TOKEN:-}}" bash "$NOTICE_PARSER" cron-run-stale 2>/dev/null || echo 999`.

2.3. Telemetry: emit `gdpr-gate-cron-binding` event via `incidents.sh` (when present) with `applied` / `unavailable` / `min-wins` variants. Preserves the always-exit-0 contract.

### Phase 3 — CODEOWNERS row (#3535, defense-in-depth)

3.1. Append the NOTICE row to `.github/CODEOWNERS` with the `# Trust-binding gate — protects last-verified from drive-by edits (issue #3535)` comment.

3.2. Verify the row lands in the secret-scanning-floor section (the file's existing security-pinning block), not the default-fallback block.

### Phase 4 — SKILL.md docs update (#3535, operator-facing surface)

4.1. Update `plugins/soleur/skills/gdpr-gate/SKILL.md` to document:
   - The `GH_TOKEN` auth contract — sourced from `secrets.GITHUB_TOKEN` in CI; absent in `/soleur:plan` and `/soleur:work` subagent contexts (operator-attested mode applies).
   - The operator-attested-mode banner text and what it implies.
   - The MIN precedence rule.
   - The CODEOWNERS pin on NOTICE.

4.2. Add an entry to `## Sharp Edges` in SKILL.md: "The gate's `cron-run-stale` subcommand depends on the workflow filename, not the workflow display name. If `scheduled-content-vendor-drift.yml` is ever renamed, this binding silently breaks — update both call sites in `notice-frontmatter.sh` and `gdpr-gate.sh` in the same PR."

### Phase 5 — Stale fixture + self-test workflow (#3536)

5.1. Create `plugins/soleur/test/fixtures/gdpr-gate-stale/NOTICE` with `last-verified: 2025-11-01` and synthetic SHAs. Include the same 5 `lifted-files:` entries (synthetic paths + synthetic SHAs) so the parser exercises both `days-stale` and `lifted-files` code paths.

5.2. Create `plugins/soleur/test/gdpr-gate-self-test.test.sh` mirroring the assertions the CI workflow will make. Run with `NOTICE_FILE=$FIXTURES_DIR/gdpr-gate-stale/NOTICE`. Assert: stdout contains `gdpr-gate rules ... days stale`, `POSTURE_FAIL:`, AND (when `GH_TOKEN=""`) the operator-attested-mode banner.

5.3. Create `.github/workflows/gdpr-gate-self-test.yml`:
   - Trigger: `pull_request` on `plugins/soleur/skills/gdpr-gate/scripts/**` + `plugins/soleur/test/fixtures/gdpr-gate-stale/**` + `lefthook.yml` (for the comment-cross-link path).
   - Steps: checkout, run `NOTICE_FILE=$FIXTURES_DIR/gdpr-gate-stale/NOTICE bash plugins/soleur/skills/gdpr-gate/scripts/gdpr-gate.sh` against a synthetic staged-files list, capture stdout, grep for the three required strings (banner, POSTURE_FAIL, operator-attested when token unset).
   - Pin actions/checkout to 40-char SHA per `2026-02-27-github-actions-sha-pinning-workflow.md`.
   - `timeout-minutes: 5` (cheap test, no network calls when `GH_TOKEN=""`).
   - Route any `${{ ... }}` expansions through `env:` per existing workflow precedent.
   - Two jobs OR matrix: one with `GH_TOKEN` available (asserts MIN behavior — cron-run-stale uses 999 because fixture's synthetic workflow won't have runs, but the **absence** of the operator-attested banner is the assertion), one with explicit `unset GH_TOKEN`. Decide between two-job and matrix at work time based on which keeps the YAML scannable.

### Phase 6 — Lefthook cross-link (#3536)

6.1. Update `lefthook.yml` lines 94-100 comment block to add: `# CI self-test: .github/workflows/gdpr-gate-self-test.yml runs the gate against a fixture NOTICE on PRs touching scripts/. This is the load-bearing gate for script regressions — the lefthook glob below intentionally does NOT cover scripts/ (pre-commit fixture runs are slow and flaky).`

6.2. **Do not** add a new `pre-commit:` stanza for the fixture run. The CI workflow is the load-bearing gate; lefthook stays fast.

### Phase 7 — Runbook §1 rewrite (#3540)

7.1. Replace `knowledge-base/engineering/ops/runbooks/vendor-pin-drift-resolution.md` §1 with the cron-failure-path test:

```bash
# 1. Create a feature branch with one upstream-blob-sha mutated to a non-existent SHA.
git checkout -b synthetic-drift-test
sed -i '0,/^    upstream-blob-sha:.*/{s/^\(    upstream-blob-sha:\).*/\1 0000000000000000000000000000000000000000/}' \
  plugins/soleur/skills/gdpr-gate/NOTICE
git commit -am 'test: mutate one upstream-blob-sha to non-existent for cron-failure-path validation'
git push -u origin synthetic-drift-test

# 2. Dispatch the workflow against this branch.
gh workflow run scheduled-content-vendor-drift.yml --ref synthetic-drift-test

# 3. Poll until the run completes.
RUN_ID=$(gh run list --workflow=scheduled-content-vendor-drift.yml \
                     --branch=synthetic-drift-test --limit=1 \
                     --json databaseId --jq '.[0].databaseId')
gh run watch "$RUN_ID"

# 4. Assert the cron-failure issue auto-filed.
gh issue list --label vendor/cron-failure --search 'created:>=YYYY-MM-DD' --limit 5
# Expected: one issue labeled vendor/cron-failure with body linking to the failed run.
```

7.2. Verify the documented `sed` form against the live NOTICE structure on a scratch branch before committing the runbook update (the indent matters — fixture NOTICEs have a 4-space indent; live NOTICE has the same).

7.3. Cite the issue: `Closes #3540` in the PR body (not in the runbook).

7.4. The new §1 explicitly notes its scope: "validates the cron-failure path (most-important invariant: NOTICE tampering produces a visible alert). Does NOT validate the happy-path auto-PR creation, which requires a real upstream content change. See ADR-on-vendor-drift-validation when added."

## Acceptance Criteria

### Pre-merge (PR)

- [ ] AC1 — **#3535 parser contract**: `bash plugins/soleur/skills/gdpr-gate/scripts/notice-frontmatter.sh cron-run-stale` exits 0 and prints `999` when `GH_TOKEN=""`. With a valid token, prints a non-negative integer or `999` on parse failure. Verified via `plugins/soleur/test/notice-frontmatter.test.sh` TS-cron-1, TS-cron-2.
- [ ] AC2 — **#3535 MIN behavior**: `cmd_days_stale` returns `MIN(last-verified-days, cron-run-days)` when both are non-999, ignoring the larger value. Verified via TS-cron-3.
- [ ] AC3 — **#3535 operator-attested banner**: when `GH_TOKEN`/`GITHUB_TOKEN` are unset, `gdpr-gate.sh` stdout contains the operator-attested-mode banner string AND the standard staleness banner (when applicable). Verified via the new self-test in Phase 5.
- [ ] AC4 — **#3535 always-exit-0 preserved**: `bash plugins/soleur/skills/gdpr-gate/scripts/gdpr-gate.sh path/to/migration.sql; echo $?` prints `0` in all paths (token present, token absent, gh-cli failure, fixture stale, fixture future-dated). Verified by manual smoke + new self-test.
- [ ] AC5 — **#3535 CODEOWNERS row**: `grep -E '^/plugins/soleur/skills/gdpr-gate/NOTICE' .github/CODEOWNERS` matches exactly one line.
- [ ] AC6 — **#3535 SKILL.md docs**: `grep -E '(GH_TOKEN|operator-attested|MIN precedence)' plugins/soleur/skills/gdpr-gate/SKILL.md` returns ≥3 lines.
- [ ] AC7 — **#3536 fixture exists**: `plugins/soleur/test/fixtures/gdpr-gate-stale/NOTICE` exists and `bash plugins/soleur/skills/gdpr-gate/scripts/notice-frontmatter.sh days-stale` against it returns an integer ≥90.
- [ ] AC8 — **#3536 fixture is synthesized**: the fixture passes `node apps/web-platform/scripts/lint-fixture-content.mjs` (no real emails, no prod-shape SHAs/UUIDs).
- [ ] AC9 — **#3536 self-test workflow exists**: `.github/workflows/gdpr-gate-self-test.yml` exists, has `actions/checkout` pinned to a 40-char SHA, has `timeout-minutes:` set.
- [ ] AC10 — **#3536 self-test asserts banners**: a temporary commit that breaks `gdpr-gate.sh` (e.g., always-echo-zero on days-stale) causes the new workflow to **fail** when run via `act` or scratch-branch CI. Verified once, reverted before merge.
- [ ] AC11 — **#3536 lefthook cross-link**: `grep -E 'gdpr-gate-self-test' lefthook.yml` returns the cross-link comment.
- [ ] AC12 — **#3540 runbook fix**: `knowledge-base/engineering/ops/runbooks/vendor-pin-drift-resolution.md` §1 no longer references `pinned-commit` mutation; references `upstream-blob-sha` mutation and `vendor/cron-failure` issue assertion.
- [ ] AC13 — **PR body** contains `Closes #3535`, `Closes #3536`, `Closes #3540` each on its own line, AND `Ref #3521`, `Ref #3517`, `Ref #2486`. PR title contains no `close|fix|resolve` token (per `wg-use-closes-n-in-pr-body-not-title-to`).
- [ ] AC14 — **`bun test plugins/soleur/test/components.test.ts` and `bash plugins/soleur/test/notice-frontmatter.test.sh` are green.**
- [ ] AC15 — **lint-rule-ids** is green (`python3 scripts/lint-rule-ids.py --retired-file scripts/retired-rule-ids.txt AGENTS.md`) — this PR does not touch AGENTS.md, but the lefthook glob covers the file.
- [ ] AC16 — **CPO sign-off** captured (`requires_cpo_signoff: true` per frontmatter). CPO Domain Review subsection appended to plan or referenced via Phase 2.5 carry-forward.
- [ ] AC17 — **`user-impact-reviewer`** invoked at review time (triggered by `requires_cpo_signoff: true` frontmatter + `compliance/critical` labels).

### Post-merge (operator)

- [ ] AC18 — Trigger `gh workflow run gdpr-gate-self-test.yml --ref main` once after merge (per `wg-after-merging-a-pr-that-adds-or-modifies`). Poll until complete. Investigate any failure before closing the session.
- [ ] AC19 — Execute the new runbook §1 once against `main` to verify the cron-failure-path test works as documented. Close the test issue afterwards.

## Test Scenarios

| ID | Scenario | Component | Expected |
| --- | --- | --- | --- |
| TS1 | Parser `cron-run-stale` without token | notice-frontmatter.sh | exits 0, prints `999` |
| TS2 | Parser `cron-run-stale` with token (stubbed gh) | notice-frontmatter.sh | exits 0, prints integer ≥0 |
| TS3 | Parser `days-stale` with both signals non-999 | notice-frontmatter.sh | prints MIN of both |
| TS4 | Parser `days-stale` with cron-run-stale=999 | notice-frontmatter.sh | prints last-verified value (fallback) |
| TS5 | Gate run against fixture NOTICE, no token | gdpr-gate.sh | stdout has staleness banner + POSTURE_FAIL + operator-attested banner; exit 0 |
| TS6 | Gate run against fixture NOTICE, with token | gdpr-gate.sh | stdout has staleness banner + POSTURE_FAIL, NO operator-attested banner; exit 0 |
| TS7 | CI workflow against scratch break (e.g., always-echo-zero) | gdpr-gate-self-test.yml | workflow fails — banner assertion misses |
| TS8 | CI workflow against current scripts | gdpr-gate-self-test.yml | workflow passes |
| TS9 | Runbook §1 dry-run on scratch branch | vendor-pin-drift-resolution.md | `vendor/cron-failure` issue auto-filed within 10 minutes of dispatch |
| TS10 | CODEOWNERS row order check | .github/CODEOWNERS | row appears in secret-scanning-floor block, owned by `@jeanderuelle` |

## Risks

- **R1 (network-dep banner path)** — `cron-run-stale` introduces a network call to `gh api` from the runtime banner. Mitigation: `2>/dev/null || echo 999` wrapper preserves always-exit-0. `timeout` wrapper (`timeout 5s gh run list ...`) bounds wall clock — `gh` inherits resolver defaults otherwise. Document the bound in SKILL.md. **Sub-risk**: `gh` CLI not installed in some agent runtimes → falls through to 999 → operator-attested mode. Acceptable.
- **R2 (subshell-exec env-export drop)** — Phase 1's sentinel env var approach (`GDPR_GATE_CRON_TIMESTAMP_UNAVAILABLE=1`) does not propagate from subshell back to caller. Mitigation: chose dual-subshell-exec design (Phase 2.1) instead — `gdpr-gate.sh` invokes the parser twice and reasons about both values in the caller frame. No env propagation needed.
- **R3 (CODEOWNERS bypass)** — CODEOWNERS only enforces if branch protection requires CODEOWNERS review on `main` (per existing CODEOWNERS comment: "Branch protection on `main` requiring CODEOWNERS review is a separate operator follow-up"). If not enforced, the row is documentary only. Mitigation: still ship the row (cheap, no-regret); explicitly call out in PR body that branch-protection enforcement remains an operator follow-up. Trust-binding via cron-run timestamp (#3535 core) is the load-bearing defense; CODEOWNERS is defense-in-depth.
- **R4 (fixture drift)** — fixture NOTICE with `last-verified: 2025-11-01` will eventually be SO stale that future test failures masquerade as fixture rot. Mitigation: pin fixture `last-verified` to a date far enough in the past that >90d holds (200d+), comment in the fixture noting the intent. Sibling fixture pattern (`plugins/soleur/test/fixtures/vendor-drift/`) uses the same approach.
- **R5 (workflow-rename silent break)** — `cron-run-stale` hard-codes the workflow filename. Renaming the workflow would silently break the binding (falls to 999 → operator-attested mode → gate stays green-but-degraded). Mitigation: SKILL.md Sharp Edges entry (Phase 4.2). Stronger mitigation deferred — could grep-link via a shared constant, but not worth the abstraction for one consumer.
- **R6 (multi-agent review burden)** — `compliance/critical` + `single-user incident` threshold triggers `user-impact-reviewer` + CPO at review. Plan-review will spawn 3 reviewers (DHH, Kieran, Code Simplicity). Expected, budgeted, and the right level of scrutiny per AGENTS.md.

## Domain Review

**Domains relevant:** Engineering (CTO), Product (CPO)

This is an engineering-internal refactor with no user-facing UI change. Product domain is relevant **only** because the `single-user incident` threshold triggers CPO sign-off per AGENTS.md `hr-weigh-every-decision-against-target-user-impact`. CMO/CLO/CFO/CRO/COO/CCO are NOT relevant — no marketing surface, no legal-doc change, no expense, no sales pipeline, no ops provisioning, no support flow.

### Engineering (CTO)

**Status:** carry-forward from PR #3521 review (this PR closes scope-outs from #3521; CTO already reviewed the parent design)
**Assessment:** Pipeline already understood. Trust-binding via cron-run timestamp follows the existing dual-source defense pattern (NOTICE + workflow). Self-test workflow follows the `scheduled-skill-freshness.yml` precedent. Runbook fix is doc-only.

### Product/UX Gate

**Tier:** N/A — no UI surface
**Decision:** auto-accepted (engineering-only)
**Agents invoked:** none
**Skipped specialists:** none
**Pencil available:** N/A

**CPO sign-off:** Required per `requires_cpo_signoff: true` frontmatter. CPO assessment carry-forward from #3521 review (same threshold, same blast radius, narrower scope: this PR makes the parent's trust model more robust, not less). If CPO has not signed off on #3521's `single-user incident` framing, invoke CPO before `/work`. Otherwise, plan-time sign-off is satisfied.

#### Findings

- This PR strengthens an existing `single-user incident` gate without expanding its blast radius or surface. The user-impact framing inherits from #3521's framing and is recorded in `## User-Brand Impact` above.

## GDPR / Compliance Gate

This plan touches `plugins/soleur/skills/gdpr-gate/**` (the compliance gate's own implementation) but does NOT touch any regulated-data surface per `hr-gdpr-gate-on-regulated-data-surfaces` (no schemas, migrations, auth flows, API routes, SQL files). The canonical regex match is empty.

However, because this plan modifies the gate's own trust model and carries `single-user incident` brand threshold, the gate's own review-time reflexivity applies:

- The implementation MUST preserve the always-exit-0 advisory contract (AC4).
- The new banner text MUST be visible on stdout (not stderr) per the agent-runtime stderr-swallow precedent.
- The cron-run binding MUST gracefully degrade to operator-attested mode in subagent contexts that lack `GH_TOKEN`. Otherwise `/soleur:plan` Phase 2.7 and `/soleur:work` Phase 2 exit would emit the operator-attested banner spuriously on every invocation, training operators to ignore it.

No Art. 9 special-category, lawful-basis, or Art. 30 trigger applies. No `compliance-posture.md` write needed.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. This plan's section is populated; do not let `/work` trim it.
- The `cron-run-stale` subcommand introduces a network call into the runtime banner path. Always wrap with `timeout 5s` and `|| echo 999` to bound wall clock — `gh` CLI inherits resolver/socket defaults otherwise (per `hr-when-a-plan-prescribes-dig-nslookup-curl` sibling pattern in plan-skill Sharp Edges).
- The self-test workflow's GH_TOKEN matrix MUST include an explicit `GH_TOKEN=""` run — not just "omit the env var", because GitHub Actions injects `GITHUB_TOKEN` automatically. Use `env: { GH_TOKEN: "", GITHUB_TOKEN: "" }` on the operator-attested-mode test job.
- The runbook §1 rewrite changes the **observable outcome** (cron-failure issue instead of auto-PR). Any operator who memorized the previous expected outcome may report a "regression" — note this in PR body and runbook prose.
- The new fixture NOTICE at `plugins/soleur/test/fixtures/gdpr-gate-stale/` must NOT be added to `vendor-pin-integrity`'s registry view. The integrity script reads `NOTICE_FILE` from the live skill NOTICE; the fixture is invoked via env-override only and lives outside the integrity gate's scope. Verify by running `bash plugins/soleur/skills/gdpr-gate/scripts/vendor-pin-integrity.sh` and confirming no extra registry entries appear.
- CODEOWNERS branch-protection enforcement on `main` is an **operator follow-up** outside the scope of this PR (requires repo-admin scope per existing CODEOWNERS comment). The row is documentary unless the protection rule is in place. PR body should call this out so the row's value is not over-stated.
- The `gh run list` form prescribed in this plan returns an empty array on a freshly-merged main with no successful runs. Test against both `--limit=1` returning a value AND returning `[]` — the `jq '.[0].updatedAt'` selector emits `null` on empty, which the parser MUST treat as 999.

## Compounds & Telemetry

- Emit `gdpr-gate-cron-binding` incidents per Phase 2.3 (variants: `applied`, `unavailable`, `min-wins`).
- After merge, monitor the `gdpr-gate-self-test.yml` workflow for false-positives across the next ~5 unrelated PRs touching `plugins/soleur/skills/gdpr-gate/scripts/**`. If the workflow flakes, file a follow-up issue rather than disabling.

## Out of Scope / Deferred

- **Signed git-tag binding for `last-verified`** (the strongest variant of #3535). Cron-run-timestamp binding is the chosen variant per the issue body; signed-tag binding requires release tooling not in place. If a future incident shows cron-run binding insufficient, file a successor issue and link to this plan.
- **Generalizing the lifted-files registry to multiple upstreams** (bundle-2 lift). #3540 already cites this as a re-evaluation trigger; out of scope here.
- **Branch protection rule on `main` requiring CODEOWNERS review.** Operator follow-up; outside agent-shell scope.
- **Workflow display-name → filename grep-linking.** R5 mitigation is a SKILL.md Sharp Edge entry only.

## PR Body Template (for `/work` to use)

```text
refactor(gdpr-gate): trust-binding + self-test gate + runbook synthetic-drift fix

Drains three scope-outs from PR #3521 review into one focused refactor PR.

Closes #3535
Closes #3536
Closes #3540

Ref #3521
Ref #3517
Ref #2486

## Summary

- **#3535** — Bind NOTICE `last-verified` to the scheduled-content-vendor-drift workflow's last successful run. Parser now exposes `cron-run-stale`; gate uses `MIN(last-verified, cron-run)` when both are available, falls back to operator-attested mode with a distinct banner when `GH_TOKEN` is unavailable. CODEOWNERS pins NOTICE.
- **#3536** — New `.github/workflows/gdpr-gate-self-test.yml` runs `gdpr-gate.sh` against a deliberately-stale fixture NOTICE on PRs touching the scripts path. Local mirror at `plugins/soleur/test/gdpr-gate-self-test.test.sh`. Asserts banner-on-stdout + operator-attested-mode behavior.
- **#3540** — Runbook §1 rewritten to mutate `upstream-blob-sha` (the field the workflow actually consumes) and assert `vendor/cron-failure` issue auto-filed.

## Brand-survival threshold

`single-user incident` — same band as parent PR #3521. CPO sign-off captured at plan time; `user-impact-reviewer` invoked at review.

## Changelog

### Soleur Plugin

- gdpr-gate: trust-binding via cron-run timestamp + operator-attested-mode fallback (#3535)
- gdpr-gate: persistent CI self-test gate against fixture NOTICE (#3536)
- runbook: corrected synthetic-drift test path (#3540)

## Test plan

- [ ] `bun test plugins/soleur/test/components.test.ts`
- [ ] `bash plugins/soleur/test/notice-frontmatter.test.sh`
- [ ] `bash plugins/soleur/test/gdpr-gate-self-test.test.sh`
- [ ] CI: `gdpr-gate-self-test.yml` green on PR
- [ ] Post-merge: `gh workflow run gdpr-gate-self-test.yml --ref main` succeeds
- [ ] Post-merge: runbook §1 dry-run files `vendor/cron-failure` issue
```

## Resume Prompt

```text
/soleur:work knowledge-base/project/plans/2026-05-11-refactor-gdpr-gate-trust-hardening-drain-plan.md

Context: branch feat-gdpr-gate-trust-hardening-drain, worktree /home/jean/git-repositories/jikig-ai/soleur/.worktrees/feat-gdpr-gate-trust-hardening-drain, PR #3541 (draft), drains #3535 + #3536 + #3540. Plan written + deepened; CPO sign-off carry-forward from PR #3521 already on file. Phase order is contract-first: parser (Phase 1) before gate caller (Phase 2) before fixtures/CI (Phase 5). Implementation next.
```
