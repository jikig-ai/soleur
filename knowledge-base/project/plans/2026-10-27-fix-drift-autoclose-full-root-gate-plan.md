---
title: "fix(ci): gate drift-issue auto-close on a fresh full-root plan (#9061)"
type: fix
date: 2026-10-27
slug: fix-drift-autoclose-full-root-gate
branch: feat-one-shot-9061-drift-autoclose
issue: 9061
closes: 9061
priority: p2-medium
domain: engineering
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

# fix(ci): gate drift-issue auto-close on a fresh full-root plan

## Overview

`apply-deploy-pipeline-fix.yml` runs a bounded `-target` apply of five
`terraform_data` resources against `apps/web-platform/infra`, then — when the
infra-config gate returns `verified` — auto-closes every open
`infra: drift detected in web-platform` issue. `scheduled-terraform-drift.yml`
files those issues from an **untargeted** `terraform plan -detailed-exitcode`
of the same root. The close therefore asserts "re-aligned with HEAD" on
evidence that predates the apply it just ran and can never see non-target
drift: #8754 was auto-closed on 2026-09-25 with its whole standing tail
pending, and the next drift run filed duplicate #8908. The partial fix that
shipped since (`scripts/infra-drift-autoclose.sh`, PR #9416) narrowed the
close to issues whose *newest recorded* plan is readable, complete and free
of pending `hcloud_server` actions — but it still reads stale evidence and
still closes an issue whose drift is non-hcloud (e.g. a pending
`cloudflare_record` destroy).

This plan adds a **post-apply full-root drift plan** step to the apply job —
the same read-only invocation the drift cron uses — and gates the close step
on its exit code. A close then literally means "a full-root plan now reads
no changes". When the plan is not clean the step records the exit code,
leaves every drift issue open, and annotates the run.

Concurrent drift on the live root right now (#10835, #10768, identical
deltas): `cloudflare_record.google_gws_recovery` pending destroy (in state,
not in config — the config-side fix is already open as PR #10678, applied
from that unmerged branch on 2026-10-20), and `hcloud_server.inngest`
pending replace (`user_data` forces replacement; expected drift documented
by the LUKS-cutover-trio retirement #10966, owned by the inngest host-replace
window, epic #10390). Both issues stay open until a full-root plan reads
clean; this PR comments on them naming the owners of each residual.

## Problem Statement / Motivation

The auto-close's evidence chain has two holes (#9061):

1. **Wrong measurement.** The `verified` verdict adjudicates the web host's
   infra-config files (the webhook re-push channel). It says nothing about
   the full-root drift plan the issue records.
2. **Stale evidence.** The `infra-drift-autoclose.sh` classifier grades the
   newest *recorded* plan embedded in the issue body/comments — written by
   the drift cron *before* this apply ran. It can only exclude one drift
   class (hcloud_server actions) and cannot observe that the apply did not
   touch the drifted resources at all.

Measured consequence: the #8754 → #8908 close-then-duplicate cycle, and a
close comment asserting a re-alignment that never happened. ADR-138
established that automated close authority over operator-facing issues is a
brand-survival surface; this one currently exercises that authority on a
measurement that does not back the claim.

## Research Insights

### Premise Validation (Phase 0.6)

- `#9061`, `#10835`, `#10768` all verified OPEN via `gh issue view --json
  state` (2026-10-27). No `closedByPullRequestsReferences` on any.
- `.github/workflows/apply-deploy-pipeline-fix.yml`,
  `scripts/infra-drift-autoclose.sh`,
  `.github/workflows/scheduled-terraform-drift.yml` all present on this
  branch's base.
- The issue's claim needs one correction: the close is not *only* gated on
  `verdict == 'verified'` — since PR #9416 it also passes through
  `infra-drift-autoclose.sh`'s evidence classifier (newest recorded plan
  readable + complete + no `hcloud_server` action). The residual defect is
  exactly what remains: the classifier grades the **recorded** plan, not a
  **fresh** one, and only excludes the hcloud class.
- Collision precheck: the only open PR naming #9061 is this pipeline's own
  WIP PR #11296. A sibling open PR **#10928** (Tier-B webhook-trio/deploy
  Access-token work, `feat-feat-g1-pr2-terraform-fed-group`) edits
  `apply-deploy-pipeline-fix.yml` — restricted to credential-loading hunks
  (`doppler secrets get` → job-env reads), none near the auto-close region
  (~line 2552). Conflict risk low; rebase if it merges first.
