---
title: "chore(workflow): move the full-suite gate to post-review; touched-file suites at implementation exit"
date: 2026-08-11
slug: chore-move-full-suite-gate-post-review
branch: feat-one-shot-7352-fullsuite-gate-post-review
issue: 7352
closes: 7352
type: chore
lane: cross-domain
domain: engineering
priority: p2-medium
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

## Overview

Reorder two existing test gates in the Soleur pipeline without changing what reaches `main`.
The `/work` Phase 2 exit currently runs the whole `scripts/test-all.sh` battery; that same
battery runs again after review fixes, in `/ship`, as the merge gate. This plan keeps the merge
gate exactly where it is and narrows the earlier one to the suites and linters that cover the
touched files, so a small diff is not measured against 460+ suites twice.

The reading discipline that surrounds both runs — the preamble/epilogue read, the coverage NOTE
that reports whether the nested infra runner actually executed, and the contention-banner
interpretation — is preserved at both positions and is not in scope for reduction.

## Research Insights

### Premise Validation (Phase 0.6)

Every reference the issue cites was resolved before research was dispatched.

| Reference | Probe | Result |
|---|---|---|
| Issue #7352 | `gh issue view 7352 --json state,title` | OPEN, title matches. Not closed by any merged PR — premise live. |
| PRs #7344 / #7343 | `gh issue view <n>` (unified numbering) | Both `MERGED`. They are the measurement session the issue's numbers came from. |
| #6969 (coverage NOTE provenance) | `gh issue view 6969` + `git grep -n 6969` | CLOSED issue "web-2 booted DARK at cloud-init stage doppler_download". Cited correctly: the infra-coverage NOTE and the "**an** exit gate, not **the** exit gate" wording in `work/SKILL.md:670,746,1081` and `ship/SKILL.md:329` all carry `#6969` as their `**Why:**`. Not a mis-citation. |
| Sibling PR #7441 | `gh pr view 7441` | OPEN, draft, branch `feat-one-shot-test-pipeline-efficiency`. Body is the auto-draft placeholder. Its follow-up tracker is #7454. **Not read** — the branch and its worktree are off-limits per the session brief. |
| `work/SKILL.md` §9 "Full-Suite Exit Gate" | Read `work/SKILL.md:742-770` | Exists at line 742 as stated. |
| `ship/SKILL.md` full-suite position | Read `ship/SKILL.md:300-358` | **The full-suite run is already there** — Phase 4 "Run Tests" (line 300) runs `bash scripts/test-all.sh` (line 333) with the epilogue `IS covered above` / `is NOT covered above` discipline inline at lines 341-350. The issue's "it already partly lives there" is accurate and materially changes the shape of the deliverable (see Cut List C2). |

### Property List (Phase 0.6b)

What the ask is *for*, stated as observable outcomes:

- **P1** — `/work` Phase 2 exits on a green, trustworthy checkpoint over the diff's own coverage, in ~1–2 min rather than the full battery's ~10–45 min.
- **P2** — cross-file breakage the touched-file set cannot see still blocks merge.
- **P3** — a red observed after review fixes is attributable to the review fixes, because the pre-review checkpoint was green.
- **P4** — per-PR contention on the repo-wide advisory lock and the shared 4 GiB tmpfs (ADR-133) is halved, a cost borne by every concurrent worktree, not only the running session.
- **P5** — whether the nested infra runner actually executed remains readable at whichever position runs the full battery (the two-polarity coverage NOTE).
- **P6** — contention banners remain read and interpreted, so a false RED is still distinguishable from a real one.
- **P7** — the suite set the Phase-2 gate runs is derived from what actually gates the changed files, not from the directories a planner expects.

### Cut List (Phase 0.6b) — mechanisms removed before research

Each row: mechanism → property it would buy → what already on `origin/main` buys it. Every "already covered" claim was grepped against the authority, and the authority is named.

- **C1 — a bespoke touched-file test-selection script.** Property P1/P7. Already bought three ways: (a) `apps/web-platform` runs **vitest 4.1.0** (`apps/web-platform/node_modules/.bin/vitest --version` → `vitest/4.1.0 linux-x64 node-v22.22.2`), whose `--changed [since]` flag runs tests *affected by* the changed files via the module graph — `--help` prints `--changed [since]   Run tests that are affected by the changed files (default: false)`, and a live `vitest list --changed origin/main --filesOnly` on this branch exits 0; a `related [...filters]` subcommand also exists. (b) `lefthook.yml` pre-commit already scopes markdownlint (`glob: "*.md"`, `run: npx --yes markdownlint-cli {staged_files}`, line 21), gitleaks (`--staged`, line 31), `lint-fixture-content.mjs {staged_files}` (line 50), `lint-infra-no-human-steps.py {staged_files}` (line 122), `lint-scheduled-show-full-output.sh {staged_files}` (line 132), `gdpr-gate.sh {staged_files}` (line 202), and a full `cd apps/web-platform && npx tsc --noEmit` (line 138) — and `/work` already makes incremental commits, so these fire per commit without any new gate. (c) the repo's canonical set-derivation idiom for the *non*-module-graph half already exists at `review/SKILL.md:1305`: "derive the set from where the changed file's SYMBOLS are referenced, repo-wide (`git grep -l '<symbol>'`), never from the directories you expect."
- **C2 — a NEW "Full-Suite Pre-Merge Gate" section at ship Phase 5.5.** Property P2/P3/P5/P6. Already bought by `ship/SKILL.md` Phase 4 (line 300), which runs `bash scripts/test-all.sh` (line 333) and already carries the epilogue-reading discipline and the "do NOT run `run-registered-suites.sh` alongside it" contention warning (lines 337-350). Adding a second run would *add* a third full-suite invocation per PR — the exact cost this issue exists to remove. The ship-side edit is therefore a **re-statement plus a re-run trigger on the existing Phase 4**, not a new gate.
- **C3 — a new linter list authored into work Phase 2 exit.** Property P1. Already bought by `lefthook.yml` pre-commit (C1b). A hand-maintained parallel list in prose would drift from `lefthook.yml` the first time a linter is added there, reproducing the hand-maintained-allowlist class the repo has already been bitten by (`knowledge-base/project/learnings/2026-05-29-target-allowlist-extension-must-sweep-all-guard-suites.md`).

### Value-Proposition Measurement (Phase 0.6c)

The justification is a cost saving, so the saving is quantified and its provenance named.

