---
title: "fix(live-verify): make bootstrap scripts functional (repo_status literal + terraform Doppler config/transformer/R2 creds)"
date: 2026-06-17
type: fix
issue: "#5472"
branch: feat-one-shot-5472-live-verify-bootstrap-scripts
lane: single-domain
status: ready
brand_survival_threshold: none
---

# fix(live-verify): make the bootstrap scripts functional as-written 🐛

## Enhancement Summary

**Deepened on:** 2026-06-17

**Gates run (all PASS):** 4.4 precedent-diff (added a Precedent Diff section), 4.45
round-1 realism (verify-the-negative + 7-check citation re-grep, all confirmed), 4.5
network-outage (skip — the only `ssh` token is the literal "NO ssh" discoverability
note; the apply drives `random_password`/`doppler_secret`, no SSH provisioner), 4.6
User-Brand Impact (present, threshold `none` + reason), 4.7 Observability (present),
4.8 PAT-shaped variable (none), 4.9 UI-wireframe (skip — no UI surface).

### Key improvements over the plan-skill output
1. **Precedent diff** added — side-by-side against `apply-web-platform-infra.yml`
   (the canonical prd_terraform+tf-var+R2 invocation) with line citations, plus the
   one intentional divergence (single `-target` apply vs saved `tfplan`).
2. **Citation accuracy** — the realism pass re-grepped every file:line claim. One
   correction: the bootstrap header Steps block is `:12-17` (was `:12-20`); fixed in
   AC5 + Files-to-Edit.
3. **Confirmed all 7 load-bearing facts** live: defect-1 line (`:182`), constraint
   (`011:10`), current bootstrap shape (no transformer/no AWS export), precedent step
   lines, test-runner glob (`test-all.sh:183`), negative-AC zero, and the two
   `live-verify.tf` resources (`:19`/`:24`).

### New considerations discovered
- None that change scope. The fix remains a one-literal swap + a Step-1 rework
  mirroring an existing working workflow + one test assertion. The plan-review +
  deepen passes converged on the same minimal shape.

## Overview