- **Premise correction on the drift delta**: the brief said "exactly two
  resources". The recorded plan delta on #10835 is `Plan: 3 to add, 0 to
  change, 4 to destroy` — the destroy is
  `cloudflare_record.google_gws_recovery` plus the *cascade* of the inngest
  replace (`hcloud_server_network.inngest`,
  `hcloud_volume_attachment.inngest_redis_luks`), and the adds include the
  `web_2_private_ip` output. Same two root causes, more rows.
- `google_gws_recovery` provenance (verified): commit `208fc18397` on the
  unmerged branch `feat-gcp-gws-domain-verification` (open PR **#10678**,
  "feat(infra): verify soleur.ai for Google Workspace") adds the
  `cloudflare_record` block to `dns.tf` **and** its `-target=` to
  `apply-web-platform-infra.yml`'s merge-apply list. The record reached
  state (created_on 2026-10-20T09:27:43Z) without the config landing on
  main — hence the pending destroy.
- `hcloud_server.inngest` carries **no** `ignore_changes=[user_data]`
  (`apps/web-platform/infra/inngest-host.tf:469-491`), so the user_data diff
  from #10966 (merged 2026-10-26) forces replacement until a host-replace
  window. Confirmed expected drift.
- Filer dedupe anomaly (observed, not fixed here): the drift filer *does*
  dedupe by title (`scheduled-terraform-drift.yml` ~L1215-1233) and did
  comment on #10768 four times on 2026-10-22 — then the 16:04 UTC run filed
  #10835 anyway with #10768 still open. Both have since stayed open;
  subsequent updates land on #10835. Transient (index lag or raced run); no
  close/reopen events on either.

### Property List (Phase 0.6b)

- P1 — a drift issue closes only when a **fresh** full-root plan for
  `apps/web-platform/infra` reads no changes (the issue's own definition of
  resolved).
- P2 — fail-closed: when the fresh plan cannot run or errors, nothing closes
  (never read an unknown as clean).
- P3 — expected-but-live drift (inngest replace, pending #10678 record)
  keeps issues open — no false close, no duplicate-filing cycle.
- P4 — the run must say what it measured: exit code, `Plan:` summary line,
  and per-issue disposition in the step summary.

### Cut List (Phase 0.6b)

- "Comment instead of close" (the issue's alternative arm) — CUT: it removes
  the auto-close value permanently (every resolved drift issue would then
  need a human close forever) to fix a measurement gap that the fresh-plan
  gate fixes directly. Recorded as Alternative below.
- A `drift_plan` step implemented *inside* `infra-drift-autoclose.sh` —
  CUT: the script is a pure stdin→verdict classifier with a synthesized
  fixture harness; shelling out to terraform inside it would couple the
  classifier to credentials it never needed. The gate belongs in the
  workflow `if:`, where `steps.<id>.outputs` already live.
- Duplicating the `google_gws_recovery` config into this PR — CUT: open PR
  #10678 already carries the identical `dns.tf` block plus the merge-apply
  `-target=`; a second copy guarantees a semantic conflict (duplicate
  resource address).

### Reuse-instead-of-build evidence

- The full-root plan invocation already exists and is maintained:
  `scheduled-terraform-drift.yml` "Terraform plan (drift detection)" step —
  `doppler run --preserve-env --name-transformer tf-var -- terraform plan
  -detailed-exitcode -no-color -input=false` (+ `-var="ssh_key_path=…"`
  when `variables.tf` declares it — it does). The apply job already has
  every input this needs: `environment: infra-privileged`, `terraform init
  -lockfile=readonly` done at job start, `terraform_wrapper: false`
  (required for `-detailed-exitcode`), `CI_SSH_PUB` generated,
  `secrets.DOPPLER_TOKEN` for `prd_terraform`.
- `apps/web-platform/infra/infra-config-gate.test.sh` AC18 already parses
  the workflow YAML and pins every `success()`-gated step's `if:` verbatim —
  the natural enforcement point for the new conjunct.
- `infra-drift-autoclose.sh`'s wiring check already asserts the close step
  is one script invocation with no inline `gh issue close` — the chokepoint
  is already singular and tested.

### Applicable learnings

- `knowledge-base/project/learnings/2026-08-13-making-a-red-gate-green-arms-everything-it-was-silently-gating.md`
  — this exact workflow: a greened gate re-armed issue-closing steps that
  asserted unmeasured re-alignment. The property here is the same claim, one
  gate deeper.
- ADR-138 — close-authority boundary: automation may close an
  operator-facing issue only inside a bounded, fail-safe class of evidence.
- `2026-05-15-drain-plan-must-revalidate-issue-state-against-codebase.md` —
  issue state ≠ codebase reality; re-verify (done above for all three).
- #11294 (open) — `random_id` ids are key bytes that terraform prints on
  every refresh line. The drift cron avoids leaking them by capturing plan
  output in a command substitution. **The new step must follow the same
  discipline: capture `PLAN_OUTPUT`, never echo it raw; only the `^Plan:`
  count line (which carries no ids) may reach the log/summary.**

### Research Reconciliation — Spec vs. Codebase

| Brief claim | Reality on branch | Plan response |
|---|---|---|
| "closes … whenever its infra-config gate verdict is verified" | Also requires `PLAN_HAS_CHANGES == 'true'` and passes the issue-evidence classifier (#9416) | Fix targets the residual hole, not the (already-landed) hcloud gate |
| "plan delta contains exactly two resources" | 3 add / 4 destroy / 1 output — the inngest replace cascades into network + volume-attachment rows | Same root causes; comment text names all rows |
| "likely created outside the merged config (Cloudflare-side) or removed from config" | Applied 2026-10-20 through Terraform from the unmerged branch `feat-gcp-gws-domain-verification` (open PR #10678) | Reconcile via #10678, not a duplicated config block here |
| Community discovery (1.5) | No uncovered stacks — Terraform/GitHub Actions are existing covered surfaces | Skipped |
| Functional overlap (1.5b) | No Task/subagent tool in this context; a repo-internal CI gate fix has no community-artifact analog | Skipped — recorded |
| External research (1.6) | Internal CI fix against repo-owned machinery; all facts verified against the files themselves | Skipped — announced |

## Proposed Solution

Add one step and one conjunct in `apply-deploy-pipeline-fix.yml`:

```yaml
      # SECOND GATE, THIRD EVIDENCE (#9061). The infra-config verdict speaks
      # for the five -target terraform_data resources; the issue-evidence
      # classifier in scripts/infra-drift-autoclose.sh grades the issue's
      # NEWEST RECORDED plan — which predates this apply. Neither
      # re-measures the root. This step re-runs the drift cron's own
      # read-only measurement AFTER the apply, and the close step below
      # requires its exit code 0. `set +e` + captured EXIT_CODE mirror the
      # drift step exactly; PLAN_OUTPUT stays in the variable (refresh lines
      # print random_id key bytes — #11294) and only the `^Plan:` count
      # line reaches the summary.
      - name: Post-apply full-root drift plan
        id: drift_plan
        if: >-
          success() && env.PLAN_HAS_CHANGES == 'true'
          && (steps.infra_config_gate.outputs.verdict == 'verified'
              || steps.infra_config_gate_pass2.outputs.verdict == 'verified')
        working-directory: ${{ env.INFRA_DIR }}
        env:
          DOPPLER_TOKEN: ${{ secrets.DOPPLER_TOKEN }}
          DOPPLER_PROJECT: soleur
          DOPPLER_CONFIG: prd_terraform
        run: |
          set +e
          PLAN_OUTPUT=$(doppler run --preserve-env --name-transformer tf-var -- \
            terraform plan -detailed-exitcode -no-color -input=false \
            -var="ssh_key_path=${CI_SSH_PUB}" 2>&1)
          EXIT_CODE=$?
          set -e
          echo "exit_code=$EXIT_CODE" >> "$GITHUB_OUTPUT"
          case "$EXIT_CODE" in
            0) echo "::notice::Post-apply full-root plan is clean — the close step may run." ;;
            2) echo "::notice::Post-apply full-root plan still shows changes — every drift issue stays open." ;;
            *) echo "::error::Post-apply full-root plan FAILED (exit $EXIT_CODE) — not readable as clean; drift issues stay open and this run asserts nothing about drift." ;;
          esac
          printf '%s\n' "$PLAN_OUTPUT" | grep -E '^Plan: [0-9]+ to ' \
            >> "$GITHUB_STEP_SUMMARY" || true

      - name: Auto-close any open drift issues for this stack
        if: >-
          success() && env.PLAN_HAS_CHANGES == 'true'
          && steps.drift_plan.outputs.exit_code == '0'
          && (steps.infra_config_gate.outputs.verdict == 'verified'
              || steps.infra_config_gate_pass2.outputs.verdict == 'verified')
        …
