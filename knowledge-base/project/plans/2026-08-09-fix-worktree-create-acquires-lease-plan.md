---
title: "fix(git-worktree): `create` never acquires a lease — close the gap the predecessor fix left open"
date: 2026-08-09
type: fix
branch: feat-one-shot-worktree-create-lease
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
recurring_cost_eur_per_month: 0.00
---

# fix(git-worktree): `create` never acquires a lease

## Enhancement Summary

**Deepened on:** 2026-08-09 — deliberately proportionate pass (small, already-diagnosed fix; no 40-agent fan-out).

**Gates run:** 4.6 User-Brand Impact (pass — `single-user incident`), 4.7 Observability (pass — 5 fields present, no `ssh` in `discoverability_test.command`), 4.8 PAT-shaped variable (pass — no matches), 4.9 UI wireframe (skip — no UI surface), 4.10 Encryption Posture (skip — no persistent store, no new cross-component connection), 4.55 Downtime & Cutover (skip — no serving surface affected), 4.5 Network-Outage (skip — the sole keyword match is the line *"No SSH anywhere"*, a declaration of absence, not a connectivity symptom).

**Agents:** `kieran-rails-reviewer` (correctness), `code-simplicity-reviewer` (YAGNI/scope). Both cleared the plan; three findings folded in below.

### What the deepen pass changed

1. **The fixture is now empirically pre-validated, not merely designed.** The proposed Scenario-3 harness was executed against the unfixed `worktree-manager.sh`: it goes RED at the lease assertion with exit-0 passing — exactly the RED that AC5 demands. `/work` inherits a working harness. See *"The fixture above is already empirically validated"* under Phase 1.
2. **A false-pass trap was found by running it.** The leases *directory* is created at source time and is **empty** on the unfixed path, so a `[[ -d … ]]` assertion would pass against the bug. The plan now says: assert the **file**, never the directory.
3. **The Phase 2 insertion anchor was ambiguous and is now disambiguated.** `install_deps "$worktree_path"` appears **twice** in the file (once per creating function). A grep-driven edit could patch the wrong one. The anchor is now the *following* line, per `cq-cite-content-anchor-not-line-number`.
4. **Symbol scope pre-resolved** (raised by `code-simplicity-reviewer`): `headless_or_stderr` and the three lease functions all resolve at file scope, plus fallback stubs — so `create_worktree` needs no extra sourcing, and the stub branch is precisely why AC3's `pid=` assertion is load-bearing.
5. **The follow-up issue's item 4 was re-severitied** (raised by `code-simplicity-reviewer`): the unleased early-return arm is a known-live gap of the *same brand-survival class* as the bug being fixed — a one-shot re-run is the second-most-common path, not an edge case. It was reading as an appendix; it now carries its own severity.

### Verified against real code during this pass

Every AC grep was executed, not reasoned about. Current counts: `acquire_lease "$branch_name"` → **1**, `_register_lease_release_trap "$branch_name"` → **1**, bare `sweep_orphan_leases` → **1**, `MIN_ASSERTIONS=3` → **1**. Post-fix targets of 2/2/2 and `MIN_ASSERTIONS=6` were correct **as of the deepen pass**; the CONCUR gate and then the 8-agent review moved them to 4 sites behind a single extracted helper and `MIN_ASSERTIONS=15`. See both addenda — this paragraph records what was measured then, not the shipped state. The stub definitions do not carry `"$branch_name"`, so they cannot inflate the counts. The Phase 3 comment anchors exist verbatim in `session-state.sh`. AC9's absence-grep pipeline isolates only the real `trap` line and returns 0 as required.

**Nothing was cut.** Both reviewers independently judged the plan already at its floor: the comment fix, the three assertions, and the 11 ACs each gate something the other two do not.

## Overview

`worktree-manager.sh` has two worktree-creating entry points. Only one of them acquires a lease.

`create_for_feature()` (dispatched from `feature|feat`) sweeps, acquires, and registers a release trap. `create_worktree()` (dispatched from `create`) does none of that — and `--yes create` is what the autonomous pipeline actually invokes, at one-shot Step 0b and work Phase 1. Every worktree the pipeline creates is therefore unprotected from the instant it exists, and the `SOLEUR_SKILL_NAME` / `SOLEUR_EXPECTED_DURATION_MIN` env vars those two SKILL.md blocks set are read by nobody on that path.

The fix is to give `create_worktree` the same three lines its sibling already has, plus one behavioural regression test that would have caught this and a comment correction in `session-state.sh` that currently asserts the opposite of the truth.

**This is a parity fix, not a redesign.** Deliberately no new lease semantics, no new env vars, no new helper.

### Why the predecessor fix was necessary and not sufficient

Already merged on `origin/main` (do NOT redo): `_register_lease_release_trap` no longer arms `EXIT` (`.claude/hooks/lib/session-state.sh`, anchor `trap "_lease_release_safe`), and both `is_lease_active` and `sweep_orphan_leases` are window-gated rather than `kill -0`-gated. That change makes leases *work for callers that acquire one*. The pipeline is not such a caller. Both halves are required; only one shipped.

