# Tasks — #7242 zot mirror error must consume the in-job token verification

Plan: `knowledge-base/project/plans/2026-08-03-fix-zot-mirror-error-must-consume-in-job-token-verification-plan.md`
Branch: `feat-one-shot-7242-zot-mirror-error-misdiagnosis`
Lane: `cross-domain` (no spec.md present — defaulted fail-closed per TR2)

> **Phase order is load-bearing.** Phase 2 changes a contract (the verdict) that Phase 3 consumes.
> Building the consumer first produces dead code and vacuous tests.

## Phase 0 — Preconditions (verify before writing code)

- [x] 0.1 Re-derive the ADR ordinal against freshly-fetched `origin/main` (`ADR-165` was highest at plan time). If it moves, sweep `plans/`, `specs/`, and every AC naming it.
- [x] 0.2 Confirm a composite action under `.github/actions/` can `source "$GITHUB_WORKSPACE/scripts/…"` (precedent: `scheduled-inngest-health.yml`). This gates the A3d shared-helper design.
- [x] 0.3 Confirm `BETTERSTACK_QUERY_{HOST,USERNAME,PASSWORD}` reach the release job (`web-platform-release.yml:95` declares `secrets: inherit`). This gates A2b.
- [x] 0.4 Re-read `check-cloudflare-token-drift.sh` `emit_json` field names (`dead`, `unverifiable`, `unverifiable_keys[].cause`) — A1 and the `unverifiable` arm depend on the exact keys.
- [x] 0.5 Confirm `scripts/lint-orphan-test-suites.sh` covers `scripts/*.test.sh` so the two new suites auto-register; otherwise add them to `scripts/test-all.sh`.
- [x] 0.6a **Outcome-disarm check (R4.1).** `|| rc=$?` makes a step's `outcome` = `success`. The mirror step gates on `BRIDGE_OUTCOME: steps.zot_bridge.outcome == 'failure'`. Confirm no change makes `zot_bridge` "succeed" on failure — that would silence `degraded()` entirely (#6416 defect class). `token_preflight` is safe; nothing gates on its outcome.
- [x] 0.6b Use `source "$GITHUB_WORKSPACE/scripts/zot-mirror-diagnosis.sh"` with `# shellcheck source=/dev/null` (R1). The library must NOT `set -euo pipefail` — it would leak `-e` into the caller (R2). Keep the helper call on ONE physical line if an AC greps for it.
- [x] 0.6c **Deliverable E enforcement decision (R3).** `lint-bot-statuses` is ADVISORY — absent from `required-checks.txt` AND the Terraform ruleset. Either promote the lint (both move as a pair) or state plainly it is advisory. Do not silently inherit a non-blocking gate.
- [x] 0.6 Read `scripts/followthroughs/zot-restart-plateau-6288.sh` exit contract (0 PASS / 1 FAIL / 2 TRANSIENT) before wiring Deliverable C.

## Phase 1 — File the deferred issues FIRST (they are the production blocker)

- [x] 1.1 File `action-required` issue: zot crash-loop recurrence of #6288 (~4/min, `oom_kills=0`, onset ~17:08 UTC 2026-08-03). Include the `zot_restarts` series.
- [x] 1.2 In that issue, record the one cheap next probe: does the container's exit status/stderr reach Better Stack? If yes the cause is a query away and needs no SSH.
- [x] 1.2b `scheduled-inngest-health.yml` shares the defect — **FIXED INLINE, not filed** (the CONCUR gate ruled the cost-of-filing threshold forced it and the proposed deferral target did not exist). Also: only SIX of the eight cited lines are issue-filing steps; `:354` is a read and `:377` dispatches a production restart, both deliberately untouched. See session-state deviation 2.
- [x] 1.3 File `action-required` issue: the zot health verdict is read-path only (`zot-liveness-heartbeat` single 60 s sample cannot see a 4/min loop; nothing probes the push path).

## Phase 2 — The verdict contract (RED → GREEN)

- [x] 2.1 Write failing tests first: rc/JSON → verdict for `live` / `stale` / `unverifiable` / `unmeasured`, including `dead=0, unverifiable>0 → unverifiable` (**the thesis assertion**) and unreadable-verdict-file → `unmeasured`.
- [x] 2.2 Rewrite `token_preflight` in `reusable-release.yml` to emit `verdict` + `checked_at`, derived from the `--json-file` JSON (`dead` / `unverifiable`), never from `rc` alone. Keep `|| rc=$?`.
- [x] 2.3 Verify the four-arm mapping green.

## Phase 3 — The shared diagnosis helper

