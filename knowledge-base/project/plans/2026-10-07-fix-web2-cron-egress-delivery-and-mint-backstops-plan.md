---
title: "Deliver cron-egress artifacts to running web-2 via deploy_pipeline_fix_web2 + inngest-bootstrap auto-mint backstops"
type: fix
date: 2026-10-07
slug: web2-cron-egress-delivery-and-mint-backstops
branch: feat-one-shot-9393-9082-egress-mint-watch
issue: 9393
closes: [9393, 9082]
priority: p2
domain: infra
lane: cross-domain
---

# Deliver cron-egress artifacts to running web-2 via deploy_pipeline_fix_web2 + inngest-bootstrap auto-mint backstops

<!-- iac-routing-ack: plan-phase-2-8-reviewed -->
<!-- The systemctl restart named below is executed BY the terraform_data
     deploy_pipeline_fix_web2 provisioner (the delivered assert script) — every
     state change is routed through Terraform; no operator-manual step exists. -->

Spec lacks valid lane: — defaulted to cross-domain (TR2 fail-closed).

Two sibling cron/scheduling pipeline fixes in one PR:

- **#9393** — `terraform_data.cron_egress_firewall` is pinned to `hcloud_server.web["web-1"]`
  and `deploy_pipeline_fix_web2` carries no cron-egress artifact, so a *running* web-2 keeps
  the old container egress allow list and resolver and runs no probe until its next replace.
- **#9082** — after `mint-inngest-bootstrap-tag.yml` shipped (#4326), two observability gaps
  remain: Guard A compares carriers only (a pin or Dockerfile-recipe change produces no mint
  run and nothing reds), and nothing watches the mint workflow's own conclusion.

## Overview

- **#9393:** deliver the three cron-egress artifacts — the carved CIDR file
  (`cron-egress-allowlist-cidr.txt`), the resolver (`cron-egress-resolve.sh`), and the probe
  (`cron-egress-postapply-assert.sh`, which re-runs the loader and runs the live
  positive/negative/GHCR-carve container probes) — through the existing SSH sibling
  `terraform_data.deploy_pipeline_fix_web2` in `apps/web-platform/infra/server.tf`, with
  parity tests. This is the code-only arm of the issue's two options; the
  web-host-replace dispatch is an operator-authorized production action and stays out of
  scope.
- **#9082(1):** add a sibling block ("Guard A2") to
  `apps/web-platform/infra/cloud-init-inngest-bootstrap.test.sh` comparing the four image
  pins (`inngest_cli_version`/`inngest_cli_sha256`, `vector_version`/`vector_sha256`) and the
  Dockerfile heredoc between the pinned tag and HEAD, reusing the mint script's extractors,
  with byte-parity rows in `.github/scripts/test/test-mint-inngest-bootstrap-tag.sh`'s Guard
  3 parity harness.
- **#9082(2):** add a slow-path check to `main-health-monitor.yml` reading the latest
  `mint-inngest-bootstrap-tag.yml` run on `main` and counting `failure` or `startup_failure`
  as red, following the queue-health sweep conventions (2026-10-06): `gh --json` piped to
  standalone jq (never `gh --jq --arg`), no pipe-fed `grep -q` readers, fail-open with a
  visible `::error::` on API failure.

## Problem Statement / Motivation

- **#9393:** after #9275 merged the GHCR carve (PR #9385), web-1 received the carve, resolver
  and probe via apply run 37209725107 (2026-10-04). The running web-2 does not:
  `terraform_data.cron_egress_firewall` SSHes only web-1, `deploy_pipeline_fix_web2`
  (the only channel that reaches a running web-2, through the web-1 bastion forward) carries
  none of the cron-egress files, and `cloud-init`/image-bake delivery reaches only fresh
  hosts. Until its #9372 rebirth, web-2's bridge containers still admit GHCR and no
  enforcement probe runs there. The issue's chosen option is code delivery through
  `deploy_pipeline_fix_web2` — superseding the 2026-10-03 "rebirth-only" decision recorded
  in the issue comments and in `cron-egress-blocked.md`, which this PR must update.
- **#9082(1):** the mint decision (`.github/scripts/mint-inngest-bootstrap-tag.sh`,
  `stage_decide`) compares carriers + four pins + recipe, but Guard A — the CI-visible
  backstop — compares carriers only. A merge that changes `inngest_cli_version` (etc.) or the
  Dockerfile heredoc while the mint run is skipped/dropped/failed leaves no red anywhere.
