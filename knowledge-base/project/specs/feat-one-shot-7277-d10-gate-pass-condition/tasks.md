# Tasks — D10 gate PASS condition (#7277)

Plan: `knowledge-base/project/plans/2026-08-05-fix-registry-luks-recut-d10-pass-condition-plan.md`
Lane: `cross-domain` (no spec.md existed; TR2 fail-closed default)
Brand-survival threshold: `single-user incident` → CPO sign-off before `/work`;
`user-impact-reviewer` + `observability-coverage-reviewer` + `platform-strategist` +
`silent-failure-hunter` at review.

**Do NOT dispatch the recut.** No `gh workflow run apply-web-platform-infra.yml` in any task.
**No `terraform apply`**, targeted or otherwise.

## Phase 0 — Preconditions (probe; pin every output into the PR)

- [x] 0.1 Capture `crane` stderr classification strings for `MANIFEST_UNKNOWN`, `NAME_UNKNOWN`,
      `UNAUTHORIZED`/`DENIED`, DNS failure. Reuse `reusable-release.yml`'s `install_crane()`
      (`CRANE_VERSION=v0.20.2`, `CRANE_SHA256=c14340087103ba9dadf61d45acd20675490fd0ccbd56ac7901fc1b502137f44b`,
      `sha256sum -c`). Do not `go install`.
- [ ] 0.2 Verify `GITHUB_TOKEN` + `packages: read` can `crane ls`/`crane digest` the required GHCR
      repos from a runner. Capability is NOT established by the workstation probe already recorded.
- [x] 0.3 Decide the signature mechanism by probe: copy `sha256-<digest>.sig` from GHCR vs re-sign
      keyless. Measure whether the repo's `cosign verify` invocation checks
      `critical.identity.docker-reference`. **No unsigned-restore arm.**
- [ ] 0.4 Throwaway-zot feasibility for the FULL pin set: record per-pass wall-clock and peak runner
      disk. Read the zot image through `local.zot_image`'s arch ternary, not `zot_image_amd64`.
- [x] 0.5 Re-confirm `/health` field names; derive the URL from `APP_DOMAIN_BASE`; send
      `Cache-Control: no-cache`; plan to assert both `version` and `build_sha`.
- [x] 0.6 Capture A5's outcome-classification strings: credential-rejected vs availability-failure.
      Measured, never guessed — this boundary is the abort/degrade line.
- [x] 0.7 A4 wiring: `zot_mirror_verdict` makes **zero** network calls — it grades a JSON file
      `check-cloudflare-token-drift.sh --json-file` must produce first. Confirm the detector's
      invocation, capture rc **and** the JSON, then grade. Skipping the detector yields `unmeasured`
      → degrade, i.e. a predicate that can never abort. Do not `set -euo pipefail` when sourcing.
- [x] 0.9 Probe `crane validate --remote` against the throwaway. If it does not work over plain-HTTP
      loopback, A2 has no blob-completeness verifier — pick and record a fallback before Phase 2.
- [x] 0.8 Re-derive the next-free ADR ordinal against freshly-fetched `origin/main` (plan-time
      value `ADR-169` is provisional).

## Phase 1 — Restore engine (test first)

- [x] 1.1 RED: write `tests/scripts/test-registry-restore-from-ghcr.sh`, self-contained, argv-
      dispatching stubs. Cover every exit code (0/2/3/4/5/6), the idempotent second pass, and the
      `--rehearse`-differs-only-in-the-tlog-flag assertion.
- [x] 1.2 GREEN: write `scripts/registry-restore-from-ghcr.sh`. Intrinsic verification via
      `crane validate --remote`. Lift the digest-through-a-file read, the `sha256:` filter and the
      `tr '\n' ' '` injection guard from `build-inngest-bootstrap-image.yml`; cite it.
- [x] 1.3 Register the suite in `scripts/test-all.sh` next to the existing D10 entry.
- [x] 1.4 Register the script in `apps/web-platform/infra/inngest-bootstrap-mirror-only.test.sh`'s
      `CRANE_SHA256` pin-parity list.

## Phase 2 — Rewrite the gate