```

- `steps.drift_plan.outputs.exit_code` resolves to empty when the step is
  skipped — `!= '0'`, so a skipped plan can never close (P2).
- Exit 1 (plan error, credential failure, lock) is explicitly not clean —
  `::error::` annotation, issues stay open, the job does not fail (the apply
  already ran and was verified; the diagnostic must not red a green apply).
- The per-issue classifier stays: it is the bot-authorship and
  evidence-readability filter (P4). The close comment text in `do_close()`
  is updated to name the new evidence — "a fresh full-root plan run by this
  job after the apply read no changes" replaces the stale-recorded-plan
  wording.

## Technical Considerations

- **`-detailed-exitcode` needs `terraform_wrapper: false`** — already set on
  this job's `setup-terraform` (line ~271); the wiring assertion keeps it
  load-bearing.
- **`doppler run` propagates the child exit code** — the drift cron depends
  on the same passthrough (`scheduled-terraform-drift.yml` "Terraform plan
  (drift detection)").
- **No raw plan output anywhere**: #11294 — `random_id` refresh lines print
  key bytes; the repo is public. `PLAN_OUTPUT` is captured in a command
  substitution (like the drift cron) and only `grep '^Plan: '` reaches
  `$GITHUB_STEP_SUMMARY`.
- **Plan is read-only** (refresh + exit code). The session constraint bars
  running plan/apply against production from this pipeline; the new step
  executes in the CI job that already holds `infra-privileged` and plans
  this root — the same authority the drift cron uses.
- **Cost**: one extra `plan` per verified apply run (~minutes, the cost the
  twice-daily cron already pays). Conditional — skipped entirely when the
  targeted plan had no changes or the verdict is not verified.
- **PR #10928 coordination**: its hunks are all in credential-loading
  steps; ours is the region around the close step. If it merges first,
  rebase; expected clean.
- **inngest `user_data` regression**: the new step's plan will show the
  pending `hcloud_server.inngest` replace until the host-replace window
  lands — meaning the gate is RED from merge until that window plus #10678.
  That is the gate working as designed; `infra-config-gate.test.sh` AC18's
  EXPECT-table update is the deliberate-change record.
- NFRs (nfr-register): reliability (a measured gate replaces an asserted
  one); no performance or security-boundary change beyond the no-echo
  discipline above.

## User-Brand Impact

- **If this lands broken, the user experiences:** the founder's public
  `infra-drift` issue(s) closed with "re-aligned with HEAD" while production
  still differs from config — the measured #8754→#8908 incident repeated,
  and a duplicate-filing loop that trains the founder to distrust the
  channel. The reverse failure (gate never green, resolved issues never
  auto-close) is benign: issues stay open for a hand close.
- **If this leaks, the user's data/workflow is exposed via:** terraform plan
  output printed to a public-repo Actions log — refresh lines carry
  `random_id` key bytes (#11294). Mitigated by construction: output is
  captured in a shell variable; only the aggregate `^Plan:` line reaches
  the step summary.
- **Brand-survival threshold:** `single-user incident`
- **Threshold decision (challengeable):** ADR-138 already classifies
  automated close authority over operator-facing issues as brand-survival;
  this change moves that authority onto measured evidence but does not
  remove the authority, so the tier stands. `requires_cpo_signoff: true` is
  set; the headless planning context could not spawn CPO — recorded in
  `specs/feat-one-shot-9061-drift-autoclose/decision-challenges.md` for the
  post-review confirmation.

## Observability

```yaml
liveness_signal:
  what: "the apply run's `drift-autoclose:` considered/closed/skipped line plus the new `exit_code=` output and `Plan:` line in the step summary"
  cadence: per-run (on every gated apply)
  alert_target: GitHub Actions run annotations + step summary (the channel the founder reads)
  configured_in: ".github/workflows/apply-deploy-pipeline-fix.yml (steps `drift_plan` and the auto-close step) + scripts/infra-drift-autoclose.sh run_loop summary"
