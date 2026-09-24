---
title: "fix: git-data-pin-redeploy source-run gate keys on the apply step, not the job conclusion (#8710)"
type: fix
date: 2026-09-24
slug: fix-pin-redeploy-gate-keys-on-apply-step
branch: feat-one-shot-8710-pin-redeploy-plan-only-gate
issue: 8710
closes: 8710
priority: p1
domain: engineering
brand_survival_threshold: aggregate pattern
lane: cross-domain
---

# fix: git-data-pin-redeploy source-run gate keys on the apply step, not the job conclusion

## Overview

Spec lacks valid lane: — defaulted to cross-domain (TR2 fail-closed).

The git-data pin-redeploy follower (`.github/workflows/git-data-pin-redeploy.yml`) decides whether to
force a production web release by reading the triggering apply run. Its gate,
`.github/actions/dispatch-web-redeploy/source-run-gate.sh`, proceeds whenever the git-data birth
(`git_data_host_create`) or replace (`git_data_host_replace`) **job** concluded `success`. A
`plan_only=true` rehearsal of the replace also concludes `success`: it plans, runs the destroy-guard,
then skips every mutating step. So each rehearsal forces an unwanted production redeploy, and that
redeploy's `git_data_pin=present fp=` startup line can later be mistaken for GO evidence of a real
replace (ADR-237 step-3, runbook `git-data-luks-cutover-5274.md` §2026-09-24 row G3).

This plan re-keys the gate on a **positive** signal: the job's own `Terraform apply` step (YAML
`id: apply`) concluded `success` in the source run. That step is the only step in either job that
runs `terraform apply`, which is the only thing that writes `doppler_secret.git_data_ssh_host_key`.
A rehearsal skips that step (census row G5a already enforces the `inputs.plan_only != true` guard on
it), so a rehearsal can no longer proceed.

Constraint for the work phase: **no workflow is dispatched to production** to verify this — no
`git-data-host-replace`, no `plan_only` rehearsal, no pin redeploy. Verification is hermetic fixtures
(bash) plus a YAML parity test (bun), mirroring the API shape measured read-only from runs
35979044625 and 35979304442.

## Research Reconciliation — Spec vs. Codebase

| Claim (issue / brief) | Reality (measured 2026-09-24) | Plan response |
|---|---|---|
| "The gate keys on the two jobs' conclusions" | True. `concl()` in `source-run-gate.sh` reads `.jobs[].conclusion` by job name only. | Re-key on the apply step. |
| "Read the run's `display_title`" (issue option 1) | `displayTitle` of rehearsal 35979044625 is the workflow name `Apply web-platform infra (…)`; the workflow has no `run-name:`. `gh run view --json` exposes no `inputs`. | Rejected: carries no signal, and it is a display string (forbidden by the brief). |
| "An `applied=true` job output" | The jobs API (`GET /actions/jobs/{id}`) returns keys `check_run_url, completed_at, conclusion, … steps, url, workflow_name` — **no `outputs`**. A `workflow_run` consumer cannot read another run's job outputs. | Rejected: unreadable from the follower. |
| "An uploaded artifact" | Readable via `/actions/runs/{id}/artifacts` (rehearsal returns `[]`), but needs a new `upload-artifact` step in a 7,000-line workflow, and an upload that fails after a real apply would skip a needed redeploy (stale pin). | Rejected (Cut List). |
| "The apply step's `git-data-pin` notice exists" | The notice is a check-run annotation; reading it needs `checks: read`, which the redeploy job does not hold (its permissions are pinned to exactly `{actions: write, contents: read}` by `terraform-target-parity.test.ts`). It is also emitted only when the fingerprint output is readable — a real apply with an unreadable fingerprint prints a `::warning::` instead, so keying on it would skip a real rotation. | Rejected as the key (Cut List). |
| "Steps are visible to the gate" | Yes. `gh run view <id> --json jobs` returns `jobs[].steps[]` with `{name, conclusion, number, status, startedAt, completedAt}`. Rehearsal: step 13 `Terraform apply (git-data-host -replace) — both-volumes-preserved assert` = `skipped`. Real replace 35979304442: same step = `success`, step 14 (boot poll) = `failure`, job = `failure`. | Key on this, using the document the gate already fetches (zero new API calls, zero new permissions). |
| "Does the pin redeploy gate on the Doppler secret actually changing?" | No. The follower holds no Doppler credential by design (header `SECRETS:` block; the parity test pins its only secret to `RESEND_API_KEY`). The only writer of `GIT_DATA_SSH_HOST_KEY` is `doppler_secret.git_data_ssh_host_key` inside the targeted `terraform apply`. | Keep it credential-free. The apply step's success is the proxy for "the secret changed"; the parity test pins that the apply step is the only `terraform apply` in each job. |
| Runbook G2 "clean means … `gh run list --workflow=git-data-pin-redeploy.yml --created ">=<G2 start>"` shows no run it triggered" | False even after this fix: the follower's `if:` admits every dispatched apply run, so a pin-redeploy run **is** created; it just does not proceed. | Rewrite the G2 cell to check the triggered run's gate output and that its `Dispatch web-platform-release…` step is `skipped`. |

## Research Insights

**Premise Validation.** #8710 is OPEN (no closing PR); #5274, #5914, #8211 are OPEN. No open PR
touches `source-run-gate.sh`, `git-data-pin-redeploy.yml`, `test-dispatch-web-redeploy.sh` or the
cutover runbook. Every cited path exists on this branch (`source-run-gate.sh`, 83 lines;
`git-data-pin-redeploy.yml`; jobs `git_data_host_replace`/`git_data_host_create` in
`apply-web-platform-infra.yml`, both with a step `id: apply`). The brief's measured context held:
pin redeploy 36015901816 printed the job-conclusion notice for push run 36015201873. The brief's
guess that job outputs are unreadable from a `workflow_run` consumer was verified by probing
`gh api repos/jikig-ai/soleur/actions/jobs/107566304612 --jq keys` (no `outputs` key) and
`gh run view --json <bad>` (field list has no `inputs`). The mechanism — step conclusion instead of
job conclusion — is not in any ADR's rejected alternatives; ADR-237 does not state the gate's rule.

