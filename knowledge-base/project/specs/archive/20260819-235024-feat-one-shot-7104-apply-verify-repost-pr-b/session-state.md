# Session State — PR-B

## Inherited from PR-A

PR-A (#7509) merged 2026-08-13T14:10:51Z as `c723e4519`, deployed and verified live at 0.253.7;
postmerge green. It shipped `tasks.md` Phases 1–3 (the `DPF_REPLACED` discriminator, the saved-plan
apply, the frame-stability arm) and ADR-186. Full PR-A record:
`../feat-one-shot-7104-apply-verify-repost-recovery/session-state.md`.

`Closes #7104` attaches to **PR-B**, per the operator's UC2 disposition. PR-A referenced the issue
in prose only, and #7104 is still OPEN with `closedByPullRequestsReferences: []`.

## Plan Phase (PR-B)

- Plan file: `knowledge-base/project/plans/2026-08-12-fix-apply-verify-repost-recovery-plan.md`
  (shared across both halves; extended in place rather than duplicated). PR-B's authoritative
  section is `# R18 — PR-B` at the end.
- Task machine: `../feat-one-shot-7104-apply-verify-repost-recovery/tasks.md`, Phases 4–10.
- Status: complete.

### Decisions

> **These are INTENT as recorded at plan time, not a description of what shipped.** One entry below
> was superseded during implementation and is corrected in place; the rest held.

- `infra_config_bounded_verify`, `infra_config_no_new_frame` and a `repush_once` *function* are all
  dead names from the pre-R16.2 design and must not be built. The one function PR-B adds is the pure
  predicate `infra_config_should_repush` (R18.1, R18.2).
- ~~The re-push is an **inline latched block inside the widened poll loop**, not a function and not
  a duplicated block.~~ **SUPERSEDED — plan R22.6 PRUNED the inline latched block outright, and it
  is not what ships.** The shipped shape is a three-step split: sensing (`infra_config_gate`),
  adjudication and grading (`repush_plan`), actuation (`repush_apply`), with the terminal verdict
  rendered by a second invocation of the same verify artifact and an `always()` backstop.
  Boundedness is STRUCTURAL — a step cannot run twice in a job — rather than latched, and the
  `head -1` call-site anchors this entry worried about were replaced by counting and parsed-YAML
  assertions. The reason the entry gives for rejecting a `repush_once` FUNCTION is still live and
  still enforced (bash suspends `errexit` into a wrapper body; Guard 2 (6) pins it).
- Guard 1 is re-derived over the predicate; boundedness moves to Guard 2, the only guard that
  quantifies over the caller (R18.3).
- AC14 is withdrawn: after PR-A, a no-op dispatch passes pass 1, so it no longer exercises the
  recovery. Measured on run 31714143720. The recovery is not producible in production on demand, so
  the hermetic two-pass integration test is promoted to the primary acceptance criterion (R18.4).
- Sentry emission moves to its own step gated on a step output, which keeps escalation credentials
  out of the verdict step and dissolves R17.6 (R18.6).
- Task 9.3 is already discharged by #7526 and #7527; task 7.7 is cut and its property bought by
  construction; task 10.4 is satisfied by run 31714143720 under AC20 (R18.5, R18.7).

### Errors

- The `## Guard Contract`, `## Files to Edit`, `## Observability`, `## Risks` and `## Acceptance
  Criteria` sections still described the pre-R16.2 design at the start of this session, even though
  `tasks.md` task 1.3 (which was to reconcile Guard 1) is ticked. All were corrected in place rather
  than superseded by a second copy.
- `tasks.md` 10.1 named `scripts/run-registered-suites.sh`, which does not exist. Corrected to
  `scripts/lint-orphan-test-suites.sh` (R18.8 §2).
- `GATE_MIN_ASSERTIONS` is 106 on disk; the PR-A findings section records 95. Corrected (R18.8 §1).

## Collision Gate

- `#7104`: OPEN, `closedByPullRequestsReferences: []`. PR #7509 (PR-A) merged with
  `closingIssuesReferences: []` — the split held.
- ADR ordinal enumerated across all **67** `origin/*` refs: highest is ADR-186 (PR-A's), so PR-B is
  provisionally **ADR-189**, re-derived immediately before merge.

## Components Invoked

`soleur:plan`, `soleur:deepen-plan`; agents `Explore`, `learnings-researcher`,
`kieran-rails-reviewer`, `architecture-strategist`, `code-simplicity-reviewer`,
`spec-flow-analyzer`, `cto`, plus a Phase-4.5 strong-model consult and an execution-verified
refutation pass; gates `lint-guard-contract.py`, `lint-infra-no-human-steps.py`, deepen-plan
halts 4.5–4.11, kb-citation and rule-ID sweeps.

Disclosed shortfall: the generic "run every discovered agent" fan-out was **not** executed —
the escalated panel and the strong-model consult had converged (three agents independently
found the same P0), and the remaining budget went to fork adjudication and execution-verified
re-checking instead. Recorded in the plan's Enhancement Summary.

## Work Phase (PR-B) — 2026-08-13

Phases 4–9 are delivered across eight commits. The measured facts, so a resumed session
does not re-derive them:

- **Task 4.0 (was blocking):** the re-push plan replaces **exactly 1** managed resource,
  `terraform_data.deploy_pipeline_fix` (`delete,create`), `host_creates=0`. Measured against
  live prd state, read-only. Guard 3's literal is `1`. **Do not re-run the terraform plan.**
- **The extraction is byte-identical:** both sides sha256 `2a23f958…`, 19774 bytes, 240 lines.
  Note the plan's R22.2 quotes 19,710 — that figure is stale; 19,774 is measured.
- **AC20 holds across the extraction:** the `DPF_REPLACED == "false"` branch is byte-identical
  to `origin/main`'s, 7403 bytes both sides. This is what licenses citing run 31714143720.
- **R19.4 §4 confirmed:** five `success()`-gated steps downstream of the gate, not the plan's
  "six". Two close the founder's issues; one swaps the running container.
- Suites: `infra-config-gate.test.sh` 127/0, `infra-config-verify.test.sh` 23/0.

### Deviations from the plan, each deliberate and stated

- **Guard 2 (task 6.3) is a commit-time verification, not a standing assert.** R22.5's
  prescribed baseline is `git show origin/main:<workflow>`, which BECOMES the post-move
  revision at merge — the baseline flips. And commit 2 parameterises the script, so a
  permanent byte-identity assert would be RED by the end of this same PR. Hashes recorded in
  ADR-189 instead.
- **The F1 pin uses an explicit two-clause form rather than the precedent's
  reconstruct-the-single-file-view trick.** That precedent exists because ~120 of its
  assertions are anchored on YAML indentation; none of the gate suite's are (`$1=="done"` is
  field-based), so the reconstruction buys nothing here while the two-clause form proves both
  (i) production invokes the script and (ii) the script carries the wiring.
- **Task 4.0 was measured with the SINGULAR `-target` form that ships** (6.9/AC19), not this
  task's "same four targets" text, which mirrors the first apply.
- **AC17 re-read under the split.** The re-push is a workflow step now, so "the re-push stub
  was invoked exactly once" is unobservable in-script; boundedness is structural and pinned by
  Guard 3 + the backstop. AC17 here drives the real script through both passes instead.

### Still open

~~`4.3`, `8.1`, `8.2` — the **committed** Guard 1 / Guard 2 mutation rows.~~ **CLOSED — see the
2026-08-14 addendum below.** Original text: Every guard in this PR has been mutation-proven
in-session and the results are recorded in the commit messages, but AC21 asks for the rows as
committed artifacts, which is stronger. Plus Phase 10's ticks and the `/review` → `/qa` →
`/compound` → `/ship` tail.

## Addendum — 2026-08-14 (tasks 4.3 / 8.1 / 8.2 and Phase 10)

Appended rather than folded into the sections above: the readings below **correct** two numbers
those sections record, and overwriting them would destroy the evidence for how each was reached.

### Tasks 8.1, 4.3, 8.2 — delivered

- **8.1** — the production call-site pin gained four clauses: the intervening `done` is now
  **counted** rather than first-matched (R19.2 — the old `awk '… $1=="done" {print NR; exit}'` was
  satisfied by any nested loop, and on the pre-split design reported PASS at
  `ci=2 adj=6 between_done=5` with the content assert moved *into* the loop); the predicate is
  invoked exactly once and directly as the `if` condition (no inline reimplementation, no wrapper —
  bash suspends `errexit` into a wrapper body, R16.1); exactly one step writes production from
  `tfplan-repush` (two producers must agree); and the **sourced library** carries no
  command-position production write, which converts "pure adjudicator" from convention into
  contract (R20.7 §1). Measured on the as-written library: **0** hits, with a positive control
  proving the detector can report a non-empty set.
- **4.3 / 8.2** — `apps/web-platform/infra/infra-config-repush-mutation.test.sh`, **17/17 rows
  behaved as expected**, registered in `infra-validation.yml` (suite **39 of 101** post-rebase, derivable by
  `run-registered-suites.sh --list`). The file header states which axes it edits AND which it does
  not, so the omissions are visible rather than implied.
- **`GATE_MIN_ASSERTIONS` re-measured 127 → 130**, flush, no slack (task 8.3's instruction re-run
  because the count moved).

### Guard 2's matrix is RE-DERIVED, and this is the deviation to read first

The plan's `## Guard Contract` §Guard 2 rows **3, 4 and 5** quantify over a latch, a per-iteration
re-push and a duplicated verify block. Plan **R22.6 PRUNES R18.3 outright**, replacing "the block
appears once plus a latch" with *exactly one step in the job invokes `terraform apply` against
`tfplan-repush`*. Under the split there is no latch and no widened loop, so those rows have no
referent as written; **row 6 (the function wrapper) is the one R22.6 says to KEEP** and it survives
as the shipped clause. The battery's rows are re-derived accordingly and each names its detector.

Note also that the plan uses **two different guard numberings**: `## Guard Contract` numbers
Guard 1 = the predicate and Guard 2 = the call-site pin (tasks 4.3 / 8.1 / 8.2), while **R22.5**
numbers Guard 1 = the `if:`-literal pin, Guard 2 = the verbatim-move gate, Guard 3 = the graded
cardinality (tasks 6.12 / 6.3 / 6.7). Both sets ship. The suite's assertion strings follow R22.5;
this addendum and the battery follow `## Guard Contract`.

### Two corrections to numbers recorded above

- **AC20 re-derived against freshly-fetched `origin/main`: the arm is byte-identical, 7269 bytes,
  sha256 `83d8e73ee8518502` on both sides.** The `## Work Phase` section above records **7403**;
  that figure measured a looser boundary. The reproducible definition, so the next reader does not
  have to guess: extract the gate step's `run:` body from `origin/main` **with PyYAML** (which
  dedents the block scalar), locate the single line carrying `NO push was expected, so no new frame
  should exist.`, take the nearest preceding `else` and its matching `fi` **at the same
  indentation**, and strip that indentation. Applying the identical extraction to
  `infra-config-verify.sh` yields the same bytes. AC20 therefore HOLDS and run **31714143720**
  measures the code that ships.