error_reporting:
  destination: "workflow run log annotations (`::error::` on plan exit outside {0,2}, `::notice::` per left-open issue)"
  fail_loud: "exit_code missing or ==1 prints `::error::Post-apply full-root plan FAILED`; the drift-autoclose summary line prints considered/closed/skipped counts"
failure_modes:
  - mode: "full-root plan errors (exit 1 — credentials, lock, provider)"
    detection: "::error:: annotation on the run; drift-autoclose considered= line shows all-skipped"
    alert_route: "Actions run annotations (operator-facing; no page — the apply itself was verified)"
  - mode: "drift persists after apply (exit 2)"
    detection: "::notice:: + `Plan: N to add…` line in step summary; issues annotated left-open by the script"
    alert_route: run log + step summary
  - mode: "gate silently unwired (step renamed/id dropped/if edited)"
    detection: "infra-config-gate.test.sh AC18 EXPECT-table mismatch + the new drift-plan structural assert (both run in CI on this PR)"
    alert_route: PR checks
logs:
  where: GitHub Actions run log + GITHUB_STEP_SUMMARY "Drift auto-close" block
  retention: Actions retention window (repo default)
discoverability_test:
  command: "grep -nF \"steps.drift_plan.outputs.exit_code == '0'\" .github/workflows/apply-deploy-pipeline-fix.yml"
  expected_output: "steps.drift_plan.outputs.exit_code == '0'"