- **#9082(2):** a red `mint-inngest-bootstrap-tag.yml` run reaches the operator only through
  its Slack step; if `SLACK_RELEASES_WEBHOOK_URL` is unset or the post fails, the red run is
  invisible.

## Proposed Solution

### #9393 — web-2 delivery through the existing sibling

`deploy_pipeline_fix_web2` already dials web-2 over SSH through the bastion forward opened
by `apply-deploy-pipeline-fix.yml`, delivers ~20 non-credential artifacts with per-file
`filesha256` content assertions, and re-fires on `hcloud_server.web["web-2"].id` change.
Extend it, do not create a new resource:

- Add the three `file()` entries to `triggers_replace` (an artifact edit re-fires delivery)
  and bump the inline sentinel `dpf-web2-remote-exec-v1` → `v2` (the lockstep rule for
  inline remote-exec edits).
- Add `mkdir -p /etc/soleur` to the first remote-exec's mkdir line (parity with the web-1
  resource; exists on web-2 from birth but the mkdir is idempotent and the parity guard
  expects the destination parent to be asserted).
- Add three `provisioner "file"` blocks:
  `cron-egress-allowlist-cidr.txt` → `/etc/soleur/cron-egress-allowlist-cidr.txt` (0644),
  `cron-egress-resolve.sh` → `/usr/local/bin/cron-egress-resolve.sh` (0755),
  `cron-egress-postapply-assert.sh` → `/usr/local/bin/cron-egress-postapply-assert.sh` (0755).
- Extend the remote-exec: root:root chown + mode chmods, one `sha256sum` content assertion
  per delivered file (same shape as the existing 20), then execute
  `bash /usr/local/bin/cron-egress-postapply-assert.sh` — identical to the web-1 resource's
  terminal step. The assert restarts `cron-egress-firewall.service` (loading the new carve
  into the live nft set), enables the resolve timer, asserts the nft structure, and runs the
  GHCR-carve + positive/negative container probes against the running
  `soleur-web-platform` container. It skips the container probes LOUDLY when the container
  is absent (fresh-host arm) — never silently.
- Update the resource's scope-boundary comment to name the three new deliveries.
- Add the three artifact paths to `apply-deploy-pipeline-fix.yml`'s `on.push.paths` — a
  body-only edit to a hashed artifact must re-fire the apply (the #5505 lesson; the paths
  filter is an explicit list, and `server.tf` alone matching is not enough for
  artifact-only PRs like the daily CIDR-refresh regeneration).
- Update `cron-egress-blocked.md` "Known residual: running web-2" — the delivery channel is
  now `deploy_pipeline_fix_web2`; rebirth remains the closing event for the *whole* artifact
  set (loader/alarm/units stay birth-frozen until #9372), but the carve+resolver+probe gap
  this issue names closes on the next apply run.

### #9082(1) — Guard A2 sibling block

New block after Guard A in `cloud-init-inngest-bootstrap.test.sh` (keeps Guard A's pinned
11-assert inventory intact):

- Reuse `GA_TAG_REF` (the pinned tag literal) and `ga_cmp` (the instrumented comparator).
- Extract the four pins at `vinngest-$GA_PIN_TAG` and at HEAD via `git show <ref>:<path>`,
  using extractor lines byte-identical (modulo variable/file operand) to the mint script's
  `p_iv`/`p_is`/`p_vv`/`p_vs` lines; extract the Dockerfile heredoc with the mint script's
  awk recipe extractor over the build workflow at both refs.
- Per-pin asserts + one recipe assert (byte-parity via `ga_cmp`), unresolvable-side rows
  (a pin absent at the tag is a finding, not "nothing to compare"), non-empty extractor
  rows (an empty pin or 0/!=1 recipe blocks reds, never compares-equal), and an exact-count
  anti-vacuity floor for the new section.
- Byte-parity rows: extend `g3_parity` in `test-mint-inngest-bootstrap-tag.sh` so the test's
  pin extractors and recipe extractor are pinned token-identical (same normalization style
  as the existing `GA_CP_PATHS:CP_PATHS` loop) to the mint script's — the
  "reusing the mint script's extractors" requirement is mechanical, not aspirational.

### #9082(2) — mint-conclusion slow-path check

New step in `main-health-monitor.yml`'s `health-check` job (after the infra suite step,
before "Record step outcomes"):

- `id: mintwatch`, `continue-on-error: true`, no `timeout-minutes` (its only calls are
  `timeout`-bounded `gh` API reads; adding a timed step would break the job-ceiling
  derivation the suite pins at `sum+15`).
