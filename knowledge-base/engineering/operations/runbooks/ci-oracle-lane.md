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
manifest), `scripts/ci-oracle-lane.test.sh` (the sentinel)

## What the lane is

A repair diff that touches only oracle data — `scripts/ci-pr-affected-audit.accept.tsv`,
`scripts/ci-pr-affected-audit.baseline.tsv`, the `AFFECTED_*_PATHS` edge arrays inside
`scripts/lib/test-affected-paths.sh`, plus documentation (`knowledge-base/**/*.md`, root `*.md`) —
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
| **locked-telemetry** | `CI_ORACLE_LANE=on` AND `readonly ORACLE_LANE_LOCKED=1` in the driver | the job runs and classifies; `active` is NEVER `true`; each oracle-classified run emits a `SOLEUR_ORACLE_LANE … would_skip=<five legs>` notice instead of skipping — this stream is the blocking pre-activation audit evidence |
| **active** | `CI_ORACLE_LANE=on` AND the lock literal removed by a separate authorized PR | the five legs in `skip_legs` skip on `pull_request`/`merge_group`, tolerated by the `test` aggregator's `ORACLE-ONLY-SKIP` arm; `shard-totality-mutations` skips; `oracle-index-check` runs the manifest |

A non-empty value that is not exactly `on` (`off`, `ON`, `on ` with whitespace) is NONE of these: the job runs
but the driver stops at `reason=switch_off` with `switch=invalid` — telemetry for a mistyped value, never an off
switch. To turn the lever off, DELETE the variable.

## Reading the `SOLEUR_ORACLE_LANE` notice

One `::notice title=ci-oracle-lane::` line per executed job, also in the step summary. Fields, in order:

| Field | Values |
|---|---|
| `event` | `pull_request`, `merge_group`, or whatever `github.event_name` carried |
| `switch` | `unset` (empty), `invalid` (non-empty, not `on`), `on` |
| `locked` | `true` while `ORACLE_LANE_LOCKED=1` stands in the driver |
| `attempt` | `github.run_attempt`; only `1` can ever reach `oracle` |
| `files` | changed-path count the classifier parsed (0 on early exits) |
| `reason` | the verdict token — enum below |
| `oracle_only` | `true` iff every changed path is in the surface |
| `would_skip` | `none`, or the five-leg list while locked (the audit datum) |
| `active` | `true` only when oracle_only AND `on` AND unlocked — never while locked |

`reason=` enum (`oracle` is the only lane verdict; everything else is a fail-closed full battery):

- `oracle` — classified oracle-only; read `would_skip`/`active` for what happened next.
- `not_lane_event` — event is not `pull_request`/`merge_group`.
- `bad_merge_shape` / `bad_mg_shape` — the pull_request merge-ref two-parent shape or the merge_group payload
  SHAs failed validation.
- `fork` — pull_request head is a fork.
- `rerun` — attempt > 1 (a re-run always runs full).
- `switch_off` — `SWITCH` was not exactly `on` (check `switch=` for the value class).
- `diff_error`, `empty_diff`, `malformed_diff`, `too_many_files` — the diff listing could not be produced or
  parsed safely (>500 files is `too_many_files`).
- `non_oracle_status`, `non_oracle_mode`, `odd_path` — a changed entry carried a status outside M/A/D, a mode
  outside {000000,100644,100755}, or a non-printable/`::`/`,`-containing path.
- `excluded` — a committed exclusion-list path (`scripts/ci-pr-affected-replay.py`, `scripts/test-all.sh`,
  `plugins/soleur/scripts/lint-ratchet.py`, `.github/workflows/ci.yml`, other `scripts/lib/**`).
- `outside_surface` — a path outside the surface.
- `extent_parse` / `extent_miss` — the `AFFECTED_*_PATHS` extent walk failed on a base/head image, or a
  `test-affected-paths.sh` hunk line fell outside extents.
