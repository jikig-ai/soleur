# Tasks — chore(infra): consumer probe HEADs the pinned manifest (#10004)

Plan: `knowledge-base/project/plans/2026-10-11-chore-zot-consumer-probe-head-pinned-manifest-plan.md`
Branch: `feat-one-shot-10004-probe-head-pinned-manifest` · Draft PR: #10041 · Deferral: #10044 (web pin)

## Phase 0 — Preconditions (read-only; again just before enqueue)

- 0.1 Rebase on `origin/main` (never merge main in); re-read `BASELINE_DECLARED_PROBES` after the rebase; do not push while a PR is queued.
- 0.2 `gh run list --status in_progress` / `--status queued`: no infra apply, host replace or `web-platform-release` run in flight.
- 0.3 No registry observation window open (recent registry replace, soak or follow-through trackers, settled applies).
- 0.4 Record baselines for the PR body (heartbeat state, canary counts, current marker rows for the bootstrap repo).
- 0.5 Re-run measurements M1-M5 against the pinned zot image (local, shortened retention delays); keep the output for the Prose ledger; remove the container and scratch files.

## Phase 1 — RED tests first (`apps/web-platform/infra/web-zot-consumer-probe.test.sh`)

- 1.1 Pin-override seam helper (`run_override_multi` gains a pin-override argument).
- 1.2 Mock registry: add `do_HEAD` for `/v2/known/second/manifests/sha256:<D>`, 404 for the evicted digest, 401 without auth, request log (method, path).
- 1.3 Rows P1-P10 and P12 (see the plan's Test Scenarios); stub-curl argv/stdin assertions with `grep -F` on files, never `producer | grep -q`.
- 1.4 Control-character rows (P11): newline, backslash and tab in `ZUSER`; tab in `ZTOK`; tab inside a list element; each proven able to FAIL.
- 1.5 Confirm the new rows are RED against the unmodified probe for the right reason.

## Phase 2 — Probe (`apps/web-platform/infra/web-zot-consumer-probe.sh`)

- 2.1 Element parsing: bare `repo` or `repo@sha256:<64 hex>` only; FATAL exit 1 on anything else before any request.
- 2.2 One request function (GET tags/list, `-I` for the manifest), same stdin config channel, `-m 10`, no `-f`, no `--retry`, `000000` normalization kept; update suite mutants (b), (c) and prove they land with `cmp -s`.
- 2.3 Shared classification function; pin results set the same `unservable` / `auth_broke` accumulators; verdicts `pinned`, `pin-missing`, `pin-forbidden`, `auth-broke`, `unreachable`, `wedged`, `unexpected`, plus `none` and `skipped`.
- 2.4 Skip the pin when `tags/list` was not 200; append `pin_code= pin_verdict=` after `ts=` in the marker row.
- 2.5 `SOLEUR_ZOT_PROBE_PIN_OVERRIDE` seam (positional; missing reads `000`).
- 2.6 Header comment (grammar, skip rule, worst case, why only web-1 carries a pin, evidence rows).

## Phase 3 — Wiring

- 3.1 `web-probe.tf`: `zot_probe_digest_inngest_bootstrap` (anchored `ZIREF="` regex, `[0]`) and `zot_probe_repo_pinned`; leave `zot_probe_repo` byte-unchanged. Write HCL with the Write/Edit tools.
- 3.2 `server.tf`: exactly two lines — the `triggers_replace` entry and the env-file `printf` argument of `terraform_data.zot_consumer_probe_install` become `local.zot_probe_repo_pinned`.
- 3.3 T7 extension in the probe suite (derived digest vs both `ZIREF` digests; bare list has no `@`; pinned join exact; writer rows name the right local; cloud-init line unchanged).

## Phase 4 — Records and prose (each sentence in the plan's Prose ledger, falsifying command run first)

- 4.1 `model.c4` edge description and comment; regenerate `model.likec4.json` via `scripts/regenerate-c4-model.sh`.
- 4.2 `betterstack-log-query.md`: heartbeat table row and the reading rule for `pin_verdict` / the pinned-manifest fault line.
- 4.3 `.github/workflows/build-inngest-bootstrap-image.yml`: one comment block and one step-summary sentence only.

## Phase 5 — Floors, baselines, discoverability

- 5.1 Raise `MIN_ASSERTS` to the new measured total (same edit as the rows); run `scripts/guard-vacuity-floor.test.sh`.
- 5.2 Run `plugins/soleur/test/fixture-relative-assert.test.sh`; regenerate the baseline only if the probe's row moved.
- 5.3 Bump `BASELINE_DECLARED_PROBES` by one (value re-read after the rebase) with a dated ledger comment; run that suite.

## Phase 6 — Mutation batteries

- 6.1 Guard 1 and Guard 2 matrices on sandbox copies, green control first, `cmp -s` per mutant; results table for the PR body.

## Phase 7 — Archive the Step-B leftovers

- 7.1 `archive-kb.sh --dry-run delete-zot-entry-gate` then without `--dry-run` (the plan); same for `one-shot-7258-delete-zot-entry-gate` (the spec directory).
- 7.2 `git status` shows staged renames and no untracked twins; commit with a pathspec as one `chore(archive-kb)` commit.

## Phase 8 — Local verification and ship

- 8.1 Plan AC16 in full (bounded output): shellcheck vs `origin/main`, the probe suite, `terraform fmt -check` / `validate`, the parity suites, the hook guard suites.
- 8.2 Mark PR #10041 ready only when verified; read the CI run created at ready; read the failing STEP before calling a red a regression; compare with `main`.
- 8.3 PR body: `Closes #10004`, measured evidence, Prose ledger, mutation results, apply-path table, web-gap statement (#10044), post-merge recipe, decision challenges.

## Phase 9 — Post-merge (agent-run, telemetry only)

- 9.1 `deploy-arm.sh find --wait <full-sha>` then `served`.
- 9.2 Read the push apply log for `zot_consumer_probe_install: Creation complete` (T0); the same merge also fires `apply-deploy-pipeline-fix.yml`, serialized by the shared concurrency group.
- 9.3 After two 30-minute buckets, read the marker rows and heartbeat state; post the result on #10004.
