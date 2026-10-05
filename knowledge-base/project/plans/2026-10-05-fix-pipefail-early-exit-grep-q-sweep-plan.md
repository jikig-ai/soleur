---
title: "fix: sweep pipe-into-early-exit-grep sites repo-wide and widen the guard (PR-1: scripts, plugins, guard)"
date: 2026-10-05
slug: pipefail-early-exit-grep-q-sweep
branch: feat-one-shot-merge-queue-pipefail-sweep
issue: 9217
lane: cross-domain
type: fix
priority: p3-low
domain: engineering
requires_cpo_signoff: false
brand_survival_threshold: aggregate pattern
---

# fix: sweep pipe-into-early-exit-grep sites repo-wide and widen the guard (PR-1: scripts, plugins, guard)

Ref #9217, #7005, #6601, #7376, #9482 (umbrella; ADR-270 stays `adopting`). Draft PR #9554.
PR bodies use `Ref #N`, never `Closes #9482`. No new issue is filed: evidence goes onto #9217, #7005, #6601 and #7376.

Spec lacks a valid `lane:` (no spec.md exists for this branch): defaulted to `cross-domain` (fail-closed).

## Overview

Merged PR #9525 (c95101f60f, 2026-10-05) took one defect class to zero in three suites: a bash pipe whose reader
(`grep -q`) exits before its writer finishes, under `set -o pipefail`. The writer takes SIGPIPE (rc 141), or EPIPE
(rc 1) where SIGPIPE is ignored, as on the CI runner. A match then reads as a miss, and a negated or `&&`-chained site
reads as a false pass. This plan is **PR-1 of a subsystem split** and covers work items 1 and 5 of the brief only:

