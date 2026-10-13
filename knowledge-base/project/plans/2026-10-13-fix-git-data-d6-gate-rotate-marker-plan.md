---
title: "fix(infra): the git-data flip's d6_replace_stale gate must accept only a real rotate run"
type: fix
date: 2026-10-13
slug: git-data-d6-gate-rotate-marker
branch: feat-one-shot-10166-flip-gate-rotate-marker
issue: 10166
closes: 10166
priority: p2-medium
domain: engineering
lane: single-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

# fix(infra): the git-data flip's d6_replace_stale gate must accept only a real rotate run

## Overview

The `flip` mode of `.github/workflows/git-data-cutover.yml` has a precondition, `d6_replace_stale`, meant to
prove that a real `git-data-host-rotate` run (fresh host plus a re-minted LUKS key) completed before user
repositories move onto the LUKS-served store. The gate decides that by matching a step NAME
(`rotate confirm token`) and requiring `conclusion == success`. That step is
`Validate dispatch inputs (rotate confirm token)` in job `git_data_host_replace`; it is unconditional by census
contract (G5c) and exits 0 with `rotate confirm: n/a` on every non-rotate target. So a plain
`git-data-host-replace` run, or a plan-only rotate, satisfies the gate. The comment at
`git-data-cutover.yml` lines 262-269 claims the opposite. Measured on plain-replace run 37846545572: job and step
both `success`, inside the 40 runs the reader scans.

A second hole (issue extra-evidence comment): the reader `continue`s past any run whose job did not succeed, so a
rotate that failed AFTER replacing the LUKS volume (run 38140050880) is skipped and an OLDER success would
discharge D6.

The CTO ruled (2026-10-13, option 1) a small gate-correctness fix: a marker step as the last step of the job, the
gate selecting it by exact name; and (plan-phase ruling, see `## CTO Rulings`) the gate must also stop on a failed
newest rotate attempt. Issue #10138's rotate re-dispatch waits on this PR merging. Nothing is dispatched, applied,
written to Doppler, wiped or destroyed by this work; the modified workflow is NOT dispatched after merge.

## Enhancement Summary

**Deepened on:** 2026-10-13
**Method:** plan-review panel (DHH, Kieran, code-simplicity, architecture, spec-flow) already applied; this pass ran the mechanical halts
(4.6 user-brand, 4.7 observability, 4.11 guard contract via `scripts/lint-guard-contract.py`, 4.12 scope check), a prototype of the lib
against fixtures, and read-only measurements of live run records. The full 40-agent fan-out was not run: the change is one gate plus its
tests, the scope was ruled by the CTO and trimmed by five reviewers, and every remaining open question was answerable by measurement.

### Key improvements
1. The classifier and scan loop were prototyped (jq 1.8.2) against 22 classifier fixtures and 7 scan scenarios (plain replace, plan-only
   rotate, legacy success, stamped, failed/cancelled rotate, refused-at-precondition, in-flight, queued-no-jobs, unreadable bodies,
   decoy job, non-array `.jobs`, empty input): every verdict in the Phase 2 table behaves as specified, including `done 3<&0` plus
   `gh ... </dev/null` keeping the id stream intact.
2. Live read-only measurement (`gh run view --json jobs`, no logs) confirmed the discriminators: plain-replace run 37846545572 has
   precondition `skipped`, apply `success`, confirm-token step `success`; rotate run 38140050880 has precondition `success`, apply
   `failure`, job `failure`, confirm-token `success`. The job name and the precondition step name (with the em dash) match the lib
   constants byte for byte (jq `--arg` equality against the real API output returned a hit).
3. `## Scope Check` rewritten to the canonical schema (ask mapping with verbatim quotes, provenance with justified `inferred` rows, split
   assessment) so the 4.12 halt passes.