- [x] 2.1 RED: rewrite `tests/scripts/test-registry-pull-path-health.sh`. **Start with the green
      row** (`rc == 0` on the all-good fixture) — the criterion whose absence let an unpassable gate
      ship. Then one positive control per abort class (10), plus A5's asymmetry in both directions.
      Remove the `${#WATCHED[@]} != 3` grep and the 4-arg stubs with the array they pin. Carry
      forward the comments-stripped `::add-mask::` structural assertion.
- [x] 2.2 GREEN: rewrite `scripts/registry-pull-path-health.sh` in place. Implement A0–A5. Drop the
      Sentry arm entirely (counters AND denominator). Keep fail-closed + the `GITHUB_ACTIONS` mask
      guard. Test seams per external dependency, each able to emit `UNKNOWN`.
- [x] 2.3 Verify the self-reference trap: the literal phrase "no valid PASS condition" must appear
      **nowhere** in the file, including historical commentary.

## Phase 3 — Wire into the dispatch

- [x] 3.1 Job-level `permissions:` (`packages: read`, plus `id-token: write` if 0.3 selects
      re-signing). Wire `DOPPLER_TOKEN_PRD` — referenced zero times in this workflow today.
- [x] 3.2 Split into an **unconditional PREPARE** step (crane install, inventory derivation, pinned
      manifest artifact) and a **conditional VERDICT** step keeping
      `if: steps.posture.outputs.probe_result != 'absent'`. Rewrite the skip's stated reason.
- [x] 3.3 Add a pre-rehearsal stock-availability probe so a dispatch that cannot proceed does not
      first move multiple GB.
- [x] 3.4 Add the **separate `needs:`-chained restore job** (no `continue-on-error`, explicit `if:`
      covering the resume arm, bounded retry on exit 3 for tunnel re-convergence, per-code
      `::error::`). `registry_luks_recut`'s `timeout-minutes: 30` stays unchanged.
- [x] 3.5 Correct all four stale `ghcr-fallback` sites; make the Dispatch summary conditional on the
      restore job's outcome; retain a truthful manual exit (not `bump_type=patch`).
- [x] 3.6 `actionlint` clean; `bash -c` extraction on every edited `run:` block (never `bash -n` on
      the YAML).

## Phase 4 — Records

