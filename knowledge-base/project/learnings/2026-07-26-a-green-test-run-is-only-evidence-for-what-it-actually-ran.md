---
date: 2026-07-26
category: workflow-patterns
module: infra-testing
tags: [test-coverage, false-green, asserted-vs-measured, gate-design, infra-validation, handoff-artifacts]
issues: [6730, 6964, 6965]
pr: 6953
---

# Learning: a green test run is only evidence for what it actually ran

## Problem

The #6730 web-host birth path went through a nine-agent review that found and fixed several P1s. The
single most useful sentence to come out of it was not about any one defect:

> nearly every defect was a property **asserted** rather than **measured** — in a PR whose own gate
> comments say "MEASURED, not assumed."

That pattern showed up at four different altitudes in one PR, and the top one nearly shipped a false
green.

### 1. The test runner did not cover the code under change

`scripts/test-all.sh` does not run anything under `apps/web-platform/infra/`. Those suites are
registered **only** as `run: bash …` steps in `.github/workflows/infra-validation.yml`. Nothing said
so at the point of use. During the work a required check (`web-1-swap-concurrency-parity`) sat **RED
behind a 223/223 green `test-all`**, and it was found by reading CI, not by testing locally.

There was also no local command that ran them. Written as a serial loop, the 70 suites take well over
ten minutes and exceed a normal command timeout — so the practical options were "run nothing" or
"push and wait for CI."

### 2. A gate made entirely of prohibitions cannot catch a missing requirement

The birth gate had five arms, all of the form *the plan may not also do X*. It had no arm asserting
what the plan **must** do. Result: it passed a plan whose only entry was the server create — the exact
#6416 shape it exists to prevent. Five correct-looking assertions, zero coverage of the actual
failure mode.

### 3. An observability read that fires before its signal can exist

The post-apply Sentry read ran immediately after `terraform apply` returned. But `cloud_init_complete`
is the **last line** of cloud-init `runcmd`, and the host's own budget is
`SOLEUR_FRESH_BOOT_WINDOW_SECONDS=900`. So on a **healthy** boot the read landed in the no-match branch
and printed *"genuinely emitted nothing"* — byte-identical to what a genuinely dark host produces. The
step satisfied ADR-128 R2's letter while inverting its purpose: it could not discriminate the two
states it existed to tell apart.

### 4. Three restored assertions were vacuous

Of five assertions restored to pin the birth job's contract, three could be satisfied without the
property holding: one by a sibling step, one by its own comment, one by an unbraced spelling that
evaded the negative match.

And one level below all of this: a job-block `awk` extractor closed on the next `^  <job>:` header but
not on the **comment preamble** that precedes it, so `$JOB` ran 19 lines past the end of the job and
swallowed the next job's prose — letting a sibling job's text satisfy an assertion about this one.

## Solution

**Make the coverage boundary announce itself.** `scripts/test-all.sh` now detects an
`apps/web-platform/infra/` path in the diff and prints, after the summary, that its green is not
evidence for that change — naming the command that is.

**Give the uncovered suites a runnable local command.**
`apps/web-platform/infra/run-registered-suites.sh` derives the suite list **from
`infra-validation.yml`** rather than globbing the directory, so the runner and CI cannot drift, and
runs them with `xargs -P min(nproc,6)` — the difference between a gate people run and one they skip.

Two guards make its own green honest:

- Deriving **zero** suites is fatal, not "0 failed". A silent zero would print a pass and read as
  success — the exact false-green the script exists to end.