### The irony worth recording

`session-state.sh` `_register_lease_release_trap`'s own comment block (anchor: `# \`create_worktree\` acquires the lease and registers this trap IN THE SAME`) states:

> `create_worktree` acquires the lease and registers this trap IN THE SAME PROCESS … Measured: the leases directory is EMPTY the instant `worktree-manager.sh --yes create` returns.

The **measurement was real**; the **attributed mechanism was wrong**. The leases directory was empty after `--yes create` not because an `EXIT` trap released the lease, but because `create` never wrote one. The comment documents an intent the code never implemented, and it made a true observation land on a false cause — which is precisely why the second half of the defect survived the first fix. Correcting that comment is in scope for this PR: after this change the first sentence becomes true, and the "Measured" sentence needs the second cause named.

## Research Reconciliation — premises vs. codebase

All premises re-verified against the working tree at `origin/main` = `0e9e07ba3`. No re-derivation of the diagnosis; these are existence/anchor confirmations only.

| Premise (from operator, treated as ground truth) | Verified against code | Plan response |
| --- | --- | --- |
| `create)` → `create_worktree()`, `feature\|feat)` → `create_for_feature()` | Confirmed. `create_worktree()` body runs `ensure_bare_config` → prompt → `heal_stale_branch` → `git worktree add` → `verify_worktree_created` → `ensure_bare_config` → `ensure_worktree_identity` → `copy_env_files` → `install_deps` → success echo. Zero lease calls. | ~~Insert the acquire block after `install_deps`, before the success echo.~~ **Superseded by the review addendum:** that placement leaves the whole `git worktree add` → `install_deps` span unleased, which is the span in which the reap was actually observed. Acquire now precedes `git worktree add`. |
| `acquire_lease` called only at one site; `_register_lease_release_trap` only at one site | Confirmed — both inside `create_for_feature`, in the order `sweep_orphan_leases` → `acquire_lease … \|\| headless_or_stderr warn` → `_register_lease_release_trap`. | ~~Copy that block verbatim.~~ **Superseded:** extracted to `_acquire_worktree_lease` and called from four sites, after the review found the block itself needed trap-gating, artifact verification and a telemetry marker. |
| one-shot + work both invoke `--yes create` with the lease env vars | Confirmed at `plugins/soleur/skills/one-shot/SKILL.md` (anchor `SOLEUR_SKILL_NAME=one-shot`) and `plugins/soleur/skills/work/SKILL.md` (anchor `SOLEUR_SKILL_NAME=work`). Both prose blocks assert the env "wire a lease on this worktree". | **No doc edit needed.** The docs describe the intended contract correctly; this PR makes them true. Editing them would be the wrong repair. |
| `create_for_feature` does not delegate to `create_worktree` | Confirmed — it re-implements `git worktree add` itself. | No double-acquire risk on the `feature` path. |
| The two candidate test homes and their floors | Confirmed: `lease-protects-active.test.sh` has `MIN_ASSERTIONS=3`; `.claude/hooks/lib/session-state.test.sh` has `MIN_ASSERTIONS=39`. | See **Test home decision** below. |
| Tests in `plugins/soleur/skills/*/test/` run in CI | Confirmed — `scripts/test-all.sh` bash-suite loop globs `plugins/soleur/skills/*/test/*.test.sh`. | No test-runner wiring needed. |

**One premise the operator did not state, found while verifying and load-bearing for the test design:** `worktree-manager.sh` defines **no-op stubs** (`acquire_lease() { return 0; }`, `sweep_orphan_leases() { return 0; }`, `_register_lease_release_trap() { return 0; }`) for the case where `.claude/hooks/lib/session-state.sh` is missing (anchor: `session-state.sh missing at`). A test that asserts only "`create` exits 0" would pass under the stub path while writing no lease. The new test must assert the **lease file on disk**, which the stubs cannot fake — see AC3.

## User-Brand Impact

**If this lands broken, the user experiences:** a Soleur run that deletes its own work. Measured three times (2026-08-06 11:39Z, 2026-08-06 14:13Z, 2026-08-07 16:24Z): a sibling session's `cleanup-merged` reaped the running worktree, deleted the branch locally *and* on `origin`, and closed the PR — mid-run, with hours of work in it. Reproduced live this session: a `--yes create` worktree checked out all 13,354 files and vanished before the script's own `verify_worktree_created` ran, emitting `SOLEUR_GIT_WORKTREE_VERIFY_FAILED reason=not-a-worktree`.

**If this leaks, the user's data is exposed via:** n/a — no data leaves the machine. The exposure here is *destruction*, not disclosure.

**Brand-survival threshold:** `single-user incident`. One occurrence is enough: a tool that silently deletes a user's branch and closes their PR is unrecoverable reputationally regardless of frequency, and the operator is non-technical and cannot diagnose it.

