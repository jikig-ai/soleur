---
category: ci
tags: [ci, oracle-lane, adr-276, activation, merge-queue, go-no-go]
date: 2026-11-05
---

# Oracle-only fast lane: dark phase, telemetry, activation and rollback

**Issues:** #12156 (the lever), #10865 (the observation window the activation audit is filed on)
**Decision record:** ADR-276, `## Amendment 2026-11-05 (oracle-only fast lane, #12156)` (rulings:
`knowledge-base/project/specs/feat-one-shot-12156-oracle-fast-lane/decision-challenges.md`, T1–T6 + O1/O2)
**Tooling:** `scripts/ci-oracle-lane.sh` (the driver), `scripts/ci-oracle-lane-suites.txt` (the validation
manifest), `scripts/ci-oracle-lane-legs.tsv` (the K=5 leg assignment), `scripts/ci-oracle-lane.test.sh` (the sentinel)

## What the lane is

A repair diff that touches only oracle data — the `AFFECTED_*_PATHS` edge arrays inside
`scripts/lib/test-affected-paths.sh` (in-extent hunks only), plus documentation
(`knowledge-base/**/*.md`, root `*.md`; the audit accept-table member retired with S4, 2026-11-09) —
changes no executable path, so the full battery proves nothing about it. The `oracle-selection` job in
`.github/workflows/ci.yml` classifies a `pull_request` or `merge_group` diff once per run; when EVERY changed
path is inside that surface the five heavy `test` legs (`test-webplat`, `test-bun`, `test-scripts`,
`test-scripts-heavy`, `web-platform-build`) may skip, `shard-totality-mutations` skips with them, and the
`oracle-index-check` leg runs the committed manifest so the oracle's own edit stays gated. It is a cost lever
that fails in one direction only: every unknown — a fork head, a re-run, a code file in the diff, a merge_group
batch that mixes a code PR in, a malformed diff — yields the full battery.

## The three states

