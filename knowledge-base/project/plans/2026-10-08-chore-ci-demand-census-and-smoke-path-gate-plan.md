---
title: "ci: S1 census script and secret-scan smoke path gate (#9721 stage 1)"
date: 2026-10-08
slug: ci-demand-census-and-smoke-path-gate
branch: feat-one-shot-9727-ci-census-smoke-gate
issue: 9727
closes: 9727
type: chore
lane: cross-domain
priority: p2-medium
domain: engineering
brand_survival_threshold: aggregate pattern
---

# ci: S1 census script and secret-scan smoke path gate (#9721 stage 1)

## Enhancement Summary

**Deepened on:** 2026-10-08. **Agents used:** architecture-strategist, spec-flow-analyzer, test-design-reviewer, security-sentinel (deepen pass); DHH, Kieran, code-simplicity, CTO devex lens (plan review). Gates run: user-brand impact, observability (5 fields; probe verb `bash`, no shell-active characters, finishes offline), PAT-shape grep (no hits), UI-wireframe (no UI surface), encryption posture (no store or connection), guard contract (`lint-guard-contract.py`: 2 entries; adequacy read below), scope check (one unfenced section, no `unmapped` rows).

1. Fail-open hardened: the output is written last and the `if:` also runs the matrix when the detect job did not succeed; the listed entry count must equal the event's own `changed_files` (catches a lagging list, a re-run on a newer head and the 3000-entry cap).
2. Subject set widened to implicit git inputs (`.gitignore`, `.gitattributes`, any `smoke/` component); the measured skip share stays about 91%. Test design made executable: mutants run against a copy of the extracted body with a landing check, reasons are asserted per arm, and the operand anchor has a known-positive control and covers more command shapes.
3. Census made measurable: one-hour sub-windows (the parent plan's own 6h baseline held 934 of the 1,000-run cap), C1 before any jobs call, `STEM` rows split into ran, skipped and queue-cancelled so the exit criterion is stated net and can fail, and input validation plus output sanitisation because fork-PR job names are attacker-chosen.
4. The Part B step body was prototyped on 2026-10-08 against a local `gh` shim applying the real `--jq` with `jq` (the body parses with `bash -n` and runs under `bash --noprofile --norc -eo pipefail`): a docs-only list gave `smoke=false`; a new file under `apps/web-platform/scripts/`, a rename out of `.gitleaks.toml`, a nested `.gitattributes` and a `changed_files` mismatch each gave `smoke=true`; a hostile file name containing a newline and `::error::` left one output line. The work phase turns these into the suite's rows.
5. Verify-the-negative result: "no document claims weekly smoke coverage" (grep of `knowledge-base/engineering`, the workflow, legal and docs found no weekly-smoke claim) and "the smoke job has no local `uses: ./` action" (only `actions/checkout`) both confirmed.

**Guard Contract adequacy read.** Assembly names the chokepoint (one step body, one `if:`) and quantifies over derived sets (tracked operands of the live job text, required jobs derived from `scripts/required-checks.txt`), not a remembered list; the matrix rows come from the design (a dropped alternative, a second member, the guard's own dispatch, the failure shapes, the wrapper) and each row names the mutant that must land.

## Overview

Stage 1 of the hosted-runner demand plan (#9721, parent plan
`knowledge-base/project/plans/2026-10-07-ci-reduce-hosted-runner-demand-plan.md`, ADR-276 `proposed`)
delivers two small, additive CI items:

1. **`scripts/ci-demand-census.sh`**, the committed measurement authority ADR-276 Decision 7 names. It turns
   the plan's Measured-state method into one reproducible command: runner-bound, non-skipped jobs only,
   totals per workflow and event, `CI` per-family minutes per run, and self-checks that refuse to print a
   total when the fetch was truncated. It has an offline `--fixture <dir>` mode so a suite (and the
   observability discoverability test) can run it with no network.
2. **A path gate for the secret-scan `smoke-tests` matrix** (lever 4a, up to 134 job-minutes per 6h window,
   a 1.8% gross upper bound). A new fail-open `smoke-relevance` job lists the PR's files through the API
   (no checkout) and the ten smoke legs run only when the PR touches a file the matrix exercises, or when
   anything about the diff is uncertain.

Scope is S1 only. Later stages (S2 to S5) are out of scope. Nothing is provisioned (lever 5 stays a memo).
`Closes #9727`.

Spec note: no `spec.md` exists for this branch, so `lane:` is `cross-domain` (fail-closed default).

## Research Reconciliation: issue and brief vs. codebase

| Claim (issue #9727, parent plan S1 row, brief) | Reality (checked on this branch / live) | Plan response |
|---|---|---|
| "the matrix runs only on `pull_request` today (no `schedule` arm exists), so a weekly arm must be added with its own test or the 'weekly full coverage' claim dropped" | True for the smoke job: `smoke-tests` has `if: github.event_name == 'pull_request'`. The workflow does carry a weekly `schedule` arm, but it runs `scan` only. No document claims weekly smoke coverage: every "weekly" in `knowledge-base/engineering/operations/secret-scanning.md` means the gitleaks scan | **Drop the claim; add no schedule arm.** The under-match risk a weekly arm would bound is closed at PR time instead, by a test that derives the files the smoke job executes and requires the gate to match each (Guard 1 assembly). See Cut List |
| "the gate must run unconditionally on non-PR events (no diff base there)" | On non-PR events `smoke-tests` does not run today, and after this change it still does not (its `pull_request` conjunct stays). Nothing runs "unconditionally off PR" | The ask is satisfied structurally: `smoke-relevance` carries `if: github.event_name == 'pull_request'` and `smoke-tests` keeps its own event conjunct, so the step body is unreachable off-PR. No in-body event guard is written (plan review: dead code, two mutation rows to keep it honest) |
| "a new `smoke-relevance` job raises the declared count and needs a `scripts/pr-fanout-ledger.txt` bump" | Verified: `yaml.safe_load` gives 6 declared jobs in `secret-scan.yml`, the ledger row says 6 | Bump to 7 and name the consequence in the row (the ledger's ratchet rule) |
| Parent-plan method: `gh api "repos/<r>/actions/runs/<id>/jobs?per_page=100&filter=latest"` per completed run | Unpaginated: a run with more than 100 jobs would silently truncate (`scripts/main-push-duplicate-skip.sh` documents the same hazard). The largest `CI` run today has 36 jobs | The census uses `--paginate` to a file and checks `length(jobs) == total_count` per run |
| Parent plan: the runs listing is the self-check authority | Verified live 2026-10-08: a 24h window reports `total_count` 2500, and page 11 of 100 returns `total_count` 0 with no runs: the listing is capped at 1000 results while `total_count` keeps the true number | Self-check C1: unique runs fetched must equal the first page's `total_count`; the census fetches in one-hour sub-windows, each checked on its own, and a sub-window at the cap fails with "narrow the window" before any jobs call instead of reporting a partial total |
| Parent plan: runs in the listing carry a workflow `name` | Dynamic runs are named per PR (`Code Quality: PR #9653`, `PR #9653`), so grouping by name explodes into one row per PR | Group by `.path` (`.github/workflows/ci.yml`, `dynamic/github-code-quality/codeql`, `dynamic/github-code-scanning/codeql`), `@ref` suffix stripped |
| Issue: "Fix-Size: 250 lines / 6 files" | The deliverable needs a script, two suites, a fixture directory, the workflow edit, the ledger row, two registrations, a CODEOWNERS line, a runbook paragraph and the ADR amendment: about 19 files and 600 lines, mostly test code | Accept and record in Split Assessment; the tests are the Guard Contract's deliverable, not padding |
| ADR-276 Status: S1 "changes no CI behaviour ... neither appends an amendment" | The text states an exemption (Decision 3(g) does not bind S1), it does not forbid an amendment. The operator rule is that each stage PR appends a dated amendment before the stage takes effect | Append a short non-activating `## Amendment 2026-10-08 (S1, #9727)` and a dated Stage-status line; status stays `proposed` (see Architecture Decision) |

## Research Insights

### Premise validation (Phase 0.6)

Checked: #9727 open; parent #9721 closed (by the merged plan PR #9722, merged 2026-10-07T22:59:43Z, which
is the issue's stated re-evaluation trigger); draft PR #9772 open on this branch; ADR-276 exists with
`status: proposed` and S1 listed against #9727 in its Stage-status table; no code-review issue overlaps
the workflow or ledger. The issue's own pre-written body is committed at
`knowledge-base/project/specs/feat-one-shot-ci-hosted-runner-demand/issues/s1-census-and-smoke-gate.md`.
Cited paths verified on this branch: `.github/workflows/secret-scan.yml` (6 jobs; `smoke-tests` at the
matrix of ten cases; weekly cron feeds `scan` only), `apps/web-platform/scripts/{rename-guard.sh,
allowlist-diff.sh,lint-fixture-content.mjs,parse-gitleaks-allowlists.mjs}`, `.gitleaks.toml`,
`.gitleaksignore`, `scripts/pr-fanout-ledger.txt` (secret-scan row: 6 jobs), `scripts/lint-orphan-test-suites.sh`.
`smoke` check contexts are not in `scripts/required-checks.txt`. ADR corpus grep for the mechanism (job-level
path gate on a non-required PR job): ADR-262 holds the battery gate (declared an approach, not a rejection of
detect jobs); `pr-quality-guards.yml` `detect` and `vendor-pin-verify.yml` `detect-changes` are the shipped
precedents. None rejected it.

### Property List (Phase 0.6b)

1. Any closed time window can be turned into the same job-minute figure by one committed command, counting
   only jobs that held a runner and were not skipped, and the command refuses to print a total from a
   truncated fetch.
2. A pull request that touches no file the smoke matrix exercises consumes no smoke runner minutes.
3. A pull request that touches such a file, or whose changed-file list cannot be determined, runs all ten
   smoke cases.
4. No required context, merge authority or non-PR event behaviour changes.
5. No claim of "weekly smoke coverage" is made that nothing backs.

### Cut List

| Mechanism proposed or implied | Property | What already covers it / why cut |
|---|---|---|
| Weekly `schedule` arm for `smoke-tests` | 5 | Cut: the claim never existed in the tree. The class it would bound (gate pattern narrower than what smoke executes) is caught earlier and for free by the named subject list and the operand anchor in Guard 1 |
| Repository-variable kill-switch (`on`) | 4 | ADR-276 Status exempts S1 from Decision 3(c): the gate fails open and the rollback is a revert; a switch would guard 1.8% of minutes |
| Per-leg step-level skip inside the matrix | 2 | Each leg would still pay runner start and checkout; job-level skip of ten legs costs one ~8 s detect job (`pr-quality-guards.yml` `detect`, measured by its own comment) |
| Detect job with `actions/checkout` + `git diff` | 2 | The pulls/files API needs no checkout (`pr-quality-guards.yml` precedent) |
| A separate committed verdict script for the gate | 3 | The step body is the single source and the suite extracts and executes it (`scripts/skill-security-scan-step-body.test.sh` precedent). A script would need a checkout of the PR tree, so a PR could edit the script that decides its own skip |
| Concurrency sampling (mean, p90, peak, minutes at 55+) in the census | 1 | Not in the issue scope list; S5 (#9730) judges queue wait at peak. Recorded on #9730 as a work-phase comment, not a new issue |
| Parallel job fetching, JSON schema files, a `--format` zoo | 1 | YAGNI: one sequential fetch of about 930 calls, key=value summary plus one JSON document |
| A new required context or aggregator for `smoke-relevance` | 4 | Smoke is non-required; adding a required name touches `required-checks.txt` and the ruleset (ADR-032 ABI) for no benefit |
| Transitive closure derivation of the smoke job's files (expand each named script's text one level, subtract runtime paths, five-member floor) | 3 | Cut at plan review (DHH, code-simplicity, CTO and Kieran converged): the directory-prefix `SUBJECT_RE` already absorbs a later helper, the expansion produced day-one false positives (runtime-created `__synthesized__` paths, a doc path inside an `echo`), and its floor was editable by the same diff. Replaced by an explicit named list plus a command-position-operand anchor (Guard 1) |
| A restricted `if:` expression evaluator and truth table | 3 | Cut: it models GitHub's expression semantics with the author's own reading of them. Replaced by exact-string equality on the extracted `if:`, `actionlint` expression checking (already in `scripts/lint-workflows.sh`), and the two live canaries |
| In-body non-PR-event and numeric-PR-number guards | 3 | Cut: the job-level `if:` makes them unreachable; ask 6 is met structurally |
| JSON output mode, `--out`, `meta.json`, `--repo`, the `--stems` flag and a hard-coded `CI` family list | 1 | Cut: summary-only output; repo from `GH_REPO` or `gh repo view`; one generic per-job-stem table covers the `CI` families and the `smoke` stem with no list to drift |
| Mutation tests of the test harness (shim flag whitelist row, re-laid-out fixture, `sed` clause mutants of the script) | 1, 3 | Cut: one harness row per guard stays (a stub that prints the verdict must turn the suite red); the clause-by-clause property is proved by golden fixture jobs that each violate exactly one clause |
| A `--last <N>h` window option, a `.head.sha` freshness guard on the file list, a label or `workflow_dispatch` that forces smoke | 1, 3 | Declined as taste (recorded in `decision-challenges.md`): the header documents the `date -u` recipe; list lag is accepted under Dependencies & Risks; touching a subject file is the documented way to force smoke |

### Measured baseline for the saving claim (Phase 0.6c)

The justification is a saving, so it is quantified and the command is named. From the parent plan's
re-measure (window 2026-10-07 13:04Z to 19:04Z): secret-scan `pull_request` 203 runner job-minutes of
which the smoke matrix is 134; 41 PR heads in the window gives about 3.3 smoke job-minutes per PR run (ten
legs of about 20 s each) against a detect job of about 8 s (0.13 min). A PR that misses the subject paths
therefore drops from about 3.3 to about 0.13 job-minutes, 96%. The criterion is stated NET, because a skipped job counts 0 minutes by construction and
"smoke minutes on PRs that miss the subject paths" could never fail: the secret-scan smoke-related minutes per PR run (the `smoke` stem plus the `smoke-relevance`
stem) must be down at least 80% against the baseline window, and the skip share (`runs_skipped / (runs_ran + runs_skipped + runs_runnerless)` for the `smoke` stem) is
reported next to the share of PRs that touched subject paths. The detect job runs once per workflow RUN, not per PR head (the workflow also fires on `labeled` and
`unlabeled`), so its cost is stated per run. The 134 is a gross upper bound: it assumes no PR touches the subject paths. Reproduced and measured by the command this PR
adds: `bash scripts/ci-demand-census.sh --start 2026-10-07T13:04:00Z --end 2026-10-07T19:04:00Z --summary`
(before; read the `STEM secret-scan.yml pull_request smoke` row) and the same command over a post-merge window (after); both outputs are attached
to #9727.

Subject-set sizing, measured 2026-10-08 with `gh pr list --state merged --limit 200 --json number,files` and a
`jq` `test()` over each file path (gh caps `files` at 100 per PR, so large PRs are undercounted): of the last
200 merged PRs, 18 (9%) touch the final subject set (the three root files, the whole
`apps/web-platform/scripts/` prefix, `.gitignore`/`.gitattributes` at any depth and any `smoke/` path component; the last two add 0 in this sample), against 5 (2.5%) for the three root
files plus only the four named scripts. The prefix costs about 6.5 points of extra smoke runs and still leaves smoke skipped on about 91% of
PRs, above the 80% target, in exchange for covering a helper added later without an edit here.

### Institutional learnings applied

- Path-gate detectors must fail open and gate on exit status, never emptiness; `|| true` on a paginated
  fetch is a silent false-skip (`knowledge-base/project/learnings/2026-09-25-path-gating-exit-status-not-emptiness.md`).
  A failed `detect` makes `needs:` dependents skip unless their `if:` handles it.
- Extract and EXECUTE workflow `run:` bodies under `bash --noprofile --norc -eo pipefail`, never grep the YAML
  (`scripts/skill-security-scan-step-body.test.sh` header; `2026-09-20-i-verified-by-reading-and-the-gate-that-mattered-failed-open.md`).
- A `gh` stub must whitelist the real flags and exit non-zero on invented ones
  (`2026-09-25-gh-stub-must-mirror-real-cli-flags.md`); `gh api -f` silently becomes POST
  (`2026-09-29-gh-api-field-flags-force-post-and-fixture-writes-leak-into-committed-artifacts.md`, which also
  records fixtures clobbering committed `scripts/suite-durations.tsv`: the suites write only under `mktemp`).
- A check that cannot report is indistinguishable from one that passed; every skip arm needs a mutation row
  (`2026-07-27-a-check-that-cannot-report-is-indistinguishable-from-one-that-passed.md`); a self-graded
  battery goes vacuous unless positive controls and a floor exist
  (`2026-07-19-a-self-graded-mutation-battery-went-vacuous-twice-in-one-pr-and-the-two-producer-count-that-fixed-it.md`).
- Under GitHub's default `bash -eo pipefail`, `grep -q` in a pipeline SIGPIPEs the producer; use herestrings
  and `|| rc=$?` captures (`test-failures/2026-07-18-pipefail-grep-q-early-match-sigpipe-flakes-drift-guards.md`,
  `best-practices/2026-07-02-gha-run-default-shell-has-pipefail-guard-grep-substitutions.md`; ADR-170).
- The first job-minute pass over-counted by 26% because runner-less jobs were included
  (`2026-10-07-a-docs-pr-took-four-review-rounds-because-each-fix-shipped-its-own-unmeasured-claims.md`).
- Committed fixtures must be synthesized (`cq-test-fixtures-synthesized-only`); the gitleaks scan covers the
  whole diff range (`best-practices/2026-07-11-gitleaks-shared-non-test-helper-not-in-test-allowlist-and-scans-whole-diff-range.md`).
- Adding a second copy of a guarded literal disarms a whole-file grep guard
  (`2026-07-20-adding-a-second-copy-of-a-guarded-literal-disarms-the-first.md`): the new job's name and `if:`
  must not be asserted by whole-file grep.

## Open Code-Review Overlap

Open `code-review` issues naming files this plan edits: #8659 and #7942 (`scripts/test-all.sh`, an EXIT-trap
class and two unregistered mutation batteries) and #8800 (`scripts/lib/test-affected-paths.sh`, a census
sandbox sharing inodes with the live repo). **Acknowledge** all three: none sits on the lines this plan adds
(two one-line registrations and one `AFFECTED_*_PATHS` block), and each stays open. Note for #8800: this
plan's suites write only under `mktemp -d`, never into the repo. No overlap on `secret-scan.yml`,
`pr-fanout-ledger.txt` or `scripts/ci-demand-census.sh`.

## Proposed Solution

### Part A: `scripts/ci-demand-census.sh`

Interface (one script, bash + jq; `gh` only in live mode):

```text
ci-demand-census.sh --start <YYYY-MM-DDTHH:MM:SSZ> --end <YYYY-MM-DDTHH:MM:SSZ> [--summary]
ci-demand-census.sh --fixture <DIR> [--summary]
```

- **Live mode** fetches into a fresh `mktemp -d` under `${TMPDIR:-/var/tmp}` (path printed on stderr, with the delete command on the last line) and then
  calls the same aggregator fixture mode uses, so there is one code path to test. The window is fetched as **one-hour sub-windows** (the
  runs listing is capped at 1,000 results and the parent plan's own 6h baseline held 934 runs, so a 6h window is at the edge): for each sub-window,
  `runs-<n>.json` is the verbatim `gh api --paginate "repos/<repo>/actions/runs?created=<a>..<b>&per_page=100"` output (multi-document JSON, sub-window ends
  shifted by one second so the inclusive `created=a..b` bounds partition cleanly), checked by C1 **immediately, before any jobs call**; and
  `jobs-<run_id>.json` is `gh api --paginate "repos/<repo>/actions/runs/<id>/jobs?per_page=100&filter=latest"` for each COMPLETED run. A sub-window that itself
  holds 1,000 or more runs exits 3 before any jobs call, printing its `total_count` and window and naming the narrower window to use.
  Progress goes to stderr every 50 runs; a failed call is retried twice, then aborts naming the run id (no `|| true`, no resume).
  The repo comes from `GH_REPO` or `gh repo view` and is validated against `^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$`. `--start` and `--end` are validated against the
  fixed `...T..:..:..Z` shape (a `+02:00` offset puts a raw `+` in the query string and silently shifts the window), `start < end`, and `end` must not be in
  the future (a lexicographic compare against `date -u +%FT%TZ`; an open window is not reproducible). Every `run_id` is validated against `^[0-9]+$` before it
  builds a path or a URL. Only GETs are issued (no `-f`, `-F`, `-X`: `-f` silently turns a `gh api` call into a POST). Live mode exits 2 when
  `GITHUB_ACTIONS=true` (about 930 calls would spend the repo-wide `GITHUB_TOKEN` budget, about 1,000 requests per hour, that every other workflow shares).
- **Fixture mode** reads the same layout (`runs-*.json`, `jobs-*.json`) and never touches the network or requires `gh`.
- **Aggregation** (all `jq`, never `--paginate` with `--jq` aggregates; each jobs file is first projected to compact rows with `jq -c`, because the raw `steps`
  arrays of about 900 files would otherwise be slurped whole): flatten `[.[].workflow_runs[]?]` and `[.[].jobs[]?]`, de-duplicating runs by id. A job is
  **counted** iff `conclusion != "skipped"`, `runner_id > 0` (null is runner-less), and `started_at` and `completed_at` are both set; its minutes are the raw
  integer-seconds difference divided by 60 once (not billing-rounded). Workflow key is `.path` with `@...` and the `.github/workflows/` prefix stripped.
  Untrusted text hygiene: every string that reaches the output (workflow path, job name, event) is passed through a jq filter replacing
  `[\u0000-\u001f\u007f-\u009f  ]` (tab included) with `?` and capped in length; every output line starts with a fixed token; nothing is built by
  `eval`, `bash -c` or string-splicing into a jq program (values go in with `--arg`); the fixture directory is read-only.
- **Output** is `KEY=value` lines, then tab-separated tables, and nothing else (`--summary` is accepted as the explicit selector the issue's discoverability
  command uses): `REPO`, `WINDOW_START`, `WINDOW_END`, `FETCHED_AT` (`WINDOW=fixture` in fixture mode), `TOTAL_JOB_MINUTES=<n.n>`, `RUNS_COMPLETED`,
  `RUNS_NOT_COMPLETED` (in-flight runs are excluded, so the total is a stated lower bound, with a stderr WARN when it is above zero), `JOBS_COUNTED`,
  `JOBS_SKIPPED`, `JOBS_RUNNERLESS`, `JOBS_UNTIMED` (so the partition `counted + skipped + runnerless + untimed = total` is assertable);
  `BY_WORKFLOW <workflow> <event> <runs> <jobs> <minutes>`;
  `STEM <workflow> <event> <stem> <runs_ran> <runs_skipped> <runs_runnerless> <jobs> <minutes> <minutes_per_run>` for EVERY workflow, where the stem is the job
  name with its trailing parenthesised matrix suffix removed (`test-scripts (3/8)` becomes `test-scripts`), `runs_ran` is runs with at least one counted job of
  the stem, `runs_skipped` is runs whose only jobs of the stem concluded `skipped`, `runs_runnerless` is runs whose jobs of the stem were all runner-less
  (queue-cancelled), and `minutes_per_run` divides by the completed runs of that workflow and event. A queue-cancelled or superseded run is therefore never
  counted as gate-skipped. The `CI` per-family per-run minutes of the issue are the `ci.yml` rows (the families are just the stems `test-scripts`, `test-webplat`,
  `shard-totality-mutations`, `test-scripts-heavy`, `e2e`; the light set is the sum of the rest), with no family list in the script to drift.
- **Self-checks (a total is printed only if all pass; exit 3 otherwise, with the reason on stderr and NO `TOTAL_JOB_MINUTES` line):** C1 per sub-window, unique run
  ids fetched equal the first page's `total_count` (the 1000-result cap, a displaced run and a truncated `--paginate` all fail here; a harmless pure duplicate with
  `total_count` equal to the unique count is de-duplicated, not failed); C2 for every completed run a jobs file exists and `length(jobs)` equals its `total_count`
  (a run with `total_count` 0 and an empty `jobs` list is legitimate, the file must still exist), accumulated across all runs before the verdict; and a census
  with zero completed runs or zero counted jobs is refused rather than reported as 0.
- **Exit codes:** 0 ok; 2 usage, validation, missing dependency, CI refusal or API/I/O error; 3 self-check failure.
- **Header comment** fixes the definitions the parent plan deferred to this PR: the denominator (completed runs in the listing); the lower bounds (in-flight runs
  are excluded and `filter=latest` omits earlier attempts of re-run jobs, so a re-measure of a closed window will not reproduce an earlier figure to the digit,
  and a job's minutes are attributed to its run's creation time, so a re-run weeks later is credited to the original window); the closed-window rule with its
  `date -u` recipe; the 1000-result cap and the sub-window split; the exit codes; that live mode is for a developer shell with `gh auth`; and that job names and
  workflow paths of fork-PR runs are attacker-chosen, so the `STEM` rows are a cost measurement, not an attestation. The runner-less fixture job shape is copied
  from a real jobs response (field names only, synthetic values).

### Part B: secret-scan smoke path gate

New job in `.github/workflows/secret-scan.yml`, and one edit to `smoke-tests`:

```yaml
  smoke-relevance:
    name: smoke-relevance (gates the smoke matrix)
    runs-on: ubuntu-24.04
    timeout-minutes: 5
    if: github.event_name == 'pull_request'
    permissions:
      contents: read
      pull-requests: read
    outputs:
      smoke: ${{ steps.relevance.outputs.smoke }}
    steps:
      - name: Smoke relevance (PR file list, fails open)
        id: relevance
        env:
          GH_TOKEN: ${{ github.token }}
          GH_REPO: ${{ github.repository }}
          PR_NUMBER: ${{ github.event.pull_request.number }}
          CHANGED_FILES: ${{ github.event.pull_request.changed_files }}
        run: |
          set -uo pipefail
          T=$(printf '\t')
          # SUBJECT: what the ten smoke cases execute or read, including implicit git inputs (.gitignore and
          # .gitattributes change what `git add` and the diff gitleaks sees). A superset on purpose.
          SUBJECT_RE='^(\.github/workflows/secret-scan\.yml|\.gitleaks\.toml|\.gitleaksignore|apps/web-platform/scripts/)|(^|/)\.git(attributes|ignore)$|(^|/)smoke/'
          emit() {  # the GITHUB_OUTPUT write is LAST: a failure before it leaves the output empty, which runs the matrix
            echo "::notice::smoke-relevance: smoke=$1 ($2)"
            echo "smoke-relevance: smoke=$1 ($2). The smoke matrix runs when a PR changes a subject path (see SUBJECT_RE in this job) and whenever this job cannot decide." >> "$GITHUB_STEP_SUMMARY"
            echo "smoke=$1" >> "$GITHUB_OUTPUT"
          }
          # one line per entry: F<TAB>filename, and P<TAB>previous_filename for a rename (no stray text reaches an annotation)
          if ! lines=$(gh api --paginate "repos/$GH_REPO/pulls/$PR_NUMBER/files?per_page=100" --jq '.[] | "F\t" + .filename, (if .previous_filename then "P\t" + .previous_filename else empty end)'); then
            emit true "file list fetch failed"; exit 0; fi
          if [ -z "$lines" ]; then emit true "empty file list"; exit 0; fi
          # completeness: the listed entries must equal the event's own changed_files (catches a list that lags the pushed head,
          # a re-run on a newer head, and the API's 3000-entry cap)
          if [ "$(grep -c "^F$T" <<<"$lines")" != "$CHANGED_FILES" ]; then emit true "file list does not match the event's changed_files"; exit 0; fi
          if ! names=$(grep -E "^[FP]$T" <<<"$lines" | cut -f2-); then emit true "name extraction failed"; exit 0; fi
          rc=0; grep -qE "$SUBJECT_RE" <<<"$names" || rc=$?   # no pipeline here: grep -q would SIGPIPE its producer under pipefail
          case "$rc" in 0) emit true "subject path changed";; 1) emit false "no subject path changed";; *) emit true "matcher error rc=$rc";; esac
```

`smoke-tests` gains `needs: smoke-relevance` and its `if:` becomes exactly
`github.event_name == 'pull_request' && !cancelled() && (needs.smoke-relevance.result != 'success' || needs.smoke-relevance.outputs.smoke != 'false')`: it skips
only when the detect job succeeded AND its output is the explicit string `false` (the precedent form, `pr-quality-guards.yml` `needs.detect.result != 'success' ||`).
Expression semantics relied on (GitHub Actions "Expressions" status-check functions and the `needs` context; confirm against the live run, not memory): an
`if:` that contains a status-check function is evaluated even when a needed job failed, was skipped or was cancelled; a missing output is the empty string, and
`'' != 'false'` is true. `!cancelled()` rather than `always()` so a superseded PR run (the workflow's own cancel-in-progress) does not keep running the matrix.
The expression does not start with `!` (a leading `!` is a YAML tag). The step summary line is what a developer sees when ten `smoke (...)` rows render grey, and
the job name says what it gates; the summary never embeds the regex (its `|` and `\.` render badly) and no file name ever reaches an annotation, summary or output.
The job-level `pull-requests: read` is a job-level exception, not the only one: `allowlist-diff` already declares job-level `pull-requests: write`. The header comment's
"permissions: contents: read ONLY (no pull-requests: read)" is therefore already stale and is reworded to "workflow-level `contents: read`; job-level exceptions:
`allowlist-diff` (`pull-requests: write`) and `smoke-relevance` (`pull-requests: read`)". Required contexts (`gitleaks scan`, `lint fixture content`,
`allowlist-diff`, `rename-guard`, `waiver discipline`) get no edge to the new job.

**This gate is a cost optimisation, not a control.** The workflow that runs on a PR is the PR's own version, so a PR can edit `SUBJECT_RE` or the `if:` and skip its own
smoke; the five required scanners still run, and the review control is CODEOWNERS. `.github/CODEOWNERS` covers `secret-scan.yml` and the four named scripts; this PR adds
`scripts/secret-scan-smoke-gate.test.sh` to it.

**Subject set (the pattern's rationale, to land as a comment above `SUBJECT_RE`):** `secret-scan.yml` itself (gitleaks pin, the case bodies); `.gitleaks.toml` and
`.gitleaksignore` (read by every `gitleaks` call); `apps/web-platform/scripts/` as a directory prefix (`rename-guard.sh`, `allowlist-diff.sh`,
`lint-fixture-content.mjs`, and the `parse-gitleaks-allowlists.mjs` both shell scripts invoke); `.gitignore` and `.gitattributes` at any depth (implicit inputs of
`git add` and of the diff gitleaks scans: a `-diff` attribute makes the patch "Binary files differ"); and any `smoke/` path component (the cases create fixtures under
`.../smoke/` directories, so a tracked file there would collide). The prefix is wider than the four files on purpose: a helper later sourced by one of them is covered
without an edit here.

**Consumers checked.** `smoke (...)` rows are not in `scripts/required-checks.txt`; `admin-merge-ready.sh` iterates the required set, never the present checks. A job-level
skipped matrix job renders as one skipped `smoke (${{ matrix.case }})` row, exactly as it already does on `merge_group` and `push`, so no consumer sees a new shape.
`cancel-superseded-pr-runs.yml` reaps by the ledger row (`cancel=yes`), unchanged. Smoke is non-required, so a red subject-path smoke does not block auto-merge or an
`--admin` merge: the gate's guarantee is "runs", not "gates". The serial `needs:` edge adds one runner start in front of the ten legs at peak queue; acceptable for a
non-required job, and costed per workflow RUN (the workflow also fires on `labeled` and `unlabeled`, so runs outnumber PR heads): about 0.13 job-minute per run against
about 3.3 saved per skipped run. Future work that adds `ready_for_review` to this workflow's `types` (S2/S3 territory) must revisit `smoke-relevance`.

## Guard Contract

Two guards are deliverables: the smoke gate (Guard 1, required by the issue) and the census self-check (Guard 2, the parent plan's Observability failure mode "census
silently undercounts"). The matrices are written from the design before either is implemented.

### Guard 1 - Smoke path gate (`smoke-relevance` and the `smoke-tests` `if:`)

**Property.** A pull request that changes a file any of the ten smoke cases executes or reads (or whose changed-file list cannot be fully determined) always runs all ten
smoke cases, and the gate can reduce runner use only by skipping `smoke-tests`, never by changing any required context or any non-PR event.

**Assembly.** The chokepoint is the single `smoke-relevance` step body plus the single `smoke-tests` `if:` expression, both in `.github/workflows/secret-scan.yml`; no
other path can skip a smoke leg. The property quantifies over three sets. (1) *The subject set*: an explicit named list in the suite (the workflow file, `.gitleaks.toml`,
`.gitleaksignore`, `rename-guard.sh`, `allowlist-diff.sh`, `lint-fixture-content.mjs`, `parse-gitleaks-allowlists.mjs`, `.gitignore`, `.gitattributes`, a nested
`.gitignore`, and a path under a `smoke/` directory), each of which must yield `smoke=true` as a modification and as a rename source, plus prefix rows (a never-existing
`apps/web-platform/scripts/new-helper.mjs` and a nested `apps/web-platform/scripts/lib/x.mjs` must be `true`; `apps/web-platform/scripts-extra/x` and `.gitleaks.toml.bak`
must be `false`), with a non-subject control (`knowledge-base/` and `plugins/` files only) that must yield `false`; PLUS a structural anchor over the live tree: every
tracked file that appears as a command-position operand in the `smoke-tests` job text (the token after `node`, `bash`, `sh`, `python3`, `python`, `source`, `.`, `jq -f`,
`npx`, or a leading `./`, any `uses: ./` path, and any `.gitleaks*` operand) must match `SUBJECT_RE`, so adding a step that runs a real tracked file outside the pattern
reddens the suite. Runtime-created fixture paths, `mkdir -p` and `git mv` operands and paths inside `echo` text are not operands and are never considered. (2) *The
failure shapes of the fetch*: non-zero exit, page-then-failure (page one without a subject file, the subject file only on the failed page two), an empty list, an entry
count that differs from `CHANGED_FILES` in either direction (including a count at the 3000-entry cap), a matcher error (`SUBJECT_RE` replaced by `(`). (3) *The verdict's
consumers and wrapper*: the `smoke-tests` `if:` (exact-string equality with the literal in Part B), `smoke-tests.needs` exactly `smoke-relevance`, no other job in the workflow
listing `smoke-relevance` or `smoke-tests` in `needs`, the job `outputs.smoke` expression, the step `id`, the step `env:` values taken from the extracted workflow (not
hard-coded in the suite), the job `permissions` and `if:`, no `continue-on-error`, exactly one `run:` step, and the step writing exactly one `smoke=` line, last.

**Mutation matrix** (each row is executed by the suite against a MUTATED COPY of the extracted body or parsed workflow, with an exact-string replace that asserts it
matched exactly once and changed the text, and counts a mutant as caught only on the suite's own rc 1 with the expected `::notice::` reason string, never on rc 2 or 127):

| # | Mutation (must make `bash scripts/secret-scan-smoke-gate.test.sh` RED) | Targets |
|---|---|---|
| 1 | Make `SUBJECT_RE` never match, or delete any one alternative (workflow file, `.gitleaks.toml`, `.gitleaksignore`, scripts prefix, git attributes/ignore, `smoke/`) in turn, or narrow the prefix to the four literal file names | the named-list and prefix rows: each member must yield `true`, so a single dropped alternative reddens a specific row |
| 2 | Add a second path reference after a compliant first, naming a REAL tracked file outside the pattern (for example a `bash scripts/lint-workflows.sh` line in a copy of the `smoke-tests` job text), with the gate unchanged; the extractor is first run on the unmutated text as a known-positive control | the operand anchor must report the new operand by name (a check that stops at the first member); a mutant naming a non-existent file proves nothing and is not used |
| 3 | Make the operand extraction return fewer than the measured 4 distinct tracked operands, or the YAML extraction find 0 steps (rename the job, break the extraction) | the suite's own dispatch: 0 operands or 0 extracted steps must FAIL, not pass |
| 4 | Change the capture to `lines=$(gh api ... \|\| true)`, drop `--paginate`, or let the shim emit page one and then exit non-zero | a failed or partial fetch must still yield `true`; the shim serves page one only without `--paginate` |
| 5 | Remove the empty-list guard, the `CHANGED_FILES` comparison, the `rc` case (treat grep rc 2 as no-match), or the `previous_filename` branch (one mutant each) | an empty list, a count mismatch in each direction (and exactly 3000), a matcher error, and a rename out of and into a subject path must yield `true`, each asserting its own reason string so one arm cannot pass for another |
| 6 | Move the `GITHUB_OUTPUT` write before the `GITHUB_STEP_SUMMARY` write and make the summary write fail, or make the step write `smoke=` twice | the output is written last and once; the `if:` also treats a non-success detect job as run |
| 7 | Edit the extracted `if:` (drop the `result != 'success'` arm, flip `!= 'false'` to `== 'true'`, drop `!cancelled()`, drop the event conjunct), change `needs`, or add `needs: smoke-relevance` to any other job | exact-string equality on the `if:`; the wrapper assertions; required jobs (derived from `scripts/required-checks.txt` names mapped to job `name:`) keep reporting with no edge to the gate |

Harness rows (edits to the SUITE, not the guard): (H1) replace the extracted body with a stub that writes `smoke=false` to `GITHUB_OUTPUT`: the shared row function, run against
the stub, must report failures above 0 on the named-list rows, and a stub writing `smoke=true` must fail the non-subject control, so the suite distinguishes the two
verdicts; (H2) a suite that runs fewer assertions than its measured count must exit non-zero, written as the `guard-vacuity-floor` shape (`-lt <literal>` on a counter, with
`_total=` and `_FLOOR=` contiguous, reporting through a direct `printf` and `exit 1`), not `-eq 0`. Must-PASS non-canonical input: a two-page list (two JSON arrays, the subject
file on page two, `CHANGED_FILES` matching) must yield `true`, and a list of only `knowledge-base/` and `plugins/` files with a matching `CHANGED_FILES` must yield `false` (a gate
that rejects everything cannot pass this row); a hostile-name fixture (`docs/a` followed by a newline and `::error::x`, and `docs/b` followed by a newline and `smoke=false`) must leave
exactly one `smoke=` line in `GITHUB_OUTPUT` and no stdout line starting with `::` other than the single notice. The `gh` shim validates the exact endpoint
(`repos/<GH_REPO>/pulls/<PR_NUMBER>/files?per_page=100`), whitelists the real flags (`api`, `--paginate`, `--jq`), exits non-zero when `GH_TOKEN` is unset as real `gh` does, applies the
passed `--jq` with real `jq` per page, flushes page one before failing in page-then-fail mode, and logs every call so the suite proves it was used. One assertion: no tracked file in the subject
set has mode 120000 (`git ls-files -s`).

**Pre-merge limit, stated, and how it is narrowed.** The suite proves the `if:` text and the step body; it cannot prove GitHub's `needs`/status-function skip semantics, and
the `false` arm cannot be exercised on this PR as written (its diff touches the workflow file). Phase 6 therefore adds a two-commit scratch canary (revert commits, no
force-push): one narrows `SUBJECT_RE` so the PR emits `smoke=false` and the ten rows skip with `smoke-relevance` green; one adds an early `exit 1` before the output write so
the empty-output arm must run the matrix. `actionlint` expression checking in `scripts/lint-workflows.sh` and the Phase 7 post-merge canary complete the evidence.

**Anchor.** The matcher is compared with a set read from the live tree (the operands of the smoke job), not only with a stored value, so one diff cannot leave the pattern behind
while adding a file the job executes. The stored part is the named list in the suite, which the same diff could edit; its independent anchor is the post-merge measurement (the
census `STEM` rows: smoke ran versus skipped per `secret-scan.yml` PR run, set against the share of PRs that touched the subject paths) attached to #9727.

### Guard 2 - Census self-check (`scripts/ci-demand-census.sh`)

**Property.** `TOTAL_JOB_MINUTES` is printed only when every completed run in the listing was fetched, every run's jobs were fetched in full, and at least one job was examined;
any shortfall exits 3 with no total.

**Assembly.** The chokepoint is the aggregator both modes share (live mode fetches into the same directory layout fixture mode reads). The three checks run over the whole set, not
a prefix: C1 over every run-listing file (unique ids against the first page's `total_count`), C2 over EVERY completed run's jobs file (existence and `length == total_count`,
accumulated across all runs before the verdict), and non-vacuity over the totals. The classification predicate (`runner_id > 0`, not skipped, both timestamps set) is a second
assembly: the golden fixture carries one job per clause that violates only that clause.

**Mutation matrix** (every row asserts `rc == 3` exactly plus a reason keyword on stderr, so an rc 2 crash never counts as caught):

| # | Mutation | Targets |
|---|---|---|
| 1 | Delete the jobs file of one completed run, varying which (first, middle, last), then of TWO runs after a compliant first | C2 existence: exit 3, no `TOTAL_JOB_MINUTES` line, and the message names every missing run (a loop that stops at the first failure, or skips the last run, fails) |
| 2 | Remove one job from a jobs file but keep its `total_count` | C2 truncation: exit 3 |
| 3 | Raise a runs-listing `total_count` above the runs present (the 1000-result cap), or duplicate one run so that the unique count is one short of `total_count` | C1: exit 3 with the narrow-the-window message; and, separately, a pure duplicate whose unique count equals `total_count` must exit 0 with the golden unchanged |
| 4 | Empty `runs-*.json` (listing `total_count` 0), an empty file, or a window whose every job is skipped | non-vacuity (the guard's own dispatch): refuse with exit 3 (an unreadable file is exit 2, pinned), never print `TOTAL_JOB_MINUTES=0` |
| 5 | Golden totals over a fixture with one job per clause: a runner-less cancelled job (`runner_id` 0) and a second with `runner_id` null, two untimed jobs (null `started_at`, null `completed_at`), a synthetic skipped job with `runner_id` > 0 and both timestamps set (labelled synthetic), and an in-progress run with a decoy jobs file | the classification predicate, one clause per job, each with a different power-of-two duration so a dropped clause shifts the golden by a unique amount; the partition `counted + skipped + runnerless + untimed = total` is asserted |

Harness rows: (H1) replace the script with a stub printing the golden `TOTAL_JOB_MINUTES`: rows 1 to 4 must go RED against it (the golden number alone cannot satisfy the
failure rows); (H2) the vacuity floor, in the same `guard-vacuity-floor` shape as Guard 1. Must-PASS non-canonical input: the committed fixture's jobs file for one run is two
`--paginate` documents (a different layout from a single document) and still yields the hand-computed total; the `STEM` rows are asserted over a stem present in only some runs, a job
name with no suffix, a nested parenthesis, an `@refs/...` path suffix, two dynamic runs with different names on one path (one row), and the same stem in two workflows. A `gh` shim
serving the committed fixture per endpoint (exact endpoints, whitelisted flags) covers the live layer: the fetched directory round-trips to the same golden; a failure on run k exits 2
naming run k; an `--end` in the future, a malformed timestamp, a non-numeric run id and `GITHUB_ACTIONS=true` all exit 2. A hostile-name job (an ESC byte, a tab, a leading `::`) must yield
one clean output line with no ESC byte and no line starting with `::`.

**Anchor.** The checks compare the fetch against counts the API reports in the same payload (`total_count`), so a single diff to the script cannot weaken them without also editing
the fixtures' own `total_count` fields. There is no stored value to anchor; the hand-computed golden is the only reference the suite asserts. The live reproduction of the parent plan's
re-measure window (8,414 job-minutes on the re-run) is reported next to the baseline with its explanation and is not asserted.

## Architecture Decision (ADR/C4)

### ADR

No new architectural decision. ADR-276 stays `proposed` and gains, as an in-scope task of this PR, a short dated `## Amendment 2026-10-08 (S1, #9727)`
plus the dated Stage-status line `2026-10-08 S1 amended` (append-only, below the table). Three sentences of substance: S1 delivered the census script and
the smoke path gate; the weekly smoke arm was dropped because the claim never existed in the tree; no other stage is activated (S1 moves no required
context, fails open and rolls back by revert, as the Status section already says). The amendment also corrects one Status sentence: the S1 smoke gate does not
"run unconditionally off `pull_request`"; the job and `smoke-tests` are `pull_request`-only and nothing runs off-PR. On Decision 3(e) it reports minutes (net, per the
Phase 7 criterion) and states that an escape rate is not defined for a non-required, PR-only job whose smoke legs never run off-PR. Two operator-facing lines: how to measure (the copy-pasteable census
command for a closed 6h window, with the 1000-result cap noted) and how to roll back (delete the `needs:` and `if:` gate on `smoke-tests`, or revert the PR,
which also reverts the ledger bump and the registrations). The `live` line is NOT appended in this PR: it needs the post-merge census, so the S2 or S3
amendment (whichever lands first) carries `S1 live` citing the attached census, or a docs commit after the Phase 7 evidence does. The operator rule
settles whether to amend; the ADR's "neither appends an amendment" is the minimum it requires of S1. `bash scripts/check-adr-ordinals.sh` must still pass.

### C4 views

Read all three model files conceptually via the parent plan's pass and re-ran the parity gate on this
branch: `bash plugins/soleur/test/c4-count-parity.test.sh` prints "ALL TESTS PASSED" (0 failed). Enumeration:
(a) external human actors: none new; (b) external systems: `github` is already modeled and the change adds
no vendor edge (the census calls the GitHub API from a developer shell or CI, an edge `github -> ...` already
described as CI/CD); (c) containers/data stores: none (the census writes a temp directory); (d) actor to
surface access changes: none. No C4 edit. The workflow-count and monitor-count cardinalities embedded in edge
prose do not move (a job is added, not a workflow).

### Sequencing

Single PR; the amendment lands with the stage it describes.

## Observability

Code-class files change (`scripts/`, `.github/workflows/`), so the block is emitted.

```yaml
liveness_signal:
  what: the census report attached to #9727 after merge (before and after STEM rows for secret-scan.yml, with the ran-versus-skipped split), plus the smoke-relevance job's `::notice::` line and step summary on every PR run stating smoke=true|false and why
  cadence: per PR run for the notice; the census on demand (S2, S3, S4 and S5 each re-run it)
  alert_target: the stage tracking issue #9727 (census attachment) and the PR check row `smoke-relevance`
  configured_in: .github/workflows/secret-scan.yml (smoke-relevance) and scripts/ci-demand-census.sh
error_reporting:
  destination: workflow run annotations (::notice:: / ::error::) and the red check row `smoke-relevance`; the census writes failures to stderr with exit 3
  fail_loud: true
failure_modes:
  - mode: gate skips smoke although a subject file changed
    detection: scripts/secret-scan-smoke-gate.test.sh executes the extracted step body for each named subject file and checks every command-position operand of the live smoke job against the pattern (runs in the test-scripts battery on every PR and merge_group)
    alert_route: red `test` context
  - mode: file-list fetch fails, is truncated, or lags the pushed head
    detection: the step emits smoke=true with a ::notice:: naming the reason (fail-open; the listed entry count must equal the event's changed_files); the smoke legs then run, so the cost is minutes, not coverage
    alert_route: the notice in the run log and, if the job itself errors, a red non-required `smoke-relevance` row
  - mode: census undercounts (truncated pagination, the 1000-result cap, runner-less jobs)
    detection: self-checks C1, C2 and the non-vacuity check exit 3 with no total; the classification predicate is proved clause by clause by golden fixture jobs in scripts/ci-demand-census.test.sh
    alert_route: red `test` context for the suite; exit 3 and stderr for a live run
logs:
  where: GitHub Actions run logs for the PR run; the census output is the attachment on #9727
  retention: GitHub default run retention; the census attachment is permanent on the issue
discoverability_test:
  command: bash scripts/ci-demand-census.sh --fixture scripts/fixtures/ci-demand-census/basic --summary
  expected_output: TOTAL_JOB_MINUTES
```

The command runs offline in well under the 15 s cap and the fixture directory is committed in this PR.
`expected_output` is the literal key; the suite pins the full line (`TOTAL_JOB_MINUTES=<golden>`) so the value
is asserted where it is hand-computed.

## Domain Review

**Domains relevant:** engineering

### Engineering (CTO)

**Status:** reviewed (carried forward)
**Assessment:** The parent plan's CTO review and the DHH, Kieran and code-simplicity verdicts on Stage 1
(parent plan "Staged rollout" paragraph) already scoped S1 as a small census script plus an optional,
droppable, non-required, fail-open smoke gate. This plan implements exactly that scope and adds nothing the
CTO flagged as blocking (no required context, no supply change, no authority change). A fresh domain-leader
spawn was not run: the only new engineering judgments (drop the weekly arm; extract-and-execute test rather
than a verdict script) are recorded in the Cut List for the plan-review panel.

No product, UX, marketing, legal, finance, sales or support surface is touched (no UI-surface path in
`Files to Create` or `Files to Edit`; no regulated-data surface; no new store or connection; no infrastructure
provisioned).

## User-Brand Impact

- **If this lands broken, the user experiences:** nothing directly: a broken gate can only fail to run the
  secret-scan smoke self-tests on a PR, so a regression in the secret-scan machinery (allowlist, rename-guard,
  fixture linter) could reach `main` unnoticed until the next PR that touches those files; the five
  required secret-scan contexts keep scanning every PR and every merge candidate.
- **If this leaks, the user's workflow is exposed via:** no data surface. The census reads public-repo run
  metadata (the repository is public) and the new job reads the PR file list with a read-only token.
- **Brand-survival threshold:** `aggregate pattern`
- **Threshold decision (challengeable):** the diff touches a sensitive path by regex
  (`.github/workflows/secret-scan.yml` matches the `secret` alternative), but the changed jobs are
  self-tests of the gate, not the gate: the required scanners are untouched, so one user's secret cannot
  reach the repository through this change alone. `none` would need a scope-out bullet; `aggregate pattern`
  needs none.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "Implement #9727 (S1 of the hosted-runner CI demand plan: census script scripts/ci-demand-census.sh + path-gate for the secret-scan smoke-tests matrix)." [brief] | Part A, Part B | mapped |
| 2 | "A small census script that implements the plan's Measured-state method: `gh api --paginate` to a file, `jq -s` to flatten, runner-bound non-skipped jobs only, totals per workflow and event, `CI` per-family per-run minutes, and one job-count self-check against the runs listing." [issue #9727] | Part A | mapped |
| 3 | "Register its suite and confirm with `bash scripts/lint-orphan-test-suites.sh`." [issue #9727] | Phase 4 (registration, classification, lint run) | mapped |
| 4 | "path-gate the secret-scan `smoke-tests` matrix on `pull_request` (lever 4a ...)" [issue #9727] | Part B | mapped |
| 5 | "a weekly arm must be added with its own test or the \"weekly full coverage\" claim dropped" [issue #9727] | Cut List, Reconciliation row 1 (claim dropped) | mapped |
| 6 | "the gate must run unconditionally on non-PR events (no diff base there)" [issue #9727] | Satisfied structurally by the job-level and `smoke-tests` `pull_request` conditions; Reconciliation row 2 | mapped |
| 7 | "a new `smoke-relevance` job raises the declared count and needs a `scripts/pr-fanout-ledger.txt` bump" [issue #9727] | Phase 3 (ledger row 6 to 7) | mapped |
| 8 | "Needs its own Guard Contract for the smoke gate (property, assembly, a mutation matrix of at least three rows) in its own plan." [issue #9727] | Guard Contract, Guard 1 | mapped |
| 9 | "`bash scripts/ci-demand-census.sh --fixture <dir> --summary` prints a `TOTAL_JOB_MINUTES` line." [issue #9727] | Part A outputs, Observability | mapped |
| 10 | "Exit: the census is attached to this issue (#9727); smoke minutes down at least 80% on PRs that miss the subject paths." [issue #9727] | Phase 7 (post-merge census and attachment) | mapped |
| 11 | "PR body must contain `Closes #9727` and end with the line \"🤖 Generated with [Claude Code](https://claude.com/claude-code)\". Every commit message ends with \"Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>\"." [brief] | Phase 6 (PR body and commit trailers) | mapped |
| 12 | "ADR-276: operator rule is that each stage PR appends a dated amendment before that stage takes effect ... keep status \"proposed\"." [brief] | Architecture Decision (ADR), Phase 5 | mapped |
| 13 | "Register the census suite and run `bash scripts/lint-orphan-test-suites.sh`; bump scripts/pr-fanout-ledger.txt if a new smoke-relevance job raises the declared count." [brief] | Phases 3 and 4 | mapped |
| 14 | "poll with the Monitor tool, never Bash run_in_background. No git stash, no force-push." [brief] | Phase 6 operating rules | mapped |
| 15 | "Provision nothing for lever 5." [brief] | Cut List (no supply work); Overview | mapped |
| 16 | "Leave the main checkout's uncommitted .mcp.json and staged scripts/followthroughs/watchdog-debounce-soak-9686.sh untouched. Do not touch the already-merged CI PRs from 2026-10-07." [brief] | Files lists name neither; no work-phase command touches the main checkout | mapped |
| 17 | "Plan S1 only; later stages are out of scope." [brief] | Overview, Non-Goals | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| `scripts/ci-demand-census.sh` | "census script scripts/ci-demand-census.sh" | asked (ask 1, 2) |
| `scripts/ci-demand-census.test.sh` and `scripts/fixtures/ci-demand-census/` | "Register its suite" | asked (ask 3); the discoverability test also needs the committed fixture (ask 9) |
| `smoke-relevance` job and `smoke-tests` `if:` edit in `secret-scan.yml` | "path-gate the secret-scan `smoke-tests` matrix on `pull_request`" | asked (ask 4) |
| `scripts/secret-scan-smoke-gate.test.sh` | "Needs its own Guard Contract for the smoke gate" | asked (ask 8): the contract's mutation matrix must be executable or it is paper |
| `scripts/pr-fanout-ledger.txt` row edit | "needs a `scripts/pr-fanout-ledger.txt` bump" | asked (ask 7) |
| `scripts/test-all.sh`, `scripts/lib/test-affected-paths.sh`, `scripts/suite-durations.tsv`, `scripts/suite-shard-legs.tsv` edits | "Register its suite and confirm with `bash scripts/lint-orphan-test-suites.sh`" | asked (ask 3); the classification and shard manifests are what the lint and the shard-totality gates require of a registration |
| ADR-276 amendment and Stage-status line | "plan to append a short dated amendment anyway for S1" | asked (ask 12) |
| Generic `STEM` table (job-name stems for every workflow, with `runs_with_stem`) | "smoke minutes down at least 80% on PRs that miss the subject paths" | inferred: the exit criterion is a per-job-stem, ran-versus-skipped measurement and the per-workflow table cannot isolate the ten `smoke` legs from the other secret-scan jobs; one generic table (not a flag and a second table) also yields the `CI` families, so the committed authority (ADR-276 Decision 7) can verify the criterion |
| Guard 2 (census self-check C1, C2, non-vacuity) and its five-row matrix | "one job-count self-check against the runs listing" | asked in part (ask 2); the matrix is inferred from the parent plan's Observability failure mode and Guard Contract requirement, because a self-check with no row proving it can fail is the vacuous guard the contract exists to prevent |
| Header comment amendments in `secret-scan.yml` (permissions line, new job rationale) | "Plan S1 only" | inferred: the file's header states "contents: read ONLY"; leaving it false after adding a job-level `pull-requests: read` is a documentation lie the next reader acts on |
| `.github/CODEOWNERS` line for `scripts/secret-scan-smoke-gate.test.sh` | "Plan S1 only" | inferred: the gate is a cost optimisation that a PR can edit to skip its own smoke, so review ownership of the suite that pins it is the only control; the other secret-scan scripts already have CODEOWNERS entries |
| Phase 6 scratch canary (two revert-able commits exercising the `false` and empty-output arms pre-merge) | "Needs its own Guard Contract for the smoke gate" | inferred: the suite cannot prove GitHub's `needs`/status-function semantics and this PR's own diff only exercises the `true` arm; without it the `false` arm is first exercised on `main` |
| Runbook paragraph in `knowledge-base/engineering/operations/secret-scanning.md` | "Plan S1 only" | inferred: the runbook describes the smoke matrix as always running on PRs; after the gate it is skipped by design on PRs outside `SUBJECT_RE`, and leaving the runbook saying otherwise misleads the next on-call who finds ten grey rows |
| Comment on #9730 about concurrency sampling | "later stages are out of scope" | inferred: the deferral needs a tracking location (workflow rule on deferrals); #9730 already exists, so no new issue |

### Split Assessment

- Subsystems touched: 3 (`scripts/`, `.github/workflows/`, `knowledge-base/`), within the 4-root threshold
- Planned files: about 19 (3 new scripts, a fixture directory of about 7 JSON files, `tasks.md`, 9 edits including CODEOWNERS) | Estimated changed lines: about 650, over the issue's 250-line estimate but under the 800-line threshold; roughly 170 are the census script, 55 workflow YAML, and the rest tests, fixtures, runbook and ADR text (after plan review cut the closure walker, the expression evaluator and most harness-of-harness rows, and deepen-plan added back the fetch-layer shim, the wrapper assertions and the per-clause fixture rows)
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR. The two parts are independent (the gate could ship alone) but share one issue and one ledger/registration pass; splitting adds a second CI cycle for no risk reduction.

## Plan Review Outcome

Panel: DHH, Kieran, code-simplicity (per mechanism, against the Property and Cut Lists) and the CTO devex lens (named panel; the other named
leaders were not activated: no product, UX, market or brand surface). The simplification panel (DHH, code-simplicity, CTO) and the correctness panel
(Kieran) fired on the same scope, the transitive closure walker, so it was deleted rather than repaired (its exclusion list was a day-one false positive
source). Applied as mechanical: closure walker replaced by a named list plus a command-position operand anchor; `if:` evaluator replaced by exact-string
equality, `actionlint` and two canaries; in-body event and PR-number guards, JSON output, `--out`, `meta.json`, `--repo`, `--stems`, the hard-coded family list
and the harness-of-harness rows removed; one generic `STEM` table with `runs_with_stem` so the exit criterion is measurable (Kieran); `per_page=100`;
the permissions header reworded (Kieran: `allowlist-diff` already has a job-level write); runbook paragraph, step summary line and job name, ADR rollback and
measure pointers, census definitions (lower bounds, rate limit) added. Taste items (declined or accepted risk) are in
`knowledge-base/project/specs/feat-one-shot-9727-ci-census-smoke-gate/decision-challenges.md`. No finding argued the operator's stated scope should change.

## Implementation Phases

Order follows `cq-write-failing-tests-before`: each suite lands before the code it guards.

### Phase 1 - Fixture and RED suites

1. `scripts/fixtures/ci-demand-census/basic/`: synthesized `runs-1.json` (about 7 runs: `ci.yml` on `pull_request`, `merge_group` and `push`; a `secret-scan.yml`
   `pull_request` run with `smoke (...)` legs and one with a skipped `smoke` stem plus a `smoke-relevance` job; a dynamic CodeQL run named per PR; a run with
   `total_count` 0 and no jobs; one in-progress run with a decoy jobs file of large minutes) and `jobs-<run_id>.json` files: matrix-suffixed names, one job per
   classification clause (a runner-less cancelled job with `runner_id` 0 and a second with `runner_id` null, two untimed jobs with null `started_at` and null
   `completed_at`, a labelled-synthetic skipped job with `runner_id` > 0 and both timestamps set), each with a different power-of-two duration, and one two-document
   (`--paginate`-shaped) jobs file. Job field names come from a real response (`gh api .../jobs?per_page=1`), values are synthetic: IDs are small integers, SHAs are
   obviously fake (`0000...`-style, no entropy), no logins or emails; run `gitleaks dir scripts/fixtures/ci-demand-census` if the binary is installed, otherwise the PR's
   gitleaks job is the gate (the `lint-fixture-content` glob does not cover `scripts/fixtures/`). Goldens are hand-computed in the suite from integer seconds.
2. `scripts/ci-demand-census.test.sh`: golden totals and tables, Guard 2 rows 1 to 5, H1, H2, the live-layer `gh` shim round trip, mutants made by `jq` edits into
   `mktemp -d` only, append-only failure ledger, the `guard-vacuity-floor` shape for the assertion floor, `TMPDIR=${TMPDIR:-/var/tmp}`, and a check that the script's header
   documents the closed-window and lower-bound definitions.
3. `scripts/secret-scan-smoke-gate.test.sh`: extracts the step body, its `env:`, the job wrapper and the `smoke-tests` `if:` from the workflow with PyYAML (precedent
   `skill-security-scan-step-body.test.sh`) and runs the body under `bash --noprofile --norc -eo pipefail` with `GITHUB_OUTPUT` and `GITHUB_STEP_SUMMARY` pointing into a temp dir
   and the `gh` shim described under Guard 1. Guard 1 rows 1 to 7, H1, H2, the named-list and prefix rows (modification and rename source), the operand anchor with its
   known-positive control, the wrapper equalities and the hostile-filename fixture. The suites are RED at this commit by design (no script, no job yet).

### Phase 2 - Census script

Implement `scripts/ci-demand-census.sh` to the interface above until its suite is green. Then run it live once over the parent plan's window
(`--start 2026-10-07T13:04:00Z --end 2026-10-07T19:04:00Z`) as the baseline and compare the total with the parent plan's re-measure (8,414); a
difference gets an explanation in the attachment (the lower-bound definitions), not a fixture edit.

### Phase 3 - Smoke gate

Edit `.github/workflows/secret-scan.yml` (new job, `smoke-tests` `needs:` and `if:`, the `SUBJECT_RE` rationale comment, the permissions header
reword). Bump `scripts/pr-fanout-ledger.txt` `secret-scan.yml` 6 to 7 with the consequence appended ("+1 smoke-relevance (#9727, ADR-276 S1): fail-open
detect gating the non-required smoke-tests matrix; no required context has a `needs:` edge to it. Not folded into an existing job as a step (the ledger's A3 remedy) because
the verdict must be a job-level output consumed through `needs:`, and folding it into a required job would couple a required context to the gate"). Add `scripts/secret-scan-smoke-gate.test.sh` to `.github/CODEOWNERS` next to the secret-scan entries. Add the runbook paragraph to
`knowledge-base/engineering/operations/secret-scanning.md`. Verify with `bash plugins/soleur/test/pr-fanout-ledger.test.sh`, `bash scripts/lint-workflows.sh`
(actionlint expression checking), `bash scripts/guard-vacuity-floor.test.sh` and the lints in the Acceptance Criteria.

### Phase 4 - Registration

`scripts/test-all.sh`: two `run_suite` lines (`scripts/ci-demand-census`, `scripts/secret-scan-smoke-gate`) at the end of the `scripts/` block
(positional shard fallback keys on registration ordinal; see the neighbours' comments). `scripts/lib/test-affected-paths.sh`: the census suite is reached
by the name-stem convention; the gate suite reads the workflow, so declare `AFFECTED_SCRIPTS_SECRET_SCAN_SMOKE_GATE_PATHS` (the workflow, the suite,
`scripts/lib/test-affected-paths.sh`, and the `apps/web-platform/scripts/` entries it names) as its neighbours do, or classify per whatever
`lint-orphan-test-suites.sh` demands. The consumer of that list is `scripts/test-all.sh`'s affected resolution (the line `_arr="AFFECTED_${_u}_PATHS"`),
which selects the suite when a diff path equals a file entry or starts with a directory entry; entries are anchored, so a directory entry carries a
trailing `/`. Suite cost, stated rather than assumed: the census suite runs the script about 15 times over a few-KB fixture, and the gate suite executes the
extracted step body about 25 times with PyYAML parsing the workflow once; both are expected to finish in a few seconds, and the real durations replace the
manifest estimates when the shard manifests are regenerated with `python3 scripts/regenerate-shard-manifest.py --incremental --write` (confirm "0 at
floor"). Run `bash scripts/lint-orphan-test-suites.sh` and the shard-totality suites it names; fix the classification, never silence the census.

### Phase 5 - ADR amendment

Append the S1 amendment and the dated Stage-status line to ADR-276 (status stays `proposed`); run `bash scripts/check-adr-ordinals.sh`.

### Phase 6 - Verify, push, PR

Run every command in the Acceptance Criteria. Commit with the required trailer (`Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`), push (no
force-push), update PR #9772 (body contains `Closes #9727`, ends with the `🤖 Generated with [Claude Code](https://claude.com/claude-code)` line). Poll CI
with the Monitor tool, not a background Bash. This PR edits `secret-scan.yml`, so its own `smoke-relevance` must read `smoke=true` and all ten legs run
(a live canary of the `true` arm and of the `needs`/`if:` semantics). Then run the **scratch canary** with two revert-able commits (revert commits, never a force-push; the
final tree equals the intended one): commit one narrows `SUBJECT_RE` so it no longer matches the workflow file, so the PR must emit `smoke=false`, the ten `smoke` rows must
skip and `smoke-relevance` must be green; commit two adds an early `exit 1` before the output write, so the empty-output arm must run the matrix. Revert both before marking
ready. This PR edits `.github/workflows/`, so `admin-merge-ready.sh` reports UNTRUSTED-CI for it: it merges through the normal queue or auto-merge, never the agent `--admin`
path. `Closes #9727` will auto-close the issue at merge, before its post-merge exit evidence exists; Phase 7 therefore comments on the closed issue rather than leaving the
evidence unattached.

### Phase 7 - Post-merge

1. Run the census over a closed post-merge window (it fetches in one-hour sub-windows, so 6 hours or more is fine), plus the Phase 2 baseline, and attach both to #9727
   with `gh issue comment 9727 --body-file`, inside a code fence. The `STEM` rows for `secret-scan.yml` `pull_request` give `runs_ran`, `runs_skipped` and `runs_runnerless`
   for the `smoke` stem and the cost of the `smoke-relevance` stem. Runs started before the merge used the old workflow, so report the coverage ratio
   (`smoke-relevance` runs over PR runs) and take the after-figures from the post-merge runs only.
2. Exit criterion, net: secret-scan smoke-related minutes per PR run (the `smoke` stem plus the `smoke-relevance` stem) down at least 80% against the baseline window, with the
   skip share reported next to the share of PRs that touched subject paths (expected about 9%, from the sizing above).
3. Live canary of the `false` arm on `main`: on the first post-merge PR that touched no subject path, `gh run view` shows `smoke-relevance` success and the ten `smoke` rows
   skipped. If no such PR appears within 48 hours, the census split alone is the evidence.
4. Comment on #9730 (S5): concurrency sampling was left out of the census and belongs to S5's re-measure.

## Files to Create

- `scripts/ci-demand-census.sh`
- `scripts/ci-demand-census.test.sh`
- `scripts/secret-scan-smoke-gate.test.sh`
- `scripts/fixtures/ci-demand-census/basic/runs.json`
- `scripts/fixtures/ci-demand-census/basic/jobs-<run_id>.json` (one per completed fixture run, ids synthetic)
- `knowledge-base/project/specs/feat-one-shot-9727-ci-census-smoke-gate/tasks.md`

## Files to Edit

- `.github/workflows/secret-scan.yml` (new `smoke-relevance` job; `smoke-tests` `needs:` and `if:`; header comments)
- `scripts/pr-fanout-ledger.txt` (secret-scan row: jobs 6 to 7, consequence text)
- `.github/CODEOWNERS` (one line for `scripts/secret-scan-smoke-gate.test.sh`, next to the secret-scan entries)
- `scripts/test-all.sh` (two registrations)
- `scripts/lib/test-affected-paths.sh` (the gate suite's `AFFECTED_*_PATHS` block, or the classification the lint requires)
- `scripts/suite-durations.tsv`, `scripts/suite-shard-legs.tsv` (regenerated by `regenerate-shard-manifest.py --incremental --write`)
- `knowledge-base/engineering/operations/secret-scanning.md` (one paragraph: smoke is skipped by design outside `SUBJECT_RE`, and the gate fails open)
- `knowledge-base/engineering/architecture/decisions/ADR-276-demand-first-hosted-runner-budget-merge-group-is-the-full-battery-authority.md` (S1 amendment, Stage-status line; status stays `proposed`)

Path-glob check: every path above was confirmed with `git ls-files` on this branch, except the files under "Files to Create", which do not exist yet by
definition. The `SUBJECT_RE` alternatives each match at least one tracked file (`.github/workflows/secret-scan.yml`, `.gitleaks.toml`, `.gitleaksignore`,
and four files under `apps/web-platform/scripts/`).

## Non-Goals

- S2 to S5 (push-run dedupe, draft light checks, affected-only PRs, CodeQL/Code Quality/supply decision).
- A weekly smoke arm, a kill-switch variable, concurrency sampling, any required-context change.
- Editing the already-merged 2026-10-07 CI PRs or the main checkout's `.mcp.json` and staged follow-through script.

## Acceptance Criteria

<!-- founder-stated check: see plan-founder-check.md -->

### Pre-merge (PR)

- [ ] `bash scripts/ci-demand-census.test.sh` exits 0 with a non-zero assertion count; every Guard 2 row and the harness row are asserted (the suite fails against a stub that prints the golden `TOTAL_JOB_MINUTES`).
- [ ] `bash scripts/secret-scan-smoke-gate.test.sh` exits 0; every Guard 1 row (1 to 7), H1 and H2 are asserted; a run that extracts 0 steps or fewer than 3 operands exits non-zero.
- [ ] `bash scripts/ci-demand-census.sh --fixture scripts/fixtures/ci-demand-census/basic --summary` prints a line matching `^TOTAL_JOB_MINUTES=` and the suite pins its value to the hand-computed golden.
- [ ] A run against a truncated copy of the fixture exits 3 and prints no `TOTAL_JOB_MINUTES` line.
- [ ] `python3 scripts/lint-guard-contract.py knowledge-base/project/plans/2026-10-08-chore-ci-demand-census-and-smoke-path-gate-plan.md` reports 2 guard entries, each with a matrix of at least 3 rows.
- [ ] `bash scripts/lint-orphan-test-suites.sh` and `bash scripts/guard-vacuity-floor.test.sh` exit 0 with both new suites registered, classified and carrying a conforming assertion floor.
- [ ] `bash plugins/soleur/test/pr-fanout-ledger.test.sh` passes with the secret-scan row at 7 jobs; `python3 -c "import yaml;print(len(yaml.safe_load(open('.github/workflows/secret-scan.yml'))['jobs']))"` prints 7.
- [ ] `python3 scripts/lint-workflow-step-env-refs.py`, `python3 scripts/lint-workflow-errexit-capture.py`, `python3 scripts/lint-workflow-run-body-syntax.py` and `bash scripts/lint-workflows.sh` exit 0.
- [ ] No required job in `secret-scan.yml` lists `smoke-relevance` in `needs:`, and `smoke-relevance` is absent from `scripts/required-checks.txt` (asserted by Guard 1 row 7, not by whole-file grep).
- [ ] `bash plugins/soleur/test/c4-count-parity.test.sh` and `bash scripts/check-adr-ordinals.sh` pass; ADR-276 `status:` is still `proposed` and the amendment plus the dated `S1 amended` line are present.
- [ ] The workflow header no longer says "contents: read ONLY" without naming the job-level exceptions; the runbook paragraph is present.
- [ ] PR #9772 body contains `Closes #9727` and its last line is `🤖 Generated with [Claude Code](https://claude.com/claude-code)`; every commit message ends with `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`.
- [ ] CI is green on the PR, including this PR's own `smoke-relevance` reading `smoke=true` (the workflow file is in its diff) and all ten smoke legs running; the Phase 6 scratch canary showed `smoke=false` with the ten rows skipped and the empty-output arm running the matrix, and both scratch commits are reverted.
- [ ] `.github/CODEOWNERS` names `scripts/secret-scan-smoke-gate.test.sh`; the live census run refuses `GITHUB_ACTIONS=true`, a future `--end`, a malformed timestamp and a non-numeric run id with exit 2.

### Post-merge (operator-free, run by the shipping agent)

- [ ] The baseline and post-merge census outputs are attached to #9727 (`gh issue comment 9727 --body-file`), and the baseline total is explained against the parent plan's 8,414.
- [ ] Smoke ran versus skipped versus queue-cancelled per `secret-scan.yml` PR run is reported from the `STEM` rows, with the secret-scan smoke-related minutes per PR run (the `smoke` stem plus the `smoke-relevance` stem) down at least 80% against the baseline (or the 48-hour fallback in Phase 7 is recorded).
- [ ] The #9730 comment about concurrency sampling is posted.

## Test Scenarios

- Given a PR whose only changed files are `knowledge-base/x.md` and `plugins/y.ts`, when `smoke-relevance` runs, then it emits `smoke=false` and the ten legs are skipped.
- Given a PR changing only `.gitleaks.toml`, when it runs, then `smoke=true`; the same for a rename whose OLD name was `apps/web-platform/scripts/rename-guard.sh`.
- Given `gh api` exits non-zero, or exits non-zero after emitting a first page, then `smoke=true`.
- Given a list whose entry count differs from the event's `changed_files` (a lagging list, a re-run on a newer head, or the 3000-entry cap), then `smoke=true`; given a matching count and no subject path, then `smoke=false`.
- Given a PR touching only `.gitattributes` or a nested `.gitignore`, then `smoke=true`.
- Given the smoke job gains a `bash scripts/other-helper.sh` step and `SUBJECT_RE` is unchanged, then the suite is RED.
- Given a fixture where one completed run has no jobs file, when the census runs, then exit 3 and no total line.
- Given a job with `runner_id` 0 and conclusion `cancelled`, then it contributes 0 minutes and is counted in `JOBS_RUNNERLESS`.
- Regression: the parent plan's first pass counted runner-less jobs as running and reported 9,392 instead of 7,456; the golden fixture's one-clause-per-job design fails the suite if any clause of the filter is dropped.

## Dependencies & Risks

- **Over-skipping.** The named list and the operand anchor are the countermeasures; the residual is a path reference built at runtime (a variable-assembled path), which the operand anchor cannot see. The directory prefix `apps/web-platform/scripts/` absorbs the likely case (a new helper beside the existing ones).
- **List lag.** `pulls/N/files` can lag a `synchronize` push and a re-run reads the current PR, not the run's SHA. The step therefore requires the listed entry count to equal the event's own `changed_files` and emits `true` on any mismatch, which also covers the 3000-entry cap; a stale list with an equal count is not detected and is bounded by the fact that smoke is non-required and the five required scanners still run. `smoke-tests` does not run on `merge_group`, so nothing re-reads the list at queue time (an earlier draft claimed it did).
- **`pulls/N/files` needs a read scope.** The job declares `pull-requests: read` at job level (`allowlist-diff` already carries a job-level `pull-requests: write`; the workflow level stays `contents: read`). Whether a token without it could read a public PR's files is not verified, so the scope is declared rather than assumed.
- **YAML and expression traps.** A leading `!` in `if:` is a YAML tag; `always()` would keep the matrix running on a cancelled run; both avoided and pinned by Guard 1 row 7.
- **Registration side effects.** Editing `scripts/test-all.sh` and `scripts/lib/test-affected-paths.sh` degrades the local affected gate to a full run for that diff (the runner/index self-edge); expected, and the registration-only carve-out may apply.
- **Live fetch cost.** About 930 `jobs` calls for a 6h window, sequential, a few minutes in a developer shell with `gh auth`; the 1000-result cap bounds the window size (the script says so when it bites).
- **Fix-Size drift.** About 650 lines against the issue's 250 (see Split Assessment); the extra is test code and bookkeeping the lints require.
- **Census window and rate.** A 6-hour window is about 930 jobs calls, fetched in one-hour sub-windows with a retry and progress output; a transient failure restarts the run (no resume), and live mode is refused in CI so it cannot spend the shared `GITHUB_TOKEN` budget.

## References & Research

- Parent plan: `knowledge-base/project/plans/2026-10-07-ci-reduce-hosted-runner-demand-plan.md` (Measured state, S1 row, Observability)
- ADR-276 (`proposed`) Status, Decision 3 and 7; ADR-262 (battery gate precedent); ADR-216 (ledger); ADR-032 (required-context ABI)
- Precedents: `.github/workflows/pr-quality-guards.yml` `detect`; `.github/workflows/vendor-pin-verify.yml` `detect-changes`; `scripts/skill-security-scan-step-body.test.sh`; `scripts/main-push-duplicate-skip.sh`
- Issue: #9727; related #9721, #9722 (merged), #9772 (this PR), #9730 (S5)