- `signalled` / `lever_error` — the EXIT-trap exits (HUP/INT/TERM, or an internal abort); both exit 0 with the
  fail-closed defaults. No notice at all on a job that did not conclude `skipped` means the classifier died
  before emitting (SIGKILL, runner loss) — that absence is itself the failure signal.

## When `oracle-index-check` fails

The leg runs every non-comment line of `scripts/ci-oracle-lane-suites.txt` serially and propagates the first
non-zero exit. On a PR or queue entry its failure is inside the required `test` aggregator and blocks merge.

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

1. **Arm the telemetry** (authorized): `gh variable set CI_ORACLE_LANE=on --repo jikig-ai/soleur`. Verify:
   `gh api repos/jikig-ai/soleur/actions/variables/CI_ORACLE_LANE` returns the variable with `"value": "on"`
   (404, 401 and 403 all exit 1 — call the variable absent only when stderr says `HTTP 404`; also check
   `gh api --paginate repos/jikig-ai/soleur/actions/organization-variables --jq '.variables[].name'` for an org
   variable that resolves through `vars`). The NEXT `pull_request`/`merge_group` run executes `oracle-selection`
   and the notice stream begins; nothing skips while `locked=true`.
2. **Observe at least one real oracle-repair merge.** On the #10865 observation window, audit the dark run's
   `SOLEUR_ORACLE_LANE` notice against the diff it classified: `oracle_only=true` with the five-leg `would_skip`
   on a genuinely oracle-only diff is the evidence; `reason=` on the non-oracle runs should be the surface/guard
   tokens, never `oracle`. A wrong classification is a stop — do not proceed.
3. **Authorized activation PR**: remove the `readonly ORACLE_LANE_LOCKED=1` line from
   `scripts/ci-oracle-lane.sh` (the comment marks it `ACTIVATION LOCK`), run
   `bash scripts/ci-oracle-lane.test.sh`, and attach the audit evidence from step 2 to #10865. First live run
   canary: watch the first `pull_request` run that goes `active=true` — the `test` aggregator should print
   `ORACLE-ONLY-SKIP` lines naming exactly the legs the notice put in `would_skip`, and `oracle-index-check`
   must be `success`. If either fails, roll back immediately.
4. The activation PR appends its own dated line under `### Stage status` in ADR-276 (append-only convention).

## Rollback

```bash
gh variable delete CI_ORACLE_LANE --repo jikig-ai/soleur
```

New runs skip the `oracle-selection` job at zero runner cost and every leg runs — fail closed by construction.
A run whose `oracle-selection` already completed keeps its cached outputs; "Re-run all jobs" re-executes the
driver at `run_attempt` 2, which the attempt guard turns into a full run. Structural rollback is a revert of the
PR, which also removes the job, the leg `if:` conjuncts, the tolerance arm, the six-leg proof term, the manifest
and the sentinel registrations.

## After any driver edit: the sentinel

`scripts/ci-oracle-lane.sh` and `scripts/ci-pr-selection.sh` carry parallel merge-ref/diff plumbing that can
drift (ruling T5) — a fix to one is consciously ported to the other, never assumed to transfer. After ANY edit
to the driver, the manifest, the leg `if:` conjuncts, the aggregator arm or the push-dedupe proof:

```bash
bash scripts/ci-oracle-lane.test.sh          # the lane sentinel: fixture diffs through the real driver,
                                             # output grammar, lock, surface/extent arms, manifest parity
bash plugins/soleur/test/ci-test-aggregator-diagnosis.test.sh   # the ORACLE-ONLY-SKIP arm over synthetic triples
bash scripts/ci-push-dedupe.test.sh          # the six-leg elide proof
```

The sentinel pins the leg-name set in BOTH directions: a new skippable leg must edit the driver's
`ORACLE_SKIP_SET` literal, the aggregator's five-name regex AND the push-dedupe proof in the same diff.