- **Five `success()`-gated steps downstream, not six.** R19.4 §4 already recorded this, but the two
  **operative** sites in the plan (§the-armed-steps bullet and R18.12's User-Brand Impact) still
  asserted *six* — the correction had not reached the text a reviewer actually reads. Both are
  corrected in place with the citation. The number is pinned by `AC18_SUCCESS_STEPS` in
  `infra-config-gate.test.sh`, which re-derives it from the parsed workflow.

### A defect found in this PR's own harness

The suite's known-negative self-test **could not fail**. It redefined `fail()` inside its own
subshell, so it proved that a function written two lines earlier increments a counter. Measured on a
sandbox copy: `fail() { :; }` left the suite reporting `127 passed, 0 failed`, **exit 0**, with the
self-test **GREEN** — the guard's-own-dispatch mutation passing through the one assertion whose
entire purpose is to catch it. It now drives the real `fail()`, and battery row **D1** pins it.

Two of the battery's own rows also failed first, and both failures were the mutations', not the
guards': **G1-5** deleted a numeric guard, which under `set -u` lets `notanumber` reach
`[[ -lt ]]` where bash's arithmetic context reads it as a *variable name* — a fatal abort, printing
no verdict, which the battery correctly refuses to score as detection. **G2-5** used a one-line
`for … do … done`, leaving `$1` equal to `for`; it landed and perturbed nothing.

### Phase 10

- **10.1** — `TEST_GROUP=scripts`: `304 suites: 302 passed, 0 failed, 0 killed, 2 skipped
  (declined — not relevant to this diff)`, rc=0. `TEST_GROUP=bun`: `7/7`, rc=0. Both preambles carry
  the honest `apps/web-platform/infra/ is NOT covered above` NOTE — that half runs at `/ship`
  Phase 4 via `run-registered-suites.sh` (ADR-183 ordering). `lint-orphan-test-suites`,
  `lint-workflow-errexit-capture` (744 `run:` bodies), `lint-guard-contract`,
  `test-infra-suite-registration` all clean. One `FAIL: harness self-test: fail() increments
  (EXPECTED)` line in the scripts log belongs to `plugins/soleur/test/proc.test.sh`'s own
  known-negative probe; that suite reports `0 failed`.
- **10.2** — `actionlint` rc=0 on both workflows; `bash -n` on the **extracted file** (never the
  `.yml`, never `bash -c`).
- **10.3 — the ordinal collided and the ADR is renumbered 187 → 189.** Re-derived across all **66**
  `origin/*` refs: `origin/feat-one-shot-7429-7402-killed-signal-and-orphan-globs` also carries an
  `ADR-187` (a different decision, `nested-runner-signals-unresolved-by-exit-shape…`) and
  `origin/feat-one-shot-7291-t5-mutation-network-flake` carries `ADR-188`. Neither is on
  `origin/main`, so all three claims are provisional and 189 is the lowest free ordinal. Swept:
  filename + **15** references across 6 files; residual `ADR-187` in the branch is **0 outside the collision narrative itself**. The bare claim "residual is 0" was self-refuting — the sentence making it contains the literal, and grep counts 6 hits across this file, `tasks.md` and `resume-prompt.md`, every one of them a NARRATIVE reference to the collision rather than a live citation of a decision. The sweep
  was scoped to the enumerated files rather than run repo-wide, because a blanket renumber is how
  another branch's work gets rewritten.
- **10.4** — SATISFIED under AC20 (above). **Do not re-dispatch.**
- **10.5** — the PR body carries `Closes #7104`; #7104 is OPEN with
  `closedByPullRequestsReferences: []` and already on milestone **Phase 4: Validate + Scale**.
- **AC27 — ships dark, asserted:** the workflow's `push` paths filter names **none** of the files
  this PR changes, so merging cannot auto-trigger a production apply. AC14′'s post-merge check is
  therefore an explicit `workflow_dispatch`.

### Environment note

`terraform init` cannot complete on this machine: `releases.hashicorp.com` answers 200 on its
root but resets over IPv6 and times out over IPv4 on the `hashicorp/tls` provider ZIP, and it
HANGS rather than failing. Worked around with a `filesystem_mirror` at `/var/tmp/tfmirror`
plus `TF_CLI_CONFIG_FILE=/var/tmp/tfcli.hcl`; the worktree's infra dir is already initialised.

## Next

- Phases 4–10 are CLOSED. Remaining: `/review` (must include `user-impact-reviewer` — the
  threshold is `single-user incident` and this PR adds a production write) → `/qa` → `/compound`
  → `/ship` → `/postmerge`. PR #7546 must carry `Closes #7104`.
- At `/ship`: re-derive the ADR ordinal **again** immediately before merge (189 is free as of
  2026-08-14 across 66 `origin/*` refs, but two siblings hold provisional 187/188 claims and a
  third could land 189), and run `apps/web-platform/infra/run-registered-suites.sh` — that
  directory has **no required CI status check**, so it is the one half of this diff no gate
  covers automatically.

## Addendum — 2026-08-16 (the review-fix pass)

Appended, not folded in: the readings below correct figures the sections above record, and
overwriting them would destroy the evidence for how each was reached.

### The ADR ordinal: KEEP 189. Do NOT renumber to 190.

The resume prompt instructed "ADR-189 → ADR-190" because a third branch was observed holding 189.
Re-derived across all **67** `origin/*` refs at the start of this pass:

| ordinal | held by |
|---|---|
| 187 | `origin/feat-one-shot-7429-7402-killed-signal-and-orphan-globs` |
| 188 | `origin/feat-one-shot-7291-t5-mutation-network-flake` |
| **189** | **`origin/feat-one-shot-7104-apply-verify-repost-pr-b` (this branch, uncontested)** |
| 190 | `origin/feat-one-shot-7341-zot-restart-loop-blocks-release` |

`origin/main`'s highest is **186**, so all four claims are provisional. The 7341 branch DID claim
189 (`5df0ab917` "docs(adr-189): claim the ordinal…") — that is the collision the resume prompt
saw — but it has **since renumbered itself to 190**. Following the instruction literally would
therefore have created a fresh collision with 7341, which is the exact harm it was written to
prevent. This is why task **10.3 stays OPEN**: re-derive again immediately before merge. Lowest
free ordinal if 189 is ever lost: **191**.

### Measurements taken this pass

- **Suite ordinal: 39 of 101** (post-rebase). The recorded "39 of 107" was wrong on the
  denominator; pre-rebase it was 38 of 100, and #7516 inserted one suite above it.
- **The extraction body is 19,774 bytes.** Re-derived at the extraction commit `9c7a021b8`: the
  file is 241 lines / 19,794 bytes, so the 240-line body is 19,794 − 20 (shebang) = 19,774. The
  plan's 19,710 was wrong at two sites; both corrected.
- **`steps.infra_config_gate.*` is referenced at 3 `if:` sites and 6 `env:` values**, with 5
  `success()`-gated and 5 `always()`-mentioning steps downstream. The plan's "two / three / one
  always(), zero edits" was false; only the five-×-`success()` half survived.
- **Eight sibling functions, not seven, and only ONE is quiet-with-rc-as-verdict**
  (`infra_config_count_invariant`). Every other sibling returns a value on stdout.
- **`main-health-monitor.yml`'s infra step budget of 15 min is CORRECT and was NOT changed.**
  The resume prompt called for 15 → 20. Measured across 8 successful runs the infra step ran
  354/366/389/419/420/431/434/447 s; `roundup5(7.45 × 1.5) = 15`, floor 10 → **15**. Reaching 20
  needs an infra max above 10 min; the observed max is 7 m 27 s. Refuted, not applied.
- **`deploy-script-tests` re-derived 14 → 15 min.** Measured from the API over the last 15
  `Infra Validation` runs (successful only): 422 … 581 s, so the recorded 565 s basis is now
  **581 s**. This PR takes the battery 17 → 22 rows; measured locally 85 s → 102 s at JOBS=4 on 16
  cores, and CI is a 4-vCPU runner where `JOBS=2`, so the added cost is roughly +45 s → ~626 s.
  `626 × 1.4 = 876 s = 14.6 min → 15`. The block's own standing instruction ("re-derive this if
  steps are added") is what triggered this.
- **#7095 does not record a bricked host.** It records a revoked baked token serving stale code
  with the site UP. Corrected in ADR-189 and in `decision-challenges.md`, where the inflation was
  carrying the CPO sign-off threshold.
- **`use_lockfile = false`** at `main.tf:19`, so `-lock-timeout` is inert and the concurrency group
  is the sole serializer. The ADR's "backend lock handling is now explicit" was false.

### A defect this pass found that was not on the list

**The branch was already CI-red.** Commit `974a77c43` (listed as DONE and verified) re-keyed the
alert step's condition from `outcome != 'success'` onto the verdict and left
`scripts/infra-config-red-alert.test.sh` asserting the old literal. That suite is registered in
`scripts/test-all.sh` (the `scripts` shard, which CI's required `test` context runs) and had been
failing **28 passed / 2 failed** since. The Phase 10 `TEST_GROUP=scripts` run recorded as
`302/0` predates that commit, and `974a77c43`'s own verification measured the *verify* suite
instead — an adjacent property. Now 45/0.

### The three commits missing `Co-Authored-By`, and why they are not rewritten

`aefce3b2e`, `2dd55a851` and `a23ae8ce0` (pre-rebase SHAs) carry no `Co-Authored-By` trailer;
confirmed with `git interpret-trailers --parse`, which reports 0 for each. Every commit added by
this review pass carries it.

They are deliberately NOT rewritten. This repo squash-merges, so the only commit body that reaches
`main` is the squash body, which `/ship` composes and which will carry the trailer. Fixing three
intermediate commits means rewriting all 23 on the branch — `git rebase -i` is unavailable in this
environment, so it would need `--exec` or `filter-branch` across the whole range — to change
history that the merge discards. The risk is real (this branch has already had one sibling
collision) and the benefit is zero once squashed. Recorded rather than silently dropped.

### Phase 2 filed

**#7576** — *"Phase 2 (#7104): name the infra-config push race at source, then add an advisory
readiness probe"*, `type/chore` + `domain/engineering`, milestone `Post-MVP / Later`. Blocked
explicitly on the first firing of this PR's recovery, with the forensics to read
(`preframe_status`, `observed_start_ts`, pass 2's `restarts[]`, the host journal), the
NAME-the-mechanism gate before any code, and the advisory-with-timeout constraint stated as
binding with the 6 s + 3 s = 9 s measurement behind it. It records that the >=3-in-30-days
trigger must NOT be built.

## Addendum — 2026-08-19 (the P0 fix pass, against the 2026-08-16 panel)

Appended, not folded in: the readings below correct figures the sections above record.

### Both P0s are closed, and both were invisible to a green suite for the same reason

- **P0-A** — pass 2 had lost the absolute `APPLY_START_EPOCH` pin, so its only surviving
  assertion was relative and any unrelated frame advance certified the recovery. Fixed with the
  cross-clock skew allowance (`INFRA_CONFIG_CLOCK_SKEW_S`, now single-sourced — there are three
  such comparisons), a DISTINCT `::error::`, and a bound against the re-push's own start stamp
  (`repush_start_epoch`, new output on `repush_apply`). Six fixtures, both directions.
- **P0-B** — the post-re-push liveness probe had no `id:`, so a re-push that bricked the sole
  no-SSH channel reported *"The infra-config gate never ran (outcome=success)"*. Fixed with the
  `id:`, a new first alert arm routing to `unreachable` with the `-replace` lever, a narrowed
  gate-never-ran predicate (`-z || == 'skipped'`), an explicit arm for the residue that narrowing
  leaves, and a branched backstop.

**Why neither was reachable from the suites.** The alert suite's step driver took two positional
outcomes and nothing else, so every arm keyed on `REPUSH_APPLY_OUTCOME` / `PASS2_VERDICT` /
`WEBHOOK_LIVENESS_OUTCOME` ran with all of them EMPTY — one point in a space the step branches on
five ways, and the point at which both re-push arms are unreachable. And `STUB_HTTP_CODE` was 200
at every drive site in the verify suite, so the 404/000/502/503 branches could not be entered
(F9). The suites were not lax; they were structurally unable to construct the failing states.

### The three defeated fixes, and their shared root cause

D1/D2/D3 all traced to **three hand-rolled shell parsers with three different noise-stripping
policies**. They are now one module, `apps/web-platform/infra/infra-config-shellscan.py`. D3's
eight measured evasions are all caught; D1's executed composite now reads depth 1 rather than 0;
D2's tally gained a producer `pass()` cannot reach (the suite's own captured stdout).

### Measurements taken this pass

- **`G1_EXPECTED_REFERENCES` 12 → 19**, and the extractor is now scoped to a DERIVED gate chain.
  It was counting every step-output reference in the 1985-line shared workflow, 2 of which were
  `steps.check_4804.outputs.open`. A first attempt at the closure included a backward half
  ("pull in what a chain step reads") which dragged that same reference back on the moment the
  #4804 step gained a verdict gate — the F8 problem returning, caught by re-measuring.
- **Assertion floors, all flush:** gate 132, verify 29 → 38, alert 45 → 66.
- **Battery rows 22 → 40**, 40/40 as expected. The alert suite is now a graded suite in it.
- **`tfplan.txt` was neither reclaimed nor gitignored** — the `.gitignore` entry `tfplan` matches
  a file named exactly `tfplan`. The binary `tfplan` was never reclaimed at all.
- **ADR-072 contains ZERO occurrences of *actuate* or *verification surface*.** ADR-189's
  citation of it was phantom; the principle is real, is now stated as originating here, and is
  registered as **AP-023**.

### A survivor that was a FIXTURE failure, not a guard failure

The first `D3-BYPASS` row added the panel's balanced phantom lines without moving the content
assert into the poll loop. It landed, and it was correctly NOT detected — balanced phantoms
around a genuinely terminal assert perturb nothing. Recorded in the row's own comment because the
survivor looked like a guard gap and was not.

### A session error worth carrying

The first P0-A mutation battery used `git checkout --` to restore between rows. The fix under
test was UNCOMMITTED, so row 1 reverted it and every row after that scored the defect against
itself. Caught by the battery's own restore check. Restore from a PRISTINE COPY, never from git —
and commit each verified unit before mutating it.
