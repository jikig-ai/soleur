---
title: "fix(ci): Wave B - convert test-harness early-exit grep readers and join the producer side (Ref #9217)"
date: 2026-10-07
slug: fix-grep-q-wave-b-test-harness-and-producer-join
branch: feat-one-shot-grep-q-wave-b-test-harness
issue: 9217
lane: cross-domain
type: fix
priority: p3-low
domain: engineering
requires_cpo_signoff: false
brand_survival_threshold: aggregate pattern
---

# fix(ci): Wave B - convert test-harness early-exit grep readers and join the producer side (Ref #9217)

Spec lacks valid lane: no spec.md exists for this branch, so lane defaulted to cross-domain (TR2 fail-closed).

## Overview

Item B of the grep -q pipe-guard series (tracker #9217; also #7376, #6601, #7005). The derived sweep in
`.claude/hooks/grep-q-pipe-guard.test.sh` still defers **804 test-harness sites in 194 files** behind ten `<=`
rows, plus 23 production sites in six file-exact rows (wave A3, not this item). This plan:

1. Takes the census from the guard itself (not `git grep`) and groups it by deferral row and subsystem.
2. Splits the work into seven PRs. **This branch and draft PR #9720 is slice S1** (107 sites in 26 in-scope files, 24 of them edited, the
   shared instrument, and the ledger edit). S2 to S7 are listed in the Slice Register as later PRs of the same
   series, not as new issues.
3. Converts each site to `grep -c ... >/dev/null`, the form with the same exit status as `grep -q`, with a small
   committed codemod whose `verify` mode proves a slice's diff is only that transform (plus an enumerated hand
   queue), because 804 hand edits cannot be reviewed line by line and a sed one-liner cannot tell a pipe from a
   quoted fixture.
4. Lowers every touched ceiling to the measured count with slack 0, deleting rows that reach zero.
5. Designs the **producer-side join** (S7): the stub that never reads the stdin a production `printf | verb`
   feeds it, and the test-side `printf | local_function` form that produced the live red on #9554's own CI.

