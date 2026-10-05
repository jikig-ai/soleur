---
module: System
date: 2026-10-05
problem_type: workflow_issue
component: testing_framework
symptoms:
  - "Two consecutive review fix rounds each found fresh bypasses of the same Dockerfile/CI guard (global-install spellings, install-line forms, action refs, job keys) while every self-run mutation row was RED"
  - "The lead's TEST_GROUP=affected run failed lint-trap-tempfile-ownership rule (c) and the fixture-relative-assert baseline (+3 sites, +1 file) after 117 targeted vitest and 4 shell suites were green"
  - "test-all-orphan-log-retention (20 passed / 8 failed) and fanout-suite-scope (rc=0 where rc=4 was wanted) went red only under an exported TEST_GROUP=affected"
  - "The semgrep seat's first run printed 'Ran 79 rules on 0 files' because semgrep skips test/ paths by default"
root_cause: logic_error
resolution_type: test_fix
severity: medium
tags: [guard-design, allowlist-vs-denylist, ratchets, affected-gate, env-leak, semgrep, review-panel, supply-chain]
synced_to: [work, semgrep-sast]
---

# Learning: a guard built from spellings needed an allowlist, and the affected run saw two ratchets my targeted tests could not

Issue #9343 / PR #9496: the release image's two global CLI installs moved into a `cli-tools` Dockerfile stage built uncached on every PR, with guards in `c4-likec4-version-pin.test.ts`, `claude-cli-pin-knows-models.test.ts` and `scripts-shard-runtime-coverage.test.sh`.

## Problem

1. **Spelling guards.** Round 1's guard refused one spelling of a global install in `runner` (`npm install -g`). Round 1 review found 14 spellings that passed; the fix widened the regex; the next round found more (`--location=global`, a continuation-split `-g`, `pnpm add -g`, `ENV NPM_CONFIG_GLOBAL`, `echo "a # b" && npm i -g x`). The same shape recurred on the install-line check (a trailing `--no-ignore-scripts`, a second `--before=` that npm reads last-wins), on the build step (`ssh`, `secret-envs`, `@main` action refs, job-level `continue-on-error`) and on workflow discovery (a continuation-split or `@latest` install in a new workflow). Every self-run mutation row was RED each time; the author's battery only mutated the spellings the author had thought of.
2. **Repo-global ratchets.** After a green targeted set (six vitest files, `tsc`, four shell suites, two mutation batteries, a docker build), the lead's single `TEST_GROUP=affected` run failed two suites that no file-based selection names: `lint-trap-tempfile-ownership` rule (c) (any `mktemp` in a `.test.sh` with no owning `trap`) and `fixture-relative-assert` (a shrink-only baseline; three `mkdir -p`/redirect/`rm -rf` operands rooted at a variable that is not provably absolute).
3. **Env leak.** The documented lead form exports `TEST_GROUP=affected`; two suites that spawn nested `test-all.sh` runs do not clear it and fail only under it.
4. **Void scan.** `semgrep` honours a default ignore list that skips `test/` paths, so a scan of test files reported 0 files and 0 findings.

## Solution