**Property List.**

1. P1 — A `plan_only` rehearsal of either git-data job never causes a production web release.
2. P2 — A real apply that published a new pin in a green job causes exactly one redeploy, as today.
3. P3 — A shape the gate cannot interpret (missing steps, renamed or duplicated apply step)
   fails loudly, never reads as "nothing to do" (the gate's existing fail-closed contract).
4. P4 — The operator can tell from the follower run whether it proceeded, and why not.
5. P5 — Both jobs (birth and replace) are covered by the same rule.

**Cut List.**

- `applied=true` job output → P1/P2 → unreadable from a `workflow_run` follower (no API exposes job
  outputs); cut.
- Uploaded "applied" artifact → P1/P2 → the apply step's own conclusion, already in the jobs document
  the gate fetches, buys the same property without a new step; and an upload failure after a real
  apply would break P2. Cut.
- Reading the `git-data-pin` notice annotation → P1/P2 → needs `checks: read` (breaks the pinned
  least-privilege set) and is absent when the fingerprint is unreadable (breaks P2); the step
  conclusion covers it. Cut as the key. (It could later feed the fingerprint into the follower's
  summary; not needed for any listed property.)
- `display_title` / `run-name:` carrying `plan_only` → P1 → a display string and a negative signal
  (absence of a marker proceeds); the apply-step conclusion is positive. Cut.
- Gating on the Doppler secret actually changing → P2 → would give the follower a Doppler
  credential it deliberately lacks; the parity test's "only `terraform apply` step" assertion ties
  the apply step to the only pin writer. Cut.
- A structured `verdict=` token in the gate's log lines → P4 → the follower run's
  `Dispatch web-platform-release…` step conclusion (`success`/`skipped`) already tells the operator
  whether it proceeded; cut.

**API shape, measured (read-only).** `gh run view <id> --json jobs` → `jobs[]` keys
`completedAt, conclusion, databaseId, name, startedAt, status, steps, url`; `steps[]` keys
`completedAt, conclusion, name, number, startedAt, status`. **Steps carry no `id`** — the YAML
`id: apply` is not in the API, so the gate must match the step `name` (the learnings researcher's
"match `steps[].id == apply`" suggestion is not implementable). A skipped job has `steps: []`.
Job names equal the YAML job ids (neither job has `name:`, already parity-tested).

**Relevant files.** `.github/actions/dispatch-web-redeploy/source-run-gate.sh` (`concl()` and the
proceed `if`); `.github/workflows/git-data-pin-redeploy.yml` (step `gate`, `track.sh` step gated on
`steps.gate.outputs.proceed == 'true'`); `.github/workflows/apply-web-platform-infra.yml` job
`git_data_host_replace` (apply step `if: inputs.plan_only != true`, `id: apply`) and job
`git_data_host_create` (apply step `id: apply`, no `plan_only` arm);
`tests/scripts/test-dispatch-web-redeploy.sh` (`_gjobs`, `_gexec`, `check_G1..G8`, GH stub loop;
`_mut_row` pattern for track.sh); `plugins/soleur/test/terraform-target-parity.test.ts`
(`describe("git-data-pin-redeploy.yml")`, helpers `extractJobBlock` at line ~1189 and
`extractStep` (name-regex) at ~530 — no step-by-id helper exists, so the new assertion walks
`parseYaml(wf).jobs[<job>].steps` and filters `s.id === "apply"`);
`tests/scripts/test-infra-privileged-tier-census.sh` row G5a (plan_only guard on every mutating
step). Existing pins of the apply step names: `terraform-target-parity.test.ts` (~line 626,
`/Terraform apply \(git-data birth\)/`) and the census fixture (line ~1163, a synthetic
`replace.yml` — not the real workflow). Suite registration: `scripts/test-all.sh`
(`run_suite "tests/scripts/dispatch-web-redeploy"`), affected-paths map
`scripts/lib/test-affected-paths.sh` (~line 1059). The suite has no row-count floor (its only floor
is the reporter self-test); it runs ~26 s locally (51 assertions green on 2026-09-24).

**Institutional learnings applied.**

- `2026-09-15-my-access-gate-proved-a-different-argv-than-the-steps-it-gated.md` — the gate must
  inspect what the guarded thing consumes: here, the step that writes the pin, not the job around it.
- `2026-06-14-fail-closed-gate-audit-every-input-branch-and-symmetric-guard.md` — audit every
  branch: both jobs, every step conclusion, missing/empty `steps` (decision rows a–h).
- `2026-08-10-a-guard-that-cannot-be-driven-red-is-vacuous-four-rounds-four-instances.md` and
  `2026-08-13-every-guard-i-shipped-was-satisfiable-by-a-guard-that-asserts-nothing.md` — mutation
  rows written from the design, a must-PASS non-canonical row, a harness row.
- `2026-08-09-my-suites-were-hermetic-so-they-certified-a-gate-reached-through-a-dead-read.md` —
  hermetic rows cannot see a dead live input, hence the static parity test binding the gate's
  constants to the workflow's `id: apply` step names.
- `security-issues/2026-09-21-pinning-ssh-host-keys-the-guards-pinned-presence-not-the-resolved-value.md`
  (#7226) — assert the resolved value (the step conclusion) rather than presence.
- Constitution §Testing "Never write a mock for an external CLI/API from memory when the code parses
  its output" — fixtures copy the measured jobs-document shape above.

**CLAUDE.md / AGENTS.md conventions.** `cq-write-failing-tests-before` (G9 RED against the
pre-fix gate first); `cq-test-fixtures-synthesized-only` (synthetic run ids/values, measured
shape); `hr-menu-option-ack-not-prod-write-auth` and the brief's no-dispatch constraint;
`wg-use-closes-n-in-pr-body-not-title-to` (`Closes #8710` in the PR body).

## Open Code-Review Overlap

None. (`gh issue list --label code-review --state open` bodies searched for every planned path and
for `git-data-pin-redeploy`, `source-run-gate`, `dispatch-web-redeploy` on 2026-09-24.)

## Problem Statement

Measured 2026-09-24 (all read-only `gh run view`):

- Rehearsal **35979044625** (`plan_only=true`) concluded `success`; its apply step was `skipped`.
  Pin redeploy **35979135707** logged `source-run-gate: git_data_host_replace concluded success in
  run 35979044625; the pin rotated — redeploying.` and dispatched production release
  **35979149543**.
- Real replace **35979304442**: apply step `success` (the new pin
  `SHA256:WRk5AW6j…` published), boot poll `failure`, job `failure`. Pin redeploy **35980551109**
  took the `::warning::` arm and did not redeploy. That is the documented behaviour for a red boot
  poll (runbook §"Boot order on the replace: what is already published when the poll reds"), and this plan keeps it.

Two older birth runs show the other shapes the gate must grade (read-only, same query):

- **34822248580**: `git_data_host_create` `failure` at the plan step (the birth gate refused); the
  apply step is listed and `skipped`. Today's gate takes the "pin may be published" warning and
  advises a forced production redeploy although nothing was applied — rule row 3 below.
- **34836141887**: birth apply `success`, boot poll `failure`, job `failure` — rule row 5 (`apply=success`).
- A job that failed early still lists **all** its steps (later ones `skipped`; 18 steps in both birth
  runs), so "apply step matched 0 times" in a job that ran steps means a rename, not an early stop.
  Runs that never started (`startup_failure` 35438190773, `cancelled` 35516720404) return
  `jobs: []`, which is rule row 1 for both jobs.

The first case is the bug: job conclusion is not evidence of an apply. It also corrupts the GO
evidence for ADR-237 step 3, and it blocks runbook row G2 (the next rehearsal), which is gated on
this issue closing.

## Proposed Solution

### Decision rule (the new gate) — v2, simplified at plan review

Per job (`git_data_host_create`, `git_data_host_replace`), let `N` = the number of entries in that
job's `steps` whose `name` equals the job's apply-step constant (a missing or `null` `steps`
counts as `N = 0` — test `(.steps | type) == "array"` explicitly, never `// []`), and `A` = that
step's `conclusion` when `N == 1` (a JSON `null` is carried as the literal `null`, never coalesced
to `""`).

| # | Job | Apply step | Result for that job |
|---|---|---|---|
| 1 | absent or `skipped` | — | quiet: no apply |
| 2 | `success` | `N == 1`, `A == success` | **proceed** (the pin rotated) |
| 3 | any | `N == 1`, `A == skipped` | quiet `::notice::` containing `no apply ran` and the likely cause ("a `plan_only` rehearsal, or the job stopped before apply"): pin unchanged |
| 4 | `success` | `N != 1` | **exit 1, fail closed**: a green job whose apply step cannot be identified (renamed, duplicated, or `steps` missing) |
| 5 | not `success` | anything else | **warning** arm (`::warning::` + step-summary line, proceed=false) that prints `apply=<A, or "not found", or "matched N times">`. When `A == success` the text says the pin **was published**; otherwise that it **may be** published. |

Combination: any job in row 4 → exit 1 before emitting outputs. Else any job in row 2 → proceed,
`source_job=<that job>` (birth wins a tie, as today). Else any job in row 5 → the warning arm. Else
the quiet notice arm. Row 1 keeps today's lookup (`length == 1` else absent); job names are
already pinned by the existing parity test (`terraform-target-parity.test.ts`, "The gate names the
two jobs by their exact apply-workflow ids").

What each row buys (Property List): row 2 + the job-success conjunct → P2; row 3 → P1 (the #8710
fix) and, for a red job, P4 (it stops today's false "pin may be published" advice to force a
production redeploy when the plan was refused before apply — run 34822248580); row 4 → P3; row 5
→ P4 (the operator sees `apply=success`, i.e. the pin was published). Both jobs through the same
rule → P5.

**Messages the operator acts on (P4).**

- Row 5 with `A == success` on the **replace** job names the runbook section
  §"If the fresh host fails a boot check after step 3" and says: start with a read, do not replace
  again; the redeploy, if wanted, is `gh workflow run git-data-pin-redeploy.yml --ref main` (no
  `source_run_id`). On the **birth** job it names the same no-`source_run_id` dispatch as the only
  recovery (a birth cannot be repeated).
- Every exit-1 `::error::` names what to change (the apply-step constant in `source-run-gate.sh`,
  or the workflow step name) and the same no-`source_run_id` dispatch for a pin that did rotate.
- The follower's failure email (`git-data-pin-redeploy.yml`, step `Email ops when the pin is not
  confirmed loaded`) today offers only "re-run" or `-f source_run_id=<apply run id>`, both of which
  hit the same refusal for an exit-1 row. Add one sentence: read the run's annotations, and if the
  source apply really published a pin, dispatch with **no** `source_run_id`. The existing
  `-f source_run_id=` sentence stays (the parity test asserts it).

Deliberately **not** modelled (plan review, v2): an in-progress source job (only a manual dispatch
can reach it; it lands in row 5, a warning — never silent, never a redeploy); a renamed or
duplicated **job** (caught in CI by the existing job-name parity assertion); a red job with
`steps: []` (row 5 — a warning, which never emails and never redeploys).

The gate's header comment carries this table verbatim, so the next maintainer does not need the
plan.

### Apply-step identity

The gate carries two constants, one per job, equal to the `name:` of the step with `id: apply` in
that job of `.github/workflows/apply-web-platform-infra.yml`:

- `git_data_host_create` → `Terraform apply (git-data birth)`
- `git_data_host_replace` → `Terraform apply (git-data-host -replace) — both-volumes-preserved assert`

Exact string equality (`jq --arg`), never a prefix/regex. A rename in the workflow without the gate
fails parity test PT1 in CI; at runtime a green job reaches rule row 4 (exit 1, failure email) and a
red job reaches row 5 (a warning naming `apply=not found`) — never a silent skip.

### Files to Edit

- `.github/actions/dispatch-web-redeploy/source-run-gate.sh` — the decision rule above; header
  comment carries the rule table (the property now reads "proceed iff the apply step concluded
  success in a job that concluded success"). Write each mutation site (below) as a single, unique
  line so `_mutant`'s `count == 1` precondition holds. Keep the notice/warning lines carrying the
  `git_data_host_create=<c>` / `git_data_host_replace=<c>` tokens that row G3's
  `::notice::.*git_data_host_create=skipped` assertion reads.
- `tests/scripts/test-dispatch-web-redeploy.sh`:
  - `_gjobs` writes per-job `status: "completed"`, `conclusion`, and `steps[]` entries of the
    measured shape (`name`, `conclusion`, `number`, `status`); a job's steps list the real
    neighbouring step names (plan step, boot anchor, apply, poll, dispatch summary) so the fixture
    reads like runs 35979044625 / 35979304442.
  - `_mutant` gains a source parameter (`_mutant SRC NAME FROM TO`, output `<basename>-mut-<NAME>.sh`)
    and `_mut_row` passes `$TRACK` for the existing track.sh rows and `$GATE` for the new gate rows.
  - Rows per Test Scenarios; the header row table rewritten; the `GH` stub loop lists every RED /
    exit-1 gate row explicitly (G3 G5 G6 G7 G9 G9b G10 G11 G12 G14 G15 G18).
- `plugins/soleur/test/terraform-target-parity.test.ts` — in `describe("git-data-pin-redeploy.yml")`,
  a predicate `applyStepParity(doc, gateSrc)` returning the list of violations, run on the real
  parsed workflow (must return `[]`) and on two in-test mutated copies (the `parseYaml(wf)` mutation
  pattern the file already uses) that must each return a violation:
  - **PT1** for each job, exactly one step has `id: apply`, and its `name` appears as a
    double-quoted literal in `source-run-gate.sh`. Mutant: rename that step.
  - **PT2** for each job, that step is the only one whose `run:` matches the command-position
    regex `/^\s*(if\s+!?\s*)?terraform(\s+-\S+)*\s+apply\b/m` (verified 2026-09-24: only the
    two `id: apply` steps match). Mutant: append a second step running `terraform apply -auto-approve`.
  - The replace apply step's `plan_only` guard is **not** re-asserted here: census row G5a
    (`tests/scripts/test-infra-privileged-tier-census.sh`) already enforces it on every mutating
    step of `git_data_host_replace`.
- `.github/workflows/git-data-pin-redeploy.yml` — the failure email body gains one sentence (read
  the run's annotations; if the source apply really published a pin, dispatch with **no**
  `source_run_id`). The existing `-f source_run_id=` sentence stays: the parity test asserts it.
  The header's `Recovery:` comment gets the same sentence.
- `knowledge-base/engineering/operations/runbooks/git-data-luks-cutover-5274.md`:
  - The bullet under §"Boot order on the replace: what is already published when the poll reds"
    that says the gate "reads the source run's job conclusions and proceeds **only** when
    `git_data_host_replace` concluded `success`": it now reads the apply step; a red boot poll after
    a green apply is reported as `apply=success` / "pin was published"; recovery unchanged. Add:
    a green follower run does not mean a redeploy happened — check its
    `Dispatch web-platform-release and wait for its deploy` step.
  - §2026-09-24 table, **runbook row G2** "Clean means" cell: replace "shows no run it triggered"
    with the T-R1 check (Test Scenarios). No other line of the §2026-09-24 record changes.

### Files to Create

None.

## Technical Considerations

- **Does merging this alone mutate production? No.** `git-data-pin-redeploy.yml` runs only on the
  completion of a *dispatched* apply run, or a manual dispatch; neither happens at merge, and the
  change touches no Terraform, no `paths:`-triggered apply and no deploy workflow. The PR body's
  first line states this.
- **Every exit-1 message names the escape hatch.** A stuck operator's natural repair — re-running
  the follower with the same `source_run_id` — hits the same refusal by design. Each `::error::`
  therefore names the fix (update the apply-step constant or the workflow step name) and the
  unconditional recovery for a pin that did rotate: `gh workflow run git-data-pin-redeploy.yml --ref
  main` (no `source_run_id`), as the existing warning arm already does.

- **No new API call, permission, secret or third-party action.** The gate already fetches
  `gh run view <rid> --json jobs`; `steps[]` is in that document. The least-privilege parity test
  (`{actions: write, contents: read}`, only `RESEND_API_KEY`) stays green unchanged.
- **Re-run attempts.** `gh run view <id>` returns the latest attempt of each job; a partial re-run
  could replay a carried-over success as a second redeploy. Pre-existing, unmeasured, tracked as
  #8760 (see Dependencies & Risks).
- **`git_data_host_create` has no `plan_only` arm.** The input's description scopes it to
  `web-host-replace` and `git-data-host-replace`; a birth with `plan_only=true` applies. The re-keyed
  gate handles it correctly (the apply step runs, so it proceeds) — noted, not changed here.
- **Architecture:** no ADR change. ADR-237 D2 already says the follower "forces a release when the
  apply run completes"; it does not state the job-conclusion rule. The C4 model does not model
  CI-to-CI edges (ADR-237 Consequences). No new decision is being made — the gate is being made to
  implement the one already recorded.
- **Attack surface:** the gate reads only GitHub's own run metadata with `github.token`; the source
  run id is validated `^[0-9]+$` before use (unchanged). Step names are matched with `jq --arg`, never
  interpolated into a filter or a workflow command.

## Alternative Approaches Considered

| Alternative | Why not |
|---|---|
| Split `terraform apply` into its own job (`plan_only` guard at job level) so the existing job-conclusion rule becomes correct (advisor consult, 2026-09-24) | The apply consumes the saved, gate-graded `tfplan` from the plan step. Moving it across jobs means either uploading `tfplan` as an artifact — it embeds the git-data host private key (`tls_private_key.git_data_host_ssh`, also inside `user_data`) and Doppler-sourced values, in a public repository's artifact store — or re-planning in the apply job, which applies a plan the destroy-guard never graded. It also splits the birth job's reviewer-gated `environment` and the `git-data-state` concurrency group across two jobs (a second dispatch could interleave between plan and apply), and re-shapes jobs that census rows G5a–G5c, the S19 poll pin and the parity suite all pin. Recorded as a deliberate trade-off: the step-name coupling is accepted and pinned (parity test + fail closed) instead. |
| Job output `applied=true` | Not readable by a `workflow_run` follower (no API field). |
| Uploaded marker artifact | New step in a 7,000-line workflow; an upload failure after a real apply would suppress a needed redeploy. |
| `git-data-pin` notice annotation | Needs `checks: read`; absent when the fingerprint is unreadable. |
| `display_title` / `run-name` carrying `plan_only` | A display string and a negative signal (the brief forbids it). |
| Proceed on apply-step success alone (drop the job-success conjunct) | Would auto-redeploy production after a red boot poll, reversing the runbook's documented recovery (read, then another replace, which re-pins and redeploys). Kept as rule row 5, a warning. |

## Plan Review Revisions (v2)

Panel: `soleur:engineering:review:dhh-rails-reviewer`, `soleur:engineering:review:kieran-rails-reviewer`,
`soleur:engineering:review:code-simplicity-reviewer` (eng) + `soleur:engineering:cto` (named, devex).
Earlier inputs: `soleur:product:spec-flow-analyzer` (7 gaps) and the Step 4.5 advisor consult.

| Decision | Source | Class | Applied |
|---|---|---|---|
| Collapse the 14-row table (a1…h) to 5 rule rows; cut rows s (in-progress), a3 (renamed/duplicated job), b/b2 (empty steps) as separate cases | DHH + simplicity (both panels on one scope → delete over fix) | mechanical | yes |
| Cut mutation rows 7, 7b–7e and test rows G13, G16, G17 (folded into G1), G19–G24, G10b, G11b | DHH + simplicity | mechanical | yes |
| Cut the parity `if:` assertion (duplicates census G5a) and the `${{` name check | DHH + simplicity + Kieran #4 | mechanical | yes |
| Parameterise `_mutant` with the source script; each mutation site a single unique line | Kieran #2 | mechanical | yes |
| Command-position regex for "only `terraform apply` step" | Kieran #6 | mechanical | yes |
| Parity mutations run in-test on mutated parsed YAML, not a scratch copy | Kieran #7 | mechanical | yes |
| G4/G8 deletion stated; GH loop listed; G3 notice token constraint stated | Kieran #9 | mechanical | yes |
| `discoverability_test` uses `grep -m1 -o` | Kieran #10 | mechanical | yes |
| AC1 rewritten as a mutation result; parity tests renamed PT1/PT2; "runbook row G2" wording | Kieran #11, #12 | mechanical | yes |
| Old AC9 rewritten: it measured concurrent sessions, not the change | standing check `cq-ac-must-not-depend-on-concurrent-sessions` | mechanical | yes |
| Failure email gains a no-`source_run_id` recovery sentence | Kieran #5 + CTO #1 | mechanical (eng panel) | yes |
| Replace-job `apply=success` warning names the runbook's "read first, never a second replace" section | CTO #2 | taste | yes — persisted to `decision-challenges.md` |
| Read-only run of the rewritten gate against four real source runs before merge (AC5) | CTO #3 | taste | yes — persisted |
| Decision table verbatim in the gate's header comment; T-R1 follower-lookup command | CTO #5, #6 | taste | yes — persisted |
| Split apply into its own job | advisor consult | rejected (see Alternatives) | no |

## User-Brand Impact

- **If this lands broken, the user experiences:** either (a) an unwanted production web redeploy on
  every git-data rehearsal (a brief restart of the web app during an operator's rehearsal), or (b) a
  missed redeploy after a real git-data replace, so the app keeps the old host-key pin and account
  erasures fail with `erasure_outcome=host_key_mismatch` until an operator redeploys.
- **If this leaks, the user's data is exposed via:** no new exposure vector. The gate reads GitHub
  run metadata only, holds no Terraform or Doppler credential, and prints only run ids, job names
  and step conclusions.
- **Brand-survival threshold:** `aggregate pattern` — a missed or spurious redeploy degrades
  erasures or availability for everyone in a window; no single user's data is exposed.

## Observability

```yaml
liveness_signal:
  what: "the pin-redeploy run's gate step log line prefixed `source-run-gate:` (one per source run, naming the source run id), plus the run's `Dispatch web-platform-release and wait for its deploy` step conclusion (success = proceeded, skipped = did not)"
  cadence: "per completed dispatched apply-web-platform-infra run (workflow_run)"
  alert_target: "operator email via notify-ops-email on any failure of the redeploy job (subject: git-data pin NOT loaded by the app); GitHub run annotations (::warning:: / ::error::) on the run page"
  configured_in: ".github/workflows/git-data-pin-redeploy.yml (steps gate + Email ops when the pin is not confirmed loaded)"

error_reporting:
  destination: "GitHub Actions annotations on the pin-redeploy run + Resend email to ops on job failure"
  fail_loud: "`::error::source-run-gate: … (fail closed)` and exit 1 when the jobs document is unreadable or a green git-data job's apply step is matched 0 or 2+ times; `::warning::source-run-gate: … apply=<conclusion> …` for a red job (pin published / may be published)"

failure_modes:
  - mode: "apply step renamed in apply-web-platform-infra.yml without updating the gate constant"
    detection: "CI: parity test PT1 in terraform-target-parity.test.ts goes red on the PR; runtime: rule row 4 exits 1 for a green job, row 5 warns `apply=not found` for a red one"
    alert_route: "PR check failure; at runtime the redeploy job fails and emails ops (green job) or annotates the run (red job)"
  - mode: "GitHub drops `steps` from the jobs document"
    detection: "rule row 4 exits 1 for a green job (N = 0)"
    alert_route: "redeploy job failure email to ops"
  - mode: "real apply succeeded but the job went red (boot poll failure)"
    detection: "rule row 5 `::warning::` with `apply=success` (pin was published) + a step-summary recovery line"
    alert_route: "run annotation; runbook git-data-luks-cutover-5274.md §If the fresh host fails a boot check after step 3"

logs:
  where: "GitHub Actions run logs of git-data-pin-redeploy.yml (gh run view <id> --log)"
  retention: "GitHub Actions log retention for the repository (90 days default)"

discoverability_test:
  command: "grep -m1 -o 'no apply ran' .github/actions/dispatch-web-redeploy/source-run-gate.sh"
  expected_output: "no apply ran"
```

`no apply ran` is the fixed phrase of the rule-row-3 notice (the #8710 skip). The work phase writes
the notice with this exact phrase, and row G9 asserts it in the gate's output. (`-m1` keeps a
second occurrence, e.g. in the header comment, from printing a second line.)

## Guard Contract

### Guard 1 — source-run gate proceeds only on a real apply

**Property.** `source-run-gate.sh` emits `proceed=true` for a source run if and only if one of the
two git-data jobs concluded `success` **and** that job's single `id: apply` step concluded `success`;
every other readable shape emits `proceed=false`, and a green git-data job whose apply step cannot
be identified exactly once exits 1.

**Assembly.** One chokepoint for the input: the single `gh run view "$rid" --json jobs` document the
gate reads. The decision quantifies over BOTH members of the job set (`BIRTH_JOB`, `REPLACE_JOB`) —
a check that inspects only one job is the defect class. Apply-step identity has one authority: the
`name:` of the `id: apply` step in each job of `apply-web-platform-infra.yml`, bound to the gate's
constants by parity test PT1. The pin-write chokepoint is that same step (the only command-position
`terraform apply` in each job — PT2), and "rehearsal ⇒ apply skipped" is carried by census row G5a
in `tests/scripts/test-infra-privileged-tier-census.sh`.

**Mutation matrix** (each FROM is a single unique line of the rewritten gate, applied with
`_mutant "$GATE" …`; the work phase records the exact FROM→TO literal pairs in the suite):

| # | Mutation | Row that must go RED |
|---|---|---|
| 1 | Revert the proceed test to the job conclusion only | G9 plan_only rehearsal → proceed=true |
| 2 | Treat a `skipped` apply step as a rotation (`!= failure` instead of `== success`) | G9 |
| 3 | Drop the birth job from the loop over jobs (second member) | G1 birth apply success → proceed=false |
| 4 | Take the first apply-named step instead of requiring `N == 1` | G15 two apply-named steps in a green job → proceed instead of exit 1 |
| 5 | Treat `N == 0` in a green job as a quiet skip | G14 renamed apply step → exit 0 instead of exit 1 |
| 6 | Drop the job-success conjunct (proceed on apply success alone) | G10 real-replace shape → proceed=true |
| 7 | Gate stubbed to `exit 0` right after `set -euo pipefail` (own dispatch) | every row in the GH list |
| 8 | Rename the replace job's `id: apply` step in a parsed copy of the workflow | PT1 reports a violation (in-test mutated YAML) |
| 9 | Append a second step running `terraform apply -auto-approve` to a parsed copy of the replace job | PT2 reports a violation (in-test mutated YAML) |

**Harness rows.**

- Suite edit that must go RED: run the new G9 against the pre-fix gate
  (`git show origin/main:.github/actions/dispatch-web-redeploy/source-run-gate.sh`) before editing
  the gate — it must fail there (AC2). A G9 that passes against the old gate is testing its own
  fixture. Recorded once in the PR body, not kept as suite code.
- Must-PASS non-canonical input: G1's birth fixture lists its steps in a non-canonical order and
  carries an extra step whose name has the apply name as a prefix
  (`Terraform apply (git-data birth) summary`, `success`); it must still proceed with
  `source_job=git_data_host_create`. A gate that rejects everything fails it; a prefix-matching
  gate reaches `N == 2` and exits 1.

**Anchor.** The gate constants and the workflow step names can be edited in one diff; PT1 proves
consistency, not integrity. What must move outside the commit for a weakening to pass: the
`@deruelle` CODEOWNERS row on `/.github/actions/dispatch-web-redeploy/` (`.github/CODEOWNERS`
line 214), and the real-API anchor of AC5 — the rewritten gate run read-only against four real
source runs, whose recorded outputs the PR body carries.

## Acceptance Criteria

- [ ] AC1 — Mutation 1 (revert to job conclusion) turns G9 RED; mutation 6 turns G10 RED.
- [ ] AC2 — Row **G9** (the #8710 regression, shape of run 35979044625: replace job `success`,
  apply step `skipped`) yields `proceed=false`, exit 0, a `::notice::` containing `no apply ran`,
  and **no** `::warning::`. G9 fails against the pre-fix gate (run it against
  `git show origin/main:.github/actions/dispatch-web-redeploy/source-run-gate.sh` before editing
  the gate — RED first, per `cq-write-failing-tests-before`); the red output is in the PR body.
- [ ] AC3 — G9b: the same rehearsal shape for the birth job → `proceed=false`, so both jobs are
  covered.
- [ ] AC4 — G1/G2 proceed with the right `source_job`; G10 (shape of 35979304442: apply `success`,
  poll `failure`, job `failure`) → `proceed=false`, `::warning::` containing `apply=success`;
  G11 (birth job `failure` at the plan step, apply `skipped` — shape of 34822248580) →
  `proceed=false`, notice only, no `::warning::`; G12 (apply `failure`) → the "pin may be
  published" warning and summary line (G4's and G8's assertions move here; G4 and G8 are deleted);
  G14 (green job, no step with the exact apply name), G15 (green job, two), G18 (green job, no
  `steps` key) → exit 1 with `fail closed`; G3/G5/G6/G7 unchanged in intent, fixtures carry steps.
- [ ] AC5 — Before merge, the rewritten gate is run **read-only** against the four real source
  runs (`SOURCE_RUN_ID=<id> bash .github/actions/dispatch-web-redeploy/source-run-gate.sh`, which
  only calls `gh run view <id> --json jobs`): 35979044625 → `proceed=false` with `no apply ran`;
  35979304442 → `proceed=false` with `apply=success`; 34822248580 → `proceed=false`, no warning;
  34836141887 → `proceed=false` with `apply=success`. This is the only check that exercises the
  em-dash step name against the real API; outputs go in the PR body.
- [ ] AC6 — Mutations 2–5 and 7 turn their named rows RED inside
  `tests/scripts/test-dispatch-web-redeploy.sh` (via `_mut_row` with the gate as source); the `GH`
  loop lists G3 G5 G6 G7 G9 G9b G10 G11 G12 G14 G15 G18.
- [ ] AC7 — `terraform-target-parity.test.ts`: `applyStepParity` returns `[]` for the real workflow
  and a violation for each of mutations 8 and 9 (in-test, no scratch copy).
- [ ] AC8 — Runbook: the "Boot order on the replace" bullet and the §2026-09-24 runbook row G2
  "Clean means" cell are corrected; `grep -c 'shows no run it triggered'
  knowledge-base/engineering/operations/runbooks/git-data-luks-cutover-5274.md` prints `0`.
- [ ] AC9 — The follower's failure email body contains both the existing
  `-f source_run_id=` sentence and a no-`source_run_id` dispatch sentence
  (`grep -c 'gh workflow run git-data-pin-redeploy.yml --ref main' .github/workflows/git-data-pin-redeploy.yml`
  is at least 2 lines, one in the email body).
- [ ] AC10 — `bash tests/scripts/test-dispatch-web-redeploy.sh`, `bun test
  plugins/soleur/test/terraform-target-parity.test.ts` and `bash
  tests/scripts/test-infra-privileged-tier-census.sh` pass; `scripts/test-all.sh --capacity` is run
  before any commit that stages a `.ts` file.
- [ ] AC11 — Every verification is hermetic or read-only: the suite runs with the `gh` PATH stub
  (exit 64 on any unexpected argv), AC5 calls only `gh run view … --json jobs`, and no task in
  `tasks.md` invokes `gh workflow run`, `gh run rerun` or a `dispatches` API.
- [ ] AC12 — Merge only when every context in
  `scripts/ci-required-ruleset-canonical-required-status-checks.json` is present **and** `success`
  by name on the exact head SHA (`gh api repos/{o}/{r}/commits/<sha>/check-runs` joined by name).
  Normal auto-merge (the PR edits `.github/actions/`, so no agent admin-merge); if `main` livelocks
  the queue, stop and hand the merge to the operator.
- [ ] AC13 — After merge, `gh issue view 8710 --json state,closedByPullRequestsReferences` shows it
  closed by this PR (the runbook row G2 precondition).

## Test Scenarios

Hermetic, in `tests/scripts/test-dispatch-web-redeploy.sh` (fixtures synthesized in the measured
shape; the `gh` stub keeps refusing any other argv with exit 64). Each negative row has a positive
control on the same fixture shape differing only in the field under test (G9 ↔ G2, G9b ↔ G1,
G14/G15/G18 ↔ G2):

- **G1** (must-PASS, non-canonical) Birth job `success`, steps reordered, a prefix-named decoy step
  `success`, apply `success` → `proceed=true`, `source_job=git_data_host_create`.
- **G2** Replace job `success`, apply `success` → `proceed=true`, `source_job=git_data_host_replace`.
- **G3** Both jobs `skipped`, `steps: []` → quiet `proceed=false`.
- **G9** Replace job `success`, apply `skipped` (plan_only rehearsal) → `proceed=false`, rc 0,
  notice with `no apply ran`, no `::warning::`.
- **G9b** The same for the birth job.
- **G10** Replace job `failure`, apply `success`, poll `failure` → `proceed=false`, `::warning::`
  with `apply=success`, summary line naming the runbook section and the no-`source_run_id` dispatch.
- **G11** Birth job `failure` at the plan step, apply `skipped` → `proceed=false`, notice only.
- **G12** Replace job `failure`, apply `failure` → the "pin may be published" warning + summary line.
- **G14** Replace job `success`, no step named exactly the apply constant → exit 1, `fail closed`.
- **G15** Replace job `success`, two steps with the apply name → exit 1.
- **G18** Replace job `success`, no `steps` key → exit 1.
- **G5 / G6 / G7** unchanged (gh failure, non-numeric id, non-`{jobs:[…]}` document).

Parity (bun): **PT1** apply-step name ⇄ gate constant for both jobs; **PT2** one command-position
`terraform apply` step per job — each run on the real workflow and on an in-test mutated copy.

Runbook read check (**T-R1**, the read-only lookup the runbook row G2 cell will carry — documented
here, not executed by this change). Find the follower run by its log, since a `workflow_run` run does not expose its
source run id:

```bash
for id in $(gh run list --workflow git-data-pin-redeploy.yml --created ">=<G2 start>" --json databaseId --jq '.[].databaseId'); do
  gh run view "$id" --log | grep -F "in run <G2 run id>" | grep -q 'no apply ran' && echo "$id"
done
```

Then
`gh run view <that id> --json jobs --jq '.jobs[0].steps[] | select(.name | startswith("Dispatch web-platform-release")) | .conclusion'`
prints `skipped`. (Verified 2026-09-24 that the log grep identifies a follower: run 35979135707's
log carries `in run 35979044625`.) The follower always runs `main`'s copy, so the fix is live the
moment it merges; no deploy step is involved.

## Success Metrics

- The next `plan_only` rehearsal (runbook G2) creates a pin-redeploy run whose dispatch step is
  `skipped` and no `web-platform-release` run.
- The next real replace (G3) produces exactly one pin redeploy that proceeds, attributable to that
  replace's run id.

## Dependencies & Risks

- **Risk: a false skip after a real rotation (stale pin).** Mitigated by rule row 4 failing closed
  (email) rather than skipping, by the parity test, and by keeping the no-`source_run_id` manual
  recovery unchanged.
- **Risk: step-name coupling.** Accepted and pinned (parity test + fail closed). The alternatives
  that avoid it (artifact, annotation, job output) each fail a requirement (Research Reconciliation).
- **Re-run attempts (pre-existing, not measured).** `gh run view <id> --json jobs` lists the latest
  attempt of each job, so after a "re-run failed jobs" of a run whose git-data job had already
  succeeded, a carried-over `success` could proceed a second time — an extra same-pin redeploy, never
  a missed one, and only when a *different* job in that run failed. No re-run of any workflow exists
  in the repository's last 500 runs to capture the real shape from, so no fixture is written from
  memory. Tracked as #8760 (re-evaluate when a real partial re-run can be captured).
- **Rule row 5 ends the follower green** (no failure email), exactly as today's warning arm. Kept:
  the operator is already handling a red apply job, the warning and step summary carry the
  recovery command, and turning them red would conflate "pin not loaded" with the gate's own
  fail-closed errors. For a birth with `apply=success` the warning names the only recovery (a dispatch with no
  `source_run_id`), since a birth cannot be repeated.
- **Concurrent edits:** no open PR touches these files (checked 2026-09-24). If a merge conflict
  lands in `scripts/guard-vacuity-floor.test.sh` `PROMOTED_FILES`, resolve as a union; re-derive
  baselines/floors after every merge.
- Do not edit the append-only PR1 counsel-review audit (#8634).

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only placeholder text, or omits
  the threshold fails `deepen-plan` Phase 4.6. This one declares `aggregate pattern`.
- The replace apply-step name contains an em dash (`—`, U+2014). Copy it byte-for-byte from the
  workflow into the gate; the parity test compares bytes, and a hyphen-minus substitute reaches
  rule row 4 (exit 1) on the next real replace.
- Write G9 (and G9b) and run them against the **pre-fix** gate before touching it: they must fail
  there. A G9 that passes against the old gate is testing its own fixture, not the fix.
- `jq` defaults: never write `.conclusion // ""` — a `null` apply conclusion must print as
  `apply=null` in the warning, not vanish. Test `(.steps | type) == "array"` explicitly.
- The `gh` stub's accepted argv stays exactly `run view <id> --json jobs`; the gate must not grow a
  second `gh` call (the stub exits 64 on anything else, which is how a drifted call shape reds the
  suite).
- Run `npx markdownlint-cli2` on this plan and on `tasks.md` before committing them.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — infrastructure/tooling change (a CI gate's decision input
and its tests). No user-facing surface, no copy, no pricing, no legal or data-processing change.

## References & Research

- Gate: `.github/actions/dispatch-web-redeploy/source-run-gate.sh`; follower:
  `.github/workflows/git-data-pin-redeploy.yml`; jobs: `.github/workflows/apply-web-platform-infra.yml`
  (`git_data_host_replace`, `git_data_host_create`, steps `id: apply`).
- Pin writer: `apps/web-platform/infra/git-data.tf` `resource "doppler_secret" "git_data_ssh_host_key"`
  (`depends_on = [hcloud_server.git_data]`).
- `plan_only` rationale: `knowledge-base/engineering/operations/runbooks/apply-web-platform-infra-job-rationale.md` §plan_only.
- ADR-237 (`knowledge-base/engineering/architecture/decisions/ADR-237-ssh-host-keys-are-pinned.md`) D2 + Consequences.
- Runs: 35979044625, 35979135707, 35979149543, 35979304442, 35980551109 (read-only).
- Issues: #8710 (this), #5274, #5914, #7226.
