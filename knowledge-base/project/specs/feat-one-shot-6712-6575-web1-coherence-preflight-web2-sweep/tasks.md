# Tasks — web-1 bake coherence gate + web-2 dispatch sweep

Plan: `knowledge-base/project/plans/2026-07-20-fix-web1-bake-coherence-gate-and-web2-dispatch-sweep-plan.md`
Closes: #6712, #6575 · Refs: #6730, #6574, #6425
Lane: `cross-domain` (fail-closed default — no spec `lane:`)
Brand-survival threshold: `single-user incident` → CPO sign-off required before `/work`.

> **Phase order is load-bearing.** Phase 1 (relocate the guard) must fully precede Phase 2
> (delete). At no commit boundary may coherence coverage be zero — AC1 verifies this per-commit.

## Phase 0 — Preconditions (verify only, no edits)

- [ ] 0.1 Read `apps/web-platform/infra/scripts/web2-recreate-preflight.sh` in full; note the four
      blocks to preserve byte-for-byte (digest gate, WANT gate, `GOT` pipeline, comparison).
- [ ] 0.2 Confirm `reusable-release.yml` has no `setup-terraform` and no `prd_terraform` token.
      If changed, prefer `terraform console` and drop task 1.3/1.4.
- [ ] 0.3 Confirm `steps.docker_build.outputs.digest` is populated and already consumed.
- [ ] 0.4 Confirm boot-side and Terraform-side hash constructions agree; record the confirmation.
- [ ] 0.5 `bash scripts/test-all.sh` — capture the baseline result set.
- [ ] 0.6 Re-grep every `file:line` anchor in the plan; two large deletions will shift them.

## Phase 1 — Relocate the guard (additive only)

- [ ] 1.1 `git mv` preflight → `host-scripts-coherence-preflight.sh`; rename env seams
      (`HOST_SCRIPTS_WANT_HASH`, `HOST_SCRIPTS_SEED_DIR`), `die()` prefix and success line; rewrite
      header host-agnostically. Logic byte-unchanged.
- [ ] 1.2 `git mv` its test → `test-host-scripts-coherence-preflight.sh`; retain all six cases;
      update `run_suite` in `scripts/test-all.sh`.
- [ ] 1.3 Create `apps/web-platform/infra/scripts/host-scripts-want-hash.sh` — parse
      `local.host_script_files` from `server.tf`, recompute the Terraform-side hash, fail closed.
- [ ] 1.4 Create `apps/web-platform/infra/host-scripts-want-hash.test.sh` asserting equality with
      `terraform console local.host_scripts_content_hash`, plus fail-closed cases; register in
      `.github/workflows/infra-validation.yml`.
- [ ] 1.5 Add the coherence step to `.github/workflows/reusable-release.yml` after `docker_build`,
      before `Install cosign`, gated on `docker_build.outcome == 'success'`.
- [ ] 1.6 Prove the gate fires against a deliberate mismatch; capture evidence for AC6. Do not
      commit the scratch artifact.
- [ ] 1.7 **Checkpoint commit.** Coverage is now 2 call sites. Deletion may begin.

## Phase 2 — Delete the web-2 dispatch surface

- [ ] 2.1 Delete `warm_standby` and `web_2_recreate` jobs + the intervening comment block.
- [ ] 2.2 Remove both enum options; rewrite the `apply_target` description for the remaining 7.
- [ ] 2.3 Delete `tests/scripts/lib/web2-recreate-gate.sh`.
- [ ] 2.4 Remove the three `web2_*` clauses + rationale from the destroy-guard `.jq`; fix the
      orphaned `host_creates` cross-reference. **Do not touch `web2_retire_allow`.**
- [ ] 2.5 Before deleting the 8 fixtures + T20-T28: confirm a surviving counter test still covers
      non-placement update detection, `forget`-as-destroy, and `IN()` exact-equality. Retarget any
      fixture whose mechanism would otherwise lose coverage (AC13).
- [ ] 2.6 Delete `deploy-status-fanout-verify.{sh,test.sh}` + its `infra-validation.yml` entry;
      preserve its design record in the new ADR.
- [ ] 2.7 Decide and record `resolve-web1-known-good-tag.sh` (recommendation: keep).

## Phase 3 — Parity sentinels (each with a `# reason:` comment)

- [ ] 3.1 `stock-preflight-coverage.test.ts`: `MIN_APPLY_TARGET_OPTIONS` 9→7,
      `MIN_GATED_TARGETS` 5→4, delete the `warm-standby` `EXCLUSION_ALLOWLIST` entry, fix prose.
- [ ] 3.2 `terraform-target-parity.test.ts`: delete both target constants and their `describe`
      blocks, remove the two `stripJob` wrappers, fix stale comments. **Delete — do not observe green.**
- [ ] 3.3 `web-1-swap-concurrency-parity.test.sh`: drop two `assert_member` lines, count `-eq 5`→`-eq 3`,
      fix the pre-existing stale header (says 4).
- [ ] 3.4 `web-hosts-fanout-parity.test.sh`: drop the apply-workflow copy check and its file guard;
      fix stale prose; leave the `-lt 1` floor alone.

## Phase 4 — Runbook replacements

- [ ] 4.1 Rewrite the `host_creates` HALT text: drop dead-path enumeration, keep the ADR-096
      routing and the `inngest-host` bullet, add the bake-verified-images sentence.
- [ ] 4.2 Delete the `stock-preflight-gate.sh` web-2 tine + rationale + setter; fix its two stale
      line refs. Rewrite T2; delete T10b/T10c/T13b **each with a stated reason**. Record the
      free-repair capability loss honestly.
- [ ] 4.3 `scheduled-inngest-health.yml`: rewrite `:838` remediation step 2; drop the fsn1/web-2
      row from the `:837` colo attribution table.
- [ ] 4.4 Delete both follow-through scripts; close #6425 with a resolved-by-#6538 comment.

## Phase 5 — Registers

- [ ] 5.1 Author the new bake-time-coherence ADR (provisional ordinal; re-derive at ship).
- [ ] 5.2 Supersede ADR-082 per the ADR-008 convention with the in-force / dead partition.
- [ ] 5.3 Rewrite ADR-114 hazard #5; **preserve `:375-380` verbatim**.
- [ ] 5.4 `issue-alerts.tf` — **comment only**; the resource survives unchanged.
- [ ] 5.5 Delete `lb-weight-gate.{sh,test.sh}` + its registration; record in ADR-068 §(c).
- [ ] 5.6 Read all three `.c4` files; act on the `model.c4` warm-standby hit; run the C4 tests.
- [ ] 5.7 Update `nic-wait-gate.test.sh` comments; keep every assert green and truthful.

## Phase 6 — Verification

- [ ] 6.1 `bash scripts/test-all.sh` green; diff against the 0.5 baseline.
- [ ] 6.2 `actionlint` on both edited workflows (never `bash -n` on workflow YAML).
- [ ] 6.3 `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`.
- [ ] 6.4 Residual sweep per AC10 (excluding plans/specs/brainstorms/archive).
- [ ] 6.5 Walk AC1 per-commit with `git rev-list` + `git show` — **not** `git log -- A B`.
- [ ] 6.6 Build the deleted-runbook-line → replacement table for the PR body (AC14).
</content>