- [x] 3.1 Write `scripts/zot-mirror-diagnosis.test.sh` first — four arms, direct function calls (Test Scenarios 7-10).
- [x] 3.2 Create `scripts/zot-mirror-diagnosis.sh`. **Signature is 4-arg** — `zot_mirror_diagnosis <verdict> <checked_at> <restart_summary> <cause>` — plus `zot_mirror_verdict` and `zot_mirror_cause_help`. (The 3-arg form in this line was the plan's estimate; the `cause` parameter is required by the `unverifiable` arm.)
  - [x] 3.2.1 `live`: cites `checked_at` + `access_hostname_for()`; no rotation headline; carries the restart series; plateau-gated re-run wording.
  - [x] 3.2.2 `stale`: the **corrected** remedy (not the falsified "branch configs inherit" clause).
  - [x] 3.2.3 `unverifiable`: surfaces the script's own `cause` + "Do NOT rotate".
  - [x] 3.2.4 `unmeasured`: unranked candidates + a base case when the settling probe is unavailable.
- [x] 3.3 Scope note in the `live` arm: it settles the Access credential only — never `ZOT_PUSH_*`.

## Phase 4 — Wire both message sites to the helper

- [x] 4.1 `reusable-release.yml` `degraded bridge` arm (~L1059) → call the helper.
- [x] 4.2 `cf-tunnel-registry-bridge/action.yml` `:188` (docker-login) → call the helper.
- [x] 4.3 Same action `:150` (listener timeout) → call the helper. **Third site; the first draft missed it.**
- [x] 4.4 Add the `token-verdict` input (`default: unmeasured`); pass `${{ steps.token_preflight.outputs.verdict || 'unmeasured' }}`. The `||` is load-bearing at both consumers.
- [x] 4.5 **Cross-consumer sweep (three callers).** `cf-tunnel-registry-bridge` is used by `reusable-release.yml`, `build-inngest-config-bundle.yml:125`, `build-inngest-bootstrap-image.yml:230`. The latter two have **no** preflight and would pin the `unmeasured` arm. Add the preflight to both (they already pass `DOPPLER_TOKEN_PRD`) or make `unmeasured` actionable standalone + record it in the input description. *(This exact miss is on record for this exact action — `specs/feat-one-shot-zot-mirror-fail-closed/decision-challenges.md:32`.)*
- [x] 4.6 Pass `TOKEN_VERDICT` via an `env:` mapping, not a `${{ }}` interpolation inside the run body (the latter bakes in as a literal and makes per-arm testing impossible). Default-expand under `set -u`.
- [x] 4.7 Thin T9 to "the block renders REAL helper output" (anchored on a literal only the helper emits, with a negative excluding the could-not-load fallback). The `SAFE_TO_RERUN` literals stay asserted via the existing UNPUBLISHED-DRAFT / Re-run-failed-jobs greps; **no separate "global" assertion was added** — those two literals already are the global assertion, since degraded() appends the suffix to every arm. ≥20 floor unmoved; T4/T5 unchanged.

## Phase 5 — Measure the origin hypothesis in-job (A2b)

- [x] 5.1 On the bridge-failure path only, query `SOLEUR_ZOT_DISK` via `scripts/betterstack-query.sh` and emit the `zot_restarts` series.
- [x] 5.2 Fail-soft: a query error prints "could not query" — never a claim about zot.
- [x] 5.3 Test Scenario 11.

## Phase 6 — Adjacent message-surface fixes

- [x] 6.1 `reusable-release.yml` — reword the ops-email "the one command that fixes it" promise; carry `verdict` into the body.
- [x] 6.2 `reusable-release.yml` — widen the `If disk-full:` telemetry pointer to registry-host health generally.
- [x] 6.3 `reusable-release.yml` — resolve the `SAFE_TO_RERUN` dispatch/no-dispatch self-contradiction.

## Phase 7 — Restore the alarm (Deliverable B2)

- [x] 7.1 Add `always() &&` to all seven issue-filing `if:` conditions in `scheduled-zot-restart-loop.yml` (L133, 169, 204, 241, 287, 322, 346).
- [x] 7.2 Harden the Sentry status at `:383` to require `exit_code == '1' && verdict == 'FIRE'`, so an abort emitting no verdict cannot check in green.
- [x] 7.3 Test Scenario 12: checker exits 1 (FIRE) → the FIRE issue step is not skipped.

## Phase 8 — The false causal claim (Deliverable B4)

- [x] 8.1 Add a named `RECENT_BOOT_S` constant to `zot-restart-loop-alarm.sh`.
- [x] 8.2 Gate the reboot claim on `uptime_s < RECENT_BOOT_S` or a `boot_id` change. **The `<2 samples → no claim` rule was replaced** by an undatable-boot arm: a point-in-time boot fact needs one row carrying `uptime_s`, not a trend, so a sample-count threshold was the wrong instrument. See session-state deviation 3.
- [x] 8.3 Add the test cases (Scenarios 13-14). N5/N15 need no edit — their needles do not change.

## Phase 9 — Docs (Deliverable D)

- [x] 9.1 `zot-registry-revert.md:128` — delete the "bad handshake = the EDGE rejected you, not an origin problem" sentence.
- [x] 9.2 `zot-registry-revert.md:76` — remove the `branch configs inherit it` clause (the detector calls it `FALSIFIED` at `:1049`).
- [x] 9.3 `zot-registry-revert.md:66` — replace "the single most likely explanation" with the preflight-verdict pointer.
- [x] 9.4 `model.c4:457` — **AMEND, do not delete.** It is a deliberate "#7071 cause class" record that stops #6416 being re-derived; deleting it re-opens that failure mode. Add the third case (route present, origin present-but-restarting). Run `c4-code-syntax.test.ts` + `c4-render.test.ts`.
- [x] 9.4b **Stale-comment obligation (R4.4):** `git grep -n '#6416\|#7071'` across `.github/`, `scripts/`, runbooks and `.c4`; update or delete what each explains. This is the direct ancestor of this issue.
- [x] 9.5 Sweep the two sibling sites carrying the same falsified claim: `cf-tunnel-registry-bridge/action.yml-9` (header) and `reusable-release.yml-1056` ("The MEASURED cause class is a CF Access service-token rotation…" — an unmeasured claim in a file already being edited).

## Phase 10 — Enforcement (Deliverable E)

- [x] 10.1 Create `scripts/lint-diagnosis-claims.sh` scanning `.github/workflows/` **and** `.github/actions/` for causal-claim phrases, requiring a measured-verdict reference or `# MEASURED-BY:`.
- [x] 10.2 Commit a `.highwater` baseline so it lands green and ratchets down. Copy the mechanism from `scripts/lint-trap-tempfile-ownership.py`: script-relative path, comment-tolerant parse, missing baseline = hard error (exit 2), blocking-upward / advisory-downward.
- [x] 10.2b **Anti-vacuity control arm (R4.2):** a fixture message that MUST trip the lint plus one that MUST NOT, and a `--census`-returns-non-zero assertion. A guard that restates the text it guards fails GREEN when the phrase list goes stale.
- [x] 10.3 Register in `scripts/test-all.sh` / the lint runner.

## Phase 11 — ADR + C4

- [x] 11.1 Write `ADR-166-*.md` with the ordinal from 0.1, scoped to *any* CI-emitted operator-facing message and naming `lint-diagnosis-claims.sh` as its enforcement.
- [x] 11.2 Record decisions (a)-(d) from the plan.
- [x] 11.3 Cite lineage — ADR-147 cl.4, ADR-154 §2, ADR-164 §2, ADR-126 §3, ADR-082/115 — and claim only the *generalization* to failure text on any job.
- [x] 11.4 Add an `AP-021` diagnostic-honesty row to `knowledge-base/engineering/architecture/principles-register.md` (AP-001…AP-020 have none).

## Phase 12 — Recovery wiring (Deliverable C)

- [x] 12.1 Wire the three blocked runs' re-run to `scripts/followthroughs/zot-restart-plateau-6288.sh` via `scheduled-followthrough-sweeper.yml` — **not** `/work`.
- [x] 12.2 Define the never-plateaus branch: escalate to the crash-loop issue; state that `allow_unmirrored_reason` publishes the draft but does not make the image pullable.

## Phase 13 — Exit gate

- [ ] 13.1 `bash scripts/test-all.sh` (the gate's own invocation — no hand-enumerated subset).
- [x] 13.2 `actionlint` on edited workflows only (`.github/actions/**` is not linted today).
- [x] 13.3 `--loglevel warn` verified present by grep at review time (1 occurrence). **NOT asserted by a committed test** — plan AC19 asked for "a real grep, not a wish", and a one-off grep is exactly the wish. Carried as a known gap rather than claimed as covered.
- [x] 13.4 `lint-orphan-test-suites.sh` clean.
- [x] 13.4b Syntax-gate the composite action: `python3 -c 'import yaml; yaml.safe_load(open(...))'` + `bash -n` on its extracted `run:` bodies (actionlint does not cover `.github/actions/**`).
- [x] 13.4c Mutation check: deleting each arm's distinguishing literal must red the suite.
- [ ] 13.5 Walk every AC 1-21; do **not** claim 20/21 as satisfied-by-merge.

> **Not acceptance criteria of this PR:** "the three drafts re-ran" and "production `build_sha`
> advanced". Both require the crash-loop to stop, which this PR does not fix. They are
> follow-throughs on the Phase 1.1 issue.