```

## Infrastructure (IaC)

No new infrastructure. The change is CI-side only (one read-only `terraform
plan` inside a job that already plans and applies this root).

### Terraform changes

- **None in this PR.** `cloudflare_record.google_gws_recovery`
  reconciliation is already carried by open PR **#10678** (`dns.tf` block +
  the `apply-web-platform-infra.yml` merge-apply `-target=` line), which is
  the correct owner — duplicating it here guarantees a same-address
  conflict. This PR comments on #10835/#10768 naming #10678 as the record's
  owner.

### Apply path

- **Not applicable** — no resources added, replaced, imported or destroyed
  by this change. The pending inngest host replace is owned by the
  host-replace window (#10966 prework, epic #10390); the record's keep-or-
  destroy question is settled by #10678's merge, or by a separately
  authorized teardown tracked outside this PR — per the session constraint,
  nothing here mutates production.

### Distinctness / drift safeguards

- The new step is **read-only** (`plan`, no `-out`, no apply) — it cannot
  mutate state; it runs under the same `infra-privileged` environment and
  `prd_terraform` credential path the drift cron uses.
- Constraint honored: nothing in this plan runs `terraform plan`/`apply`
  against production from the planning or work session; the gate executes
  in the deployed workflow only.

## Architecture Decision (ADR/C4)

- **ADR** — none created. The close-authority boundary is already recorded
  for this channel family by ADR-138's fail-safe allowlist principle and by
  the #7104/#9416 comments in the workflow and script; this change
  strengthens the evidence inside an existing boundary rather than moving
  one. If review disagrees, a short ADR titled "drift-issue close authority
  requires a fresh full-root plan" would record it — the call is left to
  reviewers rather than pre-committing an ordinal.
- **C4 views** — no C4 impact. Checked `model.c4` / `views.c4` / `spec.c4`:
  the external systems in play (GitHub Actions → GitHub Issues write edge;
  Terraform reading Hetzner/Cloudflare state; the "unauthenticated reader
  of the public repo" actor) are already modeled — the public-reader actor
  exists precisely because automation publishes to issues (#7500). No new
  actor, system, container, data store, or actor↔surface relationship is
  introduced; no edge cardinality changes.

## Guard Contract

The deliverable includes a gate — "an `infra-drift` web-platform issue may
be auto-closed only when a post-apply full-root `plan -detailed-exitcode`
exits 0" — so it carries a contract.

### Guard 1 — drift-autoclose fresh-plan gate

**Property.** The auto-close step runs only when the `drift_plan` step ran
first in the same job and exited `0` — i.e. a fresh untargeted plan of
`apps/web-platform/infra` read no changes after the apply.

**Assembly.** The chokepoints are (a) the workflow `if:` conjunction on the
single step named `Auto-close any open drift issues for this stack` (the
wiring check in `scripts/infra-drift-autoclose.test.sh` already proves it
is the only closer: exactly one step by that name, one script call, no
second `gh issue close` touching `infra-drift`), and (b) the `drift_plan`
step that produces the `exit_code` the conjunction reads — its `run:` must
invoke `terraform plan -detailed-exitcode` **without** `-target=` inside
`working-directory: apps/web-platform/infra`. Members: the close step, the
plan step, and the AC18 EXPECT table in
`apps/web-platform/infra/infra-config-gate.test.sh` that pins both `if:`
strings.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Drop `steps.drift_plan.outputs.exit_code == '0'` from the close step's `if:` (the pre-fix shape) | RED — AC18 EXPECT mismatch on that step |
| 2 | Delete `id: drift_plan` (or rename it) while leaving the `if:` — the gate's own dispatch gone; close can never see a clean reading | RED — structural assert fails (no step produces the referenced output); at runtime the condition also fails-closed |
| 3 | Move the auto-close step ABOVE the `drift_plan` step (order/lifetime — close precedes the measurement) | RED — ordering assert: plan-step index must precede close-step index |
| 4 | Drop `-detailed-exitcode` from the `drift_plan` run (plan exits 0 with changes pending) | RED — run-body assert requires the flag |
| 5 | Add `-target=terraform_data.deploy_pipeline_fix` to the `drift_plan` run (scoped plan masquerades as full-root) | RED — run-body assert rejects any `-target` in that step |
| 6 | Add a SECOND issue-closing step (`gh issue close` + `infra-drift`) elsewhere in the workflow | RED — existing wiring check `second-closer` arm |
| 7 | (harness) Neuter the new structural assert (e.g. it reads the wrong job's steps) while the workflow is correct | RED — a seeded harness self-test feeds a broken workflow YAML fixture and requires a non-`ok` verdict |
| 8 | (must-PASS, non-canonical) The `drift_plan` step's notice text is reworded | PASS — only `id:`, working-directory, the plan invocation and the exit-code output are load-bearing |

**Anchor.** The runtime reading comes from terraform's own process exit
code — outside the commit entirely; a diff cannot fake exit 0 on a drifted
root. The `if:` conjunction is pinned by AC18's EXPECT table in the same
repo — a single diff could edit both, so the anchor on the test side is PR
review of the EXPECT-table change itself plus the structural asserts (2–6)
that pin *shape*, not just the `if:` string.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "gate the close on a clean full-root drift plan (same read-only plan `scheduled-terraform-drift.yml` runs), OR only comment instead of closing. A close should mean \"a full-root plan now reads no changes\". [issue #9061]" | `drift_plan` step + close-step `if:` conjunct (Files to Edit 1) | mapped |
| 2 | "whatever config/code reconciliation the plan decides for the google_gws_recovery record [brief]" | Route to open PR #10678 (already adds the record to `dns.tf` + merge-apply target); this PR does not duplicate it — see `### Terraform changes` | mapped |
| 3 | "the plan should say how the PR body/issues should represent that (e.g., comment on #10835/#10768 explaining the residual, whether either should be closed by this PR or kept open until the replace lands) [brief]" | Phase 3 issue-comment tasks with prescribed text; both stay open; PR body `Closes #9061` only | mapped |
| 4 | "do NOT run terraform apply locally or anywhere, do NOT run terraform plan against production state, and do NOT mutate any production infra [brief]" | Hard constraint; the plan gate executes inside the deployed CI workflow only — no session-side terraform | mapped |
| 5 | "coordinate the edit to minimize conflict [brief — sibling PR edits the same workflow]" | Dependencies & Risks: #10928 hunk map is disjoint; rebase note | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| New `drift_plan` step in `apply-deploy-pipeline-fix.yml` | "gate the close on a clean full-root drift plan (same read-only plan `scheduled-terraform-drift.yml` runs)" | asked |
| `if:` conjunct on the close step | "A close should mean \"a full-root plan now reads no changes\"" | asked |
| `infra-config-gate.test.sh` AC18 EXPECT update | — | inferred — justification: AC18 pins every success()-gated `if:` verbatim; the test must move with the deliberate change or CI reds |
| New structural asserts in `infra-drift-autoclose.test.sh` wiring check | — | inferred — justification: Guard Contract rows 2–6 need a mechanical seat; the wiring check is the existing chokepoint assertion |
| `do_close()` comment text update in `infra-drift-autoclose.sh` | "A close should mean \"a full-root plan now reads no changes\"" | asked — keeps the posted claim truthful under the new evidence |
| Issue comments on #10835/#10768; no `Closes` for them in PR body | "comment on #10835/#10768 explaining the residual, whether either should be closed by this PR or kept open" | asked |

