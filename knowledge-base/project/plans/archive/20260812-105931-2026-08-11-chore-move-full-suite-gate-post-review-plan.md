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

## Operator Decisions (2026-08-12) — AUTHORITATIVE

`plan-review` classified this session as headless and therefore **persisted** the three
`decision-challenges.md` items rather than asking. That premise was wrong — the session is
interactive. Both open items were put to the operator and answered. These answers **override** any
contrary statement elsewhere in this plan; where they conflict, this section wins.

### OD1 — UC1 resolved: apply CPO's C1 conditional (NOT the narrow-to-§9 option)

The four project-agnostic lines (`work/SKILL.md:243`, `:337`, `:668`, `:818`) **are** relaxed, but
each carries the conditional: *when the project has no CI-enforced full-suite gate on the merge
branch, the full battery stays at implementation exit.* §9 and `ship/SKILL.md` — both already
Soleur-coupled — are relaxed unconditionally as planned.

This closes the `## Risks & Mitigations` row "The relaxation ships to users whose repo has neither
backstop": the compensating gate is the conditional itself, so a self-hosted user with no CI gate
keeps today's behaviour and loses nothing.

**The detection question is IN SCOPE for `/work`, not deferred.** CPO routed "how does the pipeline
detect whether a project has a CI-enforced full-suite gate?" to CTO at spec time, and the operator
selected this option knowing that. `/work` must answer it concretely before Phase 2 edits land.
Constraints on the answer:

- These are **skill prose lines an agent reads**, not executable code — so "detection" means a
  cheap, bounded check the reading agent performs, not a new script (Cut List C1 still forbids a new
  selection script, and OD1 does not reopen it).
- It must degrade **fail-safe**: unknown / unprobeable ⇒ treat as "no CI gate" ⇒ run the full
  battery at implementation exit. The relaxation is the privileged branch and must never be the
  default under uncertainty.
- It must not assume `gh` auth, a GitHub remote, or a ruleset API scope — a self-hosted user may
  have none of these, and an unauthenticated probe failure must land on the safe branch above.

### OD2 — UC2 resolved: HOLD THE MERGE until #7441 lands and a combined verification passes

The operator chose the sequencing option, not the proceed-now default. Consequences, binding on
`/ship`:

- **Implementation, review, and QA proceed now.** The hold is on the merge, not on the work.
- **This PR stays a DRAFT** through `/ship`. Do not mark it ready, do not `gh pr merge`, and do not
  enable `--auto`. `wg-verified-work-ships-without-asking` does **not** apply — the operator has
  given an explicit contrary sequencing instruction, which outranks the default.
- **Merge precondition:** PR #7441 is merged to `main`, this branch is rebased onto it, and a
  **combined** verification (`TEST_GROUP=all bash scripts/test-all.sh` on the rebased tree, per AC9)
  is green. Only then does this PR go ready.
- **Record the merge date against #1442** (usage tracking) so the alpha window's data stays
  interpretable, and note the sequencing in the PR body.
- This upgrades `## Sequencing` below: #7441 moves from *preferred predecessor* to a **hard merge
  blocker**. Its "if it has not merged, proceed" arm still governs *implementation* order only.

### OD3 — UC3 (milestone placement) — not asked, remains open

Non-blocking for implementation. Carried into the PR body and the `action-required` issue as before.

## Enhancement Summary

**Deepened on:** 2026-08-11

**Gates run:** 4.6 User-Brand Impact (pass, `single-user incident`) · 4.7 Observability (**halted** — the drafted "not applicable" claim was wrong; `plugins/*/skills/*.md` is inside the non-exempt set, so a real 5-field block was written) · 4.8 PAT-shaped (clean) · 4.9 UI wireframe (skip, no UI surface) · 4.10 Encryption posture (skip, no store/connection) · 4.55 Downtime (skip, no serving-surface change).

**Realism passes (Phase 4.45):** verify-the-negative confirmed all 7 surviving factual claims live; post-edit self-audit found 5 stale-live defects introduced by the plan-review revision, all corrected — the assertion count still read "two" in three places, the cut falsifiability tripwire was still prescribed as live in four, cut ACs (AC10b, AC12) were still cited as active mitigations, and an orphaned AC13-15 block duplicated AC8-10 with a *weaker* AC14 that reintroduced the deleted SHA-pin phrasing.

### Key improvements this pass

1. **Observability block is now real and runnable** (`bun test plugins/soleur/test/fullsuite-merge-gate.test.ts`), not an exemption argument.
2. **Internal consistency restored** after the heavy plan-review cuts — the plan no longer prescribes anything it also records as deleted.
3. **Every load-bearing negative claim re-verified against the repo**, including the two that reversed the plan's original design (R4 is CI-gated; R5 is gated by nothing).

### Note carried forward, not acted on

`scripts/test-all.sh:129`'s comment says "21 plugins/soleur/test/*.test.sh"; the real count is **65**. Pre-existing stale comment in the runner, unrelated to this plan's claims — worth a one-line fix in a passing PR, not this one.

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
- **P3** — a red observed after review fixes is attributable to the review fixes, **within the coverage of the shards the Phase-2 gate ran**. *[CORRECTED after review: the drafted P3 claimed unqualified attribution, which the design falsifies — the pre-review checkpoint is green over a shard subset while the post-review check is the full battery, so a Phase-4 red can equally be R4/R5/R6 breakage from the original implementation that the subset never covered. P3 is weakened, not preserved, and the ADR must record the weakened form: it is one of the three legs justifying keeping any Phase-2 gate at all, and it would otherwise be re-derived as intact.]*
- **P4** — per-PR contention on the repo-wide advisory lock and the shared 4 GiB tmpfs (ADR-133) is halved, a cost borne by every concurrent worktree, not only the running session.
- **P5** — whether the nested infra runner actually executed remains readable at whichever position runs the full battery (the two-polarity coverage NOTE).
- **P6** — contention banners remain read and interpreted, so a false RED is still distinguishable from a real one.
- **P7** — the suite set the Phase-2 gate runs is derived from what actually gates the changed files, not from the directories a planner expects.

### Cut List (Phase 0.6b) — mechanisms removed before research

Each row: mechanism → property it would buy → what already on `origin/main` buys it. Every "already covered" claim was grepped against the authority, and the authority is named.

