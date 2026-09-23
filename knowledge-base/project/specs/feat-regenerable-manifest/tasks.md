# Tasks — regenerate-on-conflict for self-hosted repos

Plan: `knowledge-base/project/plans/2026-09-23-feat-regenerable-conflict-resolution-for-self-hosted-repos-plan.md`
Branch: `feat-regenerable-manifest` · Ref #8542

## 1. Move the renderer into the plugin

- [x] 1.1 `git mv scripts/regenerate-c4-model.sh plugins/soleur/scripts/render-c4-model.sh` (preserve history).
- [x] 1.2 Add `--root <dir>`, defaulting to `git rev-parse --show-toplevel`; derive `DIAGRAMS_DIR` from it.
- [x] 1.3 Resolve `c4-canonical-cli.mjs` from the script's own directory, not through the repo root.
- [x] 1.4 Relax the source guard from "all three of spec/model/views" to "at least one `.c4` present"
      (a synced customer repo has no `model.c4`).
- [x] 1.5 Add `--ignore-scripts` to the `npx likec4` invocation, matching the TS producer.
- [x] 1.6 Keep the diagnostic-text gate and the element-count gate intact.
- [x] 1.7 Leave a forwarding wrapper at `scripts/regenerate-c4-model.sh` for this repo's callers.
- [x] 1.8 Update `plugins/soleur/test/c4-model-freshness.test.sh` for the new path.

## 2. Resolver

- [x] 2.1 Absolutize `PLUGIN_DIR` from `${BASH_SOURCE[0]}` **above** the `cd "$REPO_ROOT"`.
- [x] 2.2 Amend the header comment that forbids `BASH_SOURCE` — it governs the *repo* root; name the
      distinction so the next reader does not read it as still-binding.
- [x] 2.3 Replace the hardcoded argv with `bash <PLUGIN_DIR>/render-c4-model.sh --root <REPO_ROOT>`,
      marked `# ARGV-SOURCE: plugin`. Bare `${CLAUDE_PLUGIN_ROOT}` (no `:-`, per A12) only when the
      sibling is absent; `plugin.json` name check on whichever root is used, commented as
      defence-in-depth rather than as the control.
- [x] 2.4 Refuse (`na`) when any `.c4` in the diagrams directory is untracked, naming the file.
- [x] 2.5 After the regeneration loop, require `git diff --name-only` to be empty or `bail`.
- [x] 2.6 Capture the arm's combined output; put its last line in the `bail` message.
- [x] 2.7 Wrap the arm in `timeout` with a stated budget; print one progress line to stderr first.
- [x] 2.8 Add `arm=` and `root=` to the `SOLEUR_REGEN_ON_CONFLICT` success line on stdout.
- [x] 2.9 Every refusal names one imperative next action (the manual command to run).

## 3. Call sites

- [x] 3.1 `.claude/hooks/pre-merge-rebase.sh`: resolve the resolver from `${CLAUDE_PLUGIN_ROOT}` with
      the identity check, repo copy as fallback.
- [x] 3.2 `.openhands/hooks/pre-merge-rebase.sh`: same edit; keep the two byte-identical on that block.
- [x] 3.3 `merge-pr/SKILL.md`: fix the manual recovery snippet (its middle step is the repo-local
      script a self-hosted user does not have) and the poll-loop invocation.
- [x] 3.4 `drain-prs/SKILL.md`, `ship/SKILL.md`, `ship/references/settle-then-admin-merge.md`:
      plugin-anchor the documented invocations.

## 4. Tests

- [x] 4.1 Fixture: self-hosted repo (no repo-local renderer) → AC1, AC2.
- [x] 4.2 Fixture: untracked `.c4` in the diagrams dir → AC3.
- [x] 4.3 Fixture: decoy `plugins/soleur/scripts/render-c4-model.sh` in the merged repo, resolver
      loaded from the plugin root → AC4.
- [x] 4.4 Fixture: diagrams dir with `spec.c4` + `views.c4` and no `model.c4` → AC5.
- [x] 4.5 Fixture: `.c4` syntax error → AC6, asserting the diagnostic text reaches the bail message.
- [x] 4.6 Add a `tree_fp` row for a failure occurring after the `rm -f` of the conflicted path → AC7.
- [x] 4.7 Re-anchor the ratchet on a named marker comment; extend it to the `# ARGV-SOURCE:` marker.
- [x] 4.8 Raise `_min_cases` to the new count in the same edit; keep the verdict/ledger
      reconciliations green.
- [x] 4.9 Run the 6-row mutation matrix from the plan's Guard Contract; record results.
      Results, committed SUT, pristine-copy restore verified: m1 (plugin dir resolved after the
      cd) RED, m1b (relative to cwd) RED, m2 RED, m3a/m3b (stray tracked/new) RED, m4 RED, m5 RED,
      m6 RED, harness (a) floor RED. Extra rows: identity check dropped RED, arm output discarded
      RED, stray unwind dropped RED, progress line dropped RED. x3 (CLAUDE_PLUGIN_ROOT preferred
      over the sibling) SURVIVED the first battery: a fixture gap, closed by the sibling-order
      row, then RED. The hook lookup's three mutations (identity, drift, repo-only) are RED too.
- [x] 4.10 `git grep` assertion that no documented invocation remains repo-relative → AC9.

## 5. ADRs

- [x] 5.1 Amend ADR-235: the command moved into the plugin, the resolvable set is still one member,
      the `.tsv` manifest stays rejected and why the self-hosted gap did not reopen it.
- [x] 5.2 Add an ADR-179 amendment item: in-payload sibling resolved from an absolutized `BASH_SOURCE`,
      naming `sync-pr-behind.sh` as the existing instance, and recording that the manifest name check
      is defence-in-depth (A11), not the control.

## 6. Verification

- [ ] 6.1 `bash plugins/soleur/scripts/resolve-regenerable-conflicts.test.sh`
- [ ] 6.2 `bash plugins/soleur/test/c4-model-freshness.test.sh`
- [ ] 6.3 `bash plugins/soleur/test/c4-count-parity.test.sh`
- [ ] 6.4 `bunx vitest run test/c4-likec4-version-pin.test.ts` (from `apps/web-platform`)
- [ ] 6.5 `bash tests/commands/test-sync-producer-reachability.sh`
- [ ] 6.6 `shellcheck -S warning` on every edited shell file.
