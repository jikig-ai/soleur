# Tasks: fix-version-banner-inplace-install

Plan: `knowledge-base/project/plans/2026-10-12-fix-plugin-version-checkout-identity-plan.md`

## Phase 0 - RED first

- 0.1 Add the T1 positive fixtures and the T2 table-driven silent loop to `plugins/soleur/test/plugin-version.test.sh` (hand-written trees under `assert_fixture_dir`; no git needed)
- 0.2 Add the T3 malicious-config fixture + recording-stub assertions, the single gated real-git witness row, the T4 precedence/reorder rows, the T5 relation/cache rows
- 0.3 Add the T6 hook rows to `plugins/soleur/test/version-banner-hook.test.sh` (default zero-network arm under the restricted PATH, opt-in older warning, fail-open `fo_tree` with `source=checkout`, cwd in another repo)
- 0.4 Add the two T7 real-git parity rows (bare-in-`.git` clone with packed refs; `git worktree add`), gated, with run-deficit credit
- 0.5 Run both suites; record that only the new rows fail (floors untouched)

## Phase 1 - resolver

- 1.1 `read_small` (builtin `read -n 512` after `[[ -f ]]`) and `packed_ref_sha` (cap+1 `head -c` into awk)
- 1.2 `valid_ref_name` (deny-list via regex + `case`, no arrays) and `resolve_checkout_commit` (anchor, `.git` file, `commondir`, loose-then-packed)
- 1.3 Wire into `resolve_installed` after the 12-hex branch; `INST_ID` = sha12; cache file `latest-release.checkout`
- 1.4 `compute_relation`: `commit|checkout`; update the header comments

## Phase 2 - hook

- 2.1 `checkout)` arm with the `^[0-9a-f]{12}$` whitelist and `(local checkout)` label; header comment

## Phase 3 - commands

- 3.1 `commands/version.md`: top paragraph, key notes, Installed line rules, `compare-failed` sentence, `source=checkout` arm FIRST in the Step 2 template line and "Choose by" list (fetch-then-sync for the bare layout, `git pull` for a clone, `--plugin-dir` line, HEAD-not-files line, moving-checkout line)
- 3.2 `commands/help.md`: key list + version-line template

## Phase 4 - docs, C4, legal

- 4.1 README "Version Visibility" sentence + pointer; runbook one-sentence pointer
- 4.2 `model.c4` edge wording; regenerate `model.likec4.json`
- 4.3 Legal clarification edits (privacy policy 4.1, GDPR policy ~53, DPD 3.1(e)) in canonical + mirror, Last Updated notes, then `legal-doc-shas.ts` LAST
- 4.4 `grep -rn 'commit-hash install'` sweep ends with every hit widened or marketplace-only

## Phase 5 - floors and gates

- 5.1 Set exact floors in both suites; add `SKIP_RUN_DEFICIT` to the plugin-version RUNS check; prove one floor red
- 5.2 Run the gates listed under Test Scenarios (harness-parity, components, c4-count-parity, C4 render, legal gates, guard-contract lint, shellcheck, markdownlint, fixture-relative-assert)
- 5.3 Run the Guard 1 mutation battery once against throwaway copies; paste results in the PR

## Phase 6 - post-merge (ship/postmerge)

- 6.1 In the bare root: `git fetch --no-tags origin main:main`, then `worktree-manager.sh sync`
- 6.2 `claude plugin marketplace update soleur && claude plugin update soleur@soleur`
- 6.3 `claude plugin list` and the headless `--include-hook-events` capture; paste both; follow-up issue if no banner line
