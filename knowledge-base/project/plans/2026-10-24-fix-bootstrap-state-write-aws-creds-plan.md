---
title: "fix: two bootstrap scripts export read-only prd_terraform AWS_* then terraform apply — state push 403s"
type: fix
date: 2026-10-24
slug: fix-bootstrap-state-write-aws-creds
branch: feat-one-shot-10990-bootstrap-aws-creds
issue: 10990
closes: 10990
domain: engineering
brand_survival_threshold: none
reviewed_coverage: sequential-fallback
---

# fix: two bootstrap scripts export read-only prd_terraform AWS_* then terraform apply — state push 403s

## Overview

After the O5b credential-tier cutover (#8209, ADR-241) moved the state-bucket
read/write R2 keypair into `soleur-infra-privileged/prd` as `TF_STATE_AWS_*`,
the `AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY` pair left in
`soleur/prd_terraform` was deliberately demoted to read-only. Two executable
bootstrap scripts still export that read-only pair and then run a state-WRITING
`terraform apply`, so the apply dies on the S3 `PutObject` 403 mid-run and can
leave `errored.tfstate` behind. #10979 fixed the fourteen prose sites and
descoped the two armed scripts to this issue because executable sites need the
code-change path (test coverage), not a docs edit.

This plan repoints both scripts' backend-credential leg at the canonical Tier-B
pair — `TF_STATE_AWS_ACCESS_KEY_ID`/`TF_STATE_AWS_SECRET_ACCESS_KEY` from
`soleur-infra-privileged/prd`, exported as bare `AWS_*` — per the recipe the
runbook now prescribes
(`knowledge-base/engineering/operations/runbooks/infra-credential-tiers-8209.md`
§Local Terraform invocation), adds a census limb so no future script can
re-arm the same defect, and fixes one stale prescribing reference
(`plugins/soleur/skills/plan/references/plan-sharp-edges.md`) that still tells
every future drift-remediation plan to export the read-only pair before
`terraform apply`.

## Problem Statement / Motivation

- `apps/cla-evidence/infra/bootstrap.sh` (post-merge CLA-evidence bootstrap)
  exports `STATE_KEY`/`STATE_SEC` from `doppler secrets get AWS_* -p soleur -c
  prd_terraform` then runs `terraform apply -auto-approve` against a state
  backend (`soleur-terraform-state` bucket, `apps/cla-evidence/infra/main.tf`
  `backend "s3"` block) the pair can no longer write.
- `apps/web-platform/scripts/bootstrap-live-verify.sh` (the documented
  leak-rotation re-run path, per its own header) exports the same read-only
  pair and runs `terraform apply -auto-approve -target=...` against
  `apps/web-platform/infra`. A security-rotation re-run would hit the mid-apply
  failure at the worst possible time — the issue text calls this out as a
  triage-escalation candidate.

The defect is invisible to every read path: `plan`/`init`/`state pull` work
fine on the read-only pair, which is why the drift survived the O5b cutover
undetected (learning
`knowledge-base/project/learnings/2026-10-24-credential-tier-cutover-invalidates-recipes-asymmetrically.md`).

## Research Reconciliation — Spec vs. Codebase

| Issue/spec claim | Codebase reality | Plan response |
|---|---|---|
| `bootstrap.sh:127-141` exports the read-only pair then applies | Holds — `STATE_KEY`/`STATE_SEC` read `AWS_*` from `soleur/prd_terraform`; `tf_env terraform apply -auto-approve` runs under them | Edit per Proposed Solution |
| `bootstrap-live-verify.sh:62-70` export + `:84-87` apply | Holds — two `doppler secrets get AWS_* -p soleur -c prd_terraform` legs feed `doppler run -c prd_terraform --name-transformer tf-var -- terraform ... apply` | Edit per Proposed Solution |
| Backend creds must come from `soleur-infra-privileged/prd` `TF_STATE_AWS_*` | Holds — `doppler secrets -p soleur-infra-privileged -c prd --only-names` lists both names (measured 2026-10-24); `infra-credentials` action aliases them onto `AWS_*` for CI; runbook §Local Terraform invocation prescribes the export form | Canonical fix applied |
| Workflows mirror the same recipe | Partially — apply workflows still contain `doppler secrets get AWS_* -p soleur -c prd_terraform` strings but only as the documented legacy-fallback arm inside `./.github/actions/infra-credentials` jobs, gated by AC7b limbs of `tests/scripts/test-infra-privileged-tier-census.sh` | No workflow edit needed; the gap is `.sh` writers outside that census's assembly |
| Only two armed sites | Confirmed by sweep — `git grep`-style scan of every tracked `*.sh` combining an `AWS_*` reference with a state-writing terraform invocation returns exactly these two files | Sweep evidence in Research Insights; census limb makes the zero a maintained invariant |

## Research Insights

**Premise validation (Phase 0.6).** Issue #10990 is OPEN (`type/bug`,
`domain/engineering`, milestone `Post-MVP / Later`; the issue itself notes the
leak-rotation angle may warrant promotion). Cited paths all exist at the cited
anchors on this branch. Cited runbook section exists
(`infra-credential-tiers-8209.md` §Local Terraform invocation) and prescribes
exactly the fix the issue names. The cited ADR corpus entry is ADR-241
(`knowledge-base/engineering/architecture/decisions/ADR-241-terraform-credentials-are-tiered-main-only-environment-secrets.md`)
— the plan conforms to it, does not diverge. Cited mechanism (the
`TF_STATE_AWS_*` pair) verified to exist via `doppler secrets
--only-names` — measured, not assumed. #10979 (the surfacing issue) is closed
by its merged PR; the spec archive
`knowledge-base/project/specs/archive/20261024-132648-feat-one-shot-10979-runbook-cred-drift/`
records the descope decision for these two files.