Pass 1 (`a0359450dd`, PR #9632) and Pass 2 (`7bb0fbffc2`, PR #9708) are on `origin/main` and are not redone.
No ADR or C4 change: nothing here moves an ownership, tenancy, substrate or trust boundary; the guard is
test hygiene and its ledger design is recorded in the guard header.

**Honest scope.** 795 of the 804 sites sit in files that set `pipefail`, so the shape is live, but almost none
is a flake today: a small `printf "$v" | grep -q` only races when the writer is unfinished at the reader's exit
(measured on a 3-line `git log` and a few-KB `echo`, so size is not a bound). What this series buys is that the
ledger reaches its residual and a new instance cannot hide in a deferred row. The producer-side join is the one
item aimed at a defect that has actually turned a CI check red.

## Research Reconciliation: brief and trackers vs measured reality

| Brief or tracker claim | Reality (command or file) | Plan response |
| --- | --- | --- |
| "~800 hits, test-shaped ceilings" | 804 = 91 + 181 + 140 + 66 + 180 + 9 + 128 + 6 + 1 + 2 over 194 files (`bash .claude/hooks/grep-q-pipe-guard.test.sh`, DEFERRED lines, 2.2 s) | Slice by deferral row; the sums are the baseline of every slice's ledger edit |
| "flag transform -q<flags> -> -<flags>" | 787 sites carry a `-q` cluster; **17 carry `-m`** (output-bearing, not quiet) and cannot take `-c`; a cluster like `-eq` is `-e` with pattern `q`, not `-q` | Codemod parses the cluster left to right, stops at an operand-taking letter, and routes `-m` and operand-`q` to the hand queue |
| "rule out unbounded producers first" | Screened all 804 lines and the 18 continuation lines for `yes`, `tail -f`, `journalctl`, `docker logs`, `nc`, `while true`, `/dev/zero`, `timeout`, `sleep` as a producer: **0 hazards** (one hit is a pattern that merely contains `while :;`) | Phase 0 re-runs the screen per slice and records the command; the codemod refuses a line whose producer text matches the unbounded list |
| "test-harness files are mostly stubs and assertion helpers" | About 500 of 804 are `echo`/`printf "$v" \| grep -q` assertion lines; about 77 read a file (`grep -v '^#' "$F" \| grep -q`, the source-text-pin shape that flaked `gen-github-egress-cidr.test.sh:779`); about 125 are a command or function producer; stubs are a small minority | Order commits by live risk inside a slice: file-reading producers first, then command and function producers, then echo/printf |
| "decide per-site whether a conversion is behavior-preserving and whether a row can observe it" | For the mechanical class the transform changes one flag letter and inserts one redirect; everything else is byte-identical, which `verify` proves, so a per-site row would be a test of the test. Rows are owed only where a line is hand-edited | Rows for hand-queue entries only (S1 has four); the codemod's own selftest carries the discrimination rows (drop `-x`, drop `-F`, drop `>/dev/null`, invert `!`) |
| "umbrella #9482" | #9482 is the merge-queue/CodeQL decision-challenge; its relevant comment (2026-10-05) is the ejection analysis that credits #9525 | Comment there only when a slice changes an ejection-class fact (the join PR); otherwise tracker #9217 only |
| "28 production pipes into stubbable verbs" (2026-10-05) | 33 candidate lines by the census regex in production roots (one is a lint fixture); **plus 103 test-side lines** piping `printf`/`echo` into a function defined in the same file, 24 files, which is the form behind the live red | Join has two arms: production-to-stub (guard-pinned) and test-side function consumers (measured, confirmed instances fixed, remainder reported) |
| "Class W deploy files auto-apply on merge" | None of the 194 files is in `apply-deploy-pipeline-fix.yml`'s 31 path entries (empty intersection). But `apply-web-platform-infra.yml` fires on **any** push touching `apps/web-platform/infra/**` (including `*.test.sh`), and `web-platform-release.yml` fires on `apps/web-platform/**` and `plugins/soleur/**` minus `docs/` and `test/` | Per-slice trigger matrix below; S6 isolates the infra test files; S1 to S4 fire neither |
| "check which touched-file lints in ci.yml fire" | `scripts/lint-shell-trace-credential-refusal.py --changed`, `scripts/lint-orphan-test-suites.sh` and the tempfile-ownership lints all sit in the advisory `lint-bot-statuses` job (`.github/workflows/ci.yml:160`, absent from `scripts/required-checks.txt`). The xtrace lint excludes `*.test.sh` and `tests/`; of the 194 files only `scripts/test-weekly-analytics.sh`, `scripts/test-jaccard-duplicates.sh`, `scripts/test-all.sh` and `scripts/lib/test-contention.sh` are in its scope, and all four exit 0 today | The ratchets that read test text (fixture-relative, fixture-dir-operand, fixture-cd-containment, shell-capture-exit baseline) are the real touched-file risk; see Prototype |
| A research-agent claim: "lint-orphan-test-suites is required" and "`grep -c` always exits 0" | Both wrong. The lint is in the advisory job; `grep -c` exits 1 when the count is 0, which is exactly why it is exit-status-identical to `grep -q` | Recorded here so no AC leans on either |
| "new anti-vacuity floors must meet guard-vacuity-floor.test.sh's shape and be in the LIVE PROMOTED_FILES" | `PROMOTED_FILES=` is assigned four times in `scripts/guard-vacuity-floor.test.sh` (lines 721, 734, 742, 801); bash keeps the last, so only the last is live. `.claude/hooks/` is in `DEFERRED_DIRS`, `scripts/` and `plugins/soleur/test/` in `COVERED_DIRS`. The grep-q guard declares no counter (no `X=$((X+1))`), so it is floor-less today | This plan adds **no** counter and no `-lt` floor to the guard (equality pins only, the existing `SWEEP_PROBE_CHECKS` style); AC runs `guard-vacuity-floor.test.sh`. If a floor becomes necessary, the file joins the last `PROMOTED_FILES` assignment in the same commit |
| "add NOTHING to plugins/soleur/skills/work/SKILL.md" | Files lists below contain no skill file | AC asserts an empty diff for that path |

## Research Insights

### Premise Validation

Checked 2026-10-07 on `origin/main` `411f034290` (branch = main plus the init commit `ffefc8751c`; 0 commits behind).
Issues #9217, #7376, #6601, #7005, #7432, #7797, #9482 are all OPEN. PRs #9525, #9554, #9587, #9632, #9708 and
#9213 are MERGED; `a0359450dd` and `7bb0fbffc2` are ancestors of `origin/main`. The tracker's 2026-10-07 comments
confirm the next items are exactly B and the join. The mechanism (a `grep -c ... >/dev/null` rewrite) is not in
any rejected-alternatives table: it is the form the guard header already prescribes for POSIX sh and empty-capable
values, and Wave A2 shipped it. Nothing cited is stale.

### Property List and Cut List

Properties (each one observable):

- P1. Every pipe-fed early-exit reader in a test file is exit-status-identical to the original and drains its producer, or is a named exception.
- P2. Each touched ceiling equals the measured count (slack 0) and a row at zero is deleted.
- P3. A reviewer can mechanically confirm that a slice's diff is only the transform plus an enumerated hand queue.
- P4. What is left (data, `-m`, demos, mirrors of unconverted carriers) is listed, not hidden in slack.
- P5. A stub on the receiving end of a production `printf | verb` pipe reads its stdin when real `verb` would.
- P6. Each PR is small enough to review, and a merge does not fire a production workflow it does not need to.

Mechanisms named by the ask and what each buys: `grep -c >/dev/null` conversion (P1); splitting (P6); lowering
ceilings (P2); the join (P5). A repo mechanism that already covers each: the form is already in the guard header
and Wave A2; the ledger, stale check and `DEFERRED:` print exist; no join exists (grepped the guard header and `scripts/`:
the sentence "it needs a join from each production pipe to the owning suite's stub" is a statement in prose, not code).

Mechanisms this plan adds, each re-justified against the list: the committed codemod with `verify` (P3; the only
alternative, a scratch script, leaves reviewers unable to re-run it, which is the failure mode of 804 edits);
deleting the codemod in S7 (cost of ownership once the rows are gone). File-exact residual rows with a `_ts_re` widening were considered for S1 and cut by the
review panel (decision-challenges.md item 1); S7 revisits them with the real residual in hand.

**Cut List.**

| Cut | Buys | What already covers it |
| --- | --- | --- |
| A characterization row per converted site | rows that see a dropped `-w`, `-F`, `-x` or `>/dev/null` | `verify` proves every other byte of a line is unchanged, so the flag letters are the only variable; the codemod selftest holds one discrimination row per way the weaker form is satisfiable |
| A committed suite-parity harness | before/after case counts per suite | A per-slice run in two scratch worktrees; results go in the PR body (the prototype below did this) |
| Here-string conversion of `echo`/`printf` sites (the header's preferred bash form) | no pipe at all | One uniform `-c` form removes per-site judgment about newline, empty-value and `-x`/`-F` variable patterns; the header already allows `-c` for "a value that may be empty" |
| A new anti-vacuity floor in the guard | non-vacuity of the selftest | The existing `SWEEP_PROBE_CHECKS` equality pin (a deleted check cannot fail); a floor would make the file floor-bearing inside `DEFERRED_DIRS` and force a `PROMOTED_FILES` edit |
| A `census` mode, a second (Perl) lexer for the classifier, a committed 1,080-row table | a third entry point; a local-only second opinion; exhaustive `grep` semantics proof | The dry run prints the same counts and queue; the demonstration-suspect rule plus the pair run replace the second opinion; the full table runs once and its result goes in the PR body |
| Guard 3 and the `PRODUCER_JOIN` table in this plan | a contract for a mechanism S7's own plan will choose | S7 writes its own Guard Contract after J0; a seed is kept in the join section |
| Editing `scripts/lib/test-affected-paths.sh` | hand-maintained edges | Derivation covers argv literals (header of that file, "HOW TO ADD A CLASSIFICATION"); the guard's selftest invokes `python3 scripts/grep-q-drain-codemod.py` as an argv literal. Consumer: `scripts/test-all.sh --print-selection` (#9307) prints `AFFECTED_SELECTED<TAB><label><TAB>0|1` per suite, so AC-6 reads the guard's line for a diff that touches only the codemod. Editing that file would degrade local `--affected` to the full battery |

### Census (guard-derived)

Command: `bash .claude/hooks/grep-q-pipe-guard.test.sh` (rc 0), `DEFERRED:` lines; per-file detail from the guard's own
`PATTERN_V2` over its own pathspec, comment and marker lines dropped (827 hits; 23 are the six production rows, 804 test-shaped).

| Row | Hits | Files | Where |
| --- | --- | --- | --- |
| `.claude/*.test.sh` | 91 | 17 | `.claude/hooks/*.test.sh` (`session-rules-loader` 40, `skill-context-queries` 12) |
| `tests/*` | 181 | 23 | `tests/scripts` (`test-registry-restore-from-ghcr` 35, `test-dev-suite-mutex` 30, `test-tmp-purge` 22, `test-git-data-rung2-evidence-capture` 22), `tests/commands` 10 |
| `plugins/soleur/test/*` | 140 | 48 | `plugins/soleur/test` (`worktree-manager-bare-in-dotgit-layout` 24) |
| `plugins/soleur/*.test.sh` | 66 | 13 | `plugins/soleur/skills/*/test` 47, `plugins/soleur/scripts` 19 |
| `apps/web-platform/*.test.sh` | 180 | 37 | `infra` 84 (26 files), `scripts` 81 (8 files; `postgrest-reload-schema` 32), `test/infra` 15 |
| `.github/scripts/test/*` | 9 | 5 | |
| `scripts/*.test.sh` | 128 | 46 | includes `scripts/followthroughs` 27 |
| `scripts/test-*` | 6 | 3 | `test-all.sh` 2, `test-weekly-analytics.sh` 2, `test-jaccard-duplicates.sh` 2 |
| `scripts/lib/test-*` | 1 | 1 | `test-contention.sh` |
| `*.test.sh` | 2 | 1 | `.github/actions/infra-credentials/infra-credentials.test.sh` |

Shape (parse-based, not eyeballed): 787 `-q`-bearing, 17 `-m`; producers: about 500 `echo`/`printf`, about 125 command or
function, about 77 file-reading filter, about 14 stream filter, 11 `git`; 18 continuation lines whose producer is on the previous
line (none hazardous). `set -o pipefail` appears in 189 of 194 files (795 sites). The five without it
(`linear-fetch/test/persist-safe-integration`, `sentry-monitors-audit`, `scripts/lib/test-contention.sh`,
`linear-fetch/test/parity`, `sandbox-canary-regression`) hold 9 sites that cannot misread today, which the PR body states
rather than counting them as a flake fix.

**Code versus data.** A context classifier over the 804 lines puts about 640 in plain code context and about 160 in a quoted
string or heredoc. Reading the printed lines, the 160 split into executed strings (eval helpers `expect`, `check`, `assert`, `as`,
`poll`, `bash -c`; generated stub scripts), which the same transform can convert, and data the transform must not touch: command
text handed to a hook as its input (`pkill-self-match-guard` D26 to D28 and A29, `background-poll-prefer-monitor:84`), source-text
pins of a carrier that still has the shape (`registry-luks.test.sh:181,278`, `registry-luks-launch-gate.test.sh:83`, pinned until
wave A3 converts the carrier), `sed`/`perl` mutation expressions, row labels naming the shape, and deliberate SIGPIPE demonstrations
(`iac-plan-write-guard.test.sh:268`, `cron-egress-self-heal.test.sh:329,339`). The residual after all slices is estimated at 40 to 70
sites (5 to 9 percent); it is measured per slice, not promised.

### Prototype (scratch worktrees, discarded; nothing committed)

A throwaway regex pass over the 643 plain-code hits (flag cluster `q` to `c`, `>/dev/null` inserted right after the cluster):

- Converted 633, skipped 10. `bash -n` clean on all 162 changed files.
- The guard's `DEFERRED:` lines fell as expected (`.claude` 91 to 9, `tests` 181 to 28, `plugins/soleur/test` 140 to 13, `scripts/*.test.sh` 128 to 24, `apps/web-platform` 180 to 77). For S1's 26 in-scope files: 95 lines converted; of the 12 left, 5 are data (the `-m` site `pkill-self-match-guard:280` counted once, as data), 3 are the `test-tag-filter.sh` `-m` sites, 1 is the demo and 3 are real code the prototype's crude classifier mistook for heredoc text (so S1's true T0 count is 98).
- `fixture-relative-assert` (62/62), `fixture-dir-operand-assert` (71/71) and `fixture-cd-containment` stayed green with the redirect placed **between the flags and the pattern**, the placement most likely to confuse an operand-parsing ratchet.
- Eight suites run in a pristine copy and the converted copy gave identical rc and result lines (`session-rules-loader` 32/32, `monitor-supersede-guard` 56/56, `skill-context-queries`, `phase-surface-hint`, `incidents` 9, `devin-matcher-parity` 9, `alpha-metrics` 15, `test-jaccard-duplicates` 5). A wider pair run over all 162 changed files was started on a contended host (load average above 16, 150 s cap per suite and side). Partial tally after 64 suites (stopped to relieve the host): 59 identical (rc and result line); **2 differ because the conversion destroyed a demonstration** (`.claude/hooks/iac-plan-write-guard.test.sh` T6, 39/39 became 38/39; `apps/web-platform/infra/supabase-advisor/scan-workflow-mutation.test.sh` D1a and D2 FAILED, rc 0 became 1); 3 timed out on both sides and say nothing. That is the evidence behind R2's demonstration-suspect rule. The full tally goes in the PR body, not here.
- Exit-status equivalence of `grep -q<f>` and `grep -c<f> >/dev/null`: 1,080 rows (20 flag clusters x 9 inputs x 6 patterns, including `-v`, `-x`, `-F`, `-w`, empty input and no trailing newline), **0 differences in bash and in dash**. Phase 1 commits about a dozen representative rows (one per cluster class), collected into a string and asserted empty so no counter is needed; the full table result is pasted in the PR body, not committed.

### Advisor consult (ADR-083, curated payload)

One strong-model consult over the overview, phases and riskiest phase. Applied: (1) the codemod's population now comes from `git grep -anE --column -o`
with the guard's own `SWEEP_*` strings (the guard's regex engine, so the tool and the guard cannot disagree about what a site is; `--column` prints the exact
matched span, e.g. `scripts/test-jaccard-duplicates.sh:34:22: | grep -qF`, and the tool edits only that span); (2) the classifier gets a second, independent opinion
because `verify` proves transform fidelity and cannot see a mis-classified data line (the review panel then cut the Perl lexer as that opinion and replaced it with
two cheaper signals, see R2); (3) residual rows as file-exact `=` rows per slice (cut by the review panel, see Ledger lowering). Not applied, recorded in `decision-challenges.md`: dropping the join from this plan and replacing the textual stub
analysis with a shared drain helper. The operator asked for the join by name, so it stays in the series; S7 starts with its own plan, which makes that
choice with the J0 numbers.