### New considerations discovered
- The apply step's post-#10155 name (`... - post-apply backstop`) exists in no run yet (run 38140050880 still carries `... - both-volumes-preserved
  assert`), so it cannot be verified against GitHub before the first post-merge rotate; the plan's stamped-first ordering (row 4) makes that harmless.
- The `Dispatch summary` step reads `success` even inside a failed job (run 38140050880), which is why the marker's implicit `success()`
  - not the summary's conclusion - is what proves the job succeeded.

## Premise Validation (Phase 0.6)

- `gh issue view 10166`: OPEN, no closing PR; CTO ruling comment dated 2026-10-13 present. `gh pr view 10155`: MERGED
  2026-10-12 (the mode-aware post-apply backstop; it is the harness precedent, not a blocker).
- Verified on this branch (`origin/main` base): `Validate dispatch inputs (rotate confirm token)` at
  `apply-web-platform-infra.yml:3747` is unconditional, exits 0 `n/a` on non-rotate; the gate loop is at
  `git-data-cutover.yml:262-281`; job `git_data_host_replace` has no `name:` (its API name is the id); its last step
  today is `Dispatch summary` (`if: always()`).
- ADR corpus grep (`rotate` / `d6`): ADR-220 (2026-09-30 amendment) states "freshness" as a completed rotate "whose
  rotate-confirm marker step concluded success" - the ruling's mechanism does not appear in any rejected-alternatives
  table; the sentence is simply false against the code and is corrected (see Phase 4). No architectural decision is
  made, so no ADR is created.
- Premise held: nothing cited is stale. One caveat carried forward: pre-#10155 runs (e.g. 38140050880) carry a
  differently named apply step, so they classify as "not a rotate attempt" - harmless, because a stamp can only exist
  from the first post-merge rotate onward, so no older stamp exists for them to mask.

## Property List and Cut List (Phase 0.6b)

Properties the ask buys:

- P1. A plain replace and a plan-only rotate can never discharge `d6_replace_stale`.
- P2. Only a rotate whose whole job succeeded (apply, boot poll, pin load, summary) discharges it.
- P3. An unreadable, in-flight or failed NEWEST rotate attempt blocks the flip instead of being skipped in favour of
  an older success.
- P4. The decision logic is testable offline against fixture job JSON, and the workflow wiring cannot silently drift
  from the tested logic.
- P5. The confirm-token step stays unconditional (census G5c).

Cut List (mechanisms considered and removed):

- A job-level output / `needs` flag published to the cutover workflow -> P2: cross-workflow, and `gh run view` is
  already the reader's channel.
- A second `apply_target -> "is rotate"` mapping in the reader -> P1: the marker step's own `if:` is the single
  source (the lesson of the #10155 learning: a mode decided in one step must be published, not re-derived).
- Extending `tests/scripts/lib/git-data-host-replace-gate.sh` -> P4: different concern and consumer (CTO ruling).
- `gh api .../runs/<id>` inputs lookup to read `apply_target` -> P1: workflow_dispatch inputs are not exposed by
  `gh run view --json jobs`; step conclusions are.
- Mechanism that already covers a property: none. Grepped `scripts/lib/`, `tests/scripts/lib/` and the cutover
  workflow: no existing function reads step conclusions out of `gh run view` output.

## Research Insights

- Harness precedent (PR #10155): `tests/scripts/test-git-data-host-replace-gate.sh` (PA/PM rows, anti-vacuity floor
  101), `tests/scripts/lib/git-data-host-replace-gate.sh`, and in `plugins/soleur/test/terraform-target-parity.test.ts`
  `extractJobBlock` / `extractStep` / `stripComments` / `stripLineComment` plus anchored pins on comment-stripped text.
- Learning `2026-10-12-a-mode-decided-in-one-step-and-re-derived-in-the-next-is-two-sources-of-truth.md` (item 13 is
  this very defect): pin the WIRE not the endpoints; comment-stripped, line-anchored pins; run a mutation battery
  before review. `2026-10-09-my-gate-pins-were-green-and-left-position-wiring-...`: position and wiring are part of a
  gate pin. `2026-10-11-a-fake-that-ignores-its-selectors-...`: a PATH shim for `gh` must refuse any argv it does not
  model, with an epilogue row asserting it never refused. `2026-10-10-my-must-pass-arm-...`: every must-PASS arm needs
  a placement that proves the mutation landed where the property lives; every suite gets a floor.
- Runtime libs live in `scripts/lib/` with a sibling `*.test.sh` (auto-registered by `scripts/test-all.sh`
  `SUITE_GLOBS` entry `scripts/lib/*.test.sh`); precedent `bearer-curl.sh` sourced at `git-data-cutover.yml:254` with a
  fail-closed `|| fail`.
- Census G5 (`tests/scripts/test-infra-privileged-tier-census.sh:1224-1273`): gate steps are matched by
  `interlock|validate\s+dispatch|verify\s+required|preflight` and must be unconditional; mutating steps (terraform
  apply / ssh) must carry the plan_only guard; no step may be ENABLED by plan_only. The marker is a no-op `echo`, has
  `inputs.plan_only != true`, and its name matches none of those patterns.
- `gh run view <id> --json jobs` exposes per-job `name`, `conclusion` and per-step `name`, `conclusion` (not step ids,
  not dispatch inputs). Step names with em dashes must match byte for byte, hence constants plus a parity pin.
- Code-review overlap (Phase 1.7.5): none of the planned files is named in an open `code-review` issue.
- Prototype notes (deepen): `first // null` on an empty array is `null` on jq 1.8.2 and 1.7 (CI ubuntu-24.04 ships 1.7.x); the classifier
  must receive its JSON by here-string, never bare stdin, so the scan's id stream is never consumed; a `read -u 3` loop closed by
  `done 3<&0` plus `gh run view ... </dev/null` keeps the ids intact.
- Verified citations (live): #10166 OPEN, #10137 CLOSED (the rotate-arm assert fix), #10138 OPEN (the authorization item that waits on
  this PR), PR #10155 MERGED 2026-10-12; `gh run list --workflow apply-web-platform-infra.yml --branch main --event workflow_dispatch
  --limit 100` returns exactly 100 rows today, so the 40-run window is already exhausted on a busy history (the reason for 100).

## Research Reconciliation - Spec vs. Codebase

| Claim | Reality | Plan response |
|---|---|---|
| Issue body: marker step "also fixes the plan-only case" | True for plan-only; but a failed rotate also reads marker `skipped`, same as a plain replace | The lib also classifies rotate attempts via the precondition + apply steps (Fork 1 ruling) |
| CTO AC: "fails closed on a missing, skipped or empty result" | A legacy (pre-marker) successful rotate and a skipped marker are "not a stamp" but carry no uncertainty | Per-run verdict `skip` continues the scan; the overall result stays closed (`d6_replace_stale`) unless a stamp is found |
| Gate comment: confirm step "concludes success only on a rotate dispatch" | False: exits 0 `n/a` elsewhere | Comment rewritten (Phase 3) |
| Brief: gate jq "in a sourced lib function" | The scan loop (stop rules) is also decision logic | Both the per-run classifier and the scan loop live in the lib; the workflow only maps verdicts to remedies |

## CTO Rulings (recorded in `knowledge-base/project/specs/feat-one-shot-10166-flip-gate-rotate-marker/decision-challenges.md`)

- Ruled by CTO agent, 2026-10-13: option 1 (marker step) - the binding design from the issue.
- Ruled by CTO agent, 2026-10-13: failed newest rotate is IN scope; the discriminator is the apply step (not the
  precondition step, which would falsely block on a refusal that touched nothing).
- Ruled by CTO agent, 2026-10-13: new `scripts/lib/git-data-rotate-stamp.sh` + `.test.sh`; constants in the lib, parity
  test asserts workflow names equal them; exact job name; hand-rolled floor.
- Ruled by CTO agent, 2026-10-13: marker is the literal last step after `Dispatch summary`; parity pin parses `steps`.
- Ruled by CPO agent, 2026-10-13: threshold `single-user incident`.

## User-Brand Impact

- **If this lands broken, the user experiences:** a cutover (`flip`) that proceeds without a proven key rotation, so the
  predecessor-host exposure window for their repositories is not closed; or, if it fails closed wrongly, a blocked flip
  that only delays the migration (an operator re-dispatch, no data effect).
- **Artifacts and vectors (review amendment 2026-10-13):** user repository content on the LUKS-served store
  and the retained plaintext predecessor volume (vector: a fail-open stamp lets the flip run without a proven
  rotation); the LUKS passphrase lifecycle (vector: a failed newest rotate masked by an older success, or a
  stamp surviving a later plain replace, which is an accepted residual: the stamp attests a rotate job
  completed, not escrow state, and re-escrow #9949 is not claimed); the flip operator (vector: a sticky
  `d6_last_rotate_failed` that only a newer successful rotate clears pushes towards a bypass, so no bypass
  input exists and the runbook documents the exit).
- **If this leaks, the user's data is exposed via:** no new surface. The change reads run state with the existing
  `actions: read` token, prints only step names, run ids and verdict tokens, and touches no credential, plan value or
  host. The exposure risk is the fail-open gate itself.
- **Brand-survival threshold:** `single-user incident`
- **Threshold decision (challengeable):** one user's repository content sitting on an unrotated store after the flip is
  a confidentiality breach, so the threshold cannot be lower; the CPO agent confirmed it (2026-10-13).

## Architecture Decision (ADR/C4)

No architectural decision: a gate-correctness fix on an existing gate (CTO). C4: no change - no new actor, system,
container, data store or access relationship (read of Actions run state by the existing precondition step; all three
`.c4` model files checked in the sense that the cutover workflow's `actions: read` use is already the modeled
GitHub-Actions edge). The one doc correction is ADR-220's stale sentence (Phase 4). `c4-count-parity` is unaffected (no
workflow or monitor count changes; one STEP is added, not a workflow).

## Encryption Posture / IaC

Skipped: no new store, no new cross-component connection, no new infrastructure. The marker is a no-op `echo`.

## Plan-Review Dispositions (2026-10-13; DHH, Kieran, code-simplicity, architecture, spec-flow)

Applied (mechanical): stamped row moved ahead of the attempt rows (Kieran P1-1, architecture P1); run list captured before the
scan with its own `d6_run_unreadable` failure (Kieran, architecture, spec-flow); `gh` runs with `</dev/null`, loop on fd 3, jq via
here-string (Kieran P2-4); classifier always prints one token (P2-5); comment moved inside the marker step (P2-8); tokens collapsed
7 -> 5 (`skip` replaces three continue tokens); duplicate-job/duplicate-step rows, numeric-id check, PATH shim (-> `gh()` function),
M-battery 10 -> 4, parity mutants 14 -> 6, P-h and census regex pin dropped, P-e reduced to three checks, floor self-proof PR text
dropped; queued run with no jobs treated as in flight; window 40 -> 100; in-flight-before-attempt ordering stated; operator exit and
remedy wording improved; re-run, post-step, rename and dispatch-ref notes added.

Considered and kept per the CTO ruling (not re-asked): the marker step itself. The simplicity seat observed it is redundant with
the apply-step classifier for P1/P2; the CTO ruled option 1 and the marker is what makes "job and every step succeeded" a single
exact-name fact (row 4), which is also why a step-name drift cannot reject a real stamp.

Surfaced as taste (default applied, in decision-challenges.md): keep the runbook verdict rows (simplicity cut 11: the annotation
already carries the remedy) because the failed-rotate block is sticky and an operator needs its exit documented; keep the
Guard Contract matrix (the lint requires >= 3 rows).

## Observability

```yaml
liveness_signal:
  what: the flip precondition prints one verdict line per scan - d6 rotate stamp run <id>, or a fail with verdict=d6_*
  cadence: per git-data-cutover flip dispatch
  alert_target: the dispatching operator via the failed run's annotations (the notify-failure job's issue and email carry the verdict words of its own steps, not the d6_* tokens)
  configured_in: .github/workflows/git-data-cutover.yml (flip_preconditions step) and scripts/lib/git-data-rotate-stamp.sh
error_reporting:
  destination: GitHub Actions annotation ::error title=git-data-cutover preconditions::verdict=<token>
  fail_loud: exit 1 with verdict=d6_replace_stale | d6_last_rotate_failed | d6_rotate_in_flight | d6_run_unreadable
failure_modes:
  - mode: plain replace or plan-only rotate treated as a rotate
    detection: lib suite rows R1-R4 and the parity pins fail in CI
    alert_route: required CI check on the PR
  - mode: step renamed in the apply workflow without the lib constants following
    detection: parity test asserts the workflow names equal the lib constants
    alert_route: required CI check on the PR
  - mode: gh run list or gh run view fails or returns unparseable JSON
    detection: verdict d6_run_unreadable (fails closed, never continues to an older run, never reported as stale)
    alert_route: failed flip run
logs:
  where: GitHub Actions job log of the flip_preconditions step
  retention: GitHub Actions default (90 days)
discoverability_test:
  command: bash -c 'source scripts/lib/git-data-rotate-stamp.sh; git_data_rotate_run_verdict "{\"jobs\":[]}" || true'
  expected_output: skip
```

## Open Code-Review Overlap

None (checked `gh issue list --label code-review --state open` bodies against every planned file path).

## Domain Review

**Domains relevant:** Engineering

### Engineering (CTO)

**Status:** reviewed
**Assessment:** CTO ruled the design (option 1) on the issue and ruled the three plan-phase forks (failed newest rotate
in scope with an apply-step discriminator; new `scripts/lib` lib + sibling suite; marker as literal last step).

### Product

**Status:** reviewed (CPO sign-off, plan time)
**Assessment:** threshold `single-user incident` confirmed; no UI surface, no product-strategy concern. No Product/UX
gate (no user-facing page, flow or component). Specialists recommended by name: none.

## Implementation Phases

### Phase 0 - Preconditions (read-only)

- 0.1 Re-read `git-data-cutover.yml:225-290`, `apply-web-platform-infra.yml:3712-4190` and the PR #10155 files named in
  Research Insights; confirm the three step names byte for byte (`grep -n 'Rotate precondition' ...`).
- 0.2 No dispatch, no `terraform apply`, no Doppler write, no volume wipe/destroy anywhere in this work. Do NOT dispatch
  the modified workflow after merge. The local affected gate is skipped by the user's earlier decision; run only the
  focused suites named below, and rely on CI for the rest.

### Phase 1 - The marker step (`.github/workflows/apply-web-platform-infra.yml`)

Append, as the LAST step of `git_data_host_replace` (after `Dispatch summary`), a no-op step:

```yaml
      - name: Rotate completed (d6 marker)
        # (#10166) Read by git-data-cutover.yml's d6_replace_stale gate through scripts/lib/git-data-rotate-stamp.sh.
        # LAST step, no always(), no continue-on-error: the implicit success() makes "marker success" mean
        # "every earlier step, including Dispatch summary's exit 1 backstops, succeeded". Skipped on plain
        # replace, on a plan-only rotate and after any failure. Name: no "Validate"/"confirm".
        # (The comment sits INSIDE the step: extractStep/extract_step cut at the next `- name:`, so a comment
        # above it would attach to Dispatch summary's block.) Insert before the column-2 comment block that
        # precedes the next job (workspaces_luks_cutover).
        if: inputs.apply_target == 'git-data-host-rotate' && inputs.plan_only != true
        run: echo "git-data-host-rotate completed: apply, boot poll, pin load and summary succeeded (the d6 marker)"
```

- Do NOT touch `Validate dispatch inputs (rotate confirm token)` (stays unconditional, census G5c).
- File pointer for the paper-resolution lint: marker at the end of the `git_data_host_replace` job block
  (`apply-web-platform-infra.yml`, after the `Dispatch summary` step that currently ends near line 4185).

### Phase 2 - The lib and its suite (`scripts/lib/git-data-rotate-stamp.sh`, `.test.sh`)

Plan-review (2026-10-13, five seats) trimmed this phase: verdict tokens collapsed 7 -> 5, defensive duplicate-name rows,
the numeric-id check, the PATH shim, most lib mutants and most parity mutants were cut; the stamped row moved ahead of
the attempt rows; the run list is captured before scanning. See `## Plan-Review Dispositions`.

Lib API (all constants `readonly`, `GDRS_` prefix; no re-source guard, mirrors `bearer-curl.sh`):

- Constants: `GDRS_JOB_NAME=git_data_host_replace`; `GDRS_PRECONDITION_STEP="Rotate precondition — served store measured empty"`;
  `GDRS_APPLY_STEP="Terraform apply (git-data-host -replace) — post-apply backstop"`;
  `GDRS_MARKER_STEP="Rotate completed (d6 marker)"` (the em dash is U+2014; the parity pin asserts the code point).
- `git_data_rotate_run_verdict <jobs-json>`: ONE jq program (`--arg job/pre/apply/marker`, input via here-string, never bare
  stdin), prints exactly one token and returns 0 iff `stamped`. ANY jq failure, non-zero rc or empty output prints
  `unreadable` (a wrapper, so R-rows assert the printed token, not only rc). Table, evaluated in order:

| # | Condition on `gh run view --json jobs` output | Token |
|---|---|---|
| 1 | not valid JSON, or `.jobs` not an array | `unreadable` |
| 2 | no job named exactly `$job` (first match is used; names are unique), or its conclusion is `skipped` | `skip` |
| 3 | job conclusion empty or null (running / queued / waiting for approval) | `in_flight` |
| 4 | job `success` AND marker step `success` (the marker only exists on a rotate; self-sufficient, so a step-name drift in rows 5-6 can never reject a real stamp) | `stamped` |
| 5 | precondition step absent or `skipped` (plain replace, or never reached) | `skip` |
| 6 | apply step absent or `skipped` (plan-only, or refused before apply: nothing mutated) | `skip` |
| 7 | job `success` without a marker success (pre-marker legacy success) | `skip` |
| 8 | job any other conclusion (failure, cancelled, timed_out, ...) with a rotate attempt (rows 5-6 passed) | `rotate_failed` |

  Row 3 runs before the attempt rows on purpose: a job that is still running or waiting has no usable steps, so a plain
  replace waiting for approval also reads `in_flight` and blocks the flip (fails closed; the flip's own `git-data-state`
  concurrency group already serialises it behind a running replace). Stated, not hidden; the remedy says to wait or cancel
  a stale waiting run.
- `git_data_d6_scan`: reads `<run id><TAB><run status>` lines from stdin (newest first; the ids come from
  `gh run list --jq`, trusted integers, so no id-shape check). The loop reads on fd 3 and runs `gh run view "$rid" --json jobs
  </dev/null`, so nothing it calls can consume the id stream. Per run: a non-zero `gh` or empty body -> stop
  `d6_run_unreadable <rid>` (never `continue`: that was the fail-open); a run whose list status is not `completed` AND whose
  jobs array is empty (queued, no jobs yet, so its target is unknowable) -> stop `d6_rotate_in_flight <rid>`; otherwise by
  token: `stamped` -> `d6_stamped <rid>`, return 0; `skip` -> continue; `rotate_failed` -> `d6_last_rotate_failed <rid>`;
  `in_flight` -> `d6_rotate_in_flight <rid>`; `unreadable` or anything unrecognised (including empty) ->
  `d6_run_unreadable <rid>`. End of input -> `d6_replace_stale`. Returns 0 iff `d6_stamped`. The lib never calls `fail`/`exit`
  (it runs inside `$(...)`); under `set -e` off (left side of `||`) every failure is an explicit check.
  Output is one line: tokens and run ids only.

Suite `scripts/lib/git-data-rotate-stamp.test.sh` (model on `bearer-curl.test.sh`: own pass/fail with an instrument
self-test, `set -uo pipefail`, `TMPDIR` fallback, hand-rolled floor `MIN_ASSERTIONS=<measured-with-final-green>` as a
literal directly above its `if`, in a form `scripts/guard-vacuity-floor.test.sh` recognises, printf + exit 1, never via
`fail()`). Fixtures are synthesized with `jq -n`/`printf` (`cq-test-fixtures-synthesized-only`), never captured runs.

- Classifier rows: R1 plain replace (precondition skipped, apply success, confirm-token step success, marker skipped - the
  #10166 repro) -> `skip`, rc 1; R2 plan-only rotate (precondition success, apply skipped, job success, marker skipped) ->
  `skip`; R3 missing marker (legacy successful rotate) -> `skip`; R4 real rotate -> `stamped`, rc 0 (must-PASS companion:
  same with an extra unrelated step, shuffled order, and the precondition/apply steps absent - row 4 is self-sufficient);
  R5 failed rotate (apply failure, job failure, marker skipped) -> `rotate_failed`; R6 cancelled mid-apply ->
  `rotate_failed`; R7 refused at the precondition (precondition failure, apply skipped, job failure) -> `skip` (the
  false-block guard); R8 cancelled during the plan step (apply skipped) -> `skip`; R9 in-progress / null conclusion ->
  `in_flight`; R10 job skipped -> `skip`; R11 decoy job `git_data_host_replace_decoy` and case variant -> `skip`; R12 near-miss marker
  names (lowercase, trailing space) -> not `stamped`; R13 malformed bodies (empty string, `null`, `[]`, `{"jobs":null}`,
  `{"jobs":{}}`, truncated JSON) -> printed token `unreadable`; R14 steps absent/null on a successful job -> `skip`; R15 marker
  `success` but job `failure` (a failed post-job step) -> `rotate_failed` (closed and surprising: noted in the comments).
- Scan rows (a `gh()` shell function in the suite that models exactly `run view <id> --json jobs`, reads `$FX/<id>.json`, exits
  1 on a missing file, refuses any other argv with exit 64 plus a `gh.refused` line, and `cat`s its stdin so a stdin-consuming
  regression shows up as a missing row; an epilogue row asserts it never refused): S1 newest plain replace, older stamped ->
  `d6_stamped <older>`; S2 newest failed rotate, older stamped -> `d6_last_rotate_failed <newest>` (the extra-evidence hole);
  S3 newest unreadable -> `d6_run_unreadable <newest>` and the older stamped run is NOT consulted (the shim records calls);
  S4 newest in-flight -> `d6_rotate_in_flight`; S5 queued run with no jobs and status `queued` -> `d6_rotate_in_flight`; S6 only
  plain replaces / plan-only / legacy, and empty input -> `d6_replace_stale`; S7 a rotate refused at the precondition between
  the newest run and a stamped one does not block (continues to the stamped one).
- Mutation battery (a local `mutate_and_expect_red` over a COPY of the lib: refuses a byte-identical or `bash -n`-broken mutant,
  runs a healthy control first, asserts the targeted fixture's output changes): M1 marker must be `success` -> any conclusion,
  M2 `rotate_failed` arm -> continue, M3 `gh` failure -> continue, M4 the unrecognised-token arm -> continue. (Exact job name
  and the apply/precondition conditions are already killed directly by R11 and R1/R2/R7.)

### Phase 3 - The gate (`.github/workflows/git-data-cutover.yml`, step `flip_preconditions`)

Replace lines ~262-282 (the d6 comment, the `last_ok` loop and the single `fail d6_replace_stale`) with:

- A corrected comment: the gate scans the 100 newest `workflow_dispatch` runs of the apply workflow on main newest-first; a run
  discharges D6 only when its `git_data_host_replace` job succeeded AND the last-step marker `Rotate completed (d6 marker)`
  succeeded; the marker is skipped on plain replace, plan-only rotate and any failure; the newest rotate ATTEMPT decides, so a
  failed newest rotate blocks and an older success cannot mask it; the old `rotate confirm token` match is gone because that
  step succeeds on every target (displayTitle is the workflow name on dispatch runs, so the target is visible only in the
  job/step list). State the trust boundary: the lib comes from the dispatched ref's checkout (same boundary as `bearer-curl.sh`,
  held by the `main`-restricted reviewer environment).
- `source "${GITHUB_WORKSPACE:?}/scripts/lib/git-data-rotate-stamp.sh" || fail d6_run_unreadable "scripts/lib/git-data-rotate-stamp.sh could not be loaded from the dispatched ref's checkout - the d6 stamp could not be read."`, then the list is CAPTURED, no process
  substitution: `ids="$(gh run list --workflow apply-web-platform-infra.yml --branch main --event workflow_dispatch --limit 100 --json databaseId,status --jq '.[] | [.databaseId,.status] | @tsv')" || fail d6_run_unreadable "gh run list failed (API/rate limit) - the d6 stamp could not be read; re-run the flip"`, then
  `d6="$(git_data_d6_scan <<<"$ids")" || true` and `case "${d6%% *}" in d6_stamped) last_ok="${d6#* }"; echo "d6 rotate stamp: run $last_ok" ;; d6_last_rotate_failed) fail ...;; d6_rotate_in_flight) fail ...;; d6_run_unreadable) fail ...;; d6_replace_stale) fail ...;; *) fail d6_run_unreadable "unrecognised scan result" ;; esac`.
  (`|| true` is deliberate: the scan returns 1 for every non-stamp verdict; the `case` with a fail-closed `*)` arm, which also
  catches an empty capture, is the control.)
- Remedy texts: `d6_replace_stale` - "no successful git-data-host-rotate run carrying the rotate marker among the 100 newest dispatch runs (runs that
  predate the marker cannot qualify) - dispatch apply_target=git-data-host-rotate (confirm=ROTATE-GIT-DATA) from main first";
  `d6_last_rotate_failed` - "the newest rotate attempt (run N) did not complete, so host and key state are uncertain; an older
  success does not discharge D6 - read run N and the runbook, repair, and re-dispatch the rotate (a newer successful rotate
  supersedes it)"; `d6_rotate_in_flight` - "a git-data replace/rotate run (N) is running, queued or waiting for approval - re-dispatch the flip
  once it completes (cancel a stale waiting run)"; `d6_run_unreadable` - "run state could not be read - re-dispatch the flip".
- `last_ok` stays so the final `echo "preconditions clear: ... d6 replace stamped ($last_ok) ..."` is unchanged.
- No inline step-selection `jq` remains in the step.

### Phase 4 - Docs kept true (minimal)

- ADR-220 (the 2026-09-30 amendment sentence at ~line 664): correct "rotate-confirm marker step" to the real marker
  (`Rotate completed (d6 marker)`), with a dated one-line correction note (#10166). No new ADR, no decision change.
- Runbook `knowledge-base/engineering/operations/runbooks/git-data-luks-cutover-5274.md`: add verdict rows `d6_last_rotate_failed`,
  `d6_rotate_in_flight`, `d6_run_unreadable` next to the `d6_replace_stale` row (~line 965) (the failed-rotate block is sticky:
  its only exit is a newer successful rotate, or the failed run aging out of the 100-run window; if a re-dispatch is refused
  at the precondition it does not supersede the failed run), and one sentence at ~line 193: a rotate run counts only if it
  carries the marker, so runs before this change cannot discharge D6 and the rotate must be re-dispatched once (the #10138
  re-dispatch); a stamp is not invalidated by a later plain replace (it never re-mints the key).

### Phase 5 - Parity pins (`plugins/soleur/test/terraform-target-parity.test.ts`)

Add a `describe("the d6 rotate marker (#10166)")` using the existing `extractJobBlock`, `extractStep`, `stripComments` and
`parseYaml`. Every text pin runs on comment-stripped text and anchors on a line start; a pure
`checkRotateMarkerWiring(applyWorkflowText, cutoverWorkflowText, libText): string[]` returns violations so the mutation rows
can run it on mutated copies.

Pins (all true on the real tree):

- P-a (position): parse the workflow YAML; `jobs.git_data_host_replace.steps.at(-1).name` equals the lib's `GDRS_MARKER_STEP`;
  the step before it is `Dispatch summary`.
- P-b (the `if:`): the marker step's stripped text has the anchored line
  `^\s*if: inputs\.apply_target == 'git-data-host-rotate' && inputs\.plan_only != true$` (strict by design); no `always()`,
  `!cancelled()`, `failure()` and no `continue-on-error` in any quoting.
- P-c (name): marker name does not match `/validate|confirm/i`; exactly one step has that name in the job. (The census G5 suite
  already enforces gate-name and mutating patterns for the marker; not duplicated here.)
- P-d (confirm step unconditional): `Validate dispatch inputs (rotate confirm token)` exists once with no `if:` line (stripped);
  the existing line-2220 name pin stays.
- P-e (gate reads the marker): the stripped `flip_preconditions` step has the `source ".../git-data-rotate-stamp.sh" || fail
  d6_run_unreadable` line, exactly one `git_data_d6_scan` call, the run list captured with `|| fail d6_run_unreadable`, and a
  `*)` case arm that calls `fail`.
- P-f (gate no longer reads the confirm step): the stripped cutover workflow contains no `rotate confirm token`, no
  `select(.name | test(` and no `jobs_json=`.
- P-g (constants parity): the workflow's job id and the precondition, apply and marker step names equal the lib's four constants
  byte for byte, em dash asserted as U+2014 (lib text read, constants extracted with an anchored regex).

Mutation rows (each makes `checkRotateMarkerWiring` non-empty on a mutated copy; each asserts the mutation CHANGED the text and
the unmutated control is clean): drop the `plan_only` conjunct (the CTO's example); drop the `apply_target` conjunct; add
`always() &&`; append a step after the marker; restore the old `rotate confirm token` read in the gate; change one character of
the marker constant. The battery asserts it ran 6 rows.

### Phase 6 - Verify (local, focused only)

- `bash scripts/lib/git-data-rotate-stamp.test.sh` (all rows, floor, mutation battery).
- `bun test plugins/soleur/test/terraform-target-parity.test.ts -t "d6 rotate marker"`, then the whole file.
- `bash tests/scripts/test-infra-privileged-tier-census.sh` (G5a-c) and `bash tests/scripts/test-git-data-boot-signal-poll.sh` (it
  `extract_step`s `Dispatch summary`; the new trailing step must not change its extraction) - cheap and focused, not the affected gate.
- `bash scripts/guard-vacuity-floor.test.sh` (the new suite's floor must be recognised) and `shellcheck` on the new scripts; `actionlint` on the two workflows if present locally.
- Everything else (the full affected gate, repo-global ratchets) is left to CI by the user's earlier decision. Measure the floors from the final green run, not from this plan.

## Files to Edit

- `.github/workflows/apply-web-platform-infra.yml` - append the marker step (Phase 1).
- `.github/workflows/git-data-cutover.yml` - replace the d6 loop and comment (Phase 3).
- `plugins/soleur/test/terraform-target-parity.test.ts` - marker/gate/constants pins and mutation rows (Phase 5).
- `knowledge-base/engineering/architecture/decisions/ADR-220-git-data-root-access-via-web-1-jump-and-a-dedicated-terraform-minted-key.md` - one-sentence dated correction (Phase 4).
- `knowledge-base/engineering/operations/runbooks/git-data-luks-cutover-5274.md` - verdict rows and one sentence (Phase 4).

Verified paths: `git ls-files` shows each edit target exists; `scripts/lib/*.test.sh` matches `SUITE_GLOBS`; no glob prescribed
beyond that.

## Files to Create

- `scripts/lib/git-data-rotate-stamp.sh` - classifier, scan loop, constants (Phase 2).
- `scripts/lib/git-data-rotate-stamp.test.sh` - fixtures, shim, scan rows, mutation battery, floor (Phase 2).

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "add a marker step as the last step of `git_data_host_replace` in .github/workflows/apply-web-platform-infra.yml with `if: inputs.apply_target == 'git-data-host-rotate' && inputs.plan_only != true` (no always(), no continue-on-error; name must not contain \"Validate\" or \"confirm\")" [brief] | Phase 1; Files to Edit entry 1 | mapped |
| 2 | "make the d6_replace_stale gate in .github/workflows/git-data-cutover.yml select the marker by exact name, require success, fail closed on missing/skipped/empty" [brief] | Phases 2-3; Files to Edit entry 2; Files to Create entries 1-2 | mapped |
| 3 | "drop the confirm-token step name match and correct the gate comment (lines ~263-265)" [brief] | Phase 3 | mapped |
| 4 | "keep the confirm-token step unconditional (census G5c)" [brief] | Phase 1 (untouched), pin P-d | mapped |
| 5 | "offline jq fixtures (replace, plan-only rotate, missing marker rejected; real rotate accepted)" [brief] | Phase 2 rows R1-R4 | mapped |
| 6 | "parity-test pins (marker if: line, gate reads marker, gate no longer reads confirm-token step, confirm-token step still unconditional)" [brief] | Phase 5 pins P-a..P-g | mapped |
| 7 | "at least one mutation row (e.g. dropping the plan_only conjunct) caught" [brief] | Phase 5 mutation rows; Phase 2 M1-M4 | mapped |
| 8 | "The gate's step-selection jq should live in a sourced, unit-testable lib function exercised against fixture job JSON, with the workflow calling it (do not leave it inline)." [brief] | Phase 2 lib, Phase 3 call site | mapped |
| 9 | "Parity pins must run on comment-stripped, line-anchored text." [brief] | Phase 5 preamble | mapped |
| 10 | "no workflow dispatch, terraform apply, Doppler write, volume wipe or destroy; do not post-merge dispatch the modified workflow; skip the local affected gate and rely on CI" [brief] | Phase 0.2, Phase 6, AC8 | mapped |
| 11 | "No ADR change unless the plan finds one is required" [brief] | `## Architecture Decision (ADR/C4)`; Phase 4 one-sentence ADR-220 correction (not a decision) | mapped |
| 12 | "The reader must additionally stop skipping a failed newest rotate, or it still reads an older success." [issue #10166 comment] | Phase 2 scan loop, rows R5-R6, S2 | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| Files to Edit: `.github/workflows/apply-web-platform-infra.yml` (marker) | asks 1, 4 | asked |
| Files to Edit: `.github/workflows/git-data-cutover.yml` (gate) | asks 2, 3 | asked |
| Files to Edit: `plugins/soleur/test/terraform-target-parity.test.ts` | asks 6, 7, 9 | asked |
| Files to Create: `scripts/lib/git-data-rotate-stamp.sh` and `.test.sh` | ask 8 | asked |
| Scan loop and the five verdict tokens (stop rules) | ask 12 | asked |
| Queued run with no jobs treated as in flight; unreadable `gh run list` stops the scan; window 40 -> 100 | - | inferred - justification: the original reader's `continue` on any unreadable or non-success run was the fail-open this PR closes; the same fail-closed rule must hold for a run list that cannot be read and a run whose target is unknowable, and a stamp pushed out of a 40-run window would send an already-rotated system back to a destructive rotate (plan-review: spec-flow, architecture, Kieran) |
| Files to Edit: ADR-220 one-sentence correction | ask 11 | inferred - justification: the 2026-09-30 amendment states the gate reads "the rotate-confirm marker step", which this fix makes false; leaving it would make the recorded architecture lie about the gate |
| Files to Edit: runbook verdict rows and sentences | - | inferred - justification: the failed-rotate block is sticky and the new verdicts carry operator exits that must be documented where the existing `d6_replace_stale` row lives |
| Parity pin P-g (lib constants equal workflow step names) | ask 2 ("by exact name") | asked |

### Split Assessment

- Subsystems touched: 4 - `.github/workflows`, `scripts/lib`, `plugins/soleur/test`, `knowledge-base/engineering`
- Planned files: 7 | Estimated changed lines: ~650 (about 70% test code)
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR - the 4-root threshold trips only because of doc and test roots; the marker, the gate and the lib are one inseparable fix (a marker without its reader, or a reader without its marker, leaves the gate either fail-open or permanently closed), and the two doc edits are one-line truth fixes.

## Acceptance Criteria

### Pre-merge (PR)

- [x] AC1. `Rotate completed (d6 marker)` is the LAST step of `git_data_host_replace`, after `Dispatch summary`, with `if:` exactly
  `inputs.apply_target == 'git-data-host-rotate' && inputs.plan_only != true`, no `always()`, no `continue-on-error`; its name
  contains neither "Validate" nor "confirm" (P-a..P-c; `apply-web-platform-infra.yml`, end of the job block).
- [x] AC2. The gate (`git-data-cutover.yml`, `flip_preconditions`) selects the marker via `git_data_d6_scan`/`git_data_rotate_run_verdict` in
  `scripts/lib/git-data-rotate-stamp.sh` by exact job and step name, requires `success`, fails closed on missing / skipped /
  empty / unreadable; the old `rotate confirm token` match is gone and the comment is corrected (P-e, P-f).
- [x] AC3. A failed or cancelled newest rotate attempt blocks (`d6_last_rotate_failed`) and an older success cannot mask it
  (rows R5, R6, S2); a refusal before apply does not block (R7, S7); unreadable run JSON or a failed run list stops the scan (S3, P-e).
- [x] AC4. Offline jq fixtures: replace (R1), plan-only rotate (R2), missing marker (R3) rejected; real rotate (R4) accepted;
  all in `scripts/lib/git-data-rotate-stamp.test.sh`, passing, with a floor measured from the final green run.
- [x] AC5. Parity pins P-a..P-h pass on the real tree, comment-stripped and line-anchored
  (`plugins/soleur/test/terraform-target-parity.test.ts`); the confirm-token step is still unconditional (P-d) and
  `tests/scripts/test-infra-privileged-tier-census.sh` G5a-c is green.
- [x] AC6. The mutation batteries (lib M1-M4, parity rows including "drop the `plan_only` conjunct") are each RED on their mutant and green on
  the control; each row asserts its mutation changed the text.
- [x] AC7. ADR-220 sentence corrected and runbook rows added (Phase 4); no new ADR; nothing outside the Files lists changed.
- [ ] AC8. PR body: `Closes #10166`; states nothing was dispatched/applied/written/wiped, that the modified workflow is
  not to be dispatched after merge, and that runs predating the marker cannot qualify (so the rotate re-dispatch in #10138 is
  required after this merges). It also records a read-only `gh run view <id> --json jobs` of the newest `git_data_host_replace`
  run (step NAMES only) when one carries the post-#10155 apply-step name; if none does, say so (the first real rotate is then the
  live proof - stamping does not depend on those names, row 4).

### Post-merge

None operator-side in this PR (no dispatch). The #10138 rotate re-dispatch is a separate, operator-authorized action.

## Guard Contract

### Guard 1 - d6 rotate stamp (marker + lib classifier + scan)

**Property.** Only a run whose `git_data_host_replace` job succeeded with the `git-data-host-rotate` marker step succeeded
can discharge `d6_replace_stale`, and a rotate attempt that did not complete newer than that run blocks instead of being skipped.

**Assembly.** The population this quantifies over is every route by which a run record could read as "rotated": (1) the
marker step's own `if:` in `apply-web-platform-infra.yml` (the single place the target/plan_only decision is made);
(2) the lib classifier `git_data_rotate_run_verdict` (one jq program, all eight table rows); (3) the lib scan loop
`git_data_d6_scan` (the stop rules - the chokepoint every run id flows through); (4) the single workflow call site in
`git-data-cutover.yml` (`flip_preconditions`, the only reader of the stamp; a second reader would be a second source of
truth) and its `case` fail-closed `*)` arm; (5) the four name constants shared by the lib and the apply workflow;
(6) the confirm-token step, which must stay unconditional and must NOT be read by the gate. A guard scoped to the marker `if:`
alone, or to the classifier alone, is the defect: the scan loop's `continue` was the second hole.

**Mutation matrix.**

| # | Mutation (must turn the guard RED) | Targets |
|---|---|---|
| 1 | Drop `inputs.plan_only != true` from the marker `if:` | parity pin P-b (a plan-only rotate would stamp) |
| 2 | Add a second compliant-looking marker-class member: append any step AFTER the marker, or move the marker before `Dispatch summary` | P-a (position); a check that stops at the first/only step is the class |
| 3 | Lib dispatch: delete the scan loop's `rotate_failed` arm (treated as continue), with a fixture of [failed newest rotate, older stamped] | S2 / M2 (an older success would mask a failure) |
| 4 | Lib dispatch: make the unrecognised-token arm continue, or let `gh` failure `continue` | S3 / M3 / M4 (the original fail-open) |
| 5 | Reorder/lifetime: gate calls the scan BEFORE the lib is sourced, or reassigns the verdict between scan and `case` | P-e anchored sequence (position row, not a delete row) |
| 6 | Decoy job named `git_data_host_replace_decoy` with a succeeded marker; regex job match | R11 (identifier set narrower than the property) |
| 7 | The old `rotate confirm token` name match restored in the gate | P-f |

**Harness rows.** Edit to the SUITE: delete a whole scan-row block and the floor must fire (`scripts/guard-vacuity-floor.test.sh`
checks the floor mechanically); change the `gh()` function to ignore its argv selectors and the epilogue must go RED.
Must-PASS non-canonical inputs: the stamped fixture with an extra unrelated step, shuffled step order and no precondition/apply
steps still `stamped` (R4 companion); a stamped run behind a refused-before-apply rotate (S7).

**Anchor.** The stored values are the lib's four name constants. They are compared to the workflow's literal names by the
parity test in the same repo, so one diff could edit both; what lives OUTSIDE the commit is what GitHub reports. Stamping
depends only on the marker name and the job name (row 4); the precondition/apply names only classify FAILED attempts, so a
drift there fails toward "attempt not seen" and can never reject a real stamp. The PR body records, when available, a read-only
`gh run view <id> --json jobs` of the newest `git_data_host_replace` run (names only). After merge the first real rotate's
marker is the live proof; nothing is dispatched here to obtain it.

**Mechanisms validated against the post-remediation tree.** The remediation writes a new step name and new constants; the
check "does the remediation's own text match the classifier" is run: the marker name must not match the census gate-name
pattern (P-c, P-h) and must not contain `confirm`; the lib's comments quoting the old `rotate confirm token` text are
exempt because every pin runs on comment-stripped text (and a lib/workflow comment cannot satisfy a pin).

## Test Scenarios

- Given a plain replace run, when the gate classifies it, then `skip` and the scan continues (never a stamp).
- Given a plan-only rotate, then `skip`; given a legacy rotate success without the marker, then `skip` too (a stamp needs the marker).
- Given a real rotate, then `stamped`, and `d6 rotate stamp: run <id>` is printed.
- Given the newest rotate attempt failed and an older stamped rotate exists, then `d6_last_rotate_failed` for the newest.
- Given `gh run view` fails for the newest run, then `d6_run_unreadable` and no older run is consulted.

## Risks and Sharp Edges

- A plan whose `## User-Brand Impact` section is empty or placeholder fails `deepen-plan` Phase 4.6; this one is filled.
- The apply step name uses an em dash; the constants and the parity pin must carry the exact byte sequence. The lib test file
  and the TS test must be saved as UTF-8; a mutation row flips one character of each constant.
- Pre-#10155 runs name their apply step differently, so a FAILED one reads `skip` (a legacy SUCCESS reads `skip` for lack of a marker). This is intentional and harmless: no
  stamp can predate the marker, so there is nothing for an unclassifiable older failure to mask. Do not "fix" it by adding
  the legacy name.
- A queued run with no jobs yet cannot be attributed to a target, so the scan treats it as in flight (blocks, transiently)
  rather than skipping to an older stamp; a COMPLETED run with no jobs (startup failure) is skipped.
- A re-run (`run_attempt` > 1) lists the latest attempt's job/steps; the classifier reads exactly that. A failed post-job step
  (e.g. checkout post-step) after a green marker turns the job `failure`, so the run reads `rotate_failed`: closed, conservative.
- The 100-run window (raised from 40; the scan stops at the first stamp, so the cost is paid only by long unstamped tails):
  a stamp older than the 100 newest dispatch runs reads `d6_replace_stale`, whose remedy names the window.
- A step rename makes older failed rotates invisible to the classifier (any rename, not only pre-#10155); the constants and P-g
  keep future renames loud.
- `|| true` on the `git_data_d6_scan` capture is deliberate; P-e pins the captured list, the `case` and its fail-closed `*)` arm.
- The suite's `MIN_ASSERTIONS` must be set from the final measured run (`scripts/guard-vacuity-floor.test.sh` checks it mechanically); the repo-global
  ratchets (guard-vacuity ledger, discoverability counts) may move and are left to CI.
- No operator step, no dispatch, no Doppler write anywhere in this plan; the rotate re-dispatch belongs to #10138.

## Review Amendments (2026-10-13, 12-seat panel)

- A failed rotate recorded under a drifted apply-step name, or with the apply step listed but never concluded,
  now reads `rotate_failed` (an explicit `skipped` apply is the only skip): the pre-#10155 run 38140050880 shape.
- A not-completed run that lists no `git_data_host_replace` job is `in flight`, not skipped; a non-numeric id never
  reaches gh; the gate sanitises the run id it echoes and its remedies now name the commands and the exits.
- Pins added: no job-level `name:`, no `continue-on-error` on any step of the job, no marker-named step or
  same-named job elsewhere, the census gate-name regex mirrored, and the gate's d6 block is EXECUTED against a
  modelled `gh` (case-arm bodies, `--event`/`--limit`/field order, post-scan reassignment).
- Accepted residuals, recorded in the runbook: operator re-run of a rotate run overwrites its failed attempt's
  record; the 100-run window counts every target; a deleted run record unmasks an older stamp; the stamp does not
  attest escrow state. `--limit` was not raised (worst case is already 101 sequential calls).
