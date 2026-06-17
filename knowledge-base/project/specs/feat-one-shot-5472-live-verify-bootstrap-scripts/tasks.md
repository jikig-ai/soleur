---
title: "Tasks — fix(live-verify): bootstrap scripts non-functional (#5472)"
date: 2026-06-17
issue: "#5472"
branch: feat-one-shot-5472-live-verify-bootstrap-scripts
lane: single-domain
plan: knowledge-base/project/plans/2026-06-17-fix-live-verify-bootstrap-scripts-plan.md
---

# Tasks — live-verify bootstrap script fix (#5472)

Derived from the finalized (post-review) plan. Three independent shell defects across
three files in `apps/web-platform/scripts/`. No new infra, no schema change, no UI.

## Phase 1 — Defect 1: repo_status literal (RED → GREEN)

- [x] 1.1 **RED** — add a static-source assertion block to
  `apps/web-platform/scripts/seed-live-verify-user.test.sh` (after case 4, before the
  final `fail` gate): assert the `tc_accepted_version`-bearing `public.users` PATCH line
  carries `repo_status: "ready"` (target that line specifically so it does not match the
  workspaces PATCH at `:204`), and assert `repo_status: "connected"` appears nowhere in
  the seed. Confirm it FAILS against the unfixed seed.
- [x] 1.2 **GREEN** — in `apps/web-platform/scripts/seed-live-verify-user.sh`: change the
  `public.users` PATCH body (`:182`) `repo_status: "connected"` → `"ready"`; update the
  header comment (`:23`) `repo_status=connected` → `repo_status=ready`.
- [x] 1.3 Run `bash apps/web-platform/scripts/seed-live-verify-user.test.sh` → `PASSED`.

## Phase 2 — Defect 2/3: bootstrap terraform invocation

- [x] 2.1 Rework `apps/web-platform/scripts/bootstrap-live-verify.sh` Step 1 (`:40-44`) to
  the canonical Doppler+Terraform triplet:
  - export **bare** `AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY` via
    `doppler secrets get … --plain -p soleur -c prd_terraform` **before** the wrapper, with
    an emptiness guard;
  - `terraform -chdir="$INFRA" init -input=false -lockfile=readonly` (parity with the
    workflow);
  - run `terraform apply -target=…` under
    `doppler run -p soleur -c prd_terraform --name-transformer tf-var`.
  Mirror `apply-web-platform-infra.yml:213-264`. Quote all expansions.
- [x] 2.2 Keep Step 2 (`:46-47`) under `doppler run -p soleur -c prd -- bash "$SEED"`;
  keep the top-level `DOPPLER_CONFIG != "prd"` refusal guard.
- [x] 2.3 Update the bootstrap header Steps comment block (`:12-20`) to reflect the
  dual-config invocation (Step 1 → prd_terraform + tf-var + bare R2 creds; Step 2 → prd).
- [x] 2.4 Do NOT add the nested `--token` doppler form (YAGNI — local personal-token runs
  don't have the CI service-token collision).

## Phase 3 — Verify

- [x] 3.1 `bash apps/web-platform/scripts/seed-live-verify-user.test.sh` → PASSED.
- [x] 3.2 `TEST_GROUP=scripts bash scripts/test-all.sh` → all green (seed test discovered
  by `scripts/test-all.sh:183` glob; no orphan-suite regression; prod-guard cases 1–4 pass).
- [x] 3.3 `shellcheck apps/web-platform/scripts/bootstrap-live-verify.sh apps/web-platform/scripts/seed-live-verify-user.sh`
  (if available) → no new findings.
- [x] 3.4 `grep -rl "bootstrap-live-verify\|seed-live-verify" .github/workflows/` → zero
  (negative AC; scripts stay agent-run-local-only, security P0-1).

## Out of scope / non-goals

- No `.tf` resource changes — the `random_password` + `doppler_secret` resources in
  `infra/live-verify.tf` are correct; only the script that invokes them is fixed.
- No live re-run at merge (PROD already provisioned by hand); the next genuine
  bootstrap/rotation run is the live exercise. Validated in-PR by the static test +
  canonical-triplet parity.
