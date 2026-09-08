---
title: "fix(kb): register a regenerating merge driver for the generated KB index"
date: 2026-09-08
slug: fix-kb-index-merge-driver
branch: feat-one-shot-7935-kb-index-merge-driver
issue: 7935
closes: 7935
type: bug
lane: cross-domain
priority: p1-high
domain: engineering
brand_survival_threshold: none
---

> **Superseded in part, 2026-09-08 (#7935).** Implementation falsified four rows of this plan. They
> are left standing rather than edited, because a dated record is append-only.
>
> - **T6, and mutation rows G2-1 / G2-2** specify that corrupting an index's `> Total files:` count
>   makes the driver exit non-zero and write a sentinel. In that direction it no longer does. The
>   count is derived, the driver recomputes it, and an ancestor is a historical commit by
>   construction — two of the last twelve commits touching INDEX.md on `main` carry a header that
>   disagrees with their own body, so validating it refused ordinary merges. An **overcount** still
>   refuses, because rows removed while the count line survived is row loss rather than staleness.
>   See ADR-210's 2026-09-08 addendum.
> - **G2-3**'s stated discriminator ("the suite must catch G2-2") therefore names a case that no
>   longer exists.
> - **AC14** says the driver battery "exits 0 with all 13 rows scored ok"; it is 17 (G1-G16 + H1).
>   The rows added after this plan was written are G14 (the mask is not deletable), G15 (the
>   ambiguous-separator guard, which until its fixture kept its domain was covered by nothing), and
>   G16 (the overcount guard).

## Overview

`knowledge-base/INDEX.md` is a committed, generated artifact with no `.gitattributes` entry, so git
merges it as ordinary prose. Every branch that adds a knowledge-base file appends rows to it — the
file was touched 27 times in the 30 days to 2026-09-08 (a MOVING figure -- re-derive with
`git log origin/main --oneline --since='30 days ago' -- knowledge-base/INDEX.md | wc -l`, which
read 27, 29 and 30 at different hours of the same day; the earlier `--all` reading of 76 counts
every feature branch and is the wrong denominator for "conflicts with other branches on trunk") — so every such branch conflicts with every other one,
and the reflex resolution takes one side's copy whole, silently discarding the rows the other side
added. This plan registers a merge driver that resolves the path by deriving the merged index from
the three versions git hands it, wires the driver's registration into paths that already run
unattended, and adds the CI check that makes an unregistered driver loud instead of silent.

Spec lacks a valid `lane:` — defaulted to `cross-domain` (TR2 fail-closed). No `spec.md` exists for
this branch; `## Domain Review` is the authority on which domains were actually consulted.

## Enhancement Summary

**Deepened on:** 2026-09-08. **Sections enhanced:** Design, Guard Contract, Files to Create/Edit,
Acceptance Criteria, Test Scenarios, Risks, Implementation Phases, Measured facts.
**Agents used:** CTO (engineering domain), spec-flow-analyzer, Kieran (correctness),
code-simplicity-reviewer, DHH (architecture), a strong-model scoped consult, security-sentinel,
test-design-reviewer, plus a verify-the-negative sweep and a dropped-symbol self-audit.

### Key improvements

1. **The issue's literal mechanism was measured infeasible and replaced.** A merge driver cannot see
   the merged tree (M4/M5), and no post-merge hook can repair it (M6), so the driver derives the
   merged index from `%O`/`%A`/`%B` instead of regenerating from disk.
2. **The driver can no longer fail quietly.** Sentinel writes moved from hand-placed lines to an `ERR`
   trap, closing the path where an unhandled `set -e` failure reproduces the exact markerless-conflict
   defect (M7) one level down.
3. **The guard became a regeneration diff rather than a structural lint**, which is the only form that
   catches title drift and the rename-plus-edit divergence — both newly named as honest limits of the
   set-merge design.
4. **The test design was rebuilt on repo precedent**: four suites split on the seam
   `scripts/test-all.sh` documents, an executable mutation harness lifted from
   `git-fixture-env.mutation.sh`, `EXPECTED_ROWS` floors reported outside the `FAIL` counter, and a
   mandatory `KB_DIR=<fixture>` pin worth roughly three minutes of CI per run.
5. **Two live bugs in existing wiring were found and folded in**: the lefthook glob has never matched
   `knowledge-base/INDEX.md` (M17, measured against real lefthook), and `merge-pr/SKILL.md` routes the
   index to guidance that tells the reader to look for conflict markers that M7 guarantees are absent
   (M15) — a live path to the reported bug through the repo's own skill.

### New considerations discovered

- A `package.json` `prepare` script **does** fire in one CI job (M14) — the opposite of what an
  earlier draft asserted. Harmless, but the rationale had to be corrected rather than defended.
- Commit recency is not content staleness: all three generated artifacts are byte-identical to a fresh
  generation despite month-apart commit dates (M18b), which is what keeps this diff small.
- The registration key lands in the shared bare-repo config, verified empirically, so one surface
  registers all 37 worktrees — which is why a third registration surface was cut.
- Un-tracking the generated index entirely is a coherent alternative that two reviewers converged on;
  it is recorded as a challenge rather than adopted, with the costs its proponents did not price.

## Research Insights

### Premise Validation (Phase 0.6)

| Cited premise | Probe | Verdict |
|---|---|---|
| Issue #7935 is open | `gh issue view 7935 --json state` → `OPEN` | HOLDS |
| No `.gitattributes` anywhere | `git ls-files \| grep -i gitattributes` → empty; `find -iname .gitattributes` → empty | HOLDS |
| `INDEX.md` is generated by `scripts/generate-kb-index.sh` and committed | `INDEX_FILE="$KB_DIR/INDEX.md"`, written by the `} > "$INDEX_FILE"` block | HOLDS |
| The generator also emits `kb-tags.txt` / `kb-categories.txt` | `TAGS_FILE` / `CATEGORIES_FILE`; both written via `LC_ALL=C sort -u` | HOLDS |
| Mirrored copies exist under `plugins/soleur/knowledge-base/` | Directory exists | HOLDS — **but nothing in the repo writes it.** `grep -rln 'plugins/soleur/knowledge-base'` returns zero hits outside the directory; `KB_DIR` defaults to `$REPO_ROOT/knowledge-base` and no caller overrides it. Hand-maintained plugin payload, **out of scope**. |
| There is a lefthook `generate-kb-index` hook | `lefthook.yml`, anchor `generate-kb-index:` | HOLDS, with two corrections — see M17 and M18. |
| PR #7907 (CI sharding) in flight; #7937 (ship rules) separate | `gh pr view 7907` → OPEN draft; `gh issue view 7937` → OPEN | HOLDS — both stay out of scope. |
| Sibling issue #7401 ("INDEX.md is stale on main by 3,711 rows") | Still OPEN, but **measured stale as an issue**: a fresh generator run on this branch changes only the `> Total files:` line plus this plan's own row. | STALE ISSUE — not this PR's business; do not close it here. |

**Prior-art reconciliation — this mechanism was previously declined, with no stated reason.**
`knowledge-base/project/plans/2026-04-07-feat-kb-manifest-and-search-skill-plan.md`, anchor
`**Merge conflicts:**`, reads verbatim: *"INDEX.md is a generated file. Do not use `.gitattributes`
merge strategies. After any merge that conflicts on INDEX.md, regenerate by running `bash
scripts/generate-kb-index.sh`."* That is a plan, not an ADR, and it records no rationale. It is the
source of the generator's own `--help` line. #7935 supersedes it on measured evidence — the
hand-run regeneration remedy is exactly what failed three times on PR #7896 — and the ADR named in
`## Architecture Decision (ADR/C4)` records the reversal.

Separately, `knowledge-base/project/plans/2026-07-06-fix-rule-incidents-ci-telemetry-locality-plan.md`
**deferred** (did not reject) a `.gitattributes merge=ours` entry for `rule-metrics.json` as part of a
scope cut, and its `## Deferred to follow-up` still asks for one. Creating the root `.gitattributes`
here unblocks that follow-up; adding the `rule-metrics.json` line is **not** in scope.

### Measured facts

Experiments run against throwaway repos (`git init -b trunk`, `GIT_CONFIG_GLOBAL=/dev/null`,
`GIT_CONFIG_SYSTEM=/dev/null`, git 2.53.0) with `kb/INDEX.md merge=kbi` in `.gitattributes`, plus
probes against the live repo. M1, M4, M6 and M7 were **independently reproduced** by the CTO review
in its own fixtures.

| # | Question | Measured answer |
|---|---|---|
| **M1** | Does git warn when `.gitattributes` names an unregistered driver? | **No.** Silent fallback to the default text merge; output is byte-identical to having no `.gitattributes` at all. This is the fail-open case the issue's third acceptance criterion forbids, and git exposes no hook for detecting it. |
| **M2** | Does the default text merge corrupt the header count even when rows merge cleanly? | **Yes.** Base `Total files: 1`; both sides independently wrote `2`; merged file says `2` when the truth is `3`. Two sides making the *same* textual edit is a clean merge — no conflict, no marker. `merge=union` shares the defect and additionally emits the count line twice when the sides disagree. |
| **M3** | Does a custom driver fire for `git merge`? | **Yes**, and for `git rebase` and `git cherry-pick`. |
| **M4** | What does the driver see on disk? | `pwd` is the working-tree root, but the worktree **and** the index are still on the *ours* side. `ls kb` returned `INDEX.md a.md b.md` — the incoming `c.md` was absent and appeared only after the merge completed. `git ls-files` returned the pre-merge index. `MERGE_HEAD`, `REBASE_HEAD` and `CHERRY_PICK_HEAD` were all unset. |
| **M5** | Consequence of M4 | **The issue's proposed mechanism is not implementable as literally stated.** "Run `generate-kb-index.sh` against the merged tree" cannot work inside a merge driver: the merged tree does not exist yet and the driver holds no reference to the other side. A generator run at driver time indexes the ours-side file set and therefore drops exactly the incoming rows the driver exists to preserve. The driver's only inputs are `%O`, `%A`, `%B`. |
| **M6** | Can regeneration be deferred to `pre-merge-commit`? | **No.** The hook fires and does see the fully merged worktree, but a `git add` inside it is ignored: the fixture's hook rewrote and staged the index, and the merge commit still carried the driver's output while the worktree was left dirty (`M kb/INDEX.md`). `git merge` computes its tree before the hook runs. The clean-auto-merge path has no post-hoc repair point. |
| **M7** | Driver exits non-zero | git reports `CONFLICT (content)`, marks the path `UU`, and leaves `%A` (ours) content in place — **and writes no conflict markers**. The file looks clean. `.claude/hooks/guardrails.sh`'s `guardrails:block-conflict-markers` gate therefore does not fire. |
| **M8** | Driver command cannot be executed | git prints the exec failure to stderr and then reports `CONFLICT (content)` with ours content. Fail-closed and noisy — acceptable degradation. |
| **M9** | Generator cost on the real corpus | `time bash scripts/generate-kb-index.sh` → **real 9.9 s** for 6,432 files. |
| **M10** | Row ordering | The generator sorts a `rel\ttitle` TSV with `LC_ALL=C sort` — **by relative path**, not by rendered line. Rows render as `- [$title]($rel)`, so sorting rendered lines gives a *different* order. Any merge that treats rows as opaque lines is wrong. |
| **M11** | Header count semantics | `total=${#all_files[@]}`, one row per eligible file, so `> Total files: N` is exactly the row count. Confirmed live: `grep -c '^- \['` → 6432, header → `Total files: 6432`. |
| **M12** | Is the row parse-back safe on the real corpus? | Over all 6,432 rows: **zero** rows contain a second `](`, **zero** `rel` values contain `)`, and 9 rows carry an escaped `\[`. Sound today; the driver's round-trip validation is what keeps it sound as titles change. |
| **M13** | Does any CI workflow perform a merge? | **No.** `grep -rn 'git merge\|git pull' .github/workflows/*.yml` returns only two `git merge-base` uses in `ci.yml`. The driver never needs to be registered in CI; CI's role is to **catch** a bad index, not to produce a good one. |
| **M14** | Does a `package.json` `"prepare"` script fire in CI? | **Yes, in exactly one place — an earlier draft of this row said "no" and was wrong.** Every `npm ci` across `.github/workflows/` does pass `--ignore-scripts`, and every `npm install <pkg>` / `npm install -g <pkg>` form suppresses `prepare` too (both verified in a fixture against npm 12.0.2). But `ci.yml`'s `lockfile-sync` job runs a **root-level `npm install --package-lock-only` with no `--ignore-scripts` and no package name**, and that shape *does* fire `prepare` (measured: `npm notice run … prepare`). So once this plan adds `"prepare"` to the root `package.json`, that one CI step will invoke the registration script. **Blast radius is nil** — it writes `merge.kb-index.driver` into an ephemeral runner's own `.git/config`, and M13 independently establishes that no CI workflow ever performs a `git merge`, so the registered driver there is inert. The correction matters not for safety but because the plan's rationale must not rest on a false measurement. |
| **M15** | What does the existing conflict-resolution guidance say? | `plugins/soleur/skills/merge-pr/SKILL.md` §3.1 routes `Generated artifacts` to *"Take `--theirs`, then re-run the owning generator — see 3.2b"*, and §3.2b enumerates its known members: `model.likec4.json` and `rule-metrics.json`. **`knowledge-base/INDEX.md` is not in that list** (`grep -c 'knowledge-base/INDEX.md'` → 0), so it falls to *"Everything else → Claude-assisted resolution"*, whose first instruction is *"Read the file with conflict markers."* Combined with M7 that is a trap: there are no markers, the file reads as clean, and the next step is `git add`. **This is a live path to the exact row-drop the issue reports, through the repo's own sanctioned skill.** |
| **M16** | Must `INDEX.md` stay committed? | Five surfaces grep the committed file at read time — `plugins/soleur/skills/kb-search/SKILL.md` ("Tier 1 (cap 8): Grep `knowledge-base/INDEX.md`"), `plugins/soleur/agents/engineering/research/learnings-researcher.md` ("Step 0: Check INDEX.md for Broad Discovery"), plus the `brainstorm`, `spec-templates` and `archive-kb` skills. `kb-search` does carry a graceful `Missing INDEX.md → note and continue with content grep only` path, so absence degrades rather than breaks. See `## Alternative Approaches Considered` and the recorded challenge. |
| **M17** | Does the lefthook stanza's glob match `INDEX.md` itself? | **No — measured, not reasoned.** In a scratch repo with only `knowledge-base/INDEX.md` staged, `lefthook run pre-commit` (v2.1.6) against a `glob: "knowledge-base/**/*.md"` stanza printed `generate-kb-index (skip) no matching staged files` — the command never ran. Re-run with the proposed dual glob (`["knowledge-base/*.md", "knowledge-base/**/*.md"]`), the command executed. gobwas requires `**` to span one or more directory levels (`2026-03-21-lefthook-gobwas-glob-double-star.md`), and `knowledge-base/INDEX.md` sits at depth 1 — so a merge-resolution commit whose only staged KB file is the index has never triggered regeneration. |
| **M18** | Does the lefthook stanza stage the facet files? | **No.** It runs `... && git add knowledge-base/INDEX.md` only, so the two facet files are rewritten on disk and committed only when some other commit happens to sweep them up. Commit recency shows it: `kb-categories.txt` last committed **2026-08-10**, `kb-tags.txt` **2026-09-07** (by an incidental `compound:` commit that never routed through the stanza), `INDEX.md` today. |
| **M18b** | Is that commit-recency gap also a **content** staleness gap? | **No — measured.** A full generator run followed by `git diff --stat` over all three artifacts produces an empty diff: `kb-categories.txt` is byte-identical to a fresh generation despite its month-old commit date, because the category set simply has not changed. Commit recency and content freshness are different properties here, and only the second one matters to `--check`. This is what lets AC17 pass today and keeps the regeneration in this PR to the `INDEX.md` rows alone rather than dragging a month of facet drift into a merge-driver diff. |
| **M19** | Was the hook layer even armed when the drops happened? | The bare repo's `.git/hooks/` gained a real `pre-commit` and `pre-push` on **2026-09-03 23:22**; before that it held only `*.sample` files and every lefthook gate was inert (`2026-09-03-four-ways-i-destroyed-evidence-in-the-pr-that-exists-to-preserve-it.md`, item 44 — "the local pre-commit layer has run on **zero** commits"). PR #7896 merged 2026-09-07, i.e. after arming. So the drops are **not** explained by an inert hook layer; M15 and M17 are the live explanations. |
| **M20** | How does a merge driver resolve its own script path across 37 worktrees? | `git rev-parse --show-toplevel` returns the **calling worktree's** root; `--git-common-dir` returns the bare `/home/…/soleur/.git`, whose parent contains no `scripts/` because the repo is bare with linked worktrees. Neither yields a stable absolute path to the driver. Measured instead: git invokes the driver with CWD at the working-tree root **even when `git merge` is run from a subdirectory** (fixture: merged from `sub/`, driver logged the repo root). So the config value can be a plain **relative** command and is correct in every worktree, with no path baked in. |
| **M21** | Live topology | 37 linked worktrees (`git worktree list \| wc -l`), `core.hooksPath` → `/home/…/soleur/.git/hooks`, `lefthook` 2.1.6 on PATH. The "14 worktrees" figure in the cited 2026-08-09 learning is stale; the blast radius of a shared-config write is larger, though the mitigation (one idempotent key, check before write) is unchanged. |
| **M22** | C4 cardinality parity | `bash plugins/soleur/test/c4-count-parity.test.sh` → `Passed: 10  Failed: 0  ALL TESTS PASSED`. |

### Property List (Phase 0.6b)

- **P1 — no silent row loss.** Merging two branches that each add a knowledge-base file yields an
  `INDEX.md` containing both rows.
- **P2 — no header lie.** The merged `> Total files:` line equals the merged row count.
- **P3 — no per-sync conflict.** A sync that differs only in appended index rows completes without
  stopping for manual resolution.
- **P4 — active without an operator step.** The mechanism is live in a fresh clone without anyone
  being told to run a command.
- **P5 — unregistered fails loudly.** If the driver is not registered, the resulting index does not
  reach `main` looking correct.
- **P6 — no clean-looking failure.** No failure path of the driver produces a file that reads as
  successfully merged.

### Cut List (Phase 0.6b)

| Mechanism | Property it would buy | Disposition |
|---|---|---|
| Driver invokes `generate-kb-index.sh` on the merged tree | P1, P2 | **Cut — infeasible** (M4/M5). Replaced by a three-way merge over the rows in `%O`/`%A`/`%B`, rendered through code shared with the generator so the rendering is never duplicated. |
| A post-merge / `pre-merge-commit` regeneration hook | P1, P2 | **Cut — measured ineffective** (M6). |
| `merge=union` on `INDEX.md` | P3 only | **Cut — wrong by construction** (M2, M11): duplicates or silently freezes the derived count line. |
| A bespoke `--flat` driver mode for `kb-tags.txt` / `kb-categories.txt` | P1 for the facet files | **Cut — a git built-in already buys it.** These are flat lists with no derived header, and the only consumer, `plugins/soleur/skills/kb-search/SKILL.md`, validates with `grep -Fxq` — an exact-line check indifferent to ordering and duplicates. `merge=union` therefore satisfies the real contract with zero code, zero registration, and no unregistered-failure mode at all. |
| A dedicated freshness-gate suite mirroring `plugins/soleur/test/c4-model-freshness.test.sh` byte for byte | P5 | **Cut as a separate file, adopted as a seam.** The `--out DIR` primitive and the fresh-vs-committed diff are taken from that precedent; what is not taken is a second test file — the check is one case inside the functional suite. The earlier draft's reason for cutting it wholesale (false positives on `refs/pull/N/merge`) was re-examined and did not survive: see `## Design`, which measures both merge-ref cases and shows a red check there is a true positive. |
| A separate structural lint (`lint-kb-index-consistency.sh`) | P5 | **Cut — subsumed.** A checklist of structural assertions re-implements the generator's eligibility rules in a second place (which ADR-174 warns will drift) and still cannot see title drift or the rename case. Replaced by a `--check` mode on the generator itself: regenerate to a temp directory and diff. One implementation, strictly stronger. |
| A lefthook `pre-commit` registration stanza | P4 | **Cut — wrong moment.** `pre-commit` fires *after* the merge it was meant to arm, and the surface is bypassable. The shared `.git/config` means the first surface to fire anywhere registers the key fleet-wide, so a third surface adds a wiring point without adding coverage. |
| Un-tracking the generated index entirely | dissolves P1–P6 | **Not adopted — recorded as a challenge.** See `## Alternative Approaches Considered` and `knowledge-base/project/specs/feat-one-shot-7935-kb-index-merge-driver/decision-challenges.md`. |
| Re-close or re-scope #7401 | — | **Cut.** Measured non-issue on current `main`; separate issue, separate PR. |
| A `.gitattributes` line for `rule-metrics.json` | — | **Cut.** Belongs to the 2026-07-06 plan's own follow-up. |
| Covering `plugins/soleur/knowledge-base/*` | — | **Cut.** Nothing generates it. |

### Value-Proposition Measurement (Phase 0.6c)

The latency case is measured: `test-scripts` took 27 min on run 34163673236 against a 3 min
next-longest job, and `INDEX.md` conflicted 4+ times in one session on PR #7896; each conflict forces
a merge commit and a fresh CI cycle. The correctness case is measured: the ADR-206 row was dropped
three times and recovered only by an ad-hoc `grep -c`. The file's exposure is measured: 27 touches in
30 days. Note that `git log --merges -- knowledge-base/INDEX.md` over 60 days returns **0** — the
pipeline squash-merges, so branch-side sync conflicts leave no trace in `main`'s history and conflict
frequency cannot be recovered from git log. The driver's own cost is bounded by the two ~6,500-line
inputs it parses; only the CI `--check` pays M9's 9.9 s.

### Institutional learnings that constrain this plan

- `knowledge-base/project/learnings/2026-08-09-one-shared-config-key-took-all-fourteen-worktrees-down-mid-rebase.md`
  — item 4 is the direct precedent: *a generated artifact must never be conflict-resolved by picking a
  side*; `model.likec4.json` was resolved by re-deriving. Item 1 records that a shared `.git/config`
  write reaches every worktree at once (now 37, per M21).
- `knowledge-base/engineering/architecture/decisions/ADR-173-bare-config-polarity-for-linked-worktrees.md`
  and `ADR-099-git-surface-topology.md` — `extensions.worktreeConfig` must stay unset; its
  re-evaluation trigger is "a new setter appears anywhere in the toolchain". The registration script
  writes a plain top-level `merge.<name>.driver` key and must not touch `config.worktree`.
- `knowledge-base/project/learnings/workflow-issues/2026-04-03-lefthook-git-env-var-leak-breaks-tests.md`
  — severity corrected to `high`/`data_loss` on 2026-09-04: the same leak produced 16 stray commits on
  a live branch and twice collapsed a worktree index to 2 entries. Every fixture that runs `git init`
  must scrub `GIT_*`. `plugins/soleur/test/test-helpers.sh` carries the fail-loud tripwire (anchor
  `# --- Guard 3 (#7833): fail-loud git-location tripwire`, exit 97); the new suite sources it.
- `knowledge-base/project/learnings/workflow-issues/2026-04-02-lefthook-hangs-in-git-worktrees.md`
  — `lefthook run pre-commit` can hang inside `.worktrees/`, and the workaround is `LEFTHOOK=0`.
  Combined with M19, this is why no correctness property may rest on a lefthook stanza.
- `knowledge-base/project/learnings/2026-09-03-four-ways-i-destroyed-evidence-in-the-pr-that-exists-to-preserve-it.md`
  item 44 — the hook layer was inert until 2026-09-03, and its stated prevention is that session start
  should assert the hook layer is *armed*, not merely configured. Noted; not adopted here (a different
  capability, and it would widen this PR).
- `knowledge-base/project/learnings/2026-03-03-canonicalize-merge-and-conflict-marker-guard.md`
  — the pipeline canonicalized on `git merge origin/main`, so `merge.<name>.driver` is the right lever;
  it also added the staged-conflict-marker guard that M7 shows will not fire unless the driver writes
  one deliberately.
- `knowledge-base/engineering/architecture/decisions/ADR-174-kb-index-exclusion-supersedes-per-feature-archival.md`
  — the generator's row-eligibility predicate changes over time (Tier 2 is #7400). Nothing outside the
  generator may re-implement eligibility.
- `knowledge-base/project/learnings/2026-03-21-lefthook-gobwas-glob-double-star.md` — the source of M17.
- `knowledge-base/project/learnings/workflow-patterns/2026-06-04-kb-index-regen-bundles-stale-drift-prefer-surgical-edit.md`
  — a full regeneration once dragged ~993 lines of unrelated drift into a small PR. Re-measured today:
  the drift is gone, so the regeneration in this PR costs two lines.

### Conventions carried from AGENTS.md and the codebase

- `hr-never-label-any-step-as-manual-without` and the never-defer-operator-actions rule: registration
  is automated, not documented.
- `hr-verify-repo-capability-claim-before-assert`: every claim about lefthook, `package.json`,
  `.claude/settings.json` and CI here came from reading those files or running the probe.
- `cq-cite-content-anchor-not-line-number`, `cq-assert-anchor-not-bare-token`,
  `cq-write-failing-tests-before`.
- New shell suites are auto-discovered by `SUITE_GLOBS` in `scripts/test-all.sh`
  (`plugins/soleur/test/*.test.sh`, `scripts/lib/*.test.sh`); `scripts/lint-orphan-test-suites.sh`
  diffs that array against `git ls-files '*.test.sh'`.
- `plugins/soleur/test/gitleaks-merge-commit.test.sh` is the fixture template: `mktemp -d`,
  `trap 'rm -rf …' EXIT`, `git init -q -b trunk` (**never `main`** — the commit-on-main guardrail
  blocks fixture commits), inline `user.email` / `user.name`, and a real two-parent merge asserted with
  `git rev-list --parents -1 HEAD | wc -w == 3`.

## Research Reconciliation — Spec vs. Codebase

| Claim in the issue / ask | Codebase reality | Plan response |
|---|---|---|
| "the driver runs `generate-kb-index.sh` against the merged tree" | M4/M5: no merged tree, no ref to the other side | Driver derives the merged rows from `%O`/`%A`/`%B` and renders through a helper shared with the generator. The plan's central deviation. |
| "the generator is a pure function of the KB file set" | True, and it is why the row-set merge is exact for the common case (`total=${#all_files[@]}`) | Adopted — with the three divergence cases named explicitly in `## Design`. |
| "a merge driver needs local `git config`" | True, and **nothing in this repo automated any local git state** before this PR: no `prepare`/`postinstall`, no `lefthook install` call, and the hook layer itself was inert until 2026-09-03 (M19) | Registration becomes a new idempotent script on two unattended surfaces. |
| "fail loudly rather than falling back to the line-merge" | M1: git's fallback is completely silent, and git offers no hook for it | Loudness cannot come from git. It comes from the CI `--check`, which reddens on any index the driver did not produce correctly. |
| "must not silently no-op … in CI" | M13: no CI workflow merges | The CI obligation is the guard, not registration. Stated explicitly so a later reader does not assume CI-side registration coverage. |
| kb-tags.txt / kb-categories.txt are "the same defect class" | Same generator, both committed, but no derived header, and the only consumer uses `grep -Fxq` | Same class for P1, not for P2. `merge=union` (a git built-in) rather than bespoke driver code. Decision recorded below. |
| The lefthook stanza already regenerates on KB commits | Partly. M17: its glob cannot match `knowledge-base/INDEX.md` at depth 1. M18: it stages only `INDEX.md` | Both fixed in the same stanza — a dual glob and a widened `git add`. |

## Design

### The driver: `scripts/merge-kb-index.sh <ancestor> <ours> <theirs> [path]`

Registered as `merge.kb-index.driver`. Git invokes it with `%O %A %B %P`; it must overwrite `%A` and
exit 0 on success, non-zero to raise a conflict.

0. **Validate `%P` before reading anything.** The driver refuses to run on any path other than
   `knowledge-base/INDEX.md`, writing the sentinel and exiting non-zero instead. `.gitattributes` is a
   committed, PR-mergeable file, so a `merge=kb-index` line redirected onto arbitrary paths would
   otherwise have the driver parse unrelated content as KB rows and spray conflicts repo-wide. This
   is not an RCE vector (the driver *command* comes only from local config, never from
   `.gitattributes`) but it is a cheap denial-of-service lever, and the check closes it in one line.
1. **Parse** each of the three files into a `rel\ttitle` TSV. A row is `- [<title>](<rel>)`; the title
   is everything between the leading `- [` and the last `](`, `rel` is the remainder before the final
   `)`, and `\[` / `\]` are unescaped.

   **The parse must assume adversarial input, because it already is.** The generator escapes only
   `[` and `]` in titles (`title="${title//\[/\\[}"`, `title="${title//]/\\]}"`), so a `title:`
   frontmatter value containing `$(…)`, backticks, quotes or semicolons reaches a committed `INDEX.md`
   row verbatim through any ordinary PR today. M12 measured *today's* corpus, not a hostile one. The
   implementation therefore MUST:

   - never `eval` an input-derived string, and never build a command line by concatenating title or
     `rel` content;
   - read line by line (`while IFS= read -r line`, or `awk`'s record handling) — never a whole-file
     multi-line regex, which would let a crafted blob smuggle content across row boundaries;
   - strip a trailing `\r` from each line (`line="${line%$'\r'}"`) before parsing. `read -r` does not
     remove it, and an untreated CRLF leaves a stray `\r` inside `rel`, splitting the `rel`-keyed set
     arithmetic into spurious duplicate rows whenever only one side has CRLF endings;
   - reject (as a round-trip failure) any physical line beyond a fixed cap — 8 KB, far above any real
     row — rather than reading an unbounded line into memory;
   - quote every expansion; never iterate rows by word splitting.
2. **Validate every input by round-trip, not by checklist.** For each file: parse it, re-render the
   parsed rows through the shared renderer, and **byte-compare against the input**. Any mismatch →
   exit 1. This is strictly stronger than a list of structural assertions — it makes a misparse
   impossible to act on (a title containing `](`, a `rel` containing `)`, a stray bracket) and it pins
   the extracted renderer's byte-identity to the generator's on *every merge*, not only in a parity
   test. All three inputs are validated, including the ancestor: the ancestor is the base of the set
   arithmetic and is just as capable of being corrupt.
3. **Three-way merge keyed on `rel`.** Start from the ancestor set; drop rows deleted on either side;
   add rows added on either side. When a `rel` present in all three carries a different title on the
   two sides and both differ from the ancestor → exit 1. When only one side changed the title, take
   the changed one.

   **Two-sided add of the same `rel` with different titles → exit 1.** The rule above covers a `rel`
   present in all three versions. A `rel` *absent from the ancestor* and independently added on both
   sides with different titles is a distinct shape, and "add rows added on either side" does not say
   which title wins. It must not silently pick one. In practice this coincides with a git-level
   add/add conflict on the underlying `.md` file, which halts the merge anyway — but the driver runs
   for the index path independently of that, so leaving it undefined would let it exit 0 with an
   arbitrary title and quietly break AC2's byte-identity guarantee for that input shape. T20 pins it.

   **`rel` is checked for containment, separately from round-trip.** Unlike the generator — which only
   ever emits a row for a file it found itself via `find "$KB_DIR" -type f -not -type l -name '*.md'`
   — the driver's row set is a pure function of whatever `rel` strings appear in the three inputs. A
   branch that hand-edits `INDEX.md`, bypassing the generator, can introduce
   `- [Note](../../.env)`, and that row round-trips byte-identically, so validation step 2 cannot see
   it. Any row from any input whose `rel` is absolute, contains a `..` segment, or resolves outside
   `knowledge-base/` is a validation failure. This matters because M16's five consumers treat index
   rows as trustworthy relative paths and follow them.
4. **Render** through `scripts/lib/kb-index-render.sh` — the block extracted verbatim from
   `generate-kb-index.sh` — so section grouping, `LC_ALL=C sort` ordering and the `> Total files:`
   line have exactly one implementation.
5. Write to `%A`, exit 0.

**Every failure path writes a sentinel first (P6) — via an `ERR` trap, not by hand.** M7 measured
that a non-zero exit leaves ours content with no conflict markers — a file that reads as clean and
therefore invites exactly the `git add` reflex this issue is about, one layer down. The driver writes
a real conflict-marker line into `%A`:

```
<<<<<<< kb-index: merge driver could not resolve — re-run the merge after fixing registration
```

so the failure is visible to a reader and trips `guardrails:block-conflict-markers` in
`.claude/hooks/guardrails.sh` if anyone stages it.

**The sentinel must not be a manual write placed before each deliberate `exit 1`.** The sibling
generator opens with `set -euo pipefail` and this driver will follow the same house style, which
means an *unhandled* failure — an `awk` crash on adversarial input, an unbound variable under
`set -u`, a `read` failure on an embedded NUL, a signal, disk-full while writing `%A` — terminates
the script through the shell's own `-e` mechanism without ever reaching a hand-placed sentinel line.
That reproduces M7 exactly, one level down, and specifically on the adversarial-input paths this
design must assume are reachable. So the driver installs
`trap 'write_sentinel; exit 1' ERR` **before any parsing begins**; the writes at the named `exit 1`
call sites become defence in depth, not the mechanism.

**Where a row-set merge is *not* equivalent to regenerating.** The equivalence holds only while each
row's title is a pure function of that one file's bytes and both sides ran the same generator. Three
cases break it, none visible to a structural check:

1. **Rename plus edit across branches.** One side renames `X.md` → `Y.md`; the other edits `X.md`'s
   title. Git's rename detection merges the edit into `Y.md`, but the row set sees a delete of `X`'s
   row and an add of `Y`'s row carrying the *pre-edit* title.
2. **A generator rule change on one branch** — eligibility (ADR-174 / #7400), title extraction,
   escaping. The other side's rows were rendered under the old rules and are merged verbatim.
3. **A future title source outside the file** (frontmatter inheritance, a category file).

This is precisely why the CI guard is a regeneration diff and not a structural lint: only re-running
the generator over the merged tree catches all three. The driver makes the common case (both sides
only added files) correct and conflict-free; the guard makes the uncommon case loud.

### Precedent diff (deepen-plan Phase 4.4)

Four of this plan's five mechanisms have a sibling precedent in the repo. The fifth does not, and is
flagged so reviewers scrutinise it.

| Mechanism | Precedent | Divergence |
|---|---|---|
| Freshness guard | `scripts/regenerate-c4-model.sh` takes `--out PATH` ("Write the validated model to PATH instead of the tracked artifact") and `plugins/soleur/test/c4-model-freshness.test.sh` does the `cmp -s "$FRESH" "$COMMITTED"` with a `diff <(jq -S …)` diagnostic on failure | **Adopt the seam, not just the idea.** `generate-kb-index.sh` gains `--out DIR` as the primitive — writing `INDEX.md`, `kb-tags.txt`, `kb-categories.txt` into `DIR` instead of `$KB_DIR` — and `--check` is a thin wrapper (`--out "$(mktemp -d)"` then diff). The wrapper is the only divergence, justified by `## Observability`'s `discoverability_test.command` needing one runnable command. Existing arg handling is a single `[[ "${1:-}" == "--help" ]]`, so both flags are additive. |
| Mutation matrix | Two forms coexist. The *recorded* form (`plugins/soleur/test/fixture-relative-assert.test.sh`, anchor `# MUTATION MATRIX (Guard 1, #7708) -- executed in place against a pristine backup, with a GREEN unmutated control required first`) writes observed verdicts into a header comment. The *executable* form is a separate `*.mutation.sh` file that runs the battery — `plugins/soleur/test/git-fixture-env.mutation.sh`, `hook-git-env-coverage.mutation.sh`, `scripts/orphan-process-reaper-mutation.test.sh`, `scripts/ship-incident-pir-gate-mutation.test.sh`, `scripts/cf-tunnel-liveness-gate-mutations.test.sh` | **Adopt the executable form.** It is what `scripts/test-all.sh` actually registers and what makes AC14 assertable rather than narrative. The recorded form is kept as the header comment inside each `.mutation.sh` file, so the plan gets both: a battery CI runs, and a human-readable verdict ledger. |
| Fixture git repo performing a real merge | `plugins/soleur/test/gitleaks-merge-commit.test.sh` — `mktemp -d`, `git init -q -b trunk`, inline identity, a genuine conflict, `git rev-list --parents -1 HEAD \| wc -w == 3` | Adopt unchanged. |
| Shared harness + `GIT_*` tripwire | `plugins/soleur/test/test-helpers.sh`, anchor `# --- Guard 3 (#7833): fail-loud git-location tripwire` (exit 97), plus the `MIN_ASSERTIONS` anti-vacuity floor in `plugins/soleur/test/generate-kb-index.test.sh` | Adopt unchanged; the new suite declares its own floor. |
| **A git merge driver, and a production shell script that writes `git config`** | **No precedent.** No `.gitattributes` has ever existed in this repo; the learnings sweep found nothing on `merge.driver` / `git merge-file` / the `merge=` attribute. Every `git config` write in the repo today is inside a test fixture (`git config user.email t@t`); the only production config-write pattern is TypeScript (`atomicGitConfig` in `apps/web-platform/server/git-config-atomic.ts`, a `cp`-seed → `git config --file <tmp>` → `rename` sequence) | **Novel — scrutinise.** The shell script deliberately does not port `atomicGitConfig`'s hand-rolled sequence: plain `git config` already serialises through `.git/config.lock` and never hand-serialises INI, which is the property that pattern exists to guarantee. What it borrows is the posture: best-effort, never throw, always report. |

### Mutation harness mechanics

The two matrices below are narrative until the harness is specified, so it is specified here. The
mechanism is lifted from `plugins/soleur/test/git-fixture-env.mutation.sh`, which
`orphan-process-reaper-mutation.test.sh` and `ship-incident-pir-gate-mutation.test.sh` both reuse:

1. `cp` the script under test to a pristine reference copy under `mktemp -d`.
2. Per row: restore from pristine, then apply the mutation with a Python heredoc doing
   `s.replace(old, new, 1)` guarded by `assert old in s` — **never an inline `sed` string**, because a
   quoted body containing apostrophes silently no-ops.
3. **Assert the mutation landed** (`diff -q pristine mutant` must differ) *before* scoring the row. A
   mutation that does not land reports the baseline, which is indistinguishable from a pass — that is
   the vacuity this whole battery exists to prevent.
4. Run a **green unmutated control first** and abort with a distinct exit code if it is red; every row
   below it is meaningless otherwise.
5. Run the guard against the mutant, capture red/green, compare to expected.
6. `trap 'restore; rm -rf "$WORK"' EXIT INT TERM HUP`, so the working tree is never left mutated.

**The copy must replicate the directory shape.** Both `generate-kb-index.sh` and
`merge-kb-index.sh` will `source` `scripts/lib/kb-index-render.sh`. A flat `cp` of either script into
`$WORK/` leaves that `source` resolving to a non-existent `$WORK/lib/kb-index-render.sh`, so the
mutant fails to parse and **every row reports a spurious RED that is a missing-file crash, not a
caught defect** — a battery that looks perfect while testing nothing. The harness does
`mkdir -p "$WORK/lib"` and copies both files. This also gives Guard 2's renderer-drift row its
implementation: mutate only `$WORK/lib/kb-index-render.sh`, leave the driver copy pristine, feed it
inputs rendered by the *original* renderer, and assert round-trip validation fails.

`scripts/generate-kb-index.test.sh` already exposes the override this needs —
`GEN_SCRIPT="${GEN_SCRIPT:-$REPO_ROOT/scripts/generate-kb-index.sh}"`, added precisely so "the
mutation battery can point at a scratch copy of the script without mutating the working tree".

**Guard 2's rows are exercised by direct invocation** (`bash "$mutant_driver" "$O" "$A" "$B" "$P"`),
not through `git merge`: their properties are about the driver's own validation loop, not git's merge
machinery. The full `git merge`-through-fixture-config path is reserved for the functional scenarios
where the git invocation contract (M4, M20) is itself under test. Where a fixture *does* register the
driver, an **absolute** path into `$WORK` is correct — that is a throwaway repo, and it is a different
code path from the worktree-relative production registration that M20 and AC8 govern. Conflating the
two would either weaken AC8 or break the harness.

**Every generator and `--check` invocation in every suite passes an explicit `KB_DIR=<fixture>`
pointing at a synthetic corpus of ten files or fewer.** `generate-kb-index.sh` defaults `KB_DIR` to
the real 6,432-file tree, so an omitted pin silently costs M9's 9.9 s per call. Counting the design
as written — the merge scenarios, the unregistered case, Guard 1's control plus nine rows plus two
harness rows, and T13 — that is roughly nineteen invocations, i.e. over three minutes of accidental
real-corpus work if the pin is forgotten, with nothing in the suite that would notice. The check in
AC17 is the single call permitted to run against the real tree, and it runs exactly once.

### The guard: `scripts/generate-kb-index.sh --out DIR` and `--check`

`--check` regenerates into a temporary directory and diffs against the committed
`knowledge-base/INDEX.md`, `kb-tags.txt` and `kb-categories.txt`, printing the diff and exiting
non-zero on any mismatch. One implementation, no second copy of the eligibility predicate, and it
catches every case a structural lint would miss: the M1 silent fallback (the count is wrong, or a row
is absent), renderer drift, the rename divergence, and a `--theirs` side-pick.

It runs from a case in the new CI suite, so `SUITE_GLOBS` picks it up with no workflow edit. It is
**not** wired into lefthook, and the reason is stronger than "it would be redundant". Measured against
the real `lefthook` v2.1.6 in a fixture: lefthook computes every command's staged-file-vs-glob match
**once**, from the `git diff --cached` snapshot taken before any command runs. A `git add` performed
by the priority-10 `generate-kb-index` stanza is therefore invisible to a priority-11 command's glob
filter. With an exact-path glob on `knowledge-base/INDEX.md`, the fixture printed
`(skip) no matching staged files` for the priority-11 command on the ordinary "add a KB file and
commit" flow — the very scenario the guard would exist to protect. A lefthook arm here is not merely
vacuous; on the dominant path it does not execute at all. CI is the only honest home for it.

**What `--check` sees on a `pull_request` checkout, measured rather than assumed.**
`actions/checkout` resolves `refs/pull/N/merge` — a merge GitHub computed server-side, which never
consults `.gitattributes`. Two cases, and the plan takes a position on both:

- **Head and base each added a different number of KB files since the fork point.** The
  `> Total files:` line is a genuine textual conflict, GitHub cannot produce the merge ref, and the PR
  shows as unmergeable. CI does not run on a stale snapshot; the branch must sync. This is the
  latency symptom the issue reports, surfacing at the GitHub layer.
- **Head and base each added the *same* number.** Both sides wrote the identical count text, git
  merges the line cleanly to a value that is wrong by construction (M2), rows union in at their sorted
  positions, and `--check` goes **red** with no row loss. This is a true positive on the artifact — the
  merge ref's index really is wrong — but it is not actionable except by re-syncing the branch, which
  the developer must do anyway. It is called out here because it is the one shape where a red check
  does not mean "someone resolved badly", and `## Test Scenarios` T13 pins it so no future reader has
  to rediscover it.

### Registration: `scripts/install-kb-merge-driver.sh`

Idempotent and silent when already correct: read `git config --get merge.kb-index.driver`, write only
when absent or different.

**The config value is a relative command, not an absolute path.** M20 measured that git invokes the
driver with CWD at the working-tree root even when `git merge` runs from a subdirectory, so
`bash scripts/merge-kb-index.sh %O %A %B %P` is correct in all 37 worktrees with nothing baked in.
This matters: the repo is bare with linked worktrees, `--show-toplevel` returns the *calling*
worktree's root, and baking that into the shared config would pin the driver to a feature worktree
that gets deleted after merge — producing a mystery flurry of conflicts across unrelated worktrees.
`--git-common-dir` is no better here, because the bare repo's parent contains no `scripts/`.

It writes a plain top-level key to the shared `.git/config` and **must not** touch `config.worktree`
or set `extensions.worktreeConfig` (ADR-173's re-arm trigger). Concurrency: `git config` already
serialises through `.git/config.lock`; the script retries once on a lock failure and otherwise reports
to stderr and **exits 0** — it must never block session start for 37 worktrees' worth of sessions.

**Porcelain calls only, never a file edit.** The script mutates `.git/config` exclusively through
`git config <key> <value>` and never by editing or rewriting the file. This is a stated constraint,
not an implicit one, because the shared config also holds `core.hooksPath` — and a bug that clobbered
*that* key would silently disarm every lefthook gate across all 37 worktrees at once
(`guardrails:block-conflict-markers`, the commit-on-main guard, `gitleaks-staged`), which is a far
worse outcome than the unregistered merge driver this script exists to prevent. The TypeScript
sibling `atomicGitConfig` (`apps/web-platform/server/git-config-atomic.ts`) exists to get this
property via `cp`-seed → `--file <tmp>` → `rename`; the shell script gets it for free by never leaving
porcelain, and borrows only the posture: best-effort, never throw, always report.

Concurrent invocation is a realistic shape, not a hypothetical one: parallel agent sessions across 37
worktrees can fire `SessionStart` simultaneously, which is exactly the shape of the 2026-08-09
incident this plan cites. AC7 and T10 test idempotency *sequentially*; T17 adds the parallel case.

**Where registration has to reach — and where it does not.** M13 measured that no CI workflow merges,
so every merge this driver exists for happens in a local checkout. Two surfaces:

- **`.claude/settings.json` `SessionStart`** — appended to the existing array
  (`session-rules-loader.sh`, `supabase-loopback-warn.sh`, `memory-backstop.sh`). Merges in this
  workflow happen inside agent sessions in `.worktrees/`, so this is the highest-yield surface by a
  wide margin. Because the key lives in the shared config, the first session to fire registers it for
  every worktree.
- **`package.json` `"prepare"`** — fires on a bare local `npm install`, the only thing that covers the
  clone-then-immediately-merge sequence before any agent session exists. It also fires in CI's
  `lockfile-sync` job (M14), which is harmless — that runner never merges — but the plan does not
  count CI as covered by it, because a registration that only exists on one ephemeral runner protects
  nothing. This is the weakest surface and the reviewer panel split on keeping it; it stays because it
  is the only answer to the issue's literal "must not silently no-op on a fresh clone", and it is one
  line.

**The residual window is real and is stated, not papered over.** A brand-new clone whose very first
action is `git merge`, before any agent session and before any dependency install, has no driver. That
merge line-merges silently (M1). The `--check` guard catches the result at the first push. There is no
mechanism in git that closes this window, and the plan does not pretend otherwise.

### The conflict-resolution routing correction

M15 found that `plugins/soleur/skills/merge-pr/SKILL.md` routes `knowledge-base/INDEX.md` to
"Everything else → Claude-assisted resolution", whose first step is "read the file with conflict
markers" — which M7 guarantees are absent. That is a live path to the reported bug through the repo's
own skill, and it is one paragraph to fix. §3.2b gains the three generated knowledge-base paths as
known members, with the correct remedy: **re-run the merge after fixing registration; never side-pick,
and never look for markers.** The generic "take `--theirs`, then re-run the owning generator" strategy
in §3.1 is explicitly wrong for these three (M5 — regenerating from one side's tree drops the other
side's rows), so the note says so.

### The kb-tags.txt / kb-categories.txt decision (the issue's second acceptance criterion)

**Both files get git's built-in `merge=union`; the mirrored copies under
`plugins/soleur/knowledge-base/` get nothing; and the lefthook stanza is widened so the two files are
actually staged.**

- They are the same defect class for P1 — same generator, both committed, both append-mostly, and a
  side-picking resolve drops the other side's tags.
- They are **not** the same class for P2: no derived header, so M2's count corruption cannot occur.
- The **content** consumer is `plugins/soleur/skills/kb-search/SKILL.md`, which validates with
  `grep -Fxq "$tag_lc" knowledge-base/kb-tags.txt` — an exact-line check indifferent to ordering and
  duplicates. Union's weaknesses (possible unsorted or duplicated lines until the next generator run)
  are invisible to it. Two other places reference the files by **name** only:
  `.claude/hooks/kb-domain-allowlist-guard.sh` lists them in a `SANCTIONED_FILES` allowlist, and
  `plugins/soleur/skills/compound-capture/SKILL.md` points readers at them but delegates lookup to
  `kb-search`. Neither cares about row order or duplicates, so the union argument holds — but "the
  only consumer" would have been an overclaim, and this is the accurate enumeration. A bespoke driver
  mode would add code and a registration dependency to buy nothing the built-in does not already buy,
  and union — being built in — has no unregistered-failure mode at all.
- Reachability was a real gap: M18 measured `kb-categories.txt` a month stale because the lefthook
  stanza stages only `INDEX.md`. Widening that `git add` to all three (one line, in a stanza already
  being edited for M17) is what makes the union entries reachable rather than decorative.
- `plugins/soleur/knowledge-base/{INDEX.md,kb-tags.txt,kb-categories.txt}` are excluded: nothing in the
  repo writes them, so there is no generator for them to be a pure function of. The `.gitattributes`
  patterns are anchored to the root paths and cannot match the mirror.

This section is reproduced in the PR body.

## Files to Create

- `.gitattributes` (repo root) — `knowledge-base/INDEX.md merge=kb-index`,
  `knowledge-base/kb-tags.txt merge=union`, `knowledge-base/kb-categories.txt merge=union`, plus a
  comment naming the driver and the registration script.
- `scripts/merge-kb-index.sh` — the driver.
- `scripts/lib/kb-index-render.sh` — the render helper shared with the generator.
- `scripts/install-kb-merge-driver.sh` — idempotent registration.
- **Four suites, split on the seam this repo already uses.** `scripts/test-all.sh`'s registration
  comments state the rationale directly: *"the behavioural suite proves the detector can detect a
  planted orphan, and the battery is the only thing that proves each of its GUARDS can be driven
  red."* Every guard-with-battery pair in the tree is two files —
  `scripts/orphan-process-reaper.test.sh` + `orphan-process-reaper-mutation.test.sh`,
  `plugins/soleur/test/hook-git-env-coverage.test.sh` + `hook-git-env-coverage.mutation.sh`,
  `scripts/ship-incident-pir-gate.sh` + `ship-incident-pir-gate-mutation.test.sh`. Bundling all four
  concerns into one file makes a red run ambiguous between "a scenario broke" and "a guard stopped
  being enforceable", folds the ~90 s battery into the fast suite's timing budget, and mixes two
  unrelated fixture shapes. All four live under `plugins/soleur/test/`, which `SUITE_GLOBS`
  auto-discovers — root-level `scripts/*.test.sh` would need explicit `run_suite` registration.
  - `plugins/soleur/test/kb-index-merge-driver.test.sh` — functional: T1, T3–T9, T12–T14, T16, T18,
    T19, render parity, AC1–AC6, AC12, AC13.
  - `plugins/soleur/test/kb-index-merge-driver-registration.test.sh` — AC7–AC11, T10, T11, T17.
  - `plugins/soleur/test/kb-index-check-guard-mutation.test.sh` — Guard 1's battery.
  - `plugins/soleur/test/merge-kb-index-driver-mutation.test.sh` — Guard 2's battery.
- `knowledge-base/engineering/architecture/decisions/ADR-210-regenerating-merge-driver-for-committed-generated-artifacts.md`
  — ordinal provisional; see `## Architecture Decision (ADR/C4)`.

## Files to Edit

- `scripts/generate-kb-index.sh` — source `scripts/lib/kb-index-render.sh` in place of the inline
  render block; add `--out DIR` (the primitive, mirroring `regenerate-c4-model.sh --out`) and
  `--check` (the wrapper); replace the `--help` line that currently prescribes a hand-run
  post-conflict regeneration. Existing arg handling is a single `[[ "${1:-}" == "--help" ]]`, so both
  flags are additive; the four live callers (`lefthook.yml`, `kb-search/SKILL.md`,
  `compound-capture/SKILL.md`, `generate-kb-index.test.sh`) all invoke it with no arguments and are
  unaffected.
- `lefthook.yml` — in the existing `generate-kb-index` stanza only: make the glob a dual glob
  (`knowledge-base/*.md` plus `knowledge-base/**/*.md`) so a commit staging only `INDEX.md` still
  regenerates (M17), and widen `git add` to all three generated files (M18). No new stanza.
- `.claude/settings.json` — append the registration hook to the existing `SessionStart` array.
- `package.json` — add `"prepare": "bash scripts/install-kb-merge-driver.sh"`.
- `plugins/soleur/skills/merge-pr/SKILL.md` — §3.2b known-members list and the routing note (M15).
- `.github/CODEOWNERS` — explicit rows for `scripts/merge-kb-index.sh`,
  `scripts/lib/kb-index-render.sh` and `scripts/install-kb-merge-driver.sh`. The blanket `*` rule
  already assigns the owner; per the file's own convention these rows exist to record **which** files
  are gate-critical. See `## Risks & Mitigations` for what this does and does not buy today.
- `knowledge-base/INDEX.md`, `knowledge-base/kb-tags.txt`, `knowledge-base/kb-categories.txt` — all
  three are named because one generator run rewrites all three, so all three are candidates for the
  diff. M18b measured that only `INDEX.md` will actually change (the other two are already
  content-identical to a fresh generation), which is what keeps this a merge-driver diff rather than
  one carrying a month of facet churn.
- `knowledge-base/project/specs/feat-one-shot-7935-kb-index-merge-driver/tasks.md` — created by this
  skill.

## Open Code-Review Overlap

Two of the 63 open `code-review` issues name a file this plan edits.

- **#2231** *perf(kb-search): skip past frontmatter with nextfile in facet extraction* — names
  `scripts/generate-kb-index.sh`. **Acknowledge.** It targets the `awk` facet-extraction pass; this
  plan touches the render block and adds `--check`. Different region, different concern; folding a
  perf change into a correctness PR would widen the diff for no shared risk. Stays open.
- **#2963** *review: introduce Supabase typegen for ConversationPatch drift resistance* — names
  `package.json`. **Acknowledge.** It concerns a typegen script; this plan adds a `prepare` key. No
  interaction. Stays open.

## Implementation Phases

### Phase 0 — preconditions (no code)

- Re-run the ADR ordinal probe across every `origin/*` ref before writing the ADR and again before
  merge; ADR-210 is provisional (highest claimed across refs at plan time: ADR-209).
- Confirm `bash scripts/generate-kb-index.sh` still produces a small delta, so the regenerated
  `INDEX.md` in the diff carries no unrelated drift.
- Confirm the lefthook dual-glob change actually matches by running `lefthook run pre-commit` with only
  `knowledge-base/INDEX.md` staged — gobwas semantics are the whole reason M17 exists, so the fix must
  be observed, not reasoned about.

### Phase 1 — RED: the merge suite

Write `plugins/soleur/test/kb-index-merge-driver.test.sh` first and show it failing. It sources
`plugins/soleur/test/test-helpers.sh` for the Guard 3 `GIT_*` tripwire, builds a fixture under
`mktemp -d` with `git init -q -b trunk`, seeds a small knowledge-base corpus, generates the index by
calling the real generator with `KB_DIR` pointed at the fixture, branches twice, adds one distinct
file per branch, regenerates on each, registers the driver in the **fixture's own** config, performs a
real `git merge`, and asserts both rows are present, the header count equals the row count, the merge
has two parents, and the merged file is byte-identical to a fresh generator run over the merged
corpus.

### Phase 2 — GREEN: render helper, driver, `--out`/`--check`, and both batteries

Extract the render block; write the driver with `%P` validation, the safe-parsing constraints, the
`ERR`-trap sentinel, round-trip validation and path containment; add `--out DIR` and `--check`.
Re-run Phase 1 to green.

**Both mutation batteries are written here, not in Phase 1.** Rows G1-7, G1-8 and G1-9 mutate
`--check`'s own dispatch, and G2-3 mutates the driver's validation loop — none of those anchors exist
until this phase writes them, so they cannot be authored (let alone driven red) before the code they
mutate. Phase 1's RED is the functional suite only; the batteries are a Phase 2 exit criterion.

### Phase 3 — registration

Write `scripts/install-kb-merge-driver.sh`; wire `SessionStart` and `prepare`; add the idempotency,
worktree-relative-path, `extensions.worktreeConfig`, held-lock and parallel-invocation cases to
`plugins/soleur/test/kb-index-merge-driver-registration.test.sh`.

### Phase 4 — wiring, routing correction, CODEOWNERS, ADR

`.gitattributes`, the `lefthook.yml` stanza fixes, `merge-pr/SKILL.md` §3.2b, the three
`.github/CODEOWNERS` rows, the ADR, the generator `--help` correction, and the regenerated index.

### Phase 5 — verification

`bash scripts/test-all.sh scripts`, `bash scripts/lint-orphan-test-suites.sh`,
`bash plugins/soleur/test/c4-count-parity.test.sh`, then walk `## Acceptance Criteria`.

## User-Brand Impact

**If this lands broken, the user experiences:** a knowledge-base file that exists in the repository
but is unreachable from `knowledge-base/INDEX.md`, so `soleur:kb-search` and every research agent that
greps the index report "no such learning" for work that was actually written — the ADR-206 drop, made
permanent.

**If this leaks, the user's data is exposed via:** no new data path — the change moves no user data
and opens no egress. But the honest statement is not "nothing", and an earlier draft's "the driver
executes only code already committed" was a risk description phrased as reassurance. What this
change actually creates is a **new unattended local-execution surface**: after registration, an
ordinary `git merge` / `pull` / `rebase` / `cherry-pick` that touches `knowledge-base/INDEX.md`
executes `scripts/merge-kb-index.sh` as the invoking user, with no prompt and nothing in the merge
output distinguishing it from a conflict-free merge. That path runs on a file touched 27 times in 30
days, across 37 worktrees, including fully automated sessions. Guard 1 validates *artifact content*,
so a driver that emits a byte-correct index while also doing something else passes every acceptance
criterion here. The controls are: the script is small and reviewed, it gains explicit CODEOWNERS
rows (AC26), and M4 means the first merge that brings a modified driver into a worktree still runs
the *old* copy — exposure would begin only on a subsequent merge, after the change is already
checked out and reviewable.

**Brand-survival threshold:** `none` — the Files-to-Edit set is scripts, hooks, CI-discovered tests
and knowledge-base markdown; it matches no sensitive-path pattern (no `supabase/migrations/`, no
`app/api/`, no auth flow, no `.tf`). Reason recorded for preflight Check 6: *threshold: none, reason:
the change is developer-tooling only and touches no runtime, no persistence and no user-facing
surface.*

## Acceptance Criteria

### Pre-merge (PR)

1. **AC1 — real merge, both rows.** `bash plugins/soleur/test/kb-index-merge-driver.test.sh` exits 0.
   Its central case constructs two branches that each add a distinct knowledge-base file, performs an
   actual `git merge`, and asserts `grep -c` for **each** branch's row in the merged `INDEX.md`
   returns 1. Verified by performing the merge, not by reading the driver definition.
2. **AC2 — merged file equals a fresh generation.** The same case asserts byte-identity with
   `KB_DIR=<merged fixture> bash scripts/generate-kb-index.sh` output.
3. **AC3 — genuine two-parent merge.** `git rev-list --parents -1 HEAD | wc -w` returns 3 in the
   fixture, proving the assertion is not made against a fast-forward.
4. **AC4 — header count truth.** In the merged fixture index, the integer on `> Total files:` equals
   `grep -c '^- \['` of the same file.
5. **AC5 — the unregistered case is caught.** The suite runs the identical scenario with
   `merge.kb-index.driver` unset, asserts the resulting index differs from a fresh generation, and
   asserts `KB_DIR=<fixture> bash scripts/generate-kb-index.sh --check` exits non-zero on it. This is
   the executable form of the issue's third acceptance criterion.
6. **AC6 — no clean-looking failure.** With a deliberately corrupted ancestor index, the driver exits
   non-zero **and** `grep -c '^<<<<<<< kb-index' "$A"` returns 1 — the sentinel that makes M7's
   markerless conflict visible and trips `guardrails:block-conflict-markers`.
7. **AC7 — registration is idempotent and automatic.** `bash scripts/install-kb-merge-driver.sh` run
   twice in a fixture leaves one value and prints no error; a third run after the key is deleted
   restores it; a run against a config already holding the correct value performs no write.
8. **AC8 — registration is worktree-portable.** The stored value contains no absolute path:
   `git config --get merge.kb-index.driver | grep -c '^/'` returns 0, and the fixture asserts the
   driver still resolves when `git merge` is invoked from a subdirectory.
9. **AC9 — registration never arms the worktree-config wedge.**
   `grep -c 'extensions\.worktreeConfig\|config\.worktree' scripts/install-kb-merge-driver.sh` returns
   0, and the fixture asserts `git config --get extensions.worktreeConfig` is still unset afterwards.
10. **AC10 — registration never blocks a session.** With `.git/config` held under a stale
    `config.lock`, the script exits 0 and writes a diagnostic to stderr.
11. **AC11 — both registration surfaces are wired.** `grep -c 'install-kb-merge-driver'` returns ≥ 1
    in each of `package.json` and `.claude/settings.json`. The plan asserts wiring only, and
    `## Design` states in prose that `prepare` does not fire in CI, so no AC may claim CI coverage.
12. **AC12 — `.gitattributes` names all three generated paths and nothing under the plugin mirror.**
    `git check-attr merge -- knowledge-base/INDEX.md` reports `kb-index`;
    `... -- knowledge-base/kb-tags.txt` and `... -- knowledge-base/kb-categories.txt` report `union`;
    `... -- plugins/soleur/knowledge-base/INDEX.md` reports `unspecified`.
13. **AC13 — render parity.** The suite asserts the extracted helper and the generator produce
    byte-identical output for a fixture corpus, and that the generator retains no second copy of the
    header literal (`grep -c 'Total files:' scripts/generate-kb-index.sh` returns 0 — the literal now
    lives only in `scripts/lib/kb-index-render.sh`).
14. **AC14 — the mutation batteries run and score every row.**
    `bash plugins/soleur/test/kb-index-check-guard-mutation.test.sh` exits 0 with all **12** rows scored
    `ok`, and `bash plugins/soleur/test/merge-kb-index-driver-mutation.test.sh` exits 0 with all **13**
    rows scored `ok`. (The 14/12 split written at plan time was an estimate made before the code
    existed; these are the rows the implementation actually admits. Both files carry their real
    count in `EXPECTED_ROWS`, which is the binding number.) Both are registered explicitly in
    `scripts/test-all.sh` under `want_scripts`: `SUITE_GLOBS` covers
    `plugins/soleur/test/*.test.sh` and these end in `.mutation.sh`, so nothing auto-discovers
    them — including `lint-orphan-test-suites.sh`, which walks only `*.test.sh` and would report
    zero orphans while an unregistered battery gated nothing. Either file failing its own `EXPECTED_ROWS` check fails AC14. Each battery runs a green
    unmutated control first, asserts every mutation *landed* before scoring it, and reports a
    row-count shortfall by direct `printf >&2; exit 1` rather than through the `FAIL` counter. Each
    file also carries a `# MUTATION MATRIX` header comment recording the observed verdicts, per
    `plugins/soleur/test/fixture-relative-assert.test.sh`.
15. **AC15 — no orphan suites.** `bash scripts/lint-orphan-test-suites.sh` exits 0 with the new suite
    present.
16. **AC16 — full scripts shard green.** `bash scripts/test-all.sh scripts` exits 0.
17. **AC17 — the committed index is fresh.** `bash scripts/generate-kb-index.sh --check` exits 0
    against this branch's own tree.
18. **AC18 — the lefthook stanza reaches the index and the facet files.** `lefthook run pre-commit`
    with only `knowledge-base/INDEX.md` staged reports the `generate-kb-index` command as executed,
    not skipped (M17), and `grep -c 'kb-tags.txt' lefthook.yml` returns ≥ 1 (M18).
19. **AC19 — the routing correction landed.**
    `grep -c 'knowledge-base/INDEX.md' plugins/soleur/skills/merge-pr/SKILL.md` returns ≥ 1, and the
    added text contains no instruction to side-pick or to look for markers on these paths.
20. **AC20 — generator help no longer prescribes the hand-run remedy.**
    `grep -c 'After merge conflicts on INDEX.md, regenerate' scripts/generate-kb-index.sh` returns 0,
    and the replacement names the driver and the registration script.
21. **AC21 — the ADR exists at its final ordinal.** The file matched by
    `knowledge-base/engineering/architecture/decisions/ADR-2??-*merge-driver*.md` exists, and
    `grep -rn 'ADR-<superseded ordinal>' knowledge-base/project/{plans,specs}/` returns nothing after
    any renumber.
22. **AC22 — PR body carries `Closes #7935`** and reproduces
    `## The kb-tags.txt / kb-categories.txt decision` verbatim.
23. **AC23 — scope discipline.** The diff touches neither `.github/workflows/ci.yml` nor
    `plugins/soleur/skills/ship/SKILL.md`.
24. **AC24 — the parse is inert against hostile input.** T21's fixture (a title carrying `$(id)`,
    backticks, a semicolon and a quote) round-trips unchanged, and
    `grep -c '\beval\b' scripts/merge-kb-index.sh` returns 0.
25. **AC25 — path containment and `%P` are enforced.** T18, T19 and T20 each produce a non-zero exit
    and a sentinel.
26. **AC26 — the gate-critical scripts carry explicit CODEOWNERS rows.**
    `grep -c 'merge-kb-index.sh\|kb-index-render.sh\|install-kb-merge-driver.sh' .github/CODEOWNERS`
    returns 3.

### Post-merge (operator)

None. Registration runs from `SessionStart` and the `prepare` lifecycle script; no step is left to a
person.

## Guard Contract

### Guard 1 — `scripts/generate-kb-index.sh --check`

**Property.** No `knowledge-base/INDEX.md`, `kb-tags.txt` or `kb-categories.txt` reaches `main` whose
content differs from what the generator would emit for the tree it sits in.

**Assembly.** The chokepoint is the **committed artifact read from disk and diffed against a fresh
generation** — not the set of ways it was produced. That is what makes the guard blind to whether the
driver ran, and therefore what makes it cover the unregistered case (M1), renderer drift, the rename
divergence, and a `--theirs` side-pick with one mechanism. It is dispatched from exactly one place:
the case in `plugins/soleur/test/kb-index-merge-driver.test.sh`, reached by `SUITE_GLOBS` in the
`test-scripts` shard. It is deliberately **not** dispatched from lefthook, where the priority-10
regeneration would make it vacuous.

**Mutation matrix.** IDs are `G1-*` so that a bare `M<n>` anywhere in this plan means a row of the
`### Measured facts` table and nothing else — the two namespaces collided in an earlier draft, and
Guard 1's Assembly paragraph above cites Measured-fact M1 ten lines from where a locally-numbered
`M1` used to live.

| # | Edit | Must drive red |
|---|---|---|
| G1-1 | Decrement the integer on `> Total files:` by one | Guard 1 |
| G1-2 | Delete one `- [...](...)` row from the middle of a section | Guard 1 |
| G1-3 | Duplicate one row | Guard 1 |
| G1-4 | Swap two adjacent rows so `rel` ordering breaks | Guard 1 |
| G1-5 | Add a knowledge-base file without adding its row | Guard 1 |
| G1-6 | Delete one line from `kb-tags.txt` | Guard 1 — the check must quantify over all three artifacts, not only `INDEX.md` |
| G1-7 | Make `--check` compare only the first artifact and return — its own dispatch | Guard 1 must still catch G1-6 |
| G1-8 | Make `--check` exit 0 when its temp regeneration produced nothing (an empty `KB_DIR`) | Guard 1 must fail on "0 files indexed", never pass vacuously |
| G1-9 | Move the diff **after** the early `exit 0` taken when the header parses — a reorder, not a delete | Guard 1 must still catch G1-5 |

**Harness rows.**

| # | Edit to the suite (not the guard) | Must drive red |
|---|---|---|
| G1-H1 | Replace the `--check` invocation with `true` | The suite must fail its row floor, not pass |
| G1-H2 | Delete the row floor | The suite must report the drop |

**Must-pass, non-canonical.** A corpus whose titles contain escaped brackets, and a corpus with a
section holding a single row, must both pass unchanged — the contract permits both, and a guard that
rejects everything would otherwise be indistinguishable from a correct one.

**Row floor.** `plugins/soleur/test/kb-index-check-guard-mutation.test.sh` declares `EXPECTED_ROWS=14`
(9 mutations + 2 harness rows + 2 must-pass cases + 1 unmutated control) and reports a shortfall with
a direct `printf >&2; exit 1` — **never by incrementing the suite's own `FAIL` counter**. Per
`plugins/soleur/test/test-helpers.sh`, *a floor enforced through the suspect cannot witness the
suspect*: the counter is exactly what a neutered assertion helper would corrupt.

### Guard 2 — `scripts/merge-kb-index.sh`'s round-trip validation

**Property.** The driver never launders a malformed index and never fails quietly: if any of the three
inputs does not survive parse-and-re-render byte-identically, the driver writes a sentinel and raises
a conflict instead of emitting a merged file.

**Assembly.** All three inputs — `%O`, `%A`, `%B`. The recurring defect shape is validating only `%A`
and `%B` because those are the two "real" sides; the ancestor is the base of the set arithmetic and is
equally capable of being corrupt.

**Mutation matrix.**

| # | Edit | Must drive red |
|---|---|---|
| G2-1 | Corrupt the ancestor's count line only | Driver exits non-zero **and** writes the sentinel |
| G2-2 | Corrupt theirs' count line only | Same |
| G2-3 | Make the driver validate only the first input it is handed — its own dispatch | The suite must catch G2-2 |
| G2-4 | Give the same `rel` a different title on both sides, both differing from the ancestor | Driver exits non-zero rather than silently picking one |
| G2-5 | Remove the sentinel write from the failure path, keeping the non-zero exit | AC6 must fail — a non-zero exit alone is not enough (Measured fact M7) |
| G2-6 | Change the shared renderer's header text without changing the generator | Round-trip validation must fail on the very next merge |
| G2-7 | Remove the `ERR` trap, keeping the hand-placed sentinel writes, then feed a row that crashes the parser (an unbound variable, a raw NUL) rather than merely failing validation | The suite must catch a non-zero exit that wrote **no** sentinel — the M7 defect reproduced one level down |
| G2-8 | Feed a row whose `rel` is `../../.env` — one that round-trips byte-identically | Driver rejects it. A round-trip-only check cannot see this, which is why containment is a separate step |

**Harness rows.**

| # | Edit to the suite | Must drive red |
|---|---|---|
| G2-H1 | Stub the driver with `cp "$3" "$2"` (take theirs) | AC1's both-rows assertion must fail |
| G2-H2 | Remove the `git rev-list --parents` two-parent assertion | The suite's row floor must drop |

**Must-pass, non-canonical.** A merge where one side is byte-identical to the ancestor must resolve
cleanly to the changed side, with no sentinel and exit 0. A title containing `$(id)` and backticks
must round-trip as inert text — never executed, never rewritten.

**Row floor.** `plugins/soleur/test/merge-kb-index-driver-mutation.test.sh` declares `EXPECTED_ROWS=12`
(8 mutations + 2 harness rows + 1 must-pass case + 1 unmutated control), reported the same way as
Guard 1's — direct `printf >&2; exit 1`, outside the `FAIL` counter.

## Observability

```yaml
liveness_signal:
  what: the scripts CI shard runs kb-index-merge-driver.test.sh, which exercises the driver end-to-end
        and runs generate-kb-index.sh --check against the checked-out tree
  cadence: per push and per pull_request
  alert_target: the GitHub Actions check on the pull request
  configured_in: .github/workflows/ci.yml (anchor `test-scripts:`) via SUITE_GLOBS in scripts/test-all.sh
error_reporting:
  destination: process exit status, stderr, and a conflict-marker sentinel written into the merged
               file. The driver runs inside git on a developer machine with no network egress and no
               credentials, so a Sentry mirror would be an unreachable sink; the observable failures
               are git's own CONFLICT report (M7, M8), the sentinel, and a red CI check.
  fail_loud: true — the driver writes a sentinel and exits non-zero rather than emitting a file it
             could not verify, and git surfaces that as a conflict that stops the merge.
failure_modes:
  - mode: the driver is not registered, so git silently line-merges (M1)
    detection: generate-kb-index.sh --check diffs the committed artifacts against a fresh generation
    alert_route: red pull-request check on the scripts shard
  - mode: the driver is registered but its script is missing or unexecutable
    detection: git prints the exec error to stderr and raises a conflict (M8) — the merge stops
    alert_route: interactive merge output; the merge cannot complete unnoticed
  - mode: the driver runs but its render drifts from the generator's
    detection: round-trip validation fails inside the driver on the next merge (Guard 2, M15), and
               --check fails in CI
    alert_route: conflict at merge time, then a red pull-request check
  - mode: a resolve drops rows without breaking the header count
    detection: --check, which compares content rather than internal consistency
    alert_route: red pull-request check
  - mode: the registration script itself fails (unexecutable, config lock held)
    detection: it writes a diagnostic to stderr and exits 0, so the session is never blocked; the
               unregistered state it leaves behind is caught by the --check failure mode above
    alert_route: session-start stderr, then the red pull-request check
logs:
  where: GitHub Actions job logs for the scripts shard; git's own stderr locally; session-start stderr
  retention: GitHub Actions default retention
discoverability_test:
  command: bash scripts/generate-kb-index.sh --check
  expected_output: "OK: INDEX.md, kb-tags.txt and kb-categories.txt match a fresh generation (<N> files indexed)"
```

## Architecture Decision (ADR/C4)

### ADR

Write `ADR-210 — regenerating merge driver for committed generated artifacts` (ordinal
**provisional**; the probe across every `origin/*` ref found ADR-209 as the highest claimed, and
`/ship` re-verifies before merge — if it moves, sweep this plan, `tasks.md` and AC21 in the same
edit). The decision to record:

- Committed artifacts that are a pure function of a file set are merged by re-deriving the merged
  content, never by a textual merge and never by picking a side. This generalises the ad-hoc remedy
  already applied to `model.likec4.json`.
- The re-derivation happens **inside the merge driver**, from the three versions git supplies, because
  M4/M5/M6 measured that neither the working tree nor any post-merge hook can supply the merged tree
  in time.
- A merge driver's registration is a repo-local git-config write, automated from `SessionStart` and
  the `prepare` lifecycle script, stored as a worktree-relative command (M20), and deliberately not
  scoped through `extensions.worktreeConfig` (ADR-173).
- Because git gives no signal for an unregistered driver (M1), a driver is only ever half of the
  mechanism; the other half is a regeneration diff in CI. A driver shipped without one is decoration.
- `## Alternatives Considered` records: `merge=union` on the index; a `pre-merge-commit` regeneration;
  a structural consistency lint; un-tracking the generated artifacts entirely; and the 2026-04-07
  plan's blanket "do not use `.gitattributes` merge strategies", which this ADR reverses on evidence.

### C4 views

**No C4 impact**, with the enumeration that backs it, checked against all three of
`knowledge-base/engineering/architecture/diagrams/{model.c4,views.c4,spec.c4}`:

- **External human actors.** None added. No new correspondent, reviewer or recipient; the change is
  exercised by the same operator already modelled, and no actor gains or loses a path to any surface.
- **External systems.** The `#external` set is a vendor list — Anthropic API, GitHub,
  soleur-marketplace, Cloudflare, Doppler, Discord, Stripe, systemd (per-user manager), Plausible,
  Resend, Web Push Services, GitHub Container Registry, project-zot upstream, Let's Encrypt, public
  DNS resolvers, Better Stack. This change introduces no vendor, calls no API and opens no egress; a
  merge driver executes locally inside `git`.
- **Containers / data stores.** None added, removed or repurposed. `.gitattributes` and the scripts
  live inside the already-modelled repository; no queue, bucket, table or cache appears.
- **Access relationships.** None change: the driver runs with exactly the privileges of the git
  process that invokes it, on a repository the invoker has already checked out.
- **Embedded cardinalities.** No cron monitor, heartbeat slug or workflow is added, so no count in
  `model.c4`'s edge prose moves. Backed by a green run at plan time (M22) — not by the actor reasoning
  alone. Phase 5 re-runs it against the final diff.

## Domain Review

**Domains relevant:** Engineering.

### Engineering

**Status:** reviewed
**Assessment:** the CTO review independently reproduced M1, M4, M6 and M7 in its own fixtures and
raised no objection to the design or the alternatives table. It contributed three findings, all folded
in: the `prepare` surface never fires in CI (now M14, and the plan's CI-coverage claim was corrected
rather than defended); the registration script must not bake `--show-toplevel` into the shared config
(now M20, resolved by a worktree-relative command); and the cited blast radius is 37 worktrees, not 14
(now M21). It rated the guard contract as genuinely closing the loop on the reported row-loss bug,
including pre-merge via `refs/pull/N/merge`, and complexity as medium.

### Product/UX Gate

Not applicable. The mechanical UI-surface scan over `## Files to Create` and `## Files to Edit` finds
no path matching the UI-surface term list or glob superset — the set is `.gitattributes`, three shell
scripts, one shell suite, one ADR, `lefthook.yml`, `package.json`, `.claude/settings.json`, one
SKILL.md and generated knowledge-base markdown. No `components/**/*.tsx`, no `app/**/page.tsx`, no
`app/**/layout.tsx`. Product tier is **NONE**.

## Test Scenarios

| # | Scenario | Expected |
|---|---|---|
| T1 | Two branches each add one KB file; merge with the driver registered | Both rows present; count equals row count; byte-identical to a fresh generation |
| T2 | Same, with the driver unregistered | Index differs from a fresh generation **and** `--check` exits non-zero |
| T3 | One side adds a file, the other deletes a different file | Merged index has the addition and lacks the deletion |
| T4 | Both sides retitle the same file differently | Driver exits non-zero, sentinel written |
| T5 | One side changes nothing — run **twice**, once with the driver registered and once with it unset | Both resolve cleanly to the changed side. The scenario is only meaningful as a *paired* run: with the driver unset, plain git also resolves this input cleanly, so a single run proves nothing about whether the driver executed. Kept as Guard 2's over-conflict must-pass case, with the control run making "the driver ran" distinguishable from "this shape never needed it" |
| T6 | Ancestor index corrupt (count off by one) | Driver exits non-zero, sentinel written |
| T7 | `kb-tags.txt`: each side adds a distinct tag | Both present after merge (union) |
| T8 | `kb-categories.txt`: each side adds a **different** category, chosen so the unioned file violates `LC_ALL=C sort` | Both present after merge. A *plain* regeneration (never `--check`, which only reads) restores canonical order; `--check` stays red until that regeneration runs. The fixture must use two different categories — union dedupes identical lines by itself, so "both sides add the same category" would pass without exercising anything |
| T9 | `git check-attr merge` on all four paths | `kb-index`, `union`, `union`, `unspecified` |
| T10 | Registration run twice, then after deleting the key | Idempotent, then restores; no absolute path stored |
| T11 | `git merge` invoked from a subdirectory | Driver resolves via the relative command (M20) |
| T12 | Rebase instead of merge | Driver fires (M3) and the same assertions hold |
| T13 | The `refs/pull/N/merge` shape: both sides add the **same number** of KB files, line-merged without the driver | Rows both present, count wrong, `--check` red — the documented true-positive-but-only-fixable-by-syncing case |
| T14 | Fixture created with a leaked `GIT_DIR` | The Guard 3 tripwire aborts with exit 97 |
| T15 | `lefthook run pre-commit` with only `INDEX.md` staged | `generate-kb-index` executes rather than skipping (M17) |
| T16 | A crafted row triggers an **unhandled** shell error inside the parser (unbound variable, raw NUL) rather than a coded validation failure | The `ERR` trap still writes the sentinel; AC6's `grep -c '^<<<<<<< kb-index'` still returns 1 |
| T17 | N parallel `install-kb-merge-driver.sh` runs against one fixture config | No corruption, convergence on a single value, every run exits 0. Sequential idempotency (T10) does not cover this |
| T18 | A row whose `rel` is `../../.env`, byte-identical on round-trip | Driver rejects it and writes the sentinel |
| T19 | The driver invoked with `%P` set to a path other than `knowledge-base/INDEX.md` | Driver refuses, writes the sentinel, exits non-zero |
| T20 | The same `rel` added on **both** sides, absent from the ancestor, with different titles | Driver exits non-zero rather than picking a title |
| T21 | A title containing `$(id)`, backticks, a semicolon and a quote | Round-trips as inert text; nothing executes; the rendered row is unchanged |

## Risks & Mitigations

| Risk | Mitigation |
|---|---|
| **`scripts/merge-kb-index.sh` is unattended executable code on the merge path.** Once registered, it runs on every merge/rebase/cherry-pick touching the index, across 37 worktrees including automated sessions. Guard 1 checks artifact content only and cannot see a payload in a driver that still emits a correct index | Explicit CODEOWNERS rows for all three new scripts (AC26), keeping them in the file's documented "load-bearing files get explicit rows" set. **Stated honestly: this is a marker, not an enforced gate today** — `gh api repos/…/branches/main/protection` returns `Branch not protected`, and `2026-06-03-merge-is-authorization-rests-on-codeowners-review-impossible-on-solo-repo.md` records that CODEOWNERS review is structurally unenforceable on a single-maintainer repo. The rows become load-bearing the day branch protection lands, which is the same tracked follow-up the CODEOWNERS header already names. The real controls today are the script's small size, its review, and M4's one-merge delay before a modified driver executes. |
| The row parse-back (`- [title](rel)`) is ambiguous if a title ever contains `](` | Measured clean today over all 6,432 rows (M12), independently re-measured at 6,433 rows after this plan's own commit; the driver's round-trip validation makes a future misparse a loud conflict rather than a silent corruption. |
| A future generator change breaks render parity | The render lives in one file, sourced by both, and round-trip validation re-checks it on every merge (Guard 2, M15). |
| The registration script writes to a `.git/config` shared by 37 worktrees | Idempotent check-before-write; a plain top-level key; no `config.worktree`, no `extensions.worktreeConfig` (AC9); retry once on `config.lock`, then exit 0 (AC10). |
| A worktree-specific path baked into the shared config would break every other worktree | The stored value is worktree-relative; git guarantees CWD at the working-tree root (M20, AC8). |
| The fresh-clone-then-immediately-merge window has no registration | Stated openly in `## Design`; `--check` catches the result at the first push. No git mechanism closes it. |
| `--check` reddens on a `refs/pull/N/merge` checkout in the equal-additions case | A true positive on the artifact, actionable only by re-syncing. Pinned by T13 so it is not rediscovered as a mystery. |
| Adding `"prepare"` changes what a bare dependency install does | One idempotent script that exits 0 when the key is already correct; `cq-before-pushing-package-json-changes` applies; it never fires in CI (M14). |
| The lefthook dual-glob change is itself subject to gobwas semantics | Phase 0 observes `lefthook run pre-commit` with only `INDEX.md` staged rather than reasoning about the glob (AC18, T15). |
| The driver's set merge diverges from a true regeneration on rename-plus-edit | Named explicitly in `## Design`; `--check` is the mechanism that catches it, which is why the guard is a diff and not a lint. |

## Alternative Approaches Considered

| Approach | Verdict | Reason |
|---|---|---|
| Driver runs `generate-kb-index.sh` on the worktree (the issue's literal proposal) | Rejected | M4/M5: the worktree is on the ours side at driver time; it would re-create the drop. |
| `merge=union` on `INDEX.md` | Rejected | M2/M11: corrupts or duplicates the derived count line. |
| A bespoke `--flat` driver mode for the facet files | Rejected | `merge=union` already satisfies the only consumer's `grep -Fxq` contract with zero code and no unregistered-failure mode. |
| `-merge` / `merge=binary` (always conflict, resolve by hand) | Rejected | Buys P5 but loses P3 entirely — it makes every sync conflict deliberately. |
| `pre-merge-commit` regeneration | Rejected | M6: the hook's `git add` is ignored by `git merge`'s auto-commit. |
| A structural consistency lint instead of a regeneration diff | Rejected | Re-implements the eligibility predicate in a second place (ADR-174 drift) and cannot see title drift or the rename case. |
| A third registration surface on lefthook `pre-commit` | Rejected | Fires after the merge it would arm; the shared config means one surface registers fleet-wide. |
| **Stop committing the generated artifacts** (`git rm --cached` + `.gitignore`, regenerate per checkout) | **Not adopted — recorded as a challenge** | Two reviewers converged on it and the supporting facts check out (27 touches in 30 days; the generator is pure and runs in 9.9 s; `kb-search` already degrades gracefully; no CI workflow references the file; `plugins/soleur/lib/kb-coverage.ts` already calls the file "the in-repo warning for exactly this shape"). Against it: `git worktree add` does not copy ignored files, so each of 37 worktrees would start with no index and pay M9's 9.9 s from a `SessionStart` hook whose matcher fires on `startup\|resume\|clear\|compact`; the KB browser lists whatever the connected repo contains, so an untracked index stops appearing there; and un-tracking a 6,432-row file that five skills and agents grep is materially larger than #7935 scopes, against an explicit "this PR is ONLY the merge driver" instruction. Full framing in `knowledge-base/project/specs/feat-one-shot-7935-kb-index-merge-driver/decision-challenges.md`; no issue is filed, so #7935's net-issue-flow stays Closing:1 / Filing:0 / Net:-1. |
| A scheduled single-writer job that commits the index from `main` | Rejected for this PR | Still leaves every feature branch with a stale index and moves the problem rather than removing it; it is a variant of the challenge above and belongs with it. |
| Leave registration as a documented command | Rejected | `hr-never-label-any-step-as-manual-without`; the target user is non-technical. |
| Fold in the `rule-metrics.json` `merge=ours` line the 2026-07-06 plan deferred | Deferred | Belongs to that plan's own follow-up; this PR only creates the `.gitattributes` file that unblocks it. |

## Sharp Edges

- A merge driver that git cannot execute, or that exits non-zero, leaves **ours** content with the
  path marked `UU` and **writes no conflict markers of git's own** (M7, M8). This is why the driver
  writes its own sentinel on every failure path; without it the repo's staged-conflict-marker guard
  never fires and `merge-pr` §3.3's "read the file with conflict markers" leads straight to a wrong
  commit. Any runbook text must say "re-run the merge after fixing registration", never "resolve the
  markers" and never "take `--theirs`".
- The fixture repo must be initialised with `git init -b trunk`, not `main` — the commit-on-main
  guardrail blocks fixture commits, exactly as `gitleaks-merge-commit.test.sh` documents.
- Every `git` invocation in the fixture must run with `GIT_*` scrubbed. The 2026-09-04 erratum on
  `2026-04-03-lefthook-git-env-var-leak-breaks-tests.md` records 16 stray commits on a live branch and
  two worktree-index collapses from exactly this. Source `test-helpers.sh` for the exit-97 tripwire.
- lefthook globs use gobwas semantics: `**` requires at least one intermediate directory, which is why
  the existing stanza has never matched `knowledge-base/INDEX.md` itself (M17). Observe the fix with
  `lefthook run pre-commit`; do not reason about it.
- The hook layer in this repo was inert until 2026-09-03 (M19). No correctness property in this plan
  rests on a lefthook stanza for that reason.
- The ADR ordinal is a claim, not a reservation. Re-run the all-refs probe immediately before merge,
  and if it moves, sweep this plan, `tasks.md` and AC21 in the same edit.
- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text,
  or omits the threshold will fail `deepen-plan` Phase 4.6. It is filled above with threshold `none`
  and a reason.