| State | Condition | Behaviour |
|---|---|---|
| **dark** | `CI_ORACLE_LANE` unset or empty | the `oracle-selection` job is SKIPPED — no runner, no checkout, zero cost; every leg runs; `oracle-index-check` prints `not-oracle-only` and exits 0 inside a minute |
| **locked-telemetry** | `CI_ORACLE_LANE=on` AND `ORACLE_LANE_LOCKED=1` in env (the driver's `O-LOCK-READ` re-lock — the committed `readonly` literal was removed by #12300; no `ci.yml` env wires it today, so reaching it is an excluded-path edit) | the job runs and classifies; `active` is NEVER `true`; each oracle-classified run emits a `SOLEUR_ORACLE_LANE … would_skip=<leg list>` notice instead of skipping — five legs normally, four when the diff touched `knowledge-base/engineering/architecture/diagrams/*` (`test-webplat` is retained: diagrams feed its surface) — this stream was the blocking pre-activation audit evidence (satisfied on #10865); post-unlock it is the re-lock/rollback telemetry stream |
| **active** | `CI_ORACLE_LANE=on` AND the lock literal removed by a separate authorized PR (#12300, merged 2026-11-08) | the five legs in `skip_legs` skip on `pull_request`/`merge_group`, tolerated by the `test` aggregator's `ORACLE-ONLY-SKIP` arm; `shard-totality-mutations` skips; `oracle-index-check` runs the manifest |

A non-empty value that is not exactly `on` (`off`, `ON`, `on ` with whitespace) is NONE of these: the job runs <!-- markdownlint-disable-line MD038 -->
but the driver stops at `reason=switch_off` with `switch=invalid` — telemetry for a mistyped value, never an off
switch. To turn the lever off, DELETE the variable.

## Reading the `SOLEUR_ORACLE_LANE` notice

One `::notice title=ci-oracle-lane::` line per executed job, also in the step summary. Fields, in order:

| Field | Values |
|---|---|
| `event` | `pull_request`, `merge_group`, or whatever `github.event_name` carried |
| `switch` | `on`, `invalid` (non-empty, not `on`); `unset` exists in the grammar but is unreachable in CI — the job only schedules while the variable is non-empty; `unreadable` only on the `no_base_driver` fallback (the base-sourced driver could not be produced, so the switch was never evaluated) |
| `locked` | `true` when `ORACLE_LANE_LOCKED=1` is in env (the committed `readonly` literal is gone since #12300); `na` only on the `no_base_driver` fallback (the base driver's lock state is unobservable when it cannot be read) |
| `attempt` | `github.run_attempt`; only `1` can ever reach `oracle` |
| `files` | changed-path count in the diff listing — set before the per-path loop, so a mid-loop `malformed_diff` abort still reports the total count (0 on pre-listing exits) |
| `reason` | the verdict token — enum below |
| `oracle_only` | `true` iff every changed path is in the surface |
| `would_skip` | `none`, or the leg list on any oracle-classified run — emitted while locked AND when `active=true` — five legs, or four when a diagrams path was in the diff (the audit datum) |
| `active` | `true` only when oracle_only AND `on` AND unlocked — never while locked |

`reason=` enum (`oracle` is the only lane verdict; everything else is a fail-closed full battery):

- `oracle` — classified oracle-only; read `would_skip`/`active` for what happened next.
- `not_lane_event` — event is not `pull_request`/`merge_group`.
- `bad_merge_shape` / `bad_mg_shape` — the pull_request merge-ref two-parent shape or the merge_group payload
  SHAs failed validation.
- `fork` — pull_request head is a fork.
- `rerun` — attempt > 1 (a re-run always runs full).
- `switch_off` — `SWITCH` was not exactly `on` (check `switch=` for the value class).
- `bad_base_ref` / `base_fetch` / `no_merge_base` — the pull_request live-base resolution (#12418) failed
  closed after the switch gate: `PR_BASE_REF` failed branch-name grammar (never a refspec), `git fetch origin
  refs/heads/<base.ref>` failed (deleted/renamed base branch, an unreachable remote, or an anonymous fetch on
  a private repo — fail-closed but inert), or the fetched base shares no merge-base with the PR head. Seen on
  base branches deleted between event and run; on a fork, `fork` fires first.
- `diff_error`, `empty_diff`, `malformed_diff`, `too_many_files` — the diff listing could not be produced or
  parsed safely (>500 files is `too_many_files`).
- `non_oracle_status`, `non_oracle_mode`, `odd_path` — a changed entry carried a status outside M/A/D, a mode
  outside {000000,100644,100755}, or a non-printable/`::`/`,`-containing path.
- `excluded` — a committed exclusion-list path (`scripts/test-all.sh`,
  `plugins/soleur/scripts/lint-ratchet.py`, `.github/workflows/ci.yml`, other `scripts/lib/**`, and the lane's own
  machinery: `scripts/ci-oracle-lane.sh`, `scripts/ci-oracle-lane.test.sh`, `scripts/ci-oracle-lane-suites.txt`,
  `scripts/ci-oracle-lane-legs.tsv`).
- `outside_surface` — a path outside the surface.
- `extent_parse` / `extent_miss` — the `AFFECTED_*_PATHS` extent walk failed on a base/head image, or a
  `test-affected-paths.sh` hunk line fell outside extents, was a non-data line (the element grammar rejects
  `$(`, backtick, `${`, unquoted members — the index is sourced bash), or the diff was binary.
- `no_base_driver` — emitted by the WORKFLOW STEP, not the driver: the classifier is sourced from the base image
  (`git show HEAD^1:`/`git show $MERGE_GROUP_BASE_SHA:` — a PR must not rewrite the oracle that judges it), and a
  base that lacks the file fails closed with the defaults. Seen on pre-#12156 trees and on this lane's own
  introduction PR.
- `signalled` / `lever_error` — the EXIT-trap exits (HUP/INT/TERM, or an internal abort); both exit 0 with the
  fail-closed defaults. No notice at all on a job that did not conclude `skipped` means the classifier died
  before emitting (SIGKILL, runner loss) — that absence is itself the failure signal — and a job that died AT
  the job level (checkout failure, runner loss, the 3-minute cap) shows as a red `oracle-selection` check
  beside a green `test` (measured canary shape: job-level `continue-on-error` still concludes `failure` in the
  jobs API). Empty outputs = full battery, so the red is advisory; the remediation is re-running the workflow,
  not reverting.

## When `oracle-index-check` fails

The job runs the manifest across K=5 parallel matrix legs (`oracle-index-check (k/5)`): each leg executes only
the `scripts/ci-oracle-lane-suites.txt` members its `scripts/ci-oracle-lane-legs.tsv` row assigns to `ORACLE_LEG`,
serially, and propagates the first non-zero exit. Leg assignment is committed data (ADR-240 shape);
`check_legs()` in the sentinel pins legs ≡ manifest parity bi-directionally — a member added to the manifest
without a legs row reds the sentinel, and fails the leg closed at runtime. On a PR or queue entry a leg failure
rolls up into the required `test` aggregator and blocks merge.

1. Read the `::error title=oracle-index-check::manifest suite <label> exited <rc>` annotation — the named label
   is the suite that reds. Re-run it locally with the argv on its manifest line (labels are enumerate-exact
   `run_suite`/SUITE_GLOB labels; `bash scripts/test-all.sh --enumerate` prints the registration set).
2. A genuine red is an oracle defect the lane correctly caught — repair it like any oracle repair; the lane is
   doing its job, not malfunctioning.
3. `manifest line for <label> carried no argv` or `manifest … carried no suites` — the manifest file is
   malformed or empty; a vacuous leg cannot gate an oracle edit and fails closed.
4. **Manifest parity red** (a new oracle-machinery registration that is neither a member nor an exclusion, or a
   member that is no longer a live registration — the sentinel pins manifest ≡ oracle-SUT set minus exclusions
   bi-directionally): either add the registration as a member line `<label><TAB><argv>`, or add it to the
   commented exclusion list in the same file WITH the reason it is out (the SUT is not the oracle/selector
   machinery, it is a known flake, it is adjacent machinery). One or the other, in the same diff — the sentinel
   rejects a silent escape in either direction.

## Activation (the authorized sequence)

Activation is operator row O2 — a separate, explicitly authorized step, never part of a PR that ships the
mechanism and never implied by this runbook existing. The dark-phase `would_skip` audit is BLOCKING evidence
(ruling T1), not advisory.

**Status 2026-11-08:** steps 1–3 were executed — telemetry armed, audit satisfied on #10865, activation PR
#12300 merged. The first live canary (run 42458135078) was CANCELLED: `oracle-index-check` ran its serial
manifest 29m53s and hit `timeout-minutes: 30` (5 of 15 suites completed, zero failures — the suites are too
slow for the bound, not broken). `CI_ORACLE_LANE` was deleted per the rollback rule, so the lane is dark
today. Re-activation is gated on #12393 (manifest must fit the bound); then re-arm per step 1 and re-run the
canary per step 3.

1. **Arm the telemetry** (authorized): `gh variable set CI_ORACLE_LANE --body on --repo jikig-ai/soleur` —
   the value goes via `--body`; an `=` in the positional is read as part of the variable name and 422s. Verify:
   `gh api repos/jikig-ai/soleur/actions/variables/CI_ORACLE_LANE` returns the variable with `"value": "on"`
   (404, 401 and 403 all exit 1 — call the variable absent only when stderr says `HTTP 404`; also check
   `gh api --paginate repos/jikig-ai/soleur/actions/organization-variables --jq '.variables[].name'` for an org
   variable that resolves through `vars`). The NEXT `pull_request`/`merge_group` run executes `oracle-selection`
   and the notice stream begins; nothing skips while `locked=true`.
2. **Observe at least one real oracle-repair merge.** On the #10865 observation window, audit the dark run's
   `SOLEUR_ORACLE_LANE` notice against the diff it classified: `oracle_only=true` with the `would_skip` leg list
   on a genuinely oracle-only diff is the evidence; `reason=` on the non-oracle runs should be the surface/guard
   tokens, never `oracle`. A wrong classification is a stop — do not proceed.

   Collecting the evidence: the notice lands in the raw job log — `gh run view <run-id> --log | grep
   SOLEUR_ORACLE_LANE` on the run that carried the repair merge (one notice per `oracle-selection` execution).
   The notice deliberately carries NO diff identity: `head_sha`/`base_sha` go to `GITHUB_OUTPUT` only, which is
   not retrievable post-hoc. Reconstruct the classified diff from the run payload — `pull_request`: the run's
   `head_sha` is the merge ref and its parents are base/head in a `fetch-depth: 0` clone (`git log --format=%P
   <sha> -1` → `p2` PR head); the classified diff is GitHub three-dot — `git fetch origin
   <base.ref>` then `git diff $(git merge-base <p2> FETCH_HEAD) <p2>` — neither endpoint is the merge
   ref itself (#12418); `merge_group`: the payload's `head_sha`/`base_sha`
   (`gh api repos/{owner}/{repo}/actions/runs/<id>` → `.head_sha`; the base is the batch's base commit). Then
   diff `base..head` and re-apply the surface check mentally — every path must be an in-extent
   `AFFECTED_*_PATHS` hunk or a doc path (the audit accept-table member retired with S4, 2026-11-09). The expected `would_skip` list is the FIVE legs, or the FOUR-leg
   variant (`test-webplat` retained) when the diff touched `knowledge-base/engineering/architecture/diagrams/*`
   — the diagrams carve-out, which keeps the web-platform leg because diagrams feed its surface.
3. **Authorized activation PR** (executed by #12300, merged 2026-11-08): remove the
   `readonly ORACLE_LANE_LOCKED=1` line from `scripts/ci-oracle-lane.sh` (the comment marks it
   `ACTIVATION LOCK`), run `bash scripts/ci-oracle-lane.test.sh`, and attach the audit evidence from step 2
   to #10865. First live run canary: watch the first `pull_request` run that goes `active=true` — the `test`
   aggregator should print `ORACLE-ONLY-SKIP` lines naming exactly the legs the notice put in `would_skip`,
   and `oracle-index-check` must be `success`. If either fails, roll back immediately. (The 2026-11-08
   canary failed the second condition — `oracle-index-check` cancelled at `timeout-minutes: 30`; rolled
   back per §Rollback.)
4. The activation PR appends its own dated line under `### Stage status` in ADR-276 (append-only convention).

## Rollback

```bash
gh variable delete CI_ORACLE_LANE --repo jikig-ai/soleur
```

New runs skip the `oracle-selection` job at zero runner cost and every leg runs — fail closed by construction.
A softer revert path is the `ORACLE_LANE_LOCKED=1` env re-lock (`O-LOCK-READ`): it restores locked-telemetry
without deleting the variable, but no `ci.yml` env wires it today so it requires an excluded-path edit.
A run whose `oracle-selection` already completed keeps its cached outputs; "Re-run all jobs" re-executes the
driver at `run_attempt` 2, which the attempt guard turns into a full run. Structural rollback is a revert of the
PR, which also removes the job, the leg `if:` conjuncts, the tolerance arm, the six-leg proof term, the manifest
and the sentinel registrations.

## After any driver edit: the sentinel

`scripts/ci-oracle-lane.sh` is the surviving consumer of the merge-ref/diff plumbing it once shared with
the S4 selector driver (retired 2026-11-09 — the ruling-T5 porting discipline applies to any
future classifier of the same shape).

**Ports landed (dated):** the #12418 three-dot diff-base fix was ported to `scripts/ci-pr-selection.sh` as
#12484 (2026-11-09; the selector was retired the same day) — the selector's `pull_request` diff became
`merge-base(HEAD^2, live base)..HEAD^2` with the same `bad_base_ref`/`base_fetch`/`no_merge_base` fail-closed
reasons and the same refs/heads/-pinned unconditional fetch, wired from
`PR_BASE_REF: ${{ github.event.pull_request.base.ref }}` in the pr-selection step env. One deliberate
ordering difference, per each driver's own doctrine: the oracle resolves the base after its
pre-classification switch gate; the selector resolved it after the cheap env gates (event, merge shape,
fork, re-run) and before the listing, because its stage 1 ran on every well-formed `pull_request` run.
A second deliberate divergence, same T5 doctrine, still OPEN against the surviving driver: the selector's
base fetch was wrapped in `timeout 30` (`GUARD:G2-BASE-FETCH`) while the oracle's fetch stays unguarded —
a bound still considered for back-port as a follow-up.

After ANY edit
to the driver, the manifest, the leg `if:` conjuncts, the aggregator arm or the push-dedupe proof:

```bash
bash scripts/ci-oracle-lane.test.sh          # the lane sentinel: fixture diffs through the real driver,
                                             # output grammar, lock, surface/extent arms, manifest parity
bash plugins/soleur/test/ci-test-aggregator-diagnosis.test.sh   # the ORACLE-ONLY-SKIP arm over synthetic triples
bash scripts/ci-push-dedupe.test.sh          # the six-leg elide proof
```

The sentinel pins the leg-name set in BOTH directions: a new skippable leg must edit the driver's
`ORACLE_SKIP_SET` literal, the aggregator's five-name regex AND the push-dedupe proof in the same diff.
