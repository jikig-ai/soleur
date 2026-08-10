# Decision Challenges — feat-one-shot-7408-worktree-safe-branch-derivation

Persisted at plan time in headless mode (one-shot pipeline, no TTY), per ADR-084 / `decision-principles.md`. Each entry is a place where the planning session and the Phase 2.5 domain leaders **agreed the operator's stated direction should change**. The operator's direction is the default — these are surfaced for a decision, not silently applied beyond what the plan records.

`ship` renders this into the PR body and files it as an `action-required` issue.

---

## STATUS — three of the four challenges below were WITHDRAWN at plan review

DC-1, DC-2 and DC-3 were raised after the Phase 2.5 domain review (CTO + CPO), each proposing to *add* scope beyond the issue's stated fix. The plan-review panel then measured the guard chains already present in `worktree-manager.sh` and found the premise underlying all three to be **false**: once nesting is fixed, a flat-but-unleased worktree has **no data-loss path**, because `cleanup_orphan_worktree_dirs` never consults the lease (it reaps only unregistered, `.git`-less directories) and `cleanup_merged_worktrees` skips on uncommitted changes and on any commit inside 10 minutes.

**Net: the operator's original scope was very nearly right.** The issue asked for a derivation fix; the domain review inflated it to a derivation fix plus three guards; plan review cut it back to a derivation fix plus **one** guard (the descendant guard, which is genuine remediation for worktrees already nested on disk).

| # | Raised as | Outcome |
|---|---|---|
| DC-1 | Fail closed on a non-keyable slug | **WITHDRAWN** (plan R1). Premise false; would have regressed legal refnames like `feat(auth)/login` from working to hard refusal. Reduced to a `reason=` field on a marker that already fires. |
| DC-2 | Collision guard (FR5) | **WITHDRAWN** (plan R2), moved to its own issue. Cited evidence was not a slug collision; the guard would have broken the `--yes` resume path for `one-shot`/`work`. |
| DC-3 | Reaper hardening | **PARTLY UPHELD** (plan R3). Descendant guard kept — it is the only thing that helps a customer with an already-nested worktree. `$PWD` guard cut as unreachable. |
| DC-4 | `remove_worktree` does not exist | **UPHELD** — premise correction, unchanged. |

A fifth item surfaced only at plan review and is recorded in the plan as **R6**: the issue's own fourth acceptance criterion ("`create_for_feature`'s spec dir agrees with `cleanup_merged_worktrees`") is **not satisfiable by any implementation**, because the two paths have different roots. It has been restated as a self-consistency check.

The entries below are preserved as the record of what was proposed and why.

---

## DC-1 — Fail closed on a non-keyable slug, rather than warn and proceed

**Class:** user-challenge (scope/behavior change)

**Operator's stated direction (issue #7408):** "derive `safe_branch` once in `create_worktree`; use it for `worktree_path` AND the lease key." The issue frames the fix as a derivation change and does not contemplate refusing to create a worktree.

**What the plan now does:** if the slug still fails `_validate_worktree_name`, `create` **aborts non-zero** instead of proceeding unleased.

**Why:** measured — `tr '/' '-'` does not make every valid git branch name lease-keyable. `feat+foo`, `fix(scope)/bar`, `user@host/topic`, `a,b/c`, `wip;x`, `ci/rule=metrics` all still fail it. The issue's AC2 ("the lease key … passes `_validate_worktree_name`") is therefore **not satisfiable** by the stated fix alone. The plan's own v1 answer was warn-and-proceed; CTO and CPO **independently** rejected it, because proceeding with a warning permits exactly the state the issue exists to eliminate — an unleased worktree the reaper may delete — and merely narrows the input class that reaches it. A non-technical operator does not read shell sentinels.

**Blast radius:** zero for the current corpus — all 29 slash-bearing origin branches, and all origin branches, pass. No branch that works today begins failing.

**If the operator disagrees:** the correct lever is to widen the allowlist, not to downgrade the abort to a warning.

---

## DC-2 — Scope in a slug-collision guard (FR5)

**Class:** user-challenge (scope addition)

**Operator's stated direction:** not mentioned in the issue.

**What the plan now does:** `create_worktree`'s existing-directory arm compares the existing worktree's actual ref against the requested branch and **aborts** on mismatch instead of switching.

**Why:** the divergence is **live on this machine today** — `.worktrees/fix-6808-heartbeat-wire` is checked out on branch `docs-redaction-fails-open` (measured). Under `--yes`, the mode `one-shot`/`work` run in, that arm switches **automatically and unannounced**, placing the session on a branch it did not ask for. Slugification adds a second route into the same arm. CTO and CPO both required abort-not-reuse.

**Cost:** a few lines, contained in one arm.

---

## DC-3 — Scope in reaper hardening (Phase 3b)

**Class:** user-challenge (scope addition)

**Operator's stated direction:** the issue scopes the fix to the producer (`create_worktree` et al.) and does not ask for changes to `cleanup_orphan_worktree_dirs`.

**What the plan now does:** adds two skip-and-warn guards to the reaper — a **descendant guard** (skip a directory that contains a registered worktree) and a **`$PWD` guard** (skip the directory the session is standing in).

**Why:** fixing the producer stops *new* nesting but does **nothing** for a worktree already nested on disk — that directory stays reapable at the next session start, and the plugin is already installed on an external alpha tester's machine. CTO and CPO independently reframed this from "defense-in-depth, deferrable" to **remediation**. Separately, the reaper's missing `$PWD` guard is a genuine second defect surfaced by this investigation (measured: `cleanup_merged_worktrees` has the guard, the orphan reaper does not).

**Safety:** both guards are skip-only. Neither can cause a deletion that does not already happen, so the change is strictly non-destructive relative to current behavior.

**Alternative rejected:** an automatic migration of existing nested directories, which would have to `mv`/`rm` live worktrees — the exact operation whose miscarriage caused this issue.

---

## DC-4 — `remove_worktree` does not exist; `copy_env_to_worktree` substituted

**Class:** mechanical (premise correction — recorded for transparency, not for decision)

**Operator's stated direction:** "give `switch_worktree` / `remove_worktree` the same slugification symmetry."

**Reality (measured):** there is no `remove_worktree` function and no `remove` verb in the CLI dispatch. Enumerating function definitions yields `switch_worktree`, `copy_env_to_worktree`, and `cleanup_worktrees`.

**What the plan does:** applies the symmetry to `switch_worktree` and to `copy_env_to_worktree` — the latter constructs `$WORKTREE_DIR/$name` from the same operator input and was not named in the issue.

---

## Not scoped in (confirmed)

- **#7409** (session-state lease library unresolvable from plugin-cache installs) — explicitly out of scope per the issue; ships separately. Interaction noted in the plan: on an install with no lease library the reaper fails **closed**, so this fix's lease-key correctness is moot there until #7409 lands. The *nesting* half of the defect is independent of the lease layer, so this fix retains its value regardless.
- **`plugins/soleur/skills/archive-kb/scripts/archive-kb.sh`** — carries a fourth, independent copy of `tr '/' '-'` (verified). Separate process, no path-safety role. Left untouched; named in the PR body so a future transform edit knows the full call set.