### Split Assessment

- Subsystems touched: 3 — `.github/workflows`, `scripts`, `apps/web-platform/infra`
- Planned files: 4 | Estimated changed lines: ~110
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## Files to Edit

1. `.github/workflows/apply-deploy-pipeline-fix.yml` — insert the
   `drift_plan` step immediately before `Auto-close any open drift issues
   for this stack`; add the `steps.drift_plan.outputs.exit_code == '0'`
   conjunct to that step's `if:`; extend the comment block naming the
   third evidence gate.
2. `apps/web-platform/infra/infra-config-gate.test.sh` — AC18 EXPECT
   table: add the `Post-apply full-root drift plan` entry (same `if:`
   shape as the close step) and update the close-step entry with the new
   conjunct; the failure text stays accurate (say why in the commit).
3. `scripts/infra-drift-autoclose.sh` — `do_close()` close-comment text
   now cites the fresh full-root plan as evidence; the header comment
   gains the third-evidence line. No classifier/slug changes.
4. `scripts/infra-drift-autoclose.test.sh` — extend `wiring_check` (or a
   sibling assert in the same file) with the Guard-1 structural rows: the
   `drift_plan` step exists, precedes the close step, runs
   `plan -detailed-exitcode` with no `-target`, uses
   `working-directory: apps/web-platform/infra`, and exports `exit_code`;
   plus the seeded-broken-fixture harness row. Keep the existing
   single-closer and env assertions intact.