The live-verification harness (#5452/#5453) shipped two committed bootstrap shell
scripts that **do not run unattended as written**. PROD is already provisioned by
hand, but the committed scripts must work on the next run / leak-rotation. Three
independent defects, all discovered running the bootstrap manually:

1. **Wrong `repo_status` literal** in `apps/web-platform/scripts/seed-live-verify-user.sh`.
   The ladder PATCHes `public.users` with `repo_status: "connected"` (copied from
   `seed-dev-users.sh`), but the `users` `CHECK` constraint
   (`apps/web-platform/supabase/migrations/011_repo_connection.sql:10`) admits only
   `('not_connected', 'cloning', 'ready', 'error')`. `"connected"` → PostgREST
   returns **23514** (check-constraint violation) and the seed aborts. The
   rail-tested precedent `seed-qa-user.sh:83` uses `"ready"`. Fix: `"connected"` →
   `"ready"` (the workspaces PATCH at `:204` already correctly uses `"ready"`).

2. **Wrong Doppler config for the terraform step** in
   `apps/web-platform/scripts/bootstrap-live-verify.sh`. Step 1 runs
   `terraform -chdir=apps/web-platform/infra apply` under the launching
   `doppler run -c prd` env. The infra root authenticates via **`prd_terraform`**
   (`var.doppler_token_tf`, `betterstack_api_token`, `github_app_id`,
   `github_app_private_key`, ~12 `TF_VAR_*` inputs). Under `-c prd` the apply fails
   immediately with `No value for required variable` for those. Fix: run the
   terraform step under `-c prd_terraform`; keep the seed under `-c prd`.

3. **Missing `tf-var` transformer + R2 backend creds** in the same terraform step.
   The infra apply needs (a) `doppler run --name-transformer tf-var` so
   `prd_terraform` secrets inject as `TF_VAR_*`, AND (b) **raw**
   `AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY` for the Cloudflare-R2 S3 backend.
   The transformer rewrites those to `TF_VAR_aws_*`, so without the raw exports the
   backend falls back to the local AWS SSO profile and fails. `variables.tf:1-13`
   documents this exact gotcha.

The fix is a small follow-up PR: one literal swap (defect 1, plus a documentation
comment), a rework of `bootstrap-live-verify.sh` Step 1 (defects 2/3), and one new
assertion in the existing `seed-live-verify-user.test.sh` locking defect 1.

## Research Reconciliation — Spec vs. Codebase

| Claim (issue body) | Reality (verified) | Plan response |
|---|---|---|
| `seed-live-verify-user.test.sh` must be **added** | The test file **already exists** (`apps/web-platform/scripts/seed-live-verify-user.test.sh`, 113 lines, AC8 refusal-path coverage). | Plan **adds an assertion** to the existing file, not a new file. |
| Fix the `repo_status` literal (singular) | Two occurrences: code at `:182` (the bug) **and** the header comment at `:23` (`repo_status=connected`). | Fix both — the comment is a documentation lie if left. |
| `terraform apply` under `prd` fails on required vars | Confirmed: infra root reads `betterstack_api_token`, `github_app_id`, `github_app_private_key`, `doppler_token_tf` + ~12 `TF_VAR_*` from `prd_terraform`; `variables.tf:1-13` documents the nesting. | Rework Step 1 per the canonical triplet. |
| Mirror `apply-web-platform-infra.yml`'s "Extract backend credentials" step | Confirmed at `.github/workflows/apply-web-platform-infra.yml:213-235` (`doppler secrets get AWS_ACCESS_KEY_ID --plain` under `DOPPLER_CONFIG: prd_terraform`, exported bare) → `:264`/`:399` run terraform under `doppler run -c prd_terraform --name-transformer tf-var`. | Mirror exactly: bare AWS exports + transformer wrapper. |

## User-Brand Impact

**If this lands broken, the user experiences:** No direct end-user impact. The
target user is the operator/agent running the live-verify bootstrap; a broken
bootstrap means the post-deploy verification harness (#5453) cannot provision its
synthetic prod principal on the next run/rotation, so the live-verify gate stays
dark and a realtime/server-commit-timing regression (the #5391/#5421/#5436 class)
could reach production unverified.

**If this leaks, the user's data is exposed via:** N/A — the scripts already enforce
the triple-defense prod-write guard (DOPPLER_CONFIG=prd, service_role JWT, ref
match) and never echo secrets. This PR does not weaken any of those guards; it only
corrects an invalid enum literal and the terraform invocation env. The synthetic
principal is a dedicated `live-verify@soleur.ai` user with zero `scope_grants`
(WORM-write-free by construction).

**Brand-survival threshold:** none, reason: this is a non-user-facing operator
tooling fix on already-provisioned infra; it corrects scripts that abort loudly
(23514 / `No value for required variable`) rather than failing silently, and the
prod-write safety guards are untouched.

## Acceptance Criteria

_(Trimmed per plan-review consensus: AC list collapsed to the distinct post-condition
gates. The AWS-ordering ordering constraint, prod-guard non-regression, and shellcheck
are covered by AC3 + the standard suite gate rather than separate checkboxes.)_

### Pre-merge (PR)

- [x] **AC1 (defect 1):** in `apps/web-platform/scripts/seed-live-verify-user.sh` the
      `public.users` PATCH body sets `repo_status: "ready"` (not `"connected"`), AND the
      header-comment ladder description (`:23`) says `repo_status=ready`. Verify:
      `grep -c 'repo_status: "connected"' apps/web-platform/scripts/seed-live-verify-user.sh`
      returns `0` AND
      `grep -c 'repo_status=connected' apps/web-platform/scripts/seed-live-verify-user.sh`
      returns `0`. (The `public.users` PATCH is the line carrying `tc_accepted_version`;
      the workspaces PATCH at `:204` already correctly uses `repo_status: "ready"` and is
      untouched.)
- [x] **AC2 (defect 1, test — RED→GREEN):** `seed-live-verify-user.test.sh` gains a
      static-source assertion that (a) the `tc_accepted_version`-bearing `public.users`
      PATCH line carries `repo_status: "ready"`, and (b) the forbidden literal
      `repo_status: "connected"` appears nowhere in the seed. Confirmed failing (red)
      against the unfixed seed, passing (green) after AC1. Verify:
      `bash apps/web-platform/scripts/seed-live-verify-user.test.sh` prints
      `seed-live-verify-user.test.sh: PASSED`.
- [x] **AC3 (defect 2/3 — terraform invocation):** `bootstrap-live-verify.sh` Step 1
      exports **bare** `AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY` (via
      `doppler secrets get … -p soleur -c prd_terraform --plain`) **before** the wrapper,
      then runs `terraform init` and `terraform apply` under
      `doppler run -p soleur -c prd_terraform --name-transformer tf-var`. The two
      `AWS_*` exports MUST precede (be outside) the transformer wrapper — otherwise the
      transformer rewrites them to `TF_VAR_aws_*` and the R2 backend SSO-fallback-fails.
      Verify: `grep -n 'name-transformer tf-var' apps/web-platform/scripts/bootstrap-live-verify.sh`
      shows the apply wrapper, and reading the script confirms the `AWS_*` gets precede it.
- [x] **AC4 (seed step + guard preserved):** Step 2 still runs the seed under
      `doppler run -p soleur -c prd -- bash "$SEED"` (the seed reads `SUPABASE_*` +
      `LIVE_VERIFY_USER_PASSWORD` from `prd` and hard-refuses unless DOPPLER_CONFIG=prd),
      and the bootstrap's top-level `DOPPLER_CONFIG != "prd"` refusal guard is intact.
      Verify: `grep -n 'doppler run -p soleur -c prd -- bash' apps/web-platform/scripts/bootstrap-live-verify.sh`
      and `grep -n 'DOPPLER_CONFIG' apps/web-platform/scripts/bootstrap-live-verify.sh`.
- [x] **AC5 (bootstrap header truthful):** the `bootstrap-live-verify.sh` header Steps
      comment block (`:12-17`) reflects the dual-config invocation (Step 1 →
      `prd_terraform` + tf-var + bare R2 creds; Step 2 → `prd`). Verify by reading the
      header: it no longer implies a single-config flow.
- [x] **AC6 (negative AC — no CI wiring):** the scripts remain agent-run-local-only.
      Verify: `grep -rl "bootstrap-live-verify\|seed-live-verify" .github/workflows/`
      returns **zero** matches (exit 1).
- [x] **AC7 (full scripts suite green):** `TEST_GROUP=scripts bash scripts/test-all.sh`
      passes — confirms the seed test is discovered (`scripts/test-all.sh:183` globs
      `apps/web-platform/scripts/*.test.sh`) and no orphan `.test.sh` suite regressed,
      and subsumes the seed's prod-write-guard cases 1–4. Run `shellcheck` on both
      edited scripts if available; the reworked Step 1 must quote all expansions.

### Post-merge (operator)

None. PROD is already provisioned by hand, so no apply is required at merge — the fix
is validated in-PR by the static test (AC2) + canonical-triplet parity against the
working `apply-web-platform-infra.yml` (AC3). The next genuine bootstrap / leak-rotation
run is the live exercise. `Automation: not feasible to dry-run because the terraform
target writes the live random_password + Doppler prd secret; re-running it would rotate
the live synthetic principal's password for no reason.`

## Implementation Phases

### Phase 1 — Defect 1: repo_status literal (RED → GREEN)

1. **RED:** add a new assertion block to `apps/web-platform/scripts/seed-live-verify-user.test.sh`
   (after the existing case 4 / before the final `fail` gate). Static-source check —
   no curl, runs offline like the existing AC8 checks:
   - assert the **`public.users`** PATCH carries `repo_status: "ready"`. Target the
     `tc_accepted_version`-bearing object line specifically (e.g.
     `grep -E 'tc_accepted_version.*repo_status: "ready"'`) so the assertion does NOT
     conflate with the workspaces PATCH at `:204`, which legitimately also carries
     `repo_status: "ready"` (Kieran review: a bare `repo_status: "ready"` grep matches
     both lines post-fix);
   - assert `repo_status: "connected"` appears **nowhere** in the seed (the forbidden
     literal that 23514s against the `users` constraint).
   Confirm it FAILS against the current unfixed seed.
2. **GREEN:** in `seed-live-verify-user.sh`, change the `public.users` PATCH body
   (`:182`) `repo_status: "connected"` → `repo_status: "ready"`. Update the header
   comment (`:23`) `repo_status=connected` → `repo_status=ready`. Re-run the test —
   green.
3. Run `bash apps/web-platform/scripts/seed-live-verify-user.test.sh` → `PASSED`.

### Phase 2 — Defect 2/3: bootstrap terraform invocation

Rework `bootstrap-live-verify.sh` Step 1 (`:40-44`) to the canonical Doppler+Terraform
triplet (mirrors `apply-web-platform-infra.yml:213-264` and the learning at
`knowledge-base/project/learnings/2026-05-09-drift-runbook-canonical-tf-invocation-and-fresh-plan.md`).

Target shape (illustrative — implementer finalizes quoting):

```bash
echo "==> Step 1: terraform apply (-target the two live-verify resources)"

# R2/S3 backend reads creds during `terraform init`, BEFORE any provider/var
# evaluates. They must be RAW AWS_* — the --name-transformer tf-var wrapper below
# rewrites them to TF_VAR_aws_* (which the backend ignores), so export them
# outside the wrapper. Mirrors apply-web-platform-infra.yml "Extract backend
# credentials" + variables.tf:1-13.
AWS_ACCESS_KEY_ID=$(doppler secrets get AWS_ACCESS_KEY_ID --plain -p soleur -c prd_terraform)
AWS_SECRET_ACCESS_KEY=$(doppler secrets get AWS_SECRET_ACCESS_KEY --plain -p soleur -c prd_terraform)
export AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY
if [[ -z "$AWS_ACCESS_KEY_ID" || -z "$AWS_SECRET_ACCESS_KEY" ]]; then
  echo "::error::R2 backend creds empty in Doppler prd_terraform" >&2
  exit 1
fi

# -lockfile=readonly for parity with apply-web-platform-infra.yml:244 (refuses an
# unpinned provider download; defends against malicious republish).
terraform -chdir="$INFRA" init -input=false -lockfile=readonly >/dev/null

# prd_terraform carries the ~12 TF_VAR_* inputs (betterstack/github-app/doppler_token_tf);
# --name-transformer tf-var renames them so terraform sees TF_VAR_*. The bare AWS_*
# exported above survive into this child env for the backend.
doppler run -p soleur -c prd_terraform --name-transformer tf-var -- \
  terraform -chdir="$INFRA" apply -input=false -auto-approve \
    -target=random_password.live_verify_user \
    -target=doppler_secret.live_verify_user_password
```

- Keep Step 2 (the seed) under `doppler run -p soleur -c prd -- bash "$SEED"` —
  unchanged. The seed reads `SUPABASE_*` + `LIVE_VERIFY_USER_PASSWORD` from `prd`.
- Keep the top-level `DOPPLER_CONFIG != "prd"` refusal guard — the launching env is
  prd (for the seed); the terraform step nests its own `prd_terraform`.
- Update the script header comment block to reflect the dual-config invocation
  (Step 1 → prd_terraform, Step 2 → prd) so the doc matches the code.

**Note on the `--token` nesting (YAGNI):** the single-level `doppler run -c
prd_terraform --name-transformer tf-var` form is correct for local personal-token runs
(no `DOPPLER_TOKEN` service-token set). The nested `--token` form in `variables.tf:3-13`
exists only to dodge a CI service-token collision; do not add it pre-emptively. (Kieran +
DHH review both confirmed this is the right call.)

### Phase 3 — Verify

1. `bash apps/web-platform/scripts/seed-live-verify-user.test.sh` → PASSED.
2. `TEST_GROUP=scripts bash scripts/test-all.sh` → all green (no orphan-suite regress).
3. `shellcheck` both scripts if available; confirm no new findings.
4. `grep -rl "bootstrap-live-verify\|seed-live-verify" .github/workflows/` → zero.

## Files to Edit

- `apps/web-platform/scripts/seed-live-verify-user.sh` — `repo_status: "connected"` →
  `"ready"` at `:182` (code) and `:23` (header comment).
- `apps/web-platform/scripts/bootstrap-live-verify.sh` — rework Step 1 (`:40-44`) to the
  canonical triplet (bare AWS exports from `prd_terraform` + `--name-transformer tf-var`
  apply wrapper); update the header Steps comment block (`:12-17`) to reflect the
  dual-config invocation (Step 1 → prd_terraform, Step 2 → prd); keep Step 2 under `-c prd`.
- `apps/web-platform/scripts/seed-live-verify-user.test.sh` — add the
  `repo_status: "ready"` assertion (and forbidden-literal check) after case 4.

## Files to Create

None.

## Open Code-Review Overlap

None. (`gh issue list --label code-review --state open` checked against the three
edited paths — no open scope-out touches `seed-live-verify-user.sh`,
`bootstrap-live-verify.sh`, or their test.)

## Observability

Local-only one-shot script — no server-side surface, no remote sink by design
(security P0-1: prod service-role + terraform apply stay off GitHub Actions). Both
scripts run `set -euo pipefail` and fail loud to the operator terminal via `::error::`
annotations + non-zero exit. The three pre-fix failure modes all abort loudly at the
keyboard: defect 1 → PostgREST `23514` and the seed aborts; defect 2 → `No value for
required variable` and terraform aborts at Step 1; defect 3 → R2 backend `No valid
credential sources found` at `terraform init`. There is no persisted log (transient
stdout/stderr). Discoverability (NO ssh): `bash
apps/web-platform/scripts/seed-live-verify-user.test.sh` → `seed-live-verify-user.test.sh:
PASSED`, plus the negative-AC `grep -rl "bootstrap-live-verify\|seed-live-verify"
.github/workflows/` → zero.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — infrastructure/tooling bug fix on
already-provisioned infra. No user-facing surface, no schema/migration change, no
new dependency, no new vendor or runtime process. (Engineering/Infra concern is the
terraform invocation, addressed inline by mirroring the canonical workflow step;
no IaC *change* — the `.tf` resources are unchanged, only the script that invokes
them.)

## Precedent Diff (deepen-plan Phase 4.4)

The terraform invocation is a **pattern-bound behavior** with a canonical sibling
precedent in-repo. Verified side-by-side (all line numbers confirmed live by the
realism pass):

| Aspect | Precedent (`apply-web-platform-infra.yml`) | This plan (`bootstrap-live-verify.sh`) |
|---|---|---|
| Bare AWS creds | `:213-235` — `doppler secrets get AWS_ACCESS_KEY_ID --plain` under `DOPPLER_CONFIG: prd_terraform`, exported to `$GITHUB_ENV` (bare, outside the wrapper) | `export AWS_*=$(doppler secrets get … -c prd_terraform --plain)` before the wrapper |
| init | `:244` — `terraform init -input=false -lockfile=readonly` | `terraform init -input=false -lockfile=readonly` (parity adopted) |
| apply | `:399-400` — `doppler run -p soleur -c prd_terraform --name-transformer tf-var -- terraform apply` | identical wrapper, `-target`ed to the two live-verify resources |

The plan mirrors the precedent exactly. The one intentional divergence: the precedent
uses a saved `tfplan` (plan-then-apply for the destructive-change guard); the bootstrap
does a single `apply -target=… -auto-approve` because it is a tiny, non-destructive,
operator-acknowledged two-resource apply on already-provisioned infra (no guard needed —
the `-target` set is the scope guard). The seed step (`-c prd`) has no infra-side
precedent; it is the existing `seed-dev-users.sh`/`seed-qa-user.sh` prod-write pattern.

## Risks & Mitigations

- **Risk:** the reworked Step 1 quoting/expansion is subtly wrong and breaks the
  apply in a new way. **Mitigation:** mirror the *exact* working pattern from
  `apply-web-platform-infra.yml:213-264` and the runbook learning triplet;
  shellcheck both scripts (AC7).
- **Risk:** `prd_terraform` vs `prd` config confusion recurs.
  **Mitigation:** the dual-config split is the whole point of the fix — Step 1
  prd_terraform (infra creds), Step 2 prd (Supabase + password). AC3/AC4 lock each.
  See `knowledge-base/project/learnings/2026-03-29-doppler-service-token-config-scope-mismatch.md`
  (service tokens are scoped to one config; the `-c` flag works for the *personal*
  CLI token used in local agent runs).
- **Risk:** AWS creds exported inside the transformer wrapper (the original-bug
  shape). **Mitigation:** AC3 explicitly asserts the exports precede the wrapper;
  precedent `knowledge-base/project/learnings/integration-issues/2026-04-05-terraform-doppler-dual-credential-pattern.md`
  documents why (`--name-transformer tf-var` rewrites `AWS_*` → `TF_VAR_aws_*`,
  which the S3/R2 backend ignores → SSO fallback → auth failure).

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only TBD/TODO, or
  omits the threshold will fail `deepen-plan` Phase 4.6. (This plan declares
  `threshold: none` with a reason — satisfied.)
- The `--name-transformer tf-var` flag and the **bare** AWS exports are BOTH
  load-bearing and easy to drop independently. Dropping the transformer → `No value
  for required variable`; dropping the bare exports (or putting them inside the
  wrapper) → R2 backend auth failure. Both halves are locked by AC3.
- The test addition is a **static-source** check (greps the script text), not a
  live curl — the seed's write paths require prod service-role creds and must never
  run in CI (`hr-dev-prd-distinct-supabase-projects`). The 23514 is locked by
  asserting the literal in source, exactly as the existing AC8 secret-discipline
  checks do.