**Property list (Phase 0.6b).**

- P1: a state-writing terraform invocation must never execute with the
  read-only `prd_terraform` `AWS_*` pair in its environment.
- P2: the failure mode, if the credential leg breaks again, must be detected
  by CI before an operator re-run — not discovered mid-apply during a leak
  rotation.
- P3: prescribing surfaces (skill reference files) must not instruct a future
  plan to reproduce the defect.

**Cut list (Phase 0.6b).** No mechanism in the ask is cut — the issue proposes
the credential-source edit (buys P1) and test coverage (buys P2). No new
mechanism invented by this plan beyond the census limb, which is the cheapest
existing mechanism for P2: `test-infra-privileged-tier-census.sh` already
asserts the workflow-side twin of this property (AC7b), already owns the
fixture/mutation machinery, and is already registered in `scripts/test-all.sh`
with `apps/` in its affected-paths edge set — a new standalone suite would
duplicate that machinery and add registration plumbing for zero new property.
Checked: no shared helper exports the Tier-B backend pair for local scripts
(`grep -rln TF_STATE_AWS` over `scripts/`, `tests/scripts/lib/` — the only
producer is the CI-only `.github/actions/infra-credentials` action, which
writes `$GITHUB_ENV` and cannot be reused locally).

**Value-proposition measurement (Phase 0.6c).** Not fired — the justification
is correctness/security, not a cost or performance saving.

**Relevant files.**

- `apps/cla-evidence/infra/bootstrap.sh:117-140` — cred leg + `tf_env` helper +
  apply call.
- `apps/web-platform/scripts/bootstrap-live-verify.sh:43-87` — cred leg,
  comments naming the stale mirror, `init`, and the `-target` apply.
- `apps/web-platform/scripts/bootstrap-live-verify.sh:11-19` — header contract
  describing the two Doppler-config steps; must be updated with the code.
- `apps/web-platform/infra/main.tf:1-15` and `apps/cla-evidence/infra/main.tf:1-13`
  — both `backend "s3"` blocks target bucket `soleur-terraform-state` (the
  bucket `TF_STATE_AWS_*` is scoped to write).