- [x] 4.1 New ADR at the Phase-0.8 ordinal: the four candidates and the three rejections; the
      independence criterion; the fail-open analysis per predicate; why rehearsing against prod zot
      was rejected; the `IMAGE_VERIFY_MODE=warn` dependency; the falsifiable causal hypothesis
      ("if zot crash-loops again on an empty store, the store-corruption hypothesis is refuted and
      the recut is not the lever"); the chained restore as a behaviour expansion of a prod workflow.
- [x] 4.2 ADR-096 in-place amendment: new authorization condition; strike the escrow rationale
      (content-anchored, no orphaned tail, **conclusion not repaired**); amend the COLD VEHICLE
      paragraph; clause (g) stays open.
- [x] 4.3 Runbook rewrite: delete the ⛔ banner; "What authorizes a recut"; failure table incl. one
      row per restore exit code and one for post-destroy restore failure; rewritten cold-vehicle
      check 1 + new live surfaces; empty-store window around the chained restore; stock-preflight
      caveat naming `registry-region-migrate` as unguarded.
- [x] 4.4 `model.c4` edits + `model.likec4.json` re-render (`likec4@1.50.0`);
      `plugins/soleur/test/c4-model-freshness.test.sh` green. Leave the `github -> ghcr`
      config-bundle edge alone.
- [x] 4.5 Add a note to #6946 recording that #7277 tightened the recut while the bypass stayed open.
- [x] 4.6 File the tracker for the dark `ghcr-fallback` emitter + Sentry rule (#7248 sibling class),
      including `scheduled-zot-restart-loop.yml`'s auto-filed issue bodies.

## Phase 5b — Blockers closed in the second /work session

The four-agent review found the gate **could not pass** (nothing authenticated crane). That was
fixed at hand-off; these are the blockers that remained.

- [x] B1 **A5 deleted.** Was fail-closed and UNWIRED, so the gate refused on every dispatch.
      Routed to `soleur:engineering:cto` as an architectural fork rather than picked inline; the
      ruling was DELETE, on three independent grounds (dual of the independence criterion;
      undecidable on the CF-tunnel transport per #7242/ADR-166; the transport is fail-closed).
      Swept from the script, both suites, the runbook, ADR-169 and the plan. **R2 is reversed, and
      recorded as a reversal** (review row R16) — not edited to pretend it did not happen.
- [x] B2 **Rehearsal split out of the mutex-holding job** into `registry_pull_path_gate`, which
      `registry_luks_recut` now `needs:`. The recut's `timeout-minutes: 30` is derived from D11's
      630 s bound and only survives that derivation because the unmeasured multi-GB rehearsal is
      no longer inside it. Recorded honestly: the concurrency group is workflow-level, so no mutex
      was released — worst case is now the SUM across three jobs.
- [x] B3 **Resolved BY the split, not by a hoist.** Hoisting `init`/`plan` was rejected: it widens
      the plan→apply gap by the rehearsal's duration against a lock-less R2 backend, and puts
      state access in a job with no destroy authority. (Review row R17.)
- [x] B4 **The "not published (measured)" claim: conclusion right, evidence invalid.** The cited
      `crane ls NAME_UNKNOWN` was uncredentialed and hit the tags API — it cannot separate absent
      from not-visible. Re-measured with a positive control: the producing workflow has NEVER been
      dispatched and the Terraform pointer secret does not exist. So the entry stays `conditional`
      and FLOOR stays **4** — the opposite of the promotion the blocker anticipated. Corrected in
      THREE sites (the gate script carried the claim too, which the blocker did not name).
- [x] B5 **Manifest divergence closed structurally.** The upload now runs AFTER the VERDICT, so the
      artifact the restore consumes IS the inventory the rehearsal proved; `manifest_sha256=` is
      emitted on both verdict lines as the cross-check, and the ordering is pinned by a test.

### Found while doing the above (not on the blocker list)

- [x] **A live fail-open in `last_err`.** It bounded the last 400 **bytes** while `classify()` and
      every comment claimed the last **line** — and `classify()` substring-matches, so its first
      case arm won over the whole capture. On a conditional pin that turned a credential rejection
      into a silent declared skip. Fixed in both scripts. Only the mutation battery could find it:
      every real crane message is under 400 bytes, so byte-tail and line-tail are indistinguishable
      on every existing fixture.
- [x] **A pre-existing RED.** `plugins/soleur/test/terraform-target-parity.test.ts` had been 2/103
      failing for the life of the branch — the step-order SAFETY property for the job that destroys
      the sole pull path — because a step rename left its needle stale. This is the concrete cost of
      the VOID exit-gate run. Now green and strengthened to span both jobs.
- [x] **The mutation battery is a committed, registered suite**, not ad-hoc shell in a transcript.
      Its first committed run found **15 of 44** mutations surviving. All closed but one, which is
      unreachable by construction and recorded through `expect_survive` with its reachability proof
      — and which fails in BOTH directions, so the exemption cannot outlive its justification.

## Phase 5 — Exit gate

- [ ] 5.1 `bash scripts/test-all.sh scripts` green.
- [ ] 5.2 Walk every acceptance criterion; record the command and its output.
- [ ] 5.3 Re-derive the ADR ordinal against freshly-fetched `origin/main` immediately before merge;
      on renumber, sweep plan + tasks + ADR body + script headers + runbook + workflow comments.
- [ ] 5.4 PR body: `Closes #7277`.

## Phase 0 residuals — deliberately NOT checked

- **0.2** runner `packages: read` — a workstation probe cannot establish runner capability
  (different principal, different scopes). Its failure mode is shown to be a SAFE ABORT rather
  than an unsafe pass: an insufficiently-scoped token yields `MANIFEST_UNKNOWN` → `NOTFOUND` →
  abort, which costs a dispatch, not a store. This is why A1's message says "absent **or not
  visible to this credential**".
- **0.4** full-pin-set wall-clock and peak runner disk — deliberately not measured locally. A
  workstation's transfer profile does not predict a GitHub-hosted runner's, so a local number
  would be false precision on the two figures that feed the job budget. What makes it survivable:
  the restore job has its own timeout and the engine is resumable. **No artifact states a numeric
  window duration**, per CPO sign-off condition 1.

Both are recorded as named residuals in `phase-0-probe-evidence.md` and ADR-169.
