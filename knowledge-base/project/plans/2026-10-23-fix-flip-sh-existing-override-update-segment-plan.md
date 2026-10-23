---
title: "fix: flip.sh existing-override update payload omits feature_segment.segment"
type: fix
date: 2026-10-23
slug: flip-sh-existing-override-update-segment
branch: feat-one-shot-flip-sh-update-branch-segment
lane: single-domain
issue: none
closes: []
---

# fix: flip.sh existing-override update payload omits feature_segment.segment

## Overview

`plugins/soleur/skills/flag-set-role/scripts/flip.sh`, function `flip_segment_in_env`, builds two
version-POST bodies. The first-time path (create) sends `"feature_segment":{"segment":<id>}`. The
existing-override path (update) sends `"feature_segment":{"id":<fs_id>}` only, and Flagsmith rejects it:

```text
{"feature_states_to_update": [{"feature_segment": {"segment": ["This field is required."]}}]}
```

Observed live on 2026-10-23 while turning off the `new-sessions-paused` role-prd override (it exists in
both environments, so every role flip of a flag that already has an override takes the update path).
The call failed in the dev environment before any write: no Flagsmith or Doppler value changed. The
audit row (`audit_id` 23e96051-8928-4764-afd2-2bfe20e55974) was appended first (append-before-flip) and
therefore records a flip that never happened; the PR body must say so.

Fix: send both fields, `"feature_segment":{"id":<fs_id>,"segment":<segment_id>}`, which is the object
shape the same API returns on read (the `featurestates` stub in `plugins/soleur/test/operator-ack-guard.test.sh`
carries `{"id":555,"segment":101}`, and `read_segment_state` already reads `.feature_segment.segment`).

## Research Insights

**Premise validation.** The cited function and line exist on `origin/main`
(`git grep -n '"feature_segment"' origin/main -- plugins/soleur/skills/flag-set-role/scripts/flip.sh` returns
lines 319 and 322; 319 carries `segment`, 322 does not). No issue or PR is cited by number. No ADR
decides the payload shape (this is a bug in a call, not a mechanism choice).

**Call-site inventory (the property quantifies over every body that builds a `feature_segment`).**

| Site | File:anchor | Shape | Verdict |
|---|---|---|---|
| create branch | `flip.sh` `flip_segment_in_env` create arm | `{"segment":N}` | correct |
| update branch | `flip.sh` `flip_segment_in_env` update arm | `{"id":N}` | **the bug** |
| org membership / `provision_feature_segment` | calls `flip_segment_in_env ... true` | inherits the fix | covered by the one-line fix |
| `--detach-shared` | `detach_from_shared` | `segment_ids_to_delete_overrides:[N]`, empty create/update | different, valid shape; no change |
| flag-create | `plugins/soleur/skills/flag-create/scripts/create.sh` create body | `{"segment":N}` | correct (create only) |

**Property List.** (P1) A role flip on a flag that already has a segment override publishes the new
version instead of failing. (P2) A regression of that payload turns a test red before it reaches an
operator's terminal. (P3) The typed-yes TTY gate and append-before-flip order are unchanged.

**Cut List.** Nothing cut: the ask names one fix and one regression test. Not proposed: changing the
audit row (it is a WORM log; the correction is a note on the PR, not a mutation), a retry wrapper, or
a live-write probe in CI.

**Applicable learnings.** `test-failures/2026-08-19-my-stub-could-not-express-the-failure-so-the-fix-reverted-green.md`
(a stub that cannot return the bad answer lets the revert stay green: the new stub must REJECT an
update body without `segment` with the exact JSON above). `2026-05-29-append-before-flip-holds-for-every-mutation-not-just-the-obvious-one.md`
(keep the audit POST before the first version POST; assert the order).
`best-practices/2026-05-27-flagsmith-segment-rule-structure-verify-before-implementing.md` (verify payload
shape against the live API shape, here via the read-side object the live API returns).

**API verification (partial, stated honestly).** Flagsmith's published docs (checked 2026-10-23 via
Context7, `/flagsmith/flagsmith`, `docs/managing-flags/feature-versioning.md` and `updating-flags.md`)
confirm the `POST /environments/{env}/features/{feature}/versions/` endpoint family and that segment
overrides are keyed by segment id, but they do NOT publish the request schema for
`feature_states_to_update` items. The shape is therefore evidence-based, not doc-confirmed: the live
error text names `feature_segment.segment` as the required field, the create arm proves `segment` is
accepted inside `feature_segment`, and the read side (`featurestates`) returns `feature_segment` with
both `id` and `segment`, so sending the read-side object is the most defensible superset. Residual
risk: under v2 versioning the row id inside a new version may differ from the id returned by
`/feature-segments/`; if Flagsmith rejects the superset, the failure is again a fail-closed 400 with
no state change, and the next iteration drops `id`. No production write was made to test this; the
definitive proof is the first real post-merge operator run.

