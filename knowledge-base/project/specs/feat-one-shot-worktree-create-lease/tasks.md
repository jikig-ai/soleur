# Tasks — fix(git-worktree): `create` never acquires a lease

Plan: `knowledge-base/project/plans/2026-08-09-fix-worktree-create-acquires-lease-plan.md`

Three files. Phase order is load-bearing (RED before GREEN).

## 1. Setup

- [ ] 1.1 Confirm CWD is the feature worktree and branch is `feat-one-shot-worktree-create-lease`.
- [ ] 1.2 Read `create_for_feature`'s lease block in `plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh` (anchor: `acquire_lease "$branch_name"`) — it is the form to copy verbatim.
- [ ] 1.3 Read `create_worktree`'s tail (anchor: `install_deps "$worktree_path"` followed by the success echo) — that is the insertion point.
- [ ] 1.4 Read `plugins/soleur/skills/git-worktree/test/lease-protects-active.test.sh` and its sibling `create-from-origin-main.test.sh` (the upstream-bearing fixture shape scenario 3 needs).

## 2. RED — failing test first

- [ ] 2.1 Append **Scenario 3** to `plugins/soleur/skills/git-worktree/test/lease-protects-active.test.sh`: stand up an upstream + local bare repo with an `origin` remote, run `--yes create feat-probe` with `SOLEUR_SESSION_STATE_ROOT` + `SOLEUR_SKILL_NAME` + `SOLEUR_EXPECTED_DURATION_MIN` set, and assert (a) exit 0, (b) `<lease-root>/leases/feat-probe.lease` exists, (c) it contains a `pid=` line.
- [ ] 2.2 Raise `MIN_ASSERTIONS` from `3` to `6` in the same file.
- [ ] 2.3 Run the suite. Confirm it fails at assertion (b), the lease-file check — **not** at assertion (a). If it fails at (a), the fixture is wrong; fix the fixture before Phase 3. (Deepen-plan already ran this exact fixture against unfixed code and got `pass: (a)` / `FAIL: (b)` — reproduce that, do not redesign it.)
- [ ] 2.3b Assert the lease **file**, never the leases **directory** — the directory is created at source time and is empty on the unfixed path, so `[[ -d … ]]` false-passes against the bug.
- [ ] 2.4 Capture the failing output line for AC5 / the PR body.

## 3. GREEN — the fix

- [ ] 3.0 **Disambiguate the anchor first.** `install_deps "$worktree_path"` appears TWICE in the file (once per creating function). The `create_worktree` site is the one immediately followed by the `✓ Worktree created successfully!` echo; the `create_for_feature` site is the one immediately followed by `# Sweep stale leases lazily`. Do not grep for `install_deps` alone, and do not use a line number.
- [ ] 3.1 Insert into `create_worktree()` in `plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh`, after `install_deps "$worktree_path"` and before the success echo: `sweep_orphan_leases`, then `acquire_lease "$branch_name" "${SOLEUR_SKILL_NAME:-unknown}" "${SOLEUR_EXPECTED_DURATION_MIN:-240}" || headless_or_stderr warn "could not acquire lease for $branch_name"`, then `_register_lease_release_trap "$branch_name"` — with a short comment naming why (`create` is the entry point one-shot Step 0b and work Phase 1 call).
- [ ] 3.2 Do **not** vary the form, the warn text, or the ordering from `create_for_feature`'s block.
- [ ] 3.3 Re-run `lease-protects-active.test.sh` — expect `PASS: 6`, exit 0.

## 4. Comment correction

- [ ] 4.1 In `.claude/hooks/lib/session-state.sh`, `_register_lease_release_trap`: amend the comment so it no longer asserts un-conditionally that `create_worktree` acquired the lease before this PR, and so the "Measured: the leases directory is EMPTY" sentence names **both** causes (EXIT released what was acquired; `create` never acquired at all).
- [ ] 4.2 Comment-only — no behavioural change to the trap line.

## 5. Testing & verification

- [ ] 5.1 `bash plugins/soleur/skills/git-worktree/test/lease-protects-active.test.sh` → `PASS: 6`, exit 0.
- [ ] 5.2 `bash plugins/soleur/skills/git-worktree/test/create-from-origin-main.test.sh` → exit 0 (no regression from the added lease write).
- [ ] 5.3 **Live probe (once):** from a scratch worktree at `origin/main` (`git worktree add .worktrees/pm-probe origin/main --detach`) — never from the bare repo root — run `--yes create <throwaway>`, assert `<throwaway>.lease` exists under `"$(cd -P "$(git rev-parse --git-common-dir)" && pwd -P)/soleur-session-state/leases"`, then remove both worktrees and delete the local + remote throwaway branch. Capture the `ls` for the PR body.
- [ ] 5.4 Trap-fix regression guard, **absence-anchored**: assert the `trap "_lease_release_safe …"` line contains no `EXIT`. Do **not** use `grep -c 'INT TERM HUP'` — the broken form matches it too.
- [ ] 5.5 `bash scripts/test-all.sh` → exit 0.
- [ ] 5.6 `git diff --name-only origin/main...HEAD` → exactly three files, no `*.tf`, nothing under any `infra/**`, nothing registry/zot.

## 6. Ship

- [ ] 6.1 File the follow-up issue: "lease durability is bounded by the oldest checkout still running cleanup-merged" — include the measured vanishing-lease observation, the window-gating rebuttal, the stale-pre-fix-checkout hypothesis, and the `create_worktree` early-return-arm gap (which `create_for_feature` shares). Do **not** fix any of it here.
- [ ] 6.2 PR body: paste the AC5 RED evidence, the AC7 live-probe `ls`, and the note that scenario 3 transitively pins the predecessor trap fix.
- [ ] 6.3 PR body: include the honest net-issue-flow override one-liner (`<!-- gate-override: net-issue-flow -->`). Do not attach a false `Closes #N`.