### What fires on a merge, per touched path

| Workflow | Path filter | Fires for |
| --- | --- | --- |
| `web-platform-release.yml` | push to main on `apps/web-platform/**`, `plugins/soleur/**`, minus `plugins/soleur/docs/**` and `plugins/soleur/test/**` (inner gate in `reusable-release.yml` uses the same pathspecs) | S5 and S6 (version bump from the `semver:*` label, image build, deploy) |
| `apply-web-platform-infra.yml` | push to main on `apps/web-platform/infra/**` (less two sub-roots) | S6 only (a whole-root plan, so unrelated drift in that plan is applied at that merge) |
| `apply-deploy-pipeline-fix.yml` | 31 exact host-resident files | none (intersection with the 194 files is empty) |
| `lint-bot-statuses` (advisory) | every PR | all slices; the lints it carries exclude `*.test.sh` |

### Institutional learnings applied

- `knowledge-base/project/learnings/test-failures/2026-10-07-a-behavior-preserving-grep-conversion-needs-rows-that-see-discrimination.md`: rows before the rewrite; a mutant table built from printed first-red rows; a hook suite that scans the repo cannot run in a hand-extracted subtree.
- `knowledge-base/project/learnings/test-failures/2026-10-05-a-reader-that-exits-early-flipped-three-suites-and-the-stub-had-to-read-too.md`: size is not a bound; the producer-side form; a parity check must read an array body with comments dropped.
- `knowledge-base/project/learnings/test-failures/2026-10-05-the-pipefail-sweep-was-seven-times-the-tracker-figure-and-the-audits-absent-in-ci-row-was-wrong.md`: census with the guard's own pattern.
- `knowledge-base/project/learnings/test-failures/2026-10-06-a-source-text-pin-over-a-file-is-a-pipe-into-grep-q-so-the-suite-that-pins-its-own-subject-is-in-the-class.md`: file-reading producers are the live-risk subset (the 77); order commits by it.
- `knowledge-base/project/learnings/test-failures/2026-09-30-stub-drain-fidelity-and-endpoint-keyed-sweeps.md`: the drain idiom for the join (drain on the consuming flag, keep `[ ! -t 0 ]`, capture to a side file, wire-assert the bytes with the `:-` form).
- `knowledge-base/project/learnings/best-practices/2026-07-11-cron-egress-sentinel-needs-runbook-row-and-infra-glob-fires-apply.md`: `apps/web-platform/infra/**` is a path-glob trigger, not `*.tf`.
- `knowledge-base/project/learnings/2026-09-18-every-mechanism-was-validated-against-the-tree-before-its-own-backfill.md`: a net-count ceiling is satisfied exactly by an add-one-delete-one change, so validate the ledger against the tree its own remediation produces.
- `knowledge-base/project/learnings/2026-08-10-a-guard-that-cannot-be-driven-red-is-vacuous-four-rounds-four-instances.md`: matrices derived from the design, written before the guard.

## Open Code-Review Overlap

88 open `code-review` issues were searched for the 194 test files plus the guard (two-stage `gh ... --json` then `jq --slurpfile`). Matches:

- #7208 (memory-backstop post-merge hardening) names `.claude/hooks/memory-backstop.test.sh`. **Acknowledge**: different concern (backstop behavior); the file takes 7 one-line edits here.
- #8659 (33 suites replace test-helpers' composed EXIT trap) names nine `plugins/soleur/test/*.test.sh` files S2 edits, and `scripts/test-all.sh`. **Acknowledge**: trap ownership is untouched by a flag rewrite; S2's PR body lists the nine so the two do not collide in review.
- #7942 (two `*.mutation.sh` batteries run in no gate) and #8800 (census sandbox shares inodes) name `scripts/test-all.sh` and `scripts/test-all-affected.test.sh`. **Acknowledge**: S3 touches `scripts/test-all.sh` for two one-line conversions only.

No overlap is folded in; none is deferred.

## Files to Edit

S1 (this PR, #9720):

- `.claude/hooks/grep-q-pipe-guard.test.sh`: delete the rows `.github/scripts/test/*`, `scripts/lib/test-*`, `*.test.sh`; lower `.claude/*.test.sh` 91 to 5 and `scripts/test-*` 6 to 2 (both stay `<=`, slack 0); add the codemod selftest checks (raise `SWEEP_PROBE_CHECKS`); update the header's FORMS and limits text.
- 17 files under `.claude/hooks/` (all `*.test.sh`): `devin-matcher-parity`, `follow-through-directive-gate`, `guardrails`, `iac-plan-write-guard` (marker), `incident-sandbox-coverage`, `incidents`, `memory-backstop`, `monitor-supersede-guard`, `phase-surface-hint`, `pre-ask-technical-fork-gate`, `prod-write-defer-gate`, `session-rules-loader`, `ship-operator-step-gate`, `ship-runbook-ssh-gate`, `skill-context-queries`; `background-poll-prefer-monitor` and `pkill-self-match-guard` are in the census but stay untouched (data).
- 5 files under `.github/scripts/test/` (`test-cancel-superseded-pr-runs.sh`, `test-infra-suite-registration.sh`, `test-mint-inngest-bootstrap-tag.sh`, `test-no-at-mention-credfile-footgun.sh`, `test-tag-filter.sh`) and `.github/actions/infra-credentials/infra-credentials.test.sh`.
- `scripts/test-weekly-analytics.sh`, `scripts/test-jaccard-duplicates.sh`, `scripts/lib/test-contention.sh`.

Not touched in S1, on purpose: `scripts/test-all.sh` (runner self-edge: a diff to it degrades local `--affected` to the full battery; its two sites go in S3 with that stated), `scripts/lib/test-affected-paths.sh`, `scripts/guard-vacuity-floor.test.sh`, anything under `plugins/soleur/skills/work/`, `.mcp.json`.

## Files to Create

- `scripts/grep-q-drain-codemod.py` (python3 stdlib; modes `apply`, whose default dry run prints the per-tier counts and the hand queue, and `verify`).
- Learning files under `knowledge-base/project/learnings/test-failures/`, one per non-obvious finding (candidates in AC-11).
- `knowledge-base/project/specs/feat-one-shot-grep-q-wave-b-test-harness/tasks.md` and `decision-challenges.md`.

No new `*.test.sh`: a new suite under `scripts/` is in the covered floor scope (it must carry a compliant floor) and needs a `run_suite` registration in `scripts/test-all.sh` (a runner self-edge); the selftest lives in the existing guard suite instead.

## Problem Statement

The guard defers 804 test-harness sites behind ceilings that can only fall by hand, and nothing mechanical prevents a
reviewer-invisible slip in a rewrite of that size. The producer-side form (a stub that never reads stdin) is invisible to
any line search and has already turned `deploy-script-tests (3/4)` red once (`cutover-inngest-workflow.test.sh:1335`).

## Proposed Solution

### The conversion form

`<producer> | grep -q<flags> ARGS` becomes `<producer> | grep -c<flags> >/dev/null ARGS`: `q` replaced by `c`, the redirect inserted
immediately after the flag cluster. The redirect position is chosen for robustness, not looks: it needs no knowledge of where the
pattern operand ends (quotes, `$'..'`, `"$x"`, `--`), is the same redirect-before-pattern family Wave A2 and `ci-deploy.test.sh:5763` already use (that precedent writes `grep -c -- >/dev/null '--password-stdin'`, the redirect after `--`), and the
prototype shows the operand-parsing ratchets accept it. Exit status equals `grep -q`'s (0 iff a line was selected; `-v` and empty
input included; bash and dash, 1,080 rows run once and recorded in the PR body). It reads the whole stream, so the producer never takes EPIPE. It is valid in `/bin/sh`.