- `gh run list --workflow=mint-inngest-bootstrap-tag.yml --branch main --limit 3
  --json databaseId,conclusion,status,createdAt,headSha` captured to a variable, parsed by a
  standalone `jq` (never `gh --jq`; `#9533` — `--jq` does not forward `--arg`), no pipe-fed
  `grep -q` readers (predicate values via `grep -c` on captured vars or jq `length`).
- Output `verdict=red` when the newest *completed* run's conclusion is `failure` or
  `startup_failure`; `green` otherwise (success, skipped, cancelled, or no completed run —
  only the two named conclusions count as red per the issue); `unknown` on gh/jq failure,
  which emits `::error::` (fail-open, visible — never a silent green) but does not red.
- Wire the verdict: the "Create issue on failure" `if:` gains
  `|| steps.mintwatch.outputs.verdict == 'red'`; a mint-red run produces its own arm in the
  filer (TITLE/LEDE/ACTIONS naming the run and conclusion — AP-021: name only what was
  measured); a mint-red + suite-green run does NOT take the "setup failure" arm. The closer
  `if:` gains `&& steps.mintwatch.outputs.verdict != 'red'` so a green-suite sweep cannot
  retire a mint-filed tracker. The Sentry check-in status gains the same `!= 'red'` conjunct.
- `plugins/soleur/test/main-health-monitor-workflow.test.sh` gains rows pinning: the step's
  presence and read-only shape, the `--json`-to-standalone-jq convention, the
  failure/startup_failure red set, the filer/closer/heartbeat wiring, and `!inputs.dry_run`
  coverage where side-effecting.

## Technical Considerations

- **No production writes.** The diff changes IaC definitions, workflow YAML and tests only —
  no `terraform apply`, no `workflow_dispatch` on apply/deploy workflows, no prod host
  writes. Delivery to web-2 happens when the operator-enabled `apply-deploy-pipeline-fix.yml`
  next runs (it was `active` as of 2026-10-04); this PR is the mechanism, not the event.
- **Credential boundary preserved.** The three files carry no credential material —
  `deploy_pipeline_fix_web2`'s boundary (no `webhook_doppler_token_env`/`SOLEUR_DOPPLER_TOKEN`)
  is untouched; `web-host-provisioner-parity.test.sh` §1 already pins that.
- **Fresh-boot parity already holds.** All three destinations have `soleur-host-bootstrap.sh`
  install counterparts, so the parity guard's destination sweep covers the new writes
  without an allowlist entry.
- **Guard A2's known caveat:** like Guard A today, a PR that *legitimately* bumps a pin reds
  the new rows pre-merge — the same open limitation tracked by #9081 (PR-context exemption,
  still open, out of scope). On main it is the intended backstop: pinned tag behind HEAD ⇒
  a mint run was missed.
- **`startup_failure`** is a distinct GitHub run `conclusion` value (the job never started);
  it must be in the red set explicitly, not folded into `failure`.

## Research Reconciliation — Spec vs. Codebase

| Spec/issue claim | Reality on this branch | Plan response |
|---|---|---|
| #9393 comment (2026-10-03): "web-2 delivered by rebirth only, no new delivery code" | Issue still OPEN; task prompt supersedes: deliver via `deploy_pipeline_fix_web2` (code-only arm) | Implement the delivery arm; update `cron-egress-blocked.md` + note the supersession in the PR body |
| "Guard A compares carriers only" | Confirmed — Guard A (lines ~1242–1369) iterates `GA_CP_PATHS` carriers only; pins/recipe unexamined | Guard A2 sibling block |
| "nothing watches the mint workflow's own conclusion" | Confirmed — `main-health-monitor.yml` has no mint step; Slack is the only red-run channel | mintwatch slow-path step |

## Infrastructure (IaC)

### Terraform changes

- `apps/web-platform/infra/server.tf` — `resource "terraform_data" "deploy_pipeline_fix_web2"`
  extended in place (no new resource, no new root, no new provider): +3 `file()` entries in
  `triggers_replace`, +3 `provisioner "file"` blocks, remote-exec extensions, sentinel bump.
- No new variables, secrets, or providers. `var.ci_ssh_private_key` / `local.web_2_ssh_host_key`
  reused unchanged.

### Apply path

(b) cloud-init + idempotent bootstrap script — the existing
`apply-deploy-pipeline-fix.yml` → `terraform plan/apply -target=terraform_data.deploy_pipeline_fix_web2`
channel is the apply path; it runs only when the operator-enabled workflow next fires.
Expected blast-radius: one `terraform_data` resource replaced; SSH file delivery + service
restart on a weight-0 standby host (no tenant traffic per `cron-egress-blocked.md`).

