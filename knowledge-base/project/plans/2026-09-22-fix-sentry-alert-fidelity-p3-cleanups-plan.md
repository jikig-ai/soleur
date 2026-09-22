---
title: "fix(sentry): live-fidelity probe P3 cleanups: managed rule that gains an excluded trigger, derived test counts, frozen generator note, op-contract comparison type"
type: fix
date: 2026-09-22
slug: fix-sentry-alert-fidelity-p3-cleanups
branch: feat-one-shot-sentry-fidelity-p3-cleanups
issue: none
closes: none
related: [7985, 8267, 8451, 8545]
priority: p3
domain: engineering
brand_survival_threshold: none
detail_level: MORE
---

# fix(sentry): live-fidelity probe P3 cleanups

## Enhancement Summary

**Deepened on:** 2026-09-22 · **Sections enhanced:** Research Reconciliation, Proposed Solution (a),
Observability, Guard Contract, Acceptance Criteria, plus a new "Deepen-Pass Evidence" section.

1. **A second defect found and folded in.** The census does not merely miss the gained rule; it
   *accepts* it. `$KNOWN` is built from every capture entry, so a managed rule that leaves scope is
   counted as a "registered Sentry default" and a rule dropped from Terraform while live passes
   silently with rc=0 (evidence E1/E2). The `$KNOWN` narrowing and row G4-28 are the response.
2. **The remedy wording was corrected against the provider's real behaviour.** "An apply would
   silently strip it" is only one of two outcomes; the create tripwire refuses the write once a
   refresh surfaces the legacy trigger, so the finding says "an apply is NOT a repair" and names both.
3. **AC3's assertion was narrowed to an anchor**, because the `$KNOWN` narrowing legitimately changes
   the tail of that message (E3).
4. **Every count, shape and citation in the plan is now measured** (E4-E6, E9), and the two
   consumers of the probe's output were checked for class parsing (E7).

### New considerations discovered

- The suite's 28 is a fixture constant; production declares 30 native rules plus 2 frozen. A reader
  who conflates them would mis-size the derivations in (b).
- The marker must avoid the substrings `DELETED`, `UNMANAGED`, `FROZEN`, because existing rows grep
  those negatively.
- No sibling precedent exists for this finding class (E8), so the chain ORDER is the review surface.