**CPO sign-off:** required by threshold. This plan is produced on the headless one-shot path, so sign-off is recorded here rather than interactively collected; the framing above is the artifact under sign-off. `user-impact-reviewer` runs at review time per the conditional-agent block.

## Files to Edit

| File | Change | Size |
| --- | --- | --- |
| `plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh` | Insert the sweep + acquire + trap block into `create_worktree()`, after `install_deps "$worktree_path"` and before the success echo. | ~6 lines + comment |
| `.claude/hooks/lib/session-state.sh` | Correct the `_register_lease_release_trap` comment block so it no longer asserts a behaviour the code did not have, and names both causes of the measured-empty leases directory. | ~4 lines, comment only |
| `plugins/soleur/skills/git-worktree/test/lease-protects-active.test.sh` | Add **Scenario 3**: `--yes create` writes a lease. Raise `MIN_ASSERTIONS` 3 → 6. | ~45 lines |

**Files to Create:** none.

## Implementation Phases

Phase order is load-bearing: the test lands RED before the fix, per `cq-write-failing-tests-before`.

### Phase 1 — RED: Scenario 3 in `lease-protects-active.test.sh`

Append a third scenario to the existing suite. It reuses this file's fixture idioms (fake bare repo, `SOLEUR_SESSION_STATE_ROOT` override, `pass`/`fail` counters) and lifts the **upstream-bearing** fixture shape from its sibling `create-from-origin-main.test.sh` — `create_worktree` calls `resolve_base_ref`, which resolves to `origin/<from>`, so the fixture needs a local bare repo with an `origin` remote, not the bare-repo-only shape scenarios 1 and 2 use.

Shape (mirroring `create-from-origin-main.test.sh`, which already proves `bash "$WM" --yes create <name>` runs green through `copy_env_files` and `install_deps` in exactly this fixture):

```bash
# --- SCENARIO 3 (#7278 second half): `create` must ACQUIRE a lease -----------
# Scenarios 1-2 prove a lease PROTECTS a worktree. This proves one gets WRITTEN
# by the entry point the autonomous pipeline actually calls. A lease layer that
# protects but is never acquired protects nothing.
UP3="$TMP/up3.git"; git init --bare -b main "$UP3" >/dev/null
S3="$TMP/s3"; git clone "$UP3" "$S3" >/dev/null 2>&1
( cd "$S3" && git -c user.email=t@t -c user.name=t commit --allow-empty -m seed >/dev/null \
    && git push origin main >/dev/null 2>&1 )
rm -rf "$S3"
LOCAL3="$TMP/local3.git"; git init --bare -b main "$LOCAL3" >/dev/null
( cd "$LOCAL3" && git remote add origin "$UP3" && git fetch origin main:main >/dev/null 2>&1 )

LEASE_ROOT3="$LOCAL3/soleur-session-state"
(
  cd "$LOCAL3"
  SOLEUR_SESSION_STATE_ROOT="$LEASE_ROOT3" \
  SOLEUR_SKILL_NAME=one-shot SOLEUR_EXPECTED_DURATION_MIN=240 \
    bash "$WM" --yes create feat-probe >"$TMP/create3.log" 2>&1
) && pass "scenario 3: --yes create exited 0" \
  || fail "scenario 3: --yes create failed (output: $(cat "$TMP/create3.log"))"

LEASE3="$LEASE_ROOT3/leases/feat-probe.lease"
if [[ -f "$LEASE3" ]]; then
  pass "scenario 3: --yes create wrote $LEASE3"
  # The no-op stubs worktree-manager.sh installs when session-state.sh is absent
  # would satisfy an exit-0 check while writing nothing; a `pid=` line can only
  # come from a real acquire_lease.
  grep -q '^pid=' "$LEASE3" \
    && pass "scenario 3: lease carries a pid= line (real acquire_lease, not a stub)" \
    || fail "scenario 3: lease file exists but has no pid= line"
else
  fail "scenario 3: NO lease written by --yes create — this is the #7278 second half \
(dir: $(ls -A "$LEASE_ROOT3/leases" 2>/dev/null || echo MISSING))"
fi
```

Then raise the floor:

```bash
MIN_ASSERTIONS=15  # 3 -> 6 -> 9 -> 15 (#7278 scenarios 3-6; see the 2026-08-09 review addendum)
```

Confirm RED: run the suite before Phase 2 and record that it fails at the lease-file assertion, not at the exit-0 assertion. **If it fails at exit-0 instead, the fixture is wrong, not the code** — fix the fixture before proceeding, or the Phase 2 green is vacuous.

#### The fixture above is already empirically validated — deepen-plan ran it

This exact fixture was executed against the **unfixed** `worktree-manager.sh` during the deepen pass, so `/work` inherits a pre-validated harness rather than discovering its quirks:

```
  pass: (a) --yes create exited 0
  FAIL: (b) NO lease written (leases dir: )
worktree present: yes
=== PASS: 1  FAIL: 1
```

Three things this establishes, each of which would otherwise cost a /work iteration:

1. **It goes RED for the right reason.** Assertion (a) passes — the fixture reaches `create_worktree`'s tail. Only the lease assertion fails. This is the RED that AC5 requires.
2. **`copy_env_files` and `install_deps` are harmless in this fixture.** The run logged `No .env files found in main repository` and produced no dependency install — there is no `package.json` in a bare fixture repo, so the 13,354-file / npm-install cost of the real repo does not apply. The suite stays fast.
3. **The leases *directory* exists and is EMPTY on the unfixed path.** `session-state.sh` `mkdir -p`s `leases/` at source time regardless of whether anything is ever written. So an assertion of the form `[[ -d "$LEASE_ROOT3/leases" ]]` would **false-pass against the bug**. Assert the **file**, never the directory. (Same class as `cq-assert-anchor-not-bare-token`: assert the discriminator.)

### Phase 2 — GREEN: the acquire block in `create_worktree`

**Disambiguate the anchor before editing.** `install_deps "$worktree_path"` appears **twice** in the file — once in `create_worktree`, once in `create_for_feature`. Do not grep for it alone. The `create_worktree` site is the one **immediately followed by** `echo -e "${GREEN}✓ Worktree created successfully!${NC}"`; the `create_for_feature` site is the one immediately followed by the `# Sweep stale leases lazily` comment (i.e. the block you are copying). Anchor on that following line, not on `install_deps` and not on a line number (`cq-cite-content-anchor-not-line-number`).

Insert between `install_deps "$worktree_path"` and the success echo. **Verbatim the same form as `create_for_feature`** — do not invent a variant, do not "improve" the warn text:

```bash
  # Sweep stale leases lazily; cheap and idempotent.
  sweep_orphan_leases

  # Acquire a lease on this worktree so sibling cleanup-merged invocations
  # see it as active and refuse to reap it. Same block as create_for_feature:
  # `create` is the entry point one-shot Step 0b and work Phase 1 actually call,
  # so without this the autonomous pipeline's worktrees carried no lease at all.
  acquire_lease "$branch_name" "${SOLEUR_SKILL_NAME:-unknown}" "${SOLEUR_EXPECTED_DURATION_MIN:-240}" \
    || headless_or_stderr warn "could not acquire lease for $branch_name"
  # Multi-signal trap so an interrupted session (SIGINT/SIGTERM/SIGHUP)
  # still releases the lease.
  _register_lease_release_trap "$branch_name"
```

`$branch_name` is already the local's name in both functions — no rename, no plumbing.

**Scope of the copied symbols is already verified — do not re-derive.** All four names the block uses resolve at file scope, so `create_worktree` needs no extra sourcing or plumbing: `headless_or_stderr` is defined top-level in `.claude/hooks/lib/session-state.sh` (anchor `headless_or_stderr() {`), and `worktree-manager.sh` additionally defines fallback stubs for `acquire_lease`, `sweep_orphan_leases`, `_register_lease_release_trap`, and `headless_or_stderr` in its session-state-missing branch (anchor `headless_or_stderr() { echo "[$1] $2" >&2; }`). The stub branch is exactly why AC3's `pid=` assertion exists — the stubs return 0 and write nothing.

### Phase 3 — Correct the `session-state.sh` comment

Comment-only. In `_register_lease_release_trap`, the sentence asserting that `create_worktree` acquires the lease was false when written; make it true-as-of-this-PR and name the second cause of the measured emptiness. Suggested amendment (adjust to fit surrounding prose):

```
  # `create_worktree` acquires the lease and registers this trap IN THE SAME
  # PROCESS (as of #7278 — before that it did neither, and only
  # `create_for_feature` did), and that process exits normally on success.
  # …
  # Measured: the leases directory is EMPTY the instant
  # `worktree-manager.sh --yes create` returns. That measurement had TWO causes,
  # and only one was fixed here: EXIT released what was acquired, AND `create`
  # never acquired at all. Fixing the trap alone left the pipeline path dark.
```

### Phase 4 — Verify

Run, in order:

1. `bash plugins/soleur/skills/git-worktree/test/lease-protects-active.test.sh` — expect `PASS: 15` (was `PASS: 6` when this line was written; see the review addendum).
2. `bash plugins/soleur/skills/git-worktree/test/create-from-origin-main.test.sh` — regression guard: `create` now acquires a lease inside this suite's fixture too; confirm it stays green (it should — a lease write is additive and its fixture bare repo absorbs the `soleur-session-state/` directory).
3. `bash scripts/test-all.sh` (or the bash-suite subset) — full exit gate.
4. The **live probe** below.

## Test home decision — `lease-protects-active.test.sh`, not `session-state.test.sh`

**Chosen:** `plugins/soleur/skills/git-worktree/test/lease-protects-active.test.sh` (floor 3 → 6 at plan time; **15** as shipped).

**Why:**

