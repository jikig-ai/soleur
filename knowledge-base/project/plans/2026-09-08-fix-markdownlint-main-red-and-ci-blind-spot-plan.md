---
title: "markdown-lint: clear the red tree and give the linter a second home in CI"
date: 2026-09-08
slug: fix-markdownlint-main-red-and-ci-blind-spot
branch: feat-one-shot-7927-markdownlint-main-red
issue: 7927
closes: [7927, 7837, 7832, 2685]
lane: cross-domain
type: chore
priority: p2-medium
domain: engineering
brand_survival_threshold: none
requires_cpo_signoff: false
---

## Overview

The repository lints Markdown from exactly one place: a lefthook `pre-commit` command. No CI
job runs it. Pull requests land by squash merge, where lefthook never runs, so a red file
reaches the default branch whenever its pull request was merged without a local commit that
staged it. Nothing observes the accumulation.

The consequence is not cosmetic. The hook lints `{staged_files}`, and a merge commit stages
every file the merge brings in. A contributor who merges the default branch into a feature
branch locally is therefore blocked by errors in files they never opened.

This plan does two things. It clears the errors on the corpus the gate will cover, and it
gives the linter a second home in CI that reads the same rule file, the same scope file, and
the same pinned binary the hook reads — so the two cannot disagree about what is red.

Note on `lane:` — no `spec.md` exists for this branch, so `lane` defaulted to `cross-domain`
fail-closed. The domain sweep below found two genuinely relevant domains, so the default is
accurate rather than merely safe.

## Research Reconciliation — Issue Claims vs. Codebase

Every row was measured in this worktree on 2026-09-08 against `markdownlint-cli` 0.49.1 with
the repository's own `.markdownlint.json`.

| Claim (issue #7927) | Reality | Plan response |
|---|---|---|
| 49 errors across ~10 files | That is the subset a single merge staged. Across all 9,619 tracked `.md` the count is **32,356 errors in 3,818 files** | Scope is decided against the real corpus, not the merge sample |
| `work/SKILL.md` has MD038 ×9 + MD052 ×1 | **12 errors**, in two distinct classes, not one | Both classes handled separately, below |
| Escaped-backtick span at line 688 renders wrong | **Confirmed.** Anchor `against an UNTYPED client` — `` `.select(\`…\`)` ``. Sibling at anchor `` verify with `git log -1 --format=%B` `` | Root-cause fix, and it must precede the sweep — see Sharp Edge 1 |
| Three remaining MD038 are deliberate | **Four**, not three; anchors `` optional `bash ` prefix ``, `never single-space`, and two on the `Legal-doc edits have TWO independent mirror gates` line | Four sites, decided individually |
| `docs/legal/*` MD034 on three files | **Five** canonical files, plus `acceptable-use-policy.md` and `disclaimer.md`; and **five mirror files** carry the same 12 sites | Both surfaces edited identically |
| One legal heading carries a bare address | **Two.** `privacy-policy.md` §4.13 and `gdpr-policy.md` §3.10 | Both, on both surfaces |
| No `.markdownlint*` config assumed | **Both already exist.** `.markdownlint.json` disables MD013, MD024, MD026, MD029, MD033, MD036, MD040, MD041, MD056, MD060 and configures MD025. `.markdownlintignore` ignores `knowledge-base/marketing/distribution-content/` and `knowledge-base/INDEX.md` | Extended, not replaced |
| `markdownlint` absent from CI | Confirmed: `grep -rln markdownlint .github/workflows/` returns nothing across 77 workflows | Gate added |

## Research Insights

### Premise validation

`#7927` is OPEN and its diagnosis reproduces. Three sibling issues describe the same class
and are closed by this work: **#7837** (39 pre-existing errors blocking any commit that stages
the legal docs or `expenses.md`; its own suggested fix names a repo-wide CI run), **#7832**
(`knowledge-base/product/roadmap.md`, which a scheduled cron writes to — a red file there
wedges automation or pushes it toward `--no-verify`), **#2685** (MD055 in
`dhh-rails-style/SKILL.md`). **#7817** is *partially* addressed: its Part 2 (ten markdownlint
errors in `article-30-register.md`) is cleared here; its Part 1 (six bare
`**Special categories**` labels) is a content change and stays open.

`#7817` also records a prior decision this plan honours: *fix the register's errors rather than
adding it to `.markdownlintignore`*, because ignoring permanently blinds a counsel-attested
document. `knowledge-base/legal/` therefore stays in scope.

### Property list (what this must actually buy)

1. A contributor merging the default branch locally is never blocked by Markdown errors in a
   file they did not write.
2. A Markdown error that reaches the default branch is visible without a local commit.
3. The hook and CI cannot disagree about which files are linted, under which rules, by which
   binary version.
4. Files the gate does cover render correctly.

### Cut list

Mechanisms removed before or during design. Rows marked *(review)* were cut after a simplicity
panel held them against the property list and won.

| Mechanism | Property it would buy | What already buys it | Verdict |
|---|---|---|---|
| A second rule file for CI | 3 | `.markdownlint.json`, auto-loaded by both invocations of the same binary | Cut |
| A `push: main` canary workflow | 2 | The required pull-request check covers the merge path; the ruleset blocks direct pushes | Cut |
| An opt-out label on the new job | escape hatch | `.markdownlintignore` and inline `<!-- markdownlint-disable-line -->` are both reviewable in the diff, and no *required* context in `pr-quality-guards.yml` carries a label | Cut |
| Activating `stage_fixed: true` on the hook | 4 | Measured below — `--fix` corrupts prose in this corpus | Cut; the config is deleted with a comment saying why |
| An ADR recording the scope decision | 3 | *(review)* The question "why is this directory exempt?" is asked while reading `.markdownlintignore`, and the acceptance criteria already require that file to answer it in situ. An ADR sits one indirection further from the question and nothing forces it to track the ignore file | Cut |
| A preflight in the `bot-pr-with-synthetic-checks` composite action | 2, for bot pull requests | *(review)* Verified: `ALLOWED_PATHS` is exactly `knowledge-base/project/weakness-digest.md` and `knowledge-base/project/rule-metrics.json`. Under the scope below the first is excluded and the second is not Markdown, so the intersection with the swept set is empty and the synthetic green is sound by unreachability — the pattern `rule-body-lint` already uses | Cut |
| GitHub `::error::` annotation emission | legibility | *(review)* markdownlint's native `file:line:col rule detail` output is already actionable in the job log, and annotations were the sole reason the gate needed to sanitise attacker-influenced bytes out of markdownlint's `[Context: "…"]` field. A cosmetic feature that manufactured its own security requirement | Cut |
| A separate non-empty assertion on the swept set | anti-vacuity | *(review)* Subsumed by the count floor — `n < MIN_SWEPT_FILES` is true at `n = 0` for any floor of 1 or more | Cut |
| Two ignore entries (`plans/` and `specs/`) rather than one | 1 | *(review)* No stated property distinguishes `learnings/` and `brainstorms/` from `plans/` and `specs/`, and keeping them cost 2,676 swept files, 343 hand-fixed errors, and the whole composite-action deliverable | Cut down to one line |

