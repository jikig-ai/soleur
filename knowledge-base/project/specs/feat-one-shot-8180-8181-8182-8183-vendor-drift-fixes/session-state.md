# Session State

## Plan Phase
- Plan file: /home/jean/git-repositories/jikig-ai/soleur/.worktrees/feat-one-shot-8180-8181-8182-8183-vendor-drift-fixes/knowledge-base/project/plans/2026-09-14-fix-vendor-drift-machinery-plan.md
- Status: complete

### Errors
- None blocking. Minor recoverable issues: a `gh pr view`/`gh label list` session emitted an unsupported-field warning earlier in the thread (corrected by using supported fields); one backgrounded selector loop needed `get_output` to finish; the deepen-plan skill's sub-agent fan-out could not run because no Task tool exists in this session — all its gates and checks were executed inline instead (recorded in the plan's gate-evaluation record).

### Decisions
- **Merge base is main's single-bundle code, not the still-open PR #8120** (`gh pr view 8120` → OPEN/WIP): #8180/#8181/#8183 apply verbatim; #8182's named enumeration calls don't exist on main — its dedup is `total_count`-based and already complete — so #8182 is reframed as pinning that invariant plus a `fetchAllPages` helper (precedent: `get-workstream-issue-options.ts:31-44`) for the post-#8120 shape, with per-FR port notes.
- **#8180 fix ports the deleted workflow's re-vendor logic** (recovered from `git show 804114883:...scheduled-content-vendor-drift.yml`): `git merge-file --diff3` with `-L` labels per drifted file, assert-exactly-1 NOTICE block rewrite, `pinned-commit`/`last-verified` bumps — all inside the existing `step.run("safe-commit-pr")` per the same-step write+commit replay-safety learning; conflicts route to `mergeMode: "none"` + `needs-human-review` (runbook §2 contract).
- **Deepen-pass catches folded in:** the `safeCommitAndPr` return is discarded on main — the plan now requires capturing `no-changes` and reporting it via `reportSilentFallback`; the `needs-human-review` label is absent from the repo (one-time `gh label create` added as AC-9); #8180's "runbook §2 Manual Re-vendor" citation is inaccurate (actual §2 is Conflict-Marker Resolution).
- **#8183 decision: option (a)** — enrich issue bodies with the already-fetched `full_name`/`archived`/`default_branch` probe, rendering `unreachable` as probe-failed rather than affirmative values.

### Components Invoked
- `plan` skill (prose, run to completion: premise validation, research, MORE-level structure, gates)
- `deepen-plan` skill (prose, run to completion: precedent-diff, verify-the-negative, all halts 4.5–4.11 evaluated; `scripts/lint-guard-contract.py` executed → PASS with 3 guards; live citation audit via `gh`/`git` for #4483, #5111, #7710, #3521, #8120, #8180–8183, commit `804114883`, ADR-203, and the label set)

## Post-#8120 Rebase Port (2026-09-15)
- PR #8120 merged to main mid-flight (`58d98f659`, 2026-09-14T22:14:43Z). The pre-review merge-tree check caught real conflicts in all 5 touched files; rebased and ported each FR onto the multi-bundle architecture rather than resolving textually.
- Port mapping: single-bundle constants → `bundle.skillPrefix` / `bundle.noticeFileRel` / `bundle.upstreamName` / `bundle.pinnedCommit`; step `safe-commit-pr` → `safe-commit-pr-${bundle.slug}` (write loop inside it, per the same-step replay-safety learning); `listOpenPrHeads` + the `open-drift-issue-<slug>` `items` scan are the actual #8182 enumeration sites — both now page via `fetchAllPages`; DetectResult carries `driftedFiles`/`newPinnedCommit`/`repoMetaSummary` on every return via a `detection` spread.
- vendor-pin-integrity.sh: merged main's `checked` counter + vacuous-refusal with the contents-endpoint path/commit/blob binding (fail closed on non-40-hex pinned-commit).
- Tests renumbered to avoid collisions with main's TS13-TS15 additions; behavioral suite drives the multi-bundle handler (per-bundle step IDs, `res.bundles[]`, paginated pullPages/searchIssuePages fixtures, two-bundle sibling-masking test).
- Results post-port: vitest 147/147, vendor-pin-integrity 57/57, vendor-drift-workflow 55/55, vendor-drift-classify 23/23, gdpr-gate-self-test 20/20, tsc clean, eslint clean (1 pre-existing DetectResult warning), live --verify-upstream green on BOTH upstreams (goSprinto 8 bindings @7b58d68461cb, General-Legal 12 bindings @0f7c7bfabf1b), merge-tree rc=0.
- Rebased commit: `5aaff54cb` (replaces `329391274`).

## Phase 3 Review Panel + Fix Round (2026-09-15)

- 11-seat panel ran (8 always-on + test-design-reviewer + structural-enumeration + user-impact-reviewer). Deterministic gates first: semgrep 0 findings (79 rules, TS targets), shellcheck clean.
- Convergent findings resolved in-branch:
  - positional-zip misalignment → `rewriteNoticeRecord` binds expected upstream-path + old upstream/local SHAs; crossed-view tests added;
  - partial measurement → write step refuses `filesError>0` or `filesExamined!==registryCount` before advancing `pinned-commit`;
  - `liftedPath` containment → whole-set `references/` validation before any disk touch + symlink refusal + post-commit `res.paths` verification (`revendor-paths-missing`);
  - dirty-worktree replay → `git restore --source=origin/main` at step top (HEAD is the ci tip by then);
  - stale age read → `read-attestation-age` + attest arm read `origin/main:<NOTICE>`; dedup-before-write; `bumpNoticeField` replaces inline replace;
  - rollback routing → compare API `behind`/`diverged` → `rollbackSuspected` forces the issue route with `vendor/upstream-rollback` + `needs-human-review` and a supply-chain warning line (the classifier's exit-15 arm needs upstream objects the shallow clone lacks);
  - classifier truncation → bodies over `MAX_DIFF_LINES_PER_FILE` (and undecodable bodies) emit an explicit `[CRITICAL]` marker so unscreened content can never reach mergeMode direct;
  - issue-search `incomplete_results` → throw; `fetchAllPages` 20-page cap is now loud (throws on full final page); `listOpenPrHeads` filters to same-repo heads (fork-PR suppression closed);
  - `vendor-pin-integrity.sh` → `upstream_path` charset-validated before URL interpolation; `ref` travels via `-f` field arg;
  - stale docs → runbook §2 rewritten (2a clean / 2b conflicted / 2c manual), policy §4.1/§6 corrected; §7 pointer fixed.
- Test hardening: discriminating `last-verified`/`local-blob-sha` assertions, `|||||||` diff3 marker check, red-heartbeat assertion on no-changes, fork-PR + sibling-issue non-suppression, partial-measurement/null-pin/path-escape/crossed-views/rollback/blob-404 failure arms; TS16e made a real mutation discriminator (stub row for `not-a-sha`); TS16g unsafe-path refusal; structural suite gained TS17 + write-step hardening anchors.
- Deferred: `verify-upstream-blobs` is not a required ruleset context — filed #8203 (needs the always-run aggregator shape + earned-vs-fabricated synthetic design; CODEOWNERS-gated file + Terraform apply).
- Results post-fix: vitest 157/157 (140 source-shape + 17 behavioral), vendor-pin-integrity 59/59, vendor-drift-workflow 66/66, tsc clean, eslint clean, semgrep 0 findings (79 rules, 3 TS targets).
