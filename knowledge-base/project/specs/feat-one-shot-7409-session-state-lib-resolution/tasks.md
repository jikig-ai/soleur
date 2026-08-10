# Tasks — feat-one-shot-7409-session-state-lib-resolution

Plan: `knowledge-base/project/plans/2026-08-10-fix-session-state-lib-plugin-resolution-plan.md`
Issue: #7409 · Lane: `cross-domain` · Brand-survival threshold: `single-user incident`

**Destination (decided):** `plugins/soleur/scripts/lib/session-state.sh`
**Test destination:** `plugins/soleur/test/session-state.test.sh`

> **Read the plan's Sharp Edges before starting.** Five traps have already bitten this plan once each: `is_lease_active` passes vacuously; `expected_duration_min=240` is the default at two layers so asserting it proves nothing; Python `fnmatch` crosses `/` where bash globs do not; the `## User-Brand Impact` threshold must be a **bullet** or `/soleur:preflight` Check 6 hard-FAILs at ship time; and an AC grep must be **run against the tree**, not read — doing so is what found `lease-protects-active.test.sh:128`.

> **Do not close #7409 from a move-only PR.** If the CTO's two-PR split (DC-1) is ever adopted, the first PR uses `Ref #7409`; only the PR carrying Phase 2 may use `Closes #7409`.

---

## Phase 0 — Preconditions

- [ ] **0.1** Re-verify the highest ADR ordinal on freshly-fetched `origin/main`. `ADR-174` was highest at plan time. If `175` is taken, renumber **and** sweep `knowledge-base/project/{plans,specs}/feat-one-shot-7409-session-state-lib-resolution/` for the old ordinal.
- [ ] **0.2** Record the plugin delivery mechanism. `plugin.json` version is a frozen sentinel `0.0.0-dev`, so the cache dir name never changes. Verified verbs: `claude plugin marketplace update soleur` + `claude plugin update soleur`. **Also record the measured staleness** of the authoring machine's install (64 skills vs 96 in repo; mtime 2026-05-10) — it goes in the PR body.
  - Do **not** re-litigate packaging: `marketplace.json` `"source": "./plugins/soleur"` is a whole-subtree copy and nested dirs demonstrably ship (live install nests 12 deep).

## Phase 1 — Move the library and repoint consumers (one commit)

- [ ] **1.1** `git mv .claude/hooks/lib/session-state.sh plugins/soleur/scripts/lib/session-state.sh`
- [ ] **1.2** `git mv .claude/hooks/lib/session-state.test.sh plugins/soleur/test/session-state.test.sh`
  - [ ] **1.2a** `:10` → `HELPER="$SCRIPT_DIR/../scripts/lib/session-state.sh"`
  - [ ] **1.2b** `:785` — `WM="$(cd "$SCRIPT_DIR/../../.." && pwd)/plugins/soleur/skills/…"`. `../../..` reaches repo root from **both** old and new locations, so it survives **by coincidence**. Confirm, then leave it with an explicit comment.
- [ ] **1.3** Byte-identity: `session-state.sh` content unchanged except the 1.5 comment lines (see AC10).
- [ ] **1.4** Repoint consumers — literals below are verified by path arithmetic:

| File | Line(s) | New path |
|---|---|---|
| `plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh` | `:48` | `$SCRIPT_DIR/../../../scripts/lib/session-state.sh` |
| ″ | `:67` | recovery text (old `git checkout origin/main -- .claude/hooks/lib/…` will fail post-merge) |
| ″ | `:1372` | comment "reached across the plugin → .claude/hooks boundary" — now false |
| `.claude/hooks/lib/incidents.sh` | `:18` **and** `:19` | `../../../plugins/soleur/scripts/lib/session-state.sh` |
| `.claude/hooks/lib/log-rotation.sh` | `:63` **and** `:64` | same |
| `.claude/hooks/pre-merge-rebase.sh` | `:27` **and** `:32` | `../../plugins/soleur/scripts/lib/session-state.sh` |
| `scripts/lib/test-contention.sh` | `:47` | `$_tc_lib_dir/../../plugins/soleur/scripts/lib/session-state.sh` |
| `plugins/soleur/test/concurrent-ship.test.sh` | `:12` | `$REPO_ROOT/plugins/soleur/scripts/lib/session-state.sh` |
| `plugins/soleur/skills/git-worktree/test/lease-protects-active.test.sh` | `:14` | same |
| `plugins/soleur/test/worktree-manager-safe-branch-sanitization.test.sh` | `:209` | `$SCRIPT_DIR/../scripts/lib/session-state.sh` |

  - [ ] Each `source` line has a paired `# shellcheck source=` directive **one line above** — repoint both, or `shellcheck -x` emits SC1091.
