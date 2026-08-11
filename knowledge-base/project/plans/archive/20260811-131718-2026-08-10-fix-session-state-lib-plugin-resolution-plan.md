---
title: "fix(git-worktree): ship the session-state lock/lease library inside the plugin and resolve it plugin-root-relative"
date: 2026-08-10
type: fix
issue: 7409
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
status: reviewed
---

# fix(git-worktree): session-state lease library is unresolvable from plugin-cache installs

Closes #7409.

> **Lane note:** no `spec.md` existed for this branch at plan time, so `lane:` could not be carried forward. Defaulted to `cross-domain` (TR2 fail-closed).
>
> **Review status:** revised after CTO domain review, a scoped strong-model advisor consult, and a 3-agent plan-review panel (architecture-strategist, code-simplicity-reviewer, spec-flow-analyzer). Two blocking AC defects and two false rationale grounds were found in the first draft and are fixed here; the destination changed as a result. See [Recorded decision challenges](#recorded-decision-challenges).

## Overview

`.claude/hooks/lib/session-state.sh` implements Soleur's cross-session concurrency layer — `acquire_lock` / `with_lock` / `acquire_lease` / `release_lease` / `is_lease_active` / `sweep_orphan_leases` / `headless_or_stderr`. It is the only thing distinguishing a live session from an abandoned one before `worktree-manager.sh cleanup-merged` performs an **unrecoverable destructive** operation: delete the worktree, the local branch, the remote branch, and close the PR.

That library **is not shipped in the plugin**. The marketplace ships only `./plugins/soleur`, so every marketplace-installed user runs with the concurrency layer absent, silently replaced by no-op stubs.

This plan **moves** the library into the plugin and replaces the five-level path walk with a **plugin-internal, layout-invariant** resolution that depends on no environment variable.

### Measured reproduction

```
# 1. worktree-manager.sh from a simulated cache install, run in a NON-Soleur user repo:
SOLEUR_WORKTREE_LEASE_LIB_MISSING path=<cache>/soleur/soleur/9.9.9/skills/git-worktree/scripts/../../../../../.claude/hooks/lib/session-state.sh reason=fail-closed-no-reap

# 2. The SKILL.md form a marketplace user's agent literally executes:
$ bash .claude/hooks/lib/session-state.sh release_lease "$(basename "$PWD")"
bash: .claude/hooks/lib/session-state.sh: No such file or directory
exit=127
```

The real install at `~/.claude/plugins/cache/soleur/soleur/0.0.0-dev/` contains `skills/ scripts/ hooks/ agents/ commands/ docs/ test/`, nests **12 path-components deep**, and has **no `.claude/` and no `session-state.sh` at any depth**.

### The two resolution problems

| | Problem | Consumer | Fix |
|---|---|---|---|
| **P1** | `worktree-manager.sh` → library | in-plugin shell script | Co-locate + `$SCRIPT_DIR`-relative. **No env var.** Deterministic. |
| **P2** | `SKILL.md` → library | agent-executed prose | The **same** `${CLAUDE_PLUGIN_ROOT:-<anchor>}` form every Soleur skill invocation already uses, + degrade-open. |

**The destructiveness gradient is the organising principle.** The reap path is **destructive** → stays **fail-closed** (P1). The SKILL.md sites wrap **advisory** operations (`gh pr merge --squash --auto`, `release_lease`) → **degrade open, loudly**. Hard-failing there converts exit 127 into a prettier exit 127 and leaves the marketplace user equally broken.

**P2 is a one-liner, not a resolver chain.** `git-worktree/SKILL.md:173` already invokes the script as `bash ${CLAUDE_PLUGIN_ROOT:-./plugins/soleur}/skills/git-worktree/scripts/worktree-manager.sh …`. Post-move the library sits behind the *identical* anchor. If that anchor does not resolve, the user cannot run **any** Soleur skill — #7409 is not the bug they have. So a bespoke 4-arm chain plus an extracted resolver would invent a seventh competing pattern for an unreachable case.

## Deepen-Plan Research Insights

**Deepened:** 2026-08-10. Gates run: 4.4 (precedent-diff), 4.5, 4.55, 4.6, 4.7, 4.8, 4.9, 4.10. Findings below are *measurements*, not recommendations — each was produced by running the gate or the AC against the real tree.

**Gate results**

| Gate | Result |
|---|---|
| 4.4 Precedent-diff (pattern-bound behavior) | **Precedent exists and is adopted.** `$SCRIPT_DIR`-relative sourcing of a shipped plugin helper is already the canonical form: `plugins/soleur/hooks/stop-hook.sh:14` does `source "$SCRIPT_DIR/../scripts/resolve-git-root.sh"`, and `.openhands/hooks/stop-hook.sh:18-25` shows the repo-side consumer form with an `if [[ -f ]]` graceful arm. The plan's P1 resolution is the same shape — not a novel pattern. |
| 4.5 Network-outage | **Not triggered.** No SSH/connectivity symptom; no `provisioner`/`connection` block in scope. |
| 4.55 Downtime & cutover | **Not triggered.** No serving surface goes offline: no infra reboot/replace, no lock-taking DDL, no router/deploy restructure. |
| 4.6 User-Brand Impact | **HALT FIRED, then fixed** — see below. |
| 4.7 Observability | **Pass.** All 5 fields present with non-placeholder values; `discoverability_test.command` is `ssh`-free. |
| 4.8 PAT-shaped variable | **Pass.** Zero matches across all four PAT patterns. |
| 4.9 UI wireframe | **Not triggered.** No UI-surface path in Files to Create/Edit. |
| 4.10 Encryption posture | **Not triggered.** No `.tf`, migration, cloud-init, docker-compose, store class, or new cross-component connection. |

**Two defects found by running gates/ACs rather than reading them**

1. **The plan would have FAILED `/soleur:preflight` Check 6 at ship time.** Step 6.5 extracts the threshold with `grep -E '^[[:space:]]*[-*][[:space:]]+\*\*Brand-survival threshold:\*\*'` — a **bullet-form** requirement. The first draft's non-bulleted `**Brand-survival threshold:** …` yielded an empty `THRESHOLD_LINE` and a hard FAIL. Fixed to canonical bullet form and re-verified by running Step 6.5's own regex, which now returns `PASS: threshold = single-user incident`. Generalisable: the canonical bullet is a **parser contract**, not styling.

2. **AC6 would have gone red on a line the plan never listed.** Running AC6's grep against the real tree returns 9 in-scope files, including `lease-protects-active.test.sh:128` — a CLI-usage comment carrying the old path. Phase 1.5 and Files-to-Edit now list it. Generalisable: an AC that greps a scope must be **executed against the current tree at plan time**; the returned file list *is* the Files-to-Edit list for that pattern.

**Citation verification (all resolved live, none from memory)**

- Rule IDs cited: `cq-write-failing-tests-before`, `cq-assert-anchor-not-bare-token` — both confirmed ACTIVE in `AGENTS.md`; neither appears in `scripts/retired-rule-ids.txt`.
- Issues/PRs: #7409 `OPEN` (unresolved, correctly targeted) · #5454 `CLOSED` · #3689 `MERGED` · #6222 `OPEN` (correctly cited as the still-open residual class) · #7278 `CLOSED`. The #5454 attribution is taken from the code itself — `worktree-manager.sh` carries an inline `FAIL CLOSED (#5454)` comment — not from recollection.
- ADR ordinal derived from freshly-fetched `origin/main` (`ADR-174` highest), and flagged provisional.
- GitHub labels for the deferrals (`domain/engineering`, `type/bug`) confirmed to exist.
- AC grep scopes are `.claude/hooks/lib/` and `plugins/soleur/skills/` — neither contains `knowledge-base/`, so no AC self-matches this plan's own prose.
- `plugins/soleur/skills/{plan,review}/SKILL.md` confirmed **not** matched by AC6's pattern (they carry the bare basename only), so the Phase 1.6 do-not-touch list cannot false-fail the AC.

## Premise Validation

| Premise (from #7409) | Check | Verdict |
|---|---|---|
| #7409 open, unresolved | `gh issue view 7409` → `OPEN`, no closing PRs | Holds |
| Five-level walk at `worktree-manager.sh:48` | Read | Holds |
| Walk misses in a cache install | Simulated + real-install `find` | Holds |
| Library not shipped | `find ~/.claude/plugins/cache/soleur -name session-state.sh` → empty | Holds |
| Coupling is file-resolution only | `_session_state_root()` anchors to `git rev-parse --git-common-dir`; no repo-relative reads at load | Holds |
| "Five other skills" | `git grep` over `plugins/` | **STALE — six** (R1) |
| A SKILL.md scope note may exist | grep → empty | **None exists**; fix lands, so none is added |

## Research Reconciliation — Spec vs. Codebase

| Claim | Reality | Response |
|---|---|---|
| **R1.** "Five other skills — work, ship, merge-pr, product-roadmap, schedule" | **Six.** `one-shot/SKILL.md:115` omitted. Plus `git-worktree/SKILL.md:320` carries its own `source … && acquire_lease` instruction. **Seven** invocation sites total. | All seven in scope. |
| **R2.** Framed as "no lock/lease layer" | Worse: `bash <missing>` exits **127**. On `ship`/`merge-pr`/`product-roadmap`/`schedule` the wrapped command is `gh pr merge --squash --auto`, so for an installed user **the merge is never queued**. A hard functional failure. | Threshold `single-user incident`. |
| **R3.** Order "CLAUDE_PLUGIN_ROOT → plugin-relative → repo-relative" | Measured UNSET in the CLI Bash env, but **CONFOUNDED** (R8). | **Order inverted for P1**, which consults no env var and so does not wait on R8. |
| **R8.** *(confound — advisor catch)* | The plugin **is** a marketplace install here, but the measuring skill was served from the **repo** copy (`Base directory: <repo>/plugins/soleur/skills/plan`). CC may inject the var only for cache-served skills. | Measured **out of the critical path** (Phase 7). Its only output is whether Deferral 1 is filed. |
| **R4.** Duplicate with a drift gate | `plugins/soleur/AGENTS.md:68-80` permits duplication only for a pure importable `lib/*.mjs` under a logic-parity guard. A 590-line `flock`/fd primitive is the worst candidate — drift is silent and fails **open**. | **MOVE.** No drift gate. |
| **R6.** *(discovered)* | `.claude/hooks/lib/session-state.test.sh` (34 KB) is an **ORPHAN**. Verified by expanding the runner's globs **in bash**: `test-all.sh:764` reaches `.claude/hooks/*.test.sh` flat only. **The lease library's own suite has never gated CI** — how the #5454 vacuous-green class survived. | Test relocates to an auto-globbed path; AC asserts it runs. |
| **R7.** *(discovered, then DOWNGRADED by review)* | Moving the file **does** drop it from the ADR-156 `eval` ban (`hook-input-contract.test.sh:377` finds only under `.claude/hooks` + `.openhands/hooks`; carve-out `:374`). **But the `EXEC_SURFACE_GLOBS` half is NOT a narrowing** — that lint targets the `gh pr\|issue list --search` class, and `session-state.sh` contains **zero** such probes (measured). | A1: real, fixed + membership assertion. EXEC_SURFACE_GLOBS: reframed as a **pre-existing gap closed opportunistically**, with **no** mutation AC (unconstructible). |
| **R9.** *(architecture catch)* | `plugins/soleur/test/c4-model-freshness.test.sh` **byte-diffs** committed `model.likec4.json` against a fresh render, pinned in `ci.yml:699`. Editing `model.c4` without regenerating is a **guaranteed CI red**. | `model.likec4.json` + `scripts/regenerate-c4-model.sh` added to scope. |
| **R10.** *(architecture catch — my own false grounds)* | The first draft rejected `plugins/soleur/scripts/` citing `AGENTS.md:182`, which is **skill-scoped** (under `## Skill Compliance Checklist` → `### Reference Links`), not about top-level `scripts/`. It also dated `plugins/soleur/lib/` to 2026-08-09; actual creation is **2026-07-11** (`766199eda`). Both grounds **void**. | Destination re-decided on surviving grounds → `plugins/soleur/scripts/lib/`. |

## User-Brand Impact

- **If this lands broken, the user experiences:** `cleanup-merged` reaping a worktree a live session is working in — working tree, local branch, remote branch deleted and the PR closed. Hours of unpushed work gone mid-run; the tell is failures reading `fatal: Unable to read current working directory`. Secondarily, `ship`/`merge-pr` exit 127 and the PR is silently never queued for auto-merge.
- **If this leaks, the user's workflow is exposed via:** not a confidentiality surface. The lease file records `pid`, `ppid`, `skill`, `started_at`, `hostname` on the user's own disk, never transmitted. No new egress, store, or third party.
- **If this lands CORRECTLY, the user experiences (added at review):** the first session after updating would, without a hold, sweep every accumulated merged/gone worktree at once — none can hold a lease, because all of them were created while the lease layer was unreachable. Individually those reaps may be right; the objection is that arming the capability and exercising it in bulk would be the same event, and `git status --porcelain` does not list ignored paths, so a worktree holding only `.env.local` reads clean and the reap's `--force` retry deletes it. Mitigated by a one-time dry pass (`SOLEUR_WORKTREE_REAPER_ARMED`) that reports and stamps rather than deletes.
- **Brand-survival threshold:** `single-user incident` — one marketplace user losing a branch + PR to a concurrent reap is unrecoverable, and is exactly what Soleur's parallel-worktree pitch promises to prevent. `user-impact-reviewer` runs at review time.

> **Canonical bullet form is load-bearing, not styling.** `/soleur:preflight` Check 6 Step 6.5 extracts this with `grep -E '^[[:space:]]*[-*][[:space:]]+\*\*Brand-survival threshold:\*\*'`. A non-bulleted `**Brand-survival threshold:** …` line does **not** match, yields an empty `THRESHOLD_LINE`, and **FAILs the ship-time gate**. This plan's first draft had exactly that defect; it was caught by running the gate at deepen time rather than at ship time.

## Architecture Decision (ADR/C4)

### ADR

**Create `ADR-177: Shared bash primitives ship inside `plugins/soleur/` and resolve plugin-root-relative`.**

> **Ordinal PROVISIONAL.** `ADR-174` is highest on `origin/main`. `/ship`'s collision gate re-verifies. On renumber, sweep `knowledge-base/project/{plans,specs}/feat-one-shot-7409-session-state-lib-resolution/` for the old ordinal.

1. **Location.** A shared bash primitive consumed by shipped plugin code lives **inside `plugins/soleur/`**, never in `.claude/hooks/lib/` (Soleur's own repo-development harness, not shipped). Destination: **`plugins/soleur/scripts/lib/session-state.sh`**.

   Grounds, all verified: (a) `plugins/soleur/scripts/` is the plugin's established sourceable-shell-helper home — `resolve-git-root.sh` lives there and `plugins/soleur/hooks/stop-hook.sh:14` already sources it `$SCRIPT_DIR`-relative; (b) the `lib/` segment keeps the ADR-156 A1 carve-out `*/lib/session-state.sh` (`hook-input-contract.test.sh:374`) matching with **zero edit**; (c) `<x>/scripts/lib/` is an established repo pattern (`scripts/lib/`, `apps/web-platform/scripts/lib/`); (d) nested directories demonstrably ship (the live install nests 12 deep).

   *Rejected `plugins/soleur/hooks/lib/`* (first draft): the library is consumed by skills and repo scripts, not only hooks, so `hooks/` is a cohesion misnomer — and its sole surviving advantage (the A1 suffix) is equally satisfied by `scripts/lib/`. State this explicitly in the ADR: `plugins/soleur/hooks/` is Claude Code's **hook-registration** directory (the install carries `hooks.json` beside three `*-hook.sh`); placing a general concurrency library there would rest on CC registering hooks only via explicit `hooks.json` entries.

2. **Resolution order**, by consumer class:
   - **In-plugin shell (`worktree-manager.sh`): `$SCRIPT_DIR`-relative, first and only** — `$SCRIPT_DIR/../../../scripts/lib/session-state.sh`. Identical in repo and cache install. **No environment variable.** Load-bearing: an env-dependent primary would re-introduce exactly the invariant ADR-093's amendment had to pin at `buildAgentEnv`, which does not hold on the CLI.
   - **Agent-executed SKILL.md:** `${CLAUDE_PLUGIN_ROOT:-<preserved-anchor>}/scripts/lib/session-state.sh` — the same anchor form already used for every Soleur skill invocation (ADR-093 Slices B/C/D). Terminal disposition set by the **destructiveness gradient**, not a blanket rule.
   - **Repo-only consumers** (`.claude/hooks/**`, `scripts/lib/`): reach into `plugins/soleur/scripts/lib/` relative to their own location.
3. **Single source of truth — MOVE, not duplicate.** No mirror, no drift gate.
4. **Security posture (state explicitly).** Post-move a marketplace user loads the library from `~/.claude/plugins/cache/`, i.e. **outside** the untrusted connected workspace — a posture *improvement* consistent with ADR-093, not a weakening.
5. **Standardise the exact snippet in the ADR**, including the `$SS_LIB` assignment itself (the assignment *is* the defect; a snippet that shows only the `if` around it elides the hard part) and a one-line note on the `600` contention timeout replicated across the four `with_lock` sites.

**Relationship to ADR-093.** ADR-093 §Consequences declares an OPEN residual (#6222): paths `${CLAUDE_PLUGIN_ROOT}` *cannot* anchor because they live outside `plugins/soleur/`. This is that shape; ADR-177 resolves this member by **relocating the file so it becomes anchorable**. Add a cross-reference line to ADR-093 §Consequences.

### C4 views

Checked against all three model files (`model.c4`, `views.c4`, `spec.c4`), read in full.

- **External human actors:** none new — a marketplace user is the existing `founder` role.
- **External systems/vendors:** none. The plugin cache is local filesystem state, not an external system.
- **Containers/data stores:** none. The lease store is unmodeled local scratch by design (ADR-009's 2026-07-15 amendment).
- **Access relationships that change: one edge, TWO falsified descriptions.**
  1. `plugin` (element `platform.plugin`) is described as *"plugins/soleur/ — skills, agents, and knowledge base"*; it now also ships the shared bash concurrency primitives. **Falsified — correct it.**
  2. The `hooks` container (element `platform.engine.hooks`) enumerates *"TWO HARNESSES: `.claude/hooks/` … and three blocking PreToolUse mirrors in `.openhands/hooks/`"*, written while the primitives lived inside `.claude/hooks/`. It now sources its concurrency layer from a third, shipped location. **Also falsified — correct it.**
  3. Add a `hooks -> plugin` edge ("Sources the shared session-state lock/lease primitives from the deployed plugin root"). Both endpoints (`platform.engine.hooks`, `platform.plugin`) are already in the `containers` view's include list, so the edge renders with no new `include`.
- **Regenerate `model.likec4.json`** via `bash scripts/regenerate-c4-model.sh` — `c4-model-freshness.test.sh` byte-diffs it and is pinned in CI. `model.c4` is hand-authored (no generated header), so the hand edit is safe.

### Sequencing

ADR authored in this PR describing the target state, `Status: Accepted`. Nothing soak-gated.

## Observability

Existing markers (measured — do not duplicate): `SOLEUR_WORKTREE_LEASE_LIB_MISSING` at load (`worktree-manager.sh:62`) and `SOLEUR_WORKTREE_LEASE_ACQUIRE_FAILED … reason=file-absent` (`:1414`). `_acquire_worktree_lease` **early-returns 0** when the lib is missing (`:1349-1351`, deliberate), and every call site is `|| true`.

**Consequence, and why AC3 is shaped as it is:** `--yes create` exits **0 in both the broken and fixed states**. Exit code carries no information; the lease **FILE** is the only discriminator.

```yaml
liveness_signal:
  what: "SOLEUR_WORKTREE_LEASE_LIB_OK path=<resolved> — a POSITIVE marker, so 'no signal' is distinguishable from success. Existing MISSING/ACQUIRE_FAILED markers unchanged."
  cadence: "once per worktree-manager.sh invocation"
  alert_target: "operator terminal (stdout). Layer 7 — a customer's self-hosted CLI; there is no server-side sink for an installed user's local run, and inventing one would be a new egress surface."
  configured_in: "plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh, library-resolution block"
error_reporting:
  destination: "stdout (load-bearing: stderr is invisible under `claude --bg`, the mode cleanup-merged runs in — worktree-manager.sh:60-62)"
  fail_loud: true
failure_modes:
  - mode: "Library unresolvable from a plugin-cache install (the #7409 defect)"
    detection: "absence of ..._OK / presence of ..._MISSING on stdout, plus the on-disk lease FILE"
    alert_route: "operator terminal; asserted in CI by the cache-install suite"
  - mode: "acquire_lease silently writes no lease file (#5454 vacuous-green class)"
    detection: "assert the lease FILE carries pid= and a NON-DEFAULT expected_duration_min — never is_lease_active (fail-closed stub returning 'active' when the library is missing)"
    alert_route: "CI: cache-install suite + lease-protects-active.test.sh scenario 3"
  - mode: "ADR-156 eval-ban coverage silently dropped by the relocation"
    detection: "A1 membership assertion — fail if the enumerated scan set contains no path ending /lib/session-state.sh"
    alert_route: "CI: hook-input-contract.test.sh"
logs:
  where: "$(git rev-parse --git-common-dir)/soleur-session-state/logs/<PPID>.log via headless_or_stderr"
  retention: "operator-local; rotated by .claude/hooks/lib/log-rotation.sh (repo-side only)"
discoverability_test:
  # Revised at ship time. The first draft named the full lease suite, which is
  # the right REGRESSION gate and the wrong DISCOVERABILITY probe: it measured
  # 13s against preflight Check 10's 15s cap (a 2s margin that flakes on a
  # loaded machine), and its expected_output was a prose sentence that cannot
  # substring-match real stdout — so the check would have failed on mismatch
  # even when the fix was correct. A discoverability test is what an operator
  # runs to answer "is the layer live here?", so it must be fast and have a
  # machine-checkable expectation.
  command: bash plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh list
  expected_output: SOLEUR_WORKTREE_LEASE_LIB_OK
  regression_gate: "bash plugins/soleur/skills/git-worktree/test/lease-protects-active.test.sh (40 assertions incl. the cache-install, reaper-refusal, anchor-hop, interop and arming-hold scenarios)"
```

## Domain Review

**Domains relevant:** Engineering

### Engineering (CTO)

**Status:** reviewed

**Assessment:** Endorsed **MOVE** as the only option giving resolution determinism with no env-var invariant, and flagged four items now folded in: the ADR-156 scan-set regression needs a **membership assertion** (not just extended roots); the terminal fallback arm needs an explicit disposition; the orphan-suite hazard must be re-verified for the *destination*; and the delivery question ("what makes an installed user receive this?") must be answered given the frozen `0.0.0-dev` sentinel.

**Dissents carried:** two-PR split; ADR-093 amendment instead of a standalone ADR; and the CTO's `hooks/lib/` destination recommendation, which the plan-review panel subsequently showed rested on a misread rule. See [Recorded decision challenges](#recorded-decision-challenges).

### Product/UX Gate

Not applicable. The mechanical UI-surface override did not fire — no path in Files to Create/Edit matches `components/**/*.tsx`, `app/**/page.tsx`, `app/**/layout.tsx`, or any `ui-surface-terms.md` term. **Product: NONE.**

## Open Code-Review Overlap

**None.** Queried all 64 open `code-review` issues and searched each body for every planned path. Zero matches.

## GDPR / Compliance Gate

Skipped. No schema, migration, auth flow, API route, or `.sql`. Expansion triggers checked: (a) no LLM/external-API processing of operator data; (b) threshold *is* `single-user incident` but no processing activity or data field is introduced — the lease file's `hostname`/`pid` already exist and stay local; (c) no cron reading `learnings/`/`specs/`; (d) the plugin is a distribution surface but this ships only shell code. No Article 30 entry.

## Infrastructure (IaC)

Not applicable — no server, service, cron, secret, DNS record, vendor account, or persistent runtime process.

## Encryption Posture

Not applicable — no persistent store and no new cross-component connection.

## Implementation Phases

### Phase 0 — Preconditions

0.1 Re-verify the highest ADR ordinal on freshly-fetched `origin/main`; renumber and sweep this feature's artifacts if 175 is taken.

0.2 Answer the delivery question: **what makes an installed user actually receive this fix?** `plugin.json` version is a frozen sentinel `0.0.0-dev` (`plugins/soleur/AGENTS.md:22`), so the cache directory name never changes. Record the update mechanism; if users do not auto-update, say so in the PR body. A fix nobody receives is not a fix.

> **Packaging is already settled — do not re-litigate it as a precondition.** `marketplace.json` `"source": "./plugins/soleur"` is a directory copy with no manifest, and `version-bump-and-release.yml:6,38` filter on `plugins/soleur/**`. Nested directories ship (the live install nests 12 deep). There is no flat-fallback branch.

### Phase 1 — Move the library and repoint every consumer

One PR, and Phases 1-2 are **one commit** — a separate "pure rename" commit was cut because Phase 1.2 already needs a carve-out for the test's sibling-path line, and byte-identity is verified on the final tree instead (AC10).

1.1 `git mv .claude/hooks/lib/session-state.sh plugins/soleur/scripts/lib/session-state.sh`

1.2 `git mv .claude/hooks/lib/session-state.test.sh plugins/soleur/test/session-state.test.sh`
   - Destination is `plugins/soleur/test/`, **not** `scripts/lib/`, because `test-all.sh:764` globs `plugins/soleur/test/*.test.sh` and does **not** glob `plugins/soleur/scripts/lib/*.test.sh`. Landing it beside the library moves it from one orphan home to another (R6).
   - The suite has **two** `SCRIPT_DIR`-derived paths, not one — enumerate both:
     - `:10` `HELPER="$SCRIPT_DIR/session-state.sh"` → `$SCRIPT_DIR/../scripts/lib/session-state.sh`
     - `:785` `WM="$(cd "$SCRIPT_DIR/../../.." && pwd)/plugins/soleur/skills/…"` — `../../..` resolves to repo root from **both** `.claude/hooks/lib/` and `plugins/soleur/test/`, so it survives **by coincidence**. Leave it only after confirming that; note it explicitly so a future destination change does not silently point it at the wrong tree.

1.3 **Byte-identity constraint (behavioral, not ceremonial).** `session-state.sh` content must be unchanged apart from the old-path comments in 1.5, so old and new worktrees agree on lease format (R-2 / T7). Verified on the final tree by AC10, **not** by `git show --stat -M` — rename detection is a diff-renderer heuristic, not a stored property.

1.4 Repoint consumers. All arithmetic verified against the real tree:

| File:line | Becomes |
|---|---|
| `worktree-manager.sh:48` | `$SCRIPT_DIR/../../../scripts/lib/session-state.sh` |
| `worktree-manager.sh:67` | recovery text (old `git checkout origin/main -- .claude/hooks/lib/…` will fail post-merge) |
| `worktree-manager.sh:1372` | comment "reached across the plugin → .claude/hooks boundary" — **now false**, rewrite |
| `.claude/hooks/lib/incidents.sh:18` **and** `:19` | `# shellcheck source=` directive **and** the `source` line → `../../../plugins/soleur/scripts/lib/session-state.sh` |
| `.claude/hooks/lib/log-rotation.sh:63` **and** `:64` | same pair |
| `.claude/hooks/pre-merge-rebase.sh:27` **and** `:32` | same pair → `../../plugins/soleur/scripts/lib/session-state.sh` |
| `scripts/lib/test-contention.sh:47` | `$_tc_lib_dir/../../plugins/soleur/scripts/lib/session-state.sh` (keeps its env override + `LOCK_UNAVAILABLE` degradation) |
| `plugins/soleur/test/concurrent-ship.test.sh:12` | `$REPO_ROOT/plugins/soleur/scripts/lib/session-state.sh` |
| `plugins/soleur/skills/git-worktree/test/lease-protects-active.test.sh:14` | same |
| `plugins/soleur/test/worktree-manager-safe-branch-sanitization.test.sh:209` | `$SCRIPT_DIR/../scripts/lib/session-state.sh` |

**Each `source` line has a paired `# shellcheck source=` directive one line above.** Repointing one without the other leaves shellcheck resolving a dead path.

1.5 Prose sweep — stale after the move: `session-state.sh:266,362` (its **own** CLI-usage comments, which are the copy-source for the seven SKILL.md invocations), `session-state.test.sh:2,194,374`, **`lease-protects-active.test.sh:128`** (a CLI-usage comment — inside AC6's grep scope, so leaving it turns AC6 red; found by running AC6's grep against the real tree at deepen time), `session-state.sh`'s header citing `.claude/hooks/agent-token-tee.sh:160-170`, `.claude/hooks/pre-merge-auto-close-scan.sh:102`, `.claude/hooks/prod-write-defer-gate.sh:43`, `scripts/tmpfs-guard.sh:31,804`, and `git-worktree/SKILL.md:179` (describes `sync_bare_files` as a `plugins/soleur/hooks/*` whitelist; it is actually a full `checkout-index -a` mirror — already stale, made more misleading by this change).

1.6 **DO NOT TOUCH.** These use the **bare basename** `session-state.sh` with no path and need no edit; a reflexive sweep here reintroduces the #3689 hook-bypass class the first two files exist to warn about:
   - `plugins/soleur/skills/plan/SKILL.md:962`, `plugins/soleur/skills/review/SKILL.md:1339`
   - `.claude/hooks/pre-merge-rebase-parity.test.sh:150,157`, `pre-merge-rebase.test.sh:415`, `prod-write-defer-gate.test.sh:199,218` — these **assert** that the hooks still match the wrapped form; editing them breaks the gate.

### Phase 2 — SKILL.md sites (seven, two shapes)

Use the established anchor, not a bespoke chain: `${CLAUDE_PLUGIN_ROOT:-<preserved-anchor>}/scripts/lib/session-state.sh`, preserving each site's existing anchor form per ADR-093's anchor-preservation rule.

**Four `with_lock` sites** — `merge-pr:260`, `product-roadmap:234`, `schedule:472`, `ship:1714` — get degrade-open:

```bash
SS_LIB="${CLAUDE_PLUGIN_ROOT:-<preserved-anchor>}/scripts/lib/session-state.sh"
if [[ -r "$SS_LIB" ]]; then
  bash "$SS_LIB" with_lock merge-main 600 -- <CMD>
else
  echo "SOLEUR_SESSION_STATE_LIB_MISSING path=$SS_LIB reason=running-unlocked"
  <CMD>
fi
```

**Two `release_lease` sites** — `one-shot:115`, `work:220` — have no wrapped command, so degrade-open means *do nothing*. A one-liner, **not** the if/else template:

```bash
bash "${CLAUDE_PLUGIN_ROOT:-<preserved-anchor>}/scripts/lib/session-state.sh" release_lease "$(basename "$PWD")" || true
```

**One `acquire_lease` site — `git-worktree:320` — is on the DESTRUCTIVE side of the gradient and must NOT be silently `|| true`.** This is a spec-flow catch that corrects the plan's own first classification. `release_lease` failing is inert (leases expire on their own window). `acquire_lease` failing means the worktree runs **unleased** — which, *after this PR*, is exactly the state a sibling `cleanup-merged` will reap. It must warn prominently:

```bash
SS_LIB="${CLAUDE_PLUGIN_ROOT:-<preserved-anchor>}/scripts/lib/session-state.sh"
if [[ -r "$SS_LIB" ]]; then
  source "$SS_LIB" && acquire_lease "<branch>" "<skill>" <minutes>
else
  echo "SOLEUR_SESSION_STATE_LIB_MISSING path=$SS_LIB reason=worktree-UNLEASED-and-reapable"
fi
```

**Why the split** (this reversed the first draft twice — once on advisor challenge, once on spec-flow's): the disposition follows what the operation *guards*. `with_lock`/`release_lease` are advisory — hard-failing leaves the marketplace user's merge unqueued and does not fix the population #7409 is about, so they degrade open. `acquire_lease` is the **acquisition of the protection itself**; degrading it open silently manufactures the exposure. It degrades open too (there is nothing else to do) but must never do so *quietly*.

> **This PR arms the reaper.** Pre-fix, a marketplace user's library is missing, so `is_lease_active(){ return 0; }` makes `cleanup-merged` refuse to reap **anything, ever**. Post-fix the library resolves and the destructive path goes live for that entire population **for the first time**. The refusal direction therefore needs its own test and AC in a cache layout (T3 / AC5) — it is not covered by the acquisition tests.

`product-roadmap/SKILL.md:234` documents `rc=99` contention semantics from the wrapper. The else-branch runs `gh pr merge` bare, where `rc=99` cannot occur — that prose needs a clause.

### Phase 3 — Preserve the ADR-156 eval ban

3.1 `.claude/hooks/hook-input-contract.test.sh:377` — add `$REPO_ROOT/plugins/soleur/scripts` to the A1 `find` roots. The carve-out at `:374` is suffix-matched `*/lib/session-state.sh` and needs **no edit** (verified for the new destination). **Also update A1's success message**, which reads `"A1 no eval under .claude/hooks/** or .openhands/hooks/** (2 fd-close lines allow-listed)"` — a green assertion naming a narrower scan set than it actually ran is the same evidence-vs-claim gap as R6/R7.

3.2 **Membership assertion** — A1 fails if the enumerated list contains no path ending `/lib/session-state.sh`. This is the durable half, not belt-and-braces: `find … 2>/dev/null` means **removing a root makes A1 report `ok`** — it fails silently-green, the exact #5454 shape. 3.1 alone is a one-time patch with no tripwire.

> A1 skips `*.test.sh` entirely (`:368`), so the test relocation is A1-irrelevant — do not spend an AC on it.

3.3 `plugins/soleur/test/components.test.ts` `EXEC_SURFACE_GLOBS` — add `plugins/soleur/scripts/**/*.sh` and `plugins/soleur/hooks/**/*.sh`. **This is opportunistic hygiene, not a regression this PR creates:** that lint targets the `gh pr|issue list --search` class and `session-state.sh` has **zero** such probes, so nothing is lost by the move. Verified: neither directory contains any `gh pr|issue list`, so the extension is green on arrival. **No mutation AC** — one cannot be constructed.

3.4 `scripts/lint-shell-capture-exit.baseline.txt:8,9` — repoint both entries. The linter scans `git ls-files '*.sh'` so the moved file stays scanned, but `fingerprint()` keys on the path; a stale baseline turns two baselined findings into two new unbaselined offenders.

3.5 Confirm the shipped-surface `eval` exposure is a non-event. Measured at plan time: `skill-security-scan/scripts/check-codeexec.sh:3` reads **SKILL.md content on stdin**, so a shipped `.sh` is outside its surface; `plugins/soleur/AGENTS.md` carries no shipped-surface `eval` prohibition. **Expected: no new finding.** If one appears, allowlist the exact fd-close string — never rewrite the flock fd handling.

### Phase 4 — Tests (failing first, per `cq-write-failing-tests-before`)

4.1 **Cache-install scenario, added to `plugins/soleur/skills/git-worktree/test/lease-protects-active.test.sh`** (rather than a new file — that suite already stands up the bare-repo + `origin/<from>` fixture this needs, saving ~100 LOC of duplicated setup; `test-all.sh:764` globs it either way):
   - `mktemp -d`; build `<tmp>/cache/<mkt>/soleur/<ver>/` and `cp -r plugins/soleur/.` into it. **Copy only `plugins/soleur/`** — copying the repo makes the test vacuous, because the bug *is* the absence of everything outside that directory. Assert `find <cache> -name '.claude' -type d` is empty as a fixture precondition.
   - Run `--yes create feat-probe` from a throwaway repo with `SOLEUR_SKILL_NAME=one-shot SOLEUR_EXPECTED_DURATION_MIN=137`.
   - **Assert the lease FILE**: exists, and carries `pid=`, `skill=one-shot`, `expected_duration_min=137`.
   - **Do not assert the exit code** — `create` exits 0 in both states.
   - **Mutation arm (T2), in the suite:** delete the library from the cache fixture; the scenario must go RED.
   - Guard the `cd` (`if ( cd … && … )`): these suites run `set -uo pipefail` **without** `-e`, so an unguarded `cd` failure would run `--yes create` against the developer's real repo.

4.2 **Reaper-refusal scenario in a cache layout (T3) — the destructive direction.** This PR arms the reaper for the marketplace population, and nothing currently tests the refusal. From the same cache-only fixture: create a leased worktree, then run `cleanup-merged` from a **sibling** worktree, and assert the victim's directory **still exists**. Mutation-verify by clearing the lease file — the victim must then be reaped, proving the assertion is not vacuously green.

4.3 **SKILL.md-anchor hop (closes spec-flow P0-1).** Every other test invokes `worktree-manager.sh` by absolute path inside the fixture, which bypasses the exact link a marketplace user traverses. Add one scenario that invokes it **through the SKILL.md anchor form** — `bash "${CLAUDE_PLUGIN_ROOT:-./plugins/soleur}/skills/git-worktree/scripts/worktree-manager.sh" list` — with `CLAUDE_PLUGIN_ROOT` set to the cache fixture and cwd set to a **non-Soleur** repo, asserting it resolves and emits `..._OK`.

> **Scope note.** `git-worktree/SKILL.md` carries **23** such anchors and `work/SKILL.md:212` one more. This plan does **not** migrate them — they already use the repo-standard ADR-093 form, and if that form does not resolve, no Soleur skill runs at all (a far wider defect, [Deferral 1](#deferrals)). What 4.3 adds is *coverage of the hop*, so the plan can no longer be fully green while delivering nothing.

4.4 **Interop scenario (T6).** Two `worktree-manager.sh` copies — one old-path, one new-path — against a single `git-common-dir`: assert one's lease is honoured by the other's `is_lease_active`. AC10's byte-identity check proves the file is unchanged; it does **not** prove interop, which is what R-2 actually depends on.

4.5 Fix the pre-existing vacuity at `lease-protects-active.test.sh:253`, which asserts `expected_duration_min=240` — the default at both layers, so it passes whether or not the env var is read.

4.6 **Consumer-compatibility for the new stdout marker.** `SOLEUR_WORKTREE_LEASE_LIB_OK` adds an unconditional line to a stream that agents parse (skills instruct "cd into the worktree path printed by the script") and that sentinel greps read. Assert existing parsers still work, or emit the marker only when a `SOLEUR_DEBUG`-style variable is set. Decide and record; do not add an unconditional line to a parsed stream without checking.

### Phase 5 — Verification

5.1 `bash scripts/test-all.sh` — full suite; assert `plugins/soleur/test/session-state.test.sh` appears in the output (R6 — it never has). Take the reading from the same shard as any baseline: the glob loop is inside `if want_scripts` (`test-all.sh:744`).

5.2 `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`.

5.3 `bash scripts/regenerate-c4-model.sh`, then `bash plugins/soleur/test/c4-model-freshness.test.sh` and `./node_modules/.bin/vitest run test/c4-code-syntax.test.ts test/c4-render.test.ts` from `apps/web-platform`.

5.4 Re-run the Overview reproduction against the fixed tree; paste the output in the PR body.

### Phase 6 — Deferred measurement (NOT a precondition)

Settle the R8 confound: run a Soleur skill from a directory with **no** `plugins/soleur/` (so only the cache copy can resolve) and probe `echo "[${CLAUDE_PLUGIN_ROOT:-UNSET}]"` from inside it. Both branches produce the **same** committed artifact — `${CLAUDE_PLUGIN_ROOT:-<anchor>}` is correct either way, and arm 2 is needed regardless for dogfood — so this gates nothing in this PR. Its single output is whether [Deferral 1](#deferrals) is filed. Record the verdict in the spec so the next planner does not re-litigate it.

## Files to Create

- `plugins/soleur/scripts/lib/session-state.sh` *(via `git mv`)*
- `plugins/soleur/test/session-state.test.sh` *(via `git mv`)*
- `knowledge-base/engineering/architecture/decisions/ADR-177-shared-bash-primitives-ship-in-plugin.md`

## Files to Edit

- `plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh` — `:48`, `:67`, `:1372`, + the `..._OK` marker
- `plugins/soleur/skills/git-worktree/SKILL.md` — `:320` (Sharp Edge), `:179` (stale `sync_bare_files` description)
- `plugins/soleur/skills/{merge-pr:260, one-shot:115, product-roadmap:234, schedule:472, ship:1714, work:220}/SKILL.md`
- `.claude/hooks/lib/incidents.sh` `:18,:19` · `.claude/hooks/lib/log-rotation.sh` `:63,:64` · `.claude/hooks/pre-merge-rebase.sh` `:27,:32`
- `.claude/hooks/pre-merge-auto-close-scan.sh:102` · `.claude/hooks/prod-write-defer-gate.sh:43` *(prose)*
- `.claude/hooks/hook-input-contract.test.sh` — `:377` only (**not** `:374`, which is already correct)
- `scripts/lib/test-contention.sh:47` · `scripts/tmpfs-guard.sh:31,804` *(prose)* · `scripts/lint-shell-capture-exit.baseline.txt:8,9`
- `plugins/soleur/test/components.test.ts` — `EXEC_SURFACE_GLOBS`
- `plugins/soleur/test/concurrent-ship.test.sh:12` · `plugins/soleur/test/worktree-manager-safe-branch-sanitization.test.sh:209`
- `plugins/soleur/skills/git-worktree/test/lease-protects-active.test.sh` — `:14`, **`:128`**, `:253`, + the new cache-install / reaper-refusal / anchor-hop / interop scenarios
- `knowledge-base/engineering/architecture/decisions/ADR-093-…md` — cross-reference
- `knowledge-base/engineering/architecture/diagrams/model.c4` — `platform.plugin` + `platform.engine.hooks` descriptions, `hooks -> plugin` edge
- `knowledge-base/engineering/architecture/diagrams/model.likec4.json` — **regenerated**, not hand-edited

No `SKILL.md` `description:` frontmatter is edited (1800-word budget not engaged). No AGENTS.md rule is added (46000-byte cap not engaged).

## Acceptance Criteria

### Pre-merge (PR)

1. **AC1 — the move.** `test -f plugins/soleur/scripts/lib/session-state.sh && test ! -e .claude/hooks/lib/session-state.sh`.
   > Do **not** use `git grep -c 'session-state' -- .claude/hooks/lib/ == 0`: measured, a *correct* fix still returns `incidents.sh:4`, `log-rotation.sh:3` because their repointed `source` lines contain the filename. That AC fails a correct implementation.
2. **AC2 — layout-invariant resolution.** Assert **presence of the new shape**, not absence of the old, and make it a runnable boolean:
   ```bash
   grep -qE '^_SS_LIB=.*\$SCRIPT_DIR/\.\./\.\./\.\./scripts/lib/session-state\.sh' <wm> \
     && ! grep -qE '^_SS_LIB=.*\.claude' <wm>
   ```
   > A bare `grep -c … == 0` is a **proxy that passes on an empty match** — `grep -c` prints `0` *and exits 1* when awk emits nothing, so renaming `_SS_LIB`, indenting it, or moving resolution into a function all read green regardless of behavior. Presence-then-absence is the shape that cannot pass vacuously.
3. **AC3 — cache-install lease FILE.** The cache-install scenario passes: `<lease-root>/leases/feat-probe.lease` exists **as a file** and contains `pid=`, `skill=one-shot`, `expected_duration_min=137`.
   > **137, never 240.** Measured: `240` is the default at **both** `worktree-manager.sh:1354` (`${SOLEUR_EXPECTED_DURATION_MIN:-240}`) and `session-state.sh:194` (`${3:-240}`), so asserting it passes whether the env var is read or ignored — the #5454 vacuity class. `skill=one-shot` **is** discriminating (default `unknown`). Also fix the same defect at `lease-protects-active.test.sh:253`.
   > Asserting `is_lease_active` is **not** acceptable (fail-closed stub → vacuous pass).
4. **AC4 — mutation arm.** Deleting the library from the cache fixture turns AC3 RED, encoded as scenario T2 **inside the suite**.
5. **AC5 — the reaper still refuses (the destructive direction).** The T3 cache-layout scenario passes: `cleanup-merged` from a sibling worktree leaves a leased victim's directory intact, **and** reaps it once the lease file is cleared (mutation arm). Without this, the PR arms an unrecoverable operation for the whole marketplace population with zero coverage of the refusal.
6. **AC6 — all seven SKILL.md sites migrated, asserted by presence.** For each of the seven, the new anchored path `scripts/lib/session-state.sh` is present; **and** `! git grep -qE '\.claude/hooks/lib/session-state\.sh' -- plugins/soleur/skills/` (excluding the Phase 1.6 do-not-touch bare-basename files, which contain no path).
   > Do **not** rely on `git grep -c … == 0`: it prints nothing and **exits 1** on zero matches, so "returns 0" is never observable; and an absence-only assertion is satisfied by *deleting* a call site. Assert the new shape is there.
   - **AC6b — degrade-open on the four `with_lock` sites.** Each emits `reason=running-unlocked` on stdout **and** executes the wrapped command in the else-branch. Assert inside the snippet's own fence, not a whole-file grep (`cq-assert-anchor-not-bare-token`) — these files discuss the wrapper in prose and would satisfy a bare grep vacuously. Applies to the four `with_lock` sites **only**; the two `release_lease` sites have no wrapped command, and `git-worktree:320` (`acquire_lease`) asserts `reason=worktree-UNLEASED-and-reapable` instead.
   - **AC6c — the SKILL.md anchor hop resolves.** The Phase 4.3 scenario passes: invoking `worktree-manager.sh` through `${CLAUDE_PLUGIN_ROOT:-…}` from a non-Soleur cwd against the cache fixture emits `..._OK`. Every other AC enters by absolute path and cannot see this link.
7. **AC7 — ADR-156 scan set preserved.** `bash .claude/hooks/hook-input-contract.test.sh` passes, and its A1 enumerated set contains a path ending `/lib/session-state.sh`; removing `plugins/soleur/scripts` from the roots turns A1 RED (mutation-verified).
8. **AC8 — lint gates green.** `bun test plugins/soleur/test/components.test.ts` passes with the widened globs, and `python3 scripts/lint-shell-capture-exit.py --baseline scripts/lint-shell-capture-exit.baseline.txt` exits 0 with no new findings.
9. **AC9 — the orphan suite runs.** `bash scripts/test-all.sh` output names `plugins/soleur/test/session-state.test.sh` as a run suite.
10. **AC10 — byte-identity of the moved library.** `git show origin/main:.claude/hooks/lib/session-state.sh | diff - plugins/soleur/scripts/lib/session-state.sh` differs only in the Phase 1.5 comment lines. Immune to rename-detection heuristics; this is the property R-2/T7 actually depend on.
11. **AC11 — full suite green.** `bash scripts/test-all.sh` exits 0 (the gate's own invocation, not a hand-enumerated subset).
12. **AC12 — C4 rendered and fresh.** `bash plugins/soleur/test/c4-model-freshness.test.sh` passes (i.e. `model.likec4.json` was regenerated), plus `c4-code-syntax.test.ts` and `c4-render.test.ts`.
13. **AC13 — typecheck.** `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` exits 0.

### Post-merge (operator)

14. **AC14 — delivery confirmed.** Run, in Bash:
    ```bash
    claude plugin marketplace update soleur && claude plugin update soleur
    ```
    then re-run the Overview reproduction from `~/.claude/plugins/cache/soleur/soleur/0.0.0-dev/` and expect the `..._OK` marker.
    > Both verbs are **verified to exist** in Claude Code 2.1.226 (`claude plugin marketplace update [name]`, `claude plugin update <plugin>` — the latter prints "restart required to apply", harmless for an on-disk re-run). They do not appear in the top-level `claude plugin --help` list; do not conclude from that list that they are absent. `/plugin update` is a **slash command, not Bash**, and is not usable here.
    *Automation: feasible in-session via Bash once the merge lands — run it rather than deferring.*
15. **AC15 — bare-root mirror refreshed.** After merge, run `worktree-manager.sh sync-bare-files`. The bare root's on-disk copies are never updated by git, so it holds the **repointed** `.claude/hooks/lib/incidents.sh` while lacking the new target until this runs — and both source under `|| true`, i.e. they degrade **silently**. This is Phase 1's own hazard applied to the bare-root mirror.

## Test Scenarios

| # | Scenario | Expected |
|---|---|---|
| T1 | `--yes create` from a cache-only tree, non-Soleur repo | lease FILE with `pid=`/`skill=one-shot`/`expected_duration_min=137`. **No exit-code assertion** — `create` exits 0 in both states. |
| T2 | Same, library deleted from the fixture | RED — proves T1 is not vacuous |
| T3 | `cleanup-merged` from a sibling worktree while a lease is held, **cache layout** | victim survives; **and** is reaped once the lease file is cleared (mutation arm). This PR arms the reaper — the refusal direction needs its own coverage. |
| T3b | Invoke `worktree-manager.sh` via the `${CLAUDE_PLUGIN_ROOT:-…}` **SKILL.md anchor form** from a non-Soleur cwd | resolves, emits `..._OK`. Every other scenario enters by absolute path and cannot see this hop. |
| T4 | In-repo `--yes create` (existing scenario 3) | still passes — no dogfood regression |
| T5 | A1 with `plugins/soleur/scripts` removed from roots | RED |
| T6 | Old-path and new-path `worktree-manager.sh` against one `git-common-dir` | interoperate — one's lease honoured by the other's `is_lease_active` |

## Risks & Mitigations

| # | Risk | Mitigation |
|---|---|---|
| R-1 | **Fixing P1 alone delivers nothing** — a marketplace user reaches `worktree-manager.sh` only through a SKILL.md anchor. | P2 is **in scope**, which is why this is one PR. It uses the *same* anchor as every other Soleur skill invocation, so it is reachable exactly when anything else is. |
| R-2 | Mid-flight dogfood regression: an old worktree sources `.claude/hooks/lib/`, a new one sources `plugins/soleur/scripts/lib/`. | Safe **only** under byte-identity (AC10): `_session_state_root()` anchors to `git-common-dir`, so both read/write the same lease files in the same format (T6). **No lease-format change is permitted in this PR.** Old worktrees will keep printing the now-dead recovery instruction from `worktree-manager.sh:67`; self-resolving as worktrees turn over, worth a PR-body line. |
| R-3 | Transient window where a consumer path is stale | Fail-**safe**: a missing library makes `is_lease_active` return 0 → nothing is reaped. **Do not add a compat shim** at the old path — `_SOLEUR_SESSION_STATE_LOADED` (`session-state.sh:12-15`) makes a double-source harmless, but a shim re-introduces the two-homes ambiguity this PR removes. |
| R-4 | **Fix ships but nobody receives it — OBSERVED, not hypothetical.** Measured on the authoring machine: the marketplace install carries **64 skills against 96 in the repo** and has mtime **2026-05-10** — three months and 32 skills stale, while its `.in_use` marker is stamped today. It has been actively used and has received nothing. | Phase 0.2 records the mechanism; AC14 runs the two verified verbs post-merge. **State the staleness measurement in the PR body** — it is the honest answer to "does this reach anyone?", and no AC can cover a user who runs no update command. |
| R-5 | **This PR arms the reaper.** Pre-fix the marketplace population could never reap (missing lib → `is_lease_active` returns "active"); post-fix an unrecoverable operation goes live for them for the first time. | T3 + AC5 cover the refusal direction in a cache layout with a mutation arm. `acquire_lease` is classified on the destructive side (Phase 2) so a failure to acquire is never silent. |

## Alternatives Considered

| Option | Verdict |
|---|---|
| **A. MOVE to `plugins/soleur/scripts/lib/`** | **Chosen.** Sourceable-helper home + `lib/` keeps the A1 suffix carve-out matching + established `<x>/scripts/lib/` pattern + honest cohesion. |
| B. MOVE to `plugins/soleur/hooks/lib/` | Rejected. `hooks/` is CC's hook-**registration** directory and the library is consumed by skills and repo scripts too — a cohesion misnomer. Its only advantage (A1 suffix) is equally satisfied by `scripts/lib/`. |
| C. MOVE to `plugins/soleur/lib/` | Rejected. TypeScript-only by convention (created 2026-07-11, `766199eda`); dropping a 590-line bash primitive there forks a settled convention. |
| D. DUPLICATE + drift gate | Rejected. `plugins/soleur/AGENTS.md:68-80` permits duplication only for a pure importable `lib/*.mjs` under a logic-parity guard. Drift in a `flock`/fd primitive is silent and fails **open**. |
| E. Keep in `.claude/hooks/lib/`, add a fallback chain | **Not a fix.** The file genuinely does not exist in the cache tree; a chain over nonexistent paths still ends in stubs. |
| F. A bespoke 4-arm resolver + extracted `resolve-session-state.sh` | Rejected as circular and speculative: sourcing the resolver requires resolving `plugins/soleur/`, the identical problem with an extra file. Arm 4 is near-unreachable (see Overview, P2). |
| G. A class-level `plugin-self-containment` CI gate | Rejected on measurement: **65 files / 338 hits** of `.claude/` under `plugins/soleur/**`; restricted to non-test `.sh`, **8 files / ~25 hits of which exactly one is the defect** — a 96% seed-allowlist rate. The signature is also wrong: `$PROJECT_ROOT/.claude/` is *correct* (addressing the user's repo). AC2 pins the specific line and the cache-install test catches escapes behaviorally. |

## Deferrals

1. **Wider `${CLAUDE_PLUGIN_ROOT:-…}` non-resolution on marketplace CLI installs — CONDITIONAL on Phase 6.** File **only if** the var is UNSET for cache-served skills; in that case 21+ ADR-093 Slice B/C/D sites (including the three redaction gates) are affected. If SET, **do not file** — the anchor pattern is correct as designed. Relate to #6222. Labels `domain/engineering`, `type/bug` (all verified to exist).
2. **`freeze-lock.sh` depth coupling.** `.claude/hooks/lib/freeze-lock.sh:37` hardcodes "repo root is three dirs up". Not a session-state consumer — explicitly out of scope, filed so scope creep does not pull it in. (Note it is also an orphan suite by the same R6 mechanism.)

## Recorded decision challenges

Per ADR-084, taste/user-challenge decisions are surfaced, never silently applied. This plan ran **headless**, so they are persisted to `knowledge-base/project/specs/feat-one-shot-7409-session-state-lib-resolution/decision-challenges.md` for `/ship` to render into the PR body and file as an `action-required` issue.

1. **CTO: split into two PRs.** Kept as one (R-1). If split, #7409 must stay OPEN until the second merges — the move-only PR must use `Ref #7409`.
2. **CTO: record as an ADR-093 amendment.** Standalone ADR-177 + bidirectional cross-reference.
3. **Destination.** CTO recommended `hooks/lib/`; the advisor recommended `scripts/`. Architecture review then showed **both of the CTO-supplied grounds for `hooks/lib/` were factually wrong** (`AGENTS.md:182` is skill-scoped; the `plugins/soleur/lib/` date was a month off). **Resolved by synthesis:** `plugins/soleur/scripts/lib/` satisfies the advisor's cohesion objection *and* keeps the A1 suffix carve-out matching with zero edit.
4. **Advisor: degrade open, not fail loud.** **Adopted** — reversed a first-draft decision stated as "not negotiable".
5. **Architecture: add an `AP-023` principles-register row** ("no shipped plugin file resolves a path outside the plugin root"), citing the class-level gate as its enforcement. **Not adopted**, because that gate was cut on measurement (Alternative G) and an AP row with no enforcement mechanism is a claim, not a principle. Revisit if the gate is ever built.

## Sharp Edges

- **`is_lease_active` is a fail-closed stub returning 0 ("active") when the library is missing.** Any AC asserting it passes **vacuously against the exact bug**. Assert the lease **FILE**. Equally, never `[[ -d "$LEASE_DIR" ]]` — the library `mkdir -p`s it at source time regardless of whether anything is written. And never assert a value that is also the **default** (`expected_duration_min=240` is the default at two layers) — a "the env var was read" assertion must use a non-default value or it proves nothing.
- **A cache-install fixture built by copying the repo tests nothing.** The bug *is* the absence of everything outside `plugins/soleur/`. Copy only that directory and assert `.claude` is absent as a precondition.
- **A `CLAUDE_PLUGIN_ROOT` measurement from a REPO-served skill says nothing about a CACHE-served one.** Both copies can be installed at once, with the repo copy winning inside the repo. A skill preamble reading `Base directory: <repo>/plugins/soleur/...` is the tell.
- **A terminal fallback arm's disposition follows the destructiveness of what it guards, not a blanket fail-closed rule.** Fail-closed on a destructive op (reap) means "do nothing" — safe. Fail-closed on an advisory op (`gh pr merge` under a contention lock) means the merge never happens — the original bug with a better error message.
- **Relocating a file out of `.claude/hooks/` can silently narrow a green gate.** A1's `find … 2>/dev/null` reports `ok` when a root is removed. Extend the roots **and** assert membership, in the same PR. But **verify the narrowing is real before claiming it**: the `EXEC_SURFACE_GLOBS` half of this looked identical and turned out to lint a class (`gh pr|issue list --search`) the moved file has zero instances of.
- **Do NOT check shell-glob coverage with Python `fnmatch`** — its `*` crosses `/`, bash's does not. `fnmatch` reports `.claude/hooks/lib/session-state.test.sh` as matching `.claude/hooks/*.test.sh` and would have falsified the R6 orphan finding. Expand the runner's real glob list in bash.
- **Editing any `.c4` file without running `scripts/regenerate-c4-model.sh` is a guaranteed CI red** — `c4-model-freshness.test.sh` byte-diffs the committed `model.likec4.json`, and it is pinned in `ci.yml`.
- **Four hook-regex fixtures assert the BARE `session-state.sh` wrapped form.** Editing them to add a path breaks the #3689 bypass gate. They are on the Phase 1.6 do-not-touch list.