### Distinctness / drift safeguards

- `hcloud_server.web` carries `ignore_changes = [user_data, …]` — delivered artifacts reach
  running hosts ONLY through this channel; the triggers hash + server-id fold prevents
  silent skips on re-image/replace.
- Per-file `filesha256` content assertions mirror the resource's existing 20-file contract.
- Fresh-boot parity: all three destinations are already written by
  `soleur-host-bootstrap.sh` — the dual-delivery invariant holds without allowlist growth.

### Vendor-tier reality check

None — no new vendor resources.

## User-Brand Impact

- **If this lands broken, the user experiences:** nothing directly user-facing — the failure
  surface is a CI/guard red or a failed `terraform_data` provisioner (loud, not silent). The
  protected artifact is container-egress enforcement on a weight-0 standby host.
- **If this leaks, the user's [data / workflow / money] is exposed via:** no new data or
  credential surface — the three artifacts are allowlist/systemd/probe files already
  delivered to web-2 at birth by the image bake.
- **Brand-survival threshold:** `none`
- **Threshold decision (challengeable):** the diff changes delivery plumbing and CI guards
  around an existing security control; web-2 carries no tenant traffic today, so a broken
  landing cannot touch a user workload, and the delivered assert makes a mis-delivery loud.
- `threshold: none, reason: infra/CI plumbing and guard definitions only — no user-facing
  artifact changes; web-2 is a weight-0 standby and the diff's own assertion layer makes a
  mis-delivery red, not silent` (sensitive-path scope-out: `apps/web-platform/infra/` and
  `apply-deploy-pipeline-fix.yml` match the canonical regex).

## Observability

```yaml
liveness_signal:
  what: "Sentry cron monitor check-in for main-health-monitor (the watcher's own liveness); ci/main-broken tracker for the mint conclusion + suites"
  cadence: "6h (Inngest cron-main-health-monitor dispatch)"
  alert_target: "Sentry missed-check-in page; ci/main-broken issue"
  configured_in: "apps/web-platform/infra/sentry/cron-monitors.tf; .github/workflows/main-health-monitor.yml (Sentry check-in step)"

error_reporting:
  destination: "ci/main-broken GitHub issue (sentinel-deduped) + ::error:: workflow annotation"
  fail_loud: "::error::Main branch health check did not pass ... ; mintwatch ::error:: on API failure (fail-open, never silent green)"

failure_modes:
  - mode: "mint-inngest-bootstrap-tag.yml latest main run concludes failure|startup_failure"
    detection: "mintwatch step reads gh run list --json via standalone jq; verdict=red feeds filer + heartbeat"
    alert_route: "ci/main-broken tracker + Sentry check-in error"
  - mode: "cron-egress artifact drifts on web-2 (edit lands, delivery not re-fired)"
    detection: "triggers_replace hash moves → next apply re-provisions; parity test pins delivery set"
    alert_route: "apply-deploy-pipeline-fix.yml run failure (ASSERT-FAILED sentinel) / CI red"
  - mode: "pin or recipe change merges with no mint run"
    detection: "Guard A2 byte-parity rows (pinned tag vs HEAD) in cloud-init-inngest-bootstrap.test.sh"
    alert_route: "infra-validation deploy-script-tests red + main-health-monitor suite red"

logs:
  where: "GitHub Actions run logs (main-health-monitor, apply-deploy-pipeline-fix); suite stdout"
  retention: "GitHub Actions retention window"

discoverability_test:
  command: grep "id: mintwatch" .github/workflows/main-health-monitor.yml
  expected_output: "id: mintwatch"
```

## Encryption Posture

