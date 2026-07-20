# Tasks — web-2 dispatch sweep + coherence verifier re-anchoring

Plan: `knowledge-base/project/plans/2026-07-20-fix-web1-bake-coherence-gate-and-web2-dispatch-sweep-plan.md`
Closes: **#6575** · Refs: #6712 (stays OPEN), #6730, #6574, #6425
Lane: `cross-domain` (fail-closed default — no spec `lane:`)
Brand-survival threshold: `single-user incident` → CPO sign-off before `/work`.
Challenges: see `decision-challenges.md` (UC-1: #6712 does not close here).

> **Revised after deepen pass.** v1's bake-time release gate, `host-scripts-want-hash.sh` and its
> test are **not** implemented — the gate was tautological, would have poisoned `:latest`, and its
> feasibility premise was false. Build-integrity coverage was never zero
> (`cloud-init-user-data-size.test.ts:486-510`), so **no cross-phase ordering constraint applies**.
> The rename must still be **atomic with its references** (2.8).

## Phase 0 — Preconditions

- [ ] 0.1 `bash scripts/test-all.sh` — capture the baseline result set.
- [ ] 0.2 Re-grep every `file:line` anchor in the plan; Phase 2 shifts ~730 lines.

## Phase 1 — Strengthen build-integrity coverage (~10 lines)

- [ ] 1.1 In `plugins/soleur/test/cloud-init-user-data-size.test.ts`, add to the existing
      baked-set-parity describe: **assertion A** — no `RUN` between the host-scripts `COPY` and the
      end of the runner stage writes into `/opt/soleur/host-scripts/` (allow-list the existing
      ownership-only `chown -R 1001:1001` form, with a comment saying why it is safe);
      **assertion B** — `host_script_files` contains no duplicates.
- [ ] 1.2 Harden the parser: strip `^\s*#` lines before the `/"([^"]+)"/g` match; add a fixture with
      a quoted filename inside a comment asserting the parsed set is unchanged.
- [ ] 1.3 Prove non-vacuity (AC1): duplicate an entry → B fails; add a mutating `RUN` → A fails.
      Capture evidence; commit neither temporary change.

## Phase 2 — Delete the web-2 dispatch surface

- [ ] 2.1 Delete `warm_standby`, `web_2_recreate` and the intervening comment block.
- [ ] 2.2 Remove both enum options; rewrite the `apply_target` description for the remaining **7**.
- [ ] 2.3 Delete `tests/scripts/lib/web2-recreate-gate.sh`.
- [ ] 2.4 Remove the three `web2_*` clauses + rationale from the destroy-guard `.jq`; fix the
      orphaned `host_creates` cross-reference. **Do not touch `web2_retire_allow`.**
- [ ] 2.5 Before deleting the 8 fixtures + T20-T28: confirm a surviving counter test covers
      non-placement-update detection, `forget`-as-destroy, and `IN()` exact-equality. Retarget any
      fixture that would otherwise lose mechanism coverage (AC4).
- [ ] 2.6 Delete `deploy-status-fanout-verify.{sh,test.sh}` + its `infra-validation.yml:576` entry.
      Preserve its design record (the `.tag` last-write-wins trap) in the ADR.
- [ ] 2.7 Delete `lb-weight-gate.{sh,test.sh}` + its `infra-validation.yml:585` entry; record in
      ADR-068 §(c).
- [ ] 2.8 **Atomic rename commit** — `git mv` the preflight and its test to the host-agnostic names,
      rename env seams (`HOST_SCRIPTS_WANT_HASH`, `HOST_SCRIPTS_SEED_DIR`) and the `die()`/success
      prefixes, rewrite the header, update `scripts/test-all.sh:218`, and confirm no reference
      survives in `apply-web-platform-infra.yml` or `terraform-target-parity.test.ts:1252`. Logic
      byte-unchanged; all six test cases retained.
- [ ] 2.9 Retain `resolve-web1-known-good-tag.sh` + test under the retention rule (named in the
      `-replace` arm of the 3.1 chain). Correct the record: it had **two** callers.

## Phase 3 — Runbook replacements

- [ ] 3.1 Rewrite the `host_creates` HALT text: drop the dead-path enumeration, keep the ADR-096
      routing and `inngest-host` bullet, **add the complete `crane digest` → verify →
      `-var image_name=` command chain**, and add the `ignore_changes` sentence.
- [ ] 3.2 Delete the `stock-preflight-gate.sh` web-2 tine + rationale + setter; **rewrite the
      surviving `#6463` tine web-1-specific** (wait-for-stock primary; `server_type` change within
      hel1 secondary; location change flagged as implying volume recreation); fix the two stale line
      refs. Rewrite T2; delete T10b/T13b with reasons; **replace T10c** with a ≥1-remediation-line
      assertion.
- [ ] 3.3 `scheduled-inngest-health.yml`: rewrite `:838` step 2 (no recreate dispatch exists); drop
      the fsn1/web-2 row from the `:837` colo table.
- [ ] 3.4 Delete both follow-through scripts; close #6425 (AC13).

## Phase 4 — Parity sentinels (each with a `# reason:` comment)

- [ ] 4.1 `stock-preflight-coverage.test.ts`: `MIN_APPLY_TARGET_OPTIONS` 9→7, `MIN_GATED_TARGETS`
      5→4, delete the `warm-standby` `EXCLUSION_ALLOWLIST` entry, fix prose/title.
- [ ] 4.2 `terraform-target-parity.test.ts`: delete both target constants and their `describe`
      blocks (incl. the `web2-recreate-preflight.sh` assertion at `:1252`), remove the two `stripJob`
      wrappers, fix stale comments. **Delete — do not observe green.**
- [ ] 4.3 `web-1-swap-concurrency-parity.test.sh`: drop two `assert_member` lines, count `-eq 5`→
      `-eq 3`, fix the pre-existing stale header (says 4).
- [ ] 4.4 `web-hosts-fanout-parity.test.sh`: drop the apply-workflow copy check + file guard; fix
      stale prose; leave the `-lt 1` floor.

## Phase 5 — Registers

- [ ] 5.1 Author the two-invariant ADR (provisional ordinal from a freshly-fetched `origin/main`),
      including the retention rule and preserved design records.
- [ ] 5.2 Supersede ADR-082 per the ADR-008 convention; mark Item 4 **in force but UNMET (#6730)**.
- [ ] 5.3 Rewrite ADR-114 hazard #5; **preserve `:375-380` verbatim**.
- [ ] 5.4 `issue-alerts.tf` — **comment only**; resource survives unchanged (AC9).
- [ ] 5.5 Read all three `.c4` files; act on the `model.c4` warm-standby hit; run the C4 tests.
- [ ] 5.6 Update `nic-wait-gate.test.sh` comments; keep asserts green; do not restate the invalid
      `-target` inference.
- [ ] 5.7 Comment on #6712 and #6730 (AC14).

## Phase 6 — Verification

- [ ] 6.1 `bash scripts/test-all.sh` green; diff against the 0.1 baseline.
- [ ] 6.2 `actionlint` on both edited workflows (never `bash -n` on workflow YAML).
- [ ] 6.3 `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`.
- [ ] 6.4 Residual sweep per AC3 (excluding plans/specs/brainstorms/archive).
- [ ] 6.5 Build the deleted-runbook-line → replacement table for the PR body (AC8).
</content>