Four leftovers from the 2026-09 Sentry alert-API migration review, shipped as one small PR (draft #8576).
**This PR does not close #7985.** #7985 is the parent for the frozen rules and stays BLOCKED until the
provider release. This PR does not touch the two frozen rules (`auth_per_user_loop` 566671,
`sandbox_startup_failure` 669246). It does not change `def excluded` membership, and it does not change
`in_scope`/`tf_in_scope` semantics. No Terraform changes, so `plan_pr` should be a no-op.

## Overview

| # | Item | Files |
|---|---|---|
| a | A Terraform-managed native `sentry_alert` that gains an excluded trigger Sentry-side (e.g. Seer adding `seer_activity_trigger`) is misreported as `DELETED or RENAMED`, with an "an apply can recreate" remedy. That remedy is wrong. The census half also misfiles it by counting the rule as a "registered Sentry default". Add a distinct finding class. | `scripts/sentry-alert-live-fidelity.sh`, `tests/scripts/lib/sentry-alert-projection.jq` (comment only), `.github/workflows/scheduled-sentry-alert-drift.yml` (remedy bullet), `tests/scripts/test-sentry-alert-live-fidelity.sh` (new rows) |
| b | The fidelity suite hardcodes `length == 31` (F13) and `comparing 28` (F12). Derive both from the capture. | `tests/scripts/test-sentry-alert-live-fidelity.sh` |
| c | The one-shot generator's own `EXCLUDE` set predates `seer_activity_trigger`. Add a comment saying it is frozen to the 2026-09-04 capture. | `knowledge-base/project/specs/fix-7650-sentry-alert-migration/phase2-generate-alert-blocks.py` |
| d | The op-contract test's type cast declares `comparison` as an object only, but real entries also hold booleans and arrays. Widen the type and narrow it at the two use sites. | `apps/web-platform/test/sentry-zot-mirror-fallback-alert-op-contract.test.ts` |

## Research Reconciliation — Spec vs. Codebase

| Brief claim | Reality (measured 2026-09-22 on this branch) | Plan response |
|---|---|---|
| A managed rule that gains `seer_activity_trigger` is reported "DELETED or RENAMED" with an "apply fixes it" remedy. | **Confirmed.** Reproduced with the capture plus `seer_activity_trigger` appended to `byok-art-33-breach`: rc=1, one finding, `DELETED or RENAMED: 'byok-art-33-breach' … An apply can recreate a deleted rule`. The drift filer's bullet (`scheduled-sentry-alert-drift.yml`, "`DELETED or RENAMED` / `DRIFT` … Re-run `apply-sentry-infra.yml`") repeats that remedy. | Add a new finding class. See "Proposed Solution". |
| (implied) The census reports it too. | **Stale, and the reality is worse.** The frozen-rule pin's `$KNOWN` set is built from EVERY capture entry (`$CAP[] \| {id, name}`), which includes all 28 managed rules, not only the high-priority default the script's own comment describes. So the gained rule is accepted *silently*, and the count line claims `2 other excluded-type live workflow(s) are registered Sentry defaults` when only 1 is. | Narrow the capture half of `$KNOWN` to the capture's excluded-type, non-frozen entries, and check GAINED before KNOWN. |
| "An apply would PUT and silently strip the Seer trigger." | **Partly.** v0.15.7 reads an unmodeled trigger by TYPE into `legacy_trigger_conditions`, and any Create/Update re-sends it as `comparison: true` (`issue-alerts.tf`, the "WHY `ignore_changes = all`" block). `scripts/sentry-issue-alert-create-tripwire.sh` refuses any `sentry_alert` write whose `before`/`after` carries a legacy entry. The realistic outcome of "re-run apply" is therefore a refused apply, or a no-op that leaves the finding open. It is not a clean repair, and a write that got past the tripwire would corrupt or strip the trigger. | The remedy text says "an apply is NOT a repair", names both outcomes, and does not claim a single one. |
| "Line ~713 already derives a count." | Confirmed: `FROZEN_N=$(( $(jq 'length' "$CAPTURE") - N ))` plus a `.tf` grep for `FROZEN_TF_N`. | Hoist a `CAPTURE_N` derivation next to `N` and reuse it. |
| Python generator has an EXCLUDE set without `seer_activity_trigger`. | Confirmed: `EXCLUDE = {"event_unique_user_frequency_count", "new_high_priority_issue", "existing_high_priority_issue"}`, reading `phase2-live-workflows-capture-2026-09-04.json`. No test or parity check references it (`git grep` shows only `phase2-measurements-2026-09-04.md`). | Comment only. Do not sync the set. |
| `comparison` holds booleans/arrays. | Confirmed on the 09-09 capture: triggers carry `boolean` (`first_seen_event`, `reappeared_event`, `regression_event`, `new_/existing_high_priority_issue`) and `object`. The suite's Seer fixture and the live Seer default carry an array (`["pr_ready_for_review"]`). `tsconfig.json` includes `**/*.ts` under `strict`, so the test file is type-checked. | Use a union type plus a type guard at each of the two use sites. |

## Research Insights

**Premise validation.** #7985 is OPEN ("convert the 2 frozen legacy-trigger sentry_alert rules to native
triggers once the provider ships 0deba79"). This PR stays out of its scope. There is no tracking issue for
these four items, and draft PR #8576 is the vehicle. Every cited path exists on this branch. Baselines,
run before planning:

- `bash tests/scripts/test-sentry-alert-live-fidelity.sh` gives `59 passed, 0 failed`, wall 2m40s, with `EXPECTED_TESTS=59`.
- `vitest run test/sentry-zot-mirror-fallback-alert-op-contract.test.ts` gives 25 passed.

**Property List.**

- P1: A live workflow whose name is a Terraform-managed, in-scope `sentry_alert` and which carries an
  excluded trigger type gets its own finding. That finding says an apply is not a repair. It is never
  reported as `DELETED or RENAMED` and never counted as a registered Sentry default.
- P2: Vendor defaults (registry `vendor-default-workflows.json` plus the captured high-priority default,
  matched by id AND name) and the two frozen rules classify exactly as today. Every existing G4 row stays
  green unchanged.
- P3: The live and TF projection sides stay symmetric. `in_scope`, `tf_in_scope` and `def excluded` are
  byte-unchanged.
- P4: F12 and F13 derive their expected counts from the capture. No typed literals.
- P5: The generator's frozen EXCLUDE set is documented as frozen.
- P6: The op-contract test's capture type admits every `comparison` shape the capture and live API emit.

**Cut List.**

- "Narrow exclusion to all-conditions-excluded" (brief option 2) is cut. It would buy P1 only partially:
  the rule would re-enter scope and report `DRIFT … triggerConditions`, which the summary line and drift
  bullet also route to "repaired by an apply", so the wrong remedy stays. It also changes `in_scope` and
  `tf_in_scope` semantics, which P3 forbids. Today every excluded workflow in the capture is
  all-excluded (566201, 566671, 669246), so narrowing would not re-classify them, but the P1 remedy
  defect remains.
- Deriving managed names from the `.tf` (in addition to the reference keys) is cut. The daily job, which
  is the path that files issues, reads the committed reference, and those keys are exactly the managed
  in-scope names. In the apply job, a refresh that surfaces the trigger as legacy makes the tripwire
  refuse before the probe runs.

**Relevant files:**

- `scripts/sentry-alert-live-fidelity.sh`: the per-rule loop (`DELETED or RENAMED` `_finding`), the frozen-rule pin jq (`$KNOWN`, `$O`, `COUNT`, the `UNMANAGED-FROZEN` chain), and the final stderr summary line.
- `tests/scripts/lib/sentry-alert-projection.jq`: `def excluded`, `def in_scope`, `def tf_in_scope`. Comment only.
- `.github/workflows/scheduled-sentry-alert-drift.yml`: the "How to read them" bullets. The filer only keys on `live fidelity FAILED`, so no parser change is needed.
- `tests/scripts/test-sentry-alert-live-fidelity.sh`: F12 (`t_survivors_out_of_scope`), F13 (`t_live_api_shape`), the G4 block, the `_seer_live` helper, `EXPECTED_TESTS`.
- `apps/web-platform/infra/sentry/vendor-default-workflows.json`: one entry (1143693, Seer). Read-only here.

**Learnings applied:**

- `2026-08-13-every-guard-i-shipped-was-satisfiable-by-a-guard-that-asserts-nothing.md`: every new row asserts that its mutation landed, and asserts the negative, meaning the old wrong marker is absent.
- `2026-09-18-every-mechanism-was-validated-against-the-tree-before-its-own-backfill.md`: the new marker must not contain `DELETED`, `UNMANAGED` or `FROZEN` as substrings. Existing rows grep those negatively (G4-6 `! grep -q 'FROZEN\|UNMANAGED-FROZEN'`, G4-20 `! grep -q 'UNMANAGED'`).
- `cq-assert-anchor-not-bare-token`: rows grep the full `MARKER: '<name>'` anchor, not a bare token.

**CLAUDE.md / AGENTS.md conventions:** `hr-type-widening-cross-consumer-grep` applies to (d). The only
consumer of the `CAPTURE` type is the same file (a local `as` cast). `cq-test-fixtures-synthesized-only`
applies: the new fixtures are jq edits of the committed capture.

## Proposed Solution

### (a) New finding class: `MANAGED RULE GAINED EXCLUDED TRIGGER`

The marker is chosen so it contains none of `DELETED`, `UNMANAGED`, `FROZEN`.

1. **Per-rule loop.** A declared name can be absent from `live_proj` while a raw live workflow still
   carries that name. `project_live` keeps every in-scope workflow, so that live workflow must be out of
   scope, meaning it carries an excluded type. In that case do NOT emit `DELETED or RENAMED`; `continue`
   and let the frozen-rule pass classify it. Check against the raw `live_json`:
   `jq -e --arg n "$name" 'any(.[]; .name == $n)'`. Nothing else in the loop changes.
2. **Frozen-rule pin jq.** Pass the reference's names in with
   `--argjson refnames "$(jq -c 'keys' <<<"$ref_proj")"`. Inside the program:
   - `$INSCOPE` = names of `$live` workflows where `excl_type | not`.
   - `$GAINED` = members of `$O` whose `.name` is in `$refnames` and not in `$INSCOPE`. The second
     condition matters because a same-name excluded COPY of a healthy managed rule stays
     `UNMANAGED-FROZEN`, as today.
   - Order in the `$O` chain: empty-name, then DUPLICATE, then **GAINED**, then KNOWN (empty), then
     known-name-other-id, then else. Vendor-default names are not in `$refnames`, so they never reach the
     GAINED arm.
   - Finding text (one line):
     `FINDING MANAGED RULE GAINED EXCLUDED TRIGGER: '<name>' (id <id>) is a Terraform-managed sentry_alert and live Sentry now carries trigger type(s) <excluded types present> the provider cannot express, so it left the fidelity scope and nothing compares it. An apply is NOT a repair: provider v0.15.7 reads that trigger by type only (legacy_trigger_conditions) and any write re-sends it as comparison: true or drops it; scripts/sentry-issue-alert-create-tripwire.sh refuses such a write once a refresh surfaces it. Repair live state instead: PUT /api/0/organizations/<org>/workflows/<id>/ without that trigger, then GET it back — the rule returns to scope and is compared field-for-field. If the trigger is intended, the rule cannot stay a native sentry_alert: take it out of Terraform management in a reviewed PR.`
   - `COUNT` line: the third number counts `$O` members that are KNOWN **and not GAINED**, so a gained
     rule never inflates "registered Sentry defaults".
3. **Narrow `$KNOWN`'s capture half** to capture entries that are excluded-type and not frozen:
   `$CAP[] | select(excl_type and (.name as $n | $fz | index($n) | not))`. Today that is exactly
   {566201 "Send a notification for high priority issues"}, which is what the script's own comment block
   already says KNOWN is. The registry half is unchanged. Without this change, a managed rule later removed
   from Terraform while live still carries an excluded trigger would be silently KNOWN (row G4-28).
4. **Summary line** (final stderr): add `MANAGED RULE GAINED EXCLUDED TRIGGER is a managed rule that
   left scope; an apply will not repair it`.
5. **Header comment** in the probe's "FROZEN-RULE PIN" block: add a bullet for GAINED next to THE CENSUS.
6. **Projection jq, comment only.** Above `def in_scope`, note that ANY-match is deliberate and symmetric
   with `tf_in_scope`, and that the probe classifies a managed name found out of scope as
   `MANAGED RULE GAINED EXCLUDED TRIGGER` rather than widening scope. Do not touch the one-line
   `def excluded:`, because the probe greps it with `^def excluded: \[.*\];[[:space:]]*$`.
7. **Drift filer bullet** (`scheduled-sentry-alert-drift.yml`, "How to read them"): add one `printf`
   bullet for `MANAGED RULE GAINED EXCLUDED TRIGGER` with the same remedy. Leave the existing
   `DELETED or RENAMED` bullets unchanged.

### (b) Derived counts

Next to `N=$(jq 'length' "$REFERENCE")`, add:

```bash
CAPTURE_N=$(jq 'length' "$CAPTURE")
EXCL_DEF=$(grep -m1 -E '^def excluded: \[.*\];[[:space:]]*$' "$PROJ")
EXCL_CAPTURE_N=$(jq --argjson ex "$(jq -n -c "$EXCL_DEF excluded")" \
  '[.[] | select([.triggers.conditions[]?.type] as $t | any($ex[]; . as $e | $t | index($e)))] | length' "$CAPTURE")
```

Add a floor: `CAPTURE_N > N > 0`, `EXCL_CAPTURE_N > 0`, and `N == CAPTURE_N - EXCL_CAPTURE_N`. The last
one cross-checks the derivation: the projection's scope and the capture's excluded census must agree.
Otherwise exit 1 before any row runs.

- F13: `jq -e 'length == 31'` becomes `jq -e --argjson n "$CAPTURE_N" 'length == $n'`.
- F12: grep `comparing ${N} declared rule(s) against ${N} live in-scope rule(s)` with `grep -qF`. The label
  becomes `F12 scope is ${N} (= ${CAPTURE_N} captured − ${EXCL_CAPTURE_N} excluded-type) …`.
- Reuse `CAPTURE_N` in the `FROZEN_N` line (~713) instead of a second `jq length`.

### (c) Generator comment

Directly above `EXCLUDE = {…}`:

```python
# FROZEN to the 2026-09-04 capture (CAP above). This one-shot generator authored the Phase 2 blocks and is
# kept runnable only to re-diff against THAT capture. Its EXCLUDE set deliberately predates
# `seer_activity_trigger` (a Sentry-created default registered 2026-09-22, #8267) and is NOT kept in sync
# with `def excluded` in tests/scripts/lib/sentry-alert-projection.jq. Re-running it against a later
# capture requires reviewing this set first.
```

### (d) Widen `comparison`

```ts
type FrequencyComparison = { value: number; interval: string };
type TagComparison = { key: string; match: string; value: string };
// Live/capture `comparison` is polymorphic: `true` for lifecycle / high-priority triggers,
// an array for seer_activity_trigger, an object for frequency and tagged_event.
type Comparison = boolean | unknown[] | FrequencyComparison | TagComparison | Record<string, unknown>;
const isFrequency = (c: Comparison): c is FrequencyComparison =>
  typeof c === "object" && c !== null && !Array.isArray(c)
  && typeof (c as Record<string, unknown>).value === "number"
  && typeof (c as Record<string, unknown>).interval === "string";
const isTag = (c: Comparison): c is TagComparison => /* key/match/value all strings */;
```

- Both `conditions` arrays become `Array<{ type: string; comparison: Comparison }>`.
- The tag mapper filters `tagged_event`, then asserts every filtered element satisfies `isTag`, and fails
  loudly otherwise. It must never skip an element silently: `expect(c.every(isTag)).toBe(true)` before the
  `.map`, then narrow.
- The threshold test runs `expect(isFrequency(trig[0].comparison)).toBe(true)` before destructuring,
  narrowing through a guard or an `if (!isFrequency(...)) throw`.
- The test count stays at 25.

## User-Brand Impact

- **If this lands broken, the user experiences:** the operator gets a daily drift issue telling them to
  re-run the Sentry apply for a rule that gained a Seer trigger. The apply is then refused by the tripwire,
  or leaves the finding open. In the worst case a write gets past the tripwire and the paging rule's added
  trigger is corrupted. If the new branch misclassifies a vendor default or frozen rule, the operator gets
  a false P1 drift issue.
- **If this leaks, the user's data is exposed via:** no new exposure. The probe reads the same workflows
  payload with the same transport-confined curl. It gains no new credential, network destination or
  output sink, and the finding text carries only rule names and ids, which it already prints.
- **Brand-survival threshold:** `none`. This is internal alerting-fidelity tooling with no end-user surface.
  `threshold: none, reason: the diff touches only the Sentry drift probe, its tests, a spec script comment and a vitest type; no end-user data path or runtime code changes.`

## Observability

```yaml
liveness_signal:
  what: "scheduled-sentry-alert-drift.yml daily run of scripts/sentry-alert-live-fidelity.sh (and the post-apply run in apply-sentry-infra.yml)"
  cadence: "daily + per Sentry apply"
  alert_target: "GitHub issue labelled ci/sentry-alert-drift (filed/updated by the workflow) → operator"
  configured_in: ".github/workflows/scheduled-sentry-alert-drift.yml"
error_reporting:
  destination: "GitHub Actions job log + the ci/sentry-alert-drift issue body (probe stdout verbatim)"
  fail_loud: "the line 'sentry_alert live fidelity FAILED' plus a 'MANAGED RULE GAINED EXCLUDED TRIGGER:' finding line; a projection/transport failure exits 1 without the FAILED line and reds the job (verdict=unavailable)"
failure_modes:
  - mode: "a managed rule gains an excluded trigger Sentry-side"
    detection: "probe emits MANAGED RULE GAINED EXCLUDED TRIGGER (new); drift workflow files the issue"
    alert_route: "ci/sentry-alert-drift GitHub issue"
  - mode: "the new branch misclassifies a vendor default or frozen rule"
    detection: "existing G4-6/G4-14/G4-20..G4-23 rows in tests/scripts/test-sentry-alert-live-fidelity.sh red in CI (scripts/test-all.sh run_suite)"
    alert_route: "PR CI red"
logs:
  where: "GitHub Actions run logs for scheduled-sentry-alert-drift.yml / apply-sentry-infra.yml"
  retention: "GitHub Actions default log retention (90 days)"
discoverability_test:
  command: "grep -o -m1 'MANAGED RULE GAINED EXCLUDED TRIGGER' scripts/sentry-alert-live-fidelity.sh"
  expected_output: "MANAGED RULE GAINED EXCLUDED TRIGGER" or "GAINED"
```

The probe itself needs a Sentry token, so the local, credential-free signal is that the classifier
is present in the shipped script. `grep` is on preflight Check 10's `PROBE_VERB_ALLOWLIST`
(`plugins/soleur/skills/preflight/scripts/probe-verb-gate.sh:64`), and the command returns in
milliseconds, well inside the 15-second cap. The end-to-end behaviour is proved by rows G4-25
through G4-28 in `tests/scripts/test-sentry-alert-live-fidelity.sh`, which run without credentials
in fixture mode.

## Guard Contract

### Guard 1 — managed-rule-gained-excluded-trigger classification

**Property.** Every live workflow that carries an excluded trigger type, whose name is a key of the
reference and is not the name of any in-scope live workflow, and whose {id, name} is not a registered
default, is reported as `MANAGED RULE GAINED EXCLUDED TRIGGER`; it is never reported as
`DELETED or RENAMED` and never counted as a registered default, and every other excluded-type workflow
classifies exactly as before.

**Assembly.** Two chokepoints, both in `scripts/sentry-alert-live-fidelity.sh`:

1. The per-rule loop over `jq -r 'keys[]' <<<"$ref_proj"`, which is the only emitter of `DELETED or RENAMED`.
2. The frozen-rule pin jq program, where `$O` is the only population the census iterates, and `$KNOWN`
   and the `COUNT` line are the only acceptance and tally.

The excluded set reaches both through the one-line `def excluded` lifted from the projection; it enters
the loop implicitly, through `project_live`'s `in_scope`. The reference keys reach the pin only through
the new `--argjson refnames`.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Delete the GAINED arm from the `$O` chain | RED: G4-25 (marker absent) |
| 2 | Remove the loop's raw-name `continue`, so `DELETED or RENAMED` is emitted again | RED: G4-25 (negative assert on `DELETED or RENAMED: 'byok-art-33-breach'`) |
| 3 | GAINED arm evaluates only the first `$O` member (`first(...)` / `limit(1; …)`) | RED: G4-26 (two managed rules gained; the second name must appear) |
| 4 | Drop the "not in `$INSCOPE`" condition | RED: G4-27 (a same-name excluded copy of a healthy managed rule must stay `UNMANAGED-FROZEN`, not GAINED) |
| 5 | Revert the `$KNOWN` narrowing (KNOWN = whole capture) | RED: G4-28 (managed name removed from the reference, live gained, must be `UNMANAGED-FROZEN`, not silent) |
| 6 | Move GAINED after KNOWN, with mutation 5 also applied | RED: G4-25 (silently accepted, and the COUNT assert fails) |
| 7 | `COUNT` third field includes GAINED members | RED: G4-25 asserts `(${DEFAULTS_N} other excluded-type` with `DEFAULTS_N = FROZEN_N - FROZEN_TF_N`, derived |
| 8 | GAINED arm matches on name alone and ignores `excl_type` (the dispatch) | RED: F1/G4-6 identity (every managed rule would be GAINED) |

**Harness rows.**

- Suite-side RED: removing a new row's invocation from the runner list reds via `EXPECTED_TESTS` (59 → 63).
  Each new row asserts its mutation landed, for example `jq -e` that the fixture's `byok-art-33-breach`
  carries `seer_activity_trigger`.
- Must-PASS non-canonical inputs, unchanged: G4-20 (capture + registered Seer default, PASSES), G4-14
  (vendor default disabled, PASSES), G4-6 (identity, with its count line).

**Anchor.** The expected counts come from the committed capture plus a `.tf` grep (`FROZEN_TF_N`) plus the
module's `def excluded` line; none is typed. A weakening edit to `def excluded` has to pass `plan_pr` and
review of the projection file, which this PR does not touch beyond a comment.

## Acceptance Criteria

- [ ] **AC1 (a).** With the capture plus `{"type":"seer_activity_trigger","comparison":["pr_ready_for_review"]}` appended to `byok-art-33-breach`'s triggers, the probe exits 1 and prints `MANAGED RULE GAINED EXCLUDED TRIGGER: 'byok-art-33-breach'`; it prints neither `DELETED or RENAMED: 'byok-art-33-breach'` nor `UNMANAGED-FROZEN: 'byok-art-33-breach'`, and the count line reads `(${DEFAULTS_N} other excluded-type` (derived, = 1 today). Location: `scripts/sentry-alert-live-fidelity.sh` per-rule loop and frozen-pin jq. Row G4-25.
- [ ] **AC2 (a).** Two managed rules gained are both reported (G4-26).
- [ ] **AC3 (a).** A same-name excluded-type copy of an intact managed rule is still `UNMANAGED-FROZEN` (G4-27). Assert on the anchor `UNMANAGED-FROZEN: 'byok-art-33-breach'` plus the absence of the GAINED marker, NOT on the rest of that line: the `$KNOWN` narrowing moves this case from the "carries the name of a registered Sentry default under a DIFFERENT id" arm to the generic arm, so the tail of the message legitimately changes (measured below).
- [ ] **AC4 (a).** A reference missing `byok-art-33-breach`, plus live gained, gives `UNMANAGED-FROZEN: 'byok-art-33-breach'` and rc=1 (G4-28; exercises the `$KNOWN` narrowing). Today this fixture PASSes with rc=0, having compared nothing for that workflow — measured below.
- [ ] **AC5 (a, P2).** Every pre-existing row passes unchanged, in particular F1, F12, G4-6, G4-14, G4-15, and G4-20 through G4-24. `git diff origin/main -- tests/scripts/lib/sentry-alert-projection.jq` shows only added `#` comment lines: the `def excluded:` line and the `def in_scope` / `def tf_in_scope` bodies are byte-identical.
- [ ] **AC6 (a).** The drift workflow has a bullet naming `MANAGED RULE GAINED EXCLUDED TRIGGER`, and the probe's final summary line names the class.
- [ ] **AC7 (b).** `grep -nE 'length == 31|comparing 28' tests/scripts/test-sentry-alert-live-fidelity.sh` returns nothing. The derivation floor (`N == CAPTURE_N - EXCL_CAPTURE_N`) is present and exits 1 on mismatch.
- [ ] **AC8 (c).** `phase2-generate-alert-blocks.py` carries the frozen comment above `EXCLUDE`; `EXCLUDE` is unchanged, and `python3 -m py_compile` passes.
- [ ] **AC9 (d).** In the op-contract test, `comparison` is typed as the union; both use sites narrow through an asserted guard, and no `as` cast is added at a use site. `vitest run test/sentry-zot-mirror-fallback-alert-op-contract.test.ts` passes 25/25, and `tsc --noEmit -p apps/web-platform` has no new error in that file.
- [ ] **AC10.** `bash tests/scripts/test-sentry-alert-live-fidelity.sh` gives `63 passed, 0 failed`, with `EXPECTED_TESTS=63`.
- [ ] **AC11.** No `.tf` file changes (`git diff --name-only origin/main | grep -c '\.tf$'` gives 0), so `plan_pr` has no resource changes.
- [ ] **AC12 (TDD order).** G4-25 through G4-28 are written first and observed RED against the unmodified probe: G4-25 red on the marker, G4-26 red, G4-27 already green (a regression guard), G4-28 red. Then the probe change turns them green.

## Deepen-Pass Evidence (2026-09-22)

Every claim below was produced by running the command against this branch. Nothing here is cited from
memory. All probe runs are fixture-mode (`SENTRY_FIXTURE_RULES`), with the reference derived from the
committed capture through the live and reference sides of the module.

**E1 — the misclassification, reproduced.** Capture + `seer_activity_trigger` on `byok-art-33-breach`:

```text
sentry_alert live fidelity: comparing 28 declared rule(s) against 27 live in-scope rule(s)
  DELETED or RENAMED: 'byok-art-33-breach' … An apply can recreate a deleted rule …
sentry_alert live fidelity: frozen-rule pin: compared 2 of 2 … (2 other excluded-type live workflow(s)
are registered Sentry defaults, matched by id and name, content not pinned)
ERROR: sentry_alert live fidelity FAILED — 1 divergence(s)
```

Two defects in one run: the wrong remedy, and a census that counts the managed rule as a second
"registered Sentry default" (the true number is 1).

**E2 — the `$KNOWN`-whole-capture defect, isolated.** Same live fixture, with `byok-art-33-breach`
deleted from the reference (the shape of a rule removed from Terraform while still live):

```text
sentry_alert live fidelity: comparing 27 declared rule(s) against 27 live in-scope rule(s)
sentry_alert live fidelity: frozen-rule pin: … (2 other excluded-type live workflow(s) are registered …)
sentry_alert live fidelity: PASS (FIXTURE — not live) (all 27 in-scope rules match …)   rc=0
```

A live, excluded-type, unowned workflow produces a clean PASS today, because `$KNOWN` is built from
every capture entry rather than from the capture's excluded-type, non-frozen entries. This is what
row G4-28 pins and what "Proposed Solution" step 3 fixes.

**E3 — the same-name-copy case (G4-27), baseline.** Capture plus a `byok-art-33-breach` copy under id
`999900` carrying only `seer_activity_trigger`: today `UNMANAGED-FROZEN: 'byok-art-33-breach' (id
"999900") carries the name of a registered Sentry default under a DIFFERENT id …`, rc=1, and the count
line reads `1 other excluded-type`. After the narrowing the same case falls to the generic
`UNMANAGED-FROZEN` arm, so AC3 asserts the anchor only.

**E4 — the counts, derived.** `jq length` on the capture is 31; the derived reference holds 28;
capture workflows carrying an excluded type are 3 (566201 high-priority default, 566671
`auth-per-user-loop`, 669246 `sandbox-startup-failure`). `31 − 3 = 28` confirms the floor in
"(b) Derived counts". The production reference (`alert-reference.json`) holds 30, and 32
`resource "sentry_alert"` blocks exist in `issue-alerts.tf` (30 native + 2 frozen), so the suite's
28 is a fixture constant, exactly as the suite header states.

**E5 — `comparison` shapes, measured.** In the capture, trigger `comparison` is `boolean` for
`first_seen_event`, `reappeared_event`, `regression_event`, `new_high_priority_issue`,
`existing_high_priority_issue`, and `object` for `event_frequency_count` and
`event_unique_user_frequency_count`. Action-filter `comparison` is `object` for `tagged_event` only.
The array shape comes from Seer (`["pr_ready_for_review"]`), which the suite's `_seer_live` helper
already builds. So the union is `boolean | unknown[] | object`, and the two narrowing sites are the
`tagged_event` map and the `event_unique_user_frequency_count` threshold read.

**E6 — citations verified live.** `#7985` OPEN, `#8050` CLOSED, `#8267` CLOSED, `#8451` CLOSED,
`#8545` MERGED, `#8576` OPEN (`gh issue view` / `gh pr view`). Rule ids `hr-type-widening-cross-consumer-grep`,
`cq-test-fixtures-synthesized-only`, `cq-assert-anchor-not-bare-token`, `hr-observability-as-plan-quality-gate`
and `hr-weigh-every-decision-against-target-user-impact` are all active in `AGENTS.md`. Both cited
learning files exist under `knowledge-base/project/learnings/`.

**E7 — no consumer parses finding classes.** `scheduled-sentry-alert-drift.yml` branches only on
`grep -q 'live fidelity FAILED'` (its `verdict` step); the "How to read them" bullets are prose for
the issue body. `tests/scripts/test-sentry-alert-drift-workflow.sh` W7 pins the same `FAILED` literal.
A new marker therefore cannot change the filer's control flow, only its guidance text.

**E8 — precedent diff.** No sibling precedent exists for "a managed resource left the comparison scope
because live gained an unmanageable attribute": the pattern is novel in this repo. The closest
neighbours are the `UNMANAGED-FROZEN` chain (same jq program) and the census/registry identity check
(#8545), and the new arm is written in their shape: one `elif` in the same chain, the same
`FINDING <CLASS>: '<name>' (id <id>) …` line format, and the same `_finding` emitter. Reviewers should
scrutinize the ordering of the chain, which is where the behaviour is decided.

**E9 — baselines.** `bash tests/scripts/test-sentry-alert-live-fidelity.sh` → `59 passed, 0 failed`
(2m40s wall). `vitest run test/sentry-zot-mirror-fallback-alert-op-contract.test.ts` → 25 passed
(0.8s). `apps/web-platform/tsconfig.json` is `strict` and includes `**/*.ts`, so the widened type is
type-checked by `web-platform-typecheck`.

## Test Scenarios

- Given the capture with `seer_activity_trigger` added to one managed rule, when the probe runs in fixture mode, then exactly one finding appears (GAINED), rc=1, and the `live fidelity FAILED` line is present, so the drift filer's `verdict=drift` still fires.
- Given the capture plus the registered Seer default (the existing G4-20 fixture), when the probe runs, then PASS as today.
- Given the capture, when F13 builds the API-shaped fixture, then its length equals `jq length` of the capture.
- Regression: the op-contract threshold row still reads `{value, interval}` from the frozen rules' capture entries after narrowing.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected: an internal Sentry-alerting tooling and test change with no
user-facing surface and no new infrastructure. The Product/UX gate does not fire, since no UI-surface file
is in the file lists.

## Open Code-Review Overlap

None. The open `code-review` issues were queried for `sentry-alert-live-fidelity`, `sentry-alert-projection`,
`test-sentry-alert-live-fidelity`, `phase2-generate-alert-blocks`,
`sentry-zot-mirror-fallback-alert-op-contract` and `scheduled-sentry-alert-drift`, and none matched.

## Files to Edit

- `scripts/sentry-alert-live-fidelity.sh`
- `tests/scripts/lib/sentry-alert-projection.jq` (comment lines only)
- `tests/scripts/test-sentry-alert-live-fidelity.sh`
- `.github/workflows/scheduled-sentry-alert-drift.yml` (one `printf` bullet)
- `knowledge-base/project/specs/fix-7650-sentry-alert-migration/phase2-generate-alert-blocks.py` (comment)
- `apps/web-platform/test/sentry-zot-mirror-fallback-alert-op-contract.test.ts`

## Files to Create

None.

## Implementation Phases

1. **RED.** Add the `CAPTURE_N`/`EXCL_CAPTURE_N` derivations and the floor; rewrite F12 and F13; add
   rows G4-25 through G4-28 and set `EXPECTED_TESTS=63`. Run the suite: the new rows fail as AC12
   predicts, and all 59 existing rows pass.
2. **GREEN (a).** Make the probe changes in steps 1 through 5 of "Proposed Solution" (a), add the
   projection comment, and add the drift-workflow bullet. Run the suite until it shows 63/63.
3. **(c) and (d).** Add the generator comment and run `py_compile`. Widen the test type, then run vitest
   and `tsc`.
4. **Verify.** Run both suites, the `sentry-alert-live-fidelity` suite through `scripts/test-all.sh`, the
   workflow lint (actionlint, where CI runs it), and `git diff --stat` to confirm there are no `.tf` changes.

## Dependencies & Risks

- **Risk: marker substring collisions.** Several existing rows grep negatively (`FROZEN`, `UNMANAGED`,
  `DELETED`). The chosen marker contains none of them; verify with
  `grep -c 'FROZEN\|UNMANAGED\|DELETED' <<<"MANAGED RULE GAINED EXCLUDED TRIGGER"`, which gives 0.
- **Risk: narrowing `$KNOWN` changes a vendor classification.** The capture's excluded-type, non-frozen
  entries are exactly {566201}, so G4-14, G4-15 and G4-23 cover it unchanged.
- **CI is slow (100–200 queued runs).** Admin-merge needs operator approval, and only after every
  required check is green on the pinned head, except known main-origin reds.
- The suite's wall time grows by about 4 × 3s.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty or has only placeholder text fails deepen-plan
  Phase 4.6. It is filled here.
- The probe lifts `def excluded` with the regex `^def excluded: \[.*\];[[:space:]]*$`. A comment added on
  the same line, or a reflow of that line, makes the probe REFUSE. Put the new comment on its own lines
  above `def in_scope`.
- `refnames` is passed with `--argjson` from `jq -c 'keys'`. Do not interpolate names into the jq program
  text, because names contain spaces and quotes.
- F12's grep string contains `(s)`. Use `grep -qF` so the parentheses are not treated as regex.

## References

- #7985 (parent; frozen rules; BLOCKED, not closed here)
- #8451 (frozen-rule pin / Guard 4)
- #8267 / #8545 (Seer vendor-default registry)
- #8050 (plan-projected reference)
- ADR-031 (Sentry as IaC; vendor-default amendment)