**Carried from the issue** (measured during PRs #7344 / #7343, not re-measured here): a touched-file baseline on a 24-file diff ran **224 assertions in ~90 s**; the same PR's full run had its infra runner alone take **573 s**, be reaped by harness limits **4 times**, and serialise **2694 s** behind a sibling worktree holding the repo-wide advisory lock.

**Measured this session:**

- `scripts/test-all.sh` accepts `TEST_GROUP` ∈ `all|webplat|bun|scripts|infra` (`scripts/test-all.sh:140-157`) and has **no diff-scoped mode**. Its only diff-relevance gate is `_infra_in_diff` (`scripts/test-all.sh:384-391`), which decides whether to *invoke the nested infra runner*, not which suites to run. So "run only what the diff touches" is not a flag on the existing runner; it is a different command set.
- `vitest 4.1.0` `--changed` verified live (see C1a). This is the single largest shard and it already supports the scoping.

**Not re-measured, deliberately.** A fresh `time bash scripts/test-all.sh` now would contend with the live sibling worktree `feat-one-shot-test-pipeline-efficiency` for the same advisory lock and tmpfs — i.e. the measurement would both perturb that session and be perturbed by it, which is precisely the contention ADR-133 documents. The paired A/B that *would* settle it is recorded as an acceptance criterion instead (AC12), to be run on a quiet machine.

### The merge gate is CI, not the local runner — the issue's justification is wrong (in a way that makes the change safer)

The issue argues the change is safe because "the full run still gates merge". That sentence is true of the *outcome* and false of the *mechanism*, and the difference decides which regression classes are actually at risk. Verified this session against the authority, not inferred:

- **`gh api repos/:owner/:repo/rulesets`** → ruleset **14145388 "CI Required"**, `enforcement: active` on `main`. Its `required_status_checks` include the context **`test`**, alongside `e2e`, `gitleaks scan`, `adr-ordinals`, `tc-document-sha-guard`, `service-role-allowlist-gate`, `CodeQL`, `rule-body-lint`, and 13 others.
- **`.github/workflows/ci.yml:792-793`** → `test:` is an aggregator job with `needs: [test-webplat, test-bun, test-scripts]`. Those three shards run `bash scripts/test-all.sh webplat` (`:631`), `bun` (`:664`) and `scripts` (`:744`).
- **There is no `infra` shard and no infra context in the required list.** `apps/web-platform/infra/` is covered only by `.github/workflows/infra-validation.yml`, which is path-gated and is **not** a required context.

**Consequence.** For everything in the `webplat` / `bun` / `scripts` shards, a required CI context re-runs the exact same command on the PR head — so the local `test-all.sh` was never the authority there; it was a fail-fast checkpoint that saves a CI round-trip. The one thing the local run uniquely provides is the **nested infra runner**, which `TEST_GROUP=all` invokes when the diff touches `apps/web-platform/infra/` and which no required context reaches.

This reframes the whole change: removing the Phase-2 run costs *fail-fast latency* for most classes and costs *actual coverage* for exactly one — infra. That is a much narrower ceiling to name, and it is nameable precisely.

### What the pre-review full run has actually caught (the re-homing input)

Each row is a real catch story from the learnings corpus. The "already gated by required CI?" column is the correction above; the "cheap to re-home?" column is what the Phase-2 gate must do anyway to keep review interpretable (fail-fast still has value — it is the difference between finding a break in 90 s and finding it after a CI round-trip and an 8-agent review fan-out). Together they are the "name the new ceiling" answer required by `knowledge-base/project/learnings/2026-05-05-defense-relaxation-must-name-new-ceiling.md`.

| # | Class | Catch story | Shard | Gated by required CI `test`? | Cheap to re-home into the Phase-2 gate? |
|---|---|---|---|---|---|
| R1 | Source-text-coupled tests — `readFileSync(src) + expect(src).toMatch(/SYMBOL/)` break on rename/extraction even when behaviour is unchanged, and the test imports nothing from the changed module | `.../test-failures/2026-06-15-source-grep-test-breaks-on-symbol-extraction-only-full-suite-catches.md` | `scripts` | **Yes** | **Yes** — exactly what `git grep -l '<symbol>'` finds (`review/SKILL.md:1305`). Not in any module graph, so `vitest --changed` alone misses it. |
| R2 | Generated-artifact staleness — a `.c4` edit leaves `model.likec4.json` stale; `c4-model-freshness.test.sh` is an orphan the named `c4-*.test.ts` files do not cover | `.../2026-06-29-c4-source-edit-requires-regenerate-model-json-orphan-suite.md` | `scripts` | **Yes** | **Yes** — `work/SKILL.md:589` already couples `.c4` edits to `scripts/regenerate-c4-model.sh`; re-point its trailing "full-suite-only" clause at the Phase-2 set. |
| R3 | Multi-document lockstep — editing `docs/legal/*.md` drifts `legal-doc-consistency.test.ts`, the SHA pin in `lib/legal/legal-doc-shas.ts`, and the Eleventy mirror | `.../2026-05-29-legal-doc-triple-lockstep-and-rpc-grants-invoker-before-definer.md`; already at `work/SKILL.md:768` | `webplat` + the separate required `tc-document-sha-guard` context | **Yes, doubly** | **Yes** — same shape as R2, re-pointed in place. |
| R4 | Scope guards under a different name stem — extending a hand-maintained allow-list (terraform `-target=`, a CSRF route set, an RLS table list) syncs the filter and its counter but misses the guard | `.../2026-05-29-target-allowlist-extension-must-sweep-all-guard-suites.md` | `infra` | **NO — real gap** | **Yes, same mechanism as R1** — the guard is found by grepping the allow-list's *contents*, not the file's name. |
| R5 | `apps/web-platform/infra/*.test.sh` orphans — not glob-discovered; each needs a named step in `infra-validation.yml` | `.../2026-06-16-infra-test-orphan-suites-and-node-options-env-file-clobber.md` | `infra` | **NO — real gap** | **No.** An orphan suite references nothing in the diff *by definition*, so no relevance derivation can reach it. (`ci.yml:177` `lint-orphan-test-suites.sh` covers *registration* orphans, a different failure.) |
| R6 | Everything else — a sibling asserting on a changed literal with no shared symbol | The issue's own "Accepted cost" paragraph | mixed | Mostly yes | **No.** Accepted cost. |

**The named ceilings, therefore:**

1. **CI's required `test` context (ruleset 14145388) is the merge gate for R1-R3 and most of R6.** Stated explicitly so a future reader does not re-derive it wrongly.
2. **`/ship`'s local run must stay `TEST_GROUP=all`, never a shard** — it is the only gate R4 and R5 have. If it is ever allowed to shard, those two classes lose their last coverage entirely. This is the single most load-bearing sentence in the plan.
3. **The infra coverage NOTE becomes *more* load-bearing, not less.** Since the local `TEST_GROUP=all` run is now the sole gate for R4/R5, the `IS covered above` / `is NOT covered above` epilogue is the only signal that those classes were measured on this diff. This is the mechanical reason the issue's "do NOT weaken the epilogue check" instruction is correct.
4. **Falsifiability.** The relaxation is otherwise unmeasurable. A tripwire is declared in the ADR: *if a PR's required `test` context reds after a green local touched-file gate more than N times in a month, restore the unconditional Phase-2 run.* Automating that count is deferred (see `## Deferred`), because it needs a data source spanning many PRs; the tripwire itself is stated, dated, and owned.

### Contention / reaping / misread-signal corpus (why running it twice is expensive)

- **ADR-133** (`knowledge-base/engineering/architecture/decisions/ADR-133-test-all-tmpfs-contention-managed-resource-and-advisory-lock.md`) — the contended resource is **capacity**, not a colliding path: a machine-global RAM-backed 4 GiB `/tmp` shared by parallel worktrees. Decisions: observe-only contention instrumentation (`scripts/lib/test-contention.sh`), managed reaping (`scripts/tmpfs-guard.sh`), and an advisory git-common-dir lock that serialises worktrees and proceeds with `LOCK_CONTENDED_PROCEEDING` rather than aborting. Two full runs per PR is two contention windows.
  - ADR-133's 2026-08-10 addendum is load-bearing for how this plan's numbers may be cited: its verdict was measured on one machine and mount and "does not transfer" to a hosted runner on disk-backed `/var/tmp`. Its **method** transfers; its **conclusion** is a prior.
- **`work/SKILL.md:764`** — a long run is frequently reaped by the harness (`status: killed`, `exit code 144`), and that is a third result class, not a suite verdict. The three-way split (`[FAIL]` + terminal marker = failure; zero `[FAIL]`, no terminal marker, no rc file = reap; `[KILLED]` + terminal marker + `rc=3` = unresolved) is the discipline that must survive the move.
- **`scripts/test-all.sh:4`** — `EXIT CONTRACT (#7424)`: `0` all passed, `1` ≥1 FAILED, `3` zero failed and ≥1 KILLED (top-level only; a nested runner returning 3 classifies as a plain FAIL), `2` usage error. Landed in PR #7425 (merged), which is the commit immediately preceding this branch.

### Coverage-NOTE literals (must not be paraphrased)

The two-polarity NOTE is what says whether the nested infra runner actually ran. Verbatim from `scripts/test-all.sh`:

- line 1027 — `NOTE (announced in the preamble): apps/web-platform/infra/ IS covered above, via the` …
- line 1036 — `NOTE: apps/web-platform/infra/ is NOT covered above — TEST_GROUP=$TEST_GROUP excludes` …
- line 1041 — `NOTE: apps/web-platform/infra/ is NOT covered above (diff does not touch it).`

The position-agnostic reader grep that consumes them lives at `work/SKILL.md:670`:
`grep -nE 'NOTE:|NOTE \(|\[contention\] BANNER|LOCK_CONTENDED|^\[budget\]|^\[KILLED\] [^ ]+ \(exit=' "$log"`.
Both the literals and this grep are **out of scope for modification** by this plan.

### Enforcement surfaces that constrain the edit

- **No test or hook asserts that `work/SKILL.md` contains a full-suite gate.** The prescription is prose only. (`plugins/soleur/test/`, `.claude/hooks/`, `tests/scripts/` searched for a co-assertion on "Phase 2 exit" + "test-all" — none.) So this is a prose edit with no companion test to update.
- **`scripts/lint-agents-enforcement-tags.py`** resolves `[skill-enforced: …]` tags found in `AGENTS.md` / `AGENTS.rules.md` against skill bodies. Its comment at line 218 names `work Phase 2 exit` explicitly as an anchor that resolves via the self-referencing tag literal `[skill-enforced: work Phase 2 exit]` inside `work/SKILL.md`. **The tag string at `work/SKILL.md:744` must be preserved verbatim** even though the gate's body changes, or the anchor resolution path the linter documents is removed. The only `AGENTS.rules.md` rule carrying a `work Phase 2 exit` anchor is `hr-gdpr-gate-on-regulated-data-surfaces` (`AGENTS.rules.md:54`), which points at §8, not §9 — untouched by this plan.
- **`plugins/soleur/test/components.test.ts`** forbids bare-backtick `` `references/…` `` / `` `scripts/…` `` / `` `assets/…` `` patterns in SKILL.md prose — use markdown links. This gate has already fired on a SKILL.md prose edit before (`knowledge-base/project/learnings/2026-05-11-test-all-exit-gate-self-validated-on-creating-pr.md`).
- **A third full-suite position exists**: `plugins/soleur/scripts/grok-pre-push-gate.sh:123` runs `bash scripts/test-all.sh`, and `one-shot/SKILL.md:17` requires that gate on the Grok harness. It is a *pre-push* local-CI-parity gate, not a pipeline phase, and this plan does not touch it — but it means the Grok arm keeps a full run at push regardless.

### CLAUDE.md / AGENTS conventions in force

- `hr-verify-repo-capability-claim-before-assert` — every "already covered by X" claim in the Cut List names the file it was grepped against.
- `cq-cite-content-anchor-not-line-number` — line numbers here are paired with a quoted content anchor, because both SKILL.md files are actively edited by siblings.
- `wg-architecture-decision-is-a-plan-deliverable` — the ADR is a task in this plan, not a follow-up (see `## Architecture Decision (ADR/C4)`).
- `rf-review-finding-default-fix-inline` — relevant because ship Phase 5.5's default is to fix findings inline, which is what creates the post-Phase-4 mutation window this plan must close.

### Related issues / PRs

- #7352 — this work.
- #7425 (merged) — `EXIT CONTRACT` / KILLED-vs-FAILED classification, the immediate parent commit.
- #7441 (draft PR, branch `feat-one-shot-test-pipeline-efficiency`) + #7454 (its follow-up tracker) — a sibling session path-gating heavy batteries *inside* `scripts/test-all.sh`. Complementary, not conflicting: that work makes the full run cheaper; this work runs it once instead of twice. Expect a small rebase touch-up in `work/SKILL.md` (its uncommitted edits sit near line 269, ~470 lines from §9 at line 742 — low collision risk).
- #7402, #7429, #7210, #6496 — open issues against `test-all.sh` itself; none is a blocker for this reordering.

## Research Reconciliation — Issue vs. Codebase

| Issue claim | Codebase reality | Plan response |
|---|---|---|
| "`ship/SKILL.md` — make the full-suite requirement explicit in pre-merge (it already partly lives there)" | It lives there **fully**: `ship/SKILL.md` Phase 4 "Run Tests" (line 300) runs `bash scripts/test-all.sh` (line 333) with the epilogue discipline at lines 341-350. | The ship-side deliverable is **not** adding a run. It is (a) naming Phase 4 as the merge gate / post-review-fixes position, and (b) closing the window in which code changes *after* Phase 4 and still merges. Recorded as Cut List C2. |
| "the `/work` Phase 2 exit gate … full `scripts/test-all.sh`" — implying one site | `work/SKILL.md` prescribes a full run at **five** sites: line 243 (todo-list template: "Place a final 'Run full test suite and lint' task at the end"), line 337 ("Run full test suite after changes"), line 668 ("Run the full test suite after each RED/GREEN/REFACTOR cycle"), line 742 (§9 the exit gate itself), line 818 (Phase 3 code comment `# Run full test suite`). | All five are in `## Files to Edit`. Editing only §9 would leave line 668 mandating a full run **per TDD cycle** — strictly more expensive than the gate being removed — and line 818 reinstating it one phase later. |
| Implied: the touched-file set is a directory/path concept | The repo's own canonical derivation is symbol-based: `review/SKILL.md:1305` — "derive the set from where the changed file's SYMBOLS are referenced, repo-wide (`git grep -l '<symbol>'`), never from the directories you expect". | The Phase-2 gate is specified as a **derived** set (module graph + symbol graph), not an enumerated one. This is what re-homes regression classes R1 and R4. |
| Implied: removing the Phase-2 run halves the full runs per PR | There is a **third** full-suite position: `plugins/soleur/scripts/grok-pre-push-gate.sh:123`, required by `one-shot/SKILL.md:17` on the Grok harness. `ship/SKILL.md:1433` states it runs "even if Phase 4 test-all.sh already ran". | Out of scope, but stated honestly: on the Claude Code arm this change takes 2 runs → 1; on the Grok arm it takes 3 → 2. The saving is real on both, but the plan must not claim "one run per PR" universally. |
| "Do NOT weaken … the contention-banner reading discipline" | That discipline (lines 748, 762, 764, 766) is physically located **inside** §9, the section being rewritten. Deleting §9's body would delete it. | The discipline is retained in place, under a re-titled sub-heading, and `ship/SKILL.md` Phase 4's existing informal pointer ("the sibling-contention shape `work/SKILL.md` documents", line 337) is upgraded to an explicit link. No new reference file — see Cut List rationale. |
| "the full run still gates merge — no change to what reaches `main`" | **The local run is not the merge gate.** `gh api repos/:owner/:repo/rulesets` → ruleset 14145388 "CI Required" (active on `main`) requires the context `test`, which `ci.yml:792` aggregates from `test-webplat`/`test-bun`/`test-scripts`, each running `bash scripts/test-all.sh <group>`. So CI re-runs the same command on the PR head regardless. **But there is no infra shard and no infra required context** — `apps/web-platform/infra/` is covered only by the path-gated, non-required `infra-validation.yml`. | The conclusion survives and is *stronger* than the issue's argument for R1-R3, and *narrower* for R4-R5. The plan replaces "the full run gates merge" with the accurate pair of statements, and pins `TEST_GROUP=all` at ship Phase 4 as the sole gate for the infra classes. Naming Phase 4 "the merge gate" is explicitly rejected — it would license a future PR to shard it. |
| Implied: ship Phase 4 is after all code changes | Phase 5.5 ("Pre-Ship Review Gates", line 393) sits **after** Phase 4 (line 300) and contains multiple code-mutating gates; `ship/SKILL.md:1433` itself says "Phase 4 is mid-pipeline". | The SHA pin at Phase 6.4, scoped to the infra predicate. See Proposed Solution §3. |
| Implied: threshold is low because no user data is touched | `plugins/soleur/agents/engineering/review/user-impact-reviewer.md:13` **self-exits** on `aggregate pattern` ("Wrong threshold for this agent — invoking criterion not met"), and its **Meta-workflow PR branch** exists precisely for a diff touching only `plugins/soleur/skills/**` at `single-user incident`, where the enumeration target switches to the false-negative failure modes of the workflow change. | Threshold set to `single-user incident` with `requires_cpo_signoff: true`. Declaring `aggregate pattern` would *sound* more cautious while silently opting out of the one review branch built for this exact diff shape. |
| `#6969` cited as provenance for the coverage NOTE | `gh issue view 6969` returns "web-2 booted DARK at cloud-init stage doppler_download" — a boot incident, not a test-runner issue, so the citation *looks* wrong. | Not a mis-citation: `work/SKILL.md:670,746,1081`, `ship/SKILL.md:329` and `scripts/test-all.sh:333,820,944` all carry `#6969` as the `**Why:**` for the infra-coverage NOTE. The boot incident is what exposed "a green summary read as evidence for infra it never executed". Premise holds. |

## Open Code-Review Overlap

`gh issue list --label code-review --state open --json number,title,body --limit 200` returned 64 open issues; none contains `plugins/soleur/skills/work/SKILL.md` or `plugins/soleur/skills/ship/SKILL.md` in its body. **None.**

## Problem Statement

`scripts/test-all.sh` runs twice per PR on the Claude Code arm — once at `/work` Phase 2 exit and once at `/ship` Phase 4 — and the second run is the one that gates merge. The first is therefore paying full price for a partial benefit.

The price is not "the same suites twice". It is:

1. **Repo-wide serialisation.** `test-all.sh` takes an advisory git-common-dir lock (ADR-133 Decision 3). Parallel worktrees are this repo's documented workflow, so a second run per PR roughly doubles the lock queue across *every* concurrent session — a cost borne by sessions that did not run it. Measured on PR #7344: 2694 s queued behind a sibling.
2. **Capacity contention on a shared 4 GiB RAM-backed `/tmp`** (ADR-133 Decision 1), whose observable symptom is a timeout that reads exactly like a regression.
3. **Harness reaping.** The same PR saw the run reaped 4 times (`exit 144` / `status: killed`), each reap costing a re-run and a diagnosis (`work/SKILL.md:764`).
4. **Wall clock.** The nested infra runner alone measured 573 s.

Against that, a touched-file baseline on the same 24-file diff ran 224 assertions in ~90 s.

The pre-review run is not worthless — it produces the green checkpoint that makes a multi-agent review interpretable (a red tree makes every reviewer's mutation row noise) and makes a post-review red attributable. But those properties do not require the *whole* battery; they require *a trustworthy green over the diff's own coverage*.

Meanwhile `work/SKILL.md` already contradicts itself: line 746 says "Touched-file tests are the inner loop", while line 668 says "Run the full test suite after each RED/GREEN/REFACTOR cycle."

## Proposed Solution

Three moves, no new machinery.

### 1. `/work` Phase 2 exit becomes a derived touched-file gate

§9 is re-titled and its prescription changes from "run `bash scripts/test-all.sh` once" to a **derived** suite set plus the linters that already run. The set is derived three ways, in this order:

- **Module graph** — `cd apps/web-platform && ./node_modules/.bin/vitest run --changed origin/main` when the diff touches that package. Verified: vitest 4.1.0, `--changed [since]` present, `vitest list --changed origin/main --filesOnly` exits 0. This resolves importers automatically, so it needs no hand-maintained map.
- **Symbol graph** — for every symbol, exported name, or literal the diff changed, `git grep -l '<symbol>'` repo-wide and run every suite that hits. This is the repo's own canonical idiom (`review/SKILL.md:1305`) and is what catches source-text-coupled suites (R1) and differently-named scope guards (R4) — neither of which is in any module graph.
- **Existing path-triggered couplings, in place** — `work/SKILL.md` already documents the two generated-artifact/mirror couplings that no graph can derive: line 589 (`.c4` edit → `c4-model-freshness.test.sh`) and line 768 (new `docs/legal/*.md` heading → `legal-doc-consistency.test.ts` + the Eleventy mirror). Both currently end with "the full-suite exit gate is what catches it". Those clauses are re-pointed to "run this suite in the Phase 2 touched-file set". Likewise §6 "Infrastructure Validation" (line 686) already owns the `apps/*/infra/` trigger and names `run-registered-suites.sh`.

**Deliberately no new table and no new linter list.** The couplings stay where they already are, next to the instruction that creates them; a fresh central table would be a second hand-maintained allow-list, which is the exact drift class `2026-05-29-target-allowlist-extension-must-sweep-all-guard-suites.md` documents. The linters are already `{staged_files}`-scoped in `lefthook.yml` and fire on every incremental commit `/work` makes; the gate's linter obligation is therefore stated as "the final commit was made with lefthook enabled" plus the app-package `tsc --noEmit` that `work/SKILL.md` Phase 3 already prescribes.

### 2. The run-reading discipline stays put and is linked from ship

The four sub-bullets at `work/SKILL.md:748, 762, 764, 766` — dirty-tree invalidation, sibling-worktree false RED, harness reaping vs. the three-way result split, the Doppler `TEST_GROUP=webplat` caveat — are about *reading a `test-all.sh` run*, not about *when to launch one*. They are retained verbatim under a sub-heading that makes their scope explicit, and `ship/SKILL.md` Phase 4's existing informal reference (line 337, "the sibling-contention shape `work/SKILL.md` documents") becomes an explicit markdown link so the merge-gate position inherits them.

### 3. `/ship` Phase 4 is named correctly, and its infra coverage is pinned to the merging tree

Phase 4 already runs the battery. Three things change, and the naming is deliberately **not** "the merge gate":

- **It is named accurately.** Phase 4's prose states that (i) CI's required `test` context — ruleset 14145388, aggregating the three `test-all.sh` shards — is the merge gate; (ii) Phase 4 is the **last local fail-fast checkpoint**, whose value is catching a break before an 8-agent review fan-out and a CI round-trip; and (iii) Phase 4 is **the sole gate for `apps/web-platform/infra/`**, because no required context runs that shard. Calling Phase 4 "the merge gate" would be the same over-claim the issue makes, and would license a future PR to shard it.
- **`TEST_GROUP=all` is pinned as a requirement, with the reason.** A future optimisation that shards Phase 4 would silently delete the only gate R4 and R5 have.
- **The infra coverage is pinned to the tree that merges.** The run records `FULLSUITE_SHA=$(git rev-parse HEAD)`. `ship/SKILL.md:1433` already concedes Phase 4 is "mid-pipeline", and the CTO advisory enumerated the later phases that legitimately mutate the tree: Phase 5.4 preflight fixes; Phase 5.5's Code Review Completion Gate (`ship/SKILL.md:417` — "After review completes, if findings include critical or high severity issues, resolve them before continuing to Phase 6"); the Review-Findings Exit Gate whose documented default is fix-inline (`rf-review-finding-default-fix-inline`); the ADR-Ordinal Collision Gate (`:1283`), which renames files and will fire on this very PR; the Phase 6.5 conflict path (`:1674`); and the Phase 7 BEHIND auto-sync (`:1766`).

  For R1-R3 those post-Phase-4 mutations are re-gated by CI on push. For **R4/R5 they are not**, because no required context runs infra. So the assertion is narrow and cheap: at the Phase 6.4 Unpushed-Commits Gate (line 1333, which already reasons about HEAD vs. remote), if `git rev-parse HEAD != "$FULLSUITE_SHA"` **and** the cumulative diff touches `apps/web-platform/infra/`, re-run before push. Scoping it to the infra predicate is what keeps this from reinstating a third full run on every PR.

  Fail-closed detail: an unset `FULLSUITE_SHA` must **fail the gate**, never compare equal. An unset variable that satisfies a numeric or string gate is the `null == '0'` coercion class already documented at `work/SKILL.md:671`.

This pin is the **new ceiling** the defense-relaxation rule requires, stated at the precision the corrected merge-gate picture allows: *the infra runner was green on exactly the tree that merges.*

## Technical Considerations

- **The `[skill-enforced: work Phase 2 exit]` tag at `work/SKILL.md:744` must survive verbatim.** `scripts/lint-agents-enforcement-tags.py:218` names that literal as the resolution path for the `work Phase 2 exit` anchor. Re-titling the human-readable heading is fine; deleting or re-wording the bracketed tag is not.
- **`plugins/soleur/test/components.test.ts`** rejects bare-backtick `` `scripts/…` `` / `` `references/…` `` / `` `assets/…` `` patterns in SKILL.md prose — use markdown links. This gate has fired on a SKILL.md prose edit before (`2026-05-11-test-all-exit-gate-self-validated-on-creating-pr.md`).
- **Stale self-citations.** `work/SKILL.md:642` and `:649` both end with "the full-suite exit gate is what catches it", and `:1080`/`:1081`/`:1083` describe reading a `test-all.sh` run as if Phase 2 launches it. These are content anchors that become false the moment §9 changes; they are in the edit list, not left for review to find.
- **A new `plugins/soleur/test/*.test.ts` is auto-discovered** by `bun test plugins/soleur/`; a new `*.test.sh` in that directory is **not** and needs an explicit `run_suite` line (`work/SKILL.md:725`). The guard test below is therefore `.test.ts`.
- **Guard-test vacuity is the dominant risk here.** A grep for `test-all.sh` in `work/SKILL.md` will always hit — the Sharp Edges mention it a dozen times — so a naive "the token is absent" assertion is unfailable. Per `cq-assert-anchor-not-bare-token` and `review/SKILL.md:1231(c)` (a `toContain(<symbol>)` satisfied by a *comment*), the guard asserts the **positive** invariants only, anchored on the imperative inside a fenced block, and its non-vacuity is proved by mutation.
- **Sibling-branch interaction.** `feat-one-shot-test-pipeline-efficiency` (draft PR #7441) is making the full run itself cheaper by path-gating heavy batteries inside `scripts/test-all.sh`. That is complementary: it reduces the cost of each run; this reduces the number of runs. Its uncommitted `work/SKILL.md` edits sit near line 269; §9 is at line 742, so a textual collision is unlikely, but a rebase touch-up should be expected. Its `review/SKILL.md` edits do not overlap this plan's file set.

## Files to Edit

- **`plugins/soleur/skills/work/SKILL.md`**
  - line 243 — todo-list template: "Place a final 'Run full test suite and lint' task at the end" → the touched-file gate.
  - line 337 — "Run full test suite after changes" → touched-file suites.
  - line 589 — `.c4` / `c4-model-freshness.test.sh` coupling: re-point "full-suite-only, not the touched-file loop" to "include this suite in the Phase 2 touched-file set when the diff touches `*.c4`".
  - line 642 — stale citation "fail only at the full-suite exit gate" → the derived symbol-graph rule.
  - line 649 — stale citation "the full-suite exit gate is what catches it" → same.
  - line 668 — "Run the full test suite after each RED/GREEN/REFACTOR cycle" → "Run the touched-file suites after each cycle". **The single largest cost line in the file.**
  - lines 742-746 — §9 heading + body: the gate itself. Preserve `[skill-enforced: work Phase 2 exit]` at line 744 verbatim.
  - lines 748, 762, 764, 766 — retained; re-scoped under an explicit "reading a full-suite run" sub-heading.
  - line 768 — legal-doc mirror coupling: re-point "Catch it at the full-suite exit gate" to the Phase 2 touched-file set.
  - line 818 — Phase 3 code comment `# Run full test suite (use project's test command)`.
  - lines 1080, 1081, 1083 — Sharp Edges: re-scope from "the Phase 2 gate" to "whenever you run the full battery".
- **`plugins/soleur/skills/ship/SKILL.md`**
  - lines 326-333 — Phase 4 prose: name it the merge gate / post-review-fixes position; state that `/work` no longer runs it and why.
  - line 337 — upgrade the informal `work/SKILL.md` contention reference to an explicit markdown link.
  - after line 350 — record `FULLSUITE_SHA=$(git rev-parse HEAD)`.
  - line 365 (Phase 5 checklist) — "Tests pass" → "Full suite green at `$FULLSUITE_SHA` (Phase 4 gate)".
  - line 1333 (Phase 6.4 Unpushed-Commits Gate) — add the `HEAD == $FULLSUITE_SHA` assertion + re-run arm.
  - line 1433 — reconcile with the new naming (the grok pre-push gate remains a separate push-time recheck).

## Files to Create

- **`knowledge-base/engineering/architecture/decisions/ADR-181-full-suite-is-the-merge-gate-not-the-implementation-exit-gate.md`** — provisional ordinal, see `## Architecture Decision (ADR/C4)`.
- **`plugins/soleur/test/fullsuite-merge-gate.test.ts`** — the guard (auto-discovered by `bun test plugins/soleur/`).
- **`knowledge-base/project/specs/feat-one-shot-7352-fullsuite-gate-post-review/tasks.md`**.

## Implementation Phases

### Phase 1 — RED: the guard test

Write `plugins/soleur/test/fullsuite-merge-gate.test.ts` asserting, against the real files. Section slicing uses the flag-based form (`/A/{flag=1;next} /B/{flag=0} flag`), never awk's `/A/,/B/` range, which self-matches on the start line.

1. **Ship keeps an unsharded full run.** `ship/SKILL.md`'s Phase 4 section contains a fenced block whose command is `bash scripts/test-all.sh` with **no `TEST_GROUP` argument or prefix** — this is named ceiling 2, and it is the highest-value assertion in the file.
2. **The infra-scoped SHA pin exists and fails closed.** Phase 4 records a full-suite SHA; Phase 6.4 compares it to `HEAD`, guards the infra path predicate, and treats an unset value as a failure rather than a match.
3. **The enforcement-tag anchor survives.** `work/SKILL.md` still contains the literal `[skill-enforced: work Phase 2 exit]` (`scripts/lint-agents-enforcement-tags.py:218` resolves the anchor through it).
4. **The relevance-derivation rule is present at work Phase 2 exit** — the section names both derivation arms (a module-graph run and a repo-wide symbol grep) and states that an empty derived set is a stop condition, not a pass. *Per ADR-166, enforcement is the lint, not the prose: without this assertion, nothing stops the gate silently reverting to "run nothing".*
5. **Work §9 no longer prescribes the battery.** §9's own fenced blocks contain no unconditional `bash scripts/test-all.sh` invocation. Scoped to §9's fenced blocks only — a file-wide token search is unfailable, since the Sharp Edges name `test-all.sh` a dozen times.

Assertions 2, 4 and 5 are genuine REDs before Phases 2-3. Assertions 1 and 3 pass on `origin/main` already and are **regression locks**, not RED targets — stated plainly rather than dressed up as a failing test; their value is earned entirely by the Phase 4 mutation proof. Every assertion anchors on content, never on a line number (`cq-cite-content-anchor-not-line-number`).

### Phase 2 — GREEN: `work/SKILL.md`

Apply every edit in `## Files to Edit` for `work/SKILL.md`. Retitle §9; keep the enforcement tag; keep the four reading-discipline bullets under an explicit sub-heading; re-point the three stale "the full-suite exit gate catches it" citations.

### Phase 3 — GREEN: `ship/SKILL.md`

Apply every edit in `## Files to Edit` for `ship/SKILL.md`: name Phase 4 as the merge gate, link the reading discipline, record `FULLSUITE_SHA`, wire the Phase 6.4 equality assertion + re-run arm, update the Phase 5 checklist line.

### Phase 4 — Mutation-prove the guard

For each of the four assertions, mutate the corresponding line in a scratch copy and confirm the guard reds; restore. A guard whose mutation does not red is a guard that asserts nothing.

### Phase 5 — ADR

Write the ADR. Re-derive the ordinal against freshly-fetched `origin/*` immediately before writing **and** again before merge; if it moves, sweep `knowledge-base/project/{plans,specs}/` for the old ordinal in the same edit.

### Phase 6 — Verify

Run the Phase-2 touched-file gate on this very PR (its own first customer): the diff is `plugins/soleur/skills/*/SKILL.md` + `plugins/soleur/test/*.test.ts` + `knowledge-base/**`, so the derived set is `bun test plugins/soleur/` plus markdownlint on the changed `.md` files. Then run the full battery once, at ship Phase 4, per the new rule.

## Alternative Approaches Considered

| Alternative | Why not |
|---|---|
| Delete the Phase-2 gate entirely | The issue's own three counter-arguments: a red baseline voids review mutation rows; attribution of post-review reds is lost; spawning 8-10 agents against code that fails its own tests wastes the most expensive pipeline step. Two of the three were observed on #7344. |
| Add a second full run at ship Phase 5.5 (after review fixes) | Cut List C2 — Phase 4 already sits after review in every pipeline entry path. A second run would make it *three* per PR. The SHA pin gets the same property for free. |
| Extract the reading discipline into a shared `references/` file | New machinery for two consumers. `ship/SKILL.md:337` already cross-references `work/SKILL.md` prose, so the precedent is a link, not a file. |
| Build a `scripts/test-touched.sh` selector | Cut List C1 — `vitest --changed` already does the module-graph half (verified live), `git grep -l '<symbol>'` is already the repo's canonical idiom for the rest, and lefthook already scopes the linters. A new script would be a third hand-maintained surface. |
| Add a `--changed` mode to `scripts/test-all.sh` | That is the sibling session's work (PR #7441, tracker #7454), aimed at a different property (make each run cheaper). Duplicating it here would collide with a live branch. |

## User-Brand Impact

This diff touches only `plugins/soleur/skills/**` and `knowledge-base/**`, so it is a **meta-workflow change**: it contains no user-data path, and the correct enumeration target — per `plugins/soleur/agents/engineering/review/user-impact-reviewer.md` §2 "Meta-workflow PR branch" — is the **false-negative failure modes of the gate itself**. The section below enumerates that second-order surface, not an (empty) direct-exposure list.

**If this lands broken, the user experiences:** a Soleur user runs `/work`, is told the implementation phase is green, and merges a change that breaks their repository. Four concrete fail-open shapes, each with the artifact that escapes:

1. **The derived set is silently empty.** The symbol grep finds nothing, `vitest --changed` matches nothing, and the gate reports green over zero suites. Escaping artifact: **any** regression in the diff. This is the `2026-07-24` fail-open class — "a gate must fail CLOSED on every indeterminate outcome, including 'I could not measure this'". Mitigation: the gate must print what it ran and treat an empty set as a stop condition, asserted by the guard test.
2. **The infra classes lose their only gate.** A future PR shards ship Phase 4 to `TEST_GROUP=webplat` for speed. Escaping artifact: a terraform `-target=` allowlist scope guard (R4) or an `apps/web-platform/infra/*.test.sh` orphan (R5) — i.e. an infra change that can destroy a user's worktrees or hosts, since no required CI context runs that shard. Mitigation: named ceiling 2, plus the `TEST_GROUP=all` assertion in the guard test.
3. **The SHA pin compares equal when unset.** `FULLSUITE_SHA` never gets set, the Phase 6.4 assertion passes vacuously, and an infra fix made at Phase 5.5 merges unmeasured. Escaping artifact: same as (2). Mitigation: fail-closed on unset, mutation-proved (AC3).
4. **The guard test is vacuous.** It greps a token that the surrounding prose satisfies (`review/SKILL.md:1231(c)`), so the whole gate can be deleted and CI stays green. Escaping artifact: every subsequent PR, since the workflow silently reverts to "run nothing". Mitigation: four distinct-shape mutations, one per assertion (AC3) — a uniform mutation set does not count.

**If this leaks, the user's workflow is exposed via:** no new exposure vector. No credential, persisted store, or network boundary is touched, and no path matches the canonical sensitive-path regex (`plugins/soleur/skills/**` and `knowledge-base/**` fall outside `SENSITIVE_PATH_RE` — verified against `plugins/soleur/skills/preflight/SKILL.md` Check 6 Step 6.1, so preflight Check 6 and Check 10 both return SKIP). The exposure this change can cause is *omission*, not disclosure: a gate that fails open lets a defect reach the user's `main` via subsequent PRs the gate should have caught — the #2887-class second-order path the meta-workflow branch exists to review.

**Brand-survival threshold:** `single-user incident`

Rationale, stated because the intuitive answer is the wrong one: a first pass set this to `aggregate pattern`, reasoning that erosion across many PRs is the real risk. That is descriptively true and procedurally wrong. `aggregate pattern` buys *strictly less* review — `user-impact-reviewer.md:13` exits immediately on it, which would opt this change out of the single review branch designed for meta-workflow diffs. And shape (2) above is not erosive: one sharded Phase 4 plus one infra PR is a single incident that can destroy a user's hosts. `single-user incident` is both the honest threshold and the one that summons the right reviewer.

Consequently `requires_cpo_signoff: true` is set in the frontmatter, and `user-impact-reviewer` must be invoked at review time (handled by `plugins/soleur/skills/review/SKILL.md`'s conditional-agent block) with its Meta-workflow branch active.

## Observability

**Not applicable — gate skipped with reason.** Plan Phase 2.9 fires on a Files-to-Edit entry under `apps/*/server/`, `apps/*/src/`, `apps/*/infra/`, `plugins/*/scripts/`, or a new infrastructure surface. This plan's code-class file set is `plugins/soleur/skills/*/SKILL.md` (prose, not executed) and `plugins/soleur/test/*.test.ts` (a test). No runtime surface, no new error path, no new infrastructure. Preflight Check 10 will likewise return SKIP, since the diff matches no path in `SENSITIVE_PATH_RE`.

The change's own observability is the guard test: a regression in the merge-gate wiring is a red suite in `bun test plugins/soleur/`, discoverable locally with no credentials.

## Encryption Posture

**Not applicable — gate skipped with reason.** No persistent store (volume, bucket, table, queue, cache, backup target, log sink) and no new cross-component or network connection is introduced. Detection globs (`*.tf`, `supabase/migrations/*.sql`, `cloud-init*.ya?ml`, `docker-compose*.ya?ml`) match nothing in the Files-to-Edit / Files-to-Create set.

## Architecture Decision (ADR/C4)

This plan changes a cross-cutting workflow invariant every pipeline consumer honours — which gate is authoritative for merge — on a surface that already carries a live ADR corpus (ADR-133, 150, 166, 170, 171, 172, 175, 177, 178). A future engineer reading only `work/SKILL.md` would otherwise conclude the gate was dropped rather than relocated.

### ADR

**Create `ADR-181` — provisional.** One-line decision:

> The local `scripts/test-all.sh` is a fail-fast checkpoint, not the merge gate — the merge gate is CI's required `test` aggregator (ruleset 14145388) — so `/work` Phase 2 exits on a relevance-derived subset, while `/ship` retains exactly one `TEST_GROUP=all` run because it is the sole gate for `apps/web-platform/infra/`, which no required context reaches.

That framing records the fact most likely to be re-derived wrongly (which gate is authoritative) and the one dependency that keeps the infra classes alive.

The ADR must carry: the measured cost table; the R1-R6 table with both the "gated by required CI" and "cheap to re-home" columns; the four named ceilings; the falsifiability tripwire and its review date; and an `## Alternatives Considered` section with rows for "drop the pre-review gate entirely" (the three counter-arguments), "add a second full run at ship Phase 5.5" (Cut List C2), and "let ship Phase 4 shard for speed" (**rejected — deletes the only gate R4/R5 have**; recorded here so a future optimisation PR finds the rejection rather than re-deriving the idea).

Per `wg-architecture-decision-is-a-plan-deliverable` this is authored in-session via `/soleur:architecture`, not filed as a follow-up.

Prior art worth citing in the rationale (external, treat its figures as the source's unsourced assertion): the `smoke → selective → full` tiering vocabulary from `regression-testing` (proffesor-for-testing/agentic-qe), surfaced by the community-discovery pass and **not** adopted as a dependency.

**Ordinal provenance.** `ADR-181` was derived by enumerating `knowledge-base/engineering/architecture/decisions/` across **all 63 `refs/remotes/origin/*` refs** (not `origin/main` alone), whose maximum is `ADR-180`. Per the Sharp Edge, this is a *claim, not a reservation* — re-run the all-refs probe immediately before merge, and if it moves, sweep `knowledge-base/project/{plans,specs}/feat-one-shot-7352-fullsuite-gate-post-review/` for the old ordinal in the same edit so no AC verifies a nonexistent file.

### C4 views

**No C4 impact.** All three model files were read, not grepped for the feature's own noun. The enumeration checked:

- **External human actors** (`views.c4` include lists): `founder`, `emailSender`, `betaContact`, `contributor` — this change adds no actor and alters no actor's relationship to any surface.
- **External systems / vendors** (`views.c4` `context` + `containers`): `anthropic`, `github`, `cloudflare`, `doppler`, `discord`, `stripe`, `plausible`, `resend`, `pushService`, `ghcr`, `projectZot`, `zotRegistry`, `betterstack`, `sentry`, `sigstore`, `letsencrypt`, `publicResolvers`, `systemdUser` — none added, none touched.
- **Containers / data stores**: every `platform.infra.*` in the `containers` view — none touched.
- **Access relationships**: unchanged. The affected components are already modelled at C4 L3 — `model.c4:115` `work = component "work skill"` (description "Executes plans with incremental commits and test-first"), `:119` `review`, `:127` `ship` ("Validates artifacts, creates PR, manages merge lifecycle"), `:131` `oneshot`. **No description is falsified**: neither names a test gate, and `grep -niE "test-all|test suite|full suite|quality gate" model.c4` returns zero hits — the model does not represent test gates at any level.

No `.c4` edit is therefore in scope, and consequently `scripts/regenerate-c4-model.sh` and `c4-model-freshness.test.sh` are not triggered by this PR (which is also why this PR cannot serve as the R2 regression proof — see Test Scenarios).

### Sequencing

The decision is true the moment both SKILL.md edits land; nothing is soak-gated. ADR status is `accepted`, not `adopting`.

## Acceptance Criteria

### Pre-merge (PR)

1. **AC1** — `plugins/soleur/test/fullsuite-merge-gate.test.ts` exists and its five assertions pass: `bun test plugins/soleur/test/fullsuite-merge-gate.test.ts` exits 0.
2. **AC2** — the new suite appears in the run log of `bun test plugins/soleur/` (per `work/SKILL.md:725`: "it will be picked up automatically" is false by default here — confirm the label appears).
3. **AC3** — mutation proof, one per assertion: for each of the five, mutate the corresponding source line in a scratch copy and record that the guard exits non-zero; restore. Five mutations, five REDs, recorded in the PR body. A uniform mutation set does not count — each must edit a different assertion's target (`review/SKILL.md:1231`: "N mutations of one shape is one mutation"). The mutation for assertion 1 must be *sharding* the ship command (`bash scripts/test-all.sh webplat`), not deleting it — deletion is the easy mutation and the wrong threat.
3b. **AC3b** — the `FULLSUITE_SHA`-unset arm is proved separately: with the variable unset, the Phase 6.4 assertion must fail, not pass. A gate that compares equal when unset is the `null == '0'` class (`work/SKILL.md:671`).
4. **AC4** — `grep -c '\[skill-enforced: work Phase 2 exit\]' plugins/soleur/skills/work/SKILL.md` returns ≥ 1 (the enforcement-tag anchor survives).
5. **AC5** — `python3 scripts/lint-agents-enforcement-tags.py AGENTS.md AGENTS.rules.md` exits 0.
6. **AC6** — every one of the eleven `work/SKILL.md` line entries in `## Files to Edit` shows a change in `git diff origin/main...HEAD -- plugins/soleur/skills/work/SKILL.md`, verified by content anchor (not line number). Specifically, none of these anchors survives unqualified in the diff's post-image: `Run the full test suite after each RED/GREEN/REFACTOR cycle`, `Place a final "Run full test suite and lint" task`, `Run full test suite after changes`, `# Run full test suite (use project's test command)`.
7. **AC7** — the four reading-discipline passages are still present verbatim in `work/SKILL.md`, each verified by a distinctive substring: `The exit gate only describes the tree you launched it against`, `Sibling-worktree contention produces a FALSE RED`, `A long run can be reaped by the HARNESS`, `Doppler-env false-positive caveat`. **This is the "do not weaken" assertion.**
8. **AC8** — the coverage-NOTE literals are unmodified: `git diff origin/main...HEAD -- scripts/test-all.sh` is empty, and `grep -c 'is NOT covered above' plugins/soleur/skills/work/SKILL.md` and the same against `ship/SKILL.md` are each ≥ 1.
9. **AC9** — the position-agnostic banner grep at `work/SKILL.md:670` is byte-identical to its pre-change form (`grep -F` for the literal `NOTE:|NOTE \(|\[contention\] BANNER|LOCK_CONTENDED`).
10. **AC10** — `ship/SKILL.md` Phase 4 names CI's required `test` context (ruleset 14145388) as the merge gate, names itself as the last local fail-fast checkpoint and the sole gate for `apps/web-platform/infra/`, and Phase 6.4 contains the infra-scoped `HEAD == $FULLSUITE_SHA` assertion with a re-run arm. Verified by the guard test (AC1 assertions 1-2), not by a hand grep. **`ship/SKILL.md` must NOT contain the claim that the local run is the merge gate** — `grep -c 'test-all.sh.*is the merge gate' plugins/soleur/skills/ship/SKILL.md` returns 0.
10b. **AC10b** — the required-context claim is re-verified at ship time, not trusted from plan time: `gh api repos/:owner/:repo/rulesets/14145388 --jq '[.rules[]|select(.type=="required_status_checks").parameters.required_status_checks[].context]'` contains `test` and contains **no** infra context. A branch-protection change between plan and merge would falsify the ADR's central claim; this is the same shelf-life discipline as the ADR ordinal.
11. **AC11** — `bun test plugins/soleur/` is green, and `npx --yes markdownlint-cli` on every changed `.md` file exits 0. **Run the gate's own invocation**, not a hand-enumerated path list — per `2026-07-28-my-ac-verified-four-paths-while-ci-verified-five.md`, an AC whose scope differs from the gate's scope can stay green while the gate reds.
12. **AC12** — the value proposition is measured once, on a quiet machine (no sibling worktree run — confirm via the contention preamble showing no `SIBLING_RUN_DETECTED` / `SIBLING_SUITE_DETECTED` banner). Record in the PR body: wall-clock of `bash scripts/test-all.sh` vs. wall-clock of the derived touched-file set for the same diff, with both commands quoted. If the machine is not quiet, record `UNMEASURED — sibling run detected` rather than a contended number.
13. **AC13** — `ADR-181` (or its re-derived ordinal) exists, carries the R1-R6 re-homing table and the three counter-arguments to dropping the gate, and the ordinal is re-verified against all `refs/remotes/origin/*` immediately before merge. If it moved, `grep -rn 'ADR-181' knowledge-base/project/{plans,specs}/` returns zero.
14. **AC14** — the full battery is green at the SHA that merges: `bash scripts/test-all.sh` run at ship Phase 4, `rc` read from the rc file (never the harness notification), the terminal `=== N/M suites passed ===` marker present, and the epilogue NOTE + contention banners read per `work/SKILL.md:670`.
15. **AC15** — PR body uses `Closes #7352`.

### Post-merge (operator)

None. Every step above is automatable in-session: the guard test and mutations run under Bash, the ADR is a file write, the ordinal probe is `git for-each-ref` + `git ls-tree`, and the merge is `gh pr merge --squash --auto`. No browser, console, or dashboard step exists in this change.

## Test Scenarios

### RED-phase targets (Phase 1)

- `fullsuite-merge-gate.test.ts` — ship Phase 4 holds `bash scripts/test-all.sh` in a fenced block. **Fails** before Phase 3 only for assertion 2; assertion 1 passes on `origin/main` already (Phase 4 pre-exists). Stated honestly rather than pretending a false RED: assertion 1 is a **regression lock**, not a RED target, and its mutation proof (AC3) is what earns it.
- ship Phase 4 records a SHA and Phase 6.4 asserts equality — genuinely RED before Phase 3.
- `work/SKILL.md` retains `[skill-enforced: work Phase 2 exit]` — a regression lock on the Phase-2 edit.
- `work/SKILL.md` §9 fenced blocks hold no unconditional `bash scripts/test-all.sh` — genuinely RED before Phase 2.

### Regression tests

- The four "do not weaken" passages (AC7) and the coverage NOTE literals (AC8) are asserted, not assumed.

### Edge cases

- **A diff that touches nothing derivable.** A pure-`knowledge-base/**` diff derives an empty vitest set and an empty symbol set. The gate must not report green on an empty set — it must report *what it ran* and, when the set is empty, say so explicitly. A silent empty set is the `2026-07-24` fail-open class ("a gate must fail CLOSED on every indeterminate outcome, including 'I could not measure this'").
- **A diff whose symbol grep returns hundreds of files.** The derived set can exceed the full battery in cost. Cap behaviour: if the derived set exceeds the battery's suite count, run the battery instead — cheaper *and* strictly more coverage.
- **R2 cannot be proved by this PR.** This change edits no `.c4` file, so the c4 coupling re-point (line 589) is verified by reading, not by a live red. Named as a limitation rather than papered over.

## Risks & Mitigations

| Risk | Mitigation |
|---|---|
| The touched-file set under-derives and R1/R4-class breakage reaches review | The symbol-graph rule (`git grep -l '<symbol>'`) is mandatory, not advisory, and is the repo's own canonical idiom. R6 is explicitly accepted as surviving to the merge gate. |
| The guard test is vacuous — a prose grep satisfied by a comment | AC3 requires four *distinct-shape* mutations, one per assertion. Assertions anchor on the imperative inside a fenced block, never on a bare token. |
| The SHA pin is mis-wired and silently always passes | Its mutation (AC3) must red. Additionally the assertion must fail-closed when `FULLSUITE_SHA` is unset — an unset variable comparing equal to anything is the `null == '0'` coercion class (`work/SKILL.md:671`). |
| Rebase collision with `feat-one-shot-test-pipeline-efficiency` | Its `work/SKILL.md` edits are near line 269; §9 is at 742. Expect a touch-up, not a conflict. Do not read or reset that branch or worktree. |
| The ADR ordinal is claimed by a sibling mid-pipeline | AC13 re-runs the all-refs probe before merge and sweeps planning artifacts on renumber. This has collided twice in one session before (#5990). |
| Removing the Phase-2 full run also removes the only place some authors ever saw a contention banner | The four reading-discipline passages stay in `work/SKILL.md` (AC7), and ship Phase 4 links them. |
| **A future PR shards ship Phase 4 for speed, deleting the only gate R4/R5 have** | The highest-consequence risk in this plan. Three defenses: named ceiling 2 in the plan, an explicit rejected-alternative row in the ADR (so an optimiser finds the rejection instead of re-deriving the idea), and guard assertion 1, whose mutation proof is *sharding* the command rather than deleting it. |
| Branch protection changes between plan and merge, falsifying the ADR's central claim | AC10b re-queries ruleset 14145388 at ship time. Same shelf-life discipline as the ADR ordinal. |
| Sequencing against PR #7441 is wrong because its contents were not read first-hand | The dependency is recorded as **agent-sourced and unverified by this session** (see `## Sequencing`), and is framed as a decision point with a stated fallback, not as an asserted blocker. |
| The relaxation is unfalsifiable — nothing measures whether it causes escapes | A tripwire is declared in the ADR with a review date; automating the count is deferred with a tracking issue (`## Deferred`), because it needs a data source spanning many PRs. |

## Success Metrics

- Full-suite invocations per PR on the Claude Code arm: 2 → 1.
- `/work` Phase 2 exit wall clock: full-battery duration → ~1-2 min on a representative diff (AC12 records the measured pair).
- Advisory-lock queue events per PR across concurrent worktrees: halved by construction (one acquisition instead of two).
- Zero change to what reaches `main` for R1-R3: CI's required `test` context (ruleset 14145388) runs the same three `test-all.sh` shards on the PR head, independent of anything this plan touches.
- Zero change to what reaches `main` for R4-R5: still gated by exactly one local `TEST_GROUP=all` run, now additionally pinned to the merging tree when the diff touches `apps/web-platform/infra/`.
- Escape rate (the falsifiability tripwire): PRs whose required `test` context reds after a green local touched-file gate. Target 0; tripwire threshold and review date recorded in the ADR.

## Sequencing

The CTO advisory recommends landing PR #7441 (`feat-one-shot-test-pipeline-efficiency`) **first**, on four grounds: it introduces a `skip_suite()` "a decline is a counted verdict" taxonomy that a touched-file gate needs; it ships `scripts/lib/test-relevance-paths.sh` with a fail-closed linter that is the natural substrate for this plan's relevance derivation; it adds a standing "the lead runs the gate ONCE" constraint to the same `work/SKILL.md` region; and it adds `plugins/soleur/test/fanout-suite-scope.test.sh`, which may anchor on the very prose this plan rewrites. It also reports that PR as currently red on `adr-ordinals` and `test-bun`, with an ADR-178 ordinal collision.

**Provenance, stated plainly: this session did not verify any of it.** The brief prohibits reading that branch or worktree, so the findings are agent-sourced and second-hand. They are recorded because a wrong sequencing decision is expensive, not because they are established.

**Decision.** Treat #7441 as a *preferred predecessor*, not a hard blocker:

- If #7441 has merged when `/work` begins, adopt its `skip_suite()` vocabulary and `test-relevance-paths.sh` substrate rather than authoring a parallel one, and re-read the `work/SKILL.md` region for its "lead runs the gate ONCE" constraint so the two statements stay consistent.
- If it has not merged, proceed. Nothing in this plan's Files-to-Edit overlaps its reported hunk (`@@ -269 @@` in `work/SKILL.md`; §9 is at line 742), and this plan deliberately introduces **no** new selection script (Cut List C1), so there is nothing to collide with structurally. Expect a rebase touch-up.
- Either way, verify at `/work` Phase 0 whether `plugins/soleur/test/fanout-suite-scope.test.sh` exists on `origin/main` and whether it asserts on the §9 prose. If it does, its assertions are added to this plan's Files-to-Edit before §9 is rewritten.

## Deferred

- **Automated escape-rate measurement for the falsifiability tripwire.** Counting "PRs whose required `test` context reds after a green local touched-file gate" needs a data source spanning many PRs and a place to keep the running count; it is a separate work-stream, not a line in this diff. File a tracking issue at `/work` time with: what is deferred, why (needs cross-PR data), the re-evaluation criterion (the tripwire threshold and date recorded in the ADR), and the milestone from `knowledge-base/product/roadmap.md`. Per `wg-defer-only-after-inline-triage` this was triaged inline first — the *tripwire itself* ships in the ADR now; only its automation defers.

## Domain Review

**Domains relevant:** engineering

### Engineering (CTO)

**Status:** reviewed

**Assessment:** Materially corrected the plan's central premise. (a) The local `test-all.sh` is not and never was the merge gate — CI's required `test` context (ruleset 14145388, aggregating three `test-all.sh` shards) is; this makes the change safer than the issue argues for R1-R3 and relocates the single real gap to `apps/web-platform/infra/`, which no required context reaches. (b) Ship Phase 4 is not the post-all-code-changes position: Phase 5.5 contains multiple code-mutating gates after it, which independently confirms the SHA-pin design and forces the "last local fail-fast checkpoint" naming instead of "the merge gate". (c) Named the four ceilings, of which "ship Phase 4 must stay `TEST_GROUP=all`" is the load-bearing one; flagged the enforcement gap (nothing would assert the *new* gate either) as blocking, citing ADR-166 "enforcement is the lint, not the prose". (d) Confirmed the ADR is warranted, supplied the decision line, and corrected the ordinal to 181. (e) Judged PR #7441 complementary with a medium semantic dependency, recommending it land first.

**Disposition:** all five folded in. The two claims the advisory itself flagged as unverified were independently checked here — the required-context list was queried directly (`gh api repos/:owner/:repo/rulesets`) and confirms no infra context; the `fanout-suite-scope.test.sh` question is deferred to `/work` Phase 0 because verifying it requires reading a branch this session is prohibited from reading.

**Threshold challenge (accepted):** the advisory argued `single-user incident` over the drafted `aggregate pattern`, on the checkable ground that `user-impact-reviewer.md:13` self-exits on `aggregate pattern` while its Meta-workflow branch exists specifically for `plugins/soleur/skills/**` diffs at `single-user incident`. Verified by reading the agent file; threshold and `requires_cpo_signoff` updated, and the User-Brand Impact section rewritten to enumerate second-order fail-open modes rather than an empty direct-exposure list.

### Product/UX Gate

Not applicable. The mechanical UI-surface override does not fire: no path in `## Files to Edit` or `## Files to Create` matches the UI-surface term list or glob superset (`components/**/*.tsx`, `app/**/page.tsx`, `app/**/layout.tsx`). The change is orchestration and documentation, which the gate's own text names as NONE.

### Other domains

Not relevant. No legal, marketing, sales, finance, operations, or support surface is touched — the diff is two workflow SKILL.md files, one guard test, and knowledge-base artifacts.

## References & Research

- Issue #7352 — the operator-approved decision, its measurements, and the "do not weaken" constraints.
- ADR-133 — `knowledge-base/engineering/architecture/decisions/ADR-133-test-all-tmpfs-contention-managed-resource-and-advisory-lock.md`
- `plugins/soleur/skills/review/SKILL.md:1305` — derive the consumer set from symbols, repo-wide, never from expected directories.
- `knowledge-base/project/learnings/2026-05-05-defense-relaxation-must-name-new-ceiling.md`
- `knowledge-base/project/learnings/test-failures/2026-06-15-source-grep-test-breaks-on-symbol-extraction-only-full-suite-catches.md`
- `knowledge-base/project/learnings/2026-06-29-c4-source-edit-requires-regenerate-model-json-orphan-suite.md`
- `knowledge-base/project/learnings/2026-05-29-legal-doc-triple-lockstep-and-rpc-grants-invoker-before-definer.md`
- `knowledge-base/project/learnings/2026-05-29-target-allowlist-extension-must-sweep-all-guard-suites.md`
- `knowledge-base/project/learnings/2026-06-16-infra-test-orphan-suites-and-node-options-env-file-clobber.md`
- `knowledge-base/project/learnings/2026-05-11-test-all-exit-gate-self-validated-on-creating-pr.md`
- `knowledge-base/project/learnings/2026-07-24-a-security-gate-detector-nearly-shipped-the-false-green-it-was-built-to-prevent.md`
- `knowledge-base/project/learnings/2026-07-20-i-fixed-three-unfailable-gates-and-shipped-eight-more.md`
- `knowledge-base/project/learnings/2026-07-28-my-ac-verified-four-paths-while-ci-verified-five.md`
- **Community discovery:** three registries queried (`api.claude-plugins.dev`, `claudepluginhub.com`, Anthropic marketplace), ~15 queries across both the mechanism (affected-test selection) and the policy (tiered test gates). Closest candidate `regression-testing` (proffesor-for-testing/agentic-qe, 123★) self-declares `trust_tier: 3` and targets product test suites, not a plugin's own workflow prose. **Recommendation: proceed in-repo, no community adoption.** Its `smoke → selective → full` tiering vocabulary is usable as cited prior art in the ADR's rationale, treating its "70-90% time saved / ~90% regressions caught" figures as that project's unsourced assertion, not established fact.