- It reports suites on disk that **no workflow or script references**. That check immediately found
  **9 test files nothing runs** (filed as #6965) — the same false-assurance class, one level down.

**For the gate: add a requirement arm.** The birth gate now asserts the NIC and volume attachment each
create — the two members the server's own creation entails — mutation-proven. The post-apply
create-proof loop it superseded was deleted: a check reading the same `tfplan.json` the gate already
read cannot add information, only the illusion of a second opinion.

**For the observability read: poll to a terminal state** and fail the run on a dark boot, which makes
the plan's declared `alert_route` true rather than fabricated.

**For the extractor: measure the extraction.** Capture now also closes on `^  #`, and a new AC0
asserts the block is non-empty, opens on its own header, and carries no foreign preamble. Restoring
the old `awk` takes the suite 95/0 → 94/1.

## Key Insight

**"The tests pass" is a claim about a set of tests, not about your change.** Before treating green as
evidence, establish that the runner's set actually intersects the diff. A test runner that silently
excludes a directory is indistinguishable from one that covers it — until a required check goes red
in CI behind a local all-green.

Three corollaries, all of which cost time here:

- **A gate built only from prohibitions has no lower bound.** *Never do X* constrains what a plan may
  **also** do; it never forces the plan to do the right thing. Every guard needs at least one arm that
  fails when the required thing is **absent**, and that arm has to be mutation-proven, because a
  requirement arm that cannot fail is just a longer prohibition.
- **A probe that reads before its signal can physically exist reports "nothing" as confidently as a
  real absence.** Any read against an asynchronous signal needs a deadline derived from the emitter's
  own budget, and its no-match branch has to be distinguishable from its failure branch.
- **Scope your extraction, then assert the scope.** Block extractors that close on a structural
  delimiter routinely over-collect into whatever precedes the next delimiter. If assertions inherit
  their soundness from an extraction, the extraction itself needs an assertion.

Also: **`-target` is upstream-transitive only.** Dependents of a created resource are not reached. A
web-1 birth would have stranded `cloudflare_record.app` — the DNS record pointing at the dead IP — and
finished green, because the fan-out named the server but not what depends on it.

## Session Errors

- **A handoff artifact reported gate results for two paths that do not exist.** RESUME.md listed
  `plugins/soleur/test/terraform-target-parity.test.sh` and
  `plugins/soleur/test/soleur-host-bootstrap-observability.test.sh` as green at `345b7ddc2`. Neither
  exists: the first is a `.test.ts` (run by `test-all`), the second lives at
  `apps/web-platform/infra/`. Both invocations failed with "No such file or directory."
  **Recovery:** `git ls-files | grep -E '<name>'` to locate the real paths.
  **Prevention:** a handoff's gate list must cite commands verified to *resolve*, not remembered
  ones — the same asserted-not-measured failure the PR is about, in the artifact describing it.
  Routed to the `ship` skill's resume-prompt step.

- **The serial 70-suite loop hit the 10-minute command ceiling** (exit 143) and captured zero results,
  wasting the full timeout. **Recovery:** re-ran with `xargs -P 6` in the background.
  **Prevention:** fixed at the root — `run-registered-suites.sh` now exists and parallelizes.

- **A heredoc `&&`-chained into a hook-denied command lost its write.** `cat > issue.md <<EOF … EOF &&
  gh issue create …` was rejected by the `--milestone` PreToolUse hook; because the hook denies the
  *whole* invocation, the file write never happened, and the retry failed confusingly with "no such
  file or directory" pointing at the file I thought I had just written.
  **Recovery:** rewrote the file with the Write tool, then ran `gh issue create` alone.
  **Prevention:** never chain a file write into a hook-gated command with `&&`. Write the file in its
  own step (or with the Write tool) so a denial costs the command, not the artifact. Routed to the
  `ship` skill's issue-filing step.

- **A route-to-definition edit targeted the BARE REPO instead of the worktree.** The `Edit` call
  used `/home/jean/…/soleur/plugins/soleur/skills/ship/SKILL.md` — the bare-repo path — and the
  `guardrails` PreToolUse hook denied it, naming the correct worktree path. Had the hook not fired,
  the edit would have landed on stray content on no branch and silently never shipped.
  **Recovery:** re-applied against the worktree path; confirmed with `git status --short`.
  **Prevention:** already hook-enforced, and the compound skill already carries the rule ("Always use
  worktree-absolute paths … verify after the edit with `git status --short`"). The failure was not
  reading it closely enough — no new rule warranted.

- **`comm -23` failed with "file is not in sorted order"** — locale-aware `sort -u` against an
  awk-derived list. **Recovery:** `LC_ALL=C` on both sides. **Prevention:** one-off; `LC_ALL=C` is
  already the convention in the scripts that matter (`net-issue-flow.sh` sets it at the top).

- **`gh issue create` denied for a missing `--milestone`.** One-off, and the hook did its job — the
  denial message named the fix and the correct default.

Not from this session, but observed: `scripts/rule-metrics-aggregate.sh` fails its orphan gate on 7
`rule_id`s present in the local incidents log but untagged in AGENTS.md
(`adr-033-inngest-cron-canonical`, `cq-docs-cli-verification`, `durable-reminder-prefer-inngest`,
`git-commit-secret-scan`, `hr-in-github-actions-run-blocks-never-use`, `kb-domain-allowlist-guard`,
`pre-merge-auto-close-scan`). Pre-existing and local-only; the partial write was reverted per the
compound skill's documented handling.

## Tags

category: workflow-patterns
module: infra-testing
