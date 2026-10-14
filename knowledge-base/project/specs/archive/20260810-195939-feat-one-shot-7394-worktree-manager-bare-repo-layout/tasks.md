---
date: 2026-08-10
issue: "#7394"
pr: 7407
branch: feat-one-shot-7394-worktree-manager-bare-repo-layout
lane: cross-domain
plan: ../../plans/2026-08-10-fix-worktree-manager-bare-in-dotgit-config-poison-plan.md
---

# Tasks — fix(git-worktree): `ensure_bare_config` is dead code on the bare-repo-in-`.git` layout

Derived from the finalized (post-plan-review) plan. `[R#]` tags map to that plan's
`## Plan Review Revisions` table. Read the plan for rationale — this file is the checklist.

> **Two constraints that override normal commit hygiene. Read before starting.**
>
> 1. **[R2] Phase 2 and Phase 3 MUST be a single commit.** A Phase-2-only commit makes the
>    *unreversed* surgery reachable and would construct the outage state on the operator's own repo
>    at the next session-start `cleanup-merged`. Never independently revertable.
> 2. **[R1] Task 3.0 must land before any other Phase 3 write.** Until `atomic_git_config` handles
>    `--unset-all`, the pair-breaker wedges every already-healthy repo.

---

## Phase 0 — Preconditions (read-only)

- [x] 0.1 Re-read `ensure_bare_config` end to end; confirm these anchors still exist:
      the `ROUND-6 root cause` comment (~`:606`), the `*/.git && -d` guard (~`:615-624`), the
      `_bare_status` authoritative check, the three-step write order, and the fourth write block
      at ~`:684-694`.
- [x] 0.2 Confirm `plugins/soleur/test/test-helpers.sh` exposes `assert_eq`, `assert_contains`,
      `assert_file_exists`, `assert_file_not_exists`, `print_results`.
- [x] 0.3 Confirm `scripts/test-all.sh` still globs `plugins/soleur/test/*.test.sh` (no explicit
      registration needed for the new suite).
- [x] 0.4 Record `git --version` in the PR body. Every measurement in the plan is scoped to it.
- [x] 0.5 Capture the pre-change `bash scripts/test-all.sh` **`N/M` summary line** as the baseline
      for task 8.4. Read the summary line, never a piped exit code.

## Phase 1 — RED: the regression suite (write FIRST, `cq-write-failing-tests-before`)

- [x] 1.1 Create `plugins/soleur/test/worktree-manager-bare-in-dotgit-layout.test.sh`. Follow
      `worktree-manager-atomic-config.test.sh` conventions verbatim: `set -euo pipefail`, unset every
      `GIT_*` env var, source `test-helpers.sh`, source `worktree-manager.sh` (safe — the
      `BASH_SOURCE[0] == $0` guard at `:2649` means `main()` does not run on source).
- [x] 1.2 All fixtures synthesized with `git init` / `git clone --bare`
      (`cq-test-fixtures-synthesized-only`). **Every case that needs different detection state must
      `cd` into its fixture and source the script in a FRESH SUBSHELL** — `IS_BARE`,
      `IS_IN_WORKTREE`, `GIT_ROOT` are computed at source time and re-sourcing in the same shell
      silently reuses the first computation.
- [x] 1.3 Case 1 — row-3 poisoned worktree: `require_working_tree` succeeds from inside it.
      **[R8]** Attribute to **Phase 5**, not to `ensure_bare_config`.
- [x] 1.4 Case 2 — bare-in-`.git`, clean: `ensure_bare_config` performs its normalization instead of
      returning early (shared `core.bare` retained, extension absent, stale `core.worktree` removed).
- [x] 1.5 Case 3 — bare-in-`.git` + row-3 poison: pair broken; post-state matches row 1;
      `--is-bare-repository` from the worktree is `false`.
- [x] 1.6 Case 4 — genuine bare (`repo.git`, gitdir IS root) + linked worktree: same invariant.
- [x] 1.7 Case 5 — **NEGATIVE**, normal non-bare clone: zero config writes; `.git/config`
      byte-identical (`cmp` against a pre-run copy). Pins `#6184`.
- [x] 1.8 Case 6 — **NEGATIVE**, masked shared config (`ln -s /dev/null .git/config`): still
      short-circuits; emits `SOLEUR_GIT_CONFIG_MASK_SKIP … branch=non-bare-skip`; attempts no write.
      Pins `#5934` round 6.
- [x] 1.9 Case 7 — **INVARIANT**: no reachable state leaves `extensions.worktreeConfig` enabled while
      `core.bare` is present in the shared config. Assert across every intermediate state.
- [x] 1.10 Case 8 — already-poisoned worktree, `ensure_bare_config` NOT called: the self-heal alone
      makes `require_working_tree` succeed, **and the shared config is byte-unchanged**.