## Files to Create

None.

## Acceptance Criteria

- [ ] `apply-deploy-pipeline-fix.yml` contains a step `id: drift_plan` that
  runs `terraform plan -detailed-exitcode -no-color -input=false` under
  `doppler run --preserve-env --name-transformer tf-var --` in
  `apps/web-platform/infra` with `-var="ssh_key_path=${CI_SSH_PUB}"`,
  writes `exit_code` to `$GITHUB_OUTPUT`, and prints no raw plan output
  (no `random_id` refresh lines to the log — #11294).
- [ ] The `Auto-close any open drift issues for this stack` step's `if:`
  contains `steps.drift_plan.outputs.exit_code == '0'`; the step still
  calls `scripts/infra-drift-autoclose.sh` unchanged in shape (wiring
  check green).
- [ ] `bash apps/web-platform/infra/infra-config-gate.test.sh` passes with
  the updated AC18 EXPECT table (both new entries pinned verbatim).
- [ ] `bash scripts/infra-drift-autoclose.test.sh` passes, including the
  new structural asserts: removing `id: drift_plan`, reordering the steps,
  dropping `-detailed-exitcode`, or adding `-target` each fail RED.
- [ ] The `drift_plan` step's `if:` is `success() && env.PLAN_HAS_CHANGES
  == 'true' && <verdict disjunction>` so it runs exactly when the close
  gate is eligible; a skipped or errored plan yields no
  `exit_code == '0'` and the close step cannot fire (fail-closed).
- [ ] Comments are posted to #10835 and #10768 with the prescribed
  residual text (inngest replace → host-replace window #10966/#10390;
  `google_gws_recovery` → PR #10678); both issues remain OPEN; neither
  appears in a `Closes` line anywhere in the PR body — only
  `Closes #9061`.
- [ ] No step in this plan's implementation prescribes a session-side
  `terraform apply`, `terraform import`, or `terraform plan` against
  production (the session constraint — the gate executes in CI only).
- [ ] PR body names the #10928 coordination note and links #10678 as the
  record's owner.

## Test Scenarios

- Given the workflow YAML, when `infra-config-gate.test.sh` runs, then the
  AC18 step set contains both `Post-apply full-root drift plan` and
  `Auto-close any open drift issues for this stack` with their pinned
  `if:` strings — `unit`.
- Given a mutated workflow with the close step reordered above the plan
  step, when the wiring check runs, then it reports the ordering defect —
  `unit` (mutation row 3).
- Given a mutated workflow missing `-detailed-exitcode` or carrying
  `-target=` in the `drift_plan` run, when the wiring check runs, then it
  reports the run-body defect — `unit` (mutation rows 4–5).
- Given a mutated workflow with no `id: drift_plan`, when the wiring check
  runs, then it reports the missing producer — `unit` (mutation row 2).
- Given the real workflow, when the drift-plan step executes in a live run
  with residual drift, then `exit_code=2`, the `::notice::` prints, and
  the close step is skipped — `integration` (verified by the first live
  run after merge; the current inngest/gws residual guarantees this arm
  exercises immediately).
- Given the real workflow once the root is clean, when the step executes,
  then `exit_code=0` and the close step runs the existing classifier —
  `integration` (exercises after #10678 + host-replace land).

## Success Metrics

- No `infra-drift` issue is auto-closed while a full-root plan would still
  exit 2 — the #8754/#8908 close-then-duplicate cycle cannot recur.
- The next verified apply after the root goes clean closes the then-open
  drift issue(s) with a comment whose claim is backed by the fresh plan.
- Issue noise: zero new duplicate `infra: drift detected in web-platform`
  filings attributable to a false close.

## Dependencies & Risks

- **PR #10928** edits the same workflow (credential-loading hunks only —
  verified by `gh pr diff`); merge order is free, rebase if it lands
  first.
- **Gate is red by design until two outs land**: #10678 (record config)
  and the inngest host-replace window (#10966 prework, epic #10390).
  During that window every verified apply prints the `exit 2` notice and
  closes nothing — correct, but worth a line in the PR body so nobody
  "fixes" the red.
- **#11294 adjacency**: the step deliberately does not print plan output;
  the broader "terraform prints random_id ids" audit is out of scope.
- **Filer dedupe anomaly** (why #10835 exists beside #10768): observed
  once, transient; not fixed here — noted so reviewers don't fold it in.

## Domain Review

**Domains relevant:** Engineering

### Engineering

**Status:** reviewed (partial — no Task/subagent tool in this pipeline
context; inline assessment by the planner, flagged for `plan-review`)
**Assessment:** The change tightens an existing fail-closed boundary rather
than adding a mechanism. Two design points carry the risk: (a) the gate
must read terraform's own exit code, not a proxy — satisfied by
`-detailed-exitcode` under `terraform_wrapper: false` (already set), the
same contract the drift cron relies on; (b) the fresh plan must be
untargeted — a `-target=` edit re-opens the exact defect, covered by
Guard-1 mutation row 5. Architectural precedent is ADR-138 (close-authority
boundaries on operator-facing issues). The `doppler run`/`prd_terraform`
credential path is identical to the drift leg's; no new credential surface.

### Product/UX Gate

**Tier:** N/A — no user-facing surface. Mechanical UI-surface override did
not fire: `## Files to Edit`/`## Files to Create` contain no
`components/**`, `app/**/page.tsx`, `*.njk`, `*.html`, or sibling
UI-surface paths; the diff is `.github/workflows/`, `scripts/`, and a
`*.test.sh`.

## Open Code-Review Overlap

One open `code-review` issue mentions a touched-adjacent file:

- **#3828** "review: extract composite action for 9-workflow Sentry Crons
  check-in fan-out" — mentions `scheduled-terraform-drift.yml`.
  **Acknowledge**: its concern is the Sentry-crons fan-out section of that
  file; this plan does not edit that file at all. No action.

## GDPR Gate (Phase 2.7 record)

Canonical regex surfaces touched: none (no migrations, auth, API routes,
`.sql`). Trigger (b) fires (`single-user incident` threshold declared), so
a bounded pass ran inline (no skill-spawn tool in this context): the diff
introduces no new processing activity, no PII surfaces, no cross-border
vendor data — it gates a GitHub-issue close on a terraform exit code. The
five mandatory checks are all N/A (no schema columns, no PII tables, no
FKs, no new vendor env). Findings: none. Advisory only — this is not legal
review.