1. the repo-wide sweep (#9217, #6601, #7005), taken in waves by subsystem, of which PR-1 is the first wave
   (production scripts under `scripts/`, `plugins/`, `apps/web-platform/scripts/`, `apps/cla-evidence/`);
2. the guard blind spots listed in the header of `.claude/hooks/grep-q-pipe-guard.test.sh` (wrappers, flag order,
   `| head`), closed where a regex can close them and documented, with measured counts, where it cannot.

The remaining items (2 e2e ejections, 3 live-verify rail, 4 lint-bot-statuses, 6a local ratchet runner, 6b
affected-paths-only cheap CI path, 6c JOBS=1 stopgap) are separate follow-up PRs, each with a verified-against-main
status under `## Follow-up PR Register`. They are not planned in depth here.

**The headline finding is scope.** The tracker titles cite "41 production and 148 test-harness sites". Those figures
come from the July probe and cover `apps/web-platform/infra/` only. Measured on this branch today the repo-wide figure
is **1,117 code lines** (303 production in 123 files, 814 test-harness in 194 files), about seven times what the titles
suggest. The guard's "pinned set" model (one array entry per file, a pin count, an affected-paths entry) does not scale to
300 files, so this plan replaces enumeration with a derived population plus a shrink-only deferral list (see Proposed
Solution).

## Research Reconciliation: brief and trackers vs measured reality

| Brief or tracker claim | Reality (command in Research Insights) | Plan response |
| --- | --- | --- |
| "tracker titles cite roughly 41 production and 148 test-harness sites" (#6601) | Infra-only, July, different normalisation. Today `bash apps/web-platform/infra/scripts/sigpipe-triage-feasibility.sh` reports infra production 75 / 19 files, test-harness 50 / 14 files. Repo-wide, code lines outside `knowledge-base/` and `*.md`: **1,117** (303 production, 814 test) | Phase 0 re-derives and the ledger reconciles to the guard's own count; scope is split by wave |
| ".github/ runner: SIGPIPE ignored, so the defect is absent in CI" (audit `2026-07-17-sigpipe-guard-triage-feasibility.md` row "inherited SIG_IGN: producer rc 0, CORRECT") | Contradicted by PR #9525's own evidence: under an ignored SIGPIPE a builtin `printf`/`echo` writer returns rc 1 (EPIPE) and `pipefail` still promotes it; three suites flipped on the CI runner | Phase 5 appends a corrected row to the audit and records a learning |
| "size is NOT a bound" (brief) vs "needs more than the 64 KiB pipe buffer" (#7005, #7432) | The brief is right (3-line `git log` producer, a few-KB `echo`). #7005's 2026-09-27 comment already measured ~4 KiB for stdio producers | Header of the guard already carries it; the plan only keeps it consistent |
| "guard blind spots: wrappers, flag order, `\| head`" | Measured on 1,499 shell and workflow files with a quote-aware tokenizer: wrappers **6** real sites (all `LC_ALL=C grep -q`), brace-wrapped `{ grep -m1 ...; }` **4**, backslash-continued pipe **1**, flags after a flag-with-argument or after the pattern **0** real (49 tokenizer hits were all quoted text), `\| head -N` about **937** stages, `\| awk ... exit` 58, `\| sed ...q` 3, `\| read` 7 | Regex closes wrappers, braces, long flags and `-e PAT -q` order (+10 sites, `scan_sweep` only). `\| head`, multi-line awk, `sed q`, `read` and the one continued pipe stay documented residuals with these counts (the continued pipe is converted by hand) |
| "item 6a: single local ratchet command" | A diff-reachable pre-push lane already exists: `scripts/pre-push-ratchet-lane.sh` (issue #9400, PR #9409, 12 members, `--print-members`, wired in `lefthook.yml`). It is deliberately narrow; 33 suites mention `ratchet` | Not folded into PR-1 (decision below); the remaining delta is a `--ratchets` selector inside `scripts/test-all.sh`, a machinery path |
| "an open empty draft PR #9552 is a live sibling session probably on item 6b" | Confirmed: branch head is the init commit `d07a3eaaa9`, zero files, last updated 17:51Z | 6b left to it; PR-1 edits none of the runner/machinery files (AC-9) |
| "the sibling e2e font/login-poll PR merged" | Confirmed: #9523 = c35116046b; merge_group run 37348057569 (PR #9523) concluded `success` | Item 2 status below |

## Research Insights

### Premise Validation (Phase 0.6)

Checked: #7376, #9482, #9217, #6601, #7005, #7432, #8785, #9170, #9167, #8022, #7969, #7215, #5634 are all OPEN (`gh issue view`).
PRs #8866, #9033, #6998, #7035 are MERGED. PR #9525 and #9523 are merged on `origin/main`. PR #9552 is an OPEN empty draft.
`scripts/pre-push-ratchet-lane.sh`, `scripts/lint-guard-contract.py` and `apps/web-platform/infra/scripts/sigpipe-triage-feasibility.sh` exist on this branch.
Stale in the brief: none. Stale in the trackers: the 41/148 figures (scope), "defect absent on the CI runner" (mechanism), and
#8785/#9170 are fixed in code by #9523 but still open (item 2). ADR corpus grep for the mechanism: ADR-170 (errexit capture in `run:`
steps) and ADR-262 (path-gated batteries) are relevant to constraints, none rejects a derived zero guard.

### Property List and Cut List (Phase 0.6b)

Properties (observable outcomes):

- **P1** No tracked, non-deferred shell code contains `producer | grep` with an early-exiting reader, so a match cannot read as a miss.
- **P2** A new instance cannot land in a swept subtree, and a deferred subtree can only shrink.
- **P3** The guard sees the spellings that exist in this repo and a line regex can close (wrappers, braces, long flags, argument-taking flags) and its blind spots are listed with measured counts.
- **P4** The producer-side form's population is measured, not asserted.

Cut List (mechanism, property it would buy, what already covers it):

| Mechanism | Property | Why cut |
| --- | --- | --- |
| One `FILES_*` array entry, pin count and affected-paths entry per swept file (the header recipe) | P2 | A derived `git grep` pathspec covers every tracked file by construction; avoids a 300-entry array and an edit to `scripts/lib/test-affected-paths.sh`, which arms every PR-gated battery (about 2,900 s of runner time per push, ADR-262) |
| A baseline or high-water file for the sweep (`lint-shell-capture-exit.baseline.txt` precedent) | P2 | A baseline grandfathers; zero plus a shrink-only deferral list buys the same and adds no file |
| A new lint script with a `-live` always-on registration | P2 | The guard exists, is registered through the `.claude/hooks/*.test.sh` glob, and runs in about 1 s |
| A `\| head -N` ratchet | P3 | Buys no property: about 937 stages, most on bounded producers; a count ratchet churns on every legitimate site. Documented residual instead |
| Committing the transformer under `scripts/` | P1 | Needs an orphan-test registration (a machinery edit). Kept as a spec artifact for the later waves |
| Folding item 6a (local ratchet runner) into PR-1 | none in this PR | The lane exists; the delta edits `scripts/test-all.sh`, which the sibling #9552 is working near |

### Value-proposition measurement (Phase 0.6c)

No cost or speed saving is claimed. The justification is correctness of a class that flipped three suites on 2026-10-05
and cost a CI cycle each time (#7376 carries 68 comments). The only measured cost is the guard's: `bash
.claude/hooks/grep-q-pipe-guard.test.sh` takes 0.96 s today and `git grep` of the pattern over the whole repo takes 0.88 s,
so a derived pass adds about 1 s.

### Measurements (re-derive at work start; counts drift)

```bash
P='(^|[^|])\|&?[[:space:]]*grep([[:space:]]+-[A-Za-z]+)*[[:space:]]+(-[A-Za-z]*[qm][A-Za-z0-9]*|--quiet|--silent|--max-count)'
git grep -nE "$P" -- ':!knowledge-base' ':!*.md' | grep -vE ':[0-9]+:[[:space:]]*#' | wc -l     # 1117 on branch HEAD 437ae87036
```

Classifier for test harness: path matches `\.test\.sh$|/tests?/|^tests/|/test-[^/]*$|-test\.sh$|^e2e`. Cross-checked with a quote-aware
tokenizer over `git ls-files '*.sh' .github/workflows/*.yml ...` (1,499 files): 1,108 guard-visible early-exit grep stages (the 9-line
difference is `.ts`/`.js`/`.tf`/`.template` hits and two-pipe lines), so the two methods agree within 1%.

| Root | Production sites / files | Test-harness sites / files |
| --- | --- | --- |
| `scripts/` | 86 / 43 | 127 / 47 |
| `plugins/soleur/` | 63 / 28 | 202 / 61 |
| `apps/web-platform/` (not infra) | 15 / 10 | 97 / 12 |
| `apps/cla-evidence/` | 1 / 1 | 0 |
| `apps/web-platform/infra/` | 92 / 20 | 88 / 26 |
| `.github/` (workflows 42/18, scripts 3/2) | 45 / 20 | 10 / 6 |
| `lefthook.yml` | 1 / 1 | 0 |
| `tests/` | 0 | 183 / 24 |
| `.claude/` (hooks are already at zero; these are hook test suites) | 0 | 107 / 18 |

Context of the 303 production sites: 259 sit in a condition (`if`, `&&`/`||`, `!`), where the race inverts the verdict silently; 44 are bare
pipelines. About 266 are in files that set `pipefail`; 16 production files do not (the early exit is harmless there, but a sourcing caller can
set it, so the guard asserts zero regardless). Producer shape of PR-1's 164 scripts/plugins sites: `printf`/`echo` of a variable 113, a command
producer about 40, multi-stage 11. Six production files are named in a PR-gated battery's relevance array in `scripts/lib/test-relevance-paths.sh`: `ci.yml` (machinery,
`PR_GATE_MACHINERY_PATHS`) and five that arm a battery when edited (`workspaces-luks-verify.yml`, `git-data-cutover.yml`,
`apply-web-platform-infra.yml`, `apply-deploy-pipeline-fix.yml`, `apps/web-platform/infra/cloud-init.yml`); none is in PR-1's roots by exact path. Two
directory entries exist (`.github/workflows`, `apps/web-platform/`), so Phase 0 re-runs the check including them and records which batteries
and test legs the diff arms (the `apps/web-platform/scripts/` edits may select the web-platform leg, which is expected).

### Institutional learnings applied

- `2026-10-05-a-reader-that-exits-early-flipped-three-suites-and-the-stub-had-to-read-too.md`: forms, producer-side form, the membership-test-reads-the-array-body lesson, derive expected counts from the guard's own PATTERN and assert before write, a mutant must be a working weaker program, and the ratchet list must be enumerated with `grep -l`, not recalled.
- `2026-07-18-pipefail-grep-q-early-match-sigpipe-flakes-drift-guards.md`, `2026-09-23-my-sigpipe-regression-guard-pinned-the-file-size-not-the-cause.md`: size is not the pin.
- `2026-10-05-i-told-the-operator-a-count-was-wrong-and-my-grep-had-counted-a-comment.md`: re-derive every reported count by a second method and by listing, never `grep -c` alone (done above).
- `2026-09-23-non-required-did-not-mean-decoupled-and-my-canonicalizer-rewrote-its-own-evidence.md`: a mechanical rewrite cannot tell a USE from a MENTION; the transformer must refuse comments, heredoc prose and quoted strings and list them.
- `2026-07-27-the-subshell-bug-i-was-fixing-bit-me-three-more-times.md`: `x=$(fn)` loses state; matters for the capture form.
- `2026-10-01-a-grep-q-in-a-pipefail-chain-made-the-trigger-miss-its-own-bug-class.md`: a file operand is the safest form when the producer is `cat FILE`.
- Audit `knowledge-base/engineering/audits/2026-07-17-sigpipe-guard-triage-feasibility.md`: heredocs inside Terraform `remote-exec` and cloud-init `runcmd` are payload, not prose; five classifier bugs in the audit itself.

## Open Code-Review Overlap

Queried `gh issue list --label code-review --state open` (87 issues) against PR-1's production file set and the guard:

- #8859 (`plugins/soleur/skills/review/scripts/emit-review-trailer.sh`, a debt-ledger entry): **Acknowledge**. Different concern; the sweep touches one pipe in that file.
- #3595 (`scripts/audit-bot-codeql-coverage.sh`, YAML-aware parser): **Acknowledge**. Different concern.
- #3364 (`apps/web-platform/scripts/run-migrations.sh`, role ownership guard): **Acknowledge**. Different concern.
- #8593 (`scheduled-inngest-health.yml`), #3829 (`pr-quality-guards.yml`), #2197 (`server.tf`): not in PR-1; they sit in wave A2 (infra and CI). **Defer** to that PR's overlap check.

## Problem Statement

`producer | grep -q P` under `pipefail` reports failure on a successful match whenever the writer is unfinished when `grep` exits. The guard
`.claude/hooks/grep-q-pipe-guard.test.sh` holds three small pinned sets at zero; the other ~1,100 sites are unpinned, the guard cannot see
wrappers or brace-wrapped readers, and the producer side of the pipe (a stub or a program that never reads the `printf |` it is fed) is
invisible to any line search.

## Proposed Solution

### Conversion forms (decision table, applied per site; a scratch transformer does the mechanical class, the rest is a hand queue)

| Site shape | Form | Why |
| --- | --- | --- |
| `echo "$V" \| grep -q P`, `printf '%s\n' "$V" \| grep -q P` (single variable) | `grep -q P <<<"$V"` | No pipe, no subshell, repo convention since #6998. About 113 of PR-1's 165 sites |
| `printf '%s' "$V" \| grep -q P` (no trailing newline) | here-string only when the pattern cannot match an empty line; otherwise hand queue | `printf '%s' ""` writes no line, `<<<""` writes one empty line, so `grep -q '^$'`, `grep -q ''`, `-vq` and `-qx ''` flip. Measured: no PR-1 site has such a pattern, so the hand queue for this case is expected to be empty |
| `cat FILE \| grep -q P`, `head -1 FILE \| grep -q P` | `grep -q P FILE` / process substitution | A file operand has no upstream to take the signal |
| output-consuming early exit (`... \| grep -m1 P` and `grep -oEm1`, 4 sites: `monitor-pr-checks.sh`, `check-backstop-revision.sh`, `git-data-reboot-evidence-landed-8210.sh`, `watch-live-verify-pass.sh`) | `grep -m1 P <<<"$v"` (or `< <(producer)` for a pure producer) | The site reads grep's output, so no `>/dev/null` drain form applies; no pipe means no race |
| pure read-only producer inside a condition (`git log`, `git diff`, `jq`, `sed`, `nft list`, `ip addr`, `docker ps`) | `grep -q P < <(producer)` | Keeps the one-line shape; the producer is a filter with no side effect |
| every BARE pipeline under `set -e` (about 44 in production), a producer with side effects, a needed exit status, or a function that mutates state (`ssh`, `gh api` writes, `terraform`, anything run as `x=$(fn)`) | capture, then `grep -q P <<<"$out"` (hand edit) | Process substitution is not waited for and drops the producer status: `{ echo x; exit 3; } \| grep -q x` exits 3 while `grep -q x < <(...)` continues with rc 0, so a bare site would silently stop failing. A captured function loses state |

Gotchas the transformer must encode and the working ledger must report: a here-string needs a writable temp file when the body exceeds the pipe
capacity (bash before 5.1 always), so a read-only or full `/tmp` turns a match into a silent miss; under an ignored SIGPIPE an external producer in a
procsub can print `write error: Broken pipe` to stderr, which matters for suites that assert on stderr; `-q` is also an early exit by design on an
intentionally unbounded producer, which stays and gets the `# sigpipe-demo: intentional` marker; a site inside a comment, a quoted string, an LLM
prompt template literal (`drain-labeled-backlog.workflow.js` lines 181 and 184) or a heredoc that merely documents the shape is DATA, not converted, and
carries the marker (Phase 0 measures how many; the heredoc probe over PR-1's files found none). A drain form (`producer | grep -E P >/dev/null`) for a
non-bash script is NOT in the table: all 79 PR-1 `.sh` files carry a bash shebang, so it has no site today and is added only when a wave meets a real
`#!/bin/sh` site.

### Guard shape: derived population, zero, per-entry ceilings on what is deferred (replaces per-file pinning for the sweep)

The existing four named passes (`FILES_7024`, `FILES_8664`, `FILES_8855`, `FILES_7376`) stay untouched and keep the V1 pattern. A new pass,
`scan_sweep <root>`, derives its population with `git -C <root> grep --no-index` over a named pathspec constant (every shell-bearing file by
extension minus the deferral entries), strips comment lines and marked lines, and asserts zero. `--no-index` is what lets the probe plant scratch files
that are not tracked (a plain `git grep` reads tracked files only, so a scratch-file mutation would read "0 hits" and look like a pass). It is built by
giving `scan_pipes` a pattern and an optional root rather than adding a fourth near-copy beside `scan_scorers`, `scan_pipes` and `scan_7376`.

The deferral table names the subtrees not yet taken to zero, one row per entry: `path-or-glob | ceiling | tracker`. The first rows are wave A2
(`apps/web-platform/infra`, root `.github`, `lefthook.yml`) and the wave-B test-harness globs. The guard asserts per row: hits are at or below the
ceiling (a deferred subtree cannot grow while its wave is pending), hits are at least one (a row whose subtree reached zero is reported stale and must
be deleted, so a wave deletes its own row in the PR that converts the subtree), and the tracker token is present. It prints one `DEFERRED: <path> (N hits,
ceiling M, #tracker)` line per row on every run so the residual debt is visible in every CI log. There is no separate length pin: adding or removing a row
is already a one-line reviewable diff. Every entry is derived from the pathspec, not from the classifier regex used for the measurements (a git glob for
`test-*` can diverge from the regex), and Phase 0 asserts the two agree file by file and lists production-looking files that fall inside a deferred glob.
This is the ratchet without a baseline file.

Coverage is by file extension (`*.sh`, `*.yml`, `*.tf`, `*.template`, `*.js`), not by "shell-bearing": an extensionless script with a shebang would
escape. Today there are zero such hits outside two `.ts` test files, and the limit is stated in the guard header. Local `--affected` selects the guard
only for edits under `.claude/hooks/`, `plugins/` and the named infra suites, so a new bad pipe in `scripts/` is caught by CI and by running the guard
directly (Phase 5), not by a local `--affected` run.

### Item 5: what the regex closes

A prototype, measured against 21 bad and 11 good probe lines (all 21 matched, 0 false positives) and against the repo (adds exactly the
10 wrapper and brace sites listed below, loses none), extends the leading and flag parts of `PATTERN`. It applies to `scan_sweep` only (the named
passes keep V1, so none of them can turn red on a spelling they never carried):

```bash
LEAD='(^|[^|])\|&?[[:space:]]*(\{[[:space:]]+|\([[:space:]]*)?'
WRAP='((command|builtin|exec|env|nice|stdbuf[[:space:]]+-[a-zA-Z]+|timeout[[:space:]]+[0-9a-z.]+)[[:space:]]+|[A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+)*'
BIN='(\\|/[^[:space:]]*/)?(e|f)?grep'
ARG='([[:space:]]+(-[A-Za-z0-9]+|--[a-z-]+(=[^[:space:]]+)?|-[efABCm][[:space:]]+[^[:space:]]+))*'
EARLY='[[:space:]]+(-[A-Za-z]*[qm][A-Za-z0-9]*|--quiet|--silent|--max-count)'
```

Closed: `command|env|exec|timeout|nice|VAR=x` wrappers without their own flags, `\grep`, `/usr/bin/grep`, `egrep`/`fgrep`, a reader inside `{ }` or `( )`,
long flags, and `grep -e P -q` / `-A1 -q` order (the brief names "flag order"; measured 0 real sites, the 49 tokenizer hits were quoted text, so the
alternative is kept minimal and `--regexp` is not added). Not closable by a line regex, documented in the guard header with the measured counts:
`| head -N` (about 937 stages; it is dangerous where the site is bare under `set -e` and the producer writes more than a few KB, and harmless on a short
single-write producer), a multi-line awk program (58 single-line awk-exit stages are visible to `PATTERN_AWK_EXIT` in the named passes only), `| sed ...q` (3),
`| read` (7), a pipe split across lines (1 site, `apps/web-platform/scripts/check-workspace-members-write-sites.sh`, converted by hand), a reader reached
through a variable (`"$GREP" -q`, 0 sites), wrappers that take their own flags (`env -i`, `nice -n 10`, `timeout -s KILL 5`, `/usr/bin/env grep`, `sudo`,
`xargs`; 0 sites), a pipe into a function that wraps `grep`, and a procsub-out reader `cmd > >(grep -q ...)` (0 sites). Known false positive: a quoted
`-e` pattern that itself contains a space and the text `-q` (`grep -e "a -q b"`; 0 repo hits). A join pre-pass for the continued pipe was cut: it buys one site, cannot run through
`git grep`, and would change line numbers under the comment filter.

The 10 new sites: 6 wrappers (5 test files, `scripts/lint-migrated-rule-ids.sh:200`) and 4 braces (`test-tag-filter.sh` x3,
`.github/workflows/reusable-release.yml:294`, where `|| [ $? -eq 1 ]` swallows rc 1 but not 141, so it is a real instance of the class
in a release workflow, deferred to wave A2). Only `scripts/lint-migrated-rule-ids.sh` lands in PR-1.

### Producer-side form (separate: measured here, joined and fixed with the test harness in wave B)

A stub that never reads the stdin a `printf |` feeds it takes the signal on the writer side; a line search over the test file cannot see
it. Population measured today: 28 production pipes from `printf`/`echo`/`cat` into a stubbable verb (`ssh`, `docker`, `doppler`, `gh`, `curl`,
`sudo`, `nft`, `terraform`); the tests that stub those verbs create 83 `gh`, 83 `curl`, 45 `doppler`, 22 `systemctl`, 18 `logger`, 18 `docker`,
8 `terraform`, 5 `sudo`, 4 `nft`, 1 `ssh` stub. PR-1 posts these figures on #9217 and does nothing else with them: the join (production site to the
owning suite's stub, does the stub drain?) and the stub fixes both live in test files, so they are wave B's first phase, using the `drain` idiom PR
#9525 introduced.

## Technical Approach

### Phases

**Phase 0: re-measure and reconcile (read-only).** Re-run the measurement commands against the guard's own derived pathspec and a scratch
working table (not committed). Required outputs, each asserted before any write: (a) the count of the pathspec-derived non-deferred set equals the
Research Insights classifier set file by file, and production-looking files inside a deferred glob are listed (the pathspec cannot express `/test-[^/]*$`);
(b) the V2 total is V1 plus the wrapper site; (c) non-code hits (comments, quoted strings, prompt literals, heredoc payload) are counted and either
reworded, marked, or named in a second shrink-only exclusion list if there are more than a handful; (d) the count of non-bash scripts (expected 0 `.sh`);
(e) the armed-battery and test-leg set the diff selects, including the two directory entries in `scripts/lib/test-relevance-paths.sh`, and the
`--affected` selected-suite count with a CI wall-clock estimate for the PR body. PR-1's conversion set also includes the nested
`apps/web-platform/.github/workflows/constraint-gates.yml` (1 site), which the root `.github` deferral entry does not match and which is the generated
copy of `constraint-gates-workflow.template`, so the two are converted together.

**Phase 1: guard first, red.** In `.claude/hooks/grep-q-pipe-guard.test.sh`: add `scan_sweep`, the deferral table with its three checks and printed
lines, `PATTERN_V2` (added to the compile pre-check loop), and the probe fixtures and mutation-checked rows of the Guard Contract. Expected result
before any conversion: the derived pass FAILs on the roughly 165 sites. This is the RED state (`cq-write-failing-tests-before`). Commit it first.

**Phase 2: convert PR-1's roots, one commit per root.** The commits are in this order: `scripts/`, `plugins/soleur/`, `apps/web-platform/` (scripts and
the nested workflow), `apps/cla-evidence/`, then the commit that empties nothing but flips the guard to green. Each commit is individually revertable
and bisectable, and the verdict-bearing files (`check-web-host-escrow-config.sh`, `zot-restart-loop-alarm.sh`, the plugin delivery canary, the
policy-gate hooks `unkept-promise-hook.sh` and `stop-hook.sh`) are called out in the PR body. A scratch transformer does the mechanical class
(`echo|printf '%s\n' "$V" | grep -q P`); the rest is hand edits. Verification per commit: (a) an inverse transform over the changed lines reproduces
the original line for the mechanical class (assert-before-write, count equals the Phase 0 table); (b) `bash -n` on every changed file, `shellcheck`
and `actionlint` where installed; (c) each changed production script that has a registered suite has identical pass/fail counts before and after, and
the contention run (four copies, each isolated in its own scratch copy of the worktree-relative temp paths, collected by pid) is limited to the
hand-converted and verdict-bearing suites, not all 80; (d) the two constraint-scaffold `*.template` files, the generated workflow copy and the
`.workflow.js` file are read for what they emit before editing, and their parity tests are run.

**Phase 3: item 5 documentation.** Rewrite the header's "Not matched" paragraph into the measured closed/residual table above, keep a three-row
version of the conversion table in the header with the `# sigpipe-demo: intentional` marker syntax, add the one-sentence `| head` danger rule, make the
FAIL message print the one-line remediation (here-string for a variable, `grep -q P FILE` for `cat`, capture-then-here-string for side effects), and add
the V2 fixtures (keep the `||` must-not-match lines from #8866).

**Phase 4: producer-side hand-off.** Post the measured population above on #9217; the join and stub fixes are wave B's. No census in PR-1.

**Phase 5: evidence, learning, ratchets, one push.** Append one corrected row to the audit's SIGPIPE-disposition table (builtin writer under an
ignored SIGPIPE: rc 1, defect live on the runner); write one learning that links to that row instead of restating it (the scope was seven times the
tracker's figure; derived population with ceilings instead of pinning; the audit's "absent in CI" claim was wrong for builtin writers); post one
full evidence comment on #9217 (counts, wave plan, residual table, producer-side figures) and a one-line cross-link on #7005, #6601 and #7376; leave a
short note on the sibling draft PR #9552 that PR-1 edits `.claude/hooks/grep-q-pipe-guard.test.sh` and about 80 shell files and touches no runner or
machinery file. Before the push run every ratchet: `grep -lis ratchet scripts/*.test.sh scripts/lib/*.test.sh .claude/hooks/*.test.sh` (33 files today,
the brief's rule) and run each, plus `bash scripts/pre-push-ratchet-lane.sh`, `bash .claude/hooks/grep-q-pipe-guard.test.sh` directly (the local
`--affected` run may not select it), the orphan lint and `scripts/test-affected-kb-consumers.test.sh` (its baseline is regenerated with
`--write-baseline` only if a new `knowledge-base/` reference appears in a file a registered suite names; the fixtures added here avoid that
literal). Re-compare the armed-battery set against `origin/main` at ship time. Batch every fix into a single push.

### Waves (the split this plan applies)

| Wave | Scope | Sites / files | Why separate |
| --- | --- | --- | --- |
| **PR-1 (this plan, #9554)** | guard rework, item 5, every production file outside the A2 entries: `scripts/`, `plugins/soleur/`, `apps/web-platform/` (scripts and the nested `.github/workflows/constraint-gates.yml`), `apps/cla-evidence/` | about 165 / 82 (V1 count; V2 adds 1 wrapper site, 1 continued pipe is converted by hand) | homogeneous mechanical diff, no machinery path, no exact-path battery armed |
| A2 | `apps/web-platform/infra/` and `.github/` production, `lefthook.yml` | about 138 / 22 | sensitive path (host scripts, cloud-init, release workflows), arms five batteries and `ci.yml` is machinery: batch with 6b |
| B (split by root when it starts) | test harness (plugins 202, tests/ 183 + scripts 127, apps + infra + .claude + .github 300) | 814 / 194 | the producer-side join and stub fixes live here; `.claude/hooks/*.test.sh` carry the shape as fixtures and need the marker, and the guard exempts itself by that marker when B lands |

PR-1 exceeds the Scope Check thresholds on subsystem roots (6) and files (about 85); the split into A2 and B is the response. PR-1 stays one PR
because every file in it gets the same rewrite and the same guard flip, and it is commit-structured per root (Phase 2), so each root is revertable and
bisectable without more deferral rows ever reaching `main`. Why production before the test harness: no measured flake came from production code (the
#7376 flips were test suites, now at zero), so this order is not incident-driven. It is chosen because production sites carry the fail-open direction
(a verdict-bearing gate that passes vacuously), PR-1's slice is small and clean (no machinery, no battery armed by exact path), and the test harness
is 814 sites that overlap sibling sessions' suites.

## Alternative Approaches Considered

| Approach | Why not |
| --- | --- |
| Per-file pinning (`FILES_*` + `PIN_*` + affected-paths entries) for all 300 files | Unmaintainable and forces an edit of `scripts/lib/test-affected-paths.sh` (full battery on every push). The derived pass has the same strength. Cost accepted: locally, `--affected` selects the guard only for `.claude/hooks/`, `plugins/` and the named infra suites; CI runs it in full |
| Baseline allowlist (`*.baseline.txt`) | Grandfathers the class; the guard header already rejects it ("asserts nothing on day one") |
| Blind convert `\| grep -q P` to `\| grep -E P >/dev/null` everywhere (#6601 option 1) | Keeps the pipe, so no here-string or procsub gotchas, but hangs on an unbounded producer and cannot serve the output-consuming `-m1` sites; not needed today (every PR-1 `.sh` is bash), held in reserve for a real `#!/bin/sh` site |
| Convert everything in one PR | 1,117 sites / 300 files, several battery-arming, plus 814 test sites that overlap sibling sessions' suites |
| Regex `\| head` rule | Cannot see the producer; would either flag 937 sites or none (Cut List) |

## User-Brand Impact

- **If this lands broken, the user experiences:** a production-facing script that gates something (an egress or escrow check, a release or deploy helper, the plugin delivery canary, a hook that decides whether a prompt is sent) starts reporting the wrong verdict after conversion, or a plugin helper fails on a user's machine because a here-string temp file could not be created; the visible symptom is a failed run or a skipped check, not data loss.
- **If this leaks, the user's workflow is exposed via:** no secret or user data is read or written by the change itself; the exposure vector is a fail-open conversion of a security-adjacent check (for example `scripts/check-web-host-escrow-config.sh` or a redaction scan) that then passes vacuously.
- **Brand-survival threshold:** `aggregate pattern`
- **Threshold decision (challengeable):** not `single-user incident` because no single conversion exposes one user's data and every converted site is one of ~165 equivalent rewrites verified by an inverse transform; not `none` because a systematic transformer bug would repeat across ~165 sites, some of them verdict-bearing (`scripts/check-web-host-escrow-config.sh`, `scripts/zot-restart-loop-alarm.sh`, the plugin delivery canary). Measured: 0 of PR-1's 82 conversion files match the canonical `SENSITIVE_PATH_RE` (`apps/*/infra/`, release and deploy workflows are all in wave A2), so no `threshold: none` scope-out is needed here; wave A2's plan takes the sensitive-path obligations.

## Observability

```yaml
liveness_signal:
  what: the grep-q-pipe-guard suite runs in the CI test group on every PR and on every merge_group run, and prints a PASS line per pass
  cadence: per PR and per merge_group run (locally, run directly before each push; the pre-push lane does not carry it until follow-up 6a)
  alert_target: the required test check turns red on the PR, which blocks merge and ejects a queue entry
  configured_in: scripts/test-all.sh SUITE_GLOBS entry '.claude/hooks/*.test.sh' (registration), .claude/hooks/grep-q-pipe-guard.test.sh (the passes)
error_reporting:
  destination: CI job log of the test check (no Sentry surface: this is a repo-hygiene guard, not a runtime service)
  fail_loud: a FAIL line naming file, line and the forbidden shape, exit 1; an unreadable input or an empty derived population prints UNRESOLVED and exits 3
failure_modes:
  - mode: a new early-exit pipe lands in a swept subtree
    detection: the derived pass reports it as a FAIL line with file and line
    alert_route: required test check red on the PR
  - mode: the derivation returns an empty or truncated population (a pathspec typo, git missing) so the guard passes having scanned nothing
    detection: the pass asserts a size floor and one canary member per swept root, and exits 3 UNRESOLVED otherwise
    alert_route: required test check red on the PR
  - mode: a deferral entry outlives its subtree, or a deferred subtree grows while its wave is pending
    detection: the stale check fails when an entry carries no hit, and the ceiling check fails when hits exceed the recorded ceiling
    alert_route: required test check red on the PR
  - mode: a converted production script changes behaviour at runtime
    detection: the script's own registered suite (pass and fail counts compared before and after), and the contention run in Phase 2 for the hand-converted and verdict-bearing suites
    alert_route: required test check red on the PR; post-merge the scheduled workflows that run these scripts report through their existing issue-filing guards
logs:
  where: CI job logs of the test check; locally the stdout of the guard
  retention: GitHub Actions log retention
discoverability_test:
  command: bash .claude/hooks/grep-q-pipe-guard.test.sh
  expected_output: PASS: grep-q-zero-sweep-pass
```

## Guard Contract

### Guard 1 — derived sweep pass (zero, per-entry ceilings on what is deferred)

**Property.** No tracked, non-deferred file of a covered extension contains a pipe into an early-exiting grep outside a comment line or a marked intentional demo, and each deferred subtree's hit count can only fall.

**Assembly.** The population is derived, not listed: `scan_sweep <root>` runs `git -C <root> grep --no-index` over one named pathspec constant (covered extensions) minus the deferral table, in one function that every consumer calls, including the non-vacuity probe. The chokepoints the members flow through are (1) the pathspec constant, (2) the deferral table with its stale, ceiling and tracker checks, (3) the comment-and-marker filter shared with `scan_pipes`. A file added next month under a new directory is in the population without any edit; an extensionless script is not (stated limit). The scan is a line search, not a lexer: a heredoc payload and prose that merely names the shape are indistinguishable from code, so false positives are handled by the comment filter and the per-line marker, and a shape split across lines is a documented residual. The four existing named passes (`FILES_7024`, `FILES_8664`, `FILES_8855`, `FILES_7376`) are left as they are and keep V1 and their own patterns (`PATTERN_AWK_EXIT`, `PATTERN_PIPED_SCORER`).

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Append `echo "$x" \| grep -q p` to a scratch copy of a real PR-1 file, one per root (`scripts/`, `plugins/soleur/`, `apps/web-platform/scripts/`), scanned with `--no-index` | RED, one hit per root |
| 2 | Drop `*.sh` from the pathspec constant, or point the scan at an empty directory (the guard's own dispatch) | RED: UNRESOLVED exit 3 from the size floor and the per-root canary check, not "0 hits, PASS" |
| 3 | Add a second bad file under a brand-new directory after a compliant first (`tools/new/x.sh`, never named anywhere) | RED: the derived pass reports it |
| 4 | Append a bad line inside a deferred subtree whose row ceiling equals its current hit count | RED: ceiling exceeded; and a comment-only line appended there stays green |
| 5 | Keep a deferral row whose subtree has no hit | RED: stale deferral (a single check, no pin to confuse it) |
| 6 | Delete a deferral row while its subtree still has hits | RED: those hits now count |
| 7 | Put the bad line in a comment, on a marked line, and on a plain code line | comment and marked lines pass, the plain code line is RED (a test of the filter, not a loop property) |

Harness rows. Suite edit that must go RED: delete the `scan_sweep` call from the final aggregate (so the pass runs but is not scored) and the wiring probe must fail. Must-PASS non-canonical input: a fixture file whose only match is `a || grep -q p <<<"$x"` (the #8866 shape) with a trailing comment, differing from every probe line the original guard carried.

Anchor. The ceilings and the size floor are values stored in the same file as the check, so one commit can raise them with the check; this proves consistency, not integrity, exactly like the existing `PIN_*` values. What outside the commit must also move for a weakening to pass: a reviewer reads the deferral-table diff (one line per row), every row carries a tracker token, and every CI log prints a `DEFERRED:` line per row, so the debt cannot be raised silently. Locally `--affected` may not select the guard for edits under `scripts/`; CI and the direct run in Phase 5 are the backstop, and that is accepted.

### Guard 2 — widened pattern (blind-spot spellings)

**Property.** Every early-exit grep reader spelling that exists in the tracked tree (wrapper, brace or paren wrapper, long flag, an argument-taking flag before the early-exit flag) is matched by `PATTERN_V2` in `scan_sweep`, and the spellings a regex cannot close are listed with measured counts in the guard header.

**Assembly.** One pattern definition (`PATTERN_V2`) consumed by `scan_sweep` only, plus the probe fixtures extended in the existing `bad.sh`/`good.sh` style; the header table is the second place the property lives. The named passes keep V1 on purpose.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Revert `WRAP` to empty | RED: the `x \| LC_ALL=C grep -q p` and `x \| command env LC_ALL=C grep -q p` fixtures are no longer matched |
| 2 | Drop the brace alternative from `LEAD` | RED: the `x \| { grep -m1 -E v \|\| [ $? -eq 1 ]; }` fixture |
| 3 | Drop `--quiet\|--silent\|--max-count` from `EARLY` | RED: the long-flag fixtures |
| 4 | Drop the argument-taking-flag alternative from `ARG` | RED: the `x \| grep -e p -q` and `x \| grep -A1 -q p` fixtures |
| 5 | Widen `EARLY`'s class from `[qm]` to `[qmcv]` | RED: the false-positive fixtures `x \| grep -c p`, `x \| grep -v p` and `x \| { grep -oE p \|\| true; }` now match |
| 6 | Break `PATTERN_V2` so it does not compile (an unbalanced parenthesis) | RED: UNRESOLVED exit 3 from the compile pre-check, never PASS (a negated grep folds rc 2 into "no match") |

Harness rows. Suite edit that must go RED: change the expected fixture count in the aggregate condition by one. Must-PASS non-canonical input: a good fixture `x | grep -F -- "$m"` with a `--` terminator, which no original probe line used, scanned through `scan_sweep` only (`scan_scorers` carries `PATTERN_PIPED_SCORER`, which flags it by design).

Anchor. The pattern and its fixtures are in the same file, so one commit can weaken both; the measured repo-wide comparison in Phase 0 (V2 reports a superset of V1 and exactly the 10 wrapper and brace sites) is run outside the guard and recorded in the PR body.

## Follow-up PR Register

Each item is a separate PR, verified against `origin/main` at c35116046b on 2026-10-05. Not planned in depth here.

- **Item 1, waves A2 and B (the rest of the sweep).** Done on main: three suites and the guard's named passes at zero (#9525); `.claude/hooks` non-test code at zero (#6998). Remains: A2 (infra and CI production, about 138 sites, batched with 6b because `ci.yml` is machinery) and B1..B3 (814 test-harness sites, plus the producer-side join and stub fixes). Each wave deletes its deferral row.
- **Item 2, e2e ejections (#8785, #9170, #9167).** Done on main: #9523 vendored Inter through `next/font/local` (`apps/web-platform/app/fonts.ts`, guard `test/no-network-fonts.test.ts`), switched Playwright readiness from `port:` to `url:` on `/login` (180 s) and made the otp-login banner assertions select by text; merge_group run 37348057569 passed. #8785 and #9170 are fixed in code but still open (the PR used `Ref`, "to be closed with the CI e2e result"). Remains: close #8785 and #9170 with that evidence; #9167 is untouched (the plan of 2026-10-05 found its string is the mocked payload, so the cascade claim needs a comment, not a fix).
- **Item 3, live-verify rail (#8022, #7969, #7215, #5634).** Done on main: rail is `apps/web-platform/scripts/live-verify/run.ts` run by the `live-verify` job in `.github/workflows/web-platform-release.yml`; PRs #8092 (wait timeout diagnosable) and #8184 (seed) merged. Remains: all four open. #5634 and #7215 are old environmental CANT-RUN items; #7969 recurred (post-merge of PR #9315); #8022 is the live one (3 of 3 `FAIL`, "persisted but did NOT appear in the rail", after PR #9279; its 2026-10-05 comment says possibly a real regression since #9270, undiagnosed). Two things to reconcile at item-3 time: the rail runs post-deploy in the release workflow, not on `merge_group` (so the 2026-10-05 comment's "merge-queue runs" wording is loose), and the 2026-09-30 comment on #8022 calls the gate report-only while #5463 (closed) records a flip to blocking; read the job's `continue-on-error` before stating which.
- **Item 4, lint-bot-statuses.** Done on main: it is the advisory job at `.github/workflows/ci.yml` (about line 160), absent from `scripts/required-checks.txt`; the 2026-10-05 red was a deterministic content finding in the PR's own text (`lint-infra-no-human-steps.py`), it ejected nothing, and the last six main runs are green; #9523 added an advisory-red note to `plugins/soleur/skills/ship/references/merge-queue-dequeue.md`. Remains: no dedicated issue (adjacent: #7472, ship Phase 7 poll silent on non-required failures); nothing to fix, record in #9482 and close the question.
- **Item 6a, single local ratchet runner.** Done on main: `scripts/test-all.sh --affected` (the local default since issue #8322) runs diff-selected suites plus `ALWAYS_ON_SUITES`, and `scripts/pre-push-ratchet-lane.sh` (issue #9400, PR #9409, wired in `lefthook.yml`, `--print-members` lists 12 members, one conditional: `test-affected-kb-consumers`). Remains: no command runs exactly the `grep -lis ratchet` set; a `--ratchets` selector in `test-all.sh` is about 15 to 30 lines. **Decision: not folded into PR-1.** It is small in lines but it edits `scripts/test-all.sh`, a `PR_GATE_MACHINERY_PATHS` member (arms every PR-gated battery, about 2,900 s per push, and `--affected` is refused rc=4 while a sibling holds the gate), on the same runner surface as the sibling #9552. Until it lands, PR-1's AC lists the ratchets by command.
- **Item 6b, affected-paths-only cheap CI path.** Done on main: ADR-262 (#9324) path-gates the self-test batteries on `pull_request`; e2e has a classifier gate (`scripts/ci-e2e-classify.sh`); the test legs still run `test-all.sh <group>` in full. Remains: a registration-only edit of `test-all.sh` still counts as machinery (`PR_GATE_MACHINERY_PATHS`, `scripts/lib/test-relevance-paths.sh`), and the 2026-10-05 plan records PR-event workflows as about 61% of window demand, not built. **Owned by the live sibling PR #9552** (empty, init commit only); PR-1 does not touch it.
- **Item 6c, JOBS=1 stopgap (#7432).** Done on main: nothing removed; `JOBS: 1` is still pinned at `.github/workflows/main-health-monitor.yml` lines 342 and 369, check (12) of `plugins/soleur/test/main-health-monitor-workflow.test.sh` asserts them, `scripts/followthroughs/jobs1-stopgap-7432.sh` exits 0 only when zero pins remain, and `suite-runner-flake-7376.sh` closes #7376 only when #7432 closes. Remains: a soak after #9525, then the decision on #7432 (a `-P 4` non-issue-filing probe, remove both pins, delete check 12). PR-1's evidence comment on #7376 starts that soak clock.

Known accepted gaps (left alone, per the brief): a 403 secondary rate limit is not retried, and a late run on a congested runner pool is not detected by the dispatcher. No change to `infra/github/ruleset-ci-required.tf`; the three operator decisions on #9482 and ADR-270's `adopting` status are not touched.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected: an engineering-internal CI-hygiene change with no product, marketing, legal, finance, sales or support surface. The engineering lens (architecture of the guard, conversion safety) is carried by the plan-review panel (DHH, Kieran, code-simplicity, CTO devex) rather than a separate domain leader, since no architectural decision is made (no ADR or C4 change: no ownership boundary, substrate, trust boundary or ADR reversal; the C4 element lists are unaffected because the change adds no actor, system, container or relationship).

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "items 1 and 5 only — the repo-wide pipefail early-exit `grep -q` sweep (#9217, #6601, #7005) plus guard blind spots (wrappers, flag order, `\| head`) in .claude/hooks/grep-q-pipe-guard.test.sh" [brief] | Phases 1 to 3, Guards 1 and 2 | mapped |
| 2 | "Measure the real site counts first (tracker titles cite roughly 41 production and 148 test-harness sites; verify against current main" [brief] | Phase 0, Research Insights measurements | mapped |
| 3 | "convert them with the here-string or process-substitution forms, extend the guard's pinned set, and add mutation-checked regression rows" [brief] | Phase 2 (conversion forms), Phase 1 (derived pass instead of an enlarged pin array), Guard Contract | mapped |
| 4 | "Treat the producer-side form separately, since a line search cannot see it." [brief] | Producer-side form section (measured population), Phase 4 hand-off, wave B join and fixes | mapped |
| 5 | "Close what a regex can close, and document what it cannot." [brief] | Phase 3, Item 5 section | mapped |
| 6 | "The plan file MUST also list the remaining items ... as separate follow-up PRs with a one-paragraph verified-against-main status each" [brief] | Follow-up PR Register | mapped |
| 7 | "Item 6a (single local ratchet command) may be folded into PR-1 only if it is small; decide in the plan." [brief] | Register item 6a decision (not folded) | mapped |
| 8 | "coordinate by leaving 6b to it unless proven otherwise" [brief] | Register item 6b, AC-9 | mapped |
| 9 | "Do not change merge-queue ruleset parameters ... do not flip ADR-270 to accepted" [brief] | Non-goals, AC-9 | mapped |
| 10 | "BATCH PUSHES." and "Before EVERY push, run every ratchet locally" [brief] | Phase 5, AC-7 | mapped |
| 11 | "fold evidence into existing trackers before filing anything new" [brief] | Phase 5, AC-8 | mapped |
| 14 | "Close what a regex can close, and document what it cannot." and the guard header's "wrappers, flag order, `\| head`" [brief] | Item 5 section, Guard 2 | mapped |
| 12 | "PR bodies use `Ref #N`, never `Closes #9482`" [brief] | AC-10 | mapped |
| 13 | "a learning per non-obvious finding" [brief] | Phase 5 | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| `.claude/hooks/grep-q-pipe-guard.test.sh` edits (derived pass, `PATTERN_V2`, rows) | "Guard to extend: .claude/hooks/grep-q-pipe-guard.test.sh" | asked |
| PR-1's production conversion set (82 files in four roots) | "convert them with the here-string or process-substitution forms" | asked |
| Wave split A2 and B | "Split PRs by subsystem (production scripts vs test harness may be separate PRs if the diff is large)" | asked |
| Derived population plus a deferral table with per-row ceilings instead of `FILES_*` entries | — | inferred — justification: the per-file pin recipe needs an array entry, a pin count and an affected-paths edit per file (about 300), and the affected-paths edit arms every PR-gated battery; without a deferral table the guard could not land at zero before the later waves, and without ceilings the deferred subtrees (about 950 sites) could grow while they wait |
| Scratch transformer and working table for the mechanical class (not committed) | "convert them with the here-string or process-substitution forms" | asked |
| Commit structure per root, the `DEFERRED:` print line and tracker tokens, the header's remediation text | — | inferred — justification: the reviewer and the next contributor need a per-root revert point and a visible record of the remaining debt; the header text is where a contributor lands when the guard fires |
| Audit correction row in `2026-07-17-sigpipe-guard-triage-feasibility.md` | "under an ignored SIGPIPE the failing status is 1" (merged learning) | inferred — justification: the audit's table says the defect is absent on the runner, which the three flipped suites contradict; a stale claim there would mislead the next measurement |
| Learning file, tracker comments | "a learning per non-obvious finding" and "tracker comments with evidence on the existing issues" | asked |
| Producer-side population figures and the wave-B hand-off | "Treat the producer-side form separately, since a line search cannot see it." | asked |
| Follow-up register paragraphs | "a one-paragraph verified-against-main status each" | asked |

### Split Assessment

- Subsystems touched: 6 — `scripts`, `plugins/soleur`, `apps/web-platform`, `apps/cla-evidence`, `.claude/hooks`, `knowledge-base`
- Planned files: about 86 | Estimated changed lines: about 600 (165 sites, about 150 lines of guard and fixtures, about 150 of docs)
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: split — already applied: infra and CI production (A2) and the test harness (B1..B3) are separate PRs; PR-1 stays one PR because its 82 conversion files share one rewrite and one guard flip, and it is commit-structured per root.

## Acceptance Criteria

### Functional Requirements

- [ ] AC-1: Phase 0 outputs (a) to (e) are recorded in the PR body: the pathspec-derived set equals the classifier set file by file, V2 is V1 plus the wrapper site, non-code hits are counted and handled, the non-bash count, and the armed-battery and `--affected` selected-suite set; the counts in this plan are re-stated with the command that produced them.
- [ ] AC-2: After conversion, `scan_sweep` reports zero hits over every non-deferred root, and `bash .claude/hooks/grep-q-pipe-guard.test.sh` prints `PASS: grep-q-zero-sweep-pass` and exits 0.
- [ ] AC-3: Before any conversion the same pass is demonstrably RED (log the FAIL count in the PR body); each mutation row of Guards 1 and 2 was run, and each went RED (or its must-PASS stayed green). A mutation run reports `NOT LANDED` and fails if its anchor text is absent before the edit, so a mutant that edited nothing cannot read as a kill.
- [ ] AC-4: `PATTERN_V2` matches every wrapper, brace, long-flag and argument-taking-flag fixture and none of the false-positive fixtures; repo-wide the set of sites it reports (as `file:line`, not counts) is a superset of the V1 set plus the 10 new sites (6 wrapper, 4 brace); `PATTERN_V2` is in the compile pre-check loop, so a non-compiling pattern exits 3.
- [ ] AC-5: The guard header's "Not matched" paragraph is replaced by a closed/residual table carrying the measured counts (`| head` about 937, awk exit 58, `sed q` 3, `read` 7, continued pipe 1), the three-row conversion table, the marker syntax and the `| head` danger sentence; the FAIL message prints the one-line remediation.
- [ ] AC-6: Every changed shell file passes `bash -n`; every changed production script that has a registered suite has identical pass/fail counts before and after; the hand-converted and verdict-bearing suites pass 4 of 4 concurrent isolated copies, collected by pid (not by a bare `wait` after subshell-backgrounded jobs).
- [ ] AC-7: Before the push, every file from `grep -lis ratchet scripts/*.test.sh scripts/lib/*.test.sh .claude/hooks/*.test.sh` was run and passed (output listed in the PR body; this is the brief's rule), plus `scripts/pre-push-ratchet-lane.sh`, the guard run directly, the orphan lint and `scripts/test-affected-kb-consumers.test.sh`; one push only.

### Non-Functional Requirements

- [ ] AC-8: No new GitHub issue is filed; one full evidence comment is posted on #9217 (counts, wave plan, residual table, producer-side figures) and a one-line cross-link on #7005, #6601 and #7376; a short note is left on draft PR #9552.
- [ ] AC-9: `git diff --name-only origin/main...HEAD` (merge-base form, so a sibling merge cannot flip it) contains none of `scripts/test-all.sh`, `scripts/lib/test-affected-paths.sh`, `scripts/lib/test-relevance-paths.sh`, `.github/workflows/ci.yml`, `scripts/suite-shard-legs*.tsv`, `infra/github/ruleset-ci-required.tf`, `lefthook.yml`, and no ADR-270 file.
- [ ] AC-10: PR body uses `Ref #9217`, `Ref #7005`, `Ref #6601`, `Ref #7376`, `Ref #9482` and no `Closes`.
- [ ] AC-11: `python3 scripts/lint-guard-contract.py knowledge-base/project/plans/2026-10-05-fix-pipefail-early-exit-grep-q-sweep-plan.md` passes; markdownlint passes on every markdown file in the commit.
- [ ] AC-12: The `discoverability_test` command runs inside preflight Check 10's sandbox shape (repo read-only, tmpfs `HOME`, `PATH=/usr/local/bin:/usr/bin:/bin`) in under 15 s and prints `PASS: grep-q-zero-sweep-pass`; if `git grep` or `mktemp` cannot run there, the probe is replaced by a repo-relative wrapper in the same PR.
- [ ] AC-13: The audit gains one corrected SIGPIPE-disposition row, and one learning is written that links to it; the scratch transformer is not committed (waves A2 and B commit a tool only if they need one).

### Quality Gates

- [ ] Plan-review panel findings applied; `tasks.md` regenerated from the final plan.
- [ ] `soleur:review` seats include a structural-enumeration pass over the Phase 0 working table (category counts per root).

## Test Scenarios

### Acceptance Tests (RED phase targets)

- Given the guard with the derived pass and an unconverted tree, when it runs, then it FAILs listing about 165 sites and exits 1.
- Given a deferral row whose hits equal its ceiling, when a bad line is added under it, then the guard FAILs on the ceiling.
- Given PR-1's roots converted, when it runs, then every pass prints PASS and exits 0, and the discoverability line `PASS: grep-q-zero-sweep-pass` appears.
- Given a scratch copy of a file from each root with `echo "$x" | grep -q p` appended, when the pass scans the scratch root, then it reports exactly one hit per root.

### Regression Tests

- Given a wrapper line `x | LC_ALL=C grep -q p` and a brace line `x | { grep -m1 -E v || [ $? -eq 1 ]; }`, when scanned, then both are reported (and were not by the V1 pattern).
- Given the #8866 shape `a || grep -q p <<<"$x"`, when scanned, then it is not reported.
- Given a deferred subtree whose hits were all converted, when the guard runs, then it fails with "stale deferral".
- Given `printf '%s' "$V" | grep -q '^$'` with `V=""`, when the scratch transformer classifies it, then it refuses the here-string form and queues it for hand review.
- Given an output-consuming `... | grep -m1 P` site, when converted, then it becomes `grep -m1 P <<<"$v"` and keeps emitting the matched line.
- Given a bare pipeline under `set -e` whose producer exits non-zero, when converted, then it goes to the capture form so the failure is still seen.

### Edge Cases

- Given a comment line that quotes the forbidden shape, when scanned, then it is not reported; given a code line with a trailing comment, then it is.
- Given an unreadable input path, when `scan_sweep` runs, then it prints UNRESOLVED and the caller exits 3 (never "no hits").
- Given a script whose shebang is not bash, when a site is classified, then it is queued for hand review, never given a here-string.
- Given a producer with side effects (`terraform`, `ssh`, `gh api` write), when classified, then it goes to the capture form, never process substitution.

### Integration Verification (for `soleur:qa`)

- **Local:** `bash .claude/hooks/grep-q-pipe-guard.test.sh` expects `PASS: grep-q-zero-sweep-pass`.
- **Contention:** from a scratch directory, `pids=(); for i in 1 2 3 4; do bash <touched-suite> >"$o.$i" 2>&1 & pids+=($!); done; for pid in "${pids[@]}"; do wait "$pid" || echo "rc=$? pid=$pid"; done`, then compare each log's pass count with the pre-change run (a subshell-backgrounded loop followed by a bare `wait` returns immediately and reads half-written logs).
- **Producer-side figures:** the measured population (28 production pipes, the stub counts) is posted on #9217; the join is wave B's.

## Risks and Sharp Edges

- **A transformer bug repeats across 165 sites.** Mitigation: assert-before-write, inverse-transform check over the mechanical class's changed lines only, the Phase 0 reconciliation, per-root commits, and the rule that a mutant or a rewrite must be a working program (the learning's session errors 1 and 2).
- **A here-string needs a temp file for bodies over the pipe capacity.** A read-only or full `/tmp` makes a match silently read as a miss. The Phase 0 table flags production scripts that run on hosts (`scripts/zot-restart-loop-alarm.sh`, `scripts/check-web-host-escrow-config.sh`) so they are reviewed for body size and, if in doubt, use the capture form.
- **Process substitution is not waited for and drops the producer status.** A producer with side effects, and every bare pipeline under `set -e`, stays in the capture form.
- **Semantic overlap with the sibling #9552.** It may edit the relevance libraries and `ci.yml` that reference `.claude/hooks`; PR-1 touches none of them (AC-9), re-compares the armed-battery set at ship time, and leaves a note on #9552.
- **Local `--affected` may not select the guard for `scripts/` edits.** CI runs it in full and Phase 5 runs it directly; accepted and stated in Guard 1.
- **The two `*.template` files and the `.workflow.js` write into other repositories or run in a user's workspace.** Read what they emit first; run their parity tests.
- **Counts rot.** Every number in this plan is re-derived in Phase 0 and the PR body re-states them with commands (learning: a count that counted a comment).
- **`scripts/test-affected-kb-consumers.test.sh` reacts when a guard names more scripts.** The derived pass names no file, but the new fixtures must not introduce a `knowledge-base/` literal; run the ratchet before the push.
- **A plan that quotes a `## Scope Check`-like heading in prose** would trip deepen-plan; this plan keeps those only as the live sections.
- **Sibling hazard.** #9552 may touch `scripts/test-all.sh` and the relevance libraries; PR-1 does not (AC-9), so a merge conflict is limited to files PR-1 edits for the sweep (none in common today).

## Dependencies and References

- Tracker and umbrella: #7376, #9482; sweep trackers #9217, #7005, #6601; follow-through #7432.
- Merged: #9525 (c95101f60f), #9523 (c35116046b); prior art #8866, #9033, #6998, #7035, #8848.
- Guard: `.claude/hooks/grep-q-pipe-guard.test.sh`. Probe: `apps/web-platform/infra/scripts/sigpipe-triage-feasibility.sh`. Lane: `scripts/pre-push-ratchet-lane.sh`.
- Learning to read first: `knowledge-base/project/learnings/test-failures/2026-10-05-a-reader-that-exits-early-flipped-three-suites-and-the-stub-had-to-read-too.md`.