- [x] 1.11 Case 9 — after `create`: the new worktree's `config.worktree` carries `core.bare = false`.
      **[R-fact4]** Pre-assert the baseline in the same case: after a raw `git worktree add`,
      `[[ ! -e <root>/.git/worktrees/<name>/config.worktree ]]`. **Never assert a 0-byte file.**
- [x] 1.12 Case 10 — after `ensure_bare_config` on a clean fixture, `--is-bare-repository` **from the
      ROOT** is still `true`. Pins fact 7.
- [x] 1.13 **[R1]** Case 11 — already-clean fixture (extension absent): `ensure_bare_config` returns
      **0**, emits `branch=clean`, emits no `worktree wedge:`. Fails on today's `atomic_git_config`.
- [x] 1.14 **[R5]** Case 12 — self-heal target unwritable (`chmod a-w` the `worktrees/<name>/` dir):
      emits `SOLEUR_GIT_BARE_SELFHEAL … branch=failed`; CLI prints the absolute unwritable path and a
      concrete next step; exits non-zero without proceeding into git commands that will fatal.
- [x] 1.15 **[R3]** Case 13 — after self-heal, `WORKTREE_DIR` equals `<root>/.worktrees` and a
      subsequent `create` lands there. Asserting `require_working_tree` returns 0 is NOT sufficient.
- [x] 1.16 **[R-arch2]** Case 14 — **NEGATIVE**, normal `.git`-directory clone whose shared config is
      corrupted to `core.bare = true`. Assert the *intended* behaviour explicitly (heal or refuse).
- [x] 1.17 Run the suite. Confirm cases **1, 3, 7, 8, 9, 11, 12, 13** FAIL before writing any
      implementation. (2, 4, 5, 6, 10, 14 may pass or be vacuous today.)

## Phase 2 + 3 — GREEN: guard + polarity (⚠️ ONE COMMIT, [R2])

- [x] 3.0 **[R1] FIRST.** Extend `atomic_git_config`'s FR2 read-first branch (`~:448`) from
      `[[ "${1:-}" == "--unset" ]]` to also accept `--unset-all`. The existing skip condition
      (`--get` rc 1 → absent → `return 0`) is correct for both; the rc-2 multi-valued fall-through
      documented at `:449-452` is also correct for `--unset-all`. Without this, every step below
      wedges an already-healthy repo (`--unset-all` on an absent key exits 5).
- [x] 2.1 Replace the unconditional `.git`-directory skip with a two-condition skip that still
      **defaults to SKIP**: read `core.bare` from the shared config **file**
      (`git config --file "$git_dir/config" --get --type=bool core.bare`), not from `git rev-parse`.
- [x] 2.2 Anything other than a literal `true` — absent, `false`, non-zero rc, empty (**the masked
      case**, measured rc=1/empty) — keeps today's behaviour exactly: emit the benign
      `SOLEUR_GIT_CONFIG_MASK_SKIP … branch=non-bare-skip` when the config family is masked, and
      `return 0`.
- [x] 2.3 Only an unambiguous `true` falls through to the existing authoritative
      `git rev-parse --is-bare-repository` check.
- [x] 2.4 Update the guard's comment block: name the third surface explicitly, and record *why* the
      config read is mask-safe (it degrades to "absent", which routes to SKIP). **Do NOT gate on
      `core.repositoryformatversion`** (fact 2).
- [x] 3.1 **Delete** the `atomic_git_config "$shared_config" extensions.worktreeConfig true` and the
      `core.repositoryformatversion 1` writes.
- [x] 3.2 **Add** the defensive heal: if `extensions.worktreeConfig` is present in the shared config,
      `--unset-all` it via `atomic_git_config` (now safe after 3.0).
- [x] 3.3 **Keep** `core.bare = true` in the shared config and **remove** the `--unset core.bare`
      step. Retain the `--unset core.worktree` step unchanged.
- [x] 3.4 **Keep** the existing `.git/config.worktree` **file** on disk untouched (inert with the
      extension absent; deleting it is a destructive write with no benefit).
- [x] 3.5 Emit `SOLEUR_GIT_BARE_POISON … branch=healed|clean` with the discriminating fields
      (`git_dir`, `extension`, `shared_bare`, `wt_override`, `git_version`). On any write failure
      `return 1` and emit `worktree wedge: could not break the bare-config pair in <git_dir>`.
- [x] 3.6 Correct the false comments — **three sites**:
      (a) the **file header** `:7-14` — all three claims stale; the sentence *"linked worktrees
      inherit core.bare=false by default"* is **inverted** and must state the measured behaviour;
      (b) the function header's *"Fixes TWO broken states…"* (`:548`);
      (c) both call-site comments (`:1380`, `:1489`).