1. **Replace the heuristic, do not widen it** (the review skill's rule: a heuristic that produced a fresh bypass in two consecutive rounds is deleted). Over Dockerfile LOGICAL lines (backslash continuations joined, whole-line `#` comments only, because a mid-line `#` reaches the shell in a Dockerfile):
   - `cli-tools` body must be exactly the two anchored `RUN` lines;
   - `runner` may name a package manager only in its two known lines (`npm ci --omit=dev`, the pinned `npx playwright@... install`), and may `COPY --from` only `builder`;
   - every likec4 install line on every site must be exactly `npm install -g likec4@<x.y.z> --before=<date> --ignore-scripts`;
   - the build step's `with`, step and job keys are allowlists, the action ref must be a full commit SHA, `with.context` must be `apps/web-platform`;
   - install steps are checked per parsed job (and for the monitor), not by a file-wide count;
   - discovery of likec4 resolutions uses "likec4 next to any package-manager verb" over continuation-joined text and walks workflows, composite actions and the nested workflows directory.
2. **Fixture-dir idiom for a new shell test:** a per-process path under the scratch root `test-helpers.sh` already owns and removes (`$INCIDENTS_REPO_ROOT/<name>-$$`), no `mktemp` and no second `EXIT` trap (a second trap REPLACES the helper's composed one, #8659); `assert_fixture_dir "$DIR"` before the `mkdir`/redirects AND again immediately before the `rm -rf`, because the scanner's guard window starts at the nearest function head and a one-line `_helper() {` earlier in the file shortens it.
3. **TEST_GROUP leak:** evidence added to the existing selector-convergence tracker #8621; both suites pass standalone (30/0 and 53/0). Before reading either as a regression, re-run it with the variable unset.
4. **semgrep:** `Ran N rules on 0 files` is void; for test files pass `--no-git-ignore` with an empty `.semgrepignore` and confirm M equals the file count.
5. **Install-script decision (CTO ruling):** likec4 runs `--ignore-scripts` at every site so the binary the tests exercise is the binary the image ships (the only install script that runs on linux in its tree is esbuild's postinstall, which a platform optional dependency makes unnecessary; `fsevents` has one but is darwin-only); claude-code keeps lifecycle scripts because its postinstall places the native binary (scripts-off, the CLI reports "claude native binary not installed"). Recorded dissent in ADR-191.

## Key Insight

- **A guard over an open set of spellings is a denylist, and review will find a new member every round.** When the property is "nothing but X can reach Y", state X as an allowlist over the parser's own units (logical lines, parsed YAML keys) and anchor each allowed form; a self-run battery cannot show the denylist is complete, because it only mutates spellings its author already knew.
- **The targeted set a lead picks is a function of the files it already knows about; the affected run is the only instrument that sees repo-global ratchets.** A new `.test.sh` arms at least two shrink-only ratchets (trap ownership, fixture-relative operands). Run `scripts/lint-trap-tempfile-ownership.py` and `plugins/soleur/test/fixture-relative-assert.test.sh` by name before pushing any new shell test, and do not regenerate the baseline: fix the file.
- **A comment or ADR sentence the author writes from the plan's summary is a claim to falsify against the artifact it names.** Three such sentences in this PR were wrong (the source plan and cause of a "5 of 15" measurement, "the only install script", "layer keys unchanged") and two seats found them; each fell to one command.

## Session Errors

1. **Plan phase: an over-long `grep` output (forwarded).** Recovery: bounded the next command. **Prevention:** pipe unbounded searches through `head` (`hr-never-run-commands-with-unbounded-output`, already a rule).
2. **Plan phase: `gh issue create` refused by the filing gate (forwarded).** Recovery: added `--label meta/machinery`. **Prevention:** none beyond the existing gate text.
3. **A lock-fixture typing slip passed vitest and failed `tsc`.** Recovery: typed the fixture. **Prevention:** run `tsc --noEmit` alongside any new typed test helper (vitest does not type-check).
4. **Two patch scripts aborted on a stale anchor.** Recovery: re-read the exact text and re-ran (writes are atomic at the end, so nothing half-applied). **Prevention:** assert `count == 1` per replacement, as the scripts did.
5. **A mutation-battery row anchored on the old `print_results 21` went stale after the floor changed.** Recovery: the row reported "did not land" and was re-proven by hand. **Prevention:** a battery row whose anchor text a later edit changes must be re-derived in the same edit.
6. **The continuation-join regex produced a double space and broke the exact-form check.** Recovery: collapse whitespace around the join; the self-test caught it. **Prevention:** none beyond the test.
7. **My own prose cited the wrong measurement source and cause (ADR-050 addendum; "only install script"; "layer keys unchanged"); two seats caught it.** Recovery: rewrote from the archived #9300 plan and a resolved 177-package tree. **Prevention:** before citing a measurement, open the file that holds it and quote its numbers; before "the only X", run the enumeration.
8. **Round 1's fixes introduced seven more P3s found only by the verification pass.** Recovery: patched, mutation-proved, re-verified. **Prevention:** already documented (a fix commit is the least-audited surface); the targeted round plus one verifier is the mechanism and it worked.
9. **The lead's affected run caught two ratchets the targeted tests could not (trap ownership, fixture-relative baseline).** Recovery: per-process dir under the helper's scratch root plus `assert_fixture_dir` twice. **Prevention:** run the two ratchet suites by name for any new `.test.sh`; see Solution 2.
10. **`TEST_GROUP=affected` leaked into two nested-runner suites.** Recovery: re-ran them standalone (pass), commented on #8621. **Prevention:** `env -u TEST_GROUP` at the top of any suite that spawns `test-all.sh` (tracked on #8621).
11. **The semgrep seat's first scan covered 0 files.** Recovery: the seat re-ran with `--no-git-ignore` and an empty `.semgrepignore`. **Prevention:** the `semgrep-sast` agent now says `Ran N rules on 0 files` is void for test paths.
12. **Two stop-hook blocks: my closing text promised an action.** Recovery: ended waits with an explicit BLOCKED tag. **Prevention:** end a waiting turn with a stop tag, never a promise (already a pipeline pitfall).
13. **A session break mid-command and a stale monitor row from the earlier session kept appearing in hook notices.** Recovery: verified clean state (tree clean, no leftover run) before continuing. **Prevention:** after a session break, check `git status`, the branch's remote head and any leftover `test-all` process before editing.

## Cross-references

- `2026-10-01-an-ambient-ci-variable-is-inherited-by-every-nested-runner-and-a-gate-on-it-needs-a-scrub.md` (the same inherited-env class; here the variable is the documented lead form).
- `2026-10-01-a-bootstrap-stage-trusted-its-own-marker-and-a-guard-of-spelled-patterns-had-twenty-escapes.md` (spelled-pattern guards, the same denylist shape).
- `2026-09-14-i-tested-both-endpoints-and-left-the-wire-between-them-unpinned.md` (a file-selected suite set cannot see a repo-global ratchet).
- Issues: #9343, #9496, #8621; ADR-050 and ADR-191 addenda (2026-10-04).

## Tags

category: workflow-issues
module: System
