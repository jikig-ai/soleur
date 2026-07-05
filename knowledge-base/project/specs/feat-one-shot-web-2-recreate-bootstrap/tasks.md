# Tasks — web-2-recreate bootstrap (`apply_target=web-2-recreate`)

Plan: `knowledge-base/project/plans/2026-07-05-feat-web-2-recreate-bootstrap-plan.md`
Lane: cross-domain · Brand threshold: single-user incident (CPO sign-off + user-impact-reviewer at review)

## Phase 0 — Preconditions (verify, no writes)
- [ ] 0.1 Re-read `warm_standby` job (`apply-web-platform-infra.yml:628-1046`); confirm `apply`/`warm_standby`/`web_2_recreate` `if:` gates are disjoint.
- [ ] 0.2 Confirm `local.host_scripts_content_hash` via `terraform console` resolves under `doppler run --name-transformer tf-var`.
- [ ] 0.3 Confirm GHCR repo is public (`docker buildx imagetools inspect <tag>` needs no auth).
- [ ] 0.4 `git grep -ln 'scope-guard\|scope_guard' tests/ scripts/` — extend any orphan scope-guard suite.
- [ ] 0.5 Read all three `.c4` files for the C4-impact enumeration.
- [ ] 0.6 Confirm `var.image_name` has no validation block rejecting `@sha256:` (spec-flow P2-4).
- [ ] 0.7 Confirm GH runner + Hetzner host both amd64 (multi-arch manifest-list digest, spec-flow P2-5 / CTO must-fix 4).
- [ ] 0.8 `gh issue list --label code-review --state open` overlap check against Files-to-Edit.

## Phase 1 — Destroy-guard extension (contract before consumer)
- [ ] 1.1 Add `web2_out_of_scope_changes` (POSITIVE scope: any create/update/delete outside the 3-address allow-set — spec-flow P0-2) + `web2_server_replaced` keys to `tests/scripts/lib/destroy-guard-filter-web-platform.jq`. Exact-equality `IN(.address; web2_allow[])` membership (NOT `inside`/substring); `["forget"]`-semantics comment; keep existing keys byte-identical.

## Phase 2 — Guard suites
- [ ] 2.1 Extract the web_2_recreate gate into a **sourced shell function** (spec-flow P1-1); `tests/scripts/test-destroy-guard-counter-web-platform.sh` calls it directly with synthesized fixtures (`tests/scripts/fixtures/tfplan-web2-recreate-*.json`): web-2 replace PASS; web-1 delete/replace FAIL; web-2-volume destroy FAIL; web-2 in-place reboot FAIL; no-op FAIL; **web-1 non-placement in-place UPDATE FAIL (P0-2)**; **substring-collision address not falsely allowed**; **`[ack-destroy]` does NOT bypass**.
- [ ] 2.2 `plugins/soleur/test/terraform-target-parity.test.ts` — add `WEB2_RECREATE_TARGETS` + AC7 assertions; handle `web_2_recreate` at BOTH `stripJob` call sites (coverage + `MOVED_OPERATOR_CONSUMED` anchor — CTO must-fix 2).
- [ ] 2.3 Extract the digest-resolution + coherence-preflight into a **standalone script** with `set -euo pipefail` + format validation; add a pre-merge test driving it with a mismatching-digest fixture asserting non-zero exit (spec-flow P1-4/P1-2, AC10b).

## Phase 3 — `web_2_recreate` workflow job
- [ ] 3.1 Add `apply_target: web-2-recreate` choice option.
- [ ] 3.2 New `web_2_recreate` job (mirror `warm_standby` scaffolding; `timeout-minutes: 30`).
- [ ] 3.3 Step: gate `.tag` read on web-1 `reason==ok && exit_code!=-1` (P2-1); resolve → `@sha256` digest ONCE, freeze `$PINNED` (AC3b TOCTOU); validate `DIGEST =~ ^sha256:[0-9a-f]{64}$`.
- [ ] 3.4 Step: call the preflight script (docker-cp baked scripts, recompute boot-identical hash, assert == `terraform console local.host_scripts_content_hash`; format-validate WANT/GOT; ABORT RED on mismatch).
- [ ] 3.5 Step: `terraform plan -replace='hcloud_server.web["web-2"]'` + 3 web-2 `-target`s + `-var=image_name=$PINNED`; run the sourced guard fn (abort unless `web2_out_of_scope_changes==0 && nested_deletes==0 && reboot_updates==0 && web2_server_replaced==1`), reading `terraform show -json` not stderr.
- [ ] 3.6 Step: apply saved plan + attach-proof; assert volume 0-destroy.
- [ ] 3.7 Step: wait + off-host verify — REUSE the shared warm_standby poll (ROSTER_COUNT==1, staleness gate, terminal exit 1 on timeout — spec-flow P1-3); do NOT re-derive.
- [ ] 3.8 Step: on failure, surface fresh-host Sentry `emit_fail` event in job summary (best-effort, may show unrelated host / may be empty) + RED.

## Phase 4 — Documentation
- [ ] 4.1 ADR-068 Amendment (2026-07-05): recreate = warm-standby prerequisite; digest-pin determinism decision; reconcile `## C4 impact`.
- [ ] 4.2 Runbook `moved-block-wedge-cutover-5887.md`: web-2-recreate step before warm-standby step 5 (lint-infra-no-human-steps-safe phrasing).
- [ ] 4.3 `model.c4`: refine `hetzner -> ghcr` edge description (digest-pin on recreate); run c4 syntax + render tests.

## Verification (exit gate)
- [ ] V1 `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`
- [ ] V2 `./node_modules/.bin/vitest run test/terraform-target-parity.test.ts`
- [ ] V3 `bash tests/scripts/test-destroy-guard-counter-web-platform.sh`
- [ ] V4 `bash scripts/lint-infra-no-human-steps.test.sh` + lint the runbook file
- [ ] V5 `bash scripts/test-all.sh` — read N/N suites-passed summary (not just exit code)