## Open Code-Review Overlap

One open scope-out touches a planned file: #8800 (census sandbox shares inodes with the live repo)
names `scripts/lib/test-affected-paths.sh`. **Acknowledge:** a different concern (a fixture write-through
hazard); this PR adds one declared-edge array to that file and does not touch the census.

## Files to Edit

- `plugins/soleur/skills/flag-set-role/scripts/flip.sh` — update arm of `flip_segment_in_env`: add `"segment":%d` next to `"id":%d` and pass `"$segment_id"`.
- `scripts/lib/test-affected-paths.sh` — declare the new suite's edge to `flip.sh` (same pattern as the `flag-detach-shared` entry, lines around 1375-1379). Unconditional: the suite guards `flip.sh`, so it must run whenever `flip.sh` changes.
- `scripts/suite-shard-legs.tsv` — add the new suite's shard line (same pattern as `flag-detach-shared.test.sh	5`). Unconditional; the work phase confirms the leg is one CI runs.

## Files to Create

- `plugins/soleur/test/flip-update-existing-override.test.sh` — copies the pty + `yes` driver from `flag-detach-shared.test.sh` (named in the file header; extract a shared helper only when a third `flip.sh` suite appears), takes a `FLIP` env override so a mutated copy can be tested, and uses a curl stub that serves an existing override row and REJECTS (HTTP 400, the live error JSON) an update body whose `feature_segment` lacks `segment`. The stub parses the body as JSON (python3), orders `featurestates` before `versions`, and serves `role-prd`/`role-dev` by name.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "include \"segment\":<segment_id> alongside \"id\" in the update payload" | Files to Edit: `flip.sh` update arm | mapped |
| 2 | "verify against the Flagsmith versions API docs or a read-only call that this id+segment shape is accepted; do not perform any production write" | Research Insights: API verification (docs checked; schema not published; shape evidence-based, residual risk stated) | partial — see Research Insights |
| 3 | "Add a regression test row in the existing flip.sh test suite" | Files to Create: new suite — a deliberate deviation from "existing" (ruled by CTO agent: keep separate because only a stub that can return the 400 makes a revert go red; the shared `operator-ack-guard` stub serves 200 to everything) | mapped (deviation disclosed in the PR body) |
| 4 | "Also check the other update/delete call sites in flip.sh (detach-shared, org membership) for the same missing-field shape" | Research Insights: call-site inventory table | mapped |
| 5 | "do NOT merge the PR; open it ready-for-review and stop for my explicit go-ahead" | Phase 3 (ship stops before merge) | mapped |
| 6 | "The PR body must note that a WORM audit row (audit_id 23e96051-8928-4764-afd2-2bfe20e55974) was appended before the failed write" | Phase 3 PR body | mapped |
| 7 | "Do not run flip.sh without --dry-run; the typed-yes production write stays with the operator" | Acceptance Criteria (no un-stubbed run) | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| `flip.sh` update arm edit | "include \"segment\":<segment_id> alongside \"id\" in the update payload" | asked |
| New test suite file | "Add a regression test row in the existing flip.sh test suite" | asked (as a regression test; the file placement is a disclosed deviation, see row 3) |
| `test-affected-paths.sh` declared edge | — | inferred — justification: without it the new suite is not selected when `flip.sh` changes, so the regression test would not run on the next edit of the file it guards |
| `suite-shard-legs.tsv` line | — | inferred — justification: the runner hash-falls-back for untabled suites, so this is conditional hygiene; skip if the manifest guard does not require it |

### Split Assessment

- Subsystems touched: 2 — `plugins/soleur`, `scripts`
- Planned files: 4 | Estimated changed lines: 140
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## User-Brand Impact

- **If this lands broken, the user experiences:** the operator's flag flip fails closed with a Flagsmith 400 and no state change (as on 2026-10-23); a worse regression would be a payload that Flagsmith accepts but applies to the wrong segment, which the stubbed test and the eval re-verify step catch.
- **If this leaks, the user's data / workflow is exposed via:** no new exposure vector; the edit changes a JSON body that carries no credentials, and the credential path (`doppler`, stdin config) is untouched.
- **Brand-survival threshold:** `none`
- **Threshold decision (challengeable):** the change is one JSON field in operator-only tooling that fails closed, with the typed-yes TTY gate and the audit-before-write order unchanged; the next tier up applies only to code that serves end-user requests.