### Measured facts

Baseline — `markdownlint-cli` 0.49.1, repository config, all git-tracked `.md`:

| Corpus | Files | Errors |
|---|---|---|
| All tracked `.md` | 9,619 | 32,356 across 3,818 files |
| `knowledge-base/project/` | 8,228 | 29,200 |
| **The effective scope** (tracked minus `.markdownlintignore`) | **1,344** | **3,156** |

The effective set is derived, not asserted:
`git ls-files -c -i --exclude-from=.markdownlintignore -- '*.md'` returns the excluded paths,
and subtracting them from `git ls-files '*.md'` leaves 1,344 across `knowledge-base` (689),
`plugins` (413), `.grok` (67), `.openhands` (63), `todos` (59), `apps` (12), `docs` (9),
`.claude`, `.gemini`, `scripts`, `tests`, `.github`, `infra`, and eleven repository-root files.
Verified against git 2.53.0. The subtraction must run under `LC_ALL=C` — `comm` rejects the
default-locale ordering that `git ls-files | sort` produces, and it reports the disorder on
stderr while still printing a plausible count.

`markdownlint --fix` converges after three passes, but **it is not safe to run unattended on
this corpus** (Sharp Edge 2). Under a content-safe pass — `--fix` with MD037, MD038, MD049 and
MD050 withheld — the effective scope converges to **438 residual errors across 143 files**:

| Rule | Count | Character |
|---|---|---|
| MD038 no-space-in-code | 105 | judgement per site: real defect vs. deliberate illustration |
| MD025 single-title | 93 | structural convention — disabled, see below |
| MD049 emphasis-style | 70 | mechanical, but unsafe to auto-fix where an underscore is part of an identifier |
| MD028 blank-line-inside-blockquote | 54 | manual |
| MD052 reference-links-images | 34 | **real rendering defects** — undefined link references |
| MD055 table-pipe-style | 28 | mechanical |
| MD037 no-space-in-emphasis | 24 | judgement per site; the fix deletes real spaces here |
| MD001 heading-increment | 23 | structural convention — disabled, see below |
| MD046, MD051 | 7 | manual |

After the rule decision below, the hand-fixed set is **322 errors across 87 files**,
concentrated in `knowledge-base` (236) and `plugins` (78).

### Tool-choice evidence (CLI verification gate)

- `.markdownlintignore` **is** honoured by `markdownlint-cli` even when explicit file paths are
  passed, not only globs. Verified 2026-09-08 against 0.49.1. This is what lets one scope file
  serve both the hook (`{staged_files}`) and CI (whole repository). It is a behavioural detail
  of a third-party CLI with no upstream contract — a second and stronger argument for the exact
  version pin than "a new release may add a rule".
- `git ls-files -c -i --exclude-from=<file> -- '*.md'` lists exactly the tracked paths an
  exclude file matches, trailing-slash directory patterns included. Verified against git 2.53.0.
