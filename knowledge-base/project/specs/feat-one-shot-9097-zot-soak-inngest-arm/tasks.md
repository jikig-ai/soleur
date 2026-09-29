# Tasks — fix(followthroughs): retarget the zot-soak-6122 inngest sample arm onto dedicated-host boot evidence

Plan: `knowledge-base/project/plans/2026-09-29-fix-zot-soak-inngest-arm-plan.md`
Issue: #9097 · Branch: `feat-one-shot-9097-zot-soak-inngest-arm` · Lane: cross-domain (fail-closed default; no spec.md precedes this plan)

Operating norms: one PR; commit with `LEFTHOOK_EXCLUDE=bun-test,plugin-component-test,web-platform-typecheck` (CPU-contended — run the targeted suites below locally, rely on CI for the rest); never `git merge` main — `git rebase origin/main` if BEHIND. No `deploy inngest` dispatches; no Terraform/cloud-init/host changes.

## Phase 1 — Failing tests (TDD RED)

- [x] 1.1 In `scripts/followthroughs/zot-soak-6122.test.sh`, add the new rows WITHOUT yet removing `$Q_ZOTING` from `HEALTHY`/legacy specs (removing it first turns every HEALTHY-based row TRANSIENT-red on the unfixed script):
  - [x] 1.1.1 NB1 accepted-evidence row: spec carries `$Q_ZOTING=0` as the first key matching the inngest URL — shipped as a tail append (`"$HEALTHY;$Q_ZOTING=0"`) since Phase 2 removed `$Q_ZOTING=5` from HEALTHY (a substitution would no-op there; with no earlier matching key the append IS first-match — verified no other HEALTHY key is a substring of that URL) — blockers CLOSED/COMPLETED, `inngest_fixed=yes` → expect exit 0 `PASS` (RED pre-fix: unfixed script FAILs `insufficient-sample` on `inngest=0`)
  - [x] 1.1.2 NB2 zero-evidence row: `G6_NOEV` (soleur-inngest=0) → expect exit 1 `FAIL(no-inngest-freshboot-evidence)` (baseline pin; green pre-fix)
  - [x] 1.1.3 NB3 mutation row: delete the denominator's `if (( INNGEST_ZOT == 0 ))` FAIL block on a soak copy (assignment kept) and run a `G6_NOEV`+`$Q_ZOTING=0` spec → expect exit 1 `FAIL(insufficient-sample)`
  - [x] 1.1.4 NB4 residual-zero (source): `image:"inngest"` absent from comment-stripped soak code lines AND the sample `if` names `INNGEST_ZOT` (RED pre-fix)
  - [x] 1.1.5 NB5 residual-zero (runtime): after a CLOSED/COMPLETED + `inngest_fixed=yes` run, `$URL_SINK` has no line matching `image%3A%22inngest%22` (RED pre-fix)
  - [x] 1.1.6 NB6 non-canonical must-PASS: `soleur-inngest=2`, `web=5`, `$Q_ZOTING=0` (same substitution-derivation as NB1) → exit 0 PASS
  - [x] 1.1.7 Bump `SOAK_MIN_PASSES` by the new assertion count in the same edit; extend its "Raised … in the SAME edit" comment
- [x] 1.2 Run `bash scripts/followthroughs/zot-soak-6122.test.sh`; confirm NB1/NB4/NB5 are RED (and the failure modes are the semantic ones, not stub-500 TRANSIENTs)

## Phase 2 — Retarget the soak arm (GREEN)

- [x] 2.1 In `scripts/followthroughs/zot-soak-6122.sh`:
  - [x] 2.1.1 Delete the `ZOT_INNGEST=$(sentry_count 'feature:supply-chain op:image-pull registry:"zot" image:"inngest"')` query and narrow the TRANSIENT guard to `ZOT_WEB` (sentinel guarded before arithmetic)
  - [x] 2.1.2 Change the sample arm to require `ZOT_WEB >= MIN_SAMPLE` AND `INNGEST_ZOT >= 1` — hardcoded floor `1` for the inngest leg (no knob; dedicated host pulls zot only at boot, one boot per host-replace — `>=3` would recreate the unreachable-arm defect), with the rationale comment mirroring APP_ZOT's
  - [x] 2.1.3 Update `FAIL(insufficient-sample)`, `FAIL(blocked)`, and `PASS` lines to report `inngest-boots=$INNGEST_ZOT`-style evidence (no `inngest=$ZOT_INNGEST` deploy-pull count anywhere); the `insufficient-sample` threshold prose becomes per-leg (`web>=$MIN_SAMPLE`, `inngest>=1` boot — a shared "need >=3 each" is now wrong)
  - [x] 2.1.4 Update the arm (b) bullet in the top-of-file contract, the arm (b) header comment, and the `MIN_SAMPLE` comment: inngest exercise proof = dedicated-host `stage:"inngest_zot" host_name:"soleur-inngest"` boot beacon; `image:"inngest"` is a retired sample operand (named in comments only), retired because the sole `deploy inngest` sender (deploy-inngest-image.yml → quiesced web scheduler) cannot emit it post-cutover (#9097)
- [x] 2.2 Same commit, post-GREEN cleanup in the test file: remove `$Q_ZOTING` from `HEALTHY` and the legacy spec strings (~lines 221/301/308/319); keep the `Q_ZOTING` constant (NB1/NB3/NB6 use it); re-scope the thin-sample row's comment (~line 316) — post-fix it exercises only the web leg (the inngest leg's thin-evidence coverage is NB3's denominator-deleted mutant)
- [x] 2.3 Re-run `bash scripts/followthroughs/zot-soak-6122.test.sh` — fully GREEN; run `bash scripts/followthrough-exec-bit.test.sh`

## Phase 3 — Records and ship

- [x] 3.1 Append `## Amendment 2026-09-29 (#9097)` to `knowledge-base/engineering/architecture/decisions/ADR-096-migrate-container-registry-ghcr-to-self-hosted-zot.md` (evidence retarget; soak still gates 5.6)
- [x] 3.2 Comment-only fix in `apps/web-platform/test/sentry-zot-mirror-fallback-alert-op-contract.test.ts` (~lines 252-253): the remark citing `ZOT_INNGEST` sample queries must not name a removed variable (optionally run `cd apps/web-platform && bun test test/sentry-zot-mirror-fallback-alert-op-contract.test.ts` if machine tolerates)
- [x] 3.3 `gh issue comment 6122` recording the arm retarget (agent-run; no operator step)
- [x] 3.4 Open the PR: `Closes #9097` in the body (never the title), `## Changelog` section; verify ACs against the diff

## Testing gates

- Local: `bash scripts/followthroughs/zot-soak-6122.test.sh`, `bash scripts/followthrough-exec-bit.test.sh`
- CI: `scripts/zot-soak-6122-arms` leg (test-all.sh shard leg 1) plus the rest of the battery