threshold: none, reason: the touched path is operator tooling under plugins/soleur/skills that runs only from the operator's own terminal behind a typed-yes acknowledgement and never serves a user request.

## Observability

```yaml
liveness_signal:
  what:            each version POST prints "ok: <uuid>" per environment on stdout, then the role path re-reads state and ends with the "Done" line
  cadence:         per-run (operator-invoked, on demand)
  alert_target:    the operator's terminal running the typed-yes command
  configured_in:   plugins/soleur/skills/flag-set-role/scripts/flip.sh (flip_segment_in_env response check, exit 3)

error_reporting:
  destination:     stderr of flip.sh (Flagsmith error JSON), plus the WORM audit row in Supabase appended before the write
  fail_loud:       flip.sh prints the Flagsmith response JSON to stderr and exits 3; an unapplied flip is visible as the flag state unchanged in the dry-run matrix

failure_modes:
  - mode:          Flagsmith rejects the update body (missing field, as on 2026-10-23)
    detection:     exit 3 with the response JSON on stderr; the regression test fails if the body drops segment
    alert_route:   operator terminal; CI red on the new suite
  - mode:          audit row appended but no write landed
    detection:     flip.sh --dry-run matrix still shows the old enablement; compare against the audit row id in the PR body
    alert_route:   operator (reconcile by re-running the same command after the fix)

logs:
  where:           operator terminal scrollback and the Supabase audit_flag_flip table
  retention:       audit table is WORM (indefinite); terminal output is not retained

discoverability_test:
  command:         grep -c 'feature_segment":{"id":%d,"segment":%d}' plugins/soleur/skills/flag-set-role/scripts/flip.sh
  expected_output: 1
```

## Guard Contract

### Guard 1 — update-payload shape regression test

**Property.** Every version-POST body that flip.sh builds for an already-existing segment override carries both the feature-segment id and the segment id, and a body without the segment id is rejected by the test's stub exactly as the live API rejects it.

**Assembly.** The chokepoint is `flip_segment_in_env` in `flip.sh`: both the role-flip path and the org-membership path (`provision_feature_segment`) reach the Flagsmith version POST only through it, and it runs once per environment (dev env id and prd env id). The test must therefore assert every captured update POST (both environments), not the first. The detach path builds its own body and is outside this property (it carries no `feature_segment`).

**Mutation matrix.** Each row is an edit to `flip.sh` or the stub that MUST turn the suite red; derived from the property, not from the finished code.

| # | Edit | Must go RED because |
|---|------|---------------------|
| 1 | remove `"segment":%d` from the update arm (restores the 2026-10-23 bug) | stub returns the live 400 JSON, flip.sh exits 3, the positive case fails |
| 2 | keep `segment` in the dev-env call but drop it for the prd-env call only (second member after a compliant first) | the suite asserts every update POST body, so the prd body fails |
| 3 | swap the values so `"segment"` receives the fs id and `"id"` the segment id | the stub checks `segment` equals the stubbed segment id (101) and `id` equals the stubbed row id (555) |
| 4 | make the update arm unreachable (`existing_fs_id` forced empty so the create arm runs) | the suite asserts at least one captured body contains `feature_states_to_update` with a non-empty array, so it reports the update arm never ran instead of passing vacuously |

Audit-before-write order is deliberately NOT a row here: this edit does not touch it and `audit-flag-flip.test.sh` already pins it (`assert_order`). Mutation runs are one-time PR evidence run through the suite's `FLIP` override on sed-mutated copies written next to the original (the script resolves repo-relative paths); they are not permanent suite content.

**Harness rows.** (H1) Edit the SUITE: make the stub accept every body (delete its validation) — the suite's own self-check row (a deliberately segment-less body POSTed directly to the stub must come back 400) goes RED, proving the stub can express the failure. (H2) Must-PASS input that is not the canonical: run the same flow with a different stubbed segment id and row id (e.g. segment 102, row 777) — the update body must carry those ids, so a fix that hard-codes the canonical numbers fails, and the contract's permitted variation (any ids) passes.

**Anchor.** No stored value is compared (no hash, manifest row or count floor); the guard asserts a live-shaped payload against a stub that encodes the API's required field, and the outside check is the first real post-merge operator run, which fails closed.

## Acceptance Criteria