- `markdownlint-cli2` **does not read `.markdownlintignore`.** Verified 2026-09-08 against
  cli2 0.23.2 (markdownlint 0.41.1): a file under an ignored directory was linted and reported.
  The two tools disagree about scope. Sibling issues #7832 and #7837 reproduce with cli2 while
  the hook uses cli — a third source of truth this plan closes by naming cli v1 canonical in
  the shared script. Two retired rule ids (`cq-always-run-npx-markdownlint-cli2-fix-on` and
  `cq-markdownlint-fix-target-specific-paths`, retired 2026-04-23 in #2865) reference cli2;
  `cq-rule-ids-are-immutable` forbids resurrecting either, and nothing in #2865 makes cli2 the
  deliberate choice.
- When every path passed to `markdownlint-cli` is filtered out by the ignore file, it prints
  its usage text and **exits 0**. Verified. A gate whose selector resolves to nothing passes
  silently — the vacuity hazard the guard contract is built against.
- `lint-workflow-install-sites.sh` does not classify `npx --yes` as an install step, and this
  design adds no `npm ci` to a workflow, so that guard is not engaged.

### Constraints discovered in the repository

- **`lint-infra-no-human-steps.py`** is a lefthook command globbed on
  `knowledge-base/project/{plans,specs}`. Measured: **208 of 5,542 tracked plan and spec files
  currently fail it, on 514 violations.** Any sweep that restages that corpus is hard-blocked
  by the repository's own hook, and would only land behind the same `LEFTHOOK_EXCLUDE` bypass
  this issue exists to remove.
- **`scripts/lint-orphan-test-suites.sh`** walks 410 tracked `*.test.sh` against six
  registration surfaces, fails on any orphan, and *also* fails on any suite covered by more
  than one surface unless it is in `DOUBLE_COVERED_ACK`. `scripts/*.test.sh` is **not** in
  `SUITE_GLOBS`, so registration must be one explicit `run_suite` line.
- **`.github/scripts/test/run-all.sh` is bash-only by contract.** Its header states it
  directly: `guard-script-fixture-tests` is required, runs on `merge_group`, and has no path
  filter, so it gates every pull request — its suites must not need external tooling or they
  red every pull request on a bare runner. A markdownlint suite needs node. This is why the
  guard's suite cannot live there.
- **Registering a required context touches five files, not two.**
  `scripts/ci-required-ruleset-canonical-required-status-checks.json` is the single source of
  truth (22 entries today); `tests/scripts/test-audit-ruleset-bypass.sh` asserts context-set
  equality against `infra/github/ruleset-ci-required.tf` and carries a **deliberate hardcoded
  literal** `22` whose own comment says *"Bumping it is the acknowledgement"*; and
  `plugins/soleur/test/required-checks-canonical-parity.test.sh` asserts both directions of
  containment between `scripts/required-checks.txt` and the canonical JSON. Both suites run
  under `scripts/test-all.sh`.
- **`scripts/required-checks.txt`** carries an auto-fabrication guard (#6049): the
  `bot-pr-with-synthetic-checks` action derives `CHECK_NAMES` from it and posts a green
  synthetic run for every name with no per-check review. A content-scoped gate must either be
  reproduced in the action's Phase-4 preflight or be sound by unreachability. Verified:
  `ALLOWED_PATHS` is exactly `knowledge-base/project/weakness-digest.md` and
  `knowledge-base/project/rule-metrics.json`; under the scope below the first is excluded and
  the second is not Markdown, so the intersection is empty. The file is CODEOWNERS-gated.
- **Required status checks** are applied by `apply-github-infra.yml` when a pull request
  touching `infra/github/*.tf` merges, and their `context` strings are public ABI that must
  equal the job `name:`. The merge queue on the default branch was **reverted 2026-06-30**, so
  required checks gate the pull request, not a queue.
  `strict_required_status_checks_policy = true`, so every pull request must be current with the
  default branch and will therefore carry the new workflow file.
- **The legal chain.** Every `docs/legal/*.md` is SHA-pinned. `terms-and-conditions` is pinned
  by `TC_DOCUMENT_SHA`, written to a WORM consent ledger; it is **not** affected here. The
  other eight are pinned in `apps/web-platform/lib/legal/legal-doc-shas.ts`, documented as
  drift-detection only. `scripts/lint-legal-mirror-drift-baseline.sh` is a ratchet over the
  canonical and mirror pair.

### Applicable institutional learnings

| Learning | Constraint it places here |
|---|---|
| `2026-03-21-lefthook-gobwas-glob-double-star.md` | lefthook's matcher makes a bare `*` cross a slash but `**` require an intermediate directory. The hook's `glob: "*.md"` works today, but it is a *second* scope source next to the script, so it is removed rather than tuned |
| `2026-09-04-a-10-of-10-mutation-score-and-ten-escapes-it-could-not-see.md` | Mutation rows perturb the guard; **escape** rows feed it a real violation it must catch. The contract carries both |
| `2026-05-11-test-all-exit-gate-self-validated-on-creating-pr.md` | The gate must be green on the pull request that creates it, by its own invocation |
| `2026-03-19-ci-squash-fallback-bypasses-merge-gates.md` | An advisory check does not survive squash-merge automation. The gate must be a required context |
| `2026-02-27-github-actions-sha-pinning-workflow.md` | Any action reference in the new job is pinned to a 40-character commit SHA with a version comment |
| `2026-08-10-a-guard-that-cannot-be-driven-red-is-vacuous-four-rounds-four-instances.md` | The guard's own dispatch needs a floor; a zero-check alone cannot separate "certified the repository" from "certified a corner of it" |

## Open Code-Review Overlap

Two of 64 open `code-review` issues name a file this plan edits.

- **#7942** — *Two mutation batteries in `plugins/soleur/test/` are named `*.mutation.sh` and
  run in no gate.* Touches `scripts/test-all.sh`. **Acknowledge.** Different concern, but it
  places one constraint here: the new suite is named `markdown-lint.test.sh`, never
  `*.mutation.sh`, so it is not a fresh instance of the same defect.
- **#3829** — *CI gate enforcing "new Sentry monitor type means `sentry-scrub.ts` must
  change".* Touches `pr-quality-guards.yml`. **Acknowledge.** Unrelated content; adding a job
  does not conflict with a future job.

## Scope Decision

A gate that sees only changed files reproduces the blind spot exactly: in the incident that
motivated the issue, **zero** of the 49 offenders were touched by the pull request that tripped
over them. The gate is therefore a **whole-repository sweep**.

Whole-repository over *what* is the real question, and it is settled by a measured fact:
`knowledge-base/project/{plans,specs}` holds 27,203 of the 32,356 errors, and **208 of those
files already fail `lint-infra-no-human-steps.py`** — so the commit that would restage them to
fix their Markdown is itself hard-blocked by the repository's own pre-commit hook. Fixing that
corpus is not a bigger version of this work; it is different work gated by a different linter.

The exclusion covers `knowledge-base/project/` **whole** — one ignore line. `learnings/` and
`brainstorms/` are not blocked by that linter and could be fixed, but no stated property
distinguishes them from `plans/` and `specs/`: property 1 is satisfied by exclusion just as
well as by fixing, and property 4 speaks only about files the gate covers. Keeping them would
cost 2,676 swept files and 343 hand-fixed errors, and — because `weakness-digest.md` lives
under `knowledge-base/project/` — it would also drag in a change to the bot-PR composite action
to earn a synthetic green that is otherwise sound by unreachability. The whole exclusion buys
the simpler design on every axis.

The exclusion is **part of the fix, not a concession**. Because the hook and CI read the same
`.markdownlintignore`, a directory excluded from CI is also excluded from the hook — so those
8,228 files can never block a local merge again either. Property 1 is satisfied for 100% of
tracked Markdown: by exclusion for the artifact corpus, by fix-and-gate for the 1,344 files
that remain.

**Recorded dissent.** The engineering advisory argued for keeping `learnings/` and
`brainstorms/` in scope, on the grounds that an excluded directory with a follow-up issue has
no forcing function and will rot. That is a real cost, and it is not one of the four
properties, so it is recorded as a tracked deferral with its measured figures rather than
folded in — see `## Deferrals`.

### Rule-set decision: MD025 and MD001 are disabled, every rendering rule is kept

Two of the rules dominating the residual are structural conventions rather than
rendering-correctness rules, and they account for **116 of the 438** errors in the effective
scope: MD025 (single-title, 93) and MD001 (heading-increment, 23).

Enforcing MD025 here is incoherent with the configuration that already exists.
`.markdownlint.json` disables **MD041** (first-line-heading), MD025's sibling — the corpus has
already declared that top-level heading structure is not enforced. Keeping MD025 while MD041 is
off asks documents to have *at most* one top-level heading while not requiring them to have one
at all.

So: add MD025 and MD001 to the disabled set, with a comment naming the count and the MD041
coherence argument. The manual set falls to **322 errors across 87 files**, and every remaining
fix is either a real defect or a genuine per-site judgement.

This narrowing is bounded and it is the only rule change in the pull request. **Every rule that
any of the four issues trips stays enabled** — MD038, MD052, MD034, MD032, MD012 — as does
every rule that governs rendering: MD022, MD031, MD028, MD037, MD046, MD051, MD055. A
relaxation reaching those would make the fix fake; this one does not touch them.

### Alternatives considered

| Alternative | Why rejected |
|---|---|
| Gate on changed files only | Reproduces the blind spot by construction — the measured offenders were untouched by the pull request they blocked |
| Fix all 32,356 errors, gate everything | The sweep restages 208 files that fail `lint-infra-no-human-steps.py`; landable only behind `LEFTHOOK_EXCLUDE`, which is the bypass this issue exists to remove |
| Add the artifact corpus to the ignore file and change nothing else | Clears the merge-blocking symptom for 86% of files but leaves the CI blind spot open — the class returns on the next squash merge, which is what produced all 49 |
| Disable the noisy rules repo-wide instead of fixing | MD032, MD031, MD022 and MD052 are rendering-correctness rules, and MD038 and MD052 are what the issue's own root cause trips. Disabling them makes the fix fake. The bounded exception, MD025 and MD001, is argued and counted above |
| Fix all 93 MD025 sites rather than disabling the rule | Hand edits to satisfy a convention the corpus does not hold, whose sibling MD041 is already disabled. Poor value against any of the four properties |
| Switch to `markdownlint-cli2` | Measured: cli2 does not read `.markdownlintignore`, so the single shared scope file is lost |
| Keep the version floating on `npx --yes` | A new release that adds a rule reddens every open pull request simultaneously with no diff anywhere — the one genuine fleet-wide-red ingress once content is gated |
| Put the gate's logic inline in the workflow `run:` block and skip the script | Logic inside a `run:` block cannot be driven red by any suite in this repository, so the anti-vacuity floor would itself be unguarded. `scripts/lint-infra-no-human-steps.py` is the house dual-invoker precedent and it is a script for the same reason |
| Host the guard suite in `.github/scripts/test/` | That runner is bash-only by contract because `guard-script-fixture-tests` gates every pull request on a bare runner, and a markdownlint suite needs node |

## Files to Create

| Path | Purpose |
|---|---|
| `scripts/markdown-lint.sh` | The sole invoker, roughly 40 lines. Asserts the working directory and the binary version, derives the file set, enforces the anti-vacuity floor and roots-set assertion, then runs `markdownlint` |
| `scripts/markdown-lint.test.sh` | Guard suite — mutation rows, escape rows, harness rows |

## Files to Edit

| Path | Change |
|---|---|
| `package.json` (root) | Add `markdownlint-cli` to `devDependencies` pinned exactly, no caret — the single version of record |
| `package-lock.json` (root) | Regenerated; gated by the existing `lockfile-sync` required check |
| `.markdownlint.json` | Disable MD025 and MD001, with a comment naming the count and the MD041 coherence argument. No other rule change |
| `.markdownlintignore` | Add `knowledge-base/project/` with a comment naming the blocking linter and the measured counts |
| `lefthook.yml` | `markdown-lint` calls the shared script; drop the now-redundant `glob:`; delete the inert `stage_fixed: true` and leave a comment recording why `--fix` must never be added here |
| `.github/workflows/pr-quality-guards.yml` | New job invoking the script in sweep mode, shaped exactly like `guard-script-fixture-tests` |
| `infra/github/ruleset-ci-required.tf` | Register the job name as a required `context`, with the unreachability note the `rule-body-lint` entry models |
| `scripts/ci-required-ruleset-canonical-required-status-checks.json` | Add the context — the source of truth both parity suites assert against |
| `scripts/required-checks.txt` | Add the context, with a note recording the empty-intersection derivation this green rests on |
| `tests/scripts/test-audit-ruleset-bypass.sh` | Bump the deliberate literal `22` to `23` — its own comment states that bumping it is the acknowledgement |
| `scripts/test-all.sh` | One explicit `run_suite` line registering `scripts/markdown-lint.test.sh` |
| `plugins/soleur/skills/work/SKILL.md` | Two escaped-backtick spans plus four deliberate-space sites |
| `docs/legal/{privacy-policy,gdpr-policy,data-protection-disclosure,acceptable-use-policy,disclaimer}.md` | 12 MD034 autolink conversions |
| `docs/legal/{individual,corporate}-cla.md` | MD032 blockquote blank lines, canonical only |
| `plugins/soleur/docs/pages/legal/{privacy-policy,gdpr-policy,data-protection-disclosure,acceptable-use-policy,disclaimer}.md` | The same 12 conversions, byte-identically |
| `apps/web-platform/lib/legal/legal-doc-shas.ts` | Re-pin 7 entries |
| `apps/web-platform/infra/sentry/README.md` | MD012 |
| `knowledge-base/legal/article-30-register.md` | #7817 Part 2 — 10 errors |
| `knowledge-base/product/roadmap.md` | #7832 — 5 errors, hand-fixed (Sharp Edge 2) |
| `plugins/soleur/skills/dhh-rails-style/SKILL.md` | #2685 — MD055 |
| Up to 1,344 tracked `.md` in scope | Content-safe `--fix` sweep, in its own commit |

## Implementation Phases

Phase order is load-bearing. Phase 1 must precede Phase 4 or the sweep corrupts
`work/SKILL.md` (Sharp Edge 1). Phase 2 must precede Phase 3 or the guard has nothing to run.

### Phase 1 — Root cause, before anything mechanical

1. In `plugins/soleur/skills/work/SKILL.md`, replace the two backslash-escaped code spans with
   a longer delimiter run and no backslashes. Locate by content anchor, never line number
   (`cq-cite-content-anchor-not-line-number`): `against an UNTYPED client`, and
   `` verify with `git log -1 --format=%B` ``. Both anchors were confirmed unique in the file.
   The verified idiom — probed against 0.49.1 — is an outer double-backtick run with padding
   spaces and real inner backticks; the single-tick-plus-backslash form does not lint clean,
   and neither does a padded single-tick span nor a bare double-tick span. This plan file uses
   the same idiom for the same reason, and was checked against the gate before commit.
2. Decide the four remaining MD038 sites individually. They render **correctly** today — the
   trailing space is the thing being illustrated — so the fix is an inline
   `<!-- markdownlint-disable-line MD038 -->` or the outer-delimiter idiom, never deleting the
   space. Anchors: `` optional `bash ` prefix ``, `never single-space`, and two on the
   `Legal-doc edits have TWO independent mirror gates` line.
3. Confirm the file is clean by the gate's own invocation before moving on.

### Phase 2 — The single invoker

Write `scripts/markdown-lint.sh`. It stays thin; each requirement closes a measured hole rather
than adding a feature.

- **Working-directory assertion.** `.markdownlintignore` and `.markdownlint.json` are resolved
  relative to the process working directory. Both call sites run at the repository root by
  construction, so the script asserts that rather than deriving a root — and fails loudly with
  the resolved path if either config file is absent. Silently losing the ignore file turns a
  1,344-file sweep into a 3,818-error one.
- **Version assertion, not version resolution.** The pinned version lives in root
  `package.json` and nowhere else. The script asserts that `markdownlint --version` equals it,
  and **fails loudly if the binary is missing** — no `npx --yes` network fallback, which would
  re-open property 3 for exactly the fresh-clone case it is meant to close, and no stale local
  binary silently surviving a pin bump.
- **Two modes.** `--repo-sweep` — the house name, per `lint-encryption-posture.py` — derives
  the set as tracked `*.md` minus
  `git ls-files -c -i --exclude-from=.markdownlintignore -- '*.md'`, under `LC_ALL=C`. Passing
  explicit paths filters those through the same exclusion; this is the hook's mode, and
  resolving to zero files there is legitimate and exits 0 with a printed reason.
- **Anti-vacuity, sweep mode only — two assertions, both with precedent.** A hand-ratcheted
  absolute count floor carried as `MIN_SWEPT_FILES=<n>  # <n> against <m> tracked, measured
  <date>`, following `MIN_TRACKED_SUITES=320` in `lint-orphan-test-suites.sh`; and an
  **expected-roots set** assertion following `EXPECTED_SUITE_ROOTS` in the same file, whose
  comment states why a floor alone is insufficient: *"A COUNT cannot see a narrowing that stays
  above the floor, and it cannot see a SUBSTITUTION at all."* Size the floor's slack
  deliberately — that file also records that *"Slack in a floor is not safety margin, it is
  narrowing budget."*
- **Legible failure.** markdownlint's native `file:line:col rule detail` output is already
  actionable, so the script adds only a static remediation block on non-zero exit: the local
  reproduction command, the content-safe auto-fix command, and the paths of the rule file and
  the scope file. Static text, so there is no sanitisation surface.

### Phase 3 — The guard's own suite

Write `scripts/markdown-lint.test.sh` implementing the `## Guard Contract`, and register it
with **one** explicit `run_suite` line in `scripts/test-all.sh`. Do not add a workflow step as
well: `scripts/*.test.sh` is not in `SUITE_GLOBS`, so `run_suite` is surface 1 and a workflow
`run:` is surface 5, and carrying both trips the orphan linter's double-coverage error. The
suite cannot live under `.github/scripts/test/`, whose runner is bash-only by contract.

### Phase 4 — The content-safe sweep

1. Apply the rule decision to `.markdownlint.json` first — disabling MD025 and MD001 removes
   116 residual errors before a single hand edit.
2. Run `--fix` with **MD037, MD038, MD049 and MD050 withheld**, over the in-scope set, to
   convergence (three passes). Those four are the rules whose fixes alter prose bytes; the rest
   only add or remove whitespace and blank lines. Commit alone, so a reviewer can verify the
   whole diff by re-running the tool.
3. Resolve the four withheld rules by hand, per site — 24 MD037, 105 MD038 and 70 MD049 in the
   effective scope, concentrated in 52 files.
4. Resolve the remaining residual by hand: **322 errors across 87 files**, 236 under
   `knowledge-base` and 78 under `plugins`. MD052 (34) are genuine broken reference links and
   are fixed, never suppressed.
5. Fold in the sibling issues explicitly: `roadmap.md` (#7832), `article-30-register.md`
   (#7817 Part 2), `dhh-rails-style/SKILL.md` (#2685), `sentry/README.md`.
6. **Before hand-editing anything under `.grok/`, `.openhands/` or `.gemini/`** (130 in-scope
   files), determine whether it is generated —
   `plugins/soleur/scripts/sync-grok-agent-compat.ts` exists and is the first place to look. If
   a file is generated, fix its source and regenerate; hand-editing a generated file is churn
   at best and drift at worst.

### Phase 5 — The legal corpus, reviewed by hand

The legal advisory (2026-09-08) is on the record and returns **discharged** for a change
limited to what follows. Do not let this phase ride in the Phase 4 sweep.

1. Convert all **12** bare addresses to CommonMark autolinks — `ops@soleur.ai` becomes
   `<ops@soleur.ai>` — on **both** the canonical and the mirror surface, identically. The
   rendered visible text is byte-identical; the address merely becomes actionable. This is a
   presentation-layer change, and it converges the corpus onto its own prevailing house style:
   the canonical files already carry 19 to 22 autolinked addresses each against 1 to 4 bare
   ones.
2. Two sites are section headings — `privacy-policy.md` §4.13 and `gdpr-policy.md` §3.10.
   Verified safe: the published site registers no anchor plugin, so its headings carry no `id`
   at all; the GitHub slug derives from rendered text and is unchanged; and a sweep of
   `knowledge-base/`, `docs/`, `apps/` and `plugins/` for anchor-form citations of either
   document returns zero — every citation is by section number.
3. **Four sites sit on `**Last Updated:**` lines** — `privacy-policy.md` line 11 twice,
   `gdpr-policy.md` line 13, `data-protection-disclosure.md` line 12. Convert them, but change
   **no wording** on those lines: no new amendment note, no date edit, no version bump, no
   re-consent event. Asserting that a notice changed when its wording did not is worse than
   silence. These four are also the drift-ratchet blocker — Sharp Edge 3.
4. MD032 on the two CLA documents is **canonical only** — both mirrors already carry the
   blockquote blank line, so the canonical-only fix *reduces* existing drift.
5. Re-pin 7 entries in `apps/web-platform/lib/legal/legal-doc-shas.ts`. `TC_DOCUMENT_SHA` is
   untouched; neither `terms-and-conditions` nor `cookie-policy` carries an error.
6. Re-run `scripts/lint-legal-mirror-drift-baseline.sh`,
   `scripts/lint-legal-scope-block-placement.sh` and
   `apps/web-platform/scripts/check-tc-document-sha.sh`.

### Phase 6 — CI wiring

1. Add the job to `.github/workflows/pr-quality-guards.yml`, shaped exactly like
   `guard-script-fixture-tests`: **no `if:` gate and no opt-out label**. A required context
   omitted on an event leaves pull requests wedged at "Expected — Waiting". Pin every action
   reference to a 40-character commit SHA with a version comment.
2. Register the context across all four registration files in one commit — the ruleset
   Terraform, the canonical JSON, `scripts/required-checks.txt`, and the `22` to `23` literal in
   `tests/scripts/test-audit-ruleset-bypass.sh`. Two suites assert set equality and both
   directions of containment across these; editing fewer than all four fails
   `scripts/test-all.sh`.
3. In the `required-checks.txt` entry and the Terraform comment, record the derivation the
   synthetic green rests on: `ALLOWED_PATHS` is `knowledge-base/project/weakness-digest.md` and
   `knowledge-base/project/rule-metrics.json`; the first is excluded by `.markdownlintignore`
   and the second is not Markdown, so the intersection with the swept set is empty and the
   green is sound by unreachability, as `rule-body-lint`'s is. State the intersection the note
   depends on, not just the conclusion — the action's own comment warns that reachability can
   widen without anyone touching `ALLOWED_PATHS`.
4. The merge applies the ruleset through `apply-github-infra.yml`; nothing further is needed
   after merge.

### Phase 7 — Prove it can fail

Execute every row of the `## Guard Contract` against the built gate and record the observed
result per row. A guard that has never been driven red is not known to work.

## Guard Contract

### Guard 1 — `scripts/markdown-lint.sh` in `--repo-sweep` mode

**Property.** Every tracked Markdown file not named by `.markdownlintignore` satisfies
`.markdownlint.json` at the pinned binary version, and this is asserted without any local
commit.

**Assembly.** The chokepoint is `scripts/markdown-lint.sh` — the only place that resolves a
markdownlint binary, a rule file, or a file set. There are exactly two call sites: the
`markdown-lint` command in `lefthook.yml` and the new job in `pr-quality-guards.yml`. The set
is structural, not enumerated: any future caller that invokes the binary directly re-opens the
drift this guard closes. Detecting that is a **negative** assertion — a grep for a markdownlint
binary token across `lefthook.yml`, `.github/**` and `scripts/**`, excluding the script itself
— never a count of call sites, which stays green when a direct invoker is *added alongside* the
script and goes red on a legitimate third caller.

**Mutation matrix.**

| # | Edit | Must go RED because |
|---|---|---|
| M1 | Restore the escaped-backtick span at anchor `against an UNTYPED client` in `work/SKILL.md` | **Escape row.** The originating defect must be catchable |
| M2 | Add a red file in a *different* top-level root than M1's, untouched by the pull request | **Escape row**, and the second-member row: proves the sweep neither stops at the first file nor sees only changed files. The row that distinguishes this design from the rejected changed-files gate |
| M3 | Add `*.md` to `.markdownlintignore` | **Dispatch row.** Sweep mode must fail on the floor, not pass on an empty set. The measured exit-0-on-empty hazard |
| M4 | Narrow `.markdownlintignore` to drop one whole top-level root while staying above the floor | Must fail the expected-roots set assertion. A count cannot see a narrowing that stays above the floor, nor a substitution at all |
| M5 | Invoke the sweep from a subdirectory | Must fail loudly on the working-directory assertion rather than silently losing `.markdownlintignore` and reporting on the whole tree |
| M6 | Bump the pin in `package.json` without reinstalling | Must fail the version assertion. Scoped to the script's own assertion — the lockfile arm belongs to `lockfile-sync` and is not this suite's to execute |
| M7 | Add a direct `markdownlint` invocation to `lefthook.yml` alongside the script | Must fail the negative call-site assertion — a second invoker is the drift defect returning |

**Harness rows.**

| # | Edit to the SUITE | Expected |
|---|---|---|
| H1 | Replace `scripts/markdown-lint.sh` with `exit 0` | Suite RED. A suite satisfiable by a no-op asserts nothing |
| H2 | Delete the suite's red fixtures | Suite RED on "zero cases ran". A tally of `0 passed, 0 failed` must not exit 0 |
| H3 | Feed the guard a file that is unusual but legal under this configuration — a 300-character line (MD013 off), inline HTML (MD033 off), an unlabelled fence (MD040 off), no top-level heading (MD041 off), two top-level headings (MD025 off) | **Must PASS.** A guard that rejects everything is as useless as one that rejects nothing, and only a must-pass row detects it. This row also asserts the disabled-rule set is actually loaded |

M1 and M2 are **escape** tests, not mutation tests: they feed the guard a real violation it must
catch, which is the arm a mutation-only battery cannot see
(`2026-09-04-a-10-of-10-mutation-score-and-ten-escapes-it-could-not-see.md`).

## Observability

```yaml
liveness_signal:
  what: "The required check reports a conclusion on every pull request"
  cadence: "Every pull request event, and every push to a pull request branch"
  alert_target: "The pull request's own required-checks panel; a missing conclusion blocks merge rather than passing silently"
  configured_in: ".github/workflows/pr-quality-guards.yml and infra/github/ruleset-ci-required.tf"
error_reporting:
  destination: "markdownlint's native file:line:col output in the job log, followed by a static remediation block naming the reproduction and fix commands"
  fail_loud: "Non-zero exit; no advisory or warn-only arm exists in either mode"
failure_modes:
  - mode: "A Markdown error reaches the covered corpus"
    detection: "The sweep reports it with file, line, column and rule id"
    alert_route: "Required check fails; merge is blocked"
  - mode: "The scope file is widened so the sweep covers nothing meaningful"
    detection: "Count floor in sweep mode (matrix row M3)"
    alert_route: "Required check fails with the resolved count and the floor in the message"
  - mode: "The scope file is narrowed to drop a whole area while staying above the floor"
    detection: "Expected-roots set assertion (matrix row M4)"
    alert_route: "Required check fails naming the missing root"
  - mode: "The sweep runs outside the repository root and loses its config"
    detection: "Working-directory assertion plus existence checks on both config files (matrix row M5)"
    alert_route: "Required check fails naming the resolved path and the missing file"
  - mode: "The installed binary drifts from the pinned version"
    detection: "Version assertion in the script (matrix row M6), and lockfile-sync for the manifest side"
    alert_route: "Required check fails naming both versions"
  - mode: "A second invoker appears and diverges from the shared configuration"
    detection: "Negative call-site assertion in scripts/markdown-lint.test.sh (matrix row M7)"
    alert_route: "The suite fails inside scripts/test-all.sh"
logs:
  where: "GitHub Actions job log for the new job"
  retention: "GitHub Actions default retention"
discoverability_test:
  command: "bash scripts/markdown-lint.sh --repo-sweep"
  expected_output: "exit 0, with a line reporting how many files were swept and that the floor and roots-set assertions held"
```

## User-Brand Impact

**If this lands broken, the user experiences:** a published legal page on `soleur.ai/legal/…`
whose contact address renders differently than intended, or — if the sweep is run unattended —
a policy sentence with a space deleted between two words. Both are visible on a page a
prospective customer reads before trusting the product.

**If this leaks, the user's data is exposed via:** no new exposure vector. This change adds no
data flow, no store, no endpoint and no credential. The only content it touches that a user can
see is already public.

**Brand-survival threshold:** none — reason: the change is confined to Markdown formatting, a
lint invocation and a CI job; no user data, workflow or money is reachable from it. The
sensitive-path consideration is `docs/legal/**`, handled by the hand-reviewed Phase 5 with a
legal advisory on the record and no wording change.

## Domain Review

**Domains relevant:** Engineering, Legal

### Engineering

**Status:** reviewed
**Assessment:** Three panels ran — an engineering advisory, a correctness review and a
simplicity review — and every finding was verified against the repository before adoption
rather than taken on assertion. Adopted: the version of record belongs in root `package.json`
under ADR-191, not in the script; `--all` is renamed `--repo-sweep` to match
`lint-encryption-posture.py`; the suite registers on exactly one surface; the anti-vacuity
design is a count floor plus an expected-roots **set**, which is what the cited precedent
actually carries, so the separate non-empty check is subsumed; the annotation emitter and its
sanitisation requirement are cut; the composite-action preflight is cut in favour of a verified
empty-intersection argument; the scope ADR is cut because the ignore file answers the question
at the point it is asked; and registering the required context touches **five** files, not two
— a gap the first draft would have discovered only at the test gate. Rejected with reasons:
cutting the shared script entirely (logic inside a workflow `run:` block cannot be driven red by
any suite here, and `lint-infra-no-human-steps.py` is the house dual-invoker precedent), and
hosting the guard suite under `.github/scripts/test/` (that runner is bash-only by contract and
a markdownlint suite needs node).

### Legal

**Status:** reviewed
**Assessment:** The legal advisory (2026-09-08) returns a provisional **discharged** for a
change limited to 12 autolink conversions on both surfaces, 2 canonical-only blockquote fixes,
7 SHA re-pins, no `**Last Updated:**` wording edit, and no rule-configuration change beyond the
MD025 and MD001 disable. The conversion is presentation-layer under Art. 13(1)(a)-(b) and
Art. 12(1): the rendered text is unchanged and the address becomes actionable, which advances
rather than disturbs "intelligible and easily accessible form". No version bump, amendment
notice or re-consent event. The advisory surfaced three items the plan had not: a **second**
affected heading in `gdpr-policy.md` §3.10; the drift-ratchet blocker recorded as Sharp Edge 3;
and a CLA evidence-ledger discontinuity recorded as Sharp Edge 4. It also argues against the
lint-exception route — suppressing MD034 across `docs/legal/**` would freeze an internal
inconsistency inside documents whose own prevailing convention is already the autolink, and
disarm the rule for the case it exists to catch.

### Product/UX Gate

Not applicable. No path in `## Files to Create` or `## Files to Edit` matches a UI surface — no
`components/**/*.tsx`, no `app/**/page.tsx`, no `app/**/layout.tsx`.

## Architecture Decision (ADR/C4)

**No ADR.** The scope decision was assessed against the gate and cut: the question "why is this
directory exempt?" is asked while reading `.markdownlintignore`, which the acceptance criteria
require to answer it in situ with the blocking linter and the measured counts named. An ADR sits
one indirection further from the question and nothing forces it to track the ignore file. The
bot-PR unreachability derivation is recorded where its consumers read it — the
`required-checks.txt` entry and the Terraform comment — following the shape `rule-body-lint`
already uses in `infra/github/ruleset-ci-required.tf`.

**No C4 impact.** Enumerated against all three model files —
`knowledge-base/engineering/architecture/diagrams/{model.c4,views.c4,spec.c4}` — under the
completeness rubric rather than a keyword grep:

- **External human actors:** none added or changed. No new correspondent, reviewer or
  recipient; the contributor and operator actors already modelled are unchanged.
- **External systems and vendors:** none added. No new webhook, outbound API or third-party
  store. The npm registry is reached only through the existing lockfile-of-record path already
  covered by the `lockfile-sync` relationship.
- **Containers and data stores:** none touched. No new persistent store, queue or cache.
- **Actor-to-surface access relationships:** unchanged. The new job runs inside the existing
  GitHub Actions container on existing edges; it emits no Sentry heartbeat and creates no cron
  monitor.
- **Derived cardinalities:** the counts `model.c4` embeds on the `github -> sentry` edge are
  about sentry-heartbeat emitters and cron monitors, and this change adds neither.
  `bash plugins/soleur/test/c4-count-parity.test.sh` was run on 2026-09-08 against the
  unmodified tree and exits 0; the change moves none of its inputs.

## Acceptance Criteria

### Pre-merge

1. `bash scripts/markdown-lint.sh --repo-sweep` exits 0 from the repository root. The criterion
   is the gate's **own** invocation, never a hand-enumerated reconstruction of its input set.
2. The same command reports a swept-file count at or above the committed floor and names every
   expected top-level root as present.
3. `plugins/soleur/skills/work/SKILL.md` is clean by that same invocation, and neither
   surviving code span contains a backslash before a backtick.
4. In `lefthook.yml`, the `markdown-lint` command's `run:` names `scripts/markdown-lint.sh`
   (positive assertion), **and** no markdownlint binary token appears anywhere in the file
   (negative assertion). Both are required: a single count cannot express "routes through the
   script and nowhere else", and a `grep -c` that matches nothing exits 1. `stage_fixed` is
   absent from that command and a comment records why `--fix` must not be added.
5. `.markdownlintignore` contains exactly one new entry, carrying a comment that names the
   blocking linter and the measured file and error counts.
6. The new job's `name:` in `pr-quality-guards.yml` equals the `context` string in
   `infra/github/ruleset-ci-required.tf` and in
   `scripts/ci-required-ruleset-canonical-required-status-checks.json`, byte-for-byte; the job
   carries no `if:` and no opt-out label; every action reference is a 40-character SHA with a
   version comment.
7. If the new context appears in `scripts/required-checks.txt`, then either
   `.github/actions/bot-pr-with-synthetic-checks/action.yml` runs the sweep in its Phase-4
   preflight, or the entry carries the empty-intersection derivation naming both allowlist
   members and why each is outside the swept set. This plan takes the second arm. Stated as an
   implication because both land in one merge commit, and a diff shows co-presence, not
   sequence.
8. `bash tests/scripts/test-audit-ruleset-bypass.sh` and
   `bash plugins/soleur/test/required-checks-canonical-parity.test.sh` both exit 0, with the
   deliberate literal bumped to 23.
9. `bash scripts/lint-orphan-test-suites.sh` exits 0 and reports zero orphans, with the new
   suite covered by exactly one registration surface.
10. `bash scripts/markdown-lint.test.sh` exits 0, and its output enumerates one result line per
    contract row — M1 through M7, H1 through H3 — with H3 recorded as a pass and the rest as
    expected-red-observed-red.
11. `bash apps/web-platform/scripts/check-tc-document-sha.sh` exits 0 with 7 re-pinned entries
    and `TC_DOCUMENT_SHA` unchanged from the base branch.
12. `bash scripts/lint-legal-mirror-drift-baseline.sh` and
    `bash scripts/lint-legal-scope-block-placement.sh` exit 0.
13. In the legal diff, the only change to any `**Last Updated:**` line is the autolink
    bracketing of an address already present on it — no wording, date or amendment-note change.
    Every canonical autolink has an identical mirror counterpart.
14. The only `.markdownlint.json` change in the pull request is the MD025 and MD001 disable;
    MD038, MD052, MD034, MD032, MD012, MD022, MD031, MD028, MD037, MD046, MD051 and MD055 all
    remain enabled.
15. `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` exits 0.
16. `bash scripts/test-all.sh` exits 0.
17. The pull request body carries `Closes #7927`, `Closes #7837`, `Closes #7832`,
    `Closes #2685`, a `Ref #7817` noting that only its Part 2 is addressed, and the CLA
    evidence-ledger note from Sharp Edge 4.
18. `bash plugins/soleur/test/c4-count-parity.test.sh` exits 0.

### Post-merge (automated, no human step)

19. `apply-github-infra.yml` fires on the merge and the ruleset carries the new required
    context. That workflow run is the verification.

## Risks & Sharp Edges

1. **The root-cause fix must precede the sweep, or the sweep corrupts prose.** Measured:
   because the escaped-backtick span mis-pairs every later delimiter on its line, `--fix`
   "resolves" the resulting MD038s by **deleting real spaces between prose words** —
   `` the `sed` `` becomes `` the`sed` ``, and `` no `auth.users`-only `` becomes
   `` no`auth.users`-only ``, seven times on one line. Phase 1 before Phase 4 is not a
   preference.
2. **`markdownlint --fix` is not safe unattended on this corpus.** Measured independently on
   three files and independently reported in #7832: on `roadmap.md` it turns
   `All-in burn **$643.24/mo**` into `All-in burn**$643.24/mo**`; MD049's fix rewrites an
   underscore to an asterisk and will corrupt an identifier whose underscores markdownlint
   mis-parses as emphasis. MD037, MD038, MD049 and MD050 are withheld from every automated pass.
3. **Four legal MD034 sites sit on already-drifting lines.** `privacy-policy.md` line 11
   (twice), `gdpr-policy.md` line 13 and `data-protection-disclosure.md` line 12 are the
   `**Last Updated:**` correction-history lines, where the mirror deliberately carries a
   condensed history. `lint-legal-mirror-drift-baseline.sh` fails an in-place edit of an
   already-drifting line whether or not both surfaces are edited. The script's own documented
   escape — `SOLEUR_LEGAL_DRIFT_ACCEPT` with a reason naming this issue, the fact that the
   rendered text is byte-identical, and the pending resync — is the right instrument. The other
   8 sites are paired and drift-neutral.
4. **The CLA edit creates a boundary in the signature evidence ledger.** Each contributor
   record binds `cla_doc.content_sha256`, computed at signature time. Signatures after this
   merge record a different hash than signatures before it. Nothing breaks and historical
   records correctly preserve what was signed, but the pull request body must note it so a
   future roster audit does not read a whitespace fix as an unexplained instrument change.
5. **The bot-PR green rests on an intersection that can widen without anyone touching
   `ALLOWED_PATHS`.** The action's own comment warns of exactly this — a generator's output
   format change can move the other input silently. The `required-checks.txt` note must state
   the intersection it depends on, not merely assert that the green is safe, so a future
   `ALLOWED_PATHS` edit has something to re-derive against.
6. **The gate is fail-closed across the covered corpus**, so a newly red file blocks every open
   pull request until it is fixed. That is intended and is what makes property 2 real. The
   genuine fleet-wide ingress is not content — content cannot pass the gate — but an unpinned
   binary picking up a release that adds a rule. Pinning removes it and turns new-rule breakage
   into a reviewable Dependabot pull request.
7. **Do not substitute `markdownlint-cli2`.** Measured: it does not read `.markdownlintignore`,
   so swapping it silently widens scope to the excluded corpus and reddens the tree.
8. **`MIN_SWEPT_FILES` is a frozen count in a tree other pull requests are changing.** That is
   defensible — the cited precedent's floor is too — but the slack must be sized deliberately
   and the comment must carry the measured pair of numbers. It is a guard constant, not an
   acceptance criterion, which is why Sharp Edge 9 does not forbid it.
9. **Do not hardcode counts in acceptance criteria.** The measured figures here are sizing
   input. Every criterion asserts an exit code or a structural property, because a count frozen
   at plan time drifts against a tree other pull requests are changing
   (`cq-ac-must-not-depend-on-concurrent-sessions`).
10. **The sweep touches Markdown under `plugins/soleur/`**, triggering the
    `plugin-component-test` hook and therefore a full `scripts/test-all.sh` run on that commit.
    Expect it to be slow; it is not a failure.

## Deferrals

| Deferred | Reason | Re-evaluation trigger | Tracking |
|---|---|---|---|
| `knowledge-base/project/{plans,specs}` Markdown quality — 27,203 errors | The commit that would restage them is hard-blocked by `lint-infra-no-human-steps.py` on 208 files; different work, different linter | When those 208 files are remediated, or when that linter grows a corpus-wide waiver mechanism | File at `/work` time, `type/chore` plus `domain/engineering`, with the measured counts in the body |
| Widening scope to `knowledge-base/project/{learnings,brainstorms}` — 2,676 files, **343** residual errors under the content-safe pass (MD025 190, MD038 125, MD001 20, MD049 6, MD051 1, MD037 1) | No stated property distinguishes them from plans and specs, and including them drags in a composite-action change to earn a green that is otherwise sound by unreachability. The engineering advisory dissented; the dissent is recorded, not overruled silently | When the artifact-corpus deferral above is taken up, or if a rendering defect in a learning is actually observed | File at `/work` time with these measured figures and the dissent quoted, so the next decision is informed |
| #7817 Part 1 — six bare `**Special categories**` row labels | A content change to a counsel-attested register, outside this plan's markup-only scope | Independent of this work | #7817 stays open; comment recording that Part 2 is cleared |
| The canonical and mirror amendment-history divergence in three legal documents | Pre-existing, self-disclosed on the published page, and the reason Sharp Edge 3 needs its escape | The #7465 resync | Confirm a tracker exists at `/work` time; file one if not |