- [x] 3.7 **[R-kieran]** Delete the fourth write block (`~:684-694`, `core.bare true` into the bare
      root's own `config.worktree`) — permanently inert under the reversed polarity — and say so in
      the header.
- [x] 3.8 **[R-arch5]** Update `atomic_git_config`'s docstring (`:413`): it gains two further
      call-site classes in Phases 4 and 5.
- [x] 3.9 Run cases 2, 3, 5, 6, 7, 10, 11, 14 — expect GREEN.

## Phase 4 — GREEN: per-worktree seed

- [x] 4.1 After a successful `git worktree add` in `create_worktree` **and** `create_for_feature`,
      write `core.bare = false` into the new worktree's `config.worktree` via `atomic_git_config`.
- [x] 4.2 Resolve the path from `git -C "$worktree_path" rev-parse --absolute-git-dir` —
      **never** by string-joining a guessed worktree name.
- [x] 4.3 This is a **create**, not a repair: per fact 4 the file does not exist. Do not write a heal
      predicated on the file existing-and-being-empty; that condition is never true.
- [x] 4.4 Run case 9 — expect GREEN.

## Phase 5 — GREEN: detection-time self-heal

- [x] 5.1 **[R3] Placement.** Insert the recovery arm **before** `:159-160` so
      `ensure_git_root_absolute` + `WORKTREE_DIR="$GIT_ROOT/.worktrees"` run once, afterwards, on
      healed state. (If placed after, `WORKTREE_DIR` and `ensure_git_root_absolute` MUST join the
      explicit recompute list — the pre-heal `GIT_ROOT` resolves to `<common>/worktrees/<name>`.)
- [x] 5.2 Fire **only** on the three-way conjunction: `.git` in CWD/nearest ancestor is a **FILE**
      containing `gitdir: <path>`; that path resolves under `<git-common-dir>/worktrees/`; and
      `git rev-parse --is-bare-repository` reports `true`.
- [x] 5.3 Recovery: write `core.bare = false` into **this worktree's own** `config.worktree` via
      `atomic_git_config`. **[R4]** Resolve via `git rev-parse --absolute-git-dir`, never a guessed
      name. **The shared config must not be touched here** — blast radius stays at 1.
- [x] 5.4 Re-derive `IS_IN_WORKTREE`, `IS_BARE`, `GIT_ROOT` (and `WORKTREE_DIR` if 5.1's
      before-placement was not used).
- [x] 5.5 Emit `SOLEUR_GIT_BARE_SELFHEAL … worktree=<name> branch=ok|failed` with `git_version=`.
      **[R6]** One marker, outcome in `branch=`. Pin the fields actually cheap at this call site —
      it runs before most state exists, in the branch where detection is already failing.
- [x] 5.6 **[R5]** On failure the CLI MUST print, in plain language: the **absolute path** it could
      not write, likely causes (permissions / ownership / disk full / read-only mount), and one
      concrete next step. Do **not** fall back to the bare `Run from an existing worktree` text —
      that is the message the plan's *Third defect* section criticises.
- [x] 5.7 Run cases 1, 8, 12, 13 — expect GREEN.

## Phase 6 — Telemetry registration

- [x] 6.1 Extend `MARKER_RE` in `apps/web-platform/server/git-lock-marker-telemetry.ts` with
      **two** markers: `SOLEUR_GIT_BARE_POISON`, `SOLEUR_GIT_BARE_SELFHEAL`.
- [x] 6.2 Classify by `branch=`: `branch=failed` → **wedge** (Sentry); informational → **benign**
      (pino/Better Stack). Mirrors the existing `SOLEUR_GIT_CONFIG_TARGET_MASKED` (wedge) vs
      `SOLEUR_GIT_CONFIG_MASK_SKIP` (benign) split.
- [x] 6.3 Update the file's header marker-inventory comment.
- [x] 6.4 Extend `apps/web-platform/test/git-lock-marker-telemetry.test.ts`: one case per marker
      plus a `branch=failed` case asserting wedge classification.
- [x] 6.5 `git grep -c 'SOLEUR_GIT_BARE_SELFHEAL_FAILED' -- ':!knowledge-base/project/plans' ':!knowledge-base/project/specs'`
      returns **0**. **[D1]** The exclusions are required — this file and the plan both name the
      retired marker in prose, so a bare repo-wide grep fails on a correct implementation.
- [x] 6.6 `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` is clean.

## Phase 7 — Architecture records

- [x] 7.1 Amend `knowledge-base/engineering/architecture/decisions/ADR-099-git-surface-topology.md`:
      row 3's `.git` column names the **root's `.git` directory** (bare); add an explicit note that
      `[[ -d <root>/.git ]]` **cannot discriminate row 2 from row 3's root**; extend the existing
      guard-consequence sentence to record the no-op on row 3 as the defect (#7394).
- [x] 7.2 Author `ADR-173` (ordinal **provisional** — ADR-172 is highest as of 2026-08-10) via
      `/soleur:architecture`: the polarity decision, the git-version measurement scope, and
      `## Alternatives Considered` carrying the extension-on state (row 5) with the
      transition-through-row-3 rationale.
- [x] 7.3 **[R12]** Re-evaluation trigger widened to *either* a git release restoring shared-config
      writes on `worktree add`, **or** a re-audit finding a new setter of `extensions.worktreeConfig`
      anywhere in the toolchain (including herdr / the Concierge runtime).
- [x] 7.4 **[R13]** Cite `apps/web-platform/server/worktree-config-seed.ts` **by path**.
- [x] 7.5 **[R14]** Record the cross-surface convergence as a positive consequence (the reversal
      removes a latent disagreement between the two encodings rather than creating one).
- [x] 7.6 On renumber, sweep the whole feature's artifacts:
      `grep -rn 'ADR-173' knowledge-base/project/{plans,specs}/feat-one-shot-7394-*/`.

## Phase 7.5 — [D5, P0] Re-point the two sibling suites that assert the OLD polarity

⚠️ Without this, three assertions go red at 8.1–8.4 with failure text claiming the fix is a regression.

- [x] 7.5.1 `plugins/soleur/test/worktree-manager-atomic-config.test.sh` **Test 17** (~`:425-428`)
      asserts `extensions.worktreeConfig == true` on a genuine bare repo. Invert it to the new
      invariant (extension **absent**, `core.bare` **retained as true**) and rewrite both the PASS
      and FAIL strings — the current FAIL text (*"bare repo lost its extensions.worktreeConfig
      surgery — bare-layout regression"*) would mislead a future reader into restoring the bug.
- [x] 7.5.2 `plugins/soleur/test/worktree-manager-stale-lock-diag.test.sh` `:248-249` assert
      `core.repositoryformatversion == 1` and `extensions.worktreeConfig == true` *"written via
      lockless path"* — both writes are deleted by task 3.1. Their real purpose (prove the lockless
      writer works when `config.lock` is a non-regular node) is still valid, so **re-point onto a
      surviving observable**: seed the fixture with `extensions.worktreeConfig=true`, then assert it
      was **REMOVED** via the lockless path. Bonus: that exercises the `--unset-all` path task 3.0
      fixes.
- [x] 7.5.3 Do **NOT** delete these assertions — they are the only coverage of the lockless-writer
      path under a wedged lock (`#5934` / `#5912`).
- [x] 7.5.4 Sweep: `git grep -n 'extensions.worktreeConfig' plugins/soleur/test/` — every remaining
      hit must be a seed line or an absence assertion, never an "is SET by ensure_bare_config" claim.

## Phase 8 — Verification

- [x] 8.1 `bash plugins/soleur/test/worktree-manager-bare-in-dotgit-layout.test.sh` — all 14 cases.
- [x] 8.2 `bash plugins/soleur/test/worktree-manager-atomic-config.test.sh` — green. **[R-kieran2]**
      Tests 23/24: either add `[[ ! -e "$WS24/.git/config.worktree" ]]` to test 23, or update its
      comment to record that safety now comes from Phase 3's structural removal.
- [x] 8.3 `bash plugins/soleur/test/worktree-manager-bare-sync.test.sh` — green.
- [x] 8.3a **[D5]** `bash plugins/soleur/test/worktree-manager-stale-lock-diag.test.sh` — green.
- [x] 8.4 `bash scripts/test-all.sh` — read the **`N/M` summary line**, not a piped exit code. No new
      failures vs the Phase 0.5 baseline.
- [x] 8.5 Walk every Acceptance Criterion in the plan (1–14 plus 7a, 8a–8i) and record the actual
      command output for each.
- [x] 8.6 File the deferral issue from the plan's `## Deferrals`: *shrink `ensure_bare_config` to
      what facts 2 and 3 leave load-bearing*. Required before the PR is marked ready.
- [x] 8.7 PR body uses **`Closes #7394`** (a code fix taking effect at merge, not an
      ops-remediation), includes the `## Changelog` section, and records `git --version`.
- [x] 8.8 Confirm `knowledge-base/project/specs/feat-one-shot-7394-worktree-manager-bare-repo-layout/decision-challenges.md` is
      committed so `/ship` Phase 6 can render it into the PR body.

---

## Post-merge (operator)

**None.** Every step is automated in-workflow. The operator's own repo normalizes on the next
`create` / `create-for-feature` / `cleanup-merged` run.

> **Caveat recorded, not hidden ([R7]):** that normalization rides on the session-start gate
> `wg-at-session-start-run-bash-plugins-soleur`, which is an AGENTS.md rule rather than a hook, and
> the learnings corpus records it being skipped. The self-heal (Phase 5) is what makes the
> *current* worktree usable without waiting for that gate.