- **C1 — a bespoke touched-file test-selection script.** Property P1/P7. Already bought three ways: (a) `apps/web-platform` runs **vitest 4.1.0** (`apps/web-platform/node_modules/.bin/vitest --version` → `vitest/4.1.0 linux-x64 node-v22.22.2`), whose `--changed [since]` flag runs tests *affected by* the changed files via the module graph — `--help` prints `--changed [since]   Run tests that are affected by the changed files (default: false)`, and a live `vitest list --changed origin/main --filesOnly` on this branch exits 0; a `related [...filters]` subcommand also exists. (b) `lefthook.yml` pre-commit already scopes markdownlint (`glob: "*.md"`, `run: npx --yes markdownlint-cli {staged_files}`, line 21), gitleaks (`--staged`, line 31), `lint-fixture-content.mjs {staged_files}` (line 50), `lint-infra-no-human-steps.py {staged_files}` (line 122), `lint-scheduled-show-full-output.sh {staged_files}` (line 132), `gdpr-gate.sh {staged_files}` (line 202), and a full `cd apps/web-platform && npx tsc --noEmit` (line 138) — and `/work` already makes incremental commits, so these fire per commit without any new gate. (c) the repo's canonical set-derivation idiom for the *non*-module-graph half already exists at `review/SKILL.md:1305`: "derive the set from where the changed file's SYMBOLS are referenced, repo-wide (`git grep -l '<symbol>'`), never from the directories you expect."
- **C2 — a NEW "Full-Suite Pre-Merge Gate" section at ship Phase 5.5.** Property P2/P3/P5/P6. Already bought by `ship/SKILL.md` Phase 4 (line 300), which runs `bash scripts/test-all.sh` (line 333) and already carries the epilogue-reading discipline and the "do NOT run `run-registered-suites.sh` alongside it" contention warning (lines 337-350). Adding a second run would *add* a third full-suite invocation per PR — the exact cost this issue exists to remove. The ship-side edit is therefore a **re-statement of the existing Phase 4**, not a new gate.
- **C3 — a new linter list authored into work Phase 2 exit.** Property P1. Already bought by `lefthook.yml` pre-commit (C1b). A hand-maintained parallel list in prose would drift from `lefthook.yml` the first time a linter is added there, reproducing the hand-maintained-allowlist class the repo has already been bitten by (`knowledge-base/project/learnings/2026-05-29-target-allowlist-extension-must-sweep-all-guard-suites.md`).

### Value-Proposition Measurement (Phase 0.6c)

The justification is a cost saving, so the saving is quantified and its provenance named.