Not applicable — no new persistent data store, no new cross-component/network connection
(the SSH channel, file set, and probe are pre-existing; the mint watch is a read-only API
call over the runner's existing `GH_TOKEN`).

## Guard Contract

### Guard 1 — web-2 cron-egress delivery parity (cron-egress-firewall.test.sh, new section)

**Property.** The three cron-egress artifacts the issue names are delivered to web-2 by
`deploy_pipeline_fix_web2` with the same destinations and content-hash assertions the web-1
resource uses, and the delivered assert script is executed.

**Assembly.** `server.tf` `resource "terraform_data" "deploy_pipeline_fix_web2"` — the
`triggers_replace` `file()` list, every `provisioner "file"` `source`/`destination` pair,
and the remote-exec block; sliced to the resource block (same `awk '/resource .../,/^}/'`
spanner the suite already uses) so a same-named file delivered by ANOTHER resource cannot
satisfy the row.

**Mutation matrix:**

| # | Mutation | Expected |
|---|----------|----------|
| 1 | Drop `cron-egress-allowlist-cidr.txt` from the sibling's file provisioners | RED |
| 2 | Remove the `bash /usr/local/bin/cron-egress-postapply-assert.sh` execution line (delivery lands but the probe never runs) | RED |
| 3 | Deliver a fourth cron-egress file to only one resource (destination asymmetry between `cron_egress_firewall` and the sibling for the three named files) | RED |
| 4 | Remove a `file()` entry from the sibling's `triggers_replace` (delivery present but never re-fires on artifact edit) | RED |

### Guard 2 — Guard A2 pin/recipe drift (cloud-init-inngest-bootstrap.test.sh + Guard 3 parity)

**Property.** The four image pins and the Dockerfile heredoc are identical between the
pinned `vinngest-v*` tag and HEAD, extracted by lines byte-identical to the mint script's.

**Assembly.** `git show $GA_TAG_REF:<path>` vs the working copy for
`apps/web-platform/infra/inngest.tf`, `apps/web-platform/infra/vector.tf`, and
`.github/workflows/build-inngest-bootstrap-image.yml`; the extractors are the mint script's
(`grep -E '^\s*<pin>\s*=' | sed -E …` and the recipe awk), pinned token-identical by new
`g3_parity` rows in `test-mint-inngest-bootstrap-tag.sh`.

**Mutation matrix:**

| # | Mutation | Expected |
|---|----------|----------|
| 1 | Bump `inngest_cli_version` at HEAD only (tag behind) | RED on the pin row |
| 2 | Delete a pin extractor line from the suite (guard inspects 3 of 4 pins and reports green) | RED on the exact-count anti-vacuity floor |
| 3 | Diverge the suite's extractor from the mint script's (same intent, different tokens) | RED on the g3_parity row |
| 4 | A recipe edit at HEAD (heredoc body differs from the tag's) | RED on the recipe row |

### Guard 3 — mint-conclusion watch (main-health-monitor.yml + its test)

**Property.** A `failure`/`startup_failure` conclusion on the newest completed
`mint-inngest-bootstrap-tag.yml` run on main is counted as red by the monitor, filed through
the sentinel-deduped tracker, and reported to the Sentry check-in; an API failure is a
visible `::error::`, never a silent green.

**Assembly.** The `mintwatch` step output `verdict`, consumed by exactly three sites: the
filer `if:`, the closer `if:`, the heartbeat `status:`. The workflow test pins all three
consumers plus the step's `gh --json`→standalone-jq shape.

**Mutation matrix:**

| # | Mutation | Expected |
|---|----------|----------|
| 1 | Drop `startup_failure` from the red set (a job that never started reads as green) | RED on the test's red-set row |
| 2 | Remove the mint disjunct from the filer `if:` (verdict computed but never filed) | RED on the wiring row |
| 3 | Swap `gh run list … --json … | jq` for `gh --jq` or a pipe-fed `grep -q` reader | RED on the convention row |
| 4 | Closer `if:` drops the `!= 'red'` conjunct (green suites retire a mint tracker) | RED on the closer row |

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "deliver the three cron-egress artifacts through `deploy_pipeline_fix_web2` (the deploy-time delivery path that reaches running hosts), with parity tests" | §Proposed Solution #9393; Guard 1 | mapped |
| 2 | "Extend Guard A (or a sibling row in `apps/web-platform/infra/cloud-init-inngest-bootstrap.test.sh`) to compare the four image pins and the Dockerfile heredoc between the pinned tag and HEAD, reusing the mint script's extractors, with byte-parity rows" | §Proposed Solution #9082(1); Guard 2 | mapped |
| 3 | "add a slow-path check to `main-health-monitor.yml`: read the latest `mint-inngest-bootstrap-tag.yml` run on `main` and count `failure` or `startup_failure` as red" | §Proposed Solution #9082(2); Guard 3 | mapped |
| 4 | "Do NOT take the other arm (dispatching web-host-replace is an operator-authorized prod action — out of scope)" | non-goal; documented | mapped |
| 5 | "PR body MUST include `Closes #9393` and `Closes #9082`, each on its own body line" | ship-phase requirement | mapped |

### Plan-Item Provenance

| Plan item | User words cited | Verdict |
|-----------|------------------|---------|
| Three artifact files delivered via web2 sibling | "deliver the three cron-egress artifacts through deploy_pipeline_fix_web2" | asked |
| `apply-deploy-pipeline-fix.yml` paths additions | "with parity tests" + the delivery channel must actually fire on artifact edits (the #5505 lesson encoded in this repo) | inferred — required for the delivery to be reachable on future artifact-only merges |
| `cron-egress-blocked.md` residual update | delivery path changes the documented residual | inferred — keeps the runbook truthful |
| Guard A2 sibling block + Guard 3 parity rows | "a sibling row … reusing the mint script's extractors, with byte-parity rows" | asked |
| mintwatch step + filer/closer/heartbeat wiring | "count `failure` or `startup_failure` as red (fail-open-with-`::error::` dedupe conventions…)" | asked |
| Test file updates (ship-deploy-pipeline-fix-gate, main-health-monitor-workflow) | "with parity tests" + coupled-surface tests that would otherwise red | inferred |

### Split Assessment

- Subsystems touched: 3 — `apps/web-platform/infra/` (Terraform + shell suites), `.github/workflows/` + `.github/scripts/`, `plugins/soleur/test/` + `knowledge-base/` runbook.
- Planned files: ~8 | Estimated changed lines: ~450
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR — the two issues are sibling cron/scheduling pipeline fixes the dispatch groups deliberately; each is independently reviewable by section.

## Acceptance Criteria

- [ ] `terraform_data.deploy_pipeline_fix_web2` in server.tf delivers
      `cron-egress-allowlist-cidr.txt` → `/etc/soleur/`, `cron-egress-resolve.sh` →
      `/usr/local/bin/`, `cron-egress-postapply-assert.sh` → `/usr/local/bin/`; all three
      `file()` basenames are in its `triggers_replace`; remote-exec asserts each file's
      `filesha256` and executes the assert script; the inline sentinel is bumped; modes are
      0755 for the two scripts, 0644 for the CIDR file, all root:root.
- [ ] `apply-deploy-pipeline-fix.yml` `on.push.paths` includes the three cron-egress paths.
- [ ] `cron-egress-firewall.test.sh` (or a sibling suite) pins the web-2 delivery set:
      resource-scoped source/destination pairs, triggers entries, the assert-execution line —
      and is driven RED by each Guard-1 matrix mutation (mutation-proven).
- [ ] `cloud-init-inngest-bootstrap.test.sh` compares the four pins + Dockerfile heredoc
      between `vinngest-$GA_PIN_TAG` and HEAD with per-item byte-parity asserts, non-empty
      extractor guards, and an exact-count anti-vacuity floor; Guard 3 parity rows pin the
      extractors token-identical to `mint-inngest-bootstrap-tag.sh`.
- [ ] `main-health-monitor.yml` reads the newest completed mint run on main via
      `gh run list --json` → standalone `jq`; `failure`/`startup_failure` → `verdict=red`
      feeding the filer (dedicated arm), closer (non-closing conjunct), and heartbeat; a gh/jq
      failure emits `::error::` and resolves `unknown` (never silent green).
- [ ] `plugins/soleur/test/main-health-monitor-workflow.test.sh` and
      `plugins/soleur/test/ship-deploy-pipeline-fix-gate.test.ts` updated for the new
      surfaces (expected paths set, web2 allowed set, mintwatch wiring rows).
- [ ] `cron-egress-blocked.md` "Known residual: running web-2" updated for the new channel.
- [ ] No `terraform apply`, no workflow_dispatch, no prod host writes; PR body contains
      `Closes #9393` and `Closes #9082` on their own lines.

## Test Scenarios

- Given `server.tf` with the three artifacts dropped from `deploy_pipeline_fix_web2`, when
  the parity suite runs, then the named delivery rows red (Guard-1 mutation arm).
- Given HEAD's `inngest_cli_version` bumped vs the pinned tag, when Guard A2 runs, then the
  `inngest_cli_version` row reds naming the pin.
- Given the mint suite's pin extractor token drifted from the mint script's, when
  `test-mint-inngest-bootstrap-tag.sh` runs, then the `g3_parity` row reds.
- Given a fixture where the newest completed mint run concludes `startup_failure`, when the
  mintwatch shape is exercised (test rows + `jq` against captured JSON), then `verdict=red`.
- Verification commands (local, no prod):
  - `bash apps/web-platform/infra/cron-egress-firewall.test.sh` → all rows PASS
  - `bash apps/web-platform/infra/cloud-init-inngest-bootstrap.test.sh` → all rows PASS
  - `bash .github/scripts/test/test-mint-inngest-bootstrap-tag.sh` → all rows PASS
  - `bun test plugins/soleur/test/ship-deploy-pipeline-fix-gate.test.ts` → pass
  - `bash plugins/soleur/test/main-health-monitor-workflow.test.sh` → pass
  - `bash apps/web-platform/infra/web-host-provisioner-parity.test.sh` → pass (needs terraform)
  - `terraform fmt -check apps/web-platform/infra/server.tf` → clean (run under `terraform fmt`)

## Success Metrics

- A body-only edit to any of the three artifacts produces a `terraform plan` diff replacing
  `deploy_pipeline_fix_web2` (hash moves) and fires `apply-deploy-pipeline-fix.yml` on merge.
- Guard A2 reds when HEAD's pins/recipe diverge from the pinned tag's; the monitor reds when
  the newest mint run concludes `failure`/`startup_failure`.

## Dependencies & Risks

- Delivery to web-2 still requires the `apply-deploy-pipeline-fix.yml` workflow to run —
  operator-gated, same as every artifact it carries today. This PR supplies the mechanism;
  the run event is operator-authorized.
- Running `cron-egress-postapply-assert.sh` on web-2 restarts the firewall service and probes
  the standby container — intended effect; it skips container probes loudly when the
  container is absent.
- Residual (named, not hidden): the loader (`cron-egress-nftables.sh`), alarm, and systemd
  units remain birth-frozen on web-2 until the #9372 rebirth — the issue's three-artifact
  scope; #9393's re-evaluation criteria (next web-2 replace / active-active Phase 5) covers
  the rest.
- Guard A2 inherits Guard A's pre-merge red on legitimate pin bumps until #9081 lands —
  noted, not fixed here.

## References & Research

- Issues: #9393 (this PR), #9082 (this PR), #9275/#9385 (GHCR carve), #9151 (web-2 sibling
  shape), #4326/#9079 (auto-mint), #9081 (Guard A PR-exemption, open), #9372 (rebirth),
  #5505 (paths-filter parity lesson), #9533 (`gh --jq` no `--arg`).
- Files: `apps/web-platform/infra/server.tf` (`terraform_data.cron_egress_firewall` ~2504,
  `deploy_pipeline_fix_web2` ~2135), `apps/web-platform/infra/cloud-init-inngest-bootstrap.test.sh`
  (Guard A ~1242), `.github/scripts/mint-inngest-bootstrap-tag.sh` (`extract_side` ~344,
  `stage_decide` ~382), `.github/workflows/main-health-monitor.yml` (filer ~419, closer ~879),
  `.github/workflows/scheduled-actions-queue-health.yml` (dedupe convention ~128–143).
- Runbook: `knowledge-base/engineering/operations/runbooks/cron-egress-blocked.md`
  ("Known residual: running web-2" ~668).

## Research Insights

- **Premise validation:** all cited artifacts exist on this branch —
  `terraform_data.cron_egress_firewall` (server.tf:2504, pinned `web["web-1"]`),
  `deploy_pipeline_fix_web2` (server.tf:2135, no cron-egress entries), Guard A
  (cloud-init-inngest-bootstrap.test.sh:1242, carriers-only confirmed), the mint script's
  extractors (`.github/scripts/mint-inngest-bootstrap-tag.sh:344-378`),
  `main-health-monitor.yml` (no mint step), `cloud-init-inngest-bootstrap.test.sh`,
  `apply-deploy-pipeline-fix.yml` (explicit `on.push.paths` list lacking the three paths).
  Both issues OPEN with `closedByPullRequestsReferences: []`; every merged PR surfaced by
  the collision probes (#9414, #9385, #9487, #9476, #9451, #9079) either closes a different
  issue or is a citation — no implementation collision.
- **Mechanism minimality — Property List:** (1) a running web-2 receives carve+resolver+probe
  without a host replace; (2) artifact edits re-fire delivery; (3) pin/recipe drift vs the
  pinned tag is red in CI; (4) a red mint conclusion is surfaced by the standing monitor;
  (5) API failure is loud-not-silent. **Cut list:** new `terraform_data` resource (cut —
  `deploy_pipeline_fix_web2` already buys properties 1–2); a dedicated mint-watch workflow
  (cut — `main-health-monitor.yml` already runs 6h and owns the filing/heartbeat machinery);
  delivering the loader/alarm/units (cut — out of the issue's three-artifact scope, tracked
  by #9393's re-evaluation clause).
- **Supersession note:** #9393's 2026-10-03 comment recorded "rebirth-only" as the decision;
  the dispatch's chosen option supersedes it (code-only arm). `cron-egress-blocked.md` and
  the PR body carry the supersession so the next reader does not resurrect the stale arm.

## Enhancement Summary

Deepen pass (2026-10-07, inline — this harness has no Task-fan-out; each gate was
evaluated mechanically against the plan and the code it cites):

- **Phase 4.5 (network-outage, conditional):** evaluated, not fired. The plan drives
  no `terraform apply` — delivery rides the operator-enabled
  `apply-deploy-pipeline-fix.yml`, whose SSH path is the pinned CI key + bastion
  forward, not an operator-IP-dependent dial.
- **Phase 4.55 (downtime & cutover, conditional):** evaluated, not fired. No
  reboot/replace (only `terraform_data` provisioner edits), no locking DDL, no
  serving-surface restart — the single oneshot service re-run happens on a
  weight-0 standby host. A `## Downtime & Cutover` section is not required.
- **Phase 4.6 (user-brand):** PASS — section present, `none` threshold with the
  required sensitive-path scope-out reason (`apps/web-platform/infra/` and the
  deploy workflow match `SENSITIVE_PATH_RE`).
- **Phase 4.7 (observability):** PASS — all 5 fields populated; probe verb `grep`
  is allowlisted and the expected literal is matchable.
- **Phase 4.8 (PAT halt):** PASS — regex sweep returned zero matches.
- **Phase 4.9 (UI wireframe):** N/A — no UI surface.
- **Phase 4.10 (encryption posture):** N/A — no new store or connection; declared
  in-plan.
- **Phase 4.11 (guard contract):** PASS — `scripts/lint-guard-contract.py`
  scanned the plan: 3 guard entries, valid.
- **Phase 4.12 (scope check):** PASS — Ask Mapping / Provenance / Split present.
- **Ordering constraint confirmed:** `deploy_pipeline_fix_web2`'s last provisioner
  MUST stay the #9169 ghcr-deny block (secret-free, after the webhook restart);
  the cron-egress deliveries + assert execution land in the delivery/verify block
  before it.
- **Knock-on surfaces confirmed:** `web-host-provisioner-parity.test.sh` sweeps
  destination-keyed and all three new destinations have `soleur-host-bootstrap.sh`
  counterparts (no allowlist edit); `ship-deploy-pipeline-fix-gate.test.ts` pins
  the paths set + web2 `allowed` set (both must grow); the suite-count floors are
  `>=`, so added destinations cannot red them.

### Key Improvements (deepen pass)

- Named the provisioner-ordering rule (ghcr deny stays LAST) as an implementation
  constraint rather than leaving it to be rediscovered at review.
- Named the exact consumers of `steps.mintwatch.outputs.verdict` (filer / closer /
  heartbeat) so the wiring is checkable, and fixed the discoverability probe to a
  literal `id: mintwatch` match.

### New Considerations Discovered

- `apply-deploy-pipeline-fix.yml`'s `paths:` is an explicit list that does NOT
  include the three artifact files — a daily CIDR-refresh regeneration PR would
  silently not re-fire delivery. The paths additions are therefore required, not
  optional (recorded as an inferred plan item in Provenance).

## Sharp Edges

- The `deploy_pipeline_fix_web2` inline sentinel (`dpf-web2-remote-exec-v1`) MUST bump in
  lockstep with the remote-exec edit — the comment above the resource makes that load-bearing.
- `apply-deploy-pipeline-fix.yml`'s `paths:` is an explicit list: hashing a file the list
  does not name makes artifact-only merges silent no-deliveries (#5505's exact shape).
- The mintwatch step must NOT grow `timeout-minutes` — the job ceiling is pinned at
  `sum(step ceilings)+15` by `main-health-monitor-workflow.test.sh` check (6); a timed step
  breaks the derivation. Bound the `gh` call with `timeout` instead.
- `steps.mintwatch.outputs.verdict` is string output, not a step outcome — it stays `0`-exit
  with `continue-on-error: true` so a mint-API failure cannot kill the 185-minute suite job.
- `gh --jq` does not forward `--arg` (#9533) — all field extraction is standalone `jq` over
  `--json` output; no `cmd | grep -q` predicates (SIGPIPE class), use `grep -c` on captured
  vars or jq.
- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/
  placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. Fill it before
  requesting deepen-plan or `soleur:work`.