- [ ] **1.5** Prose sweep: `session-state.sh:266,362` (its own CLI-usage comments — the copy-source for the SKILL.md invocations), `session-state.test.sh:2,194,374`, **`lease-protects-active.test.sh:128`** (CLI-usage comment — **inside AC6's grep scope**; omitting it turns AC6 red), `session-state.sh` header (`agent-token-tee.sh:160-170`), `.claude/hooks/pre-merge-auto-close-scan.sh:102`, `.claude/hooks/prod-write-defer-gate.sh:43`, `scripts/tmpfs-guard.sh:31,804`, `git-worktree/SKILL.md:179`.
  - Self-check before claiming AC6: `git grep -lE '\.claude/hooks/lib/session-state\.sh' -- plugins/soleur/skills/` must return **nothing**. At plan time it returned 9 files — that list *is* the work list for this pattern.
- [ ] **1.6** ⛔ **DO NOT TOUCH** — these use the bare basename `session-state.sh` with no path:
  - `plugins/soleur/skills/plan/SKILL.md:962`, `plugins/soleur/skills/review/SKILL.md:1339`
  - `.claude/hooks/pre-merge-rebase-parity.test.sh:150,157`, `pre-merge-rebase.test.sh:415`, `prod-write-defer-gate.test.sh:199,218` — these **assert** the hooks still match the wrapped form; editing them breaks the #3689 bypass gate.

## Phase 2 — SKILL.md sites (seven, three shapes)

Anchor: `${CLAUDE_PLUGIN_ROOT:-<preserved-anchor>}/scripts/lib/session-state.sh` — preserve each site's existing anchor form (ADR-093 anchor-preservation).

- [ ] **2.1** Four `with_lock` sites — `merge-pr:260`, `product-roadmap:234`, `schedule:472`, `ship:1714` — degrade-open `if/else`, emitting `reason=running-unlocked` on **stdout** and running `<CMD>` in the else-branch.
- [ ] **2.2** Two `release_lease` sites — `one-shot:115`, `work:220` — one-liner with `|| true`. No if/else, no marker.
- [ ] **2.3** One `acquire_lease` site — `git-worktree:320` — degrades open but **never silently**: emit `reason=worktree-UNLEASED-and-reapable`. This is on the destructive side of the gradient.
- [ ] **2.4** `product-roadmap/SKILL.md:234` documents `rc=99` contention semantics; the bare else-branch cannot produce `rc=99` — add a clause.

## Phase 3 — Preserve guard surfaces

- [ ] **3.1** `.claude/hooks/hook-input-contract.test.sh:377` — add `$REPO_ROOT/plugins/soleur/scripts` to the A1 `find` roots. **Also update A1's success message**, which still names only `.claude/hooks/**` / `.openhands/hooks/**`. The carve-out at `:374` needs **no edit** (suffix-matched `*/lib/session-state.sh`).
- [ ] **3.2** Add the **membership assertion**: A1 fails if the enumerated list has no path ending `/lib/session-state.sh`. Durable half — `find … 2>/dev/null` means a removed root reports `ok` (silently green).
- [ ] **3.3** `plugins/soleur/test/components.test.ts` `EXEC_SURFACE_GLOBS` — add `plugins/soleur/scripts/**/*.sh` and `plugins/soleur/hooks/**/*.sh`. Opportunistic hygiene, **not** a regression this PR creates (that lint targets `gh pr|issue list --search`; the library has zero such probes). **No mutation AC** — one cannot be constructed.
- [ ] **3.4** `scripts/lint-shell-capture-exit.baseline.txt:8,9` — repoint both entries (fingerprint keys on path).
- [ ] **3.5** Confirm shipped-surface `eval` is a non-event (expected: yes — `check-codeexec.sh` reads SKILL.md on stdin, so shipped `.sh` is out of scope). If flagged, allowlist the exact fd-close string; never rewrite the flock fd handling.

## Phase 4 — Tests (write failing first)

- [ ] **4.1** Cache-install acquisition scenario, added to `lease-protects-active.test.sh` (reuses its bare-repo + `origin/<from>` fixture):
  - [ ] Build `<tmp>/cache/<mkt>/soleur/<ver>/`; `cp -r plugins/soleur/.` **only**. Assert `find <cache> -name '.claude' -type d` is empty as a precondition.
  - [ ] `--yes create feat-probe` with `SOLEUR_SKILL_NAME=one-shot SOLEUR_EXPECTED_DURATION_MIN=137`.
  - [ ] Assert the lease **FILE** carries `pid=`, `skill=one-shot`, `expected_duration_min=137`. **No exit-code assertion** — `create` exits 0 in both states.
  - [ ] Mutation arm (T2): delete the library from the fixture → RED.
  - [ ] Guard the `cd` (`if ( cd … && … )`) — these suites run `set -uo pipefail` **without** `-e`.
- [ ] **4.2** **Reaper-refusal scenario (T3)** — cache layout: `cleanup-merged` from a sibling leaves a leased victim intact; clearing the lease file makes it reap. This PR arms the reaper; nothing else covers the refusal.
- [ ] **4.3** **SKILL.md-anchor hop (T3b)** — invoke `worktree-manager.sh` via `${CLAUDE_PLUGIN_ROOT:-./plugins/soleur}/…` from a **non-Soleur** cwd against the cache fixture; assert `..._OK`. Every other test enters by absolute path and cannot see this link.
- [ ] **4.4** **Interop scenario (T6)** — old-path and new-path copies against one `git-common-dir`; one's lease honoured by the other's `is_lease_active`.
- [ ] **4.5** Fix the pre-existing vacuity at `lease-protects-active.test.sh:253` (`expected_duration_min=240` → non-default).
- [ ] **4.6** Decide the `SOLEUR_WORKTREE_LEASE_LIB_OK` marker's compatibility: it adds an unconditional line to a stream agents parse. Either assert existing parsers still work, or gate it behind a debug variable.

## Phase 5 — ADR + C4

- [ ] **5.1** Write `ADR-175` — location, per-consumer-class resolution order, MOVE-not-duplicate, the security-posture note, and the **standardised snippet including the `$SS_LIB` assignment** (the assignment is the defect; showing only the `if` around it elides the hard part). Alternatives table: A–G from the plan.
- [ ] **5.2** Cross-reference from `ADR-093` §Consequences (this resolves a member of its declared #6222 residual class).
- [ ] **5.3** `model.c4` — correct **both** falsified descriptions (`platform.plugin`, `platform.engine.hooks`) and add the `hooks -> plugin` edge. Both endpoints are already in the `containers` view include list, so no new `include` line.
- [ ] **5.4** ⚠️ `bash scripts/regenerate-c4-model.sh` — `c4-model-freshness.test.sh` **byte-diffs** the committed `model.likec4.json` and is pinned in CI. Skipping this is a guaranteed red.

## Phase 6 — Verification

- [ ] **6.1** `bash scripts/test-all.sh` exits 0, and its output **names** `plugins/soleur/test/session-state.test.sh` (R6 — it never has). Pin the same `TEST_GROUP` shard for any comparison.
- [ ] **6.2** `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` (the `npm run -w` form fails — no root `workspaces`).
- [ ] **6.3** `bash plugins/soleur/test/c4-model-freshness.test.sh`; `./node_modules/.bin/vitest run test/c4-code-syntax.test.ts test/c4-render.test.ts` from `apps/web-platform`.
- [ ] **6.4** Byte-identity (AC10): `git show origin/main:.claude/hooks/lib/session-state.sh | diff - plugins/soleur/scripts/lib/session-state.sh` differs only in Phase 1.5 comments.
- [ ] **6.5** Re-run the plan's Overview reproduction against the fixed tree; paste output in the PR body.

## Phase 7 — Deferred measurement (NOT a precondition)

- [ ] **7.1** Settle the R8 confound: run a Soleur skill from a directory with **no** `plugins/soleur/` and probe `echo "[${CLAUDE_PLUGIN_ROOT:-UNSET}]"`. Both branches yield the **same** committed artifact, so this gates nothing here.
- [ ] **7.2** File Deferral 1 **only if** UNSET. Labels `domain/engineering`, `type/bug` (verified to exist). Relate to #6222.
- [ ] **7.3** File Deferral 2 (`freeze-lock.sh:37` depth coupling; also an orphan suite) — out of scope, filed so scope creep does not pull it in.

## Phase 8 — Ship

- [ ] **8.1** PR body: `Closes #7409`, the reproduction before/after, the **install-staleness measurement**, the R-5 "this PR arms the reaper" note, and the `decision-challenges.md` render.
- [ ] **8.2** Post-merge: `claude plugin marketplace update soleur && claude plugin update soleur`, then re-run the reproduction from the cache install (AC14).
- [ ] **8.3** Post-merge: `worktree-manager.sh sync-bare-files` — the bare root holds repointed sources whose target is absent until this runs, and both degrade **silently** (AC15).