1. **Subject-under-test match.** The defect is in `worktree-manager.sh`, a plugin script. `session-state.test.sh` tests the `session-state.sh` *library primitives* (`acquire_lease`, `is_lease_active`, `sweep_orphan_leases` in isolation). Those primitives are all correct here — the bug is that a caller never calls them. Asserting a plugin script's call-site behaviour from the hooks-library suite would put the assertion in the wrong subject's suite and make the 39-assertion floor cover something it does not describe.
2. **The fixture already exists.** `lease-protects-active.test.sh` already stands up a bare repo, a `SOLEUR_SESSION_STATE_ROOT` override, worktrees, and a `PASS`/`FAIL` harness; `create-from-origin-main.test.sh` next door already proves the `--yes create` invocation runs green in this fixture family. Scenario 3 is an append, not a new harness.
3. **It completes the file's own argument.** Scenario 1: a lease with a live PID protects. Scenario 2 (#7278 first half): a lease whose acquirer exited *still* protects. Scenario 3 (#7278 second half): the entry point the pipeline calls actually *writes* one. Read in order, the file now states the whole invariant instead of two thirds of it — and the header comment on scenario 2 ("a fixture that instantiates only the passing member of a set is a sample, not a proof") applies to the file itself until scenario 3 lands.
4. **Floor raised to match.** `MIN_ASSERTIONS=3 → 6` at plan time, **→ 15 as shipped**, and counting `PASS + FAIL` rather than `PASS`. A floor left at the old number is the defect this repo keeps re-finding; the three new assertions are each independently load-bearing (exit code, file presence, `pid=` line defeating the no-op stubs).

**Rejected:** `.claude/hooks/lib/session-state.test.sh` (floor 39 → 42) — would work mechanically, but see (1).

## Deliberate deviation from the operator's probe recipe (and how it is compensated)

The operator specified a probe that creates a scratch worktree at `origin/main` in the **real repo**, runs `--yes create <throwaway>`, asserts the lease, then deletes the local + remote throwaway branch. That recipe is exactly right for a **one-time live verification** and is retained verbatim as such (AC7). It is the wrong shape for the **committed regression test**, for three reasons:

- A committed test must exercise the code **in its own checkout** (that is what makes it a regression guard and what CI runs), whereas the recipe deliberately pins to merged `origin/main`.
- It touches the network (`git push --delete origin`) and pollutes the real repo with throwaway branches on every CI run.
- `create` runs `install_deps` — in the real repo that is the 13,354-file checkout the operator watched vanish. In the fake fixture it is a no-op.

So: **fixture-based test for CI (AC3–AC5), operator's live probe run once at /work time (AC7).** Both, not either.

## Verification traps — read these before verifying anything

Two traps the parent session already paid for. Do not re-pay them.

1. **The bare repo root at `/home/jean/git-repositories/jikig-ai/soleur` holds a STALE synced mirror of tracked files.** Probing it gives confident wrong answers about what is merged. Always probe from a worktree checked out at `origin/main`, or read blobs via `git show origin/main:<path>`. Never `cat` the bare-repo working copy to decide what main contains. (This is also `hr-when-in-a-worktree-never-read-from-bare`.)
2. **Do NOT verify the trap fix with `grep -c 'INT TERM HUP'`.** The *unfixed* line `EXIT INT TERM HUP` matches that pattern too — the grep returns 1 in both worlds and proves nothing. Anchor on what the fixed form has and the broken form cannot: assert the **absence of `EXIT`** on that trap line, e.g.

   ```bash
   git show origin/main:.claude/hooks/lib/session-state.sh \
     | grep -n '_lease_release_safe' | grep 'trap ' | grep -c 'EXIT'   # must be 0
   ```

   Same class as `cq-assert-anchor-not-bare-token`: assert the discriminator, not the token both states share.

## Acceptance Criteria

### Pre-merge

