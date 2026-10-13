# Tasks: fix-version-banner-inplace-install

Plan: `knowledge-base/project/plans/2026-10-12-fix-plugin-version-checkout-identity-plan.md`

## Phase 0.0 - premise probe (before any test or code)

- 0.0.1 Append a distinct probe line to `version-banner.sh` in the cache copy (`installPath`) and the folder copy; run one `cd /tmp && claude -p "reply ok"`; read which probe fired; restore both (`worktree-manager.sh sync` for the folder copy); repeat with `--plugin-dir <worktree>/plugins/soleur`
- 0.0.2 Write the observed roots to `specs/fix-version-banner-inplace-install/measurements.md`; apply the outcome table (folder -> proceed; cache -> STOP and re-scope; neither -> re-run interactively, else STOP)

## Phase 0 - RED first

- 0.1 Add the T1 positive fixtures and the T2 table-driven silent loop to `plugins/soleur/test/plugin-version.test.sh` (hand-written trees under `assert_fixture_dir`; no git needed)
- 0.2 Add the T3 malicious-config fixture + recording-stub assertions, the single gated real-git witness row, the T4 precedence/reorder rows, the T5 relation/cache rows
- 0.3 Add the T6 hook rows to `plugins/soleur/test/version-banner-hook.test.sh` (default zero-network arm under the restricted PATH, opt-in older warning, fail-open `fo_tree` with `source=checkout`, cwd in another repo)
- 0.4 Add the two T7 real-git parity rows (bare-in-`.git` clone with packed refs; `git worktree add`), gated, with run-deficit credit
- 0.5 Apply the Test-design corrections (plan, Test Scenarios): move the existing repo-run `unknown` row onto a sandbox copy, single-field-delta silent table over one base fixture, per-site validator rows, cap boundary pairs, FIFO writer bound, real-git four-shape loop, separate non-bare witness fixture, `skip_case` run-credit arg + `GB_CASES/GB_RUNS`, `SKIP_BANNER_DEFICIT`
- 0.6 Run both suites; record that only the new rows fail (floors untouched)

## Phase 1 - resolver

- 1.1 `file_size` (`stat -c %s || stat -f %z`), `read_small` (`[[ -f && -r ]]`, size <= 512, `{ IFS= read -r -n 512; } 2>/dev/null || true`) and `packed_ref_sha` (size <= 4 MiB, awk with `ENVIRON`)
- 1.2 `valid_ref_name` (deny-list via `case`, no arrays) and `resolve_checkout_commit` (anchor incl. existence of `plugin.json` ONLY (CTO override 2026-10-13: no `marketplace.json` check; NUL-spliced HEAD = byte-count vs stat-size mismatch = unknown, LC_ALL=C), parameter-expansion paths, `.git` file, `commondir`, loose-then-packed)
- 1.3 Wire into `resolve_installed` after the 12-hex branch; `INST_ID` = sha12; cache file `latest-release.checkout`; `load_cache` maps another commit's checkout entry to `cache=missing`
- 1.4 `compute_relation`: `commit|checkout` with a 12-hex re-validation before `curl`; update the header comments (incl. the cache paragraph)

## Phase 2 - hook

- 2.1 `checkout)` arm with the `^[0-9a-f]{12}$` whitelist and `(local checkout)` label; header comment

## Phase 3 - commands

- 3.1 `commands/version.md`: top paragraph, key notes, Installed line rules, `compare-failed` sentence, `source=checkout` arm FIRST in the Step 2 template line and "Choose by" list (three labelled sub-cases with the `rev-parse --is-bare-repository` test: bare = fetch-then-sync, clone = `git pull`, `--plugin-dir` = no marketplace commands; HEAD-not-files line; moving-checkout line; unknown-text sentence for an unreadable checkout)
- 3.2 `commands/help.md`: key list + version-line template

## Phase 4 - docs, C4, legal

- 4.1 README "Version Visibility" sentence + pointer; runbook one-sentence pointer
- 4.2 `model.c4` edge wording (two phrases); regenerate `model.likec4.json`; ADR-182 one-line dated amendment
- 4.3 Legal clarification edits (privacy policy 4.1, GDPR policy ~53, DPD 3.1(e)) in canonical + mirror, Last Updated notes, then `legal-doc-shas.ts` LAST
- 4.4 Sweep `commit-hash install|one file per install|install id|cached per install` (`| grep -vi checkout` prints only intentionally marketplace-only lines, listed in the PR)

## Phase 5 - floors and gates

- 5.1 Set exact floors in both suites; add `SKIP_RUN_DEFICIT` to the plugin-version RUNS check; prove one floor red
- 5.2 Run the gates listed under Test Scenarios (harness-parity, components, c4-count-parity, C4 render, legal gates, guard-contract lint, shellcheck, markdownlint, fixture-relative-assert)
- 5.3 Run the Guard 1 mutation battery once against throwaway copies; paste results in the PR

## Phase 6 - post-merge (ship/postmerge)

- 6.1 In the bare root: `git fetch --no-tags origin main:main`, then `worktree-manager.sh sync`
- 6.2 `claude plugin marketplace update soleur && claude plugin update soleur@soleur`
- 6.3 Record `H0`, run the headless `--include-hook-events` capture from `/tmp`, record `H1`; PASS = banner sha in `{H0,H1}` plus the literal `(local checkout)`; paste the three outputs; linked follow-up issue if no banner line

CTO overrides 2026-10-13 (see plan, 'BINDING CTO overrides'): (1) anchor has no `marketplace.json` check; bare-in-`.git` fixture omits it; vendored row flips to checkout; (2) NUL-spliced HEAD pins `unknown` via byte-count vs `stat` size compare under `LC_ALL=C`.