- [ ] `flip.sh` update arm builds `"feature_segment":{"id":<fs_id>,"segment":<segment_id>}` and the create arm is unchanged.
- [ ] `plugins/soleur/test/flip-update-existing-override.test.sh` passes on the fixed script and fails (exit non-zero) on the pre-fix `flip.sh`, run through the suite's `FLIP` override against `git show origin/main:plugins/soleur/skills/flag-set-role/scripts/flip.sh` written to a sibling copy.
- [ ] The four mutation rows and two harness rows above each behave as stated (red/pass); a one-line summary of the one-time run goes in the PR body (not into the permanent suite).
- [ ] The suite asserts the captured update body is ONE valid JSON object (guards the extra `%d` / argument-count hazard) with `id` and `segment` equal to the stubbed row id and segment id, for EVERY captured update POST (dev and prd).
- [ ] The suite proves the stub is in force: `curl` and `doppler` resolve to the stub directory, tokens are fake, and a real network or secret binary being reached fails the suite (the pty run is the typed-yes path, so this is the dry-run-equivalent safeguard).
- [ ] The suite's stub 400 body reaches `flip.sh` through the real `fs_api` path and produces exit 3 on the pre-fix script (confirmed by the pre-fix run above, not assumed).
- [ ] `python3 scripts/lint-guard-contract.py` accepts this plan.
- [ ] Existing suites still pass: `flag-detach-shared.test.sh`, `flag-org-scoping-pr2.test.sh`, `audit-flag-flip.test.sh`, `flip-flag-map-parity.test.sh`, `operator-ack-guard.test.sh`, `flagsmith-stdin-config.test.sh`.
- [ ] No test or command in this PR runs `flip.sh` against the real Flagsmith or Doppler (stubbed PATH only); no production write.
- [ ] PR body carries a `## Changelog` section, `semver:patch`, and states: (a) audit row 23e96051-8928-4764-afd2-2bfe20e55974 was appended before the failed write and records a flip that never happened (no Flagsmith or Doppler change was made), and a successful rerun appends a second, later row; (b) the recovery line "if you see `feature_segment.segment: This field is required`, you are on a pre-fix checkout: pull main and rerun"; (c) one sentence on the new-suite-instead-of-existing deviation and why; (d) the partial API verification and residual risk.
- [ ] A follow-up issue is filed for the wider append-before-flip hazard (any 400/5xx/network failure leaves an orphan audit row; candidate fixes: outcome-update row, status column, append after confirmation), labelled per the repo's deferral convention with a re-evaluation criterion.
- [ ] PR is left open and un-merged for the operator's explicit go-ahead.

## Test Scenarios

1. Role flip, override exists in both envs: exit 0; two update POSTs (dev 90722, prd 90721), each one valid JSON object with `id` and `segment` equal to the stubbed ids.
2. Stub rejection self-check: POST a segment-less update body straight to the stub; it returns HTTP 400 with the live error JSON.
3. Different ids (H2): rerun scenario 1 with segment 102 and row 777; the bodies carry those ids.
4. First-time override (no existing row): the create arm still sends `{"segment":N}` (unchanged behaviour, one assertion; kept only if no existing suite already covers the create arm — work phase greps `flag-org-scoping-pr2.test.sh`, whose stub returns no row).

## Implementation Phases

1. **Red:** write the new suite and run it against the current `flip.sh`; confirm scenario 1 fails with the live 400 JSON.
2. **Green:** edit the update arm; run the new suite and the five neighbouring suites.
3. **Wire and ship:** add the declared edge and the shard line (both unconditional); run the mutation and harness rows once and record a one-line summary; file the append-before-flip follow-up issue; open the PR with the Changelog, audit-row note and recovery line, stop before merge. Compound records a durable learning about the orphan audit row (the correction must live next to the data's readers, not only in the PR body).

## Sharp Edges

- The existing `flag-detach-shared.test.sh` stub serves the detach verb only, and the shared `operator-ack-guard.test.sh` stub answers 200 to everything, so neither can return the live 400. A separate small suite keeps the failure axis (a stub that rejects) local; the CTO agent ruled this keeps maintenance acceptable (one copied pty driver, extract a helper at the third suite).
- Stub case order matters: in the detach stub `*"/versions/"*` precedes everything and would swallow `.../versions/<uuid>/featurestates/`. The new stub must match `featurestates` first.
- `%d` with a zero-padded id reads as octal (pre-existing, ids are plain integers); the extra `%d` makes the argument count `"$existing_fs_id" "$segment_id" "$enabled"` exactly, and a mismatch silently emits `0` or a doubled object, which is why the suite parses the body instead of grepping the format string.
- Do not run `flip.sh` without `--dry-run` outside the stubbed PATH; the real typed-yes flip stays with the operator.
- The audit row from the failed attempt cannot be removed or edited (WORM). The correction lives in the PR body and, if the operator wants, a comment on the cutover tracking issue.
- After merge the operator reruns the same flip command; a green run will append a second audit row, which is expected.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — operator tooling bug fix with a regression test.