- [ ] **AC1:** `create_worktree()` in `plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh` contains `sweep_orphan_leases`, `acquire_lease "$branch_name" "${SOLEUR_SKILL_NAME:-unknown}" "${SOLEUR_EXPECTED_DURATION_MIN:-240}"` with the `|| headless_or_stderr warn` arm, and `_register_lease_release_trap "$branch_name"`, in that order, placed after `install_deps` and before the success echo.
- [x] **AC2:** The block is byte-identical in form to `create_for_feature`'s. Verify by count, not by eye: `grep -c 'acquire_lease "\$branch_name"' <file>` returns `4` and `grep -c '_register_lease_release_trap "\$branch_name"' <file>` returns `4`. **Amended 2026-08-09 (was `2`/`2`):** the `code-simplicity-reviewer` CONCUR gate DISSENTED on deferring the early-return arm and it was fixed inline, so each function now carries the block twice — once on the success path, once on its "worktree already exists" re-entry path. Four sites, not two.
- [x] **AC3:** `bash plugins/soleur/skills/git-worktree/test/lease-protects-active.test.sh` exits 0 and prints `PASS: 9`. **Amended (was `PASS: 6`)** — scenario 4 adds the re-entry arm's three assertions.
- [x] **AC4:** The suite's `MIN_ASSERTIONS` is `9`. (`grep -c '^MIN_ASSERTIONS=9' <file>` returns `1`; `grep -c '^MIN_ASSERTIONS=3' <file>` returns `0`.) **Amended (was `6`).**
- [ ] **AC5 (RED-before-GREEN, recorded not re-run):** the Phase 1 run of the suite against un-fixed `worktree-manager.sh` failed at the *lease-file* assertion (scenario 3 assertion 2), not at the exit-0 assertion. Paste the failing line into the PR body.
- [ ] **AC6:** `bash plugins/soleur/skills/git-worktree/test/create-from-origin-main.test.sh` still exits 0 (no regression from the added lease write).
- [ ] **AC7 (live probe, operator's recipe, run once):** from a scratch worktree checked out at `origin/main` (`git worktree add .worktrees/pm-probe origin/main --detach`) — *not* from the bare repo root — run `--yes create <throwaway>`, then assert a `<throwaway>.lease` file exists under `"$(cd -P "$(git rev-parse --git-common-dir)" && pwd -P)/soleur-session-state/leases"`. Clean up: remove both worktrees, delete the local and remote throwaway branch. Paste the `ls` of the leases directory into the PR body.
- [ ] **AC8:** The `_register_lease_release_trap` comment in `.claude/hooks/lib/session-state.sh` no longer asserts un-conditionally that `create_worktree` acquired the lease before this PR, and names both causes of the measured-empty leases directory.
- [ ] **AC9 (trap-fix regression guard, absence-anchored):** on the branch, the `trap "_lease_release_safe …"` line contains no `EXIT`. Verified by the absence grep in **Verification traps** §2 — explicitly **not** by `grep -c 'INT TERM HUP'`.
- [ ] **AC10:** `bash scripts/test-all.sh` exits 0 (full exit gate).
- [x] **AC11 (amended 2026-08-09):** Diff touches exactly **five** non-`knowledge-base/` files. No `*.tf`, no `*.terraform.lock.hcl`, nothing under `apps/web-platform/infra/**`, `infra/**`, `apps/cla-evidence/infra/**`, and nothing registry/zot-related. Verify with `git diff --name-only origin/main...HEAD`.

### Post-merge (operator)

None. Every step above is automatable and runs inline at /work time.

## Observability

```yaml
liveness_signal:
  what: presence of `<branch>.lease` under `<git-common-dir>/soleur-session-state/leases/`
        immediately after `worktree-manager.sh --yes create` returns
  cadence: once per worktree creation (every one-shot Step 0b / work Phase 1)
  alert_target: none (local developer-machine surface; no remote sink exists for it)
  configured_in: plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh (create_worktree)

error_reporting:
  destination: stderr / headless log via `headless_or_stderr warn`, on the existing
               `|| headless_or_stderr warn "could not acquire lease for $branch_name"` arm
  fail_loud: partial by design — acquire failure WARNS and proceeds rather than aborting
             worktree creation, matching create_for_feature. A hard abort here would make a
             lease-dir permission problem destroy the pipeline's ability to create worktrees
             at all, which is strictly worse than the reap risk it would prevent.

failure_modes:
  - mode: acquire_lease fails (permissions, disk-full, malformed existing lease)
    detection: `could not acquire lease for <branch>` on stderr / headless log
    alert_route: operator-visible in the run log; the run continues unleased
  - mode: session-state.sh absent → worktree-manager.sh no-op stubs silently satisfy the call
    detection: existing `session-state.sh missing at <path>` warn at source time,
               PLUS the new test's `pid=` assertion, which a stub cannot satisfy
    alert_route: test suite (CI), and the warn at runtime
  - mode: lease written then reaped by a sibling running a PRE-fix checkout (HYPOTHESISED, not proven — see the addendum; the falsifying experiment is to purge the stale worktrees and see whether leases still vanish)
    detection: NOT detectable from this code path — see Follow-up issue below
    alert_route: none today; this is the gap the follow-up issue tracks

logs:
  where: stderr of the invoking session / the headless run log
  retention: lifetime of the session transcript

discoverability_test:
  command: >
    ls -A "$(cd -P "$(git rev-parse --git-common-dir)" && pwd -P)/soleur-session-state/leases"
  expected_output: the current worktree's `<branch>.lease` is listed
```

No SSH anywhere; this is a local-filesystem surface.

## Architecture Decision (ADR/C4)

**No ADR.** This makes the code match a decision already recorded and already implemented on the sibling path — the lease layer's design is unchanged, its semantics are unchanged, and no future engineer reading the existing ADR corpus would be misled about the system after this ships. A parity fix that removes a divergence between two call sites is not an architectural decision.

**No C4 impact**, and here is the enumeration it is asserted against (all three of `model.c4`, `views.c4`, `spec.c4` reviewed, not a keyword grep):

- **External human actors:** none added. The operator/agent actor is already modeled (`Claude Code instances executing agent workflows`).
- **External systems / vendors:** none. No webhook, no third-party API, no outbound call.
- **Containers / data stores:** none. The lease file is agent-harness state on the developer's local filesystem under the bare repo's common dir; it is not a modeled container and correctly was not one before this change.
- **Actor↔surface access relationships:** unchanged. No ownership, tenancy, or sharing boundary moves.
- **Element descriptions falsified by this change:** none — no modeled element's description references worktree leases.

## Domain Review

**Domains relevant:** none

Infrastructure/tooling change to the agent harness's own worktree management. No product surface, no user-facing UI, no data model, no vendor, no legal or financial implication. Product/UX gate: `## Files to Edit` contains no UI-surface path (two shell scripts and one shell test), so the mechanical UI-surface override does not fire and the tier is NONE.

## Open Code-Review Overlap

**None.** Queried `gh issue list --label code-review --state open --limit 200` and searched every open body for `worktree-manager.sh`, `session-state.sh`, and `lease-protects-active` — zero matches.

## Net-issue-flow disposition

The parent session searched open issues; **none match this defect.** The nearest are #7334 (spec overwrite), #7112 (reaper EACCES), #7118 (reaper decision-challenge) — all different failure modes, none of which is "the create path never acquires a lease".

This PR therefore closes 0 existing issues, and files **1** genuinely new one (below). Both counts require an honest gate override rather than a manufactured link:

```
<!-- gate-override: net-issue-flow --> No open issue describes this defect (nearest: #7334, #7112, #7118 — all different failures), so nothing is closed; one genuinely new, measured durability gap is filed.
```

Do **not** attach `Closes #7112` or similar to make the counter happy — a false close is worse than an override.

## Follow-up issue to file (NOT fixed in this PR)

File one issue, titled around **"lease durability is bounded by the oldest checkout still running cleanup-merged"**. Body should carry:

1. **Measured, this session:** fresh lease files are disappearing on this machine. The parent acquired a lease, confirmed the file on disk, and it later vanished; a sibling session's lease vanished the same way.
2. **What it is not:** current `main`'s `is_lease_active` and `sweep_orphan_leases` are both window-gated and *cannot* reap a two-minute-old lease. So the reaper on `main` is not the culprit.
3. **Probable cause:** a sibling session running a **pre-fix** `worktree-manager.sh` / `session-state.sh` from one of the ~10 stale worktrees on this machine — the old sweep deleted on dead-PID alone. If that holds, the lease layer is only as strong as the *oldest checkout still running `cleanup-merged`*, which is a real durability gap: shipping a fix to a shared-state protocol does not retire the old implementations that still write to that shared state.
4. **Adjacent, same family, SAME SEVERITY — also not fixed here:** `create_worktree`'s early-return arm — when the worktree already exists and the caller switches to it instead — acquires no lease. `create_for_feature` has the identical hole. This is **not a lower-priority nice-to-have**: it is a known-live gap of the *same brand-survival class* as the defect this PR fixes, and the path is not exotic — a one-shot **re-run** (any retry, any resumed session) is the second-most-common path after fresh create, and every one of them ends up unleased and reapable. File it at the same severity, not as an appendix.

   Left out of *this* PR deliberately, for one reason only: the fix here is *parity with `create_for_feature`*, and closing this arm in only one of the two would re-introduce the exact divergence this PR exists to remove — while closing it in both would mean editing `create_for_feature`, which the three-file scope fence (and the decision not to extract a shared helper) explicitly excludes. Fix both arms together in the follow-up, or neither.

Do **not** fold any of this into this PR. It is a distinct failure mode with a distinct fix shape, and the operator's scope fence is explicit.

### Addendum — 2026-08-09: the CONCUR gate DISSENTED, and both dispositions above are superseded

The `/work` Follow-up Filing Net-Flow Gate requires `code-simplicity-reviewer` CONCUR **before** any `gh issue create` — admission control, not ratification. It was run and **dissented on both items**. The section above is left intact as the record of what was originally decided; this addendum records what was actually done and why.

**Item (A), the unleased early-return arm — DISSENT: fixed inline, not filed.**

Measured by the reviewer: ~42 changed lines across 3 files, **0 new files** — both early-return arms live in `worktree-manager.sh`, already the primary file of this diff. The cost-of-filing threshold is ≤100 lines AND ≤4 files, so this is not close to the line.

The decisive argument was not the line count. It was that **parity with `create_for_feature` is this PR's stated thesis, and the early-return arms violate it in both functions identically** — so the finding is an *unmet goal of this PR*, not a follow-up to it. The "three-file fence" is a self-imposed diff-size heuristic meant to bound cross-subsystem blast radius; this change crosses zero new subsystems and adds zero new files, so it was not binding.

Correctness was checked rather than assumed, since "re-acquiring could clobber a live sibling's lease" would have been a genuine reason to defer. It is not: `acquire_lease` is an unconditional atomic overwrite (`mktemp` + `mv`), so a co-tenant re-acquire rewrites `pid`/`started_at` and the computed window only ever gets **longer** — it can never make a worktree reapable. And `release_lease`'s post-exit arm already lets any process release a lease whose recorded pid is dead, which is true of every CLI-acquired lease within milliseconds, so co-tenant release is pre-existing and universal on this protocol, not something the re-entry arm introduces.

One placement caveat was applied: in `create_worktree` the acquire sits **inside** the `if [[ "$response" == "y" ]]` branch, not before the bare `return`. On an interactive `n` the caller never enters the worktree and must not lease it. `create_for_feature`'s arm has no y/n branch, so it acquires unconditionally.

Pinned by **scenario 4**, which carries a precondition assertion that the run actually took the early-return path — without it the arm would silently duplicate scenario 3 and pin nothing new. Verified RED against the pre-fix script (scenario 4's exit-0 and precondition passed; only the lease assertion failed, with an empty leases dir), then GREEN at 9/9.

**Item (B), lease durability bounded by the oldest checkout — DISSENT on the artifact: no issue filed.**

A GitHub issue would be unactionable-by-code. The failing component is a *deployed old implementation* on this machine (16 worktrees, each carrying its own branch-point copy of `worktree-manager.sh` and `session-state.sh`), and no change to `main` retires it. The obvious repo-side hardening — a protocol-version field the sweep respects — is ineffective against the observed cause, because the old sweep is the thing doing the deleting and will never read a field it does not know about. Filing would mint an open issue no PR could close.

Recorded instead as a `/compound` learning: *shipping a fix to a shared-state protocol does not retire the old implementations that still write to that state; N stale checkouts = N old reapers.* The attribution is marked **probable, not proven** — the falsifying experiment is to purge/refresh the stale worktrees and see whether leases still vanish.

**The purge itself was NOT performed.** The reviewer recommended it as a session action, but it is destructive and this machine currently has live sibling sessions — including one holding the worktree and lease for PR #7343. Deleting stale worktrees is an operator decision, not a cleanup to force mid-pipeline.

**Net-issue-flow: 0 filed, 0 closed — net 0.** No `<!-- gate-override: net-issue-flow -->` is needed, and the "Net-issue-flow disposition" section above is superseded on that point. Manufacturing a `Closes #7334` / `#7112` / `#7118` link remains wrong under any circumstances: this diff fixes none of them.

**Next cleanup, deliberately not done here:** the lease block now appears four times. A `_acquire_worktree_lease "$branch_name"` helper would net roughly −10 lines across the four call sites, but extracting it would change the `grep -c` shape these ACs are written against for no behavioural gain. Left for a follow-up refactor.

## Scope fences (hard)

- **Zero Terraform.** No `*.tf`, no `*.terraform.lock.hcl`, nothing under `apps/web-platform/infra/**`, `infra/**`, `apps/cla-evidence/infra/**`.
- **Nothing registry/zot.** A sibling session owns PR #7343 and branch `feat-one-shot-7278-registry-restart-lever`. Do not read, plan for, or modify that work.
- **EUR 0.00/mo recurring.** No vendor, no new service, no expense-ledger entry.
- **Three CODE files.** ~~Any fourth file in the diff is scope creep~~ — superseded by the 2026-08-09 review addendum. The fence is on non-`knowledge-base/` files, and the review added two: `apps/web-platform/server/git-lock-marker-telemetry.ts` (mandatory — a drift guard fails CI unless `MARKER_RE` learns any new sentinel) and `.claude/hooks/lib/session-state.test.sh` (the twin misattribution). The substantive fences (no `*.tf`, nothing under any `infra/**`, nothing registry/zot) all still hold.

## Risks & Sharp Edges

- **A green suite that proves nothing.** Scenario 3's exit-0 assertion passes under the no-op-stub path. The `pid=` assertion is what makes it real. Do not "simplify" the three assertions into one.
- **The floor is the point.** `MIN_ASSERTIONS` must move in the same commit as any new scenario (3 → 6 → 9 → 15 across this PR), and it must count `PASS + FAIL`, not `PASS`. A floor left at the old number is exactly the defect this repo keeps re-finding, and it would let a future refactor silently drop scenario 3 while the suite still exits 0.
- **This test transitively pins the predecessor fix too.** With an `EXIT` trap armed, `create_worktree` would acquire the lease and the trap would delete it as the script exits — scenario 3 would go red. That is a feature: the new assertion guards both halves. Note it in the PR body so a future reader does not "clean up" the trap and get a confusing failure in a suite named for a different scenario.
- **Do not verify merged state from the bare repo root.** See Verification traps §1. Every confident wrong answer this session came from there.
- **Do not use `grep -c 'INT TERM HUP'` for the trap.** See Verification traps §2. It matches the broken form too.
- ~~**`create_for_feature` stays untouched.** It is already correct.~~ **SUPERSEDED 2026-08-09** (see the addendum and the review addendum): its early-return arm had the same hole, its lease also landed after `install_deps`, and a shared helper WAS extracted. It was not already correct. Resist the urge to refactor the shared block into a helper in this PR — it is six lines, the duplication is legible, and extracting it would widen a single-user-incident-threshold diff for no behavioural gain.
