---
title: "fix: green main CI — three d1fa52f9 (#11652 cf-lb-overlay) failure signatures: apply workflow byte gate, ga_overlay random_id redaction, G4c bash/python root parity"
type: fix
date: 2026-10-31
slug: fix-main-ci-red-cf-lb-overlay-trio
branch: feat-one-shot-11687-main-ci-red
issue: 11687
closes: 11687
domain: engineering
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

# fix: green main CI — three d1fa52f9 (#11652 cf-lb-overlay) failure signatures

## Overview

Main CI run 41181409803 on `d1fa52f9` (#11652 — cf-lb-overlay dispatch machinery) is the
first red main build since `6a6cdc0c` (run 41149796033); `d1fa52f9` is the only commit
between. Three distinct, independently-verified failure signatures, all inside the #11652
diff, all reproduced locally on this branch:

1. `plugins/soleur/test/workflow-file-size.test.ts` — `apply-web-platform-infra.yml` is
   **490228 bytes, 228 over** the 490000-byte gate (GitHub's hard refusal is 512000).
2. `plugins/soleur/test/terraform-target-parity.test.ts` — the `ga_overlay` job's
   `Terraform plan (GA LB trio only)` and `Terraform apply (the graded tfplan)` steps in
   `.github/workflows/cf-lb-overlay.yml` run Terraform on `apps/web-platform/infra` (a
   root that declares key-bearing `random_id.*` resources) without piping output through
   `tf_redact_random_ids` — three assertions red (the violations list, the non-vacuity
   census, the pristine-baseline of the mutation test).
3. `test-scripts` → `infra-privileged-tier-census` G4c-parity — `GUARD4_ROOTS` (python,
   line 205) lists three roots including `apps/web-platform/infra/lb-staging`;
   `materialize_base_dir`'s bash `for _r in` list (line ~2291) lists only two. #11652
   added lb-staging to the python side deliberately and missed the bash side
   (419 passed / 1 failed).

One PR covers all three: they share one merge as root cause, each fix is small and
independent, and splitting triples the cycle time on an all-PRs-blocked main.

## Problem Statement / Motivation

The required `test` aggregate is red on `main`, which blocks every open PR (#11676's
update-branch CI hit identical failures). Signature 2 is additionally a live credential
leak vector: the `ga-overlay` dispatch arm is reviewer-gated and has not run yet, but the
first dispatch would print `random_id.egress_audit_ingest_token`,
`random_id.github_webhook_secret`, `random_id.inngest_event_key_dedicated`,
`random_id.inngest_event_key_dev`, and siblings into the Actions log in cleartext — the
exact class #11294's redaction sweep exists to prevent.

## Proposed Solution

### Fix 1 — relocate sub-root exclusion prose to the job-rationale runbook (ADR-231 convention)

The byte gate has an established escape: `# Rationale: <runbook> §<id>` pointers whose ids
biject with `## <id>` headings in
`knowledge-base/engineering/operations/runbooks/apply-web-platform-infra-job-rationale.md`
(enforced by the same test file). #11652 added a 4-line comment + the `!lb-staging/**`
line (~+250 B) on top of an ~870 B headroom.

Replace the four per-exclusion comment blocks in the `push.paths:` list (rung2-rehearsal,
inngest-provision-rehearsal, git-data-root-key, lb-staging — ~19 comment lines, ~1.8 KB)
with one short context comment plus a single pointer line:

```yaml
      # Each `!` below is a SEPARATE Terraform root with its own state key; a merge touching
      # only it must never fire a PRODUCTION apply of the parent root.
      # Rationale: knowledge-base/engineering/operations/runbooks/apply-web-platform-infra-job-rationale.md §push-paths sub-root exclusions
      - "!apps/web-platform/infra/rung2-rehearsal/**"
      - "!apps/web-platform/infra/inngest-provision-rehearsal/**"
      - "!apps/web-platform/infra/git-data-root-key/**"
      - "!apps/web-platform/infra/lb-staging/**"
```

Move the removed prose — the #7025/R10 NEGATED-not-`paths-ignore` mechanism note, the
per-root reason each exclusion exists, and the deliberate non-exclusions
(`modules/git-data-userdata/`, `cloud-init-inngest.yml`, the
`git-data-root-key.fingerprint` anchor) — into a new runbook section
`## push-paths sub-root exclusions` (the `§` id must equal the heading text exactly, and
the pointer/heading sets must stay bijective — the test asserts `pointers == headings`,
`pointers.length >= 10`). The four `!` path lines themselves are preserved verbatim.
Net saving ≈ 1.4 KB → ~488.8 KB, restoring ~1.2 KB headroom.

### Fix 2 — pipe the ga_overlay terraform streams through the #11294 redactor

Apply the convention already used by every other step on `apps/web-platform/infra`
(e.g. `apply-web-platform-infra.yml` ~line 2100):

- In `Terraform plan (GA LB trio only)`: add
  `# shellcheck source=tests/scripts/lib/tf-redact-random-ids.sh` +
  `source "${GITHUB_WORKSPACE}/tests/scripts/lib/tf-redact-random-ids.sh"` near the top of
  the run block; append `2>&1 | tf_redact_random_ids` to the `doppler run -- terraform
  plan` invocation; change `rc=$?` to `rc=${PIPESTATUS[0]}` (pipefail is already set, so a
  terraform failure still fails the step — the existing `if [[ $rc -ne 0 ]]` arm is kept).
- In `Terraform apply (the graded tfplan)`: add the same `source` lines and append
  `2>&1 | tf_redact_random_ids` to `terraform apply -no-color -input=false -auto-approve
  tfplan`. `set -euo pipefail` makes the step fail on terraform non-zero unchanged.

The staging arms (`REHEARSAL_DIR` = `apps/web-platform/infra/lb-staging`) need nothing —
that root declares no key-bearing `random_*`, and the test's root classification already
proves it clean. The `terraform show` plan-gate step is not a counted verb and its
`grep -E 'will be|Plan:'` fallback is a value-free selection — leave it.

### Fix 3 — close the bash/python root-list divergence (and give the fixture the third root)

In `tests/scripts/test-infra-privileged-tier-census.sh`:

- `materialize_base_dir` (~line 2289): extend the `mkdir -p` to also create
  `"$_dest/apps/web-platform/infra/lb-staging"`, and extend the
  `for _r in` list (~line 2291) to
  `apps/web-platform/infra apps/web-platform/infra/git-data-root-key apps/web-platform/infra/lb-staging`.
- G4GIT fixture (~line 3928): `mkdir -p "$G4GIT/repo/apps/web-platform/infra/lb-staging"`
  and commit a fixture `apps/web-platform/infra/lb-staging/main.tf` (e.g.
  `resource "terraform_data" "base_lb" {}`) into **M0** so every fixture ref
  (M0/M1/M2/HEAD variants) carries the root — otherwise `ls-tree` returns empty for
  lb-staging, `materialize_base_dir` fails `empty-listing`, and every g4git leg reds
  `base unavailable` (fail-closed by design; the fixture must model a repo where all
  three roots exist).
- Update the stale doc comment at line ~24 which names only the two older roots.
- Loop-order note: keep lb-staging last — the M2 floor arm (git-data-root-key holds no
  `.tf`) must still fire its per-root floor and produce the same `base unavailable`
  verdict; order inside the sorted parity comparison is irrelevant.

Do **not** revert the python side: #11652's commit message records `lb-staging added to
GUARD4_ROOTS` as a deliberate review-hardening item — the bash materializer is the side
that was missed.

## Technical Considerations

- **Byte arithmetic (verified).** File is 490228; gate is 490000; the four comment blocks
  total ~1.8 KB; replacement pointer+context ≈ 0.35 KB; expected result ≈ 488.8 KB
  (≥ 228 B required, ~1.2 KB margin). If the implementer's final text lands < 229 B of
  savings, relocate additional sibling comment prose under the same heading rather than
  reintroducing prose in the workflow.
- **Pointer↔heading bijection is load-bearing.** Adding `## push-paths sub-root
  exclusions` without the matching `§push-paths sub-root exclusions` pointer (or vice
  versa) reds the runbook-pointer test.
- **PIPESTATUS correctness.** `rc=$?` after a pipeline reads the last element's status;
  the convention is `rc=${PIPESTATUS[0]}` so terraform's exit code — not the redactor's —
  drives the `::error::` arm.
- **`set -e` interaction.** The plan step deliberately runs under `set +e`; the apply step
  under `set -euo pipefail` — piping through the redactor under pipefail preserves the
  failure, so no `|| true` is wanted.
- **Fixture-model honesty.** The G4GIT synthetic repo must declare the root at M0 because
  `materialize_base_dir` is fail-closed on `empty-listing`/`floor` — the b9 floor arm
  still exercises the per-root zero-`.tf` refusal via git-data-root-key.
- **NFR impacts:** none (CI/quality-gate surfaces only).

### Attack Surface Enumeration (signature 2 — secret-leak fix)

All ways `random_*` key material can leave the `ga_overlay` job:

- `terraform plan` stdout/stderr — **fixed** by `2>&1 | tf_redact_random_ids`.
- `terraform apply` stdout/stderr — **fixed** the same way.
- `terraform show -json tfplan` → `$RUNNER_TEMP/ga-overlay-plan.json` — consumed only by
  `cf_lb_gate_ga` inside the runner; never printed to a public sink. Safe (documented).
- `terraform show -no-color tfplan | grep -E 'will be|Plan:' | head -30 >&2` — prints only
  header/count lines on gate failure; the parity test's `valueFreeGrep` allowlist already
  classifies it. Safe, unchanged.
- `tfplan` binary artifact — never uploaded; lives only in the runner workspace. Safe.
- The staging arms on `REHEARSAL_DIR` — root declares no `random_*`. Safe by root
  classification.

## Research Insights

**Premise Validation.** Issue #11687 is OPEN (`gh issue view`). `d1fa52f9` verified at
`HEAD~1`; `git show` confirms it added the 4-line `!lb-staging/**` block to
`apply-web-platform-infra.yml`, created `cf-lb-overlay.yml`, and added `lb-staging` to the
python `GUARD4_ROOTS` (commit message: deliberate review hardening) while the bash
`materialize_base_dir` list stayed at two roots. All three failures reproduced locally
this session: `bun test plugins/soleur/test/workflow-file-size.test.ts` → "490228 bytes,
228 bytes over"; `bun test .../terraform-target-parity.test.ts` → 3 fails, all naming the
two `ga_overlay` steps; the parity extraction prints `bash={infra, git-data-root-key}
python={infra, git-data-root-key, lb-staging}` — issue's "419/1" consistent.
Collision pre-check (`collision-precheck.sh 11687`): only our own draft PR #11690 on this
branch; two foreign `test-all.sh` pids owned by `.worktrees/feat-one-shot-11578-*` —
informational, not this scope.

**Property List** (Phase 0.6b).

- P1: `apply-web-platform-infra.yml` ≤ 490000 bytes while every `!` exclusion and its
  rationale survive (relocated, not deleted) — the test's own hint names the runbook.
- P2: every terraform plan/apply/refresh/destroy stream on `apps/web-platform/infra`
  passes through `tf_redact_random_ids` (#11294 contract, already enforced repo-wide).
- P3: `materialize_base_dir`'s bash root set equals `GUARD4_ROOTS`, with the base
  materialization able to succeed on refs that carry all three roots (fixture + live).

**Cut List.** None — zero new machinery. Each fix brings an existing surface back inside
an existing gate's contract (ADR-231 relocation, #11294 redactor, #9956 parity).

**Relevant paths.** `.github/workflows/apply-web-platform-infra.yml` (paths block ~lines
19–52); `knowledge-base/engineering/operations/runbooks/apply-web-platform-infra-job-
rationale.md` (19 level-2 headings, pointer-bijected);
`.github/workflows/cf-lb-overlay.yml` (`ga_overlay` ~lines 412–530);
`tests/scripts/lib/tf-redact-random-ids.sh` (the redactor; exists);
`tests/scripts/test-infra-privileged-tier-census.sh` (ipt.py heredoc line 205;
`materialize_base_dir` ~2285; parity check ~4148; G4GIT fixture ~3920);
`plugins/soleur/test/workflow-file-size.test.ts` (gate + pointer bijection);
`plugins/soleur/test/terraform-target-parity.test.ts` (redaction sweep ~1843–1925).

**Learnings applied.** `2026-10-30-gate-allow-sets-bound-which-resources-not-what-they-
say.md` (root-scoped gates); sharp-edges: run each prescribed command once before
finalizing; PIPESTATUS not `$?` after a redactor pipe; census lists need a second
enumerator (the parity check IS that enumerator — keep two lists, keep them equal);
markdownlint on plan + tasks.md before summary.

**Community / functional overlap.** Repo-internal CI repair against repo-authored gates;
no community artifact applies. External research skipped (strong local context,
mechanical fixes on already-patterned conventions).

## User-Brand Impact

- **If this lands broken, the user experiences:** main's required `test`/`test-scripts`
  checks stay red — every open PR remains unmergeable; if the redaction regresses, the
  first `ga-overlay` dispatch prints several sole-copy infra credentials into the Actions
  log.
- **If this leaks, the user's [data / workflow / money] is exposed via:** infra key
  material (`github_webhook_secret`, Inngest event keys, egress audit ingest token)
  readable in the `cf-lb-overlay.yml#ga_overlay` job log — forgeable webhooks and ingest.
- **Brand-survival threshold:** `single-user incident`
- **Threshold decision (challengeable):** one unredacted dispatch exposes multiple
  rotation-requiring infra credentials in a single run — a single-incident security
  event, matching the #11652 epic's own `single-user incident` review tier.

`requires_cpo_signoff: true` is set per the sign-off lifecycle; the CPO consult could not
be spawned in this planning harness — recorded in `decision-challenges.md` for the review
pipeline.

## Observability

The fix's observability surface is the CI gate set itself; the plan adds no runtime
surface.

```yaml
liveness_signal:
  what: "required `test` + `test-scripts` aggregates on ci.yml (the three red legs ARE the signal)"
  cadence: "per push to main and per PR"
  alert_target: "GitHub required-check red on the run (observed live as run 41181409803)"
  configured_in: ".github/workflows/ci.yml"
error_reporting:
  destination: "GitHub Actions job logs (test-bun; test-scripts shard 3/8)"
  fail_loud: "bun `(fail)` lines; `=== infra-privileged-tier-census: N passed, M failed ===`"
failure_modes:
  - mode: "apply-web-platform-infra.yml regrows past 490000 bytes"
    detection: "workflow-file-size.test.ts `no workflow file exceeds the gate`"
    alert_route: "required `test` check red on the touching PR"
  - mode: "any terraform step on a key-bearing root loses or never gains the redactor"
    detection: "terraform-target-parity.test.ts redaction sweep (violations + census + mutation baseline)"
    alert_route: "required `test` check red"
  - mode: "bash and python GUARD4 root lists diverge again"
    detection: "G4c-parity assertion in test-infra-privileged-tier-census.sh"
    alert_route: "required `test-scripts` check red"
  - mode: "base materialization on a ref predating a root's first .tf"
    detection: "IPT_G4C_BASE_MATERIALIZE=fail stderr + G4c row `base unavailable` (fail-closed)"
    alert_route: "required `test-scripts` check red; operator seam IPT_BASE_REF"
logs:
  where: "GitHub Actions job logs for the failing legs; materializer failure lines on stderr"
  retention: "GitHub run-log retention (~90 days)"
discoverability_test:
  command: "grep -l tf_redact_random_ids .github/workflows/cf-lb-overlay.yml"
  expected_output: ".github/workflows/cf-lb-overlay.yml"
```

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "workflow-file-size.test.ts — apply-web-platform-infra.yml 490228 bytes, 228 over the 490000 gate; relocate comment prose to a runbook" [issue #11687 sig 1] | Fix 1 / Phase 2 / Files-to-Edit entries 1–2 | mapped |
| 2 | "terraform-target-parity.test.ts — .github/workflows/cf-lb-overlay.yml#ga_overlay plan output does not redact random_id.* secrets" [issue #11687 sig 2] | Fix 2 / Phase 3 / Files-to-Edit entry 3 | mapped |
| 3 | "infra-privileged-tier-census G4c-parity — bash and python root lists diverged" [issue #11687 sig 3] | Fix 3 / Phase 4 / Files-to-Edit entry 4 | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| Relocate exclusion comment prose to runbook `§push-paths sub-root exclusions` | "relocate comment prose to a runbook" | asked |
| Source + pipe `tf_redact_random_ids` in both ga_overlay terraform steps | "plan output does not redact random_id.* secrets" | asked |
| Extend `materialize_base_dir` root list + mkdir + G4GIT fixture lb-staging .tf | "the bash and python root lists diverged" | asked |
| lb-staging fixture file inside the G4GIT repo | — | inferred — justification: the fail-closed `empty-listing`/`floor` arms red every g4git leg unless the fixture repo declares the root at M0; parity alone is not sufficient |
| Runbook heading + pointer addition | — | inferred — justification: the pointer↔heading bijection test requires the pair |

### Split Assessment

- Subsystems touched: 3 — `.github`, `tests`, `knowledge-base`
- Planned files: 4 | Estimated changed lines: ~70
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR — one merge is the shared root cause; issue asks for the trio together.

## Files to Edit

1. `.github/workflows/apply-web-platform-infra.yml` — replace the four sub-root exclusion
   comment blocks (push `paths:` ~lines 20–47) with a 2-line context comment + the
   `§push-paths sub-root exclusions` pointer; keep all four `!` path lines and the
   destroy-guard-filter entry unchanged.
2. `knowledge-base/engineering/operations/runbooks/apply-web-platform-infra-job-rationale.md`
   — append `## push-paths sub-root exclusions` carrying the relocated prose (mechanism
   note + per-root reasons + the deliberate non-exclusions).
3. `.github/workflows/cf-lb-overlay.yml` — `ga_overlay` plan and apply steps: source
   `tests/scripts/lib/tf-redact-random-ids.sh`, pipe terraform output
   `2>&1 | tf_redact_random_ids`, plan step `rc=${PIPESTATUS[0]}`.
4. `tests/scripts/test-infra-privileged-tier-census.sh` — `materialize_base_dir` mkdir +
   `for _r in` list gains `apps/web-platform/infra/lb-staging`; G4GIT fixture gains
   `lb-staging/main.tf` committed at M0; refresh the two-root doc comment at ~line 24.

## Files to Create

None.

## Open Code-Review Overlap

None — `gh issue list --label code-review --state open` bodies contain none of the four
edited paths.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — infrastructure/tooling change. No UI-surface
files in the edit set; Product/UX gate is NONE by the mechanical scan.

## Guard Contract

The deliverable modifies one guard's assembly (the bash half of the G4c root-list parity)
and satisfies two other guards unchanged; one contract entry covers the guard whose
machinery this diff edits.

### Guard 1 — G4c bash↔python root-list parity

**Property.** The bash base-materialization root set and ipt.py's `GUARD4_ROOTS` enumerate
the same terraform roots — a root present on one side alone is censused at HEAD with no
materialized base (or materialized but never scanned) and its deletions slip silently.

**Assembly.** Exactly two enumeration sites inside
`tests/scripts/test-infra-privileged-tier-census.sh`: the `GUARD4_ROOTS` assignment in the
embedded ipt.py (~line 205) and the `for _r in apps/…` list in `materialize_base_dir`
(~line 2291) — plus the materializer's `mkdir -p` and the G4GIT fixture's committed files,
which decide whether a listed root can actually materialize. The parity check (~line
4148) is the chokepoint the two lists flow through.

**Mutation matrix.**

| # | Mutation | Expected |
|---|----------|----------|
| 1 | Add a fourth root to `GUARD4_ROOTS` only | RED — parity fail, bash list lacks it |
| 2 | Delete the `for _r in` line (bash side reports nothing checked) | RED — empty bash list vs non-empty py list (own-dispatch) |
| 3 | Add `lb-staging` to the bash list without the G4GIT fixture file | RED — g4git legs fail `empty-listing`/`base unavailable` (a second member after a compliant first must still materialize) |
| 4 | Reorder the bash root list | PASS — both sides are `sort`-normalized (must-PASS, non-canonical order) |
| 5 | Drop `apps/web-platform/infra/lb-staging` from `GUARD4_ROOTS` to "fix" parity the other way | RED — the parity sets agree but lb-staging's live deletions lose G4c coverage; caught by the fixture legs' intent + flagged here as the rejected direction |

## Acceptance Criteria

<!-- founder-stated check: n/a — headless pipeline -->

- [ ] `wc -c .github/workflows/apply-web-platform-infra.yml` reports ≤ 490000 bytes.
- [ ] `bun test plugins/soleur/test/workflow-file-size.test.ts` → 0 failures (size gate + pointer↔heading bijection both green).
- [ ] `bun test plugins/soleur/test/terraform-target-parity.test.ts` → 0 failures (all three redaction-sweep assertions green).
- [ ] `bash tests/scripts/test-infra-privileged-tier-census.sh` → `420 passed, 0 failed` (or the suite's then-current count with 0 failed — the parity leg reports `pass`).
- [ ] `grep -c 'tf_redact_random_ids' .github/workflows/cf-lb-overlay.yml` returns exactly 2 (plan + apply pipes; the filename spelling `tf-redact-random-ids.sh` does not match).
- [ ] All four `!apps/web-platform/infra/{rung2-rehearsal,inngest-provision-rehearsal,git-data-root-key,lb-staging}/**` lines remain verbatim in the `push.paths:` list.
- [ ] The runbook contains `## push-paths sub-root exclusions` and the workflow's matching `# Rationale: … §push-paths sub-root exclusions` pointer line.
- [ ] `actionlint` (or the repo's workflow-lint equivalent) is clean on both edited workflows.
- [ ] `bash tests/scripts/test-cf-lb-overlay-gate.sh` → green (adjacent suite, unchanged gate lib).
- [ ] PR body uses `Closes #11687` and summarizes all three fixes.

## Test Scenarios

Each scenario runs the failing gate's own invocation (not a reconstruction):

- **(integration)** Given the relocated-prose edit, when `bun test plugins/soleur/test/workflow-file-size.test.ts` runs, then "no workflow file exceeds the gate" passes and the pointer↔heading bijection test passes with `pointers == headings`.
- **(integration)** Given the redactor wiring, when `bun test plugins/soleur/test/terraform-target-parity.test.ts` runs, then the violations list is empty and the non-vacuity census passes (`rootLeaks`-clean for every non-redacting step; zero non-redacting steps on `apps/web-platform/infra`).
- **(integration)** Given the bash-list + fixture edit, when `bash tests/scripts/test-infra-privileged-tier-census.sh` runs, then `G4c-parity` passes and every g4git base-resolution leg still reaches its expected verdict (b9 floor arm included).
- **(unit, mutation)** Given the bash list extended without the fixture file, when the g4git legs run, then `empty-listing`/`base unavailable` reds — proves the fixture edit is load-bearing, not incidental.
- **(unit, mutation)** Given `rc=$?` left unchanged beside the new pipe, when a plan failure is simulated, then `PIPESTATUS[0]` vs `$?` divergence is the delta the fix must not ship — covered by reading the convention at `apply-web-platform-infra.yml` ~line 2110.
- **(integration, regression)** Given all three fixes, when the PR's own CI runs `test-bun` + `test-scripts`, then the run concludes green — the same legs that red at run 41181409803.

## Context

- Red run: `https://github.com/jikig-ai/soleur/actions/runs/41181409803` (jobs: test-bun
  124479985087, test-scripts (3/8) 124479985214, test aggregate 124489657657).
- Last green on main: run 41149796033 on `6a6cdc0c`; `d1fa52f9` is the only commit between.
- Advisory note from the issue: `affected-index-ratchet` new-pair was observed on PR
  #11676 — non-required; this diff edits no accept TSV, so no action expected, but watch
  the advisory on our own run.
- The staging arms' exemption is `env.REHEARSAL_DIR`-keyed (sub-root); do not rename that
  env or the G2 sole-copy census rescans them.
- Deferred-risk note: a branch forked before `d1fa52f9` materializes a base lacking
  lb-staging and reds `base unavailable` — documented fail-closed behavior; remedy is
  rebase/merge or the `IPT_BASE_REF` operator seam.

## References

- Issue: #11687 — `gh issue view 11687`
- Introducing merge: `d1fa52f9` / PR #11652 (cf-lb-overlay dispatch machinery, Ref #11181)
- Redaction library: `tests/scripts/lib/tf-redact-random-ids.sh` (#11294)
- Relocation convention: `knowledge-base/engineering/operations/runbooks/apply-web-platform-infra-job-rationale.md` (ADR-231 §2, per the pointer test's comment)
- Redactor call-site precedent: `.github/workflows/apply-web-platform-infra.yml` ~line 2100 (source + `2>&1 | tf_redact_random_ids` + `rc=${PIPESTATUS[0]}`)
- Census suite: `tests/scripts/test-infra-privileged-tier-census.sh` (#8209, ADR-241; G4c base machinery #9956)