### Eligibility tiers (decided per site by the classifier, printed with a reason)

| Tier | Meaning | Action | Row owed |
| --- | --- | --- | --- |
| T0 | `-q` cluster, code context, bounded producer | codemod `apply` | none: `verify` proves the line differs from base only by the transform |
| T1 | same, inside an executed string (eval helper argument, `bash -c`, generated stub heredoc) | codemod `apply --exec-strings` after the reviewer marks the line `exec` | none |
| H-m | `-m N` (output-bearing) | hand: capture then match, `grep -m1 P <<<"$V"` only where `$V` is never empty | yes, one that sees a first-match-not-first-line input |
| H-mirror | a test replica of production logic that production has since converted | hand: copy the production form, not the codemod form | yes |
| H-data | the shape is data (hook input, source-text pin of an unconverted carrier, mutation expression, label) | leave; stays counted in the row until its carrier converts | none |
| H-demo | a deliberate SIGPIPE demonstration | append `# sigpipe-demo: intentional` (trailing comment, single-line statements only) | none: the demo is its own observer |
| X | unbounded producer or operand-`q` cluster | refuse, list | decided by hand |

Rule for the executed-versus-data call: a string is code if it is handed to something that executes it (eval helper, `bash -c`, a
generated script) and data if it is handed to something that parses, matches or classifies it (a hook under test, `grep -F`, `sed`,
`perl`, a label).

### The codemod (`scripts/grep-q-drain-codemod.py`)

Rules, each with a selftest check:

- R1 Population is the guard's own: the tool extracts the guard's `SWEEP_*` strings, builds `PATTERN_V2` and runs `git grep --no-index --exclude-standard -anE --column -o -e "$PATTERN_V2"` with the guard's pathspec, so it edits exactly the span the guard matched and never reimplements the regex in another dialect. A selftest check asserts the dry run's total equals the guard's `DEFERRED:` sum before conversion.
- R2 One bash-aware line tokenizer decides code versus data: quote and heredoc state carried across lines, reset at blank lines, comments and `fi|done|esac|else`; `<<<` is never a heredoc opener; unsure goes to the hand queue with the reason. Two cheap signals back it, because `verify` cannot see a mis-classified data line: (a) a **demonstration-suspect** file is never auto-applied (a file whose text names `sigpipe`, `EPIPE`, `false-FAIL` or `broken pipe` is routed to hand review; the partial prototype pair run found two such suites whose converted copy failed, `iac-plan-write-guard.test.sh` T6 and `supabase-advisor/scan-workflow-mutation.test.sh` D1a/D2, because the converted line was the thing the row demonstrates); (b) the per-suite pair run. A second lexer (the repo's `.claude/hooks/lib/filing-shape.pl`, or `shfmt`, which is installed nowhere in the repo) was considered and cut by three review seats as a local-only opinion nothing durable depends on.
- R3 Cluster parse is left to right and stops at `e f A B C m d D` (they take an operand): `-eq` is refused; `--quiet`/`--silent` map to `-c`.
- R4 `apply` is one line in, one line out (line numbers and every `# sigpipe-demo` marker survive), idempotent (a second run changes 0 lines), dry-run by default (`--write` to modify). Hand edits are exempt from this rule and are listed to `verify`.
- R5 No network, no writes outside the named files.
- R6 `verify --base REF --hand-edits FILE`: pairs the removed and added lines of each `git diff -U0 REF` hunk and requires `transform(removed) == added`. `FILE` lists hand edits keyed by BASE-side line range, `path:OLD[-OLD2]:reason` (the `-a,b` side of the `@@` header); a hunk whose removed range lies wholly inside a listed range is exempt, including a hunk whose added and removed counts differ. A listed range that matches no hunk, a hunk that is neither a transform nor listed, and a transform that changes the line count all fail; zero verified lines exits 3 (`UNRESOLVED`), never 0. It proves the transform, not the classification.
- R7 The dry run prints per-row and per-tier counts and the hand queue (`path:line:tier:reason`), which is the PR body's table.

### Hand queue for S1 (from the census, before the codemod runs)

| Site | Tier | Action |
| --- | --- | --- |
| `.claude/hooks/background-poll-prefer-monitor.test.sh:84` | H-data | untouched: command text passed to the hook as `mk_bg` input |
| `.claude/hooks/pkill-self-match-guard.test.sh:223,224,225,280` | H-data | untouched: `run_case` hook inputs (A29 is the `-m` one) |
| `.claude/hooks/iac-plan-write-guard.test.sh:268` | H-demo | marker: the row asserts that the pre-fix shape races (T6) |
| `.github/scripts/test/test-tag-filter.sh:75,109,138` | H-m + H-mirror | `run_pipeline` replicates the old release pipeline (`printf \| grep \| sort -V -r \| { grep -m1 ... \|\| [ $? -eq 1 ]; }`); `.github/workflows/reusable-release.yml` (around lines 298-299) now reads `tags=$(git tag ...)` then `grep -m1 -E P <<<"$tags" \|\| [ $? -eq 1 ]`. Mirror that, keep the `$? -eq 1` tolerance, and add a row where the first match is not on the first line (the `vinngest-v1.0.0` collision under the bare `v` prefix, #4082) |
| the remaining 98 sites | T0 | `apply` |

So S1 removes 102 hits (107 minus the 5 data lines) and 804 becomes 702.

### Ledger lowering (S1)

Before and after, from `bash .claude/hooks/grep-q-pipe-guard.test.sh`:

| Row | Before | After |
| --- | --- | --- |
| `.claude/*.test.sh` | `<=` 91 | `<=` 5 (two files, both data) |
| `.github/scripts/test/*` | `<=` 9 | deleted (0) |
| `scripts/test-*` | `<=` 6 | `<=` 2 (`scripts/test-all.sh`, converted in S3 and the row deleted there) |
| `scripts/lib/test-*` | `<=` 1 | deleted (0) |
| `*.test.sh` | `<=` 2 | deleted (0) |
| the other five test rows and the six production rows | unchanged | unchanged (`tests/*` 181, `plugins/soleur/test/*` 140, `plugins/soleur/*.test.sh` 66, `apps/web-platform/*.test.sh` 180, `scripts/*.test.sh` 128; 23 production hits) |

Each lowered value is the number the guard prints after conversion, with slack 0. A row that reaches zero fails as stale until deleted, so deletion is forced, not optional. A `<=` row at slack 0 is still satisfied by an add-one-delete-one change; that hole is named in Risks and revisited in S7 (file-exact `=` rows need a `_ts_re` widening, because the guard's `GATED_PROD_ROWS` check counts a file-exact test path as a production row).

### Phases (S1)

**Phase 0, re-measure (read-only).** Run the guard and keep the `DEFERRED:` lines. Re-run the unbounded-producer screen and the
code-versus-data count for S1's files. Intersect S1's files with the three workflow path filters (expect empty). Run the xtrace lint on
the four in-scope-looking files (expect rc 0). `uptime`: if the load average is above the core count, local `--affected` is skipped and
the PR body says so verbatim.

**Phase 1, instrument and guard first (red).** In the guard, add the codemod selftest checks and the ledger edits first; they fail because
the tool does not exist (`cq-write-failing-tests-before`). Write `scripts/grep-q-drain-codemod.py` until the checks pass. The selftest fixtures
are synthesized strings (`cq-test-fixtures-synthesized-only`): one check per flag cluster class, per refusal reason, about a dozen equivalence
rows in bash (and dash when present), idempotency, and the `verify` RED fixtures. Python3 missing prints `UNRESOLVED` and exits 3, like the existing git check.

**Phase 2, convert.** Three commits in live-risk order inside the slice: file-reading producers, command and function producers, echo/printf.
Then the hand queue, each hand edit with its row. Record every hand edit in a `hand-edits` list (path:line:reason) for `verify`.

**Phase 3, verify.** `verify --base origin/main --hand-edits <list>` must print `unexplained: 0`. `bash -n` on all 24 edited files. A pair run
(pristine worktree versus branch, same command, 150 s cap) for every touched suite that runs locally; list the ones that do not (they need
root, network or Doppler) in the PR body and let CI carry them. Run `bash scripts/pre-push-ratchet-lane.sh`,
`bash scripts/guard-vacuity-floor.test.sh` and the guard.

**Phase 4, hand-applied mutation battery** (the Guard 1 matrix; the Guard 2 matrix is the committed RED fixtures) on scratch copies in a committed worktree with a clean-tree check, recording
the first red row from the printed output, not from memory.

**Phase 5, evidence and ship.** Learning files; tracker comment on #9217 with the DEFERRED before/after table and the NOT-fixed list; the ship tail
below.

## Slice Register (later PRs of the same series, separate follow-ups, not new issues)

Each is one PR, merged before the next because every slice edits adjacent lines of the guard's deferral table (a conflict on one line
is resolved by hand; no mid-flight sync of a BEHIND branch). Verified against `origin/main` `411f034290` on 2026-10-07.

| Slice | Row(s) lowered or deleted | Hits / files | Fires on merge | Notes |
| --- | --- | --- | --- | --- |
| S1 (#9720) | `.claude/*.test.sh` (91 to 5), `.github/scripts/test/*`, `scripts/lib/test-*`, `*.test.sh` (deleted), `scripts/test-*` (6 to 2) | 107 in scope / 24 edited | nothing | codemod, selftest, ledger |
| S2 | `plugins/soleur/test/*` | 140 / 48 | nothing (`plugins/soleur/test/**` is excluded from the release) | nine files overlap #8659; `worktree-manager-bare-in-dotgit-layout` alone is 24 |
| S3 | `scripts/*.test.sh`, the rest of `scripts/test-*` | 130 / 47 | nothing | includes `scripts/followthroughs` (27) and `scripts/test-all.sh` (2; local `--affected` degrades to the full battery for that diff, stated in the PR body) |
| S4 | `tests/*` | 181 / 23 | nothing | `tests/scripts/test-registry-restore-from-ghcr.sh` (35) and `test-dev-suite-mutex.sh` (30) are the large files; `test-git-data-birth-readiness-gate.sh:2971-2974` are probe functions that pin the guard's own pattern (H-data) |
| S5 | `plugins/soleur/*.test.sh`, `apps/web-platform/*.test.sh` narrowed to `apps/web-platform/infra/*.test.sh` | 162 / 24 | `web-platform-release.yml` (patch bump; labels `semver:patch`, `app:web-platform`) | `plugins/soleur/skills/*/test` and `plugins/soleur/scripts`; `apps/web-platform/scripts` and `apps/web-platform/test/infra` |
| S6 | `apps/web-platform/infra/*.test.sh`, plus the Arm F fix in `cutover-inngest-workflow.test.sh` | 84 / 26 | `web-platform-release.yml` and `apply-web-platform-infra.yml` | the workflow plans the whole root, so unrelated drift in that plan is applied at this merge; postmerge reads the apply run for the merge SHA |
| S7 | the producer-side join (Arm P and the Arm F remainder), then the cleanup | n/a | depends on the stub edits | starts with its own `soleur:plan` run that uses the section below and the J0 numbers; deletes the codemod and its selftest once no glob row is left |

Demonstration-suspect files already visible in later slices (R2 routes their hits to hand review, never auto-apply): `plugins/soleur/test/worktree-manager-porcelain-sigpipe.test.sh` (S2), `tests/scripts/test-git-data-birth-readiness-gate.sh` probe functions at lines 2971-2974 (S4), `apps/web-platform/infra/cron-egress-self-heal.test.sh`, `supabase-advisor/scan-workflow-mutation.test.sh` and `workspaces-luks-freeze.test.sh` (S6). Each slice's dry run re-derives the list from the sigpipe/EPIPE/false-FAIL/broken-pipe text signal.

Order is S1 to S7. The join (S7) has no code dependency on S2 to S6 and can move up if a producer-side flake recurs; it sits last
because its stub fixes land in suites that S2 to S6 also edit, and a late join avoids rebasing those one-line hunks.

Per slice, unchanged from S1: `Ref #9217`, never `Closes`; no `[skip-deploy-fix-apply]`; a tracker comment with the command that produced
each number; one learning per non-obvious finding; an explicit NOT-fixed list; `Filed:` line (and a net-issue-flow override justification if
any issue is filed); Merge Danger (`Undo:` and `Blast Radius:`); Pipeline Tally; Changelog; Model Dissents; then `soleur:postmerge`
(deploy-arm `find --wait`, then served, which must read CONTAINS).

## Producer-side join (S7 design)

The guard header's last paragraph names it: "THE PRODUCER SIDE of the pipe ... is invisible to any line search: it needs a join from each
production pipe to the owning suite's stub." Two arms. This is a design sketch plus a fixed Guard Contract, not a work breakdown: S7 opens with its own
plan once J0 has produced the numbers, and that plan chooses between the flag-keyed textual evidence below and a shared stub-drain helper that stubs of the
listed verbs call (an advisor suggestion; simpler to check, but it edits every owning stub and it drains on the verb rather than the consuming flag, which the
2026-09-30 learning says masks a mutant that drops the flag).

**Arm P, production pipe to owner stub (guard-pinned).**

- J0 measure. Derive production sites with `git grep` over the production roots for `(printf|echo|cat) ... | [sudo] <verb>` with verb in `gh curl doppler docker terraform nft ssh sudo systemctl logger` (33 candidate lines today: `gh` 10, `docker` 7, `curl` 6, `doppler` 5, `terraform` 3, `sudo` 1, `nft` 1). Keep the sites whose script sets `pipefail` and whose pipeline status is observed (a `|| bail`, an `if !`, errexit). For each, the owners are the suites that name the production file on a code line and define a stub for the verb (heredoc stub file, `verb()` function, a stub helper). Post the counts on #9217.
- J1 fix. In each owner, make the stub drain exactly when argv carries the consuming flag (`--body-file -`, `--password-stdin`, `--config -`, `-f -`, and the doppler secret-write verb when its value is piped), keep `[ ! -t 0 ]`, capture the bytes to a `$CALLS` side file, and wire-assert them with the `${KNOB:-default}` form (idioms from the 2026-09-30 and 2026-10-05 learnings). A stub that is non-draining on purpose (the luks suite's `FIXTURE_NO_DRAIN` control) is listed as an exemption with its reason.
- J2 pin (seed for S7's own Guard Contract, not an entry here). Property: for every production pipe from `printf`, `echo` or `cat` into a stdin-consuming verb in a `pipefail` script, every suite that runs that script with the verb stubbed carries a stub that drains stdin when argv has the consuming flag, or the pair is listed with a reason. Candidate mechanism: a `PRODUCER_JOIN` table in the guard (site, verb, consuming flag, owners) whose derived site set must equal the table's, every derived owner in its row, and each owner's stub carrying the flag token and a stdin reader positioned **before** the stub's first `exit`/`return` in the same arm. Mutation rows S7 must carry: a new unlisted production site; a stub with its drain deleted; a second owner after a compliant first; an empty production derivation (exit 3); a stale row; and a REORDER row that moves the drain below the stub's `exit` (the property is about when the read happens, so a delete-only battery would not see it). Harness rows: a non-draining control stub under a delayed writer must reproduce the EPIPE; three drain spellings must pass.

**Arm F, test-side function consumers (measured; the confirmed instance is fixed in S6, the remainder is reported on #9217).** 103 lines in 24 files pipe `printf`/`echo`/`cat` into a function defined in the
same file (largest: `lint-credential-path-literals.test.sh` 17, `cron-egress-self-heal.test.sh` 16, `eval-gate.test.sh` 11). The live instance is
`apps/web-platform/infra/cutover-inngest-workflow.test.sh:1330,1335,1341,1348,1352`: `printf '%s\n' "$FIX..." | _generation_scoped_count ...` where the
stubbed `_current_instance_row_counts` makes the function return before it reads stdin. A line search cannot say whether a function reads stdin on every
path, so Arm F is: measure functions with an early `return`/`exit` ahead of their first stdin reader, convert confirmed instances to
`fn args <<<"$V"` (no pipe, so no writer to signal; the function runs in the same subshell it already runs in), and report the remainder on the tracker.
It is not pinned by a guard. The confirmed instance sits in `apps/web-platform/infra/cutover-inngest-workflow.test.sh`, an S6 file, so it is fixed there as a hand edit with a row (a function that returns before reading, fed by a delayed `printf`), not held back for S7.

**Honest limits of the join.** Stub detection is textual: a stub built by a helper whose name the pattern does not know is invisible, which the
header will state with the measured count. The join proves the stub is shaped to drain; the dynamic control (non-draining stub under a delayed writer
reproduces the EPIPE) proves the failure exists, and is a row.

## Alternative Approaches Considered

| Alternative | Why not |
| --- | --- |
| One PR for all 804 sites | 194 files, a release and a production apply fire at once, and a single red suite blocks the whole queue entry; the transform is mechanical but the data/executed call is not |
| Scratch (uncommitted) transformer, as PR-1 and Wave A2 used | Five more PRs depend on it and the reviewer cannot re-run it; the earlier plan said "committed by the first later wave that needs it", which is this one |
| A `sed -E` one-liner | Cannot distinguish a pipe from a quoted fixture or a heredoc; cannot refuse `-eq`; cannot verify |
| Here-strings for `echo`/`printf` sites | Per-site judgment about empty values, `printf '%s'` without a newline and variable `-x`/`-F` patterns; 500 judgments instead of none |
| Converting all residual data lines by rewording labels and pins | A source-text pin of an unconverted carrier must keep the carrier's text; the rest is small and decided per slice |
| File-exact `=` rows for each slice's residual, with a `_ts_re` widening, from S1 | Considered (advisor) and cut by three review seats: it changes the guard's production-row classifier to close a hole in about 7 data lines; revisit in S7 (decision-challenges.md item 1) |
| Put the join first | It addresses the one defect that turned CI red, but its stub fixes land in files S2 to S6 also edit; kept last, movable |

## User-Brand Impact

- **If this lands broken, the user experiences:** a hook or gate suite that stopped asserting what it names, so a regression in a policy-gate hook (`prod-write-defer-gate`, `browser-snapshot-credential-guard`, `session-rules-loader`), an infra drift guard or a release-script check ships green; the visible symptom is a defect that the suite exists to catch reaching a user build.
- **If this leaks, the user's workflow is exposed via:** no secret or user data is read or written by the change; the exposure vector is a fail-open conversion that makes a security-adjacent assertion pass vacuously (a dropped `-x`/`-F`, an inverted `!`, a fixture converted that was the hook's input).
- **Brand-survival threshold:** `aggregate pattern`
- **Threshold decision (challengeable):** not `single-user incident` because no conversion touches user data, each site is one of ~800 equivalent one-token rewrites proved by `verify`, and the hand queue is small and enumerated; not `none` because a systematic classifier or transform bug would repeat across hundreds of assertion sites, some guarding hooks, and S6 touches `apps/web-platform/infra/` (a sensitive path), so the section carries no `threshold: none` scope-out.

## Observability

```yaml
liveness_signal:
  what: the grep-q-pipe-guard suite runs in the CI test group on every PR and merge_group run and prints PASS lines plus one DEFERRED line per row
  cadence: per PR and per merge_group run; run directly before each push
  alert_target: the required test check turns red on the PR, which blocks merge and ejects a queue entry
  configured_in: scripts/test-all.sh SUITE_GLOBS entry '.claude/hooks/*.test.sh' (registration), .claude/hooks/grep-q-pipe-guard.test.sh (the passes)
error_reporting:
  destination: CI job log of the test check (repo-hygiene guard, no Sentry surface)
  fail_loud: a FAIL line naming file, line and the forbidden shape or the exceeded/stale/loose ceiling, exit 1; an unreadable input, an empty derived population or a missing python3 prints UNRESOLVED and exits 3
failure_modes:
  - mode: a new early-exit pipe lands in a swept subtree or a former row
    detection: the derived pass reports it as outside the deferral table or over its ceiling
    alert_route: required test check red on the PR
  - mode: the ledger drifts loose (a ceiling above its hit count) or stale (a row with no hits)
    detection: the existing loose/stale checks plus slack printed on every DEFERRED line
    alert_route: required test check red on the PR
  - mode: the codemod's selftest is deleted or neutered
    detection: SWEEP_PROBE_CHECKS equality pin counts the checks; the RED fixtures fail if verify stops failing
    alert_route: required test check red on the PR
  - mode: a converted suite changes behavior
    detection: the suite's own result line compared base versus branch (recorded in the PR body) and the suite itself in CI
    alert_route: required test check red on the PR
logs:
  where: CI job logs of the test check; locally the stdout of the guard
  retention: GitHub Actions log retention
discoverability_test:
  command: bash .claude/hooks/grep-q-pipe-guard.test.sh
  expected_output: grep-q-sweep-probe-pass
```

Detection note for preflight Check 10: the command is one deterministic file with no build or network and measured 2.2 s on this tree against
the 15 s cap (`time bash .claude/hooks/grep-q-pipe-guard.test.sh`, rc 0). AC-12 re-measures it after the selftest rows land, since they add python3 calls.

## Guard Contract

### Guard 1 — deferral ledger after the test-harness conversion

**Property.** After a slice merges, every pipe into an early-exit grep outside a comment or a marked demo is either converted or counted by a row
whose ceiling equals today's hit count, and no row carries slack.

**Assembly.** One population and one verdict: `scan_sweep <root>` (git grep over `SWEEP_PATHSPEC` with `PATTERN_V2`, comments and markers dropped) and
`sweep_verdict` over `SWEEP_DEFERRALS`, plus the existing `_ts_re`/`GATED_PROD_ROWS` row-shape checks and the `DEFERRED:` print. Every slice edits only that
table and the header; the probe drives the same functions on scratch roots. The chokepoint is `scan_sweep`; a second scanner (the codemod's dry run)
exists only as a parity check against it.

**Mutation matrix** (hand-applied on scratch copies in a committed worktree after a green control; each row names its expected result):

| # | Mutation | Expected |
| --- | --- | --- |
| 1 | Append `echo "$x" \| grep -q p` to a converted file whose row was deleted (`scripts/test-jaccard-duplicates.sh`) | RED: outside the deferral table |
| 2 | Append one hit to a file under a still-deferred row at its ceiling (`tests/scripts/test-tmp-purge.sh`) | RED: ceiling exceeded |
| 3 | Append the deleted row `'*.test.sh \| <= \| 2 \| #9217'` after the other test rows (so earlier rows keep their files) | RED: stale deferral |
| 4 | Revert one converted site in `.claude/hooks/session-rules-loader.test.sh` while the lowered `.claude/*.test.sh` ceiling is 5 | RED: ceiling exceeded (proves slack 0) |
| 5 | Empty the table (`SWEEP_DEFERRALS=()`) | RED: every residual hit is undeferred (the guard's own dispatch) |
| 6 | Add a second bad file in another former row's directory after a compliant first | RED: the derived pass reports both |

Harness rows. Suite edit that must go RED: change `SWEEP_PROBE_CHECKS` by one. Must-PASS non-canonical input: a fixture line `x | grep -cE >/dev/null -- "$p"` (flags and redirect in an order no existing probe line used), scanned through `scan_sweep`.

Anchor. Ceilings and checks live in the file they protect, so one commit can raise both; this proves consistency, not integrity. What must also move for a weakening to pass: the PR body's before/after `DEFERRED:` table (produced by the command, reviewable against the diff) and the tracker comment; the add-one-delete-one hole stays open for every `<=` row until its slice lands and is named in Risks, not claimed as covered.

### Guard 2 — `verify` (the diff is only the transform)

**Property.** Every changed line of a slice's diff over swept files is either the codemod's forward transform of its base line or is in the enumerated hand-edit list with a reason, and the count of unexplained lines is zero. This is a property of the TRANSFORM only: a data line converted by mistake still equals `transform(removed)` and passes, so classification is held by R2's two opinions, the printed data list a reviewer reads, and the per-suite pair run, not by `verify`.

**Assembly.** `verify` consumes `git diff -U0 --no-color <base>` for all changed files, pairs removed with added lines per hunk, and applies the same forward-transform function `apply` uses (one function, two callers). Chokepoints: the diff producer, the transform, the hand-edit list. A rename, a mode change or an unequal hunk fails.

**Mutation matrix:**

| # | Mutation | Expected |
| --- | --- | --- |
| 1 | Change a pattern's text in one converted line (`'FALLBACK'` to `'FALLBACX'`) | RED naming file:line |
| 2 | Remove `>/dev/null` from one converted line | RED: not equal to the transform of its base |
| 3 | Drop `-x` (`-cx` to `-c`) in one converted line | RED |
| 4 | Run `verify` over an empty diff or a wrong base | exit 3 UNRESOLVED, never 0 (the tool's own dispatch) |
| 5 | Two files in the diff: first compliant, second hand-edited and unlisted | RED: all members are checked, not the first |
| 6 | A hand edit listed but absent from the diff | RED: stale hand-edit entry |
| 7 | A converted line that also joins or splits lines (line count changes) | RED |

Harness rows. Suite edit that must go RED: neuter `verify` to exit 0 (the RED fixtures then pass vacuously and the checks fail). Must-PASS non-canonical input: a fixture using the cluster `-Eq`, a `--quiet` spelling and a line that already ends in `2>/dev/null`.

Anchor. The base ref must be `origin/main`, not the branch; the independent number is the dry run's parity with the guard's `DEFERRED:` sum before any conversion. Both live in the commit, so the outside anchor is the PR body's `verify` output pasted from the command and a reviewer re-running it.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected: an engineering-internal CI-hygiene change with no product, marketing, legal, finance, sales or support surface. The engineering lens (classifier safety, ledger design) is carried by the plan-review panel.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "Item B of the grep -q pipe-guard series (tracker #9217; also #7376, #6601; umbrella #9482): Wave B test harness conversion (~800 hits, test-shaped ceilings) plus the producer-side join." [brief] | Overview, Slice Register, Producer-side join | mapped |
| 2 | "Pass 1 (a0359450) and Pass 2 (PR #9708, 7bb0fbff) are merged and must NOT be redone." [brief] | Premise Validation, Overview | mapped |
| 3 | "START with a fresh census: `bash .claude/hooks/grep-q-pipe-guard.test.sh` and read the DEFERRED: lines (do not eyeball git grep)" [brief] | Research Insights, Census; Phase 0 | mapped |
| 4 | "convert test-harness `<producer> \| grep -q` sites to the exit-status-identical `grep -c ... >/dev/null` form (flag transform -q<flags> -> -<flags>; rule out unbounded producers first, since dropping -q reads to EOF)" [brief] | Conversion form, tiers, codemod, Phase 2; the unbounded-producer reconciliation row | mapped |
| 5 | "split by subsystem if the diff is too large for one PR (each its own merged PR)" [brief] | Slice Register | mapped |
| 6 | "LOWER the test-shaped ceilings in .claude/hooks/grep-q-pipe-guard.test.sh to the measured count with NO slack" [brief] | Ledger lowering, Guard 1 | mapped |
| 7 | "Then the producer-side join." [brief] | Producer-side join (design and the Arm F fix in S6), Slice Register S7 (delivery, tracked on #9217) | mapped |
| 8 | "Per-PR rules: evidence comment on tracker #9217 (and #7797/#9482 where relevant); one learning per non-obvious finding; say plainly in the PR body and tracker comment which items were NOT fixed; use Ref not Closes; never use [skip-deploy-fix-apply]; Class W deploy files auto-apply on merge." [brief] | Phase 5, Slice Register footer, AC-10 to AC-12, trigger matrix | mapped |
| 9 | "check which touched-file lints in ci.yml fire on a script before editing it" [brief] | the touched-file-lints reconciliation row, the trigger table, Phase 0 | mapped |
| 10 | "new anti-vacuity floors must meet guard-vacuity-floor.test.sh's shape and be in the LIVE PROMOTED_FILES" [brief] | the PROMOTED_FILES reconciliation row, Cut List, AC-6 | mapped |
| 11 | "add NOTHING to plugins/soleur/skills/work/SKILL.md (about 60 bytes under its 362000-byte ceiling)" [brief] | Files to Edit (excluded), AC-13 | mapped |
| 12 | "verify subagent claims at file:line; read rc files not completion notifications; do not launch a second git commit while a hook runs; local --affected may be skipped on a contended host (say so verbatim in the PR body); do not re-sync a BEHIND branch mid-flight; queue is runner-saturated, so keep pushes minimal." [brief] | the research-agent-claims reconciliation row, Phase 0 and 3, Risks, AC-10 | mapped |
| 13 | "Ship tail per PR: Filed: line plus net-issue-flow override justification if issues filed, semver label, app:web-platform label if apps/web-platform changed, Merge Danger (Undo:, Blast Radius:), Pipeline Tally, Changelog, Model Dissents, then soleur:postmerge (deploy-arm find --wait, then served, must read CONTAINS)." [brief] | Slice Register footer, AC-12 | mapped |
| 14 | "the plan MUST first take the fresh census, group sites by file/subsystem, and decide a PR split (this branch/PR #9720 = the first slice; list later slices as separate follow-up PRs of the same series, not as new issues unless needed)" [brief] | Census, Slice Register | mapped |
| 15 | "decide per-site whether a conversion is behavior-preserving and whether a row can observe it" [brief] | Eligibility tiers, hand queue, Cut List | mapped |
| 16 | "Also include the \"producer-side join\" item from the series brief (read tracker #9217 and the hook suite header for what this means)." [brief] | Producer-side join | mapped |
| 17 | "the main checkout has an uncommitted `M .mcp.json` that is not yours; leave it." [brief] | AC-13 | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| Guard edits (ledger rows, header text) | "LOWER the test-shaped ceilings in .claude/hooks/grep-q-pipe-guard.test.sh to the measured count with NO slack" | asked |
| 24 edited test files in S1 (26 in scope; two are data-only) | "convert test-harness `<producer> \| grep -q` sites to the exit-status-identical `grep -c ... >/dev/null` form" | asked |
| Slice Register S2 to S7 | "list later slices as separate follow-up PRs of the same series, not as new issues unless needed" | asked |
| Hand queue and tier table | "decide per-site whether a conversion is behavior-preserving and whether a row can observe it" | asked |
| Producer-side join (Arm P design, Arm F fix in S6, S7 slice) | "Also include the \"producer-side join\" item from the series brief" | asked |
| Learning files | "one learning per non-obvious finding" | asked |
| `scripts/grep-q-drain-codemod.py` with `apply` and `verify` | asks 4 and 5 | inferred — justification: 804 edits cannot be reviewed by eye and a sed pass cannot tell a pipe from a quoted fixture; the earlier plan deferred committing a transformer to "the first later wave that needs it", and five PRs now do |
| Codemod selftest checks inside the guard and the `SWEEP_PROBE_CHECKS` raise | ask 4 | inferred — justification: an untested tool that rewrites 804 lines is the vacuity class this series exists to stop; the guard is floor-less and already holds the pinned-probe style, so no new suite, registration or floor is needed |
| Deleting the codemod and selftest in S7 | ask 5 | inferred — justification: once no glob row is left the tool has no caller; leaving it is unowned machinery |
| `decision-challenges.md` and `tasks.md` | ask 14 | inferred — justification: the headless plan contract persists taste decisions for the ship PR body, and `soleur:work` consumes `tasks.md` |
| The 23-hit production rows left unchanged | ask 2 | inferred — justification: wave A3 carriers are host-replace or image-pin gated and the brief limits this item to the test harness |

### Split Assessment

- Subsystems touched: 4 — `.claude`, `.github`, `scripts`, `knowledge-base` (S1; the series adds `plugins/soleur`, `apps/web-platform`, `tests`)
- Planned files: about 34 (S1: 24 edited, guard, codemod, plan, tasks, decision-challenges, up to 3 learnings, spec dir) | Estimated changed lines: about 500 (107 one-line edits, about 150 of guard and selftest, about 160 of codemod, docs)
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: split — applied at the series level (S1 here, S2 to S7 in the Slice Register, boundary = one deferral row per PR so ceilings never conflict mid-row). Within S1 stay one PR: the 24 edited files are 107 one-line edits proved by one `verify` run.

## Acceptance Criteria

S1 (this PR). The pre-merge boxes are checkable on the final tree; the post-merge boxes are executed by `soleur:postmerge` and the tracker comment, with no human step.

### Pre-merge (PR)

- [ ] AC-1 `bash .claude/hooks/grep-q-pipe-guard.test.sh` rc 0 and its `DEFERRED:` lines read: the three file-exact rows `=` 1, `=` 4 and `=` 2, the five untouched test globs unchanged (`tests/*` 181, `plugins/soleur/test/*` 140, `plugins/soleur/*.test.sh` 66, `apps/web-platform/*.test.sh` 180, `scripts/*.test.sh` 128), the five replaced or deleted globs absent, the six production rows unchanged (23 hits); slack 0 on every line.
- [ ] AC-2 Test-shaped hits fall from 804 to 702 (command: sum of the `DEFERRED:` hits of the ten test rows before, and of the surviving test rows after, pasted in the PR body).
- [ ] AC-3 `python3 scripts/grep-q-drain-codemod.py verify --base origin/main --hand-edits <list>` prints `unexplained: 0` with exactly four listed hand-edit ranges (the `test-tag-filter.sh` block and the marker line in `iac-plan-write-guard.test.sh`, base-side line numbers), and `apply` run a second time changes 0 lines.
- [ ] AC-4 `bash -n` passes on all 24 edited files; the hand-edit rows (first match not on the first line; first-line-only reader) fail under their mutant and pass on the final tree.
- [ ] AC-5 The PR body carries one table row per edited suite: either identical rc and result line between a pristine worktree and the branch, or `not run locally` with the reason (root, network, Doppler, timeout); a difference blocks the PR until explained.
- [ ] AC-6 `bash scripts/guard-vacuity-floor.test.sh`, `bash scripts/lint-orphan-test-suites.sh` and `bash scripts/pre-push-ratchet-lane.sh` pass; `git diff` adds no `X=$((X+1))` counter or `-lt` floor to the guard; `python3 scripts/lint-shell-trace-credential-refusal.py --changed --base origin/main` is clean; `bash scripts/test-all.sh --print-selection` on a diff that touches only the codemod prints `AFFECTED_SELECTED` 1 for the grep-q guard (if it does not, name the missing edge in the PR body rather than editing `scripts/lib/test-affected-paths.sh`).
- [ ] AC-7 The Guard 1 matrix (six rows) was hand-applied on scratch copies after a green control, each mutant RED with its first failing row recorded from the printed output and the restore check clean (`git status` empty); the Guard 2 matrix is the selftest's committed RED fixtures, which run in CI, not a separate hand run.
- [ ] AC-8 About a dozen representative equivalence rows (one per flag-cluster class) run in the selftest, bash always and dash when present (absent dash prints `UNRESOLVED` and exits 3, never a silent skip), collected into a string asserted empty; the full 1,080-row result is pasted in the PR body.
- [ ] AC-9 None of S1's files matches the three workflow path filters (empty intersections, commands in the PR body); the first line of the PR body states that merging this PR fires no release and no apply.
- [ ] AC-10 The PR body is authored by `soleur:ship` from the diff plus the durable artifacts, so the NOT-fixed list and the Decision notes live in `knowledge-base/project/specs/feat-one-shot-grep-q-wave-b-test-harness/` (`tasks.md` ship notes, `decision-challenges.md`) for it to fold in. The body carries `Ref #9217` (not `Closes`), no `[skip-deploy-fix-apply]`, the NOT-fixed list under a heading that avoids the ship-gate deny tokens, and, if skipped, the sentence "`scripts/test-all.sh --affected` was not run because the host is contended (load average N), so CI is the gate."
- [ ] AC-11 Learning files, one per non-obvious finding: (a) test-harness hits are about 20 percent data or executed strings and need classification before a transform, with the prototype numbers; (b) a `<=` ceiling at slack 0 is still satisfied by add-one-delete-one, and `_ts_re`/`GATED_PROD_ROWS` classify file-exact test rows as production unless widened; (c) a test replica of production logic (`test-tag-filter.sh`) goes stale when the carrier converts. Confirm each is non-obvious at work time; do not write filler.
- [ ] AC-12 `markdownlint-cli2` is clean on the plan, `tasks.md` and each learning; the discoverability command is re-measured under the 15 s cap after the selftest rows land.
- [ ] AC-13 `git diff --stat origin/main -- plugins/soleur/skills/work/SKILL.md .mcp.json` is empty.

### Post-merge (automated)

- [ ] AC-14 Tracker comment on #9217 with the before/after table, the per-tier counts, the command behind each number, and the NOT-fixed list; `Filed:` line, `semver:patch`, `type/chore` and `domain/engineering` labels (no `app:web-platform` label: nothing under `apps/web-platform` changes), Merge Danger with `Undo:` and `Blast Radius:`, Pipeline Tally, Changelog, Model Dissents.
- [ ] AC-15 `soleur:postmerge`: deploy-arm `find --wait`, then served, which must read CONTAINS. S1 fires no release and no apply, so the expected finding is that no run exists for the merge SHA, recorded as such.

NOT fixed by S1 (stated in the PR body and the tracker comment): the other 702 test-shaped sites (S2 to S7); the 23 wave A3 production sites; the five data lines in `.claude`; `scripts/test-all.sh` (S3); the producer-side join (S7); the guard's own blind spots (variable binary, split-line pipes, `| head`, `.md` fences, `.ts`); #9638 and #9639; the add-one-delete-one hole in the five glob rows whose slices have not landed.

Series (checked at S7): the codemod and its selftest gone, no `<=` glob row left, `grep -c -e 'grep-q-drain-codemod' .claude/hooks/grep-q-pipe-guard.test.sh` prints 0, `PRODUCER_JOIN` pins the derived site set.

## Test Scenarios

- Given `printf '%s' "$o" | grep -qE 'a|b'`, when `apply` runs, then the line is `printf '%s' "$o" | grep -cE >/dev/null 'a|b'` and `verify` accepts it.
- Given `x | grep -eq y` (`q` is the pattern of `-e`), then `apply` refuses and lists it; the line is unchanged.
- Given `x | grep -m1 P`, then it is routed to the hand queue as H-m.
- Given a quoted hook-input line (`run_case "D26" 'while ps | grep -q foo; do ...' deny`), then `apply` refuses it as data.
- Given a quoted-delimiter heredoc body and a `<<<` here-string line, then the heredoc body is refused and the here-string line is not mistaken for a heredoc opener.
- Given a line already converted, when `apply` runs again, then 0 lines change.
- Given an empty diff, when `verify` runs, then exit 3 and a message that nothing was verified.
- Given the hand-edit row for `test-tag-filter.sh`, when the first matching tag is on line 2, then the helper returns it (a first-line-only reader fails the row).
- Given a stub of `gh` that drains stdin on `--body-file -` (S7), when a delayed `printf` writes after the stub starts, then the pipeline status is 0 under `pipefail` with SIGPIPE ignored; with the non-draining control it is 1.

## Risks and Sharp Edges

- **A classifier error converts data, and `verify` cannot see it** (a mis-converted data line still equals `transform(removed)`). Mitigations: two independent classifier opinions that must agree for T0; refuse on unsure; the printed tier reasons; the per-suite pair run; the data list above is the first thing a reviewer reads. The hook-input fixtures are the worst case (a changed fixture can silently test a different input), which is why a green suite alone is not accepted as evidence for them.
- **Known surviving mutant: add-one-delete-one.** A `<=` ceiling at slack 0 is satisfied by moving a hit between two files under the same glob row (net count unchanged). It stays open for every `<=` row until its slice lands and for the `.claude` and `scripts/test-all.sh` residuals until S7 decides on file-exact rows; it is listed here, not claimed as covered.
- **Producers now run to EOF.** Wall time can rise where a producer is a full SUT run. The pair run records per-suite wall time; a suite that grows noticeably is listed in the PR body.
- **A pinned source text.** Any suite that pins the text of a converted test file would break; the ratchets that read test text (fixture-relative, fixture-dir-operand, fixture-cd-containment, `lint-shell-capture-exit` baseline keyed on path, class and normalized text) are run, and the prototype passed the first three. The capture-exit baseline holds no pipe-fed `grep -q` line from the 194 files (its five `grep -q` rows are file operands).
- **Merge triggers.** S5 and S6 fire a release, S6 a production apply; S1 to S4 fire neither. Do not use `[skip-deploy-fix-apply]`: it is irrelevant to these paths and the brief forbids it.
- **The ledger table is a shared hot spot.** Merge the slices in order; resolve a one-line conflict by hand; never re-sync a BEHIND branch mid-flight; keep pushes minimal while the queue is saturated.
- **`scripts/test-all.sh`.** A diff to the runner degrades local `--affected` to the full battery (a registration-only diff is exempt, a conversion is not). Stated in S3's body.
- **Verify the verifiers.** Two research-agent claims were wrong (see the reconciliation table); every `file:line` and every count in this plan was re-read or re-run. Read rc files, not completion notifications; do not start a second `git commit` while a hook is running.
- A plan whose `## User-Brand Impact` is empty, holds only `TBD`/`TODO`/placeholder text or omits the threshold fails `deepen-plan` Phase 4.6; this one declares `aggregate pattern`.

## Dependencies and References

- Tracker #9217 (this series); #7376, #6601, #7005, #7432 (related); #7797 (xtrace lint: comment only if a touched file enters its scope, which S1 does not); #9482 (only if a slice changes an ejection-class fact, expected in S7); #9638 and #9639 (not fixed).
- Merged: #9213, #9525, #9554, #9587, #9632, #9708. Draft PR #9720 (this branch).
- Guard: `.claude/hooks/grep-q-pipe-guard.test.sh` (header, `SWEEP_DEFERRALS`, `SWEEP_PROBE_CHECKS`, `GATED_PROD_ROWS`, `_ts_re`).
- Prior plans: `knowledge-base/project/plans/2026-10-05-fix-pipefail-early-exit-grep-q-sweep-plan.md`, `knowledge-base/project/plans/archive/20261006-132616-2026-10-06-fix-pipefail-early-exit-wave-a2-infra-ci-plan.md`.
- Workflows read for triggers: `.github/workflows/web-platform-release.yml`, `.github/workflows/apply-web-platform-infra.yml`, `.github/workflows/apply-deploy-pipeline-fix.yml`, `.github/workflows/ci.yml` (`lint-bot-statuses`).