- `apps/web-platform/infra/main.tf:86-88` — `provider "doppler"` authenticates
  with `var.doppler_token_tf`; `soleur-infra-privileged/prd` carries
  `DOPPLER_TOKEN_TF` (verified via `--only-names`), which is why the canonical
  nested-loader form (below) is adopted for the live-verify apply leg.
- `tests/scripts/test-infra-privileged-tier-census.sh` — host suite for the
  new limb; its header already claims AC7b ("the state-bucket writers are Tier
  B, and their backend credentials come from `TF_STATE_AWS_*` first") while
  its assembly covers only `.github/workflows`, `.github/actions` and `*.tf` —
  local `.sh` writers are the uncovered member class this issue exposes.
- `plugins/soleur/skills/plan/references/plan-sharp-edges.md:140` — prescribes
  `export AWS_* from prd_terraform` + `terraform <plan|apply>`; stale for the
  `apply` arm post-O5b.
- Canonical recipe: `knowledge-base/engineering/operations/runbooks/infra-credential-tiers-8209.md`
  §Local Terraform invocation (ambient `export AWS_*` from `TF_STATE_AWS_*`,
  then nested `doppler run` loaders with the inner `--preserve-env`).

**Learnings applied.**

- `2026-10-24-credential-tier-cutover-invalidates-recipes-asymmetrically.md` —
  the sweep keyed on the credential *source* name, prose-vs-executable
  classification, and the read/write asymmetry all come from this file; the
  two scripts were descoped to this issue by name.
- `2026-10-19-doppler-branch-config-does-not-inherit-new-keys...` — verified
  `soleur-infra-privileged/prd` contents with `--only-names` (measurement,
  not prose trust).
- Sharp edge (`plan-sharp-edges.md:280`) — every prescribed command was run
  once at plan time where it is read-only (see each command's provenance note).

**Open Code-Review Overlap:** None — `gh issue list --label code-review
--state open` bodies contain neither `apps/cla-evidence/infra/bootstrap.sh`
nor `apps/web-platform/scripts/bootstrap-live-verify.sh` (checked 2026-10-24).

## Proposed Solution

**Edit 1 — `apps/cla-evidence/infra/bootstrap.sh`** (cred leg only; the
script builds `tf_env` by hand and does not use `doppler run` loaders, so no
nested-loader change applies):

```bash
# State-backend creds: the soleur-terraform-state R2 bucket's READ/WRITE pair
# lives in Tier B (soleur-infra-privileged/prd) as TF_STATE_AWS_* — the
# prd_terraform AWS_* pair is read-only since O5b (#8209/ADR-241) and 403s the
# apply's state PutObject. All-or-none: a half-set pair authenticates as nobody.
STATE_KEY=$(doppler secrets get TF_STATE_AWS_ACCESS_KEY_ID    -p soleur-infra-privileged -c prd --plain) \
  || { red "TF_STATE_AWS_ACCESS_KEY_ID unreadable in soleur-infra-privileged/prd"; exit 1; }
STATE_SEC=$(doppler secrets get TF_STATE_AWS_SECRET_ACCESS_KEY -p soleur-infra-privileged -c prd --plain) \
  || { red "TF_STATE_AWS_SECRET_ACCESS_KEY unreadable in soleur-infra-privileged/prd"; exit 1; }
```

keep the existing `tf_env` export shape (`AWS_ACCESS_KEY_ID="$STATE_KEY"` etc.
unchanged), and keep the `CF_ACCOUNT_ID` read on `prd_terraform` — it is a
config value, not a credential tier, and `soleur-infra-privileged` does not
carry it (verified via `--only-names`).

**Edit 2 — `apps/web-platform/scripts/bootstrap-live-verify.sh`**: same source
swap for the two `doppler secrets get` legs (naming `TF_STATE_AWS_*` /
`soleur-infra-privileged/prd` in both the calls and the `::error::` messages),
plus the canonical nested-loader form for the apply leg — the runbook's
prescribed local invocation, and materially protective here because the apply
writes `doppler_secret.live_verify_user_password` through `provider "doppler"`
= `var.doppler_token_tf`, a name Tier B carries and Tier A (`prd_terraform`,
writable by `DOPPLER_TOKEN_WRITE` until O11) can have planted:

```bash
export AWS_ACCESS_KEY_ID=$(doppler secrets get TF_STATE_AWS_ACCESS_KEY_ID -p soleur-infra-privileged -c prd --plain) || {
  echo "::error::Failed to read TF_STATE_AWS_ACCESS_KEY_ID from Doppler soleur-infra-privileged/prd (R2 backend write cred)" >&2
  exit 1
}
export AWS_SECRET_ACCESS_KEY=$(doppler secrets get TF_STATE_AWS_SECRET_ACCESS_KEY -p soleur-infra-privileged -c prd --plain) || {
  echo "::error::Failed to read TF_STATE_AWS_SECRET_ACCESS_KEY from Doppler soleur-infra-privileged/prd (R2 backend write cred)" >&2
  exit 1
}
# (existing empty check retained)

terraform -chdir="$INFRA" init -input=false -lockfile=readonly >/dev/null   # unchanged — init reads only the backend leg

doppler run -p soleur-infra-privileged -c prd --name-transformer tf-var -- \
  doppler run -p soleur -c prd_terraform --name-transformer tf-var --preserve-env -- \
  terraform -chdir="$INFRA" apply -input=false -auto-approve \
    -target=random_password.live_verify_user \
    -target=doppler_secret.live_verify_user_password
```

The inner `--preserve-env` is load-bearing per the runbook: without it the
inner loader would overwrite the outer Tier-B `TF_VAR_*` values with
`prd_terraform`'s plantable copies. Update the surrounding comment block and
the header's step-1 description (`:11-12`) to name the Tier-B source and the
nested loader; the "Mirrors apply-web-platform-infra.yml" sentence stays true
(the workflow's loader aliases `TF_STATE_AWS_*` onto `AWS_*` in
`infra-credentials/action.yml`).

**Edit 3 — `plugins/soleur/skills/plan/references/plan-sharp-edges.md:140`**:
split the prescribed triplet into read vs write invocations — keep the
`prd_terraform` export for `plan`/`init`/`state pull`/`refresh`, and prescribe
`export AWS_*` from `TF_STATE_AWS_*` in `soleur-infra-privileged/prd` plus the
nested-loader form for `apply`/`import`/`state push`/`state mv`/`taint`, with a
one-line pointer to the runbook section and the "read-only post-O5b" note.
Folded in under `hr-write-boundary-sentinel-sweep-all-write-sites`: the entry
prescribes a recipe that produces this exact defect in every future
drift-remediation plan.

**Edit 4 — `tests/scripts/test-infra-privileged-tier-census.sh`**: add a limb
("AC7b limb 3 — local `.sh` state-writers") asserting the property over the
executable-script population, plus its mutation-battery rows (see Guard
Contract).

## Technical Considerations

- **Read-path legitimacy.** The `prd_terraform` `AWS_*` pair remains correct
  for `plan`/`init`/`state pull`/`refresh` by design; the guard's trigger is
  conditioned on a state-*writing* invocation so a legitimately read-only
  script is not flagged.
- **`init` stays on the ambient pair.** `terraform init` reads only the
  backend credentials — with the Tier-B pair exported it is a superset of the
  required permission; no init change needed in either script.
- **Auth reachability (measured).** `doppler run -p soleur -c prd -- doppler
  secrets -p soleur-infra-privileged -c prd --only-names` returns the Tier-B
  name list under the environment's existing auth (measured 2026-10-24), and a
  plain `doppler secrets get -p soleur-infra-privileged -c prd` resolves the
  same way — so neither script needs a new token or a restructured launch
  contract. `bootstrap-live-verify.sh` keeps its `DOPPLER_CONFIG == "prd"`
  entry guard.
- **No `*.tf`, no workflows, no new TF_VARs.** Nothing the diff touches feeds
  a push-triggered apply path; the two scripts are operator/agent-invoked
  locally and deliberately never wired into CI (bootstrap-live-verify's
  negative AC — zero hits for its name under `.github/workflows/` — remains
  true and must stay true).
- **No new infrastructure, no new persistent store, no new cross-component
  connection** — Phase 2.8 IaC routing and Phase 2.11 encryption posture do
  not fire. No new data-model/ownership/trust boundary — Phase 2.10 ADR gate
  does not fire (the change conforms to ADR-241; it records no new decision).
- **NFRs:** security (credential-tier conformance, anti-plant `--preserve-env`),
  reliability (rotation path actually runnable). No performance surface.
- **No user-facing surface** — the Product/UX mechanical override does not
  fire (no `components/**/*.tsx`, `app/**/page.tsx`, or `app/**/layout.tsx` in
  Files to Edit/Create).

## Files to Edit

- `apps/cla-evidence/infra/bootstrap.sh` — cred-leg source swap + comment
  update (~8 lines).
- `apps/web-platform/scripts/bootstrap-live-verify.sh` — cred-leg source swap,
  error-message source names, nested-loader apply leg, header + comment
  updates (~20 lines).
- `plugins/soleur/skills/plan/references/plan-sharp-edges.md` — split the
  stale triplet at the line-140 entry into read vs write forms (~10 lines).
- `tests/scripts/test-infra-privileged-tier-census.sh` — new AC7b limb for
  `.sh` state-writers + mutation rows (~120-180 lines, matching the suite's
  existing `check()` + fixture conventions).

## Files to Create

- None.

## User-Brand Impact

- **If this lands broken, the user experiences:** nothing end-user-facing —
  the two scripts are operator/agent-run bootstrap and leak-rotation paths;
  the defect's blast radius is an operator-visible mid-apply abort with a
  forked `errored.tfstate`, worst during an active credential-leak rotation.
- **If this leaks, the user's [data / workflow / money] is exposed via:** no
  new exposure vector — the fix narrows which credential the scripts hold
  (read/write Tier-B pair read by explicit name) and adds no secret to logs,
  argv, or files; both pairs are already held in Doppler.
- **Brand-survival threshold:** `none`
- **Threshold decision (challengeable):** failure is loud, operator-visible,
  and internal-tooling-shaped (a 403 abort, not silent corruption or a user
  data path); the runbook fallback (manual rotation per the runbook) exists,
  so no single end user is harmed by a defect here.

*Scope-out override:* `threshold: none, reason: the diff touches credential-sourcing shell code (a preflight sensitive path) but changes no user data path, adds no secret surface, and its worst failure is an operator-visible apply abort — no user-facing artifact is produced or altered`

## Observability

```yaml
liveness_signal:
  what: infra-privileged tier census suite — prints ok/FAIL rows including the new `.sh` state-writer limb
  cadence: per CI run on PRs touching apps/ or .github/ (affected selection), plus the full battery at ship
  alert_target: required CI check on the PR
  configured_in: tests/scripts/test-infra-privileged-tier-census.sh (new limb; existing run_suite registration in scripts/test-all.sh)
error_reporting:
  destination: CI suite output (FAIL lines name the offending script path)
  fail_loud: non-zero suite exit turns the required check red; at operator run time a broken cred leg aborts the script on a non-zero doppler/terraform exit with a named ::error::/red line
failure_modes:
  - mode: a state-writing .sh re-points its AWS_* leg at the read-only prd_terraform pair (this defect recurring, or a new script arming it)
    detection: new census limb reds on the diff — assert at PR time, before any operator run
    alert_route: PR check failure
  - mode: half-set Tier-B pair (one of TF_STATE_AWS_* missing from soleur-infra-privileged/prd)
    detection: script-side all-or-none/empty guard aborts before terraform runs
    alert_route: operator terminal ::error:: line
logs:
  where: script stdout (::error:: lines are stdout-pinned per constitution convention) and CI run log
  retention: CI log retention; operator terminal for local runs
discoverability_test:
  command: grep -l TF_STATE_AWS_ACCESS_KEY_ID apps/cla-evidence/infra/bootstrap.sh apps/web-platform/scripts/bootstrap-live-verify.sh
  expected_output: apps/cla-evidence/infra/bootstrap.sh apps/web-platform/scripts/bootstrap-live-verify.sh
```

## Guard Contract

### Guard 1 — `.sh` state-writer credential-source limb (in `test-infra-privileged-tier-census.sh`)

**Property.** Every tracked (or untracked-present, per the suite's
fail-closed census convention) `*.sh` file that contains a state-writing
terraform invocation (`terraform apply`, `import`, `state push`, `state mv`,
`taint`) sources its ambient `AWS_*` backend leg from a Tier-B name
(`TF_STATE_AWS_*` or `GIT_DATA_ROOT_STATE_AWS_*`), and no such file feeds
terraform the read-only `prd_terraform` `AWS_*` pair.

**Assembly.** Derived, not enumerated: the Python census walks `*.sh` under
`IPT_REPO_ROOT` (filesystem walk — untracked files censused too, matching the
suite's stated convention), classifies each as a state-writer by the
invocation token set above (a file containing only `plan`/`init`/`state pull`
is a read, exempt), then asserts each state-writer carries a `doppler secrets
get`/`export` leg naming `TF_STATE_AWS_` (or `GIT_DATA_ROOT_STATE_AWS_`) AND
contains no `secrets get AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY` read
resolved against `prd_terraform`. The population floor is asserted at the two
known armed files so a "0 checked" run cannot exit green. Limit stated
honestly: a script that passes `AWS_*` purely from the caller's environment
with no Doppler read at all is out of this limb's scope (the defect class is
the Doppler-source choice, and the runbook prescribes no ambient-env recipe).

**Mutation matrix.**

| # | Mutation | Expected |
|---|----------|----------|
| 1 | Fixture `.sh` state-writer sources `AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY` from `prd_terraform` (today's buggy shape) | RED — limb names the file |
| 2 | Guard's write-token set dropped (fixture apply reads as read-only) | RED — dispatch/anti-vacuity row: population floor (`>= 2` known files) unmet |
| 3 | Compliant first script plus a SECOND state-writer added carrying the prd_terraform pair | RED — the check does not stop at the first member |
| 4 | Compliant script mutated to a half-set (reads `TF_STATE_AWS_ACCESS_KEY_ID` only, secret leg deleted) | RED — all-or-none pair assertion |
| 5 | Harness: limb's classification key removed from `ipt.py`'s check (row count would go to zero) | RED — the floor assertion on the two known files fails |
| 6 | Read-only control: fixture `.sh` with `doppler secrets get AWS_* -c prd_terraform` + only `terraform plan` | PASS — the exemption is load-bearing (read invocations may keep the pair) |
| 7 | Compliant fixture (both `TF_STATE_AWS_*` legs + `terraform apply`) | PASS — must-PASS input that is not the real tree's shape |

**Anchor.** The pinned names (`TF_STATE_AWS_*`, `GIT_DATA_ROOT_STATE_AWS_*`,
the `prd_terraform` forbidden source) live in the census's `TIER_B_NAMES`
constant and are cross-pinned by the runbook §Local Terraform invocation and
`infra-credentials/action.yml`'s alias block; weakening the guard's literals
requires editing the same names in three places in one diff, which review
sees.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "Source the backend pair from `soleur-infra-privileged/prd` `TF_STATE_AWS_ACCESS_KEY_ID`/`TF_STATE_AWS_SECRET_ACCESS_KEY` (exported as bare `AWS_*` — the tf-var transformer never sets them), per the canonical form in `knowledge-base/engineering/operations/runbooks/infra-credential-tiers-8209.md` §Local Terraform invocation." [issue #10990 §Fix] | Proposed Solution Edits 1-2 (both script cred legs) + nested-loader arm | mapped |
| 2 | "Executable code, so this needs the code-change path (test coverage for the credential legs), not a docs edit." [issue #10990 §Fix] | Edit 4 — census limb + Guard Contract mutation matrix | mapped |
| 3 | "`apps/cla-evidence/infra/bootstrap.sh:127-141` — exports the read-only pair, then `terraform apply -auto-approve`" [issue #10990 §Armed sites] | Edit 1 | mapped |
| 4 | "`apps/web-platform/scripts/bootstrap-live-verify.sh:62-70` export + `:84-87` `terraform apply -auto-approve`" [issue #10990 §Armed sites] | Edit 2 | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| `bootstrap.sh` cred-leg swap | asks 1+3 | asked |
| `bootstrap-live-verify.sh` cred-leg swap | asks 1+4 | asked |
| Census limb + mutation battery | ask 2 | asked |
| Nested-loader adoption in `bootstrap-live-verify.sh` apply leg | "per the canonical form in `.../infra-credential-tiers-8209.md` §Local Terraform invocation" (ask 1 — the section's canonical local invocation IS the nested loader) | asked-by-citation; flagged in `decision-challenges.md` since the issue's parenthetical scopes tighter than the section it cites |
| `plan-sharp-edges.md:140` stale-recipe fix | — | inferred — justification: the mandate `hr-write-boundary-sentinel-sweep-all-write-sites` covers prescribing surfaces; the entry instructs future plans to export the read-only pair before `apply`, which is this defect re-armed |
| `specs/<branch>/decision-challenges.md` row(s) | — | inferred — justification: pipeline contract requires persisting the assumed technical rulings |

### Split Assessment

- Subsystems touched: 4 — `apps/cla-evidence`, `apps/web-platform`, `tests`, `plugins`
- Planned files: 4 edited / 0 created | Estimated changed lines: ~160 (mostly the census limb)
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR — the root count trips the threshold on a technicality: the four roots are one defect class (the cred-source fix, its guard, and one prescribing-prose correction); splitting the `plugins/` prose edit into its own PR would strand a 10-line doc fix behind a second review cycle while the armed scripts stay 403-broken. Recorded per the gate's advisory rule.

## Acceptance Criteria

- [ ] AC1 — `grep -n 'TF_STATE_AWS_ACCESS_KEY_ID\|TF_STATE_AWS_SECRET_ACCESS_KEY' apps/cla-evidence/infra/bootstrap.sh` shows both names, each via `doppler secrets get` against `-p soleur-infra-privileged -c prd` — and `grep -n 'secrets get AWS_ACCESS_KEY_ID\|secrets get AWS_SECRET_ACCESS_KEY' apps/cla-evidence/infra/bootstrap.sh` returns zero hits.
- [ ] AC2 — same two assertions hold for `apps/web-platform/scripts/bootstrap-live-verify.sh`.
- [ ] AC3 — `grep -n 'preserve-env' apps/web-platform/scripts/bootstrap-live-verify.sh` shows the inner `doppler run` carrying `--preserve-env` inside the nested invocation on the apply leg.
- [ ] AC4 — `bash tests/scripts/test-infra-privileged-tier-census.sh` exits 0 and its output contains the new limb's `ok` row naming the `.sh` state-writer check.
- [ ] AC5 — the limb's mutation battery rows all report their expected verdicts (RED rows driven red, control rows green) — asserted by the suite's own battery output.
- [ ] AC6 — `grep -n 'apply' plugins/soleur/skills/plan/references/plan-sharp-edges.md` shows the line-140 entry's triplet split into read vs write invocations (the write arm names `TF_STATE_AWS_` + `soleur-infra-privileged`), and `grep -c 'secrets get AWS_ACCESS_KEY_ID'` on that file no longer counts the unqualified write recipe.
- [ ] AC7 — `grep -rl 'bootstrap-live-verify\|seed-live-verify' .github/workflows/` returns zero (the script's own standing negative AC — the fix must not wire it into CI).
- [ ] AC8 — `bash -n apps/cla-evidence/infra/bootstrap.sh && bash -n apps/web-platform/scripts/bootstrap-live-verify.sh` both pass.
- [ ] AC9 — full suite gate: the diff triggers the affected runner's selection of `tests/scripts/infra-privileged-tier-census` (the limb's host), verified by `bash scripts/test-all.sh --print-selection` listing it, or the full `scripts` group run green.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — infrastructure/tooling change. The
eight-domain sweep was assessed inline (sequential-fallback mode — no Task
spawn on this harness): Product (no UI-surface file in Files to Edit/Create —
mechanical override checked against ui-surface-terms, no match); Marketing,
Sales, Support, Legal, Finance, Operations, Product all none. Engineering is
the owning domain and the whole scope.

## Test Scenarios

- **Census limb — regression (unit):** Given a fixture `.sh` state-writer
  sourcing `AWS_*` from `prd_terraform`, when the limb runs, then it REDs and
  names the file. (Guard Contract rows 1-5.)
- **Census limb — exemption (unit):** Given a `.sh` that reads the
  `prd_terraform` pair for `terraform plan` only, when the limb runs, then it
  stays green — the property is about state writes. (Row 6.)
- **Scripts — post-fix shape (static):** ACs 1-3, 6-8 above.
- **Live spot-check (manual, operator-run — not an AC):** the next real
  invocation of either script performs `terraform apply` against
  `soleur-terraform-state` without a `PutObject` 403. Not automated: it
  requires the real R2 write credential and mutates prod state — deliberately
  out of CI per the script's own negative-AC design. `doppler secrets
  --only-names` evidence that the pair exists is already captured in Research
  Insights.
- **Property that must never break (unit, pinned by the limb):** no tracked
  `.sh` may combine a state-writing terraform invocation with a
  `secrets get AWS_*` read resolved against `prd_terraform`.

## Success Metrics

- Both scripts' next real runs reach `terraform apply` completion (no
  mid-apply 403, no `errored.tfstate`).
- The census limb is permanently green on `main` — the property becomes
  un-regressable rather than once-fixed.

## Dependencies & Risks

- **Risk — operator auth without Tier-B read:** the scripts now require the
  runner's Doppler auth to read `soleur-infra-privileged/prd`. Verified for
  this environment (`--only-names` returns the project), and the scripts
  already abort loudly on a `doppler secrets get` failure; residual: an
  operator whose workplace role lacks the project gets a named error at the
  cred leg instead of a mid-apply 403 — strictly better failure shape.
- **Risk — nested-loader behavioral nuance:** the outer
  `--name-transformer tf-var` also renames Doppler's own injected meta names;
  the inner loader's `--preserve-env` precedence is the measured contract
  (runbook records the measurement). If `soleur-infra-privileged/prd` later
  gains a name that must NOT win, that is a tier-listing concern, not this
  diff's.
- **Risk — census suite edit regression:** the limb rides a 4400-line
  load-bearing suite; the mutation battery asserts the limb reds on the buggy
  shape before it can read green on the fixed one, and the suite's own
  self-test + fixture conventions bound the blast radius.
- **Dependency:** none external — the Tier-B pair already exists (verified).

## References & Research

- Issue: #10990 (this work), #10979 (surfacing fix — prose sites), #8209 /
  ADR-241 (credential tiers).
- Canonical recipe: `knowledge-base/engineering/operations/runbooks/infra-credential-tiers-8209.md`
  §Local Terraform invocation.
- CI twin of the fix: `.github/actions/infra-credentials/action.yml`
  (Tier-B `TF_STATE_AWS_*` → bare `AWS_*` alias, all-or-none guard).
- Host suite: `tests/scripts/test-infra-privileged-tier-census.sh` (AC7b).
- Learning: `knowledge-base/project/learnings/2026-10-24-credential-tier-cutover-invalidates-recipes-asymmetrically.md`.
- Sequencing note for `soleur:work`: scripts first, then the sharp-edges prose
  and the census limb; the limb's fixture mutants prove the new check before
  it gates the fixed tree.