**Carried from the issue** (measured during PRs #7344 / #7343, not re-measured here): a touched-file baseline on a 24-file diff ran **224 assertions in ~90 s**; the same PR's full run had its infra runner alone take **573 s**, be reaped by harness limits **4 times**, and serialise **2694 s** behind a sibling worktree holding the repo-wide advisory lock.

**Measured this session:**

- `scripts/test-all.sh` accepts `TEST_GROUP` ∈ `all|webplat|bun|scripts|infra` (`scripts/test-all.sh:140-157`) and has **no diff-scoped mode**. Its only diff-relevance gate is `_infra_in_diff` (`scripts/test-all.sh:384-391`), which decides whether to *invoke the nested infra runner*, not which suites to run. So "run only what the diff touches" is not a flag on the existing runner; it is a different command set.
- `vitest 4.1.0` `--changed` verified live (see C1a). This is the single largest shard and it already supports the scoping.

**Not re-measured, deliberately.** A fresh `time bash scripts/test-all.sh` now would contend with the live sibling worktree `feat-one-shot-test-pipeline-efficiency` for the same advisory lock and tmpfs — i.e. the measurement would both perturb that session and be perturbed by it, which is precisely the contention ADR-133 documents. The paired A/B that *would* settle it is recorded as a PR-body reporting obligation instead, to be run on a quiet machine. It is deliberately not an AC: its only honest form carries an always-available `UNMEASURED` escape hatch, and an AC that cannot fail is not an AC.

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
| R4 | Scope guards under a different name stem — extending a hand-maintained allow-list (terraform `-target=`, a CSRF route set, an RLS table list) syncs the filter and its counter but misses the guard | `.../2026-05-29-target-allowlist-extension-must-sweep-all-guard-suites.md` | **`bun`** | **YES — the drafted "real gap" was wrong** | **Already covered.** Verified: `plugins/soleur/test/terraform-target-parity.test.ts:2055` — `describe("registry gate allow-sets match their jobs' -target sets")` — IS the R4 guard, it lives in `plugins/soleur/test/` and so runs under `scripts/test-all.sh:883` `run_suite "plugins/soleur" bun test plugins/soleur/`, inside the required `test` aggregator. R4 already blocks merge. |
| R5 | `apps/web-platform/infra/*.test.sh` orphans — not glob-discovered; each needs a named step in `infra-validation.yml` | `.../2026-06-16-infra-test-orphan-suites-and-node-options-env-file-clobber.md` | `infra` | **NO — and nothing else gates it either** | **No, and the drafted mitigation was illusory.** `ci.yml:177` `lint-orphan-test-suites.sh` lives in job `lint-bot-statuses`, which `ci.yml:119-120` labels in terms: *"ADVISORY job — absent from `scripts/required-checks.txt` and the ruleset, so a PR can merge with it red"* — **and its scope is `scripts/*.test.sh`, not `apps/web-platform/infra/`**. `run-registered-suites.sh` `report_orphans()` prints a NOTE rather than failing. So R5 orphans are gated by **nothing, before or after this plan**. |
| R6 | Everything else — a sibling asserting on a changed literal with no shared symbol | The issue's own "Accepted cost" paragraph | mixed | Mostly yes | **No.** Accepted cost. |

**The named ceilings, therefore:**

1. **CI's required `test` context (ruleset 14145388) is the merge gate for R1-R3 and most of R6.** Stated explicitly so a future reader does not re-derive it wrongly.
2. **`/ship`'s local run must stay `TEST_GROUP=all`, never a shard** — it is the only *enforcing* gate the registered `apps/web-platform/infra/` suites have, since `infra-validation.yml` is not a required context. If it is ever allowed to shard, that coverage disappears with no CI backstop. **This is the single most load-bearing sentence in the plan**, and the guard test's one assertion exists solely to hold it.
3. **The infra coverage NOTE becomes *more* load-bearing, not less.** Since the local `TEST_GROUP=all` run is the sole enforcing gate there, the `IS covered above` / `is NOT covered above` epilogue is the only signal that those suites were measured on this diff. This is the mechanical reason the issue's "do NOT weaken the epilogue check" instruction is correct.

*(A fourth ceiling — a falsifiability tripwire — was drafted and is cut. It read: "if a PR's required `test` context reds after a green local gate more than N times in a month, restore the unconditional Phase-2 run." `N` was never specified and the counting was deferred to an issue nobody would action, which makes it a promise to measure that reads as falsifiability without providing any. The honest replacement is one line in the ADR: if this bites, put it back.)*

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

### 1. `/work` Phase 2 exit runs a SHARDED `test-all.sh`, not a hand-derived command set

**[REVISED after plan-review — this replaces a raw `vitest --changed` + `git grep` derivation.]**

§9 is re-titled and its prescription changes from `bash scripts/test-all.sh` (all four shards) to **the `TEST_GROUP` shards the diff touches**:

```bash
# one or more of, per the shard map below:
TEST_GROUP=bun bash scripts/test-all.sh
TEST_GROUP=scripts bash scripts/test-all.sh
TEST_GROUP=webplat bash scripts/test-all.sh
```

Shard map, derived from `scripts/test-all.sh:150-157`, not hand-maintained: diff touches `apps/web-platform/**` → `webplat`; `plugins/soleur/**`, `scripts/**`, `.claude/hooks/**`, `tests/**`, `AGENTS*.md` → `bun` and/or `scripts`; `apps/web-platform/infra/**` → **defer to ship**, because `TEST_GROUP=infra` is the 573 s runner and its classes (R4/R5) are gated there anyway.

**Why this shape rather than a derived command set.** The first draft prescribed `vitest run --changed origin/main` plus a repo-wide `git grep -l '<symbol>'` per changed symbol. Five reviewers converged on that being the weakest part of the plan, and a sharded `test-all.sh` dissolves all of it:

- **It keeps the contention preamble.** `scripts/lib/test-contention.sh:423,457` fires `SIBLING_RUN_DETECTED` / `SIBLING_SUITE_DETECTED` / `LOW_TMP_HEADROOM` on *any* `test-all.sh` invocation. `one-shot/SKILL.md:106` records (#7247) that a duplicate-implementation collision "surfaced only because `test-all.sh` printed a `SIBLING_RUN_DETECTED` banner naming the sibling worktree, **after a full RED→GREEN cycle had been built and had to be reverted**". A raw vitest+grep gate emits no banner, so the earliest sibling-collision signal would have moved past the 8-10-agent review fan-out — landing that cost on the wrong side of this plan's own ledger. This was the missed side-effect role the defense-relaxation rule exists to catch.
- **It keeps the failure taxonomy.** The `EXIT CONTRACT` (`scripts/test-all.sh:4`), the terminal `=== N/M suites passed ===` marker, the rc file, and the `rc=3` UNRESOLVED class all apply unchanged. An ad-hoc command set has none of them — and `vitest run --changed` with zero matches exits 1 (`passWithNoTests` defaults false), which is indistinguishable from a real red by exit code alone.
- **It has no empty-set state.** A shard always runs a defined suite list, so the "empty derived set" fail-open — the plan's own worst failure shape, and the one its *own dogfood diff* landed in — cannot arise. No stop-condition prose, no cap rule, no `git fetch origin main` precondition on a derivation that no longer exists.
- **It needs no new mechanism.** `TEST_GROUP` already exists and is already how CI shards. This is the honest version of Cut List C1: the cheapest mechanism that buys P1/P4/P7 was already in the runner.
- **It preserves per-cycle cost sanity.** The rewritten `work/SKILL.md:668` says "run the shard(s) your diff touches" — a bounded, repeatable command, not a repo-wide grep per changed symbol per TDD cycle.

**Path-triggered couplings stay where they already are**, re-pointed in place: `work/SKILL.md:589` (`.c4` → `c4-model-freshness.test.sh`) and `:768` (new `docs/legal/*.md` heading → `legal-doc-consistency.test.ts` + mirror). Both are in the `scripts`/`webplat` shards, so the shard map already reaches them; the edit only corrects their "full-suite-only" phrasing. §6 "Infrastructure Validation" (line 686) already owns the `apps/*/infra/` trigger.

**Linters.** `lefthook.yml` pre-commit already scopes them per commit. But the obligation is stated as *checkable*, not honour-system: `work/SKILL.md:588` sanctions `LEFTHOOK=0 git commit` as "common with `core.bare=true` repos" — this repo — and `lefthook.yml:295` has exactly one `pre-push` command, so there is no push-time backstop. The gate therefore says: if any commit on the branch was made under `LEFTHOOK=0`, run the corresponding linters explicitly before exiting Phase 2.

### 2. The run-reading discipline stays put and is linked from ship

The four sub-bullets at `work/SKILL.md:748, 762, 764, 766` — dirty-tree invalidation, sibling-worktree false RED, harness reaping vs. the three-way result split, the Doppler `TEST_GROUP=webplat` caveat — are about *reading a `test-all.sh` run*, not about *when to launch one*. They are retained verbatim under a sub-heading that makes their scope explicit, and `ship/SKILL.md` Phase 4's existing informal reference (line 337, "the sibling-contention shape `work/SKILL.md` documents") becomes an explicit markdown link so the merge-gate position inherits them.

### 3. `/ship` Phase 4 is named correctly, and its infra coverage is pinned to the merging tree

Phase 4 already runs the battery. Three things change, and the naming is deliberately **not** "the merge gate":

- **It is named accurately.** Phase 4's prose states that (i) CI's required `test` context — ruleset 14145388, aggregating the three `test-all.sh` shards — is the merge gate; (ii) Phase 4 is the **last local fail-fast checkpoint**; and (iii) Phase 4 is **the sole gate for `apps/web-platform/infra/`**, because no required context runs that shard. Calling Phase 4 "the merge gate" would be the same over-claim the issue makes, and would license a future PR to shard it.
- **`TEST_GROUP=all` is pinned as a requirement, with the reason.** A future optimisation that shards Phase 4 would silently delete the only gate R4 and R5 have. This is the load-bearing sentence of the whole change.
- **No re-run trigger, and no `FULLSUITE_SHA`. Both are cut.** **[REVISED TWICE. The first draft specified a `FULLSUITE_SHA` shell variable recorded at Phase 4 and compared at Phase 6.4. Three reviewers independently killed the *mechanism*: the Bash tool persists only CWD between calls, and Phase 4 (`:300`) to Phase 6.4 (`:1333`) spans ~1000 prose lines and dozens of tool calls — `ship/SKILL.md:278,284,310` is written around exactly that constraint. Combined with the drafted fail-closed-on-unset rule the gate would have failed on 100% of PRs and re-run the battery on every infra diff, silently reinstating the third full run this plan exists to remove, while the drafted mutation proof *passed* against that degenerate gate.**

  **A fourth reviewer then killed the *purpose*, which is why the state-free replacement is also cut rather than shipped.** The trigger existed to keep R4 and R5 measured on the merging tree. Verified above: **R4 is already blocked by required CI** (`terraform-target-parity.test.ts:2055` in the `bun` shard), and **R5 is blocked by nothing at all** — `lint-orphan-test-suites.sh` is in an ADVISORY job and does not scan `apps/web-platform/infra/` anyway. A mechanism protecting one class that CI already blocks and one that nothing blocks buys no property in the Property List. Per Phase 0.6b it is cut, not researched further.]**

**The one real ceiling that survives:** ship Phase 4 stays `TEST_GROUP=all`. That is what runs the *registered* infra suites, and no required context does. It is asserted by the guard test's single assertion.

**The infra gap is real but it is a RULESET gap, not a test-ordering gap.** Its correct fix is promoting `infra-validation.yml`'s `infra-validate-required` job into `scripts/required-checks.txt`, `scripts/ci-required-ruleset-canonical-required-status-checks.json`, and `infra/github/ruleset-ci-required.tf` — already parity-guarded by `plugins/soleur/test/required-checks-canonical-parity.test.sh` Test 1. Verified absent: `grep -c infra-validate-required scripts/required-checks.txt` → 0. That belongs in its own issue and must not be smuggled into a test-reordering PR as prose. See `## Deferred`.

## Technical Considerations

- **The `[skill-enforced: work Phase 2 exit]` tag at `work/SKILL.md:744` must survive verbatim.** `scripts/lint-agents-enforcement-tags.py:218` names that literal as the resolution path for the `work Phase 2 exit` anchor. Re-titling the human-readable heading is fine; deleting or re-wording the bracketed tag is not.
- **`plugins/soleur/test/components.test.ts`** rejects bare-backtick `` `scripts/…` `` / `` `references/…` `` / `` `assets/…` `` patterns in SKILL.md prose — use markdown links. This gate has fired on a SKILL.md prose edit before (`2026-05-11-test-all-exit-gate-self-validated-on-creating-pr.md`).
- **Stale self-citations.** `work/SKILL.md:642` and `:649` both end with "the full-suite exit gate is what catches it", and `:1080`/`:1081`/`:1083` describe reading a `test-all.sh` run as if Phase 2 launches it. These are content anchors that become false the moment §9 changes; they are in the edit list, not left for review to find.
- **A new `plugins/soleur/test/*.test.ts` is auto-discovered** by `bun test plugins/soleur/`; a new `*.test.sh` in that directory is **not** and needs an explicit `run_suite` line (`work/SKILL.md:725`). The guard test below is therefore `.test.ts`.
- **Guard-test vacuity is the dominant risk here.** A grep for `test-all.sh` in `work/SKILL.md` will always hit — the Sharp Edges mention it a dozen times — so a naive "the token is absent" assertion is unfailable. Per `cq-assert-anchor-not-bare-token` and `review/SKILL.md:1231(c)` (a `toContain(<symbol>)` satisfied by a *comment*), the guard asserts the **positive** invariants only, anchored on the imperative inside a fenced block, and its non-vacuity is proved by mutation.
- **Sibling-branch interaction.** `feat-one-shot-test-pipeline-efficiency` (draft PR #7441) is making the full run itself cheaper by path-gating heavy batteries inside `scripts/test-all.sh`. That is complementary: it reduces the cost of each run; this reduces the number of runs. Its uncommitted `work/SKILL.md` edits sit near line 269; §9 is at line 742, so a textual collision is unlikely, but a rebase touch-up should be expected. Its `review/SKILL.md` edits do not overlap this plan's file set.

## Files to Edit

- **`plugins/soleur/skills/work/SKILL.md`**
  - line 243 — todo-list template: "Place a final 'Run full test suite and lint' task at the end" → the touched-file gate. **PROJECT-AGNOSTIC — carries the OD1/C1 conditional.**
  - line 337 — "Run full test suite after changes" → touched-file suites. **PROJECT-AGNOSTIC — carries the OD1/C1 conditional.**
  - line 589 — `.c4` / `c4-model-freshness.test.sh` coupling: re-point "full-suite-only, not the touched-file loop" to "include this suite in the Phase 2 touched-file set when the diff touches `*.c4`".
  - line 642 — stale citation "fail only at the full-suite exit gate" → the derived symbol-graph rule.
  - line 649 — stale citation "the full-suite exit gate is what catches it" → same.
  - line 668 — "Run the full test suite after each RED/GREEN/REFACTOR cycle" → "Run the touched-file suites after each cycle". **The single largest cost line in the file. PROJECT-AGNOSTIC — carries the OD1/C1 conditional.**
  - lines 742-746 — §9 heading + body: the gate itself. Preserve `[skill-enforced: work Phase 2 exit]` at line 744 verbatim (hygiene, not a verified coupling — see Phase 1).
  - **lines 748-770 — §9 runs to 770, not 768.** Retained; re-scoped under an explicit "reading a `test-all.sh` run" sub-heading. **Six** passages, not four — the drafted list missed two that a §9 rewrite would destroy: `:750-760` (*"My edit is unrelated to the running suite" is how the exit gate gets invalidated* — #7376) and `:770` (*Feature-branch-CWD blind spot for `.claude/hooks/*.test.sh`* — #5192/#5209). Both are the same "do not weaken" class and are added to AC7.
  - line 768 — legal-doc mirror coupling: re-point *"Catch it at the full-suite exit gate"* to the shard that covers it.
  - line 818 — Phase 3 code comment `# Run full test suite (use project's test command)`. **PROJECT-AGNOSTIC — carries the OD1/C1 conditional.**

  **The four PROJECT-AGNOSTIC lines above are governed by OD1.** They are relaxed *with* the
  conditional, not left untouched and not relaxed bare. `/work` resolves the detection mechanism
  under OD1's three constraints (agent-performed check, fail-safe to "run the full battery" on any
  uncertainty, no assumption of `gh` auth / GitHub remote / ruleset scope) before these edits land.
  - lines 1080, 1081, 1083 — Sharp Edges: re-scope from "the Phase 2 gate" to "whenever you run the full battery".
- **`plugins/soleur/skills/ship/SKILL.md`**
  - lines 326-333 — Phase 4 prose: **name CI's required `test` context as the merge gate**, and Phase 4 as the last local fail-fast checkpoint and the sole gate for `apps/web-platform/infra/`. **Do NOT write "the local run is the merge gate"** — Proposed Solution §3 and AC10 both forbid it, and the drafted wording here contradicted them.
  - lines 338-339 — upgrade the informal `work/SKILL.md` contention reference to an explicit markdown link. (Line 337 is mid-sentence; the quoted phrase is at 338-339.)
  - line 369 (Phase 5 checklist; 365 is blank) — "Tests pass" → "Full suite green (Phase 4), re-run after any post-Phase-4 infra change".
  - line 1433 — reconcile with the new naming (the grok pre-push gate remains a separate push-time recheck, and makes the re-run redundant on that arm).
- **`plugins/soleur/skills/plan/SKILL.md`** — **missed in the drafted list.** Two Sharp Edges tell future *planners* the wrong thing about where these classes are caught:
  - `:1092` — *"the scope guard is an orphan suite (different name stem) that **only the full-suite exit gate** exercises … caught only by the **work Phase 2 `test-all.sh` exit gate**"*. This is the plan's own **R4** class. Left unedited, it perpetuates the exact fail-open this plan exists to close.
  - `:1076` — *"both surfaced only at the full-suite exit gate on #5005"*.

## Files to Create

- **`knowledge-base/engineering/architecture/decisions/ADR-183-full-suite-runs-at-ship-not-at-implementation-exit.md`** — provisional ordinal, see `## Architecture Decision (ADR/C4)`.
- **`plugins/soleur/test/fullsuite-merge-gate.test.ts`** — the guard (auto-discovered by `bun test plugins/soleur/`).
- **`knowledge-base/project/specs/feat-one-shot-7352-fullsuite-gate-post-review/tasks.md`**.

## Implementation Phases

### Phase 1 — RED: the guard test

**[REVISED — the drafted 5-assertion set had two assertions that could not fail and one resting on a false premise. Reduced to two.]**

Write `plugins/soleur/test/fullsuite-merge-gate.test.ts` with exactly **one** assertion:

1. **Ship keeps an UNSHARDED full run.** `ship/SKILL.md`'s Phase 4 section prescribes `bash scripts/test-all.sh` with no `TEST_GROUP` argument or prefix. This is named ceiling 2 and the only assertion guarding an irreversible loss: a future speed-PR that shards Phase 4 silently deletes the only gate R4/R5 have. Its mutation is *sharding* the command, not deleting it — deletion is the easy mutation and the wrong threat.
*(A second assertion — the infra re-run trigger — was drafted and is now cut with the mechanism it guarded. One assertion is the honest count.)*

**Cut from the drafted set, with reasons — each was caught by review, not by me:**

- *"§9 contains no unconditional `bash scripts/test-all.sh` in a fenced block"* — **§9 has zero fenced blocks.** Lines 742-770 contain no fence; the first fence in that region is at `:782`, inside Phase 2.5. The §9 prescription at `:746` is inline backticks in a prose paragraph. So the assertion passes on `origin/main` today, is not a RED, and can *never* fail — a future editor restoring the imperative in the same inline form keeps it green forever. Exactly the unfailable-guard class the plan's own Technical Considerations calls "the dominant risk here".
- *"the enforcement-tag anchor survives"* — **the coupling is false.** Kieran mutated `work/SKILL.md:744` to `[skill-enforced: DELETED]` and re-ran the linter: `rc=0`, `OK: 10 hook + 30 skill tag(s) resolved`. `AGENTS.rules.md` contains no `work Phase 2 exit` anchor at all (`:54`'s tags are `[hook-enforced: lefthook gdpr-gate.sh] [skill-enforced: plan/work/ship gates]`). AC4 and AC5 could not detect the deletion they were nominated to detect. The tag is still preserved as good hygiene, but it gets no assertion and no AC.
- *"the derivation rule is present"* — dissolved with the derivation itself (Proposed Solution §1). There is no longer a derivation to assert.
- *the SHA-pin assertion and AC3b* — dissolved with `FULLSUITE_SHA`.

The single assertion passes on `origin/main` today and is a **regression lock**, not a RED target — stated plainly rather than dressed up as a failing test, since its whole value is earned by the AC2 sharding mutation. This plan therefore has **no RED phase**, which is the honest consequence of every other mechanism being cut. It anchors on content, never a line number, and slice sections with the flag-based awk form (`/A/{flag=1;next} /B/{flag=0} flag`), never `/A/,/B/`, which self-matches on the start line. The slice anchors must be retitle-stable: use the `## Phase 4:` / `## Phase ` heading boundary, and note that `work/SKILL.md:762` sits at column 0 while its siblings are indented 3 spaces, so no indentation-based slice is safe.

### Phase 2 — GREEN: `work/SKILL.md`

Apply every edit in `## Files to Edit` for `work/SKILL.md`. Retitle §9 to the shard gate; keep the enforcement tag (hygiene); keep **all six** reading-discipline passages across `:748-770` under an explicit "reading a `test-all.sh` run" sub-heading; re-point the stale "the full-suite exit gate catches it" citations at `:589`, `:642`, `:649`, `:768`.

### Phase 3 — GREEN: `ship/SKILL.md` and `plan/SKILL.md`

Apply every edit in `## Files to Edit` for both files. For ship: **name CI's required `test` context as the merge gate** (never the local run), link the reading discipline, and update the Phase 5 checklist line at `:369`. For plan: correct `:1092` and `:1076`.

### Phase 4 — Mutation-prove the guard

Mutate the single assertion's target in a scratch copy and confirm the guard reds; restore. Per AC2 the mutation is *sharding* the ship command, not deleting it. A guard whose mutation does not red is a guard that asserts nothing.

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
2. **The registered infra suites lose their only enforcing gate.** A future PR shards ship Phase 4 to `TEST_GROUP=webplat` for speed. Escaping artifact: a registered `apps/web-platform/infra/*.test.sh` failure — an infra change that can destroy a user's worktrees or hosts — since `infra-validation.yml` is not a required context. Mitigation: the `TEST_GROUP=all` ceiling and the guard test's one assertion.
3. **A reaped ship Phase 4 is shipped on rather than re-run.** With two full runs a reaped Phase 2 was recovered by Phase 4; with one, "unresolved" under ship-time pressure resolves to "ship anyway". Escaping artifact: same as (2). Mitigation: Phase 4 prose states a reap is UNRESOLVED per the three-way split (`work/SKILL.md:764`) and must be re-run.
4. **The guard test is vacuous.** It greps a token that the surrounding prose satisfies (`review/SKILL.md:1231(c)`), so the whole gate can be deleted and CI stays green. Escaping artifact: every subsequent PR, since the workflow silently reverts to "run nothing". Mitigation: four distinct-shape mutations, one per assertion (AC3) — a uniform mutation set does not count.

**If this leaks, the user's workflow is exposed via:** no new exposure vector. No credential, persisted store, or network boundary is touched, and no path matches the canonical sensitive-path regex (`plugins/soleur/skills/**` and `knowledge-base/**` fall outside `SENSITIVE_PATH_RE` — verified against `plugins/soleur/skills/preflight/SKILL.md` Check 6 Step 6.1, so preflight Check 6 and Check 10 both return SKIP). The exposure this change can cause is *omission*, not disclosure: a gate that fails open lets a defect reach the user's `main` via subsequent PRs the gate should have caught — the #2887-class second-order path the meta-workflow branch exists to review.

**Brand-survival threshold:** `single-user incident`

Rationale, stated because the intuitive answer is the wrong one: a first pass set this to `aggregate pattern`, reasoning that erosion across many PRs is the real risk. That is descriptively true and procedurally wrong. `aggregate pattern` buys *strictly less* review — `user-impact-reviewer.md:13` exits immediately on it, which would opt this change out of the single review branch designed for meta-workflow diffs. And shape (2) above is not erosive: one sharded Phase 4 plus one infra PR is a single incident that can destroy a user's hosts. `single-user incident` is both the honest threshold and the one that summons the right reviewer.

Consequently `requires_cpo_signoff: true` is set in the frontmatter, and `user-impact-reviewer` must be invoked at review time (handled by `plugins/soleur/skills/review/SKILL.md`'s conditional-agent block) with its Meta-workflow branch active.

## Observability

**[REVISED — the drafted "not applicable, gate skipped" text was wrong and deepen-plan Phase 4.7 halted on it.** The exemption covers `\.md$` **outside** `plugins/*/skills/`; this plan's Files-to-Edit are `.md` files *inside* `plugins/soleur/skills/`, plus a new `plugins/soleur/test/*.test.ts`. So the gate applies and the 5-field schema is required. Recorded rather than quietly corrected, because "I assumed the gate did not apply to me" is the failure mode the gate exists for.**]

The observable surface of this change is the guard test — it is the only executable artifact, and its whole job is to detect that ship Phase 4 stopped running an unsharded battery.

```yaml
liveness_signal:
  what: "plugins/soleur/test/fullsuite-merge-gate.test.ts executes and passes"
  cadence: "every push and merge_group event"
  alert_target: "the required `test` status context (ruleset 14145388) goes red on the PR"
  configured_in: ".github/workflows/ci.yml:663-664 (test-bun shard) -> scripts/test-all.sh:883 `run_suite \"plugins/soleur\" bun test plugins/soleur/`"

error_reporting:
  destination: "GitHub Actions job log for test-bun, surfaced as the required `test` check"
  fail_loud: true   # a red required check blocks merge; there is no silent-degrade path

failure_modes:
  - mode: "ship Phase 4 is sharded (TEST_GROUP added), deleting the only enforcing gate for registered apps/web-platform/infra/ suites"
    detection: "fullsuite-merge-gate.test.ts assertion 1 fails"
    alert_route: "required `test` context red -> merge blocked"
  - mode: "the guard suite itself is deleted or renamed, so nothing asserts the ceiling"
    detection: "suite count drop in the test-bun shard; `bun test plugins/soleur/` no longer lists the label"
    alert_route: "visible in the test-bun job log; NOT independently alarmed — accepted limitation, and the reason AC2's mutation proof is mandatory rather than optional"
  - mode: "the guard passes vacuously because its section slice matches nothing after a Phase 4 retitle"
    detection: "AC2 mutation proof (shard the command) fails to red"
    alert_route: "caught at implementation time by AC2, not at runtime"

logs:
  where: "GitHub Actions run logs for the ci.yml test-bun job"
  retention: "90 days (GitHub default for this repo's public actions retention)"

discoverability_test:
  command: "bun test plugins/soleur/test/fullsuite-merge-gate.test.ts"
  expected_output: "exit 0, with the assertion naming ship Phase 4's unsharded test-all.sh invocation reported as passing"
```

No `credentials_required`: the probe reads two committed files and needs no credential. The first token is `bun`, which is on preflight Check 10's `PROBE_VERB_ALLOWLIST`, and the command contains no `ssh`.

Preflight Check 10 itself will return **SKIP** at ship time, since the diff matches no path in `SENSITIVE_PATH_RE` — but the block is required and executable regardless, and stating a runnable probe is cheaper than arguing the exemption.

## Encryption Posture

**Not applicable — gate skipped with reason.** No persistent store (volume, bucket, table, queue, cache, backup target, log sink) and no new cross-component or network connection is introduced. Detection globs (`*.tf`, `supabase/migrations/*.sql`, `cloud-init*.ya?ml`, `docker-compose*.ya?ml`) match nothing in the Files-to-Edit / Files-to-Create set.

## Architecture Decision (ADR/C4)

This plan changes a cross-cutting workflow invariant every pipeline consumer honours — which gate is authoritative for merge — on a surface that already carries a live ADR corpus (ADR-133, 150, 166, 170, 171, 172, 175, 177, 178). A future engineer reading only `work/SKILL.md` would otherwise conclude the gate was dropped rather than relocated.

### ADR

**Create `ADR-183` — provisional.** One-line decision:

> The local `scripts/test-all.sh` is a fail-fast checkpoint, not the merge gate — the merge gate is CI's required `test` aggregator (ruleset 14145388) — so `/work` Phase 2 exits on a relevance-derived subset, while `/ship` retains exactly one `TEST_GROUP=all` run because it is the sole gate for `apps/web-platform/infra/`, which no required context reaches.

That framing records the fact most likely to be re-derived wrongly (which gate is authoritative) and the one dependency that keeps the infra classes alive.

The ADR must carry: the measured cost table; the R1-R6 table with both the "gated by required CI" and "cheap to re-home" columns; the four named ceilings; one line on reverting if this bites; and an `## Alternatives Considered` section with rows for "drop the pre-review gate entirely" (the three counter-arguments), "add a second full run at ship Phase 5.5" (Cut List C2), and "let ship Phase 4 shard for speed" (**rejected — deletes the only gate R4/R5 have**; recorded here so a future optimisation PR finds the rejection rather than re-deriving the idea).

Per `wg-architecture-decision-is-a-plan-deliverable` this is authored in-session via `/soleur:architecture`, not filed as a follow-up.

Prior art worth citing in the rationale (external, treat its figures as the source's unsourced assertion): the `smoke → selective → full` tiering vocabulary from `regression-testing` (proffesor-for-testing/agentic-qe), surfaced by the community-discovery pass and **not** adopted as a dependency.

**Ordinal provenance — and a live demonstration of why it is provisional.** An earlier probe in this same session reported 63 refs with a maximum of `ADR-180`, and this plan drafted `ADR-181`. Two reviewers independently re-ran it and found **64 refs, maximum `ADR-182`** — with `ADR-181` held by `origin/feat-one-shot-test-pipeline-efficiency` (`ADR-181-local-gate-declines-are-counted-verdicts.md`), the exact sibling branch this plan sequences against and is prohibited from reading. Re-verified here:

| Ordinal | Holding ref |
|---|---|
| 179 | `origin/feat-one-shot-7442-sync-plugin-root-anchoring` |
| 180 | `origin/feat-one-shot-guard-contract-assembly` |
| 181 | `origin/feat-one-shot-test-pipeline-efficiency` |
| 182 | `origin/feat-one-shot-7440-zot-log-shipping` |

**Next free is `ADR-183`.** The ordinal moved *during the drafting of this plan* — which is the Sharp Edge's point stated as evidence rather than as caution. It is a *claim, not a reservation*: re-run the all-refs probe immediately before merge, and if it moves again, sweep `knowledge-base/project/{plans,specs}/feat-one-shot-7352-fullsuite-gate-post-review/` for the old ordinal **in the same edit**, so no AC ends up verifying a nonexistent file.

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

**[REVISED — 17 ACs reduced to 9. The cuts are recorded because "why did this AC go away" is the question a reviewer will ask.]**

1. **AC1** — `plugins/soleur/test/fullsuite-merge-gate.test.ts` exists and its single assertion passes: `bun test plugins/soleur/test/fullsuite-merge-gate.test.ts` exits 0.
2. **AC2** — mutation proof: **shard** the ship Phase 4 command to `bash scripts/test-all.sh webplat` → the guard must red. Restore. Recorded in the PR body. Sharding, not deletion — deletion is the easy mutation and the wrong threat.
3. **AC3** — **the "do not weaken" assertion.** All **six** reading-discipline passages are present verbatim in `work/SKILL.md`, each by a distinctive substring: `The exit gate only describes the tree you launched it against`; `"My edit is unrelated to the running suite" is how the exit gate gets invalidated`; `Sibling-worktree contention produces a FALSE RED`; `A long run can be reaped by the HARNESS`; `Doppler-env false-positive caveat`; `Feature-branch-CWD blind spot`. Plus the coverage-NOTE polarity strings `is NOT covered above` in both `work/SKILL.md` and `ship/SKILL.md`. *(Absorbs the drafted AC7 + AC8 + AC9, which were three ceremonies over one property; the two extra passages and the two extra substrings come from review.)*
4. **AC4** — the banner grep at `work/SKILL.md:670` is byte-identical to its pre-change form, verified by `git diff origin/main...HEAD -- plugins/soleur/skills/work/SKILL.md | grep -c '^-.*\[contention\] BANNER'` returning 0. *(The drafted AC9 used `grep -F` on a **truncated** prefix that dropped `|^\[budget\]|^\[KILLED\] [^ ]+ \(exit=` — so it would have passed with the `[KILLED]` half deleted, i.e. the exact three-way-split signal the plan says must survive. Presence ≠ byte-identity; use the diff.)*
5. **AC5** — `ship/SKILL.md` does **not** claim the local run is the merge gate. Verified as a **positive** assertion on the corrected framing (Phase 4 names CI's required `test` context), not as an absence-grep. *(The drafted AC10's `grep -c 'test-all.sh.*is the merge gate' … returns 0` reds on the plan's own prescribed prose — Proposed Solution §3(i) instructs writing "…is the merge gate" into Phase 4 — and `grep` is line-scoped against prose hard-wrapped at ~80 cols, so it is unreliable in both directions.)*
6. **AC6** — `plan/SKILL.md:1092` and `:1076` no longer tell planners that R4/R5 are caught at the work Phase 2 exit gate.
7. **AC7** — `bun test plugins/soleur/` is green and `lefthook run pre-commit` passes on the staged set. **Run each gate's own invocation**, not a hand-enumerated path list — per `2026-07-28-my-ac-verified-four-paths-while-ci-verified-five.md`. *(The drafted AC11 forbade hand-enumeration in one clause and prescribed `markdownlint-cli` "on every changed `.md` file" — a hand-enumerated list — in the next.)*
8. **AC8** — `ADR-183` (or its re-derived ordinal) exists and carries the decision line, the two ceilings, and the three alternative rows. The ordinal is re-verified against all `refs/remotes/origin/*` immediately before merge; if it moved, the sweep of `knowledge-base/project/{plans,specs}/` happens **in the same edit**.
9. **AC9** — the full battery is green at ship Phase 4: `TEST_GROUP=all bash scripts/test-all.sh`, `rc` read from the rc file (never the harness notification), terminal `=== N/M suites passed ===` marker present, and the epilogue NOTE + contention banners read per `work/SKILL.md:670`.
10. **AC10** — PR body uses `Closes #7352`.
11. **AC11 (OD1)** — each of the four project-agnostic lines (`work/SKILL.md:243`, `:337`, `:668`, `:818`) carries the C1 conditional, asserted by content anchor rather than line number. The guard test additionally asserts the **fail-safe polarity**: the prose must make "no CI-enforced full-suite gate on the merge branch" ⇒ *run the full battery*, so a mutation that flips the default to the relaxed branch reds. An assertion that merely finds the word "conditional" is vacuous and does not satisfy this AC.
12. **AC12 (OD1)** — the detection mechanism is named concretely in `work/SKILL.md` and satisfies all three OD1 constraints: agent-performed (no new selection script), fail-safe under uncertainty, and no assumed `gh` auth / GitHub remote / ruleset API scope. Recorded in the PR body with the reasoning for the mechanism chosen.
13. **AC13 (OD2)** — the PR is **still a draft** when `/ship` completes, and the PR body states the merge is held on #7441 per OD2. A ready-for-review or merged PR at this point is an AC **failure**, not an overachievement.

**Cut, with reasons:**

- *"the new suite appears in the run log"* — a phase-output audit, and it mis-cited `work/SKILL.md:725` (which is about `apps/web-platform/infra/*.test.sh` and `tests/scripts/test-*.sh`). A `plugins/soleur/test/*.test.ts` **is** auto-discovered by `scripts/test-all.sh:883`. AC1 and AC7 cover it twice.
- *AC3b (`FULLSUITE_SHA` unset arm)* — dissolved with the variable.
- *AC4/AC5 (enforcement tag + linter)* — the coupling was mutation-disproved; the linter cannot detect the deletion it was nominated to detect.
- *AC6 (eleven Files-to-Edit entries show a change)* — a checklist audit of the plan's own instructions, and it **contradicted AC7**: entry 8 is "lines 748-770 — retained" while AC7 required those passages verbatim. Mutually unsatisfiable.
- *AC10b (re-query the ruleset at ship time)* — treating one documented sentence as a live invariant needing a pre-merge API probe. The ADR ages like every ADR.
- *AC12 (measure the value proposition)* — **cut as an AC, kept as a reporting obligation.** It was unfailable: its own escape hatch (`record UNMEASURED — sibling run detected`) is always available, and the plan documents that a sibling worktree is running the same battery on the same machine. An AC that cannot fail is not an AC. The PR body states the measurement or states plainly that the cost case is carried from PRs #7344/#7343 and was not re-measured here.

### Pre-merge hold (OD2)

The merge is gated on a sibling PR, so these are pre-merge steps that outlive this pipeline run:

- **H1** — PR #7441 is merged to `main`.
- **H2** — this branch is rebased onto the post-#7441 `main`, and the `work/SKILL.md` touch-up
  reconciling its "the lead runs the gate ONCE" constraint (near line 269) with the retitled §9 is
  applied in the same rebase.
- **H3** — combined verification per AC9 (`TEST_GROUP=all bash scripts/test-all.sh`) is green **on
  the rebased tree**. The pre-rebase run does not satisfy this — per the token-discipline rule, a
  verification claim about a tree that no longer exists is re-run, not inherited.
- **H4** — only then: mark ready, merge, and record the merge date against #1442.

### Post-merge (operator)

None. Every step above is automatable in-session: the guard test and mutations run under Bash, the ADR is a file write, the ordinal probe is `git for-each-ref` + `git ls-tree`, and the merge is `gh pr merge --squash --auto`. No browser, console, or dashboard step exists in this change.

## Test Scenarios

### RED-phase targets (Phase 1)

- **Assertion 1** (ship Phase 4 stays unsharded) — passes on `origin/main` already. A **regression lock**, not a RED target; its value is earned entirely by the AC2(a) sharding mutation. Stated plainly rather than dressed up as a failing test.

### Regression tests

- The six "do not weaken" passages and both coverage-NOTE polarity strings (AC3) are asserted, not assumed.
- The banner grep's byte-identity (AC4) is asserted via `git diff`, not via a prefix `grep -F`.

### Edge cases

- **A pure-`knowledge-base/**` diff.** Under the revised design this maps to no shard, so the Phase-2 gate runs the linters only and says so. There is no empty-derived-set state to fail open on, because there is no derivation. *(The drafted design's own dogfood diff landed in exactly that state — neither derivation arm matched a `plugins/soleur/skills/**` + `knowledge-base/**` change, yet Phase 6 asserted a path-derived set that neither arm produced. That contradiction is what the shard map removes.)*
- **This PR's own diff** maps to `TEST_GROUP=bun` (for `plugins/soleur/**`, which is where the new guard test lands) and `TEST_GROUP=scripts`. Four existing suites `readFileSync` `work/SKILL.md` — `workflow-fidelity.test.ts`, `mandatory-wireframes-hardening.test.ts`, `scratch-path-collision.test.ts`, `lane-frontmatter.test.sh` — and all four are inside those two shards. The drafted derivation would have reached none of them.
- **R2 cannot be proved by this PR.** This change edits no `.c4` file, so the c4 coupling re-point (line 589) is verified by reading, not by a live red. Named as a limitation rather than papered over.
- **No cap rule.** The drafted "if the derived set exceeds the battery's suite count, run the battery instead" is deleted: it compared files to suites, `grep -c 'run_suite ' scripts/test-all.sh` is 145 so "hundreds of files" would never have tripped it, and it appeared in no shipping surface. A shard has a fixed cost; nothing to cap.

## Risks & Mitigations

| Risk | Mitigation |
|---|---|
| The Phase-2 shard set under-covers and R1/R4-class breakage reaches review | The shard map is derived from `scripts/test-all.sh:150-157`, not hand-maintained, and a shard runs its whole registered suite list — so R1 (source-text-coupled) and R4 (differently-named guards) are covered whenever their shard is selected. R6 is explicitly accepted as surviving to the merge gate. |
| The guard test is vacuous — a prose grep satisfied by surrounding prose | One assertion, one mutation (AC2). The drafted set had two assertions that could never fail; both were cut rather than patched. |
| **Loss of the pre-review reap redundancy** | With two full runs, a reaped Phase 2 was recovered by Phase 4; with one, a reaped Phase 4 has no second chance — and "unresolved" under ship-time pressure resolves to "ship anyway" more often than to a 45-minute re-run. Mitigation: ship Phase 4's prose states that a reaped run is UNRESOLVED per the three-way split (`work/SKILL.md:764`) and must be re-run, never shipped on. *(Surfaced by CPO; the plan's own research records 4 reaps on PR #7344.)* |
| ~~**The relaxation ships to users whose repo has neither backstop**~~ **RESOLVED by OD1** | Settled by the operator 2026-08-12: apply CPO's C1 conditional. The four generic lines (`work/SKILL.md:243,337,668,818`) are relaxed *with* the conditional "when the project has no CI-enforced full-suite gate on the merge branch, the full battery stays at implementation exit", so a user with neither backstop keeps today's behaviour. Residual risk moves to the **detection mechanism**, next row. |
| **The OD1 detection check misfires and silently relaxes a user's gate** | This is the new failure surface OD1 introduces, and it is the one that fails *quietly*. Mitigated by OD1's fail-safe constraint: unknown / unprobeable / no `gh` auth / no GitHub remote ⇒ treat as "no CI gate" ⇒ run the full battery. The relaxation is the privileged branch and is never the default under uncertainty. `/work` must state the chosen mechanism and demonstrate the fail-safe branch. |
| Rebase collision with `feat-one-shot-test-pipeline-efficiency` | Its `work/SKILL.md` edits are near line 269; §9 is at 742. Expect a touch-up, not a conflict. Do not read or reset that branch or worktree. **Under OD2 this PR merges only AFTER #7441**, so the rebase is mandatory and the combined verification runs on the rebased tree. |
| The ADR ordinal is claimed by a sibling mid-pipeline | AC8 re-runs the all-refs probe before merge and sweeps planning artifacts on renumber. This has collided twice in one session before (#5990). |
| Removing the Phase-2 full run also removes the only place some authors ever saw a contention banner | The four reading-discipline passages stay in `work/SKILL.md` (AC7), and ship Phase 4 links them. |
| **A future PR shards ship Phase 4 for speed, deleting the only gate R4/R5 have** | The highest-consequence risk in this plan. Three defenses: named ceiling 2 in the plan, an explicit rejected-alternative row in the ADR (so an optimiser finds the rejection instead of re-deriving the idea), and guard assertion 1, whose mutation proof is *sharding* the command rather than deleting it. |
| Branch protection changes between plan and merge, falsifying the ADR's central claim | Accepted. The ADR ages like every ADR; a drafted pre-merge API probe (AC10b) was cut as bureaucracy. The claim is dated and sourced in the ADR. |
| Sequencing against PR #7441 is wrong because its contents were not read first-hand | The dependency is recorded as **agent-sourced and unverified by this session** (see `## Sequencing`), and is framed as a decision point with a stated fallback, not as an asserted blocker. |
| The relaxation is unfalsifiable — nothing measures whether it causes escapes | The ADR records one line: if this bites, restore the unconditional Phase-2 run. A quantified tripwire was drafted and cut — an unspecified `N` with deferred counting is not falsifiability. |

## Success Metrics

- Full-suite invocations per PR on the Claude Code arm: 2 → 1.
- `/work` Phase 2 exit wall clock: full-battery duration → ~1-2 min on a representative diff (the PR body records the measured pair, or states plainly that the cost case is carried from PRs #7344/#7343).
- Advisory-lock queue events per PR across concurrent worktrees: halved by construction (one acquisition instead of two).
- Zero change to what reaches `main` for R1-R3: CI's required `test` context (ruleset 14145388) runs the same three `test-all.sh` shards on the PR head, independent of anything this plan touches.
- Zero change to what reaches `main` for R4: already blocked by the required `test` context via `terraform-target-parity.test.ts` in the `bun` shard. For registered infra suites: still gated by exactly one local `TEST_GROUP=all` run at ship Phase 4. For R5 orphans: unchanged, because nothing gated them before either — tracked separately in `## Deferred`.
- Escape rate: PRs whose required `test` context reds after a green local Phase-2 shard gate. Target 0. Not automated — see `## Deferred`.

## Sequencing

The CTO advisory recommends landing PR #7441 (`feat-one-shot-test-pipeline-efficiency`) **first**, on four grounds: it introduces a `skip_suite()` "a decline is a counted verdict" taxonomy that a touched-file gate needs; it ships `scripts/lib/test-relevance-paths.sh` with a fail-closed linter that is the natural substrate for this plan's relevance derivation; it adds a standing "the lead runs the gate ONCE" constraint to the same `work/SKILL.md` region; and it adds `plugins/soleur/test/fanout-suite-scope.test.sh`, which may anchor on the very prose this plan rewrites. It also reports that PR as currently red on `adr-ordinals` and `test-bun`, with an ADR-178 ordinal collision.

**Provenance, stated plainly: this session did not verify any of it.** The brief prohibits reading that branch or worktree, so the findings are agent-sourced and second-hand. They are recorded because a wrong sequencing decision is expensive, not because they are established.

**Decision — SUPERSEDED by OD2 for the merge, retained for implementation order.** The operator
settled UC2 on 2026-08-12: #7441 is a **hard blocker on the MERGE**. Implementation, review, and QA
proceed now; the PR stays draft until H1-H4 in `## Acceptance Criteria → Pre-merge hold (OD2)` are
satisfied. The bullets below still govern *how* to implement while #7441 is in flight:

- If #7441 has merged when `/work` begins, adopt its `skip_suite()` vocabulary and `test-relevance-paths.sh` substrate rather than authoring a parallel one, and re-read the `work/SKILL.md` region for its "lead runs the gate ONCE" constraint so the two statements stay consistent.
- If it has not merged, proceed. Nothing in this plan's Files-to-Edit overlaps its reported hunk (`@@ -269 @@` in `work/SKILL.md`; §9 is at line 742), and this plan deliberately introduces **no** new selection script (Cut List C1), so there is nothing to collide with structurally. Expect a rebase touch-up.
- Either way, verify at `/work` Phase 0 whether `plugins/soleur/test/fanout-suite-scope.test.sh` exists on `origin/main` and whether it asserts on the §9 prose. If it does, its assertions are added to this plan's Files-to-Edit before §9 is rewritten.

## Deferred

- **Promote `infra-validate-required` to a required status check.** The R5 gap this plan discovered is a ruleset gap: `apps/web-platform/infra/` orphan suites are gated by nothing, and `infra-validation.yml`'s `infra-validate-required` job is absent from `scripts/required-checks.txt` (verified: `grep -c` → 0). Fixing it means editing that file plus `scripts/ci-required-ruleset-canonical-required-status-checks.json` and `infra/github/ruleset-ci-required.tf`, which `plugins/soleur/test/required-checks-canonical-parity.test.sh` Test 1 parity-guards. File as its own issue: this is a branch-protection change, and folding it into a test-reordering PR would hide a merge-policy change inside a workflow-prose diff. Triaged inline first per `wg-defer-only-after-inline-triage` — it is genuinely a different subsystem, not deferred scope.
- **Automated escape-rate measurement.** Counting "PRs whose required `test` context reds after a green local touched-file gate" needs a data source spanning many PRs and a place to keep the running count; it is a separate work-stream, not a line in this diff. File a tracking issue at `/work` time with: what is deferred, why (needs cross-PR data), the re-evaluation criterion, and the milestone from `knowledge-base/product/roadmap.md`. Per `wg-defer-only-after-inline-triage` this was triaged inline first — the ADR's one-line revert note ships now; only the measurement defers.

## Domain Review

**Domains relevant:** engineering

### Engineering (CTO)

**Status:** reviewed

**Assessment:** Materially corrected the plan's central premise. (a) The local `test-all.sh` is not and never was the merge gate — CI's required `test` context (ruleset 14145388, aggregating three `test-all.sh` shards) is; this makes the change safer than the issue argues for R1-R3 and relocates the single real gap to `apps/web-platform/infra/`, which no required context reaches. (b) Ship Phase 4 is not the post-all-code-changes position: Phase 5.5 contains multiple code-mutating gates after it, which forces the "last local fail-fast checkpoint" naming instead of "the merge gate". (c) Named the ceilings, of which "ship Phase 4 must stay `TEST_GROUP=all`" is the load-bearing one; flagged the enforcement gap (nothing would assert the *new* gate either) as blocking, citing ADR-166 "enforcement is the lint, not the prose". (d) Confirmed the ADR is warranted, supplied the decision line, and supplied an ordinal that a later probe corrected again to 183. (e) Judged PR #7441 complementary with a medium semantic dependency, recommending it land first.

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
